"""Generate the P2 RKF-IMU versus ModernTCN Fig. 6 candidate.

This script is intentionally independent of the frozen ``figures_final``
pipeline output root. It reads existing closed-loop results and only writes
under ``figures_final_1/Fig06_rkf_imu_p2_trace``.
"""

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
from matplotlib.patches import Patch


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


FIGURE_ROOT = ROOT / "results/paper/7.6/figures_final_1/Fig06_rkf_imu_p2_trace"
STEM = "fig06_rkf_imu_p2_trace"
WIDTH_MM = 89.0
HEIGHT_MM = 104.0
TIE_TOLERANCE_DEG = 0.05
METRIC_START_S = 0.5

RKF_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/"
    "12_rkf_six_path_benchmark/04_rkf_closed_loop/cases/p02_sharp_turn_transition"
)
MTCN_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/40_legal_imu_uncertainty_fusion/04_cases/"
    "nominal/G0/s42/path_closed_loop_sharp_turn_transition_theta10_v1"
)


def load_source_data() -> tuple[pd.DataFrame, list[Path], dict[str, object]]:
    rkf_trace_path = RKF_CASE / "trace.csv"
    rkf_debug_path = RKF_CASE / "rkf_runtime_debug.csv"
    rkf_metrics_path = RKF_CASE / "case_metrics.json"
    rkf_manifest_path = RKF_CASE / "case_manifest.json"
    mtcn_trace_path = MTCN_CASE / "trace.csv"
    mtcn_metrics_path = MTCN_CASE / "case_metrics.json"

    rkf = pd.read_csv(rkf_trace_path)
    debug = pd.read_csv(rkf_debug_path)
    mtcn = pd.read_csv(mtcn_trace_path)
    rkf_metrics = json.loads(rkf_metrics_path.read_text(encoding="utf-8"))
    mtcn_metrics = json.loads(mtcn_metrics_path.read_text(encoding="utf-8"))
    rkf_manifest = json.loads(rkf_manifest_path.read_text(encoding="utf-8"))

    trace_columns = {"t_s", "theta_true", "theta_sched"}
    debug_columns = {
        "step",
        "theta_rkf",
        "innovation_norm",
        "external_accel_variance_max",
        "covariance_updated",
        "anomaly_detected",
        "observer_valid",
    }
    require_columns(rkf, trace_columns, rkf_trace_path)
    require_columns(mtcn, trace_columns, mtcn_trace_path)
    require_columns(debug, debug_columns, rkf_debug_path)

    if len(rkf) != 5201 or len(mtcn) != 5201 or len(debug) != 5200:
        raise ValueError(
            "P2 candidate expects 5201 samples per trace and 5200 RKF updates; "
            f"got RKF={len(rkf)}, ModernTCN={len(mtcn)}, debug={len(debug)}"
        )
    steps = debug["step"].to_numpy(dtype=int)
    if not np.array_equal(steps, np.arange(1, len(rkf))):
        raise ValueError("RKF debug.step no longer maps to trace indices 1..5200")
    if not np.array_equal(rkf["t_s"].to_numpy(), mtcn["t_s"].to_numpy()):
        raise ValueError("RKF and ModernTCN P2 time axes are not exactly aligned")
    if not np.array_equal(rkf["theta_true"].to_numpy(), mtcn["theta_true"].to_numpy()):
        raise ValueError("RKF and ModernTCN P2 truth trajectories are not exactly aligned")
    if not np.isclose(rkf["t_s"].iloc[-1], 52.0):
        raise ValueError("The complete P2 trajectory must end at 52 s")

    initial_nan = np.array([np.nan])
    initial_zero = np.array([0], dtype=int)
    data = pd.DataFrame(
        {
            "sample_index": np.arange(len(rkf), dtype=int),
            "debug_step": np.concatenate((initial_nan, steps.astype(float))),
            "t_s": rkf["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(rkf["theta_true"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.rad2deg(mtcn["theta_sched"].to_numpy(dtype=float)),
            "theta_rkf_deg": np.rad2deg(rkf["theta_sched"].to_numpy(dtype=float)),
            "rkf_innovation_norm_mps2": np.concatenate(
                (initial_nan, debug["innovation_norm"].to_numpy(dtype=float))
            ),
            "rkf_external_accel_variance_max_m2ps4": np.concatenate(
                (initial_nan, debug["external_accel_variance_max"].to_numpy(dtype=float))
            ),
            "rkf_covariance_updated": np.concatenate(
                (initial_zero, debug["covariance_updated"].to_numpy(dtype=int))
            ),
            "rkf_anomaly_detected": np.concatenate(
                (initial_zero, debug["anomaly_detected"].to_numpy(dtype=int))
            ),
            "rkf_observer_valid": np.concatenate(
                (initial_zero, debug["observer_valid"].to_numpy(dtype=int))
            ),
        }
    )
    data["abs_error_mtcn_deg"] = (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    data["abs_error_rkf_deg"] = (data["theta_rkf_deg"] - data["theta_true_deg"]).abs()
    data["delta_abs_error_deg"] = data["abs_error_rkf_deg"] - data["abs_error_mtcn_deg"]
    data["evaluation_sample"] = (data["t_s"] >= METRIC_START_S).astype(int)
    evaluated = data["evaluation_sample"].eq(1)
    data["rkf_locally_better"] = (
        evaluated & data["delta_abs_error_deg"].lt(-TIE_TOLERANCE_DEG)
    ).astype(int)
    data["mtcn_locally_better"] = (
        evaluated & data["delta_abs_error_deg"].gt(TIE_TOLERANCE_DEG)
    ).astype(int)
    data["near_tie"] = (
        evaluated & data["delta_abs_error_deg"].abs().le(TIE_TOLERANCE_DEG)
    ).astype(int)

    evaluation = data.loc[evaluated]
    n_eval = len(evaluation)
    rkf_better_fraction = float(evaluation["rkf_locally_better"].mean())
    mtcn_better_fraction = float(evaluation["mtcn_locally_better"].mean())
    tie_fraction = float(evaluation["near_tie"].mean())
    if not np.isclose(rkf_better_fraction + mtcn_better_fraction + tie_fraction, 1.0):
        raise ValueError("Local comparison fractions do not partition the evaluation samples")

    covariance_steps = data.loc[data["rkf_covariance_updated"].eq(1), "t_s"].to_numpy()
    checks = {
        "caption_contract": (
            "Complete P2 sharp-turn transition trace comparing frozen ModernTCN-delta seed 42 "
            "with the causal Zhu2024 RKF-IMU closed loop using deterministic sensor seed 4631. "
            "The trace illustrates local estimator complementarity and does not replace the "
            "formal multi-route statistics or claim that the current Fusion controller uses RKF."
        ),
        "fixed_case": "P2 Sharp-turn transition",
        "modern_tcn_controller": "NODE40_G0",
        "modern_tcn_seed": 42,
        "rkf_controller": rkf_metrics["controller_id"],
        "rkf_method": rkf_metrics["method_id"],
        "rkf_sensor_seed": int(rkf_manifest["sensor_seed"]),
        "trace_samples": int(len(data)),
        "rkf_debug_updates": int(len(debug)),
        "alignment_rule": (
            "Both trace time axes and truth arrays are exactly equal; RKF debug.step maps to "
            "trace index 1..5200; no interpolation or cropping"
        ),
        "time_start_s": float(data["t_s"].iloc[0]),
        "time_end_s": float(data["t_s"].iloc[-1]),
        "metric_initialization_exclusion_s": METRIC_START_S,
        "evaluation_samples": n_eval,
        "local_tie_tolerance_deg": TIE_TOLERANCE_DEG,
        "rkf_locally_better_fraction": rkf_better_fraction,
        "mtcn_locally_better_fraction": mtcn_better_fraction,
        "near_tie_fraction": tie_fraction,
        "delta_mean_deg": float(evaluation["delta_abs_error_deg"].mean()),
        "error_difference_direction": (
            "negative means RKF-IMU has lower absolute scheduled-grade error than ModernTCN-delta"
        ),
        "rkf_theta_mae_deg": float(rkf_metrics["theta_sched_mae_deg"]),
        "mtcn_theta_mae_deg": float(mtcn_metrics["theta_sched_mae_deg"]),
        "rkf_ey_rmse_m": float(rkf_metrics["ey_rmse"]),
        "mtcn_ey_rmse_m": float(mtcn_metrics["ey_rmse"]),
        "rkf_epsi_rmse_rad": float(rkf_metrics["epsi_rmse"]),
        "mtcn_epsi_rmse_rad": float(mtcn_metrics["epsi_rmse"]),
        "rkf_j_du": float(rkf_metrics["j_du"]),
        "mtcn_j_du": float(mtcn_metrics["j_du"]),
        "rkf_covariance_update_count": int(data["rkf_covariance_updated"].sum()),
        "rkf_covariance_update_interval_s": (
            [float(covariance_steps.min()), float(covariance_steps.max())]
            if covariance_steps.size
            else []
        ),
        "rkf_observer_invalid_update_count": int((debug["observer_valid"] == 0).sum()),
        "middle_panel_semantics": (
            "Innovation norm is in m/s^2; external-acceleration variance is in (m/s^2)^2 "
            "and is not an attitude confidence interval"
        ),
        "paper_tex_modified": False,
        "existing_results_modified": False,
    }
    raw_inputs = [
        rkf_trace_path,
        rkf_debug_path,
        rkf_metrics_path,
        rkf_manifest_path,
        mtcn_trace_path,
        mtcn_metrics_path,
    ]
    return data, raw_inputs, checks


def build_figure(data: pd.DataFrame) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    grid = fig.add_gridspec(
        3,
        1,
        height_ratios=[2.45, 1.10, 1.35],
        left=0.17,
        right=0.86,
        bottom=0.105,
        top=0.80,
        hspace=0.22,
    )
    ax_grade = fig.add_subplot(grid[0])
    ax_diag = fig.add_subplot(grid[1], sharex=ax_grade)
    ax_delta = fig.add_subplot(grid[2], sharex=ax_grade)
    ax_var = ax_diag.twinx()
    axes = (ax_grade, ax_diag, ax_delta)
    time = data["t_s"].to_numpy(dtype=float)

    for ax in axes:
        ax.axvspan(0, METRIC_START_S, facecolor=PALETTE["invalid"], alpha=0.28, linewidth=0)

    ax_grade.plot(
        time,
        data["theta_rkf_deg"],
        color=PALETTE["imu"],
        linestyle=(0, (4, 2)),
        linewidth=0.85,
        zorder=3,
    )
    ax_grade.plot(
        time,
        data["theta_mtcn_deg"],
        color=PALETTE["mtcn"],
        linewidth=0.9,
        zorder=4,
    )
    ax_grade.plot(
        time,
        data["theta_true_deg"],
        color=PALETTE["truth"],
        linewidth=1.15,
        zorder=5,
    )
    ax_grade.set_ylabel("Grade angle (deg)", labelpad=2)
    add_panel_label(ax_grade, "(a)", x=-0.23, y=1.015)

    innovation = data["rkf_innovation_norm_mps2"].to_numpy(dtype=float)
    variance = data["rkf_external_accel_variance_max_m2ps4"].to_numpy(dtype=float)
    ax_diag.plot(time, innovation, color=PALETTE["gru"], linewidth=0.65, zorder=3)
    ax_var.plot(time, variance, color=PALETTE["tcn"], linewidth=0.8, linestyle=(0, (3, 1.5)), zorder=2)
    updates = data["rkf_covariance_updated"].to_numpy(dtype=bool)
    ax_diag.scatter(
        time[updates],
        innovation[updates],
        marker="^",
        s=10,
        facecolor=PALETTE["warning"],
        edgecolor="white",
        linewidth=0.25,
        zorder=5,
    )
    ax_diag.set_ylim(0, 0.40)
    ax_diag.set_yticks([0, 0.2, 0.4])
    ax_var.set_ylim(0, 0.065)
    ax_var.set_yticks([0, 0.03, 0.06])
    ax_diag.set_ylabel(r"Innovation norm (m s$^{-2}$)", labelpad=2)
    ax_var.set_ylabel(r"Max ext. accel. var. (m$^2$ s$^{-4}$)", labelpad=2, color=PALETTE["tcn"])
    ax_var.tick_params(axis="y", colors=PALETTE["tcn"], direction="out", pad=1.5)
    ax_var.spines["right"].set_visible(True)
    ax_var.spines["right"].set_color(PALETTE["tcn"])
    ax_var.spines["right"].set_linewidth(0.65)
    ax_var.spines["top"].set_visible(False)
    add_panel_label(ax_diag, "(b)", x=-0.23, y=1.015)
    diagnostic_legend = ax_diag.legend(
        [
            Line2D([], [], color=PALETTE["gru"], linewidth=0.75),
            Line2D([], [], color=PALETTE["tcn"], linewidth=0.8, linestyle="--"),
            Line2D([], [], color=PALETTE["warning"], marker="^", linestyle="none", markersize=3.6),
        ],
        ["Innovation", "External-accel. variance", "Covariance update"],
        loc="upper right",
        ncol=1,
        handlelength=1.6,
        borderaxespad=0.2,
        labelspacing=0.2,
        frameon=True,
    )
    diagnostic_legend.get_frame().set_facecolor("white")
    diagnostic_legend.get_frame().set_edgecolor("none")
    diagnostic_legend.get_frame().set_alpha(0.88)

    delta = data["delta_abs_error_deg"].to_numpy(dtype=float)
    finite = np.isfinite(delta)
    ax_delta.axhspan(
        -TIE_TOLERANCE_DEG,
        TIE_TOLERANCE_DEG,
        facecolor=COLORS["neutral"],
        alpha=0.55,
        linewidth=0,
        zorder=0,
    )
    ax_delta.fill_between(
        time,
        0,
        delta,
        where=finite & (delta <= -TIE_TOLERANCE_DEG),
        color=COLORS["benefit"],
        alpha=0.30,
        linewidth=0,
        interpolate=True,
    )
    ax_delta.fill_between(
        time,
        0,
        delta,
        where=finite & (delta >= TIE_TOLERANCE_DEG),
        color=COLORS["adverse"],
        alpha=0.24,
        edgecolor=COLORS["adverse"],
        linewidth=0.18,
        hatch="////",
        interpolate=True,
    )
    ax_delta.plot(time, delta, color="#555555", linewidth=0.48)
    ax_delta.axhline(0, color="#222222", linewidth=0.6)
    limit = math.ceil(float(np.nanmax(np.abs(delta))) * 2) / 2
    ax_delta.set_ylim(-limit, limit)
    ax_delta.set_ylabel(
        r"$|e_{\mathrm{RKF}}|-|e_{\mathrm{MTCN}\!-\!\delta}|$" + "\n(deg)",
        labelpad=2,
    )
    ax_delta.set_xlabel("Time (s)")
    ax_delta.text(
        0.01,
        0.06,
        "<0: RKF-IMU better",
        transform=ax_delta.transAxes,
        ha="left",
        va="bottom",
        fontsize=6.0,
        color=COLORS["benefit"],
    )
    ax_delta.text(
        0.99,
        0.94,
        ">0: ModernTCN better",
        transform=ax_delta.transAxes,
        ha="right",
        va="top",
        fontsize=6.0,
        color=COLORS["adverse"],
    )
    add_panel_label(ax_delta, "(c)", x=-0.23, y=1.015)

    for ax in axes:
        ax.set_xlim(0, 52)
        ax.set_xticks([0, 10, 20, 30, 40, 50])
        clean_axis(ax)
    ax_grade.tick_params(labelbottom=False)
    ax_diag.tick_params(labelbottom=False)

    fig.text(
        0.515,
        0.975,
        "P2 sharp-turn transition | ModernTCN seed 42 | RKF sensor seed 4631",
        ha="center",
        va="top",
        fontsize=6.2,
        color=COLORS["ink"],
    )
    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.15),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.85, linestyle="--"),
            Patch(facecolor=PALETTE["invalid"], alpha=0.28),
        ],
        ["Truth", "ModernTCN-delta", "Zhu2024 RKF-IMU", "Metric warm-up"],
        loc="upper center",
        ncol=2,
        bbox_to_anchor=(0.515, 0.94),
        handlelength=2.4,
        columnspacing=1.0,
        labelspacing=0.25,
    )
    return fig


