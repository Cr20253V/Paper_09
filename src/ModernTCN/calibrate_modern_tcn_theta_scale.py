"""Apply a scalar calibration to a ModernTCN theta head and re-evaluate.

The calibration multiplies ``theta_head.weight`` and ``theta_head.bias`` in the
checkpoint state dict. For the optional slope-probability theta gate this is
equivalent to multiplying the final theta output, while leaving all
classification outputs unchanged.
"""

from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path
from typing import Dict, Iterable, Tuple

import numpy as np
import torch
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics, metric_row, multitask_loss
from modern_tcn_model import build_model_from_checkpoint_dict


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Scale-calibrate ModernTCN theta head")
    p.add_argument("--checkpoint", type=str, required=True)
    p.add_argument("--dataset-file", type=str, required=True)
    p.add_argument("--run-tag", type=str, required=True)
    p.add_argument("--scale", type=float, required=True)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--batch-size", type=int, default=512)
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    root = find_project_root()
    checkpoint = Path(args.checkpoint)
    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    state = {k: v.detach().cpu().clone() for k, v in ckpt["model_state"].items()}
    for key in ("theta_head.weight", "theta_head.bias"):
        if key not in state:
            raise KeyError(f"checkpoint does not contain {key}")
        state[key] = state[key] * float(args.scale)
    new_ckpt = dict(ckpt)
    new_ckpt["model_state"] = state
    new_ckpt["theta_scale_calibration"] = {
        "base_checkpoint": str(checkpoint),
        "scale": float(args.scale),
        "note": "theta_head weight and bias multiplied by scale; classification heads unchanged",
    }

    model = build_model_from_checkpoint_dict(new_ckpt)
    device = _select_device(args.device)
    model.to(device).eval()
    cfg = model.cfg
    data = load_modern_tcn_dataset(Path(args.dataset_file))
    test_split = data["test"]
    test_loader = DataLoader(AGVWindowDataset(test_split), batch_size=args.batch_size, shuffle=False, num_workers=0)
    class_w_main = class_weights(
        data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)
    ).to(device)
    class_w_turn = class_weights(
        data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)
    ).to(device)

    t0 = time.time()
    test_loss, logits_main, logits_turn, theta_hat = _predict_full(
        model, test_loader, class_w_main, class_w_turn, cfg, device
    )
    test_metrics = compute_metrics(logits_main, logits_turn, theta_hat, test_split, test_loss)
    new_ckpt["test_metrics"] = test_metrics
    new_ckpt["train_seconds"] = float(ckpt.get("train_seconds", 0.0))

    out_dir = root / "results" / "modern_tcn" / args.run_tag
    out_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_file = out_dir / f"modern_tcn_seed{args.seed}.pt"
    summary_csv = out_dir / f"modern_tcn_seed{args.seed}_summary.csv"
    report_file = out_dir / "ModernTCN_theta_scale_calibration_report.md"
    new_ckpt["theta_scale_calibration"]["elapsed_seconds"] = time.time() - t0
    torch.save(new_ckpt, checkpoint_file)
    row = metric_row(args.seed, int(new_ckpt.get("best_epoch", 0)), test_metrics, {"checkpoint_file": str(checkpoint_file), "report_file": str(report_file)})
    _write_csv(summary_csv, [row])
    _write_report(report_file, args, checkpoint_file, test_metrics)
    print("[ModernTCN theta scale calibration] done")
    print(f"  checkpoint={checkpoint_file}")
    print(f"  theta_mae={test_metrics['theta_mae_deg']:.4f}")
    print(f"  theta_p95={test_metrics['theta_abs_le_8_p95_abs_err_deg']:.4f}")
    print(f"  flat_p95={test_metrics['theta_flat_abs_p95_deg']:.4f}")
    print(f"  zero_p95={test_metrics['theta_true_zero_abs_p95_deg']:.4f}")
    return {"checkpoint_file": str(checkpoint_file), "test_metrics": test_metrics}


@torch.no_grad()
def _predict_full(model, loader, class_w_main, class_w_turn, cfg, device) -> Tuple[float, np.ndarray, np.ndarray, np.ndarray]:
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


def _write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _write_report(path: Path, args: argparse.Namespace, checkpoint_file: Path, metrics: Dict[str, object]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN theta scale calibration report\n\n")
        f.write(f"- base checkpoint: `{args.checkpoint}`\n")
        f.write(f"- output checkpoint: `{checkpoint_file}`\n")
        f.write(f"- theta scale: `{args.scale:.6f}`\n\n")
        f.write("| metric | value |\n|---|---:|\n")
        for key in [
            "acc_main",
            "acc_turn",
            "acc_turn_transition",
            "theta_mae_deg",
            "theta_abs_le_8_p95_abs_err_deg",
            "theta_abs_le_8_max_abs_err_deg",
            "theta_flat_abs_p95_deg",
            "theta_near_flat_abs_p95_deg",
            "theta_true_zero_abs_p95_deg",
            "theta_flat_abs_max_deg",
            "slope_recall",
            "uphill_recall",
            "downhill_recall",
        ]:
            f.write(f"| {key} | {float(metrics.get(key, float('nan'))):.6f} |\n")


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
