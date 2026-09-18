#!/usr/bin/env python3
"""Validate all 40 raw prediction cases, compute one metric implementation and frozen CIs."""

from __future__ import annotations

import csv
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np


SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
METHODS = ["modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"]
PRIMARY = ["theta_mae_deg", "theta_abs_le_10_p95_abs_err_deg"]
REP_PRIMARY = ["theta_mae_deg", "theta_edge_p95_abs_err"]
ITERATIONS = 10000
RNG_SEED = 20260715


def root() -> Path:
    for p in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (p / "init_project.m").is_file():
            return p
    raise RuntimeError("project root not found")


ROOT = root()
TASK = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison"
sys.path.insert(0, str(ROOT / "src/ModernTCN"))
from modern_tcn_data import load_modern_tcn_dataset  # noqa: E402
from modern_tcn_metrics import compute_metrics  # noqa: E402


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    names: list[str] = []
    for row in rows:
        for key in row:
            if key not in names:
                names.append(key)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=names, extrasaction="ignore")
        w.writeheader(); w.writerows(rows)


def write_json(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, allow_nan=True) + "\n", encoding="utf-8")


def scalar_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in metrics.items() if isinstance(v, (int, float, np.integer, np.floating, bool))}


def load_prediction(path: Path, split) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rows = read_rows(path)
    if len(rows) != len(split.X):
        raise ValueError(f"{path}: expected {len(split.X)} rows, got {len(rows)}")
    def col(name: str, dtype=float) -> np.ndarray:
        return np.asarray([dtype(r[name]) for r in rows])
    if not np.array_equal(col("window_index", int), np.arange(1, len(rows) + 1)):
        raise ValueError(f"{path}: window index/order mismatch")
    checks = [
        (col("y_main_true", int), split.y_main.reshape(-1), "y_main"),
        (col("y_turn_true", int), split.y_turn.reshape(-1), "y_turn"),
        (col("mask_theta", int), split.mask_theta.reshape(-1).astype(int), "mask_theta"),
    ]
    for actual, expected, name in checks:
        if not np.array_equal(actual, expected):
            raise ValueError(f"{path}: {name} truth mismatch")
    if not np.allclose(col("theta_true_rad"), split.y_theta.reshape(-1), atol=1e-7, rtol=1e-6):
        raise ValueError(f"{path}: theta truth mismatch")
    lm = np.column_stack([col(f"main_logit_{i}") for i in range(3)])
    lt = np.column_stack([col(f"turn_logit_{i}") for i in range(3)])
    th = col("theta_hat_rad")
    if not np.isfinite(lm).all() or not np.isfinite(lt).all() or not np.isfinite(th).all():
        raise ValueError(f"{path}: nonfinite prediction")
    return lm, lt, th


def paired_bootstrap(target: dict[int, float], comparator: dict[int, float], seed_offset: int = 0) -> dict[str, float]:
    seeds = sorted(set(target) & set(comparator))
    if seeds != SEEDS:
        raise ValueError(f"incomplete paired seeds: {seeds}")
    effects = np.asarray([comparator[s] - target[s] for s in seeds], dtype=float)
    rel = np.asarray([100.0 * (comparator[s] - target[s]) / comparator[s] if comparator[s] != 0 else np.nan for s in seeds])
    # A5 freezes the RNG seed for each bootstrap invocation.  seed_offset is
    # retained only for call compatibility and must not alter the RNG stream.
    rng = np.random.default_rng(RNG_SEED)
    idx = rng.integers(0, len(seeds), size=(ITERATIONS, len(seeds)))
    samples = effects[idx].mean(axis=1)
    rel_samples = np.nanmean(rel[idx], axis=1)
    return {
        "target_mean": float(np.mean([target[s] for s in seeds])),
        "comparator_mean": float(np.mean([comparator[s] for s in seeds])),
        "absolute_effect": float(effects.mean()),
        "absolute_ci_low": float(np.percentile(samples, 2.5)),
        "absolute_ci_high": float(np.percentile(samples, 97.5)),
        "relative_effect_percent": float(np.nanmean(rel)),
        "relative_ci_low_percent": float(np.nanpercentile(rel_samples, 2.5)),
        "relative_ci_high_percent": float(np.nanpercentile(rel_samples, 97.5)),
        "improved_seed_count": int(np.sum(effects > 0)),
        "paired_seed_count": len(seeds),
        "bootstrap_iterations": ITERATIONS,
        "bootstrap_seed": RNG_SEED,
        "ci_method": "percentile_95",
        "resampling_unit": "paired_model_seed",
    }


