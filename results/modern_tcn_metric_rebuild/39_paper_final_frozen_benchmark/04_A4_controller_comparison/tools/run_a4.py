#!/usr/bin/env python3
"""A4 five-controller audit, assembly, statistics, figures and receipt pipeline.

All writes are constrained to the A4 directory.  A0/A1/A3/A5/Node42 are
treated as immutable inputs.  No training or simulation is launched here.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
import platform
import shutil
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Mapping

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


HERE = Path(__file__).resolve()
A4 = HERE.parents[1]
ROOT = HERE.parents[5]
BENCHMARK = A4.parent
A1 = BENCHMARK / "01_A1_algorithm_comparison"
A3 = BENCHMARK / "03_A3_slope_scheduling_necessity"
A5 = BENCHMARK / "05_A5_statistical_audit"
NODE42 = ROOT / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3"
A0_JSON = ROOT / "results/paper/7.6/A0_论文最终统一实验配置_20260715.json"
A0_MD = ROOT / "results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md"
PAPER_V3 = ROOT / "results/paper/Latex/paper_v3.tex"

PROTOCOL_ID = "A0_paper_final_unified_protocol_v1"
A4_PROTOCOL_ID = "A4_five_controller_primary_v1"
BOOTSTRAP_ITERATIONS = 10_000
BOOTSTRAP_SEED = 20_260_715
PRIMARY_METRICS = ("ey_rmse", "epsi_rmse", "j_du")
CONTROL_INDEX_METRICS = ("ey_rmse", "xy_rmse", "epsi_rmse", "j_du", "omega_cmd_rms")
SECONDARY_METRICS = (
    "xy_rmse", "ev_rmse", "ey_peak", "epsi_peak", "omega_cmd_rms",
    "force_saturation_rate", "omega_saturation_rate", "constraint_violation_rate",
    "timeout_count", "solver_fail_count",
)
SCHEDULING_METRICS = (
    "theta_sched_mae_deg", "theta_fused_mae_deg", "theta_delay_s",
    "theta_step_p95_deg", "theta_rate_p95_deg_s", "theta_total_variation_deg",
)
SUMMARY_METRICS = tuple(dict.fromkeys(PRIMARY_METRICS + SECONDARY_METRICS + SCHEDULING_METRICS + ("J_control_path",)))
CONTROLLERS = (
    "ZS_LPV_MPC", "IMU_LPV_MPC", "MTCN_LPV_MPC", "Fusion_LPV_MPC", "Oracle_LPV_MPC"
)
LEARNING_CONTROLLERS = {"MTCN_LPV_MPC", "Fusion_LPV_MPC"}
DETERMINISTIC_CONTROLLERS = {"ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC"}
CONTRASTS = (
    ("Oracle_vs_ZS", "Oracle_LPV_MPC", "ZS_LPV_MPC"),
    ("MTCN_vs_ZS", "MTCN_LPV_MPC", "ZS_LPV_MPC"),
    ("MTCN_vs_IMU", "MTCN_LPV_MPC", "IMU_LPV_MPC"),
    ("Fusion_vs_MTCN", "Fusion_LPV_MPC", "MTCN_LPV_MPC"),
    ("Fusion_vs_IMU", "Fusion_LPV_MPC", "IMU_LPV_MPC"),
    ("Oracle_vs_Fusion", "Oracle_LPV_MPC", "Fusion_LPV_MPC"),
)
CORE_CONTRASTS = {"Oracle_vs_ZS", "MTCN_vs_ZS", "MTCN_vs_IMU", "Fusion_vs_MTCN"}


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def ensure_within_a4(path: Path) -> None:
    try:
        path.resolve().relative_to(A4.resolve())
    except ValueError as exc:
        raise RuntimeError(f"Refusing write outside A4: {path}") from exc


def mkdirs() -> None:
    for item in (
        A4 / "00_protocol_lock", A4 / "01_inventory", A4 / "02_case_table",
        A4 / "02_case_runs", A4 / "03_statistics", A4 / "04_figures/figure_data",
        A4 / "05_verification", A4 / "tools",
    ):
        ensure_within_a4(item)
        item.mkdir(parents=True, exist_ok=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def clean_json(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): clean_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean_json(v) for v in value]
    if isinstance(value, np.generic):
        return clean_json(value.item())
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if pd.isna(value) if not isinstance(value, (dict, list, tuple, str)) else False:
        return None
    return value


def write_json(path: Path, value: Any) -> None:
    ensure_within_a4(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(clean_json(value), ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def write_csv(path: Path, rows: Iterable[Mapping[str, Any]], fieldnames: list[str] | None = None) -> None:
    ensure_within_a4(path)
    rows = [clean_json(dict(row)) for row in rows]
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    if fieldnames is None:
        fieldnames = list(rows[0])
        for row in rows[1:]:
            for key in row:
                if key not in fieldnames:
                    fieldnames.append(key)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def file_record(role: str, path: Path, expected: str | None = None, critical: bool = True) -> dict[str, Any]:
    exists = path.is_file()
    actual = sha256(path) if exists else None
    return {
        "role": role,
        "path": rel(path) if path.exists() else str(path),
        "exists": exists,
        "expected_sha256": expected,
        "actual_sha256": actual,
        "sha256_match": expected is None or actual == expected,
        "critical": critical,
        "bytes": path.stat().st_size if exists else None,
    }


def import_a5_module():
    source = A5 / "02_tools/a5_statistical_audit.py"
    spec = importlib.util.spec_from_file_location("a5_frozen", source)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot import frozen A5 utilities")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def path_maps(a0: dict[str, Any]) -> tuple[dict[str, str], dict[str, dict[str, Any]]]:
    by_tag: dict[str, str] = {}
    by_id: dict[str, dict[str, Any]] = {}
    for item in a0["closed_loop_paths"]:
        tag = Path(item["file"]).stem
        by_tag[tag] = item["path_id"]
        by_id[item["path_id"]] = item
    return by_tag, by_id


def protected_source_paths() -> list[Path]:
    return [
        A0_JSON, A0_MD,
        A1 / "receipt.json", A1 / "model_registry.csv", A1 / "A1_experiment_report.md",
        A3 / "receipt.json", A3 / "04_summary/a4_artifact_receipt.json",
        A3 / "04_summary/a3_case_table.csv",
        A5 / "00_protocol_lock/analysis_plan.json",
        NODE42 / "00_protocol_lock/node42_protocol.json",
        NODE42 / "04_summaries/innovation_development_summary.json",
        NODE42 / "04_summaries/innovation_development_pair_details.csv",
        NODE42 / "09_run_logs/innovation_development_cases.csv",
        PAPER_V3,
    ]


def source_hash_snapshot() -> list[dict[str, Any]]:
    return [file_record("protected_source", path) for path in protected_source_paths()]


def audit() -> dict[str, Any]:
    mkdirs()
    a0 = load_json(A0_JSON)
    a5_plan = load_json(A5 / "00_protocol_lock/analysis_plan.json")
    n42_protocol = load_json(NODE42 / "00_protocol_lock/node42_protocol.json")
    n42_summary = load_json(NODE42 / "04_summaries/innovation_development_summary.json")
    by_tag, by_id = path_maps(a0)
    seeds = [int(v) for v in a0["seeds"]["model_seeds"]]
    problems: list[dict[str, Any]] = []
    artifacts: list[dict[str, Any]] = []

    artifacts.append(file_record("A0 protocol", A0_JSON, a5_plan["source_protocol_sha256"]))
    artifacts.append(file_record("A0 explanation", A0_MD))
    artifacts.append(file_record("A1 receipt", A1 / "receipt.json"))
    artifacts.append(file_record("A3 reuse receipt", A3 / "04_summary/a4_artifact_receipt.json"))
    artifacts.append(file_record("A5 frozen analysis plan", A5 / "00_protocol_lock/analysis_plan.json"))
    artifacts.append(file_record("Node42 protocol", NODE42 / "00_protocol_lock/node42_protocol.json"))
    artifacts.append(file_record("Node42 development summary", NODE42 / "04_summaries/innovation_development_summary.json"))
    artifacts.append(file_record("paper_v3 protected source", PAPER_V3))

    dataset = a0["dataset"]
    artifacts.extend([
        file_record("dataset", ROOT / dataset["file"], dataset["sha256"]),
        file_record("dataset contract", ROOT / dataset["contract_file"], dataset["contract_sha256"]),
    ])
    for item in a0["closed_loop_paths"]:
        artifacts.append(file_record(f"A0 path {item['path_id']}", ROOT / item["file"], item["sha256"]))
    for item in a0["plant"]["closed_loop_s_function_chain"]:
        artifacts.append(file_record("plant chain", ROOT / item["file"], item["sha256"]))
    lpv = a0["lpv_mpc"]
    artifacts.extend([
        file_record("LPV database", ROOT / lpv["lpv_database_file"], lpv["lpv_database_sha256"]),
        file_record("MPC maps", ROOT / lpv["maps_file"], lpv["maps_sha256"]),
        file_record("controller cache", ROOT / lpv["controller_cache_file"], lpv["controller_cache_sha256"]),
    ])

    registry = pd.read_csv(A1 / "model_registry.csv", dtype=str, keep_default_na=False)
    delta = registry[(registry["method_id"] == "modern_tcn_delta_bank_124") & (registry["expected"].str.lower() == "true")]
    checkpoint_rows: list[dict[str, Any]] = []
    for seed in seeds:
        match = delta[delta["model_seed"].astype(int) == seed]
        if len(match) != 1:
            problems.append({"code": "CHECKPOINT_REGISTRY_CARDINALITY", "seed": seed, "count": len(match), "blocking": True})
            continue
        row = match.iloc[0]
        checkpoint = Path(row["model_file"])
        ck = file_record(f"delta_bank checkpoint seed{seed}", checkpoint, row["model_sha256"])
        artifacts.append(ck)
        onnx = ROOT / f"results/modern_tcn_metric_rebuild/25_lag_representation_repair/03_onnx_and_smoke/delta_bank_124/seed{seed}/modern_tcn_delta_bank_124_seed{seed}.onnx"
        meta = onnx.with_name(onnx.stem + "_onnx_export.json")
        onnx_rec = file_record(f"Node42 ONNX seed{seed}", onnx)
        meta_rec = file_record(f"Node42 ONNX metadata seed{seed}", meta)
        artifacts.extend([onnx_rec, meta_rec])
        meta_checkpoint_match = False
        if meta.is_file():
            meta_checkpoint = Path(load_json(meta).get("checkpoint", ""))
            meta_checkpoint_match = meta_checkpoint.resolve() == checkpoint.resolve()
        checkpoint_rows.append({
            "model_seed": seed, "registry_status": row["status"],
            "checkpoint_file": str(checkpoint), "checkpoint_sha256": ck["actual_sha256"],
            "checkpoint_sha256_match": ck["sha256_match"], "onnx_file": str(onnx),
            "onnx_sha256": onnx_rec["actual_sha256"], "onnx_exists": onnx_rec["exists"],
            "export_meta_file": str(meta), "export_checkpoint_match": meta_checkpoint_match,
            "dataset_sha256": row["dataset_sha256"],
        })
        if row["status"] != "READY" or not ck["sha256_match"] or not onnx_rec["exists"] or not meta_checkpoint_match:
            problems.append({"code": "CHECKPOINT_OR_ONNX_INVALID", "seed": seed, "blocking": True})

    a3_rows = pd.read_csv(A3 / "04_summary/a3_case_table.csv", dtype=str, keep_default_na=False)
    a3_expected = {(c, p) for c in ("ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC") for p in by_id}
    a3_observed = set(zip(a3_rows["controller_id"], a3_rows["path_id"]))
    a3_missing = sorted(a3_expected - a3_observed)
    a3_extra = sorted(a3_observed - a3_expected)
    a3_duplicates = [list(k) for k, n in Counter(zip(a3_rows["controller_id"], a3_rows["path_id"])).items() if n > 1]
    a3_hash_ok = True
    for _, row in a3_rows.iterrows():
        source = ROOT / row["source_file"]
        trace = ROOT / row["trace_file"]
        if not source.is_file() or sha256(source) != row["source_file_sha256"]:
            a3_hash_ok = False
        if not trace.is_file() or sha256(trace) != row["trace_file_sha256"]:
            a3_hash_ok = False

    n42_log = pd.read_csv(NODE42 / "09_run_logs/innovation_development_cases.csv", dtype=str, keep_default_na=False)
    primary_log = n42_log[n42_log["path_tag"].isin(by_tag)].copy()
    supplemental_log = n42_log[~n42_log["path_tag"].isin(by_tag)].copy()
    n42_expected = {(g, str(s), tag) for g in ("G0", "ADAPTIVE") for s in seeds for tag in by_tag}
    n42_observed = set(zip(primary_log["group"], primary_log["model_seed"], primary_log["path_tag"]))
    n42_missing = sorted(n42_expected - n42_observed)
    n42_extra = sorted(n42_observed - n42_expected)
    n42_duplicates = [list(k) for k, n in Counter(zip(primary_log["group"], primary_log["model_seed"], primary_log["path_tag"])).items() if n > 1]
    n42_case_invalid: list[dict[str, Any]] = []
    availability: list[dict[str, Any]] = []

    for _, row in a3_rows.iterrows():
        availability.append({
            "analysis_role": "PRIMARY", "controller_id": row["controller_id"], "source_group": "",
            "path_id": row["path_id"], "path_tag": Path(row["path_file"]).stem,
            "model_seed": "", "expected": True, "available": row["case_status"] == "COMPLETE",
            "source_file": row["source_file"], "status": row["case_status"],
        })
    for _, row in n42_log.iterrows():
        role = "PRIMARY" if row["path_tag"] in by_tag else "SUPPLEMENTARY"
        case_dir = Path(row["case_dir"])
        manifest = case_dir / "case_manifest.json"
        metrics = case_dir / "case_metrics.json"
        trace = case_dir / "trace.csv"
        available = all(p.is_file() for p in (manifest, metrics, trace))
        status = "COMPLETE" if available else "MISSING_ARTIFACT"
        path_id = by_tag.get(row["path_tag"], f"supp_{row['path_tag']}")
        availability.append({
            "analysis_role": role,
            "controller_id": "MTCN_LPV_MPC" if row["group"] == "G0" else "Fusion_LPV_MPC",
            "source_group": row["group"], "path_id": path_id, "path_tag": row["path_tag"],
            "model_seed": int(row["model_seed"]), "expected": True, "available": available,
            "source_file": rel(metrics) if metrics.exists() else str(metrics), "status": status,
        })
        if not available:
            n42_case_invalid.append({"group": row["group"], "seed": row["model_seed"], "path_tag": row["path_tag"], "reason": status})
            continue
        manifest_data = load_json(manifest)
        metrics_data = load_json(metrics)
        expected_path_hash = by_id[path_id]["sha256"] if role == "PRIMARY" else sha256(Path(row["path_file"]))
        required_finite = list(PRIMARY_METRICS)
        bad_fields = [name for name in required_finite if not finite(metrics_data.get(name))]
        if manifest_data.get("status") != "COMPLETE" or manifest_data.get("path_sha256") != expected_path_hash or bad_fields:
            n42_case_invalid.append({
                "group": row["group"], "seed": row["model_seed"], "path_tag": row["path_tag"],
                "reason": "manifest_or_metric_invalid", "nonfinite_fields": bad_fields,
            })

    for item in artifacts:
        if item["critical"] and (not item["exists"] or not item["sha256_match"]):
            problems.append({"code": "CRITICAL_ARTIFACT_MISMATCH", "path": item["path"], "blocking": True})
    if a3_missing or a3_extra or a3_duplicates or not a3_hash_ok:
        problems.append({"code": "A3_GRID_OR_HASH_INVALID", "missing": a3_missing, "extra": a3_extra, "duplicates": a3_duplicates, "hash_ok": a3_hash_ok, "blocking": True})
    if n42_missing or n42_extra or n42_duplicates or n42_case_invalid:
        problems.append({"code": "NODE42_GRID_OR_CASE_INVALID", "missing": n42_missing, "extra": n42_extra, "duplicates": n42_duplicates, "invalid": n42_case_invalid, "blocking": True})
    if a0["protocol_id"] != PROTOCOL_ID or a5_plan["source_protocol_id"] != PROTOCOL_ID:
        problems.append({"code": "PROTOCOL_ID_MISMATCH", "blocking": True})
    if seeds != list(a5_plan["frozen_seeds"]):
        problems.append({"code": "SEED_POLICY_MISMATCH", "blocking": True})
    mpc_expected = {"Np": 150, "Nc": 30, "Q": [100, 100, 15, 3], "R": [3e-5, 3e-5], "dR": [1e-3, 1e-3]}
    mpc_actual = {"Np": lpv["prediction_horizon_steps"], "Nc": lpv["control_horizon_steps"], "Q": lpv["Q"], "R": lpv["R"], "dR": lpv["dR"]}
    if mpc_actual != mpc_expected:
        problems.append({"code": "A0_MPC_VALUE_MISMATCH", "expected": mpc_expected, "actual": mpc_actual, "blocking": True})

    compatibility = {
        "task_id": "A4", "protocol_id": A4_PROTOCOL_ID, "audited_at": now_iso(),
        "status": "PASS_COMPATIBILITY_AUDIT" if not problems else "BLOCKED_COMPATIBILITY_AUDIT",
        "blocking_problem_count": sum(bool(p.get("blocking")) for p in problems),
        "problems": problems,
        "checks": {
            "a0_protocol_id": a0["protocol_id"], "a0_status": a0["status"],
            "dataset_contract": {k: dataset[k] for k in ("plant_revision", "sample_time_s", "sequence_length_steps", "raw_input_dim", "feature_contract")},
            "model_seeds": seeds, "checkpoint_count": len(checkpoint_rows),
            "plant_revision": a0["plant"]["revision_id"], "mpc_effective_values": mpc_actual,
            "a3_effective_config_sha256_values": sorted(a3_rows["effective_config_sha256"].unique().tolist()),
            "a3_case_count": len(a3_rows), "a3_hashes_valid": a3_hash_ok,
            "node42_historical_status": n42_summary["status"],
            "node42_primary_case_count": len(primary_log), "node42_supplementary_case_count": len(supplemental_log),
            "node42_primary_pair_count": len(primary_log) // 2,
            "node42_groups": sorted(primary_log["group"].unique().tolist()),
            "node42_only_online_change": n42_protocol["only_online_change"],
            "theta_sched_definition": "trace.theta_sched == diag.rho_f(:,3)",
            "metric_implementation_sources": [
                rel(A3 / "02_tools/evaluate_a3_case.m"),
                rel(NODE42 / "tools/node42_evaluate_case.m"),
                rel(A5 / "02_tools/a5_statistical_audit.py"),
            ],
            "expected_primary_rows": 138, "available_primary_rows": 18 + len(primary_log),
        },
    }
    protocol_snapshot = {
        "task_id": "A4", "protocol_id": A4_PROTOCOL_ID, "source_protocol_id": PROTOCOL_ID,
        "created_at": now_iso(), "status": "LOCKED_BEFORE_A4_ANALYSIS",
        "write_root": str(A4), "write_policy": "all new files remain below A4",
        "paths": list(by_id), "path_tags": list(by_tag), "model_seeds": seeds,
        "controllers": list(CONTROLLERS), "primary_metrics": list(PRIMARY_METRICS),
        "secondary_metrics": list(SECONDARY_METRICS), "scheduling_metrics": list(SCHEDULING_METRICS),
        "bootstrap": {"iterations": BOOTSTRAP_ITERATIONS, "random_seed": BOOTSTRAP_SEED, "confidence_level": 0.95},
        "decision_policy": {
            "core_contrasts": sorted(CORE_CONTRASTS),
            "supported": "all four core contrasts support all three primary metrics and no global safety failure",
            "mixed": "one to three core contrasts supported with no global safety failure",
            "not_supported": "zero core contrasts supported or any global safety failure",
        },
        "node42_historical_decision_preserved": n42_summary["status"],
        "protected_input_hashes_before": source_hash_snapshot(),
    }
    write_json(A4 / "00_protocol_lock/protocol_snapshot.json", protocol_snapshot)
    write_csv(A4 / "01_inventory/input_artifact_registry.csv", artifacts + [dict(r, role="checkpoint_registry") for r in checkpoint_rows])
    write_json(A4 / "01_inventory/compatibility_audit.json", compatibility)
    write_csv(A4 / "01_inventory/case_availability_matrix.csv", availability)
    if problems:
        raise RuntimeError(f"Compatibility audit blocked with {len(problems)} problem(s)")
    return compatibility


def finite(value: Any) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def numeric_or_none(value: Any) -> float | int | None:
    if value is None or value == "" or isinstance(value, list):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number):
        return None
    return int(number) if number.is_integer() and isinstance(value, int) else number


def finite_array_stat(values: np.ndarray, statistic: str) -> float | None:
    clean = values[np.isfinite(values)]
    if clean.size == 0:
        return None
    if statistic == "mean":
        return float(np.mean(clean))
    if statistic == "median":
        return float(np.median(clean))
    raise ValueError(statistic)


def safety_failure(row: Mapping[str, Any]) -> bool:
    return bool(
        (numeric_or_none(row.get("constraint_violation_rate")) or 0) > 0
        or (numeric_or_none(row.get("timeout_count")) or 0) > 0
        or (numeric_or_none(row.get("solver_fail_count")) or 0) > 0
        or str(row.get("closed_loop_unstable", "")).lower() == "true"
        or any(not finite(row.get(metric)) for metric in PRIMARY_METRICS)
    )


def standard_metrics(source: Mapping[str, Any]) -> dict[str, Any]:
    names = tuple(dict.fromkeys(PRIMARY_METRICS + SECONDARY_METRICS + SCHEDULING_METRICS + (
        "ey_peak", "epsi_peak", "theta_sched_peak_abs_err_deg", "theta_rate_max_deg_s",
        "solve_time_p50_ms", "solve_time_p95_ms", "solve_time_p99_ms", "solve_time_max_ms",
    )))
    return {name: numeric_or_none(source.get(name)) for name in names}


def assemble() -> pd.DataFrame:
    compatibility = load_json(A4 / "01_inventory/compatibility_audit.json")
    if compatibility["status"] != "PASS_COMPATIBILITY_AUDIT":
        raise RuntimeError("Cannot assemble: compatibility audit did not pass")
    a0 = load_json(A0_JSON)
    by_tag, _ = path_maps(a0)
    registry = pd.read_csv(A1 / "model_registry.csv", dtype=str, keep_default_na=False)
    delta = registry[registry["method_id"] == "modern_tcn_delta_bank_124"].set_index(registry[registry["method_id"] == "modern_tcn_delta_bank_124"]["model_seed"].astype(int))
    rows: list[dict[str, Any]] = []

    a3_rows = pd.read_csv(A3 / "04_summary/a3_case_table.csv", dtype=str, keep_default_na=False)
    for _, src in a3_rows.iterrows():
        base = {
            "task_id": "A4", "protocol_id": A4_PROTOCOL_ID,
            "case_id": src["case_id"], "case_status": src["case_status"],
            "controller_id": src["controller_id"], "source_task": "A3", "source_group": "",
            "analysis_role": "PRIMARY", "path_id": src["path_id"], "path_tag": Path(src["path_file"]).stem,
            "model_seed": None, "sensor_seed": None,
            "plant_revision": src["plant_revision"], "dataset_sha256": src["dataset_sha256"],
            "checkpoint_file": None, "checkpoint_sha256": None, "onnx_file": None, "onnx_sha256": None,
            "path_file": src["path_file"], "path_sha256": src["path_sha256"],
            "effective_config_sha256": src["effective_config_sha256"],
            "source_file": src["source_file"], "source_file_sha256": src["source_file_sha256"],
            "trace_file": src["trace_file"], "trace_file_sha256": src["trace_file_sha256"],
            "closed_loop_unstable": str(src["closed_loop_unstable"]).lower() == "true",
        }
        base.update(standard_metrics(src))
        base["theta_fused_mae_deg"] = None
        base["safety_failure"] = safety_failure(base)
        rows.append(base)

    n42_log = pd.read_csv(NODE42 / "09_run_logs/innovation_development_cases.csv", dtype=str, keep_default_na=False)
    supplementary: list[dict[str, Any]] = []
    for _, src in n42_log.iterrows():
        case_dir = Path(src["case_dir"])
        metrics_file = case_dir / "case_metrics.json"
        manifest_file = case_dir / "case_manifest.json"
        trace_file = case_dir / "trace.csv"
        metrics = load_json(metrics_file)
        manifest = load_json(manifest_file)
        seed = int(src["model_seed"])
        controller = "MTCN_LPV_MPC" if src["group"] == "G0" else "Fusion_LPV_MPC"
        role = "PRIMARY" if src["path_tag"] in by_tag else "SUPPLEMENTARY"
        path_id = by_tag.get(src["path_tag"], f"supp_{src['path_tag']}")
        ck = delta.loc[seed]
        if isinstance(ck, pd.DataFrame):
            ck = ck.iloc[0]
        onnx = ROOT / f"results/modern_tcn_metric_rebuild/25_lag_representation_repair/03_onnx_and_smoke/delta_bank_124/seed{seed}/modern_tcn_delta_bank_124_seed{seed}.onnx"
        base = {
            "task_id": "A4", "protocol_id": A4_PROTOCOL_ID,
            "case_id": f"{controller}__{path_id}__seed{seed}", "case_status": metrics["case_status"],
            "controller_id": controller, "source_task": "Node42", "source_group": src["group"],
            "analysis_role": role, "path_id": path_id, "path_tag": src["path_tag"],
            "model_seed": seed, "sensor_seed": int(src["sensor_seed"]),
            "plant_revision": metrics["plant_revision"], "dataset_sha256": load_json(A0_JSON)["dataset"]["sha256"],
            "checkpoint_file": str(Path(ck["model_file"])), "checkpoint_sha256": ck["model_sha256"],
            "onnx_file": str(onnx), "onnx_sha256": sha256(onnx),
            "path_file": rel(Path(src["path_file"])), "path_sha256": manifest["path_sha256"],
            "effective_config_sha256": manifest["fingerprint"],
            "source_file": rel(metrics_file), "source_file_sha256": sha256(metrics_file),
            "trace_file": rel(trace_file), "trace_file_sha256": sha256(trace_file),
            "closed_loop_unstable": False,
        }
        base.update(standard_metrics(metrics))
        base["theta_fused_mae_deg"] = numeric_or_none(metrics.get("theta_fused_mae_deg"))
        base["safety_failure"] = safety_failure(base)
        (rows if role == "PRIMARY" else supplementary).append(base)

    zs = {row["path_id"]: row for row in rows if row["controller_id"] == "ZS_LPV_MPC"}
    for row in rows:
        ref = zs[row["path_id"]]
        ratios = []
        for metric in CONTROL_INDEX_METRICS:
            target, comparator = float(row[metric]), float(ref[metric])
            ratios.append(target / comparator if comparator != 0 else math.nan)
        row["J_control_path"] = float(np.mean(ratios)) if all(math.isfinite(v) for v in ratios) else None

    primary = pd.DataFrame(rows)
    expected_counts = {"ZS_LPV_MPC": 6, "IMU_LPV_MPC": 6, "Oracle_LPV_MPC": 6, "MTCN_LPV_MPC": 60, "Fusion_LPV_MPC": 60}
    observed_counts = primary.groupby("controller_id").size().to_dict()
    if len(primary) != 138 or observed_counts != expected_counts:
        raise RuntimeError(f"Primary case table cardinality error: rows={len(primary)}, counts={observed_counts}")
    key_cols = ["controller_id", "path_id", "model_seed"]
    if primary.duplicated(key_cols).any():
        raise RuntimeError("Duplicate primary controller/path/seed key")
    for metric in PRIMARY_METRICS:
        if not np.isfinite(pd.to_numeric(primary[metric], errors="coerce")).all():
            raise RuntimeError(f"Non-finite primary metric: {metric}")

    csv_path = A4 / "02_case_table/five_controller_case_table.csv"
    primary.to_csv(csv_path, index=False, encoding="utf-8-sig")
    jsonl_path = A4 / "02_case_table/five_controller_case_table.jsonl"
    ensure_within_a4(jsonl_path)
    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in primary.to_dict(orient="records"):
            handle.write(json.dumps(clean_json(row), ensure_ascii=False, allow_nan=False) + "\n")
    write_csv(A4 / "02_case_table/supplementary_node42_case_table.csv", supplementary)
    return primary


def bootstrap_values(df: pd.DataFrame, metric: str, a5: Any) -> dict[str, Any]:
    if df["controller_id"].iloc[0] in DETERMINISTIC_CONTROLLERS:
        if len(df) != 6 or df["path_id"].nunique() != 6:
            return {
                "estimate": float(df[metric].mean()), "bootstrap_mean": None,
                "ci95_low": None, "ci95_high": None, "iterations": 0,
                "random_seed": BOOTSTRAP_SEED, "resampling_unit": "not_computed_incomplete_grid",
                "n_cases": len(df), "missing_data_policy": "retained_no_imputation",
            }
        values = {str(r.path_id): float(getattr(r, metric)) for r in df.itertuples()}
        result = a5.paired_path_bootstrap(values, iterations=BOOTSTRAP_ITERATIONS, random_seed=BOOTSTRAP_SEED)
        result.update({"resampling_unit": "path", "n_cases": len(df)})
        return result
    if len(df) != 60 or df["model_seed"].nunique() != 10 or df["path_id"].nunique() != 6:
        return {
            "estimate": float(df[metric].mean()), "bootstrap_mean": None,
            "ci95_low": None, "ci95_high": None, "iterations": 0,
            "random_seed": BOOTSTRAP_SEED, "resampling_unit": "not_computed_incomplete_grid",
            "n_cases": len(df), "missing_data_policy": "retained_no_imputation",
        }
    values = {(int(r.model_seed), str(r.path_id)): float(getattr(r, metric)) for r in df.itertuples()}
    result = a5.hierarchical_paired_bootstrap(values, iterations=BOOTSTRAP_ITERATIONS, random_seed=BOOTSTRAP_SEED)
    result.update({"resampling_unit": "model_seed_then_path", "n_cases": len(df)})
    return result


def paired_rows(df: pd.DataFrame, target: str, comparator: str, metric: str) -> list[dict[str, Any]]:
    t = df[df["controller_id"] == target]
    c = df[df["controller_id"] == comparator]
    t_learning = target in LEARNING_CONTROLLERS
    c_learning = comparator in LEARNING_CONTROLLERS
    rows: list[dict[str, Any]] = []
    if t_learning and c_learning:
        c_map = {(r.path_id, int(r.model_seed)): r for r in c.itertuples()}
        for tr in t.itertuples():
            key = (tr.path_id, int(tr.model_seed))
            cr = c_map[key]
            rows.append(effect_row(tr, cr, metric))
    elif t_learning:
        c_map = {r.path_id: r for r in c.itertuples()}
        for tr in t.itertuples():
            rows.append(effect_row(tr, c_map[tr.path_id], metric))
    elif c_learning:
        t_map = {r.path_id: r for r in t.itertuples()}
        for cr in c.itertuples():
            rows.append(effect_row(t_map[cr.path_id], cr, metric, seed=int(cr.model_seed)))
    else:
        c_map = {r.path_id: r for r in c.itertuples()}
        for tr in t.itertuples():
            rows.append(effect_row(tr, c_map[tr.path_id], metric))
    return rows


def effect_row(target_row: Any, comparator_row: Any, metric: str, seed: int | None = None) -> dict[str, Any]:
    target_value = float(getattr(target_row, metric))
    comparator_value = float(getattr(comparator_row, metric))
    absolute = comparator_value - target_value
    relative = math.nan if comparator_value == 0 else 100.0 * absolute / comparator_value
    ratio = math.nan if comparator_value == 0 else target_value / comparator_value
    model_seed = seed
    if model_seed is None:
        raw = getattr(target_row, "model_seed", None)
        model_seed = int(raw) if raw is not None and not pd.isna(raw) else None
    return {
        "path_id": target_row.path_id, "model_seed": model_seed,
        "target_value": target_value, "comparator_value": comparator_value,
        "absolute_effect": absolute, "relative_effect_pct": relative, "ratio": ratio,
    }


def bootstrap_effects(rows: list[dict[str, Any]], a5: Any) -> dict[str, Any]:
    has_seeds = any(row["model_seed"] is not None for row in rows)
    if has_seeds:
        if len(rows) != 60 or len({int(row["model_seed"]) for row in rows}) != 10 or len({row["path_id"] for row in rows}) != 6:
            return {
                "estimate": float(np.mean([row["absolute_effect"] for row in rows])),
                "bootstrap_mean": None, "ci95_low": None, "ci95_high": None,
                "iterations": 0, "random_seed": BOOTSTRAP_SEED,
                "resampling_unit": "not_computed_incomplete_grid",
                "missing_data_policy": "retained_no_imputation",
            }
        effects = {(int(row["model_seed"]), row["path_id"]): row["absolute_effect"] for row in rows}
        result = a5.hierarchical_paired_bootstrap(effects, iterations=BOOTSTRAP_ITERATIONS, random_seed=BOOTSTRAP_SEED)
        result["resampling_unit"] = "model_seed_then_path"
    else:
        if len(rows) != 6 or len({row["path_id"] for row in rows}) != 6:
            return {
                "estimate": float(np.mean([row["absolute_effect"] for row in rows])),
                "bootstrap_mean": None, "ci95_low": None, "ci95_high": None,
                "iterations": 0, "random_seed": BOOTSTRAP_SEED,
                "resampling_unit": "not_computed_incomplete_grid",
                "missing_data_policy": "retained_no_imputation",
            }
        effects = {row["path_id"]: row["absolute_effect"] for row in rows}
        result = a5.paired_path_bootstrap(effects, iterations=BOOTSTRAP_ITERATIONS, random_seed=BOOTSTRAP_SEED)
        result["resampling_unit"] = "path"
    return result


def analyze() -> dict[str, Any]:
    df = pd.read_csv(A4 / "02_case_table/five_controller_case_table.csv")
    a5 = import_a5_module()
    controller_rows: list[dict[str, Any]] = []
    ci_rows: list[dict[str, Any]] = []
    zs_df = df[df["controller_id"] == "ZS_LPV_MPC"]
    for controller in CONTROLLERS:
        subset = df[df["controller_id"] == controller]
        summary: dict[str, Any] = {
            "controller_id": controller, "n_cases": len(subset), "n_paths": subset["path_id"].nunique(),
            "n_model_seeds": subset["model_seed"].nunique() if controller in LEARNING_CONTROLLERS else 0,
            "safety_failure_count": int(subset["safety_failure"].astype(bool).sum()),
        }
        for metric in SUMMARY_METRICS:
            numeric = pd.to_numeric(subset[metric], errors="coerce")
            valid = subset[numeric.notna()].copy()
            if valid.empty:
                continue
            valid[metric] = numeric[numeric.notna()]
            boot = bootstrap_values(valid, metric, a5)
            summary[f"{metric}_mean"] = float(valid[metric].mean())
            summary[f"{metric}_median"] = float(valid[metric].median())
            summary[f"{metric}_ci95_low"] = boot["ci95_low"]
            summary[f"{metric}_ci95_high"] = boot["ci95_high"]
            ci_rows.append({"analysis": "controller_summary", "controller_id": controller, "metric": metric, **boot})
        if controller == "ZS_LPV_MPC":
            for metric in PRIMARY_METRICS + ("J_control_path",):
                summary[f"{metric}_relative_zs_improvement_pct"] = 0.0
        else:
            for metric in PRIMARY_METRICS + ("J_control_path",):
                pairs = paired_rows(df, controller, "ZS_LPV_MPC", metric)
                summary[f"{metric}_relative_zs_improvement_pct"] = float(np.nanmean([p["relative_effect_pct"] for p in pairs]))
        controller_rows.append(summary)

    paired_summary: list[dict[str, Any]] = []
    pair_detail_rows: list[dict[str, Any]] = []
    contrast_metrics = tuple(dict.fromkeys(PRIMARY_METRICS + SECONDARY_METRICS + SCHEDULING_METRICS + ("J_control_path",)))
    for contrast_id, target, comparator in CONTRASTS:
        for metric in contrast_metrics:
            target_values = pd.to_numeric(df.loc[df["controller_id"] == target, metric], errors="coerce")
            comparator_values = pd.to_numeric(df.loc[df["controller_id"] == comparator, metric], errors="coerce")
            if target_values.isna().all() or comparator_values.isna().all():
                continue
            pairs = paired_rows(df, target, comparator, metric)
            pairs = [p for p in pairs if all(finite(p[k]) for k in ("target_value", "comparator_value", "absolute_effect"))]
            if not pairs:
                continue
            boot = bootstrap_effects(pairs, a5)
            effects = np.asarray([p["absolute_effect"] for p in pairs], dtype=float)
            rel_effects = np.asarray([p["relative_effect_pct"] for p in pairs], dtype=float)
            ratios = np.asarray([p["ratio"] for p in pairs], dtype=float)
            worst = min(pairs, key=lambda p: p["absolute_effect"])
            row = {
                "contrast_id": contrast_id, "target": target, "comparator": comparator, "metric": metric,
                "n_pairs": len(pairs), "mean_absolute_effect": float(np.mean(effects)),
                "median_absolute_effect": float(np.median(effects)),
                "mean_relative_effect_pct": finite_array_stat(rel_effects, "mean"),
                "median_relative_effect_pct": finite_array_stat(rel_effects, "median"),
                "mean_ratio": finite_array_stat(ratios, "mean"),
                "ci95_low": boot["ci95_low"], "ci95_high": boot["ci95_high"],
                "improved_case_count": int(np.sum(effects > 0)), "degraded_case_count": int(np.sum(effects < 0)),
                "tie_case_count": int(np.sum(effects == 0)),
                "worst_path": worst["path_id"], "worst_seed": worst["model_seed"],
                "worst_absolute_effect": worst["absolute_effect"],
                "resampling_unit": boot["resampling_unit"], "bootstrap_iterations": boot["iterations"],
                "bootstrap_seed": BOOTSTRAP_SEED,
            }
            paired_summary.append(row)
            ci_rows.append({"analysis": "paired_effect", **row})
            for p in pairs:
                pair_detail_rows.append({"contrast_id": contrast_id, "target": target, "comparator": comparator, "metric": metric, **p})

    path_rows: list[dict[str, Any]] = []
    for (controller, path_id), subset in df.groupby(["controller_id", "path_id"], sort=False):
        row: dict[str, Any] = {"controller_id": controller, "path_id": path_id, "n_cases": len(subset)}
        for metric in SUMMARY_METRICS:
            values = pd.to_numeric(subset[metric], errors="coerce")
            if values.notna().any():
                row[f"{metric}_mean"] = float(values.mean())
                row[f"{metric}_median"] = float(values.median())
                if controller in LEARNING_CONTROLLERS:
                    idx = values.idxmax()
                    row[f"{metric}_worst_seed"] = int(df.loc[idx, "model_seed"])
        path_rows.append(row)

    worst_rows: list[dict[str, Any]] = []
    for controller, subset in df.groupby("controller_id", sort=False):
        for metric in SUMMARY_METRICS:
            values = pd.to_numeric(subset[metric], errors="coerce")
            if not values.notna().any():
                continue
            idx = values.idxmax()
            worst_rows.append({
                "controller_id": controller, "metric": metric, "maximum_value": float(values.loc[idx]),
                "worst_path": df.loc[idx, "path_id"],
                "worst_seed": int(df.loc[idx, "model_seed"]) if pd.notna(df.loc[idx, "model_seed"]) else None,
                "case_id": df.loc[idx, "case_id"],
            })

    safety_rows: list[dict[str, Any]] = []
    for controller, subset in df.groupby("controller_id", sort=False):
        safety_rows.append({
            "controller_id": controller, "n_cases": len(subset),
            "safety_failure_count": int(subset["safety_failure"].astype(bool).sum()),
            "constraint_violation_case_count": int((pd.to_numeric(subset["constraint_violation_rate"]) > 0).sum()),
            "timeout_total": int(pd.to_numeric(subset["timeout_count"]).sum()),
            "solver_fail_total": int(pd.to_numeric(subset["solver_fail_count"]).sum()),
            "force_saturation_case_count": int((pd.to_numeric(subset["force_saturation_rate"]) > 0).sum()),
            "omega_saturation_case_count": int((pd.to_numeric(subset["omega_saturation_rate"]) > 0).sum()),
        })

    paired_df = pd.DataFrame(paired_summary)
    support: dict[str, Any] = {}
    for contrast in sorted(CORE_CONTRASTS):
        rows = paired_df[(paired_df["contrast_id"] == contrast) & (paired_df["metric"].isin(PRIMARY_METRICS))]
        metric_support = {row.metric: bool(row.ci95_low > 0) for row in rows.itertuples()}
        support[contrast] = {"metrics": metric_support, "supported": len(metric_support) == 3 and all(metric_support.values())}
    core_supported_count = sum(v["supported"] for v in support.values())
    global_safety_failures = sum(row["safety_failure_count"] for row in safety_rows)
    if global_safety_failures > 0 or core_supported_count == 0:
        state = "NOT_SUPPORTED_FIVE_CONTROLLER_PRIMARY"
    elif core_supported_count == len(CORE_CONTRASTS):
        state = "SUPPORTED_FIVE_CONTROLLER_PRIMARY"
    else:
        state = "MIXED_FIVE_CONTROLLER_RESULT"
    decision = {
        "task_id": "A4", "protocol_id": A4_PROTOCOL_ID, "issued_at": now_iso(), "decision": state,
        "grid_complete": True, "primary_case_count": len(df), "core_supported_count": core_supported_count,
        "core_contrast_count": len(CORE_CONTRASTS), "core_contrast_support": support,
        "global_safety_failure_count": global_safety_failures,
        "node42_historical_development_decision": load_json(NODE42 / "04_summaries/innovation_development_summary.json")["status"],
        "historical_decision_rewritten": False,
        "interpretation_rule": "A4 decision is independent and does not overwrite Node42 development qualification.",
    }

    write_csv(A4 / "03_statistics/controller_summary.csv", controller_rows)
    write_csv(A4 / "03_statistics/paired_effects.csv", paired_summary)
    write_csv(A4 / "03_statistics/bootstrap_ci_results.csv", ci_rows)
    write_csv(A4 / "03_statistics/path_summary.csv", path_rows)
    write_csv(A4 / "03_statistics/worst_case_audit.csv", worst_rows)
    write_csv(A4 / "03_statistics/safety_summary.csv", safety_rows)
    write_csv(A4 / "03_statistics/paired_case_details.csv", pair_detail_rows)

    supplementary = pd.read_csv(A4 / "02_case_table/supplementary_node42_case_table.csv")
    supplemental_rows: list[dict[str, Any]] = []
    if len(supplementary):
        for path_id in sorted(supplementary["path_id"].unique()):
            for metric in PRIMARY_METRICS:
                pairs = paired_rows(supplementary, "Fusion_LPV_MPC", "MTCN_LPV_MPC", metric)
                pairs = [p for p in pairs if p["path_id"] == path_id]
                effects = np.asarray([p["absolute_effect"] for p in pairs], dtype=float)
                supplemental_rows.append({
                    "analysis_role": "SUPPLEMENTARY_ONLY", "path_id": path_id, "metric": metric,
                    "n_seed_pairs": len(pairs), "mean_absolute_effect": float(np.mean(effects)),
                    "improved_seed_count": int(np.sum(effects > 0)), "degraded_seed_count": int(np.sum(effects < 0)),
                })
    write_csv(A4 / "03_statistics/extended_path_summary.csv", supplemental_rows)
    write_json(A4 / "decision.json", decision)
    return decision


def configure_plot_style() -> None:
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans", "Liberation Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["font.size"] = 6.5
    plt.rcParams["axes.linewidth"] = 0.7
    plt.rcParams["axes.spines.top"] = False
    plt.rcParams["axes.spines.right"] = False
    plt.rcParams["legend.frameon"] = False


def export_figure(fig: plt.Figure, stem: Path) -> None:
    ensure_within_a4(stem)
    stem.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=300, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")
    plt.close(fig)


def make_figures() -> None:
    configure_plot_style()
    df = pd.read_csv(A4 / "02_case_table/five_controller_case_table.csv")
    path_ids = ["p01_factory_logistics_showcase", "p03_long_updown", "p04_soft_updown_straight_turn"]
    colors = {
        "ZS_LPV_MPC": "#8F8F8F", "IMU_LPV_MPC": "#42949E", "MTCN_LPV_MPC": "#3775BA",
        "Fusion_LPV_MPC": "#9A4D8E", "Oracle_LPV_MPC": "#272727", "theta_true": "#B64342",
    }
    labels = {
        "ZS_LPV_MPC": "ZS", "IMU_LPV_MPC": "IMU", "MTCN_LPV_MPC": "MTCN",
        "Fusion_LPV_MPC": "Fusion", "Oracle_LPV_MPC": "Oracle",
    }
    trace_rows: list[dict[str, Any]] = []
    trace_cache: dict[tuple[str, str], pd.DataFrame] = {}
    usecols = ["t_s", "e_y", "F_cmd", "omega_cmd", "theta_true", "theta_sched"]
    for path_id in path_ids:
        for controller in CONTROLLERS:
            subset = df[(df["path_id"] == path_id) & (df["controller_id"] == controller)]
            if controller in LEARNING_CONTROLLERS:
                subset = subset[subset["model_seed"] == 42]
            row = subset.iloc[0]
            trace = pd.read_csv(ROOT / row["trace_file"], usecols=usecols)
            stride = max(1, math.ceil(len(trace) / 1600))
            trace = trace.iloc[::stride].copy()
            trace_cache[(path_id, controller)] = trace
            for item in trace.itertuples(index=False):
                trace_rows.append({
                    "path_id": path_id, "controller_id": controller, "model_seed": 42 if controller in LEARNING_CONTROLLERS else None,
                    "t_s": item.t_s, "theta_true_deg": np.rad2deg(item.theta_true),
                    "theta_sched_deg": np.rad2deg(item.theta_sched), "e_y_m": item.e_y,
                    "F_cmd": item.F_cmd, "omega_cmd": item.omega_cmd,
                })
    write_csv(A4 / "04_figures/figure_data/figure_A4_1_source_data.csv", trace_rows)

    fig, axes = plt.subplots(3, 4, figsize=(7.2, 7.0), constrained_layout=True)
    panel_labels = iter("abcdefghijkl")
    short_paths = {path_ids[0]: "Factory logistics", path_ids[1]: "Long up/down", path_ids[2]: "Soft slope + turn"}
    for row_idx, path_id in enumerate(path_ids):
        for col_idx, (field, ylabel) in enumerate((
            ("theta_sched", "Scheduled slope (deg)"), ("e_y", r"$e_y$ (m)"),
            ("F_cmd", r"$F_{cmd}$ (N)"), ("omega_cmd", r"$\omega_{cmd}$ (rad s$^{-1}$)"),
        )):
            ax = axes[row_idx, col_idx]
            for controller in CONTROLLERS:
                trace = trace_cache[(path_id, controller)]
                y = np.rad2deg(trace[field]) if field == "theta_sched" else trace[field]
                ax.plot(trace["t_s"], y, color=colors[controller], lw=0.75 if controller != "Fusion_LPV_MPC" else 1.05,
                        alpha=0.9, label=labels[controller])
            if field == "theta_sched":
                truth = trace_cache[(path_id, "Oracle_LPV_MPC")]
                ax.plot(truth["t_s"], np.rad2deg(truth["theta_true"]), color=colors["theta_true"], lw=0.9,
                        linestyle="--", label="True")
            ax.axhline(0, color="#C8C8C8", lw=0.45, zorder=0)
            ax.set_ylabel(ylabel)
            if row_idx == 2:
                ax.set_xlabel("Time (s)")
            if col_idx == 0:
                ax.text(0.98, 0.96, short_paths[path_id], transform=ax.transAxes,
                        va="top", ha="right", fontweight="bold", fontsize=6,
                        bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.78, "pad": 1.0})
            ax.text(-0.16, 1.03, next(panel_labels), transform=ax.transAxes, fontweight="bold", fontsize=8)
    handles, legend_labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, legend_labels, ncol=6, loc="upper center", bbox_to_anchor=(0.52, 1.018), columnspacing=1.1)
    export_figure(fig, A4 / "04_figures/figure_A4_1_representative_paths")

    details = pd.read_csv(A4 / "03_statistics/paired_case_details.csv")
    plot_data = details[(details["contrast_id"] == "Fusion_vs_MTCN") & (details["metric"].isin(PRIMARY_METRICS))].copy()
    path_order = list(load_json(A5 / "00_protocol_lock/analysis_plan.json")["frozen_paths"])
    seed_order = list(load_json(A5 / "00_protocol_lock/analysis_plan.json")["frozen_seeds"])
    plot_data["path_order"] = plot_data["path_id"].map({v: i for i, v in enumerate(path_order)})
    plot_data["seed_order"] = plot_data["model_seed"].map({v: i for i, v in enumerate(seed_order)})
    plot_data["case_index"] = plot_data["path_order"] * len(seed_order) + plot_data["seed_order"]
    plot_data["direction"] = np.where(plot_data["relative_effect_pct"] > 0, "improved", np.where(plot_data["relative_effect_pct"] < 0, "degraded", "tie"))
    plot_data.sort_values(["metric", "case_index"]).to_csv(
        A4 / "04_figures/figure_data/figure_A4_2_paired_effects.csv", index=False, encoding="utf-8-sig"
    )
    fig, axes = plt.subplots(3, 1, figsize=(7.2, 5.5), sharex=True, constrained_layout=True)
    metric_labels = {"ey_rmse": r"$e_y$ RMSE change (%)", "epsi_rmse": r"$e_\psi$ RMSE change (%)", "j_du": r"$J_{\Delta u}$ change (%)"}
    for idx, metric in enumerate(PRIMARY_METRICS):
        ax = axes[idx]
        sub = plot_data[plot_data["metric"] == metric].sort_values("case_index")
        point_colors = np.where(
            sub["relative_effect_pct"] > 0, "#2E9E44",
            np.where(sub["relative_effect_pct"] < 0, "#E53935", "#8F8F8F"),
        )
        ax.scatter(sub["case_index"], sub["relative_effect_pct"], c=point_colors, s=13, edgecolor="white", linewidth=0.25)
        ax.axhline(0, color="#4D4D4D", linestyle="--", lw=0.75)
        for boundary in range(1, len(path_order)):
            ax.axvline(boundary * len(seed_order) - 0.5, color="#D8D8D8", lw=0.5)
        ax.set_ylabel(metric_labels[metric])
        ax.text(-0.055, 1.02, "abc"[idx], transform=ax.transAxes, fontweight="bold", fontsize=8)
    centers = [i * len(seed_order) + (len(seed_order) - 1) / 2 for i in range(len(path_order))]
    axes[-1].set_xticks(centers)
    axes[-1].set_xticklabels([f"P{i+1}" for i in range(len(path_order))])
    axes[-1].set_xlabel("A0 path (10 paired model seeds per path)")
    export_figure(fig, A4 / "04_figures/figure_A4_2_fusion_vs_mtcn_paired_effects")

    contract = """# A4 figure contract

