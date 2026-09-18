"""Run SCI E5 confidence-aware scheduling filter workflow.

E5 is intentionally deployment-side only.  It reads the frozen baseline
ModernTCN-small checkpoint, caches test predictions, replays scheduling filters
offline, and writes a conservative decision.  It does not train, export ONNX,
or write formal closed-loop comparison outputs.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import traceback
from dataclasses import asdict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import numpy as np
import torch
from torch.utils.data import DataLoader

from confidence_scheduling import (
    SchedulingResult,
    SchedulingSpec,
    apply_confidence_scheduling,
    confidence_distribution,
    confidence_from_logits,
    finite_max,
    finite_mean,
    finite_percentile,
    row_order_segment_audit,
    step_abs_diffs_by_segment,
)
from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics
from modern_tcn_model import build_model_from_checkpoint_dict
from train_modern_tcn import _build_config, _select_device, _to_device


DATASET_REL = Path("data") / "tcn" / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
CONTRACT_REL = Path("data") / "tcn" / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5_contract.json"
E0_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "e0_decision.json"
E1_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "loss_optimization_decision.json"
E1_BASE_CONFIG_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "uncertainty_seed21" / "config.json"
E2_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "02_hard_sample_loss" / "hard_sample_loss_decision.json"
E3_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "03_physics_group_gate" / "physics_group_gate_decision.json"
E4_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "04_mode_conditioned_theta" / "mode_theta_decision.json"
BASELINE_OFFLINE_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "baseline_offline_metrics.csv"
BASELINE_CLOSED_LOOP_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "baseline_closed_loop_metrics.csv"
E5_REL = Path("results") / "modern_tcn_sci_innovation" / "05_confidence_scheduling"
SANDBOX_REL = Path("results") / "modern_tcn_sci_innovation" / "06_closed_loop_validation" / "sandbox"
BASELINE_CKPT_REL = (
    Path("results")
    / "paper"
    / "agv_model_parameter_correction_workflow"
    / "08_models"
    / "modern_tcn"
    / "modern_tcn_v5_plantfix_turn_l020_tt25_tcm14_stw055_slrw060_seed101"
    / "modern_tcn_seed101.pt"
)
BASELINE_ONNX_REL = (
    Path("results")
    / "paper"
    / "agv_model_parameter_correction_workflow"
    / "08_models"
    / "modern_tcn"
    / "modern_tcn_v5_plantfix_turn_l020_tt25_tcm14_stw055_slrw060_seed101"
    / "modern_tcn_seed101.onnx"
)
FORBIDDEN_DIRS = [
    Path("results") / "compare" / "tcn_gru_modern_closed_loop",
    Path("results") / "paper" / "agv_model_parameter_correction_workflow" / "09_closed_loop" / "dual_modern_seed101_full",
]

BASELINE_THRESHOLDS = {
    "acc_main": 0.966963,
    "acc_turn": 0.578845,
    "acc_turn_transition": 0.497765,
    "theta_mae_deg": 0.679395,
    "flat_recall": 0.969577,
    "stall_recall": 0.718750,
    "slope_recall": 0.974909,
    "theta_edge_p95_abs_err": 2.755057,
    "flat_peak_theta_error": 5.335740,
}

OFFLINE_SPECS = [
    SchedulingSpec("cs_main_c06_d01", "main_conf", 0.6, 0.1),
    SchedulingSpec("cs_main_c07_d01", "main_conf", 0.7, 0.1),
    SchedulingSpec("cs_mainturn_c06_d01", "main_turn_conf", 0.6, 0.1),
    SchedulingSpec("cs_main_c06_d02", "main_conf", 0.6, 0.2),
    SchedulingSpec("rate_limit_only_d01", "rate_limit_only", 0.0, 0.1, offline_only=True),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ModernTCN SCI E5 confidence scheduling workflow.")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--force-sandbox", action="store_true", help="Reserved; E5 still writes only sandbox paths.")
    parser.add_argument("--skip-sandbox", action="store_true", help="Do not run MATLAB sandbox even if offline gate passes.")
    args = parser.parse_args()

    root = find_project_root()
    e5_root = root / E5_REL
    e5_root.mkdir(parents=True, exist_ok=True)
    try:
        decision = run_workflow(root, e5_root, args)
    except Exception as exc:
        write_failure(e5_root, exc)
        raise
    print(json.dumps(decision, indent=2, ensure_ascii=False))
    return 0


def run_workflow(root: Path, e5_root: Path, args: argparse.Namespace) -> Dict[str, object]:
    failure_file = e5_root / "failure_report.md"
    if failure_file.exists():
        failure_file.unlink()

    e0 = read_json(root / E0_DECISION_REL)
    e1 = read_json(root / E1_DECISION_REL)
    e2 = read_json(root / E2_DECISION_REL)
    e3 = read_json(root / E3_DECISION_REL)
    e4 = read_json(root / E4_DECISION_REL)
    baseline = load_baseline(root)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    contract = data["contract"]
    order_audit = row_order_segment_audit(data["test"].run_id)
    checks = preflight_checks(root, e5_root, e0, e1, e2, e3, e4, contract, baseline, order_audit)
    write_preflight(e5_root, checks, baseline, contract, order_audit)
    if checks["failure_reasons"]:
        raise RuntimeError("E5 preflight failed: " + "; ".join(checks["failure_reasons"]))

    cache = build_prediction_cache(root, e5_root, data, baseline, args)
    offline_rows: List[Dict[str, object]] = []
    for spec in OFFLINE_SPECS:
        run_dir = e5_root / spec.tag
        run_dir.mkdir(parents=True, exist_ok=True)
        row = run_offline_spec(run_dir, spec, cache, baseline, order_audit)
        offline_rows.append(row)

    ranked = rank_offline_rows(offline_rows)
    write_offline_master(e5_root, baseline, ranked)
    gate = offline_gate(ranked, baseline)
    selected = selected_confidence_candidate(ranked, gate)

    sandbox_executed = False
    sandbox_result: Dict[str, object] = {
        "executed": False,
        "reason": "offline gate did not select a confidence scheduling candidate",
    }
    if selected is not None and gate["can_enter_sandbox"] and not args.skip_sandbox:
        sandbox_result = write_sandbox_preflight(root, e5_root, selected)
        # The first implementation deliberately does not launch Simulink
        # automatically: MATLAB-side closed-loop requires local Simulink
        # runtime availability and the selected filter must first be reviewed.
        sandbox_result["executed"] = False
        sandbox_result["reason"] = "sandbox preflight generated; automatic Simulink launch not enabled in E5 runner"
    elif selected is not None and args.skip_sandbox:
        sandbox_result = {"executed": False, "reason": "--skip-sandbox was used", "selected_run_tag": selected["run_tag"]}

    decision = write_summary_decision_handoff(
        root=root,
        e5_root=e5_root,
        baseline=baseline,
        ranked=ranked,
        gate=gate,
        selected=selected,
        sandbox_executed=sandbox_executed,
        sandbox_result=sandbox_result,
        order_audit=order_audit,
    )
    return decision


def preflight_checks(
    root: Path,
    e5_root: Path,
    e0: Dict[str, object],
    e1: Dict[str, object],
    e2: Dict[str, object],
    e3: Dict[str, object],
    e4: Dict[str, object],
    contract,
    baseline: Dict[str, object],
    order_audit: Dict[str, object],
) -> Dict[str, object]:
    failures: List[str] = []
    if e0.get("decision") != "PASS":
        failures.append("E0 decision is not PASS")
    if e1.get("e1_status") != "PASS" or e1.get("best_loss_mode") != "fixed":
        failures.append("E1 does not freeze fixed loss")
    if e2.get("e2_status") != "PASS":
        failures.append("E2 status is not PASS")
    if e3.get("e3_status") != "PASS":
        failures.append("E3 status is not PASS")
    if e4.get("e4_status") != "PASS" or not bool(e4.get("can_enter_e5", False)):
        failures.append("E4 decision does not allow E5")
    strategy = e4.get("e5_base_strategy", {})
    if strategy.get("source") != "baseline_small" or strategy.get("model_family") != "small":
        failures.append("E4 e5_base_strategy is not baseline_small/small")
    if int(contract.input_dim) != 22:
        failures.append(f"dataset input_dim is {contract.input_dim}, expected 22")
    if int(contract.seq_len) != 128:
        failures.append(f"dataset seq_len is {contract.seq_len}, expected 128")
    if str(contract.feature_contract) != "passive17_plus_all5":
        failures.append(f"feature_contract is {contract.feature_contract}, expected passive17_plus_all5")
    for path in [root / BASELINE_CKPT_REL, root / BASELINE_ONNX_REL, root / DATASET_REL, root / CONTRACT_REL, root / BASELINE_CLOSED_LOOP_REL]:
        if not path.exists():
            failures.append(f"required baseline file missing: {path}")
    for key in ["theta_edge_p95_abs_err", "flat_peak_theta_error"]:
        if not is_finite_number(baseline.get(key)):
            failures.append(f"baseline {key} is missing")
    if not str(e5_root.resolve()).endswith(str((root / E5_REL).resolve())):
        failures.append(f"E5 output root is unexpected: {e5_root}")
    sandbox_root = (root / SANDBOX_REL).resolve()
    if "formal" in [part.lower() for part in sandbox_root.parts]:
        failures.append(f"sandbox root contains formal path part: {sandbox_root}")
    for forbidden in FORBIDDEN_DIRS:
        if paths_overlap(e5_root.resolve(), (root / forbidden).resolve()):
            failures.append(f"E5 output overlaps forbidden directory: {forbidden}")
    return {
        "failure_reasons": failures,
        "phase": "E5_confidence_scheduling",
        "base_strategy": {"source": "baseline_small", "model_family": "small", "loss_mode": "fixed"},
        "baseline_checkpoint": str(root / BASELINE_CKPT_REL),
        "baseline_onnx": str(root / BASELINE_ONNX_REL),
        "dataset_file": str(root / DATASET_REL),
        "sandbox_root": str(root / SANDBOX_REL),
        "matlab_e5_default_enable": False,
        "output_root_is_isolated": True,
        "order_audit": order_audit,
        "no_training": True,
        "no_onnx_export": True,
        "no_baseline_overwrite": True,
        "no_formal_compare_write": True,
    }


def build_prediction_cache(
    root: Path,
    e5_root: Path,
    data: Dict[str, object],
    baseline: Dict[str, object],
    args: argparse.Namespace,
) -> Dict[str, object]:
    device = _select_device(args.device)
    ckpt = torch.load(root / BASELINE_CKPT_REL, map_location=device, weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).to(device)
    model.eval()
    base_cli = read_json(root / E1_BASE_CONFIG_REL)["cli_args"]
    cfg_args = argparse.Namespace(**base_cli)
    cfg_args.model_family = "small"
    cfg = _build_config(cfg_args, data["contract"], "small")
    test_split = data["test"]
    loader = DataLoader(
        AGVWindowDataset(test_split),
        batch_size=int(args.batch_size),
        shuffle=False,
        num_workers=int(args.num_workers),
    )
    class_w_main = class_weights(
        data["train"].y_main,
        3,
        getattr(cfg, "main_class_weight", "none"),
        list(getattr(cfg, "main_class_multipliers", [1.0, 1.0, 1.0])),
    ).to(device)
    class_w_turn = class_weights(
        data["train"].y_turn,
        3,
        getattr(cfg, "turn_class_weight", "none"),
        list(getattr(cfg, "turn_class_multipliers", [1.0, 1.0, 1.0])),
    ).to(device)

    logits_main_parts: List[np.ndarray] = []
    logits_turn_parts: List[np.ndarray] = []
    theta_parts: List[np.ndarray] = []
    with torch.no_grad():
        for batch in loader:
            batch = _to_device(batch, device)
            logits_main, logits_turn, theta_hat = model(batch["X"])
            logits_main_parts.append(logits_main.detach().cpu().numpy())
            logits_turn_parts.append(logits_turn.detach().cpu().numpy())
            theta_parts.append(theta_hat.detach().cpu().numpy().reshape(-1))

    logits_main = np.concatenate(logits_main_parts, axis=0)
    logits_turn = np.concatenate(logits_turn_parts, axis=0)
    theta_raw_rad = np.concatenate(theta_parts, axis=0)
    theta_raw_deg = np.rad2deg(theta_raw_rad)
    metrics = compute_metrics(logits_main, logits_turn, theta_raw_rad, test_split, float("nan"))
    metrics["theta_edge_p95_abs_err"] = max(
        float(metrics.get("theta_neg_10_8_p95_abs_err_deg", float("nan"))),
        float(metrics.get("theta_pos_8_10_p95_abs_err_deg", float("nan"))),
    )
    metrics["flat_peak_theta_error"] = float(metrics.get("theta_flat_abs_max_deg", float("nan")))
    regression = baseline_regression_status(metrics, baseline)
    if not regression["pass"]:
        raise RuntimeError("baseline prediction regression failed: " + "; ".join(regression["failures"]))

    conf_pack = confidence_from_logits(logits_main, logits_turn, "main_conf")
    cache_file = e5_root / "baseline_prediction_cache.npz"
    np.savez_compressed(
        cache_file,
        logits_main=logits_main,
        logits_turn=logits_turn,
        theta_raw_rad=theta_raw_rad,
        theta_raw_deg=theta_raw_deg,
        y_theta_rad=test_split.y_theta,
        y_theta_deg=np.rad2deg(test_split.y_theta),
        y_main=test_split.y_main,
        y_turn=test_split.y_turn,
        mask_theta=test_split.mask_theta,
        turn_transition=test_split.turn_transition.astype(np.uint8),
        run_id=test_split.run_id,
        main_conf=conf_pack["main_conf"],
        turn_conf=conf_pack["turn_conf"],
    )
    meta = {
        "cache_file": str(cache_file),
        "checkpoint": str(root / BASELINE_CKPT_REL),
        "dataset": str(root / DATASET_REL),
        "n_test_windows": int(theta_raw_deg.size),
        "baseline_metrics": clean_json(metrics),
        "baseline_regression": regression,
        "no_training": True,
        "no_onnx_export": True,
    }
    write_json(e5_root / "baseline_prediction_cache_meta.json", meta)
    write_baseline_cache_report(e5_root, meta)
    return {
        "cache_file": cache_file,
        "logits_main": logits_main,
        "logits_turn": logits_turn,
        "theta_raw_deg": theta_raw_deg,
        "theta_raw_rad": theta_raw_rad,
        "theta_true_deg": np.rad2deg(test_split.y_theta),
        "theta_true_rad": test_split.y_theta,
        "y_main": test_split.y_main,
        "mask_theta": test_split.mask_theta,
        "run_id": test_split.run_id,
        "main_conf": conf_pack["main_conf"],
        "turn_conf": conf_pack["turn_conf"],
        "baseline_metrics": metrics,
    }


def run_offline_spec(
    run_dir: Path,
    spec: SchedulingSpec,
    cache: Dict[str, object],
    baseline: Dict[str, object],
    order_audit: Dict[str, object],
) -> Dict[str, object]:
    result = apply_confidence_scheduling(
        theta_hat_deg=cache["theta_raw_deg"],
        logits_main=cache["logits_main"],
        logits_turn=cache["logits_turn"],
        run_id=cache["run_id"],
        spec=spec,
    )
    row = offline_metrics(spec, result, cache, baseline, order_audit)
    np.savez_compressed(
        run_dir / f"{spec.tag}_offline_trace.npz",
        theta_raw_deg=cache["theta_raw_deg"],
        theta_sched_deg=result.theta_sched_deg,
        theta_true_deg=cache["theta_true_deg"],
        confidence=result.confidence,
        c_eff=result.c_eff,
        low_conf_flag=result.low_conf_flag.astype(np.uint8),
        rate_limit_hit_flag=result.rate_limit_hit_flag.astype(np.uint8),
        segment_id=result.segment_id,
        run_id=cache["run_id"],
    )
    write_csv(run_dir / f"{spec.tag}_offline_metrics.csv", [row])
    write_run_report(run_dir, spec, row)
    return row


def offline_metrics(
    spec: SchedulingSpec,
    result: SchedulingResult,
    cache: Dict[str, object],
    baseline: Dict[str, object],
    order_audit: Dict[str, object],
) -> Dict[str, object]:
    theta_true = np.asarray(cache["theta_true_deg"], dtype=np.float64).reshape(-1)
    theta_raw = np.asarray(cache["theta_raw_deg"], dtype=np.float64).reshape(-1)
    theta_sched = result.theta_sched_deg
    mask_theta = np.asarray(cache["mask_theta"]).reshape(-1).astype(bool)
    y_main = np.asarray(cache["y_main"]).reshape(-1)
    slope_mask = mask_theta
    flat_mask = y_main == 0
    edge_mask = slope_mask & (np.abs(theta_true) >= 8.0) & (np.abs(theta_true) <= 10.0)

    raw_err = np.abs(theta_raw - theta_true)
    sched_err = np.abs(theta_sched - theta_true)
    raw_steps = step_abs_diffs_by_segment(theta_raw, result.segment_id)
    sched_steps = step_abs_diffs_by_segment(theta_sched, result.segment_id)
    conf_pack = confidence_from_logits(cache["logits_main"], cache["logits_turn"], spec.confidence_mode)
    main_conf = conf_pack["main_conf"]
    turn_conf = conf_pack["turn_conf"]

    raw_mae = finite_mean(raw_err[slope_mask])
    sched_mae = finite_mean(sched_err[slope_mask])
    raw_step_p95 = finite_percentile(raw_steps, 95)
    sched_step_p95 = finite_percentile(sched_steps, 95)
    flat_peak = finite_max(np.abs(theta_sched[flat_mask]))
    raw_flat_peak = finite_max(np.abs(theta_raw[flat_mask]))
    edge_p95 = finite_percentile(sched_err[edge_mask], 95)
    raw_edge_p95 = finite_percentile(raw_err[edge_mask], 95)

    row: Dict[str, object] = {
        "run_tag": spec.tag,
        "confidence_mode": spec.confidence_mode,
        "conf_threshold": spec.conf_threshold,
        "delta_theta_max_deg_per_step": spec.delta_theta_max_deg_per_step,
        "offline_only": bool(spec.offline_only),
        "theta_raw_mae_deg": raw_mae,
        "theta_sched_mae_deg": sched_mae,
        "theta_raw_step_p95_deg": raw_step_p95,
        "theta_sched_step_p95_deg": sched_step_p95,
        "theta_sched_smoothness": finite_mean(np.square(sched_steps)),
        "theta_raw_smoothness": finite_mean(np.square(raw_steps)),
        "low_conf_window_ratio": float(np.mean(result.low_conf_flag)),
        "rate_limit_hit_ratio": float(np.mean(result.rate_limit_hit_flag)),
        "flat_peak_theta_error": flat_peak,
        "theta_edge_p95_abs_err": edge_p95,
        "raw_flat_peak_theta_error": raw_flat_peak,
        "raw_theta_edge_p95_abs_err": raw_edge_p95,
        "delta_theta_mae_deg": raw_mae - sched_mae,
        "delta_step_p95_deg": raw_step_p95 - sched_step_p95,
        "delta_flat_peak_theta_error": raw_flat_peak - flat_peak,
        "delta_theta_edge_p95_abs_err": raw_edge_p95 - edge_p95,
        "advisory_step_metrics": bool(result.advisory_step_metrics),
        "segment_count": result.segment_count,
        "n_windows": int(theta_raw.size),
        "n_slope_windows": int(np.sum(slope_mask)),
        "n_flat_windows": int(np.sum(flat_mask)),
        "n_edge_windows": int(np.sum(edge_mask)),
        "baseline_theta_mae_deg": baseline["theta_mae_deg"],
        "baseline_flat_peak_theta_error": baseline["flat_peak_theta_error"],
        "baseline_theta_edge_p95_abs_err": baseline["theta_edge_p95_abs_err"],
        "offline_ordering_note": "split-order replay; step/smoothness advisory when run_id is interleaved",
        "segment_reset_policy": "initialize first point from theta_hat; do not inherit across run_id changes",
    }
    row.update(confidence_distribution(main_conf, "main_conf"))
    row.update(confidence_distribution(turn_conf, "turn_conf"))
    safe, reason = offline_safety_status(row)
    row["offline_safe"] = safe
    row["offline_safe_reason"] = reason
    row["confidence_has_trigger"] = float(row["low_conf_window_ratio"]) > 0.0
    row["rate_limit_has_trigger"] = float(row["rate_limit_hit_ratio"]) > 0.0
    row["rank_score"] = offline_rank_score(row)
    return clean_json(row)


def offline_safety_status(row: Dict[str, object]) -> Tuple[bool, str]:
    failures: List[str] = []
    if float(row["theta_sched_mae_deg"]) > float(row["theta_raw_mae_deg"]) + 0.010:
        failures.append(
            f"theta_sched_mae_deg {row['theta_sched_mae_deg']:.6f} > raw+0.010 {float(row['theta_raw_mae_deg']) + 0.010:.6f}"
        )
    if float(row["flat_peak_theta_error"]) > float(row["raw_flat_peak_theta_error"]) + 0.300:
        failures.append(
            f"flat_peak_theta_error {row['flat_peak_theta_error']:.6f} > raw+0.300 {float(row['raw_flat_peak_theta_error']) + 0.300:.6f}"
        )
    if float(row["theta_edge_p95_abs_err"]) > float(row["raw_theta_edge_p95_abs_err"]) + 0.300:
        failures.append(
            f"theta_edge_p95_abs_err {row['theta_edge_p95_abs_err']:.6f} > raw+0.300 {float(row['raw_theta_edge_p95_abs_err']) + 0.300:.6f}"
        )
    if float(row["low_conf_window_ratio"]) <= 0.0 and float(row["rate_limit_hit_ratio"]) <= 0.0:
        failures.append("low_conf_window_ratio and rate_limit_hit_ratio are both zero")
    if failures:
        return False, "; ".join(failures)
    return True, "offline safety screen passed"


def offline_rank_score(row: Dict[str, object]) -> float:
    # Higher is better. MAE, edge, and flat peak are protection terms.
    return (
        1.5 * float(row["delta_step_p95_deg"])
        + 0.8 * float(row["delta_theta_edge_p95_abs_err"])
        + 0.8 * float(row["delta_flat_peak_theta_error"])
        + 0.6 * float(row["delta_theta_mae_deg"])
        + 0.1 * float(row["low_conf_window_ratio"])
    )


def rank_offline_rows(rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
    return sorted(rows, key=lambda r: (truthy(r.get("offline_safe")), float(r.get("rank_score", -1e9))), reverse=True)


def offline_gate(ranked: List[Dict[str, object]], baseline: Dict[str, object]) -> Dict[str, object]:
    confidence_rows = [r for r in ranked if not truthy(r.get("offline_only"))]
    safe_conf = [r for r in confidence_rows if truthy(r.get("offline_safe"))]
    rate_only = next((r for r in ranked if r["run_tag"] == "rate_limit_only_d01"), None)
    reasons: List[str] = []
    if not safe_conf:
        reasons.append("no confidence scheduling config passed offline safety screen")
    trigger_rows = [r for r in confidence_rows if float(r.get("low_conf_window_ratio", 0.0)) > 0.0 or float(r.get("rate_limit_hit_ratio", 0.0)) > 0.0]
    if not trigger_rows:
        reasons.append("all confidence configs have zero fallback/rate-limit trigger")
    best_conf = safe_conf[0] if safe_conf else None
    confidence_extra = False
    if best_conf is not None and rate_only is not None:
        confidence_extra = float(best_conf["rank_score"]) > float(rate_only["rank_score"]) + 0.010
        if not confidence_extra:
            reasons.append("rate_limit_only_d01 explains offline benefit; confidence gating has no clear extra value")
    if best_conf is not None:
        if float(best_conf["theta_sched_mae_deg"]) > float(best_conf["theta_raw_mae_deg"]) + 0.010:
            reasons.append("selected confidence config worsens theta MAE")
        if float(best_conf["flat_peak_theta_error"]) > float(best_conf["raw_flat_peak_theta_error"]) + 0.300:
            reasons.append("selected confidence config worsens flat peak")
        if float(best_conf["theta_edge_p95_abs_err"]) > float(best_conf["raw_theta_edge_p95_abs_err"]) + 0.300:
            reasons.append("selected confidence config worsens theta edge")
    can_enter = best_conf is not None and confidence_extra and not reasons
    return {
        "can_enter_sandbox": bool(can_enter),
        "reasons": reasons if reasons else ["offline safety screen found one confidence scheduling candidate"],
        "best_confidence_run_tag": best_conf["run_tag"] if best_conf is not None else "",
        "rate_limit_only_rank_score": float(rate_only["rank_score"]) if rate_only is not None else float("nan"),
        "best_confidence_rank_score": float(best_conf["rank_score"]) if best_conf is not None else float("nan"),
        "offline_is_safety_screen_only": True,
    }


def selected_confidence_candidate(ranked: List[Dict[str, object]], gate: Dict[str, object]) -> Dict[str, object] | None:
    tag = gate.get("best_confidence_run_tag", "")
    if not tag:
        return None
    return next((r for r in ranked if r["run_tag"] == tag), None)


def write_summary_decision_handoff(
    root: Path,
    e5_root: Path,
    baseline: Dict[str, object],
    ranked: List[Dict[str, object]],
    gate: Dict[str, object],
    selected: Dict[str, object] | None,
    sandbox_executed: bool,
    sandbox_result: Dict[str, object],
    order_audit: Dict[str, object],
) -> Dict[str, object]:
    decision = {
        "phase": "E5_confidence_scheduling",
        "e5_status": "PASS",
        "method_label": "confidence-aware scheduling filter",
        "base_strategy": {"source": "baseline_small", "model_family": "small", "loss_mode": "fixed"},
        "offline_ranking": [
            {
                "run_tag": r["run_tag"],
                "rank_score": r["rank_score"],
                "offline_safe": r["offline_safe"],
                "theta_raw_mae_deg": r["theta_raw_mae_deg"],
                "theta_sched_mae_deg": r["theta_sched_mae_deg"],
                "theta_raw_step_p95_deg": r["theta_raw_step_p95_deg"],
                "theta_sched_step_p95_deg": r["theta_sched_step_p95_deg"],
                "low_conf_window_ratio": r["low_conf_window_ratio"],
                "rate_limit_hit_ratio": r["rate_limit_hit_ratio"],
                "flat_peak_theta_error": r["flat_peak_theta_error"],
                "theta_edge_p95_abs_err": r["theta_edge_p95_abs_err"],
                "offline_safe_reason": r["offline_safe_reason"],
            }
            for r in ranked
        ],
        "offline_gate": gate,
        "selected_sandbox_candidate": selected["run_tag"] if selected is not None and gate["can_enter_sandbox"] else "",
        "sandbox_closed_loop_executed": bool(sandbox_executed),
        "sandbox_closed_loop_better_than_raw_baseline": False,
        "sandbox_result": sandbox_result,
        "can_enter_phase6_sandbox_expansion": bool(sandbox_executed and sandbox_result.get("better_than_raw_baseline", False)),
        "can_enter_phase6_formal": False,
        "order_audit": order_audit,
        "no_training": True,
        "no_onnx_export": True,
        "no_baseline_overwrite": True,
        "no_formal_compare_write": True,
    }
    write_json(e5_root / "confidence_scheduling_decision.json", decision)
    write_json(e5_root / "confidence_scheduling_summary.json", {"baseline": clean_json(baseline), "decision": decision})
    write_summary_md(e5_root, decision, ranked, gate, order_audit)
    write_handoff(e5_root, decision)
    return decision


def write_preflight(e5_root: Path, checks: Dict[str, object], baseline: Dict[str, object], contract, order_audit: Dict[str, object]) -> None:
    lines = [
        "# E5 Confidence Scheduling Preflight",
        "",
        f"- status: {'PASS' if not checks['failure_reasons'] else 'FAIL'}",
        "- scope: E5 offline scheduling safety screen only; no training/export/formal compare",
        f"- baseline checkpoint: `{checks['baseline_checkpoint']}`",
        f"- baseline ONNX: `{checks['baseline_onnx']}`",
        f"- dataset: `{checks['dataset_file']}`",
        f"- sandbox root: `{checks['sandbox_root']}`",
        f"- model_family: `{checks['base_strategy']['model_family']}`",
        f"- source: `{checks['base_strategy']['source']}`",
        f"- loss_mode: `{checks['base_strategy']['loss_mode']}`",
        f"- input_dim: {contract.input_dim}",
        f"- seq_len: {contract.seq_len}",
        f"- feature_contract: `{contract.feature_contract}`",
        f"- matlab E5 default enable: {checks['matlab_e5_default_enable']}",
        f"- no training: {checks['no_training']}",
        f"- no ONNX export: {checks['no_onnx_export']}",
        f"- no baseline overwrite: {checks['no_baseline_overwrite']}",
        f"- no formal compare write: {checks['no_formal_compare_write']}",
        "",
        "## Baseline References",
        "",
        f"- acc_main: {baseline['acc_main']:.6f}",
        f"- acc_turn: {baseline['acc_turn']:.6f}",
        f"- acc_turn_transition: {baseline['acc_turn_transition']:.6f}",
        f"- theta_mae_deg: {baseline['theta_mae_deg']:.6f}",
        f"- flat_peak_theta_error: {baseline['flat_peak_theta_error']:.6f}",
        f"- theta_edge_p95_abs_err: {baseline['theta_edge_p95_abs_err']:.6f}",
        "",
        "## Replay Order Audit",
        "",
        "```json",
        json.dumps(order_audit, indent=2, ensure_ascii=False),
        "```",
    ]
    if checks["failure_reasons"]:
        lines.extend(["", "## Failure Reasons", ""])
        lines.extend([f"- {x}" for x in checks["failure_reasons"]])
    (e5_root / "e5_preflight.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_baseline_cache_report(e5_root: Path, meta: Dict[str, object]) -> None:
    metrics = meta["baseline_metrics"]
    lines = [
        "# E5 Baseline Prediction Cache",
        "",
        f"- cache: `{meta['cache_file']}`",
        f"- checkpoint: `{meta['checkpoint']}`",
        f"- dataset: `{meta['dataset']}`",
        f"- n_test_windows: {meta['n_test_windows']}",
        f"- regression pass: {meta['baseline_regression']['pass']}",
        "",
        "## Recomputed Metrics",
        "",
        f"- acc_main: {metrics['acc_main']:.6f}",
        f"- acc_turn: {metrics['acc_turn']:.6f}",
        f"- acc_turn_transition: {metrics['acc_turn_transition']:.6f}",
        f"- theta_mae_deg: {metrics['theta_mae_deg']:.6f}",
        f"- flat_peak_theta_error: {metrics['flat_peak_theta_error']:.6f}",
        f"- theta_edge_p95_abs_err: {metrics['theta_edge_p95_abs_err']:.6f}",
    ]
    (e5_root / "baseline_prediction_cache.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_run_report(run_dir: Path, spec: SchedulingSpec, row: Dict[str, object]) -> None:
    lines = [
        f"# E5 Offline Run: {spec.tag}",
        "",
        "## Config",
        "",
        "```json",
        json.dumps(asdict(spec), indent=2, ensure_ascii=False),
        "```",
        "",
        "## Metrics",
        "",
        f"- offline_safe: {row['offline_safe']}",
        f"- reason: {row['offline_safe_reason']}",
        f"- theta_raw_mae_deg: {row['theta_raw_mae_deg']:.6f}",
        f"- theta_sched_mae_deg: {row['theta_sched_mae_deg']:.6f}",
        f"- theta_raw_step_p95_deg: {row['theta_raw_step_p95_deg']:.6f}",
        f"- theta_sched_step_p95_deg: {row['theta_sched_step_p95_deg']:.6f}",
        f"- low_conf_window_ratio: {row['low_conf_window_ratio']:.6f}",
        f"- rate_limit_hit_ratio: {row['rate_limit_hit_ratio']:.6f}",
        f"- flat_peak_theta_error: {row['flat_peak_theta_error']:.6f}",
        f"- theta_edge_p95_abs_err: {row['theta_edge_p95_abs_err']:.6f}",
        f"- advisory_step_metrics: {row['advisory_step_metrics']}",
        "",
        "Offline step/smoothness metrics are advisory if the test split order is not a true time sequence.",
    ]
    (run_dir / f"{spec.tag}_offline_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_offline_master(e5_root: Path, baseline: Dict[str, object], ranked: List[Dict[str, object]]) -> None:
    baseline_row = {
        "run_tag": "baseline_raw_reference",
        "confidence_mode": "raw",
        "conf_threshold": "",
        "delta_theta_max_deg_per_step": "",
        "offline_only": "reference",
        "theta_raw_mae_deg": baseline["theta_mae_deg"],
        "theta_sched_mae_deg": baseline["theta_mae_deg"],
        "theta_raw_step_p95_deg": "",
        "theta_sched_step_p95_deg": "",
        "theta_sched_smoothness": "",
        "low_conf_window_ratio": "",
        "rate_limit_hit_ratio": "",
        "flat_peak_theta_error": baseline["flat_peak_theta_error"],
        "theta_edge_p95_abs_err": baseline["theta_edge_p95_abs_err"],
        "offline_safe": "reference",
        "rank_score": "",
    }
    write_csv(e5_root / "confidence_scheduling_offline_master_table.csv", [baseline_row, *ranked])
    write_csv(e5_root / "confidence_scheduling_master_table.csv", [baseline_row, *ranked])


def write_summary_md(
    e5_root: Path,
    decision: Dict[str, object],
    ranked: List[Dict[str, object]],
    gate: Dict[str, object],
    order_audit: Dict[str, object],
) -> None:
    lines = [
        "# E5 Confidence-Aware Scheduling Summary",
        "",
        f"- E5 status: `{decision['e5_status']}`",
        "- role: offline safety screen for deployment-side theta scheduling",
        "- baseline replacement: False",
        f"- sandbox closed-loop executed: {decision['sandbox_closed_loop_executed']}",
        f"- can enter Phase 6 sandbox expansion: {decision['can_enter_phase6_sandbox_expansion']}",
        f"- can enter Phase 6 formal: {decision['can_enter_phase6_formal']}",
        "- no training: True",
        "- no ONNX export: True",
        "- no baseline overwrite: True",
        "- no formal compare write: True",
        "",
        "## Offline Gate",
        "",
        f"- can enter sandbox: {gate['can_enter_sandbox']}",
        f"- best confidence run: `{gate.get('best_confidence_run_tag', '')}`",
        "",
        "Reasons:",
        "",
    ]
    lines.extend([f"- {x}" for x in gate.get("reasons", [])])
    lines.extend(
        [
            "",
            "## Replay Order",
            "",
            f"- run IDs contiguous: {order_audit['run_ids_are_contiguous']}",
            f"- contiguous segments: {order_audit['n_contiguous_segments']}",
            f"- advisory step metrics: {order_audit['advisory_step_metrics']}",
            "",
            "## Offline Ranking",
            "",
            "| rank | run | safe | theta raw | theta sched | step raw p95 | step sched p95 | low conf | rate hit | flat peak | edge p95 | score |",
            "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for idx, row in enumerate(ranked, start=1):
        lines.append(
            f"| {idx} | `{row['run_tag']}` | {row['offline_safe']} | "
            f"{float(row['theta_raw_mae_deg']):.6f} | {float(row['theta_sched_mae_deg']):.6f} | "
            f"{float(row['theta_raw_step_p95_deg']):.6f} | {float(row['theta_sched_step_p95_deg']):.6f} | "
            f"{float(row['low_conf_window_ratio']):.6f} | {float(row['rate_limit_hit_ratio']):.6f} | "
            f"{float(row['flat_peak_theta_error']):.6f} | {float(row['theta_edge_p95_abs_err']):.6f} | "
            f"{float(row['rank_score']):.6f} |"
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "Offline smoothness is advisory because the test split is not a proven time-contiguous replay. E5 does not prove superiority over the frozen baseline; it only screens deployment-side filter candidates.",
        ]
    )
    (e5_root / "confidence_scheduling_offline_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (e5_root / "confidence_scheduling_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_handoff(e5_root: Path, decision: Dict[str, object]) -> None:
    lines = [
        "# ModernTCN SCI Innovation E5 Handoff",
        "",
        "阶段：`E5 / 05_confidence_scheduling`",
        "",
        "## 结论",
        "",
        f"- E5 status: `{decision['e5_status']}`",
        "- E5 role: deployment-side offline safety screen, not baseline replacement",
        f"- sandbox closed-loop executed: {decision['sandbox_closed_loop_executed']}",
        f"- sandbox better than raw baseline: {decision['sandbox_closed_loop_better_than_raw_baseline']}",
        f"- can enter Phase 6 sandbox expansion: {decision['can_enter_phase6_sandbox_expansion']}",
        f"- can enter Phase 6 formal: {decision['can_enter_phase6_formal']}",
        "",
        "## Offline 排序",
        "",
        "| rank | run | safe | theta_sched_mae | low_conf | rate_hit | reason |",
        "|---:|---|---|---:|---:|---:|---|",
    ]
    for idx, row in enumerate(decision["offline_ranking"], start=1):
        lines.append(
            f"| {idx} | `{row['run_tag']}` | {row['offline_safe']} | "
            f"{float(row['theta_sched_mae_deg']):.6f} | {float(row['low_conf_window_ratio']):.6f} | "
            f"{float(row['rate_limit_hit_ratio']):.6f} | {row['offline_safe_reason']} |"
        )
    lines.extend(
        [
            "",
            "## 必读证据",
            "",
            "- `e5_preflight.md`",
            "- `baseline_prediction_cache.md`",
            "- `confidence_scheduling_offline_master_table.csv`",
            "- `confidence_scheduling_offline_summary.md`",
            "- `confidence_scheduling_decision.json`",
            "",
            "## Safety",
            "",
            "- no training: True",
            "- no ONNX export: True",
            "- no baseline overwrite: True",
            "- no formal compare write: True",
            "- MATLAB E5 filter default disabled: True",
        ]
    )
    (e5_root / "HANDOFF_NEXT_CHAT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_sandbox_preflight(root: Path, e5_root: Path, selected: Dict[str, object]) -> Dict[str, object]:
    sandbox_dir = root / SANDBOX_REL / selected["run_tag"]
    sandbox_dir.mkdir(parents=True, exist_ok=True)
    out = {
        "selected_run_tag": selected["run_tag"],
        "sandbox_dir": str(sandbox_dir),
        "raw_baseline_required": True,
        "scheduled_required": True,
        "baseline_onnx": str(root / BASELINE_ONNX_REL),
        "dataset_file": str(root / DATASET_REL),
        "path_tag": "path_closed_loop_sharp_turn_transition_theta10_v1",
        "formal_compare_write": False,
    }
    write_json(e5_root / "e5_sandbox_preflight.json", out)
    lines = [
        "# E5 Sandbox Closed-Loop Preflight",
        "",
        f"- selected run: `{selected['run_tag']}`",
        f"- sandbox dir: `{sandbox_dir}`",
        "- back-to-back raw baseline required: True",
        "- back-to-back scheduled candidate required: True",
        f"- baseline ONNX: `{root / BASELINE_ONNX_REL}`",
        f"- dataset: `{root / DATASET_REL}`",
        "- first path: `path_closed_loop_sharp_turn_transition_theta10_v1`",
        "- formal compare write: False",
        "",
        "The E5 runner generated this preflight but did not automatically launch Simulink.",
    ]
    (e5_root / "e5_sandbox_preflight.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def baseline_regression_status(metrics: Dict[str, object], baseline: Dict[str, object]) -> Dict[str, object]:
    tolerances = {
        "acc_main": 5e-6,
        "acc_turn": 5e-6,
        "acc_turn_transition": 5e-6,
        "theta_mae_deg": 5e-5,
        "flat_recall": 5e-6,
        "stall_recall": 5e-6,
        "slope_recall": 5e-6,
        "theta_edge_p95_abs_err": 5e-4,
        "flat_peak_theta_error": 5e-4,
    }
    failures: List[str] = []
    deltas = {}
    for key, tol in tolerances.items():
        actual = float(metrics[key])
        ref = float(baseline[key])
        delta = actual - ref
        deltas[key] = delta
        if abs(delta) > tol:
            failures.append(f"{key}: actual {actual:.9f}, reference {ref:.9f}, delta {delta:.9g}, tol {tol}")
    return {"pass": not failures, "failures": failures, "deltas": clean_json(deltas)}


def load_baseline(root: Path) -> Dict[str, object]:
    out: Dict[str, object] = {}
    offline_rows = read_csv_dicts(root / BASELINE_OFFLINE_REL)
    if not offline_rows:
        raise FileNotFoundError(f"baseline offline metrics missing rows: {root / BASELINE_OFFLINE_REL}")
    out.update({k: parse_float(v) for k, v in offline_rows[0].items() if parse_float(v) is not None})
    champion_summary = root / BASELINE_CKPT_REL.parent / "modern_tcn_seed101_summary.csv"
    if champion_summary.exists():
        rows = read_csv_dicts(champion_summary)
        if rows:
            row = rows[0]
            out["theta_edge_p95_abs_err"] = max(
                float(row.get("theta_neg_10_8_p95_abs_err_deg", "nan")),
                float(row.get("theta_pos_8_10_p95_abs_err_deg", "nan")),
            )
            out["flat_peak_theta_error"] = float(row.get("theta_flat_abs_max_deg", "nan"))
    for key, val in BASELINE_THRESHOLDS.items():
        out.setdefault(key, val)
    closed_loop_rows = read_csv_dicts(root / BASELINE_CLOSED_LOOP_REL)
    for row in closed_loop_rows:
        if row.get("scope") == "aggregate":
            for key in ["ey_rmse_mean", "xy_rmse_mean", "j_du_mean"]:
                if key in row:
                    parsed = parse_float(row[key])
                    if parsed is not None:
                        out[f"closed_loop_{key}"] = parsed
    return out


def write_failure(e5_root: Path, exc: BaseException) -> None:
    e5_root.mkdir(parents=True, exist_ok=True)
    lines = [
        "# E5 Failure Report",
        "",
        "- status: FAIL",
        f"- error_type: `{type(exc).__name__}`",
        f"- error: `{exc}`",
        "- no training: True",
        "- no ONNX export: True",
        "- no baseline overwrite: True",
        "- no formal compare write: True",
        "",
        "## Traceback",
        "",
        "```text",
        "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)),
        "```",
    ]
    (e5_root / "failure_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_json(path: Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(clean_json(data), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_csv_dicts(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields: List[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fields:
                fields.append(key)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def clean_json(obj):
    if isinstance(obj, dict):
        return {str(k): clean_json(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean_json(v) for v in obj]
    if isinstance(obj, tuple):
        return [clean_json(v) for v in obj]
    if isinstance(obj, (np.bool_, bool)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating, float)):
        val = float(obj)
        return val if math.isfinite(val) else None
    return obj


def parse_float(value: object) -> float | None:
    try:
        if value is None or value == "":
            return None
        val = float(value)
        return val if math.isfinite(val) else None
    except Exception:
        return None


def is_finite_number(value: object) -> bool:
    try:
        return math.isfinite(float(value))
    except Exception:
        return False


def truthy(value: object) -> bool:
    if isinstance(value, str):
        return value.strip().lower() in {"true", "1", "yes"}
    return bool(value)


def paths_overlap(a: Path, b: Path) -> bool:
    try:
        a.relative_to(b)
        return True
    except ValueError:
        pass
    try:
        b.relative_to(a)
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())

