from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import FLOOR, G, SEEDS, TS, build_quality_model, build_tables, fold_index, keys, load_case
from node53_stage4_runtime_gate_v3 import FEATURES, summarize


LOCAL_PACKAGES = NODE / "cache/python_packages"
if str(LOCAL_PACKAGES) not in sys.path:
    sys.path.insert(0, str(LOCAL_PACKAGES))

import joblib  # noqa: E402
import sklearn  # noqa: E402
from sklearn.ensemble import HistGradientBoostingClassifier  # noqa: E402


OUT = NODE / "04_fusion_calibration/iterations/07_supervised_runtime_gate_v6"
DEG = math.pi / 180.0
FEATURE_NAMES = [
    "ecdf_one_minus_accel_weight", "ecdf_accel_norm_deviation", "ecdf_abs_innovation", "ecdf_internal_nis", "ecdf_gyro_vibration",
    "quality_score", "dominant_one_minus_accel_weight", "dominant_accel_norm_deviation", "dominant_abs_innovation", "dominant_internal_nis", "dominant_gyro_vibration",
    "innovation_deg", "abs_innovation_deg", "internal_nis_log1p", "accel_weight", "accel_norm_deviation", "gyro_vibration_log1p",
    "theta_tcn_deg", "theta_tcn_rate_deg_per_s", "conf_main", "regime_flat_slow", "regime_slope_slow", "regime_flat_transition", "regime_slope_transition",
]


def preregistered_candidates() -> list[dict[str, Any]]:
    return [
        {"candidate_id": "C24", "Kmax": 0.9, "p_help_threshold": 0.60, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5},
        {"candidate_id": "C25", "Kmax": 0.9, "p_help_threshold": 0.65, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5},
        {"candidate_id": "C26", "Kmax": 0.9, "p_help_threshold": 0.70, "quality_intercept": 1.0, "quality_slope": 0.5, "quality_floor": 0.5},
    ]


def runtime_features(case: dict[str, np.ndarray], quality_model: dict[str, Any]) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    theta = np.asarray(case["theta_tcn"], float); innovation = np.asarray(case["theta_imu"], float) - theta; rate = np.diff(theta, prepend=theta[0]) / TS
    regime = (np.abs(theta) >= 1.3 * DEG).astype(int) + 2 * (np.abs(rate) >= 1.0 * DEG)
    raw = [1 - case["accel_weight"], np.abs(case["accel_norm"] - G), np.abs(case["innovation"]), case["nis"], case["gyro_vibration_feature"]]
    parts = np.vstack([np.interp(v, quality_model[name]["values"], quality_model[name]["probabilities"], left=0, right=1) for v, name in zip(raw, FEATURES)]).T
    quality = np.clip(np.max(parts, axis=1), 0, 1); dominant = np.argmax(parts, axis=1); dominant_onehot = np.eye(5, dtype=float)[dominant]; regime_onehot = np.eye(4, dtype=float)[regime]
    X = np.column_stack([
        parts, quality, dominant_onehot, np.rad2deg(innovation), np.rad2deg(np.abs(innovation)), np.log1p(np.maximum(case["nis"], 0)), case["accel_weight"], np.abs(case["accel_norm"] - G), np.log1p(np.maximum(case["gyro_vibration_feature"], 0)), np.rad2deg(theta), np.rad2deg(rate), np.clip(case["conf_main"], 0, 1), regime_onehot,
    ]).astype(np.float32, copy=False)
    if X.shape[1] != len(FEATURE_NAMES):
        raise RuntimeError(f"Node53 v6 feature count mismatch: {X.shape[1]} != {len(FEATURE_NAMES)}")
    return X, {"theta": theta, "innovation": innovation, "rate": rate, "regime": regime, "quality": quality}