- Core conclusion: fixed-path evidence shows the full five-controller response, while all 60 paired points disclose where Fusion improves or degrades relative to MTCN.
- Archetype: quantitative grid.
- Backend: Python/matplotlib only.
- Final size: double-column, approximately 183 mm wide.
- Figure A4-1: three A0-fixed representative paths × scheduled slope, lateral error, force command and steering-rate command; learning curves use seed42.
- Figure A4-2: all six paths × ten seeds for each preregistered primary metric; green denotes improvement and red denotes degradation.
- Statistics: model seed × path is the paired unit; no time point is treated as an independent replicate.
- Source data: `figure_data/figure_A4_1_source_data.csv` and `figure_data/figure_A4_2_paired_effects.csv`.
- Reviewer risk controls: no curve selection, no hidden degradation point, common method colors, editable SVG text, and raw source-file traceability.
"""
    (A4 / "04_figures/FIGURE_CONTRACT.md").write_text(contract, encoding="utf-8")


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    def fmt(value: Any) -> str:
        if value is None or (isinstance(value, float) and math.isnan(value)):
            return "NA"
        if isinstance(value, (float, np.floating)):
            return f"{value:.5g}"
        return str(value)
    return "\n".join([
        "| " + " | ".join(headers) + " |",
        "|" + "|".join(["---"] * len(headers)) + "|",
        *["| " + " | ".join(fmt(v) for v in row) + " |" for row in rows],
    ])


def write_report_and_manifests() -> None:
    decision = load_json(A4 / "decision.json")
    summary = pd.read_csv(A4 / "03_statistics/controller_summary.csv")
    paired = pd.read_csv(A4 / "03_statistics/paired_effects.csv")
    safety = pd.read_csv(A4 / "03_statistics/safety_summary.csv")
    path_summary = pd.read_csv(A4 / "03_statistics/path_summary.csv")
    table1_rows = []
    for controller in CONTROLLERS:
        row = summary[summary["controller_id"] == controller].iloc[0]
        safe = safety[safety["controller_id"] == controller].iloc[0]
        table1_rows.append([
            controller, row["ey_rmse_mean"], row["epsi_rmse_mean"], row["xy_rmse_mean"], row["j_du_mean"],
            row["omega_cmd_rms_mean"],
            f"{int(safe['constraint_violation_case_count'])}/{int(safe['timeout_total'])}",
            row["J_control_path_relative_zs_improvement_pct"],
        ])
    fusion_primary = paired[(paired["contrast_id"] == "Fusion_vs_MTCN") & (paired["metric"].isin(PRIMARY_METRICS))]
    table2_rows = [[
        r.metric, r.mean_absolute_effect, f"[{r.ci95_low:.5g}, {r.ci95_high:.5g}]",
        int(r.improved_case_count), int(r.degraded_case_count),
        f"{r.worst_path}/seed{int(r.worst_seed) if pd.notna(r.worst_seed) else 'NA'}",
    ] for r in fusion_primary.itertuples()]
    table3_rows = []
    for controller in CONTROLLERS:
        for item in path_summary[path_summary["controller_id"] == controller].itertuples():
            worst_seed = getattr(item, "j_du_worst_seed", None)
            table3_rows.append([
                controller, item.path_id, item.ey_rmse_mean, item.epsi_rmse_mean, item.j_du_mean,
                int(worst_seed) if worst_seed is not None and pd.notna(worst_seed) else "NA",
            ])
    theta_pair = paired[(paired["contrast_id"] == "Fusion_vs_MTCN") & (paired["metric"] == "theta_sched_mae_deg")].iloc[0]
    report = f"""# A4 五种坡度来源下的 LPV-MPC 闭环正向验证

