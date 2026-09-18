from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import FLOOR, SEEDS, TS, build_quality_model, build_tables, fold_index, keys, load_case
from node53_stage4_slope_aware_v7 import OUT, V6, preregistered_candidates
from node53_stage4_supervised_gate_v6 import runtime_features


LOCAL_PACKAGES = NODE / "cache/python_packages"
if str(LOCAL_PACKAGES) not in sys.path:
    sys.path.insert(0, str(LOCAL_PACKAGES))
import joblib  # noqa: E402

DEG = math.pi / 180.0


def _hysteresis(theta: np.ndarray, entry_deg: float, exit_deg: float) -> np.ndarray:
    state = False
    out = np.zeros(theta.size, dtype=bool)
    entry = entry_deg * DEG
    exit_value = exit_deg * DEG
    for i, value in enumerate(np.abs(theta)):
        if state:
            if value <= exit_value:
                state = False
        elif value >= entry:
            state = True
        out[i] = state
    return out


def _core(case: dict[str, np.ndarray], tables: dict[str, Any], quality_model: dict[str, Any], model: Any) -> dict[str, np.ndarray]:
    X, aux = runtime_features(case, quality_model)
    theta = np.asarray(aux["theta"], float)
    truth = np.asarray(case["truth"], float)
    innovation = np.asarray(aux["innovation"], float)
    quality = np.asarray(aux["quality"], float)
    regime = np.asarray(aux["regime"], int)
    qbin = np.digitize(quality, [0.5, 0.8])
    p_help = np.asarray(model.predict_proba(X)[:, 1], float)
    pt = np.maximum(np.asarray(tables["P_tcn_total"], float)[regime, qbin], FLOOR) * (2.0 - np.clip(np.asarray(case["conf_main"], float), 0.0, 1.0))
    pf = np.maximum(np.asarray(tables["P_fuzzyakf_total"], float)[regime, qbin], FLOOR)
    cross = np.asarray(tables["cross_error_total"], float)[regime, qbin]
    cross = np.clip(cross, -0.95 * np.sqrt(pt * pf), 0.95 * np.sqrt(pt * pf))
    S = np.maximum(pt + pf - 2.0 * cross, FLOOR)
    nis = innovation * innovation / S
    kraw = (pt - cross) / S
    eligible = np.asarray(case["ready"], bool) & np.asarray(case["observer_valid"], bool) & np.isfinite(theta + truth + innovation + p_help) & (np.abs(innovation) <= 2.0 * DEG) & (nis <= 25.0)
    slope = {entry: _hysteresis(theta, entry, 0.6 * entry) for entry in (0.5, 0.8, 1.0)}
    return {"theta": theta, "truth": truth, "innovation": innovation, "quality": quality, "p_help": p_help, "nis": nis, "kraw": kraw, "eligible": eligible, "slope_0.5": slope[0.5], "slope_0.8": slope[0.8], "slope_1.0": slope[1.0]}


def _rate_limited_correction(target: np.ndarray, gate: np.ndarray, step: float) -> np.ndarray:
    correction = np.zeros(target.size, float)
    indices = np.flatnonzero(gate)
    previous_index = -2
    previous = 0.0
    for index in indices:
        if index != previous_index + 1:
            previous = 0.0
        previous += float(np.clip(target[index] - previous, -step, step))
        correction[index] = previous
        previous_index = int(index)
    return correction


