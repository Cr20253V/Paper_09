from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from PIL import Image, ImageOps


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 116.0
DPI = 600
DT_S = 0.01
WINDOW_START_S = 129.95
WINDOW_END_S = 144.94
WARMUP_S = 0.5
OUTPUT_STEM = "fig07_fusion_mechanism"

REFERENCE = "#222222"
MTCN_BLUE = "#0072B2"
FUSED_BLUE = "#004C6D"
OBSERVER_ORANGE = "#D55E00"
GAIN_GREEN = "#009E73"
NIS_PURPLE = "#7A5195"
ACTIVE_BLUE = "#56B4E9"
FALLBACK_GRAY = "#E6E6E6"
GRID_GRAY = "#E5E5E5"
AXIS_GRAY = "#555555"


def configure_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "DejaVu Sans", "Liberation Sans"],
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 7.2,
            "xtick.labelsize": 6.3,
            "ytick.labelsize": 6.3,
            "legend.fontsize": 6.2,
            "axes.linewidth": 0.65,
            "xtick.major.width": 0.65,
            "ytick.major.width": 0.65,
            "xtick.major.size": 3.0,
            "ytick.major.size": 3.0,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "savefig.facecolor": "white",
        }
    )


def find_project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "src").is_dir() and (parent / "results").is_dir():
            return parent
    raise RuntimeError("Could not locate the project root")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def matlab_prctile(values: np.ndarray, percentile: float) -> float:
    return float(np.percentile(values, percentile, method="hazen"))