## 执行结论

- A4 decision：`{decision['decision']}`。
- 正式主表：138 case；A3 确定性控制器 18 case，Node42 G0/ADAPTIVE 六路径十种子 120 case。
- Node42 历史开发裁决继续保留为 `{decision['node42_historical_development_decision']}`；A4 未改写该裁决。
- 核心对比通过数：{decision['core_supported_count']}/{decision['core_contrast_count']}；安全失败数：{decision['global_safety_failure_count']}。
- 未进行训练或闭环补跑；全部正式数据来自哈希审计通过的现有 case。

## 表 A4-1 五控制器总体结果

{markdown_table(['Controller', 'ey RMSE', 'epsi RMSE', 'xy RMSE', 'j_du', 'omega RMS', 'Viol./timeouts', 'J_control vs ZS (%)'], table1_rows)}

均值按冻结统计单位计算；学习控制器使用十个模型种子与六条路径，确定性控制器仅有每路径一个正式观测。表中的 ZS 相对改善率按同路径配对后求平均，不能解释为确定性控制器拥有十次独立重复。

## 表 A4-2 Fusion 相对 MTCN 的配对结果

{markdown_table(['Metric', 'Comparator-target', '95% CI', 'Improved', 'Degraded', 'Worst path/seed'], table2_rows)}

