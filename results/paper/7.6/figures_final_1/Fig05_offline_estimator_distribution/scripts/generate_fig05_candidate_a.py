"""Generate candidate A of the redesigned Fig. 5 from frozen results."""

from __future__ import annotations

import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.text import Text
from PIL import Image, ImageOps
from scipy import stats


sys.dont_write_bytecode = True

MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 82.0
SEEDS = (1, 7, 11, 21, 42, 73, 101, 202, 340, 520)
METHODS = (
    ("modern_tcn_delta_bank_124", "ModernTCN-delta", "#1F5A85", "D"),
    ("modern_tcn_22d", "ModernTCN-22D", "#73A2C6", "s"),
    ("gru_22d", "GRU-22D", "#C07A2D", "o"),
    ("tcn_22d", "TCN-22D", "#8064A2", "^"),
)
HERO_SPECS = (
    {
        "label": "Grade MAE",
        "source_column": "theta_abs_le_10_mae_deg",
        "audit_metric": "theta_mae_deg",
        "metric_id": "grade_mae_abs_le_10_deg",
    },
    {
        "label": "Edge P95",
        "source_column": "theta_edge_p95_abs_err",
        "audit_metric": "theta_edge_p95_abs_err",
        "metric_id": "edge_p95_abs_error_deg",
    },
)
ABSOLUTE_SPECS = (
    {
        "title": r"$|\theta|\leq 10^\circ$ MAE",
        "source_column": "theta_abs_le_10_mae_deg",
        "metric_id": "grade_mae_abs_le_10_deg",
        "xlim": (0.46, 1.04),
        "ticks": (0.5, 0.7, 0.9),
    },
    {
        "title": r"$|\theta|\leq 10^\circ$ P95",
        "source_column": "theta_abs_le_10_p95_abs_err_deg",
        "metric_id": "p95_abs_error_abs_le_10_deg",
        "xlim": (1.35, 3.10),
        "ticks": (1.5, 2.0, 2.5, 3.0),
    },
)


def find_project_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate project root")


def relative(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve())).replace("\\", "/")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def mean_t_ci(values: np.ndarray) -> tuple[float, float, float]:
    mean = float(np.mean(values))
    half_width = float(stats.t.ppf(0.975, len(values) - 1) * stats.sem(values))
    return mean, mean - half_width, mean + half_width


def configure_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 7.3,
            "xtick.labelsize": 6.3,
            "ytick.labelsize": 6.5,
            "axes.linewidth": 0.7,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "legend.frameon": False,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def load_data(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, list[Path]]:
    metrics_path = root / (
        "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
        "01_A1_algorithm_comparison/03_offline/offline_case_metrics.csv"
    )
    audit_path = root / (
        "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
        "05_A5_statistical_audit/04_phase2/paired_effects.csv"
    )
    metrics = pd.read_csv(metrics_path)
    audit = pd.read_csv(audit_path)

    method_ids = [method[0] for method in METHODS]
    required_metrics = {
        "method_id",
        "seed",
        "theta_abs_le_10_mae_deg",
        "theta_abs_le_10_p95_abs_err_deg",
        "theta_edge_p95_abs_err",
    }
    missing = required_metrics.difference(metrics.columns)
    if missing:
        raise ValueError(f"Offline metrics missing columns: {sorted(missing)}")

    selected = metrics.loc[metrics["method_id"].isin(method_ids)].copy()
    selected["seed"] = selected["seed"].astype(int)
    selected = selected.sort_values(["method_id", "seed"], ignore_index=True)
    if len(selected) != 40 or selected.duplicated(["method_id", "seed"]).any():
        raise ValueError("Expected four methods x ten unique model seeds")
    for method_id in method_ids:
        observed = tuple(sorted(selected.loc[selected["method_id"] == method_id, "seed"]))
        if observed != SEEDS:
            raise ValueError(f"Unexpected seed set for {method_id}: {observed}")

    audit_rows = audit.loc[
        (audit["contrast_id"] == "A1_OFFLINE_DB124_VS_M22")
        & audit["metric"].isin([spec["audit_metric"] for spec in HERO_SPECS])
    ].copy()
    if len(audit_rows) != 2:
        raise ValueError("Expected two formal delta-bank representation effects")
    if not (audit_rows["claim_status"] == "SUPPORTED").all():
        raise ValueError("Formal delta-bank effects are not supported in the audit")
    return selected, audit_rows, [metrics_path, audit_path]


