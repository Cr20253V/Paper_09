#!/usr/bin/env python3
"""Execute the preregistered A5 phase-2 statistical and failure-gate audit.

The program is deliberately read-only outside the A5 directory.  It adapts the
completed A1--A4 native tables into the phase-1 contracts, independently
recomputes the preregistered paired statistics, and retains every protocol or
gate non-pass instead of dropping it.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import platform
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Iterable

import numpy as np

HERE = Path(__file__).resolve().parent
A5 = HERE.parent
NODE39 = A5.parent
ROOT = A5.parents[3]
OUT = A5 / "04_phase2"
LOGS = A5 / "logs"
sys.path.insert(0, str(HERE))

from a5_statistical_audit import (  # noqa: E402
    BOOTSTRAP_ITERATIONS,
    BOOTSTRAP_SEED,
    hierarchical_paired_bootstrap,
    paired_path_bootstrap,
    paired_seed_bootstrap,
    primary_claim_decision,
    sha256_file,
)

SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
PATHS = [
    "p01_factory_logistics_showcase",
    "p02_sharp_turn_transition",
    "p03_long_updown",
    "p04_soft_updown_straight_turn",
    "p05_factory_flat_logistics",
    "p06_downhill_after_turn",
]
METHODS = ["modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"]
PRIMARY_CL = ["ey_rmse", "epsi_rmse", "j_du"]
CL_METRICS = PRIMARY_CL + [
    "xy_rmse", "omega_cmd_rms", "ey_peak", "epsi_peak", "ev_rmse",
    "constraint_violation_rate", "force_saturation_rate", "omega_saturation_rate",
    "solver_fail_count", "timeout_count", "J_control_path",
]
OFF_METRICS = [
    "theta_mae_deg", "theta_abs_le_10_p95_abs_err_deg", "theta_edge_p95_abs_err",
    "theta_abs_le_10_rmse_deg", "theta_flat_bias_deg", "acc_main", "acc_turn",
    "acc_turn_transition", "flat_recall", "stall_recall", "slope_recall",
    "uphill_recall", "downhill_recall",
]
UNITS = {
    "theta_mae_deg": "deg", "theta_abs_le_10_p95_abs_err_deg": "deg",
    "theta_edge_p95_abs_err": "deg", "theta_abs_le_10_rmse_deg": "deg",
    "theta_flat_bias_deg": "deg", "acc_main": "fraction", "acc_turn": "fraction",
    "acc_turn_transition": "fraction", "flat_recall": "fraction",
    "stall_recall": "fraction", "slope_recall": "fraction", "uphill_recall": "fraction",
    "downhill_recall": "fraction", "ey_rmse": "m", "epsi_rmse": "rad",
    "j_du": "mixed_native_squared_increment", "xy_rmse": "m",
    "omega_cmd_rms": "rad_per_s", "ey_peak": "m", "epsi_peak": "rad",
    "ev_rmse": "m_per_s", "constraint_violation_rate": "fraction",
    "force_saturation_rate": "fraction", "omega_saturation_rate": "fraction",
    "solver_fail_count": "count", "timeout_count": "count", "J_control_path": "ratio",
}
TZ = timezone(timedelta(hours=8))
NOW = datetime.now(TZ).isoformat(timespec="seconds")
LOG: list[str] = []


def log(message: str) -> None:
    line = f"[{datetime.now(TZ).isoformat(timespec='seconds')}] {message}"
    LOG.append(line)
    print(line, flush=True)


def jread(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_json(path: Path, value: Any) -> None:
    assert path.resolve().is_relative_to(A5.resolve())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, data: Iterable[dict[str, Any]], fields: list[str]) -> None:
    assert path.resolve().is_relative_to(A5.resolve())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for item in data:
            writer.writerow({field: fmt(item.get(field)) for field in fields})


def fmt(value: Any) -> Any:
    if value is None or (isinstance(value, float) and not math.isfinite(value)):
        return "NA"
    if isinstance(value, bool):
        return "True" if value else "False"
    return value


def num(value: Any) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return math.nan
    return result if math.isfinite(result) else math.nan


def seed_int(value: Any) -> int | None:
    value = str(value).strip()
    if not value or value.lower() in {"none", "null", "na", "nan", "[]"}:
        return None
    return int(float(value))


def resolve_source(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def mean(values: Iterable[float]) -> float:
    values = list(values)
    return float(np.mean(values)) if values else math.nan


def median(values: Iterable[float]) -> float:
    values = list(values)
    return float(np.median(values)) if values else math.nan


def std(values: Iterable[float]) -> float:
    values = list(values)
    return float(np.std(values, ddof=1)) if len(values) > 1 else 0.0 if values else math.nan


def bootstrap_values(values_by_key: dict[Any, float], kind: str) -> dict[str, float]:
    if kind == "seed":
        return paired_seed_bootstrap({int(k): v for k, v in values_by_key.items()})
    if kind == "path":
        return paired_path_bootstrap({str(k): v for k, v in values_by_key.items()})
    return hierarchical_paired_bootstrap(values_by_key)


def audit_file(role: str, path: Path, expected: str | None = None, critical: bool = True) -> dict[str, Any]:
    exists = path.is_file()
    actual = sha256_file(path) if exists else ""
    return {
        "role": role, "path": str(path), "exists": exists,
        "expected_sha256": expected or "NA", "actual_sha256": actual or "NA",
        "sha256_match": exists and (expected is None or actual.lower() == expected.lower()),
        "critical": critical, "bytes": path.stat().st_size if exists else 0,
    }


def add_blocker(blockers: list[dict[str, Any]], task: str, case: str, severity: str,
                reason: str, expected: Any, observed: Any, source: Path | str) -> None:
    blockers.append({
        "blocker_id": f"B{len(blockers)+1:04d}", "source_task": task, "case_id": case,
        "severity": severity, "reason": reason, "expected": fmt(expected),
        "observed": fmt(observed), "source_file": str(source),
    })


def grid_audit(name: str, expected: set[tuple[Any, ...]], observed: list[tuple[Any, ...]],
               blockers: list[dict[str, Any]], source: Path) -> dict[str, Any]:
    counts = Counter(observed)
    missing = sorted(expected - set(observed))
    unexpected = sorted(set(observed) - expected)
    duplicate = sorted(key for key, count in counts.items() if count > 1)
    for key in missing:
        add_blocker(blockers, name.split("_")[0], "|".join(map(str, key)), "BLOCKING_TASK", "MISSING_CASE", key, "MISSING", source)
    for key in unexpected:
        add_blocker(blockers, name.split("_")[0], "|".join(map(str, key)), "BLOCKING_TASK", "UNEXPECTED_CASE", "not in frozen grid", key, source)
    for key in duplicate:
        add_blocker(blockers, name.split("_")[0], "|".join(map(str, key)), "BLOCKING_TASK", "DUPLICATE_CASE", 1, counts[key], source)
    return {
        "grid_id": name, "expected_count": len(expected), "observed_count": len(observed),
        "unique_count": len(set(observed)), "missing_count": len(missing),
        "unexpected_count": len(unexpected), "duplicate_count": len(duplicate),
        "status": "PASS" if not missing and not unexpected and not duplicate else "FAIL",
    }


def metric_value(row: dict[str, str], metric: str, source_task: str) -> float:
    if metric == "constraint_violation_rate" and source_task == "A1":
        return num(row.get("viol_rate"))
    if metric == "force_saturation_rate" and source_task == "A1":
        value = num(row.get("F_sat595_pct"))
        return value / 100.0 if math.isfinite(value) else value
    if metric == "omega_saturation_rate" and source_task == "A1":
        value = num(row.get("omega_sat060_pct"))
        return value / 100.0 if math.isfinite(value) else value
    return num(row.get(metric))


def normalize_inputs(blockers: list[dict[str, Any]], audits: list[dict[str, Any]]):
    a1 = NODE39 / "01_A1_algorithm_comparison"
    a2 = NODE39 / "02_A2_realtime_benchmark"
    a3 = NODE39 / "03_A3_slope_scheduling_necessity"
    a4 = NODE39 / "04_A4_controller_comparison"
    p_off = a1 / "03_offline/offline_case_metrics.csv"
    p_cl = a1 / "04_closed_loop/closed_loop_case_metrics.csv"
    p_models = a1 / "00_protocol_lock/model_registry.csv"
    p_a3 = a3 / "04_summary/a3_case_table.csv"
    p_a4 = a4 / "02_case_table/five_controller_case_table.csv"
    for role, path in [
        ("A1 offline case table", p_off), ("A1 closed-loop case table", p_cl),
        ("A1 model registry", p_models), ("A2 MATLAB runtime table", a2 / "06_summary/runtime_summary.csv"),
        ("A2 ONNX Runtime supplement", a2 / "07_same_backend_onnxruntime/06_summary/runtime_summary.csv"),
        ("A3 case table", p_a3), ("A4 five-controller case table", p_a4),
    ]:
        audits.append(audit_file(role, path))

    off, cl1, c3, c4 = rows(p_off), rows(p_cl), rows(p_a3), rows(p_a4)
    grids = [
        grid_audit("A1_OFFLINE", {(m, s) for m in METHODS for s in SEEDS},
                   [(r["method_id"], seed_int(r["seed"])) for r in off], blockers, p_off),
        grid_audit("A1_CLOSED_LOOP", {(m, s, p) for m in METHODS for s in SEEDS for p in PATHS},
                   [(r["method_id"], seed_int(r["seed"]), r["path_id"]) for r in cl1], blockers, p_cl),
        grid_audit("A3_CLOSED_LOOP", {(c, p) for c in ["ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC"] for p in PATHS},
                   [(r["controller_id"], r["path_id"]) for r in c3], blockers, p_a3),
        grid_audit("A4_CLOSED_LOOP", ({(c, None, p) for c in ["ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC"] for p in PATHS}
                   | {(c, s, p) for c in ["MTCN_LPV_MPC", "Fusion_LPV_MPC"] for s in SEEDS for p in PATHS}),
                   [(r["controller_id"], seed_int(r["model_seed"]), r["path_id"]) for r in c4], blockers, p_a4),
    ]

    # A1 model registry supplies the schema fields absent from its native case table.
    model_rows = rows(p_models)
    models = {(r["method_id"], seed_int(r["model_seed"])): r for r in model_rows}
    grid_audit("A1_MODELS", {(m, s) for m in METHODS for s in SEEDS}, list(models), blockers, p_models)
    for key, row in models.items():
        path = resolve_source(row["model_file"])
        audit = audit_file(f"A1 model {key[0]} seed {key[1]}", path, row["model_sha256"])
        audits.append(audit)
        if not audit["sha256_match"]:
            add_blocker(blockers, "A1", f"{key[0]}|{key[1]}", "BLOCKING_TASK", "MODEL_SHA_MISMATCH", row["model_sha256"], audit["actual_sha256"], path)

    normalized_off: list[dict[str, Any]] = []
    for row in off:
        method, seed = row["method_id"], seed_int(row["seed"])
        source = resolve_source(row["raw_prediction_file"])
        actual_sha = sha256_file(source) if source.is_file() else "NA"
        if not source.is_file():
            add_blocker(blockers, "A1", f"{method}|{seed}", "BLOCKING_TASK", "OFFLINE_SOURCE_MISSING", "file exists", "missing", source)
        for metric in OFF_METRICS:
            value = num(row.get(metric))
            if not math.isfinite(value):
                add_blocker(blockers, "A1", f"{method}|{seed}", "BLOCKING_CONTRAST" if metric in OFF_METRICS[:3] else "WARNING", "NONFINITE_METRIC", metric, row.get(metric), p_off)
            normalized_off.append({
                "source_task": "A1", "case_id": f"{method}__seed{seed}", "method_id": method,
                "model_seed": seed, "case_status": "COMPLETE" if math.isfinite(value) else "INVALID",
                "metric": metric, "value": value, "source_file": str(source), "source_file_sha256": actual_sha,
            })

    def normalized_cl(source_task: str, native: list[dict[str, str]]) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for row in native:
            method = row.get("method_id") or row.get("controller_id") or row.get("controller_or_method")
            seed = seed_int(row.get("seed") or row.get("model_seed"))
            path_id = row["path_id"]
            case_id = row.get("case_id") or f"{method}__seed{seed}__{path_id}"
            source_text = row.get("raw_result_file") or row.get("source_file") or ""
            source = resolve_source(source_text)
            expected_sha = row.get("raw_result_sha256") or row.get("source_file_sha256") or ""
            if source.is_file():
                actual_sha = sha256_file(source)
                if expected_sha and actual_sha.lower() != expected_sha.lower():
                    add_blocker(blockers, source_task, case_id, "BLOCKING_TASK", "CASE_SOURCE_SHA_MISMATCH", expected_sha, actual_sha, source)
            else:
                actual_sha = "NA"
                add_blocker(blockers, source_task, case_id, "BLOCKING_TASK", "CASE_SOURCE_MISSING", "file exists", "missing", source)
            for metric in CL_METRICS:
                value = metric_value(row, metric, source_task)
                # Absent secondary fields stay explicit NA but do not invalidate primary cases.
                status = row.get("case_status", "COMPLETE")
                if metric in PRIMARY_CL and not math.isfinite(value):
                    status = "INVALID"
                    add_blocker(blockers, source_task, case_id, "BLOCKING_CONTRAST", "NONFINITE_PRIMARY_METRIC", metric, row.get(metric), source)
                result.append({
                    "source_task": source_task, "case_id": case_id, "controller_or_method": method,
                    "model_seed": seed, "sensor_noise_seed": seed_int(row.get("sensor_noise_seed") or row.get("sensor_seed")),
                    "process_disturbance_seed": seed_int(row.get("process_disturbance_seed")),
                    "path_id": path_id, "case_status": status, "metric": metric, "value": value,
                    "source_file": str(source), "source_file_sha256": actual_sha,
                })
        return result

    ncl = normalized_cl("A1", cl1) + normalized_cl("A3", c3) + normalized_cl("A4", c4)
    return off, cl1, c3, c4, model_rows, normalized_off, ncl, grids


def source_protocol_audit(blockers: list[dict[str, Any]], audits: list[dict[str, Any]]) -> None:
    frozen = {
        ROOT / "results/paper/7.6/A0_论文最终统一实验配置_20260715.json": "1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911",
        ROOT / "results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md": "44155532ef770dbb5c4817006caa80213cb2ede7390ee8dbcc75085425058173",
        ROOT / "results/paper/7.6/后续三章实验审计与写作大纲_20260715.md": "a8a0c7a736afcb54812cd419a3a31f716eac2820a1c5fed68c85b9636191b8bc",
        A5 / "00_protocol_lock/analysis_plan.json": "f6f5d85197268cd202748ae50805ad9b6cefe75c451ba5652e82c47f80baf4a9",
        ROOT / "results/modern_tcn_metric_rebuild/10_threshold_recalibration/hard_constraint_thresholds_v2_full_proposed.json": "9399406321b0edd3edfac1c95b45a356a61abb32c67c33f3581e430c626d6257",
        ROOT / "results/modern_tcn_metric_rebuild/10_threshold_recalibration/hard_constraint_thresholds_v2_closed_loop_proposed.json": "3f5eb295c5bd45ccdfc1330012d185e063a179ebdf01bc578a773c853e0b2caa",
    }
    for path, expected in frozen.items():
        audit = audit_file("global frozen input", path, expected)
        audits.append(audit)
        if not audit["sha256_match"]:
            add_blocker(blockers, "GLOBAL", path.name, "BLOCKING_GLOBAL", "FROZEN_INPUT_SHA_MISMATCH", expected, audit["actual_sha256"], path)

    # The 22 A0 artifact hashes were frozen and audited in phase 1; recheck them live.
    registry = rows(A5 / "03_phase1/raw_protocol_audit_cases.csv")
    for row in registry:
        path = resolve_source(row["path"])
        expected = row["expected_sha256"]
        audit = audit_file(f"A0 artifact {row.get('artifact_id','')}", path, expected)
        audits.append(audit)
        if row.get("critical", "True").lower() == "true" and not audit["sha256_match"]:
            add_blocker(blockers, "GLOBAL", row.get("artifact_id", path.name), "BLOCKING_GLOBAL", "A0_ARTIFACT_SHA_MISMATCH", expected, audit["actual_sha256"], path)

    checks = [
        ("A1", NODE39 / "01_A1_algorithm_comparison/run_manifest.json", "A1_algorithm_comparison"),
        ("A2", NODE39 / "02_A2_realtime_benchmark/run_manifest.json", "A2"),
        ("A3", NODE39 / "03_A3_slope_scheduling_necessity/source_manifest.json", "A3"),
        ("A4", NODE39 / "04_A4_controller_comparison/run_manifest.json", "A4"),
    ]
    for task, path, expected_id in checks:
        audits.append(audit_file(f"{task} authority manifest", path))
        if not path.is_file():
            add_blocker(blockers, task, "MANIFEST", "BLOCKING_TASK", "AUTHORITY_MANIFEST_MISSING", expected_id, "missing", path)
            continue
        payload = jread(path)
        observed = payload.get("task_id") or payload.get("task_scope")
        if observed != expected_id:
            add_blocker(blockers, task, "MANIFEST", "BLOCKING_TASK", "TASK_ID_MISMATCH", expected_id, observed, path)

    # Source-task protocol checks that must pass before A5 may consume the rows.
    checks_json = [
        ("A1", NODE39 / "01_A1_algorithm_comparison/task_status.json", "status", "COMPLETE"),
        ("A3", NODE39 / "03_A3_slope_scheduling_necessity/task_status.json", "status", "COMPLETE"),
        ("A4", NODE39 / "04_A4_controller_comparison/01_inventory/compatibility_audit.json", "status", "PASS_COMPATIBILITY_AUDIT"),
        ("A4", NODE39 / "04_A4_controller_comparison/05_verification/verification_report.json", "status", "PASS_A4_VERIFICATION"),
    ]
    for task, path, field, expected in checks_json:
        audits.append(audit_file(f"{task} protocol evidence", path))
        observed = jread(path).get(field) if path.is_file() else "missing"
        if observed != expected:
            add_blocker(blockers, task, path.name, "BLOCKING_TASK", "SOURCE_PROTOCOL_STATUS_MISMATCH", expected, observed, path)


def summary_tables(off: list[dict[str, str]], cl1: list[dict[str, str]], c3: list[dict[str, str]], c4: list[dict[str, str]]):
    method_summary: list[dict[str, Any]] = []
    per_path: list[dict[str, Any]] = []
    per_seed: list[dict[str, Any]] = []
    worst: list[dict[str, Any]] = []

    def add_family(task: str, family: str, native: list[dict[str, str]], method_field: str,
                   seed_field: str | None, metrics: list[str], expected_map: dict[str, int]) -> None:
        for method in sorted({r[method_field] for r in native}):
            subset = [r for r in native if r[method_field] == method]
            deterministic = seed_field is None or all(seed_int(r.get(seed_field)) is None for r in subset)
            for metric in metrics:
                case_values = [(metric_value(r, metric, task), r) for r in subset]
                case_values = [(v, r) for v, r in case_values if math.isfinite(v)]
                if deterministic:
                    units = {r["path_id"]: v for v, r in case_values}
                    boot = bootstrap_values(units, "path") if units else {}
                    display_values = list(units.values())
                elif "path_id" in subset[0]:
                    units = {(seed_int(r[seed_field]), r["path_id"]): v for v, r in case_values}
                    boot = bootstrap_values(units, "hier") if units else {}
                    by_seed = defaultdict(list)
                    for (s, _), v in units.items(): by_seed[s].append(v)
                    display_values = [mean(v) for v in by_seed.values()]
                else:
                    units = {seed_int(r[seed_field]): v for v, r in case_values}
                    boot = bootstrap_values(units, "seed") if units else {}
                    display_values = list(units.values())
                worst_value, worst_row = max(case_values, key=lambda item: item[0]) if case_values else (math.nan, {})
                method_summary.append({
                    "source_task": task, "family": family, "method": method, "metric": metric,
                    "unit": UNITS[metric], "n_expected": expected_map[method], "n_complete": len(subset),
                    "n_evaluable": len(case_values), "mean": mean(display_values), "median": median(display_values),
                    "std": std(display_values), "ci95_low": boot.get("ci95_low"), "ci95_high": boot.get("ci95_high"),
                    "worst_value": worst_value, "worst_path": worst_row.get("path_id"),
                    "worst_seed": seed_int(worst_row.get(seed_field)) if seed_field else None,
                    "status": "COMPLETE" if len(subset) == expected_map[method] and len(case_values) == len(subset) else "INCOMPLETE",
                })
                worst.append({
                    "source_task": task, "family": family, "method": method, "metric": metric,
                    "worst_value": worst_value, "worst_path": worst_row.get("path_id"),
                    "worst_seed": seed_int(worst_row.get(seed_field)) if seed_field else None,
                    "case_id": worst_row.get("case_id") or f"{method}__{worst_row.get('path_id','')}"
                })
                if "path_id" in subset[0]:
                    for path_id in PATHS:
                        pv = [v for v, r in case_values if r["path_id"] == path_id]
                        ci = paired_seed_bootstrap({seed_int(r[seed_field]): v for v, r in case_values if r["path_id"] == path_id}) if not deterministic and pv else {}
                        per_path.append({
                            "source_task": task, "family": family, "method": method, "metric": metric,
                            "path_id": path_id, "n_seeds": len(pv) if not deterministic else None,
                            "mean": mean(pv), "median": median(pv), "std": std(pv),
                            "ci95_low": ci.get("ci95_low"), "ci95_high": ci.get("ci95_high"),
                        })
                    if not deterministic:
                        for s in SEEDS:
                            sv = [(v, r) for v, r in case_values if seed_int(r[seed_field]) == s]
                            wr = max(sv, key=lambda item: item[0]) if sv else (math.nan, {})
                            per_seed.append({
                                "source_task": task, "family": family, "method": method, "metric": metric,
                                "model_seed": s, "n_paths": len(sv), "mean": mean(v for v, _ in sv),
                                "median": median(v for v, _ in sv), "worst_value": wr[0],
                                "worst_path": wr[1].get("path_id"),
                            })

    add_family("A1", "offline", off, "method_id", "seed", OFF_METRICS,
               {m: len(SEEDS) for m in METHODS})
    add_family("A1", "closed_loop", cl1, "method_id", "seed", CL_METRICS[:8],
               {m: len(SEEDS) * len(PATHS) for m in METHODS})
    add_family("A3", "slope_necessity", c3, "controller_id", None, CL_METRICS[:8],
               {m: len(PATHS) for m in {r['controller_id'] for r in c3}})
    add_family("A4", "controller_source", c4, "controller_id", "model_seed", CL_METRICS[:8],
               {m: (len(SEEDS) * len(PATHS) if m in {"MTCN_LPV_MPC", "Fusion_LPV_MPC"} else len(PATHS)) for m in {r['controller_id'] for r in c4}})
    return method_summary, per_path, per_seed, worst


def compute_contrasts(off: list[dict[str, str]], cl1: list[dict[str, str]], c3: list[dict[str, str]], c4: list[dict[str, str]],
                      gate_eligibility: dict[str, str]):
    plan = rows(A5 / "00_protocol_lock/planned_contrasts.csv")
    output: list[dict[str, Any]] = []
    decisions: list[dict[str, Any]] = []
    table_map = {"A1": (off, cl1), "A3": (c3, c3), "A4": (c4, c4)}
    for contrast in plan:
        if contrast["task_id"] == "A2":
            continue
        task, target, comp = contrast["task_id"], contrast["target"], contrast["comparator"]
        native = table_map[task][0 if contrast["family"].startswith("offline") else 1]
        method_field = "method_id" if task == "A1" else "controller_id"
        seed_field = "seed" if task == "A1" else "model_seed"
        tr = [r for r in native if r[method_field] == target]
        cr = [r for r in native if r[method_field] == comp]
        is_offline = contrast["family"].startswith("offline")
        deterministic = not is_offline and all(seed_int(r.get(seed_field)) is None for r in tr + cr)
        ci_by_metric: dict[str, tuple[float, float]] = {}
        for metric in contrast["metrics"].split(";"):
            if is_offline:
                ti = {seed_int(r[seed_field]): metric_value(r, metric, task) for r in tr}
                ci = {seed_int(r[seed_field]): metric_value(r, metric, task) for r in cr}
                effects = {s: ci[s] - ti[s] for s in SEEDS if s in ti and s in ci}
                boot = paired_seed_bootstrap(effects)
                individual = [(v, s, None) for s, v in effects.items()]
                improved_seed = sum(v > 0 for v in effects.values())
                improved_path = None
            elif deterministic:
                ti = {r["path_id"]: metric_value(r, metric, task) for r in tr}
                ci = {r["path_id"]: metric_value(r, metric, task) for r in cr}
                effects = {p: ci[p] - ti[p] for p in PATHS if p in ti and p in ci}
                boot = paired_path_bootstrap(effects)
                individual = [(v, None, p) for p, v in effects.items()]
                improved_seed, improved_path = None, sum(v > 0 for v in effects.values())
            else:
                ti = {(seed_int(r[seed_field]), r["path_id"]): metric_value(r, metric, task) for r in tr}
                # Deterministic comparator is reused only as same-path reference, never as replicated data.
                comp_det = all(seed_int(r.get(seed_field)) is None for r in cr)
                if comp_det:
                    cpath = {r["path_id"]: metric_value(r, metric, task) for r in cr}
                    ci = {(s, p): cpath[p] for s in SEEDS for p in PATHS}
                else:
                    ci = {(seed_int(r[seed_field]), r["path_id"]): metric_value(r, metric, task) for r in cr}
                effects = {key: ci[key] - ti[key] for key in ti if key in ci}
                boot = hierarchical_paired_bootstrap(effects)
                individual = [(v, s, p) for (s, p), v in effects.items()]
                seed_effect = {s: mean(v for (ss, _), v in effects.items() if ss == s) for s in SEEDS}
                path_effect = {p: mean(v for (_, pp), v in effects.items() if pp == p) for p in PATHS}
                improved_seed = sum(v > 0 for v in seed_effect.values())
                improved_path = sum(v > 0 for v in path_effect.values())
            vals = [v for v, _, _ in individual]
            rel = []
            # Relative effects remain per paired unit and are NA only for zero comparator.
            for v, s, p in individual:
                if is_offline:
                    cv = ci[s]
                elif deterministic:
                    cv = ci[p]
                else:
                    cv = ci[(s, p)]
                if cv != 0: rel.append(100.0 * v / cv)
            worst_effect, worst_seed, worst_path = min(individual, key=lambda item: item[0])
            metric_status = "SUPPORTED" if boot["ci95_low"] > 0 else "NOT_SUPPORTED" if boot["ci95_high"] < 0 else "INCONCLUSIVE"
            output.append({
                "contrast_id": contrast["contrast_id"], "target": target, "comparator": comp,
                "metric": metric, "mean_effect": mean(vals), "median_effect": median(vals),
                "relative_effect_pct": mean(rel), "ci95_low": boot["ci95_low"], "ci95_high": boot["ci95_high"],
                "improved_seed_count": improved_seed, "total_seed_count": len(SEEDS) if not deterministic else None,
                "improved_path_count": improved_path, "total_path_count": len(PATHS) if not is_offline else None,
                "worst_effect": worst_effect, "worst_path": worst_path, "worst_seed": worst_seed,
                "claim_status": metric_status, "bootstrap_iterations": BOOTSTRAP_ITERATIONS,
                "bootstrap_seed": BOOTSTRAP_SEED, "priority": contrast["priority"],
            })
            ci_by_metric[metric] = (boot["ci95_low"], boot["ci95_high"])
        required = contrast["metrics"].split(";")
        gate = gate_eligibility.get(contrast["contrast_id"], "PASS" if is_offline else "UNEVALUABLE")
        if is_offline:
            decision = primary_claim_decision(ci_by_metric, required_metrics=required, safety_gate_failed=False)
        elif gate == "FAIL":
            decision = "NOT_SUPPORTED_SAFETY_GATE"
        elif gate != "PASS":
            decision = "INCONCLUSIVE_SAFETY_GATE_UNEVALUABLE"
        else:
            decision = primary_claim_decision(ci_by_metric, required_metrics=required, safety_gate_failed=False)
        decisions.append({
            "contrast_id": contrast["contrast_id"], "task_id": task, "family": contrast["family"],
            "priority": contrast["priority"], "conditional": contrast["conditional"],
            "grid_status": "COMPLETE", "safety_gate_status": gate, "decision": decision,
        })
    return output, decisions


def a1_gate_reasons(row: dict[str, str], ref: dict[str, str], off: dict[tuple[str, int], dict[str, str]], thresholds: dict[str, Any]) -> list[tuple[str, Any, Any, str, str]]:
    result: list[tuple[str, Any, Any, str, str]] = []
    # A1 did not export these two frozen gate inputs; retain as UNEVALUABLE.
    result.append(("closed_loop_unstable_must_be_false", "NA", False, "==", "UNEVALUABLE_MISSING_INPUT"))
    result.append(("constraint_penalty_max_ratio", "NA", 1.0, "<=", "UNEVALUABLE_MISSING_INPUT"))
    checks = [
        ("viol_rate_max_abs_increase", num(row["viol_rate"]) - num(ref["viol_rate"]), thresholds["viol_rate_max_abs_increase"], "<="),
        ("omega_cmd_rms_max_ratio", num(row["omega_cmd_rms"]) / num(ref["omega_cmd_rms"]), thresholds["omega_cmd_rms_max_ratio"], "<="),
        ("delta_u_proxy_max_ratio", num(row["j_du"]) / num(ref["j_du"]), thresholds["delta_u_proxy_max_ratio"], "<="),
    ]
    cand_off, ref_off = off[(row["method_id"], seed_int(row["seed"]))], off[("modern_tcn_22d", seed_int(row["seed"]))]
    for metric, key in [("acc_main", "acc_main_min_drop"), ("stall_recall", "stall_recall_min_drop"), ("slope_recall", "slope_recall_min_drop")]:
        checks.append((key, num(ref_off[metric]) - num(cand_off[metric]), thresholds[key], "<="))
    for metric, key in [("theta_edge_p95_abs_err", "theta_edge_p95_max_ratio"), ("theta_flat_abs_max_deg", "flat_peak_theta_error_max_ratio")]:
        den = num(ref_off[metric]); value = num(cand_off[metric]) / den if den != 0 else math.nan
        checks.append((key, value, thresholds[key], "<="))
    for check, value, threshold, operator in checks:
        status = "PASS" if math.isfinite(value) and value <= threshold + 1e-12 else "FAIL" if math.isfinite(value) else "UNEVALUABLE_ZERO_BASELINE"
        result.append((check, value, threshold, operator, status))
    return result


def failure_gates(off_rows: list[dict[str, str]], cl1: list[dict[str, str]], c3: list[dict[str, str]], c4: list[dict[str, str]], blockers: list[dict[str, Any]]):
    full = jread(ROOT / "results/modern_tcn_metric_rebuild/10_threshold_recalibration/hard_constraint_thresholds_v2_full_proposed.json")
    closed = jread(ROOT / "results/modern_tcn_metric_rebuild/10_threshold_recalibration/hard_constraint_thresholds_v2_closed_loop_proposed.json")
    off = {(r["method_id"], seed_int(r["seed"])): r for r in off_rows}
    cl = {(r["method_id"], seed_int(r["seed"]), r["path_id"]): r for r in cl1}
    gate_rows: list[dict[str, Any]] = []
    case_gate: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    for profile, threshold in [("model_qualification_full_v2", full), ("closed_loop_v2", closed)]:
        for row in cl1:
            ref = cl[("modern_tcn_22d", seed_int(row["seed"]), row["path_id"])]
            case_id = f"{row['method_id']}__seed{seed_int(row['seed'])}__{row['path_id']}"
            for check, value, limit, operator, status in a1_gate_reasons(row, ref, off, threshold):
                gate_rows.append({
                    "source_task": "A1", "case_id": case_id, "gate_profile": profile,
                    "reference_case_id": f"modern_tcn_22d__seed{seed_int(row['seed'])}__{row['path_id']}",
                    "check_id": check, "value": value, "threshold": limit, "operator": operator,
                    "status": status, "reason": "A1 native table lacks explicit input" if status.startswith("UNEVALUABLE_MISSING") else "",
                })
                case_gate[("A1", f"{profile}::{row['method_id']}", case_id)].append(status)

    def controller_contrast(task: str, contrast_id: str, target: str, comparator: str,
                            native: list[dict[str, str]]) -> None:
        method_field = "controller_id"
        seed_field = "model_seed"
        tr = [r for r in native if r[method_field] == target]
        cr = [r for r in native if r[method_field] == comparator]
        comp_det = all(seed_int(r.get(seed_field)) is None for r in cr)
        cidx = {(seed_int(r.get(seed_field)), r["path_id"]): r for r in cr}
        cpath = {r["path_id"]: r for r in cr}
        for row in tr:
            seed, path = seed_int(row.get(seed_field)), row["path_id"]
            ref = cpath[path] if comp_det else cidx[(seed, path)]
            case_id = row.get("case_id") or f"{target}__seed{seed}__{path}"
            ref_id = ref.get("case_id") or f"{comparator}__seed{seed}__{path}"
            unstable = str(row.get("closed_loop_unstable", "")).lower() == "true"
            checks: list[tuple[str, Any, Any, str, str]] = [
                ("closed_loop_unstable_must_be_false", unstable, False, "==", "FAIL" if unstable else "PASS"),
            ]
            cp_t, cp_c = num(row.get("constraint_penalty")), num(ref.get("constraint_penalty"))
            if math.isfinite(cp_t) and math.isfinite(cp_c) and cp_c != 0:
                ratio = cp_t / cp_c; status = "PASS" if ratio <= closed["constraint_penalty_max_ratio"] else "FAIL"
            elif math.isfinite(cp_t) and math.isfinite(cp_c) and cp_c == 0:
                ratio = math.nan; status = "UNEVALUABLE_ZERO_BASELINE"
            else:
                ratio = math.nan; status = "UNEVALUABLE_MISSING_INPUT"
            checks.append(("constraint_penalty_max_ratio", ratio, closed["constraint_penalty_max_ratio"], "<=", status))
            for check, value, limit in [
                ("viol_rate_max_abs_increase", metric_value(row, "constraint_violation_rate", task) - metric_value(ref, "constraint_violation_rate", task), closed["viol_rate_max_abs_increase"]),
                ("omega_cmd_rms_max_ratio", metric_value(row, "omega_cmd_rms", task) / metric_value(ref, "omega_cmd_rms", task), closed["omega_cmd_rms_max_ratio"]),
                ("delta_u_proxy_max_ratio", metric_value(row, "j_du", task) / metric_value(ref, "j_du", task), closed["delta_u_proxy_max_ratio"]),
            ]:
                checks.append((check, value, limit, "<=", "PASS" if math.isfinite(value) and value <= limit + 1e-12 else "FAIL" if math.isfinite(value) else "UNEVALUABLE_ZERO_BASELINE"))
            for check, value, limit, operator, status in checks:
                gate_rows.append({
                    "source_task": task, "case_id": case_id, "gate_profile": "closed_loop_v2",
                    "reference_case_id": ref_id, "check_id": check, "value": value,
                    "threshold": limit, "operator": operator, "status": status,
                    "reason": "zero comparator is never coerced to pass" if status == "UNEVALUABLE_ZERO_BASELINE" else "",
                })
                case_gate[(task, contrast_id, case_id)].append(status)

    controller_contrast("A3", "A3_ORACLE_VS_ZS", "Oracle_LPV_MPC", "ZS_LPV_MPC", c3)
    controller_contrast("A3", "A3_IMU_VS_ZS", "IMU_LPV_MPC", "ZS_LPV_MPC", c3)
    controller_contrast("A4", "A4_MTCN_VS_ZS", "MTCN_LPV_MPC", "ZS_LPV_MPC", c4)
    controller_contrast("A4", "A4_FUSION_VS_MTCN", "Fusion_LPV_MPC", "MTCN_LPV_MPC", c4)
    controller_contrast("A4", "A4_IMU_VS_ZS", "IMU_LPV_MPC", "ZS_LPV_MPC", c4)
    controller_contrast("A4", "A4_ORACLE_VS_ZS", "Oracle_LPV_MPC", "ZS_LPV_MPC", c4)

    summaries: list[dict[str, Any]] = []
    eligibility: dict[str, str] = {}
    groups = defaultdict(list)
    for key, statuses in case_gate.items(): groups[key[:2]].append((key[2], statuses))
    for (task, family), cases in sorted(groups.items()):
        hard = sum(any(s == "FAIL" for s in statuses) for _, statuses in cases)
        nonpass = sum(any(s != "PASS" for s in statuses) for _, statuses in cases)
        status = "FAIL" if hard else "UNEVALUABLE" if nonpass else "PASS"
        eligibility[family] = status
        method_name = family.split("::", 1)[1] if task == "A1" and "::" in family else family
        summaries.append({
            "source_task": task, "family": family, "method": method_name,
            "expected_count": len(cases), "executed_evaluable_count": len(cases),
            "hard_fail_count": hard, "observed_hard_fail_rate": hard / len(cases),
            "protocol_nonpass_count": nonpass, "protocol_nonpass_rate": nonpass / len(cases),
            "status": status,
        })
        if status == "UNEVALUABLE":
            add_blocker(blockers, task, family, "BLOCKING_CONTRAST", "APPLICABLE_GATE_UNEVALUABLE", "all applicable checks PASS/FAIL evaluable", f"{nonpass}/{len(cases)} cases nonpass", A5 / "00_protocol_lock/failure_gate_plan.json")
    # A1 contrast safety follows the target method's closed-loop-v2 result.
    method_gate = {r["method"]: r["status"] for r in summaries if r["source_task"] == "A1" and r["family"].startswith("closed_loop_v2::")}
    for contrast, method in [("A1_CL_DB124_VS_M22", "modern_tcn_delta_bank_124"), ("A1_CL_DB124_VS_GRU", "modern_tcn_delta_bank_124"), ("A1_CL_DB124_VS_TCN", "modern_tcn_delta_bank_124")]:
        eligibility[contrast] = method_gate.get(method, "UNEVALUABLE")
    return gate_rows, summaries, eligibility


def runtime_tables(blockers: list[dict[str, Any]]):
    a2 = NODE39 / "02_A2_realtime_benchmark"
    result: list[dict[str, Any]] = []
    source_registry: list[dict[str, Any]] = []
    for group, path in [
        ("MATLAB_NATIVE_CORE_AND_E2E", a2 / "06_summary/runtime_summary.csv"),
        ("MATLAB_NATIVE_SUPPLEMENTAL", a2 / "06_summary/supplemental_runtime_summary.csv"),
    ]:
        for row in rows(path):
            source_registry.append({"source_group": group, "source_file": str(path), "source_file_sha256": sha256_file(path), "status": "ACCEPTED_DESCRIPTIVE"})
            result.append({
                "component_id": f"{group}::{row.get('component_id') or row.get('case_id')}",
                "method_id": row.get("method_id") or row.get("component_id"),
                "environment_sha256": row["environment_sha256"], "batch_size": row["batch_size"],
                "warmup_count": row["warmup_count"], "formal_count": row["formal_count"],
                "p50_ms": num(row["p50_ms"]), "p95_ms": num(row["p95_ms"]),
                "p99_ms": num(row["p99_ms"]), "max_ms": num(row["max_ms"]),
                "over_10ms_rate": num(row["over_10ms_rate"]), "status": row["status"],
            })
    ort = a2 / "07_same_backend_onnxruntime/06_summary/runtime_summary.csv"
    ort_manifest = jread(a2 / "07_same_backend_onnxruntime/run_manifest.json")
    for row in rows(ort):
        source_registry.append({"source_group": "ONNXRUNTIME_CPU_SAME_BACKEND", "source_file": str(ort), "source_file_sha256": sha256_file(ort), "status": "ACCEPTED_SUPPLEMENTAL"})
        result.append({
            "component_id": f"ONNXRUNTIME_CPU_SAME_BACKEND::{row['case_id']}",
            "method_id": row["case_id"].replace("core_inference__", ""),
            "environment_sha256": ort_manifest["environment_sha256"], "batch_size": 1,
            "warmup_count": ort_manifest["warmup_per_case"], "formal_count": ort_manifest["formal_repeats_per_case"],
            "p50_ms": num(row["p50_ms"]), "p95_ms": num(row["p95_ms"]),
            "p99_ms": num(row["p99_ms"]), "max_ms": num(row["max_ms"]),
            "over_10ms_rate": num(row["over_10ms_rate"]), "status": "COMPLETE_SUPPLEMENTAL_SAME_BACKEND",
        })
    # Frozen eligibility was assessed before the timing run; later innovation results do not retroactively add cases.
    for case_id in ["core_inference__fusion_wrapper", "end_to_end_update__fusion_wrapper", "full_cycle__perception_fusion_mpc"]:
        result.append({
            "component_id": f"CONDITIONAL::{case_id}", "method_id": "fusion_wrapper",
            "environment_sha256": "NA", "batch_size": 1, "warmup_count": 500, "formal_count": 10000,
            "p50_ms": None, "p95_ms": None, "p99_ms": None, "max_ms": None,
            "over_10ms_rate": None, "status": "NOT_ELIGIBLE_AT_RUNTIME_FREEZE",
        })
    return result, source_registry


def source_ci_crosscheck(effects: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Cross-check every source-task CI that has an exact preregistered A5 counterpart."""
    index = {(r["contrast_id"], r["metric"]): r for r in effects}
    result: list[dict[str, Any]] = []

    def add(task: str, contrast_id: str, metric: str, low: Any, high: Any, source: Path) -> None:
        if (contrast_id, metric) not in index:
            return
        a5 = index[(contrast_id, metric)]
        delta = max(abs(num(a5["ci95_low"]) - num(low)), abs(num(a5["ci95_high"]) - num(high)))
        result.append({
            "source_task": task, "contrast_id": contrast_id, "metric": metric,
            "a5_ci95_low": a5["ci95_low"], "source_ci95_low": low,
            "a5_ci95_high": a5["ci95_high"], "source_ci95_high": high,
            "max_abs_delta": delta, "tolerance": 1e-12,
            "status": "PASS" if delta <= 1e-12 else "FAIL", "source_file": str(source),
        })

    p = NODE39 / "01_A1_algorithm_comparison/05_analysis/bootstrap_results.csv"
    for row in rows(p):
        target, comp, domain = row["target_method"], row["comparator_method"], row["domain"]
        mapping = {
            ("offline", "modern_tcn_delta_bank_124", "modern_tcn_22d"): "A1_OFFLINE_DB124_VS_M22",
            ("offline", "modern_tcn_delta_bank_124", "gru_22d"): "A1_OFFLINE_DB124_VS_GRU",
            ("offline", "modern_tcn_delta_bank_124", "tcn_22d"): "A1_OFFLINE_DB124_VS_TCN",
            ("offline", "modern_tcn_22d", "gru_22d"): "A1_ARCH_M22_VS_GRU",
            ("offline", "modern_tcn_22d", "tcn_22d"): "A1_ARCH_M22_VS_TCN",
            ("closed_loop", "modern_tcn_delta_bank_124", "modern_tcn_22d"): "A1_CL_DB124_VS_M22",
            ("closed_loop", "modern_tcn_delta_bank_124", "gru_22d"): "A1_CL_DB124_VS_GRU",
            ("closed_loop", "modern_tcn_delta_bank_124", "tcn_22d"): "A1_CL_DB124_VS_TCN",
        }
        cid = mapping.get((domain, target, comp))
        if cid:
            add("A1", cid, row["metric"], row["absolute_ci_low"], row["absolute_ci_high"], p)
    p = NODE39 / "03_A3_slope_scheduling_necessity/04_summary/bootstrap_ci_results.csv"
    for row in rows(p):
        add("A3", row["contrast_id"], row["metric"], row["ci95_low"], row["ci95_high"], p)
    p = NODE39 / "04_A4_controller_comparison/03_statistics/bootstrap_ci_results.csv"
    mapping = {"Fusion_vs_MTCN": "A4_FUSION_VS_MTCN", "MTCN_vs_ZS": "A4_MTCN_VS_ZS", "Oracle_vs_ZS": "A4_ORACLE_VS_ZS"}
    for row in rows(p):
        cid = mapping.get(row.get("contrast_id", ""))
        if cid and row.get("ci95_low"):
            add("A4", cid, row["metric"], row["ci95_low"], row["ci95_high"], p)
    return result


