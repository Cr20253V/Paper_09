"""Fine-tune only the ModernTCN theta head.

This is intended for controller-integration work: preserve main/turn
classification while improving whether theta_hat is safe for MPC scheduling.
By default all layers except ``theta_head`` are frozen.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import time
from pathlib import Path
from typing import Dict, Iterable, Tuple

import numpy as np
import torch
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, SplitArrays, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics, metric_row, multitask_loss, selection_score
from modern_tcn_model import build_model_from_checkpoint_dict


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Fine-tune ModernTCN theta head only")
    p.add_argument("--checkpoint", type=str, required=True)
    p.add_argument("--dataset-file", type=str, default="")
    p.add_argument("--run-tag", type=str, required=True)
    p.add_argument("--seed", type=int, default=73)
    p.add_argument("--epochs", type=int, default=80)
    p.add_argument("--batch-size", type=int, default=512)
    p.add_argument("--lr", type=float, default=2e-3)
    p.add_argument("--weight-decay", type=float, default=1e-5)
    p.add_argument("--patience", type=int, default=18)
    p.add_argument("--min-epochs", type=int, default=15)
    p.add_argument("--lambda-theta", type=float, default=0.55)
    p.add_argument("--lambda-theta-flat", type=float, default=1.50)
    p.add_argument(
        "--theta-flat-loss-mode",
        type=str,
        default="near_zero",
        choices=["near_zero", "true_zero", "near_flat", "main_flat", "none"],
    )
    p.add_argument("--theta-flat-zero-tol-deg", type=float, default=0.3)
    p.add_argument("--lambda-theta-near-flat", type=float, default=3.00)
    p.add_argument("--theta-near-flat-deg", type=float, default=0.50)
    p.add_argument("--lambda-theta-error-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-near-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-true-zero-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-active-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-small-neg", type=float, default=0.0)
    p.add_argument("--lambda-theta-small-neg-excess", type=float, default=0.0)
    p.add_argument("--theta-excess-target-deg", type=float, default=1.0)
    p.add_argument("--theta-flat-excess-target-deg", type=float, default=0.5)
    p.add_argument("--theta-small-neg-min-deg", type=float, default=-4.0)
    p.add_argument("--theta-small-neg-max-deg", type=float, default=-2.0)
    p.add_argument("--theta-gate-mode", type=str, default="none", choices=["none", "main_slope_prob"])
    p.add_argument("--theta-gate-power", type=float, default=1.0)
    p.add_argument("--theta-gate-floor", type=float, default=0.0)
    p.add_argument("--theta-neg-weight", type=float, default=None)
    p.add_argument("--theta-pos-weight", type=float, default=None)
    p.add_argument("--select-theta-weight", type=float, default=0.60)
    p.add_argument("--select-theta-ref-deg", type=float, default=1.0)
    p.add_argument("--select-theta-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-p95-weight", type=float, default=2.0)
    p.add_argument("--select-theta-near-flat-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-true-zero-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-peak-weight", type=float, default=0.0)
    p.add_argument("--select-theta-small-neg-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-bias-weight", type=float, default=1.0)
    p.add_argument("--augment-npz", type=str, default="")
    p.add_argument("--unfreeze-last-block", action="store_true")
    p.add_argument("--unfreeze-main-head", action="store_true")
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    root = find_project_root()
    _set_seed(args.seed)

    checkpoint = Path(args.checkpoint)
    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt)
    device = _select_device(args.device)
    model.to(device)
    cfg = model.cfg
    cfg.lambda_theta = float(args.lambda_theta)
    cfg.lambda_theta_flat = float(args.lambda_theta_flat)
    cfg.theta_flat_loss_mode = str(args.theta_flat_loss_mode)
    cfg.theta_flat_zero_tol_deg = float(args.theta_flat_zero_tol_deg)
    cfg.lambda_theta_near_flat = float(args.lambda_theta_near_flat)
    cfg.theta_near_flat_deg = float(args.theta_near_flat_deg)
    cfg.lambda_theta_error_excess = float(args.lambda_theta_error_excess)
    cfg.lambda_theta_flat_excess = float(args.lambda_theta_flat_excess)
    cfg.lambda_theta_near_flat_excess = float(args.lambda_theta_near_flat_excess)
    cfg.lambda_theta_true_zero_excess = float(args.lambda_theta_true_zero_excess)
    cfg.lambda_theta_active_excess = float(args.lambda_theta_active_excess)
    cfg.lambda_theta_small_neg = float(args.lambda_theta_small_neg)
    cfg.lambda_theta_small_neg_excess = float(args.lambda_theta_small_neg_excess)
    cfg.theta_excess_target_deg = float(args.theta_excess_target_deg)
    cfg.theta_flat_excess_target_deg = float(args.theta_flat_excess_target_deg)
    cfg.theta_small_neg_min_deg = float(args.theta_small_neg_min_deg)
    cfg.theta_small_neg_max_deg = float(args.theta_small_neg_max_deg)
    cfg.theta_gate_mode = str(args.theta_gate_mode)
    cfg.theta_gate_power = float(args.theta_gate_power)
    cfg.theta_gate_floor = float(args.theta_gate_floor)
    if args.theta_neg_weight is not None:
        cfg.theta_neg_weight = float(args.theta_neg_weight)
    if args.theta_pos_weight is not None:
        cfg.theta_pos_weight = float(args.theta_pos_weight)
    cfg.select_theta_weight = float(args.select_theta_weight)
    cfg.select_theta_ref_deg = float(args.select_theta_ref_deg)
    cfg.select_theta_p95_weight = float(args.select_theta_p95_weight)
    cfg.select_theta_flat_p95_weight = float(args.select_theta_flat_p95_weight)
    cfg.select_theta_near_flat_p95_weight = float(args.select_theta_near_flat_p95_weight)
    cfg.select_theta_true_zero_p95_weight = float(args.select_theta_true_zero_p95_weight)
    cfg.select_theta_flat_peak_weight = float(args.select_theta_flat_peak_weight)
    cfg.select_theta_small_neg_p95_weight = float(args.select_theta_small_neg_p95_weight)
    cfg.select_theta_flat_bias_weight = float(args.select_theta_flat_bias_weight)

    _freeze_for_theta(model, args.unfreeze_last_block, args.unfreeze_main_head)
    model.eval()
    trainable = [p for p in model.parameters() if p.requires_grad]
    if not trainable:
        raise RuntimeError("no trainable parameters selected")

    dataset_file = Path(args.dataset_file) if args.dataset_file else Path(ckpt["contract"]["dataset_file"])
    data = load_modern_tcn_dataset(dataset_file)
    train_split = data["train"]
    if args.augment_npz:
        train_split = _append_augment(train_split, Path(args.augment_npz))
    val_split = data["val"]
    test_split = data["test"]

    train_loader = DataLoader(AGVWindowDataset(train_split), batch_size=args.batch_size, shuffle=True, num_workers=0)
    val_loader = DataLoader(AGVWindowDataset(val_split), batch_size=args.batch_size, shuffle=False, num_workers=0)
    test_loader = DataLoader(AGVWindowDataset(test_split), batch_size=args.batch_size, shuffle=False, num_workers=0)
    class_w_main = class_weights(
        data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)
    ).to(device)
    class_w_turn = class_weights(
        data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)
    ).to(device)

    out_dir = root / "results" / "modern_tcn" / args.run_tag
    out_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_file = out_dir / f"modern_tcn_seed{args.seed}.pt"
    summary_csv = out_dir / f"modern_tcn_seed{args.seed}_summary.csv"
    history_csv = out_dir / f"modern_tcn_seed{args.seed}_history.csv"
    report_file = out_dir / "ModernTCN_theta_finetune_report.md"

    opt = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(args.epochs, 1))
    best_score = math.inf
    best_epoch = 0
    best_state = None
    best_val_metrics: Dict[str, object] = {}
    patience_count = 0
    history_rows = []
    t0 = time.time()

    print("[ModernTCN theta finetune] start")
    print(f"  base={checkpoint}")
    print(f"  dataset={dataset_file}")
    print(f"  train/val/test={len(train_split.X)}/{len(val_split.X)}/{len(test_split.X)}")
    print(f"  output={out_dir}")
    print(f"  device={device}")
    print(f"  trainable_params={sum(p.numel() for p in trainable)}")
    print(f"  theta_weight neg/pos={cfg.theta_neg_weight:.3f}/{cfg.theta_pos_weight:.3f}")
    print(
        f"  theta_gate={cfg.theta_gate_mode} power={cfg.theta_gate_power:.3f} "
        f"floor={cfg.theta_gate_floor:.3f}"
    )

    for epoch in range(1, args.epochs + 1):
        train_loss = _train_epoch(model, train_loader, opt, class_w_main, class_w_turn, cfg, device)
        scheduler.step()
        val_loss, val_logits_main, val_logits_turn, val_theta = _predict_full(
            model, val_loader, class_w_main, class_w_turn, cfg, device
        )
        val_metrics = compute_metrics(val_logits_main, val_logits_turn, val_theta, val_split, val_loss)
        score = selection_score(val_metrics, cfg)
        history_rows.append(_history_row(epoch, opt.param_groups[0]["lr"], train_loss, val_metrics, score))
        if score < best_score:
            best_score = score
            best_epoch = epoch
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            best_val_metrics = dict(val_metrics)
            patience_count = 0
        else:
            patience_count += 1

        if epoch == 1 or epoch % 5 == 0 or epoch == args.epochs:
            print(
                f"  epoch {epoch:03d} train={train_loss:.5f} val={val_metrics['loss_total']:.5f} "
                f"theta={val_metrics['theta_mae_deg']:.4f} "
                f"p95={val_metrics['theta_abs_le_8_p95_abs_err_deg']:.4f} "
                f"pos6_8={val_metrics['theta_pos_6_8_mae_deg']:.4f} "
                f"neg8_6={val_metrics['theta_neg_8_6_mae_deg']:.4f} "
                f"neg4_2={val_metrics['theta_neg_4_2_mae_deg']:.4f} "
                f"flat_p95={val_metrics['theta_flat_abs_p95_deg']:.4f} "
                f"zero_p95={val_metrics['theta_true_zero_abs_p95_deg']:.4f} "
                f"flat_bias={val_metrics['theta_flat_bias_deg']:.4f} score={score:.5f}"
            )
        if epoch >= args.min_epochs and patience_count >= args.patience:
            print(f"[ModernTCN theta finetune] early stop epoch={epoch}, best_epoch={best_epoch}")
            break

    if best_state is None:
        raise RuntimeError("fine-tune did not produce a checkpoint")
    model.load_state_dict(best_state)
    test_loss, logits_main, logits_turn, theta_hat = _predict_full(
        model, test_loader, class_w_main, class_w_turn, cfg, device
    )
    test_metrics = compute_metrics(logits_main, logits_turn, theta_hat, test_split, test_loss)
    train_seconds = time.time() - t0

    new_ckpt = dict(ckpt)
    new_ckpt["model_state"] = best_state
    new_ckpt["model_config"] = cfg.to_dict()
    new_ckpt["seed"] = args.seed
    new_ckpt["best_epoch"] = best_epoch
    new_ckpt["best_val_score"] = best_score
    new_ckpt["best_val_metrics"] = best_val_metrics
    new_ckpt["test_metrics"] = test_metrics
    new_ckpt["train_seconds"] = train_seconds
    new_ckpt["theta_finetune"] = {
        "base_checkpoint": str(checkpoint),
        "augment_npz": args.augment_npz,
        "unfreeze_last_block": bool(args.unfreeze_last_block),
        "unfreeze_main_head": bool(args.unfreeze_main_head),
        "theta_neg_weight": float(cfg.theta_neg_weight),
        "theta_pos_weight": float(cfg.theta_pos_weight),
        "theta_gate_mode": str(cfg.theta_gate_mode),
        "theta_gate_power": float(cfg.theta_gate_power),
        "theta_gate_floor": float(cfg.theta_gate_floor),
    }
    torch.save(new_ckpt, checkpoint_file)

    paths = {"checkpoint_file": str(checkpoint_file), "report_file": str(report_file)}
    row = metric_row(args.seed, best_epoch, test_metrics, paths)
    _write_csv(summary_csv, [row])
    _write_csv(history_csv, history_rows)
    _write_report(report_file, args, cfg.to_dict(), best_val_metrics, test_metrics, row, train_seconds)

    print("[ModernTCN theta finetune] done")
    print(f"  checkpoint={checkpoint_file}")
    print(f"  theta={test_metrics['theta_mae_deg']:.4f} deg")
    print(f"  theta_p95={test_metrics['theta_abs_le_8_p95_abs_err_deg']:.4f} deg")
    print(f"  theta_pos_6_8={test_metrics['theta_pos_6_8_mae_deg']:.4f} deg")
    print(f"  theta_neg_8_6={test_metrics['theta_neg_8_6_mae_deg']:.4f} deg")
    print(f"  theta_neg_4_2={test_metrics['theta_neg_4_2_mae_deg']:.4f} deg")
    print(f"  flat_p95={test_metrics['theta_flat_abs_p95_deg']:.4f} deg")
    print(f"  true_zero_p95={test_metrics['theta_true_zero_abs_p95_deg']:.4f} deg")
    print(f"  flat_bias={test_metrics['theta_flat_bias_deg']:.4f} deg")
    print(f"  near_flat_p95={test_metrics['theta_near_flat_abs_p95_deg']:.4f} deg")
    print(f"  main={test_metrics['acc_main']:.4f} turn={test_metrics['acc_turn']:.4f}")
    return {"checkpoint_file": str(checkpoint_file), "test_metrics": test_metrics}


def _freeze_for_theta(model, unfreeze_last_block: bool, unfreeze_main_head: bool = False) -> None:
    for p in model.parameters():
        p.requires_grad = False
    for p in model.theta_head.parameters():
        p.requires_grad = True
    if unfreeze_main_head:
        for p in model.main_head.parameters():
            p.requires_grad = True
    if unfreeze_last_block and len(model.blocks) > 0:
        for p in model.blocks[-1].parameters():
            p.requires_grad = True


def _append_augment(split: SplitArrays, npz_file: Path) -> SplitArrays:
    if not npz_file.exists():
        raise FileNotFoundError(f"missing augment file: {npz_file}")
    aug = np.load(npz_file)
    X = aug["X"].astype(np.float32)
    n = X.shape[0]
    y_theta = aug["y_theta"].astype(np.float32).reshape(-1)
    y_main = aug["y_main"].astype(np.int64).reshape(-1) if "y_main" in aug else np.zeros(n, dtype=np.int64)
    y_turn = aug["y_turn"].astype(np.int64).reshape(-1) if "y_turn" in aug else np.ones(n, dtype=np.int64)
    mask_theta = aug["mask_theta"].astype(np.float32).reshape(-1) if "mask_theta" in aug else np.ones(n, dtype=np.float32)
    main_weight = aug["main_weight"].astype(np.float32).reshape(-1) if "main_weight" in aug else np.zeros(n, dtype=np.float32)
    turn_weight = aug["turn_weight"].astype(np.float32).reshape(-1) if "turn_weight" in aug else np.zeros(n, dtype=np.float32)
    theta_weight = aug["theta_weight"].astype(np.float32).reshape(-1) if "theta_weight" in aug else np.ones(n, dtype=np.float32)
    turn_purity = aug["turn_purity"].astype(np.float32).reshape(-1) if "turn_purity" in aug else np.ones(n, dtype=np.float32)
    turn_transition = aug["turn_transition"].astype(bool).reshape(-1) if "turn_transition" in aug else np.zeros(n, dtype=bool)
    run_id = aug["run_id"].astype(np.float32).reshape(-1) if "run_id" in aug else np.full(n, -1, dtype=np.float32)
    return SplitArrays(
        X=np.concatenate([split.X, X], axis=0),
        y_main=np.concatenate([split.y_main, y_main], axis=0),
        y_turn=np.concatenate([split.y_turn, y_turn], axis=0),
        y_theta=np.concatenate([split.y_theta, y_theta], axis=0),
        mask_theta=np.concatenate([split.mask_theta, mask_theta], axis=0),
        main_weight=np.concatenate([split.main_weight, main_weight], axis=0),
        turn_weight=np.concatenate([split.turn_weight, turn_weight], axis=0),
        theta_weight=np.concatenate([split.theta_weight, theta_weight], axis=0),
        turn_purity=np.concatenate([split.turn_purity, turn_purity], axis=0),
        turn_transition=np.concatenate([split.turn_transition, turn_transition], axis=0),
        run_id=np.concatenate([split.run_id, run_id], axis=0),
    )


def _train_epoch(model, loader, opt, class_w_main, class_w_turn, cfg, device) -> float:
    model.eval()
    total_loss = 0.0
    total_n = 0
    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        opt.zero_grad(set_to_none=True)
        logits_main, logits_turn, theta_hat = model(batch["X"])
        loss, _ = multitask_loss(logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg)
        loss.backward()
        torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], max_norm=1.0)
        opt.step()
        n = int(batch["X"].shape[0])
        total_loss += float(loss.detach().cpu()) * n
        total_n += n
    return total_loss / max(total_n, 1)


@torch.no_grad()
def _predict_full(model, loader, class_w_main, class_w_turn, cfg, device) -> Tuple[float, np.ndarray, np.ndarray, np.ndarray]:
    model.eval()
    logits_main_all = []
    logits_turn_all = []
    theta_all = []
    loss_sum = 0.0
    n_sum = 0
    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        logits_main, logits_turn, theta_hat = model(batch["X"])
        loss, _ = multitask_loss(logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg)
        n = int(batch["X"].shape[0])
        loss_sum += float(loss.detach().cpu()) * n
        n_sum += n
        logits_main_all.append(logits_main.detach().cpu().numpy())
        logits_turn_all.append(logits_turn.detach().cpu().numpy())
        theta_all.append(theta_hat.detach().cpu().numpy())
    return (
        loss_sum / max(n_sum, 1),
        np.concatenate(logits_main_all, axis=0),
        np.concatenate(logits_turn_all, axis=0),
        np.concatenate(theta_all, axis=0).reshape(-1),
    )


def _history_row(epoch: int, lr: float, train_loss: float, val_metrics: Dict[str, object], score: float) -> Dict[str, object]:
    return {
        "epoch": epoch,
        "lr": lr,
        "train_loss": train_loss,
        "val_loss": val_metrics["loss_total"],
        "val_score": score,
        "val_theta_mae_deg": val_metrics["theta_mae_deg"],
        "val_theta_abs_le_8_p95_abs_err_deg": val_metrics["theta_abs_le_8_p95_abs_err_deg"],
        "val_theta_flat_abs_p95_deg": val_metrics["theta_flat_abs_p95_deg"],
        "val_theta_flat_abs_max_deg": val_metrics["theta_flat_abs_max_deg"],
        "val_theta_flat_bias_deg": val_metrics["theta_flat_bias_deg"],
        "val_theta_near_flat_abs_p95_deg": val_metrics["theta_near_flat_abs_p95_deg"],
        "val_theta_true_zero_abs_p95_deg": val_metrics["theta_true_zero_abs_p95_deg"],
        "val_theta_abs_le_8_mae_deg": val_metrics["theta_abs_le_8_mae_deg"],
        "val_theta_abs_le_10_mae_deg": val_metrics["theta_abs_le_10_mae_deg"],
        "val_theta_pos_6_8_mae_deg": val_metrics["theta_pos_6_8_mae_deg"],
        "val_theta_neg_8_6_mae_deg": val_metrics["theta_neg_8_6_mae_deg"],
        "val_theta_neg_4_2_mae_deg": val_metrics["theta_neg_4_2_mae_deg"],
        "val_theta_neg_4_2_p95_abs_err_deg": val_metrics["theta_neg_4_2_p95_abs_err_deg"],
        "val_acc_main": val_metrics["acc_main"],
        "val_acc_turn": val_metrics["acc_turn"],
        "val_acc_turn_transition": val_metrics["acc_turn_transition"],
    }


def _write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _write_report(
    path: Path,
    args: argparse.Namespace,
    cfg: Dict[str, object],
    val_metrics: Dict[str, object],
    test_metrics: Dict[str, object],
    row: Dict[str, object],
    train_seconds: float,
) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN theta-head fine-tune report\n\n")
        f.write(f"- base checkpoint: `{args.checkpoint}`\n")
        f.write(f"- augment npz: `{args.augment_npz}`\n")
        f.write(f"- best epoch: {row['best_epoch']}\n")
        f.write(f"- train seconds: {train_seconds:.1f}\n\n")
        f.write("## Config\n\n```json\n")
        f.write(json.dumps(cfg, indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("## Test Metrics\n\n| metric | value |\n|---|---:|\n")
        for key in [
            "acc_main",
            "acc_turn",
            "acc_turn_transition",
            "turn_left_recall",
            "theta_mae_deg",
            "theta_abs_le_8_mae_deg",
            "theta_abs_le_8_p95_abs_err_deg",
            "theta_abs_le_8_max_abs_err_deg",
            "theta_abs_le_10_mae_deg",
            "theta_abs_le_10_p95_abs_err_deg",
            "theta_pos_6_8_mae_deg",
            "theta_pos_6_8_p95_abs_err_deg",
            "theta_pos_6_8_bias_deg",
            "theta_neg_8_6_mae_deg",
            "theta_neg_8_6_p95_abs_err_deg",
            "theta_neg_8_6_bias_deg",
            "theta_active_abs_ge_2_mae_deg",
            "theta_active_abs_ge_2_p95_abs_err_deg",
            "theta_neg_4_2_mae_deg",
            "theta_neg_4_2_p95_abs_err_deg",
            "theta_neg_4_2_bias_deg",
            "theta_flat_abs_p95_deg",
            "theta_flat_abs_max_deg",
            "theta_flat_bias_deg",
            "theta_near_flat_abs_p95_deg",
            "theta_near_flat_abs_max_deg",
            "theta_near_flat_bias_deg",
            "theta_true_zero_abs_p95_deg",
            "theta_true_zero_abs_max_deg",
            "theta_true_zero_bias_deg",
            "theta_flat_turn_abs_p95_deg",
            "flat_recall",
            "slope_recall",
            "slope_sign_acc",
        ]:
            f.write(f"| {key} | {float(test_metrics.get(key, float('nan'))):.4f} |\n")
        f.write("\n## Validation Best Metrics\n\n```json\n")
        f.write(json.dumps(val_metrics, indent=2, ensure_ascii=False))
        f.write("\n```\n")


def _set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def _select_device(name: str) -> torch.device:
    if name == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError("requested cuda but torch.cuda.is_available() is false")
        return torch.device("cuda")
    if name == "cpu":
        return torch.device("cpu")
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


if __name__ == "__main__":
    main()
