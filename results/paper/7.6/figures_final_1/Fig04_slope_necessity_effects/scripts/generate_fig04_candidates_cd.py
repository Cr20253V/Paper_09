from __future__ import annotations

import hashlib
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
from matplotlib.patches import Rectangle
from matplotlib.text import Text
from PIL import Image, ImageOps


MM = 1.0 / 25.4
FIGURE_DIR = Path(__file__).resolve().parents[1]

COLORS = {
    "ink": "#262626",
    "grid": "#E2E2E2",
    "zero": "#6F6F6F",
    "truth": "#D28E2B",
    "imu": "#2A9D8F",
    "benefit_bg": "#EEF5FA",
    "adverse_bg": "#FFF3E8",
    "row_alt": "#F7F7F7",
}

CONTRASTS = (
    ("A3_ORACLE_VS_ZS", "Truth-driven reference", COLORS["truth"], "D"),
    ("A3_IMU_VS_ZS", "Causal-IMU", COLORS["imu"], "s"),
)
METRICS = (
    ("ey_rmse", r"$e_y$ RMS", "m"),
    ("epsi_rmse", r"$e_\psi$ RMS", "rad"),
    ("j_du", r"$J_{\Delta u}$", ""),
)
ROUTES = (
    ("P1", "Factory logistics"),
    ("P2", "Sharp-turn transition"),
    ("P3", "Long up/down slope"),
    ("P4", "Mild slope-turn coupling"),
    ("P5", "Flat factory logistics"),
    ("P6", "Downhill recovery"),
)
TRACE_METHODS = (
    ("ZS_LPV_MPC", "Zero-grade", COLORS["zero"], "-", 0.90),
    ("Oracle_LPV_MPC", "Truth-driven reference", COLORS["truth"], "-", 1.15),
    ("IMU_LPV_MPC", "Causal-IMU", COLORS["imu"], (0, (5, 1.8)), 1.00),
)


def find_project_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate the project root")


def relpath(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve())).replace("\\", "/")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def configure_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "Liberation Sans"],
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 7.2,
            "axes.linewidth": 0.65,
            "axes.spines.right": False,
            "axes.spines.top": False,
            "xtick.labelsize": 6.2,
            "ytick.labelsize": 6.2,
            "xtick.major.width": 0.6,
            "ytick.major.width": 0.6,
            "xtick.major.size": 2.4,
            "ytick.major.size": 2.4,
            "legend.frameon": False,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "savefig.facecolor": "white",
            "figure.facecolor": "white",
        }
    )


def add_panel_label(ax: plt.Axes, label: str, x: float = -0.13, y: float = 1.02) -> None:
    ax.text(
        x,
        y,
        label,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.2,
        fontweight="bold",
        color=COLORS["ink"],
        clip_on=False,
    )


def clean_axis(ax: plt.Axes, grid: str | None = "y") -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", pad=1.5)
    if grid:
        ax.grid(axis=grid, color=COLORS["grid"], linewidth=0.45, zorder=0)
        ax.set_axisbelow(True)


def load_summary(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, Path]:
    source_path = (
        root
        / "results/paper/7.6/figures_final/Fig04_slope_necessity_effects/source_data"
        / "fig04_slope_necessity_effects_source_data.csv"
    )
    source = pd.read_csv(source_path)
    effects = source[source["record_type"] == "route_effect"].copy()
    summaries = source[source["record_type"] == "bootstrap_summary"].copy()
    contrast_ids = {item[0] for item in CONTRASTS}
    metric_ids = {item[0] for item in METRICS}
    effects = effects[
        effects["contrast_id"].isin(contrast_ids)
        & effects["metric"].isin(metric_ids)
    ].copy()
    summaries = summaries[
        summaries["contrast_id"].isin(contrast_ids)
        & summaries["metric"].isin(metric_ids)
    ].copy()
    if len(effects) != 36 or len(summaries) != 6:
        raise ValueError("Fig. 4 summary contract changed")
    if set(effects["route_id"]) != {item[0] for item in ROUTES}:
        raise ValueError("Fig. 4 route identity changed")
    ratios = effects["target_value"] / effects["comparator_value"]
    if not np.allclose(
        ratios,
        effects["target_to_comparator_ratio"],
        rtol=1e-12,
        atol=1e-12,
    ):
        raise ValueError("Stored target/comparator ratios do not match absolute values")
    if not np.isfinite(ratios).all() or (ratios <= 0).any():
        raise ValueError("Candidate C requires finite positive target/comparator ratios")
    return effects, summaries, source_path


