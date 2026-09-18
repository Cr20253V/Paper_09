from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from a2ort_paths import EXPECTED_PARENT_SHA, ORT_ROOT


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def percentile(values: np.ndarray, q: float) -> float:
    return float(np.percentile(values, q, method="linear"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    environment_file = args.run_dir / "environment.json"
    environment = json.loads(environment_file.read_text(encoding="utf-8-sig"))
    environment_sha = environment.get("environment_sha256", "")
    if len(environment_sha) != 64:
        raise RuntimeError("Missing stable environment SHA256")
    expected_methods = {
        "modern_tcn_22d",
        "gru_22d",
        "tcn_22d",
        "modern_tcn_delta_bank_124",
    }
    case_files = sorted((args.run_dir / "cases").glob("*.json"))
    if len(case_files) != 4:
        raise RuntimeError(f"Expected four case files, found {len(case_files)}")
    child_receipt_files = sorted((args.run_dir / "child_receipts").glob("*.json"))
    if len(child_receipt_files) != 4:
        raise RuntimeError(f"Expected four atomic child receipts, found {len(child_receipt_files)}")
    rows = []
    checks = []
    for case_file in case_files:
        case = json.loads(case_file.read_text(encoding="utf-8-sig"))
        if case.get("method_id") not in expected_methods:
            raise RuntimeError(f"Unexpected method in {case_file}: {case.get('method_id')}")
        if case.get("authority_model_sha256") != EXPECTED_PARENT_SHA[case["method_id"]]:
            raise RuntimeError(f"Authority SHA mismatch in {case_file}")
        model_path = Path(case["model_file"])
        if sha256(model_path) != case.get("model_sha256"):
            raise RuntimeError(f"Runtime model SHA mismatch in {case_file}")
        if case.get("environment_sha256") != environment_sha:
            raise RuntimeError(f"Environment SHA mismatch in {case_file}")
        if not case.get("formal") or case.get("batch") != 1 or case.get("warmup_count") != 500 or case.get("formal_count") != 10000:
            raise RuntimeError(f"Formal protocol mismatch in {case_file}")
        if case.get("provider") != "CPUExecutionProvider" or case.get("intra_op_num_threads") != 1 or case.get("inter_op_num_threads") != 1:
            raise RuntimeError(f"Backend/thread protocol mismatch in {case_file}")
        raw_path_resolved = Path(case["raw_timing_file"]).resolve()
        if args.run_dir.resolve() not in raw_path_resolved.parents:
            raise RuntimeError(f"Raw timing path escaped run directory: {raw_path_resolved}")
        raw_file = Path(case["raw_timing_file"])
        receipt_file = Path(case.get("child_receipt_file", ""))
        if not receipt_file.is_file() or args.run_dir.resolve() not in receipt_file.resolve().parents:
            raise RuntimeError(f"Missing or escaped atomic child receipt for {case_file}")
        child_receipt = json.loads(receipt_file.read_text(encoding="utf-8-sig"))
        if (
            child_receipt.get("status") != "CHILD_COMPLETE"
            or child_receipt.get("completion_protocol") != "atomic_child_receipt_v1"
            or child_receipt.get("method_id") != case["method_id"]
            or child_receipt.get("case_id") != case["case_id"]
            or not child_receipt.get("formal")
            or child_receipt.get("warmup_count") != 500
            or child_receipt.get("formal_count") != 10000
            or child_receipt.get("raw_rows") != 10000
            or child_receipt.get("environment_sha256") != environment_sha
            or child_receipt.get("model_sha256") != case.get("model_sha256")
            or child_receipt.get("authority_model_sha256") != case.get("authority_model_sha256")
            or child_receipt.get("case_sha256_before_monitor_augmentation")
            != case.get("child_case_sha256_before_monitor_augmentation")
            or Path(child_receipt.get("raw_timing_file", "")).resolve() != raw_file.resolve()
            or Path(child_receipt.get("case_file", "")).resolve() != case_file.resolve()
        ):
            raise RuntimeError(f"Atomic child receipt validation failed for {case_file}")
        if sha256(raw_file) != child_receipt.get("raw_timing_sha256"):
            raise RuntimeError(f"Atomic child receipt raw SHA mismatch for {case_file}")
        with raw_file.open("r", encoding="utf-8", newline="") as handle:
            raw = list(csv.DictReader(handle))
        values = np.array([float(r["latency_ms"]) for r in raw], dtype=np.float64)
        iterations = np.array([int(r["iteration"]) for r in raw], dtype=np.int64)
        input_indices = np.array([int(r["input_index"]) for r in raw], dtype=np.int64)
        recomputed = {
            "p50_ms": percentile(values, 50),
            "p95_ms": percentile(values, 95),
            "p99_ms": percentile(values, 99),
            "max_ms": float(np.max(values)),
            "over_10ms_rate": float(np.mean(values > 10.0)),
        }
        expected_indices = 1 + (np.arange(10000, dtype=np.int64) % 3602)
        memory_file = Path(case.get("raw_memory_file", ""))
        memory_rows = 0
        memory_pids: set[int] = set()
        memory_roles: set[str] = set()
        memory_peak_working_set = 0
        memory_peak_private = 0
        if memory_file.is_file():
            with memory_file.open("r", encoding="utf-8-sig", newline="") as handle:
                memory_data = list(csv.DictReader(handle))
            memory_rows = len(memory_data)
            memory_pids = {int(row["pid"]) for row in memory_data}
            memory_roles = {row.get("process_role", "") for row in memory_data}
            memory_peak_working_set = max((int(row["working_set_bytes"]) for row in memory_data), default=0)
            memory_peak_private = max((int(row["private_bytes"]) for row in memory_data), default=0)
        passed = (
            len(values) == 10000
            and np.isfinite(values).all()
            and np.all(values >= 0)
            and np.array_equal(iterations, np.arange(1, 10001))
            and np.array_equal(input_indices, expected_indices)
            and memory_rows > 0
            and memory_pids == {int(child_receipt["child_pid"])}
            and memory_roles == {"benchmark_python"}
            and int(case.get("external_memory_pid", -1)) == int(child_receipt["child_pid"])
            and case.get("external_memory_pid_matches_child_receipt") is True
            and int(case.get("external_peak_working_set_bytes", 0)) == memory_peak_working_set > 0
            and int(case.get("external_peak_private_bytes", 0)) == memory_peak_private > 0
        )
        for key, value in recomputed.items():
            passed = passed and abs(value - float(case[key])) <= 1e-9
        checks.append({"case_id": case["case_id"], "raw_rows": len(values), "memory_rows": memory_rows, "pass": bool(passed), **recomputed})
        rows.append(
            {
                "case_id": case["case_id"],
                "comparison_group": case["comparison_group"],
                "parameter_count": case["parameter_count"],
                "model_file_bytes": case["model_file_bytes"],
                **recomputed,
                "over_10ms_count": int(np.sum(values > 10.0)),
                "meets_p95_10ms": recomputed["p95_ms"] <= 10.0,
                "meets_p99_10ms": recomputed["p99_ms"] <= 10.0,
                "zero_overrun": bool(np.sum(values > 10.0) == 0),
            }
        )
    if not all(c["pass"] for c in checks):
        raise RuntimeError("Raw timing validation failed")
    if {case_file.stem.removeprefix("core_inference__") for case_file in case_files} != expected_methods:
        raise RuntimeError("Formal method set mismatch")
    if {receipt_file.stem.removeprefix("core_inference__") for receipt_file in child_receipt_files} != expected_methods:
        raise RuntimeError("Atomic child-receipt method set mismatch")
    with (args.run_dir / "runtime_summary.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    receipt = {
        "status": "FORMAL_RUN_COMPLETE",
        "validated_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "case_count": 4,
        "raw_timing_rows": 40000,
        "checks": checks,
        "interpretation_note": "22D rows support architecture-only comparison; delta-bank is representation plus architecture.",
    }
    (args.run_dir / "validation_receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    (args.run_dir / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    (args.run_dir / "task_status.json").write_text(
        json.dumps({"status": "FORMAL_RUN_COMPLETE", "updated_at": receipt["validated_at"]}, indent=2), encoding="utf-8"
    )
    run_manifest = {
        "run_id": args.run_dir.name,
        "status": "FORMAL_RUN_COMPLETE",
        "case_ids": [r["case_id"] for r in rows],
        "warmup_per_case": 500,
        "formal_per_case": 10000,
        "raw_timing_rows": 40000,
        "environment_file": str((args.run_dir / "environment.json").resolve()),
    }
    (args.run_dir / "run_manifest.json").write_text(json.dumps(run_manifest, indent=2), encoding="utf-8")
    artifacts = []
    for path in sorted(args.run_dir.rglob("*")):
        if path.is_file() and path.name != "artifact_manifest.json":
            artifacts.append({
                "relative_path": path.relative_to(args.run_dir).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            })
    (args.run_dir / "artifact_manifest.json").write_text(json.dumps(artifacts, indent=2), encoding="utf-8")

    # A successful future run must also finalize the root-level handoff. This
    # prevents a valid timestamped run from leaving a stale pre-run decision.
    summary_dir = ORT_ROOT / "06_summary"
    summary_dir.mkdir(parents=True, exist_ok=True)
    root_rows = [{**row, "source_run": args.run_dir.name} for row in rows]
    with (summary_dir / "runtime_summary.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(root_rows[0]))
        writer.writeheader()
        writer.writerows(root_rows)
    root_decision = {
        "status": "FORMAL_RUN_COMPLETE",
        "finalized_at": receipt["validated_at"],
        "latest_completed_run": args.run_dir.name,
        "equivalence_gate": "PASS",
        "formal_case_count": 4,
        "formal_raw_timing_rows": 40000,
        "latency_validation": "PASS",
        "performance_claim_allowed": True,
        "all_methods_meet_p95_10ms": all(row["meets_p95_10ms"] for row in rows),
        "all_methods_meet_p99_10ms": all(row["meets_p99_10ms"] for row in rows),
        "memory_monitor": "PASS_ACTUAL_CHILD_PID_MATCHED_AT_EVERY_CASE",
        "interpretation_guard": "Use 22D rows for architecture-only latency; delta-bank is representation plus architecture; disclose frozen TCN/GRU CBT semantics.",
    }
    (summary_dir / "decision.json").write_text(json.dumps(root_decision, indent=2), encoding="utf-8")
    root_manifest = {
        "protocol_id": "A2_SUPPLEMENT_UNIFIED_ORT_SEED42_V1",
        "status": "FORMAL_RUN_COMPLETE",
        "formal_run_count": 1,
        "latest_completed_run": args.run_dir.name,
        "formal_case_count": 4,
        "formal_raw_timing_rows": 40000,
        "environment_sha256": environment_sha,
        "success_authority": "atomic_child_receipt_plus_artifact_validation",
        "root_summary_finalized": True,
    }
    (ORT_ROOT / "run_manifest.json").write_text(json.dumps(root_manifest, indent=2), encoding="utf-8")
    print("FORMAL_RUN_COMPLETE")


if __name__ == "__main__":
    main()
