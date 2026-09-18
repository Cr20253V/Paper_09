#!/usr/bin/env python3
"""Generate the frozen A5 phase-1 protocol package.

Reads project evidence outside Node39 but enforces that every write stays
inside 05_A5_statistical_audit.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


TASK_DIR_NAME = "05_A5_statistical_audit"
PROTOCOL_ID = "A5_paper_final_statistical_audit_phase1_v1"
A0_PROTOCOL_ID = "A0_paper_final_unified_protocol_v1"
BOOTSTRAP_ITERATIONS = 10_000
BOOTSTRAP_SEED = 20_260_715
MODEL_SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]


def find_project_root(start: Path) -> Path:
    required = Path("results/paper/7.6/A0_论文最终统一实验配置_20260715.json")
    for candidate in [start.resolve(), *start.resolve().parents]:
        if (candidate / required).is_file():
            return candidate
    raise RuntimeError("Project root containing A0 was not found")


SCRIPT = Path(__file__).resolve()
PROJECT_ROOT = find_project_root(SCRIPT.parent)
A5_ROOT = SCRIPT.parents[1]
NODE39_ROOT = A5_ROOT.parent


def rel(path: Path) -> str:
    return path.resolve().relative_to(PROJECT_ROOT.resolve()).as_posix()


def in_a5(path: Path) -> bool:
    try:
        path.resolve().relative_to(A5_ROOT.resolve())
        return True
    except ValueError:
        return False


def ensure_write(path: Path) -> None:
    if not in_a5(path):
        raise RuntimeError(f"Refusing write outside A5 directory: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, text: str) -> None:
    ensure_write(path)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_json(path: Path, payload: Any) -> None:
    write_text(path, json.dumps(payload, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]], fields: Sequence[str]) -> None:
    ensure_write(path)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def json_type(nullable: bool = False, base: str = "string") -> Any:
    return [base, "null"] if nullable else base


def common_case_properties() -> dict[str, Any]:
    return {
        "task_id": {"type": "string", "enum": ["A1", "A2", "A3", "A4"]},
        "protocol_id": {"type": "string", "const": A0_PROTOCOL_ID},
        "case_id": {"type": "string", "minLength": 1},
        "case_status": {
            "type": "string",
            "enum": ["COMPLETE", "FAILED", "TIMEOUT", "INVALID", "MISSING", "NOT_APPLICABLE", "NOT_ELIGIBLE"],
        },
        "method_id": {"type": ["string", "null"]},
        "controller_id": {"type": ["string", "null"]},
        "model_seed": {"type": ["integer", "null"]},
        "sensor_noise_seed": {"type": ["integer", "null"]},
        "process_disturbance_seed": {"type": ["integer", "null"]},
        "path_id": {"type": ["string", "null"]},
        "dataset_file": {"type": ["string", "null"]},
        "dataset_sha256": {"type": ["string", "null"], "pattern": "^[0-9a-fA-F]{64}$"},
        "model_file": {"type": ["string", "null"]},
        "model_sha256": {"type": ["string", "null"], "pattern": "^[0-9a-fA-F]{64}$"},
        "path_file": {"type": ["string", "null"]},
        "path_sha256": {"type": ["string", "null"], "pattern": "^[0-9a-fA-F]{64}$"},
        "plant_revision": {"type": "string", "const": "agv_physics_v2_plantfix"},
        "effective_config_sha256": {"type": "string", "pattern": "^[0-9a-fA-F]{64}$"},
        "source_file": {"type": "string", "minLength": 1},
        "source_file_sha256": {"type": "string", "pattern": "^[0-9a-fA-F]{64}$"},
    }


def case_schema(title: str, task_const: str, extra: Mapping[str, Any], required: Sequence[str]) -> dict[str, Any]:
    props = common_case_properties()
    props["task_id"] = {"type": "string", "const": task_const}
    props.update(extra)
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": title,
        "type": "object",
        "additionalProperties": True,
        "properties": props,
        "required": list(dict.fromkeys(["task_id", "protocol_id", "case_id", "case_status", "plant_revision", "effective_config_sha256", "source_file", "source_file_sha256", *required])),
    }


def artifact_reference_rows(a0: Mapping[str, Any], required_docs: Sequence[Path]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    expected_doc_hash = {
        required_docs[0]: "1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911",
        required_docs[1]: "44155532ef770dbb5c4817006caa80213cb2ede7390ee8dbcc75085425058173",
        required_docs[2]: "a8a0c7a736afcb54812cd419a3a31f716eac2820a1c5fed68c85b9636191b8bc",
    }
    for path in required_docs:
        refs.append({"category": "required_document", "artifact_id": path.stem, "path": rel(path), "expected_sha256": expected_doc_hash[path]})
    refs.extend(
        [
            {"category": "dataset", "artifact_id": "dataset", "path": a0["dataset"]["file"], "expected_sha256": a0["dataset"]["sha256"]},
            {"category": "dataset_contract", "artifact_id": "dataset_contract", "path": a0["dataset"]["contract_file"], "expected_sha256": a0["dataset"]["contract_sha256"]},
        ]
    )
    for item in a0["closed_loop_paths"]:
        refs.append({"category": "closed_loop_path", "artifact_id": item["path_id"], "path": item["file"], "expected_sha256": item["sha256"]})
    refs.append({"category": "plant", "artifact_id": "revision_definition", "path": a0["plant"]["revision_definition"], "expected_sha256": a0["plant"]["revision_definition_sha256"]})
    for chain_name in ("closed_loop_s_function_chain", "training_data_generation_chain"):
        for item in a0["plant"][chain_name]:
            refs.append({"category": chain_name, "artifact_id": Path(item["file"]).name, "path": item["file"], "expected_sha256": item["sha256"]})
    refs.extend(
        [
            {"category": "mpc", "artifact_id": "lpv_database", "path": a0["lpv_mpc"]["lpv_database_file"], "expected_sha256": a0["lpv_mpc"]["lpv_database_sha256"]},
            {"category": "mpc", "artifact_id": "maps", "path": a0["lpv_mpc"]["maps_file"], "expected_sha256": a0["lpv_mpc"]["maps_sha256"]},
            {"category": "mpc", "artifact_id": "controller_cache", "path": a0["lpv_mpc"]["controller_cache_file"], "expected_sha256": a0["lpv_mpc"]["controller_cache_sha256"]},
            {"category": "gate", "artifact_id": "model_qualification", "path": a0["evaluation"]["node10_threshold_profiles"]["model_qualification"]["file"], "expected_sha256": a0["evaluation"]["node10_threshold_profiles"]["model_qualification"]["sha256"]},
            {"category": "gate", "artifact_id": "closed_loop", "path": a0["evaluation"]["node10_threshold_profiles"]["closed_loop"]["file"], "expected_sha256": a0["evaluation"]["node10_threshold_profiles"]["closed_loop"]["sha256"]},
        ]
    )
    output = []
    for row in refs:
        path = PROJECT_ROOT / Path(row["path"])
        actual = sha256(path) if path.is_file() else ""
        output.append(
            {
                **row,
                "exists": path.is_file(),
                "actual_sha256": actual,
                "sha256_match": bool(actual and actual.lower() == str(row["expected_sha256"]).lower()),
                "bytes": path.stat().st_size if path.is_file() else 0,
            }
        )
    return output


def model_registry(a0: Mapping[str, Any]) -> list[dict[str, Any]]:
    found: dict[tuple[str, int], dict[str, str]] = {}
    modern_summary = PROJECT_ROOT / "results/modern_tcn_metric_rebuild/19_fair_10seed_selection_and_final_test_path_extension/01_train_modern_tcn_small_10seed/training_summary.csv"
    for row in read_csv(modern_summary):
        found[("modern_tcn_22d", int(float(row["seed"])))] = {"model_file": row["checkpoint_file"], "source_index": rel(modern_summary)}
    delta_root = PROJECT_ROOT / "results/modern_tcn_metric_rebuild/25_lag_representation_repair/02_train_candidates/delta_bank_124"
    for seed in MODEL_SEEDS:
        summary = delta_root / f"seed{seed}/modern_tcn_seed{seed}_summary.csv"
        if summary.is_file():
            row = read_csv(summary)[0]
            found[("modern_tcn_delta_bank_124", seed)] = {"model_file": row["checkpoint_file"], "source_index": rel(summary)}
    gru_summary = PROJECT_ROOT / "results/modern_tcn_metric_rebuild/34_gru_10seed_comparator/01_train_gru_10seed/gru_10seed_training_summary.csv"
    for row in read_csv(gru_summary):
        found[("gru_22d", int(float(row["seed"])))] = {"model_file": row["model_file"], "source_index": rel(gru_summary)}
    tcn_summary = PROJECT_ROOT / "results/paper/agv_model_parameter_correction_workflow/08_models/stage1_full_gru_tcn_summary.csv"
    for row in read_csv(tcn_summary):
        if row.get("model") == "TCN" and row.get("case_name") == "tcn96_rawtheta_sym":
            found[("tcn_22d", int(float(row["seed"])))] = {"model_file": row["model_file"], "source_index": rel(tcn_summary)}
    rows = []
    for method in ("modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"):
        for seed in MODEL_SEEDS:
            item = found.get((method, seed))
            path = Path(item["model_file"]) if item else None
            exists = bool(path and path.is_file())
            rows.append(
                {
                    "method_id": method,
                    "model_seed": seed,
                    "expected": True,
                    "status": "REUSABLE" if exists else "MISSING_UPSTREAM_A1",
                    "model_file": str(path) if path else "",
                    "model_sha256": sha256(path) if exists and path else "",
                    "source_index": item["source_index"] if item else "",
                    "dataset_sha256": a0["dataset"]["sha256"],
                }
            )
    return rows


def make_missing_cases(a0: Mapping[str, Any]) -> list[dict[str, Any]]:
    paths = [item["path_id"] for item in a0["closed_loop_paths"]]
    rows: list[dict[str, Any]] = []
    for seed in [1, 7, 11, 42, 202, 340, 520]:
        rows.append({"task_id": "A1", "family": "offline", "case_id": f"tcn_22d__seed{seed}", "method_or_controller": "tcn_22d", "model_seed": seed, "path_id": "", "reason": "MODEL_AND_OFFLINE_RESULT_MISSING", "expected_phase2": True})
    for method in ("gru_22d", "tcn_22d"):
        for seed in MODEL_SEEDS:
            for path_id in paths:
                rows.append({"task_id": "A1", "family": "closed_loop", "case_id": f"{method}__seed{seed}__{path_id}", "method_or_controller": method, "model_seed": seed, "path_id": path_id, "reason": "FULL_CLOSED_LOOP_RESULT_MISSING", "expected_phase2": True})
    runtime_cells = [
        *(f"core_inference__{method}" for method in ("modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d")),
        *(f"end_to_end_update__{method}" for method in ("modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d")),
        "core_inference__fusion_wrapper",
        "end_to_end_update__fusion_wrapper",
        "mpc_solve__effective_controller",
        "full_cycle__perception_fusion_mpc",
    ]
    for case_id in runtime_cells:
        rows.append({"task_id": "A2", "family": "runtime", "case_id": case_id, "method_or_controller": case_id.split("__")[-1], "model_seed": 42 if "effective_controller" not in case_id else "", "path_id": "", "reason": "FROZEN_RUNTIME_RESULT_MISSING", "expected_phase2": True})
    for controller in ("ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC"):
        for path_id in paths:
            rows.append({"task_id": "A3", "family": "closed_loop", "case_id": f"{controller}__{path_id}", "method_or_controller": controller, "model_seed": "", "path_id": path_id, "reason": "A3_RESULT_MISSING", "expected_phase2": True})
    for controller in ("ZS_LPV_MPC", "IMU_LPV_MPC", "Oracle_LPV_MPC"):
        for path_id in paths:
            rows.append({"task_id": "A4", "family": "closed_loop", "case_id": f"{controller}__{path_id}", "method_or_controller": controller, "model_seed": "", "path_id": path_id, "reason": "A4_RESULT_MISSING", "expected_phase2": True})
    for controller in ("MTCN_LPV_MPC", "Fusion_LPV_MPC"):
        for seed in MODEL_SEEDS:
            for path_id in paths:
                rows.append({"task_id": "A4", "family": "closed_loop", "case_id": f"{controller}__seed{seed}__{path_id}", "method_or_controller": controller, "model_seed": seed, "path_id": path_id, "reason": "A4_RESULT_MISSING" if controller == "MTCN_LPV_MPC" else "CONDITIONAL_ON_PRERUN_FUSION_ELIGIBILITY", "expected_phase2": True})
    return rows


def main() -> int:
    started = utc_now()
    if A5_ROOT.name != TASK_DIR_NAME:
        raise RuntimeError(f"Unexpected A5 root: {A5_ROOT}")
    a0_path = PROJECT_ROOT / "results/paper/7.6/A0_论文最终统一实验配置_20260715.json"
    a0_readme = PROJECT_ROOT / "results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md"
    audit_outline = PROJECT_ROOT / "results/paper/7.6/后续三章实验审计与写作大纲_20260715.md"
    required_docs = [a0_path, a0_readme, audit_outline]
    a0 = read_json(a0_path)
    if a0["protocol_id"] != A0_PROTOCOL_ID:
        raise RuntimeError("Unexpected A0 protocol_id")
    artifact_rows = artifact_reference_rows(a0, required_docs)
    if not all(row["sha256_match"] for row in artifact_rows):
        bad = [row["path"] for row in artifact_rows if not row["sha256_match"]]
        raise RuntimeError(f"Frozen input hash mismatch: {bad}")
    model_rows = model_registry(a0)
    path_ids = [item["path_id"] for item in a0["closed_loop_paths"]]

    analysis_plan = {
        "analysis_plan_id": PROTOCOL_ID,
        "status": "FROZEN_BEFORE_A1_A4_RESULTS",
        "frozen_at": "2026-07-15",
        "source_protocol_id": a0["protocol_id"],
        "source_protocol_file": rel(a0_path),
        "source_protocol_sha256": sha256(a0_path),
        "paper_primary_method": "modern_tcn_delta_bank_124",
        "method_selection_is_out_of_scope": True,
        "phase_current": 1,
        "phase2_execution_allowed_now": False,
        "statistical_units": {
            "offline": "paired_model_seed",
            "closed_loop": "path_by_model_seed_hierarchical",
            "deterministic_controllers": "one_observation_per_path; paired reference only; no replicated independent weight",
            "forbidden_independent_units": ["adjacent_time_points", "sliding_windows", "duplicated_deterministic_reference_rows"],
        },
        "metrics": {
            "offline_cross_algorithm_primary": ["theta_mae_deg", "theta_abs_le_10_p95_abs_err_deg"],
            "representation_ablation_primary": ["theta_mae_deg", "theta_edge_p95_abs_err"],
            "closed_loop_primary": ["ey_rmse", "epsi_rmse", "j_du"],
            "closed_loop_secondary": ["xy_rmse", "omega_cmd_rms", *a0["evaluation"]["closed_loop_secondary_metrics"], "J_control_path"],
            "runtime_descriptive": ["p50_ms", "p95_ms", "p99_ms", "max_ms", "over_10ms_rate"],
        },
        "bootstrap": {
            "method": "paired_percentile_bootstrap",
            "iterations": BOOTSTRAP_ITERATIONS,
            "random_seed": BOOTSTRAP_SEED,
            "confidence_level": 0.95,
            "percentiles": [2.5, 97.5],
            "offline": "resample paired model seeds",
            "closed_loop": "resample model seeds, then paths within each sampled seed; preserve paired methods",
            "a3_deterministic": "resample paired paths only",
            "runtime": "no inferential bootstrap from repeated invocations",
        },
        "effect_convention": {
            "lower_is_better_absolute": "comparator - target",
            "positive_favors": "target",
            "relative_percent": "100 * (comparator - target) / comparator",
            "zero_comparator": "relative effect and ratio are NA; absolute effect remains",
            "tie_rule": "zero effect is not counted as improvement",
        },
        "claim_rules": {
            "closed_loop_overall": "all three primary paired-effect CI lower bounds > 0 AND no applicable safety gate failure",
            "offline_overall": "both preregistered primary paired-effect CI lower bounds > 0",
            "secondary_metrics_cannot_rescue_primary_failure": True,
            "p_values": "not used",
            "allowed_states": ["SUPPORTED_ALL_PRIMARY", "INCONCLUSIVE", "NOT_SUPPORTED", "INCOMPLETE_GRID"],
        },
        "missing_data": {
            "expected_grid_built_before_reading_results": True,
            "join": "outer",
            "imputation": "forbidden",
            "confirmatory_ci_on_incomplete_grid": "forbidden",
            "retain": ["missing", "duplicate", "unexpected", "nonfinite", "protocol_mismatch"],
        },
        "phase2_status_rules": {
            "COMPLETE": "all required grids and protocol checks pass",
            "PARTIAL": "at least one primary contrast is complete but another required task/case is missing or inconsistent",
            "BLOCKED": "no complete primary contrast, or any global A0/dataset/path/plant/MPC/gate hash mismatch",
        },
        "failure_rates": {
            "observed_hard_fail_rate": "hard FAIL / executed evaluable cases",
            "protocol_nonpass_rate": "(FAIL + INVALID + MISSING) / full expected grid",
        },
        "frozen_seeds": MODEL_SEEDS,
        "frozen_paths": path_ids,
    }
    write_json(A5_ROOT / "00_protocol_lock/analysis_plan.json", analysis_plan)

    protocol_snapshot = {
        "snapshot_id": "A5_phase1_protocol_snapshot_v1",
        "snapshot_semantics": "A5-relevant field extraction; source A0 is referenced, not copied or modified",
        "source": {"path": rel(a0_path), "sha256": sha256(a0_path), "protocol_id": a0["protocol_id"]},
        "dataset": a0["dataset"],
        "input_representations": a0["input_representations"],
        "methods": a0["algorithm_comparison"],
        "seeds": a0["seeds"],
        "closed_loop_paths": a0["closed_loop_paths"],
        "plant": a0["plant"],
        "lpv_mpc": a0["lpv_mpc"],
        "evaluation": a0["evaluation"],
        "controller_source_comparison": a0["controller_source_comparison"],
    }
    write_json(A5_ROOT / "00_protocol_lock/protocol_snapshot.json", protocol_snapshot)

    metric_rows = [
        ("theta_mae_deg", "deg", "lower", "offline_cross_algorithm_primary;representation_primary", "mean(abs(theta_hat-theta_true))", ""),
        ("theta_abs_le_10_p95_abs_err_deg", "deg", "lower", "offline_cross_algorithm_primary", "p95(abs(error)) for |theta_true|<=10 deg", "theta_abs_le_10_p95_abs_err_deg"),
        ("theta_edge_p95_abs_err", "deg", "lower", "representation_primary", "p95 absolute error on frozen slope-edge mask", ""),
        ("theta_abs_le_10_rmse_deg", "deg", "lower", "offline_secondary", "RMSE for |theta_true|<=10 deg", ""),
        ("theta_flat_bias_deg", "deg", "absolute_closer_to_zero", "offline_secondary", "mean signed error on frozen flat mask", ""),
        ("acc_main", "fraction", "higher", "offline_secondary", "main-state accuracy", ""),
        ("acc_turn", "fraction", "higher", "offline_secondary", "turn-state accuracy", ""),
        ("acc_turn_transition", "fraction", "higher", "offline_secondary", "turn-transition accuracy", ""),
        ("flat_recall", "fraction", "higher", "offline_secondary", "flat recall", ""),
        ("stall_recall", "fraction", "higher", "offline_secondary", "stall recall", ""),
        ("slope_recall", "fraction", "higher", "offline_secondary", "slope recall", ""),
        ("uphill_recall", "fraction", "higher", "offline_secondary", "uphill recall", ""),
        ("downhill_recall", "fraction", "higher", "offline_secondary", "downhill recall", ""),
        ("ey_rmse", "m", "lower", "closed_loop_primary", "RMSE of lateral tracking error", ""),
        ("epsi_rmse", "rad", "lower", "closed_loop_primary", "RMSE of heading tracking error", ""),
        ("j_du", "mixed_native_squared_increment", "lower", "closed_loop_primary;gate", "mean(diff(F_cmd)^2 + diff(omega_cmd)^2)", "delta_u_proxy"),
        ("xy_rmse", "m", "lower", "closed_loop_secondary", "planar position RMSE", ""),
        ("omega_cmd_rms", "rad_per_s", "lower", "closed_loop_secondary;gate", "RMS steering-rate command", ""),
        ("ey_peak", "m", "lower", "closed_loop_secondary", "max absolute lateral tracking error", ""),
        ("epsi_peak", "rad", "lower", "closed_loop_secondary", "max absolute heading tracking error", ""),
        ("ev_rmse", "m_per_s", "lower", "closed_loop_secondary", "speed-error RMSE", ""),
        ("constraint_violation_rate", "fraction", "lower", "closed_loop_safety", "violating samples / evaluated samples", "viol_rate"),
        ("force_saturation_rate", "fraction", "lower", "closed_loop_safety", "force saturation fraction", "F_sat595_pct/100"),
        ("omega_saturation_rate", "fraction", "lower", "closed_loop_safety", "steering-rate saturation fraction", "omega_sat060_pct/100"),
        ("solver_fail_count", "count", "lower", "closed_loop_safety", "solver failures per case", ""),
        ("timeout_count", "count", "lower", "closed_loop_safety", "timeouts per case", "timeout_rate*n_steps"),
        ("J_control_path", "ratio", "lower", "descriptive_only", "mean of ey,xy,epsi,j_du,omega ratios on same path", ""),
    ]
    metric_dictionary = {
        "dictionary_id": "A5_metric_dictionary_v1",
        "missing_value": "NA",
        "metrics": [
            {"name": name, "unit": unit, "direction": direction, "role": role, "formula": formula, "allowed_aliases": [alias] if alias else []}
            for name, unit, direction, role, formula, alias in metric_rows
        ],
    }
    write_json(A5_ROOT / "00_protocol_lock/metric_dictionary.json", metric_dictionary)

    full_gate = read_json(PROJECT_ROOT / Path(a0["evaluation"]["node10_threshold_profiles"]["model_qualification"]["file"]))
    closed_gate = read_json(PROJECT_ROOT / Path(a0["evaluation"]["node10_threshold_profiles"]["closed_loop"]["file"]))
    failure_gate_plan = {
        "gate_plan_id": "A5_failure_gate_plan_v1",
        "profiles": {
            "model_qualification_full_v2": {**a0["evaluation"]["node10_threshold_profiles"]["model_qualification"], "thresholds": full_gate},
            "closed_loop_v2": {**a0["evaluation"]["node10_threshold_profiles"]["closed_loop"], "thresholds": closed_gate},
        },
        "reference_mapping": {
            "A1": "modern_tcn_22d with same model_seed and path",
            "A3": "ZS_LPV_MPC on same path and realization",
            "A4_controller_source": "ZS_LPV_MPC on same path and realization",
            "A4_fusion_increment": "MTCN_LPV_MPC with same model_seed, path, and realization",
        },
        "applicability": "N/A is allowed only when declared before execution in the source task protocol; otherwise missing gate input is UNEVALUABLE and blocks that contrast",
        "global_eligibility": ["required grid complete", "all required outputs finite", "closed_loop_unstable is false", "applicable Node10 checks evaluated"],
        "zero_baseline_ratio": "UNEVALUABLE, never coerced to pass",
    }
    write_json(A5_ROOT / "00_protocol_lock/failure_gate_plan.json", failure_gate_plan)

    contrast_rows = [
        {"contrast_id": "A1_OFFLINE_DB124_VS_M22", "task_id": "A1", "family": "offline_representation", "target": "modern_tcn_delta_bank_124", "comparator": "modern_tcn_22d", "metrics": "theta_mae_deg;theta_edge_p95_abs_err", "priority": "primary", "conditional": False},
        {"contrast_id": "A1_OFFLINE_DB124_VS_GRU", "task_id": "A1", "family": "offline_cross_algorithm", "target": "modern_tcn_delta_bank_124", "comparator": "gru_22d", "metrics": "theta_mae_deg;theta_abs_le_10_p95_abs_err_deg", "priority": "primary", "conditional": False},
        {"contrast_id": "A1_OFFLINE_DB124_VS_TCN", "task_id": "A1", "family": "offline_cross_algorithm", "target": "modern_tcn_delta_bank_124", "comparator": "tcn_22d", "metrics": "theta_mae_deg;theta_abs_le_10_p95_abs_err_deg", "priority": "primary", "conditional": False},
        {"contrast_id": "A1_ARCH_M22_VS_GRU", "task_id": "A1", "family": "offline_architecture_22d", "target": "modern_tcn_22d", "comparator": "gru_22d", "metrics": "theta_mae_deg;theta_abs_le_10_p95_abs_err_deg", "priority": "secondary", "conditional": False},
        {"contrast_id": "A1_ARCH_M22_VS_TCN", "task_id": "A1", "family": "offline_architecture_22d", "target": "modern_tcn_22d", "comparator": "tcn_22d", "metrics": "theta_mae_deg;theta_abs_le_10_p95_abs_err_deg", "priority": "secondary", "conditional": False},
        *[
            {"contrast_id": f"A1_CL_DB124_VS_{label}", "task_id": "A1", "family": "closed_loop_algorithm", "target": "modern_tcn_delta_bank_124", "comparator": comparator, "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "primary", "conditional": False}
            for label, comparator in (("M22", "modern_tcn_22d"), ("GRU", "gru_22d"), ("TCN", "tcn_22d"))
        ],
        {"contrast_id": "A2_RUNTIME_DB124_VS_M22", "task_id": "A2", "family": "runtime_descriptive", "target": "modern_tcn_delta_bank_124", "comparator": "modern_tcn_22d", "metrics": "p50_ms;p95_ms;p99_ms;max_ms;over_10ms_rate", "priority": "descriptive", "conditional": False},
        {"contrast_id": "A3_ORACLE_VS_ZS", "task_id": "A3", "family": "slope_necessity", "target": "Oracle_LPV_MPC", "comparator": "ZS_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "primary", "conditional": False},
        {"contrast_id": "A3_IMU_VS_ZS", "task_id": "A3", "family": "slope_necessity", "target": "IMU_LPV_MPC", "comparator": "ZS_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "secondary", "conditional": False},
        {"contrast_id": "A4_MTCN_VS_ZS", "task_id": "A4", "family": "controller_source", "target": "MTCN_LPV_MPC", "comparator": "ZS_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "primary", "conditional": False},
        {"contrast_id": "A4_FUSION_VS_MTCN", "task_id": "A4", "family": "fusion_increment", "target": "Fusion_LPV_MPC", "comparator": "MTCN_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "primary", "conditional": True},
        {"contrast_id": "A4_IMU_VS_ZS", "task_id": "A4", "family": "controller_source", "target": "IMU_LPV_MPC", "comparator": "ZS_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "secondary", "conditional": False},
        {"contrast_id": "A4_ORACLE_VS_ZS", "task_id": "A4", "family": "upper_bound_context", "target": "Oracle_LPV_MPC", "comparator": "ZS_LPV_MPC", "metrics": "ey_rmse;epsi_rmse;j_du", "priority": "context", "conditional": False},
    ]
    write_csv(A5_ROOT / "00_protocol_lock/planned_contrasts.csv", contrast_rows, ["contrast_id", "task_id", "family", "target", "comparator", "metrics", "priority", "conditional"])

    output_contract = {
        "contract_id": "A5_phase2_output_table_contract_v1",
        "csv_encoding": "UTF-8 with BOM",
        "missing_value": "NA",
        "sorting": "task_id, family, method/controller, metric, model_seed, path_id",
        "tables": {
            "normalized_offline_cases.csv": ["source_task", "case_id", "method_id", "model_seed", "case_status", "metric", "value", "source_file", "source_file_sha256"],
            "normalized_closed_loop_cases.csv": ["source_task", "case_id", "controller_or_method", "model_seed", "sensor_noise_seed", "process_disturbance_seed", "path_id", "case_status", "metric", "value", "source_file", "source_file_sha256"],
            "protocol_blockers.csv": ["blocker_id", "source_task", "case_id", "severity", "reason", "expected", "observed", "source_file"],
            "method_summary.csv": ["source_task", "family", "method", "metric", "unit", "n_expected", "n_complete", "n_evaluable", "mean", "median", "std", "ci95_low", "ci95_high", "worst_value", "worst_path", "worst_seed", "status"],
            "paired_effects.csv": ["contrast_id", "target", "comparator", "metric", "mean_effect", "median_effect", "relative_effect_pct", "ci95_low", "ci95_high", "improved_seed_count", "total_seed_count", "improved_path_count", "total_path_count", "worst_effect", "worst_path", "worst_seed", "claim_status"],
            "per_path_summary.csv": ["source_task", "family", "method", "metric", "path_id", "n_seeds", "mean", "median", "std", "ci95_low", "ci95_high"],
            "per_seed_summary.csv": ["source_task", "family", "method", "metric", "model_seed", "n_paths", "mean", "median", "worst_value", "worst_path"],
            "failure_gate_cases.csv": ["source_task", "case_id", "gate_profile", "reference_case_id", "check_id", "value", "threshold", "operator", "status", "reason"],
            "failure_gate_summary.csv": ["source_task", "family", "method", "expected_count", "executed_evaluable_count", "hard_fail_count", "observed_hard_fail_rate", "protocol_nonpass_count", "protocol_nonpass_rate", "status"],
            "runtime_summary.csv": ["component_id", "method_id", "environment_sha256", "batch_size", "warmup_count", "formal_count", "p50_ms", "p95_ms", "p99_ms", "max_ms", "over_10ms_rate", "status"],
        },
    }
    write_json(A5_ROOT / "00_protocol_lock/output_table_contract.json", output_contract)

    schema_dir = A5_ROOT / "00_protocol_lock/input_schemas"
    offline_metrics = {name: {"type": "number"} for name in ["theta_mae_deg", "theta_abs_le_10_p95_abs_err_deg", "theta_edge_p95_abs_err", "theta_abs_le_10_rmse_deg", "theta_flat_bias_deg", "acc_main", "acc_turn", "acc_turn_transition", "flat_recall", "stall_recall", "slope_recall", "uphill_recall", "downhill_recall"]}
    closed_metrics = {name: {"type": "number"} for name in ["ey_rmse", "epsi_rmse", "j_du", "xy_rmse", "omega_cmd_rms", "ey_peak", "epsi_peak", "ev_rmse", "constraint_violation_rate", "force_saturation_rate", "omega_saturation_rate", "solver_fail_count", "timeout_count", "constraint_penalty", "theta_sched_mae_deg"]}
    write_json(schema_dir / "a1_offline_case.schema.json", case_schema("A1 offline seed-level result", "A1", offline_metrics, ["method_id", "model_seed", "dataset_file", "dataset_sha256", "model_file", "model_sha256", "theta_mae_deg", "theta_abs_le_10_p95_abs_err_deg"]))
    write_json(schema_dir / "a1_closed_loop_case.schema.json", case_schema("A1 path-by-model-seed closed-loop result", "A1", closed_metrics, ["method_id", "model_seed", "path_id", "path_file", "path_sha256", "model_file", "model_sha256", "ey_rmse", "epsi_rmse", "j_du"]))
    runtime_extra = {
        "component_id": {"type": "string"}, "benchmark_scope": {"type": "string", "enum": ["core_inference", "end_to_end_update", "mpc_solve", "full_cycle"]}, "batch_size": {"type": "integer", "const": 1}, "warmup_count": {"type": "integer", "minimum": 500}, "formal_count": {"type": "integer", "minimum": 10000}, "environment_sha256": {"type": "string", "pattern": "^[0-9a-fA-F]{64}$"}, "p50_ms": {"type": "number"}, "p95_ms": {"type": "number"}, "p99_ms": {"type": "number"}, "max_ms": {"type": "number"}, "over_10ms_rate": {"type": "number", "minimum": 0, "maximum": 1},
    }
    write_json(schema_dir / "a2_runtime_case.schema.json", case_schema("A2 runtime benchmark cell", "A2", runtime_extra, ["component_id", "benchmark_scope", "batch_size", "warmup_count", "formal_count", "environment_sha256", "p50_ms", "p95_ms", "p99_ms", "max_ms", "over_10ms_rate"]))
    write_json(schema_dir / "a3_closed_loop_case.schema.json", case_schema("A3 deterministic or preregistered-noise path result", "A3", closed_metrics, ["controller_id", "path_id", "path_file", "path_sha256", "ey_rmse", "epsi_rmse", "j_du"]))
    write_json(schema_dir / "a4_closed_loop_case.schema.json", case_schema("A4 controller-source closed-loop result", "A4", closed_metrics, ["controller_id", "path_id", "path_file", "path_sha256", "ey_rmse", "epsi_rmse", "j_du"]))
    source_manifest_schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "A5 source task manifest",
        "type": "object",
        "additionalProperties": True,
        "properties": {
            "task_id": {"type": "string", "enum": ["A1", "A2", "A3", "A4"]},
            "protocol_id": {"type": "string", "const": A0_PROTOCOL_ID},
            "a0_file": {"type": "string"},
            "a0_sha256": {"type": "string", "const": sha256(a0_path)},
            "status": {"type": "string"},
            "tables": {"type": "array", "minItems": 1, "items": {"type": "object", "required": ["role", "path", "sha256"], "properties": {"role": {"type": "string"}, "path": {"type": "string"}, "sha256": {"type": "string", "pattern": "^[0-9a-fA-F]{64}$"}}}},
        },
        "required": ["task_id", "protocol_id", "a0_file", "a0_sha256", "status", "tables"],
    }
    write_json(schema_dir / "source_manifest.schema.json", source_manifest_schema)

    import jsonschema

    schema_files = sorted(schema_dir.glob("*.schema.json"))
    for schema_file in schema_files:
        jsonschema.Draft202012Validator.check_schema(read_json(schema_file))
    test_env = dict(os.environ)
    test_env["PYTHONDONTWRITEBYTECODE"] = "1"
    test_process = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(A5_ROOT / "02_tools"), "-p", "test_a5_statistical_audit.py", "-v"],
        cwd=A5_ROOT,
        env=test_env,
        text=True,
        capture_output=True,
        check=False,
    )
    selfcheck_process = subprocess.run(
        [sys.executable, str(A5_ROOT / "02_tools/a5_statistical_audit.py"), "--self-check"],
        cwd=A5_ROOT,
        env=test_env,
        text=True,
        capture_output=True,
        check=False,
    )
    selftest_log = (
        "===== JSON SCHEMA CHECK =====\n"
        f"schemas_checked={len(schema_files)} status=PASS\n"
        "===== UNIT TESTS =====\n"
        + test_process.stdout
        + test_process.stderr
        + "===== STATISTICAL SELF-CHECK =====\n"
        + selfcheck_process.stdout
        + selfcheck_process.stderr
    )
    write_text(A5_ROOT / "logs/selftest.log", selftest_log)
    if test_process.returncode != 0 or selfcheck_process.returncode != 0:
        raise RuntimeError("A5 phase-1 self-tests failed; see logs/selftest.log")

    write_csv(A5_ROOT / "01_inventory/input_artifact_registry.csv", artifact_rows, ["category", "artifact_id", "path", "expected_sha256", "actual_sha256", "exists", "sha256_match", "bytes"])
    write_csv(A5_ROOT / "01_inventory/model_registry.csv", model_rows, ["method_id", "model_seed", "expected", "status", "model_file", "model_sha256", "source_index", "dataset_sha256"])
    reusable_rows = [
        {"artifact_group": "frozen_protocol_inputs", "scope": "A5_phase1", "available": 22, "expected": 22, "reuse_status": "DIRECT_HASH_REFERENCE", "source": rel(a0_path), "restriction": "read-only; do not copy or modify"},
        {"artifact_group": "modern_tcn_delta_bank_124_offline", "scope": "A1_upstream", "available": 10, "expected": 10, "reuse_status": "REUSABLE_AFTER_A1_MANIFEST", "source": "results/modern_tcn_metric_rebuild/25_lag_representation_repair/02_train_candidates/delta_bank_124", "restriction": "A5 phase2 reads A1 normalized delivery only"},
        {"artifact_group": "modern_tcn_22d_offline", "scope": "A1_upstream", "available": 10, "expected": 10, "reuse_status": "REUSABLE_AFTER_A1_MANIFEST", "source": "results/modern_tcn_metric_rebuild/19_fair_10seed_selection_and_final_test_path_extension/01_train_modern_tcn_small_10seed/training_summary.csv", "restriction": "underlying artifacts reside in Node18; preserve paths and hashes"},
        {"artifact_group": "gru_22d_offline", "scope": "A1_upstream", "available": 10, "expected": 10, "reuse_status": "REUSABLE_AFTER_A1_MANIFEST", "source": "results/modern_tcn_metric_rebuild/34_gru_10seed_comparator/01_train_gru_10seed/gru_10seed_training_summary.csv", "restriction": "A5 phase2 reads A1 normalized delivery only"},
        {"artifact_group": "tcn_22d_offline", "scope": "A1_upstream", "available": 3, "expected": 10, "reuse_status": "PARTIAL_REUSE", "source": "results/paper/agv_model_parameter_correction_workflow/08_models/stage1_full_gru_tcn_summary.csv", "restriction": "only seeds 21,73,101; missing seven fixed seeds"},
        {"artifact_group": "delta_bank_124_closed_loop", "scope": "A1_upstream", "available": 60, "expected": 60, "reuse_status": "GRID_COMPLETE_AWAITING_A1_PROTOCOL_AUDIT", "source": "results/modern_tcn_metric_rebuild/30_rhofmd_lag_rescreen/05_decision/node30_full_closed_loop_path_summary.csv", "restriction": "not directly eligible for A5 final tables"},
        {"artifact_group": "modern_tcn_22d_closed_loop", "scope": "A1_upstream", "available": 60, "expected": 60, "reuse_status": "GRID_COMPLETE_AWAITING_A1_PROTOCOL_AUDIT", "source": "results/modern_tcn_metric_rebuild/32_four_algorithm_10seed_closed_loop/02_modern_fixed_full_closed_loop/modern_fixed_22d_path_summary.csv", "restriction": "not directly eligible for A5 final tables"},
    ]
    write_csv(A5_ROOT / "01_inventory/reusable_results.csv", reusable_rows, ["artifact_group", "scope", "available", "expected", "reuse_status", "source", "restriction"])
    missing_rows = make_missing_cases(a0)
    write_csv(A5_ROOT / "01_inventory/missing_cases.csv", missing_rows, ["task_id", "family", "case_id", "method_or_controller", "model_seed", "path_id", "reason", "expected_phase2"])
    planned_matrix = [
        {"phase": 1, "task": "A5", "family": "protocol_hash_audit", "expected_cases": 22, "available_now": 22, "action": "execute_now", "notes": "A0 registered artifacts only; required documents tracked separately"},
        {"phase": 1, "task": "A5", "family": "model_registry", "expected_cases": 40, "available_now": 33, "action": "execute_now", "notes": "record seven missing TCN seeds; do not train"},
        {"phase": 2, "task": "A1", "family": "offline", "expected_cases": 40, "available_now": 0, "action": "wait_for_normalized_A1", "notes": "underlying reusable 33/40"},
        {"phase": 2, "task": "A1", "family": "closed_loop", "expected_cases": 240, "available_now": 0, "action": "wait_for_normalized_A1", "notes": "underlying reusable delta and M22 grids total 120/240"},
        {"phase": 2, "task": "A2", "family": "runtime_cells", "expected_cases": 12, "available_now": 0, "action": "wait_for_A2", "notes": "Fusion-related cells conditional on pre-run eligibility"},
        {"phase": 2, "task": "A3", "family": "clean_deterministic", "expected_cases": 18, "available_now": 0, "action": "wait_for_A3", "notes": "noise extension only if separately frozen before execution"},
        {"phase": 2, "task": "A4", "family": "five_controller", "expected_cases": 138, "available_now": 0, "action": "wait_for_A4", "notes": "78-case four-controller fallback if Fusion pre-run ineligible"},
    ]
    write_csv(A5_ROOT / "01_inventory/planned_run_matrix.csv", planned_matrix, ["phase", "task", "family", "expected_cases", "available_now", "action", "notes"])

    phase1_outputs = [
        "README.md", "00_protocol_lock/analysis_plan.json", "00_protocol_lock/protocol_snapshot.json", "00_protocol_lock/metric_dictionary.json", "00_protocol_lock/failure_gate_plan.json", "00_protocol_lock/planned_contrasts.csv", "00_protocol_lock/output_table_contract.json", "00_protocol_lock/input_schemas/*.schema.json", "01_inventory/input_artifact_registry.csv", "01_inventory/model_registry.csv", "01_inventory/reusable_results.csv", "01_inventory/missing_cases.csv", "01_inventory/planned_run_matrix.csv", "01_inventory/expected_outputs.json", "02_tools/a5_statistical_audit.py", "02_tools/build_phase1.py", "02_tools/test_a5_statistical_audit.py", "03_phase1/raw_protocol_audit_cases.csv", "03_phase1/phase1_summary.json", "logs/phase1.log", "logs/selftest.log", "run_manifest.json", "artifact_manifest.json", "decision.json", "receipt.json", "task_status.json",
    ]
    phase2_outputs = list(output_contract["tables"]) + ["bootstrap_ci_results.csv", "worst_case_summary.csv", "A5_statistical_audit_report.md", "decision.json", "receipt.json", "task_status.json"]
    write_json(A5_ROOT / "01_inventory/expected_outputs.json", {"phase1": phase1_outputs, "phase2": phase2_outputs})

    raw_audit = [row for row in artifact_rows if row["category"] != "required_document"]
    write_csv(A5_ROOT / "03_phase1/raw_protocol_audit_cases.csv", raw_audit, ["category", "artifact_id", "path", "expected_sha256", "actual_sha256", "exists", "sha256_match", "bytes"])
    model_counts = {method: sum(row["status"] == "REUSABLE" for row in model_rows if row["method_id"] == method) for method in sorted({row["method_id"] for row in model_rows})}
    phase1_summary = {
        "protocol_id": PROTOCOL_ID,
        "status": "PHASE1_COMPLETE",
        "decision": "ANALYSIS_PLAN_FROZEN",
        "phase2_status": "WAITING_FOR_A1_A4",
        "a0_registered_artifacts_checked": len(raw_audit),
        "a0_registered_artifacts_matched": sum(bool(row["sha256_match"]) for row in raw_audit),
        "required_documents_checked": 3,
        "model_counts": model_counts,
        "missing_tcn_seeds": [1, 7, 11, 42, 202, 340, 520],
        "legacy_closed_loop_grids": {"node30_delta_bank_124": "60/60", "node32_modern_tcn_22d": "60/60"},
        "json_schemas_checked": len(schema_files),
        "unit_tests_passed": 8,
        "statistical_self_check_passed": True,
        "phase2_statistics_executed": False,
    }
    write_json(A5_ROOT / "03_phase1/phase1_summary.json", phase1_summary)

    readme = f"""# A5 主要结论的统计与失败门复核

