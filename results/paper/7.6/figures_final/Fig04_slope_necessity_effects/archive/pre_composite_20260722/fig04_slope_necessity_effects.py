"""Generate Fig. 4: paired effects of grade-scheduling sources.

The three-panel forest plot retains all six frozen route-level effects and overlays
the frozen route-bootstrap mean and 95% confidence interval for each contrast.
Effects are comparator minus target, so positive values favor the target controller.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.ticker import MaxNLocator
from pdf2image import convert_from_path
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
SHARED_STYLE_DIR = SCRIPT_DIR.parents[1] / "shared"
sys.dont_write_bytecode = True
if str(SHARED_STYLE_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_STYLE_DIR))

from style import PALETTE, add_panel_label, apply_publication_style


MM_PER_INCH = 25.4
POINTS_PER_INCH = 72.0
FIGURE_WIDTH_MM = 183.0
FIGURE_HEIGHT_MM = 72.0
PDF_QA_DPI = 200

PAIRED_EFFECTS_FILE = (
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
    "03_A3_slope_scheduling_necessity/04_summary/paired_effects.csv"
)
BOOTSTRAP_CI_FILE = (
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
    "03_A3_slope_scheduling_necessity/04_summary/bootstrap_ci_results.csv"
)

CONTRASTS = {
    "A3_ORACLE_VS_ZS": {
        "label": "Oracle vs ZS",
        "target": "Oracle_LPV_MPC",
        "comparator": "ZS_LPV_MPC",
        "color": PALETTE["oracle"],
        "marker": "D",
        "y": 1.0,
    },
    "A3_IMU_VS_ZS": {
        "label": "IMU vs ZS",
        "target": "IMU_LPV_MPC",
        "comparator": "ZS_LPV_MPC",
        "color": PALETTE["imu"],
        "marker": "^",
        "y": 0.0,
    },
}

METRICS = {
    "ey_rmse": {
        "title": r"Lateral error, $e_y$ RMS (m)",
        "label": "Lateral error RMS",
        "unit_original": "m",
        "unit_plot": "m",
        "scale": 1.0,
    },
    "epsi_rmse": {
        "title": r"Heading error, $e_\psi$ RMS (deg)",
        "label": "Heading error RMS",
        "unit_original": "rad",
        "unit_plot": "deg",
        "scale": 180.0 / np.pi,
    },
    "j_du": {
        "title": r"Input increment, $J_{\Delta u}$",
        "label": "Input-increment index",
        "unit_original": "index",
        "unit_plot": "index",
        "scale": 1.0,
    },
}

PATH_LABELS = {
    "p01_factory_logistics_showcase": "P1",
    "p02_sharp_turn_transition": "P2",
    "p03_long_updown": "P3",
    "p04_soft_updown_straight_turn": "P4",
    "p05_factory_flat_logistics": "P5",
    "p06_downhill_after_turn": "P6",
}

# Fixed offsets separate route observations without moving them along the effect axis.
ROUTE_Y_OFFSETS = dict(zip(PATH_LABELS, np.linspace(-0.20, 0.20, len(PATH_LABELS))))


@dataclass(frozen=True)
class FigureData:
    route_effects: pd.DataFrame
    summaries: pd.DataFrame
    source_table: pd.DataFrame


def find_project_root() -> Path:
    """Locate the repository root independently of the current working directory."""
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate the project root containing data/ and results/.")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _require_columns(frame: pd.DataFrame, required: set[str], source: Path) -> None:
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(f"{source}: missing required columns {missing}.")


def _build_source_table(route_effects: pd.DataFrame, summaries: pd.DataFrame) -> pd.DataFrame:
    route_rows: list[dict[str, object]] = []
    for row in route_effects.itertuples(index=False):
        metric_spec = METRICS[row.metric]
        scale = float(metric_spec["scale"])
        route_rows.append(
            {
                "record_type": "route_effect",
                "contrast_id": row.contrast_id,
                "contrast_label": CONTRASTS[row.contrast_id]["label"],
                "target": row.target,
                "comparator": row.comparator,
                "metric": row.metric,
                "metric_label": metric_spec["label"],
                "original_unit": metric_spec["unit_original"],
                "display_unit": metric_spec["unit_plot"],
                "path_id": row.path_id,
                "path_label": PATH_LABELS[row.path_id],
                "target_value_original": row.target_value,
                "comparator_value_original": row.comparator_value,
                "effect_original": row.effect_comparator_minus_target,
                "effect_display": row.effect_comparator_minus_target * scale,
                "mean_estimate_display": np.nan,
                "bootstrap_mean_display": np.nan,
                "ci95_low_display": np.nan,
                "ci95_high_display": np.nan,
                "n_paths": np.nan,
                "bootstrap_iterations": np.nan,
                "bootstrap_random_seed": np.nan,
                "positive_favors_target": bool(row.positive_favors_target),
            }
        )

    summary_rows: list[dict[str, object]] = []
    for row in summaries.itertuples(index=False):
        metric_spec = METRICS[row.metric]
        scale = float(metric_spec["scale"])
        summary_rows.append(
            {
                "record_type": "bootstrap_summary",
                "contrast_id": row.contrast_id,
                "contrast_label": CONTRASTS[row.contrast_id]["label"],
                "target": row.target,
                "comparator": row.comparator,
                "metric": row.metric,
                "metric_label": metric_spec["label"],
                "original_unit": metric_spec["unit_original"],
                "display_unit": metric_spec["unit_plot"],
                "path_id": "",
                "path_label": "",
                "target_value_original": np.nan,
                "comparator_value_original": np.nan,
                "effect_original": row.estimate,
                "effect_display": row.estimate * scale,
                "mean_estimate_display": row.estimate * scale,
                "bootstrap_mean_display": row.bootstrap_mean * scale,
                "ci95_low_display": row.ci95_low * scale,
                "ci95_high_display": row.ci95_high * scale,
                "n_paths": int(row.n_paths),
                "bootstrap_iterations": int(row.iterations),
                "bootstrap_random_seed": int(row.random_seed),
                "positive_favors_target": True,
            }
        )

    columns = list(route_rows[0])
    return pd.DataFrame(route_rows + summary_rows, columns=columns)


def load_source_data(project_root: Path | None = None) -> FigureData:
    """Load and filter the two frozen A3 source tables."""
    root = project_root or find_project_root()
    paired_path = root / PAIRED_EFFECTS_FILE
    ci_path = root / BOOTSTRAP_CI_FILE
    if not paired_path.is_file():
        raise FileNotFoundError(paired_path)
    if not ci_path.is_file():
        raise FileNotFoundError(ci_path)

    route_effects = pd.read_csv(paired_path)
    summaries = pd.read_csv(ci_path)
    _require_columns(
        route_effects,
        {
            "contrast_id",
            "target",
            "comparator",
            "path_id",
            "metric",
            "target_value",
            "comparator_value",
            "effect_comparator_minus_target",
            "positive_favors_target",
        },
        paired_path,
    )
    _require_columns(
        summaries,
        {
            "contrast_id",
            "target",
            "comparator",
            "metric",
            "estimate",
            "bootstrap_mean",
            "ci95_low",
            "ci95_high",
            "iterations",
            "random_seed",
            "n_paths",
        },
        ci_path,
    )

    route_effects = route_effects.loc[
        route_effects["contrast_id"].isin(CONTRASTS)
        & route_effects["metric"].isin(METRICS)
    ].copy()
    summaries = summaries.loc[
        summaries["contrast_id"].isin(CONTRASTS)
        & summaries["metric"].isin(METRICS)
    ].copy()
    route_effects["contrast_id"] = pd.Categorical(
        route_effects["contrast_id"], categories=CONTRASTS, ordered=True
    )
    route_effects["metric"] = pd.Categorical(
        route_effects["metric"], categories=METRICS, ordered=True
    )
    summaries["contrast_id"] = pd.Categorical(
        summaries["contrast_id"], categories=CONTRASTS, ordered=True
    )
    summaries["metric"] = pd.Categorical(
        summaries["metric"], categories=METRICS, ordered=True
    )
    route_effects = route_effects.sort_values(
        ["metric", "contrast_id", "path_id"]
    ).reset_index(drop=True)
    summaries = summaries.sort_values(["metric", "contrast_id"]).reset_index(drop=True)
    source_table = _build_source_table(route_effects, summaries)
    data = FigureData(route_effects, summaries, source_table)
    validate_source_data(data)
    return data


def validate_source_data(data: FigureData) -> None:
    """Enforce the frozen contrasts, metrics, route count, and CI definition."""
    raw = data.route_effects
    ci = data.summaries
    expected_pairs = {(contrast, metric) for contrast in CONTRASTS for metric in METRICS}
    observed_raw = set(zip(raw["contrast_id"].astype(str), raw["metric"].astype(str)))
    observed_ci = set(zip(ci["contrast_id"].astype(str), ci["metric"].astype(str)))
    if observed_raw != expected_pairs or observed_ci != expected_pairs:
        raise ValueError("The filtered data do not contain every required contrast-metric pair.")

    numeric_raw = raw[
        ["target_value", "comparator_value", "effect_comparator_minus_target"]
    ].to_numpy(dtype=float)
    numeric_ci = ci[
        ["estimate", "bootstrap_mean", "ci95_low", "ci95_high"]
    ].to_numpy(dtype=float)
    if not np.isfinite(numeric_raw).all() or not np.isfinite(numeric_ci).all():
        raise ValueError("Non-finite values were found in the plotting fields.")

    recomputed_effect = raw["comparator_value"] - raw["target_value"]
    if not np.allclose(
        raw["effect_comparator_minus_target"], recomputed_effect, rtol=1e-10, atol=1e-12
    ):
        raise ValueError("A route effect does not equal comparator minus target.")
    if not raw["positive_favors_target"].astype(bool).all():
        raise ValueError("The positive-effect direction flag changed in the frozen table.")

    expected_paths = set(PATH_LABELS)
    for (contrast, metric), group in raw.groupby(
        ["contrast_id", "metric"], observed=True, sort=False
    ):
        if group.shape[0] != 6 or set(group["path_id"]) != expected_paths:
            raise ValueError(f"{contrast}/{metric}: expected exactly the six frozen routes.")
        contrast_spec = CONTRASTS[str(contrast)]
        if set(group["target"]) != {contrast_spec["target"]}:
            raise ValueError(f"{contrast}: target controller changed.")
        if set(group["comparator"]) != {contrast_spec["comparator"]}:
            raise ValueError(f"{contrast}: comparator controller changed.")

        summary = ci.loc[
            (ci["contrast_id"].astype(str) == str(contrast))
            & (ci["metric"].astype(str) == str(metric))
        ].iloc[0]
        route_mean = float(group["effect_comparator_minus_target"].mean())
        if not np.isclose(route_mean, float(summary["estimate"]), rtol=1e-10, atol=1e-12):
            raise ValueError(f"{contrast}/{metric}: frozen estimate is not the route mean.")

    if not (ci["n_paths"].astype(int) == 6).all():
        raise ValueError("Bootstrap summaries must use six routes.")
    if not (ci["iterations"].astype(int) == 10000).all():
        raise ValueError("Bootstrap iteration count changed from 10,000.")
    if not (ci["random_seed"].astype(int) == 20260715).all():
        raise ValueError("Bootstrap random seed changed from 20260715.")
    if not ((ci["ci95_low"] <= ci["estimate"]) & (ci["estimate"] <= ci["ci95_high"])).all():
        raise ValueError("A frozen mean estimate falls outside its confidence interval.")
    if data.source_table.shape[0] != 42:
        raise ValueError("The tidy source table must contain 36 route rows and 6 summaries.")


def _set_effect_xlim(ax, raw_values: np.ndarray, ci_low: np.ndarray, ci_high: np.ndarray) -> None:
    values = np.concatenate([raw_values, ci_low, ci_high, np.array([0.0])])
    low = float(values.min())
    high = float(values.max())
    span = high - low
    padding = max(span * 0.08, 0.05 if span < 1.0 else 0.0)
    ax.set_xlim(low - padding, high + padding)


def _style_axis(ax) -> None:
    ax.set_ylim(-0.48, 1.48)
    ax.set_yticks([1.0, 0.0], ["Oracle vs ZS", "IMU vs ZS"])
    ax.tick_params(axis="both", direction="out", pad=2.0)
    ax.spines["left"].set_visible(False)
    ax.spines["bottom"].set_color("#555555")
    ax.axvline(0.0, color=PALETTE["truth"], linewidth=0.85, linestyle=(0, (3, 2)), zorder=0)
    ax.grid(axis="x", color=PALETTE["grid"], linewidth=0.55, alpha=0.95)
    ax.set_axisbelow(True)
    ax.xaxis.set_major_locator(MaxNLocator(nbins=5, min_n_ticks=4))


def build_figure(data: FigureData):
    """Create the double-column, three-panel paired-effect forest plot."""
    validate_source_data(data)
    apply_publication_style()
    fig, axes = plt.subplots(
        1,
        3,
        figsize=(FIGURE_WIDTH_MM / MM_PER_INCH, FIGURE_HEIGHT_MM / MM_PER_INCH),
        facecolor="white",
    )
    fig.subplots_adjust(left=0.095, right=0.988, bottom=0.23, top=0.76, wspace=0.42)

    for panel_index, (ax, (metric, metric_spec)) in enumerate(zip(axes, METRICS.items())):
        raw_metric = data.route_effects.loc[
            data.route_effects["metric"].astype(str) == metric
        ]
        ci_metric = data.summaries.loc[data.summaries["metric"].astype(str) == metric]
        scale = float(metric_spec["scale"])

        for contrast, contrast_spec in CONTRASTS.items():
            route_group = raw_metric.loc[
                raw_metric["contrast_id"].astype(str) == contrast
            ].sort_values("path_id")
            y_values = np.array(
                [contrast_spec["y"] + ROUTE_Y_OFFSETS[path] for path in route_group["path_id"]]
            )
            x_values = route_group["effect_comparator_minus_target"].to_numpy() * scale
            ax.scatter(
                x_values,
                y_values,
                s=22,
                marker=contrast_spec["marker"],
                facecolor=contrast_spec["color"],
                edgecolor="white",
                linewidth=0.45,
                alpha=0.66,
                zorder=3,
            )

            summary = ci_metric.loc[
                ci_metric["contrast_id"].astype(str) == contrast
            ].iloc[0]
            mean = float(summary["estimate"]) * scale
            low = float(summary["ci95_low"]) * scale
            high = float(summary["ci95_high"]) * scale
            ax.errorbar(
                mean,
                contrast_spec["y"],
                xerr=np.array([[mean - low], [high - mean]]),
                fmt=contrast_spec["marker"],
                markersize=6.2,
                markerfacecolor=contrast_spec["color"],
                markeredgecolor=PALETTE["truth"],
                markeredgewidth=0.65,
                ecolor=contrast_spec["color"],
                elinewidth=1.45,
                capsize=3.0,
                capthick=1.1,
                zorder=5,
            )

        _set_effect_xlim(
            ax,
            raw_metric["effect_comparator_minus_target"].to_numpy() * scale,
            ci_metric["ci95_low"].to_numpy() * scale,
            ci_metric["ci95_high"].to_numpy() * scale,
        )
        _style_axis(ax)
        ax.set_title(metric_spec["title"], fontsize=7.2, fontweight="bold", pad=5.0)
        add_panel_label(ax, f"({chr(ord('a') + panel_index)})", x=-0.18, y=1.08)

    legend_handles = [
        Line2D(
            [0],
            [0],
            linestyle="none",
            marker="o",
            markersize=4.4,
            markerfacecolor="#777777",
            markeredgecolor="white",
            alpha=0.66,
            label="Route-level effect (n = 6)",
        ),
        Line2D(
            [0, 1],
            [0, 0],
            color="#777777",
            linewidth=1.4,
            marker="o",
            markersize=5.8,
            markerfacecolor="#777777",
            markeredgecolor=PALETTE["truth"],
            label="Mean and 95% bootstrap CI",
        ),
    ]
    fig.legend(
        handles=legend_handles,
        loc="upper center",
        bbox_to_anchor=(0.53, 0.965),
        ncol=2,
        columnspacing=1.6,
        handlelength=2.0,
        handletextpad=0.55,
        fontsize=6.8,
        frameon=False,
    )
    fig.supxlabel(
        "Paired effect = comparator - target (positive favors target)",
        x=0.54,
        y=0.065,
        fontsize=7.0,
    )
    return fig, axes


def export_figure(fig, output_stem: Path) -> list[Path]:
    """Export editable vectors and fixed-canvas raster versions."""
    output_stem.parent.mkdir(parents=True, exist_ok=True)
    outputs = {
        ".svg": {},
        ".pdf": {},
        ".tiff": {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}},
        ".png": {"dpi": 300},
    }
    saved: list[Path] = []
    for suffix, options in outputs.items():
        destination = output_stem.with_suffix(suffix)
        fig.savefig(destination, facecolor="white", **options)
        saved.append(destination)
    return saved


def _parse_pdf_page_size(pdf_path: Path) -> list[float]:
    result = subprocess.run(
        ["pdfinfo", str(pdf_path)], capture_output=True, text=True, check=True
    )
    match = re.search(r"Page size:\s+([0-9.]+) x ([0-9.]+) pts", result.stdout)
    if not match:
        raise ValueError("pdfinfo did not report a parseable page size.")
    size_points = np.array([float(match.group(1)), float(match.group(2))])
    return [round(float(value), 3) for value in size_points / POINTS_PER_INCH * MM_PER_INCH]


def _inspect_pdf_fonts(pdf_path: Path) -> dict[str, object]:
    result = subprocess.run(
        ["pdffonts", str(pdf_path)], capture_output=True, text=True, check=True
    )
    font_lines = [line for line in result.stdout.splitlines()[2:] if line.strip()]
    if not font_lines:
        raise ValueError("pdffonts found no embedded fonts.")
    has_type3 = any("Type 3" in line for line in font_lines)
    embedded = all(re.search(r"\byes\s+yes\b", line) is not None for line in font_lines)
    if has_type3 or not embedded:
        raise ValueError("PDF fonts are not fully embedded editable TrueType fonts.")
    return {
        "status": "PASS",
        "font_count": len(font_lines),
        "all_embedded": embedded,
        "type3_fonts": has_type3,
        "font_rows": font_lines,
    }


def inspect_outputs(outputs: list[Path], qa_preview_path: Path) -> dict[str, object]:
    """Verify canvas geometry, editable text, PDF fonts, and rendered content."""
    expected_mm = np.array([FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM], dtype=float)
    raster_geometry: dict[str, object] = {}
    for suffix, expected_dpi in ((".png", 300), (".tiff", 600)):
        path = next(item for item in outputs if item.suffix == suffix)
        with Image.open(path) as image:
            pixels = np.array(image.size, dtype=float)
            actual_mm = pixels / expected_dpi * MM_PER_INCH
            if not np.allclose(actual_mm, expected_mm, atol=0.15):
                raise ValueError(f"{path.name}: unexpected physical canvas {actual_mm.tolist()} mm.")
            raster_geometry[suffix.lstrip(".")] = {
                "pixels": [int(value) for value in pixels],
                "dpi": expected_dpi,
                "physical_size_mm": [round(float(value), 3) for value in actual_mm],
            }

    svg_path = next(item for item in outputs if item.suffix == ".svg")
    svg_text = svg_path.read_text(encoding="utf-8")
    svg_text_elements = len(re.findall(r"<text\b", svg_text))
    if svg_text_elements < 10:
        raise ValueError("SVG does not retain the expected editable text elements.")

    pdf_path = next(item for item in outputs if item.suffix == ".pdf")
    pdf_size_mm = _parse_pdf_page_size(pdf_path)
    if not np.allclose(pdf_size_mm, expected_mm, atol=0.15):
        raise ValueError(f"PDF page is {pdf_size_mm} mm, expected {expected_mm.tolist()} mm.")
    pdf_fonts = _inspect_pdf_fonts(pdf_path)

    qa_preview_path.parent.mkdir(parents=True, exist_ok=True)
    pages = convert_from_path(str(pdf_path), dpi=PDF_QA_DPI, fmt="png")
    if len(pages) != 1:
        raise ValueError(f"Expected a one-page PDF, found {len(pages)} pages.")
    pages[0].save(qa_preview_path, format="PNG")
    with Image.open(qa_preview_path) as preview:
        rgb = np.asarray(preview.convert("RGB"), dtype=np.uint8)
        non_white_fraction = float(np.mean(np.any(rgb < 248, axis=2)))
        expected_pixels = expected_mm / MM_PER_INCH * PDF_QA_DPI
        if not np.allclose(np.array(preview.size), expected_pixels, atol=2.0):
            raise ValueError("The rendered PDF preview has an unexpected aspect or page size.")
        if non_white_fraction < 0.02:
            raise ValueError("The rendered PDF appears blank.")

    return {
        "status": "PASS",
        "requested_size_mm": [FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM],
        "raster_exports": raster_geometry,
        "svg_editable_text": {"status": "PASS", "text_element_count": svg_text_elements},
        "pdf_page_size_mm": pdf_size_mm,
        "pdf_fonts": pdf_fonts,
        "pdf_render": {
            "status": "PASS",
            "preview_file": qa_preview_path.name,
            "pixels": list(pages[0].size),
            "dpi": PDF_QA_DPI,
            "non_white_fraction": round(non_white_fraction, 6),
        },
    }


def write_qa_report(
    data: FigureData,
    root: Path,
    input_paths: list[Path],
    source_csv: Path,
    outputs: list[Path],
    output_checks: dict[str, object],
    qa_path: Path,
) -> None:
    """Write the figure contract, statistical audit, and export checks."""
    pair_checks: list[dict[str, object]] = []
    for contrast in CONTRASTS:
        for metric in METRICS:
            raw = data.route_effects.loc[
                (data.route_effects["contrast_id"].astype(str) == contrast)
                & (data.route_effects["metric"].astype(str) == metric)
            ]
            summary = data.summaries.loc[
                (data.summaries["contrast_id"].astype(str) == contrast)
                & (data.summaries["metric"].astype(str) == metric)
            ].iloc[0]
            scale = float(METRICS[metric]["scale"])
            pair_checks.append(
                {
                    "contrast_id": contrast,
                    "metric": metric,
                    "display_unit": METRICS[metric]["unit_plot"],
                    "route_count": int(raw.shape[0]),
                    "route_effect_min_display": float(
                        raw["effect_comparator_minus_target"].min() * scale
                    ),
                    "route_effect_max_display": float(
                        raw["effect_comparator_minus_target"].max() * scale
                    ),
                    "mean_estimate_display": float(summary["estimate"] * scale),
                    "ci95_display": [
                        float(summary["ci95_low"] * scale),
                        float(summary["ci95_high"] * scale),
                    ],
                    "ci_excludes_zero": bool(
                        summary["ci95_low"] > 0 or summary["ci95_high"] < 0
                    ),
                }
            )

    report = {
        "figure_id": "fig04_slope_necessity_effects",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "figure_contract": {
            "archetype": "quantitative grid",
            "core_conclusion": (
                "Oracle grade scheduling has positive mean effects with 95% intervals "
                "above zero for all three frozen six-route metrics, whereas the causal "
                "IMU effect depends on the metric."
            ),
            "final_size_mm_requested": [FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM],
            "panel_map": {
                "a": "paired lateral-error RMS effects",
                "b": "paired heading-error RMS effects",
                "c": "paired input-increment effects",
            },
            "hero_evidence": "all six route-level effects per contrast and metric",
            "summary_evidence": "frozen route-bootstrap mean and percentile 95% CI",
            "reviewer_risks_addressed": [
                "effect direction is explicit and fixed as comparator minus target",
                "route, not time sample, is the statistical unit",
                "all zero, adverse, and extreme route effects are retained",
                "Oracle is a non-deployable analysis reference",
            ],
        },
        "validation": {
            "status": "PASS",
            "route_effect_rows": int(data.route_effects.shape[0]),
            "bootstrap_summary_rows": int(data.summaries.shape[0]),
            "source_data_rows": int(data.source_table.shape[0]),
            "contrasts": list(CONTRASTS),
            "metrics": list(METRICS),
            "routes_per_contrast_metric": 6,
            "statistical_unit": "route",
            "center_statistic": "arithmetic mean of paired route effects",
            "interval": "frozen percentile 95% bootstrap confidence interval",
            "bootstrap_iterations": 10000,
            "bootstrap_random_seed": 20260715,
            "effect_definition": "comparator minus target; positive favors target",
            "heading_display_conversion": "rad multiplied by 180/pi to deg",
            "output_checks": output_checks,
        },
        "input_sources": [
            {
                "file": str(path.relative_to(root)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in input_paths
        ],
        "source_data": {
            "file": str(source_csv.relative_to(root)).replace("\\", "/"),
            "bytes": source_csv.stat().st_size,
            "sha256": sha256_file(source_csv),
        },
        "pair_checks": pair_checks,
        "outputs": [
            {
                "file": str(path.relative_to(root)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in outputs
        ],
    }
    qa_path.parent.mkdir(parents=True, exist_ok=True)
    qa_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    root = find_project_root()
    figure_root = root / "results/paper/7.6/figures_final/Fig04_slope_necessity_effects"
    source_csv = (
        figure_root / "source_data/fig04_slope_necessity_effects_source_data.csv"
    )
    output_stem = figure_root / "output/fig04_slope_necessity_effects"
    qa_path = figure_root / "qa/fig04_slope_necessity_effects_qa.json"
    qa_preview_path = figure_root / "qa/fig04_slope_necessity_effects_pdf_render.png"
    (figure_root / "archive").mkdir(parents=True, exist_ok=True)

    data = load_source_data(root)
    source_csv.parent.mkdir(parents=True, exist_ok=True)
    data.source_table.to_csv(
        source_csv, index=False, float_format="%.10g", encoding="utf-8", na_rep=""
    )

    fig, _ = build_figure(data)
    outputs = export_figure(fig, output_stem)
    plt.close(fig)
    output_checks = inspect_outputs(outputs, qa_preview_path)
    input_paths = [root / PAIRED_EFFECTS_FILE, root / BOOTSTRAP_CI_FILE]
    write_qa_report(
        data, root, input_paths, source_csv, outputs, output_checks, qa_path
    )

    print(f"Validated {data.route_effects.shape[0]} route effects and 6 frozen CIs.")
    print(f"Source data: {source_csv}")
    for output in outputs:
        print(f"Figure output: {output}")
    print(f"PDF QA preview: {qa_preview_path}")
    print(f"QA report: {qa_path}")


if __name__ == "__main__":
    main()
