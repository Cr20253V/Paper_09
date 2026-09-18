#!/usr/bin/env python3
"""Resume A1 inventory/offline aggregation after the frozen TCN job exits.

This watcher never runs formal closed-loop cases.  It writes only below the
Node39/A1 task root and leaves the task at READY_FOR_MANUAL_CLOSED_LOOP when
all 40 offline cases have been validated.
"""

from __future__ import annotations

import json
import ctypes
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def project_root() -> Path:
    for p in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (p / "init_project.m").is_file():
            return p
    raise RuntimeError("project root not found")


ROOT = project_root()
TASK = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison"
TOOLS = TASK / "01_tools"
LOG = TASK / "logs/post_training_continuation.log"
RECEIPT = TASK / "02_models/tcn_training_receipt.json"
PID_FILE = TASK / "logs/train_missing_tcn.pid"
MATLAB = Path(r"D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe")


def append(message: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"[{now()}] {message}\n")


def process_alive(pid: int) -> bool:
    if os.name == "nt":
        process_query_limited_information = 0x1000
        handle = ctypes.windll.kernel32.OpenProcess(process_query_limited_information, False, pid)
        if not handle:
            return False
        ctypes.windll.kernel32.CloseHandle(handle)
        return True
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def run(label: str, args: list[str], acceptable: set[int] = {0}) -> int:
    append(f"START {label}: {args}")
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, encoding="utf-8", errors="replace")
    append(f"END {label}: exit={result.returncode}")
    if result.stdout:
        append(f"STDOUT {label}:\n{result.stdout.rstrip()}")
    if result.stderr:
        append(f"STDERR {label}:\n{result.stderr.rstrip()}")
    if result.returncode not in acceptable:
        raise RuntimeError(f"{label} failed with exit {result.returncode}")
    return result.returncode


def training_complete() -> bool:
    if not RECEIPT.is_file():
        return False
    try:
        return bool(json.loads(RECEIPT.read_text(encoding="utf-8"))["complete"])
    except Exception:
        return False


def main() -> int:
    pid = int(PID_FILE.read_text(encoding="utf-8").strip())
    append(f"watching frozen TCN training pid={pid}")
    while process_alive(pid):
        time.sleep(60)
    if not training_complete():
        append("TRAINING_FAILED_OR_INCOMPLETE; no downstream evaluation started")
        return 2

    run("refresh_inventory", [sys.executable, str(TOOLS / "build_a1_inventory.py")])
    batch = (
        "addpath(fullfile(pwd,'results','modern_tcn_metric_rebuild',"
        "'39_paper_final_frozen_benchmark','01_A1_algorithm_comparison','01_tools')); "
        "run_A1_offline_matlab;"
    )
    run("offline_matlab", [str(MATLAB), "-batch", batch])
    run("finalize_offline", [sys.executable, str(TOOLS / "finalize_A1_offline.py")])
    # Exit 4 is the expected provisional state while 120 manual cases remain.
    run("finalize_provisional", [sys.executable, str(TOOLS / "finalize_A1.py")], {0, 4})
    append("POST_TRAINING_CONTINUATION_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
