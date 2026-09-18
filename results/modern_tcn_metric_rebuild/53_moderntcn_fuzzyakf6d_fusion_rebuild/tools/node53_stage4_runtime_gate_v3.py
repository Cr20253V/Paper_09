from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import FLOOR, G, SEEDS, TS, build_quality_model, build_tables, fold_index, keys, load_case


OUT = NODE / "04_fusion_calibration/iterations/04_runtime_gate_v3"
FEATURES = ("one_minus_accel_weight", "accel_norm_deviation", "abs_innovation", "nis", "gyro_vibration_feature")
DEG = math.pi / 180.0


def preregistered_candidates() -> list[dict[str, Any]]:
    """Candidates are fixed before this iteration reads any test/formal result."""
    pair = ["accel_norm_deviation", "gyro_vibration_feature"]
    return [
        {"candidate_id": "C8", "Kmax": 0.9, "gate": "q_lt_0p5_pair", "feature_quality_max": {x: 0.5 for x in pair}, "innovation_min_deg": 0.0, "innovation_max_deg": 2.0},
        {"candidate_id": "C9", "Kmax": 0.9, "gate": "q_lt_0p5_pair_innovation_ge_0p25", "feature_quality_max": {x: 0.5 for x in pair}, "innovation_min_deg": 0.25, "innovation_max_deg": 2.0},
        {"candidate_id": "C10", "Kmax": 1.1, "gate": "q_lt_0p5_pair", "feature_quality_max": {x: 0.5 for x in pair}, "innovation_min_deg": 0.0, "innovation_max_deg": 2.0},
        {"candidate_id": "C11", "Kmax": 0.9, "gate": "gyro_q_lt_0p8_accel_q_lt_0p5", "feature_quality_max": {"accel_norm_deviation": 0.5, "gyro_vibration_feature": 0.8}, "innovation_min_deg": 0.0, "innovation_max_deg": 2.0},
        {"candidate_id": "C12", "Kmax": 0.9, "gate": "gyro_q_lt_0p8_accel_q_lt_0p5_innovation_ge_0p25", "feature_quality_max": {"accel_norm_deviation": 0.5, "gyro_vibration_feature": 0.8}, "innovation_min_deg": 0.25, "innovation_max_deg": 2.0},
        {"candidate_id": "C13", "Kmax": 1.1, "gate": "gyro_q_lt_0p8_accel_q_lt_0p5", "feature_quality_max": {"accel_norm_deviation": 0.5, "gyro_vibration_feature": 0.8}, "innovation_min_deg": 0.0, "innovation_max_deg": 2.0},
        {"candidate_id": "C14", "Kmax": 0.9, "gate": "q_lt_0p4_any_feature", "feature_quality_max": {x: 0.4 for x in FEATURES}, "innovation_min_deg": 0.0, "innovation_max_deg": 2.0},
        {"candidate_id": "C15", "Kmax": 0.9, "gate": "q_lt_0p5_pair_innovation_ge_0p5", "feature_quality_max": {x: 0.5 for x in pair}, "innovation_min_deg": 0.5, "innovation_max_deg": 2.0},
    ]