def relative_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def load_and_align(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, object]]:
    case_dir = root / (
        "results/modern_tcn_metric_rebuild/53_moderntcn_fuzzyakf6d_fusion_rebuild/"
        "08_formal_six_path_exploratory_v7/cases/V7/seed42/"
        "p01_factory_logistics_showcase/attempts/20260801_205613_566"
    )
    runtime_path = case_dir / "node53_v7_runtime_debug.csv"
    trace_path = case_dir / "trace.csv"
    runtime = pd.read_csv(runtime_path)
    trace = pd.read_csv(trace_path)

    required_runtime = {
        "step",
        "theta_tcn",
        "theta_fuzzyakf",
        "theta_fused",
        "K_eff",
        "correction",
        "NIS",
        "fallback",
        "innovation",
        "quality_score",
        "p_help",
        "v7_gate",
    }
    required_trace = {"t_s", "theta_true", "theta_sched"}
    missing_runtime = required_runtime.difference(runtime.columns)
    missing_trace = required_trace.difference(trace.columns)
    if missing_runtime or missing_trace:
        raise ValueError(
            f"Missing columns: runtime={sorted(missing_runtime)}, trace={sorted(missing_trace)}"
        )
    if len(trace) != len(runtime) + 1:
        raise ValueError(
            f"Expected trace to contain one extra terminal sample; got {len(trace)} and {len(runtime)}"
        )
    expected_steps = np.arange(1, len(runtime) + 1)
    if not np.array_equal(runtime["step"].to_numpy(dtype=int), expected_steps):
        raise ValueError("Runtime step column is not contiguous from 1")
    trace_time = trace["t_s"].to_numpy(dtype=float)
    if not np.allclose(np.diff(trace_time), DT_S, atol=1e-12, rtol=0):
        raise ValueError("Trace time base is not uniformly sampled at 0.01 s")

    # Runtime row i (step i+1) corresponds to trace row i: t = (step - 1) * dt.
    aligned_trace = trace.iloc[: len(runtime)].reset_index(drop=True).copy()
    mapped_time = (runtime["step"].to_numpy(dtype=float) - 1.0) * DT_S
    if not np.allclose(mapped_time, aligned_trace["t_s"], atol=1e-12, rtol=0):
        raise ValueError("Runtime-to-trace row mapping failed")

    active = runtime["fallback"].to_numpy(dtype=int) == 0
    rad_to_deg = 180.0 / np.pi
    aligned = pd.DataFrame(
        {
            "time_s": aligned_trace["t_s"].to_numpy(dtype=float),
            "reference_grade_deg": aligned_trace["theta_true"].to_numpy(dtype=float)
            * rad_to_deg,
            "modern_tcn_delta_deg": runtime["theta_tcn"].to_numpy(dtype=float)
            * rad_to_deg,
            "qualified_observer_deg": runtime["theta_fuzzyakf"].to_numpy(dtype=float)
            * rad_to_deg,
            "fused_grade_deg": runtime["theta_fused"].to_numpy(dtype=float) * rad_to_deg,
            "scheduled_grade_deg": aligned_trace["theta_sched"].to_numpy(dtype=float)
            * rad_to_deg,
            "effective_gain": runtime["K_eff"].to_numpy(dtype=float),
            "correction_deg": runtime["correction"].to_numpy(dtype=float) * rad_to_deg,
            "innovation_deg": runtime["innovation"].to_numpy(dtype=float) * rad_to_deg,
            "nis": runtime["NIS"].to_numpy(dtype=float),
            "quality_score": runtime["quality_score"].to_numpy(dtype=float),
            "p_help": runtime["p_help"].to_numpy(dtype=float),
            "v7_gate": runtime["v7_gate"].to_numpy(dtype=int),
            "fallback": runtime["fallback"].to_numpy(dtype=int),
            "active": active.astype(int),
        }
    )
    if not np.isfinite(aligned.select_dtypes(include=[np.number]).to_numpy()).all():
        raise ValueError("Aligned source data contain non-finite values")

    fallback = ~active
    fallback_identity_max = float(
        np.max(
            np.abs(
                runtime.loc[fallback, "theta_fused"].to_numpy(dtype=float)
                - runtime.loc[fallback, "theta_tcn"].to_numpy(dtype=float)
            )
        )
    )
    active_reduced_error = float(
        np.mean(
            np.abs(
                runtime.loc[active, "theta_fused"].to_numpy(dtype=float)
                - aligned_trace.loc[active, "theta_true"].to_numpy(dtype=float)
            )
            < np.abs(
                runtime.loc[active, "theta_tcn"].to_numpy(dtype=float)
                - aligned_trace.loc[active, "theta_true"].to_numpy(dtype=float)
            )
        )
    )
    warmup = trace["t_s"].to_numpy(dtype=float) >= WARMUP_S
    scheduled_mae_deg = float(
        np.mean(
            np.abs(
                trace.loc[warmup, "theta_sched"].to_numpy(dtype=float)
                - trace.loc[warmup, "theta_true"].to_numpy(dtype=float)
            )
        )
        * rad_to_deg
    )
    case_summary = {
        "route": "P1 Factory logistics",
        "model_seed": 42,
        "sensor_seed": 4631,
        "runtime_samples": int(len(runtime)),
        "trace_samples": int(len(trace)),
        "sample_interval_s": DT_S,
        "alignment_rule": "runtime row i maps to trace row i; t_s=(step-1)*0.01",
        "active_fraction": float(np.mean(active)),
        "exact_fallback_fraction": float(np.mean(fallback)),
        "active_samples_with_reduced_grade_error_fraction": active_reduced_error,
        "scheduled_grade_mae_deg_after_0p5s_warmup": scheduled_mae_deg,
        "nis_p95_matlab_hazen": matlab_prctile(runtime["NIS"].to_numpy(dtype=float), 95),
        "active_k_eff_p05_matlab_hazen": matlab_prctile(
            runtime.loc[active, "K_eff"].to_numpy(dtype=float), 5
        ),
        "active_k_eff_p95_matlab_hazen": matlab_prctile(
            runtime.loc[active, "K_eff"].to_numpy(dtype=float), 95
        ),
        "fallback_identity_max_abs_rad": fallback_identity_max,
        "window_start_s": WINDOW_START_S,
        "window_end_s": WINDOW_END_S,
    }
    return aligned, trace, {
        "runtime_path": runtime_path,
        "trace_path": trace_path,
        "case_summary": case_summary,
    }


