from __future__ import annotations

import json
import math
import sys
from itertools import product
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import FLOOR, SEEDS, TS, build_quality_model, build_tables, fold_index, keys, load_case
from node53_stage4_supervised_gate_v6 import runtime_features


LOCAL_PACKAGES = NODE / "cache/python_packages"
if str(LOCAL_PACKAGES) not in sys.path:
    sys.path.insert(0, str(LOCAL_PACKAGES))
import joblib  # noqa: E402


OUT = NODE / "04_fusion_calibration/iterations/08_slope_aware_paper_fusion_v7"
V6 = NODE / "04_fusion_calibration/iterations/07_supervised_runtime_gate_v6"
DEG = math.pi / 180.0


def preregistered_candidates() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for index, values in enumerate(product((0.7, 0.9, 1.0), (0.60, 0.65), (0.5, 0.8, 1.0), (0.25, 0.5)), 1):
        kmax, p_help, entry, innovation_min = values
        rows.append({
            "candidate_id": f"V7C{index:02d}",
            "Kmax": kmax,
            "p_help_threshold": p_help,
            "slope_entry_deg": entry,
            "slope_exit_deg": 0.6 * entry,
            "innovation_min_deg": innovation_min,
            "innovation_max_deg": 2.0,
            "quality_intercept": 1.0,
            "quality_slope": 0.5,
            "quality_floor": 0.5,
            "correction_limit_deg": 0.5,
            "correction_rate_limit_deg_s": 5.0,
        })
    return rows


def _region_sums(error: np.ndarray, truth: np.ndarray) -> dict[str, float | int]:
    masks = {
        "near_flat": np.abs(truth) < 0.5 * DEG,
        "slope": np.abs(truth) >= 1.3 * DEG,
        "transition": (np.abs(truth) >= 0.5 * DEG) & (np.abs(truth) < 1.3 * DEG),
    }
    out: dict[str, float | int] = {}
    for name, mask in masks.items():
        out[f"{name}_abs_error_sum_deg"] = float(np.rad2deg(np.sum(error[mask])))
        out[f"{name}_sample_count"] = int(np.sum(mask))
    return out


def evaluate_case(
    case: dict[str, np.ndarray], tables: dict[str, Any], spec: dict[str, Any],
    quality_model: dict[str, Any], model: Any,
) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    X, aux = runtime_features(case, quality_model)
    theta = np.asarray(aux["theta"], float)
    truth = np.asarray(case["truth"], float)
    innovation = np.asarray(aux["innovation"], float)
    regime = np.asarray(aux["regime"], int)
    quality = np.asarray(aux["quality"], float)
    qbin = np.digitize(quality, [0.5, 0.8])
    p_help = np.asarray(model.predict_proba(X)[:, 1], float)
    fused = theta.copy()
    fallback = np.ones(len(theta), bool)
    gate = np.zeros(len(theta), bool)
    kraw_values: list[float] = []
    keff_values: list[float] = []
    cap_values: list[bool] = []
    correction = 0.0
    slope_active = False
    entry = spec["slope_entry_deg"] * DEG
    exit_value = spec["slope_exit_deg"] * DEG
    innovation_min = spec["innovation_min_deg"] * DEG
    innovation_max = spec["innovation_max_deg"] * DEG
    correction_limit = spec["correction_limit_deg"] * DEG
    correction_step = spec["correction_rate_limit_deg_s"] * DEG * TS

    for i in range(len(theta)):
        magnitude = abs(theta[i])
        if slope_active:
            if magnitude <= exit_value:
                slope_active = False
        elif magnitude >= entry:
            slope_active = True
        gate[i] = slope_active and p_help[i] >= spec["p_help_threshold"] and innovation_min <= abs(innovation[i]) <= innovation_max
        rr, qq = int(regime[i]), int(qbin[i])
        pt = max(float(tables["P_tcn_total"][rr][qq]), FLOOR) * (2.0 - float(np.clip(case["conf_main"][i], 0.0, 1.0)))
        pf = max(float(tables["P_fuzzyakf_total"][rr][qq]), FLOOR)
        cross = float(np.clip(tables["cross_error_total"][rr][qq], -0.95 * math.sqrt(pt * pf), 0.95 * math.sqrt(pt * pf)))
        s = max(pt + pf - 2.0 * cross, FLOOR)
        nis = innovation[i] * innovation[i] / s
        bad = (not bool(case["ready"][i])) or (not bool(case["observer_valid"][i])) or nis > 25.0 or not gate[i]
        if bad:
            correction = 0.0
            continue
        fallback[i] = False
        nis_weight = 1.0 if nis <= 9.0 else math.sqrt(9.0 / nis)
        quality_weight = float(np.clip(spec["quality_intercept"] - spec["quality_slope"] * quality[i], spec["quality_floor"], 1.0))
        kraw = (pt - cross) / s
        keff = min(spec["Kmax"], max(0.0, kraw)) * quality_weight * nis_weight
        target = float(np.clip(keff * innovation[i], -correction_limit, correction_limit))
        correction += float(np.clip(target - correction, -correction_step, correction_step))
        fused[i] = theta[i] + correction
        kraw_values.append(kraw)
        keff_values.append(keff)
        cap_values.append(kraw > spec["Kmax"])

    base_error = np.abs(theta - truth)
    fused_error = np.abs(fused - truth)
    active = np.abs(fused - theta) >= 0.05 * DEG
    improve = active & (fused_error < base_error - 0.10 * DEG)
    degrade = active & (fused_error > base_error + 0.10 * DEG)
    metric: dict[str, Any] = {
        "sample_count": int(len(theta)),
        "baseline_abs_error_sum_deg": float(np.rad2deg(np.sum(base_error))),
        "fused_abs_error_sum_deg": float(np.rad2deg(np.sum(fused_error))),
        "active_count": int(np.sum(active)),
        "improve_count": int(np.sum(improve)),
        "degrade_count": int(np.sum(degrade)),
        "fallback_count": int(np.sum(fallback)),
        "gate_count": int(np.sum(gate)),
        "nonfinite_count": int(np.sum(~np.isfinite(fused))),
        "fallback_identity_max_abs": float(np.max(np.abs(fused[fallback] - theta[fallback]))) if np.any(fallback) else 0.0,
    }
    metric.update({f"baseline_{k}": v for k, v in _region_sums(base_error, truth).items()})
    metric.update({f"fused_{k}": v for k, v in _region_sums(fused_error, truth).items()})
    return metric, {
        "K_raw": np.asarray(kraw_values, float),
        "K_eff": np.asarray(keff_values, float),
        "cap": np.asarray(cap_values, bool),
        "fallback": fallback,
        "gate": gate,
    }