def quality_parts(case: dict[str, np.ndarray], model: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    values = [1 - case["accel_weight"], np.abs(case["accel_norm"] - G), np.abs(case["innovation"]), case["nis"], case["gyro_vibration_feature"]]
    parts = np.vstack([np.interp(v, model[name]["values"], model[name]["probabilities"], left=0, right=1) for v, name in zip(values, FEATURES)])
    return np.clip(np.max(parts, axis=0), 0, 1), np.argmax(parts, axis=0)


def runtime_gate(spec: dict[str, Any], quality: np.ndarray, dominant: np.ndarray, innovation: np.ndarray) -> np.ndarray:
    max_by_feature = np.array([spec["feature_quality_max"].get(name, -1.0) for name in FEATURES], float)
    allowed_feature = max_by_feature[dominant] >= 0
    abs_deg = np.rad2deg(np.abs(innovation))
    return allowed_feature & (quality < max_by_feature[dominant]) & (abs_deg >= spec["innovation_min_deg"]) & (abs_deg <= spec["innovation_max_deg"])


def fusion_metrics_v3(case: dict[str, np.ndarray], tables: dict[str, Any], spec: dict[str, Any], model: dict[str, Any]) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    theta = np.asarray(case["theta_tcn"], float); truth = np.asarray(case["truth"], float)
    rate = np.diff(theta, prepend=theta[0]) / TS
    regime = (np.abs(theta) >= np.deg2rad(1.3)).astype(int) + 2 * (np.abs(rate) >= np.deg2rad(1.0))
    quality, dominant = quality_parts(case, model); qbin = np.digitize(quality, [0.5, 0.8])
    innovation = np.asarray(case["theta_imu"], float) - theta
    correction = 0.0; fused = theta.copy(); fallback = np.zeros(len(theta), bool)
    raw: list[float] = []; eff: list[float] = []; cap: list[bool] = []; active_gate = runtime_gate(spec, quality, dominant, innovation)
    for i in range(len(theta)):
        rr, qq = int(regime[i]), int(qbin[i])
        pt = max(float(tables["P_tcn_total"][rr][qq]), FLOOR) * (2 - float(np.clip(case["conf_main"][i], 0, 1)))
        pf = max(float(tables["P_fuzzyakf_total"][rr][qq]), FLOOR)
        cross = float(np.clip(tables["cross_error_total"][rr][qq], -0.95 * math.sqrt(pt * pf), 0.95 * math.sqrt(pt * pf)))
        s = max(pt + pf - 2 * cross, FLOOR); nis = innovation[i] * innovation[i] / s
        bad = (not bool(case["ready"][i])) or (not bool(case["observer_valid"][i])) or abs(innovation[i]) > np.deg2rad(2) or nis > 25 or not bool(active_gate[i])
        fallback[i] = bad
        if bad:
            correction = 0.0
            continue
        nw = 1.0 if nis <= 9 else math.sqrt(9 / nis)
        qw = np.clip(0.5 - 0.3 * quality[i], 0.1, 1.0)
        kraw = (pt - cross) / s; ke = min(spec["Kmax"], max(0.0, kraw)) * qw * nw
        target = np.clip(ke * innovation[i], -np.deg2rad(0.5), np.deg2rad(0.5))
        correction += np.clip(target - correction, -np.deg2rad(5) * TS, np.deg2rad(5) * TS)
        fused[i] = theta[i] + correction; raw.append(kraw); eff.append(ke); cap.append(kraw > spec["Kmax"])
    base_err = np.abs(theta - truth); fused_err = np.abs(fused - truth)
    active = np.abs(fused - theta) >= np.deg2rad(0.05)
    improve = active & (fused_err < base_err - np.deg2rad(0.10)); degrade = active & (fused_err > base_err + np.deg2rad(0.10))
    metrics = {"baseline_mae_deg": float(np.rad2deg(np.mean(base_err))), "fused_mae_deg": float(np.rad2deg(np.mean(fused_err))), "mae_ratio": float(np.mean(fused_err) / max(np.mean(base_err), 1e-15)), "sample_count": int(len(theta)), "active_count": int(np.sum(active)), "improve_count": int(np.sum(improve)), "degrade_count": int(np.sum(degrade)), "fallback_count": int(np.sum(fallback)), "active_fraction": float(np.mean(active)), "active_improve_fraction": float(np.sum(improve) / max(np.sum(active), 1)), "active_degrade_fraction": float(np.sum(degrade) / max(np.sum(active), 1))}
    return metrics, {"fused": fused, "K_raw": np.asarray(raw), "K_eff": np.asarray(eff), "cap": np.asarray(cap, bool), "fallback": fallback, "gate_active": active_gate, "quality": quality, "dominant": dominant}


def summarize(spec: dict[str, Any], metrics: list[dict[str, Any]], diagnostics: list[dict[str, np.ndarray]], folds: list[float]) -> dict[str, Any]:
    total = max(sum(int(x["sample_count"]) for x in metrics), 1); active = sum(int(x["active_count"]) for x in metrics); improve = sum(int(x["improve_count"]) for x in metrics); degrade = sum(int(x["degrade_count"]) for x in metrics)
    base = sum(float(x["baseline_mae_deg"]) * int(x["sample_count"]) for x in metrics) / total; fused = sum(float(x["fused_mae_deg"]) * int(x["sample_count"]) for x in metrics) / total
    raw = np.concatenate([x["K_raw"] for x in diagnostics if x["K_raw"].size]); eff = np.concatenate([x["K_eff"] for x in diagnostics if x["K_eff"].size]); cap = np.concatenate([x["cap"] for x in diagnostics if x["cap"].size])
    row = {**spec, "baseline_mae_deg": float(base), "fused_mae_deg": float(fused), "mae_ratio": float(fused / max(base, 1e-15)), "sample_count": total, "active_count": active, "improve_count": improve, "degrade_count": degrade, "active_fraction": active / total, "active_improve_fraction": improve / max(active, 1), "active_degrade_fraction": degrade / max(active, 1), "K_raw_p95_p05": float(np.percentile(raw, 95) - np.percentile(raw, 5)) if raw.size else 0.0, "K_eff_p95_p05": float(np.percentile(eff, 95) - np.percentile(eff, 5)) if eff.size else 0.0, "cap_fraction": float(np.mean(cap)) if cap.size else 1.0, "below_cap_fraction": float(np.mean(eff <= spec["Kmax"] - 0.01)) if eff.size else 0.0, "fold_mae_ratios": folds}
    gates = {"mae_ratio": row["mae_ratio"] <= 0.95, "active_fraction": row["active_fraction"] >= 0.10, "active_improve_fraction": row["active_improve_fraction"] >= 0.60, "active_degrade_fraction": row["active_degrade_fraction"] <= 0.05, "K_raw_p95_p05": row["K_raw_p95_p05"] >= 0.02, "K_eff_p95_p05": row["K_eff_p95_p05"] >= 0.02, "cap_fraction": row["cap_fraction"] < 0.95, "below_cap_fraction": row["below_cap_fraction"] >= 0.05, "cv_fold_mae_ratio": not folds or max(folds) <= 1.0}
    row["failed_gates"] = [k for k, v in gates.items() if not v]; row["qualified"] = not row["failed_gates"]; return row


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    items = keys(); specs = preregistered_candidates()
    pooled = {s["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for s in specs}; fold_rows: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]; held = [x for x in items if fold_index(x) == fold]
        model = build_quality_model(fit); tables, _ = build_tables(fit, model)
        for spec in specs:
            metrics: list[dict[str, Any]] = []; diagnostics: list[dict[str, np.ndarray]] = []
            for split, run_id in held:
                for seed in SEEDS:
                    metric, diag = fusion_metrics_v3(load_case(split, run_id, seed), tables, spec, model); metrics.append(metric); diagnostics.append(diag)
            summary = summarize(spec, metrics, diagnostics, []); pooled[spec["candidate_id"]]["metrics"].extend(metrics); pooled[spec["candidate_id"]]["diagnostics"].extend(diagnostics); pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"]); fold_rows.append({"fold": fold, "fit_runs": len(fit), "held_runs": len(held), **summary})
    rows = [summarize(s, pooled[s["candidate_id"]]["metrics"], pooled[s["candidate_id"]]["diagnostics"], pooled[s["candidate_id"]]["folds"]) for s in specs]
    qualified = [r for r in rows if r["qualified"]]; selected = sorted(qualified, key=lambda r: (r["mae_ratio"], r["active_degrade_fraction"], r["candidate_id"]))[0] if qualified else None
    prereg = json.loads((OUT / "protocol_amendment.json").read_text(encoding="utf-8"))
    report = {"status": "PASS_NODE53_STAGE4_V3_SELECTION" if selected else "STOP_NODE53_STAGE4_V3_NO_QUALIFIED_FUSION", "candidate_count": len(rows), "candidate_scope": "runtime-only feature-specific quality gates; Kmax 0.9/1.1; train+validation grouped CV", "selected": selected, "candidates": rows, "fold_count": 3, "development_run_count": len(items), "quality_model_source": "Node53 train+validation ECDF fit inside each fold; unchanged feature definitions", "tables_source": "Node53 train+validation covariance tables fit inside each fold; unchanged", "test_read": False, "formal_read": False, "preregistration_sha256": sha256(OUT / "protocol_amendment.json"), "previous_stage4_v2_sha256": sha256(NODE / "04_fusion_calibration/iterations/02_expanded_kmax/selection_decision.json")}
    write_csv(OUT / "fusion_candidate_table.csv", rows); write_csv(OUT / "cv_fold_metrics.csv", fold_rows); write_json(OUT / "selection_decision.json", report)
    if selected:
        frozen = json.loads((NODE / "fusion_covariance_tables.json").read_text(encoding="utf-8")); write_json(OUT / "selected_fusion_config.json", {"status": "FROZEN_NODE53_STAGE4_V3_SELECTION", "selected": selected, "tables": frozen["tables"], "quality_model": frozen["quality_model"], "test_read": False, "formal_read": False})
    else:
        write_json(OUT / "STOP_NODE53_STAGE4_V3_NO_QUALIFIED_FUSION.json", report)
    print(json.dumps({"status": report["status"], "selected": selected, "rows": rows}, indent=2)); return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
