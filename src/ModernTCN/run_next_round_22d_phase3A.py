"""Run Phase 3A seq256 small seed21 exploratory screening.

This runner is intentionally narrow:
- one small k31 seed21 run with the retained champion recipe;
- no ONNX export, MATLAB, Simulink, closed-loop, k51, or seed expansion;
- outputs stay under results/modern_tcn_next_round_22d/03_seq256_small_baseline.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


ROOT = Path(__file__).resolve().parents[2]
SRC_DIR = ROOT / "src" / "ModernTCN"
OUT_ROOT = ROOT / "results" / "modern_tcn_next_round_22d" / "03_seq256_small_baseline"
PHASE_DIR = OUT_ROOT / "phase3A_seed21"
RUN_TAG = "small_seq256_k31_champion_recipe_seed21"
RUN_DIR = PHASE_DIR / RUN_TAG

SEQ128_DATASET = (
    ROOT
    / "data"
    / "tcn"
    / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
)
SEQ256_DATASET = (
    ROOT
    / "data"
    / "tcn"
    / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5_seq256.mat"
)
SEQ256_AUDIT = ROOT / "results" / "modern_tcn_next_round_22d" / "02_seq256_dataset" / "seq256_builder_policy_audit.md"
SEQ256_VALIDATION = ROOT / "results" / "modern_tcn_next_round_22d" / "02_seq256_dataset" / "seq256_dataset_validation.md"
BASELINE_CKPT = (
    ROOT
    / "results"
    / "paper"
    / "agv_model_parameter_correction_workflow"
    / "08_models"
    / "modern_tcn"
    / "modern_tcn_v5_plantfix_turn_l020_tt25_tcm14_stw055_slrw060_seed101"
    / "modern_tcn_seed101.pt"
)
BASELINE_SUMMARY = BASELINE_CKPT.with_name("modern_tcn_seed101_summary.csv")
CHAMPION_DIR = BASELINE_CKPT.parent

WATCH_DIRS = [
    ROOT / "results" / "modern_tcn_ablation",
    CHAMPION_DIR,
    ROOT / "results" / "compare",
    ROOT / "src" / "ModernTCN" / "generated_layers",
]

RECIPE_KEYS = [
    "channels",
    "blocks",
    "kernel_size",
    "dropout",
    "temporal_padding",
    "lambda_turn",
    "lambda_theta",
    "lambda_theta_flat",
    "turn_transition_weight",
    "main_class_weight_method",
    "turn_class_weight_method",
    "main_class_multipliers",
    "turn_class_multipliers",
    "select_turn_weight",
    "select_turn_transition_weight",
    "select_turn_transition_target",
    "select_theta_weight",
    "theta_flat_loss_mode",
    "theta_flat_zero_tol_deg",
]

PHASE3_VALUES: Dict[str, object] = {
    "channels": 64,
    "blocks": 5,
    "kernel_size": 31,
    "dropout": 0.15,
    "temporal_padding": "same",
    "lambda_turn": 0.2,
    "lambda_theta": 0.55,
    "lambda_theta_flat": 0.12,
    "turn_transition_weight": 2.5,
    "main_class_weight_method": "sqrt_inverse",
    "turn_class_weight_method": "sqrt_inverse",
    "main_class_multipliers": [1.2, 1.0, 0.95],
    "turn_class_multipliers": [1.4, 0.8, 1.4],
    "select_turn_weight": 0.55,
    "select_turn_transition_weight": 1.2,
    "select_turn_transition_target": 0.82,
    "select_theta_weight": 0.3,
    "theta_flat_loss_mode": "near_zero",
    "theta_flat_zero_tol_deg": 0.3,
}

GATE_SPECS = [
    ("acc_main", ">=", -0.003),
    ("acc_turn", ">=", -0.005),
    ("acc_turn_transition", ">=", 0.0),
    ("theta_mae_deg", "<=", 0.010),
    ("flat_recall", ">=", -0.010),
    ("stall_recall", ">=", -0.050),
    ("slope_recall", ">=", -0.005),
    ("theta_edge_p95_abs_err", "<=", 0.050),
]

NEAR_HARD_FLOORS = [
    ("acc_main", ">=", -0.006),
    ("stall_recall", ">=", -0.070),
    ("slope_recall", ">=", -0.008),
    ("theta_mae_deg", "<=", 0.030),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ModernTCN next-round 22D Phase 3A runner")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--patience", type=int, default=25)
    parser.add_argument("--min-epochs", type=int, default=30)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--skip-train", action="store_true", help="Only summarize an existing run.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    ensure_phase_inputs()
    if RUN_DIR.exists() and any(RUN_DIR.iterdir()) and not args.skip_train:
        raise FileExistsError(
            f"Phase 3A run directory already exists and is non-empty: {RUN_DIR}. "
            "Refusing to overwrite."
        )
    PHASE_DIR.mkdir(parents=True, exist_ok=True)

    before = snapshot_watch_dirs()
    write_csv(PHASE_DIR / "phase3A_old_dir_snapshot_before.csv", before)
    preflight_rows = run_preflight(args)
    write_preflight_report(preflight_rows)
    recipe_rows = write_recipe_parity()
    if any(str(r["match"]) != "1" for r in recipe_rows):
        raise RuntimeError("Phase 3A recipe does not match retained champion recipe; see phase3A_recipe_parity.csv")

    if not args.skip_train:
        train_phase3a(args)

    summary_src = RUN_DIR / "modern_tcn_seed21_summary.csv"
    if not summary_src.exists():
        raise FileNotFoundError(f"Expected summary not found: {summary_src}")
    summary_dst = PHASE_DIR / "phase3A_seq256_small_seed21_summary.csv"
    shutil.copyfile(summary_src, summary_dst)
    baseline = read_single_csv(BASELINE_SUMMARY)
    candidate = read_single_csv(summary_dst)
    gate_rows, decision_payload = evaluate_gate(baseline, candidate)
    write_csv(PHASE_DIR / "phase3A_gate_matrix.csv", gate_rows)
    after = snapshot_watch_dirs()
    write_csv(PHASE_DIR / "phase3A_old_dir_snapshot_after.csv", after)
    isolation_rows = compare_snapshots(before, after)
    write_csv(PHASE_DIR / "phase3A_old_dir_snapshot_diff.csv", isolation_rows)

    isolation_ok = all(int(r["file_count_changed"]) == 0 and int(r["latest_mtime_changed"]) == 0 for r in isolation_rows)
    decision_payload["old_dir_isolation_ok"] = isolation_ok
    decision_payload["old_dir_snapshot_diff"] = rel(PHASE_DIR / "phase3A_old_dir_snapshot_diff.csv")
    if not isolation_ok:
        decision_payload["decision"] = "NO_PROMOTION"
        decision_payload["next_allowed_step"] = "STOP_FAILURE_OLD_DIR_CHANGED"
        write_failure_report(isolation_rows)

    (PHASE_DIR / "phase3A_decision.json").write_text(
        json.dumps(decision_payload, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    write_report(decision_payload, gate_rows, isolation_rows)
    run_git_generated_check()
    print(PHASE_DIR / "phase3A_report.md")


def ensure_phase_inputs() -> None:
    missing = [
        path
        for path in [SEQ128_DATASET, SEQ256_DATASET, SEQ256_AUDIT, SEQ256_VALIDATION, BASELINE_CKPT, BASELINE_SUMMARY]
        if not path.exists()
    ]
    if missing:
        raise FileNotFoundError("Missing required Phase 3A inputs: " + ", ".join(str(p) for p in missing))


def snapshot_watch_dirs() -> List[Dict[str, object]]:
    rows = []
    for path in WATCH_DIRS:
        exists = path.exists()
        file_count = 0
        total_bytes = 0
        latest_mtime = 0.0
        latest_file = ""
        if exists:
            if path.is_file():
                files = [path]
            else:
                files = [p for p in path.rglob("*") if p.is_file()]
            file_count = len(files)
            for file in files:
                try:
                    stat = file.stat()
                except OSError:
                    continue
                total_bytes += int(stat.st_size)
                if float(stat.st_mtime) > latest_mtime:
                    latest_mtime = float(stat.st_mtime)
                    latest_file = str(file)
        rows.append(
            {
                "path": str(path),
                "exists": int(exists),
                "file_count": int(file_count),
                "total_bytes": int(total_bytes),
                "latest_mtime_epoch": f"{latest_mtime:.6f}",
                "latest_mtime_local": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(latest_mtime))
                if latest_mtime
                else "",
                "latest_file": latest_file,
            }
        )
    return rows


def compare_snapshots(before: List[Dict[str, object]], after: List[Dict[str, object]]) -> List[Dict[str, object]]:
    rows = []
    before_by_path = {str(r["path"]): r for r in before}
    for a in after:
        path = str(a["path"])
        b = before_by_path[path]
        file_count_changed = int(a["file_count"]) != int(b["file_count"])
        latest_mtime_changed = str(a["latest_mtime_epoch"]) != str(b["latest_mtime_epoch"])
        rows.append(
            {
                "path": path,
                "before_file_count": b["file_count"],
                "after_file_count": a["file_count"],
                "file_count_changed": int(file_count_changed),
                "before_latest_mtime_epoch": b["latest_mtime_epoch"],
                "after_latest_mtime_epoch": a["latest_mtime_epoch"],
                "latest_mtime_changed": int(latest_mtime_changed),
                "before_latest_file": b["latest_file"],
                "after_latest_file": a["latest_file"],
            }
        )
    return rows


def run_preflight(args: argparse.Namespace) -> List[Dict[str, object]]:
    rows = []
    rows.append(
        run_command_check(
            "contract_negative_tests",
            [sys.executable, str(SRC_DIR / "test_modern_tcn_contracts.py")],
        )
    )
    common_recipe_args = training_recipe_args()
    rows.append(
        run_command_check(
            "seq128_dry_run",
            [
                sys.executable,
                str(SRC_DIR / "train_modern_tcn.py"),
                "--dry-run",
                "--dataset-file",
                str(SEQ128_DATASET),
                "--model-family",
                "small",
                "--seed",
                "21",
                "--device",
                args.device,
                "--limit-train",
                "4",
                "--limit-val",
                "4",
                "--limit-test",
                "4",
                *common_recipe_args,
            ],
        )
    )
    rows.append(
        run_command_check(
            "seq256_dry_run",
            [
                sys.executable,
                str(SRC_DIR / "train_modern_tcn.py"),
                "--dry-run",
                "--dataset-file",
                str(SEQ256_DATASET),
                "--model-family",
                "small",
                "--seed",
                "21",
                "--device",
                args.device,
                "--limit-train",
                "4",
                "--limit-val",
                "4",
                "--limit-test",
                "4",
                *common_recipe_args,
            ],
        )
    )
    return rows


def run_command_check(name: str, cmd: List[str]) -> Dict[str, object]:
    proc = subprocess.run(cmd, cwd=str(ROOT), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out_file = PHASE_DIR / f"{name}.txt"
    out_file.write_text(proc.stdout, encoding="utf-8")
    if proc.returncode != 0:
        raise RuntimeError(f"{name} failed with exit code {proc.returncode}. See {out_file}")
    return {
        "check": name,
        "pass": 1,
        "returncode": proc.returncode,
        "log_file": rel(out_file),
        "command": command_for_report(cmd),
    }


def write_preflight_report(rows: List[Dict[str, object]]) -> None:
    with (PHASE_DIR / "phase3A_preflight_report.md").open("w", encoding="utf-8") as f:
        f.write("# Phase 3A Preflight Report\n\n")
        f.write("- status: `PASS`\n")
        f.write("- seq128 baseline dry-run: `PASS`\n")
        f.write("- seq256 dry-run shape check: `PASS`\n")
        f.write("- contract negative tests: `PASS`\n")
        f.write("- ONNX/MATLAB/Simulink/closed-loop: `not executed`\n\n")
        f.write("| check | pass | log |\n|---|---:|---|\n")
        for row in rows:
            f.write(f"| `{row['check']}` | {row['pass']} | `{row['log_file']}` |\n")


def write_recipe_parity() -> List[Dict[str, object]]:
    baseline_recipe = load_baseline_recipe()
    rows = []
    for key in RECIPE_KEYS:
        baseline_value = baseline_recipe.get(key)
        phase3_value = PHASE3_VALUES[key]
        rows.append(
            {
                "parameter": key,
                "baseline_recipe_value": json.dumps(baseline_value, ensure_ascii=False),
                "phase3_value": json.dumps(phase3_value, ensure_ascii=False),
                "match": int(values_equal(baseline_value, phase3_value)),
            }
        )
    write_csv(PHASE_DIR / "phase3A_recipe_parity.csv", rows)
    return rows


def load_baseline_recipe() -> Dict[str, object]:
    import torch

    ckpt = torch.load(BASELINE_CKPT, map_location="cpu", weights_only=False)
    model_config = ckpt.get("model_config", {})
    return {key: model_config.get(key) for key in RECIPE_KEYS}


def values_equal(a: object, b: object) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(float(a), float(b), rel_tol=1e-8, abs_tol=1e-8)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)) and len(a) == len(b):
        return all(values_equal(x, y) for x, y in zip(list(a), list(b)))
    return a == b


def train_phase3a(args: argparse.Namespace) -> None:
    cmd = [
        sys.executable,
        str(SRC_DIR / "train_modern_tcn.py"),
        "--dataset-file",
        str(SEQ256_DATASET),
        "--output-root",
        str(PHASE_DIR),
        "--run-tag",
        RUN_TAG,
        "--no-overwrite",
        "--model-family",
        "small",
        "--seed",
        "21",
        "--epochs",
        str(args.epochs),
        "--batch-size",
        str(args.batch_size),
        "--patience",
        str(args.patience),
        "--min-epochs",
        str(args.min_epochs),
        "--device",
        args.device,
        "--num-workers",
        str(args.num_workers),
        *training_recipe_args(),
    ]
    log_file = PHASE_DIR / "phase3A_train_console.log"
    with log_file.open("w", encoding="utf-8") as log:
        proc = subprocess.run(cmd, cwd=str(ROOT), text=True, stdout=log, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise RuntimeError(f"Phase 3A training failed with exit code {proc.returncode}. See {log_file}")
    (PHASE_DIR / "phase3A_train_command.txt").write_text(command_for_report(cmd) + "\n", encoding="utf-8")


def training_recipe_args() -> List[str]:
    return [
        "--channels",
        "64",
        "--blocks",
        "5",
        "--kernel-size",
        "31",
        "--dropout",
        "0.15",
        "--temporal-padding",
        "same",
        "--lambda-turn",
        "0.2",
        "--lambda-theta",
        "0.55",
        "--lambda-theta-flat",
        "0.12",
        "--turn-transition-weight",
        "2.5",
        "--main-class-weight-method",
        "sqrt_inverse",
        "--turn-class-weight-method",
        "sqrt_inverse",
        "--main-class-multipliers",
        "1.2",
        "1.0",
        "0.95",
        "--turn-class-multipliers",
        "1.4",
        "0.8",
        "1.4",
        "--select-turn-weight",
        "0.55",
        "--select-turn-transition-weight",
        "1.2",
        "--select-turn-transition-target",
        "0.82",
        "--select-theta-weight",
        "0.3",
        "--theta-flat-loss-mode",
        "near_zero",
        "--theta-flat-zero-tol-deg",
        "0.3",
    ]


def evaluate_gate(baseline: Dict[str, str], candidate: Dict[str, str]) -> Tuple[List[Dict[str, object]], Dict[str, object]]:
    gate_rows = []
    failures = []
    for metric, op, delta in GATE_SPECS:
        base_value = metric_value(baseline, metric)
        cand_value = metric_value(candidate, metric)
        threshold = base_value + delta
        passed = cand_value >= threshold if op == ">=" else cand_value <= threshold
        if not passed:
            failures.append(metric)
        gate_rows.append(
            {
                "metric": metric,
                "op": op,
                "baseline": f"{base_value:.12g}",
                "delta": f"{delta:.12g}",
                "threshold": f"{threshold:.12g}",
                "candidate": f"{cand_value:.12g}",
                "passed": int(passed),
            }
        )

    hard_floor_failures = []
    for metric, op, delta in NEAR_HARD_FLOORS:
        base_value = metric_value(baseline, metric)
        cand_value = metric_value(candidate, metric)
        threshold = base_value + delta
        passed = cand_value >= threshold if op == ">=" else cand_value <= threshold
        if not passed:
            hard_floor_failures.append(metric)

    if not failures:
        decision = "PASS"
        next_allowed_step = "MATLAB parity + seeds 42/101 confirmatory plan"
    elif hard_floor_failures or len(failures) > 2:
        decision = "NO_PROMOTION"
        next_allowed_step = "STOP seq256 small; no seed expansion, no deployment"
    else:
        decision = "NEAR"
        next_allowed_step = "confirmatory / limited adjustment plan"

    payload = {
        "decision": decision,
        "dataset_status": "exploratory_python_builder",
        "matlab_parity_required_before_promotion": True,
        "seed21_screening_only": True,
        "not_replacement_for_seed101_champion": True,
        "next_allowed_step": next_allowed_step,
        "baseline_summary": str(BASELINE_SUMMARY),
        "candidate_summary": str(PHASE_DIR / "phase3A_seq256_small_seed21_summary.csv"),
        "seq256_builder_policy_audit": str(SEQ256_AUDIT),
        "full_gate_failures": failures,
        "near_hard_floor_failures": hard_floor_failures,
        "onnx_executed": False,
        "matlab_executed": False,
        "simulink_executed": False,
        "closed_loop_executed": False,
    }
    return gate_rows, payload


def write_failure_report(isolation_rows: List[Dict[str, object]]) -> None:
    with (PHASE_DIR / "failure_report.md").open("w", encoding="utf-8") as f:
        f.write("# Phase 3A Failure Report\n\n")
        f.write("- reason: watched legacy directories changed during Phase 3A.\n")
        f.write("- action: no promotion; inspect `phase3A_old_dir_snapshot_diff.csv`.\n\n")
        f.write("| path | file_count_changed | latest_mtime_changed |\n|---|---:|---:|\n")
        for row in isolation_rows:
            f.write(f"| `{row['path']}` | {row['file_count_changed']} | {row['latest_mtime_changed']} |\n")


def write_report(
    decision: Dict[str, object],
    gate_rows: List[Dict[str, object]],
    isolation_rows: List[Dict[str, object]],
) -> None:
    candidate = read_single_csv(PHASE_DIR / "phase3A_seq256_small_seed21_summary.csv")
    with (PHASE_DIR / "phase3A_report.md").open("w", encoding="utf-8") as f:
        f.write("# Phase 3A seq256 small seed21 Exploratory Screening\n\n")
        f.write("## Decision\n\n")
        f.write(f"- decision: `{decision['decision']}`\n")
        f.write(f"- next_allowed_step: `{decision['next_allowed_step']}`\n")
        f.write("- dataset_status: `exploratory_python_builder`\n")
        f.write("- matlab_parity_required_before_promotion: `true`\n")
        f.write("- seed21_screening_only: `true`\n")
        f.write("- not_replacement_for_seed101_champion: `true`\n")
        f.write("- ONNX/MATLAB/Simulink/closed-loop: `not executed`\n\n")
        f.write("## Scope Boundary\n\n")
        f.write("- This run uses seq256 data built by the Python builder and keeps the builder audit attached.\n")
        f.write("- The seq128 champion is seed101; this seed21 result is only a continue/stop screen.\n")
        f.write("- No k51, loss tuning, seed42/101 expansion, ONNX export, MATLAB, Simulink, or closed-loop was executed.\n\n")
        f.write("## Evidence\n\n")
        f.write(f"- preflight: `{rel(PHASE_DIR / 'phase3A_preflight_report.md')}`\n")
        f.write(f"- recipe parity: `{rel(PHASE_DIR / 'phase3A_recipe_parity.csv')}`\n")
        f.write(f"- train command: `{rel(PHASE_DIR / 'phase3A_train_command.txt')}`\n")
        f.write(f"- candidate summary: `{rel(PHASE_DIR / 'phase3A_seq256_small_seed21_summary.csv')}`\n")
        f.write(f"- gate matrix: `{rel(PHASE_DIR / 'phase3A_gate_matrix.csv')}`\n")
        f.write(f"- decision json: `{rel(PHASE_DIR / 'phase3A_decision.json')}`\n")
        f.write(f"- dataset audit: `{rel(SEQ256_AUDIT)}`\n\n")
        f.write("## Candidate Metrics\n\n")
        for key in [
            "acc_main",
            "acc_turn",
            "acc_turn_transition",
            "theta_mae_deg",
            "flat_recall",
            "stall_recall",
            "slope_recall",
            "theta_edge_p95_abs_err",
            "flat_peak_theta_error",
            "false_turn_straight",
        ]:
            f.write(f"- {key}: `{candidate.get(key, '')}`\n")
        f.write("\n## Gate Matrix\n\n")
        f.write("| metric | op | threshold | candidate | passed |\n|---|---|---:|---:|---:|\n")
        for row in gate_rows:
            f.write(
                f"| `{row['metric']}` | `{row['op']}` | {row['threshold']} | "
                f"{row['candidate']} | {row['passed']} |\n"
            )
        f.write("\n## Isolation Check\n\n")
        f.write("| path | file_count_changed | latest_mtime_changed |\n|---|---:|---:|\n")
        for row in isolation_rows:
            f.write(f"| `{row['path']}` | {row['file_count_changed']} | {row['latest_mtime_changed']} |\n")


def run_git_generated_check() -> None:
    patterns = [r"\.pt$", r"\.onnx$", r"\.mat$", r"\.log$", r"\.cache$"]
    proc = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    files = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    generated = [f for f in files if any(__import__("re").search(pat, f, __import__("re").IGNORECASE) for pat in patterns)]
    report = {
        "unignored_generated_artifacts": generated,
        "pass": len(generated) == 0,
    }
    (PHASE_DIR / "phase3A_git_generated_check.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def read_single_csv(path: Path) -> Dict[str, str]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise RuntimeError(f"Expected exactly one row in {path}, got {len(rows)}")
    return rows[0]


def to_float(row: Dict[str, str], key: str) -> float:
    try:
        return float(row.get(key, "nan"))
    except Exception:
        return float("nan")


def metric_value(row: Dict[str, str], key: str) -> float:
    value = to_float(row, key)
    if not math.isnan(value):
        return value
    if key == "theta_edge_p95_abs_err":
        return max(
            to_float(row, "theta_neg_10_8_p95_abs_err_deg"),
            to_float(row, "theta_pos_8_10_p95_abs_err_deg"),
        )
    return value


def write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    fieldnames: List[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve())).replace("\\", "/")
    except Exception:
        return str(path)


def command_for_report(cmd: List[str]) -> str:
    return " ".join(quote_arg(str(part)) for part in cmd)


def quote_arg(part: str) -> str:
    if not part:
        return '""'
    if any(ch.isspace() for ch in part):
        return '"' + part.replace('"', '\\"') + '"'
    return part


if __name__ == "__main__":
    main()
