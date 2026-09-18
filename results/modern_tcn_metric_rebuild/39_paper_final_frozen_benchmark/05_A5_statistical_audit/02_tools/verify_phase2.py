#!/usr/bin/env python3
"""Final read-back verification and artifact-manifest refresh for A5 phase 2."""

from __future__ import annotations

import csv
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
A5 = HERE.parent
P2 = A5 / "04_phase2"
NOW = datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_csv(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_json(path: Path, data) -> None:
    assert path.resolve().is_relative_to(A5.resolve())
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    checks = []
    required = [
        "normalized_offline_cases.csv", "normalized_closed_loop_cases.csv", "protocol_blockers.csv",
        "method_summary.csv", "per_path_summary.csv", "per_seed_summary.csv", "paired_effects.csv",
        "bootstrap_ci.csv", "contrast_decisions.csv", "worst_cases.csv", "failure_gate_cases.csv",
        "failure_gate_summary.csv", "runtime_summary.csv", "grid_audit.csv",
        "input_protocol_audit_cases.csv", "input_model_registry.csv", "runtime_source_registry.csv",
        "source_ci_crosscheck.csv", "phase2_summary.json", "A5_experiment_report.md",
    ]
    missing = [name for name in required if not (P2 / name).is_file()]
    checks.append({"check": "required_outputs", "passed": not missing, "detail": missing or f"{len(required)}/{len(required)}"})

    analysis_sha = sha(A5 / "00_protocol_lock/analysis_plan.json")
    checks.append({"check": "analysis_plan_immutable", "passed": analysis_sha == "f6f5d85197268cd202748ae50805ad9b6cefe75c451ba5652e82c47f80baf4a9", "detail": analysis_sha})
    grids = read_csv(P2 / "grid_audit.csv")
    checks.append({"check": "all_expected_grids_complete", "passed": all(r["status"] == "PASS" for r in grids), "detail": {r["grid_id"]: f"{r['observed_count']}/{r['expected_count']}" for r in grids}})
    inputs = read_csv(P2 / "input_protocol_audit_cases.csv")
    checks.append({"check": "all_input_hash_audits_pass", "passed": all(r["sha256_match"] == "True" for r in inputs), "detail": f"{sum(r['sha256_match']=='True' for r in inputs)}/{len(inputs)}"})
    cross = read_csv(P2 / "source_ci_crosscheck.csv")
    max_delta = max(float(r["max_abs_delta"]) for r in cross)
    unique_ci = len({(r["contrast_id"], r["metric"]) for r in cross})
    checks.append({"check": "source_ci_reproduction", "passed": len(cross) == 38 and unique_ci == 34 and all(r["status"] == "PASS" for r in cross), "detail": {"source_rows_checked": len(cross), "unique_a5_pairs": unique_ci, "max_abs_delta": max_delta, "tolerance": 1e-12}})
    blockers = read_csv(P2 / "protocol_blockers.csv")
    decision = json.loads((A5 / "decision.json").read_text(encoding="utf-8-sig"))
    checks.append({"check": "partial_status_has_explicit_blockers", "passed": decision["status"] == "PARTIAL" and len(blockers) > 0 and all(r["severity"] == "BLOCKING_CONTRAST" for r in blockers), "detail": {"status": decision["status"], "blocker_count": len(blockers)}})
    norm_off = read_csv(P2 / "normalized_offline_cases.csv")
    norm_cl = read_csv(P2 / "normalized_closed_loop_cases.csv")
    checks.append({"check": "normalized_long_table_counts", "passed": len(norm_off) == 520 and len(norm_cl) == 5544, "detail": {"offline": len(norm_off), "closed_loop": len(norm_cl)}})

    proc = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(HERE), "-p", "test_*.py", "-v"], capture_output=True, text=True)
    checks.append({"check": "unit_tests", "passed": proc.returncode == 0 and "Ran 8 tests" in proc.stderr + proc.stdout, "detail": (proc.stderr + proc.stdout).strip()})
    status = "PASS" if all(c["passed"] for c in checks) else "FAIL"
    report = {"task_id": "A5", "phase": 2, "verified_at": NOW, "status": status, "checks": checks, "artifact_manifest_self_excluded": True}
    verification = P2 / "verification_report.json"
    write_json(verification, report)

    receipt_path = A5 / "receipt.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8-sig"))
    receipt["verification"] = str(verification)
    receipt["verification_sha256"] = sha(verification)
    receipt["verification_status"] = status
    write_json(receipt_path, receipt)
    (A5 / "logs/phase2_verification.log").write_text(f"[{NOW}] status={status}; checks={len(checks)}; max_ci_delta={max_delta}\n", encoding="utf-8")

    manifest = []
    for path in sorted(A5.rglob("*")):
        if path.is_file() and path.name != "artifact_manifest.json":
            manifest.append({"relative_path": str(path.relative_to(A5)).replace("\\", "/"), "bytes": path.stat().st_size, "sha256": sha(path)})
    write_json(A5 / "artifact_manifest.json", manifest)
    print(json.dumps({"status": status, "checks": len(checks), "artifacts": len(manifest), "max_ci_delta": max_delta}, indent=2))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
