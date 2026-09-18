"""Generate the four-estimator, ten-seed offline error distribution figure."""

from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image
from scipy.stats import t as student_t

SCRIPT_DIR = Path(__file__).resolve().parent
SHARED_STYLE_DIR = SCRIPT_DIR.parents[1] / "shared"
sys.dont_write_bytecode = True
if str(SHARED_STYLE_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_STYLE_DIR))

from style import PALETTE, add_panel_label, apply_publication_style


MM_PER_INCH = 25.4
FIGURE_WIDTH_MM = 183.0
FIGURE_HEIGHT_MM = 70.0
EXPECTED_SEEDS = (1, 7, 11, 21, 42, 73, 101, 202, 340, 520)
SOURCE_RELATIVE_PATH = (
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
    "01_A1_algorithm_comparison/03_offline/offline_case_metrics.csv"
)


@dataclass(frozen=True)
class MethodSpec:
    method_id: str
    label: str
    tick_label: str
    color_key: str
    marker: str


@dataclass(frozen=True)
class MetricSpec:
    source_column: str
    output_column: str
    title: str
    ylabel: str
    y_max: float
    major_step: float


METHODS = (
    MethodSpec(
        "modern_tcn_delta_bank_124",
        "ModernTCN-delta",
        "ModernTCN-\ndelta",
        "fusion",
        "o",
    ),
    MethodSpec("modern_tcn_22d", "ModernTCN-22D", "ModernTCN-\n22D", "mtcn", "s"),
    MethodSpec("gru_22d", "GRU-22D", "GRU-\n22D", "gru", "^"),
    MethodSpec("tcn_22d", "TCN-22D", "TCN-\n22D", "tcn", "v"),
)

METRICS = (
    MetricSpec(
        "theta_abs_le_10_mae_deg",
        "grade_mae_deg",
        "Grade MAE",
        "MAE (deg)",
        1.2,
        0.2,
    ),
    MetricSpec(
        "theta_abs_le_10_p95_abs_err_deg",
        "p95_abs_error_deg",
        "P95 absolute error",
        "P95 absolute error (deg)",
        4.0,
        0.5,
    ),
)


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


def load_source_data(project_root: Path | None = None) -> pd.DataFrame:
    """Load the 40 frozen method-seed results and retain only figure source fields."""
    root = project_root or find_project_root()
    source_path = root / SOURCE_RELATIVE_PATH
    if not source_path.is_file():
        raise FileNotFoundError(source_path)

    required = ["method_id", "seed", *(metric.source_column for metric in METRICS)]
    raw = pd.read_csv(source_path, usecols=required)
    method_lookup = {spec.method_id: spec for spec in METHODS}
    selected = raw.loc[raw["method_id"].isin(method_lookup)].copy()
    selected["method_label"] = selected["method_id"].map(
        {method_id: spec.label for method_id, spec in method_lookup.items()}
    )
    selected["method_order"] = selected["method_id"].map(
        {spec.method_id: order for order, spec in enumerate(METHODS)}
    )
    selected = selected.rename(
        columns={metric.source_column: metric.output_column for metric in METRICS}
    )
    selected = selected[
        [
            "method_id",
            "method_label",
            "method_order",
            "seed",
            *(metric.output_column for metric in METRICS),
        ]
    ].sort_values(["method_order", "seed"], ignore_index=True)
    validate_source_data(selected)
    return selected


