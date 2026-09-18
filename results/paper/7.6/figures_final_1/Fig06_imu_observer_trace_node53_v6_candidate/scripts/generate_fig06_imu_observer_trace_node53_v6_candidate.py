"""Generate the formal P2 version of Fig. 6 from raw IMU observer outputs."""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D


def find_project_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate the project root containing data/ and results/.")


ROOT = find_project_root()
SHARED = ROOT / "results/paper/7.6/figures_final/shared"
sys.path.insert(0, str(SHARED))

from final_figure_pipeline import (  # noqa: E402
    COLORS,
    MM,
    _export,
    _figure_artist_checks,
    _inspect_outputs,
    _source_record,
    clean_axis,
    configure_style,
    relpath,
    require_columns,
    sha256_file,
)
from style import PALETTE, add_panel_label  # noqa: E402


FIGURE_ROOT = ROOT / (
    "results/paper/7.6/figures_final_1/Fig06_imu_observer_trace_node53_v6_candidate"
)
STEM = "fig06_imu_observer_trace"
WIDTH_MM = 89.0
HEIGHT_MM = 104.0
METRIC_START_S = 0.5
DECISIVE_TOLERANCE_DEG = 0.10

NODE53_ROOT = ROOT / (
    "results/modern_tcn_metric_rebuild/53_moderntcn_fuzzyakf6d_fusion_rebuild"
)
NODE53_CASE = NODE53_ROOT / (
    "08_formal_six_path_exploratory_v6/cases/V6/seed42/"
    "p02_sharp_turn_transition"
)