def historical_audit(registry: list[dict[str, str]], cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_case = {(r["method_id"], int(r["model_seed"])): r for r in registry}
    out: list[dict[str, Any]] = []
    for case in cases:
        key = (case["method_id"], int(case["seed"]))
        source = by_case[key].get("source_index", "")
        source_path = ROOT / source if source else None
        for metric in PRIMARY:
            row = {"method_id": key[0], "seed": key[1], "metric": metric, "unified_value": case.get(metric, math.nan), "source_file": str(source_path or ""), "historical_value": "", "absolute_difference": "", "status": "SOURCE_UNAVAILABLE"}
            if source_path and source_path.is_file():
                try:
                    candidates = read_rows(source_path)
                    match = [x for x in candidates if int(float(x.get("seed", x.get("model_seed", -1)))) == key[1]]
                    if not match and len(candidates) == 1: match = candidates
                    if match and metric in match[-1] and match[-1][metric] != "":
                        old = float(match[-1][metric]); new = float(case[metric])
                        row.update({"historical_value": old, "absolute_difference": abs(new-old), "status": "AUDITED"})
                except Exception as exc:
                    row["status"] = f"AUDIT_ERROR:{type(exc).__name__}"
            out.append(row)
    return out


def main() -> int:
    dataset_file = ROOT / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
    split = load_modern_tcn_dataset(dataset_file=dataset_file)["test"]
    registry = read_rows(TASK / "model_registry.csv")
    cases: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    for method in METHODS:
        for seed in SEEDS:
            path = TASK / "03_offline/raw" / f"{method}_seed{seed}_predictions.csv"
            if not path.is_file():
                missing.append({"method_id": method, "seed": seed, "reason": "raw_prediction_missing", "expected_file": str(path)})
                continue
            try:
                lm, lt, th = load_prediction(path, split)
                metrics = compute_metrics(lm, lt, th, split, float("nan"))
                metrics["theta_edge_p95_abs_err"] = max(float(metrics.get("theta_neg_10_8_p95_abs_err_deg", np.nan)), float(metrics.get("theta_pos_8_10_p95_abs_err_deg", np.nan)))
                full = {"task_id": "A1_algorithm_comparison", "method_id": method, "seed": seed, "raw_prediction_file": str(path), "metrics": metrics}
                write_json(path.with_name(path.stem.replace("_predictions", "_metrics") + ".json"), full)
                cases.append({"method_id": method, "seed": seed, "raw_prediction_file": str(path), **scalar_metrics(metrics)})
            except Exception as exc:
                missing.append({"method_id": method, "seed": seed, "reason": f"validation_error:{exc}", "expected_file": str(path)})
    cases.sort(key=lambda x: (METHODS.index(x["method_id"]), x["seed"]))
    write_rows(TASK / "03_offline/offline_case_metrics.csv", cases)
    write_rows(TASK / "offline_case_metrics.csv", cases)
    write_rows(TASK / "03_offline/offline_missing_after_eval.csv", missing)

    numeric = [k for k, v in cases[0].items() if isinstance(v, (int, float, np.integer, np.floating)) and k != "seed"] if cases else []
    summaries: list[dict[str, Any]] = []
    for method in METHODS:
        selected = [r for r in cases if r["method_id"] == method]
        for metric in numeric:
            vals = np.asarray([float(r[metric]) for r in selected if np.isfinite(float(r[metric]))])
            if vals.size:
                summaries.append({"method_id": method, "metric": metric, "n_seeds": len(vals), "mean": float(vals.mean()), "median": float(np.median(vals)), "std": float(vals.std(ddof=1)) if len(vals)>1 else 0.0, "min": float(vals.min()), "max": float(vals.max())})
    write_rows(TASK / "03_offline/offline_method_summary.csv", summaries)

    lookup = {(r["method_id"], int(r["seed"])): r for r in cases}
    contrasts = [
        ("cross_algorithm", "modern_tcn_delta_bank_124", "modern_tcn_22d", PRIMARY, True),
        ("cross_algorithm", "modern_tcn_delta_bank_124", "gru_22d", PRIMARY, True),
        ("cross_algorithm", "modern_tcn_delta_bank_124", "tcn_22d", PRIMARY, True),
        ("architecture_control", "modern_tcn_22d", "gru_22d", PRIMARY, True),
        ("architecture_control", "modern_tcn_22d", "tcn_22d", PRIMARY, True),
        ("architecture_control", "gru_22d", "tcn_22d", PRIMARY, False),
        ("representation_ablation", "modern_tcn_delta_bank_124", "modern_tcn_22d", REP_PRIMARY, True),
    ]
    effects: list[dict[str, Any]] = []
    offset = 0
    if not missing:
        for family, target, comparator, metrics, confirmatory in contrasts:
            for metric in metrics:
                offset += 1
                tv = {s: float(lookup[(target,s)][metric]) for s in SEEDS}
                cv = {s: float(lookup[(comparator,s)][metric]) for s in SEEDS}
                stat = paired_bootstrap(tv, cv, offset)
                effects.append({"domain": "offline", "contrast_family": family, "target_method": target, "comparator_method": comparator, "metric": metric, "confirmatory": confirmatory, "effect_convention": "comparator-target; positive favors target", **stat, "ci_supports_target": stat["absolute_ci_low"] > 0})
    write_rows(TASK / "05_analysis/paired_effects.csv", effects)
    write_rows(TASK / "05_analysis/bootstrap_results.csv", effects)
    write_rows(TASK / "05_analysis/offline_bootstrap_results.csv", effects)
    write_rows(TASK / "05_analysis/architecture_control.csv", [r for r in effects if r["contrast_family"] == "architecture_control"])
    write_rows(TASK / "05_analysis/representation_ablation.csv", [r for r in effects if r["contrast_family"] == "representation_ablation"])
    write_rows(TASK / "03_offline/historical_consistency_audit.csv", historical_audit(registry, cases))

    confirm = [r for r in effects if r["contrast_family"] == "cross_algorithm" and r["confirmatory"]]
    if missing:
        offline_decision = "INCOMPLETE_GRID"
    elif all(bool(r["ci_supports_target"]) for r in confirm):
        offline_decision = "SUPPORTED_ALL_PRIMARY"
    elif all(float(r["absolute_effect"]) > 0 for r in confirm):
        offline_decision = "INCONCLUSIVE"
    else:
        offline_decision = "NOT_SUPPORTED"
    decision = {
        "task_id": "A1_algorithm_comparison", "updated_at": now(), "provisional": True,
        "decision": "INCOMPLETE_GRID", "offline_decision": offline_decision,
        "offline_cases_complete": len(cases), "offline_cases_expected": 40,
        "closed_loop_cases_complete": 120, "closed_loop_cases_expected": 240,
        "reason": "formal GRU/TCN closed-loop cases remain for manual execution",
        "results_used_for_recipe_or_threshold_changes": False,
    }
    status = {
        "task_id": "A1_algorithm_comparison", "updated_at": now(),
        "status": "READY_FOR_MANUAL_CLOSED_LOOP" if not missing else "OFFLINE_INCOMPLETE",
        "models_ready": sum(r["status"] == "READY" for r in registry),
        "offline_cases_complete": len(cases), "offline_cases_expected": 40,
        "closed_loop_cases_reused": 120, "closed_loop_cases_new_complete": 0,
        "next_action": "run manual GRU and TCN closed-loop commands" if not missing else "complete missing offline cases",
    }
    write_json(TASK / "decision.json", decision)
    write_json(TASK / "task_status.json", status)
    report = f"""# A1 Experiment Report\n\n- protocol: `A0_paper_final_unified_protocol_v1`\n- current status: `{status['status']}`\n- models registered: `{status['models_ready']}/40`\n- unified offline cases: `{len(cases)}/40`\n- offline decision: `{offline_decision}`\n- reusable closed-loop cases: `120/120`\n- manual GRU/TCN closed-loop cases complete: `0/120`\n- overall decision: `INCOMPLETE_GRID` (provisional until the full 240-case closed-loop grid is present)\n\nNo path, seed, training recipe, threshold, plant revision, or MPC setting was changed in response to results.\n"""
    (TASK / "A1_experiment_report.md").write_text(report, encoding="utf-8")
    print(json.dumps({"offline_complete": len(cases), "missing": len(missing), "offline_decision": offline_decision}, ensure_ascii=False))
    return 0 if not missing else 3


if __name__ == "__main__":
    raise SystemExit(main())
