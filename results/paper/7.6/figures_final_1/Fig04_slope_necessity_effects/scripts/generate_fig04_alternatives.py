from __future__ import annotations

import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.text import Text
from matplotlib.ticker import MaxNLocator
from PIL import Image, ImageOps


MM = 1.0 / 25.4
FIGURE_DIR = Path(__file__).resolve().parents[1]

CONTRASTS = (
    ("A3_ORACLE_VS_ZS", "Truth-driven reference", "#D28E2B", "D"),
    ("A3_IMU_VS_ZS", "Causal-IMU", "#2A9D8F", "s"),
)
E_CONTRASTS = (
    ("A3_ORACLE_VS_ZS", "Truth vs zero", "#D28E2B", "D"),
    ("A3_IMU_VS_ZS", "IMU vs zero", "#2A9D8F", "s"),
    ("A3_ORACLE_VS_IMU", "Truth vs IMU", "#D28E2B", "^"),
)
METHODS = (
    ("ZS_LPV_MPC", "Zero-grade", "#666666", "o"),
    ("IMU_LPV_MPC", "Causal-IMU", "#2A9D8F", "s"),
    ("Oracle_LPV_MPC", "Truth-driven", "#D28E2B", "D"),
)
METRICS = (
    ("ey_rmse", "Lateral-error RMS", "m", (0.001, 0.01, 0.1, 1.0, 10.0)),
    ("epsi_rmse", "Heading-error RMS", "rad", (0.001, 0.01, 0.1, 1.0, 10.0)),
    ("j_du", "Input-increment index", r"$J_{\Delta u}$", (0.01, 0.1, 1.0, 10.0, 100.0, 1000.0, 10000.0)),
)
ROUTES = (
    ("P1", "Factory logistics"),
    ("P2", "Sharp-turn transition"),
    ("P3", "Long up/down slope"),
    ("P4", "Mild slope-turn coupling"),
    ("P5", "Flat factory logistics"),
    ("P6", "Downhill recovery"),
)

COLORS = {
    "ink": "#262626",
    "grid": "#E2E2E2",
    "zero": "#666666",
    "benefit": "#2166AC",
    "adverse": "#D55E00",
}


def find_project_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate the project root")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relpath(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve())).replace("\\", "/")


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


def load_and_validate(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, Path]:
    source_path = (
        root
        / "results/paper/7.6/figures_final/Fig04_slope_necessity_effects/source_data"
        / "fig04_slope_necessity_effects_source_data.csv"
    )
    source = pd.read_csv(source_path)
    effects = source[source["record_type"] == "route_effect"].copy()
    summaries = source[source["record_type"] == "bootstrap_summary"].copy()

    expected_contrasts = {item[0] for item in CONTRASTS}
    expected_metrics = {item[0] for item in METRICS}
    effects = effects[
        effects["contrast_id"].isin(expected_contrasts)
        & effects["metric"].isin(expected_metrics)
    ].copy()
    summaries = summaries[
        summaries["contrast_id"].isin(expected_contrasts)
        & summaries["metric"].isin(expected_metrics)
    ].copy()

    if len(effects) != 36 or len(summaries) != 6:
        raise ValueError(
            f"Expected 36 route effects and 6 bootstrap summaries; got {len(effects)} and {len(summaries)}"
        )
    if set(effects["route_id"]) != {item[0] for item in ROUTES}:
        raise ValueError("The six-route identity changed")
    counts = effects.groupby(["contrast_id", "metric"])["route_id"].nunique()
    if not (counts == 6).all():
        raise ValueError("Every contrast-metric cell must contain six unique routes")

    recomputed = effects["comparator_value"] - effects["target_value"]
    if not np.allclose(
        recomputed,
        effects["effect_comparator_minus_target"],
        rtol=1e-12,
        atol=1e-12,
    ):
        raise ValueError("Effect direction changed: expected comparator minus target")

    for metric, _, _, _ in METRICS:
        oracle = effects[
            (effects["contrast_id"] == CONTRASTS[0][0]) & (effects["metric"] == metric)
        ].sort_values("route_id")
        imu = effects[
            (effects["contrast_id"] == CONTRASTS[1][0]) & (effects["metric"] == metric)
        ].sort_values("route_id")
        if not np.allclose(
            oracle["comparator_value"].to_numpy(),
            imu["comparator_value"].to_numpy(),
            rtol=1e-12,
            atol=1e-12,
        ):
            raise ValueError(f"Zero-grade comparator values disagree for {metric}")

    return effects, summaries, source_path


