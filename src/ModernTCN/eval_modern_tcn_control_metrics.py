"""Evaluate ModernTCN with theta metrics relevant to MPC scheduling.

The regular training summary reports slope-only theta MAE.  For controller
scheduling we also need to know whether flat/near-flat windows produce fake
slope.  This script evaluates an existing checkpoint on one dataset split and
writes a compact JSON/CSV report.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Dict

import numpy as np
import torch
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics, multitask_loss
from modern_tcn_model import build_model_from_checkpoint_dict


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN control-oriented theta evaluation")
    p.add_argument("--checkpoint", type=str, required=True)
    p.add_argument("--dataset-file", type=str, default="")
    p.add_argument("--split", type=str, default="test", choices=["train", "val", "test"])
    p.add_argument("--batch-size", type=int, default=512)
    p.add_argument("--output-dir", type=str, default="")
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    root = find_project_root()
    checkpoint = Path(args.checkpoint)
    if not checkpoint.exists():
        raise FileNotFoundError(f"missing checkpoint: {checkpoint}")
    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).eval()
    device = torch.device("cpu")
    model.to(device)

    dataset_file = Path(args.dataset_file) if args.dataset_file else Path(ckpt["contract"]["dataset_file"])
    data = load_modern_tcn_dataset(dataset_file)
    split = data[args.split]
    loader = DataLoader(AGVWindowDataset(split), batch_size=args.batch_size, shuffle=False)
    cfg = model.cfg
    class_w_main = class_weights(
        data["train"].y_main, 3, cfg.main_class_weight_method, list(cfg.main_class_multipliers)
    ).to(device)
    class_w_turn = class_weights(
        data["train"].y_turn, 3, cfg.turn_class_weight_method, list(cfg.turn_class_multipliers)
    ).to(device)

    logits_main, logits_turn, theta_hat, loss_total = _predict(model, loader, class_w_main, class_w_turn, cfg)
    metrics = compute_metrics(logits_main, logits_turn, theta_hat, split, loss_total)
    result = {
        "checkpoint": str(checkpoint),
        "dataset_file": str(dataset_file),
        "split": args.split,
        "n": int(split.X.shape[0]),
        "metrics": metrics,
    }

    out_dir = Path(args.output_dir) if args.output_dir else checkpoint.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{checkpoint.stem}_{args.split}_control_metrics"
    json_file = out_dir / f"{stem}.json"
    csv_file = out_dir / f"{stem}.csv"
    json_file.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    _write_csv(csv_file, metrics)

    keys = [
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "turn_left_recall",
        "theta_mae_deg",
        "theta_flat_abs_p95_deg",
        "theta_flat_bias_deg",
        "theta_near_flat_abs_p95_deg",
        "theta_near_flat_bias_deg",
        "theta_flat_turn_abs_p95_deg",
        "theta_slope_control_mae_deg",
        "slope_sign_acc",
        "flat_recall",
        "slope_recall",
    ]
    print("[ModernTCN control metrics]")
    print(f"  checkpoint={checkpoint}")
    print(f"  dataset={dataset_file}")
    for key in keys:
        value = metrics.get(key, float("nan"))
        print(f"  {key}={float(value):.6f}")
    print(f"  json={json_file}")
    print(f"  csv={csv_file}")
    return result


@torch.no_grad()
def _predict(model, loader, class_w_main, class_w_turn, cfg):
    logits_main_all = []
    logits_turn_all = []
    theta_all = []
    loss_sum = 0.0
    n_sum = 0
    for batch in loader:
        batch = {k: v.to("cpu") for k, v in batch.items()}
        logits_main, logits_turn, theta_hat = model(batch["X"])
        loss, _ = multitask_loss(logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg)
        n = int(batch["X"].shape[0])
        loss_sum += float(loss.detach().cpu()) * n
        n_sum += n
        logits_main_all.append(logits_main.detach().cpu().numpy())
        logits_turn_all.append(logits_turn.detach().cpu().numpy())
        theta_all.append(theta_hat.detach().cpu().numpy())
    return (
        np.concatenate(logits_main_all, axis=0),
        np.concatenate(logits_turn_all, axis=0),
        np.concatenate(theta_all, axis=0).reshape(-1),
        loss_sum / max(n_sum, 1),
    )


def _write_csv(path: Path, metrics: Dict[str, object]) -> None:
    rows = []
    for key, value in metrics.items():
        if isinstance(value, (int, float, np.floating)) and not isinstance(value, bool):
            rows.append({"metric": key, "value": float(value)})
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["metric", "value"])
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - command-line diagnostics
        print(f"[ModernTCN control metrics] failed: {exc}", file=sys.stderr)
        raise