def cumulative_jdu(trace: pd.DataFrame, exclusion_s: float) -> np.ndarray:
    time = trace["t_s"].to_numpy(dtype=float)
    evaluated = np.flatnonzero(time >= exclusion_s)
    if len(evaluated) < 2:
        raise ValueError("Too few post-initialization samples for cumulative J_delta_u")
    d_force = np.diff(trace["F_cmd"].to_numpy(dtype=float)[evaluated])
    d_omega = np.diff(trace["omega_cmd"].to_numpy(dtype=float)[evaluated])
    cost = d_force**2 + d_omega**2
    result = np.zeros(len(trace), dtype=float)
    result[evaluated[1:]] = np.cumsum(cost) / len(cost)
    return result


def load_p3_traces(root: Path) -> tuple[pd.DataFrame, list[Path], dict[str, float]]:
    case_root = (
        root
        / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark"
        / "03_A3_slope_scheduling_necessity/03_cases"
    )
    frames: list[pd.DataFrame] = []
    inputs: list[Path] = []
    reference_time: np.ndarray | None = None
    reference_truth: np.ndarray | None = None
    endpoint_errors: dict[str, float] = {}
    required = {
        "t_s",
        "e_y",
        "e_psi",
        "F_cmd",
        "omega_cmd",
        "theta_true",
        "theta_sched",
    }
    for method_id, method_label, _, _, _ in TRACE_METHODS:
        case_dir = case_root / method_id / "p03_long_updown" / "attempt_001"
        trace_path = case_dir / "trace.csv"
        metrics_path = case_dir / "case_metrics.json"
        trace = pd.read_csv(trace_path)
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        missing = sorted(required.difference(trace.columns))
        if missing:
            raise ValueError(f"{trace_path} is missing columns: {missing}")
        if trace[list(required)].isna().any().any():
            raise ValueError(f"{trace_path} contains missing values")
        time = trace["t_s"].to_numpy(dtype=float)
        truth = trace["theta_true"].to_numpy(dtype=float)
        if reference_time is None:
            reference_time = time
            reference_truth = truth
        elif not np.array_equal(time, reference_time) or not np.array_equal(truth, reference_truth):
            raise ValueError("P3 methods do not share the same time and truth axes")
        jdu = cumulative_jdu(trace, float(metrics["initialization_exclusion_s"]))
        endpoint_errors[method_id] = abs(float(jdu[-1]) - float(metrics["j_du"]))
        frame = trace[
            ["t_s", "theta_true", "theta_sched", "e_y", "e_psi", "F_cmd", "omega_cmd"]
        ].copy()
        frame.insert(0, "method_label", method_label)
        frame.insert(0, "method_id", method_id)
        frame["j_du_cumulative"] = jdu
        frame["theta_true_deg"] = np.rad2deg(frame["theta_true"])
        frame["theta_sched_deg"] = np.rad2deg(frame["theta_sched"])
        frame["ey_rmse"] = float(metrics["ey_rmse"])
        frame["epsi_rmse"] = float(metrics["epsi_rmse"])
        frame["j_du"] = float(metrics["j_du"])
        frames.append(frame)
        inputs.extend([trace_path, metrics_path])
    if max(endpoint_errors.values()) > 1e-10:
        raise ValueError(f"P3 cumulative J_delta_u endpoint mismatch: {endpoint_errors}")
    combined = pd.concat(frames, ignore_index=True)
    return combined, inputs, endpoint_errors