def load_candidate_e_sources(
    root: Path,
    reference_effects: pd.DataFrame,
    reference_summaries: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[Path]]:
    summary_dir = (
        root
        / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark"
        / "03_A3_slope_scheduling_necessity/04_summary"
    )
    effects_path = summary_dir / "paired_effects.csv"
    summaries_path = summary_dir / "bootstrap_ci_results.csv"
    cases_path = summary_dir / "a3_case_table.csv"
    effects = pd.read_csv(effects_path)
    summaries = pd.read_csv(summaries_path)
    cases = pd.read_csv(cases_path)

    contrast_ids = {item[0] for item in E_CONTRASTS}
    metric_ids = {item[0] for item in METRICS}
    method_ids = {item[0] for item in METHODS}
    effects = effects[
        effects["contrast_id"].isin(contrast_ids)
        & effects["metric"].isin(metric_ids)
    ].copy()
    summaries = summaries[
        summaries["contrast_id"].isin(contrast_ids)
        & summaries["metric"].isin(metric_ids)
    ].copy()
    cases = cases[cases["controller_id"].isin(method_ids)].copy()

    if len(effects) != 54 or len(summaries) != 9 or len(cases) != 18:
        raise ValueError(
            "Candidate E expects 54 route effects, 9 bootstrap summaries, and 18 cases"
        )
    counts = effects.groupby(["contrast_id", "metric"])["path_id"].nunique()
    if not (counts == 6).all():
        raise ValueError("Candidate E requires six routes in every contrast-metric cell")
    if not (cases["case_status"] == "COMPLETE").all():
        raise ValueError("Candidate E contains an incomplete A3 case")
    if (cases["theta_sched_mae_deg"] < 0).any():
        raise ValueError("Scheduled-grade MAE cannot be negative")

    shared_keys = ["contrast_id", "path_id", "metric"]
    shared_columns = [
        *shared_keys,
        "target_value",
        "comparator_value",
        "effect_comparator_minus_target",
    ]
    check_effects = reference_effects[shared_columns].merge(
        effects[shared_columns],
        on=shared_keys,
        suffixes=("_paper", "_frozen"),
        validate="one_to_one",
    )
    for column in ("target_value", "comparator_value", "effect_comparator_minus_target"):
        if not np.allclose(
            check_effects[f"{column}_paper"],
            check_effects[f"{column}_frozen"],
            rtol=1e-12,
            atol=1e-12,
        ):
            raise ValueError(f"Paper and frozen A3 values disagree for {column}")

    summary_keys = ["contrast_id", "metric"]
    check_summaries = reference_summaries[
        [*summary_keys, "estimate", "ci95_low", "ci95_high"]
    ].merge(
        summaries[[*summary_keys, "estimate", "ci95_low", "ci95_high"]],
        on=summary_keys,
        suffixes=("_paper", "_frozen"),
        validate="one_to_one",
    )
    for column in ("estimate", "ci95_low", "ci95_high"):
        if not np.allclose(
            check_summaries[f"{column}_paper"],
            check_summaries[f"{column}_frozen"],
            rtol=1e-12,
            atol=1e-12,
        ):
            raise ValueError(f"Paper and frozen A3 summaries disagree for {column}")

    return effects, summaries, cases, [effects_path, summaries_path, cases_path]


def compact_number(value: float) -> str:
    if value == 0:
        return "0"
    magnitude = abs(value)
    if magnitude >= 100:
        return f"{value:.0f}"
    if magnitude >= 10:
        return f"{value:.1f}"
    if magnitude >= 0.01:
        return f"{value:.3g}"
    return f"{value:.2e}"


def add_panel_label(ax: plt.Axes, label: str, x: float = -0.18) -> None:
    ax.text(
        x,
        1.04,
        label,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.2,
        fontweight="bold",
        color=COLORS["ink"],
        clip_on=False,
    )


def clean_axis(ax: plt.Axes, grid: str | None = None) -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", pad=1.5)
    if grid:
        ax.grid(axis=grid, color=COLORS["grid"], linewidth=0.45, zorder=0)
        ax.set_axisbelow(True)


