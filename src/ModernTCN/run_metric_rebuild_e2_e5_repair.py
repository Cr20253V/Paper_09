"""Audit and repair E2/E5 evidence contracts before metric rebuild.

This runner is intentionally conservative.  It does not rescue failed SCI
experiments, export ONNX, run MATLAB/Simulink, or write formal compare results.
Its primary job is to decide whether old E2/E5 evidence is usable, advisory, or
contract-limited for the new control-oriented metric rebuild.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import h5py
import numpy as np

from modern_tcn_data import find_project_root


STATUS_PASS_REPAIRED = "PASS_REPAIRED"
STATUS_PASS_CONTRACT_LIMITED = "PASS_CONTRACT_LIMITED"
STATUS_FAIL_SCRIPT_OR_ARTIFACT = "FAIL_SCRIPT_OR_ARTIFACT"

DATASET_REL = (
    Path("data")
    / "tcn"
    / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
)
CURRENT_DATASET_REL = Path("data") / "tcn" / "CURRENT_ModernTCN_DATASET.json"
E2_DECISION_REL = (
    Path("results")
    / "modern_tcn_sci_innovation"
    / "02_hard_sample_loss"
    / "hard_sample_loss_decision.json"
)
E5_DECISION_REL = (
    Path("results")
    / "modern_tcn_sci_innovation"
    / "05_confidence_scheduling"
    / "confidence_scheduling_decision.json"
)
E5_CACHE_REL = (
    Path("results")
    / "modern_tcn_sci_innovation"
    / "05_confidence_scheduling"
    / "baseline_prediction_cache.npz"
)
E5_CACHE_META_REL = (
    Path("results")
    / "modern_tcn_sci_innovation"
    / "05_confidence_scheduling"
    / "baseline_prediction_cache_meta.json"
)
METRIC_ROOT_REL = Path("results") / "modern_tcn_metric_rebuild"
DEFAULT_OUTPUT_REL = METRIC_ROOT_REL / "00_replay_contract_repair"

REQUIRED_REPLAY_FIELDS = [
    "sample_id",
    "run_id",
    "segment_id",
    "window_start_idx",
    "window_end_idx",
    "global_time_idx",
    "sample_time",
    "split",
    "path_id",
    "scenario_id",
    "label_time_policy",
    "is_contiguous_next",
]
SPLITS = ["train", "val", "test"]
SCHEDULED_E5_METRICS = [
    "theta_sched_mae_deg",
    "theta_sched_flat_peak_error",
    "theta_sched_edge_p95_abs_err",
    "theta_sched_smoothness",
    "theta_sched_step_p95",
    "theta_sched_jump_p95",
    "theta_step",
    "theta_jump",
]


@dataclass(frozen=True)
class SplitContract:
    split: str
    metadata_level: str
    has_run_id: bool
    has_window_start_idx: bool
    has_window_end_idx: bool
    has_global_time_idx: bool
    has_sample_time: bool
    has_dt_sec: bool
    row_count: int
    reason: str


@dataclass(frozen=True)
class RepairContext:
    root: Path
    metric_root: Path
    output_root: Path
    e2_root: Path
    e5_root: Path
    dataset_file: Path
    max_smoke_windows: int
    regression_tol: float
    regression_tol_max: float


@dataclass(frozen=True)
class SchedulingSpec:
    tag: str
    confidence_mode: str
    conf_threshold: float
    delta_theta_max_deg_per_step: float
    offline_only: bool = False


E5_SPECS = [
    SchedulingSpec("cs_main_c06_d01", "main_conf", 0.6, 0.1),
    SchedulingSpec("cs_main_c06_d02", "main_conf", 0.6, 0.2),
    SchedulingSpec("cs_main_c07_d01", "main_conf", 0.7, 0.1),
    SchedulingSpec("cs_mainturn_c06_d01", "main_turn_conf", 0.6, 0.1),
    SchedulingSpec("rate_limit_only_d01", "rate_limit_only", 0.0, 0.1, offline_only=True),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit/repair E2/E5 evidence contracts for metric rebuild.")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_REL)
    parser.add_argument("--no-overwrite", action="store_true")
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max-smoke-windows", type=int, default=0)
    parser.add_argument("--regression-tol", type=float, default=1e-5)
    parser.add_argument("--regression-tol-max", type=float, default=1e-4)
    args = parser.parse_args()

    root = find_project_root()
    output_root = resolve_output_root(root, args.output_root)
    metric_root = output_root.parent if output_root.name == "00_replay_contract_repair" else root / METRIC_ROOT_REL
    ctx = RepairContext(
        root=root,
        metric_root=metric_root.resolve(),
        output_root=output_root.resolve(),
        e2_root=(metric_root / "02_e2_smooth_fixed").resolve(),
        e5_root=(metric_root / "05_e5_replay_fixed").resolve(),
        dataset_file=(root / DATASET_REL).resolve(),
        max_smoke_windows=max(0, int(args.max_smoke_windows)),
        regression_tol=float(args.regression_tol),
        regression_tol_max=float(args.regression_tol_max),
    )
    ensure_output_scope(root, ctx)

    if args.dry_run:
        result = run_workflow(ctx, write_outputs=False, audit_only=True)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0

    if args.no_overwrite:
        enforce_no_overwrite([ctx.output_root, ctx.e2_root, ctx.e5_root])

    for path in [ctx.output_root, ctx.e2_root, ctx.e5_root]:
        path.mkdir(parents=True, exist_ok=True)

    try:
        result = run_workflow(ctx, write_outputs=True, audit_only=bool(args.audit_only))
    except Exception as exc:
        write_failure_report(ctx, exc)
        raise

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


def run_workflow(ctx: RepairContext, write_outputs: bool, audit_only: bool) -> Dict[str, object]:
    required = {
        "dataset": ctx.dataset_file,
        "current_dataset_pointer": ctx.root / CURRENT_DATASET_REL,
        "e2_decision": ctx.root / E2_DECISION_REL,
        "e5_decision": ctx.root / E5_DECISION_REL,
    }
    missing = [f"{name}: {path}" for name, path in required.items() if not path.exists()]
    if missing:
        decision = {
            "repair_status": STATUS_FAIL_SCRIPT_OR_ARTIFACT,
            "reason": "required artifacts are missing",
            "missing": missing,
        }
        if write_outputs:
            write_common_contract_outputs(ctx, [], [], [], [], decision)
            write_e2_not_run_decision(ctx, STATUS_FAIL_SCRIPT_OR_ARTIFACT, "required artifacts are missing")
            write_e5_not_run_decision(ctx, STATUS_FAIL_SCRIPT_OR_ARTIFACT, "required artifacts are missing")
        return decision

    e2_decision = read_json(ctx.root / E2_DECISION_REL)
    e5_decision = read_json(ctx.root / E5_DECISION_REL)
    audit_rows, split_contracts = audit_replay_contract(ctx.dataset_file)
    invalid_rows = build_invalid_evidence_registry(ctx, e2_decision, e5_decision)

    test_contract = next((x for x in split_contracts if x.split == "test"), None)
    all_split_replay = all(is_replay_level_ok(x.metadata_level) for x in split_contracts)
    test_replay_ok = bool(test_contract and is_replay_level_ok(test_contract.metadata_level))

    manifest_rows: List[Dict[str, object]] = []
    segment_rows: List[Dict[str, object]] = []
    pair_rows: List[Dict[str, object]] = []
    baseline_result: Dict[str, object] = {}
    e5_result: Dict[str, object] = {}
    e2_result: Dict[str, object] = {}

    if test_replay_ok:
        manifest_rows, segment_rows = build_test_replay_manifest(ctx, test_contract.metadata_level)
        if ctx.max_smoke_windows > 0:
            manifest_rows = manifest_rows[: ctx.max_smoke_windows]
            segment_rows = summarize_manifest_segments(manifest_rows)

    if not manifest_rows:
        decision = {
            "repair_status": STATUS_PASS_CONTRACT_LIMITED,
            "manifest_available": False,
            "reason": "current dataset does not expose auditable test replay continuity metadata",
            "test_metadata_level": test_contract.metadata_level if test_contract else "missing_test_split",
            "metric_rebuild_can_continue": True,
            "e5_replay_fixed_status": "not_run_contract_limited",
            "e2_smooth_fixed_status": "not_run_contract_limited",
        }
        if write_outputs:
            write_common_contract_outputs(ctx, audit_rows, split_contracts, manifest_rows, segment_rows, decision)
            write_invalid_evidence_registry(ctx, invalid_rows)
            write_e5_not_run_decision(ctx, STATUS_PASS_CONTRACT_LIMITED, decision["reason"])
            write_e2_not_run_decision(ctx, STATUS_PASS_CONTRACT_LIMITED, decision["reason"])
            write_final_report(ctx, decision, split_contracts, baseline_result, e5_result, e2_result)
        return decision

    if audit_only:
        decision = {
            "repair_status": STATUS_PASS_REPAIRED,
            "manifest_available": True,
            "audit_only": True,
            "metric_rebuild_can_continue": True,
            "test_metadata_level": test_contract.metadata_level if test_contract else "",
        }
        if write_outputs:
            write_common_contract_outputs(ctx, audit_rows, split_contracts, manifest_rows, segment_rows, decision)
            write_invalid_evidence_registry(ctx, invalid_rows)
            write_e5_not_run_decision(ctx, STATUS_PASS_REPAIRED, "--audit-only was used")
            write_e2_not_run_decision(ctx, STATUS_PASS_REPAIRED, "--audit-only was used")
            write_final_report(ctx, decision, split_contracts, baseline_result, e5_result, e2_result)
        return decision

    baseline_result = run_baseline_replay(ctx, manifest_rows)
    if baseline_result["repair_status"] == STATUS_FAIL_SCRIPT_OR_ARTIFACT:
        decision = {
            "repair_status": STATUS_FAIL_SCRIPT_OR_ARTIFACT,
            "manifest_available": True,
            "reason": baseline_result["reason"],
            "metric_rebuild_can_continue": False,
            "e5_replay_fixed_status": "not_run_baseline_regression_failed",
            "e2_smooth_fixed_status": "not_run_baseline_regression_failed",
        }
        if write_outputs:
            write_common_contract_outputs(ctx, audit_rows, split_contracts, manifest_rows, segment_rows, decision)
            write_invalid_evidence_registry(ctx, invalid_rows)
            write_baseline_replay_outputs(ctx, manifest_rows, baseline_result)
            write_e5_not_run_decision(ctx, STATUS_FAIL_SCRIPT_OR_ARTIFACT, baseline_result["reason"])
            write_e2_not_run_decision(ctx, STATUS_FAIL_SCRIPT_OR_ARTIFACT, baseline_result["reason"])
            write_final_report(ctx, decision, split_contracts, baseline_result, e5_result, e2_result)
        return decision

    e5_result = run_e5_replay_fixed(ctx, manifest_rows, baseline_result)
    if all_split_replay:
        pair_rows = build_training_pair_registry(ctx, split_contracts)
        e2_result = {
            "repair_status": STATUS_PASS_CONTRACT_LIMITED,
            "e2_smooth_fixed_status": "not_run_pair_aware_training_not_enabled",
            "reason": "continuous metadata exists, but this runner only audits pair eligibility; pair-aware training must be enabled before running E2 smooth-fixed",
            "valid_pair_count": int(sum(1 for row in pair_rows if truthy(row.get("is_contiguous_pair")))),
        }
    else:
        e2_result = {
            "repair_status": STATUS_PASS_CONTRACT_LIMITED,
            "e2_smooth_fixed_status": "not_run_contract_limited",
            "reason": "train/val/test do not all expose replay-contiguous metadata",
            "train_val_test_metadata_levels": {x.split: x.metadata_level for x in split_contracts},
        }

    final_status = STATUS_PASS_REPAIRED if e5_result.get("repair_status") == STATUS_PASS_REPAIRED else STATUS_PASS_CONTRACT_LIMITED
    decision = {
        "repair_status": final_status,
        "manifest_available": True,
        "metric_rebuild_can_continue": True,
        "test_metadata_level": test_contract.metadata_level if test_contract else "",
        "all_split_replay_available": all_split_replay,
        "baseline_replay_status": baseline_result["repair_status"],
        "e5_replay_fixed_status": e5_result.get("e5_replay_fixed_status", ""),
        "e2_smooth_fixed_status": e2_result.get("e2_smooth_fixed_status", ""),
    }
    if write_outputs:
        write_common_contract_outputs(ctx, audit_rows, split_contracts, manifest_rows, segment_rows, decision)
        write_invalid_evidence_registry(ctx, invalid_rows)
        write_baseline_replay_outputs(ctx, manifest_rows, baseline_result)
        write_e5_replay_outputs(ctx, e5_result)
        write_e2_not_run_decision(ctx, e2_result["repair_status"], e2_result["reason"], extra=e2_result)
        if pair_rows:
            write_csv(ctx.e2_root / "e2_smooth_pair_registry.csv", pair_rows)
        write_final_report(ctx, decision, split_contracts, baseline_result, e5_result, e2_result)
    return decision


def audit_replay_contract(dataset_file: Path) -> Tuple[List[Dict[str, object]], List[SplitContract]]:
    rows: List[Dict[str, object]] = []
    split_contracts: List[SplitContract] = []
    with h5py.File(dataset_file, "r") as f:
        root = f["dataset"]
        for split in SPLITS:
            row_count = infer_split_row_count(root, split)
            split_contract = make_split_contract(root, split, row_count)
            split_contracts.append(split_contract)
            for field in REQUIRED_REPLAY_FIELDS:
                exists, source, notes = field_exists(root, split, field)
                repair_needed = not exists
                rows.append(
                    {
                        "split": split,
                        "field_name": field,
                        "exists": bool(exists),
                        "source_file": str(dataset_file),
                        "source_dataset": source,
                        "repair_needed": bool(repair_needed),
                        "metadata_level": split_contract.metadata_level,
                        "notes": notes,
                    }
                )
    return rows, split_contracts


def make_split_contract(root: h5py.Group, split: str, row_count: int) -> SplitContract:
    has_run_id = dataset_has(root, f"run_id_{split}")
    has_start = dataset_has(root, f"window_start_idx_{split}")
    has_end = dataset_has(root, f"window_end_idx_{split}")
    has_global_time = dataset_has(root, f"global_time_idx_{split}")
    has_sample_time = dataset_has(root, f"sample_time_{split}")
    has_dt = dataset_has(root, f"dt_sec_{split}") or dataset_has(root, f"dt_{split}")

    if has_run_id and has_start and has_end and (has_global_time or has_sample_time or has_dt):
        level = "level2_time_contiguous"
        reason = "run/window/time metadata present"
    elif has_run_id and has_start and has_end:
        level = "level1_window_contiguous"
        reason = "run/window metadata present; time metadata absent"
    else:
        level = "level0_invalid"
        if has_run_id:
            reason = "run_id exists, but window_start_idx/window_end_idx are absent"
        else:
            reason = "run_id and window metadata are absent"

    return SplitContract(
        split=split,
        metadata_level=level,
        has_run_id=has_run_id,
        has_window_start_idx=has_start,
        has_window_end_idx=has_end,
        has_global_time_idx=has_global_time,
        has_sample_time=has_sample_time,
        has_dt_sec=has_dt,
        row_count=row_count,
        reason=reason,
    )


def field_exists(root: h5py.Group, split: str, field: str) -> Tuple[bool, str, str]:
    split_name = f"{field}_{split}"
    if dataset_has(root, split_name):
        return True, f"dataset/{split_name}", "per-window split field"
    if field == "run_id" and dataset_has(root, f"run_id_{split}"):
        return True, f"dataset/run_id_{split}", "per-window run id exists"
    if field == "label_time_policy":
        if dataset_has(root, "meta/label_time_policy"):
            return True, "dataset/meta/label_time_policy", "dataset-level contract field"
        if dataset_has(root, "contract/label_time_policy"):
            return True, "dataset/contract/label_time_policy", "dataset-level contract field"
    if field == "split":
        return False, "", "split is implicit in *_train/val/test arrays, not stored as per-window metadata"
    if field in {"path_id", "scenario_id"}:
        source = "dataset/run_table/path_file" if field == "path_id" else "dataset/run_table/scene"
        if dataset_has(root, source.replace("dataset/", "")):
            return False, source, "run-level source exists, but no per-window replay metadata links it safely"
    return False, "", "missing from current dataset contract"


def build_test_replay_manifest(ctx: RepairContext, metadata_level: str) -> Tuple[List[Dict[str, object]], List[Dict[str, object]]]:
    with h5py.File(ctx.dataset_file, "r") as f:
        root = f["dataset"]
        split = "test"
        run_id = read_vector(root[f"run_id_{split}"])
        start_idx = read_vector(root[f"window_start_idx_{split}"])
        end_idx = read_vector(root[f"window_end_idx_{split}"])
        y_main = read_vector(root[f"y_main_{split}"])
        y_turn = read_vector(root[f"y_turn_{split}"])
        theta_true = read_vector(root[f"y_theta_{split}"])
        sample_id = optional_vector(root, f"sample_id_{split}", fill=np.nan, length=run_id.size)
        global_time = optional_vector(root, f"global_time_idx_{split}", fill=np.nan, length=run_id.size)
        sample_time = optional_vector(root, f"sample_time_{split}", fill=np.nan, length=run_id.size)
        dt_sec_values = optional_vector(root, f"dt_sec_{split}", fill=np.nan, length=run_id.size)

    order = np.lexsort((end_idx, start_idx, run_id))
    rows: List[Dict[str, object]] = []
    current_segment = -1
    prev_pos: Optional[int] = None
    expected_step_by_run = expected_step_map(run_id, start_idx)

    for out_idx, pos_np in enumerate(order):
        pos = int(pos_np)
        if prev_pos is None or run_id[pos] != run_id[prev_pos]:
            current_segment += 1
            contiguous_prev = False
            reason = "segment_start"
            dt_sec = float("nan")
        else:
            start_delta = float(start_idx[pos] - start_idx[prev_pos])
            end_delta = float(end_idx[pos] - end_idx[prev_pos])
            expected = expected_step_by_run.get(float(run_id[pos]), float("nan"))
            contiguous_prev = bool(start_delta > 0 and end_delta > 0)
            if np.isfinite(expected) and expected > 0:
                contiguous_prev = bool(contiguous_prev and abs(start_delta - expected) <= max(1e-9, 0.05 * expected))
            reason = (
                f"same_run_monotonic_window_delta={start_delta:g}"
                if contiguous_prev
                else f"noncontiguous_or_unexpected_window_delta={start_delta:g}"
            )
            if np.isfinite(sample_time[pos]) and np.isfinite(sample_time[prev_pos]):
                dt_sec = float(sample_time[pos] - sample_time[prev_pos])
            elif np.isfinite(dt_sec_values[pos]):
                dt_sec = float(dt_sec_values[pos])
            else:
                dt_sec = float("nan")
            if not contiguous_prev:
                current_segment += 1
        rows.append(
            {
                "replay_segment_id": current_segment,
                "run_id": clean_scalar(run_id[pos]),
                "sample_id": clean_scalar(sample_id[pos]),
                "window_start_idx": clean_scalar(start_idx[pos]),
                "window_end_idx": clean_scalar(end_idx[pos]),
                "global_time_idx": clean_scalar(global_time[pos]),
                "sample_time": clean_scalar(sample_time[pos]),
                "is_first_in_segment": not contiguous_prev,
                "is_last_in_segment": False,
                "is_contiguous_prev": contiguous_prev,
                "is_contiguous_next": False,
                "main_label": clean_scalar(y_main[pos]),
                "turn_label": clean_scalar(y_turn[pos]),
                "theta_true": clean_scalar(theta_true[pos]),
                "split": split,
                "original_row_index": pos,
                "prediction_row_index": pos,
                "source_file": str(ctx.dataset_file),
                "metadata_level": metadata_level,
                "contiguity_reason": reason,
                "dt_sec": clean_scalar(dt_sec),
            }
        )
        prev_pos = pos

    for idx, row in enumerate(rows):
        is_next = bool(idx + 1 < len(rows) and rows[idx + 1]["is_contiguous_prev"])
        row["is_contiguous_next"] = is_next
        row["is_last_in_segment"] = not is_next

    return rows, summarize_manifest_segments(rows)


def summarize_manifest_segments(manifest_rows: Sequence[Dict[str, object]]) -> List[Dict[str, object]]:
    by_segment: Dict[int, List[Dict[str, object]]] = {}
    for row in manifest_rows:
        by_segment.setdefault(int(row["replay_segment_id"]), []).append(row)
    out = []
    for seg, rows in sorted(by_segment.items()):
        run_ids = sorted({str(row["run_id"]) for row in rows})
        contiguous_steps = sum(1 for row in rows if truthy(row.get("is_contiguous_prev")))
        out.append(
            {
                "replay_segment_id": seg,
                "run_id": ";".join(run_ids),
                "n_windows": len(rows),
                "valid_contiguous_step_count": contiguous_steps,
                "first_original_row_index": rows[0]["original_row_index"],
                "last_original_row_index": rows[-1]["original_row_index"],
                "metadata_level": rows[0].get("metadata_level", ""),
            }
        )
    return out


def run_baseline_replay(ctx: RepairContext, manifest_rows: Sequence[Dict[str, object]]) -> Dict[str, object]:
    cache_file = ctx.root / E5_CACHE_REL
    cache_meta_file = ctx.root / E5_CACHE_META_REL
    if not cache_file.exists() or not cache_meta_file.exists():
        return {
            "repair_status": STATUS_FAIL_SCRIPT_OR_ARTIFACT,
            "reason": "baseline prediction cache is missing; automatic baseline inference is not enabled in this repair runner",
        }

    meta = read_json(cache_meta_file)
    cache = np.load(cache_file)
    n_cache = int(np.asarray(cache["theta_raw_deg"]).reshape(-1).size)
    max_idx = max(int(row["prediction_row_index"]) for row in manifest_rows) if manifest_rows else -1
    if max_idx >= n_cache:
        return {
            "repair_status": STATUS_FAIL_SCRIPT_OR_ARTIFACT,
            "reason": f"manifest prediction index {max_idx} exceeds cache rows {n_cache}",
        }

    idx = np.asarray([int(row["prediction_row_index"]) for row in manifest_rows], dtype=np.int64)
    theta_raw = np.asarray(cache["theta_raw_deg"], dtype=np.float64).reshape(-1)[idx]
    theta_true = np.asarray(cache["theta_true_deg"], dtype=np.float64).reshape(-1)[idx]
    y_main = np.asarray(cache["y_main"]).reshape(-1)[idx]
    y_turn = np.asarray(cache["y_turn"]).reshape(-1)[idx]
    turn_transition = np.asarray(cache["turn_transition"]).reshape(-1).astype(bool)[idx]
    mask_theta = np.asarray(cache["mask_theta"]).reshape(-1).astype(bool)[idx]
    logits_main = np.asarray(cache["logits_main"])[idx]
    logits_turn = np.asarray(cache["logits_turn"])[idx]

    pred_main = softmax_np(logits_main).argmax(axis=1)
    pred_turn = softmax_np(logits_turn).argmax(axis=1)
    y_turn_cls = y_turn.reshape(-1).astype(int)
    contiguous_mask = np.asarray([truthy(row.get("is_contiguous_prev")) for row in manifest_rows], dtype=bool)
    step_values = contiguous_diffs(theta_raw, contiguous_mask)
    slope_mask = mask_theta
    flat_mask = y_main == 0
    edge_mask = slope_mask & (np.abs(theta_true) >= 8.0) & (np.abs(theta_true) <= 10.0)

    metrics = {
        "theta_mae_deg": finite_mean(np.abs(theta_raw[slope_mask] - theta_true[slope_mask])),
        "theta_edge_p95_abs_err": finite_percentile(np.abs(theta_raw[edge_mask] - theta_true[edge_mask]), 95),
        "flat_peak_theta_error": finite_max(np.abs(theta_raw[flat_mask])),
        "theta_jump_p95": finite_percentile(step_values, 95),
        "theta_step_p95": finite_percentile(step_values, 95),
        "turn_transition_acc": masked_acc(pred_turn, y_turn_cls, turn_transition),
        "stall_recall": recall_for_class(pred_main, y_main.astype(int), 1),
        "segment_count": len({int(row["replay_segment_id"]) for row in manifest_rows}),
        "valid_contiguous_step_count": int(np.sum(contiguous_mask)),
    }
    regression = baseline_regression(metrics, meta.get("baseline_metrics", {}), ctx.regression_tol, ctx.regression_tol_max)
    return {
        "repair_status": STATUS_PASS_REPAIRED if regression["pass"] else STATUS_FAIL_SCRIPT_OR_ARTIFACT,
        "reason": "baseline replay regression passed" if regression["pass"] else "baseline replay regression failed",
        "metrics": clean_json(metrics),
        "regression": clean_json(regression),
        "cache_file": str(cache_file),
        "cache_meta_file": str(cache_meta_file),
    }


def run_e5_replay_fixed(
    ctx: RepairContext,
    manifest_rows: Sequence[Dict[str, object]],
    baseline_result: Dict[str, object],
) -> Dict[str, object]:
    cache = np.load(ctx.root / E5_CACHE_REL)
    idx = np.asarray([int(row["prediction_row_index"]) for row in manifest_rows], dtype=np.int64)
    theta_raw = np.asarray(cache["theta_raw_deg"], dtype=np.float64).reshape(-1)[idx]
    theta_true = np.asarray(cache["theta_true_deg"], dtype=np.float64).reshape(-1)[idx]
    y_main = np.asarray(cache["y_main"]).reshape(-1)[idx]
    mask_theta = np.asarray(cache["mask_theta"]).reshape(-1).astype(bool)[idx]
    logits_main = np.asarray(cache["logits_main"])[idx]
    logits_turn = np.asarray(cache["logits_turn"])[idx]
    contiguous_prev = np.asarray([truthy(row.get("is_contiguous_prev")) for row in manifest_rows], dtype=bool)
    segment_id = np.asarray([int(row["replay_segment_id"]) for row in manifest_rows], dtype=np.int64)

    rows: List[Dict[str, object]] = []
    for spec in E5_SPECS:
        sched, flags = apply_manifest_scheduling(theta_raw, logits_main, logits_turn, segment_id, contiguous_prev, spec)
        row = e5_replay_metrics(spec, theta_raw, sched, theta_true, y_main, mask_theta, contiguous_prev, flags, baseline_result)
        rows.append(row)
    safe_rows = [row for row in rows if truthy(row.get("replay_safe"))]
    return {
        "repair_status": STATUS_PASS_REPAIRED,
        "e5_replay_fixed_status": "class_b_replay_safe" if safe_rows else "negative_no_safe_replay_config",
        "class_b_candidates": [row["run_tag"] for row in safe_rows],
        "metrics_rows": clean_json(rows),
        "decision_reason": "safe replay configs found" if safe_rows else "no replay-fixed E5 config passed safety screen",
    }


def e5_replay_metrics(
    spec: SchedulingSpec,
    theta_raw: np.ndarray,
    theta_sched: np.ndarray,
    theta_true: np.ndarray,
    y_main: np.ndarray,
    mask_theta: np.ndarray,
    contiguous_prev: np.ndarray,
    flags: Dict[str, np.ndarray],
    baseline_result: Dict[str, object],
) -> Dict[str, object]:
    slope_mask = mask_theta.astype(bool)
    flat_mask = y_main == 0
    edge_mask = slope_mask & (np.abs(theta_true) >= 8.0) & (np.abs(theta_true) <= 10.0)
    raw_err = np.abs(theta_raw - theta_true)
    sched_err = np.abs(theta_sched - theta_true)
    raw_steps = contiguous_diffs(theta_raw, contiguous_prev)
    sched_steps = contiguous_diffs(theta_sched, contiguous_prev)
    raw_mae = finite_mean(raw_err[slope_mask])
    sched_mae = finite_mean(sched_err[slope_mask])
    raw_flat_peak = finite_max(np.abs(theta_raw[flat_mask]))
    sched_flat_peak = finite_max(np.abs(theta_sched[flat_mask]))
    raw_edge = finite_percentile(raw_err[edge_mask], 95)
    sched_edge = finite_percentile(sched_err[edge_mask], 95)
    replay_safe = (
        sched_mae <= raw_mae + 0.010
        and sched_flat_peak <= raw_flat_peak + 0.300
        and sched_edge <= raw_edge + 0.300
        and finite_percentile(sched_steps, 95) <= finite_percentile(raw_steps, 95)
    )
    return {
        "run_tag": spec.tag,
        "confidence_mode": spec.confidence_mode,
        "conf_threshold": spec.conf_threshold,
        "delta_theta_max_deg_per_step": spec.delta_theta_max_deg_per_step,
        "theta_raw_mae_deg": raw_mae,
        "theta_sched_mae_deg": sched_mae,
        "theta_raw_flat_peak_error": raw_flat_peak,
        "theta_sched_flat_peak_error": sched_flat_peak,
        "theta_raw_edge_p95_abs_err": raw_edge,
        "theta_sched_edge_p95_abs_err": sched_edge,
        "theta_raw_step_p95": finite_percentile(raw_steps, 95),
        "theta_sched_step_p95": finite_percentile(sched_steps, 95),
        "theta_raw_jump_p95": finite_percentile(raw_steps, 95),
        "theta_sched_jump_p95": finite_percentile(sched_steps, 95),
        "rate_limit_hit_ratio": finite_mean(flags["rate_limit_hit"].astype(float)),
        "low_conf_ratio": finite_mean(flags["low_conf"].astype(float)),
        "valid_contiguous_step_count": int(np.sum(contiguous_prev)),
        "segment_reset_count": int(np.sum(flags["reset"].astype(bool))),
        "replay_safe": bool(replay_safe),
        "candidate_class": "Class B" if replay_safe else "negative",
        "formal_claim_allowed": False,
    }


def build_training_pair_registry(ctx: RepairContext, split_contracts: Sequence[SplitContract]) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    with h5py.File(ctx.dataset_file, "r") as f:
        root = f["dataset"]
        for contract in split_contracts:
            if not is_replay_level_ok(contract.metadata_level):
                continue
            split = contract.split
            run_id = read_vector(root[f"run_id_{split}"])
            start_idx = read_vector(root[f"window_start_idx_{split}"])
            end_idx = read_vector(root[f"window_end_idx_{split}"])
            order = np.lexsort((end_idx, start_idx, run_id))
            expected = expected_step_map(run_id, start_idx)
            pair_id = len(rows)
            prev: Optional[int] = None
            for pos_np in order:
                pos = int(pos_np)
                if prev is not None and run_id[pos] == run_id[prev]:
                    step = float(start_idx[pos] - start_idx[prev])
                    expected_step = expected.get(float(run_id[pos]), float("nan"))
                    valid = step > 0 and (not np.isfinite(expected_step) or abs(step - expected_step) <= max(1e-9, 0.05 * expected_step))
                    rows.append(
                        {
                            "pair_id": pair_id,
                            "split": split,
                            "prev_sample_id": f"{split}:{prev}",
                            "curr_sample_id": f"{split}:{pos}",
                            "prev_original_row_index": prev,
                            "curr_original_row_index": pos,
                            "same_segment": bool(run_id[pos] == run_id[prev]),
                            "is_contiguous_pair": bool(valid),
                            "contiguity_reason": f"window_start_delta={step:g}",
                        }
                    )
                    pair_id += 1
                prev = pos
    return rows


def build_invalid_evidence_registry(
    ctx: RepairContext,
    e2_decision: Dict[str, object],
    e5_decision: Dict[str, object],
) -> List[Dict[str, object]]:
    e2_artifact = ctx.root / E2_DECISION_REL
    e5_artifact = ctx.root / E5_DECISION_REL
    rows = [
        {
            "artifact": str(e2_artifact),
            "phase": "E2",
            "metric_or_claim": "theta_smoothness_claim",
            "validity": "invalid_not_run",
            "reason": f"theta_smooth_status={e2_decision.get('theta_smooth_status', '')}",
            "allowed_use": "not allowed for focal_plus_theta_smoothness ranking",
            "replacement_artifact": "results/modern_tcn_metric_rebuild/02_e2_smooth_fixed/e2_smooth_fixed_decision.json",
        },
        {
            "artifact": str(e2_artifact),
            "phase": "E2",
            "metric_or_claim": "focal_loss_metrics",
            "validity": "valid_focal_only",
            "reason": f"method_label={e2_decision.get('method_label', '')}",
            "allowed_use": "focal-only historical ranking",
            "replacement_artifact": "",
        },
    ]
    for metric_name in SCHEDULED_E5_METRICS:
        rows.append(
            {
                "artifact": str(e5_artifact),
                "phase": "E5",
                "metric_or_claim": metric_name,
                "validity": "advisory_only",
                "reason": "scheduled metric is stateful and old replay order is non-contiguous",
                "allowed_use": "historical advisory only; exclude from formal J_control/J_smooth_event",
                "replacement_artifact": "results/modern_tcn_metric_rebuild/05_e5_replay_fixed/e5_replay_fixed_decision.json",
            }
        )
    rows.append(
        {
            "artifact": str(ctx.root / E5_CACHE_META_REL),
            "phase": "E5",
            "metric_or_claim": "raw_baseline_order_independent_metrics",
            "validity": "valid_if_regression_passed",
            "reason": "raw baseline metrics do not depend on scheduled state order",
            "allowed_use": "baseline reference only after regression check",
            "replacement_artifact": "results/modern_tcn_metric_rebuild/00_replay_contract_repair/baseline_replay_metrics.csv",
        }
    )
    return rows


def write_common_contract_outputs(
    ctx: RepairContext,
    audit_rows: Sequence[Dict[str, object]],
    split_contracts: Sequence[SplitContract],
    manifest_rows: Sequence[Dict[str, object]],
    segment_rows: Sequence[Dict[str, object]],
    decision: Dict[str, object],
) -> None:
    write_csv(ctx.output_root / "replay_contract_audit.csv", audit_rows, fieldnames=[
        "split",
        "field_name",
        "exists",
        "source_file",
        "source_dataset",
        "repair_needed",
        "metadata_level",
        "notes",
    ])
    write_replay_contract_audit_md(ctx, split_contracts, audit_rows, decision)
    write_csv(ctx.output_root / "test_replay_manifest.csv", manifest_rows, fieldnames=[
        "replay_segment_id",
        "run_id",
        "sample_id",
        "window_start_idx",
        "window_end_idx",
        "global_time_idx",
        "sample_time",
        "is_first_in_segment",
        "is_last_in_segment",
        "is_contiguous_prev",
        "is_contiguous_next",
        "main_label",
        "turn_label",
        "theta_true",
        "split",
        "original_row_index",
        "prediction_row_index",
        "source_file",
        "metadata_level",
        "contiguity_reason",
        "dt_sec",
    ])
    write_csv(ctx.output_root / "test_replay_segments_summary.csv", segment_rows, fieldnames=[
        "replay_segment_id",
        "run_id",
        "n_windows",
        "valid_contiguous_step_count",
        "first_original_row_index",
        "last_original_row_index",
        "metadata_level",
    ])
    write_json(ctx.output_root / "repair_decision.json", clean_json(decision))


def write_replay_contract_audit_md(
    ctx: RepairContext,
    split_contracts: Sequence[SplitContract],
    audit_rows: Sequence[Dict[str, object]],
    decision: Dict[str, object],
) -> None:
    lines = [
        "# Replay Contract Audit",
        "",
        f"- generated_at: {now_iso()}",
        f"- dataset_file: `{ctx.dataset_file}`",
        f"- repair_status: `{decision.get('repair_status', '')}`",
        f"- metric_rebuild_can_continue: {decision.get('metric_rebuild_can_continue', '')}",
        "",
        "## Split Metadata Levels",
        "",
        "| split | metadata_level | rows | reason |",
        "|---|---|---:|---|",
    ]
    for item in split_contracts:
        lines.append(f"| {item.split} | `{item.metadata_level}` | {item.row_count} | {item.reason} |")
    missing = [row for row in audit_rows if not truthy(row.get("exists"))]
    lines.extend(
        [
            "",
            "## Missing Or Non-Per-Window Fields",
            "",
            "| split | field | repair_needed | notes |",
            "|---|---|---|---|",
        ]
    )
    for row in missing:
        lines.append(f"| {row['split']} | `{row['field_name']}` | {row['repair_needed']} | {row['notes']} |")
    (ctx.output_root / "replay_contract_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_invalid_evidence_registry(ctx: RepairContext, rows: Sequence[Dict[str, object]]) -> None:
    write_csv(ctx.output_root / "invalid_evidence_registry.csv", rows, fieldnames=[
        "artifact",
        "phase",
        "metric_or_claim",
        "validity",
        "reason",
        "allowed_use",
        "replacement_artifact",
    ])


def write_baseline_replay_outputs(
    ctx: RepairContext,
    manifest_rows: Sequence[Dict[str, object]],
    baseline_result: Dict[str, object],
) -> None:
    metrics = baseline_result.get("metrics", {})
    write_csv(ctx.output_root / "baseline_replay_metrics.csv", [metrics] if metrics else [])
    write_json(ctx.output_root / "baseline_replay_decision.json", clean_json(baseline_result))
    # Keep prediction output compact: it is an index-aligned trace, not a full logits dump.
    if baseline_result.get("repair_status") == STATUS_PASS_REPAIRED:
        cache = np.load(ctx.root / E5_CACHE_REL)
        idx = np.asarray([int(row["prediction_row_index"]) for row in manifest_rows], dtype=np.int64)
        theta_raw = np.asarray(cache["theta_raw_deg"], dtype=np.float64).reshape(-1)[idx]
        pred_rows = []
        for out_i, row in enumerate(manifest_rows):
            pred_rows.append(
                {
                    "replay_row_index": out_i,
                    "replay_segment_id": row["replay_segment_id"],
                    "prediction_row_index": row["prediction_row_index"],
                    "theta_raw_deg": clean_scalar(theta_raw[out_i]),
                    "theta_true": row["theta_true"],
                    "is_contiguous_prev": row["is_contiguous_prev"],
                }
            )
        write_csv(ctx.output_root / "baseline_replay_predictions.csv", pred_rows)
    lines = [
        "# Baseline Replay Report",
        "",
        f"- repair_status: `{baseline_result.get('repair_status', '')}`",
        f"- reason: {baseline_result.get('reason', '')}",
        "",
        "## Regression",
        "",
        "```json",
        json.dumps(clean_json(baseline_result.get("regression", {})), indent=2, ensure_ascii=False),
        "```",
    ]
    (ctx.output_root / "baseline_replay_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_e5_not_run_decision(ctx: RepairContext, status: str, reason: str) -> None:
    decision = {
        "phase": "E5_replay_fixed",
        "repair_status": status,
        "e5_replay_fixed_status": "not_run_contract_limited" if status == STATUS_PASS_CONTRACT_LIMITED else "not_run",
        "reason": reason,
        "scheduled_metrics_from_original_e5": "advisory_only",
        "formal_claim_allowed": False,
        "no_training": True,
        "no_onnx_export": True,
        "no_matlab_simulink": True,
        "no_formal_compare_write": True,
    }
    write_json(ctx.e5_root / "e5_replay_fixed_decision.json", decision)
    (ctx.e5_root / "e5_replay_fixed_summary.md").write_text(
        "\n".join(
            [
                "# E5 Replay-Fixed Summary",
                "",
                f"- repair_status: `{status}`",
                f"- status: `{decision['e5_replay_fixed_status']}`",
                f"- reason: {reason}",
                "- original E5 scheduled metrics: advisory_only",
                "- formal claim allowed: False",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    write_csv(ctx.e5_root / "e5_replay_fixed_metrics.csv", [])


def write_e5_replay_outputs(ctx: RepairContext, e5_result: Dict[str, object]) -> None:
    rows = e5_result.get("metrics_rows", [])
    write_csv(ctx.e5_root / "e5_replay_fixed_metrics.csv", rows)
    decision = {
        "phase": "E5_replay_fixed",
        "repair_status": e5_result.get("repair_status", STATUS_PASS_REPAIRED),
        "e5_replay_fixed_status": e5_result.get("e5_replay_fixed_status", ""),
        "class_b_candidates": e5_result.get("class_b_candidates", []),
        "decision_reason": e5_result.get("decision_reason", ""),
        "formal_claim_allowed": False,
        "no_training": True,
        "no_onnx_export": True,
        "no_matlab_simulink": True,
        "no_formal_compare_write": True,
    }
    write_json(ctx.e5_root / "e5_replay_fixed_decision.json", decision)
    lines = [
        "# E5 Replay-Fixed Summary",
        "",
        f"- repair_status: `{decision['repair_status']}`",
        f"- e5_replay_fixed_status: `{decision['e5_replay_fixed_status']}`",
        f"- class_b_candidates: {', '.join(decision['class_b_candidates']) if decision['class_b_candidates'] else '(none)'}",
        "- formal claim allowed: False",
        "",
        "## Metrics",
        "",
        "| run | replay_safe | theta_sched_mae | flat_peak | edge_p95 | step_p95 |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['run_tag']} | {row['replay_safe']} | {float(row['theta_sched_mae_deg']):.6g} | "
            f"{float(row['theta_sched_flat_peak_error']):.6g} | {float(row['theta_sched_edge_p95_abs_err']):.6g} | "
            f"{float(row['theta_sched_step_p95']):.6g} |"
        )
    (ctx.e5_root / "e5_replay_fixed_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_e2_not_run_decision(
    ctx: RepairContext,
    status: str,
    reason: str,
    extra: Optional[Dict[str, object]] = None,
) -> None:
    decision = {
        "phase": "E2_smooth_fixed",
        "repair_status": status,
        "e2_smooth_fixed_status": "not_run_contract_limited" if status == STATUS_PASS_CONTRACT_LIMITED else "not_run",
        "reason": reason,
        "original_e2_allowed_use": "hard-sample focal only",
        "theta_smoothness_claim": "invalid_not_run",
        "formal_claim_allowed": False,
        "no_onnx_export": True,
        "no_matlab_simulink": True,
        "no_formal_compare_write": True,
    }
    if extra:
        decision.update(clean_json(extra))
    write_json(ctx.e2_root / "e2_smooth_fixed_decision.json", decision)
    write_csv(ctx.e2_root / "e2_smooth_fixed_metrics.csv", [])
    lines = [
        "# E2 Smooth-Fixed Summary",
        "",
        f"- repair_status: `{decision['repair_status']}`",
        f"- e2_smooth_fixed_status: `{decision['e2_smooth_fixed_status']}`",
        f"- reason: {decision['reason']}",
        "- original E2 allowed use: hard-sample focal only",
        "- theta smoothness claim: invalid_not_run",
    ]
    (ctx.e2_root / "e2_smooth_fixed_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_final_report(
    ctx: RepairContext,
    decision: Dict[str, object],
    split_contracts: Sequence[SplitContract],
    baseline_result: Dict[str, object],
    e5_result: Dict[str, object],
    e2_result: Dict[str, object],
) -> None:
    levels = {item.split: item.metadata_level for item in split_contracts}
    lines = [
        "# E2/E5 Repair Final Report",
        "",
        f"- generated_at: {now_iso()}",
        f"- repair_status: `{decision.get('repair_status', '')}`",
        f"- metric_rebuild_can_continue: {decision.get('metric_rebuild_can_continue', '')}",
        f"- dataset_file: `{ctx.dataset_file}`",
        "",
        "## Answers",
        "",
        f"1. Current data supports continuous replay: {bool(decision.get('manifest_available', False))}.",
        f"2. Original E2 is not full focal + smoothness because theta smoothness was disabled by contract; allowed use is focal-only.",
        "3. Original E5 cannot enter formal control-oriented ranking because every scheduled metric depends on previous scheduled state and the old replay order is not auditable.",
        f"4. test_replay_manifest generated with rows: {count_csv_rows(ctx.output_root / 'test_replay_manifest.csv') if (ctx.output_root / 'test_replay_manifest.csv').exists() else 0}.",
        f"5. Baseline replay status: `{baseline_result.get('repair_status', 'not_run')}`.",
        f"6. E5 replay-fixed status: `{e5_result.get('e5_replay_fixed_status', decision.get('e5_replay_fixed_status', 'not_run'))}`.",
        f"7. E2 smooth-fixed status: `{e2_result.get('e2_smooth_fixed_status', decision.get('e2_smooth_fixed_status', 'not_run'))}`.",
        "8. Candidates allowed into metric rebuild are governed by invalid_evidence_registry.csv.",
        "9. Original E5 scheduled evidence is advisory_only; original E2 smoothness evidence is invalid/not_run.",
        "",
        "## Metadata Levels",
        "",
        "```json",
        json.dumps(levels, indent=2, ensure_ascii=False),
        "```",
        "",
        "## Decision",
        "",
        "```json",
        json.dumps(clean_json(decision), indent=2, ensure_ascii=False),
        "```",
    ]
    (ctx.output_root / "e2_e5_repair_final_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_failure_report(ctx: RepairContext, exc: BaseException) -> None:
    ctx.output_root.mkdir(parents=True, exist_ok=True)
    decision = {
        "repair_status": STATUS_FAIL_SCRIPT_OR_ARTIFACT,
        "reason": str(exc),
        "traceback": traceback.format_exc(),
        "metric_rebuild_can_continue": False,
    }
    write_json(ctx.output_root / "repair_decision.json", decision)
    lines = [
        "# E2/E5 Repair Failure Report",
        "",
        f"- generated_at: {now_iso()}",
        f"- repair_status: `{STATUS_FAIL_SCRIPT_OR_ARTIFACT}`",
        f"- reason: {exc}",
        "",
        "```text",
        traceback.format_exc(),
        "```",
    ]
    (ctx.output_root / "failure_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def apply_manifest_scheduling(
    theta_raw: np.ndarray,
    logits_main: np.ndarray,
    logits_turn: np.ndarray,
    segment_id: np.ndarray,
    contiguous_prev: np.ndarray,
    spec: SchedulingSpec,
) -> Tuple[np.ndarray, Dict[str, np.ndarray]]:
    confidence_pack = confidence_from_logits(logits_main, logits_turn, spec.confidence_mode)
    confidence = confidence_pack["confidence"]
    n = theta_raw.size
    theta_sched = np.zeros(n, dtype=np.float64)
    low_conf = np.zeros(n, dtype=bool)
    rate_hit = np.zeros(n, dtype=bool)
    reset = np.zeros(n, dtype=bool)
    delta_max = float(spec.delta_theta_max_deg_per_step)
    for i in range(n):
        can_use_prev = bool(i > 0 and contiguous_prev[i] and segment_id[i] == segment_id[i - 1])
        if not can_use_prev:
            theta_sched[i] = theta_raw[i]
            reset[i] = True
            if spec.confidence_mode not in {"none", "rate_limit_only"}:
                low_conf[i] = confidence[i] < float(spec.conf_threshold)
            continue
        prev = theta_sched[i - 1]
        if spec.confidence_mode in {"none", "rate_limit_only"}:
            c = 1.0
        else:
            low_conf[i] = confidence[i] < float(spec.conf_threshold)
            c = 0.0 if low_conf[i] else confidence[i]
        blended = c * theta_raw[i] + (1.0 - c) * prev
        delta = blended - prev
        clipped = np.clip(delta, -delta_max, delta_max)
        theta_sched[i] = prev + clipped
        rate_hit[i] = bool(abs(delta - clipped) > 1e-12)
    return theta_sched, {"low_conf": low_conf, "rate_limit_hit": rate_hit, "reset": reset}


def confidence_from_logits(logits_main: np.ndarray, logits_turn: np.ndarray, mode: str) -> Dict[str, np.ndarray]:
    prob_main = softmax_np(logits_main)
    prob_turn = softmax_np(logits_turn)
    main_conf = np.max(prob_main, axis=1)
    turn_conf = np.max(prob_turn, axis=1)
    norm = str(mode).lower()
    if norm in {"main_conf", "main"}:
        conf = main_conf
    elif norm in {"main_turn_conf", "mainturn", "main_conf*turn_conf"}:
        conf = main_conf * turn_conf
    elif norm in {"none", "rate_limit_only"}:
        conf = np.ones_like(main_conf)
    else:
        raise ValueError(f"Unknown confidence mode: {mode}")
    return {"confidence": conf, "main_conf": main_conf, "turn_conf": turn_conf}


def baseline_regression(
    replay_metrics: Dict[str, float],
    baseline_metrics: Dict[str, object],
    tol: float,
    tol_max: float,
) -> Dict[str, object]:
    checks = [
        ("theta_mae_deg", "theta_mae_deg"),
        ("flat_peak_theta_error", "flat_peak_theta_error"),
        ("theta_edge_p95_abs_err", "theta_edge_p95_abs_err"),
        ("turn_transition_acc", "acc_turn_transition"),
        ("stall_recall", "stall_recall"),
    ]
    failures = []
    deltas = {}
    warnings = []
    for replay_key, baseline_key in checks:
        actual = to_float(replay_metrics.get(replay_key))
        expected = to_float(baseline_metrics.get(baseline_key))
        if not (np.isfinite(actual) and np.isfinite(expected)):
            warnings.append(f"{replay_key} or {baseline_key} is nan")
            continue
        delta = actual - expected
        deltas[f"{replay_key}_minus_{baseline_key}"] = delta
        if abs(delta) > tol_max:
            failures.append(f"{replay_key} delta {delta:g} exceeds max tolerance {tol_max:g}")
        elif abs(delta) > tol:
            warnings.append(f"{replay_key} delta {delta:g} exceeds strict tolerance {tol:g}")
    return {"pass": not failures, "failures": failures, "warnings": warnings, "deltas": clean_json(deltas)}


def expected_step_map(run_id: np.ndarray, start_idx: np.ndarray) -> Dict[float, float]:
    out: Dict[float, float] = {}
    for rid in np.unique(run_id):
        starts = np.sort(start_idx[run_id == rid])
        diffs = np.diff(starts)
        diffs = diffs[diffs > 0]
        if diffs.size:
            values, counts = np.unique(diffs, return_counts=True)
            out[float(rid)] = float(values[np.argmax(counts)])
        else:
            out[float(rid)] = float("nan")
    return out


def resolve_output_root(root: Path, output_root: Path) -> Path:
    output_root = Path(output_root)
    if not output_root.is_absolute():
        output_root = root / output_root
    return output_root.resolve()


def ensure_output_scope(root: Path, ctx: RepairContext) -> None:
    metric_root = (root / METRIC_ROOT_REL).resolve()
    for path in [ctx.output_root, ctx.e2_root, ctx.e5_root]:
        try:
            path.resolve().relative_to(metric_root)
        except ValueError as exc:
            raise RuntimeError(f"output path escapes metric rebuild root: {path}") from exc


def enforce_no_overwrite(paths: Sequence[Path]) -> None:
    blocked = []
    for path in paths:
        if path.exists() and any(path.iterdir()):
            blocked.append(str(path))
    if blocked:
        raise FileExistsError("--no-overwrite refused non-empty output directories: " + "; ".join(blocked))


def dataset_has(root: h5py.Group, key: str) -> bool:
    parts = [part for part in key.split("/") if part]
    obj = root
    for part in parts:
        if not isinstance(obj, h5py.Group) or part not in obj:
            return False
        obj = obj[part]
    return isinstance(obj, h5py.Dataset) or isinstance(obj, h5py.Group)


def infer_split_row_count(root: h5py.Group, split: str) -> int:
    key = f"run_id_{split}"
    if key in root:
        return int(np.asarray(root[key]).reshape(-1).size)
    x_key = f"X_{split}"
    if x_key in root:
        return int(root[x_key].shape[-1])
    return 0


def read_vector(ds: h5py.Dataset) -> np.ndarray:
    return np.asarray(ds).reshape(-1).copy()


def optional_vector(root: h5py.Group, key: str, fill: float, length: int) -> np.ndarray:
    if key in root:
        return read_vector(root[key])
    return np.full(length, fill, dtype=np.float64)


def is_replay_level_ok(level: str) -> bool:
    return level in {"level1_window_contiguous", "level2_time_contiguous"}


def softmax_np(logits: np.ndarray) -> np.ndarray:
    arr = np.asarray(logits, dtype=np.float64)
    arr = arr - np.max(arr, axis=1, keepdims=True)
    exp = np.exp(arr)
    return exp / np.sum(exp, axis=1, keepdims=True)


def contiguous_diffs(values: np.ndarray, contiguous_prev: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64).reshape(-1)
    mask = np.asarray(contiguous_prev).reshape(-1).astype(bool)
    if values.size <= 1:
        return np.zeros(0, dtype=np.float64)
    diffs = np.abs(values[1:] - values[:-1])
    valid = mask[1:]
    return diffs[valid]


def masked_acc(pred: np.ndarray, truth: np.ndarray, mask: np.ndarray) -> float:
    mask = np.asarray(mask).reshape(-1).astype(bool)
    if not np.any(mask):
        return float("nan")
    return float(np.mean(np.asarray(pred).reshape(-1)[mask] == np.asarray(truth).reshape(-1)[mask]))


def recall_for_class(pred: np.ndarray, truth: np.ndarray, cls: int) -> float:
    truth = np.asarray(truth).reshape(-1)
    pred = np.asarray(pred).reshape(-1)
    mask = truth == cls
    if not np.any(mask):
        return float("nan")
    return float(np.mean(pred[mask] == cls))


def finite_mean(values: Sequence[float]) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.mean(arr))


def finite_max(values: Sequence[float]) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.max(arr))


def finite_percentile(values: Sequence[float], pct: float) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.percentile(arr, pct))


def read_json(path: Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(clean_json(data), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_csv(
    path: Path,
    rows: Sequence[Dict[str, object]],
    fieldnames: Optional[Sequence[str]] = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    row_list = list(rows)
    if fieldnames is None:
        keys: List[str] = []
        for row in row_list:
            for key in row.keys():
                if key not in keys:
                    keys.append(key)
        fieldnames = keys
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(fieldnames), extrasaction="ignore")
        writer.writeheader()
        for row in row_list:
            writer.writerow({key: csv_scalar(row.get(key, "")) for key in fieldnames})


def count_csv_rows(path: Path) -> int:
    if not path.exists():
        return 0
    with path.open("r", encoding="utf-8", newline="") as f:
        return max(0, sum(1 for _ in csv.DictReader(f)))


def clean_json(obj):
    if isinstance(obj, dict):
        return {str(k): clean_json(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean_json(v) for v in obj]
    if isinstance(obj, tuple):
        return [clean_json(v) for v in obj]
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        value = float(obj)
        return value if math.isfinite(value) else None
    if isinstance(obj, float):
        return obj if math.isfinite(obj) else None
    if isinstance(obj, Path):
        return str(obj)
    return obj


def csv_scalar(value: object) -> object:
    if isinstance(value, (list, dict, tuple)):
        return json.dumps(clean_json(value), ensure_ascii=False)
    if isinstance(value, float) and not math.isfinite(value):
        return "NaN"
    if isinstance(value, np.generic):
        return csv_scalar(value.item())
    return value


def clean_scalar(value: object) -> object:
    if isinstance(value, np.generic):
        value = value.item()
    if isinstance(value, float) and not math.isfinite(value):
        return "NaN"
    return value


def to_float(value: object) -> float:
    try:
        if value is None:
            return float("nan")
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def truthy(value: object) -> bool:
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y"}
    return bool(value)


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


if __name__ == "__main__":
    sys.exit(main())
