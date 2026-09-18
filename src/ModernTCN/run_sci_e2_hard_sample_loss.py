"""Run SCI E2 hard-sample focal loss experiments.

This runner is intentionally scoped to:
results/modern_tcn_sci_innovation/02_hard_sample_loss/

It does not export ONNX, does not call MATLAB/Simulink, and uses
train_modern_tcn.py with model_family=small and loss_mode=fixed.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import sys
import time
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import torch
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import multitask_loss_components
from train_modern_tcn import _build_config, _select_device, _set_seed, _to_device, train_one_seed


DATASET_REL = Path("data") / "tcn" / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
E0_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "e0_decision.json"
E1_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "loss_optimization_decision.json"
E1_BASE_CONFIG_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "uncertainty_seed21" / "config.json"
BASELINE_CSV_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "baseline_offline_metrics.csv"
E2_REL = Path("results") / "modern_tcn_sci_innovation" / "02_hard_sample_loss"

REQUIRED_RUN_FILES = [
    "modern_tcn_seed21.pt",
    "modern_tcn_seed21_summary.csv",
    "modern_tcn_seed21_history.csv",
    "config.json",
    "git_hash.txt",
    "dataset_contract_copy.json",
    "feature_names.txt",
    "ModernTCN_train_report.md",
]

SMOKE_SPECS = [
    ("smoke_transition_focal", 0.2, 0.0),
    ("smoke_stall_focal", 0.0, 0.2),
    ("smoke_combo_focal", 0.2, 0.2),
]

PRIMARY_RUN_SPECS = [
    ("fs_t02_s02_sm000_seed21", 0.2, 0.2),
    ("fs_t05_s02_sm000_seed21", 0.5, 0.2),
    ("fs_t02_s05_sm000_seed21", 0.2, 0.5),
    ("fs_t05_s05_sm000_seed21", 0.5, 0.5),
]

LOW_RISK_RUN_SPECS = [
    ("fs_t005_s005_sm000_seed21", 0.05, 0.05),
    ("fs_t01_s005_sm000_seed21", 0.10, 0.05),
    ("fs_t005_s01_sm000_seed21", 0.05, 0.10),
    ("fs_t02_s01_sm000_seed21", 0.20, 0.10),
]

LOSS_SCALE_NEAR_RATIO = 0.75
THETA_SMOOTH_STATUS = "disabled_contract_limited"


@dataclass(frozen=True)
class RunSpec:
    tag: str
    lambda_transition: float
    lambda_stall: float


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ModernTCN SCI E2 hard-sample focal loss workflow.")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--min-epochs", type=int, default=30)
    parser.add_argument("--patience", type=int, default=25)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--smoke-epochs", type=int, default=2)
    parser.add_argument("--skip-formal", action="store_true")
    args = parser.parse_args()

    root = find_project_root()
    e2_root = root / E2_REL
    e2_root.mkdir(parents=True, exist_ok=True)

    try:
        result = run_workflow(root, e2_root, args)
    except Exception as exc:
        write_failure(e2_root, exc)
        raise
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


def run_workflow(root: Path, e2_root: Path, args: argparse.Namespace) -> Dict[str, object]:
    e0 = read_json(root / E0_DECISION_REL)
    e1 = read_json(root / E1_DECISION_REL)
    base_cli = read_json(root / E1_BASE_CONFIG_REL)["cli_args"]
    baseline = load_baseline(root)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    contract = data["contract"]
    run_order_audit = audit_run_order(data)

    checks = preflight_checks(root, e2_root, e0, e1, contract, baseline, PRIMARY_RUN_SPECS + LOW_RISK_RUN_SPECS)
    verify_zero_loss_equivalence(root, base_cli, args.device)
    checks["zero_loss_equivalence_verified"] = True
    verify_no_overwrite_guard(root, e2_root, base_cli, args.device)
    checks["no_overwrite_guard_verified"] = True
    write_preflight(e2_root, checks, baseline, contract, run_order_audit, scale_rows=[], formal_specs=PRIMARY_RUN_SPECS)

    if checks["failure_reasons"]:
        raise RuntimeError("E2 preflight failed: " + "; ".join(checks["failure_reasons"]))

    smoke_rows: List[Dict[str, object]] = []
    for tag, lam_t, lam_s in SMOKE_SPECS:
        print(f"[E2 smoke] {tag}")
        train_args = make_train_args(
            root,
            e2_root,
            base_cli,
            run_tag=tag,
            lambda_transition=lam_t,
            lambda_stall=lam_s,
            seed=21,
            epochs=args.smoke_epochs,
            min_epochs=1,
            patience=1,
            batch_size=64,
            limit_train=512,
            limit_val=256,
            limit_test=256,
            device=args.device,
            num_workers=args.num_workers,
        )
        result = train_one_seed(train_args)
        row = smoke_scale_row(tag, lam_t, lam_s, result["test_metrics"])
        smoke_rows.append(row)

    high_scale = any(bool(r["scale_warning"]) for r in smoke_rows)
    formal_specs = LOW_RISK_RUN_SPECS if high_scale else PRIMARY_RUN_SPECS
    write_preflight(e2_root, checks, baseline, contract, run_order_audit, scale_rows=smoke_rows, formal_specs=formal_specs)
    write_smoke_report(e2_root, smoke_rows, formal_specs, high_scale)

    formal_rows: List[Dict[str, object]] = []
    if not args.skip_formal:
        for tag, lam_t, lam_s in formal_specs:
            print(f"[E2 formal] {tag}")
            train_args = make_train_args(
                root,
                e2_root,
                base_cli,
                run_tag=tag,
                lambda_transition=lam_t,
                lambda_stall=lam_s,
                seed=21,
                epochs=args.epochs,
                min_epochs=args.min_epochs,
                patience=args.patience,
                batch_size=args.batch_size,
                limit_train=0,
                limit_val=0,
                limit_test=0,
                device=args.device,
                num_workers=args.num_workers,
            )
            result = train_one_seed(train_args)
            row = formal_row(root, e2_root, tag, lam_t, lam_s, result, baseline)
            formal_rows.append(row)

    if formal_rows:
        write_master_table(e2_root, baseline, formal_rows)
        decision = write_summary_and_decision(e2_root, baseline, formal_rows, formal_specs, high_scale)
    else:
        decision = {
            "phase": "E2_hard_sample_focal_loss",
            "e2_status": "PASS_SMOKE_ONLY",
            "formal_runs_executed": False,
            "can_enter_e3": False,
            "reason": "skip_formal was used",
        }
        (e2_root / "hard_sample_loss_decision.json").write_text(json.dumps(decision, indent=2, ensure_ascii=False), encoding="utf-8")
    return decision


def preflight_checks(
    root: Path,
    e2_root: Path,
    e0: Dict[str, object],
    e1: Dict[str, object],
    contract,
    baseline: Dict[str, object],
    specs: Iterable[Tuple[str, float, float]],
) -> Dict[str, object]:
    failures: List[str] = []
    if e0.get("decision") != "PASS":
        failures.append("E0 decision is not PASS")
    if e1.get("e1_status") != "PASS" or not bool(e1.get("can_enter_e2", False)):
        failures.append("E1 decision does not allow E2")
    if e1.get("recommended_e2_loss_mode") != "fixed":
        failures.append("E1 recommended_e2_loss_mode is not fixed")
    if int(contract.input_dim) != 22:
        failures.append(f"dataset input_dim is {contract.input_dim}, expected 22")
    if int(contract.seq_len) != 128:
        failures.append(f"dataset seq_len is {contract.seq_len}, expected 128")
    if str(contract.feature_contract) != "passive17_plus_all5":
        failures.append(f"feature_contract is {contract.feature_contract}, expected passive17_plus_all5")
    for key in ["theta_edge_p95_abs_err", "flat_peak_theta_error"]:
        if not is_finite_number(baseline.get(key)):
            failures.append(f"baseline {key} is missing or nan")
    for tag, _, _ in specs:
        run_dir = e2_root / tag
        if run_dir.exists() and any(run_dir.iterdir()):
            failures.append(f"output run directory would be overwritten: {run_dir}")
    if (root / "results" / "compare" / "tcn_gru_modern_closed_loop").exists():
        compare_note = "old compare directory exists but is not touched"
    else:
        compare_note = "old compare directory not present"
    return {
        "failure_reasons": failures,
        "compare_note": compare_note,
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
    }


def load_baseline(root: Path) -> Dict[str, object]:
    row = read_csv_rows(root / BASELINE_CSV_REL)[0]
    out: Dict[str, object] = dict(row)
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "acc_turn_pure",
    ]:
        out[key] = to_float(out.get(key))
    source = Path(str(row.get("source", "")))
    if not source.is_absolute():
        source = root / source
    champ = read_csv_rows(source)[0]
    out["baseline_summary_source"] = str(source)
    out["theta_neg_10_8_p95_abs_err_deg"] = to_float(champ.get("theta_neg_10_8_p95_abs_err_deg"))
    out["theta_pos_8_10_p95_abs_err_deg"] = to_float(champ.get("theta_pos_8_10_p95_abs_err_deg"))
    out["theta_edge_p95_abs_err"] = max(
        out["theta_neg_10_8_p95_abs_err_deg"],
        out["theta_pos_8_10_p95_abs_err_deg"],
    )
    out["theta_flat_abs_max_deg"] = to_float(champ.get("theta_flat_abs_max_deg"))
    out["flat_peak_theta_error"] = out["theta_flat_abs_max_deg"]
    out["acc_turn_pure"] = to_float(champ.get("acc_turn_pure"))
    return out


def audit_run_order(data: Dict[str, object]) -> Dict[str, object]:
    out: Dict[str, object] = {}
    for split_name in ["train", "val", "test"]:
        split = data[split_name]
        rid = np.asarray(split.run_id).reshape(-1)
        changes = np.where(rid[1:] != rid[:-1])[0] + 1 if rid.size > 1 else np.array([], dtype=np.int64)
        seen = set()
        last = object()
        reappears = False
        for value in rid.tolist():
            if value != last:
                if value in seen:
                    reappears = True
                    break
                seen.add(value)
                last = value
        out[split_name] = {
            "n_windows": int(rid.size),
            "unique_runs": int(len(np.unique(rid))) if rid.size else 0,
            "contiguous_segments": int(len(changes) + 1) if rid.size else 0,
            "run_reappears": bool(reappears),
        }
    out["theta_smooth_status"] = THETA_SMOOTH_STATUS
    out["reason"] = "run_id exists, but windows are not ordered as contiguous same-run sequences and no window/order index is available"
    return out


def verify_zero_loss_equivalence(root: Path, base_cli: Dict[str, object], device_mode: str) -> None:
    args = make_train_args(
        root,
        root / E2_REL,
        base_cli,
        run_tag="__zero_equivalence__",
        lambda_transition=0.0,
        lambda_stall=0.0,
        seed=21,
        epochs=1,
        min_epochs=1,
        patience=1,
        batch_size=16,
        limit_train=16,
        limit_val=16,
        limit_test=16,
        device=device_mode,
        num_workers=0,
        no_overwrite=False,
    )
    _set_seed(123)
    device = _select_device(device_mode)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=16, limit_val=16, limit_test=16)
    cfg = _build_config(args, data["contract"], "small")
    model = __import__("modern_tcn_model").build_model_from_config(cfg, "small").to(device)
    loader = DataLoader(AGVWindowDataset(data["train"]), batch_size=16, shuffle=False)
    class_w_main = class_weights(data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)).to(device)
    class_w_turn = class_weights(data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)).to(device)
    batch = _to_device(next(iter(loader)), device)
    with torch.no_grad():
        logits_main, logits_turn, theta_hat = model(batch["X"])
        total, parts = multitask_loss_components(logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg)
    base_total = parts["loss_main_bundle_base"] + parts["loss_turn_bundle_base"] + parts["loss_theta_bundle_base"]
    diff = float(torch.abs(total - base_total).detach().cpu())
    if diff > 1e-7:
        raise RuntimeError(f"zero E2 loss does not preserve fixed baseline loss; diff={diff}")
    for key in ["loss_transition_focal_weighted", "loss_stall_focal_weighted", "loss_theta_smooth"]:
        if abs(float(parts[key].detach().cpu())) > 1e-12:
            raise RuntimeError(f"{key} is not zero under zero/off E2 config")


def verify_no_overwrite_guard(root: Path, e2_root: Path, base_cli: Dict[str, object], device_mode: str) -> None:
    probe = e2_root / "__no_overwrite_probe__"
    probe.mkdir(parents=True, exist_ok=True)
    marker = probe / "marker.txt"
    marker.write_text("probe\n", encoding="utf-8")
    try:
        args = make_train_args(
            root,
            e2_root,
            base_cli,
            run_tag=probe.name,
            lambda_transition=0.0,
            lambda_stall=0.0,
            seed=21,
            epochs=1,
            min_epochs=1,
            patience=1,
            batch_size=16,
            limit_train=16,
            limit_val=16,
            limit_test=16,
            device=device_mode,
            num_workers=0,
            no_overwrite=True,
        )
        try:
            train_one_seed(args)
        except FileExistsError:
            return
        raise RuntimeError("--no-overwrite did not reject an existing non-empty output directory")
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def make_train_args(
    root: Path,
    e2_root: Path,
    base_cli: Dict[str, object],
    run_tag: str,
    lambda_transition: float,
    lambda_stall: float,
    seed: int,
    epochs: int,
    min_epochs: int,
    patience: int,
    batch_size: int,
    limit_train: int,
    limit_val: int,
    limit_test: int,
    device: str,
    num_workers: int,
    no_overwrite: bool = True,
) -> argparse.Namespace:
    values = dict(base_cli)
    values.update(
        {
            "seed": seed,
            "model_family": "small",
            "dataset_file": str(root / DATASET_REL),
            "output_root": str(e2_root),
            "run_tag": run_tag,
            "no_overwrite": no_overwrite,
            "loss_mode": "fixed",
            "epochs": int(epochs),
            "min_epochs": int(min_epochs),
            "patience": int(patience),
            "batch_size": int(batch_size),
            "limit_train": int(limit_train),
            "limit_val": int(limit_val),
            "limit_test": int(limit_test),
            "device": device,
            "num_workers": int(num_workers),
            "dry_run": False,
            "lambda_transition_focal": float(lambda_transition),
            "lambda_stall_focal": float(lambda_stall),
            "lambda_theta_smooth": 0.0,
            "focal_gamma": 2.0,
            "theta_smooth_mode": "off",
        }
    )
    return argparse.Namespace(**values)


def smoke_scale_row(tag: str, lam_t: float, lam_s: float, metrics: Dict[str, object]) -> Dict[str, object]:
    turn_base = to_float(metrics.get("loss_turn_bundle_base"))
    main_base = to_float(metrics.get("loss_main_bundle_base"))
    transition_weighted = to_float(metrics.get("loss_transition_focal_weighted"))
    stall_weighted = to_float(metrics.get("loss_stall_focal_weighted"))
    transition_ratio = transition_weighted / max(abs(turn_base), 1e-8)
    stall_ratio = stall_weighted / max(abs(main_base), 1e-8)
    return {
        "run_tag": tag,
        "lambda_transition_focal": lam_t,
        "lambda_stall_focal": lam_s,
        "base_main_bundle": main_base,
        "base_turn_bundle": turn_base,
        "base_theta_bundle": to_float(metrics.get("loss_theta_bundle_base")),
        "raw_transition_focal": to_float(metrics.get("loss_transition_focal_raw")),
        "weighted_transition_focal": transition_weighted,
        "transition_focal_to_base_turn_ratio": transition_ratio,
        "raw_stall_focal": to_float(metrics.get("loss_stall_focal_raw")),
        "weighted_stall_focal": stall_weighted,
        "stall_focal_to_base_main_ratio": stall_ratio,
        "scale_warning": transition_ratio >= LOSS_SCALE_NEAR_RATIO or stall_ratio >= LOSS_SCALE_NEAR_RATIO,
    }


def formal_row(
    root: Path,
    e2_root: Path,
    tag: str,
    lam_t: float,
    lam_s: float,
    result: Dict[str, object],
    baseline: Dict[str, object],
) -> Dict[str, object]:
    run_dir = e2_root / tag
    missing = [name for name in REQUIRED_RUN_FILES if not (run_dir / name).exists()]
    summary = read_csv_rows(run_dir / "modern_tcn_seed21_summary.csv")[0]
    row: Dict[str, object] = dict(summary)
    row["run_tag"] = tag
    row["lambda_transition_focal"] = lam_t
    row["lambda_stall_focal"] = lam_s
    row["lambda_theta_smooth"] = 0.0
    row["theta_smooth_status"] = THETA_SMOOTH_STATUS
    row["missing_required_files"] = ";".join(missing)
    row["artifact_complete"] = not missing
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_pure",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_edge_p95_abs_err",
        "flat_peak_theta_error",
        "flat_as_stall_ratio",
        "stall_as_flat_ratio",
    ]:
        row[key] = to_float(row.get(key))
    row["delta_acc_main"] = row["acc_main"] - baseline["acc_main"]
    row["delta_acc_turn"] = row["acc_turn"] - baseline["acc_turn"]
    row["delta_acc_turn_transition"] = row["acc_turn_transition"] - baseline["acc_turn_transition"]
    row["delta_theta_mae_deg"] = baseline["theta_mae_deg"] - row["theta_mae_deg"]
    row["delta_flat_recall"] = row["flat_recall"] - baseline["flat_recall"]
    row["delta_stall_recall"] = row["stall_recall"] - baseline["stall_recall"]
    row["delta_slope_recall"] = row["slope_recall"] - baseline["slope_recall"]
    row["delta_theta_edge_p95_abs_err"] = baseline["theta_edge_p95_abs_err"] - row["theta_edge_p95_abs_err"]
    row["delta_flat_peak_theta_error"] = baseline["flat_peak_theta_error"] - row["flat_peak_theta_error"]
    eligible, eligible_reason = eligible_status(row, baseline)
    promotable, promotable_reason = promotable_status(row, baseline, eligible)
    row["eligible"] = eligible
    row["eligible_reason"] = eligible_reason
    row["promotable"] = promotable
    row["promotable_reason"] = promotable_reason
    row["rank_score"] = rank_score(row)
    return row


def eligible_status(row: Dict[str, object], baseline: Dict[str, object]) -> Tuple[bool, str]:
    checks = [
        ("acc_main", row["acc_main"], ">=", baseline["acc_main"] - 0.003),
        ("acc_turn", row["acc_turn"], ">=", baseline["acc_turn"] - 0.005),
        ("acc_turn_transition", row["acc_turn_transition"], ">=", baseline["acc_turn_transition"]),
        ("theta_mae_deg", row["theta_mae_deg"], "<=", baseline["theta_mae_deg"] + 0.01),
        ("flat_recall", row["flat_recall"], ">=", baseline["flat_recall"] - 0.010),
        ("stall_recall", row["stall_recall"], ">=", baseline["stall_recall"] - 0.050),
        ("slope_recall", row["slope_recall"], ">=", baseline["slope_recall"] - 0.005),
        ("theta_edge_p95_abs_err", row["theta_edge_p95_abs_err"], "<=", baseline["theta_edge_p95_abs_err"]),
        ("flat_peak_theta_error", row["flat_peak_theta_error"], "<=", baseline["flat_peak_theta_error"]),
    ]
    failures = []
    if not bool(row.get("artifact_complete", False)):
        failures.append("missing required artifacts")
    for key, actual, op, threshold in checks:
        passed = actual >= threshold if op == ">=" else actual <= threshold
        if not passed:
            failures.append(f"{key} {op} {threshold:.6f}, actual {actual:.6f}")
    return not failures, "; ".join(failures) if failures else "protection metrics pass"


def promotable_status(row: Dict[str, object], baseline: Dict[str, object], eligible: bool) -> Tuple[bool, str]:
    if not eligible:
        return False, "not eligible"
    target_improved = row["acc_turn_transition"] > baseline["acc_turn_transition"] or row["stall_recall"] > baseline["stall_recall"]
    if not target_improved:
        return False, "eligible but no target metric improved"
    flat_as_stall_limit = max(0.05, (1.0 - baseline["flat_recall"]) + 0.02)
    if is_finite_number(row.get("flat_as_stall_ratio")) and row["flat_as_stall_ratio"] > flat_as_stall_limit:
        return False, f"flat_as_stall_ratio {row['flat_as_stall_ratio']:.6f} > limit {flat_as_stall_limit:.6f}"
    if row["acc_turn_pure"] < baseline.get("acc_turn_pure", 0.0) - 0.005:
        return False, "acc_turn_pure degraded"
    return True, "eligible and target metric improved"


def rank_score(row: Dict[str, object]) -> float:
    return (
        2.0 * float(row.get("delta_acc_turn_transition", 0.0))
        + 1.5 * float(row.get("delta_stall_recall", 0.0))
        + 0.5 * float(row.get("delta_theta_mae_deg", 0.0))
        + 0.5 * float(row.get("delta_theta_edge_p95_abs_err", 0.0))
        + 0.25 * float(row.get("delta_flat_peak_theta_error", 0.0))
        + 0.5 * float(row.get("delta_acc_main", 0.0))
        + 0.5 * float(row.get("delta_flat_recall", 0.0))
        + 0.5 * float(row.get("delta_slope_recall", 0.0))
    )


def write_preflight(
    e2_root: Path,
    checks: Dict[str, object],
    baseline: Dict[str, object],
    contract,
    run_order_audit: Dict[str, object],
    scale_rows: List[Dict[str, object]],
    formal_specs: Iterable[Tuple[str, float, float]],
) -> None:
    lines = [
        "# E2 Engineering Preflight",
        "",
        f"- status: {'FAIL' if checks['failure_reasons'] else 'PASS'}",
        "- scope: E2 / 02_hard_sample_loss only; no ONNX; no MATLAB/Simulink.",
        "- method label: hard-sample focal only",
        f"- theta_smooth_status: `{THETA_SMOOTH_STATUS}`",
        f"- dataset input: `[batch,{contract.seq_len},{contract.input_dim}]`",
        f"- feature_contract: `{contract.feature_contract}`",
        f"- compare note: {checks['compare_note']}",
        f"- zero_loss_equivalence_verified: {checks.get('zero_loss_equivalence_verified', False)}",
        f"- no_overwrite_guard_verified: {checks.get('no_overwrite_guard_verified', False)}",
        "",
        "## Baseline Reference",
        "",
        f"- source: `{baseline.get('baseline_summary_source')}`",
        f"- acc_main: {baseline['acc_main']}",
        f"- acc_turn: {baseline['acc_turn']}",
        f"- acc_turn_transition: {baseline['acc_turn_transition']}",
        f"- theta_mae_deg: {baseline['theta_mae_deg']}",
        f"- flat_recall: {baseline['flat_recall']}",
        f"- stall_recall: {baseline['stall_recall']}",
        f"- slope_recall: {baseline['slope_recall']}",
        f"- theta_edge_p95_abs_err: {baseline['theta_edge_p95_abs_err']}",
        f"- flat_peak_theta_error: {baseline['flat_peak_theta_error']}",
        "",
        "## Theta Smoothness Audit",
        "",
        "```json",
        json.dumps(run_order_audit, indent=2, ensure_ascii=False),
        "```",
        "",
        "## Planned Formal Runs",
        "",
    ]
    for tag, lam_t, lam_s in formal_specs:
        lines.append(f"- `{tag}`: lambda_transition={lam_t}, lambda_stall={lam_s}, lambda_smooth=0")
    if scale_rows:
        lines.extend(["", "## Smoke Loss Scale", "", "| run | transition/base_turn | stall/base_main | warning |", "|---|---:|---:|---|"])
        for row in scale_rows:
            lines.append(
                f"| {row['run_tag']} | {row['transition_focal_to_base_turn_ratio']:.6f} | "
                f"{row['stall_focal_to_base_main_ratio']:.6f} | {row['scale_warning']} |"
            )
    if checks["failure_reasons"]:
        lines.extend(["", "## Failure Reasons", ""])
        lines.extend(f"- {x}" for x in checks["failure_reasons"])
    (e2_root / "e2_preflight.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_smoke_report(e2_root: Path, rows: List[Dict[str, object]], formal_specs: Iterable[Tuple[str, float, float]], high_scale: bool) -> None:
    with (e2_root / "e2_smoke_report.md").open("w", encoding="utf-8") as f:
        f.write("# E2 Smoke Report\n\n")
        f.write("- status: PASS\n")
        f.write(f"- high_loss_scale_detected: {high_scale}\n")
        f.write(f"- formal_grid: {'low_risk_0.05_0.1_0.2' if high_scale else 'primary_0.2_0.5'}\n")
        f.write(f"- theta_smooth_status: `{THETA_SMOOTH_STATUS}`\n\n")
        f.write("## Loss Scale\n\n")
        f.write("| run | base main | base turn | base theta | raw transition | weighted transition | transition/base turn | raw stall | weighted stall | stall/base main | warning |\n")
        f.write("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n")
        for row in rows:
            f.write(
                f"| {row['run_tag']} | {row['base_main_bundle']:.6f} | {row['base_turn_bundle']:.6f} | "
                f"{row['base_theta_bundle']:.6f} | {row['raw_transition_focal']:.6f} | "
                f"{row['weighted_transition_focal']:.6f} | {row['transition_focal_to_base_turn_ratio']:.6f} | "
                f"{row['raw_stall_focal']:.6f} | {row['weighted_stall_focal']:.6f} | "
                f"{row['stall_focal_to_base_main_ratio']:.6f} | {row['scale_warning']} |\n"
            )
        f.write("\n## Formal Runs Selected\n\n")
        for tag, lam_t, lam_s in formal_specs:
            f.write(f"- `{tag}`: transition={lam_t}, stall={lam_s}, smooth=0\n")
    write_csv(e2_root / "e2_smoke_loss_scale.csv", rows)


def write_master_table(e2_root: Path, baseline: Dict[str, object], rows: List[Dict[str, object]]) -> None:
    baseline_row = {
        "run_tag": "baseline_lock",
        "lambda_transition_focal": 0.0,
        "lambda_stall_focal": 0.0,
        "lambda_theta_smooth": 0.0,
        "theta_smooth_status": "baseline",
        "eligible": "reference",
        "promotable": "reference",
        "rank_score": 0.0,
    }
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_pure",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_edge_p95_abs_err",
        "flat_peak_theta_error",
    ]:
        baseline_row[key] = baseline.get(key, float("nan"))
    all_rows = [baseline_row] + sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True)
    write_csv(e2_root / "hard_sample_loss_master_table.csv", all_rows)


def write_summary_and_decision(
    e2_root: Path,
    baseline: Dict[str, object],
    rows: List[Dict[str, object]],
    formal_specs: Iterable[Tuple[str, float, float]],
    high_scale: bool,
) -> Dict[str, object]:
    ranked = sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True)
    promotable = [r for r in ranked if truthy(r.get("promotable"))]
    eligible = [r for r in ranked if truthy(r.get("eligible"))]
    best = promotable[0] if promotable else (eligible[0] if eligible else ranked[0])
    decision = {
        "phase": "E2_hard_sample_focal_loss",
        "e2_status": "PASS",
        "method_label": "hard-sample focal only",
        "theta_smooth_status": THETA_SMOOTH_STATUS,
        "formal_grid": [tag for tag, _, _ in formal_specs],
        "high_loss_scale_detected": high_scale,
        "n_formal_runs": len(rows),
        "n_eligible_runs": len(eligible),
        "n_promotable_runs": len(promotable),
        "best_run_tag": best["run_tag"],
        "best_is_promotable": truthy(best.get("promotable")),
        "can_expand_seeds_42_101": bool(promotable),
        "can_enter_e3": True,
        "e3_loss_strategy": (
            {
                "source": "E2_best_promotable",
                "loss_mode": "fixed",
                "lambda_transition_focal": best["lambda_transition_focal"],
                "lambda_stall_focal": best["lambda_stall_focal"],
                "lambda_theta_smooth": 0.0,
                "run_tag": best["run_tag"],
            }
            if promotable
            else {
                "source": "baseline_fixed_loss",
                "loss_mode": "fixed",
                "reason": "E2 has no promotable run; continue E3 with original baseline fixed loss",
            }
        ),
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
        "ranking": [
            {
                "run_tag": r["run_tag"],
                "rank_score": r["rank_score"],
                "eligible": truthy(r.get("eligible")),
                "promotable": truthy(r.get("promotable")),
                "delta_acc_turn_transition": r["delta_acc_turn_transition"],
                "delta_stall_recall": r["delta_stall_recall"],
                "delta_theta_mae_deg": r["delta_theta_mae_deg"],
                "delta_theta_edge_p95_abs_err": r["delta_theta_edge_p95_abs_err"],
                "delta_flat_peak_theta_error": r["delta_flat_peak_theta_error"],
                "eligible_reason": r["eligible_reason"],
                "promotable_reason": r["promotable_reason"],
            }
            for r in ranked
        ],
    }
    (e2_root / "hard_sample_loss_decision.json").write_text(json.dumps(decision, indent=2, ensure_ascii=False), encoding="utf-8")
    write_summary_md(e2_root, baseline, decision, ranked)
    return decision


def write_summary_md(e2_root: Path, baseline: Dict[str, object], decision: Dict[str, object], ranked: List[Dict[str, object]]) -> None:
    with (e2_root / "hard_sample_loss_summary.md").open("w", encoding="utf-8") as f:
        f.write("# E2 Hard-Sample Focal Loss Summary\n\n")
        f.write(f"- E2 status: {decision['e2_status']}\n")
        f.write(f"- method label: `{decision['method_label']}`\n")
        f.write(f"- theta_smooth_status: `{decision['theta_smooth_status']}`\n")
        f.write(f"- eligible runs: {decision['n_eligible_runs']}\n")
        f.write(f"- promotable runs: {decision['n_promotable_runs']}\n")
        f.write(f"- can expand seeds 42/101: {decision['can_expand_seeds_42_101']}\n")
        f.write(f"- can enter E3: {decision['can_enter_e3']}\n")
        f.write("- no ONNX export: True\n")
        f.write("- no MATLAB/Simulink closed-loop: True\n")
        f.write("- no baseline overwrite: True\n\n")
        f.write("## Baseline\n\n")
        f.write(f"- acc_main: {baseline['acc_main']:.6f}\n")
        f.write(f"- acc_turn_transition: {baseline['acc_turn_transition']:.6f}\n")
        f.write(f"- stall_recall: {baseline['stall_recall']:.6f}\n")
        f.write(f"- theta_edge_p95_abs_err: {baseline['theta_edge_p95_abs_err']:.6f}\n")
        f.write(f"- flat_peak_theta_error: {baseline['flat_peak_theta_error']:.6f}\n\n")
        f.write("## Ranking\n\n")
        f.write("| rank | run | eligible | promotable | d_turn_transition | d_stall | d_theta_mae | d_edge | d_flat_peak | reason |\n")
        f.write("|---:|---|---|---|---:|---:|---:|---:|---:|---|\n")
        for idx, row in enumerate(ranked, start=1):
            f.write(
                f"| {idx} | {row['run_tag']} | {truthy(row.get('eligible'))} | {truthy(row.get('promotable'))} | "
                f"{row['delta_acc_turn_transition']:.6f} | {row['delta_stall_recall']:.6f} | "
                f"{row['delta_theta_mae_deg']:.6f} | {row['delta_theta_edge_p95_abs_err']:.6f} | "
                f"{row['delta_flat_peak_theta_error']:.6f} | {row['promotable_reason']} |\n"
            )
        f.write("\n## E3 Recommendation\n\n")
        f.write("```json\n")
        f.write(json.dumps(decision["e3_loss_strategy"], indent=2, ensure_ascii=False))
        f.write("\n```\n")


def write_failure(e2_root: Path, exc: BaseException) -> None:
    e2_root.mkdir(parents=True, exist_ok=True)
    text = [
        "# E2 Failure Report",
        "",
        f"- status: FAIL",
        f"- error_type: `{type(exc).__name__}`",
        f"- error: `{exc}`",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "- no baseline overwrite: True",
        "",
        "## Traceback",
        "",
        "```text",
        "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)),
        "```",
    ]
    (e2_root / "failure_report.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def read_json(path: Path) -> Dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    fieldnames: List[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def to_float(value: object) -> float:
    try:
        return float(value)
    except Exception:
        return float("nan")


def is_finite_number(value: object) -> bool:
    try:
        return math.isfinite(float(value))
    except Exception:
        return False


def truthy(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"true", "1", "yes"}


if __name__ == "__main__":
    sys.exit(main())
