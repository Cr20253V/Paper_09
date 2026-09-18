"""Generate the two-panel P2 RKF observer trace with five legend entries."""

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
    _boolean_intervals,
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
    "results/paper/7.6/figures_final_1/Fig06_rkf_imu_p2_trace_five_legend"
)
STEM = "fig06_rkf_imu_p2_trace_five_legend"
WIDTH_MM = 89.0
HEIGHT_MM = 104.0

RKF_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/"
    "12_rkf_six_path_benchmark/04_rkf_closed_loop/cases/p02_sharp_turn_transition"
)
MTCN_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/40_legal_imu_uncertainty_fusion/04_cases/"
    "nominal/G0/s42/path_closed_loop_sharp_turn_transition_theta10_v1"
)
RKF_TOOLS = ROOT / (
    "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/11_rkf_trial/tools"
)


def unit_vector(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if not np.isfinite(norm) or norm < 1e-12:
        return np.array([0.0, 0.0, 1.0])
    return vector / norm


def skew(vector: np.ndarray) -> np.ndarray:
    return np.array(
        [
            [0.0, -vector[2], vector[1]],
            [vector[2], 0.0, -vector[0]],
            [-vector[1], vector[0], 0.0],
        ]
    )


def replay_rkf_covariance(debug: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    """Replay the frozen MATLAB RKF and propagate P to var(theta)."""
    sample_time = 0.01
    gravity = 9.81
    window_length = 10
    external_accel_coefficient = math.exp(-sample_time / 0.25)
    gyro_noise_std = np.array([0.002, 0.002, 0.002])
    accel_noise_std = np.array([0.05, 0.05, 0.05])
    gyro_bias = np.array([0.0, 0.00035, 0.0])
    accel_bias = np.array([0.03, 0.02, -0.02])
    initial_attitude_std = np.deg2rad(2.0)
    max_external_accel_variance = 100.0

    direction = np.array([0.0, 0.0, 1.0])
    covariance = np.eye(3) * initial_attitude_std**2
    external_accel_previous = np.zeros(3)
    external_accel_covariance = np.zeros((3, 3))
    innovation_buffer = np.zeros((3, window_length))
    innovation_count = 0
    innovation_index = 0
    initialized = False

    def update(packet: np.ndarray) -> tuple[float, float]:
        nonlocal direction, covariance, external_accel_previous
        nonlocal external_accel_covariance, innovation_count, innovation_index, initialized

        accel = packet[:3] - accel_bias
        gyro = packet[3:] - gyro_bias
        if not initialized:
            direction = unit_vector(accel)
            external_accel_previous = accel - gravity * direction
            initialized = True

        omega_cross = skew(gyro)
        transition = np.eye(3) + sample_time * omega_cross
        direction_pred = unit_vector(transition @ direction)
        process_covariance = (
            sample_time**2
            * skew(direction)
            @ np.diag(gyro_noise_std**2)
            @ skew(direction).T
        )
        covariance_pred = transition @ covariance @ transition.T + process_covariance
        covariance_pred = 0.5 * (covariance_pred + covariance_pred.T)

        observation = gravity * np.eye(3)
        accel_model = external_accel_coefficient * external_accel_previous
        innovation = accel - accel_model - observation @ direction_pred
        innovation_buffer[:, innovation_index] = innovation
        innovation_index = (innovation_index + 1) % window_length
        innovation_count = min(innovation_count + 1, window_length)

        accel_covariance = np.diag(accel_noise_std**2)
        predicted_innovation_covariance = (
            observation @ covariance_pred @ observation.T
            + external_accel_covariance
            + accel_covariance
        )
        anomaly_detected = innovation @ innovation > np.trace(predicted_innovation_covariance)
        if innovation_count == window_length and anomaly_detected:
            sample_covariance = innovation_buffer @ innovation_buffer.T / window_length
            estimated_external_covariance = (
                sample_covariance
                - observation @ covariance_pred @ observation.T
                - accel_covariance
            )
            adaptive_variance = np.clip(
                np.diag(estimated_external_covariance),
                0.0,
                max_external_accel_variance,
            )
            external_accel_covariance = np.diag(adaptive_variance)

        measurement_covariance = accel_covariance + external_accel_covariance
        innovation_covariance = (
            observation @ covariance_pred @ observation.T + measurement_covariance
        )
        gain_numerator = covariance_pred @ observation.T
        gain = np.linalg.solve(innovation_covariance.T, gain_numerator.T).T
        direction = unit_vector(direction_pred + gain @ innovation)
        identity_minus_gain = np.eye(3) - gain @ observation
        covariance = (
            identity_minus_gain @ covariance_pred @ identity_minus_gain.T
            + gain @ measurement_covariance @ gain.T
        )
        covariance = 0.5 * (covariance + covariance.T)
        external_accel_previous = accel - gravity * direction

        theta = math.atan2(direction[0], direction[2])
        denominator = direction[0] ** 2 + direction[2] ** 2
        theta_jacobian = np.array([direction[2], 0.0, -direction[0]]) / denominator
        theta_variance = float(theta_jacobian @ covariance @ theta_jacobian)
        return theta, theta_variance

    mount_error = np.deg2rad(0.15)
    mount_rotation = np.array(
        [
            [math.cos(mount_error), 0.0, math.sin(mount_error)],
            [0.0, 1.0, 0.0],
            [-math.sin(mount_error), 0.0, math.cos(mount_error)],
        ]
    )
    stationary_packet = np.concatenate(
        (mount_rotation @ np.array([0.0, 0.0, gravity]) + accel_bias, gyro_bias)
    )
    for _ in range(100):
        update(stationary_packet)

    theta = np.empty(len(debug))
    theta_variance = np.empty(len(debug))
    packet_columns = ["fx", "fy", "fz", "gx", "gy", "gz"]
    for index, packet in enumerate(debug[packet_columns].to_numpy(dtype=float)):
        theta[index], theta_variance[index] = update(packet)
    return theta, theta_variance


def load_source_data() -> tuple[pd.DataFrame, list[Path], dict[str, object]]:
    rkf_trace_path = RKF_CASE / "trace.csv"
    rkf_debug_path = RKF_CASE / "rkf_runtime_debug.csv"
    rkf_manifest_path = RKF_CASE / "case_manifest.json"
    mtcn_trace_path = MTCN_CASE / "trace.csv"
    mtcn_debug_path = MTCN_CASE / "node40_runtime_debug.csv"
    estimator_path = RKF_TOOLS / "node45r3_rkf_estimator.m"
    estimator_config_path = RKF_TOOLS / "node45r3_rkf_config.m"
    runtime_selector_path = RKF_TOOLS / "node45r3_runtime_selector.m"
    trial_config_path = RKF_TOOLS / "node45r3_trial_config.m"

    rkf_trace = pd.read_csv(rkf_trace_path)
    rkf_debug = pd.read_csv(rkf_debug_path)
    mtcn_trace = pd.read_csv(mtcn_trace_path)
    mtcn_debug = pd.read_csv(mtcn_debug_path)
    rkf_manifest = json.loads(rkf_manifest_path.read_text(encoding="utf-8"))

    require_columns(rkf_trace, {"t_s", "theta_true"}, rkf_trace_path)
    require_columns(mtcn_trace, {"t_s", "theta_true"}, mtcn_trace_path)
    require_columns(
        rkf_debug,
        {
            "step",
            "fx",
            "fy",
            "fz",
            "gx",
            "gy",
            "gz",
            "theta_rkf",
            "observer_valid",
        },
        rkf_debug_path,
    )
    require_columns(mtcn_debug, {"step", "theta_tcn"}, mtcn_debug_path)
    if len(rkf_trace) != 5201 or len(mtcn_trace) != 5201:
        raise ValueError("P2 traces must each contain 5201 samples")
    if len(rkf_debug) != 5200 or len(mtcn_debug) != 5200:
        raise ValueError("P2 observer logs must each contain 5200 updates")
    expected_steps = np.arange(1, 5201)
    if not np.array_equal(rkf_debug["step"].to_numpy(dtype=int), expected_steps):
        raise ValueError("RKF debug.step does not map exactly to trace samples 1..5200")
    if not np.array_equal(mtcn_debug["step"].to_numpy(dtype=int), expected_steps):
        raise ValueError("ModernTCN debug.step does not map exactly to trace samples 1..5200")
    if not np.array_equal(rkf_trace["t_s"].to_numpy(), mtcn_trace["t_s"].to_numpy()):
        raise ValueError("RKF and ModernTCN time axes are not exactly aligned")
    if not np.array_equal(
        rkf_trace["theta_true"].to_numpy(), mtcn_trace["theta_true"].to_numpy()
    ):
        raise ValueError("RKF and ModernTCN truth trajectories are not exactly aligned")

    replay_theta, replay_variance = replay_rkf_covariance(rkf_debug)
    replay_error_deg = np.rad2deg(replay_theta - rkf_debug["theta_rkf"].to_numpy(dtype=float))
    maximum_replay_error_deg = float(np.max(np.abs(replay_error_deg)))
    if maximum_replay_error_deg > 1e-10:
        raise ValueError(
            f"RKF covariance replay does not reproduce theta_rkf: {maximum_replay_error_deg} deg"
        )
    if not np.isfinite(replay_variance).all() or (replay_variance < 0).any():
        raise ValueError("Replayed RKF attitude variance is not finite and nonnegative")

    initial_nan = np.array([np.nan])
    data = pd.DataFrame(
        {
            "sample_index": np.arange(5201, dtype=int),
            "debug_step": np.concatenate((initial_nan, expected_steps.astype(float))),
            "t_s": rkf_trace["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(rkf_trace["theta_true"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.concatenate(
                (initial_nan, np.rad2deg(mtcn_debug["theta_tcn"].to_numpy(dtype=float)))
            ),
            "theta_rkf_deg": np.concatenate(
                (initial_nan, np.rad2deg(rkf_debug["theta_rkf"].to_numpy(dtype=float)))
            ),
            "rkf_theta_variance_rad2": np.concatenate((initial_nan, replay_variance)),
            "rkf_observer_valid": np.concatenate(
                ([0], rkf_debug["observer_valid"].to_numpy(dtype=int))
            ),
            "observer_update_available": np.concatenate(([0], np.ones(5200, dtype=int))),
        }
    )
    data["rkf_uncertainty_halfwidth_deg"] = np.rad2deg(
        1.96 * np.sqrt(data["rkf_theta_variance_rad2"])
    )
    data["delta_abs_error_deg"] = (
        (data["theta_rkf_deg"] - data["theta_true_deg"]).abs()
        - (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    )
    data["rkf_locally_better"] = (
        data["rkf_observer_valid"].eq(1) & data["delta_abs_error_deg"].lt(0)
    ).astype(int)
    invalid = data["rkf_observer_valid"].eq(0) | data["observer_update_available"].eq(0)

    checks = {
        "caption_contract": (
            "Complete P2 observer-output trace for ModernTCN-delta seed 42 and Zhu2024 "
            "RKF-IMU sensor seed 4631. The shaded band is the replayed linearized RKF state "
            "uncertainty, estimate +/- 1.96 sqrt(var(theta)); it is not a calibrated coverage claim."
        ),
        "five_legend_entries": [
            "Truth",
            "ModernTCN-delta",
            "Zhu2024 RKF-IMU",
            "RKF linearized uncertainty +/-1.96 sqrt(var(theta))",
            "Invalid / unavailable",
        ],
        "panel_count": 2,
        "middle_panel_removed": True,
        "fixed_case": "P2 sharp-turn transition, ModernTCN seed 42, RKF sensor seed 4631",
        "trace_samples": int(len(data)),
        "debug_updates_per_observer": 5200,
        "alignment_rule": (
            "Both debug.step arrays equal trace sample indices 1..5200; time and truth arrays "
            "are exactly equal; no interpolation or cropping"
        ),
        "rkf_covariance_replay_definition": (
            "Exact deterministic replay of node45r3_rkf_estimator.m including 100 stationary "
            "initialization updates; var(theta)=J_theta P J_theta^T"
        ),
        "rkf_replay_max_abs_theta_error_deg": maximum_replay_error_deg,
        "rkf_uncertainty_halfwidth_min_deg": float(
            data["rkf_uncertainty_halfwidth_deg"].min()
        ),
        "rkf_uncertainty_halfwidth_max_deg": float(
            data["rkf_uncertainty_halfwidth_deg"].max()
        ),
        "uncertainty_calibrated_coverage_claim": False,
        "invalid_or_unavailable_samples": int(invalid.sum()),
        "valid_observer_updates": int(data["rkf_observer_valid"].sum()),
        "error_difference_direction": (
            "negative means RKF-IMU has lower absolute raw observer error than ModernTCN-delta"
        ),
        "time_start_s": float(data["t_s"].iloc[0]),
        "time_end_s": float(data["t_s"].iloc[-1]),
        "paper_tex_modified": False,
        "existing_figure_outputs_modified": False,
        "rkf_sensor_seed": int(rkf_manifest["sensor_seed"]),
    }
    raw_inputs = [
        rkf_trace_path,
        rkf_debug_path,
        rkf_manifest_path,
        mtcn_trace_path,
        mtcn_debug_path,
        estimator_path,
        estimator_config_path,
        runtime_selector_path,
        trial_config_path,
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
    invalid = (
        data["rkf_observer_valid"].to_numpy(dtype=bool) == 0
    ) | (data["observer_update_available"].to_numpy(dtype=bool) == 0)
    for axis in axes:
        for start, stop in _boolean_intervals(time, invalid):
            axis.axvspan(
                start,
                stop,
                facecolor=PALETTE["invalid"],
                edgecolor="#AFAFAF",
                linewidth=0.25,
                hatch="////",
                alpha=0.32,
                zorder=0,
            )

    rkf = data["theta_rkf_deg"].to_numpy(dtype=float)
    halfwidth = data["rkf_uncertainty_halfwidth_deg"].to_numpy(dtype=float)
    ax_grade.fill_between(
        time,
        rkf - halfwidth,
        rkf + halfwidth,
        color=PALETTE["imu"],
        alpha=0.14,
        linewidth=0,
    )
    ax_grade.plot(
        time,
        rkf,
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

    for axis in axes:
        axis.set_xlim(0, 52)
        axis.set_xticks([0, 10, 20, 30, 40, 50])
        clean_axis(axis)
    ax_grade.tick_params(labelbottom=False)

    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.15),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.8, linestyle="--"),
            Patch(facecolor=PALETTE["imu"], alpha=0.14),
            Patch(
                facecolor=PALETTE["invalid"],
                edgecolor="#AFAFAF",
                hatch="////",
                alpha=0.32,
            ),
        ],
        [
            "Truth",
            "ModernTCN-delta",
            "Zhu2024 RKF-IMU",
            r"RKF uncertainty $\pm1.96\sqrt{var(\theta)}$",
            "Invalid / unavailable",
        ],
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
    figure = build_figure(data)
    artist_checks = _figure_artist_checks(figure, expected_panels=2)
    outputs = _export(figure, output_dir / STEM)
    plt.close(figure)
    output_checks = _inspect_outputs(outputs, WIDTH_MM, HEIGHT_MM, qa_dir, STEM)

    visual_status = "PASS" if approve_visual_qa else "PENDING"
    manifest = {
        "figure_id": "Fig06_rkf_imu_p2_trace_five_legend",
        "status": "CANDIDATE_NOT_YET_INSERTED_IN_TEX",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib", "RKF covariance replay"],
        "output_root_contract": "new five-legend directory only; existing figure outputs unchanged",
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
                "five_entry_legend_layout": visual_status,
                "legend_and_label_overlap": visual_status,
                "color_and_grayscale_separability": visual_status,
                "cropping_and_panel_lettering": visual_status,
            },
            "reviewer_notes": (
                "Reviewed at 89 mm in color and grayscale. The five-entry legend, two panels, "
                "replayed RKF uncertainty band, and initial unavailable interval are readable."
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