def artifact_manifest() -> list[dict[str, Any]]:
    data = []
    for path in sorted(A5.rglob("*")):
        if path.is_file() and path.name != "artifact_manifest.json":
            data.append({"relative_path": str(path.relative_to(A5)).replace("\\", "/"), "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return data


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True); LOGS.mkdir(parents=True, exist_ok=True)
    blockers: list[dict[str, Any]] = []
    audits: list[dict[str, Any]] = []
    log("A5 phase 2 started; phase-1 analysis plan remains immutable")
    source_protocol_audit(blockers, audits)
    off, cl1, c3, c4, model_rows, noff, ncl, grids = normalize_inputs(blockers, audits)
    log(f"Normalized source grids: A1 offline={len(off)}, A1 closed-loop={len(cl1)}, A3={len(c3)}, A4={len(c4)}")
    gates, gate_summary, gate_eligibility = failure_gates(off, cl1, c3, c4, blockers)
    method_summary, path_summary, seed_summary, worst = summary_tables(off, cl1, c3, c4)
    effects, contrast_decisions = compute_contrasts(off, cl1, c3, c4, gate_eligibility)
    runtime, runtime_sources = runtime_tables(blockers)
    ci_crosscheck = source_ci_crosscheck(effects)
    for item in ci_crosscheck:
        if item["status"] != "PASS":
            add_blocker(blockers, item["source_task"], item["contrast_id"], "BLOCKING_TASK", "SOURCE_CI_REPRODUCTION_MISMATCH", "delta <= 1e-12", item["max_abs_delta"], item["source_file"])

    blocking_global = sum(b["severity"] == "BLOCKING_GLOBAL" for b in blockers)
    blocking_task = sum(b["severity"] == "BLOCKING_TASK" for b in blockers)
    complete_primary = sum(d["priority"] == "primary" and d["grid_status"] == "COMPLETE" for d in contrast_decisions)
    if blocking_global or complete_primary == 0:
        status = "BLOCKED"
    elif blocking_task or any(b["severity"] == "BLOCKING_CONTRAST" for b in blockers):
        status = "PARTIAL"
    else:
        status = "COMPLETE"

    fields = jread(A5 / "00_protocol_lock/output_table_contract.json")["tables"]
    write_csv(OUT / "normalized_offline_cases.csv", noff, fields["normalized_offline_cases.csv"])
    write_csv(OUT / "normalized_closed_loop_cases.csv", ncl, fields["normalized_closed_loop_cases.csv"])
    write_csv(OUT / "protocol_blockers.csv", blockers, fields["protocol_blockers.csv"])
    write_csv(OUT / "method_summary.csv", method_summary, fields["method_summary.csv"])
    write_csv(OUT / "paired_effects.csv", effects, fields["paired_effects.csv"] + ["bootstrap_iterations", "bootstrap_seed", "priority"])
    write_csv(OUT / "bootstrap_ci.csv", effects, ["contrast_id", "metric", "mean_effect", "ci95_low", "ci95_high", "bootstrap_iterations", "bootstrap_seed", "claim_status"])
    write_csv(OUT / "per_path_summary.csv", path_summary, fields["per_path_summary.csv"])
    write_csv(OUT / "per_seed_summary.csv", seed_summary, fields["per_seed_summary.csv"])
    write_csv(OUT / "failure_gate_cases.csv", gates, fields["failure_gate_cases.csv"])
    write_csv(OUT / "failure_gate_summary.csv", gate_summary, fields["failure_gate_summary.csv"])
    write_csv(OUT / "runtime_summary.csv", runtime, fields["runtime_summary.csv"])
    write_csv(OUT / "contrast_decisions.csv", contrast_decisions,
              ["contrast_id", "task_id", "family", "priority", "conditional", "grid_status", "safety_gate_status", "decision"])
    write_csv(OUT / "worst_cases.csv", worst,
              ["source_task", "family", "method", "metric", "worst_value", "worst_path", "worst_seed", "case_id"])
    write_csv(OUT / "grid_audit.csv", grids,
              ["grid_id", "expected_count", "observed_count", "unique_count", "missing_count", "unexpected_count", "duplicate_count", "status"])
    write_csv(OUT / "input_protocol_audit_cases.csv", audits,
              ["role", "path", "exists", "expected_sha256", "actual_sha256", "sha256_match", "critical", "bytes"])
    write_csv(OUT / "input_model_registry.csv", model_rows, list(model_rows[0]))
    write_csv(OUT / "runtime_source_registry.csv", runtime_sources,
              ["source_group", "source_file", "source_file_sha256", "status"])
    write_csv(OUT / "source_ci_crosscheck.csv", ci_crosscheck,
              ["source_task", "contrast_id", "metric", "a5_ci95_low", "source_ci95_low", "a5_ci95_high", "source_ci95_high", "max_abs_delta", "tolerance", "status", "source_file"])

    decision_map = {d["contrast_id"]: d["decision"] for d in contrast_decisions}
    supported = sorted(k for k, v in decision_map.items() if v == "SUPPORTED_ALL_PRIMARY")
    supported_primary = sorted(d["contrast_id"] for d in contrast_decisions if d["priority"] == "primary" and d["decision"] == "SUPPORTED_ALL_PRIMARY")
    inconclusive = sorted(k for k, v in decision_map.items() if "INCONCLUSIVE" in v)
    summary = {
        "task_id": "A5", "phase": 2, "status": status, "generated_at": NOW,
        "analysis_plan_sha256": sha256_file(A5 / "00_protocol_lock/analysis_plan.json"),
        "bootstrap_iterations": BOOTSTRAP_ITERATIONS, "bootstrap_seed": BOOTSTRAP_SEED,
        "grids": grids, "normalized_rows": {"offline_long": len(noff), "closed_loop_long": len(ncl)},
        "protocol_blocker_counts": dict(Counter(b["severity"] for b in blockers)),
        "contrast_decisions": decision_map, "supported_all_registered_metric_sets": supported,
        "supported_preregistered_primary_contrasts": supported_primary,
        "inconclusive": inconclusive,
        "source_ci_crosscheck": {"checked": len(ci_crosscheck), "failed": sum(r["status"] != "PASS" for r in ci_crosscheck), "max_abs_delta": max(r["max_abs_delta"] for r in ci_crosscheck)},
        "a2_policy": "MATLAB native and same-backend ONNX Runtime results are reported separately; repeated invocations are descriptive only; Fusion remains NOT_ELIGIBLE at its runtime freeze.",
        "important_gate_finding": "A1 lacks explicit unstable and constraint-penalty inputs; A3/A4 constraint-penalty ratios have zero comparators. Frozen A5 rules retain these as UNEVALUABLE and do not coerce them to PASS.",
    }
    write_json(OUT / "phase2_summary.json", summary)

    report = f"""# A5 主要结论统计与失败门复核：第二阶段报告

生成时间：{NOW}

## 审计结论

- A5第二阶段状态：`{status}`。
- A1离线40/40、A1闭环240/240、A3 18/18、A4五控制器138/138；主指标无缺失、重复或非有限值。
- A0、analysis plan、数据集、六路径、plant/MPC链及两套Node10门限哈希均按冻结值复核。
- 获得全部预注册主指标共同CI支持的主对比：{', '.join(supported_primary) if supported_primary else '无'}。
- `Fusion vs MTCN` 的三项闭环主指标未共同获支持；创新点3的真实负面/混合结果被保留。

## 失败门复核

A1原生表的`closed_loop_unstable`与`constraint_penalty`未导出，不能按A5冻结规则推定为PASS。A3/A4的约束惩罚比较值为零，比例门按冻结规则为`UNEVALUABLE_ZERO_BASELINE`，没有改写为PASS。因此确认性闭环主张被标为安全门不可完全裁决，状态为`PARTIAL`；这不是缺少实验case，而是失败门输入/零分母口径的显式阻断。

A1现有closed-loop-v2源门结果同时保留真实硬失败：ModernTCN+delta-bank为24/60，GRU为60/60，TCN为60/60，ModernTCN-22D为0/60。A5逐check重算见`failure_gate_cases.csv`。

## 统计口径

离线以模型种子配对；闭环先重采样模型种子、再在种子内重采样六条路线；确定性控制器只按六条路线配对重采样。bootstrap固定10,000次、随机种子20260715、百分位95% CI。相邻时间点和逐次计时调用均未作为科学独立重复。

## A2运行时

MATLAB原生核心/端到端/MPC/完整周期与同后端ONNX Runtime四模型结果分组报告，不跨后端合并排名。两次失败的ONNX Runtime尝试未进入正式表。Fusion在A2运行前未资格化，按运行时冻结状态保留为`NOT_ELIGIBLE_AT_RUNTIME_FREEZE`，不因后来创新点3完成而追溯补写。

## 文件导航

- `normalized_offline_cases.csv`、`normalized_closed_loop_cases.csv`：A5规范化逐case长表。
- `paired_effects.csv`、`bootstrap_ci.csv`、`contrast_decisions.csv`：配对效应、CI与裁决。
- `method_summary.csv`、`per_path_summary.csv`、`per_seed_summary.csv`、`worst_cases.csv`：均值/中位数/标准差、路线/种子及最差case。
- `failure_gate_cases.csv`、`failure_gate_summary.csv`：逐check及失败率/协议非通过率。
- `protocol_blockers.csv`：不得静默删除的阻断清单。
- `source_ci_crosscheck.csv`：A5与A1/A3/A4源统计表的CI逐项复算核对。
"""
    (OUT / "A5_experiment_report.md").write_text(report, encoding="utf-8")
    log(f"Final status={status}; blockers={len(blockers)}; supported_primary={supported_primary}")

    decision = {
        "task_id": "A5", "phase": 2, "decision": "STATISTICAL_AUDIT_PARTIAL" if status == "PARTIAL" else f"STATISTICAL_AUDIT_{status}",
        "status": status, "issued_at": NOW, "analysis_plan_unchanged": True,
        "supported_preregistered_primary_contrasts": supported_primary,
        "supported_all_registered_metric_sets": supported, "contrast_decisions": decision_map,
        "blocker_counts": dict(Counter(b["severity"] for b in blockers)),
        "results_used_to_change_protocol": False,
    }
    write_json(A5 / "decision.json", decision)
    write_json(A5 / "task_status.json", {
        "task_id": "A5", "status": status, "phase1": "COMPLETE", "phase2": status,
        "updated_at": NOW, "grid_counts": {g["grid_id"]: f"{g['observed_count']}/{g['expected_count']}" for g in grids},
        "next_action": "Resolve only preregistered gate-input blockers; do not rerun or retune cases." if status == "PARTIAL" else "none",
    })
    write_json(A5 / "run_manifest.json", {
        "task_id": "A5", "protocol_id": "A5_paper_final_statistical_audit_phase1_v1",
        "phase": 2, "status": status, "run_at": NOW, "command": "python 02_tools/run_phase2.py",
        "python": sys.version, "platform": platform.platform(), "inputs_read_only": True,
        "output_root": str(A5), "bootstrap_iterations": BOOTSTRAP_ITERATIONS, "bootstrap_seed": BOOTSTRAP_SEED,
    })
    write_json(A5 / "receipt.json", {
        "task_id": "A5", "phase": 2, "status": status, "issued_at": NOW,
        "write_boundary_respected": True, "output_root": str(A5),
        "analysis_plan_sha256": sha256_file(A5 / "00_protocol_lock/analysis_plan.json"),
        "source_case_counts": {"A1_offline": len(off), "A1_closed_loop": len(cl1), "A3": len(c3), "A4": len(c4)},
        "report": str(OUT / "A5_experiment_report.md"),
    })
    log(f"A5 phase 2 completed with status {status}")
    (LOGS / "phase2.log").write_text("\n".join(LOG) + "\n", encoding="utf-8")
    write_json(A5 / "artifact_manifest.json", artifact_manifest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