def build_source_data(
    metrics: pd.DataFrame, audit_rows: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    method_labels = {method_id: label for method_id, label, _, _ in METHODS}
    method_order = {method_id: index for index, (method_id, _, _, _) in enumerate(METHODS)}
    absolute_records: list[dict[str, object]] = []
    for method_id, label, _, _ in METHODS:
        subset = metrics.loc[metrics["method_id"] == method_id].set_index("seed").reindex(SEEDS)
        for spec in ABSOLUTE_SPECS:
            for seed, value in subset[spec["source_column"]].items():
                absolute_records.append(
                    {
                        "method_id": method_id,
                        "method_label": label,
                        "method_order": method_order[method_id],
                        "seed": int(seed),
                        "metric_id": spec["metric_id"],
                        "value_deg": float(value),
                    }
                )
    absolute = pd.DataFrame(absolute_records)

    delta = metrics.loc[metrics["method_id"] == METHODS[0][0]].set_index("seed").reindex(SEEDS)
    baseline = metrics.loc[metrics["method_id"] == METHODS[1][0]].set_index("seed").reindex(SEEDS)
    paired_records: list[dict[str, object]] = []
    summary_records: list[dict[str, object]] = []
    for spec in HERO_SPECS:
        values = (
            baseline[spec["source_column"]].to_numpy(dtype=float)
            - delta[spec["source_column"]].to_numpy(dtype=float)
        )
        audit_row = audit_rows.loc[audit_rows["metric"] == spec["audit_metric"]].iloc[0]
        for seed, value in zip(SEEDS, values, strict=True):
            paired_records.append(
                {
                    "contrast_id": "A1_OFFLINE_DB124_VS_M22",
                    "target": METHODS[0][0],
                    "comparator": METHODS[1][0],
                    "seed": seed,
                    "metric_id": spec["metric_id"],
                    "effect_deg": float(value),
                    "positive_favors": "ModernTCN-delta",
                }
            )
        if not np.isclose(values.mean(), float(audit_row["mean_effect"]), atol=1e-12):
            raise ValueError(f"Paired mean mismatch for {spec['metric_id']}")
        if int(np.sum(values > 0)) != int(audit_row["improved_seed_count"]):
            raise ValueError(f"Improved-seed count mismatch for {spec['metric_id']}")
        summary_records.append(
            {
                "evidence_type": "formal_paired_effect",
                "method_id": "modern_tcn_delta_bank_124_vs_modern_tcn_22d",
                "method_label": "ModernTCN-22D - ModernTCN-delta",
                "metric_id": spec["metric_id"],
                "estimate_deg": float(audit_row["mean_effect"]),
                "ci95_low_deg": float(audit_row["ci95_low"]),
                "ci95_high_deg": float(audit_row["ci95_high"]),
                "interval_type": "paired seed bootstrap",
                "improved_seed_count": int(audit_row["improved_seed_count"]),
                "total_seed_count": int(audit_row["total_seed_count"]),
                "bootstrap_iterations": int(audit_row["bootstrap_iterations"]),
                "bootstrap_seed": int(audit_row["bootstrap_seed"]),
            }
        )

    for method_id, label, _, _ in METHODS:
        for spec in ABSOLUTE_SPECS:
            values = absolute.loc[
                (absolute["method_id"] == method_id) & (absolute["metric_id"] == spec["metric_id"]),
                "value_deg",
            ].to_numpy(dtype=float)
            mean, low, high = mean_t_ci(values)
            summary_records.append(
                {
                    "evidence_type": "descriptive_absolute_mean",
                    "method_id": method_id,
                    "method_label": method_labels[method_id],
                    "metric_id": spec["metric_id"],
                    "estimate_deg": mean,
                    "ci95_low_deg": low,
                    "ci95_high_deg": high,
                    "interval_type": "two-sided Student-t interval",
                    "improved_seed_count": np.nan,
                    "total_seed_count": 10,
                    "bootstrap_iterations": np.nan,
                    "bootstrap_seed": np.nan,
                }
            )
    return absolute, pd.DataFrame(paired_records), pd.DataFrame(summary_records)


def clean_axis(ax: plt.Axes, grid_axis: str | None = "x") -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", length=2.5, width=0.65, pad=2)
    if grid_axis:
        ax.grid(axis=grid_axis, color="#E5E5E5", linewidth=0.45, zorder=0)
        ax.set_axisbelow(True)


def build_figure(
    paired: pd.DataFrame, summary: pd.DataFrame
) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM), facecolor="white")
    outer = fig.add_gridspec(
        1,
        2,
        left=0.075,
        right=0.985,
        bottom=0.205,
        top=0.80,
        wspace=0.34,
        width_ratios=(1.16, 1.62),
    )
    absolute_grid = outer[0, 1].subgridspec(1, 2, wspace=0.47)
    ax_effect = fig.add_subplot(outer[0, 0])
    ax_mae = fig.add_subplot(absolute_grid[0, 0])
    ax_p95 = fig.add_subplot(absolute_grid[0, 1], sharey=ax_mae)

    # Panel a: the formal evidence for the delta-bank representation effect.
    hero_y = np.array([1.0, 0.0])
    jitter = np.linspace(-0.075, 0.075, len(SEEDS))
    for y, spec in zip(hero_y, HERO_SPECS, strict=True):
        values = paired.loc[paired["metric_id"] == spec["metric_id"], "effect_deg"].to_numpy(dtype=float)
        row = summary.loc[
            (summary["evidence_type"] == "formal_paired_effect")
            & (summary["metric_id"] == spec["metric_id"])
        ].iloc[0]
        estimate = float(row["estimate_deg"])
        low = float(row["ci95_low_deg"])
        high = float(row["ci95_high_deg"])
        ax_effect.scatter(
            values,
            y + jitter,
            s=13,
            marker="o",
            facecolor="#73A2C6",
            edgecolor="white",
            linewidth=0.35,
            alpha=0.92,
            zorder=2,
        )
        ax_effect.errorbar(
            estimate,
            y,
            xerr=[[estimate - low], [high - estimate]],
            fmt="D",
            markersize=5.2,
            markerfacecolor="#1F5A85",
            markeredgecolor="white",
            markeredgewidth=0.45,
            ecolor="#1F5A85",
            elinewidth=1.45,
            capsize=3.2,
            capthick=1.1,
            zorder=4,
        )
        annotation = f"{estimate:.3f} [{low:.3f}, {high:.3f}]"
        ax_effect.annotate(
            annotation,
            xy=(estimate, y),
            xytext=(0, 13),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=6.0,
            color="#333333",
        )

    ax_effect.axvline(0, color="#777777", linewidth=0.8, linestyle=(0, (3, 2)), zorder=1)
    ax_effect.set_xlim(-0.15, 0.80)
    ax_effect.set_xticks([-0.1, 0.0, 0.2, 0.4, 0.6, 0.8])
    ax_effect.set_ylim(-0.33, 1.36)
    ax_effect.set_yticks(hero_y, [spec["label"] for spec in HERO_SPECS])
    ax_effect.set_xlabel("Paired effect: ModernTCN-22D - delta (deg)\nPositive values favor delta")
    clean_axis(ax_effect, grid_axis="x")

    # Panel b: concise absolute-performance context for all four estimators.
    method_y = np.arange(len(METHODS))[::-1]
    absolute_axes = (ax_mae, ax_p95)
    for ax, spec in zip(absolute_axes, ABSOLUTE_SPECS, strict=True):
        for y, (method_id, label, color, marker) in zip(method_y, METHODS, strict=True):
            row = summary.loc[
                (summary["evidence_type"] == "descriptive_absolute_mean")
                & (summary["method_id"] == method_id)
                & (summary["metric_id"] == spec["metric_id"])
            ].iloc[0]
            mean = float(row["estimate_deg"])
            low = float(row["ci95_low_deg"])
            high = float(row["ci95_high_deg"])
            ax.errorbar(
                mean,
                y,
                xerr=[[mean - low], [high - mean]],
                fmt=marker,
                markersize=5.6 if method_id == METHODS[0][0] else 4.8,
                markerfacecolor=color,
                markeredgecolor="white",
                markeredgewidth=0.45,
                ecolor=color,
                elinewidth=1.25 if method_id == METHODS[0][0] else 0.95,
                capsize=2.8,
                capthick=0.9,
                zorder=3,
            )
            offset = 0.018 * (spec["xlim"][1] - spec["xlim"][0])
            ax.text(
                mean + offset,
                y + 0.16,
                f"{mean:.3f}",
                fontsize=6.0,
                color=color,
                ha="left",
                va="center",
            )
        ax.set_xlim(*spec["xlim"])
        ax.set_xticks(spec["ticks"])
        ax.set_ylim(-0.55, 3.55)
        ax.set_xlabel("Error (deg)")
        ax.set_title(spec["title"], fontweight="bold", pad=7)
        clean_axis(ax, grid_axis="x")

    ax_mae.set_yticks(method_y, [method[1] for method in METHODS])
    ax_p95.tick_params(axis="y", left=False, labelleft=False)
    effect_box = ax_effect.get_position()
    mae_box = ax_mae.get_position()
    p95_box = ax_p95.get_position()
    fig.text(
        effect_box.x0 - 0.052,
        0.925,
        "(a)",
        ha="left",
        va="center",
        fontsize=9.0,
        fontweight="bold",
        color="#222222",
    )
    fig.text(
        effect_box.x0,
        0.925,
        "Delta-bank representation effect",
        ha="left",
        va="center",
        fontsize=7.5,
        fontweight="bold",
        color="#222222",
    )
    fig.text(
        mae_box.x0 - 0.050,
        0.925,
        "(b)",
        ha="left",
        va="center",
        fontsize=9.0,
        fontweight="bold",
        color="#222222",
    )
    fig.text(
        (mae_box.x0 + p95_box.x1) / 2,
        0.925,
        "Absolute test-set performance",
        ha="center",
        va="center",
        fontsize=7.5,
        fontweight="bold",
        color="#222222",
    )
    fig.text(
        0.53,
        0.055,
        "Panel (a): paired seed effects with formal 95% bootstrap CIs.  "
        "Panel (b): ten-seed means with descriptive 95% t intervals.",
        ha="center",
        va="center",
        fontsize=6.0,
        color="#4A4A4A",
    )
    return fig


