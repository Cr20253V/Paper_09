from __future__ import annotations

import argparse
import csv
import ctypes
import hashlib
import json
import os
import platform
import sys
import time
from ctypes import wintypes
from datetime import datetime, timezone
from pathlib import Path

import h5py
import numpy as np
import onnxruntime as ort

from a2ort_paths import (
    A1_REGISTRY,
    DATASET,
    EXPECTED_PARENT_SHA,
    GRU_FULL_ONNX,
    MODERN_22D_ONNX,
    MODERN_DELTA_ONNX,
    PARAM_COUNTS,
    TCN_FULL_ONNX,
)


MODEL_PATHS = {
    "modern_tcn_22d": MODERN_22D_ONNX,
    "gru_22d": GRU_FULL_ONNX,
    "tcn_22d": TCN_FULL_ONNX,
    "modern_tcn_delta_bank_124": MODERN_DELTA_ONNX,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_write_text(path: Path, text: str) -> None:
    """Publish a complete file atomically; a success receipt is written last."""
    path.parent.mkdir(parents=True, exist_ok=True)
    # Keep the temporary basename deliberately short. This experiment lives in
    # a deep Windows path and appending to the final basename can exceed MAX_PATH.
    temporary = path.parent / f".a{os.getpid():x}.tmp"
    if temporary.exists():
        temporary.unlink()
    try:
        temporary.write_text(text, encoding="utf-8")
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def authority_model(method: str) -> tuple[Path, str]:
    with A1_REGISTRY.open("r", encoding="utf-8-sig", newline="") as handle:
        matches = [r for r in csv.DictReader(handle) if r["method_id"] == method and r["model_seed"] == "42"]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one A1 seed42 authority row for {method}")
    path = Path(matches[0]["model_file"])
    actual = sha256(path)
    if actual != EXPECTED_PARENT_SHA[method] or matches[0]["model_sha256"].lower() != actual:
        raise RuntimeError(f"Authority-model SHA mismatch for {method}")
    return path, actual


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD),
        ("PageFaultCount", wintypes.DWORD),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


def process_memory() -> dict[str, int]:
    counters = PROCESS_MEMORY_COUNTERS_EX()
    counters.cb = ctypes.sizeof(counters)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
    psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
    handle = kernel32.GetCurrentProcess()
    ok = psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb)
    if not ok:
        raise ctypes.WinError()
    return {
        "working_set_bytes": int(counters.WorkingSetSize),
        "peak_working_set_bytes": int(counters.PeakWorkingSetSize),
        "private_bytes": int(counters.PrivateUsage),
        "peak_pagefile_bytes": int(counters.PeakPagefileUsage),
    }


def load_inputs(method: str) -> np.ndarray:
    with h5py.File(DATASET, "r") as handle:
        x = np.asarray(handle["dataset/X_test"], dtype=np.float32).transpose(2, 1, 0)
    x = np.ascontiguousarray(x)
    if method != "modern_tcn_delta_bank_124":
        return x
    outputs = [x]
    for lag in (1, 2, 4):
        prev = x.copy()
        prev[:, lag:, :] = x[:, :-lag, :]
        outputs.append(np.clip(x - prev, -5.0, 5.0))
    return np.ascontiguousarray(np.concatenate(outputs, axis=2), dtype=np.float32)


