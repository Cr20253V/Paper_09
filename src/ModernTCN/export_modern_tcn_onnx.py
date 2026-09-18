"""将训练好的 ModernTCN checkpoint 导出为 ONNX，并保存 PyTorch 参考输出。

导出前强制 `model.eval()`，固定输入形状 `[batch, 128, input_dim]`，不启用
dynamic axes。第一版默认 opset=17；如果 MATLAB 导入报算子不支持，再按
错误信息降级或替换模型算子。
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import warnings
from pathlib import Path

import numpy as np
import torch
from scipy.io import savemat

from modern_tcn_data import find_project_root, load_modern_tcn_dataset
from modern_tcn_lag_features import augment_split_by_metadata, normalize_input_augment
from modern_tcn_model import build_model_from_checkpoint_dict


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="导出 ModernTCN ONNX")
    p.add_argument("--checkpoint", type=str, required=True)
    p.add_argument("--onnx-file", type=str, default="")
    p.add_argument("--sample-file", type=str, default="")
    p.add_argument("--opset", type=int, default=17)
    p.add_argument("--sample-count", type=int, default=16)
    p.add_argument("--no-overwrite", "--no_overwrite", dest="no_overwrite", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if importlib.util.find_spec("onnx") is None:
        raise SystemExit("缺少 onnx。请先运行：python -m pip install onnx")
    if importlib.util.find_spec("onnxscript") is None:
        raise SystemExit("缺少 onnxscript。请先运行：python -m pip install onnxscript")
    root = find_project_root()
    checkpoint = Path(args.checkpoint)
    if not checkpoint.exists():
        raise FileNotFoundError(f"找不到 checkpoint：{checkpoint}")

    # checkpoint 内含普通 Python dict/list，显式关闭 weights_only 以兼容新版 PyTorch 默认策略。
    ckpt = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt)
    model.eval()
    input_augmentation = dict(ckpt.get("input_augmentation", {}) or {})
    if not input_augmentation:
        input_augmentation = {
            "input_augment": ckpt.get("input_augment", "none"),
            "delta_lag": ckpt.get("delta_lag", 1),
            "delta_pad": ckpt.get("delta_pad", "zero"),
            "raw_input_dim": ckpt.get("raw_input_dim", ckpt["model_config"]["input_dim"]),
            "augmented_input_dim": ckpt.get("augmented_input_dim", ckpt["model_config"]["input_dim"]),
            "raw_feature_contract": ckpt.get("raw_feature_contract", ckpt.get("contract", {}).get("feature_contract", "")),
        }
    input_augment = normalize_input_augment(input_augmentation.get("input_augment", "none"))
    delta_lag = int(input_augmentation.get("delta_lag", 1) or 1)
    delta_pad = str(input_augmentation.get("delta_pad", "zero") or "zero")

    out_dir = checkpoint.parent
    onnx_file = Path(args.onnx_file) if args.onnx_file else out_dir / checkpoint.name.replace(".pt", ".onnx")
    sample_file = Path(args.sample_file) if args.sample_file else out_dir / checkpoint.name.replace(".pt", "_pytorch_reference.mat")
    meta_file = onnx_file.with_name(onnx_file.stem + "_onnx_export.json")
    if args.no_overwrite:
        existing = [p for p in [onnx_file, sample_file, meta_file] if p.exists()]
        if existing:
            raise FileExistsError("--no-overwrite enabled and export outputs already exist: " + ", ".join(str(p) for p in existing))

    dummy = torch.zeros(1, ckpt["model_config"]["seq_len"], ckpt["model_config"]["input_dim"], dtype=torch.float32)
    with torch.no_grad():
        with warnings.catch_warnings():
            warnings.filterwarnings(
                "ignore",
                message="You are using the legacy TorchScript-based ONNX export.*",
                category=DeprecationWarning,
            )
            torch.onnx.export(
                model,
                dummy,
                onnx_file,
                export_params=True,
                opset_version=args.opset,
                do_constant_folding=True,
                input_names=["input_window"],
                output_names=["logits_main", "logits_turn", "theta_hat"],
                dynamo=False,
            )

    # 保存一组 test 窗口的 PyTorch 输出，供 ONNXRuntime 和 MATLAB 做三方一致性。
    data = load_modern_tcn_dataset(Path(ckpt["contract"]["dataset_file"]))
    raw_sample_split = data["test"]
    sample_split = raw_sample_split
    if input_augment != "none":
        sample_split = augment_split_by_metadata(sample_split, input_augmentation)
    X_raw_sample = raw_sample_split.X[: args.sample_count].astype(np.float32)
    X_sample = sample_split.X[: args.sample_count].astype(np.float32)
    with torch.no_grad():
        lm, lt, th = model(torch.from_numpy(X_sample).float())
    savemat(
        sample_file,
        {
            "X_sample": X_sample,
            "X_raw_sample": X_raw_sample,
            "logits_main_pytorch": lm.numpy().astype(np.float32),
            "logits_turn_pytorch": lt.numpy().astype(np.float32),
            "theta_hat_pytorch": th.numpy().astype(np.float32),
        },
    )

    meta = {
        "checkpoint": str(checkpoint),
        "model_family": str(ckpt.get("model_family", "small")),
        "onnx_file": str(onnx_file),
        "sample_file": str(sample_file),
        "opset": args.opset,
        "input_shape": [1, ckpt["model_config"]["seq_len"], ckpt["model_config"]["input_dim"]],
        "input_augment": input_augment,
        "raw_input_dim": int(input_augmentation.get("raw_input_dim", ckpt["model_config"]["input_dim"] // (2 if input_augment == "delta_lag" else 1))),
        "augmented_input_dim": int(input_augmentation.get("augmented_input_dim", ckpt["model_config"]["input_dim"])),
        "delta_lag": delta_lag if input_augment == "delta_lag" else 1,
        "delta_pad": delta_pad,
        "lag_steps": input_augmentation.get("lag_steps", []),
        "lag_pad": input_augmentation.get("lag_pad", "edge"),
        "delta_clip_abs": input_augmentation.get("delta_clip_abs", 5.0),
        "method": input_augmentation.get("method", ""),
        "normalization": input_augmentation.get("normalization", ""),
        "raw_feature_contract": str(input_augmentation.get("raw_feature_contract", "")),
        "output_names": ["logits_main", "logits_turn", "theta_hat"],
        "note": "导出前已调用 model.eval()；dropout 在 ONNX 推理中关闭；第一版固定 batch=1，离线批量检查脚本会逐窗口推理；当前默认使用 legacy TorchScript ONNX exporter 以获得更稳定的 PyTorch/ONNXRuntime 数值一致性。",
    }
    for key in (
        "raw_feature_names",
        "raw_feature_mean",
        "raw_feature_std",
        "physics_feature_names",
        "physics_feature_mean",
        "physics_feature_std",
        "physics_feature_std_floor",
        "physics_params",
        "physics_ema_taus",
        "physics_clip_abs",
        "source_feature_names",
        "forbidden_source_features",
        "fit_policy",
    ):
        if key in input_augmentation:
            meta[key] = input_augmentation[key]
    meta_file.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print("[ModernTCN ONNX] 导出完成")
    print(f"  onnx: {onnx_file}")
    print(f"  sample: {sample_file}")
    print(f"  meta: {meta_file}")


if __name__ == "__main__":
    main()
