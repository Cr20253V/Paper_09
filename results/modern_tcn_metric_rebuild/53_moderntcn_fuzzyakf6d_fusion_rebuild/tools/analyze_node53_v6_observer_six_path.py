from __future__ import annotations

import csv
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

from node53_common import NODE, ROOT, rel, sha256, write_csv, write_json


CASE_ROOT = NODE / "08_formal_six_path_exploratory_v6/cases/V6/seed42"
OUTPUT = NODE / "09_statistics/v6_observer_vs_moderntcn_six_path"
METRIC_START_S = 0.5
DECISIVE_TOLERANCE_DEG = 0.10
SLOPE_THRESHOLD_DEG = 1.3
PATHS = [
    ("p01_factory_logistics_showcase", "P1 Factory logistics"),
    ("p02_sharp_turn_transition", "P2 Sharp-turn transition"),
    ("p03_long_updown", "P3 Long up/down"),
    ("p04_soft_updown_straight_turn", "P4 Mild slope-turn coupling"),
    ("p05_factory_flat_logistics", "P5 Flat factory logistics"),
    ("p06_downhill_after_turn", "P6 Downhill recovery"),
]


def longest_run_seconds(mask: np.ndarray, dt: float) -> float:
    longest = current = 0
    for value in mask.astype(bool):
        if value:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return float(longest * dt)


def finite_float(value: float) -> float | None:
    value = float(value)
    return value if math.isfinite(value) else None


def subset_metrics(frame: pd.DataFrame, mask: np.ndarray, prefix: str) -> dict[str, object]:
    part = frame.loc[mask]
    if part.empty:
        return {f"{prefix}_sample_count": 0}
    eo = part["abs_error_r2_deg"].to_numpy(float)
    em = part["abs_error_mtcn_deg"].to_numpy(float)
    delta = eo - em
    return {
        f"{prefix}_sample_count": int(len(part)),
        f"{prefix}_r2_mae_deg": finite_float(np.mean(eo)),
        f"{prefix}_mtcn_mae_deg": finite_float(np.mean(em)),
        f"{prefix}_r2_to_mtcn_mae_ratio": finite_float(np.mean(eo) / np.mean(em)) if np.mean(em) > 0 else None,
        f"{prefix}_r2_lower_abs_error_fraction": finite_float(np.mean(delta < 0)),
        f"{prefix}_r2_decisive_win_fraction": finite_float(np.mean(delta < -DECISIVE_TOLERANCE_DEG)),
        f"{prefix}_mtcn_decisive_win_fraction": finite_float(np.mean(delta > DECISIVE_TOLERANCE_DEG)),
        f"{prefix}_near_tie_fraction": finite_float(np.mean(np.abs(delta) <= DECISIVE_TOLERANCE_DEG)),
    }