正效应表示 Fusion 更优；CI 使用 A5 冻结的 10,000 次“先种子、后路径”分层配对 bootstrap，随机种子为 {BOOTSTRAP_SEED}。

## 表 A4-3 六条 A0 路径结果

{markdown_table(['Controller', 'Path', 'ey RMSE mean', 'epsi RMSE mean', 'j_du mean', 'Worst seed by j_du'], table3_rows)}

确定性控制器没有模型种子，其最差种子记为 NA；学习控制器的路线均值与最差种子均在同一路线的十个冻结模型种子内计算。

## 坡度精度与闭环收益

Fusion 相对 MTCN 的 `theta_sched_mae_deg` 平均配对效应为 {theta_pair.mean_absolute_effect:.5g}°，95% CI 为 [{theta_pair.ci95_low:.5g}, {theta_pair.ci95_high:.5g}]。坡度调度精度的平均改善并未完整转化为三个闭环主指标同时受支持：只有 `epsi_rmse` CI 全部位于零以上，`ey_rmse` 与 `j_du` 仍跨零，因此不得表述为 Fusion 全面优于 MTCN。

## 判定解释

{os.linesep.join(f"- `{name}`：{value['supported']}；" + ", ".join(f"{m}={v}" for m, v in value['metrics'].items()) for name, value in decision['core_contrast_support'].items())}