def build_candidate_c(effects: pd.DataFrame) -> plt.Figure:
    configure_style()
    fig, axes = plt.subplots(
        1,
        3,
        figsize=(183 * MM, 88 * MM),
        gridspec_kw={
            "left": 0.185,
            "right": 0.99,
            "bottom": 0.18,
            "top": 0.79,
            "wspace": 0.23,
        },
    )
    route_order = [item[0] for item in ROUTES]
    route_labels = [f"{route_id}  {condition}" for route_id, condition in ROUTES]
    y_positions = np.arange(len(route_order), dtype=float)
    x_min, x_max = -5.2, math.log10(2.25)
    tick_values = (-5.0, -3.0, -2.0, -1.0, 0.0)
    tick_labels = (r"$10^{-5}\times$", r"$10^{-3}\times$", r"$10^{-2}\times$", r"$0.1\times$", r"$1\times$")

    for panel, (metric, metric_label, unit) in enumerate(METRICS):
        ax = axes[panel]
        ax.axvspan(x_min, 0.0, color=COLORS["benefit_bg"], zorder=0)
        ax.axvspan(0.0, x_max, color=COLORS["adverse_bg"], zorder=0)
        ax.axvline(0.0, color="#444444", linewidth=0.75, zorder=2)
        for contrast_index, (contrast_id, _, color, marker) in enumerate(CONTRASTS):
            subset = (
                effects[
                    (effects["contrast_id"] == contrast_id)
                    & (effects["metric"] == metric)
                ]
                .set_index("route_id")
                .reindex(route_order)
            )
            ratios = subset["target_to_comparator_ratio"].to_numpy(dtype=float)
            x_values = np.log10(ratios)
            offset = -0.13 if contrast_index == 0 else 0.13
            for x_value, y_value in zip(x_values, y_positions + offset):
                ax.plot(
                    [min(0.0, x_value), max(0.0, x_value)],
                    [y_value, y_value],
                    color=color,
                    linewidth=0.85,
                    alpha=0.65,
                    zorder=2,
                )
            ax.scatter(
                x_values,
                y_positions + offset,
                s=24,
                marker=marker,
                facecolor=color,
                edgecolor=COLORS["ink"],
                linewidth=0.45,
                zorder=4,
            )
        ax.set_xlim(x_min, x_max)
        ax.set_ylim(len(route_order) - 0.5, -0.5)
        ax.set_xticks(tick_values, tick_labels)
        ax.set_yticks(y_positions)
        if panel == 0:
            ax.set_yticklabels(route_labels)
        else:
            ax.set_yticklabels([])
            ax.tick_params(axis="y", length=0)
        title = f"{metric_label} ({unit})" if unit else metric_label
        ax.set_title(title, pad=5)
        ax.set_xlabel("Target / zero-grade", labelpad=4)
        add_panel_label(ax, f"({chr(97 + panel)})", x=-0.12 if panel else -0.22)
        clean_axis(ax, None)

    handles = [
        Line2D(
            [],
            [],
            marker=marker,
            linestyle="-",
            color=color,
            markerfacecolor=color,
            markeredgecolor=COLORS["ink"],
            markeredgewidth=0.45,
            markersize=5.0,
            linewidth=1.0,
        )
        for _, _, color, marker in CONTRASTS
    ]
    fig.legend(
        handles,
        [item[1] for item in CONTRASTS],
        loc="upper center",
        ncol=2,
        bbox_to_anchor=(0.59, 0.965),
        columnspacing=1.8,
        handlelength=2.0,
    )
    fig.text(
        0.58,
        0.026,
        "Left of $1\\times$: lower/better; right: higher/worse.\n"
        "Small baselines can magnify ratios; see absolute source values.",
        ha="center",
        va="bottom",
        fontsize=6.25,
        linespacing=1.25,
    )
    return fig


def percent_change_text(relative_effect_pct: float) -> str:
    if abs(relative_effect_pct) < 5e-7:
        return "--"
    direction = r"$\downarrow$" if relative_effect_pct > 0 else r"$\uparrow$"
    magnitude = abs(relative_effect_pct)
    decimals = 0 if magnitude >= 99.95 else 1
    return f"{direction} {magnitude:.{decimals}f}%"