def validate_source_data(data: pd.DataFrame) -> None:
    """Enforce the frozen 4-method x 10-seed comparison contract."""
    required = {
        "method_id",
        "method_label",
        "method_order",
        "seed",
        *(metric.output_column for metric in METRICS),
    }
    missing = sorted(required.difference(data.columns))
    if missing:
        raise ValueError(f"Source data are missing columns: {missing}")
    if data.shape[0] != len(METHODS) * len(EXPECTED_SEEDS):
        raise ValueError(f"Expected 40 rows, found {data.shape[0]}.")
    if data.duplicated(["method_id", "seed"]).any():
        raise ValueError("Duplicate method-seed rows were found.")

    expected_ids = [spec.method_id for spec in METHODS]
    observed_ids = list(data.sort_values("method_order")["method_id"].drop_duplicates())
    if observed_ids != expected_ids:
        raise ValueError(f"Method order mismatch: expected {expected_ids}, got {observed_ids}.")

    expected_seed_set = set(EXPECTED_SEEDS)
    for spec in METHODS:
        method = data.loc[data["method_id"] == spec.method_id]
        observed_seeds = set(method["seed"].astype(int))
        if observed_seeds != expected_seed_set:
            raise ValueError(
                f"{spec.method_id}: expected seeds {sorted(expected_seed_set)}, "
                f"got {sorted(observed_seeds)}."
            )
        observed_labels = set(method["method_label"])
        if observed_labels != {spec.label}:
            raise ValueError(f"{spec.method_id}: inconsistent display label {observed_labels}.")

    metric_columns = [metric.output_column for metric in METRICS]
    values = data[metric_columns].to_numpy(dtype=float)
    if not np.isfinite(values).all():
        raise ValueError("Non-finite values were found in the plotted metrics.")
    if np.any(values < 0.0):
        raise ValueError("Absolute-error metrics must be non-negative.")
    for metric in METRICS:
        maximum = float(data[metric.output_column].max())
        if maximum >= metric.y_max:
            raise ValueError(
                f"{metric.output_column}: maximum {maximum:.4g} reaches the locked "
                f"axis limit {metric.y_max:.4g}."
            )


def mean_t_interval(values: np.ndarray, confidence: float = 0.95) -> tuple[float, float, float]:
    """Return the sample mean and two-sided Student-t interval for that mean."""
    values = np.asarray(values, dtype=float)
    if values.ndim != 1 or values.size < 2 or not np.isfinite(values).all():
        raise ValueError("A t interval requires at least two finite one-dimensional values.")
    mean = float(np.mean(values))
    standard_error = float(np.std(values, ddof=1) / np.sqrt(values.size))
    critical = float(student_t.ppf(0.5 + confidence / 2.0, df=values.size - 1))
    return mean, mean - critical * standard_error, mean + critical * standard_error


def _seed_offsets() -> dict[int, float]:
    offsets = np.linspace(-0.145, 0.145, len(EXPECTED_SEEDS))
    return {seed: float(offset) for seed, offset in zip(EXPECTED_SEEDS, offsets)}


def _style_axes(ax, metric: MetricSpec) -> None:
    ax.set_xlim(-0.45, len(METHODS) - 0.55)
    ax.set_ylim(0.0, metric.y_max)
    ax.set_yticks(np.arange(0.0, metric.y_max + metric.major_step / 2.0, metric.major_step))
    ax.set_xticks(np.arange(len(METHODS)))
    ax.set_xticklabels([spec.tick_label for spec in METHODS], linespacing=0.94)
    for label, spec in zip(ax.get_xticklabels(), METHODS):
        label.set_color(PALETTE[spec.color_key])
        label.set_fontweight("bold")
    ax.set_ylabel(metric.ylabel, labelpad=1.7)
    ax.set_title(metric.title, loc="left", fontsize=7.8, fontweight="bold", pad=5.0)
    ax.grid(axis="y", color=PALETTE["grid"], linewidth=0.55, alpha=0.95)
    ax.set_axisbelow(True)
    ax.tick_params(axis="x", length=0, pad=3.0)
    ax.tick_params(axis="y", direction="out", pad=1.5)
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")


