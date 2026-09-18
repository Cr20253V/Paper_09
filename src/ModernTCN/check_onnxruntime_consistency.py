"""比较 PyTorch 参考输出和 ONNXRuntime 输出。

该脚本是三方一致性检查的第二步：
    1. PyTorch 输出：由 export_modern_tcn_onnx.py 保存到 MAT。
    2. ONNXRuntime 输出：本脚本读取同一 ONNX 和同一 X_sample。
    3. MATLAB 输出：由 ModernTCN_check_matlab_onnx.m 完成。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict

import numpy as np
from scipy.io import loadmat


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN ONNXRuntime 一致性检查")
    p.add_argument("--onnx-file", type=str, required=True)
    p.add_argument("--sample-file", type=str, required=True)
    p.add_argument("--max-abs-tol", type=float, default=1e-4)
    p.add_argument("--mean-abs-tol", type=float, default=1e-5)
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise SystemExit("缺少 onnxruntime。请先运行：python -m pip install onnx onnxruntime") from exc

    onnx_file = Path(args.onnx_file)
    sample_file = Path(args.sample_file)
    sample = loadmat(sample_file)
    X = sample["X_sample"].astype(np.float32)

    session = ort.InferenceSession(str(onnx_file), providers=["CPUExecutionProvider"])
    outputs = _run_onnx(session, X)
    refs = [sample["logits_main_pytorch"], sample["logits_turn_pytorch"], sample["theta_hat_pytorch"]]
    names = ["logits_main", "logits_turn", "theta_hat"]

    result = {
        "onnx_file": str(onnx_file),
        "sample_file": str(sample_file),
        "threshold": {"max_abs_error": args.max_abs_tol, "mean_abs_error": args.mean_abs_tol},
        "outputs": {},
    }
    passed = True
    for name, out, ref in zip(names, outputs, refs):
        diff = np.abs(np.asarray(out) - np.asarray(ref))
        max_abs = float(diff.max())
        mean_abs = float(diff.mean())
        ok = max_abs <= args.max_abs_tol and mean_abs <= args.mean_abs_tol
        passed = passed and ok
        result["outputs"][name] = {"max_abs_error": max_abs, "mean_abs_error": mean_abs, "pass": ok}
    result["pass"] = passed

    out_json = onnx_file.with_name(onnx_file.stem + "_onnxruntime_consistency.json")
    out_md = onnx_file.with_name(onnx_file.stem + "_onnxruntime_consistency.md")
    out_json.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    _write_md(out_md, result)
    print(f"[ModernTCN ONNXRuntime] pass={int(passed)}")
    print(f"  json: {out_json}")
    print(f"  report: {out_md}")
    return result


def _run_onnx(session, X: np.ndarray):
    """兼容固定 batch=1 的 ONNX 导出。

    第一阶段为了 MATLAB/Simulink 单窗口部署更稳，ONNX 输入固定为
    [1, 128, 19]。一致性检查使用 16 个测试窗口时，需要逐窗口推理后拼接。
    如果后续改为 dynamic batch，这里也能直接一次性推理。
    """

    input_shape = session.get_inputs()[0].shape
    batch_dim = input_shape[0]
    output_names = ["logits_main", "logits_turn", "theta_hat"]
    if isinstance(batch_dim, int) and batch_dim == 1 and X.shape[0] != 1:
        chunks = []
        for i in range(X.shape[0]):
            yi = session.run(output_names, {"input_window": X[i : i + 1]})
            chunks.append(yi)
        return [np.concatenate([c[j] for c in chunks], axis=0) for j in range(3)]
    return session.run(output_names, {"input_window": X})


def _write_md(path: Path, result: Dict[str, object]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN ONNXRuntime 一致性检查\n\n")
        f.write(f"- onnx: `{result['onnx_file']}`\n")
        f.write(f"- sample: `{result['sample_file']}`\n")
        f.write(f"- pass: `{int(result['pass'])}`\n\n")
        f.write("| output | max abs error | mean abs error | pass |\n")
        f.write("|---|---:|---:|---:|\n")
        for name, row in result["outputs"].items():
            f.write(f"| {name} | {row['max_abs_error']:.6g} | {row['mean_abs_error']:.6g} | {int(row['pass'])} |\n")


if __name__ == "__main__":
    main()