def contiguous_active_intervals(time: np.ndarray, active: np.ndarray) -> list[tuple[float, float]]:
    active = np.asarray(active, dtype=bool)
    transitions = np.diff(active.astype(int), prepend=0, append=0)
    starts = np.flatnonzero(transitions == 1)
    stops = np.flatnonzero(transitions == -1)
    intervals = []
    for start, stop in zip(starts, stops):
        left = float(time[start] - DT_S / 2.0)
        right = float(time[stop - 1] + DT_S / 2.0)
        intervals.append((left, right))
    return intervals


def style_axis(axis: plt.Axes, grid: bool = True) -> None:
    if grid:
        axis.grid(True, color=GRID_GRAY, linewidth=0.45, zorder=0)
    axis.spines["left"].set_color(AXIS_GRAY)
    axis.spines["bottom"].set_color(AXIS_GRAY)
    axis.tick_params(colors="#333333", direction="out")


def shade_active(axis: plt.Axes, intervals: list[tuple[float, float]], alpha: float = 0.12) -> None:
    for left, right in intervals:
        axis.axvspan(left, right, color=ACTIVE_BLUE, alpha=alpha, linewidth=0, zorder=0.5)


def add_state_strip(
    axis: plt.Axes,
    time: np.ndarray,
    active: np.ndarray,
    y0: float,
    y1: float,
) -> None:
    axis.axhspan(y0, y1, color=FALLBACK_GRAY, linewidth=0, zorder=1.0)
    for left, right in contiguous_active_intervals(time, active):
        axis.add_patch(
            Rectangle(
                (left, y0),
                right - left,
                y1 - y0,
                facecolor=ACTIVE_BLUE,
                edgecolor="none",
                zorder=1.2,
            )
        )


