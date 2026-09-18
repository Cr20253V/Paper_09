"""Benchmark ModernTCN single-window ONNXRuntime inference latency.

The benchmark intentionally uses batch size 1 and input shape [1, 128, 19],
matching the online closed-loop deployment path.  It writes raw timings and a
small summary under results/compare/realtime_benchmark by default.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import statistics
import sys
import time
from pathlib import Path
from typing import Dict, List

import h5py
import numpy as np


def parse_args() -> argparse.Namespace:
    root = find_project_root()
    default_out = root / "results" / "compare" / "realtime_benchmark"
    default_onnx = (
        root
        / "results"
        / "modern_tcn"
        / "modern_tcn_theta10_uniform_h0_v2_seed21"
        / "modern_tcn_seed21.onnx"
    )
    default_dataset = (
        root
        / "data"
        / "tcn"
        / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat"
    )

    p = argparse.ArgumentParser(description="ModernTCN ONNXRuntime latency benchmark")
    p.add_argument("--onnx-file", type=Path, default=default_onnx)
    p.add_argument("--dataset-file", type=Path, default=default_dataset)
    p.add_argument("--out-dir", type=Path, default=default_out)
    p.add_argument("--sample-count", type=int, default=512)
    p.add_argument("--warmup", type=int, default=200)
    p.add_argument("--repeat", type=int, default=5000)
    p.add_argument("--provider", type=str, default="CPUExecutionProvider")
    p.add_argument("--intra-op-num-threads", type=int, default=1)
    return p.parse_args()


def find_project_root(start: Path | None = None) -> Path:
    if start is None:
        start = Path(__file__).resolve()
    for p in (start, *start.parents):
        if (p / "init_project.m").exists() and (p / "data" / "tcn").exists():
            return p
    cwd = Path.cwd().resolve()
    for p in (cwd, *cwd.parents):
        if (p / "init_project.m").exists() and (p / "data" / "tcn").exists():
            return p
    raise FileNotFoundError("Could not locate project root.")


def read_test_windows(dataset_file: Path, sample_count: int) -> np.ndarray:
    if not dataset_file.exists():
        raise FileNotFoundError(f"Dataset not found: {dataset_file}")
    with h5py.File(dataset_file, "r") as f:
        ds = f["dataset"]["X_test"]
        if ds.ndim != 3:
            raise ValueError(f"Expected dataset.X_test to be 3-D, got shape={ds.shape}")
        n_total = int(ds.shape[2])
        n = min(max(1, int(sample_count)), n_total)
        indices = np.linspace(0, n_total - 1, n, dtype=np.int64)
        raw = np.asarray(ds[:, :, indices], dtype=np.float32)
    # MATLAB v7.3 stores this as [feature, time, window].  ONNX expects
    # [batch, time, feature].
    return np.transpose(raw, (2, 1, 0)).copy()


def make_session(onnx_file: Path, provider: str, intra_op_num_threads: int):
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise SystemExit("onnxruntime is not installed in the active Python.") from exc

    if not onnx_file.exists():
        raise FileNotFoundError(f"ONNX file not found: {onnx_file}")

    opts = ort.SessionOptions()
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    if intra_op_num_threads > 0:
        opts.intra_op_num_threads = int(intra_op_num_threads)
    session = ort.InferenceSession(str(onnx_file), sess_options=opts, providers=[provider])
    return session, ort


def run_benchmark(session, windows: np.ndarray, warmup: int, repeat: int) -> Dict[str, object]:
    input_name = session.get_inputs()[0].name
    output_names = [o.name for o in session.get_outputs()]
    n = int(windows.shape[0])

    for i in range(int(warmup)):
        x = windows[i % n : i % n + 1]
        session.run(output_names, {input_name: x})

    elapsed_ms: List[float] = []
    sample_idx: List[int] = []
    for i in range(int(repeat)):
        j = i % n
        x = windows[j : j + 1]
        t0 = time.perf_counter_ns()
        session.run(output_names, {input_name: x})
        t1 = time.perf_counter_ns()
        elapsed_ms.append((t1 - t0) / 1e6)
        sample_idx.append(j)

    arr = np.asarray(elapsed_ms, dtype=np.float64)
    return {
        "input_name": input_name,
        "output_names": output_names,
        "sample_idx": sample_idx,
        "elapsed_ms": elapsed_ms,
        "summary": {
            "n": int(arr.size),
            "mean_ms": float(arr.mean()),
            "std_ms": float(arr.std(ddof=0)),
            "min_ms": float(arr.min()),
            "p50_ms": float(np.percentile(arr, 50)),
            "p95_ms": float(np.percentile(arr, 95)),
            "p99_ms": float(np.percentile(arr, 99)),
            "max_ms": float(arr.max()),
        },
    }


def write_outputs(args: argparse.Namespace, ort, windows: np.ndarray, result: Dict[str, object]) -> None:
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    raw_file = out_dir / "realtime_onnx_runtime_raw.csv"
    summary_file = out_dir / "realtime_onnx_runtime_summary.csv"
    metadata_file = out_dir / "realtime_onnx_runtime_metadata.json"
    report_file = out_dir / "realtime_onnx_runtime_report.md"

    elapsed = result["elapsed_ms"]
    sample_idx = result["sample_idx"]
    with raw_file.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["iteration", "sample_index", "elapsed_ms"])
        for i, (j, ms) in enumerate(zip(sample_idx, elapsed), start=1):
            w.writerow([i, j, f"{ms:.9g}"])

    s = result["summary"]
    row = {
        "metric": "onnxruntime_single_window",
        "n": s["n"],
        "mean_ms": s["mean_ms"],
        "std_ms": s["std_ms"],
        "min_ms": s["min_ms"],
        "p50_ms": s["p50_ms"],
        "p95_ms": s["p95_ms"],
        "p99_ms": s["p99_ms"],
        "max_ms": s["max_ms"],
        "batch_size": 1,
        "sample_count": int(windows.shape[0]),
        "warmup": int(args.warmup),
        "repeat": int(args.repeat),
        "provider": args.provider,
        "intra_op_num_threads": int(args.intra_op_num_threads),
        "onnx_file": str(args.onnx_file),
        "dataset_file": str(args.dataset_file),
    }
    with summary_file.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(row.keys()))
        w.writeheader()
        w.writerow(row)

    metadata = {
        "python": sys.version,
        "python_executable": sys.executable,
        "platform": platform.platform(),
        "processor": platform.processor(),
        "cpu_count": os.cpu_count(),
        "onnxruntime_version": ort.__version__,
        "numpy_version": np.__version__,
        "input_name": result["input_name"],
        "output_names": result["output_names"],
        "windows_shape": list(windows.shape),
    }
    metadata_file.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    with report_file.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN ONNXRuntime Latency Benchmark\n\n")
        f.write(f"- onnx: `{args.onnx_file}`\n")
        f.write(f"- dataset: `{args.dataset_file}`\n")
        f.write(f"- provider: `{args.provider}`\n")
        f.write(f"- batch size: `1`\n")
        f.write(f"- warmup: `{args.warmup}`\n")
        f.write(f"- repeat: `{args.repeat}`\n\n")
        f.write("| metric | value (ms) |\n")
        f.write("|---|---:|\n")
        for key in ["mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"]:
            f.write(f"| {key} | {s[key]:.6g} |\n")

    print(f"[onnx benchmark] summary: {summary_file}")
    print(f"[onnx benchmark] report:  {report_file}")


def main() -> None:
    args = parse_args()
    windows = read_test_windows(args.dataset_file, args.sample_count)
    session, ort = make_session(args.onnx_file, args.provider, args.intra_op_num_threads)
    result = run_benchmark(session, windows, args.warmup, args.repeat)
    write_outputs(args, ort, windows, result)


if __name__ == "__main__":
    main()
