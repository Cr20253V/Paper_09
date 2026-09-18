"""Run SCI E4 mode-conditioned theta expert experiments.

This runner is scoped to:
results/modern_tcn_sci_innovation/04_mode_conditioned_theta/

It does not export ONNX, does not call MATLAB/Simulink, and trains only the
three seed21 flat-theta regularization probes requested for E4.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import numpy as np
import torch
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics, multitask_loss_components
from modern_tcn_model import build_model_from_checkpoint_dict, build_model_from_config
from train_modern_tcn import _build_config, _select_device, _set_seed, _to_device, train_one_seed


DATASET_REL = Path("data") / "tcn" / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
E0_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "e0_decision.json"
E1_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "loss_optimization_decision.json"
E1_BASE_CONFIG_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "uncertainty_seed21" / "config.json"
E2_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "02_hard_sample_loss" / "hard_sample_loss_decision.json"
E3_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "03_physics_group_gate" / "physics_group_gate_decision.json"
BASELINE_CSV_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "baseline_offline_metrics.csv"
BASELINE_CKPT_REL = (
    Path("results")
    / "paper"
    / "agv_model_parameter_correction_workflow"
    / "08_models"
    / "modern_tcn"
    / "modern_tcn_v5_plantfix_turn_l020_tt25_tcm14_stw055_slrw060_seed101"
    / "modern_tcn_seed101.pt"
)
E4_REL = Path("results") / "modern_tcn_sci_innovation" / "04_mode_conditioned_theta"

MAIN_NAMES = ["flat", "stall", "slope"]
THETA_BINS = [
    ("near_zero_abs_le_0p5", -0.5, 0.5),
    ("small_neg_2_0p5", -2.0, -0.5),
    ("small_pos_0p5_2", 0.5, 2.0),
    ("mid_neg_8_2", -8.0, -2.0),
    ("mid_pos_2_8", 2.0, 8.0),
    ("edge_neg_10_8", -10.0, -8.0),
    ("edge_pos_8_10", 8.0, 10.0),
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

REQUIRED_RUN_FILES = [
    "modern_tcn_mode_theta_seed21.pt",
    "modern_tcn_mode_theta_seed21_summary.csv",
    "modern_tcn_mode_theta_seed21_history.csv",
    "config.json",
    "git_hash.txt",
    "dataset_contract_copy.json",
    "feature_names.txt",
    "ModernTCNModeTheta_train_report.md",
    "theta_mae_by_true_main.csv",
    "theta_mae_by_pred_main.csv",
    "theta_mae_by_theta_bin.csv",
    "expert_contribution_statistics.json",
    "expert_differentiation_statistics.json",
    "main_confusion_matrix.csv",
    "mode_theta_run_decision.json",
]


@dataclass(frozen=True)
class RunSpec:
    tag: str
    flat_reg_lambda: float


FORMAL_SPECS = [
    RunSpec("mode_theta_detach_flatreg000_seed21", 0.0),
    RunSpec("mode_theta_detach_flatreg001_seed21", 0.01),
    RunSpec("mode_theta_detach_flatreg003_seed21", 0.03),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ModernTCN SCI E4 mode-conditioned theta workflow.")
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
    e4_root = root / E4_REL
    e4_root.mkdir(parents=True, exist_ok=True)
    try:
        decision = run_workflow(root, e4_root, args)
    except Exception as exc:
        write_failure(e4_root, exc)
        raise
    print(json.dumps(decision, indent=2, ensure_ascii=False))
    return 0


def run_workflow(root: Path, e4_root: Path, args: argparse.Namespace) -> Dict[str, object]:
    stale_failure = e4_root / "failure_report.md"
    if stale_failure.exists():
        stale_failure.unlink()
    e0 = read_json(root / E0_DECISION_REL)
    e1 = read_json(root / E1_DECISION_REL)
    e2 = read_json(root / E2_DECISION_REL)
    e3 = read_json(root / E3_DECISION_REL)
    base_cli = read_json(root / E1_BASE_CONFIG_REL)["cli_args"]
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    contract = data["contract"]
    baseline = load_baseline(root)

    checks = preflight_checks(root, e4_root, e0, e1, e2, e3, contract, baseline, FORMAL_SPECS)
    baseline_detail = baseline_checkpoint_metrics(root, args.device)
    baseline.update(baseline_detail["metrics"])
    write_preflight(e4_root, checks, baseline, baseline_detail, contract)
    if checks["failure_reasons"]:
        raise RuntimeError("E4 preflight failed: " + "; ".join(checks["failure_reasons"]))

    smoke_rows = run_smoke(root, e4_root, base_cli, args)
    write_smoke_report(e4_root, smoke_rows)

    formal_rows: List[Dict[str, object]] = []
    if not args.skip_formal:
        for spec in FORMAL_SPECS:
            train_args = make_train_args(
                root=root,
                e4_root=e4_root,
                base_cli=base_cli,
                run_tag=spec.tag,
                flat_reg_lambda=spec.flat_reg_lambda,
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
                no_overwrite=True,
                dry_run=False,
            )
            result = train_one_seed(train_args)
            formal_rows.append(formal_row(root, e4_root, spec, result, baseline, args.device))

    if formal_rows:
        write_master_table(e4_root, baseline, formal_rows)
        decision = write_summary_decision_handoff(e4_root, baseline, formal_rows)
    else:
        decision = {
            "phase": "E4_mode_conditioned_theta",
            "e4_status": "PASS_SMOKE_ONLY",
            "formal_runs_executed": False,
            "can_expand_seeds_42_101": False,
            "can_enter_e5": False,
            "reason": "skip_formal was used",
        }
        (e4_root / "mode_theta_decision.json").write_text(
            json.dumps(decision, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return decision


def preflight_checks(
    root: Path,
    e4_root: Path,
    e0: Dict[str, object],
    e1: Dict[str, object],
    e2: Dict[str, object],
    e3: Dict[str, object],
    contract,
    baseline: Dict[str, object],
    specs: Sequence[RunSpec],
) -> Dict[str, object]:
    failures: List[str] = []
    if e0.get("decision") != "PASS":
        failures.append("E0 decision is not PASS")
    if e1.get("e1_status") != "PASS" or e1.get("best_loss_mode") != "fixed":
        failures.append("E1 does not freeze fixed loss for E4")
    if e2.get("e2_status") != "PASS":
        failures.append("E2 status is not PASS")
    if e3.get("e3_status") != "PASS" or not bool(e3.get("can_enter_e4", False)):
        failures.append("E3 decision does not allow E4")
    strategy = e3.get("e4_base_strategy", {})
    if strategy.get("source") != "baseline_fixed_loss" or strategy.get("model_family") != "small":
        failures.append("E3 e4_base_strategy is not baseline fixed small")
    if int(contract.input_dim) != 22:
        failures.append(f"dataset input_dim is {contract.input_dim}, expected 22")
    if int(contract.seq_len) != 128:
        failures.append(f"dataset seq_len is {contract.seq_len}, expected 128")
    if str(contract.feature_contract) != "passive17_plus_all5":
        failures.append(f"feature_contract is {contract.feature_contract}, expected passive17_plus_all5")
    for key in ["theta_edge_p95_abs_err", "flat_peak_theta_error"]:
        if not is_finite_number(baseline.get(key)):
            failures.append(f"baseline {key} is missing or nan")
    for spec in specs:
        run_dir = e4_root / spec.tag
        if run_dir.exists() and any(run_dir.iterdir()):
            failures.append(f"output run directory would be overwritten: {run_dir}")
    return {
        "failure_reasons": failures,
        "baseline_checkpoint": str(root / BASELINE_CKPT_REL),
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
        "loss_mode": "fixed",
        "base_model_family": "small",
        "explicit_e1_e2_e3_disabled": True,
    }


def run_smoke(root: Path, e4_root: Path, base_cli: Dict[str, object], args: argparse.Namespace) -> List[Dict[str, object]]:
    rows = [
        run_dry_run(root, e4_root, base_cli, args, "small_dry_run", "small"),
        run_dry_run(root, e4_root, base_cli, args, "small_mode_theta_dry_run", "small_mode_theta"),
        baseline_checkpoint_regression(root, args.device),
        detach_gradient_probe(root, base_cli, args.device),
        no_overwrite_probe(root, e4_root, base_cli, args),
        expert_stats_probe(root, e4_root, base_cli, args),
    ]
    return rows


def run_dry_run(
    root: Path,
    e4_root: Path,
    base_cli: Dict[str, object],
    args: argparse.Namespace,
    tag: str,
    family: str,
) -> Dict[str, object]:
    train_args = make_train_args(
        root=root,
        e4_root=e4_root / "_smoke",
        base_cli=base_cli,
        run_tag=tag,
        flat_reg_lambda=0.0,
        seed=21,
        epochs=args.smoke_epochs,
        min_epochs=1,
        patience=1,
        batch_size=64,
        limit_train=64,
        limit_val=64,
        limit_test=64,
        device=args.device,
        num_workers=0,
        no_overwrite=False,
        dry_run=True,
    )
    train_args.model_family = family
    result = train_one_seed(train_args)
    return {"check": tag, "status": result.get("status", "ok"), "detail": "dry_run forward ok"}


def baseline_checkpoint_regression(root: Path, device_mode: str) -> Dict[str, object]:
    ckpt_path = root / BASELINE_CKPT_REL
    if not ckpt_path.exists():
        raise FileNotFoundError(f"baseline checkpoint not found: {ckpt_path}")
    device = _select_device(device_mode)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).to(device)
    model.eval()
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=4, limit_val=4, limit_test=4)
    xb = torch.from_numpy(data["train"].X[:4]).float().to(device)
    with torch.no_grad():
        outputs = model(xb)
    shapes = [tuple(o.shape) for o in outputs]
    expected = [(4, 3), (4, 3), (4, 1)]
    if shapes != expected:
        raise RuntimeError(f"baseline checkpoint output shapes changed: {shapes} != {expected}")
    return {"check": "baseline_checkpoint_regression", "status": "PASS", "detail": str(shapes)}


def detach_gradient_probe(root: Path, base_cli: Dict[str, object], device_mode: str) -> Dict[str, object]:
    device = _select_device(device_mode)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=32, limit_val=16, limit_test=16)
    args = make_train_args(
        root=root,
        e4_root=root / E4_REL / "_smoke",
        base_cli=base_cli,
        run_tag="detach_gradient_probe",
        flat_reg_lambda=0.0,
        seed=21,
        epochs=1,
        min_epochs=1,
        patience=1,
        batch_size=32,
        limit_train=32,
        limit_val=16,
        limit_test=16,
        device=device_mode,
        num_workers=0,
        no_overwrite=False,
        dry_run=False,
    )
    cfg = _build_config(args, data["contract"], "small_mode_theta")
    xb = torch.from_numpy(data["train"].X[:16]).float().to(device)

    def main_head_grad_sum(detach: bool) -> float:
        _set_seed(123)
        model = build_model_from_config(cfg, "small_mode_theta").to(device)
        details = model.forward_experts(xb, detach_override=detach)
        theta_hat = details["theta_hat"]
        loss = (theta_hat.reshape(-1) ** 2).mean()
        model.zero_grad(set_to_none=True)
        loss.backward()
        total = 0.0
        for param in model.main_head.parameters():
            if param.grad is not None:
                total += float(param.grad.detach().abs().sum().cpu())
        return total

    detached_grad = main_head_grad_sum(True)
    attached_grad = main_head_grad_sum(False)
    if detached_grad > 1e-10:
        raise RuntimeError(f"theta_gate_detach=True leaked main_head grad: {detached_grad}")
    if attached_grad <= 1e-10:
        raise RuntimeError("theta_gate_detach=False did not produce detectable main_head grad")
    return {
        "check": "detach_gradient_probe",
        "status": "PASS",
        "detail": f"detached_grad={detached_grad:.3e}, attached_grad={attached_grad:.3e}",
    }


def no_overwrite_probe(root: Path, e4_root: Path, base_cli: Dict[str, object], args: argparse.Namespace) -> Dict[str, object]:
    probe = e4_root / "__no_overwrite_probe__"
    probe.mkdir(parents=True, exist_ok=True)
    (probe / "marker.txt").write_text("probe\n", encoding="utf-8")
    try:
        train_args = make_train_args(
            root=root,
            e4_root=e4_root,
            base_cli=base_cli,
            run_tag=probe.name,
            flat_reg_lambda=0.0,
            seed=21,
            epochs=1,
            min_epochs=1,
            patience=1,
            batch_size=16,
            limit_train=16,
            limit_val=16,
            limit_test=16,
            device=args.device,
            num_workers=0,
            no_overwrite=True,
            dry_run=False,
        )
        try:
            train_one_seed(train_args)
        except FileExistsError:
            return {"check": "no_overwrite_probe", "status": "PASS", "detail": "existing non-empty dir rejected"}
        raise RuntimeError("--no-overwrite did not reject an existing non-empty E4 run directory")
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def expert_stats_probe(root: Path, e4_root: Path, base_cli: Dict[str, object], args: argparse.Namespace) -> Dict[str, object]:
    tag = "expert_stats_probe"
    probe_dir = e4_root / "_smoke" / tag
    if probe_dir.exists():
        shutil.rmtree(probe_dir)
    train_args = make_train_args(
        root=root,
        e4_root=e4_root / "_smoke",
        base_cli=base_cli,
        run_tag=tag,
        flat_reg_lambda=0.01,
        seed=21,
        epochs=max(int(args.smoke_epochs), 1),
        min_epochs=1,
        patience=1,
        batch_size=64,
        limit_train=128,
        limit_val=64,
        limit_test=64,
        device=args.device,
        num_workers=0,
        no_overwrite=True,
        dry_run=False,
    )
    result = train_one_seed(train_args)
    write_run_e4_artifacts(root, probe_dir, result["checkpoint_file"], "expert_stats_probe", baseline=None, device_mode=args.device)
    stats_file = probe_dir / "expert_differentiation_statistics.json"
    if not stats_file.exists():
        raise RuntimeError("expert stats probe did not produce expert_differentiation_statistics.json")
    return {"check": "expert_stats_probe", "status": "PASS", "detail": str(stats_file)}


def make_train_args(
    root: Path,
    e4_root: Path,
    base_cli: Dict[str, object],
    run_tag: str,
    flat_reg_lambda: float,
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
    no_overwrite: bool,
    dry_run: bool,
) -> argparse.Namespace:
    values = dict(base_cli)
    values.update(
        {
            "seed": int(seed),
            "model_family": "small_mode_theta",
            "dataset_file": str(root / DATASET_REL),
            "output_root": str(e4_root),
            "run_tag": run_tag,
            "no_overwrite": bool(no_overwrite),
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
            "dry_run": bool(dry_run),
            "lambda_transition_focal": 0.0,
            "lambda_stall_focal": 0.0,
            "lambda_theta_smooth": 0.0,
            "focal_gamma": 2.0,
            "theta_smooth_mode": "off",
            "theta_gate_detach": True,
            "flat_theta_reg_lambda": float(flat_reg_lambda),
            "theta_expert_hidden": 0,
        }
    )
    return argparse.Namespace(**values)


def baseline_checkpoint_metrics(root: Path, device_mode: str) -> Dict[str, object]:
    ckpt_path = root / BASELINE_CKPT_REL
    device = _select_device(device_mode)
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).to(device)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    split = data["test"]
    loader = DataLoader(AGVWindowDataset(split), batch_size=512, shuffle=False, num_workers=0)
    cfg = model.cfg
    class_w_main = class_weights(data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)).to(device)
    class_w_turn = class_weights(data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)).to(device)
    logits_main, logits_turn, theta_hat, loss_parts = predict_arrays(model, loader, split, device, class_w_main, class_w_turn, cfg)
    metrics = compute_metrics(logits_main, logits_turn, theta_hat, split, loss_parts["loss_total"])
    metrics.update({k: v for k, v in loss_parts.items() if k != "loss_total"})
    pred_main = np.asarray(logits_main).argmax(axis=1)
    detail = {
        "checkpoint": str(ckpt_path),
        "metrics": {
            "by_true_main": theta_mae_by_main(theta_hat, split.y_theta, split.y_main),
            "by_pred_main": theta_mae_by_main(theta_hat, split.y_theta, pred_main),
            "by_theta_bin": theta_mae_by_bin(theta_hat, split.y_theta),
        },
    }
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_neg_10_8_p95_abs_err_deg",
        "theta_pos_8_10_p95_abs_err_deg",
        "theta_flat_abs_max_deg",
    ]:
        detail["metrics"][key] = metrics.get(key)
    return detail


@torch.no_grad()
def predict_arrays(model, loader, split, device, class_w_main, class_w_turn, cfg):
    model.eval()
    logits_main_all = []
    logits_turn_all = []
    theta_all = []
    loss_sum = 0.0
    n_sum = 0
    part_sums: Dict[str, float] = {}
    for batch in loader:
        batch = _to_device(batch, device)
        if hasattr(model, "forward_experts"):
            details = model.forward_experts(batch["X"])
            logits_main = details["logits_main"]
            logits_turn = details["logits_turn"]
            theta_hat = details["theta_hat"]
            extra = details
        else:
            logits_main, logits_turn, theta_hat = model(batch["X"])
            extra = None
        loss, parts = multitask_loss_components(
            logits_main,
            logits_turn,
            theta_hat,
            batch,
            class_w_main,
            class_w_turn,
            cfg,
            extra_outputs=extra,
        )
        n = int(batch["X"].shape[0])
        loss_sum += float(loss.detach().cpu()) * n
        n_sum += n
        for key, value in parts.items():
            part_sums[key] = part_sums.get(key, 0.0) + float(value.detach().cpu()) * n
        logits_main_all.append(logits_main.detach().cpu().numpy())
        logits_turn_all.append(logits_turn.detach().cpu().numpy())
        theta_all.append(theta_hat.detach().cpu().numpy())
    loss_parts = {key: value / max(n_sum, 1) for key, value in part_sums.items()}
    loss_parts["loss_total"] = loss_sum / max(n_sum, 1)
    return (
        np.concatenate(logits_main_all, axis=0),
        np.concatenate(logits_turn_all, axis=0),
        np.concatenate(theta_all, axis=0).reshape(-1),
        loss_parts,
    )


@torch.no_grad()
def collect_expert_arrays(model, loader, device) -> Dict[str, np.ndarray]:
    if not hasattr(model, "forward_experts"):
        return {}
    model.eval()
    keys = ["theta_experts", "theta_contributions", "main_prob", "theta_hat", "logits_main"]
    acc = {key: [] for key in keys}
    for batch in loader:
        batch = _to_device(batch, device)
        details = model.forward_experts(batch["X"])
        for key in keys:
            acc[key].append(details[key].detach().cpu().numpy())
    return {key: np.concatenate(values, axis=0) for key, values in acc.items()}


def formal_row(
    root: Path,
    e4_root: Path,
    spec: RunSpec,
    result: Dict[str, object],
    baseline: Dict[str, object],
    device_mode: str,
) -> Dict[str, object]:
    run_dir = e4_root / spec.tag
    write_run_e4_artifacts(root, run_dir, result["checkpoint_file"], spec.tag, baseline, device_mode)
    row = dict(read_csv_rows(run_dir / "modern_tcn_mode_theta_seed21_summary.csv")[0])
    row["run_tag"] = spec.tag
    row["flat_theta_reg_lambda"] = spec.flat_reg_lambda
    row["missing_required_files"] = ""
    row["artifact_complete"] = True
    by_true = read_csv_rows(run_dir / "theta_mae_by_true_main.csv")
    diff_stats = read_json(run_dir / "expert_differentiation_statistics.json")
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_edge_p95_abs_err",
        "flat_peak_theta_error",
    ]:
        row[key] = to_float(row.get(key))
        row[f"delta_{key}"] = row[key] - baseline[key]
    row["delta_theta_mae_improvement"] = baseline["theta_mae_deg"] - row["theta_mae_deg"]
    row["delta_edge_improvement"] = baseline["theta_edge_p95_abs_err"] - row["theta_edge_p95_abs_err"]
    row["delta_flat_peak_improvement"] = baseline["flat_peak_theta_error"] - row["flat_peak_theta_error"]
    for label in MAIN_NAMES:
        value = find_row_value(by_true, "label", label, "mae_deg")
        base_value = baseline.get("by_true_main", {}).get(label, {}).get("mae_deg", float("nan"))
        row[f"theta_mae_true_{label}"] = value
        row[f"delta_theta_mae_true_{label}_improvement"] = base_value - value if is_finite_number(base_value) else float("nan")
    row["expert_not_differentiated"] = bool(diff_stats.get("not_differentiated", False))
    row["expert_pairwise_mae_max_deg"] = to_float(diff_stats.get("expert_pairwise_mae_max_deg"))
    row["expert_pairwise_corr_min"] = to_float(diff_stats.get("expert_pairwise_corr_min"))
    row["mean_abs_theta_flat_minus_theta_slope_deg"] = to_float(diff_stats.get("mean_abs_theta_flat_minus_theta_slope_deg"))
    safe, safe_reason = safe_eligible_status(row, baseline)
    promotable, promotable_reason = promotable_status(row, baseline, safe)
    row["safe_eligible"] = safe
    row["safe_eligible_reason"] = safe_reason
    row["promotable"] = promotable
    row["promotable_reason"] = promotable_reason
    row["rank_score"] = rank_score(row)
    run_decision = {
        "run_tag": spec.tag,
        "safe_eligible": safe,
        "safe_eligible_reason": safe_reason,
        "promotable": promotable,
        "promotable_reason": promotable_reason,
        "expert_not_differentiated": row["expert_not_differentiated"],
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
    }
    (run_dir / "mode_theta_run_decision.json").write_text(
        json.dumps(run_decision, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    missing = [name for name in REQUIRED_RUN_FILES if not (run_dir / name).exists()]
    row["missing_required_files"] = ";".join(missing)
    row["artifact_complete"] = not missing
    if missing:
        row["safe_eligible"] = False
        row["safe_eligible_reason"] = "missing required artifacts: " + ";".join(missing)
        row["promotable"] = False
        row["promotable_reason"] = "not safe_eligible"
    return row


def write_run_e4_artifacts(
    root: Path,
    run_dir: Path,
    checkpoint_file: str,
    run_tag: str,
    baseline: Dict[str, object] | None,
    device_mode: str,
) -> None:
    device = _select_device(device_mode)
    ckpt = torch.load(checkpoint_file, map_location=device, weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).to(device)
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    split = data["test"]
    loader = DataLoader(AGVWindowDataset(split), batch_size=512, shuffle=False, num_workers=0)
    cfg = model.cfg
    class_w_main = class_weights(data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)).to(device)
    class_w_turn = class_weights(data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)).to(device)
    logits_main, logits_turn, theta_hat, loss_parts = predict_arrays(model, loader, split, device, class_w_main, class_w_turn, cfg)
    metrics = compute_metrics(logits_main, logits_turn, theta_hat, split, loss_parts["loss_total"])
    pred_main = np.asarray(logits_main).argmax(axis=1)
    expert = collect_expert_arrays(model, loader, device)
    write_csv(run_dir / "theta_mae_by_true_main.csv", theta_mae_by_main_rows(theta_hat, split.y_theta, split.y_main))
    write_csv(run_dir / "theta_mae_by_pred_main.csv", theta_mae_by_main_rows(theta_hat, split.y_theta, pred_main))
    write_csv(run_dir / "theta_mae_by_theta_bin.csv", theta_mae_by_bin_rows(theta_hat, split.y_theta))
    write_csv(run_dir / "main_confusion_matrix.csv", confusion_rows(metrics.get("cm_main", []), MAIN_NAMES))
    contribution = expert_contribution_statistics(expert, split.y_main, pred_main)
    differentiation = expert_differentiation_statistics(expert, split.y_main, pred_main)
    (run_dir / "expert_contribution_statistics.json").write_text(
        json.dumps(contribution, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (run_dir / "expert_differentiation_statistics.json").write_text(
        json.dumps(differentiation, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def theta_mae_by_main_rows(theta_hat, theta_true, labels) -> List[Dict[str, object]]:
    theta_hat = np.asarray(theta_hat).reshape(-1)
    theta_true = np.asarray(theta_true).reshape(-1)
    labels = np.asarray(labels).reshape(-1)
    rows = []
    for idx, name in enumerate(MAIN_NAMES):
        mask = labels == idx
        rows.append(theta_error_row(name, theta_hat, theta_true, mask))
    return rows


def theta_mae_by_main(theta_hat, theta_true, labels) -> Dict[str, Dict[str, object]]:
    return {row["label"]: row for row in theta_mae_by_main_rows(theta_hat, theta_true, labels)}


def theta_mae_by_bin_rows(theta_hat, theta_true) -> List[Dict[str, object]]:
    theta_hat = np.asarray(theta_hat).reshape(-1)
    theta_true = np.asarray(theta_true).reshape(-1)
    theta_deg = np.rad2deg(theta_true)
    rows = []
    for name, lo, hi in THETA_BINS:
        if lo < 0 < hi:
            mask = (theta_deg >= lo) & (theta_deg <= hi)
        else:
            mask = (theta_deg >= lo) & (theta_deg < hi)
        rows.append(theta_error_row(name, theta_hat, theta_true, mask))
    return rows


def theta_mae_by_bin(theta_hat, theta_true) -> Dict[str, Dict[str, object]]:
    return {row["label"]: row for row in theta_mae_by_bin_rows(theta_hat, theta_true)}


def theta_error_row(label: str, theta_hat, theta_true, mask) -> Dict[str, object]:
    mask = np.asarray(mask).reshape(-1).astype(bool)
    if not mask.any():
        return {"label": label, "n": 0, "mae_deg": float("nan"), "p95_abs_err_deg": float("nan"), "bias_deg": float("nan")}
    err_deg = np.rad2deg(np.asarray(theta_hat).reshape(-1)[mask] - np.asarray(theta_true).reshape(-1)[mask])
    return {
        "label": label,
        "n": int(mask.sum()),
        "mae_deg": float(np.mean(np.abs(err_deg))),
        "p95_abs_err_deg": float(np.percentile(np.abs(err_deg), 95)),
        "bias_deg": float(np.mean(err_deg)),
    }


def expert_contribution_statistics(expert: Dict[str, np.ndarray], y_true, y_pred) -> Dict[str, object]:
    experts_deg = np.rad2deg(np.asarray(expert["theta_experts"]))
    contrib_deg = np.rad2deg(np.asarray(expert["theta_contributions"]))
    probs = np.asarray(expert["main_prob"])
    y_true = np.asarray(y_true).reshape(-1)
    y_pred = np.asarray(y_pred).reshape(-1)
    payload: Dict[str, object] = {
        "overall": contribution_summary(experts_deg, contrib_deg, probs),
        "by_true_main": {},
        "by_pred_main": {},
    }
    for idx, name in enumerate(MAIN_NAMES):
        payload["by_true_main"][name] = contribution_summary(experts_deg[y_true == idx], contrib_deg[y_true == idx], probs[y_true == idx])
        payload["by_pred_main"][name] = contribution_summary(experts_deg[y_pred == idx], contrib_deg[y_pred == idx], probs[y_pred == idx])
    return payload


def contribution_summary(experts_deg, contrib_deg, probs) -> Dict[str, object]:
    if np.asarray(experts_deg).size == 0:
        return {"n": 0}
    abs_contrib = np.abs(contrib_deg)
    denom = np.maximum(abs_contrib.sum(axis=1, keepdims=True), 1e-12)
    share = abs_contrib / denom
    entropy = -np.sum(probs * np.log(np.clip(probs, 1e-12, 1.0)), axis=1)
    return {
        "n": int(experts_deg.shape[0]),
        "expert_mean_deg": dict(zip(MAIN_NAMES, [float(x) for x in experts_deg.mean(axis=0)])),
        "expert_std_deg": dict(zip(MAIN_NAMES, [float(x) for x in experts_deg.std(axis=0)])),
        "contribution_mean_deg": dict(zip(MAIN_NAMES, [float(x) for x in contrib_deg.mean(axis=0)])),
        "contribution_abs_share_mean": dict(zip(MAIN_NAMES, [float(x) for x in share.mean(axis=0)])),
        "main_prob_mean": dict(zip(MAIN_NAMES, [float(x) for x in probs.mean(axis=0)])),
        "p_main_entropy_mean": float(entropy.mean()),
    }


def expert_differentiation_statistics(expert: Dict[str, np.ndarray], y_true, y_pred) -> Dict[str, object]:
    experts_deg = np.rad2deg(np.asarray(expert["theta_experts"]))
    probs = np.asarray(expert["main_prob"])
    pairs = [(0, 1, "flat_stall"), (0, 2, "flat_slope"), (1, 2, "stall_slope")]
    pairwise_corr = {}
    pairwise_mae = {}
    for a, b, name in pairs:
        if experts_deg.shape[0] < 2 or np.std(experts_deg[:, a]) < 1e-12 or np.std(experts_deg[:, b]) < 1e-12:
            corr = float("nan")
        else:
            corr = float(np.corrcoef(experts_deg[:, a], experts_deg[:, b])[0, 1])
        pairwise_corr[name] = corr
        pairwise_mae[name] = float(np.mean(np.abs(experts_deg[:, a] - experts_deg[:, b])))
    contribution = expert_contribution_statistics(expert, y_true, y_pred)
    by_true_share = contribution["by_true_main"]
    share_delta = max_contribution_share_delta(by_true_share)
    corr_values = [v for v in pairwise_corr.values() if is_finite_number(v)]
    mae_values = [v for v in pairwise_mae.values() if is_finite_number(v)]
    not_diff = bool(
        mae_values
        and max(mae_values) < 0.05
        and corr_values
        and min(corr_values) > 0.995
        and share_delta < 0.05
    )
    entropy = -np.sum(probs * np.log(np.clip(probs, 1e-12, 1.0)), axis=1)
    return {
        "expert_pairwise_corr": pairwise_corr,
        "expert_pairwise_mae_deg": pairwise_mae,
        "expert_pairwise_corr_min": min(corr_values) if corr_values else float("nan"),
        "expert_pairwise_mae_max_deg": max(mae_values) if mae_values else float("nan"),
        "mean_abs_theta_flat_minus_theta_slope_deg": pairwise_mae["flat_slope"],
        "dominant_expert_by_true_main": dominant_expert_by_group(contribution["by_true_main"]),
        "dominant_expert_by_pred_main": dominant_expert_by_group(contribution["by_pred_main"]),
        "p_main_entropy": {
            "mean": float(entropy.mean()),
            "std": float(entropy.std()),
        },
        "contribution_share_max_delta_by_true_main": share_delta,
        "not_differentiated": not_diff,
        "not_differentiated_rule": "max pairwise MAE < 0.05 deg and min corr > 0.995 and contribution share delta < 0.05",
    }


def max_contribution_share_delta(by_group: Dict[str, object]) -> float:
    values = []
    for summary in by_group.values():
        share = summary.get("contribution_abs_share_mean", {}) if isinstance(summary, dict) else {}
        if share:
            values.append([float(share.get(name, float("nan"))) for name in MAIN_NAMES])
    arr = np.asarray(values, dtype=float)
    if arr.size == 0 or not np.isfinite(arr).any():
        return float("nan")
    return float(np.nanmax(arr, axis=0).max() - np.nanmin(arr, axis=0).min())


def dominant_expert_by_group(by_group: Dict[str, object]) -> Dict[str, str]:
    out = {}
    for label, summary in by_group.items():
        share = summary.get("contribution_abs_share_mean", {}) if isinstance(summary, dict) else {}
        if not share:
            out[label] = ""
            continue
        out[label] = max(MAIN_NAMES, key=lambda name: float(share.get(name, -math.inf)))
    return out


def confusion_rows(cm, names: Sequence[str]) -> List[Dict[str, object]]:
    rows = []
    for i, row in enumerate(cm):
        item = {"truth": names[i] if i < len(names) else str(i)}
        for j, value in enumerate(row):
            item[f"pred_{names[j] if j < len(names) else j}"] = int(value)
        rows.append(item)
    return rows


def safe_eligible_status(row: Dict[str, object], baseline: Dict[str, object]) -> Tuple[bool, str]:
    checks = [
        ("acc_main", row["acc_main"], ">=", baseline["acc_main"] - 0.003),
        ("flat_recall", row["flat_recall"], ">=", baseline["flat_recall"] - 0.010),
        ("stall_recall", row["stall_recall"], ">=", baseline["stall_recall"] - 0.050),
        ("slope_recall", row["slope_recall"], ">=", baseline["slope_recall"] - 0.005),
        ("acc_turn", row["acc_turn"], ">=", baseline["acc_turn"] - 0.005),
        ("acc_turn_transition", row["acc_turn_transition"], ">=", baseline["acc_turn_transition"] - 0.010),
        ("theta_mae_deg", row["theta_mae_deg"], "<=", baseline["theta_mae_deg"] + 0.020),
        ("flat_peak_theta_error", row["flat_peak_theta_error"], "<=", baseline["flat_peak_theta_error"] + 0.300),
        ("theta_edge_p95_abs_err", row["theta_edge_p95_abs_err"], "<=", baseline["theta_edge_p95_abs_err"] + 0.300),
    ]
    failures = []
    if not bool(row.get("artifact_complete", False)):
        failures.append("missing required artifacts")
    for key, actual, op, threshold in checks:
        passed = actual >= threshold if op == ">=" else actual <= threshold
        if not passed:
            failures.append(f"{key} {op} {threshold:.6f}, actual {actual:.6f}")
    return not failures, "; ".join(failures) if failures else "safe protection metrics pass"


def promotable_status(row: Dict[str, object], baseline: Dict[str, object], safe_eligible: bool) -> Tuple[bool, str]:
    if not safe_eligible:
        return False, "not safe_eligible"
    theta_improvements = [
        row["delta_theta_mae_improvement"] >= 0.005,
        row["delta_flat_peak_improvement"] >= 0.10,
        row["delta_edge_improvement"] >= 0.10,
        by_class_improvement(row),
    ]
    if row["theta_mae_true_stall"] - baseline.get("by_true_main", {}).get("stall", {}).get("mae_deg", math.inf) > 0.05:
        return False, "stall theta by-class degraded > 0.05 deg"
    if row["theta_mae_true_slope"] - baseline.get("by_true_main", {}).get("slope", {}).get("mae_deg", math.inf) > 0.05:
        return False, "slope theta by-class degraded > 0.05 deg"
    if any(theta_improvements):
        return True, "safe_eligible with clear theta improvement"
    return False, "safe_eligible but no clear theta improvement"


def by_class_improvement(row: Dict[str, object]) -> bool:
    deltas = [to_float(row.get(f"delta_theta_mae_true_{name}_improvement")) for name in MAIN_NAMES]
    finite = [x for x in deltas if is_finite_number(x)]
    if not finite:
        return False
    return min(finite) >= -0.05 and max(finite) >= 0.03


def rank_score(row: Dict[str, object]) -> float:
    return (
        1.0 * row["delta_theta_mae_improvement"]
        + 0.5 * row["delta_flat_peak_improvement"]
        + 0.5 * row["delta_edge_improvement"]
        + 2.0 * (row["acc_main"] - BASELINE_THRESHOLDS["acc_main"])
        + 0.5 * (row["acc_turn_transition"] - BASELINE_THRESHOLDS["acc_turn_transition"])
        - (0.1 if row.get("expert_not_differentiated") else 0.0)
    )


def load_baseline(root: Path) -> Dict[str, object]:
    row = read_csv_rows(root / BASELINE_CSV_REL)[0]
    out = {key: float(value) for key, value in BASELINE_THRESHOLDS.items()}
    for key in ["acc_main", "acc_turn", "acc_turn_transition", "theta_mae_deg", "flat_recall", "stall_recall", "slope_recall"]:
        if key in row and is_finite_number(row[key]):
            out[key] = to_float(row[key])
    source = Path(str(row.get("source", "")))
    if source and not source.is_absolute():
        source = root / source
    if source.exists():
        champ = read_csv_rows(source)[0]
        out["baseline_summary_source"] = str(source)
        neg = to_float(champ.get("theta_neg_10_8_p95_abs_err_deg"))
        pos = to_float(champ.get("theta_pos_8_10_p95_abs_err_deg"))
        if is_finite_number(neg) and is_finite_number(pos):
            out["theta_edge_p95_abs_err"] = max(neg, pos)
        flat_peak = to_float(champ.get("theta_flat_abs_max_deg"))
        if is_finite_number(flat_peak):
            out["flat_peak_theta_error"] = flat_peak
    else:
        out["baseline_summary_source"] = str(source)
    return out


def write_preflight(e4_root: Path, checks: Dict[str, object], baseline: Dict[str, object], baseline_detail: Dict[str, object], contract) -> None:
    lines = [
        "# E4 Engineering Preflight",
        "",
        f"- status: {'FAIL' if checks['failure_reasons'] else 'PASS'}",
        "- scope: E4 / 04_mode_conditioned_theta only; no ONNX; no MATLAB/Simulink.",
        "- base strategy: `small + fixed loss` from frozen baseline.",
        "- model_family: `small_mode_theta`",
        "- formal runs: `flatreg000`, `flatreg001`, `flatreg003`, seed21 only.",
        f"- dataset input: `[batch,{contract.seq_len},{contract.input_dim}]`",
        f"- feature_contract: `{contract.feature_contract}`",
        f"- baseline checkpoint: `{checks['baseline_checkpoint']}`",
        "",
        "## Baseline Reference",
        "",
    ]
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_edge_p95_abs_err",
        "flat_peak_theta_error",
    ]:
        lines.append(f"- {key}: {baseline[key]}")
    lines.extend(["", "## Baseline E4-Aligned Theta Metrics", "", "```json"])
    lines.append(json.dumps(baseline_detail["metrics"], indent=2, ensure_ascii=False))
    lines.append("```")
    if checks["failure_reasons"]:
        lines.extend(["", "## Failure Reasons", ""])
        lines.extend(f"- {x}" for x in checks["failure_reasons"])
    (e4_root / "e4_preflight.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_smoke_report(e4_root: Path, rows: List[Dict[str, object]]) -> None:
    lines = [
        "# E4 Smoke Report",
        "",
        "- status: PASS",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "",
        "| check | status | detail |",
        "|---|---|---|",
    ]
    for row in rows:
        lines.append(f"| `{row['check']}` | `{row['status']}` | `{row.get('detail', '')}` |")
    (e4_root / "e4_smoke_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_master_table(e4_root: Path, baseline: Dict[str, object], rows: List[Dict[str, object]]) -> None:
    baseline_row = {
        "run_tag": "baseline_lock",
        "flat_theta_reg_lambda": "",
        "safe_eligible": "reference",
        "promotable": "reference",
        "rank_score": 0.0,
    }
    for key in [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_edge_p95_abs_err",
        "flat_peak_theta_error",
    ]:
        baseline_row[key] = baseline.get(key, float("nan"))
    write_csv(e4_root / "mode_theta_master_table.csv", [baseline_row] + sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True))


def write_summary_decision_handoff(e4_root: Path, baseline: Dict[str, object], rows: List[Dict[str, object]]) -> Dict[str, object]:
    ranked = sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True)
    safe = [r for r in ranked if truthy(r.get("safe_eligible"))]
    promotable = [r for r in ranked if truthy(r.get("promotable"))]
    best = promotable[0] if promotable else (safe[0] if safe else ranked[0])
    decision = {
        "phase": "E4_mode_conditioned_theta",
        "e4_status": "PASS",
        "n_formal_runs": len(rows),
        "n_safe_eligible_runs": len(safe),
        "n_promotable_runs": len(promotable),
        "best_run_tag": best["run_tag"],
        "can_expand_seeds_42_101": bool(promotable),
        "can_enter_e5": True,
        "e5_base_strategy": (
            {"source": "E4_best_promotable", "run_tag": best["run_tag"], "model_family": "small_mode_theta"}
            if promotable
            else {"source": "baseline_small", "model_family": "small", "reason": "E4 has no promotable run; E5 sandbox may still proceed"}
        ),
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
        "ranking": [
            {
                "run_tag": r["run_tag"],
                "rank_score": r["rank_score"],
                "safe_eligible": truthy(r.get("safe_eligible")),
                "promotable": truthy(r.get("promotable")),
                "flat_theta_reg_lambda": r["flat_theta_reg_lambda"],
                "theta_mae_deg": r["theta_mae_deg"],
                "flat_peak_theta_error": r["flat_peak_theta_error"],
                "theta_edge_p95_abs_err": r["theta_edge_p95_abs_err"],
                "acc_main": r["acc_main"],
                "acc_turn": r["acc_turn"],
                "acc_turn_transition": r["acc_turn_transition"],
                "expert_not_differentiated": truthy(r.get("expert_not_differentiated")),
                "safe_eligible_reason": r["safe_eligible_reason"],
                "promotable_reason": r["promotable_reason"],
            }
            for r in ranked
        ],
    }
    (e4_root / "mode_theta_decision.json").write_text(json.dumps(decision, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_summary(e4_root, decision, ranked)
    write_handoff(e4_root, decision)
    return decision


def write_summary(e4_root: Path, decision: Dict[str, object], ranked: List[Dict[str, object]]) -> None:
    lines = [
        "# E4 Mode-Conditioned Theta Experts Summary",
        "",
        f"- E4 status: {decision['e4_status']}",
        f"- safe eligible runs: {decision['n_safe_eligible_runs']}",
        f"- promotable runs: {decision['n_promotable_runs']}",
        f"- best run: `{decision['best_run_tag']}`",
        f"- can expand seeds 42/101: {decision['can_expand_seeds_42_101']}",
        f"- can enter E5: {decision['can_enter_e5']}",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "- no baseline overwrite: True",
        "",
        "## Ranking",
        "",
        "| rank | run | safe | promotable | flat_reg | theta | flat_peak | edge | acc_main | expert_diff | reason |",
        "|---:|---|---|---|---:|---:|---:|---:|---:|---|---|",
    ]
    for idx, row in enumerate(ranked, start=1):
        lines.append(
            f"| {idx} | `{row['run_tag']}` | {truthy(row.get('safe_eligible'))} | {truthy(row.get('promotable'))} | "
            f"{float(row['flat_theta_reg_lambda']):.3f} | {float(row['theta_mae_deg']):.6f} | "
            f"{float(row['flat_peak_theta_error']):.6f} | {float(row['theta_edge_p95_abs_err']):.6f} | "
            f"{float(row['acc_main']):.6f} | {not truthy(row.get('expert_not_differentiated'))} | {row['promotable_reason']} |"
        )
    lines.extend(["", "## E5 Strategy", "", "```json", json.dumps(decision["e5_base_strategy"], indent=2, ensure_ascii=False), "```"])
    (e4_root / "mode_theta_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_handoff(e4_root: Path, decision: Dict[str, object]) -> None:
    lines = [
        "# ModernTCN SCI Innovation E4 Handoff",
        "",
        "阶段：`E4 / 04_mode_conditioned_theta`",
        "",
        "## 结论",
        "",
        f"- E4 status: `{decision['e4_status']}`",
        f"- best run: `{decision['best_run_tag']}`",
        f"- safe eligible runs: {decision['n_safe_eligible_runs']}",
        f"- promotable runs: {decision['n_promotable_runs']}",
        f"- can expand seeds 42/101: {decision['can_expand_seeds_42_101']}",
        f"- can enter E5: {decision['can_enter_e5']}",
        "",
        "## 下一阶段策略",
        "",
        "```json",
        json.dumps(decision["e5_base_strategy"], indent=2, ensure_ascii=False),
        "```",
        "",
        "## 必读证据",
        "",
        "- `e4_preflight.md`",
        "- `e4_smoke_report.md`",
        "- `mode_theta_master_table.csv`",
        "- `mode_theta_summary.md`",
        "- `mode_theta_decision.json`",
        "",
        "## Safety",
        "",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "- no baseline overwrite: True",
    ]
    (e4_root / "HANDOFF_NEXT_CHAT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_failure(e4_root: Path, exc: BaseException) -> None:
    e4_root.mkdir(parents=True, exist_ok=True)
    text = [
        "# E4 Failure Report",
        "",
        "- status: FAIL",
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
    (e4_root / "failure_report.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def find_row_value(rows: List[Dict[str, str]], key: str, key_value: str, value_key: str) -> float:
    for row in rows:
        if str(row.get(key)) == key_value:
            return to_float(row.get(value_key))
    return float("nan")


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