def _evaluate(core: dict[str, np.ndarray], tables: dict[str, Any], spec: dict[str, Any]) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    theta = core["theta"]; truth = core["truth"]; innovation = core["innovation"]
    slope = core[f"slope_{spec['slope_entry_deg']:.1f}"]
    gate = core["eligible"] & slope & (core["p_help"] >= spec["p_help_threshold"]) & (np.abs(innovation) >= spec["innovation_min_deg"] * DEG)
    nis_weight = np.where(core["nis"] <= 9.0, 1.0, np.sqrt(9.0 / np.maximum(core["nis"], 1e-15)))
    quality_weight = np.clip(spec["quality_intercept"] - spec["quality_slope"] * core["quality"], spec["quality_floor"], 1.0)
    keff = np.minimum(spec["Kmax"], np.maximum(0.0, core["kraw"])) * quality_weight * nis_weight
    target = np.clip(keff * innovation, -spec["correction_limit_deg"] * DEG, spec["correction_limit_deg"] * DEG)
    correction = _rate_limited_correction(target, gate, spec["correction_rate_limit_deg_s"] * DEG * TS)
    fused = theta + correction
    base_error = np.abs(theta - truth); fused_error = np.abs(fused - truth)
    active = np.abs(correction) >= 0.05 * DEG
    improve = active & (fused_error < base_error - 0.10 * DEG)
    degrade = active & (fused_error > base_error + 0.10 * DEG)
    masks = {"near_flat": np.abs(truth) < 0.5 * DEG, "slope": np.abs(truth) >= 1.3 * DEG, "transition": (np.abs(truth) >= 0.5 * DEG) & (np.abs(truth) < 1.3 * DEG)}
    metric: dict[str, Any] = {
        "sample_count": int(theta.size), "baseline_abs_error_sum_deg": float(np.rad2deg(np.sum(base_error))), "fused_abs_error_sum_deg": float(np.rad2deg(np.sum(fused_error))),
        "active_count": int(np.sum(active)), "improve_count": int(np.sum(improve)), "degrade_count": int(np.sum(degrade)), "fallback_count": int(np.sum(~gate)), "gate_count": int(np.sum(gate)),
        "nonfinite_count": int(np.sum(~np.isfinite(fused))), "fallback_identity_max_abs": float(np.max(np.abs(fused[~gate] - theta[~gate]))) if np.any(~gate) else 0.0,
    }
    for name, mask in masks.items():
        metric[f"baseline_{name}_abs_error_sum_deg"] = float(np.rad2deg(np.sum(base_error[mask]))); metric[f"fused_{name}_abs_error_sum_deg"] = float(np.rad2deg(np.sum(fused_error[mask]))); metric[f"baseline_{name}_sample_count"] = int(np.sum(mask)); metric[f"fused_{name}_sample_count"] = int(np.sum(mask))
    return metric, {"K_raw": core["kraw"][gate], "K_eff": keff[gate], "cap": core["kraw"][gate] > spec["Kmax"]}