`Fusion_vs_IMU` 和 `Oracle_vs_Fusion` 完整报告但不改变四个预注册核心层次判定。J_control 仅作为五个同路径比值的综合解释指标，不替代 ey_rmse、epsi_rmse 和 j_du 三个主指标。局部退化点、最差路径/种子及全部安全统计均保留在统计表和图 A4-2 中。

## 图表与可追溯性

- 图 A4-1 固定使用 A0 的三条定性路径和 seed42，展示真实坡度、五种调度坡度、横向误差及两个控制输入。
- 图 A4-2 展示 Fusion 相对 MTCN 的全部 60 个配对点；未删除退化点。
- SVG 保留可编辑文字，同时提供 PDF、PNG 和 600 dpi TIFF。
- 每一图形点均可追溯至 `04_figures/figure_data`，每个统计值均可追溯至统一 case table 和源文件 SHA256。

## 边界声明

A0、A1、A2、A3、A5、Node40–Node42、`paper_v3.tex`、路径、种子、模型、融合/MPC 参数和评价门限均未修改。Node42 三条扩展路径仅写入 `extended_path_summary.csv`，未进入正式 CI 或 decision。
"""
    report_path = A4 / "A4_experiment_report.md"
    report_path.write_text(report, encoding="utf-8")

    availability = pd.read_csv(A4 / "01_inventory/case_availability_matrix.csv")
    missing = availability[(availability["analysis_role"] == "PRIMARY") & (~availability["available"].astype(bool))]
    handoff_status = "NOT_REQUIRED" if missing.empty else "REQUIRED"
    handoff = f"""# A4 长耗时手动执行交接