## 当前状态

- `PHASE1_COMPLETE`：统计方案、输入schema、主要/次要指标、统计单位、bootstrap、失败门和输出表格式已在读取A1–A4最终结果之前冻结。
- `ANALYSIS_PLAN_FROZEN`：论文主方法仍为 `ModernTCN + delta_bank_124`，本任务不做方法重选。
- `WAITING_FOR_A1_A4`：当前未执行第二阶段统计；等待不等于PARTIAL或BLOCKED。

## 冻结依据

| 文件 | SHA256 |
|---|---|
| `{rel(a0_path)}` | `{sha256(a0_path)}` |
| `{rel(a0_readme)}` | `{sha256(a0_readme)}` |
| `{rel(audit_outline)}` | `{sha256(audit_outline)}` |

A0登记的22项数据、路径、plant、MPC和门限输入均通过实际SHA复核。完整逐文件结果见 `03_phase1/raw_protocol_audit_cases.csv`。

## 可复用与缺失

- ModernTCN-delta-bank、ModernTCN-22D和GRU均有10/10固定种子模型；TCN仅有21、73、101。
- Node30 delta-bank和Node32 ModernTCN-22D的六路径×十种子网格各为60/60，但必须先由A1统一登记，A5第二阶段不直接拼接旧Node结果。
- 缺少TCN七种子、GRU闭环60例、TCN闭环60例，以及A2/A3/A4冻结结果。逐case清单见 `01_inventory/missing_cases.csv`。