def build_figure(data: pd.DataFrame):
    """Build the two-panel raw distribution and matched-seed comparison."""
    validate_source_data(data)
    apply_publication_style()

    fig = plt.figure(
        figsize=(FIGURE_WIDTH_MM / MM_PER_INCH, FIGURE_HEIGHT_MM / MM_PER_INCH),
        facecolor="white",
    )
    grid = fig.add_gridspec(
        1,
        2,
        left=0.075,
        right=0.985,
        bottom=0.295,
        top=0.88,
        wspace=0.28,
    )
    axes = np.array([fig.add_subplot(grid[0, column]) for column in range(2)])
    offsets = _seed_offsets()

    for panel_index, (ax, metric) in enumerate(zip(axes, METRICS)):
        _style_axes(ax, metric)
        add_panel_label(ax, f"({chr(ord('a') + panel_index)})", x=-0.13, y=1.025)

        delta = data.loc[data["method_id"] == METHODS[0].method_id].set_index("seed")
        baseline = data.loc[data["method_id"] == METHODS[1].method_id].set_index("seed")
        for seed in EXPECTED_SEEDS:
            offset = offsets[seed]
            ax.plot(
                [0.0 + offset, 1.0 + offset],
                [delta.at[seed, metric.output_column], baseline.at[seed, metric.output_column]],
                color="#B8B8B8",
                linewidth=0.55,
                alpha=0.8,
                zorder=1,
            )

        for method_index, spec in enumerate(METHODS):
            method = data.loc[data["method_id"] == spec.method_id].set_index("seed")
            x_values = np.array([method_index + offsets[seed] for seed in EXPECTED_SEEDS])
            y_values = method.loc[list(EXPECTED_SEEDS), metric.output_column].to_numpy(dtype=float)
            color = PALETTE[spec.color_key]
            ax.scatter(
                x_values,
                y_values,
                s=18.0,
                marker=spec.marker,
                facecolor=color,
                edgecolor="white",
                linewidth=0.35,
                alpha=0.92,
                zorder=3,
            )

            mean, lower, upper = mean_t_interval(y_values)
            ax.vlines(method_index, lower, upper, color=PALETTE["truth"], linewidth=0.8, zorder=4)
            ax.hlines(
                [lower, upper],
                method_index - 0.055,
                method_index + 0.055,
                color=PALETTE["truth"],
                linewidth=0.8,
                zorder=4,
            )
            ax.scatter(
                [method_index],
                [mean],
                s=28.0,
                marker=spec.marker,
                facecolor=color,
                edgecolor=PALETTE["truth"],
                linewidth=0.6,
                zorder=5,
            )
            ax.hlines(
                mean,
                method_index - 0.105,
                method_index + 0.105,
                color=PALETTE["truth"],
                linewidth=1.0,
                zorder=6,
            )

    fig.text(
        0.53,
        0.075,
        "Points show individual seeds; black marks show mean and 95% t CI; "
        "gray lines pair identical ModernTCN seeds.\n"
        "Test split: run-disjoint, not fully path-template-disjoint.",
        ha="center",
        va="center",
        fontsize=6.0,
        color="#444444",
        linespacing=1.3,
    )
    return fig, axes


def export_figure(fig, output_stem: Path) -> list[Path]:
    """Export editable vector formats and fixed-size raster formats."""
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


def inspect_output_geometry(outputs: list[Path]) -> dict[str, object]:
    """Verify raster dimensions and editable SVG text at final print size."""
    expected_mm = np.array([FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM], dtype=float)
    raster_geometry: dict[str, object] = {}
    for suffix, expected_dpi in ((".png", 300), (".tiff", 600)):
        path = next(item for item in outputs if item.suffix == suffix)
        with Image.open(path) as image:
            pixels = np.array(image.size, dtype=float)
            actual_mm = pixels / expected_dpi * MM_PER_INCH
            if not np.allclose(actual_mm, expected_mm, atol=0.15):
                raise ValueError(
                    f"{path.name}: canvas is {actual_mm.tolist()} mm, expected "
                    f"{expected_mm.tolist()} mm."
                )
            raster_geometry[suffix.lstrip(".")] = {
                "pixels": [int(value) for value in pixels],
                "dpi": expected_dpi,
                "physical_size_mm": [round(float(value), 3) for value in actual_mm],
            }

    svg_path = next(item for item in outputs if item.suffix == ".svg")
    svg_text = svg_path.read_text(encoding="utf-8")
    if "<text" not in svg_text or "Grade MAE" not in svg_text:
        raise ValueError("SVG text is not editable or expected labels are missing.")
    return {
        "requested_size_mm": [FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM],
        "raster_exports": raster_geometry,
        "svg_editable_text": True,
        "status": "PASS",
    }


def _metric_summary(data: pd.DataFrame) -> list[dict[str, object]]:
    summary: list[dict[str, object]] = []
    for spec in METHODS:
        method = data.loc[data["method_id"] == spec.method_id]
        for metric in METRICS:
            mean, lower, upper = mean_t_interval(method[metric.output_column].to_numpy())
            summary.append(
                {
                    "method_id": spec.method_id,
                    "method_label": spec.label,
                    "metric": metric.output_column,
                    "n_seeds": int(method.shape[0]),
                    "mean": mean,
                    "ci95_lower": lower,
                    "ci95_upper": upper,
                    "minimum": float(method[metric.output_column].min()),
                    "maximum": float(method[metric.output_column].max()),
                }
            )
    return summary


