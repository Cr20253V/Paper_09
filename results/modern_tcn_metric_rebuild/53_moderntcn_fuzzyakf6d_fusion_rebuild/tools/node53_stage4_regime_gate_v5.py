from __future__ import annotations

import json
import math
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import FLOOR, SEEDS, TS, build_quality_model, build_tables, fold_index, keys, load_case
from node53_stage4_runtime_gate_v3 import FEATURES, quality_parts, runtime_gate, summarize


OUT = NODE / "04_fusion_calibration/iterations/06_regime_gate_v5"


def preregistered_candidates() -> list[dict[str, Any]]:
    broad_gate = {"accel_norm_deviation": 0.5, "gyro_vibration_feature": 0.8}
    return [
        {"candidate_id": "C20", "Kmax": 0.9, "gate": "broad_feature_gate_plus_slope_regimes", "feature_quality_max": broad_gate, "innovation_min_deg": 0.25, "innovation_max_deg": 2.0, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5, "allowed_regimes": [1, 3]},
        {"candidate_id": "C21", "Kmax": 0.9, "gate": "broad_feature_gate_plus_slope_regimes", "feature_quality_max": broad_gate, "innovation_min_deg": 0.25, "innovation_max_deg": 2.0, "quality_intercept": 0.75, "quality_slope": 0.3, "quality_floor": 0.25, "allowed_regimes": [1, 3]},
        {"candidate_id": "C22", "Kmax": 0.9, "gate": "broad_feature_gate_plus_slope_transition", "feature_quality_max": broad_gate, "innovation_min_deg": 0.25, "innovation_max_deg": 2.0, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5, "allowed_regimes": [3]},
        {"candidate_id": "C23", "Kmax": 0.9, "gate": "broad_feature_gate_plus_slope_regimes_innovation_ge_0p5", "feature_quality_max": broad_gate, "innovation_min_deg": 0.5, "innovation_max_deg": 2.0, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5, "allowed_regimes": [1, 3]},
    ]


