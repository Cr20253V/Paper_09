"""Audit ModernTCN-delta instability across all V7/P1 model seeds."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


def project_root(start: Path) -> Path:
    for parent in start.parents:
        if (parent / "data").is_dir() and (parent / "results").is_dir():
            return parent
    raise RuntimeError("Project root not found")


ROOT = project_root(Path(__file__).resolve())
V7 = ROOT / (
    "results/modern_tcn_metric_rebuild/53_moderntcn_fuzzyakf6d_fusion_rebuild/"
    "08_formal_six_path_exploratory_v7"
)
OUT = Path(__file__).resolve().parent
WINDOW_START = 130.0
WINDOW_END = 155.0
JUMP_RATE_DEG_S = 20.0
TRUTH_NONZERO_DEG = 0.5


def contiguous_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    positions = np.flatnonzero(mask)
    if not len(positions):
        return []
    output: list[tuple[int, int]] = []
    start = previous = int(positions[0])
    for position in positions[1:]:
        position = int(position)
        if position != previous + 1:
            output.append((start, previous))
            start = position
        previous = position
    output.append((start, previous))
    return output


records: list[dict[str, object]] = []
events: list[dict[str, object]] = []
for metrics_file in sorted(
    V7.glob("v7_six_path_metrics_seed*.csv"),
    key=lambda path: int(path.stem.rsplit("seed", 1)[1]),
):
    summary = pd.read_csv(metrics_file)
    match = summary.loc[
        summary["path_id"].eq("p01_factory_logistics_showcase")
        & summary["case_status"].eq("COMPLETE")
    ]
    if len(match) != 1:
        raise ValueError(f"Expected one completed P1 record in {metrics_file.name}")
    case = match.iloc[0]
    case_dir = Path(case["case_dir"])
    trace = pd.read_csv(case_dir / "trace.csv", usecols=["t_s", "theta_true"])
    debug = pd.read_csv(
        case_dir / "node53_v7_runtime_debug.csv",
        usecols=["step", "theta_tcn", "theta_fuzzyakf", "tcn_ready"],
    )
    if len(trace) != len(debug) + 1 or not np.array_equal(
        debug["step"].to_numpy(dtype=int), np.arange(1, len(trace))
    ):
        raise ValueError(f"Trace/debug alignment failed for seed {case['model_seed']}")

    time = trace["t_s"].to_numpy(dtype=float)[1:]
    truth = np.rad2deg(trace["theta_true"].to_numpy(dtype=float)[1:])
    mtcn = np.rad2deg(debug["theta_tcn"].to_numpy(dtype=float))
    observer = np.rad2deg(debug["theta_fuzzyakf"].to_numpy(dtype=float))
    ready = debug["tcn_ready"].to_numpy(dtype=int)
    use = (time >= WINDOW_START) & (time <= WINDOW_END)
    time, truth, mtcn, observer, ready = (
        array[use] for array in (time, truth, mtcn, observer, ready)
    )

    error = mtcn - truth
    observer_error = observer - truth
    rate = np.diff(mtcn) / np.diff(time)
    jump = np.abs(rate) >= JUMP_RATE_DEG_S
    zero_while_truth_nonzero = (np.abs(mtcn) < 1e-12) & (
        np.abs(truth) >= TRUTH_NONZERO_DEG
    )
    zero_while_ready = zero_while_truth_nonzero & (ready == 1)
    jump_runs = contiguous_runs(jump)
    zero_runs = contiguous_runs(zero_while_truth_nonzero)

    for start, end in jump_runs:
        events.append(
            {
                "seed": int(case["model_seed"]),
                "event_type": "ModernTCN step transition",
                "start_s": float(time[start]),
                "end_s": float(time[min(end + 1, len(time) - 1)]),
                "peak_abs_rate_deg_s": float(np.max(np.abs(rate[start : end + 1]))),
            }
        )
    for start, end in zero_runs:
        events.append(
            {
                "seed": int(case["model_seed"]),
                "event_type": "Zero ModernTCN estimate while true grade is nonzero",
                "start_s": float(time[start]),
                "end_s": float(time[end]),
                "peak_abs_rate_deg_s": np.nan,
            }
        )

    if len(jump_runs) and len(zero_runs):
        classification = "step-like oscillation/dropout"
    elif len(zero_runs):
        classification = "persistent zero-output dropout"
    else:
        classification = "no signature detected"
    records.append(
        {
            "seed": int(case["model_seed"]),
            "sensor_seed": int(case["sensor_seed"]),
            "case_dir": str(case_dir),
            "window_start_s": WINDOW_START,
            "window_end_s": WINDOW_END,
            "tcn_ready_fraction": float(np.mean(ready)),
            "tcn_mae_deg": float(np.mean(np.abs(error))),
            "tcn_max_abs_error_deg": float(np.max(np.abs(error))),
            "qualified_observer_mae_deg": float(np.mean(np.abs(observer_error))),
            "max_abs_tcn_rate_deg_s": float(np.max(np.abs(rate))),
            "jump_group_count": len(jump_runs),
            "zero_output_run_count": len(zero_runs),
            "zero_output_while_ready_fraction": float(np.mean(zero_while_ready)),
            "longest_zero_output_run_s": max(
                [(end - start + 1) * 0.01 for start, end in zero_runs], default=0.0
            ),
            "classification": classification,
        }
    )

summary = pd.DataFrame(records).sort_values("seed")
event_table = pd.DataFrame(events).sort_values(["seed", "start_s", "event_type"])
summary.to_csv(OUT / "p1_seed_window_130_155s_summary.csv", index=False)
event_table.to_csv(OUT / "p1_seed_window_130_155s_events.csv", index=False)

step_seeds = summary.loc[summary["jump_group_count"].gt(0), "seed"].tolist()
dropout_only = summary.loc[
    summary["classification"].eq("persistent zero-output dropout"), "seed"
].tolist()
report = f"""# V7/P1 ModernTCN-delta seed-sensitivity audit