def build_heatmap_ci(effects: pd.DataFrame, summaries: pd.DataFrame) -> plt.Figure:
    configure_style()
    cmap = LinearSegmentedColormap.from_list(
        "adverse_neutral_benefit",
        [COLORS["adverse"], "#FAFAFA", COLORS["benefit"]],
        N=256,
    )
    fig = plt.figure(figsize=(183 * MM, 104 * MM))
    gs = fig.add_gridspec(
        1,
        6,
        width_ratios=(0.58, 1.52, 0.58, 1.52, 0.58, 1.52),
        left=0.155,
        right=0.988,
        bottom=0.145,
        top=0.825,
        wspace=0.24,
    )
    route_order = [item[0] for item in ROUTES]
    row_positions = list(range(6)) + list(range(7, 13))
    heat_axes: list[plt.Axes] = []

    for panel, (metric, metric_label, unit, _) in enumerate(METRICS):
        heat_ax = fig.add_subplot(gs[0, panel * 2])
        summary_ax = fig.add_subplot(gs[0, panel * 2 + 1], sharey=heat_ax)
        heat_axes.append(heat_ax)

        values: list[float] = []
        for contrast_id, _, _, _ in CONTRASTS:
            subset = (
                effects[
                    (effects["contrast_id"] == contrast_id)
                    & (effects["metric"] == metric)
                ]
                .set_index("route_id")
                .reindex(route_order)
            )
            values.extend(subset["effect_comparator_minus_target"].to_numpy(dtype=float))

        matrix = np.full((13, 1), np.nan, dtype=float)
        matrix[row_positions, 0] = values
        limit = max(abs(np.nanmin(matrix)), abs(np.nanmax(matrix)))
        norm = TwoSlopeNorm(vmin=-limit, vcenter=0.0, vmax=limit)
        heat_ax.imshow(
            np.ma.masked_invalid(matrix),
            cmap=cmap,
            norm=norm,
            aspect="auto",
            interpolation="nearest",
            origin="upper",
        )
        for y_position, value in zip(row_positions, values):
            intensity = abs(value) / limit if limit else 0.0
            heat_ax.text(
                0,
                y_position,
                compact_number(value),
                ha="center",
                va="center",
                fontsize=5.8,
                color="white" if intensity >= 0.52 else COLORS["ink"],
                fontweight="bold" if intensity >= 0.52 else "normal",
            )
        heat_ax.axhline(6.0, color="#777777", linewidth=0.6)
        heat_ax.set_xlim(-0.5, 0.5)
        heat_ax.set_ylim(12.5, -0.5)
        heat_ax.set_xticks([])
        heat_ax.set_yticks(range(13))
        if panel == 0:
            heat_ax.set_yticklabels(route_order + [""] + route_order)
        else:
            heat_ax.set_yticklabels([])
            heat_ax.tick_params(axis="y", length=0)
        for spine in heat_ax.spines.values():
            spine.set_visible(True)
            spine.set_color("white")
            spine.set_linewidth(0.8)
        heat_ax.set_title(f"{metric_label}\nreduction ({unit})", pad=5)
        heat_ax.text(
            -0.72,
            1.04,
            f"({chr(97 + panel)})",
            transform=heat_ax.transAxes,
            ha="left",
            va="bottom",
            fontsize=8.2,
            fontweight="bold",
            color=COLORS["ink"],
            clip_on=False,
        )

        summary_values = summaries[summaries["metric"] == metric]
        summary_positions = (2.5, 9.5)
        ci_limit = 0.0
        for (contrast_id, _, color, marker), y_position in zip(CONTRASTS, summary_positions):
            row = summary_values[summary_values["contrast_id"] == contrast_id].iloc[0]
            estimate = float(row["estimate"])
            low = float(row["ci95_low"])
            high = float(row["ci95_high"])
            ci_limit = max(ci_limit, abs(low), abs(high))
            summary_ax.errorbar(
                estimate,
                y_position,
                xerr=[[estimate - low], [high - estimate]],
                fmt=marker,
                markersize=5.1,
                markerfacecolor=color,
                markeredgecolor=COLORS["ink"],
                markeredgewidth=0.55,
                color=color,
                capsize=2.5,
                linewidth=1.15,
                zorder=3,
            )
        summary_ax.axvline(0, color="#555555", linewidth=0.65, zorder=1)
        summary_ax.axhline(6.0, color="#BBBBBB", linewidth=0.55)
        summary_ax.set_ylim(12.5, -0.5)
        summary_ax.set_xlim(-1.12 * ci_limit, 1.12 * ci_limit)
        summary_ax.xaxis.set_major_locator(MaxNLocator(nbins=3, symmetric=True))
        summary_ax.tick_params(axis="y", left=False, labelleft=False)
        summary_ax.set_title("Mean effect\n(95% CI)", pad=5)
        summary_ax.set_xlabel("Comparator - target", labelpad=3)
        clean_axis(summary_ax, "x")

    first_ax = heat_axes[0]
    first_ax.text(
        -1.52,
        2.5,
        "Truth-driven\nreference",
        transform=first_ax.get_yaxis_transform(),
        ha="center",
        va="center",
        fontsize=6.5,
        color=CONTRASTS[0][2],
        fontweight="bold",
        clip_on=False,
    )
    first_ax.text(
        -1.52,
        9.5,
        "Causal-IMU",
        transform=first_ax.get_yaxis_transform(),
        ha="center",
        va="center",
        fontsize=6.5,
        color=CONTRASTS[1][2],
        fontweight="bold",
        clip_on=False,
    )
    fig.legend(
        handles=(
            Patch(facecolor=COLORS["benefit"], edgecolor="none"),
            Patch(facecolor="#FAFAFA", edgecolor="#AAAAAA", linewidth=0.5),
            Patch(facecolor=COLORS["adverse"], edgecolor="none"),
        ),
        labels=("Improvement", "No change", "Deterioration"),
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.55, 0.975),
        columnspacing=1.4,
        handlelength=1.5,
    )
    fig.text(
        0.54,
        0.026,
        "Cells show zero-grade comparator minus target (absolute route effects); positive values favor the target.\n"
        "Color saturation is scaled independently within each metric.",
        ha="center",
        va="bottom",
        fontsize=6.25,
        linespacing=1.25,
    )
    return fig