def build_figure(window: pd.DataFrame) -> tuple[plt.Figure, list[plt.Axes]]:
    configure_style()
    figure = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    grid = figure.add_gridspec(
        5,
        1,
        left=0.11,
        right=0.985,
        bottom=0.095,
        top=0.885,
        hspace=0.52,
        height_ratios=[1.72, 0.78, 0.90, 1.30, 0.18],
    )
    grade_axis = figure.add_subplot(grid[0])
    gain_axis = figure.add_subplot(grid[1], sharex=grade_axis)
    correction_axis = figure.add_subplot(grid[2], sharex=grade_axis)
    nis_axis = figure.add_subplot(grid[3], sharex=grade_axis)
    state_axis = figure.add_subplot(grid[4], sharex=grade_axis)

    time = window["time_s"].to_numpy(dtype=float)
    active = window["active"].to_numpy(dtype=bool)
    active_intervals = contiguous_active_intervals(time, active)

    shade_active(grade_axis, active_intervals)
    grade_axis.plot(time, window["reference_grade_deg"], color=REFERENCE, linewidth=1.25, zorder=7)
    grade_axis.plot(
        time,
        window["modern_tcn_delta_deg"],
        color=MTCN_BLUE,
        linestyle=(0, (5.2, 2.0)),
        linewidth=0.95,
        zorder=4,
    )
    grade_axis.plot(
        time,
        window["qualified_observer_deg"],
        color=OBSERVER_ORANGE,
        linestyle=(0, (5.0, 1.8, 1.2, 1.8)),
        linewidth=0.90,
        zorder=3,
    )
    grade_axis.plot(time, window["fused_grade_deg"], color=FUSED_BLUE, linewidth=1.35, zorder=6)
    grade_min = float(window[
        ["reference_grade_deg", "modern_tcn_delta_deg", "qualified_observer_deg", "fused_grade_deg"]
    ].min().min())
    grade_max = float(window[
        ["reference_grade_deg", "modern_tcn_delta_deg", "qualified_observer_deg", "fused_grade_deg"]
    ].max().max())
    grade_axis.set_ylim(np.floor((grade_min - 0.15) * 2) / 2, np.ceil((grade_max + 0.15) * 2) / 2)
    grade_axis.set_ylabel("Grade (deg)", labelpad=7)
    grade_axis.set_title(
        "(a) Selective and bounded grade correction",
        loc="left",
        fontweight="bold",
        pad=3,
    )
    grade_axis.text(
        1.0,
        1.025,
        "P1 Factory logistics | model seed 42",
        transform=grade_axis.transAxes,
        ha="right",
        va="bottom",
        fontsize=6.3,
        color=AXIS_GRAY,
    )
    shade_active(gain_axis, active_intervals)
    gain_axis.plot(time, window["effective_gain"], color=GAIN_GREEN, linewidth=1.05, zorder=4)
    gain_axis.set_ylim(0, 1.02)
    gain_axis.set_yticks([0, 0.5, 1.0])
    gain_axis.set_ylabel("Effective gain", labelpad=7)
    gain_axis.set_title(
        "(b) Effective gain and bounded correction",
        loc="left",
        fontweight="bold",
        pad=3,
    )

    shade_active(correction_axis, active_intervals)
    correction_axis.plot(time, window["correction_deg"], color=OBSERVER_ORANGE, linewidth=1.05, zorder=4)
    correction_axis.axhline(0.5, color="#999999", linestyle=(0, (3.0, 2.0)), linewidth=0.65, zorder=2)
    correction_axis.axhline(-0.5, color="#999999", linestyle=(0, (3.0, 2.0)), linewidth=0.65, zorder=2)
    correction_axis.text(
        WINDOW_END_S - 0.06,
        0.47,
        "+0.5 deg bound",
        ha="right",
        va="bottom",
        fontsize=5.7,
        color="#777777",
    )
    correction_axis.text(
        WINDOW_END_S - 0.06,
        -0.47,
        "-0.5 deg bound",
        ha="right",
        va="top",
        fontsize=5.7,
        color="#777777",
    )
    correction_axis.set_ylim(-0.64, 0.58)
    correction_axis.set_yticks([-0.5, 0, 0.5])
    correction_axis.set_ylabel("Correction (deg)", labelpad=7)
    add_state_strip(correction_axis, time, active, -0.635, -0.59)

    shade_active(nis_axis, active_intervals, alpha=0.09)
    nis_values = np.clip(window["nis"].to_numpy(dtype=float), 1e-4, None)
    nis_axis.plot(time, nis_values, color=NIS_PURPLE, linewidth=1.0, zorder=4)
    nis_axis.axhline(9.0, color=OBSERVER_ORANGE, linestyle=(0, (4.0, 2.2)), linewidth=0.70)
    nis_axis.axhline(25.0, color="#B24A3B", linestyle=(0, (1.5, 1.8)), linewidth=0.70)
    nis_axis.text(
        WINDOW_END_S - 0.06,
        9.0,
        "downweight 9",
        ha="right",
        va="bottom",
        fontsize=5.7,
        color=OBSERVER_ORANGE,
    )
    nis_axis.text(
        WINDOW_END_S - 0.06,
        25.0,
        "reject 25",
        ha="right",
        va="bottom",
        fontsize=5.7,
        color="#9A3D32",
    )
    nis_axis.set_yscale("log")
    nis_axis.set_ylim(0.03, 40)
    nis_axis.set_yticks([0.05, 0.1, 0.3, 1, 9, 25])
    nis_axis.set_yticklabels(["0.05", "0.1", "0.3", "1", "9", "25"])
    nis_axis.set_ylabel("NIS", labelpad=7)
    nis_axis.set_title(
        "(c) Innovation consistency and fusion state",
        loc="left",
        fontweight="bold",
        pad=3,
    )

    state_axis.set_ylim(0, 1)
    state_axis.set_yticks([])
    state_axis.set_ylabel("State", fontsize=6.0, rotation=0, ha="right", va="center", labelpad=5)
    state_axis.axhspan(0, 1, color=FALLBACK_GRAY, linewidth=0)
    for left, right in active_intervals:
        state_axis.axvspan(left, right, color=ACTIVE_BLUE, alpha=0.95, linewidth=0)
    for spine in state_axis.spines.values():
        spine.set_visible(False)
    state_axis.tick_params(axis="y", length=0)

    detail_axes = [grade_axis, gain_axis, correction_axis, nis_axis, state_axis]
    for axis in detail_axes:
        axis.set_xlim(WINDOW_START_S, WINDOW_END_S)
    for axis in [grade_axis, gain_axis, correction_axis, nis_axis]:
        style_axis(axis)
    for axis in [grade_axis, gain_axis, correction_axis, nis_axis]:
        axis.tick_params(labelbottom=False)
    state_axis.set_xticks([130, 132.5, 135, 137.5, 140, 142.5, 144.5])
    state_axis.set_xlabel("Time (s)", labelpad=2)
    state_axis.tick_params(axis="x", colors="#333333", direction="out", pad=1.5)

    handles = [
        Line2D([], [], color=REFERENCE, linewidth=1.25, label="Reference grade"),
        Line2D(
            [],
            [],
            color=MTCN_BLUE,
            linestyle=(0, (5.2, 2.0)),
            linewidth=1.0,
            label="ModernTCN-delta",
        ),
        Line2D(
            [],
            [],
            color=OBSERVER_ORANGE,
            linestyle=(0, (5.0, 1.8, 1.2, 1.8)),
            linewidth=0.95,
            label="Qualified observer",
        ),
        Line2D([], [], color=FUSED_BLUE, linewidth=1.45, label="Fused grade"),
        Patch(facecolor=ACTIVE_BLUE, alpha=0.35, edgecolor="none", label="Active correction"),
    ]
    figure.legend(
        handles=handles,
        loc="upper center",
        bbox_to_anchor=(0.535, 0.982),
        ncol=5,
        frameon=False,
        handlelength=2.5,
        columnspacing=1.15,
        handletextpad=0.50,
    )
    return figure, [grade_axis, gain_axis, correction_axis, nis_axis, state_axis]