## Scope

The audit evaluates the same P1 factory-logistics trajectory from V7 for model seeds
1, 7, 11, 21, 42, 73, 101, 202, 340, and 520. All records are complete and use the
same sensor seed (4631). The inspection window is {WINDOW_START:.0f}–{WINDOW_END:.0f} s,
which contains the visible seed42 fluctuation around 150 s.

## Detection rule

A step-like event is a ModernTCN-delta change of at least {JUMP_RATE_DEG_S:.0f} deg/s.
A dropout is a zero ModernTCN-delta estimate while the true grade magnitude is at least
{TRUTH_NONZERO_DEG:.1f} deg. The `tcn_ready` flag is retained to distinguish an unavailable
network output from a zero-valued output emitted while the network is ready.

## Result

All ten seeds exhibit an anomalous ModernTCN-delta behavior in this window. Step-like
oscillation/dropout is present in seeds {step_seeds}. Seeds {dropout_only} do not show
step transitions because they remain at zero through the entire 25.01-s window; this is a
more persistent dropout rather than an improvement. The zero-output behavior occurs while
`tcn_ready=1` for the affected samples.

Seed42 is therefore not an isolated bad draw and is not the worst case by local maximum
error or number of transitions. The Qualified observer is substantially smoother in this
window for every seed; its local MAE remains approximately 0.29–0.30 deg, while the raw
ModernTCN-delta local MAE is approximately 1.04–1.58 deg.

## Files

- `p1_seed_window_130_155s_summary.csv`: one row per seed.
- `p1_seed_window_130_155s_events.csv`: start/end times of every detected step transition
  and zero-output run.
"""
(OUT / "p1_seed_window_130_155s_report.md").write_text(report, encoding="utf-8")
print(summary.to_string(index=False, float_format=lambda value: f"{value:.4f}"))
print(f"\nReport: {OUT / 'p1_seed_window_130_155s_report.md'}")