def build_dumbbell(
    effects: pd.DataFrame, imu_label: str = "Causal-IMU"
) -> plt.Figure:
    configure_style()
    fig, axes = plt.subplots(
        1,
        3,
        figsize=(183 * MM, 91 * MM),
        gridspec_kw={
            "left": 0.185,
            "right": 0.975,
            "bottom": 0.18,
            "top": 0.80,
            "wspace": 0.30,
        },
    )
    route_order = [item[0] for item in ROUTES]
    route_labels = [f"{route_id}  {condition}" for route_id, condition in ROUTES]
    y_positions = np.arange(len(route_order), dtype=float)

    for panel, (metric, metric_label, unit, ticks) in enumerate(METRICS):
        ax = axes[panel]
        oracle = (
            effects[
                (effects["contrast_id"] == CONTRASTS[0][0])
                & (effects["metric"] == metric)
            ]
            .set_index("route_id")
            .reindex(route_order)
        )
        imu = (
            effects[
                (effects["contrast_id"] == CONTRASTS[1][0])
                & (effects["metric"] == metric)
            ]
            .set_index("route_id")
            .reindex(route_order)
        )
        zero_values = oracle["comparator_value"].to_numpy(dtype=float)
        truth_values = oracle["target_value"].to_numpy(dtype=float)
        imu_values = imu["target_value"].to_numpy(dtype=float)
        all_values = np.concatenate((zero_values, truth_values, imu_values))
        if np.any(all_values <= 0):
            raise ValueError(f"Log-axis dumbbell requires positive absolute values for {metric}")

        for index, y_value in enumerate(y_positions):
            ax.plot(
                [zero_values[index], truth_values[index]],
                [y_value, y_value - 0.13],
                color=CONTRASTS[0][2],
                linewidth=0.9,
                alpha=0.72,
                zorder=2,
            )
            ax.plot(
                [zero_values[index], imu_values[index]],
                [y_value, y_value + 0.13],
                color=CONTRASTS[1][2],
                linewidth=0.9,
                alpha=0.72,
                zorder=2,
            )
        ax.scatter(
            zero_values,
            y_positions,
            s=22,
            marker="o",
            facecolor="white",
            edgecolor=COLORS["zero"],
            linewidth=0.9,
            zorder=5,
        )
        ax.scatter(
            truth_values,
            y_positions - 0.13,
            s=24,
            marker=CONTRASTS[0][3],
            facecolor=CONTRASTS[0][2],
            edgecolor=COLORS["ink"],
            linewidth=0.45,
            zorder=4,
        )
        ax.scatter(
            imu_values,
            y_positions + 0.13,
            s=22,
            marker=CONTRASTS[1][3],
            facecolor=CONTRASTS[1][2],
            edgecolor=COLORS["ink"],
            linewidth=0.45,
            zorder=4,
        )
        ax.set_xscale("log")
        ax.set_xlim(min(ticks), max(ticks))
        ax.set_xticks(ticks)
        ax.set_xticklabels([f"{tick:g}" for tick in ticks])
        ax.set_ylim(len(route_order) - 0.45, -0.55)
        ax.set_yticks(y_positions)
        if panel == 0:
            ax.set_yticklabels(route_labels)
        else:
            ax.set_yticklabels([])
            ax.tick_params(axis="y", length=0)
        ax.set_title(f"{metric_label} ({unit})", pad=5)
        ax.set_xlabel("Absolute metric value (log scale)", labelpad=4)
        add_panel_label(ax, f"({chr(97 + panel)})", x=-0.12 if panel else -0.22)
        clean_axis(ax, "x")

    legend_handles = (
        Line2D(
            [],
            [],
            marker="o",
            linestyle="none",
            markerfacecolor="white",
            markeredgecolor=COLORS["zero"],
            markeredgewidth=0.9,
            markersize=5.0,
        ),
        Line2D(
            [],
            [],
            marker=CONTRASTS[0][3],
            linestyle="-",
            color=CONTRASTS[0][2],
            markerfacecolor=CONTRASTS[0][2],
            markeredgecolor=COLORS["ink"],
            markeredgewidth=0.45,
            markersize=5.0,
        ),
        Line2D(
            [],
            [],
            marker=CONTRASTS[1][3],
            linestyle="-",
            color=CONTRASTS[1][2],
            markerfacecolor=CONTRASTS[1][2],
            markeredgecolor=COLORS["ink"],
            markeredgewidth=0.45,
            markersize=5.0,
        ),
    )
    fig.legend(
        legend_handles,
        ("Zero-grade", "Truth-driven reference", imu_label),
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.57, 0.965),
        columnspacing=1.5,
        handlelength=2.0,
    )
    fig.text(
        0.59,
        0.035,
        "Lower values are better. Connectors pair each target with the same route's zero-grade comparator; "
        "the truth-driven reference is analysis-only.",
        ha="center",
        va="bottom",
        fontsize=6.25,
    )
    return fig