def inspect_artists(figure: plt.Figure) -> dict[str, object]:
    figure.canvas.draw()
    renderer = figure.canvas.get_renderer()
    figure_box = figure.bbox
    visible_text = [item for item in figure.findobj(plt.Text) if item.get_visible() and item.get_text()]
    minimum_font = min(float(item.get_fontsize()) for item in visible_text)
    overflow = []
    for item in visible_text:
        box = item.get_window_extent(renderer=renderer)
        tolerance = 2.0
        if (
            box.x0 < figure_box.x0 - tolerance
            or box.y0 < figure_box.y0 - tolerance
            or box.x1 > figure_box.x1 + tolerance
            or box.y1 > figure_box.y1 + tolerance
        ):
            overflow.append(item.get_text())
    return {
        "primary_panel_count": 3,
        "minimum_visible_font_pt": round(minimum_font, 2),
        "material_text_overflow_count": len(overflow),
        "material_text_overflow": overflow,
        "status": "PASS" if minimum_font >= 5.2 and not overflow else "FAIL",
    }


def export_figure(figure: plt.Figure, output_dir: Path) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [output_dir / f"{OUTPUT_STEM}.{suffix}" for suffix in ("pdf", "svg", "png")]
    figure.savefig(outputs[0])
    figure.savefig(outputs[1])
    figure.savefig(outputs[2], dpi=DPI)
    return outputs