def finalize(approve_visual_qa: bool) -> Path:
    source_dir = FIGURE_ROOT / "source_data"
    output_dir = FIGURE_ROOT / "output"
    qa_dir = FIGURE_ROOT / "qa"
    for directory in (source_dir, output_dir, qa_dir, FIGURE_ROOT / "archive"):
        directory.mkdir(parents=True, exist_ok=True)

    data, raw_inputs, checks = load_source_data()
    source_path = source_dir / f"{STEM}_source_data.csv"
    data.to_csv(source_path, index=False)
    fig = build_figure(data)
    artist_checks = _figure_artist_checks(fig, expected_panels=3)
    outputs = _export(fig, output_dir / STEM)
    plt.close(fig)
    output_checks = _inspect_outputs(outputs, WIDTH_MM, HEIGHT_MM, qa_dir, STEM)

    visual_qa = {
        "status": "PASS" if approve_visual_qa else "PENDING_MANUAL_REVIEW",
        "review_at_final_size": True,
        "checks": {
            "font_readability": "PASS" if approve_visual_qa else "PENDING",
            "legend_and_label_overlap": "PASS" if approve_visual_qa else "PENDING",
            "color_and_grayscale_separability": "PASS" if approve_visual_qa else "PENDING",
            "cropping_and_panel_lettering": "PASS" if approve_visual_qa else "PENDING",
            "caption_contract_consistency": "PASS" if approve_visual_qa else "PENDING",
        },
        "reviewer_notes": (
            "Reviewed at the 89 mm target width in color and grayscale; full P2 trace, RKF "
            "diagnostics, update markers, and signed local error difference are readable."
            if approve_visual_qa
            else "Run with --approve-visual-qa only after inspecting the generated color and grayscale previews."
        ),
    }
    manifest = {
        "figure_id": "Fig06_rkf_imu_p2_trace",
        "status": "CANDIDATE_NOT_YET_INSERTED_IN_TEX",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib", "matlab data-reading principles"],
        "output_root_contract": "figures_final_1 only; no overwrite of frozen paper figures or simulation results",
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
        "visual_qa": visual_qa,
    }
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2)
    manifest_path = FIGURE_ROOT / "manifest.json"
    qa_path = qa_dir / f"{STEM}_qa.json"
    manifest_path.write_text(encoded, encoding="utf-8")
    qa_path.write_text(encoded, encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), "outputs": [str(p) for p in outputs]}, indent=2))
    return manifest_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--approve-visual-qa",
        action="store_true",
        help="Mark visual QA as passed after inspecting the generated color and grayscale previews.",
    )
    arguments = parser.parse_args()
    finalize(arguments.approve_visual_qa)
