from __future__ import annotations

import hashlib
import json
from pathlib import Path

import h5py
import numpy as np
import onnxruntime as ort
from scipy.io import loadmat

from a2ort_paths import (
    DATASET,
    GRU_FULL_ONNX,
    MODERN_22D_ONNX,
    MODERN_DELTA_ONNX,
    NATIVE_REFERENCE,
    ORT_ROOT,
    TCN_FULL_ONNX,
    VALIDATION,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def softmax(x: np.ndarray) -> np.ndarray:
    z = x - np.max(x, axis=1, keepdims=True)
    e = np.exp(z)
    return e / np.sum(e, axis=1, keepdims=True)


def session(path: Path) -> ort.InferenceSession:
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 1
    opts.inter_op_num_threads = 1
    opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(str(path), sess_options=opts, providers=["CPUExecutionProvider"])


def run_full(path: Path, inputs: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    sess = session(path)
    input_name = sess.get_inputs()[0].name
    main = np.empty((len(inputs), 3), np.float32)
    turn = np.empty((len(inputs), 3), np.float32)
    theta = np.empty((len(inputs), 1), np.float32)
    for i in range(len(inputs)):
        outputs = sess.run(None, {input_name: inputs[i : i + 1]})
        main[i], turn[i], theta[i] = outputs
    return main, turn, theta


def compare(method: str, path: Path, inputs: np.ndarray, ref: dict[str, np.ndarray]) -> dict[str, object]:
    logits_main, logits_turn, theta = run_full(path, inputs)
    main_prob = softmax(logits_main)
    turn_prob = softmax(logits_turn)
    ref_main = np.asarray(ref[f"{method}_main_prob"], dtype=np.float32)
    ref_turn = np.asarray(ref[f"{method}_turn_prob"], dtype=np.float32)
    ref_theta = np.asarray(ref[f"{method}_theta"], dtype=np.float32).reshape(-1, 1)
    metrics = {
        "method_id": f"{method}_22d",
        "onnx_file": str(path.resolve()),
        "onnx_sha256": sha256(path),
        "windows": int(len(inputs)),
        "main_probability_max_abs_error": float(np.max(np.abs(main_prob - ref_main))),
        "turn_probability_max_abs_error": float(np.max(np.abs(turn_prob - ref_turn))),
        "theta_max_abs_error_rad": float(np.max(np.abs(theta - ref_theta))),
        "main_label_agreement": float(np.mean(np.argmax(main_prob, axis=1) == np.argmax(ref_main, axis=1))),
        "turn_label_agreement": float(np.mean(np.argmax(turn_prob, axis=1) == np.argmax(ref_turn, axis=1))),
        "finite_outputs": bool(np.isfinite(logits_main).all() and np.isfinite(logits_turn).all() and np.isfinite(theta).all()),
    }
    metrics["pass"] = bool(
        metrics["main_probability_max_abs_error"] <= 1e-4
        and metrics["turn_probability_max_abs_error"] <= 1e-4
        and metrics["theta_max_abs_error_rad"] <= 1e-4
        and metrics["main_label_agreement"] == 1.0
        and metrics["turn_label_agreement"] == 1.0
        and metrics["finite_outputs"]
    )
    return metrics


def modern_sidecar(path: Path) -> Path:
    if "delta_bank_124" in str(path):
        return path.with_name(path.stem + "_onnxruntime_consistency.json")
    candidates = [
        path.with_name(path.stem + "_onnxruntime_consistency.json"),
        path.parent / "modern_tcn_seed42_onnxruntime_consistency.json",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"No consistency sidecar found for {path}")


def validate_modern(path: Path, inputs: np.ndarray, method: str) -> dict[str, object]:
    sidecar_path = modern_sidecar(path)
    sidecar = json.loads(sidecar_path.read_text(encoding="utf-8-sig"))
    logits_main, logits_turn, theta = run_full(path, inputs[: min(64, len(inputs))])
    finite = bool(np.isfinite(logits_main).all() and np.isfinite(logits_turn).all() and np.isfinite(theta).all())
    passed = bool(sidecar.get("pass", False) and finite)
    return {
        "method_id": method,
        "onnx_file": str(path.resolve()),
        "onnx_sha256": sha256(path),
        "existing_consistency_sidecar": str(sidecar_path.resolve()),
        "existing_consistency_pass": bool(sidecar.get("pass", False)),
        "additional_smoke_windows": min(64, len(inputs)),
        "finite_outputs": finite,
        "pass": passed,
    }


def delta_bank(x: np.ndarray) -> np.ndarray:
    outputs = [x]
    for lag in (1, 2, 4):
        prev = x.copy()
        prev[:, lag:, :] = x[:, :-lag, :]
        outputs.append(np.clip(x - prev, -5.0, 5.0))
    return np.ascontiguousarray(np.concatenate(outputs, axis=2), dtype=np.float32)


def main() -> None:
    reference = loadmat(NATIVE_REFERENCE, simplify_cells=True)
    with h5py.File(DATASET, "r") as handle:
        x = np.asarray(handle["dataset/X_test"], dtype=np.float32).transpose(2, 1, 0)
    x = np.ascontiguousarray(x)
    if x.shape != (3602, 128, 22):
        raise RuntimeError(f"Unexpected frozen test shape: {x.shape}")
    checks = [
        compare("tcn", TCN_FULL_ONNX, x, reference),
        compare("gru", GRU_FULL_ONNX, x, reference),
        validate_modern(MODERN_22D_ONNX, x, "modern_tcn_22d"),
        validate_modern(MODERN_DELTA_ONNX, delta_bank(x), "modern_tcn_delta_bank_124"),
    ]
    result = {"status": "PASS" if all(c["pass"] for c in checks) else "FAIL", "checks": checks}
    (VALIDATION / "equivalence_summary.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if result["status"] != "PASS":
        raise SystemExit(4)


if __name__ == "__main__":
    main()