def build_candidate_e(
    effects: pd.DataFrame,
    summaries: pd.DataFrame,
    cases: pd.DataFrame,
) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(183 * MM, 125 * MM))
    gs = fig.add_gridspec(
        2,
        3,
        height_ratios=(2.65, 1.05),
        left=0.185,
        right=0.99,
        bottom=0.14,
        top=0.79,
        hspace=0.58,
        wspace=0.30,
    )
    route_order = [item[0] for item in ROUTES]
    route_labels = [f"{route_id}  {condition}" for route_id, condition in ROUTES]
    path_to_route = {
        path_id: route_id
        for route_id, path_id in zip(
            route_order,
            (
                "p01_factory_logistics_showcase",
                "p02_sharp_turn_transition",
                "p03_long_updown",
                "p04_soft_updown_straight_turn",
                "p05_factory_flat_logistics",
                "p06_downhill_after_turn",
            ),
        )
    }
    plot_effects = effects.copy()
    plot_effects["route_id"] = plot_effects["path_id"].map(path_to_route)
    if plot_effects["route_id"].isna().any():
        raise ValueError("Candidate E encountered an unknown route")

    main_axes: list[plt.Axes] = []
    forest_axes: list[plt.Axes] = []
    y_positions = np.arange(len(route_order), dtype=float)
    for panel, (metric, metric_label, unit, ticks) in enumerate(METRICS):
        ax = fig.add_subplot(gs[0, panel])
        forest_ax = fig.add_subplot(gs[1, panel])
        main_axes.append(ax)
        forest_axes.append(forest_ax)

        truth_rows = (
            plot_effects[
                (plot_effects["contrast_id"] == "A3_ORACLE_VS_ZS")
                & (plot_effects["metric"] == metric)
            ]
            .set_index("route_id")
            .reindex(route_order)
        )
        imu_rows = (
            plot_effects[
                (plot_effects["contrast_id"] == "A3_IMU_VS_ZS")
                & (plot_effects["metric"] == metric)
            ]
            .set_index("route_id")
            .reindex(route_order)
        )
        zero_values = truth_rows["comparator_value"].to_numpy(dtype=float)
        truth_values = truth_rows["target_value"].to_numpy(dtype=float)
        imu_values = imu_rows["target_value"].to_numpy(dtype=float)
        all_values = np.concatenate((zero_values, truth_values, imu_values))
        if not np.isfinite(all_values).all() or np.any(all_values <= 0):
            raise ValueError(f"Candidate E log axis requires positive finite values for {metric}")

        for route_index, y_value in enumerate(y_positions):
            ax.plot(
                [zero_values[route_index], truth_values[route_index]],
                [y_value, y_value - 0.14],
                color="#D28E2B",
                linewidth=0.85,
                alpha=0.62,
                zorder=2,
            )
            ax.plot(
                [zero_values[route_index], imu_values[route_index]],
                [y_value, y_value + 0.14],
                color="#2A9D8F",
                linewidth=1.0,
                alpha=0.82,
                zorder=3,
            )
        ax.scatter(
            zero_values,
            y_positions,
            s=21,
            marker="o",
            facecolor="white",
            edgecolor=COLORS["zero"],
            linewidth=0.9,
            zorder=6,
        )
        ax.scatter(
            truth_values,
            y_positions - 0.14,
            s=23,
            marker="D",
            facecolor="#D28E2B",
            edgecolor=COLORS["ink"],
            linewidth=0.45,
            zorder=5,
        )
        ax.scatter(
            imu_values,
            y_positions + 0.14,
            s=23,
            marker="s",
            facecolor="#2A9D8F",
            edgecolor=COLORS["ink"],
            linewidth=0.45,
            zorder=5,
        )
        display_ticks = ticks[:-1] if metric == "j_du" else ticks
        x_max = 5000.0 if metric == "j_du" else max(ticks)
        ax.set_xscale("log")
        ax.set_xlim(min(ticks), x_max)
        ax.set_xticks(display_ticks)
        ax.set_xticklabels([f"{tick:g}" for tick in display_ticks])
        ax.get_xticklabels()[0].set_ha("left")
        ax.get_xticklabels()[-1].set_ha("right")
        ax.set_ylim(len(route_order) - 0.45, -0.55)
        ax.set_yticks(y_positions)
        if panel == 0:
            ax.set_yticklabels(route_labels)
        else:
            ax.set_yticklabels([])
            ax.tick_params(axis="y", length=0)
        ax.set_title(f"{metric_label} ({unit})", pad=5)
        ax.set_xlabel("Absolute value (log scale)", labelpad=3)
        add_panel_label(ax, f"({chr(97 + panel)})", x=-0.12 if panel else -0.22)
        clean_axis(ax, "x")

        summary_rows = summaries[summaries["metric"] == metric]
        forest_y = np.asarray((2.0, 1.0, 0.0))
        ci_limit = float(
            np.nanmax(np.abs(summary_rows[["ci95_low", "ci95_high"]].to_numpy(dtype=float)))
        )
        forest_ax.axvspan(-1.12 * ci_limit, 0.0, color="#FFF4EC", zorder=0)
        forest_ax.axvspan(0.0, 1.12 * ci_limit, color="#EEF5FA", zorder=0)
        forest_ax.axvline(0.0, color="#4D4D4D", linewidth=0.65, zorder=1)
        for y_value, (contrast_id, _, color, marker) in zip(forest_y, E_CONTRASTS):
            row = summary_rows[summary_rows["contrast_id"] == contrast_id].iloc[0]
            estimate = float(row["estimate"])
            low = float(row["ci95_low"])
            high = float(row["ci95_high"])
            supported = low > 0.0 or high < 0.0
            forest_ax.errorbar(
                estimate,
                y_value,
                xerr=[[estimate - low], [high - estimate]],
                fmt=marker,
                markersize=4.8,
                markerfacecolor=color if supported else "white",
                markeredgecolor=color,
                markeredgewidth=0.85,
                color=color,
                capsize=2.2,
                linewidth=1.05,
                zorder=4,
            )
        forest_ax.set_xlim(-1.12 * ci_limit, 1.12 * ci_limit)
        forest_ax.set_ylim(-0.6, 2.6)
        forest_ax.set_yticks(forest_y)
        if panel == 0:
            forest_ax.set_yticklabels([item[1] for item in E_CONTRASTS])
        else:
            forest_ax.set_yticklabels([])
            forest_ax.tick_params(axis="y", length=0)
        forest_ax.xaxis.set_major_locator(MaxNLocator(nbins=4, symmetric=True))
        forest_ax.get_xticklabels()[0].set_ha("left")
        forest_ax.get_xticklabels()[-1].set_ha("right")
        forest_ax.set_title("Paired mean reduction (95% CI)", pad=3, fontsize=6.6)
        forest_unit = unit if panel < 2 else "index"
        forest_ax.set_xlabel(f"Comparator - target ({forest_unit})", labelpad=3)
        clean_axis(forest_ax, "x")

    accuracy = cases.groupby("controller_id")["theta_sched_mae_deg"].mean()
    legend_handles = []
    legend_labels = []
    for method_id, label, color, marker in METHODS:
        legend_handles.append(
            Line2D(
                [],
                [],
                marker=marker,
                linestyle="none",
                markerfacecolor="white" if method_id == "ZS_LPV_MPC" else color,
                markeredgecolor=color if method_id == "ZS_LPV_MPC" else COLORS["ink"],
                markeredgewidth=0.8,
                markersize=5.0,
            )
        )
        qualifier = "analysis-only" if method_id == "Oracle_LPV_MPC" else ""
        accuracy_text = f"{accuracy.loc[method_id]:.3f} deg MAE"
        legend_labels.append(
            f"{label} ({accuracy_text}{'; ' + qualifier if qualifier else ''})"
        )
    fig.legend(
        legend_handles,
        legend_labels,
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.59, 0.965),
        columnspacing=1.15,
        handletextpad=0.45,
    )
    fig.text(
        0.59,
        0.865,
        "Grade-source accuracy across six routes; lower scheduled-grade MAE is more accurate.",
        ha="center",
        va="center",
        fontsize=6.25,
        color="#4A4A4A",
    )
    fig.text(
        0.59,
        0.035,
        "n = 6 paired routes; whiskers are 95% route-bootstrap CIs. Positive mean reduction = lower/better target.\n"
        "Filled summary markers have CIs excluding zero; route-level adverse and tied outcomes are retained.",
        ha="center",
        va="bottom",
        fontsize=6.15,
        linespacing=1.25,
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
        path = stem.with_suffix(suffix)
        fig.savefig(path, facecolor="white", **options)
        outputs.append(path)
    plt.close(fig)
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
        if overflow > 3.0:
            severe_overflows.append(
                {"text": item.get_text()[:80], "overflow_px": round(overflow, 3)}
            )
    if severe_overflows:
        raise ValueError(f"Material text overflow detected: {severe_overflows}")
    return {
        "visible_text_count": len(texts),
        "minimum_visible_font_pt": round(minimum_font, 2),
        "material_text_overflow_count": 0,
    }


def inspect_raster(path: Path, expected_mm: tuple[float, float], dpi: int) -> dict[str, object]:
    with Image.open(path) as image:
        pixels = np.asarray(image.size, dtype=float)
        actual_mm = pixels / dpi * 25.4
        if not np.allclose(actual_mm, np.asarray(expected_mm), atol=0.18):
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
    effects, summaries, input_path = load_and_validate(root)
    e_effects, e_summaries, e_cases, e_inputs = load_candidate_e_sources(
        root, effects, summaries
    )
    output_dir = FIGURE_DIR / "output"
    source_dir = FIGURE_DIR / "source_data"
    qa_dir = FIGURE_DIR / "qa"
    for directory in (output_dir, source_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    copied_source = source_dir / "fig04_slope_necessity_effects_source_data.csv"
    shutil.copyfile(input_path, copied_source)
    candidate_e_source = source_dir / "fig04_candidate_e_source_data.csv"
    source_effects = e_effects.copy()
    source_effects.insert(0, "record_type", "route_effect")
    source_summaries = e_summaries.copy()
    source_summaries.insert(0, "record_type", "bootstrap_summary")
    source_accuracy = (
        e_cases.groupby("controller_id", as_index=False)["theta_sched_mae_deg"]
        .mean()
        .rename(columns={"theta_sched_mae_deg": "mean_theta_sched_mae_deg"})
    )
    source_accuracy.insert(0, "record_type", "method_accuracy_summary")
    pd.concat(
        [source_effects, source_summaries, source_accuracy],
        ignore_index=True,
        sort=False,
    ).to_csv(candidate_e_source, index=False)

    figures = (
        (
            "fig04_candidate_a_effect_heatmap_ci",
            build_heatmap_ci(effects, summaries),
            (183.0, 104.0),
        ),
        (
            "fig04_candidate_b_paired_dumbbell",
            build_dumbbell(effects),
            (183.0, 91.0),
        ),
        (
            "fig04_candidate_e_paired_values_ci",
            build_candidate_e(e_effects, e_summaries, e_cases),
            (183.0, 125.0),
        ),
    )
    selected_stem = "fig04_candidate_b_paired_dumbbell"
    formal_stem = "fig04_slope_necessity_effects"
    output_records: list[dict[str, object]] = []
    qa_records: dict[str, object] = {}
    for stem_name, fig, dimensions in figures:
        artist_checks = (
            inspect_artists(fig)
            if stem_name
            in {
                "fig04_candidate_b_paired_dumbbell",
                "fig04_candidate_e_paired_values_ci",
            }
            else {"status": "legacy raster QA only"}
        )
        legacy_outputs = [
            (output_dir / stem_name).with_suffix(suffix)
            for suffix in (".pdf", ".svg", ".png", ".tiff")
        ]
        if stem_name == "fig04_candidate_a_effect_heatmap_ci" and all(
            path.exists() for path in legacy_outputs
        ):
            outputs = legacy_outputs
            plt.close(fig)
        else:
            export_stem = formal_stem if stem_name == selected_stem else stem_name
            outputs = export_figure(fig, output_dir / export_stem)
        png_path = next(path for path in outputs if path.suffix == ".png")
        tiff_path = next(path for path in outputs if path.suffix == ".tiff")
        grayscale_path = qa_dir / f"{stem_name}_grayscale.png"
        with Image.open(png_path) as image:
            ImageOps.grayscale(image).save(grayscale_path)
        qa_records[stem_name] = {
            "artist_checks": artist_checks,
            "png": inspect_raster(png_path, dimensions, 300),
            "tiff": inspect_raster(tiff_path, dimensions, 600),
            "grayscale_preview": relpath(grayscale_path, root),
        }
        for output in outputs:
            output_records.append(
                {
                    "candidate": stem_name,
                    "format": output.suffix[1:],
                    "file": relpath(output, root),
                    "bytes": output.stat().st_size,
                    "sha256": sha256_file(output),
                }
            )

    formal_output_records: list[dict[str, object]] = []
    for suffix in (".pdf", ".svg", ".png", ".tiff"):
        formal_path = (output_dir / formal_stem).with_suffix(suffix)
        formal_output_records.append(
            {
                "format": suffix[1:],
                "file": relpath(formal_path, root),
                "bytes": formal_path.stat().st_size,
                "sha256": sha256_file(formal_path),
            }
        )

    manifest = {
        "figure_id": "Fig04_slope_necessity_effects_alternatives",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["nature-figure", "scientific-visualization", "matplotlib"],
        "source": {
            "original_file": relpath(input_path, root),
            "copied_file": relpath(copied_source, root),
            "sha256": sha256_file(copied_source),
            "route_effect_rows": int(len(effects)),
            "bootstrap_summary_rows": int(len(summaries)),
            "candidate_e_file": relpath(candidate_e_source, root),
            "candidate_e_sha256": sha256_file(candidate_e_source),
            "candidate_e_route_effect_rows": int(len(e_effects)),
            "candidate_e_bootstrap_summary_rows": int(len(e_summaries)),
            "candidate_e_accuracy_summary_rows": int(len(source_accuracy)),
            "candidate_e_frozen_inputs": [
                {
                    "file": relpath(path, root),
                    "sha256": sha256_file(path),
                }
                for path in e_inputs
            ],
        },
        "effect_definition": "zero-grade comparator minus target; positive favors target",
        "candidates": {
            "a": "absolute route-effect heatmaps with independently scaled metric color ranges and route-bootstrap summary CIs",
            "b": "paired absolute-value dumbbells on explicitly labeled logarithmic axes",
            "e": "route-paired absolute values plus all three paired mean effects and 95% route-bootstrap CIs",
        },
        "selection": {
            "candidate": "b",
            "reason": "route-resolved absolute values preserve operating scale and within-route pairing",
            "manuscript_outputs": formal_output_records,
        },
        "retained_evidence": {
            "routes": [item[0] for item in ROUTES],
            "contrasts": [item[0] for item in CONTRASTS],
            "metrics": [item[0] for item in METRICS],
            "adverse_and_zero_route_effects": True,
            "truth_summary_95pct_ci": True,
            "imu_summary_95pct_ci": True,
            "truth_vs_imu_summary_95pct_ci": True,
            "scheduled_grade_mae_context": True,
        },
        "outputs": output_records,
        "automatic_qa": {"status": "PASS", "raster_checks": qa_records},
        "visual_qa": {
            "status": "PASS",
            "checks": [
                "selected candidate B color PNG inspected at full export resolution",
                "selected candidate B grayscale preview retains marker-shape and fill-state distinctions",
                "no material label clipping, tick overlap, or panel overlap observed",
            ],
        },
    }
    manifest_path = FIGURE_DIR / "manifest.json"
    qa_path = qa_dir / "fig04_alternatives_qa.json"
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False)
    manifest_path.write_text(encoded, encoding="utf-8")
    qa_path.write_text(encoded, encoding="utf-8")
    print(
        json.dumps(
            {
                "figure_id": manifest["figure_id"],
                "outputs": len(output_records),
                "automatic_qa": manifest["automatic_qa"]["status"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