def analyze_case(path_id: str, path_name: str) -> tuple[dict[str, object], list[dict[str, object]]]:
    case = CASE_ROOT / path_id
    trace_path = case / "trace.csv"
    debug_path = case / "node53_v6_runtime_debug.csv"
    manifest_path = case / "case_manifest.json"
    trace = pd.read_csv(trace_path, usecols=["t_s", "theta_true"])
    debug = pd.read_csv(
        debug_path,
        usecols=["step", "theta_tcn", "theta_fuzzyakf", "observer_valid"],
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    expected_steps = np.arange(1, len(debug) + 1)
    actual_steps = debug["step"].to_numpy(int)
    if len(trace) != len(debug) + 1 or not np.array_equal(actual_steps, expected_steps):
        raise RuntimeError(f"Trace/debug alignment failed for {path_id}")
    if not np.all(debug["observer_valid"].to_numpy(bool)):
        raise RuntimeError(f"Observer validity failed for {path_id}")

    t = trace["t_s"].to_numpy(float)[1:]
    truth = np.rad2deg(trace["theta_true"].to_numpy(float)[1:])
    mtcn = np.rad2deg(debug["theta_tcn"].to_numpy(float))
    r2 = np.rad2deg(debug["theta_fuzzyakf"].to_numpy(float))
    frame = pd.DataFrame(
        {
            "t_s": t,
            "theta_true_deg": truth,
            "theta_mtcn_deg": mtcn,
            "theta_r2_deg": r2,
            "abs_error_mtcn_deg": np.abs(mtcn - truth),
            "abs_error_r2_deg": np.abs(r2 - truth),
        }
    )
    frame["delta_abs_error_deg"] = frame["abs_error_r2_deg"] - frame["abs_error_mtcn_deg"]
    evaluated = frame["t_s"].to_numpy(float) >= METRIC_START_S
    frame = frame.loc[evaluated].reset_index(drop=True)
    delta = frame["delta_abs_error_deg"].to_numpy(float)
    eo = frame["abs_error_r2_deg"].to_numpy(float)
    em = frame["abs_error_mtcn_deg"].to_numpy(float)
    dt = float(np.median(np.diff(frame["t_s"].to_numpy(float))))
    r2_mae = float(np.mean(eo))
    mtcn_mae = float(np.mean(em))
    oracle_mae = float(np.mean(np.minimum(eo, em)))
    flat = np.abs(frame["theta_true_deg"].to_numpy(float)) < SLOPE_THRESHOLD_DEG
    slope = ~flat

    row: dict[str, object] = {
        "path_id": path_id,
        "path_name": path_name,
        "model_seed": int(manifest["model_seed"]),
        "sensor_seed": int(manifest["sensor_seed"]),
        "evaluation_start_s": METRIC_START_S,
        "evaluation_end_s": float(frame["t_s"].iloc[-1]),
        "evaluation_samples": int(len(frame)),
        "r2_mae_deg": r2_mae,
        "mtcn_mae_deg": mtcn_mae,
        "r2_minus_mtcn_mae_deg": r2_mae - mtcn_mae,
        "r2_to_mtcn_mae_ratio": r2_mae / mtcn_mae if mtcn_mae > 0 else None,
        "mae_winner": "R2_06" if r2_mae < mtcn_mae else ("ModernTCN-delta" if mtcn_mae < r2_mae else "tie"),
        "r2_rmse_deg": float(np.sqrt(np.mean(eo**2))),
        "mtcn_rmse_deg": float(np.sqrt(np.mean(em**2))),
        "r2_lower_abs_error_fraction": float(np.mean(delta < 0)),
        "mtcn_lower_abs_error_fraction": float(np.mean(delta > 0)),
        "exact_tie_fraction": float(np.mean(delta == 0)),
        "r2_decisive_win_fraction": float(np.mean(delta < -DECISIVE_TOLERANCE_DEG)),
        "mtcn_decisive_win_fraction": float(np.mean(delta > DECISIVE_TOLERANCE_DEG)),
        "near_tie_fraction": float(np.mean(np.abs(delta) <= DECISIVE_TOLERANCE_DEG)),
        "mean_local_advantage_for_r2_deg": float(np.mean(em - eo)),
        "median_local_advantage_for_r2_deg": float(np.median(em - eo)),
        "r2_decisive_longest_run_s": longest_run_seconds(delta < -DECISIVE_TOLERANCE_DEG, dt),
        "mtcn_decisive_longest_run_s": longest_run_seconds(delta > DECISIVE_TOLERANCE_DEG, dt),
        "samplewise_oracle_mae_deg": oracle_mae,
        "oracle_gain_over_best_individual_fraction": 1.0 - oracle_mae / min(r2_mae, mtcn_mae) if min(r2_mae, mtcn_mae) > 0 else None,
        "trace_sha256": sha256(trace_path),
        "debug_sha256": sha256(debug_path),
        "manifest_sha256": sha256(manifest_path),
    }
    row.update(subset_metrics(frame, flat, "flat"))
    row.update(subset_metrics(frame, slope, "slope"))

    bins = [-np.inf, -1.0, -0.5, -0.1, 0.1, 0.5, 1.0, np.inf]
    labels = ["r2_better_ge_1", "r2_better_0p5_to_1", "r2_better_0p1_to_0p5", "near_tie", "mtcn_better_0p1_to_0p5", "mtcn_better_0p5_to_1", "mtcn_better_ge_1"]
    indices = np.digitize(delta, bins[1:-1], right=False)
    distribution = [
        {
            "path_id": path_id,
            "bin": label,
            "sample_count": int(np.sum(indices == index)),
            "sample_fraction": float(np.mean(indices == index)),
        }
        for index, label in enumerate(labels)
    ]
    return row, distribution


def main() -> int:
    rows: list[dict[str, object]] = []
    distributions: list[dict[str, object]] = []
    for path_id, path_name in PATHS:
        row, distribution = analyze_case(path_id, path_name)
        rows.append(row)
        distributions.extend(distribution)

    write_csv(OUTPUT / "observer_vs_moderntcn_by_path.csv", rows)
    write_csv(OUTPUT / "local_advantage_distribution.csv", distributions)
    r2_mae_wins = sum(row["mae_winner"] == "R2_06" for row in rows)
    r2_area_majority = sum(float(row["r2_lower_abs_error_fraction"]) > 0.5 for row in rows)
    pooled: dict[str, dict[str, object]] = {}
    for scope in ("all", "flat", "slope"):
        count_key = "evaluation_samples" if scope == "all" else f"{scope}_sample_count"
        prefix = "" if scope == "all" else f"{scope}_"
        sample_count = sum(int(row.get(count_key, 0) or 0) for row in rows)
        values: dict[str, object] = {"sample_count": sample_count}
        for metric in (
            "r2_mae_deg",
            "mtcn_mae_deg",
            "r2_lower_abs_error_fraction",
            "r2_decisive_win_fraction",
            "mtcn_decisive_win_fraction",
            "near_tie_fraction",
        ):
            key = prefix + metric
            pairs = [
                (float(row[key]), int(row.get(count_key, 0) or 0))
                for row in rows
                if row.get(key) is not None and int(row.get(count_key, 0) or 0) > 0
            ]
            values[metric] = sum(value * weight for value, weight in pairs) / sum(weight for _, weight in pairs)
        pooled[scope] = values
    summary = {
        "status": "COMPLETE_NODE53_V6_OBSERVER_SIX_PATH_ANALYSIS",
        "classification": "EXPLORATORY_NONQUALIFIED_R2_06_FUSION_REBUILD",
        "comparison": "raw R2_06_FuzzyAKF6D versus raw ModernTCN-delta from the same six Node53 closed-loop cases",
        "metric_start_s": METRIC_START_S,
        "decisive_tolerance_deg": DECISIVE_TOLERANCE_DEG,
        "slope_threshold_deg": SLOPE_THRESHOLD_DEG,
        "path_count": len(rows),
        "r2_mae_win_path_count": r2_mae_wins,
        "r2_lower_abs_error_majority_path_count": r2_area_majority,
        "sample_weighted_summary": pooled,
        "all_observer_samples_valid": True,
        "model_seed": 42,
        "sensor_seed": 4631,
        "qualification_status_unchanged": "STOP_NODE53_V6_QUALIFICATION_FAILED",
        "formal_claim_allowed": False,
        "rows": rows,
    }
    write_json(OUTPUT / "observer_vs_moderntcn_summary.json", summary)

    report = [
        "# Node53 V6 六路径原始观测器对比",
        "",
        "口径与 Fig06 一致：0.5 s 后评估，delta=|e_R2_06|-|e_ModernTCN|，delta<-0.10 deg 记为 R2_06 明确胜出。",
        "",
        "|路径|R2_06 MAE (deg)|ModernTCN MAE (deg)|MAE胜者|R2_06逐样本更好|R2_06明确胜出|ModernTCN明确胜出|近似持平|",
        "|---|---:|---:|---|---:|---:|---:|---:|",
    ]
    for row in rows:
        report.append(
            f"|{row['path_name']}|{row['r2_mae_deg']:.6f}|{row['mtcn_mae_deg']:.6f}|{row['mae_winner']}|"
            f"{100*row['r2_lower_abs_error_fraction']:.2f}%|{100*row['r2_decisive_win_fraction']:.2f}%|"
            f"{100*row['mtcn_decisive_win_fraction']:.2f}%|{100*row['near_tie_fraction']:.2f}%|"
        )
    report.extend(
        [
            "",
            f"R2_06 在 {r2_mae_wins}/6 条路径取得更低整体 MAE，在 {r2_area_majority}/6 条路径中逐样本胜出占比超过 50%。",
            "",
            f"按全部样本汇总：R2_06/ModernTCN MAE = {pooled['all']['r2_mae_deg']:.6f}/{pooled['all']['mtcn_mae_deg']:.6f} deg。",
            f"坡地样本汇总：R2_06/ModernTCN MAE = {pooled['slope']['r2_mae_deg']:.6f}/{pooled['slope']['mtcn_mae_deg']:.6f} deg。",
            f"平地样本汇总：R2_06/ModernTCN MAE = {pooled['flat']['r2_mae_deg']:.6f}/{pooled['flat']['mtcn_mae_deg']:.6f} deg。",
            "",
            "本结果是固定 model seed 42、sensor seed 4631 的探索性闭环描述，不改变既有 qualification 失败状态。",
        ]
    )
    report_path = OUTPUT / "analysis_report_zh.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
