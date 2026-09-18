"""Run ModernTCN multi-seed training on the theta10 uniform V2 dataset.

This entry point is intentionally separate from the older phase1 runner:
it always trains every requested seed, uses the horizon=0 V2 dataset by
default, and writes one aggregate CSV/report after all seeds finish.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from statistics import mean, pstdev
from typing import Dict, Iterable, List

from modern_tcn_data import find_project_root
from train_modern_tcn import train_one_seed


DEFAULT_DATASET = "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat"
DEFAULT_SEEDS = [11, 21, 42, 73, 101]
KEY_METRICS = [
    "acc_main",
    "flat_recall",
    "slope_recall",
    "acc_turn",
    "acc_turn_transition",
    "turn_right_recall",
    "turn_left_recall",
    "theta_mae_deg",
    "theta_abs_le_10_p95_abs_err_deg",
    "theta_neg_10_8_p95_abs_err_deg",
    "theta_pos_8_10_p95_abs_err_deg",
    "theta_neg_8_6_p95_abs_err_deg",
    "theta_pos_6_8_p95_abs_err_deg",
    "theta_neg_2_0p5_p95_abs_err_deg",
    "theta_pos_0p5_2_p95_abs_err_deg",
    "theta_true_zero_abs_p95_deg",
    "theta_flat_abs_p95_deg",
    "theta_flat_bias_deg",
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN theta10 V2 multi-seed training")
    p.add_argument("--dataset-file", type=str, default=DEFAULT_DATASET)
    p.add_argument("--seeds", type=int, nargs="+", default=DEFAULT_SEEDS)
    p.add_argument("--run-tag-prefix", type=str, default="modern_tcn_theta10_uniform_h0_v2")
    p.add_argument("--epochs", type=int, default=180)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--patience", type=int, default=35)
    p.add_argument("--min-epochs", type=int, default=50)
    p.add_argument("--channels", type=int, default=64)
    p.add_argument("--blocks", type=int, default=5)
    p.add_argument("--kernel-size", type=int, default=31)
    p.add_argument(
        "--temporal-padding",
        type=str,
        default="same",
        choices=["same", "causal"],
        help="Temporal convolution padding mode. 默认 same，causal 仅用于因果消融实验。",
    )
    p.add_argument("--dropout", type=float, default=0.15)
    p.add_argument("--turn-head-source", type=str, default="full", choices=["full", "inputstats", "kinematic_stats"])
    p.add_argument("--lambda-turn", type=float, default=0.08)
    p.add_argument("--lambda-theta", type=float, default=0.55)
    p.add_argument("--lambda-theta-flat", type=float, default=0.12)
    p.add_argument("--theta-flat-loss-mode", type=str, default="near_zero", choices=["near_zero", "true_zero", "near_flat", "main_flat", "none"])
    p.add_argument("--theta-flat-zero-tol-deg", type=float, default=0.3)
    p.add_argument("--lambda-theta-near-flat", type=float, default=0.0)
    p.add_argument("--theta-near-flat-deg", type=float, default=0.5)
    p.add_argument("--lambda-theta-error-excess", type=float, default=0.05)
    p.add_argument("--lambda-theta-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-near-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-true-zero-excess", type=float, default=0.10)
    p.add_argument("--lambda-theta-active-excess", type=float, default=0.10)
    p.add_argument("--lambda-theta-small-neg", type=float, default=0.0)
    p.add_argument("--lambda-theta-small-neg-excess", type=float, default=0.0)
    p.add_argument("--theta-excess-target-deg", type=float, default=1.0)
    p.add_argument("--theta-flat-excess-target-deg", type=float, default=0.5)
    p.add_argument("--theta-small-neg-min-deg", type=float, default=-4.0)
    p.add_argument("--theta-small-neg-max-deg", type=float, default=-2.0)
    p.add_argument("--theta-gate-mode", type=str, default="none", choices=["none", "main_slope_prob"])
    p.add_argument("--theta-gate-power", type=float, default=1.0)
    p.add_argument("--theta-gate-floor", type=float, default=0.0)
    p.add_argument("--theta-neg-weight", type=float, default=1.0)
    p.add_argument("--theta-pos-weight", type=float, default=1.0)
    p.add_argument("--turn-transition-weight", type=float, default=1.4)
    p.add_argument("--turn-class-multipliers", type=float, nargs=3, default=[1.08, 1.00, 1.08])
    p.add_argument("--select-turn-weight", type=float, default=0.30)
    p.add_argument("--select-turn-transition-weight", type=float, default=1.20)
    p.add_argument("--select-turn-transition-target", type=float, default=0.82)
    p.add_argument("--select-turn-left-weight", type=float, default=0.0)
    p.add_argument("--select-turn-left-target", type=float, default=0.88)
    p.add_argument("--select-turn-lr-weight", type=float, default=0.20)
    p.add_argument("--select-turn-lr-target", type=float, default=0.88)
    p.add_argument("--select-theta-weight", type=float, default=0.30)
    p.add_argument("--select-theta-ref-deg", type=float, default=2.0)
    p.add_argument("--select-theta-p95-weight", type=float, default=0.80)
    p.add_argument("--select-theta-p95-target-deg", type=float, default=1.20)
    p.add_argument("--select-theta-flat-p95-weight", type=float, default=0.35)
    p.add_argument("--select-theta-flat-p95-target-deg", type=float, default=0.70)
    p.add_argument("--select-theta-near-flat-p95-weight", type=float, default=0.20)
    p.add_argument("--select-theta-near-flat-p95-target-deg", type=float, default=0.70)
    p.add_argument("--select-theta-true-zero-p95-weight", type=float, default=0.45)
    p.add_argument("--select-theta-true-zero-p95-target-deg", type=float, default=0.50)
    p.add_argument("--select-theta-extreme-p95-weight", type=float, default=0.60)
    p.add_argument("--select-theta-extreme-p95-target-deg", type=float, default=1.20)
    p.add_argument("--select-theta-edge-p95-weight", type=float, default=0.70)
    p.add_argument("--select-theta-edge-p95-target-deg", type=float, default=1.50)
    p.add_argument("--select-theta-small-nonzero-p95-weight", type=float, default=0.80)
    p.add_argument("--select-theta-small-nonzero-p95-target-deg", type=float, default=1.00)
    p.add_argument("--select-theta-flat-bias-weight", type=float, default=0.30)
    p.add_argument("--select-theta-flat-bias-target-deg", type=float, default=0.15)
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    p.add_argument("--num-workers", type=int, default=0)
    p.add_argument("--limit-train", type=int, default=0, help="Smoke-test only. Keep 0 for formal training.")
    p.add_argument("--limit-val", type=int, default=0, help="Smoke-test only. Keep 0 for formal training.")
    p.add_argument("--limit-test", type=int, default=0, help="Smoke-test only. Keep 0 for formal training.")
    p.add_argument("--dry-run", action="store_true", help="Check data/model wiring without training.")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    root = find_project_root()
    dataset_file = _resolve_dataset(root, args.dataset_file)

    print("[ModernTCN V2 multi-seed]")
    print(f"  dataset: {dataset_file}")
    print(f"  seeds: {args.seeds}")
    print(f"  temporal_padding: {args.temporal_padding}")
    print(f"  theta_gate_mode: {args.theta_gate_mode}")
    print(f"  theta_flat_loss_mode: {args.theta_flat_loss_mode}, tol={args.theta_flat_zero_tol_deg:g} deg")

    rows: List[Dict[str, str]] = []
    for index, seed in enumerate(args.seeds, start=1):
        print(f"\n[ModernTCN V2 multi-seed] seed {seed} ({index}/{len(args.seeds)})")
        train_args = _build_train_args(args, seed, dataset_file)
        result = train_one_seed(train_args)
        if args.dry_run:
            break
        row = _read_single_row(Path(result["summary_csv"]))
        row["run_tag"] = train_args.run_tag
        row["checkpoint_file"] = result["checkpoint_file"]
        rows.append(row)

    if args.dry_run:
        print("[ModernTCN V2 multi-seed] dry-run finished.")
        return

    out_dir = root / "results" / "modern_tcn"
    summary_csv = out_dir / f"{args.run_tag_prefix}_multiseed_summary.csv"
    report_file = out_dir / f"{args.run_tag_prefix}_multiseed_report.md"
    _write_csv(summary_csv, rows)
    _write_report(report_file, args, dataset_file, rows)
    print("\n[ModernTCN V2 multi-seed] all seeds finished")
    print(f"  summary: {summary_csv}")
    print(f"  report: {report_file}")


def _resolve_dataset(root: Path, dataset_file: str) -> Path:
    path = Path(dataset_file)
    if not path.is_absolute():
        path = root / path
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")
    return path


def _build_train_args(args: argparse.Namespace, seed: int, dataset_file: Path) -> argparse.Namespace:
    return argparse.Namespace(
        seed=seed,
        dataset_file=str(dataset_file),
        run_tag=f"{args.run_tag_prefix}_seed{seed}",
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        weight_decay=args.weight_decay,
        patience=args.patience,
        min_epochs=args.min_epochs,
        channels=args.channels,
        blocks=args.blocks,
        kernel_size=args.kernel_size,
        temporal_padding=args.temporal_padding,
        dropout=args.dropout,
        turn_head_source=args.turn_head_source,
        lambda_turn=args.lambda_turn,
        lambda_theta=args.lambda_theta,
        lambda_theta_flat=args.lambda_theta_flat,
        theta_flat_loss_mode=args.theta_flat_loss_mode,
        theta_flat_zero_tol_deg=args.theta_flat_zero_tol_deg,
        lambda_theta_near_flat=args.lambda_theta_near_flat,
        theta_near_flat_deg=args.theta_near_flat_deg,
        lambda_theta_error_excess=args.lambda_theta_error_excess,
        lambda_theta_flat_excess=args.lambda_theta_flat_excess,
        lambda_theta_near_flat_excess=args.lambda_theta_near_flat_excess,
        lambda_theta_true_zero_excess=args.lambda_theta_true_zero_excess,
        lambda_theta_active_excess=args.lambda_theta_active_excess,
        lambda_theta_small_neg=args.lambda_theta_small_neg,
        lambda_theta_small_neg_excess=args.lambda_theta_small_neg_excess,
        theta_excess_target_deg=args.theta_excess_target_deg,
        theta_flat_excess_target_deg=args.theta_flat_excess_target_deg,
        theta_small_neg_min_deg=args.theta_small_neg_min_deg,
        theta_small_neg_max_deg=args.theta_small_neg_max_deg,
        theta_gate_mode=args.theta_gate_mode,
        theta_gate_power=args.theta_gate_power,
        theta_gate_floor=args.theta_gate_floor,
        theta_neg_weight=args.theta_neg_weight,
        theta_pos_weight=args.theta_pos_weight,
        turn_transition_weight=args.turn_transition_weight,
        turn_class_multipliers=args.turn_class_multipliers,
        select_turn_weight=args.select_turn_weight,
        select_turn_transition_weight=args.select_turn_transition_weight,
        select_turn_transition_target=args.select_turn_transition_target,
        select_turn_left_weight=args.select_turn_left_weight,
        select_turn_left_target=args.select_turn_left_target,
        select_turn_lr_weight=args.select_turn_lr_weight,
        select_turn_lr_target=args.select_turn_lr_target,
        select_theta_weight=args.select_theta_weight,
        select_theta_ref_deg=args.select_theta_ref_deg,
        select_theta_p95_weight=args.select_theta_p95_weight,
        select_theta_p95_target_deg=args.select_theta_p95_target_deg,
        select_theta_flat_p95_weight=args.select_theta_flat_p95_weight,
        select_theta_flat_p95_target_deg=args.select_theta_flat_p95_target_deg,
        select_theta_near_flat_p95_weight=args.select_theta_near_flat_p95_weight,
        select_theta_near_flat_p95_target_deg=args.select_theta_near_flat_p95_target_deg,
        select_theta_true_zero_p95_weight=args.select_theta_true_zero_p95_weight,
        select_theta_true_zero_p95_target_deg=args.select_theta_true_zero_p95_target_deg,
        select_theta_extreme_p95_weight=args.select_theta_extreme_p95_weight,
        select_theta_extreme_p95_target_deg=args.select_theta_extreme_p95_target_deg,
        select_theta_edge_p95_weight=args.select_theta_edge_p95_weight,
        select_theta_edge_p95_target_deg=args.select_theta_edge_p95_target_deg,
        select_theta_small_nonzero_p95_weight=args.select_theta_small_nonzero_p95_weight,
        select_theta_small_nonzero_p95_target_deg=args.select_theta_small_nonzero_p95_target_deg,
        select_theta_flat_bias_weight=args.select_theta_flat_bias_weight,
        select_theta_flat_bias_target_deg=args.select_theta_flat_bias_target_deg,
        device=args.device,
        num_workers=args.num_workers,
        limit_train=args.limit_train,
        limit_val=args.limit_val,
        limit_test=args.limit_test,
        dry_run=args.dry_run,
    )


def _read_single_row(path: Path) -> Dict[str, str]:
    with path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one summary row in {path}, got {len(rows)}")
    return rows[0]


def _write_csv(path: Path, rows: Iterable[Dict[str, str]]) -> None:
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


def _write_report(path: Path, args: argparse.Namespace, dataset_file: Path, rows: List[Dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN theta10 V2 multi-seed report\n\n")
        f.write(f"- dataset: `{dataset_file}`\n")
        f.write(f"- seeds: `{args.seeds}`\n")
        f.write(f"- epochs: `{args.epochs}`, batch_size: `{args.batch_size}`\n")
        f.write(f"- temporal_padding: `{args.temporal_padding}`\n")
        f.write(f"- theta_gate_mode: `{args.theta_gate_mode}`\n")
        f.write(f"- theta_flat_loss_mode: `{args.theta_flat_loss_mode}`, zero_tol_deg: `{args.theta_flat_zero_tol_deg}`\n")
        f.write(f"- lambda_theta: `{args.lambda_theta}`, lambda_turn: `{args.lambda_turn}`\n\n")
        f.write(f"- turn_lr_target: `{args.select_turn_lr_target}`, turn_lr_weight: `{args.select_turn_lr_weight}`\n\n")
        f.write("## Aggregate\n\n")
        f.write("| metric | mean | std |\n|---|---:|---:|\n")
        for metric in KEY_METRICS:
            values = [_to_float(row.get(metric, "")) for row in rows]
            values = [x for x in values if math.isfinite(x)]
            if not values:
                continue
            std_value = pstdev(values) if len(values) > 1 else 0.0
            f.write(f"| {metric} | {mean(values):.4f} | {std_value:.4f} |\n")
        f.write("\n## Per seed\n\n")
        f.write("| seed | acc_main | acc_turn_transition | turn_L/R | theta_mae | theta_10_p95 | edge_neg_p95 | edge_pos_p95 | checkpoint |\n")
        f.write("|---:|---:|---:|---:|---:|---:|---:|---:|---|\n")
        for row in rows:
            turn_lr = _turn_lr_ratio(row)
            f.write(
                f"| {int(float(row['seed']))} | {_fmt(row, 'acc_main')} | {_fmt(row, 'acc_turn_transition')} | "
                f"{turn_lr:.4f} | {_fmt(row, 'theta_mae_deg')} | {_fmt(row, 'theta_abs_le_10_p95_abs_err_deg')} | "
                f"{_fmt(row, 'theta_neg_10_8_p95_abs_err_deg')} | {_fmt(row, 'theta_pos_8_10_p95_abs_err_deg')} | "
                f"`{row.get('checkpoint_file', '')}` |\n"
            )


def _to_float(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def _fmt(row: Dict[str, str], key: str) -> str:
    value = _to_float(row.get(key, ""))
    return "nan" if not math.isfinite(value) else f"{value:.4f}"


def _turn_lr_ratio(row: Dict[str, str]) -> float:
    right = _to_float(row.get("turn_right_recall", ""))
    left = _to_float(row.get("turn_left_recall", ""))
    if not math.isfinite(right) or not math.isfinite(left) or max(right, left) <= 0:
        return float("nan")
    return min(right, left) / max(right, left)


if __name__ == "__main__":
    main()