def load_source_data() -> tuple[pd.DataFrame, list[Path], dict[str, object]]:
    trace_path = NODE53_CASE / "trace.csv"
    debug_path = NODE53_CASE / "node53_v6_runtime_debug.csv"
    manifest_path = NODE53_CASE / "case_manifest.json"
    method_path = NODE53_ROOT / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json"

    trace = pd.read_csv(trace_path)
    debug = pd.read_csv(debug_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    method = json.loads(method_path.read_text(encoding="utf-8"))

    require_columns(trace, {"t_s", "theta_true"}, trace_path)
    require_columns(
        debug,
        {"step", "theta_tcn", "theta_fuzzyakf", "observer_valid"},
        debug_path,
    )

    if len(trace) != 5201:
        raise ValueError("The P2 trace must contain 5201 samples")
    if len(debug) != 5200:
        raise ValueError("The P2 observer log must contain 5200 updates")
    expected_steps = np.arange(1, 5201)
    if not np.array_equal(debug["step"].to_numpy(dtype=int), expected_steps):
        raise ValueError("debug.step does not map exactly to trace samples 1..5200")
    if not np.array_equal(debug["observer_valid"].to_numpy(dtype=int), np.ones(5200)):
        raise ValueError("All 5200 P2 observer updates must be valid")

    initial_nan = np.array([np.nan])
    data = pd.DataFrame(
        {
            "sample_index": np.arange(5201, dtype=int),
            "debug_step": np.concatenate((initial_nan, expected_steps.astype(float))),
            "t_s": trace["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(trace["theta_true"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.concatenate(
                (initial_nan, np.rad2deg(debug["theta_tcn"].to_numpy(dtype=float)))
            ),
            "theta_observer_deg": np.concatenate(
                (initial_nan, np.rad2deg(debug["theta_fuzzyakf"].to_numpy(dtype=float)))
            ),
        }
    )
    data["abs_error_mtcn_deg"] = (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    data["abs_error_observer_deg"] = (
        data["theta_observer_deg"] - data["theta_true_deg"]
    ).abs()
    data["delta_abs_error_deg"] = (
        data["abs_error_observer_deg"] - data["abs_error_mtcn_deg"]
    )
    data["evaluation_sample"] = data["t_s"].ge(METRIC_START_S).astype(int)
    evaluated = data["evaluation_sample"].eq(1)
    data["observer_better_beyond_tolerance"] = (
        evaluated & data["delta_abs_error_deg"].lt(-DECISIVE_TOLERANCE_DEG)
    ).astype(int)
    data["mtcn_better_beyond_tolerance"] = (
        evaluated & data["delta_abs_error_deg"].gt(DECISIVE_TOLERANCE_DEG)
    ).astype(int)
    data["near_tie"] = (
        evaluated & data["delta_abs_error_deg"].abs().le(DECISIVE_TOLERANCE_DEG)
    ).astype(int)

    evaluation = data.loc[evaluated]
    observer_mae = float(evaluation["abs_error_observer_deg"].mean())
    mtcn_mae = float(evaluation["abs_error_mtcn_deg"].mean())
    oracle_mae = float(
        np.minimum(
            evaluation["abs_error_observer_deg"], evaluation["abs_error_mtcn_deg"]
        ).mean()
    )
    best_individual_mae = min(observer_mae, mtcn_mae)
    checks = {
        "caption_contract": (
            "Complete P2 sharp-turn transition comparing raw observer outputs from "
            "ModernTCN-delta (model seed 42) and the Qualified observer "
            "(sensor seed 4631). "
            "Panel (a) shows grade estimates; panel (b) shows the local absolute-error "
            "difference, where negative values favor the Qualified observer."
        ),
        "fixed_case": "P2 sharp-turn transition",
        "observer_protocol_id": manifest["protocol_id"],
        "observer_method_id": method["method_id"],
        "observer_source_field": "theta_fuzzyakf",
        "random_sensor_noise": True,
        "three_legend_entries": [
            "Truth",
            "ModernTCN-delta",
            "Qualified observer",
        ],
        "removed_visual_claims": [
            "Observer uncertainty band",
            "Initial invalid/unavailable indicator",
        ],
        "comparison_scope": (
            "Both estimator branches are raw outputs from the same Node53 V6 P2 "
            "closed-loop simulation"
        ),
        "trace_samples": int(len(data)),
        "observer_updates_per_method": 5200,
        "alignment_rule": (
            "debug.step equals trace sample indices 1..5200; no interpolation, "
            "cropping, or downsampling"
        ),
        "time_start_s": float(data["t_s"].iloc[0]),
        "time_end_s": float(data["t_s"].iloc[-1]),
        "metric_initialization_exclusion_s": METRIC_START_S,
        "decisive_tolerance_deg": DECISIVE_TOLERANCE_DEG,
        "qualified_observer_mae_deg": observer_mae,
        "mtcn_raw_observer_mae_deg": mtcn_mae,
        "observer_decisive_win_fraction": float(
            evaluation["observer_better_beyond_tolerance"].mean()
        ),
        "mtcn_decisive_win_fraction": float(
            evaluation["mtcn_better_beyond_tolerance"].mean()
        ),
        "near_tie_fraction": float(evaluation["near_tie"].mean()),
        "ideal_samplewise_minimum_gain_over_best_fraction": float(
            1.0 - oracle_mae / best_individual_mae
        ),
        "error_difference_direction": (
            "negative means the Qualified observer has lower absolute raw observer error "
            "than ModernTCN-delta"
        ),
        "sensor_seed": int(manifest["sensor_seed"]),
        "mtcn_model_seed": int(manifest["model_seed"]),
        "panel_count": 2,
        "paper_tex_modified": False,
        "simulation_results_modified": False,
    }
    raw_inputs = [
        trace_path,
        debug_path,
        manifest_path,
        method_path,
    ]
    return data, raw_inputs, checks


def build_figure(data: pd.DataFrame) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    grid = fig.add_gridspec(
        2,
        1,
        height_ratios=[2.45, 1.15],
        left=0.17,
        right=0.98,
        bottom=0.11,
        top=0.89,
        hspace=0.18,
    )
    ax_grade = fig.add_subplot(grid[0])
    ax_delta = fig.add_subplot(grid[1], sharex=ax_grade)
    time = data["t_s"].to_numpy(dtype=float)

    ax_grade.plot(
        time,
        data["theta_observer_deg"],
        color=PALETTE["imu"],
        linestyle=(0, (4, 2)),
        linewidth=0.85,
        zorder=2,
    )
    ax_grade.plot(
        time,
        data["theta_mtcn_deg"],
        color=PALETTE["mtcn"],
        linewidth=0.9,
        zorder=2,
    )
    ax_grade.plot(
        time,
        data["theta_true_deg"],
        color=PALETTE["truth"],
        linewidth=1.15,
        zorder=3,
    )
    ax_grade.set_ylabel("Grade angle (deg)", labelpad=2)
    add_panel_label(ax_grade, "(a)", x=-0.19, y=1.015)

    delta = data["delta_abs_error_deg"].to_numpy(dtype=float)
    finite = np.isfinite(delta)
    ax_delta.fill_between(
        time,
        0,
        delta,
        where=finite & (delta <= 0),
        color=COLORS["benefit"],
        alpha=0.30,
    )
    ax_delta.fill_between(
        time,
        0,
        delta,
        where=finite & (delta > 0),
        color=COLORS["adverse"],
        alpha=0.28,
    )
    ax_delta.plot(time, delta, color="#555555", linewidth=0.48)
    ax_delta.axhline(0, color="#222222", linewidth=0.6)
    limit = math.ceil(float(np.nanmax(np.abs(delta))) * 2) / 2
    ax_delta.set_ylim(-limit, limit)
    ax_delta.set_ylabel(
        r"$|e_{\mathrm{obs}}|-|e_{\mathrm{MTCN}\! -\!\delta}|$" + "\n(deg)",
        labelpad=2,
    )
    ax_delta.set_xlabel("Time (s)")
    add_panel_label(ax_delta, "(b)", x=-0.19, y=1.015)

    for axis in (ax_grade, ax_delta):
        axis.set_xlim(0, 52)
        axis.set_xticks([0, 10, 20, 30, 40, 50])
        clean_axis(axis)
    ax_grade.tick_params(labelbottom=False)

    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.15),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.85, linestyle="--"),
        ],
        ["Truth", "ModernTCN-delta", "Qualified observer"],
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.58, 0.982),
        handlelength=2.35,
        handletextpad=0.55,
        columnspacing=0.85,
        fontsize=6.4,
    )
    return fig


