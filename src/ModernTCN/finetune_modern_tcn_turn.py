"""Fine-tune the ModernTCN turn head for closed-loop deployment.

The Node 7.5 closed-loop attribution points to turn probability calibration:
ModernTCN often predicts straight through real turn windows.  This script keeps
the deployed backbone, main head, and theta head intact by default, and updates
only ``turn_head`` using stronger transition and left/right class weighting.
Optional flags can unfreeze the final block/main/theta heads for controlled
hard-window recovery experiments.
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
    p = argparse.ArgumentParser(description="Fine-tune ModernTCN turn/head hard windows")
    p.add_argument("--checkpoint", type=str, required=True)
    p.add_argument("--dataset-file", type=str, default="")
    p.add_argument("--run-tag", type=str, required=True)
    p.add_argument("--seed", type=int, default=21)
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--batch-size", type=int, default=512)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-5)
    p.add_argument("--patience", type=int, default=12)
    p.add_argument("--min-epochs", type=int, default=8)
    p.add_argument("--lambda-turn", type=float, default=1.0)
    p.add_argument("--turn-transition-weight", type=float, default=6.0)
    p.add_argument("--turn-class-multipliers", type=float, nargs=3, default=[2.2, 0.55, 2.2])
    p.add_argument("--select-turn-weight", type=float, default=1.0)
    p.add_argument("--select-turn-transition-weight", type=float, default=4.0)
    p.add_argument("--select-turn-transition-target", type=float, default=0.82)
    p.add_argument("--select-turn-left-weight", type=float, default=1.5)
    p.add_argument("--select-turn-left-target", type=float, default=0.82)
    p.add_argument("--select-turn-lr-weight", type=float, default=1.5)
    p.add_argument("--select-turn-lr-target", type=float, default=0.80)
    p.add_argument("--lambda-theta", type=float, default=None)
    p.add_argument("--lambda-theta-flat", type=float, default=None)
    p.add_argument("--lambda-theta-error-excess", type=float, default=None)
    p.add_argument("--lambda-theta-active-excess", type=float, default=None)
    p.add_argument("--theta-excess-target-deg", type=float, default=None)
    p.add_argument("--select-theta-weight", type=float, default=None)
    p.add_argument("--select-theta-p95-weight", type=float, default=None)
    p.add_argument("--select-theta-p95-target-deg", type=float, default=None)
    p.add_argument("--select-theta-edge-p95-weight", type=float, default=None)
    p.add_argument("--select-theta-edge-p95-target-deg", type=float, default=None)
    p.add_argument("--limit-train", type=int, default=0)
    p.add_argument("--limit-val", type=int, default=0)
    p.add_argument("--limit-test", type=int, default=0)
    p.add_argument("--augment-npz", type=str, default="")
    p.add_argument("--unfreeze-last-block", action="store_true")
    p.add_argument("--unfreeze-main-head", action="store_true")
    p.add_argument("--unfreeze-theta-head", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    root = find_project_root()
    _set_seed(args.seed)

    checkpoint = Path(args.checkpoint)
    if not checkpoint.exists():
        raise FileNotFoundError(f"missing checkpoint: {checkpoint}")
    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt)
    device = _select_device(args.device)
    model.to(device)
    cfg = model.cfg

    cfg.lambda_turn = float(args.lambda_turn)
    cfg.turn_transition_weight = float(args.turn_transition_weight)
    cfg.turn_class_multipliers = tuple(float(x) for x in args.turn_class_multipliers)
    cfg.select_turn_weight = float(args.select_turn_weight)
    cfg.select_turn_transition_weight = float(args.select_turn_transition_weight)
    cfg.select_turn_transition_target = float(args.select_turn_transition_target)
    cfg.select_turn_left_weight = float(args.select_turn_left_weight)
    cfg.select_turn_left_target = float(args.select_turn_left_target)
    cfg.select_turn_lr_weight = float(args.select_turn_lr_weight)
    cfg.select_turn_lr_target = float(args.select_turn_lr_target)
    _set_if_not_none(cfg, "lambda_theta", args.lambda_theta)
    _set_if_not_none(cfg, "lambda_theta_flat", args.lambda_theta_flat)
    _set_if_not_none(cfg, "lambda_theta_error_excess", args.lambda_theta_error_excess)
    _set_if_not_none(cfg, "lambda_theta_active_excess", args.lambda_theta_active_excess)
    _set_if_not_none(cfg, "theta_excess_target_deg", args.theta_excess_target_deg)
    _set_if_not_none(cfg, "select_theta_weight", args.select_theta_weight)
    _set_if_not_none(cfg, "select_theta_p95_weight", args.select_theta_p95_weight)
    _set_if_not_none(cfg, "select_theta_p95_target_deg", args.select_theta_p95_target_deg)
    _set_if_not_none(cfg, "select_theta_edge_p95_weight", args.select_theta_edge_p95_weight)
    _set_if_not_none(cfg, "select_theta_edge_p95_target_deg", args.select_theta_edge_p95_target_deg)

    _freeze_for_turn(model, args.unfreeze_last_block, args.unfreeze_main_head, args.unfreeze_theta_head)
    trainable = [p for p in model.parameters() if p.requires_grad]
    if not trainable:
        raise RuntimeError("no trainable parameters selected")

    dataset_file = Path(args.dataset_file) if args.dataset_file else Path(ckpt["contract"]["dataset_file"])
    data = load_modern_tcn_dataset(
        dataset_file=dataset_file,
        limit_train=args.limit_train,
        limit_val=args.limit_val,
        limit_test=args.limit_test,
    )
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

    print("[ModernTCN turn finetune] preflight")
    print(f"  base={checkpoint}")
    print(f"  dataset={dataset_file}")
    print(f"  train/val/test={len(train_split.X)}/{len(val_split.X)}/{len(test_split.X)}")
    print(f"  device={device}")
    print(f"  trainable_params={sum(p.numel() for p in trainable)}")
    print(f"  trainable_names={', '.join(_trainable_names(model))}")
    print(f"  lambda_turn={cfg.lambda_turn:.3f}, transition_weight={cfg.turn_transition_weight:.3f}")
    print(f"  lambda_theta={cfg.lambda_theta:.3f}, theta_excess_target_deg={cfg.theta_excess_target_deg:.3f}")
    print(f"  turn_class_multipliers={list(cfg.turn_class_multipliers)}")

    if args.dry_run:
        xb = torch.from_numpy(train_split.X[:4]).float().to(device)
        with torch.no_grad():
            outputs = model(xb)
        print("[ModernTCN turn finetune] dry-run ok")
        print(f"  X: {tuple(xb.shape)}")
        print(f"  outputs: {[tuple(o.shape) for o in outputs]}")
        return {"status": "dry_run_ok", "trainable_params": sum(p.numel() for p in trainable)}

    out_dir = root / "results" / "modern_tcn" / args.run_tag
    out_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_file = out_dir / f"modern_tcn_seed{args.seed}.pt"
    summary_csv = out_dir / f"modern_tcn_seed{args.seed}_summary.csv"
    history_csv = out_dir / f"modern_tcn_seed{args.seed}_history.csv"
    report_file = out_dir / "ModernTCN_turn_finetune_report.md"

    opt = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(args.epochs, 1))
    best_score = math.inf
    best_epoch = 0
    best_state = None
    best_val_metrics: Dict[str, object] = {}
    patience_count = 0
    history_rows = []
    t0 = time.time()

    print("[ModernTCN turn finetune] start")
    print(f"  output={out_dir}")

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
                f"turn={val_metrics['acc_turn']:.4f} turnT={val_metrics['acc_turn_transition']:.4f} "
                f"right={val_metrics['turn_right_recall']:.4f} straight={val_metrics['turn_straight_recall']:.4f} "
                f"left={val_metrics['turn_left_recall']:.4f} theta={val_metrics['theta_mae_deg']:.4f} "
                f"score={score:.5f}"
            )
        if epoch >= args.min_epochs and patience_count >= args.patience:
            print(f"[ModernTCN turn finetune] early stop epoch={epoch}, best_epoch={best_epoch}")
            break

    if best_state is None:
        raise RuntimeError("turn fine-tune did not produce a checkpoint")
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
    new_ckpt["turn_finetune"] = {
        "base_checkpoint": str(checkpoint),
        "augment_npz": args.augment_npz,
        "unfreeze_last_block": bool(args.unfreeze_last_block),
        "unfreeze_main_head": bool(args.unfreeze_main_head),
        "unfreeze_theta_head": bool(args.unfreeze_theta_head),
        "lambda_turn": float(cfg.lambda_turn),
        "lambda_theta": float(cfg.lambda_theta),
        "lambda_theta_error_excess": float(getattr(cfg, "lambda_theta_error_excess", 0.0)),
        "lambda_theta_active_excess": float(getattr(cfg, "lambda_theta_active_excess", 0.0)),
        "theta_excess_target_deg": float(getattr(cfg, "theta_excess_target_deg", 1.0)),
        "turn_transition_weight": float(cfg.turn_transition_weight),
        "turn_class_multipliers": list(cfg.turn_class_multipliers),
        "trainable_names": _trainable_names(model),
    }
    torch.save(new_ckpt, checkpoint_file)

    paths = {"checkpoint_file": str(checkpoint_file), "report_file": str(report_file)}
    row = metric_row(args.seed, best_epoch, test_metrics, paths)
    _write_csv(summary_csv, [row])
    _write_csv(history_csv, history_rows)
    _write_report(report_file, args, cfg.to_dict(), best_val_metrics, test_metrics, row, train_seconds)

    print("[ModernTCN turn finetune] done")
    print(f"  checkpoint={checkpoint_file}")
    print(
        f"  test turn={test_metrics['acc_turn']:.4f}, turnT={test_metrics['acc_turn_transition']:.4f}, "
        f"right={test_metrics['turn_right_recall']:.4f}, straight={test_metrics['turn_straight_recall']:.4f}, "
        f"left={test_metrics['turn_left_recall']:.4f}"
    )
    print(
        f"  test main={test_metrics['acc_main']:.4f}, theta={test_metrics['theta_mae_deg']:.4f} deg, "
        f"flat={test_metrics['flat_recall']:.4f}, slope={test_metrics['slope_recall']:.4f}"
    )
    return {"checkpoint_file": str(checkpoint_file), "test_metrics": test_metrics}


def _set_if_not_none(cfg, name: str, value) -> None:
    if value is not None:
        setattr(cfg, name, float(value))


def _freeze_for_turn(
    model,
    unfreeze_last_block: bool,
    unfreeze_main_head: bool = False,
    unfreeze_theta_head: bool = False,
) -> None:
    for p in model.parameters():
        p.requires_grad = False
    for p in model.turn_head.parameters():
        p.requires_grad = True
    if unfreeze_main_head:
        for p in model.main_head.parameters():
            p.requires_grad = True
    if unfreeze_theta_head:
        for p in model.theta_head.parameters():
            p.requires_grad = True
    if unfreeze_last_block and len(model.blocks) > 0:
        for p in model.blocks[-1].parameters():
            p.requires_grad = True


def _trainable_names(model) -> list[str]:
    names = []
    for name, param in model.named_parameters():
        if param.requires_grad:
            names.append(name)
    return names


def _append_augment(split: SplitArrays, npz_file: Path) -> SplitArrays:
    if not npz_file.exists():
        raise FileNotFoundError(f"missing augment file: {npz_file}")
    aug = np.load(npz_file)
    X = aug["X"].astype(np.float32)
    n = X.shape[0]
    y_turn = aug["y_turn"].astype(np.int64).reshape(-1) if "y_turn" in aug else np.ones(n, dtype=np.int64)
    y_main = aug["y_main"].astype(np.int64).reshape(-1) if "y_main" in aug else np.zeros(n, dtype=np.int64)
    y_theta = aug["y_theta"].astype(np.float32).reshape(-1) if "y_theta" in aug else np.zeros(n, dtype=np.float32)
    mask_theta = aug["mask_theta"].astype(np.float32).reshape(-1) if "mask_theta" in aug else np.zeros(n, dtype=np.float32)
    main_weight = aug["main_weight"].astype(np.float32).reshape(-1) if "main_weight" in aug else np.zeros(n, dtype=np.float32)
    turn_weight = aug["turn_weight"].astype(np.float32).reshape(-1) if "turn_weight" in aug else np.ones(n, dtype=np.float32)
    theta_weight = aug["theta_weight"].astype(np.float32).reshape(-1) if "theta_weight" in aug else np.zeros(n, dtype=np.float32)
    turn_purity = aug["turn_purity"].astype(np.float32).reshape(-1) if "turn_purity" in aug else np.ones(n, dtype=np.float32)
    turn_transition = aug["turn_transition"].astype(bool).reshape(-1) if "turn_transition" in aug else np.zeros(n, dtype=bool)
    run_id = aug["run_id"].astype(np.float32).reshape(-1) if "run_id" in aug else np.full(n, -2, dtype=np.float32)
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
        "val_acc_main": val_metrics["acc_main"],
        "val_acc_turn": val_metrics["acc_turn"],
        "val_acc_turn_transition": val_metrics["acc_turn_transition"],
        "val_acc_turn_pure": val_metrics["acc_turn_pure"],
        "val_turn_right_recall": val_metrics["turn_right_recall"],
        "val_turn_straight_recall": val_metrics["turn_straight_recall"],
        "val_turn_left_recall": val_metrics["turn_left_recall"],
        "val_turn_confidence_mean": val_metrics.get("turn_confidence_mean", float("nan")),
        "val_turn_low_conf_0p60_ratio": val_metrics.get("turn_low_conf_0p60_ratio", float("nan")),
        "val_acc_main": val_metrics["acc_main"],
        "val_theta_mae_deg": val_metrics["theta_mae_deg"],
        "val_flat_recall": val_metrics["flat_recall"],
        "val_slope_recall": val_metrics["slope_recall"],
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
        f.write("# ModernTCN turn-head fine-tune report\n\n")
        f.write(f"- base checkpoint: `{args.checkpoint}`\n")
        f.write(f"- augment npz: `{args.augment_npz}`\n")
        f.write(f"- best epoch: {row['best_epoch']}\n")
        f.write(f"- train seconds: {train_seconds:.1f}\n")
        f.write(f"- unfreeze last block: `{bool(args.unfreeze_last_block)}`\n")
        f.write(f"- unfreeze main head: `{bool(args.unfreeze_main_head)}`\n\n")
        f.write(f"- unfreeze theta head: `{bool(args.unfreeze_theta_head)}`\n\n")
        f.write("## Config\n\n```json\n")
        f.write(json.dumps(cfg, indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("## Test Metrics\n\n| metric | value |\n|---|---:|\n")
        for key in [
            "acc_main",
            "acc_turn",
            "acc_turn_pure",
            "acc_turn_transition",
            "turn_right_recall",
            "turn_straight_recall",
            "turn_left_recall",
            "turn_confidence_mean",
            "turn_low_conf_0p60_ratio",
            "turn_low_conf_0p70_ratio",
            "theta_mae_deg",
            "flat_recall",
            "slope_recall",
            "main_confidence_mean",
            "main_low_conf_0p60_ratio",
            "main_low_conf_0p70_ratio",
        ]:
            f.write(f"| {key} | {float(test_metrics.get(key, float('nan'))):.4f} |\n")
        f.write("\n## Confusion Matrix Turn\n\n")
        f.write("Rows are true `[right, straight, left]`; columns are predicted `[right, straight, left]`.\n\n")
        f.write("```json\n")
        f.write(json.dumps(test_metrics.get("cm_turn", []), indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("## Validation Best Metrics\n\n```json\n")
        f.write(json.dumps(val_metrics, indent=2, ensure_ascii=False))
        f.write("\n```\n")


def _set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True


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
