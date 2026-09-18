"""Benchmark single-window ONNXRuntime latency for ModernTCN ablations."""

from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path
from typing import Dict

import numpy as np


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN ONNXRuntime latency benchmark")
    p.add_argument("--onnx-file", type=Path, required=True)
    p.add_argument("--sample-file", type=Path, required=True)
    p.add_argument("--warmup", type=int, default=50)
    p.add_argument("--repeat", type=int, default=500)
    p.add_argument("--baseline-p95-ms", type=float, default=float("nan"))
    p.add_argument("--max-relative-p95", type=float, default=1.25)
    p.add_argument("--max-absolute-p95-ms", type=float, default=5.0)
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise SystemExit("缺少 onnxruntime。请先运行：python -m pip install onnxruntime") from exc
    from scipy.io import loadmat

    sample = loadmat(args.sample_file)
    x = sample["X_sample"][:1].astype(np.float32)
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = 1
    session = ort.InferenceSession(str(args.onnx_file), sess_options=sess_options, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output_names = [o.name for o in session.get_outputs()]
    for _ in range(max(args.warmup, 0)):
        session.run(output_names, {input_name: x})
    times_ms = []
    for _ in range(max(args.repeat, 1)):
        t0 = time.perf_counter()
        session.run(output_names, {input_name: x})
        times_ms.append((time.perf_counter() - t0) * 1000.0)
    arr = np.asarray(times_ms, dtype=np.float64)
    p95 = float(np.percentile(arr, 95))
    rel_ok = True
    if np.isfinite(args.baseline_p95_ms) and args.baseline_p95_ms > 0:
        rel_ok = p95 <= args.baseline_p95_ms * args.max_relative_p95
    abs_ok = p95 <= args.max_absolute_p95_ms
    result = {
        "onnx_file": str(args.onnx_file),
        "sample_file": str(args.sample_file),
        "warmup": args.warmup,
        "repeat": args.repeat,
        "mean_ms": float(arr.mean()),
        "p50_ms": float(np.percentile(arr, 50)),
        "p95_ms": p95,
        "p99_ms": float(np.percentile(arr, 99)),
        "max_ms": float(arr.max()),
        "baseline_p95_ms": args.baseline_p95_ms,
        "max_relative_p95": args.max_relative_p95,
        "max_absolute_p95_ms": args.max_absolute_p95_ms,
        "pass": bool(rel_ok and abs_ok),
    }
    out_csv = args.onnx_file.with_name("onnxruntime_latency_summary.csv")
    out_md = args.onnx_file.with_name("onnxruntime_latency_report.md")
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(result.keys()))
        writer.writeheader()
        writer.writerow(result)
    with out_md.open("w", encoding="utf-8") as f:
        f.write("# ONNXRuntime Latency Report\n\n")
        f.write(f"- onnx: `{args.onnx_file}`\n")
        f.write(f"- repeat: `{args.repeat}`\n")
        f.write(f"- p95_ms: `{p95:.6g}`\n")
        f.write(f"- max_absolute_p95_ms: `{args.max_absolute_p95_ms:.6g}`\n")
        f.write(f"- baseline_p95_ms: `{args.baseline_p95_ms}`\n")
        f.write(f"- pass: `{int(result['pass'])}`\n")
    print(json.dumps(result, indent=2))
    if not result["pass"]:
        raise SystemExit("ONNXRuntime latency gate failed.")
    return result


if __name__ == "__main__":
    main()