def finalize(approve_visual_qa: bool) -> Path:
    source_dir = FIGURE_ROOT / "source_data"
    output_dir = FIGURE_ROOT / "output"
    qa_dir = FIGURE_ROOT / "qa"
    for directory in (source_dir, output_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    data, raw_inputs, checks = load_source_data()
    source_path = source_dir / f"{STEM}_source_data.csv"
    data.to_csv(source_path, index=False)
    figure = build_figure(data)
    artist_checks = _figure_artist_checks(figure, expected_panels=2)
    outputs = _export(figure, output_dir / STEM)
    plt.close(figure)
    output_checks = _inspect_outputs(outputs, WIDTH_MM, HEIGHT_MM, qa_dir, STEM)

    visual_status = "PASS" if approve_visual_qa else "PENDING"
    manifest = {
        "figure_id": "Fig06_imu_observer_trace",
        "status": "CANDIDATE_NOT_YET_INSERTED_IN_TEX",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib"],
        "output_root_contract": (
            "formal Fig. 6 candidate in figures_final_1; earlier P2 candidates, paper TeX, "
            "and simulation results unchanged"
        ),
        "frozen_inputs": [
            _source_record(path, ROOT, f"input_{index + 1}")
            for index, path in enumerate(raw_inputs)
        ],
        "source_data": {
            "file": relpath(source_path, ROOT),
            "rows": int(data.shape[0]),
            "columns": list(data.columns),
            "sha256": sha256_file(source_path),
        },
        "outputs": [_source_record(path, ROOT, path.suffix[1:]) for path in outputs],
        "automatic_qa": {
            "status": "PASS",
            "contract_checks": checks,
            "artist_checks": artist_checks,
            "output_checks": {
                **{key: value for key, value in output_checks.items() if key != "grayscale_preview"},
                "grayscale_preview": relpath(output_checks["grayscale_preview"], ROOT),
            },
        },
        "visual_qa": {
            "status": "PASS" if approve_visual_qa else "PENDING_MANUAL_REVIEW",
            "review_at_final_size": True,
            "checks": {
                "font_readability": visual_status,
                "three_entry_legend_layout": visual_status,
                "legend_and_label_overlap": visual_status,
                "color_and_grayscale_separability": visual_status,
                "cropping_and_panel_lettering": visual_status,
            },
            "reviewer_notes": (
                "Reviewed at 89 mm in color and grayscale. The single-row three-entry legend, "
                "two-panel layout, and line-style distinctions remain readable."
                if approve_visual_qa
                else "Run with --approve-visual-qa after inspecting both generated previews."
            ),
        },
    }
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2)
    manifest_path = FIGURE_ROOT / "manifest.json"
    manifest_path.write_text(encoded, encoding="utf-8")
    (qa_dir / f"{STEM}_qa.json").write_text(encoded, encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), "outputs": [str(p) for p in outputs]}, indent=2))
    return manifest_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--approve-visual-qa", action="store_true")
    arguments = parser.parse_args()
    finalize(arguments.approve_visual_qa)
