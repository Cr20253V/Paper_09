#!/usr/bin/env python3
"""Native PyTorch inference for the 20 frozen ModernTCN A1 cases."""

from __future__ import annotations

import csv
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch


def find_root() -> Path:
    for p in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (p / "init_project.m").is_file():
            return p
    raise RuntimeError("project root not found")


ROOT = find_root()
TASK = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison"
sys.path.insert(0, str(ROOT / "src/ModernTCN"))
from modern_tcn_data import load_modern_tcn_dataset  # noqa: E402
from modern_tcn_lag_features import augment_array_by_metadata  # noqa: E402
from modern_tcn_model import build_model_from_checkpoint_dict  # noqa: E402


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def valid_output(path: Path, expected: int) -> bool:
    if not path.is_file():
        return False
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as f:
            return sum(1 for _ in f) == expected + 1
    except OSError:
        return False


def infer_case(method: str, seed: int, model_file: Path, split, device: torch.device) -> Path:
    out = TASK / "03_offline/raw" / f"{method}_seed{seed}_predictions.csv"
    audit = out.with_suffix(".audit.json")
    if valid_output(out, len(split.X)) and audit.is_file():
        print(f"[A1 offline modern] reuse {method} seed={seed}")
        return out
    started = time.time()
    ckpt = torch.load(model_file, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt).to(device).eval()
    aug = dict(ckpt.get("input_augmentation", {}) or {})
    X = augment_array_by_metadata(split.X, aug)
    expected_dim = int(ckpt["model_config"]["input_dim"])
    if X.shape != (len(split.X), 128, expected_dim):
        raise ValueError(f"{method} seed={seed}: augmented shape {X.shape}, expected (*,128,{expected_dim})")
    main_parts, turn_parts, theta_parts = [], [], []
    with torch.no_grad():
        for start in range(0, len(X), 256):
            xb = torch.from_numpy(X[start : start + 256]).float().to(device)
            lm, lt, th = model(xb)
            main_parts.append(lm.detach().cpu().numpy())
            turn_parts.append(lt.detach().cpu().numpy())
            theta_parts.append(th.detach().cpu().numpy().reshape(-1))
    lm = np.concatenate(main_parts, axis=0)
    lt = np.concatenate(turn_parts, axis=0)
    th = np.concatenate(theta_parts, axis=0)
    pred_main = lm.argmax(axis=1)
    pred_turn = lt.argmax(axis=1)
    fields = ["window_index", "run_id", "y_main_true", "y_turn_true", "theta_true_rad", "mask_theta", "pred_main", "pred_turn", "theta_hat_rad", "main_logit_0", "main_logit_1", "main_logit_2", "turn_logit_0", "turn_logit_1", "turn_logit_2"]
    tmp = out.with_suffix(".tmp.csv")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(fields)
        for i in range(len(X)):
            w.writerow([i + 1, float(split.run_id[i]), int(split.y_main[i]), int(split.y_turn[i]), float(split.y_theta[i]), int(split.mask_theta[i]), int(pred_main[i]), int(pred_turn[i]), float(th[i]), *[float(x) for x in lm[i]], *[float(x) for x in lt[i]]])
    tmp.replace(out)
    audit.write_text(json.dumps({
        "task_id": "A1_algorithm_comparison", "method_id": method, "seed": seed,
        "model_file": str(model_file), "model_sha256": sha256(model_file),
        "dataset_file": str(ROOT / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"),
        "test_windows": len(X), "seq_len": 128, "raw_input_dim": 22, "effective_input_dim": X.shape[-1],
        "input_augmentation": aug, "device": str(device), "elapsed_seconds": time.time() - started,
        "output_file": str(out), "output_sha256": sha256(out), "status": "COMPLETE",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[A1 offline modern] complete {method} seed={seed} elapsed={time.time()-started:.1f}s")
    return out


def main() -> int:
    registry = list(csv.DictReader((TASK / "model_registry.csv").open("r", encoding="utf-8-sig", newline="")))
    dataset_file = ROOT / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
    data = load_modern_tcn_dataset(dataset_file=dataset_file)
    split = data["test"]
    if data["contract"].seq_len != 128 or data["contract"].input_dim != 22 or len(split.X) != 3602:
        raise RuntimeError(f"frozen dataset contract mismatch: {data['contract']} n={len(split.X)}")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    selected = [r for r in registry if r["method_id"] in {"modern_tcn_delta_bank_124", "modern_tcn_22d"} and r["status"] == "READY"]
    if len(selected) != 20:
        raise RuntimeError(f"expected 20 ready ModernTCN cases, got {len(selected)}")
    for row in selected:
        infer_case(row["method_id"], int(row["model_seed"]), Path(row["model_file"]), split, device)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