def percentile(values: np.ndarray, q: float) -> float:
    return float(np.percentile(values, q, method="linear"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--method", choices=MODEL_PATHS, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--formal", action="store_true")
    args = parser.parse_args()
    if args.formal and not os.environ.get("A2_ORT_EXCLUSIVE_TOKEN"):
        raise RuntimeError("Formal timing must be launched by invoke_ort_benchmark.ps1")

    warmup = 500 if args.formal else 5
    repeats = 10000 if args.formal else 20
    model_path = MODEL_PATHS[args.method]
    authority_path, authority_sha = authority_model(args.method)
    inputs = load_inputs(args.method)
    expected_shape = (3602, 128, 88 if args.method == "modern_tcn_delta_bank_124" else 22)
    if inputs.shape != expected_shape or inputs.dtype != np.float32 or not inputs.flags.c_contiguous:
        raise RuntimeError(f"Input contract violation: {inputs.shape}, {inputs.dtype}, C={inputs.flags.c_contiguous}")

    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 1
    opts.inter_op_num_threads = 1
    opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    before_session = process_memory()
    sess = ort.InferenceSession(str(model_path), sess_options=opts, providers=["CPUExecutionProvider"])
    if sess.get_providers()[0] != "CPUExecutionProvider":
        raise RuntimeError(f"Unexpected execution provider: {sess.get_providers()}")
    input_name = sess.get_inputs()[0].name
    before_timing = process_memory()

    for i in range(warmup):
        sess.run(None, {input_name: inputs[i % len(inputs) : i % len(inputs) + 1]})

    latency_ns = np.empty(repeats, dtype=np.int64)
    input_index = np.empty(repeats, dtype=np.int32)
    for i in range(repeats):
        idx = i % len(inputs)
        sample = inputs[idx : idx + 1]
        start = time.perf_counter_ns()
        outputs = sess.run(None, {input_name: sample})
        latency_ns[i] = time.perf_counter_ns() - start
        input_index[i] = idx + 1
        if any(not np.isfinite(out).all() for out in outputs):
            raise RuntimeError(f"Non-finite output at iteration {i + 1}")
    after_timing = process_memory()
    latency_ms = latency_ns.astype(np.float64) / 1e6

    raw_dir = args.run_dir / "raw_timing"
    case_dir = args.run_dir / "cases"
    raw_dir.mkdir(parents=True, exist_ok=True)
    case_dir.mkdir(parents=True, exist_ok=True)
    raw_file = raw_dir / f"core_inference__{args.method}.csv"
    if raw_file.exists():
        raise FileExistsError(f"Refusing to overwrite raw timing: {raw_file}")
    raw_temporary = raw_file.parent / f".r{os.getpid():x}.tmp"
    if raw_temporary.exists():
        raw_temporary.unlink()
    with raw_temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["iteration", "input_index", "latency_ns", "latency_ms", "over_10ms"])
        writer.writerows(
            (i + 1, int(input_index[i]), int(latency_ns[i]), f"{latency_ms[i]:.9f}", bool(latency_ms[i] > 10.0))
            for i in range(repeats)
        )
    os.replace(raw_temporary, raw_file)

    result = {
        "case_id": f"core_inference__{args.method}",
        "method_id": args.method,
        "comparison_group": "representation_plus_architecture" if args.method == "modern_tcn_delta_bank_124" else "architecture_only",
        "case_status": "COMPLETE",
        "formal": bool(args.formal),
        "batch": 1,
        "warmup_count": warmup,
        "formal_count": repeats,
        "input_shape": [1, 128, inputs.shape[2]],
        "input_dtype": "float32",
        "input_contiguous": "C",
        "model_file": str(model_path.resolve()),
        "model_sha256": sha256(model_path),
        "model_file_bytes": model_path.stat().st_size,
        "parameter_count": PARAM_COUNTS[args.method],
        "authority_model_file": str(authority_path.resolve()),
        "authority_model_sha256": authority_sha,
        "dataset_file": str(DATASET.resolve()),
        "dataset_sha256": sha256(DATASET),
        "runtime": "onnxruntime",
        "runtime_version": ort.__version__,
        "provider": "CPUExecutionProvider",
        "intra_op_num_threads": 1,
        "inter_op_num_threads": 1,
        "execution_mode": "ORT_SEQUENTIAL",
        "graph_optimization_level": "ORT_ENABLE_ALL",
        "timer": "time.perf_counter_ns",
        "data_movement_protocol": "preloaded C-contiguous numpy slice passed to InferenceSession.run; outputs allocated and returned",
        "p50_ms": percentile(latency_ms, 50),
        "p95_ms": percentile(latency_ms, 95),
        "p99_ms": percentile(latency_ms, 99),
        "max_ms": float(np.max(latency_ms)),
        "over_10ms_count": int(np.sum(latency_ms > 10.0)),
        "over_10ms_rate": float(np.mean(latency_ms > 10.0)),
        "memory_before_session": before_session,
        "memory_before_timing": before_timing,
        "memory_after_timing": after_timing,
        "peak_working_set_delta_from_before_session_bytes": after_timing["peak_working_set_bytes"] - before_session["peak_working_set_bytes"],
        "session_load_working_set_delta_bytes": before_timing["working_set_bytes"] - before_session["working_set_bytes"],
        "memory_scope_note": "process lifetime peak includes Python, preloaded inputs, and session; session-load delta is reported separately",
        "raw_timing_file": str(raw_file.resolve()),
        "python": platform.python_version(),
        "python_executable": sys.executable,
    }
    environment_file = args.run_dir / "environment.json"
    if environment_file.is_file():
        result["environment_sha256"] = json.loads(environment_file.read_text(encoding="utf-8-sig")).get("environment_sha256", "")
    case_file = case_dir / f"core_inference__{args.method}.json"
    if case_file.exists():
        raise FileExistsError(f"Refusing to overwrite case result: {case_file}")
    atomic_write_text(case_file, json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.stdout.flush()

    # This is the authoritative child-completion signal. It is published only
    # after raw timings and case metadata are complete and stdout is flushed.
    receipt_file = args.run_dir / "child_receipts" / f"core_inference__{args.method}.json"
    if receipt_file.exists():
        raise FileExistsError(f"Refusing to overwrite child receipt: {receipt_file}")
    receipt = {
        "status": "CHILD_COMPLETE",
        "case_id": result["case_id"],
        "method_id": args.method,
        "child_pid": os.getpid(),
        "completed_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "formal": bool(args.formal),
        "warmup_count": warmup,
        "formal_count": repeats,
        "raw_rows": repeats,
        "raw_timing_file": str(raw_file.resolve()),
        "raw_timing_sha256": sha256(raw_file),
        "case_file": str(case_file.resolve()),
        "case_sha256_before_monitor_augmentation": sha256(case_file),
        "model_sha256": result["model_sha256"],
        "authority_model_sha256": authority_sha,
        "environment_sha256": result.get("environment_sha256", ""),
        "completion_protocol": "atomic_child_receipt_v1",
    }
    atomic_write_text(receipt_file, json.dumps(receipt, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