def fit_fold_model(fold: int, fit_items: list[tuple[str, int]], quality_model: dict[str, Any]) -> tuple[HistGradientBoostingClassifier, dict[str, Any]]:
    rng = np.random.default_rng(20260715 + fold); helpful_rows: list[np.ndarray] = []; harmful_rows: list[np.ndarray] = []; raw_helpful = 0; raw_harmful = 0
    for split, run_id in fit_items:
        for seed in SEEDS:
            case = load_case(split, run_id, seed); X, aux = runtime_features(case, quality_model); truth = np.asarray(case["truth"], float); base = np.abs(aux["theta"] - truth); observer = np.abs(np.asarray(case["theta_imu"], float) - truth)
            eligible = case["ready"].astype(bool) & case["observer_valid"].astype(bool) & np.isfinite(truth) & (np.abs(aux["innovation"]) <= 2 * DEG)
            helpful = np.flatnonzero(eligible & (observer < base - 0.10 * DEG)); harmful = np.flatnonzero(eligible & (observer > base + 0.10 * DEG)); raw_helpful += len(helpful); raw_harmful += len(harmful)
            if len(helpful): helpful_rows.append(X[rng.choice(helpful, size=min(300, len(helpful)), replace=False)])
            if len(harmful): harmful_rows.append(X[rng.choice(harmful, size=min(300, len(harmful)), replace=False)])
    Xh = np.concatenate(helpful_rows); Xd = np.concatenate(harmful_rows); cap = 150000
    if len(Xh) > cap: Xh = Xh[rng.choice(len(Xh), size=cap, replace=False)]
    if len(Xd) > cap: Xd = Xd[rng.choice(len(Xd), size=cap, replace=False)]
    X = np.concatenate([Xh, Xd]); y = np.concatenate([np.ones(len(Xh), dtype=np.uint8), np.zeros(len(Xd), dtype=np.uint8)]); order = rng.permutation(len(y)); X = X[order]; y = y[order]
    model = HistGradientBoostingClassifier(max_iter=100, learning_rate=0.05, max_depth=3, max_leaf_nodes=15, min_samples_leaf=100, l2_regularization=1e-3, random_state=20260715)
    model.fit(X, y)
    audit = {"fold": fold, "fit_run_count": len(fit_items), "raw_helpful_count": raw_helpful, "raw_harmful_count": raw_harmful, "sampled_helpful_count": len(Xh), "sampled_harmful_count": len(Xd), "training_sample_count": len(y), "feature_count": X.shape[1], "feature_names": FEATURE_NAMES, "truth_used_for_training_label_only": True, "runtime_truth_feature": False}
    return model, audit