def _paired_summary(data: pd.DataFrame) -> list[dict[str, object]]:
    delta = data.loc[data["method_id"] == METHODS[0].method_id].set_index("seed")
    baseline = data.loc[data["method_id"] == METHODS[1].method_id].set_index("seed")
    summary: list[dict[str, object]] = []
    for metric in METRICS:
        difference = delta.loc[list(EXPECTED_SEEDS), metric.output_column] - baseline.loc[
            list(EXPECTED_SEEDS), metric.output_column
        ]
        summary.append(
            {
                "metric": metric.output_column,
                "difference_definition": "ModernTCN-delta minus ModernTCN-22D",
                "delta_lower_seed_count": int((difference < 0.0).sum()),
                "equal_seed_count": int((difference == 0.0).sum()),
                "delta_higher_seed_count": int((difference > 0.0).sum()),
                "mean_paired_difference": float(difference.mean()),
            }
        )
    return summary


def write_qa_report(
    data: pd.DataFrame,
    root: Path,
    source_csv: Path,
    outputs: list[Path],
    output_geometry: dict[str, object],
    qa_path: Path,
) -> None:
    frozen_source = root / SOURCE_RELATIVE_PATH
    report = {
        "figure_id": "fig05_offline_estimator_distribution",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "figure_contract": {
            "archetype": "quantitative grid",
            "core_conclusion": (
                "ModernTCN-delta has the lowest mean grade MAE and P95 absolute error "
                "on the frozen test set while matched-seed lines retain seed variability."
            ),
            "final_size_mm_requested": [FIGURE_WIDTH_MM, FIGURE_HEIGHT_MM],
            "panel_grid": [1, 2],
            "test_split_note": "run-disjoint, not fully path-template-disjoint",
        },
        "validation": {
            "status": "PASS",
            "row_count": int(data.shape[0]),
            "method_count": int(data["method_id"].nunique()),
            "seeds_per_method": {
                spec.method_id: int((data["method_id"] == spec.method_id).sum())
                for spec in METHODS
            },
            "seed_order": list(EXPECTED_SEEDS),
            "duplicate_method_seed_rows": int(data.duplicated(["method_id", "seed"]).sum()),
            "all_metrics_finite": True,
            "y_axes_start_at_zero": True,
            "paired_lines": "identical seeds, ModernTCN-delta to ModernTCN-22D only",
            "ci_definition": "two-sided 95% Student-t interval for the mean across 10 seeds",
            "ci_degrees_of_freedom": len(EXPECTED_SEEDS) - 1,
            "output_canvas_geometry": output_geometry,
        },
        "frozen_input": {
            "file": SOURCE_RELATIVE_PATH,
            "bytes": frozen_source.stat().st_size,
            "sha256": sha256_file(frozen_source),
        },
        "source_data": {
            "file": str(source_csv.relative_to(root)).replace("\\", "/"),
            "rows": int(data.shape[0]),
            "sha256": sha256_file(source_csv),
        },
        "metric_summary": _metric_summary(data),
        "paired_modern_tcn_summary": _paired_summary(data),
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
    figure_root = root / "results/paper/7.6/figures_final/Fig05_offline_estimator_distribution"
    source_csv = (
        figure_root / "source_data/fig05_offline_estimator_distribution_source_data.csv"
    )
    output_stem = figure_root / "output/fig05_offline_estimator_distribution"
    qa_path = figure_root / "qa/fig05_offline_estimator_distribution_qa.json"

    data = load_source_data(root)
    source_csv.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(source_csv, index=False, float_format="%.10g", encoding="utf-8")

    fig, _ = build_figure(data)
    outputs = export_figure(fig, output_stem)
    plt.close(fig)
    output_geometry = inspect_output_geometry(outputs)
    write_qa_report(data, root, source_csv, outputs, output_geometry, qa_path)

    print(f"Validated {data.shape[0]} method-seed rows.")
    print(f"Source data: {source_csv}")
    for output in outputs:
        print(f"Figure output: {output}")
    print(f"QA report: {qa_path}")


if __name__ == "__main__":
    main()