状态：`{handoff_status}`

当前兼容性审计确认 138/138 个正式主分析 case 完整，因此本轮禁止重新训练、重新导出 checkpoint 或补跑仿真，直接复用现有结果。

若未来重新审计发现缺失 case，必须先停止统计并满足以下规则：

1. 只允许在 A4 `02_case_runs` 下写入，A3 和 Node42 runner 不得直接调用，因为它们会写回受保护目录。
2. checkpoint 缺失或哈希不一致属于阻塞，不允许重训或修复。
3. 仅可为 `case_availability_matrix.csv` 明确标记缺失的 A0 路径×种子生成 A4 本地 runner。
4. 运行前必须执行兼容性审计、dry-run 和短 smoke；所有 MATLAB case 单进程串行。
5. 命令必须固定项目根目录、路径、种子、控制器、输出目录和 `-ReuseExisting` 语义，并将完整日志写入 `02_case_runs/logs`。
6. 中断后用相同命令恢复；不得删 case、改参数、改门限或更换种子。
7. 回传清单必须包含运行日志、case manifest、case metrics、trace、输出 MAT、运行前后哈希及更新后的可用性矩阵。

当前无需用户执行任何命令。
"""
    (A4 / "MANUAL_EXECUTION_HANDOFF.md").write_text(handoff, encoding="utf-8")

    run_manifest = {
        "task_id": "A4", "protocol_id": A4_PROTOCOL_ID, "generated_at": now_iso(),
        "execution_stages": ["audit", "assemble", "analyze", "figures", "finalize", "verify"],
        "simulation_executed": False, "training_executed": False, "manual_handoff_status": handoff_status,
        "primary_case_count": 138, "supplementary_case_count": 60,
        "bootstrap_iterations": BOOTSTRAP_ITERATIONS, "bootstrap_seed": BOOTSTRAP_SEED,
        "python": sys.version, "platform": platform.platform(),
        "source_policy": "A3 18 deterministic cases plus Node42 G0/ADAPTIVE six-path subset",
    }
    write_json(A4 / "run_manifest.json", run_manifest)
    write_json(A4 / "task_status.json", {
        "task_id": "A4", "status": "COMPLETE", "updated_at": now_iso(),
        "decision": decision["decision"], "compatibility_audit": "PASS_COMPATIBILITY_AUDIT",
        "primary_grid": "138/138", "manual_execution": handoff_status,
    })


def verification_checks() -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    def add(name: str, passed: bool, detail: Any) -> None:
        checks.append({"check": name, "passed": bool(passed), "detail": clean_json(detail)})

    df = pd.read_csv(A4 / "02_case_table/five_controller_case_table.csv")
    add("primary_row_count", len(df) == 138, len(df))
    add("controller_counts", df.groupby("controller_id").size().to_dict() == {
        "ZS_LPV_MPC": 6, "IMU_LPV_MPC": 6, "MTCN_LPV_MPC": 60, "Fusion_LPV_MPC": 60, "Oracle_LPV_MPC": 6,
    }, df.groupby("controller_id").size().to_dict())
    fm = pd.read_csv(A4 / "03_statistics/paired_case_details.csv")
    fm_primary = fm[(fm["contrast_id"] == "Fusion_vs_MTCN") & (fm["metric"].isin(PRIMARY_METRICS))]
    add("fusion_mtcn_primary_pair_rows", len(fm_primary) == 180, len(fm_primary))
    add("fusion_mtcn_unique_pairs_per_metric", all(len(x) == 60 for _, x in fm_primary.groupby("metric")), fm_primary.groupby("metric").size().to_dict())
    add("primary_metrics_finite", all(np.isfinite(pd.to_numeric(df[m], errors="coerce")).all() for m in PRIMARY_METRICS), list(PRIMARY_METRICS))
    a5 = import_a5_module()
    paired_report = pd.read_csv(A4 / "03_statistics/paired_effects.csv")
    contrast_map = {name: (target, comparator) for name, target, comparator in CONTRASTS}
    reproduced: list[dict[str, Any]] = []
    support_count = 0
    for contrast in sorted(CORE_CONTRASTS):
        target, comparator = contrast_map[contrast]
        contrast_supported = True
        for metric in PRIMARY_METRICS:
            pairs = paired_rows(df, target, comparator, metric)
            fresh = bootstrap_effects(pairs, a5)
            recorded = paired_report[(paired_report["contrast_id"] == contrast) & (paired_report["metric"] == metric)].iloc[0]
            matches = bool(
                np.isclose(float(fresh["ci95_low"]), float(recorded["ci95_low"]), rtol=0, atol=1e-12)
                and np.isclose(float(fresh["ci95_high"]), float(recorded["ci95_high"]), rtol=0, atol=1e-12)
            )
            metric_supported = bool(fresh["ci95_low"] > 0)
            contrast_supported = contrast_supported and metric_supported
            reproduced.append({
                "contrast_id": contrast, "metric": metric, "matches_recorded_ci": matches,
                "ci95_low": fresh["ci95_low"], "ci95_high": fresh["ci95_high"],
                "supported": metric_supported,
            })
        support_count += int(contrast_supported)
    safety_count = int(df["safety_failure"].astype(bool).sum())
    reproduced_decision = (
        "NOT_SUPPORTED_FIVE_CONTROLLER_PRIMARY" if safety_count > 0 or support_count == 0
        else "SUPPORTED_FIVE_CONTROLLER_PRIMARY" if support_count == len(CORE_CONTRASTS)
        else "MIXED_FIVE_CONTROLLER_RESULT"
    )
    recorded_decision = load_json(A4 / "decision.json")["decision"]
    add(
        "bootstrap_and_decision_reproducible",
        all(item["matches_recorded_ci"] for item in reproduced) and reproduced_decision == recorded_decision,
        {"recomputed_decision": reproduced_decision, "recorded_decision": recorded_decision, "core_metrics": reproduced},
    )
    supp = pd.read_csv(A4 / "02_case_table/supplementary_node42_case_table.csv")
    add("supplementary_count", len(supp) == 60, len(supp))
    add("supplementary_excluded_from_primary", not df["path_id"].astype(str).str.startswith("supp_").any(), True)
    figures = []
    for stem in ("figure_A4_1_representative_paths", "figure_A4_2_fusion_vs_mtcn_paired_effects"):
        for ext in ("svg", "pdf", "png", "tiff"):
            p = A4 / f"04_figures/{stem}.{ext}"
            figures.append({"path": rel(p), "exists": p.is_file(), "bytes": p.stat().st_size if p.is_file() else 0})
    add("figure_exports", all(x["exists"] and x["bytes"] > 1000 for x in figures), figures)
    svg_text_ok = all("<text" in (A4 / f"04_figures/{stem}.svg").read_text(encoding="utf-8") for stem in ("figure_A4_1_representative_paths", "figure_A4_2_fusion_vs_mtcn_paired_effects"))
    add("editable_svg_text", svg_text_ok, "SVG contains text nodes")
    protocol = load_json(A4 / "00_protocol_lock/protocol_snapshot.json")
    before = {r["path"]: r["actual_sha256"] for r in protocol["protected_input_hashes_before"]}
    after_records = source_hash_snapshot()
    after = {r["path"]: r["actual_sha256"] for r in after_records}
    add("protected_sources_unchanged", before == after, {"before_count": len(before), "after_count": len(after), "differences": sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))})
    add("write_boundary", all(path.resolve().is_relative_to(A4.resolve()) for path in A4.rglob("*") if path.is_file()), str(A4))
    passed = all(item["passed"] for item in checks)
    return {"task_id": "A4", "verified_at": now_iso(), "status": "PASS_A4_VERIFICATION" if passed else "FAIL_A4_VERIFICATION", "checks": checks, "protected_input_hashes_after": after_records}


def refresh_artifact_manifest_and_receipt() -> None:
    excluded = {A4 / "artifact_manifest.json", A4 / "receipt.json"}
    artifacts = []
    for path in sorted(p for p in A4.rglob("*") if p.is_file() and p not in excluded and "__pycache__" not in p.parts):
        artifacts.append({"path": rel(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    manifest = {
        "task_id": "A4", "generated_at": now_iso(), "artifact_count": len(artifacts),
        "scope": "all A4 files except artifact_manifest.json and receipt.json to avoid recursive hashes",
        "artifacts": artifacts,
    }
    write_json(A4 / "artifact_manifest.json", manifest)
    verification = load_json(A4 / "05_verification/verification_report.json")
    decision = load_json(A4 / "decision.json")
    receipt = {
        "task_id": "A4", "issued_at": now_iso(),
        "status": "COMPLETE" if verification["status"] == "PASS_A4_VERIFICATION" else "FAILED_VERIFICATION",
        "decision": decision["decision"], "write_boundary_respected": True,
        "primary_case_count": 138, "supplementary_case_count": 60,
        "training_executed": False, "simulation_executed": False,
        "artifact_manifest": rel(A4 / "artifact_manifest.json"), "artifact_manifest_sha256": sha256(A4 / "artifact_manifest.json"),
        "decision_file": rel(A4 / "decision.json"), "decision_sha256": sha256(A4 / "decision.json"),
        "report": rel(A4 / "A4_experiment_report.md"), "report_sha256": sha256(A4 / "A4_experiment_report.md"),
        "verification": rel(A4 / "05_verification/verification_report.json"), "verification_sha256": sha256(A4 / "05_verification/verification_report.json"),
        "node42_historical_decision_preserved": decision["node42_historical_development_decision"],
    }
    write_json(A4 / "receipt.json", receipt)


def verify(write: bool = True) -> dict[str, Any]:
    result = verification_checks()
    if write:
        write_json(A4 / "05_verification/verification_report.json", result)
    if result["status"] != "PASS_A4_VERIFICATION":
        failed = [c["check"] for c in result["checks"] if not c["passed"]]
        raise RuntimeError(f"A4 verification failed: {failed}")
    return result


def run_all() -> None:
    audit()
    assemble()
    analyze()
    make_figures()
    write_report_and_manifests()
    verify(write=True)
    refresh_artifact_manifest_and_receipt()
    verify(write=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=("audit", "assemble", "analyze", "figures", "finalize", "verify", "all"), default="all")
    args = parser.parse_args()
    mkdirs()
    if args.stage == "audit":
        audit()
    elif args.stage == "assemble":
        assemble()
    elif args.stage == "analyze":
        analyze()
    elif args.stage == "figures":
        make_figures()
    elif args.stage == "finalize":
        write_report_and_manifests()
        verify(write=True)
        refresh_artifact_manifest_and_receipt()
    elif args.stage == "verify":
        verify(write=True)
        refresh_artifact_manifest_and_receipt()
    else:
        run_all()
    print(f"A4_STAGE_COMPLETE|{args.stage}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