def summarize(spec: dict[str, Any], metrics: list[dict[str, Any]], diagnostics: list[dict[str, np.ndarray]], folds: list[float]) -> dict[str, Any]:
    samples = max(sum(int(x["sample_count"]) for x in metrics), 1)
    baseline_sum = sum(float(x["baseline_abs_error_sum_deg"]) for x in metrics)
    fused_sum = sum(float(x["fused_abs_error_sum_deg"]) for x in metrics)
    row: dict[str, Any] = {
        **spec,
        "sample_count": samples,
        "baseline_mae_deg": baseline_sum / samples,
        "fused_mae_deg": fused_sum / samples,
        "mae_ratio": fused_sum / max(baseline_sum, 1e-15),
        "active_fraction": sum(int(x["active_count"]) for x in metrics) / samples,
        "active_improve_fraction": sum(int(x["improve_count"]) for x in metrics) / max(sum(int(x["active_count"]) for x in metrics), 1),
        "active_degrade_fraction": sum(int(x["degrade_count"]) for x in metrics) / max(sum(int(x["active_count"]) for x in metrics), 1),
        "fallback_fraction": sum(int(x["fallback_count"]) for x in metrics) / samples,
        "gate_fraction": sum(int(x["gate_count"]) for x in metrics) / samples,
        "nonfinite_count": sum(int(x["nonfinite_count"]) for x in metrics),
        "fallback_identity_max_abs": max(float(x["fallback_identity_max_abs"]) for x in metrics),
        "fold_mae_ratios": folds,
        "worst_fold_mae_ratio": max(folds) if folds else float("nan"),
    }
    for region in ("near_flat", "slope", "transition"):
        count = max(sum(int(x[f"baseline_{region}_sample_count"]) for x in metrics), 1)
        base = sum(float(x[f"baseline_{region}_abs_error_sum_deg"]) for x in metrics) / count
        fused = sum(float(x[f"fused_{region}_abs_error_sum_deg"]) for x in metrics) / count
        row[f"{region}_baseline_mae_deg"] = base
        row[f"{region}_fused_mae_deg"] = fused
        row[f"{region}_mae_ratio"] = fused / max(base, 1e-15)
        row[f"{region}_mae_delta_deg"] = fused - base
    raw = np.concatenate([x["K_raw"] for x in diagnostics if x["K_raw"].size]) if any(x["K_raw"].size for x in diagnostics) else np.array([])
    eff = np.concatenate([x["K_eff"] for x in diagnostics if x["K_eff"].size]) if any(x["K_eff"].size for x in diagnostics) else np.array([])
    cap = np.concatenate([x["cap"] for x in diagnostics if x["cap"].size]) if any(x["cap"].size for x in diagnostics) else np.array([])
    row["K_raw_p95_p05"] = float(np.ptp(np.percentile(raw, [5, 95]))) if raw.size else 0.0
    row["K_eff_p95_p05"] = float(np.ptp(np.percentile(eff, [5, 95]))) if eff.size else 0.0
    row["cap_fraction"] = float(np.mean(cap)) if cap.size else 0.0
    criteria = {
        "pooled_mae_improves": row["mae_ratio"] < 1.0,
        "every_fold_noninferior": bool(folds) and max(folds) <= 1.0,
        "slope_region_improves": row["slope_mae_ratio"] < 1.0,
        "near_flat_delta_bounded": row["near_flat_mae_delta_deg"] <= 0.01,
        "runtime_finite": row["nonfinite_count"] == 0,
        "fallback_identity": row["fallback_identity_max_abs"] <= 1e-15,
    }
    row["acceptance_failures"] = [name for name, value in criteria.items() if not value]
    row["development_accepted"] = not row["acceptance_failures"]
    return row


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if not (OUT / "protocol_amendment.json").is_file():
        raise FileNotFoundError("V7 protocol amendment must exist before candidate evaluation")
    items = keys()
    specs = preregistered_candidates()
    pooled = {x["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for x in specs}
    fold_rows: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]
        held = [x for x in items if fold_index(x) == fold]
        quality_model = build_quality_model(fit)
        tables, table_audit = build_tables(fit, quality_model)
        model_file = V6 / "models" / f"fold_{fold}_hist_gradient_boosting.joblib"
        model = joblib.load(model_file)
        for spec in specs:
            metrics: list[dict[str, Any]] = []
            diagnostics: list[dict[str, np.ndarray]] = []
            for split, run_id in held:
                for seed in SEEDS:
                    metric, diag = evaluate_case(load_case(split, run_id, seed), tables, spec, quality_model, model)
                    metrics.append(metric)
                    diagnostics.append(diag)
            summary = summarize(spec, metrics, diagnostics, [])
            summary.update({"fold": fold, "fit_run_count": len(fit), "held_run_count": len(held), "covariance_psd": bool(table_audit["psd"]), "gate_model_sha256": sha256(model_file)})
            fold_rows.append(summary)
            pooled[spec["candidate_id"]]["metrics"].extend(metrics)
            pooled[spec["candidate_id"]]["diagnostics"].extend(diagnostics)
            pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"])
    rows = [summarize(spec, pooled[spec["candidate_id"]]["metrics"], pooled[spec["candidate_id"]]["diagnostics"], pooled[spec["candidate_id"]]["folds"]) for spec in specs]
    accepted = [x for x in rows if x["development_accepted"]]
    selected = sorted(accepted, key=lambda x: (x["mae_ratio"], x["worst_fold_mae_ratio"], x["near_flat_mae_delta_deg"], x["candidate_id"]))[0] if accepted else None
    status = "PASS_NODE53_STAGE4_V7_PAPER_SELECTION" if selected else "STOP_NODE53_STAGE4_V7_NO_DEVELOPMENT_ACCEPTED_CANDIDATE"
    report = {
        "status": status,
        "classification": "RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK",
        "candidate_count": len(rows),
        "selected": selected,
        "candidates": rows,
        "development_run_count": len(items),
        "model_seed_count": len(SEEDS),
        "fold_count": 3,
        "selection_does_not_use_44R1_qualification_gates": True,
        "test_read": False,
        "this_stage_six_path_read": False,
        "six_path_results_previously_exposed": True,
        "runtime_truth_read": False,
        "preregistration_sha256": sha256(OUT / "protocol_amendment.json"),
        "v6_selection_sha256": sha256(V6 / "selection_decision.json"),
    }
    write_csv(OUT / "fusion_candidate_table.csv", rows)
    write_csv(OUT / "cv_fold_metrics.csv", fold_rows)
    write_json(OUT / "selection_decision.json", report)
    if selected:
        quality_model = build_quality_model(items)
        tables, table_audit = build_tables(items, quality_model)
        final_model = V6 / "models/final_train_validation_hist_gradient_boosting.joblib"
        frozen = {
            "status": "FROZEN_NODE53_V7_TRAIN_VALIDATION_CONFIG",
            "classification": report["classification"],
            "selected": selected,
            "tables": tables,
            "quality_model": quality_model,
            "supervised_gate": {
                "source": "Node53 V6 final train+validation HGB gate; unchanged model, V7 selects runtime gating parameters",
                "model_path": str(final_model.resolve()),
                "model_sha256": sha256(final_model),
            },
            "covariance_psd": bool(table_audit["psd"]),
            "test_read": False,
            "this_stage_six_path_read": False,
            "runtime_truth_read": False,
        }
        write_json(OUT / "selected_fusion_config.json", frozen)
    else:
        write_json(OUT / "STOP_NODE53_STAGE4_V7_NO_DEVELOPMENT_ACCEPTED_CANDIDATE.json", report)
    print(json.dumps({"status": status, "selected": selected}, indent=2))
    return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