def fusion_metrics_v5(case: dict[str, np.ndarray], tables: dict[str, Any], spec: dict[str, Any], model: dict[str, Any]) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    theta = np.asarray(case["theta_tcn"], float); truth = np.asarray(case["truth"], float); rate = np.diff(theta, prepend=theta[0]) / TS
    regime = (np.abs(theta) >= np.deg2rad(1.3)).astype(int) + 2 * (np.abs(rate) >= np.deg2rad(1.0)); quality, dominant = quality_parts(case, model); qbin = np.digitize(quality, [0.5, 0.8]); innovation = np.asarray(case["theta_imu"], float) - theta
    gate = runtime_gate(spec, quality, dominant, innovation) & np.isin(regime, np.asarray(spec["allowed_regimes"], int)); correction = 0.0; fused = theta.copy(); fallback = np.zeros(len(theta), bool); raw: list[float] = []; eff: list[float] = []; cap: list[bool] = []
    for i in range(len(theta)):
        rr, qq = int(regime[i]), int(qbin[i]); pt = max(float(tables["P_tcn_total"][rr][qq]), FLOOR) * (2 - float(np.clip(case["conf_main"][i], 0, 1))); pf = max(float(tables["P_fuzzyakf_total"][rr][qq]), FLOOR); cross = float(np.clip(tables["cross_error_total"][rr][qq], -0.95 * math.sqrt(pt * pf), 0.95 * math.sqrt(pt * pf))); s = max(pt + pf - 2 * cross, FLOOR); nis = innovation[i] * innovation[i] / s
        bad = (not bool(case["ready"][i])) or (not bool(case["observer_valid"][i])) or abs(innovation[i]) > np.deg2rad(2) or nis > 25 or not bool(gate[i]); fallback[i] = bad
        if bad: correction = 0.0; continue
        nw = 1.0 if nis <= 9 else math.sqrt(9 / nis); qw = np.clip(spec["quality_intercept"] - spec["quality_slope"] * quality[i], spec["quality_floor"], 1.0); kraw = (pt - cross) / s; ke = min(spec["Kmax"], max(0.0, kraw)) * qw * nw; target = np.clip(ke * innovation[i], -np.deg2rad(0.5), np.deg2rad(0.5)); correction += np.clip(target - correction, -np.deg2rad(5) * TS, np.deg2rad(5) * TS); fused[i] = theta[i] + correction; raw.append(kraw); eff.append(ke); cap.append(kraw > spec["Kmax"])
    base_err = np.abs(theta - truth); fused_err = np.abs(fused - truth); active = np.abs(fused - theta) >= np.deg2rad(0.05); improve = active & (fused_err < base_err - np.deg2rad(0.10)); degrade = active & (fused_err > base_err + np.deg2rad(0.10))
    metrics = {"baseline_mae_deg": float(np.rad2deg(np.mean(base_err))), "fused_mae_deg": float(np.rad2deg(np.mean(fused_err))), "mae_ratio": float(np.mean(fused_err) / max(np.mean(base_err), 1e-15)), "sample_count": int(len(theta)), "active_count": int(np.sum(active)), "improve_count": int(np.sum(improve)), "degrade_count": int(np.sum(degrade)), "fallback_count": int(np.sum(fallback)), "active_fraction": float(np.mean(active)), "active_improve_fraction": float(np.sum(improve) / max(np.sum(active), 1)), "active_degrade_fraction": float(np.sum(degrade) / max(np.sum(active), 1))}
    return metrics, {"fused": fused, "K_raw": np.asarray(raw), "K_eff": np.asarray(eff), "cap": np.asarray(cap, bool), "fallback": fallback}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True); items = keys(); specs = preregistered_candidates(); pooled = {s["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for s in specs}; fold_rows: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]; held = [x for x in items if fold_index(x) == fold]; model = build_quality_model(fit); tables, _ = build_tables(fit, model)
        for spec in specs:
            metrics: list[dict[str, Any]] = []; diagnostics: list[dict[str, np.ndarray]] = []
            for split, run_id in held:
                for seed in SEEDS:
                    metric, diag = fusion_metrics_v5(load_case(split, run_id, seed), tables, spec, model); metrics.append(metric); diagnostics.append(diag)
            summary = summarize(spec, metrics, diagnostics, []); pooled[spec["candidate_id"]]["metrics"].extend(metrics); pooled[spec["candidate_id"]]["diagnostics"].extend(diagnostics); pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"]); fold_rows.append({"fold": fold, "fit_runs": len(fit), "held_runs": len(held), **summary})
    rows = [summarize(s, pooled[s["candidate_id"]]["metrics"], pooled[s["candidate_id"]]["diagnostics"], pooled[s["candidate_id"]]["folds"]) for s in specs]; qualified = [r for r in rows if r["qualified"]]; selected = sorted(qualified, key=lambda r: (r["mae_ratio"], r["active_degrade_fraction"], r["candidate_id"]))[0] if qualified else None
    report = {"status": "PASS_NODE53_STAGE4_V5_SELECTION" if selected else "STOP_NODE53_STAGE4_V5_NO_QUALIFIED_FUSION", "candidate_count": len(rows), "candidate_scope": "runtime feature gate plus slope regime gate; Kmax 0.9; train+validation grouped CV", "selected": selected, "candidates": rows, "fold_count": 3, "development_run_count": len(items), "test_read": False, "formal_read": False, "preregistration_sha256": sha256(OUT / "protocol_amendment.json"), "previous_stage4_v4_sha256": sha256(NODE / "04_fusion_calibration/iterations/05_quality_gain_v4/selection_decision.json")}
    write_csv(OUT / "fusion_candidate_table.csv", rows); write_csv(OUT / "cv_fold_metrics.csv", fold_rows); write_json(OUT / "selection_decision.json", report)
    if selected:
        frozen = json.loads((NODE / "fusion_covariance_tables.json").read_text(encoding="utf-8")); write_json(OUT / "selected_fusion_config.json", {"status": "FROZEN_NODE53_STAGE4_V5_SELECTION", "selected": selected, "tables": frozen["tables"], "quality_model": frozen["quality_model"], "test_read": False, "formal_read": False})
    else: write_json(OUT / "STOP_NODE53_STAGE4_V5_NO_QUALIFIED_FUSION.json", report)
    print(json.dumps({"status": report["status"], "selected": selected, "rows": rows}, indent=2)); return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