def inspect_exports(outputs: list[Path], qa_dir: Path) -> dict[str, object]:
    qa_dir.mkdir(parents=True, exist_ok=True)
    png_path = next(path for path in outputs if path.suffix == ".png")
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    expected_pixels = (round(WIDTH_MM * DPI / 25.4), round(HEIGHT_MM * DPI / 25.4))
    with Image.open(png_path) as image:
        actual_pixels = image.size
        grayscale = ImageOps.grayscale(image)
        grayscale.save(qa_dir / f"{OUTPUT_STEM}_grayscale.png", dpi=(DPI, DPI))
        gray_array = np.asarray(grayscale, dtype=np.uint8)
        nonwhite_fraction = float(np.mean(gray_array < 250))
    svg_root = ElementTree.parse(svg_path).getroot()
    editable_text_elements = sum(1 for element in svg_root.iter() if element.tag.endswith("text"))
    checks = {
        "requested_size_mm": [WIDTH_MM, HEIGHT_MM],
        "png_dpi": DPI,
        "png_pixels": list(actual_pixels),
        "expected_png_pixels": list(expected_pixels),
        "png_size_matches": all(
            abs(actual - expected) <= 1 for actual, expected in zip(actual_pixels, expected_pixels)
        ),
        "png_nonwhite_fraction": round(nonwhite_fraction, 5),
        "svg_editable_text_elements": editable_text_elements,
    }
    checks["status"] = (
        "PASS"
        if checks["png_size_matches"] and checks["svg_editable_text_elements"] > 0
        else "FAIL"
    )
    return checks


def write_qa_report(
    figure_dir: Path,
    summary: dict[str, object],
    artist_checks: dict[str, object],
    export_checks: dict[str, object],
    window_samples: int,
    overall_status: str,
) -> None:
    report = f"""# Fig. 7 QA Report

## Scope

- Figure generation only; no manuscript text, context, or table files were modified.
- Backend: Python 3 with pandas, NumPy, and matplotlib only for data processing, rendering, export, and visual QA.
- Figure archetype: schematic-led quantitative mechanism trace.
- Core conclusion: the Qualified observer supplies a selective and bounded correction; fallback preserves the ModernTCN-delta estimate exactly.

## Data and alignment

- Runtime samples: {summary['runtime_samples']}
- Trace samples: {summary['trace_samples']}
- Mapping: `{summary['alignment_rule']}`
- Detail window: {summary['window_start_s']:.2f}-{summary['window_end_s']:.2f} s ({window_samples} samples)
- Units: grade, innovation, and correction converted from rad to deg; gain, NIS, and state retained dimensionless.

## Numeric checks

- Active fraction: {summary['active_fraction']:.6f}
- Exact fallback fraction: {summary['exact_fallback_fraction']:.6f}
- Active samples with reduced grade error: {summary['active_samples_with_reduced_grade_error_fraction']:.6f}
- Scheduled-grade MAE after 0.5 s warm-up: {summary['scheduled_grade_mae_deg_after_0p5s_warmup']:.6f} deg
- NIS P95 (MATLAB/Hazen convention): {summary['nis_p95_matlab_hazen']:.6f}
- Active-state K_eff P05/P95: {summary['active_k_eff_p05_matlab_hazen']:.6f} / {summary['active_k_eff_p95_matlab_hazen']:.6f}
- Fallback identity maximum absolute deviation: {summary['fallback_identity_max_abs_rad']:.3e} rad

## Layout and export checks

- Artist QA: {artist_checks['status']}
- Minimum visible font: {artist_checks['minimum_visible_font_pt']:.2f} pt
- Text overflow count: {artist_checks['material_text_overflow_count']}
- Export QA: {export_checks['status']}
- Final size: {WIDTH_MM:.0f} x {HEIGHT_MM:.0f} mm
- PNG: {export_checks['png_pixels'][0]} x {export_checks['png_pixels'][1]} px at {DPI} dpi
- SVG editable text elements: {export_checks['svg_editable_text_elements']}
- Grayscale QA copy generated in `qa/`.

## Overall status

**{overall_status}**
"""
    (figure_dir / "QA_REPORT.md").write_text(report, encoding="utf-8")