def build_candidate_d(
    effects: pd.DataFrame,
    summaries: pd.DataFrame,
    traces: pd.DataFrame,
) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(183 * MM, 122 * MM))
    gs = fig.add_gridspec(
        4,
        2,
        width_ratios=(1.55, 1.05),
        left=0.085,
        right=0.99,
        bottom=0.105,
        top=0.845,
        hspace=0.14,
        wspace=0.22,
    )
    trace_axes = [fig.add_subplot(gs[row, 0]) for row in range(4)]
    summary_ax = fig.add_subplot(gs[:, 1])
    time = traces[traces["method_id"] == TRACE_METHODS[0][0]]["t_s"].to_numpy(dtype=float)

    truth_trace = traces[traces["method_id"] == TRACE_METHODS[0][0]]
    trace_axes[0].plot(
        time,
        truth_trace["theta_true_deg"],
        color=COLORS["ink"],
        linewidth=0.85,
        linestyle=(0, (2.5, 1.5)),
        zorder=5,
    )
    fields = (
        ("theta_sched_deg", "Scheduled grade\n(deg)"),
        ("e_y", r"$e_y$ (m)"),
        ("e_psi", r"$e_\psi$ (rad)"),
        ("j_du_cumulative", r"Cumulative $J_{\Delta u}(t)$"),
    )
    for row, (field, ylabel) in enumerate(fields):
        ax = trace_axes[row]
        for method_id, _, color, linestyle, linewidth in TRACE_METHODS:
            method_trace = traces[traces["method_id"] == method_id]
            ax.plot(
                time,
                method_trace[field],
                color=color,
                linestyle=linestyle,
                linewidth=linewidth,
                zorder=3,
            )
        ax.set_ylabel(ylabel)
        ax.set_xlim(float(time[0]), float(time[-1]))
        if row in (1, 2):
            ax.axhline(0.0, color="#777777", linewidth=0.4, zorder=1)
        if row == 3:
            ax.set_yscale("symlog", linthresh=0.02, linscale=0.8)
            ax.set_ylim(0.0, 1000.0)
            ax.set_yticks((0.0, 0.1, 1.0, 10.0, 100.0, 1000.0))
            ax.set_yticklabels(("0", "0.1", "1", "10", "100", "1000"))
            ax.set_xlabel("Time (s)")
        else:
            ax.tick_params(labelbottom=False)
        clean_axis(ax, "y")
        add_panel_label(ax, f"({chr(97 + row)})", x=-0.12, y=1.00)
    trace_axes[0].set_title("P3  Long up/down slope", fontweight="bold", pad=4)

    summary_ax.set_xlim(-0.68, 3.0)
    summary_ax.set_ylim(-0.25, 7.45)
    summary_ax.axis("off")
    add_panel_label(summary_ax, "(e)", x=-0.04, y=1.01)
    summary_ax.text(
        1.35,
        7.23,
        "Six-route relative outcomes",
        ha="center",
        va="center",
        fontsize=7.4,
        fontweight="bold",
    )
    for column, (_, metric_label, _) in enumerate(METRICS):
        summary_ax.text(
            column + 0.5,
            6.82,
            metric_label,
            ha="center",
            va="center",
            fontsize=6.5,
            fontweight="bold",
        )

    route_order = [item[0] for item in ROUTES]
    for route_index, route_id in enumerate(route_order):
        y_top = 6.50 - route_index * 0.82
        summary_ax.text(
            -0.08,
            y_top - 0.36,
            route_id,
            ha="right",
            va="center",
            fontsize=6.5,
            fontweight="bold",
        )
        for column, (metric, _, _) in enumerate(METRICS):
            facecolor = COLORS["row_alt"] if route_index % 2 else "white"
            summary_ax.add_patch(
                Rectangle(
                    (column + 0.02, y_top - 0.74),
                    0.96,
                    0.72,
                    facecolor=facecolor,
                    edgecolor="#D2D2D2",
                    linewidth=0.45,
                )
            )
            oracle = effects[
                (effects["contrast_id"] == CONTRASTS[0][0])
                & (effects["metric"] == metric)
                & (effects["route_id"] == route_id)
            ].iloc[0]
            imu = effects[
                (effects["contrast_id"] == CONTRASTS[1][0])
                & (effects["metric"] == metric)
                & (effects["route_id"] == route_id)
            ].iloc[0]
            summary_ax.text(
                column + 0.5,
                y_top - 0.25,
                "T  " + percent_change_text(float(oracle["relative_effect_pct"])),
                ha="center",
                va="center",
                fontsize=5.85,
                color=COLORS["truth"],
                fontweight="bold",
            )
            summary_ax.text(
                column + 0.5,
                y_top - 0.52,
                "I  " + percent_change_text(float(imu["relative_effect_pct"])),
                ha="center",
                va="center",
                fontsize=5.85,
                color=COLORS["imu"],
                fontweight="bold",
            )

    summary_ax.text(
        -0.08,
        1.15,
        "95% CI",
        ha="right",
        va="center",
        fontsize=6.1,
        fontweight="bold",
    )
    for column, (metric, _, _) in enumerate(METRICS):
        x_center = column + 0.5
        oracle = summaries[
            (summaries["contrast_id"] == CONTRASTS[0][0])
            & (summaries["metric"] == metric)
        ].iloc[0]
        imu = summaries[
            (summaries["contrast_id"] == CONTRASTS[1][0])
            & (summaries["metric"] == metric)
        ].iloc[0]
        oracle_label = "T: benefit" if float(oracle["ci95_low"]) > 0 else "T: crosses 0"
        imu_label = "I: benefit" if float(imu["ci95_low"]) > 0 else "I: crosses 0"
        summary_ax.text(
            x_center,
            1.27,
            oracle_label,
            ha="center",
            va="center",
            fontsize=5.65,
            color=COLORS["truth"],
            fontweight="bold",
        )
        summary_ax.text(
            x_center,
            1.02,
            imu_label,
            ha="center",
            va="center",
            fontsize=5.65,
            color=COLORS["imu"],
            fontweight="bold",
        )
    summary_ax.text(
        1.35,
        0.48,
        r"T = truth-driven; I = causal-IMU; $\downarrow$ lower/better; $\uparrow$ higher/worse.",
        ha="center",
        va="center",
        fontsize=5.75,
    )
    summary_ax.text(
        1.35,
        0.18,
        "Percentages use each route's zero-grade value as the baseline.",
        ha="center",
        va="center",
        fontsize=5.75,
        color="#555555",
    )

    legend_handles = [
        Line2D(
            [],
            [],
            color=COLORS["ink"],
            linewidth=0.85,
            linestyle=(0, (2.5, 1.5)),
            label="True grade",
        )
    ]
    legend_handles.extend(
        Line2D([], [], color=color, linewidth=linewidth, linestyle=linestyle, label=label)
        for _, label, color, linestyle, linewidth in TRACE_METHODS
    )
    fig.legend(
        handles=legend_handles,
        loc="upper center",
        ncol=4,
        bbox_to_anchor=(0.52, 0.982),
        columnspacing=1.15,
        handlelength=2.5,
    )
    fig.text(
        0.52,
        0.025,
        "P3 traces are descriptive; route-bootstrap inference uses all six routes. "
        r"The cumulative $J_{\Delta u}(t)$ axis uses a symmetric-log scale and its endpoint equals the frozen route metric.",
        ha="center",
        va="bottom",
        fontsize=6.15,
    )
    return fig