def _summary(spec: dict[str, Any], metrics: list[dict[str, Any]], diagnostics: list[dict[str, np.ndarray]], folds: list[float]) -> dict[str, Any]:
    total = max(sum(int(x["sample_count"]) for x in metrics), 1); base = sum(float(x["baseline_abs_error_sum_deg"]) for x in metrics); fused = sum(float(x["fused_abs_error_sum_deg"]) for x in metrics); active = sum(int(x["active_count"]) for x in metrics)
    row: dict[str, Any] = {**spec, "sample_count": total, "baseline_mae_deg": base / total, "fused_mae_deg": fused / total, "mae_ratio": fused / max(base, 1e-15), "active_fraction": active / total, "active_improve_fraction": sum(int(x["improve_count"]) for x in metrics) / max(active, 1), "active_degrade_fraction": sum(int(x["degrade_count"]) for x in metrics) / max(active, 1), "fallback_fraction": sum(int(x["fallback_count"]) for x in metrics) / total, "gate_fraction": sum(int(x["gate_count"]) for x in metrics) / total, "nonfinite_count": sum(int(x["nonfinite_count"]) for x in metrics), "fallback_identity_max_abs": max(float(x["fallback_identity_max_abs"]) for x in metrics), "fold_mae_ratios": folds, "worst_fold_mae_ratio": max(folds) if folds else float("nan")}
    for region in ("near_flat", "slope", "transition"):
        count = max(sum(int(x[f"baseline_{region}_sample_count"]) for x in metrics), 1); b = sum(float(x[f"baseline_{region}_abs_error_sum_deg"]) for x in metrics) / count; f = sum(float(x[f"fused_{region}_abs_error_sum_deg"]) for x in metrics) / count; row[f"{region}_baseline_mae_deg"] = b; row[f"{region}_fused_mae_deg"] = f; row[f"{region}_mae_ratio"] = f / max(b, 1e-15); row[f"{region}_mae_delta_deg"] = f - b
    raw = np.concatenate([x["K_raw"] for x in diagnostics if x["K_raw"].size]); eff = np.concatenate([x["K_eff"] for x in diagnostics if x["K_eff"].size]); cap = np.concatenate([x["cap"] for x in diagnostics if x["cap"].size]); row["K_raw_p95_p05"] = float(np.ptp(np.percentile(raw, [5, 95]))) if raw.size else 0.0; row["K_eff_p95_p05"] = float(np.ptp(np.percentile(eff, [5, 95]))) if eff.size else 0.0; row["cap_fraction"] = float(np.mean(cap)) if cap.size else 0.0
    criteria = {"pooled_mae_improves": row["mae_ratio"] < 1.0, "every_fold_noninferior": bool(folds) and max(folds) <= 1.0, "slope_region_improves": row["slope_mae_ratio"] < 1.0, "near_flat_delta_bounded": row["near_flat_mae_delta_deg"] <= 0.01, "runtime_finite": row["nonfinite_count"] == 0, "fallback_identity": row["fallback_identity_max_abs"] <= 1e-15}; row["acceptance_failures"] = [k for k, v in criteria.items() if not v]; row["development_accepted"] = not row["acceptance_failures"]; return row


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True); items = keys(); specs = preregistered_candidates(); pooled = {x["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for x in specs}; fold_rows: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]; held = [x for x in items if fold_index(x) == fold]; quality_model = build_quality_model(fit); tables, table_audit = build_tables(fit, quality_model); model_file = V6 / "models" / f"fold_{fold}_hist_gradient_boosting.joblib"; model = joblib.load(model_file); cores = []
        for split, run_id in held:
            for seed in SEEDS:
                cores.append(_core(load_case(split, run_id, seed), tables, quality_model, model))
        for spec in specs:
            metrics = []; diagnostics = []
            for core in cores:
                metric, diag = _evaluate(core, tables, spec); metrics.append(metric); diagnostics.append(diag)
            summary = _summary(spec, metrics, diagnostics, []); summary.update({"fold": fold, "fit_run_count": len(fit), "held_run_count": len(held), "covariance_psd": bool(table_audit["psd"]), "gate_model_sha256": sha256(model_file)}); fold_rows.append(summary); pooled[spec["candidate_id"]]["metrics"].extend(metrics); pooled[spec["candidate_id"]]["diagnostics"].extend(diagnostics); pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"])
    rows = [_summary(s, pooled[s["candidate_id"]]["metrics"], pooled[s["candidate_id"]]["diagnostics"], pooled[s["candidate_id"]]["folds"]) for s in specs]; accepted = [x for x in rows if x["development_accepted"]]; selected = sorted(accepted, key=lambda x: (x["mae_ratio"], x["worst_fold_mae_ratio"], x["near_flat_mae_delta_deg"], x["candidate_id"]))[0] if accepted else None; status = "PASS_NODE53_STAGE4_V7_PAPER_SELECTION" if selected else "STOP_NODE53_STAGE4_V7_NO_DEVELOPMENT_ACCEPTED_CANDIDATE"; report = {"status": status, "classification": "RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK", "candidate_count": len(rows), "selected": selected, "candidates": rows, "development_run_count": len(items), "model_seed_count": len(SEEDS), "fold_count": 3, "selection_does_not_use_44R1_qualification_gates": True, "test_read": False, "this_stage_six_path_read": False, "six_path_results_previously_exposed": True, "runtime_truth_read": False, "preregistration_sha256": sha256(OUT / "protocol_amendment.json"), "v6_selection_sha256": sha256(V6 / "selection_decision.json")}; write_csv(OUT / "fusion_candidate_table.csv", rows); write_csv(OUT / "cv_fold_metrics.csv", fold_rows); write_json(OUT / "selection_decision.json", report)
    if selected:
        quality_model = build_quality_model(items); tables, table_audit = build_tables(items, quality_model); final_model = V6 / "models/final_train_validation_hist_gradient_boosting.joblib"; write_json(OUT / "selected_fusion_config.json", {"status": "FROZEN_NODE53_V7_TRAIN_VALIDATION_CONFIG", "classification": report["classification"], "selected": selected, "tables": tables, "quality_model": quality_model, "supervised_gate": {"source": "Node53 V6 final train+validation HGB gate; unchanged model, V7 selects runtime gating parameters", "model_path": str(final_model.resolve()), "model_sha256": sha256(final_model)}, "covariance_psd": bool(table_audit["psd"]), "test_read": False, "this_stage_six_path_read": False, "runtime_truth_read": False})
    else: write_json(OUT / "STOP_NODE53_STAGE4_V7_NO_DEVELOPMENT_ACCEPTED_CANDIDATE.json", report)
    print(json.dumps({"status": status, "selected": selected}, indent=2)); return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