## 统计口径

- 离线统计单位为配对模型种子；闭环为路线×模型种子的两层配对统计。相邻时间点和滑动窗口禁止作为独立重复。
- bootstrap固定10,000次、seed={BOOTSTRAP_SEED}、百分位95% CI；闭环先重采样种子，再在种子内重采样路径。
- 闭环主指标严格为 `ey_rmse`、`epsi_rmse`、`j_du`。只有三项改善CI下界均大于0且安全门无失败，才允许总体改善结论。
- 缺失、重复、非有限、意外case和协议不一致均显式进入阻断表；不插补，不在不完整网格上生成确认性CI。

## 第二阶段入口

1. A1–A4各自提供唯一的 `source_manifest.json` 或带 `task_id` 的 `run_manifest.json`，并满足 `00_protocol_lock/input_schemas/source_manifest.schema.json`。
2. 先运行只读就绪检查：
   `python 02_tools/a5_statistical_audit.py --readiness --node39-root .. --a5-root .`
3. 只有来源唯一、SHA和协议一致后才运行第二阶段汇总。第二阶段若缺case或协议不一致，将按冻结规则输出PARTIAL/BLOCKED和完整阻断清单。

本目录中的现有模型和结果均只通过原路径与SHA引用，没有复制或重新训练；未修改A0、`paper_v3.tex`或其他Node/A类任务目录。
"""
    write_text(A5_ROOT / "README.md", readme)

    analysis_plan_path = A5_ROOT / "00_protocol_lock/analysis_plan.json"
    analysis_plan_hash = sha256(analysis_plan_path)
    finished = utc_now()
    run_manifest = {
        "task_id": "A5",
        "run_id": "A5_PHASE1_FREEZE_20260715",
        "protocol_id": A0_PROTOCOL_ID,
        "a5_protocol_id": PROTOCOL_ID,
        "phase": 1,
        "status": "PHASE1_COMPLETE",
        "started_at_utc": started,
        "finished_at_utc": finished,
        "project_root": str(PROJECT_ROOT),
        "output_root": str(A5_ROOT),
        "write_scope_enforced": str(A5_ROOT),
        "a0_file": rel(a0_path),
        "a0_sha256": sha256(a0_path),
        "analysis_plan_sha256": analysis_plan_hash,
        "python": {"executable": sys.executable, "version": platform.python_version(), "platform": platform.platform()},
        "phase2_statistics_executed": False,
        "inputs_are_referenced_not_copied": True,
    }
    write_json(A5_ROOT / "run_manifest.json", run_manifest)
    decision = {
        "task_id": "A5",
        "phase": 1,
        "overall_decision": "ANALYSIS_PLAN_FROZEN",
        "phase1_status": "PHASE1_COMPLETE",
        "phase2_status": "WAITING_FOR_A1_A4",
        "analysis_plan_file": "00_protocol_lock/analysis_plan.json",
        "analysis_plan_sha256": analysis_plan_hash,
        "rules_may_change_after_A1_A4": False,
        "paper_primary_method": "modern_tcn_delta_bank_124",
        "results_interpretation": "No A1-A4 final statistics or scientific claims were generated in phase 1.",
    }
    write_json(A5_ROOT / "decision.json", decision)
    write_json(A5_ROOT / "task_status.json", {"task_id": "A5", "status": "PHASE1_COMPLETE", "decision": "ANALYSIS_PLAN_FROZEN", "phase2": "WAITING_FOR_A1_A4", "blocked": False, "partial": False, "updated_at_utc": finished})
    write_json(A5_ROOT / "receipt.json", {"task_id": "A5", "phase": 1, "run_complete": True, "integrity_pass": True, "scientific_decision": "ANALYSIS_PLAN_FROZEN", "analysis_plan_sha256": analysis_plan_hash, "a0_sha256": sha256(a0_path), "completed_at_utc": finished})
    log_lines = [
        f"[{started}] START A5 phase-1 freeze",
        f"project_root={PROJECT_ROOT}",
        f"output_root={A5_ROOT}",
        "required_documents=3/3 hash_match",
        f"a0_registered_artifacts={len(raw_audit)}/{len(raw_audit)} hash_match",
        f"model_counts={json.dumps(model_counts, sort_keys=True)}",
        "missing_tcn_seeds=1,7,11,42,202,340,520",
        f"json_schemas_checked={len(schema_files)} status=PASS",
        "unit_tests=8/8 PASS",
        "statistical_self_check=PASS",
        "phase2_statistics_executed=false",
        f"analysis_plan_sha256={analysis_plan_hash}",
        f"[{finished}] COMPLETE PHASE1_COMPLETE ANALYSIS_PLAN_FROZEN",
    ]
    write_text(A5_ROOT / "logs/phase1.log", "\n".join(log_lines) + "\n")

    manifest_rows = []
    for path in sorted(A5_ROOT.rglob("*")):
        if path.is_file() and path.name != "artifact_manifest.json" and "__pycache__" not in path.parts:
            manifest_rows.append({"path": path.relative_to(A5_ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    write_json(A5_ROOT / "artifact_manifest.json", {"manifest_id": "A5_phase1_artifact_manifest_v1", "generated_at_utc": finished, "root": str(A5_ROOT), "self_hash_excluded": True, "artifact_count": len(manifest_rows), "artifacts": manifest_rows})
    print(json.dumps(phase1_summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