def fusion_metrics_v6(case: dict[str, np.ndarray], tables: dict[str, Any], spec: dict[str, Any], quality_model: dict[str, Any], model: HistGradientBoostingClassifier) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    X, aux = runtime_features(case, quality_model); theta = aux["theta"]; truth = np.asarray(case["truth"], float); regime = aux["regime"]; quality = aux["quality"]; innovation = aux["innovation"]; qbin = np.digitize(quality, [0.5, 0.8]); p_help = model.predict_proba(X)[:, 1]
    gate = p_help >= spec["p_help_threshold"]; correction = 0.0; fused = theta.copy(); fallback = np.zeros(len(theta), bool); raw: list[float] = []; eff: list[float] = []; cap: list[bool] = []
    for i in range(len(theta)):
        rr, qq = int(regime[i]), int(qbin[i]); pt = max(float(tables["P_tcn_total"][rr][qq]), FLOOR) * (2 - float(np.clip(case["conf_main"][i], 0, 1))); pf = max(float(tables["P_fuzzyakf_total"][rr][qq]), FLOOR); cross = float(np.clip(tables["cross_error_total"][rr][qq], -0.95 * math.sqrt(pt * pf), 0.95 * math.sqrt(pt * pf))); s = max(pt + pf - 2 * cross, FLOOR); nis = innovation[i] * innovation[i] / s
        bad = (not bool(case["ready"][i])) or (not bool(case["observer_valid"][i])) or abs(innovation[i]) > 2 * DEG or nis > 25 or not bool(gate[i]); fallback[i] = bad
        if bad: correction = 0.0; continue
        nw = 1.0 if nis <= 9 else math.sqrt(9 / nis); qw = np.clip(spec["quality_intercept"] - spec["quality_slope"] * quality[i], spec["quality_floor"], 1.0); kraw = (pt - cross) / s; ke = min(spec["Kmax"], max(0.0, kraw)) * qw * nw; target = np.clip(ke * innovation[i], -0.5 * DEG, 0.5 * DEG); correction += np.clip(target - correction, -5 * DEG * TS, 5 * DEG * TS); fused[i] = theta[i] + correction; raw.append(kraw); eff.append(ke); cap.append(kraw > spec["Kmax"])
    base_err = np.abs(theta - truth); fused_err = np.abs(fused - truth); active = np.abs(fused - theta) >= 0.05 * DEG; improve = active & (fused_err < base_err - 0.10 * DEG); degrade = active & (fused_err > base_err + 0.10 * DEG)
    metrics = {"baseline_mae_deg": float(np.rad2deg(np.mean(base_err))), "fused_mae_deg": float(np.rad2deg(np.mean(fused_err))), "mae_ratio": float(np.mean(fused_err) / max(np.mean(base_err), 1e-15)), "sample_count": int(len(theta)), "active_count": int(np.sum(active)), "improve_count": int(np.sum(improve)), "degrade_count": int(np.sum(degrade)), "fallback_count": int(np.sum(fallback)), "active_fraction": float(np.mean(active)), "active_improve_fraction": float(np.sum(improve) / max(np.sum(active), 1)), "active_degrade_fraction": float(np.sum(degrade) / max(np.sum(active), 1))}
    return metrics, {"fused": fused, "K_raw": np.asarray(raw), "K_eff": np.asarray(eff), "cap": np.asarray(cap, bool), "fallback": fallback, "p_help": p_help}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True); model_dir = OUT / "models"; model_dir.mkdir(parents=True, exist_ok=True); items = keys(); specs = preregistered_candidates(); pooled = {s["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for s in specs}; fold_rows: list[dict[str, Any]] = []; model_audits: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]; held = [x for x in items if fold_index(x) == fold]; quality_model = build_quality_model(fit); tables, table_audit = build_tables(fit, quality_model); model, model_audit = fit_fold_model(fold, fit, quality_model); model_path = model_dir / f"fold_{fold}_hist_gradient_boosting.joblib"; joblib.dump(model, model_path); model_audit.update({"model_path": str(model_path), "model_sha256": sha256(model_path), "sklearn_version": sklearn.__version__, "table_psd": bool(table_audit["psd"])}); model_audits.append(model_audit)
        for spec in specs:
            metrics: list[dict[str, Any]] = []; diagnostics: list[dict[str, np.ndarray]] = []
            for split, run_id in held:
                for seed in SEEDS:
                    metric, diag = fusion_metrics_v6(load_case(split, run_id, seed), tables, spec, quality_model, model); metrics.append(metric); diagnostics.append(diag)
            summary = summarize(spec, metrics, diagnostics, []); pooled[spec["candidate_id"]]["metrics"].extend(metrics); pooled[spec["candidate_id"]]["diagnostics"].extend(diagnostics); pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"]); fold_rows.append({"fold": fold, "fit_runs": len(fit), "held_runs": len(held), **summary})
    rows = [summarize(s, pooled[s["candidate_id"]]["metrics"], pooled[s["candidate_id"]]["diagnostics"], pooled[s["candidate_id"]]["folds"]) for s in specs]; qualified = [r for r in rows if r["qualified"]]; selected = sorted(qualified, key=lambda r: (r["mae_ratio"], r["active_degrade_fraction"], r["candidate_id"]))[0] if qualified else None
    report = {"status": "PASS_NODE53_STAGE4_V6_SELECTION" if selected else "STOP_NODE53_STAGE4_V6_NO_QUALIFIED_FUSION", "candidate_count": len(rows), "candidate_scope": "supervised runtime trust gate; train-label truth only; runtime observable features only", "selected": selected, "candidates": rows, "fold_count": 3, "development_run_count": len(items), "test_read": False, "formal_read": False, "runtime_truth_read": False, "preregistration_sha256": sha256(OUT / "protocol_amendment.json"), "previous_stage4_v5_sha256": sha256(NODE / "04_fusion_calibration/iterations/06_regime_gate_v5/selection_decision.json"), "model_audits": model_audits}
    write_csv(OUT / "fusion_candidate_table.csv", rows); write_csv(OUT / "cv_fold_metrics.csv", fold_rows); write_json(OUT / "model_training_audit.json", {"status": "PASS_NODE53_V6_FOLD_MODEL_TRAINING", "models": model_audits, "test_read": False, "formal_read": False}); write_json(OUT / "selection_decision.json", report)
    if selected:
        frozen = json.loads((NODE / "fusion_covariance_tables.json").read_text(encoding="utf-8")); write_json(OUT / "selected_fusion_config.json", {"status": "FROZEN_NODE53_STAGE4_V6_SELECTION", "selected": selected, "tables": frozen["tables"], "quality_model": frozen["quality_model"], "supervised_gate": {"model_family": "HistGradientBoostingClassifier", "feature_names": FEATURE_NAMES, "fold_model_audits": model_audits}, "test_read": False, "formal_read": False})
    else: write_json(OUT / "STOP_NODE53_STAGE4_V6_NO_QUALIFIED_FUSION.json", report)
    print(json.dumps({"status": report["status"], "selected": selected, "rows": rows, "model_audits": model_audits}, indent=2)); return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