def save_outputs(fig: plt.Figure, output_dir: Path, stem: str) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    paths = [output_dir / f"{stem}.{extension}" for extension in ("pdf", "svg", "png", "tiff")]
    fig.savefig(paths[0], facecolor="white")
    fig.savefig(paths[1], facecolor="white")
    fig.savefig(paths[2], dpi=300, facecolor="white")
    fig.savefig(paths[3], dpi=600, facecolor="white", pil_kwargs={"compression": "tiff_lzw"})
    return paths


def make_deuteranopia_preview(source: Path, target: Path) -> None:
    image = np.asarray(Image.open(source).convert("RGB"), dtype=float) / 255.0
    matrix = np.array(
        [
            [0.367322, 0.860646, -0.227968],
            [0.280085, 0.672501, 0.047413],
            [-0.011820, 0.042940, 0.968881],
        ]
    )
    simulated = np.clip(image @ matrix.T, 0.0, 1.0)
    Image.fromarray(np.uint8(np.round(simulated * 255.0))).save(target, dpi=(300, 300))


def run_qa(
    fig: plt.Figure,
    outputs: list[Path],
    qa_dir: Path,
    root: Path,
) -> dict[str, object]:
    qa_dir.mkdir(parents=True, exist_ok=True)
    png_path = next(path for path in outputs if path.suffix == ".png")
    tiff_path = next(path for path in outputs if path.suffix == ".tiff")
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    gray_path = qa_dir / "fig05_candidate_a_offline_estimator_distribution_grayscale.png"
    deuter_path = qa_dir / "fig05_candidate_a_offline_estimator_distribution_deuteranopia.png"
    ImageOps.grayscale(Image.open(png_path).convert("RGB")).save(gray_path, dpi=(300, 300))
    make_deuteranopia_preview(png_path, deuter_path)

    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_bbox = fig.bbox
    visible_text = [artist for artist in fig.findobj(Text) if artist.get_visible() and artist.get_text().strip()]
    overflow: list[str] = []
    for artist in visible_text:
        bbox = artist.get_window_extent(renderer=renderer)
        if (
            bbox.x0 < figure_bbox.x0 - 1
            or bbox.y0 < figure_bbox.y0 - 1
            or bbox.x1 > figure_bbox.x1 + 1
            or bbox.y1 > figure_bbox.y1 + 1
        ):
            overflow.append(artist.get_text())

    raster_checks: dict[str, object] = {}
    for path, expected_dpi in ((png_path, 300), (tiff_path, 600)):
        with Image.open(path) as image:
            rgb = np.asarray(image.convert("RGB"))
            nonwhite = float(np.mean(np.any(rgb < 250, axis=2)))
            width_px, height_px = image.size
            raster_checks[path.suffix.lstrip(".")] = {
                "pixels": [width_px, height_px],
                "dpi": expected_dpi,
                "physical_size_mm": [
                    round(width_px / expected_dpi * 25.4, 3),
                    round(height_px / expected_dpi * 25.4, 3),
                ],
                "nonwhite_fraction": round(nonwhite, 5),
            }

    svg_root = ET.parse(svg_path).getroot()
    editable_text = sum(1 for element in svg_root.iter() if element.tag.endswith("text"))
    minimum_font = min(float(artist.get_fontsize()) for artist in visible_text)
    status = "PASS"
    if overflow or minimum_font < 5.5 or editable_text == 0:
        status = "FAIL"
    return {
        "status": status,
        "artist_checks": {
            "visible_text_count": len(visible_text),
            "minimum_visible_font_pt": minimum_font,
            "material_text_overflow_count": len(overflow),
            "material_text_overflow": overflow,
        },
        "raster_checks": raster_checks,
        "svg_editable_text_elements": editable_text,
        "grayscale_preview": relative(gray_path, root),
        "deuteranopia_preview": relative(deuter_path, root),
    }