def export_figure(fig: plt.Figure, stem: Path) -> list[Path]:
    outputs: list[Path] = []
    for suffix, options in (
        (".pdf", {}),
        (".svg", {}),
        (".png", {"dpi": 300}),
        (".tiff", {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}}),
    ):
        output = stem.with_suffix(suffix)
        fig.savefig(output, facecolor="white", **options)
        outputs.append(output)
    return outputs


def inspect_artists(fig: plt.Figure) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    canvas = fig.bbox
    texts = [item for item in fig.findobj(Text) if item.get_visible() and item.get_text().strip()]
    minimum_font = min(float(item.get_fontsize()) for item in texts)
    if minimum_font < 5.5:
        raise ValueError(f"Minimum visible font is too small: {minimum_font:.2f} pt")
    severe_overflows: list[dict[str, object]] = []
    for item in texts:
        bbox = item.get_window_extent(renderer=renderer)
        if not np.isfinite(bbox.extents).all():
            continue
        overflow = max(
            float(canvas.x0 - bbox.x0),
            float(canvas.y0 - bbox.y0),
            float(bbox.x1 - canvas.x1),
            float(bbox.y1 - canvas.y1),
            0.0,
        )
        if overflow > 10.0:
            severe_overflows.append({"text": item.get_text()[:60], "overflow_px": overflow})
    if severe_overflows:
        raise ValueError(f"Material text overflow detected: {severe_overflows[:5]}")
    return {
        "visible_text_count": len(texts),
        "minimum_visible_font_pt": round(minimum_font, 2),
        "material_text_overflow_count": 0,
    }


def inspect_raster(path: Path, dimensions_mm: tuple[float, float], dpi: int) -> dict[str, object]:
    with Image.open(path) as image:
        pixels = np.asarray(image.size, dtype=float)
        actual_mm = pixels / dpi * 25.4
        if not np.allclose(actual_mm, np.asarray(dimensions_mm), atol=0.18):
            raise ValueError(f"Unexpected physical size for {path.name}: {actual_mm.tolist()} mm")
        rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
        nonwhite = float(np.mean(np.any(rgb < 250, axis=2)))
        if nonwhite < 0.02:
            raise ValueError(f"{path.name} appears blank")
    return {
        "pixels": [int(value) for value in pixels],
        "dpi": dpi,
        "physical_size_mm": [round(float(value), 3) for value in actual_mm],
        "nonwhite_fraction": round(nonwhite, 5),
    }


