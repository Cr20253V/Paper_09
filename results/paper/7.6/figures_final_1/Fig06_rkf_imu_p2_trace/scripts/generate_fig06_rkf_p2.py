"""Generate the original-style Fig. 6 layout with the P2 RKF-IMU trace."""

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


FIGURE_ROOT = ROOT / "results/paper/7.6/figures_final_1/Fig06_rkf_imu_p2_trace"
STEM = "fig06_rkf_imu_p2_trace"
WIDTH_MM = 89.0
HEIGHT_MM = 104.0
METRIC_START_S = 0.5
TIE_TOLERANCE_DEG = 0.05

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
    rkf_metrics_path = RKF_CASE / "case_metrics.json"
    rkf_manifest_path = RKF_CASE / "case_manifest.json"
    mtcn_trace_path = MTCN_CASE / "trace.csv"
    mtcn_metrics_path = MTCN_CASE / "case_metrics.json"

    rkf = pd.read_csv(rkf_trace_path)
    mtcn = pd.read_csv(mtcn_trace_path)
    rkf_metrics = json.loads(rkf_metrics_path.read_text(encoding="utf-8"))
    rkf_manifest = json.loads(rkf_manifest_path.read_text(encoding="utf-8"))
    mtcn_metrics = json.loads(mtcn_metrics_path.read_text(encoding="utf-8"))

    required = {"t_s", "theta_true", "theta_sched"}
    require_columns(rkf, required, rkf_trace_path)
    require_columns(mtcn, required, mtcn_trace_path)
    if len(rkf) != 5201 or len(mtcn) != 5201:
        raise ValueError(
            f"P2 expects 5201 samples per trace; got RKF={len(rkf)}, ModernTCN={len(mtcn)}"
        )
    if not np.array_equal(rkf["t_s"].to_numpy(), mtcn["t_s"].to_numpy()):
        raise ValueError("RKF and ModernTCN time axes are not exactly aligned")
    if not np.array_equal(rkf["theta_true"].to_numpy(), mtcn["theta_true"].to_numpy()):
        raise ValueError("RKF and ModernTCN truth trajectories are not exactly aligned")
    if not np.all(np.diff(rkf["t_s"]) > 0) or not np.isclose(rkf["t_s"].iloc[-1], 52.0):
        raise ValueError("The complete P2 trajectory must be strictly increasing from 0 to 52 s")

    data = pd.DataFrame(
        {
            "sample_index": np.arange(len(rkf), dtype=int),
            "t_s": rkf["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(rkf["theta_true"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.rad2deg(mtcn["theta_sched"].to_numpy(dtype=float)),
            "theta_rkf_deg": np.rad2deg(rkf["theta_sched"].to_numpy(dtype=float)),
        }
    )
    data["abs_error_mtcn_deg"] = (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    data["abs_error_rkf_deg"] = (data["theta_rkf_deg"] - data["theta_true_deg"]).abs()
    data["delta_abs_error_deg"] = data["abs_error_rkf_deg"] - data["abs_error_mtcn_deg"]
    data["rkf_locally_better"] = data["delta_abs_error_deg"].lt(0).astype(int)
    data["evaluation_sample"] = data["t_s"].ge(METRIC_START_S).astype(int)
    evaluated = data["evaluation_sample"].eq(1)
    data["rkf_better_beyond_tolerance"] = (
        evaluated & data["delta_abs_error_deg"].lt(-TIE_TOLERANCE_DEG)
    ).astype(int)
    data["mtcn_better_beyond_tolerance"] = (
        evaluated & data["delta_abs_error_deg"].gt(TIE_TOLERANCE_DEG)
    ).astype(int)
    data["near_tie"] = (
        evaluated & data["delta_abs_error_deg"].abs().le(TIE_TOLERANCE_DEG)
    ).astype(int)

    evaluation = data.loc[evaluated]
    checks = {
        "caption_contract": (
            "Complete P2 sharp-turn transition trace comparing frozen ModernTCN-delta seed 42 "
            "with the causal Zhu2024 RKF-IMU closed loop using deterministic sensor seed 4631. "
            "Panel (a) shows scheduled grade; panel (b) shows the signed local absolute-error "
            "difference, where negative values favor RKF-IMU."
        ),
        "layout_basis": (
            "Original Fig06_imu_observer_trace style, with its middle gain panel removed and "
            "the former panel (c) renumbered as panel (b)"
        ),
        "fixed_case": "P2 sharp-turn transition, ModernTCN seed 42, RKF sensor seed 4631",
        "trace_samples": int(len(data)),
        "alignment_rule": "time and truth arrays exactly equal; no interpolation or cropping",
        "time_start_s": float(data["t_s"].iloc[0]),
        "time_end_s": float(data["t_s"].iloc[-1]),
        "metric_initialization_exclusion_s": METRIC_START_S,
        "local_tie_tolerance_deg": TIE_TOLERANCE_DEG,
        "rkf_locally_better_fraction": float(evaluation["rkf_better_beyond_tolerance"].mean()),
        "mtcn_locally_better_fraction": float(evaluation["mtcn_better_beyond_tolerance"].mean()),
        "near_tie_fraction": float(evaluation["near_tie"].mean()),
        "error_difference_direction": (
            "negative means RKF-IMU has lower absolute scheduled-grade error than ModernTCN-delta"
        ),
        "rkf_controller": rkf_metrics["controller_id"],
        "rkf_method": rkf_metrics["method_id"],
        "rkf_sensor_seed": int(rkf_manifest["sensor_seed"]),
        "rkf_theta_mae_deg": float(rkf_metrics["theta_sched_mae_deg"]),
        "mtcn_theta_mae_deg": float(mtcn_metrics["theta_sched_mae_deg"]),
        "rkf_ey_rmse_m": float(rkf_metrics["ey_rmse"]),
        "mtcn_ey_rmse_m": float(mtcn_metrics["ey_rmse"]),
        "rkf_epsi_rmse_rad": float(rkf_metrics["epsi_rmse"]),
        "mtcn_epsi_rmse_rad": float(mtcn_metrics["epsi_rmse"]),
        "rkf_j_du": float(rkf_metrics["j_du"]),
        "mtcn_j_du": float(mtcn_metrics["j_du"]),
        "panel_count": 2,
        "paper_tex_modified": False,
        "simulation_results_modified": False,
    }
    raw_inputs = [
        rkf_trace_path,
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
        2,
        1,
        height_ratios=[2.5, 1.25],
        left=0.17,
        right=0.98,
        bottom=0.105,
        top=0.83,
        hspace=0.19,
    )
    ax_grade = fig.add_subplot(grid[0])
    ax_delta = fig.add_subplot(grid[1], sharex=ax_grade)
    axes = (ax_grade, ax_delta)
    time = data["t_s"].to_numpy(dtype=float)

    ax_grade.plot(
        time,
        data["theta_rkf_deg"],
        color=PALETTE["imu"],
        linestyle=(0, (4, 2)),
        linewidth=0.8,
    )
    ax_grade.plot(
        time,
        data["theta_mtcn_deg"],
        color=PALETTE["mtcn"],
        linewidth=0.9,
    )
    ax_grade.plot(
        time,
        data["theta_true_deg"],
        color=PALETTE["truth"],
        linewidth=1.15,
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
        r"$|e_{\mathrm{RKF}}|-|e_{\mathrm{MTCN}\!-\!\delta}|$" + "\n(deg)",
        labelpad=2,
    )
    ax_delta.set_xlabel("Time (s)")
    add_panel_label(ax_delta, "(b)", x=-0.19, y=1.015)

    for ax in axes:
        ax.set_xlim(0, 52)
        ax.set_xticks([0, 10, 20, 30, 40, 50])
        clean_axis(ax)
    ax_grade.tick_params(labelbottom=False)

    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.15),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.8, linestyle="--"),
        ],
        ["Truth", "ModernTCN-delta", "Zhu2024 RKF-IMU"],
        loc="upper center",
        ncol=2,
        bbox_to_anchor=(0.58, 0.985),
        handlelength=2.5,
        columnspacing=1.1,
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
    artist_checks = _figure_artist_checks(fig, expected_panels=2)
    outputs = _export(fig, output_dir / STEM)
    plt.close(fig)
    output_checks = _inspect_outputs(outputs, WIDTH_MM, HEIGHT_MM, qa_dir, STEM)

    visual_status = "PASS" if approve_visual_qa else "PENDING"
    manifest = {
        "figure_id": "Fig06_rkf_imu_p2_trace",
        "status": "CANDIDATE_NOT_YET_INSERTED_IN_TEX",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib", "matlab data-reading principles"],
        "output_root_contract": "figures_final_1 only; frozen paper figures and simulation results unchanged",
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
                "legend_and_label_overlap": visual_status,
                "color_and_grayscale_separability": visual_status,
                "cropping_and_panel_lettering": visual_status,
                "original_fig06_style_consistency": visual_status,
            },
            "reviewer_notes": (
                "Reviewed at 89 mm in color and grayscale. The two-panel layout retains the "
                "original Fig06 styling with the RKF trace substituted and the gain panel removed."
                if approve_visual_qa
                else "Run with --approve-visual-qa after inspecting the generated previews."
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