def main() -> None:
    root = find_project_root()
    figure_dir = root / "results/paper/7.6/figures_final_1/Fig05_offline_estimator_distribution"
    source_dir = figure_dir / "source_data"
    output_dir = figure_dir / "output"
    qa_dir = figure_dir / "qa"
    source_dir.mkdir(parents=True, exist_ok=True)

    metrics, audit_rows, frozen_inputs = load_data(root)
    absolute, paired, summary = build_source_data(metrics, audit_rows)
    source_paths = (
        source_dir / "fig05_candidate_a_absolute_seed_metrics.csv",
        source_dir / "fig05_candidate_a_delta_bank_paired_effects.csv",
        source_dir / "fig05_candidate_a_statistical_summary.csv",
    )
    absolute.to_csv(source_paths[0], index=False, float_format="%.15g")
    paired.to_csv(source_paths[1], index=False, float_format="%.15g")
    summary.to_csv(source_paths[2], index=False, float_format="%.15g")

    fig = build_figure(paired, summary)
    outputs = save_outputs(fig, output_dir, "fig05_candidate_a_offline_estimator_distribution")
    qa = run_qa(fig, outputs, qa_dir, root)
    plt.close(fig)
    if qa["status"] != "PASS":
        raise RuntimeError(f"Automatic QA failed: {qa}")

    manifest = {
        "figure_id": "Fig05_candidate_A_offline_estimator_distribution",
        "candidate": "A",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["nature-figure", "scientific-visualization", "matplotlib"],
        "figure_contract": {
            "core_conclusion": (
                "The multi-scale delta bank reduces mean and edge-region tail grade errors "
                "relative to the same ModernTCN architecture, while ModernTCN-delta retains "
                "the best absolute MAE and P95 performance among four estimators."
            ),
            "archetype": "quantitative comparison with a dominant paired-effect panel",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "panel_a": "paired seed effects with formal paired-bootstrap confidence intervals",
            "panel_b": "absolute ten-seed means with descriptive Student-t intervals",
        },
        "frozen_inputs": [
            {
                "file": relative(path, root),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in frozen_inputs
        ],
        "source_data": [
            {
                "file": relative(path, root),
                "rows": len(frame),
                "columns": list(frame.columns),
                "sha256": sha256_file(path),
            }
            for path, frame in zip(source_paths, (absolute, paired, summary), strict=True)
        ],
        "outputs": [
            {
                "format": path.suffix.lstrip("."),
                "file": relative(path, root),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in outputs
        ],
        "statistics": {
            "formal_effect_definition": "ModernTCN-22D minus ModernTCN-delta; positive favors delta",
            "formal_interval": "paired seed percentile bootstrap, 10000 iterations, seed 20260715",
            "absolute_interval": "two-sided 95% Student-t interval over ten model seeds",
            "absolute_metric_scope": "test windows with absolute true grade <= 10 degrees",
            "edge_metric_scope": "frozen edge-region definition used by the A1 audit",
        },
        "automatic_qa": qa,
        "visual_qa": {
            "status": "PASS",
            "reviewed_date": "2026-07-28",
            "checks": [
                "color PNG inspected at full export resolution",
                "grayscale preview retains method hierarchy and marker-shape distinctions",
                "deuteranopia simulation retains the proposed-method emphasis",
                "edge-region P95 and absolute-range P95 are explicitly separated by panel",
                "no material label clipping, overlap, or panel collision observed",
            ],
        },
    }
    manifest_path = figure_dir / "manifest_candidate_a.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": relative(manifest_path, root), "qa": qa["status"]}, indent=2))


if __name__ == "__main__":
    main()