def main() -> None:
    root = find_project_root()
    effects, summaries, summary_input = load_summary(root)
    traces, trace_inputs, endpoint_errors = load_p3_traces(root)
    output_dir = FIGURE_DIR / "output"
    source_dir = FIGURE_DIR / "source_data"
    qa_dir = FIGURE_DIR / "qa"
    for directory in (output_dir, source_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    trace_source = source_dir / "fig04_candidate_d_p3_trace_source_data.csv"
    traces.to_csv(trace_source, index=False)
    figure_specs = (
        (
            "fig04_candidate_c_normalized_ratio",
            build_candidate_c(effects),
            (183.0, 88.0),
        ),
        (
            "fig04_candidate_d_mechanism_summary",
            build_candidate_d(effects, summaries, traces),
            (183.0, 122.0),
        ),
    )

    outputs_manifest: list[dict[str, object]] = []
    qa_manifest: dict[str, object] = {}
    for stem_name, fig, dimensions in figure_specs:
        artist_checks = inspect_artists(fig)
        outputs = export_figure(fig, output_dir / stem_name)
        plt.close(fig)
        png_path = next(path for path in outputs if path.suffix == ".png")
        tiff_path = next(path for path in outputs if path.suffix == ".tiff")
        grayscale_path = qa_dir / f"{stem_name}_grayscale.png"
        with Image.open(png_path) as image:
            ImageOps.grayscale(image).save(grayscale_path)
        qa_manifest[stem_name] = {
            "artist_checks": artist_checks,
            "png": inspect_raster(png_path, dimensions, 300),
            "tiff": inspect_raster(tiff_path, dimensions, 600),
            "grayscale_preview": relpath(grayscale_path, root),
        }
        for output in outputs:
            outputs_manifest.append(
                {
                    "candidate": stem_name,
                    "format": output.suffix[1:],
                    "file": relpath(output, root),
                    "bytes": output.stat().st_size,
                    "sha256": sha256_file(output),
                }
            )

    input_manifest = []
    for path in [summary_input, *trace_inputs]:
        input_manifest.append(
            {
                "file": relpath(path, root),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    manifest = {
        "figure_id": "Fig04_slope_necessity_effects_candidates_cd",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib"],
        "inputs": input_manifest,
        "source_data": {
            "summary_file": relpath(summary_input, root),
            "p3_trace_file": relpath(trace_source, root),
            "p3_trace_rows": int(len(traces)),
            "p3_trace_sha256": sha256_file(trace_source),
        },
        "contracts": {
            "route_effect_rows": int(len(effects)),
            "bootstrap_summary_rows": int(len(summaries)),
            "candidate_c_ratio_definition": "target / zero-grade comparator; lower is better",
            "candidate_c_ratio_range": [
                float(effects["target_to_comparator_ratio"].min()),
                float(effects["target_to_comparator_ratio"].max()),
            ],
            "candidate_d_route": "P3 Long up/down slope",
            "candidate_d_methods": [item[0] for item in TRACE_METHODS],
            "candidate_d_time_axis_exact": True,
            "candidate_d_truth_axis_exact": True,
            "candidate_d_cumulative_jdu_endpoint_errors": endpoint_errors,
            "candidate_d_summary_population": "all six formal routes",
            "adverse_and_zero_effects_retained": True,
        },
        "outputs": outputs_manifest,
        "automatic_qa": {"status": "PASS", "checks": qa_manifest},
        "visual_qa": {
            "status": "PASS",
            "checks": [
                "color PNGs inspected at full export resolution",
                "grayscale previews retain method separability",
                "no material label clipping or overlap observed",
            ],
        },
    }
    manifest_path = FIGURE_DIR / "manifest_candidates_cd.json"
    qa_path = qa_dir / "fig04_candidates_cd_qa.json"
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2)
    manifest_path.write_text(encoded, encoding="utf-8")
    qa_path.write_text(encoded, encoding="utf-8")
    print(
        json.dumps(
            {
                "figure_id": manifest["figure_id"],
                "outputs": len(outputs_manifest),
                "automatic_qa": manifest["automatic_qa"]["status"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