def main() -> None:
    root = find_project_root()
    figure_dir = root / "results/paper/7.6/figures/Fig07_fusion_mechanism"
    output_dir = figure_dir / "output"
    source_dir = figure_dir / "source_data"
    qa_dir = figure_dir / "qa"
    source_dir.mkdir(parents=True, exist_ok=True)
    qa_dir.mkdir(parents=True, exist_ok=True)

    aligned, trace, metadata = load_and_align(root)
    window_mask = aligned["time_s"].between(WINDOW_START_S, WINDOW_END_S, inclusive="both")
    window = aligned.loc[window_mask].reset_index(drop=True)
    if len(window) != 1500:
        raise ValueError(f"Expected 1500 samples in detail window, found {len(window)}")

    summary = dict(metadata["case_summary"])
    summary["window_samples"] = int(len(window))
    summary["window_active_fraction"] = float(window["active"].mean())
    source_path = source_dir / "fig07_window_data.csv"
    summary_path = source_dir / "fig07_case_summary.json"
    window.to_csv(source_path, index=False, float_format="%.12g")
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=True), encoding="utf-8")

    figure, _ = build_figure(window)
    artist_checks = inspect_artists(figure)
    outputs = export_figure(figure, output_dir)
    plt.close(figure)
    export_checks = inspect_exports(outputs, qa_dir)

    expected_checks = {
        "active_fraction": bool(np.isclose(summary["active_fraction"], 0.059759, atol=5e-7)),
        "fallback_fraction": bool(
            np.isclose(summary["exact_fallback_fraction"], 0.940241, atol=5e-7)
        ),
        "active_error_reduction": bool(
            np.isclose(
                summary["active_samples_with_reduced_grade_error_fraction"],
                0.940776,
                atol=5e-7,
            )
        ),
        "scheduled_mae": bool(
            np.isclose(
                summary["scheduled_grade_mae_deg_after_0p5s_warmup"], 0.407417, atol=5e-7
            )
        ),
        "nis_p95": bool(np.isclose(summary["nis_p95_matlab_hazen"], 0.291554, atol=5e-7)),
        "fallback_identity": bool(summary["fallback_identity_max_abs_rad"] == 0.0),
        "window_active_fraction": bool(
            np.isclose(summary["window_active_fraction"], 0.5093333333333333, atol=1e-12)
        ),
    }
    overall_status = (
        "PASS"
        if artist_checks["status"] == "PASS"
        and export_checks["status"] == "PASS"
        and all(expected_checks.values())
        else "FAIL"
    )

    input_paths = [metadata["runtime_path"], metadata["trace_path"]]
    manifest = {
        "figure_id": "Fig07_fusion_mechanism",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "scope": "Figure generation only; no TeX, context, or table files modified.",
        "figure_contract": {
            "core_conclusion": "Qualified observer information enters only as a selective and bounded correction; fallback returns exactly to ModernTCN-delta.",
            "archetype": "schematic-led quantitative mechanism trace",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "panel_map": {
                "a": "detailed grade trajectories and active correction intervals in the prescribed window",
                "b": "effective gain, bounded correction, and local fusion state",
                "c": "log-scale NIS with fixed thresholds and active/fallback state",
            },
        },
        "inputs": [
            {
                "file": relative_path(path, root),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in input_paths
        ],
        "source_data": {
            "window_file": relative_path(source_path, root),
            "window_sha256": sha256_file(source_path),
            "summary_file": relative_path(summary_path, root),
            "summary_sha256": sha256_file(summary_path),
        },
        "outputs": [
            {
                "format": path.suffix[1:],
                "file": relative_path(path, root),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in outputs
        ],
        "automatic_qa": {
            "status": overall_status,
            "numeric_checks": expected_checks,
            "artist_checks": artist_checks,
            "export_checks": export_checks,
        },
    }
    manifest_text = json.dumps(manifest, indent=2, ensure_ascii=True)
    (figure_dir / "manifest.json").write_text(manifest_text, encoding="utf-8")
    (qa_dir / f"{OUTPUT_STEM}_qa.json").write_text(manifest_text, encoding="utf-8")
    write_qa_report(figure_dir, summary, artist_checks, export_checks, len(window), overall_status)

    if overall_status != "PASS":
        raise RuntimeError(f"Figure QA failed: {json.dumps(manifest['automatic_qa'], indent=2)}")
    print(json.dumps({"status": overall_status, "outputs": [str(path) for path in outputs]}, indent=2))


if __name__ == "__main__":
    main()
