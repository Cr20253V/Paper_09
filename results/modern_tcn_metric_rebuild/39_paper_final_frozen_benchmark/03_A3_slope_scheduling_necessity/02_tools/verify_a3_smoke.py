#!/usr/bin/env python3
"""Verify the latest successful A3 smoke traces and deterministic IMU replay."""
from __future__ import annotations
import csv, json
from pathlib import Path

ROOT = Path(r"E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\03_A3_slope_scheduling_necessity")


def latest_trace(case: str) -> Path:
    files = sorted((ROOT / "03_cases" / "_smoke" / case).glob("attempt_*/trace.csv"))
    if not files:
        raise FileNotFoundError(case)
    return files[-1]


def column(path: Path, name: str) -> list[float]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return [float(r[name]) for r in csv.DictReader(f)]


def main() -> None:
    a = latest_trace("IMU_LPV_MPC__p03_long_updown__imu_a")
    b = latest_trace("IMU_LPV_MPC__p03_long_updown__imu_b")
    xa, xb = column(a, "theta_imu_raw"), column(b, "theta_imu_raw")
    n = min(len(xa), len(xb))
    d = max((abs(xa[i] - xb[i]) for i in range(n)), default=float("nan"))
    out = {
        "task_id": "A3", "status": "PASS_DETERMINISTIC" if len(xa) == len(xb) and d <= 1e-12 else "FAIL_NONDETERMINISTIC",
        "trace_a": str(a), "trace_b": str(b), "samples_a": len(xa), "samples_b": len(xb),
        "max_abs_theta_imu_difference_rad": d, "tolerance_rad": 1e-12,
    }
    dest = ROOT / "00_protocol_lock" / "imu_determinism_check.json"
    dest.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False))
    if not out["status"].startswith("PASS"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
