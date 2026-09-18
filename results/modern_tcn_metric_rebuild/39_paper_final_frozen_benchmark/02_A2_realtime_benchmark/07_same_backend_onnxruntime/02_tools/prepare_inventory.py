from __future__ import annotations

import csv
import hashlib
import json
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import scipy
import torch

from a2ort_paths import (
    A1_REGISTRY,
    DATASET,
    EXPECTED_EXISTING_ONNX_SHA,
    EXPECTED_PARENT_SHA,
    MODERN_22D_ONNX,
    MODERN_DELTA_ONNX,
    ORT_ROOT,
    ROOT,
    ensure_output_dirs,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_seed42_rows() -> dict[str, dict[str, str]]:
    with A1_REGISTRY.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = [r for r in csv.DictReader(handle) if r["model_seed"] == "42"]
    result = {r["method_id"]: r for r in rows}
    missing = sorted(set(EXPECTED_PARENT_SHA) - set(result))
    if missing:
        raise RuntimeError(f"A1 registry is missing seed42 rows: {missing}")
    return result


def stable_rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def main() -> None:
    ensure_output_dirs()
    rows = read_seed42_rows()
    records: list[dict[str, object]] = []
    for method_id, expected in EXPECTED_PARENT_SHA.items():
        source = Path(rows[method_id]["model_file"])
        actual = sha256(source)
        if actual != expected or rows[method_id]["model_sha256"].lower() != expected:
            raise RuntimeError(f"Frozen parent SHA mismatch for {method_id}: {actual}")
        records.append(
            {
                "artifact_id": f"{method_id}__authority_model",
                "role": "A1_SEED42_AUTHORITY",
                "method_id": method_id,
                "path": str(source.resolve()),
                "relative_path": stable_rel(source),
                "sha256": actual,
                "bytes": source.stat().st_size,
                "parent_sha256": "",
                "status": "VERIFIED",
            }
        )

    for method_id, path in (
        ("modern_tcn_delta_bank_124", MODERN_DELTA_ONNX),
        ("modern_tcn_22d", MODERN_22D_ONNX),
    ):
        actual = sha256(path)
        if actual != EXPECTED_EXISTING_ONNX_SHA[method_id]:
            raise RuntimeError(f"Existing ModernTCN ONNX SHA mismatch for {method_id}: {actual}")
        records.append(
            {
                "artifact_id": f"{method_id}__existing_onnx",
                "role": "REUSED_DEPLOYMENT_DERIVATIVE",
                "method_id": method_id,
                "path": str(path.resolve()),
                "relative_path": stable_rel(path),
                "sha256": actual,
                "bytes": path.stat().st_size,
                "parent_sha256": EXPECTED_PARENT_SHA[method_id],
                "status": "VERIFIED",
            }
        )

    dataset_sha = sha256(DATASET)
    expected_dataset = "ab5dde32ef3627aa7032a3b4f7632c87cb471287a638f2b14a25a179a660196f"
    if dataset_sha != expected_dataset:
        raise RuntimeError(f"A0 dataset SHA mismatch: {dataset_sha}")
    records.append(
        {
            "artifact_id": "a0_dataset",
            "role": "FROZEN_DATASET",
            "method_id": "all",
            "path": str(DATASET.resolve()),
            "relative_path": stable_rel(DATASET),
            "sha256": dataset_sha,
            "bytes": DATASET.stat().st_size,
            "parent_sha256": "",
            "status": "VERIFIED",
        }
    )

    registry = ORT_ROOT / "01_inventory/input_artifact_registry.csv"
    with registry.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)

    environment = {
        "captured_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "python_executable": sys.executable,
        "python": platform.python_version(),
        "platform": platform.platform(),
        "numpy": np.__version__,
        "onnx": onnx.__version__,
        "onnxruntime": ort.__version__,
        "torch": torch.__version__,
        "scipy": scipy.__version__,
        "available_providers": ort.get_available_providers(),
        "required_provider": "CPUExecutionProvider",
    }
    if "CPUExecutionProvider" not in environment["available_providers"]:
        raise RuntimeError("ONNX Runtime CPUExecutionProvider is unavailable")
    (ORT_ROOT / "03_environment/preparation_environment.json").write_text(
        json.dumps(environment, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print("Frozen input inventory and Python environment verified.")


if __name__ == "__main__":
    main()

