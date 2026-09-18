"""Run SCI E3 physics-group residual gate experiments.

This runner is scoped to:
results/modern_tcn_sci_innovation/03_physics_group_gate/

It does not export ONNX, does not call MATLAB/Simulink, and trains only the
two seed21 alpha-init probes requested for E3.
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

import torch

from modern_tcn_data import find_project_root, load_modern_tcn_dataset
from modern_tcn_model import build_model_from_checkpoint_dict
from train_modern_tcn import _select_device, train_one_seed


DATASET_REL = Path("data") / "tcn" / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
E0_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "e0_decision.json"
E1_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "loss_optimization_decision.json"
E1_BASE_CONFIG_REL = Path("results") / "modern_tcn_sci_innovation" / "01_loss_optimization" / "uncertainty_seed21" / "config.json"
E2_DECISION_REL = Path("results") / "modern_tcn_sci_innovation" / "02_hard_sample_loss" / "hard_sample_loss_decision.json"
BASELINE_LOCK_REL = Path("results") / "modern_tcn_sci_innovation" / "00_baseline_lock" / "baseline_lock.md"
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
E3_REL = Path("results") / "modern_tcn_sci_innovation" / "03_physics_group_gate"

GROUP_SPEC = {
    "yaw_steering": ["gyro_z", "delta_lf", "delta_rr", "kappa_proxy", "yaw_consistency_error"],
    "drive_current_load": [
        "I_lf",
        "I_rr",
        "I_sum",
        "I_diff_signed",
        "I_diff_abs",
        "I_drive_signed",
        "drive_load_proxy",
        "current_per_accel",
        "accel_per_current",
    ],
    "velocity_acceleration": ["v_hat", "dv_hat_dt", "dv_hat_dt_lp", "accel_x_wheel", "a_hp"],
    "wheel_imbalance": ["omega_wheel_lf", "omega_wheel_rr", "ws_imbalance"],
}

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
    "modern_tcn_pg_seed21.pt",
    "modern_tcn_pg_seed21_summary.csv",
    "modern_tcn_pg_seed21_history.csv",
    "config.json",
    "git_hash.txt",
    "dataset_contract_copy.json",
    "feature_names.txt",
    "ModernTCNPhysicsGroupGate_train_report.md",
    "physics_gate_statistics.json",
]


@dataclass(frozen=True)
class RunSpec:
    tag: str
    alpha_init: float


FORMAL_SPECS = [
    RunSpec("pg_alpha0_seed21", 0.0),
    RunSpec("pg_alpha01_seed21", 0.1),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ModernTCN SCI E3 physics-group residual gate workflow.")
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
    e3_root = root / E3_REL
    e3_root.mkdir(parents=True, exist_ok=True)
    try:
        decision = run_workflow(root, e3_root, args)
    except Exception as exc:
        write_failure(e3_root, exc)
        raise
    print(json.dumps(decision, indent=2, ensure_ascii=False))
    return 0


def run_workflow(root: Path, e3_root: Path, args: argparse.Namespace) -> Dict[str, object]:
    stale_failure = e3_root / "failure_report.md"
    if stale_failure.exists():
        stale_failure.unlink()
    e0 = read_json(root / E0_DECISION_REL)
    e1 = read_json(root / E1_DECISION_REL)
    e2 = read_json(root / E2_DECISION_REL)
    base_cli = read_json(root / E1_BASE_CONFIG_REL)["cli_args"]
    data = load_modern_tcn_dataset(dataset_file=root / DATASET_REL, limit_train=0, limit_val=0, limit_test=0)
    contract = data["contract"]
    feature_names = [str(x) for x in data["feat_names"]]
    feature_audit = build_feature_group_audit(feature_names)
    baseline = load_baseline(root)

    checks = preflight_checks(root, e3_root, e0, e1, e2, contract, baseline, feature_audit, FORMAL_SPECS)
    write_feature_group_audit(e3_root, feature_audit)
    write_preflight(e3_root, checks, baseline, contract, feature_audit)
    if checks["failure_reasons"]:
        raise RuntimeError("E3 preflight failed: " + "; ".join(checks["failure_reasons"]))

    smoke_rows = run_smoke(root, e3_root, base_cli, args, feature_audit)
    write_smoke_report(e3_root, smoke_rows)

    formal_rows: List[Dict[str, object]] = []
    if not args.skip_formal:
        for spec in FORMAL_SPECS:
            train_args = make_train_args(
                root=root,
                e3_root=e3_root,
                base_cli=base_cli,
                feature_audit=feature_audit,
                run_tag=spec.tag,
                alpha_init=spec.alpha_init,
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
            formal_rows.append(formal_row(e3_root, spec, result, baseline))

    if formal_rows:
        write_master_table(e3_root, baseline, formal_rows)
        decision = write_summary_decision_handoff(e3_root, baseline, formal_rows)
    else:
        decision = {
            "phase": "E3_physics_group_gate",
            "e3_status": "PASS_SMOKE_ONLY",
            "formal_runs_executed": False,
            "can_enter_e4": False,
            "reason": "skip_formal was used",
        }
        (e3_root / "physics_group_gate_decision.json").write_text(
            json.dumps(decision, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return decision


def preflight_checks(
    root: Path,
    e3_root: Path,
    e0: Dict[str, object],
    e1: Dict[str, object],
    e2: Dict[str, object],
    contract,
    baseline: Dict[str, object],
    feature_audit: Dict[str, object],
    specs: Sequence[RunSpec],
) -> Dict[str, object]:
    failures: List[str] = []
    if e0.get("decision") != "PASS":
        failures.append("E0 decision is not PASS")
    if e1.get("e1_status") != "PASS":
        failures.append("E1 status is not PASS")
    if e1.get("best_loss_mode") != "fixed":
        failures.append("E1 best_loss_mode is not fixed")
    if e2.get("e2_status") != "PASS" or not bool(e2.get("can_enter_e3", False)):
        failures.append("E2 decision does not allow E3")
    if str(e2.get("e3_loss_strategy", {}).get("loss_mode", "")) != "fixed":
        failures.append("E2 e3_loss_strategy is not fixed")
    if int(contract.input_dim) != 22:
        failures.append(f"dataset input_dim is {contract.input_dim}, expected 22")
    if int(contract.seq_len) != 128:
        failures.append(f"dataset seq_len is {contract.seq_len}, expected 128")
    if str(contract.feature_contract) != "passive17_plus_all5":
        failures.append(f"feature_contract is {contract.feature_contract}, expected passive17_plus_all5")
    if not bool(feature_audit.get("pass", False)):
        failures.append("feature group index audit failed")
    for key in ["theta_edge_p95_abs_err", "flat_peak_theta_error"]:
        if not is_finite_number(baseline.get(key)):
            failures.append(f"baseline {key} is missing or nan")
    for spec in specs:
        run_dir = e3_root / spec.tag
        if run_dir.exists() and any(run_dir.iterdir()):
            failures.append(f"output run directory would be overwritten: {run_dir}")
    return {
        "failure_reasons": failures,
        "baseline_checkpoint": str(root / BASELINE_CKPT_REL),
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
        "loss_mode": "fixed",
        "explicit_e1_e2_loss_disabled": True,
    }


def run_smoke(
    root: Path,
    e3_root: Path,
    base_cli: Dict[str, object],
    args: argparse.Namespace,
    feature_audit: Dict[str, object],
) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    rows.append(run_dry_run(root, e3_root, base_cli, args, feature_audit, "small_dry_run", "small", 0.0))
    rows.append(
        run_dry_run(
            root,
            e3_root,
            base_cli,
            args,
            feature_audit,
            "small_physics_group_gate_dry_run",
            "small_physics_group_gate",
            0.0,
        )
    )
    rows.append(baseline_checkpoint_regression(root, args.device))
    rows.append(no_overwrite_probe(root, e3_root, base_cli, args, feature_audit))
    rows.append(gate_stats_probe(root, e3_root, base_cli, args, feature_audit))
    return rows


def run_dry_run(
    root: Path,
    e3_root: Path,
    base_cli: Dict[str, object],
    args: argparse.Namespace,
    feature_audit: Dict[str, object],
    tag: str,
    family: str,
    alpha_init: float,
) -> Dict[str, object]:
    train_args = make_train_args(
        root=root,
        e3_root=e3_root / "_smoke",
        base_cli=base_cli,
        feature_audit=feature_audit,
        run_tag=tag,
        alpha_init=alpha_init,
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
    if family == "small":
        train_args.physics_group_names = None
        train_args.physics_group_indices = None
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
    return {
        "check": "baseline_checkpoint_regression",
        "status": "PASS",
        "checkpoint": str(ckpt_path),
        "output_shapes": str(shapes),
    }


def no_overwrite_probe(
    root: Path,
    e3_root: Path,
    base_cli: Dict[str, object],
    args: argparse.Namespace,
    feature_audit: Dict[str, object],
) -> Dict[str, object]:
    probe = e3_root / "__no_overwrite_probe__"
    probe.mkdir(parents=True, exist_ok=True)
    (probe / "marker.txt").write_text("probe\n", encoding="utf-8")
    try:
        train_args = make_train_args(
            root=root,
            e3_root=e3_root,
            base_cli=base_cli,
            feature_audit=feature_audit,
            run_tag=probe.name,
            alpha_init=0.0,
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
        raise RuntimeError("--no-overwrite did not reject an existing non-empty E3 run directory")
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def gate_stats_probe(
    root: Path,
    e3_root: Path,
    base_cli: Dict[str, object],
    args: argparse.Namespace,
    feature_audit: Dict[str, object],
) -> Dict[str, object]:
    tag = "gate_stats_probe"
    probe_dir = e3_root / "_smoke" / tag
    if probe_dir.exists():
        shutil.rmtree(probe_dir)
    train_args = make_train_args(
        root=root,
        e3_root=e3_root / "_smoke",
        base_cli=base_cli,
        feature_audit=feature_audit,
        run_tag=tag,
        alpha_init=0.0,
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
    train_one_seed(train_args)
    stats_file = probe_dir / "physics_gate_statistics.json"
    history_file = probe_dir / "modern_tcn_pg_seed21_history.csv"
    summary_file = probe_dir / "modern_tcn_pg_seed21_summary.csv"
    if not stats_file.exists() or not history_file.exists() or not summary_file.exists():
        raise RuntimeError("gate stats probe did not produce required E3 alpha/gate artifacts")
    rows = read_csv_rows(history_file)
    if not rows or "alpha" not in rows[0]:
        raise RuntimeError("gate stats probe history does not contain alpha")
    summary = read_csv_rows(summary_file)[0]
    for key in ["alpha_final", "test_gate_all_finite", "test_gate_interpretability_score"]:
        if key not in summary:
            raise RuntimeError(f"gate stats probe summary missing {key}")
    return {"check": "gate_stats_probe", "status": "PASS", "detail": str(stats_file)}


def make_train_args(
    root: Path,
    e3_root: Path,
    base_cli: Dict[str, object],
    feature_audit: Dict[str, object],
    run_tag: str,
    alpha_init: float,
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
            "model_family": "small_physics_group_gate",
            "dataset_file": str(root / DATASET_REL),
            "output_root": str(e3_root),
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
            "branch_channels": 16,
            "branch_kernel": 31,
            "alpha_init": float(alpha_init),
            "gate_hidden": 32,
            "physics_group_spec": "default_22d_agv",
            "physics_group_names": ",".join(feature_audit["group_names"]),
            "physics_group_indices": ";".join(
                ",".join(str(idx) for idx in group) for group in feature_audit["group_indices"]
            ),
        }
    )
    return argparse.Namespace(**values)


def build_feature_group_audit(feature_names: Sequence[str]) -> Dict[str, object]:
    index_by_name = {name: idx for idx, name in enumerate(feature_names)}
    rows = []
    group_indices: List[List[int]] = []
    group_names: List[str] = []
    failures: List[str] = []
    assigned: List[str] = []
    for group_name, names in GROUP_SPEC.items():
        indices = []
        for name in names:
            if name not in index_by_name:
                failures.append(f"missing feature {name} for group {group_name}")
                continue
            idx = index_by_name[name]
            indices.append(idx)
            assigned.append(name)
            rows.append(
                {
                    "index_1based": idx + 1,
                    "index_0based": idx,
                    "feature": name,
                    "group": group_name,
                }
            )
        if indices:
            group_names.append(group_name)
            group_indices.append(indices)
    duplicate_features = sorted({name for name in assigned if assigned.count(name) > 1})
    missing_features = [name for name in feature_names if name not in assigned]
    if duplicate_features:
        failures.append("duplicate assigned features: " + ", ".join(duplicate_features))
    residual_group = "empty"
    if missing_features:
        residual_group = "non_empty"
        group_names.append("residual")
        group_indices.append([index_by_name[name] for name in missing_features])
        for name in missing_features:
            rows.append(
                {
                    "index_1based": index_by_name[name] + 1,
                    "index_0based": index_by_name[name],
                    "feature": name,
                    "group": "residual",
                }
            )
    rows = sorted(rows, key=lambda r: int(r["index_1based"]))
    return {
        "pass": not failures,
        "failure_reasons": failures,
        "feature_names": list(feature_names),
        "rows": rows,
        "group_names": group_names,
        "group_indices": group_indices,
        "duplicate_features": duplicate_features,
        "missing_features": missing_features,
        "residual_group": residual_group,
    }


def formal_row(e3_root: Path, spec: RunSpec, result: Dict[str, object], baseline: Dict[str, object]) -> Dict[str, object]:
    run_dir = e3_root / spec.tag
    missing = [name for name in REQUIRED_RUN_FILES if not (run_dir / name).exists()]
    row = dict(read_csv_rows(run_dir / "modern_tcn_pg_seed21_summary.csv")[0])
    row["run_tag"] = spec.tag
    row["alpha_init"] = spec.alpha_init
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
        "alpha_final",
        "test_gate_mean_entropy",
        "test_gate_yaw_transition_minus_overall",
        "test_gate_drive_stall_minus_overall",
        "test_gate_velocity_slope_flat_abs_delta",
    ]:
        row[key] = to_float(row.get(key))
    row["test_gate_interpretability_score"] = int(float(row.get("test_gate_interpretability_score", 0) or 0))
    row["test_gate_all_finite"] = truthy(row.get("test_gate_all_finite"))
    row["test_gate_single_collapse"] = truthy(row.get("test_gate_single_collapse"))
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
    if not math.isfinite(float(row.get("alpha_final", float("nan")))):
        failures.append("alpha_final is not finite")
    if abs(float(row.get("alpha_final", 0.0))) > 10.0:
        failures.append("alpha_final exploded beyond abs 10")
    if not bool(row.get("test_gate_all_finite", False)):
        failures.append("gate contains non-finite values")
    if bool(row.get("test_gate_single_collapse", False)):
        failures.append("gate collapsed to a single group")
    for key, actual, op, threshold in checks:
        passed = actual >= threshold if op == ">=" else actual <= threshold
        if not passed:
            failures.append(f"{key} {op} {threshold:.6f}, actual {actual:.6f}")
    return not failures, "; ".join(failures) if failures else "protection metrics pass"


def promotable_status(row: Dict[str, object], baseline: Dict[str, object], eligible: bool) -> Tuple[bool, str]:
    if not eligible:
        return False, "not eligible"
    target_improved = (
        row["acc_turn_transition"] > baseline["acc_turn_transition"]
        or row["stall_recall"] > baseline["stall_recall"]
        or row["theta_mae_deg"] < baseline["theta_mae_deg"]
        or row["theta_edge_p95_abs_err"] < baseline["theta_edge_p95_abs_err"]
        or row["flat_peak_theta_error"] < baseline["flat_peak_theta_error"]
    )
    interpretable = int(row.get("test_gate_interpretability_score", 0)) >= 2
    main_not_down = row["acc_main"] >= baseline["acc_main"] - 0.001
    if target_improved:
        return True, "eligible and at least one target metric improved"
    if interpretable and main_not_down:
        return True, "eligible with interpretable gate and protected main metric"
    return False, "eligible but no target improvement and insufficient gate interpretability"


def rank_score(row: Dict[str, object]) -> float:
    return (
        2.0 * float(row.get("delta_acc_turn_transition", 0.0))
        + 1.5 * float(row.get("delta_stall_recall", 0.0))
        + 0.5 * float(row.get("delta_theta_mae_deg", 0.0))
        + 0.5 * float(row.get("delta_theta_edge_p95_abs_err", 0.0))
        + 0.25 * float(row.get("delta_flat_peak_theta_error", 0.0))
        + 0.25 * float(row.get("test_gate_interpretability_score", 0.0))
        + 0.5 * float(row.get("delta_acc_main", 0.0))
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
        out["acc_turn_pure"] = to_float(champ.get("acc_turn_pure"))
    else:
        out["baseline_summary_source"] = str(source)
        out["acc_turn_pure"] = float("nan")
    return out


def write_feature_group_audit(e3_root: Path, audit: Dict[str, object]) -> None:
    lines = [
        "# E3 Feature Group Index Audit",
        "",
        f"- status: {'PASS' if audit['pass'] else 'FAIL'}",
        "- index policy: 0-based indices are passed to PyTorch config; 1-based indices are reported for human audit.",
        f"- residual_group: `{audit['residual_group']}`",
        f"- group_names: `{audit['group_names']}`",
        "",
        "| index_1based | index_0based | feature | group |",
        "|---:|---:|---|---|",
    ]
    for row in audit["rows"]:
        lines.append(f"| {row['index_1based']} | {row['index_0based']} | `{row['feature']}` | `{row['group']}` |")
    if audit["failure_reasons"]:
        lines.extend(["", "## Failure Reasons", ""])
        lines.extend(f"- {x}" for x in audit["failure_reasons"])
    (e3_root / "feature_group_index_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_preflight(e3_root: Path, checks: Dict[str, object], baseline: Dict[str, object], contract, audit: Dict[str, object]) -> None:
    lines = [
        "# E3 Engineering Preflight",
        "",
        f"- status: {'FAIL' if checks['failure_reasons'] else 'PASS'}",
        "- scope: E3 / 03_physics_group_gate only; no ONNX; no MATLAB/Simulink.",
        "- model_family: `small_physics_group_gate`",
        "- loss_mode: `fixed`",
        "- E1/E2 loss explicitly disabled: transition_focal=0, stall_focal=0, theta_smooth=0, theta_smooth_mode=off",
        f"- dataset input: `[batch,{contract.seq_len},{contract.input_dim}]`",
        f"- feature_contract: `{contract.feature_contract}`",
        f"- residual_group: `{audit['residual_group']}`",
        f"- baseline checkpoint regression target: `{checks['baseline_checkpoint']}`",
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
    if checks["failure_reasons"]:
        lines.extend(["", "## Failure Reasons", ""])
        lines.extend(f"- {x}" for x in checks["failure_reasons"])
    (e3_root / "e3_preflight.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_smoke_report(e3_root: Path, rows: List[Dict[str, object]]) -> None:
    lines = [
        "# E3 Smoke Report",
        "",
        "- status: PASS",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "",
        "| check | status | detail |",
        "|---|---|---|",
    ]
    for row in rows:
        detail = row.get("detail", row.get("checkpoint", ""))
        lines.append(f"| `{row['check']}` | `{row['status']}` | `{detail}` |")
    (e3_root / "e3_smoke_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_master_table(e3_root: Path, baseline: Dict[str, object], rows: List[Dict[str, object]]) -> None:
    baseline_row: Dict[str, object] = {
        "run_tag": "baseline_lock",
        "alpha_init": "",
        "alpha_final": "",
        "eligible": "reference",
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
    write_csv(e3_root / "physics_group_gate_master_table.csv", [baseline_row] + sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True))


def write_summary_decision_handoff(e3_root: Path, baseline: Dict[str, object], rows: List[Dict[str, object]]) -> Dict[str, object]:
    ranked = sorted(rows, key=lambda r: float(r["rank_score"]), reverse=True)
    eligible = [r for r in ranked if truthy(r.get("eligible"))]
    promotable = [r for r in ranked if truthy(r.get("promotable"))]
    best = promotable[0] if promotable else (eligible[0] if eligible else ranked[0])
    e3_status = "PASS" if not any(engineering_failed(r) for r in ranked) else "FAIL_ENGINEERING"
    can_enter_e4 = e3_status == "PASS"
    e4_base = (
        {"source": "E3_best_promotable", "run_tag": best["run_tag"], "model_family": "small_physics_group_gate"}
        if promotable
        else {"source": "baseline_fixed_loss", "model_family": "small", "reason": "E3 has no promotable run"}
    )
    decision = {
        "phase": "E3_physics_group_gate",
        "e3_status": e3_status,
        "n_formal_runs": len(rows),
        "n_eligible_runs": len(eligible),
        "n_promotable_runs": len(promotable),
        "best_run_tag": best["run_tag"],
        "can_expand_seeds_42_101": bool(promotable),
        "can_enter_e4": bool(can_enter_e4),
        "e4_base_strategy": e4_base,
        "no_onnx_export": True,
        "no_matlab_simulink_closed_loop": True,
        "no_baseline_overwrite": True,
        "ranking": [
            {
                "run_tag": r["run_tag"],
                "rank_score": r["rank_score"],
                "eligible": truthy(r.get("eligible")),
                "promotable": truthy(r.get("promotable")),
                "alpha_final": r["alpha_final"],
                "gate_interpretability_score": r.get("test_gate_interpretability_score"),
                "delta_acc_turn_transition": r["delta_acc_turn_transition"],
                "delta_stall_recall": r["delta_stall_recall"],
                "delta_theta_mae_deg": r["delta_theta_mae_deg"],
                "eligible_reason": r["eligible_reason"],
                "promotable_reason": r["promotable_reason"],
            }
            for r in ranked
        ],
    }
    (e3_root / "physics_group_gate_decision.json").write_text(json.dumps(decision, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_summary(e3_root, baseline, decision, ranked)
    write_handoff(e3_root, decision, ranked)
    return decision


def engineering_failed(row: Dict[str, object]) -> bool:
    reason = str(row.get("eligible_reason", ""))
    return any(
        marker in reason
        for marker in [
            "missing required artifacts",
            "alpha_final is not finite",
            "alpha_final exploded",
            "gate contains non-finite",
        ]
    )


def write_summary(e3_root: Path, baseline: Dict[str, object], decision: Dict[str, object], ranked: List[Dict[str, object]]) -> None:
    lines = [
        "# E3 Physics-Group Residual Gate Summary",
        "",
        f"- E3 status: {decision['e3_status']}",
        f"- eligible runs: {decision['n_eligible_runs']}",
        f"- promotable runs: {decision['n_promotable_runs']}",
        f"- can expand seeds 42/101: {decision['can_expand_seeds_42_101']}",
        f"- can enter E4: {decision['can_enter_e4']}",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "- no baseline overwrite: True",
        "",
        "## Ranking",
        "",
        "| rank | run | eligible | promotable | alpha_final | gate_score | d_turn_transition | d_stall | d_theta_mae | reason |",
        "|---:|---|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for idx, row in enumerate(ranked, start=1):
        lines.append(
            f"| {idx} | `{row['run_tag']}` | {truthy(row.get('eligible'))} | {truthy(row.get('promotable'))} | "
            f"{row['alpha_final']:.6f} | {row.get('test_gate_interpretability_score')} | "
            f"{row['delta_acc_turn_transition']:.6f} | {row['delta_stall_recall']:.6f} | "
            f"{row['delta_theta_mae_deg']:.6f} | {row['promotable_reason']} |"
        )
    lines.extend(["", "## E4 Strategy", "", "```json", json.dumps(decision["e4_base_strategy"], indent=2, ensure_ascii=False), "```"])
    (e3_root / "physics_group_gate_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_handoff(e3_root: Path, decision: Dict[str, object], ranked: List[Dict[str, object]]) -> None:
    lines = [
        "# ModernTCN SCI Innovation E3 Handoff",
        "",
        "阶段：`E3 / 03_physics_group_gate`",
        "",
        "## 结论",
        "",
        f"- E3 status: `{decision['e3_status']}`",
        f"- best run: `{decision['best_run_tag']}`",
        f"- eligible runs: {decision['n_eligible_runs']}",
        f"- promotable runs: {decision['n_promotable_runs']}",
        f"- can expand seeds 42/101: {decision['can_expand_seeds_42_101']}",
        f"- can enter E4: {decision['can_enter_e4']}",
        "",
        "## 下一阶段策略",
        "",
        "```json",
        json.dumps(decision["e4_base_strategy"], indent=2, ensure_ascii=False),
        "```",
        "",
        "## 必读证据",
        "",
        "- `e3_preflight.md`",
        "- `feature_group_index_audit.md`",
        "- `e3_smoke_report.md`",
        "- `physics_group_gate_master_table.csv`",
        "- `physics_group_gate_summary.md`",
        "- `physics_group_gate_decision.json`",
        "",
        "## Safety",
        "",
        "- no ONNX export: True",
        "- no MATLAB/Simulink closed-loop: True",
        "- no baseline overwrite: True",
    ]
    (e3_root / "HANDOFF_NEXT_CHAT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_failure(e3_root: Path, exc: BaseException) -> None:
    e3_root.mkdir(parents=True, exist_ok=True)
    text = [
        "# E3 Failure Report",
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
    (e3_root / "failure_report.md").write_text("\n".join(text) + "\n", encoding="utf-8")


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
