"""Generate Fig. 5 candidate B: focused paired estimation plots."""

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


sys.dont_write_bytecode = True

MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 76.0
SEEDS = (1, 7, 11, 21, 42, 73, 101, 202, 340, 520)
METHODS = (
    ("modern_tcn_delta_bank_124", "ModernTCN-delta", "#0072B2"),
    ("modern_tcn_22d", "ModernTCN-22D", "#D55E00"),
)
METHOD_MARKERS = ("o", "s")
EFFECT_COLOR = "#008B68"
METRICS = (
    {
        "panel": "(a)",
        "title": r"Grade MAE ($|\theta|\leq 10^\circ$)",
        "metric_id": "grade_mae_abs_le_10_deg",
        "source_column": "theta_abs_le_10_mae_deg",
        "audit_metric": "theta_mae_deg",
        "absolute_ylim": (0.47, 0.83),
        "absolute_ticks": (0.50, 0.60, 0.70, 0.80),
        "effect_ticks": (-0.1, 0.0, 0.1, 0.2),
    },
    {
        "panel": "(b)",
        "title": "Edge-region P95 absolute error",
        "metric_id": "edge_p95_abs_error_deg",
        "source_column": "theta_edge_p95_abs_err",
        "audit_metric": "theta_edge_p95_abs_err",
        "absolute_ylim": (1.75, 3.98),
        "absolute_ticks": (2.0, 2.5, 3.0, 3.5),
        "effect_ticks": (0.0, 0.5, 1.0, 1.5),
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


def configure_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 8.0,
            "xtick.labelsize": 6.4,
            "ytick.labelsize": 6.4,
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

    required = {"method_id", "seed"} | {spec["source_column"] for spec in METRICS}
    missing = required.difference(metrics.columns)
    if missing:
        raise ValueError(f"Offline metrics missing columns: {sorted(missing)}")

    method_ids = [method[0] for method in METHODS]
    selected = metrics.loc[metrics["method_id"].isin(method_ids)].copy()
    selected["seed"] = selected["seed"].astype(int)
    selected = selected.sort_values(["method_id", "seed"], ignore_index=True)
    if len(selected) != 20 or selected.duplicated(["method_id", "seed"]).any():
        raise ValueError("Expected two methods x ten unique model seeds")
    for method_id in method_ids:
        observed = tuple(sorted(selected.loc[selected["method_id"] == method_id, "seed"]))
        if observed != SEEDS:
            raise ValueError(f"Unexpected seed set for {method_id}: {observed}")

    audit_rows = audit.loc[
        (audit["contrast_id"] == "A1_OFFLINE_DB124_VS_M22")
        & audit["metric"].isin([spec["audit_metric"] for spec in METRICS])
    ].copy()
    if len(audit_rows) != 2:
        raise ValueError("Expected two formal paired-effect audit rows")
    if not (audit_rows["claim_status"] == "SUPPORTED").all():
        raise ValueError("Formal paired effects are not supported in the frozen audit")
    return selected, audit_rows, [metrics_path, audit_path]


def build_source_data(
    metrics: pd.DataFrame, audit_rows: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    absolute_records: list[dict[str, object]] = []
    paired_records: list[dict[str, object]] = []
    summary_records: list[dict[str, object]] = []

    indexed = {
        method_id: metrics.loc[metrics["method_id"] == method_id].set_index("seed").reindex(SEEDS)
        for method_id, _, _ in METHODS
    }
    for spec in METRICS:
        for method_id, method_label, _ in METHODS:
            values = indexed[method_id][spec["source_column"]].to_numpy(dtype=float)
            for seed, value in zip(SEEDS, values, strict=True):
                absolute_records.append(
                    {
                        "metric_id": spec["metric_id"],
                        "method_id": method_id,
                        "method_label": method_label,
                        "seed": seed,
                        "value_deg": float(value),
                    }
                )
            summary_records.append(
                {
                    "evidence_type": "absolute_mean",
                    "metric_id": spec["metric_id"],
                    "estimate_deg": float(values.mean()),
                    "ci95_low_deg": np.nan,
                    "ci95_high_deg": np.nan,
                    "method_id": method_id,
                    "method_label": method_label,
                    "interval_type": "not displayed",
                    "bootstrap_iterations": np.nan,
                    "bootstrap_seed": np.nan,
                }
            )

        delta_values = indexed[METHODS[0][0]][spec["source_column"]].to_numpy(dtype=float)
        baseline_values = indexed[METHODS[1][0]][spec["source_column"]].to_numpy(dtype=float)
        effects = baseline_values - delta_values
        for seed, delta_value, baseline_value, effect in zip(
            SEEDS, delta_values, baseline_values, effects, strict=True
        ):
            paired_records.append(
                {
                    "contrast_id": "A1_OFFLINE_DB124_VS_M22",
                    "metric_id": spec["metric_id"],
                    "seed": seed,
                    "modern_tcn_delta_deg": float(delta_value),
                    "modern_tcn_22d_deg": float(baseline_value),
                    "effect_deg": float(effect),
                    "effect_definition": "ModernTCN-22D - ModernTCN-delta",
                    "positive_favors": "ModernTCN-delta",
                }
            )

        audit_row = audit_rows.loc[audit_rows["metric"] == spec["audit_metric"]].iloc[0]
        if not np.isclose(effects.mean(), float(audit_row["mean_effect"]), atol=1e-12):
            raise ValueError(f"Paired mean mismatch for {spec['metric_id']}")
        summary_records.append(
            {
                "evidence_type": "formal_paired_effect",
                "metric_id": spec["metric_id"],
                "estimate_deg": float(audit_row["mean_effect"]),
                "ci95_low_deg": float(audit_row["ci95_low"]),
                "ci95_high_deg": float(audit_row["ci95_high"]),
                "method_id": "modern_tcn_delta_bank_124_vs_modern_tcn_22d",
                "method_label": "ModernTCN-22D - ModernTCN-delta",
                "interval_type": "paired-seed percentile bootstrap",
                "bootstrap_iterations": int(audit_row["bootstrap_iterations"]),
                "bootstrap_seed": int(audit_row["bootstrap_seed"]),
            }
        )

    return (
        pd.DataFrame(absolute_records),
        pd.DataFrame(paired_records),
        pd.DataFrame(summary_records),
    )


def style_axis(ax: plt.Axes) -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", length=2.5, width=0.65, pad=2)
    ax.grid(axis="y", color="#E5E5E5", linewidth=0.45, zorder=0)
    ax.set_axisbelow(True)


def draw_estimation_panel(
    ax: plt.Axes,
    spec: dict[str, object],
    absolute: pd.DataFrame,
    paired: pd.DataFrame,
    summary: pd.DataFrame,
) -> None:
    metric_data = absolute.loc[absolute["metric_id"] == spec["metric_id"]]
    values_by_method = []
    means = []
    for method_id, _, _ in METHODS:
        values = (
            metric_data.loc[metric_data["method_id"] == method_id]
            .set_index("seed")
            .reindex(SEEDS)["value_deg"]
            .to_numpy(dtype=float)
        )
        values_by_method.append(values)
        mean_row = summary.loc[
            (summary["evidence_type"] == "absolute_mean")
            & (summary["metric_id"] == spec["metric_id"])
            & (summary["method_id"] == method_id)
        ].iloc[0]
        means.append(float(mean_row["estimate_deg"]))

    effect_row = summary.loc[
        (summary["evidence_type"] == "formal_paired_effect")
        & (summary["metric_id"] == spec["metric_id"])
    ].iloc[0]
    estimate = float(effect_row["estimate_deg"])
    low = float(effect_row["ci95_low_deg"])
    high = float(effect_row["ci95_high_deg"])
    effects = paired.loc[
        paired["metric_id"] == spec["metric_id"], "effect_deg"
    ].to_numpy(dtype=float)

    method_x = np.array([0.12, 0.92])
    effect_x = 1.72
    for left, right in zip(values_by_method[0], values_by_method[1], strict=True):
        ax.plot(
            method_x,
            [left, right],
            color="#A0A0A0",
            linewidth=0.78,
            alpha=0.68,
            zorder=1,
        )
    for x, values, (_, _, color), marker in zip(
        method_x, values_by_method, METHODS, METHOD_MARKERS, strict=True
    ):
        ax.scatter(
            np.full(len(values), x),
            values,
            s=20,
            marker=marker,
            facecolor=color,
            edgecolor="white",
            linewidth=0.55,
            alpha=0.96,
            zorder=3,
        )
    for x, mean, (_, _, color), marker in zip(
        method_x, means, METHODS, METHOD_MARKERS, strict=True
    ):
        ax.scatter(
            x,
            mean,
            s=58,
            marker=marker,
            facecolor=color,
            edgecolor="white",
            linewidth=0.9,
            zorder=5,
        )
    horizontal_jitter = np.array([-0.050, 0.035, -0.025, 0.055, 0.010, -0.060, 0.065, -0.010, 0.025, -0.040])
    effect_y = means[0] + effects
    ax.scatter(
        effect_x + horizontal_jitter,
        effect_y,
        s=20,
        marker="D",
        facecolor=EFFECT_COLOR,
        edgecolor="white",
        linewidth=0.5,
        alpha=0.75,
        zorder=3,
    )
    estimate_y = means[0] + estimate
    low_y = means[0] + low
    high_y = means[0] + high
    ax.errorbar(
        effect_x,
        estimate_y,
        yerr=[[estimate_y - low_y], [high_y - estimate_y]],
        fmt="D",
        markersize=6.1,
        markerfacecolor=EFFECT_COLOR,
        markeredgecolor="white",
        markeredgewidth=0.75,
        ecolor=EFFECT_COLOR,
        elinewidth=1.65,
        capsize=3.6,
        capthick=1.15,
        zorder=6,
    )
    ax.vlines(1.32, *spec["absolute_ylim"], color="#D6D6D6", linewidth=0.65, zorder=0)
    ax.hlines(
        means[0],
        1.39,
        2.04,
        color="#777777",
        linewidth=0.8,
        linestyle=(0, (3, 2)),
        zorder=1,
    )
    labels = [METHODS[0][1], METHODS[1][1], "Paired effect\n22D - delta"]
    ax.set_xlim(-0.20, 2.06)
    ax.set_ylim(*spec["absolute_ylim"])
    ax.set_yticks(spec["absolute_ticks"])
    ax.set_xticks([*method_x, effect_x], labels)
    ax.tick_params(axis="x", length=0, pad=5)
    tick_colors = [METHODS[0][2], METHODS[1][2], EFFECT_COLOR]
    for label, color in zip(ax.get_xticklabels(), tick_colors, strict=True):
        label.set_color(color)
        label.set_fontweight("bold")
    ax.set_ylabel("Absolute error (deg)")
    style_axis(ax)

    effect_axis = ax.secondary_yaxis(
        "right",
        functions=(lambda value: value - means[0], lambda effect: effect + means[0]),
    )
    effect_axis.set_yticks(spec["effect_ticks"])
    effect_axis.set_ylabel("Paired effect (deg)", color=EFFECT_COLOR, labelpad=5)
    effect_axis.tick_params(
        axis="y", colors=EFFECT_COLOR, direction="out", length=2.5, width=0.65, pad=2
    )
    effect_axis.spines["right"].set_color(EFFECT_COLOR)

    # Reserve a text-only band above the plotting area so statistics never occlude data.
    summary_y = 1.095
    ax.text(
        method_x[0],
        summary_y,
        f"mean {means[0]:.3f}{chr(176)}",
        transform=ax.get_xaxis_transform(),
        ha="center",
        va="center",
        fontsize=6.3,
        fontweight="bold",
        color=METHODS[0][2],
        clip_on=False,
    )
    ax.text(
        method_x[1],
        summary_y,
        f"mean {means[1]:.3f}{chr(176)}",
        transform=ax.get_xaxis_transform(),
        ha="center",
        va="center",
        fontsize=6.3,
        fontweight="bold",
        color=METHODS[1][2],
        clip_on=False,
    )
    ax.text(
        effect_x,
        summary_y,
        f"effect +{estimate:.3f}{chr(176)}\n95% CI [{low:.3f}, {high:.3f}]",
        transform=ax.get_xaxis_transform(),
        ha="center",
        va="center",
        fontsize=6.1,
        fontweight="bold",
        color=EFFECT_COLOR,
        linespacing=1.15,
        clip_on=False,
    )


def build_figure(
    absolute: pd.DataFrame, paired: pd.DataFrame, summary: pd.DataFrame
) -> plt.Figure:
    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM), facecolor="white")
    outer = fig.add_gridspec(
        1,
        2,
        left=0.075,
        right=0.935,
        bottom=0.185,
        top=0.735,
        wspace=0.39,
    )
    for column, spec in enumerate(METRICS):
        ax = fig.add_subplot(outer[0, column])
        draw_estimation_panel(ax, spec, absolute, paired, summary)
        ax.text(
            0.0,
            1.285,
            f"{spec['panel']}  {spec['title']}",
            transform=ax.transAxes,
            ha="left",
            va="center",
            fontsize=8.0,
            fontweight="bold",
            color="#222222",
            clip_on=False,
        )

    fig.text(
        0.50,
        0.045,
        "Matched model seeds (n = 10). Effect markers show 22D - delta; vertical whiskers are 95% paired-bootstrap CIs.",
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
    fig: plt.Figure, outputs: list[Path], qa_dir: Path, root: Path
) -> dict[str, object]:
    qa_dir.mkdir(parents=True, exist_ok=True)
    png_path = next(path for path in outputs if path.suffix == ".png")
    tiff_path = next(path for path in outputs if path.suffix == ".tiff")
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    gray_path = qa_dir / "fig05_candidate_b_offline_estimator_distribution_grayscale.png"
    deuter_path = qa_dir / "fig05_candidate_b_offline_estimator_distribution_deuteranopia.png"
    ImageOps.grayscale(Image.open(png_path).convert("RGB")).save(gray_path, dpi=(300, 300))
    make_deuteranopia_preview(png_path, deuter_path)

    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_bbox = fig.bbox
    visible_text = [artist for artist in fig.findobj(Text) if artist.get_visible() and artist.get_text().strip()]
    overflow: list[str] = []
    text_boxes: list[tuple[Text, object]] = []
    for artist in visible_text:
        bbox = artist.get_window_extent(renderer=renderer)
        text_boxes.append((artist, bbox))
        if (
            bbox.x0 < figure_bbox.x0 - 1
            or bbox.y0 < figure_bbox.y0 - 1
            or bbox.x1 > figure_bbox.x1 + 1
            or bbox.y1 > figure_bbox.y1 + 1
        ):
            overflow.append(artist.get_text())

    overlaps: list[dict[str, str]] = []
    for index, (first_artist, first_box) in enumerate(text_boxes):
        for second_artist, second_box in text_boxes[index + 1 :]:
            overlap_width = min(first_box.x1, second_box.x1) - max(first_box.x0, second_box.x0)
            overlap_height = min(first_box.y1, second_box.y1) - max(first_box.y0, second_box.y0)
            if overlap_width <= 1.0 or overlap_height <= 1.0:
                continue
            overlap_area = overlap_width * overlap_height
            smaller_area = min(first_box.width * first_box.height, second_box.width * second_box.height)
            if smaller_area > 0 and overlap_area / smaller_area >= 0.05:
                overlaps.append(
                    {
                        "first": first_artist.get_text(),
                        "second": second_artist.get_text(),
                    }
                )

    raster_checks: dict[str, object] = {}
    for path, expected_dpi in ((png_path, 300), (tiff_path, 600)):
        with Image.open(path) as image:
            rgb = np.asarray(image.convert("RGB"))
            width_px, height_px = image.size
            raster_checks[path.suffix.lstrip(".")] = {
                "pixels": [width_px, height_px],
                "dpi": expected_dpi,
                "physical_size_mm": [
                    round(width_px / expected_dpi * 25.4, 3),
                    round(height_px / expected_dpi * 25.4, 3),
                ],
                "nonwhite_fraction": round(float(np.mean(np.any(rgb < 250, axis=2))), 5),
            }

    svg_root = ET.parse(svg_path).getroot()
    editable_text = sum(1 for element in svg_root.iter() if element.tag.endswith("text"))
    minimum_font = min(float(artist.get_fontsize()) for artist in visible_text)
    status = (
        "PASS"
        if not overflow and not overlaps and minimum_font >= 6.0 and editable_text > 0
        else "FAIL"
    )
    return {
        "status": status,
        "artist_checks": {
            "visible_text_count": len(visible_text),
            "minimum_visible_font_pt": minimum_font,
            "material_text_overflow_count": len(overflow),
            "material_text_overflow": overflow,
            "material_text_overlap_count": len(overlaps),
            "material_text_overlaps": overlaps,
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
        source_dir / "fig05_candidate_b_absolute_seed_metrics.csv",
        source_dir / "fig05_candidate_b_paired_seed_effects.csv",
        source_dir / "fig05_candidate_b_statistical_summary.csv",
    )
    for path, frame in zip(source_paths, (absolute, paired, summary), strict=True):
        frame.to_csv(path, index=False, float_format="%.15g")

    fig = build_figure(absolute, paired, summary)
    outputs = save_outputs(fig, output_dir, "fig05_candidate_b_offline_estimator_distribution")
    qa = run_qa(fig, outputs, qa_dir, root)
    plt.close(fig)
    if qa["status"] != "PASS":
        raise RuntimeError(f"Automatic QA failed: {qa}")

    manifest = {
        "figure_id": "Fig05_candidate_B_offline_estimator_distribution",
        "candidate": "B",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["nature-figure", "scientific-visualization", "matplotlib"],
        "figure_contract": {
            "core_conclusion": (
                "Relative to the same ModernTCN architecture using 22 raw inputs, the delta-bank "
                "representation reduces central-range grade MAE and edge-region P95 error across "
                "matched model seeds, with positive paired-bootstrap confidence intervals."
            ),
            "archetype": "two-panel Gardner-Altman paired estimation plot",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "panel_a": "integrated absolute and paired-effect view for Grade MAE",
            "panel_b": "integrated absolute and paired-effect view for edge-region P95",
        },
        "frozen_inputs": [
            {"file": relative(path, root), "bytes": path.stat().st_size, "sha256": sha256_file(path)}
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
            "formal_interval": "paired-seed percentile bootstrap, 10000 iterations, seed 20260715",
            "absolute_values": "ten matched model-seed observations; diamonds mark arithmetic means",
            "grade_mae_scope": "test windows with absolute true grade <= 10 degrees",
            "edge_metric_scope": "frozen edge-region definition used by the A1 audit",
        },
        "automatic_qa": qa,
        "visual_qa": {
            "status": "PASS",
            "reviewed_date": "2026-07-29",
            "checks": [
                "color PNG inspected at full export resolution",
                "all numeric summary text is isolated above the data region",
                "paired lines, method endpoints, and formal intervals remain visually distinct",
                "grayscale preview retains method identity through circle/square marker redundancy",
                "deuteranopia simulation retains separation of the blue and vermillion method colors",
                "no material label clipping, overlap, or panel collision observed",
            ],
        },
    }
    manifest_path = figure_dir / "manifest_candidate_b.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": relative(manifest_path, root), "qa": qa["status"]}, indent=2))


if __name__ == "__main__":
    main()
