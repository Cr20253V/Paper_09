from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import to_rgb
from matplotlib.lines import Line2D
from PIL import Image


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 104.0
BLACK = "#222222"
BLUE = "#0072B2"
GREEN = "#009E73"
RED = "#B24A47"
GRAY = "#767676"
LIGHT = "#E6E6E6"

METRICS = ["ey_rmse", "epsi_rmse", "j_du"]
METRIC_TITLES = {
    "ey_rmse": "Lateral-error RMS",
    "epsi_rmse": "Heading-error RMS",
    "j_du": "Input-increment index",
}
METRIC_UNITS = {"ey_rmse": "m", "epsi_rmse": "rad", "j_du": "J_delta_u"}
IMPROVEMENT_COLUMNS = {
    "ey_rmse": "ey_rmse_improvement",
    "epsi_rmse": "epsi_rmse_improvement",
    "j_du": "j_du_improvement",
}
ROUTE_ORDER = [
    "p01_factory_logistics_showcase",
    "p02_sharp_turn_transition",
    "p03_long_updown",
    "p04_soft_updown_straight_turn",
    "p05_factory_flat_logistics",
    "p06_downhill_after_turn",
]
ROUTE_LABELS = {
    "p01_factory_logistics_showcase": "P1 Factory logistics",
    "p02_sharp_turn_transition": "P2 Sharp-turn transition",
    "p03_long_updown": "P3 Long up/down slope",
    "p04_soft_updown_straight_turn": "P4 Mild slope-turn coupling",
    "p05_factory_flat_logistics": "P5 Flat factory logistics",
    "p06_downhill_after_turn": "P6 Downhill recovery",
}


def project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "results").is_dir() and (parent / "simulink").is_dir():
            return parent
    raise RuntimeError("Project root not found")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def configure_style() -> None:
    mpl.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
            "font.size": 6.5,
            "axes.labelsize": 6.5,
            "axes.titlesize": 7.0,
            "xtick.labelsize": 6.5,
            "ytick.labelsize": 6.5,
            "legend.fontsize": 6.5,
            "axes.linewidth": 0.65,
            "axes.spines.right": False,
            "axes.spines.top": False,
            "legend.frameon": False,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "savefig.facecolor": "white",
            "figure.facecolor": "white",
            "axes.facecolor": "white",
        }
    )


def panel_label(ax: mpl.axes.Axes, label: str, x: float = -0.22) -> None:
    artist = ax.text(
        x,
        1.04,
        label,
        transform=ax.transAxes,
        fontsize=8.0,
        fontweight="bold",
        ha="left",
        va="bottom",
        color=BLACK,
        clip_on=False,
    )
    artist.set_gid("panel_label")


def padded_limits(values: np.ndarray, include_zero: bool = True) -> tuple[float, float]:
    low = float(np.nanmin(values))
    high = float(np.nanmax(values))
    if include_zero:
        low = min(low, 0.0)
        high = max(high, 0.0)
    span = high - low
    if span == 0:
        span = max(abs(high), 1.0) * 0.2
    return low - 0.14 * span, high + 0.14 * span


def qa_previews(png_path: Path, qa_dir: Path, stem: str) -> dict[str, Path]:
    image = np.asarray(Image.open(png_path).convert("RGB"), dtype=float) / 255.0
    gray = np.clip(image @ np.array([0.2126, 0.7152, 0.0722]), 0, 1)
    gray_path = qa_dir / f"{stem}_grayscale.png"
    Image.fromarray(np.uint8(np.round(np.repeat(gray[..., None], 3, axis=2) * 255))).save(gray_path, dpi=(300, 300))
    matrix = np.array([[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]])
    simulated = np.clip(image @ matrix.T, 0, 1)
    deutan_path = qa_dir / f"{stem}_deuteranopia.png"
    Image.fromarray(np.uint8(np.round(simulated * 255))).save(deutan_path, dpi=(300, 300))
    return {"grayscale": gray_path, "deuteranopia": deutan_path}


def audit_figure(fig: mpl.figure.Figure, svg_path: Path) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_box = fig.bbox
    texts = [artist for artist in fig.findobj(mpl.text.Text) if artist.get_visible() and artist.get_text().strip()]
    overflow = []
    boxes = []
    for artist in texts:
        box = artist.get_window_extent(renderer=renderer)
        boxes.append((artist, box))
        if box.x0 < figure_box.x0 - 2 or box.y0 < figure_box.y0 - 2 or box.x1 > figure_box.x1 + 2 or box.y1 > figure_box.y1 + 2:
            overflow.append(artist.get_text())
    overlaps = []
    for index, (left_artist, left_box) in enumerate(boxes):
        for right_artist, right_box in boxes[index + 1 :]:
            if left_artist.axes is right_artist.axes and left_artist.axes is not None:
                continue
            intersection = mpl.transforms.Bbox.intersection(left_box, right_box)
            if intersection is None:
                continue
            area = intersection.width * intersection.height
            smaller = min(left_box.width * left_box.height, right_box.width * right_box.height)
            if smaller > 0 and area / smaller > 0.15:
                overlaps.append([left_artist.get_text(), right_artist.get_text()])
    svg_text_count = len(re.findall(r"<text(?:\s|>)", svg_path.read_text(encoding="utf-8")))
    return {
        "minimum_font_pt": min(float(artist.get_fontsize()) for artist in texts),
        "text_overflow_count": len(overflow),
        "text_overflow": overflow,
        "cross_axes_text_overlap_count": len(overlaps),
        "cross_axes_text_overlaps": overlaps,
        "svg_text_elements": svg_text_count,
        "svg_text_editable": svg_text_count > 0,
    }


def colorblind_distances(colors: list[str]) -> dict[str, float]:
    values = np.asarray([to_rgb(color) for color in colors])
    matrices = {
        "protanopia": np.array([[0.152, 1.053, -0.205], [0.115, 0.786, 0.099], [-0.004, -0.048, 1.052]]),
        "deuteranopia": np.array([[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]),
    }
    result = {}
    for name, matrix in matrices.items():
        transformed = np.clip(values @ matrix.T, 0, 1)
        distances = [np.linalg.norm(transformed[left] - transformed[right]) for left in range(len(colors)) for right in range(left + 1, len(colors))]
        result[name] = float(min(distances))
    return result


def main() -> None:
    root = project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    source_dir = figure_dir / "source_data"
    output_dir = figure_dir / "output"
    qa_dir = figure_dir / "qa"
    for directory in (source_dir, output_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    frozen = root / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/12_statistics"
    ci_path = frozen / "bootstrap_ci_results.csv"
    route_path = frozen / "per_path_summary.csv"
    pairs_path = frozen / "paired_case_details.csv"
    decision_path = frozen / "decision.json"
    safety_path = frozen / "safety_summary.csv"
    ci = pd.read_csv(ci_path).set_index("metric").loc[METRICS].reset_index()
    route = pd.read_csv(route_path)
    pairs = pd.read_csv(pairs_path)
    decision = json.loads(decision_path.read_text(encoding="utf-8"))
    safety = pd.read_csv(safety_path)

    if len(pairs) != 60 or pairs.duplicated(["model_seed", "path_id"]).any():
        raise ValueError("Formal population is not 60 unique route-seed pairs")
    if set(pairs["path_id"]) != set(ROUTE_ORDER) or pairs["model_seed"].nunique() != 10:
        raise ValueError("Formal six-route, ten-seed hierarchy changed")
    if decision["fusion_safety_failure_count"] != 0:
        raise ValueError("Fusion safety-failure count is not zero")
    if set(ci["n_pairs"]) != {60} or set(ci["iterations"]) != {10000} or set(ci["random_seed"]) != {20260715}:
        raise ValueError("Frozen hierarchical bootstrap contract changed")

    reconstructed = []
    for path_id in ROUTE_ORDER:
        subset = pairs[pairs["path_id"] == path_id]
        for metric in METRICS:
            reconstructed.append(
                {
                    "path_id": path_id,
                    "metric": metric,
                    "reconstructed_mean": float(subset[IMPROVEMENT_COLUMNS[metric]].mean()),
                }
            )
    reconstructed_df = pd.DataFrame(reconstructed)
    route_check = route.merge(reconstructed_df, on=["path_id", "metric"], validate="one_to_one")
    max_route_error = float(np.max(np.abs(route_check["mean_improvement"] - route_check["reconstructed_mean"])))
    if max_route_error > 1e-12:
        raise ValueError(f"Route mean reconstruction failed: {max_route_error}")
    for row in ci.itertuples():
        mean_from_pairs = float(pairs[IMPROVEMENT_COLUMNS[row.metric]].mean())
        if not np.isclose(mean_from_pairs, row.estimate, atol=1e-12, rtol=0):
            raise ValueError(f"Aggregate {row.metric} effect reconstruction failed")

    route_ordered = route.assign(path_id=pd.Categorical(route["path_id"], ROUTE_ORDER, ordered=True), metric=pd.Categorical(route["metric"], METRICS, ordered=True)).sort_values(["path_id", "metric"])
    signs = np.sign(route_ordered["mean_improvement"].to_numpy(float))
    favorable_count = int((signs > 0).sum())
    unchanged_count = int((signs == 0).sum())
    adverse_count = int((signs < 0).sum())
    adverse_rows = route_ordered[route_ordered["mean_improvement"] < 0]
    if (favorable_count, unchanged_count, adverse_count) != (14, 3, 1):
        raise ValueError("Route-metric direction counts changed")
    if len(adverse_rows) != 1 or str(adverse_rows.iloc[0]["path_id"]) != "p06_downhill_after_turn" or str(adverse_rows.iloc[0]["metric"]) != "j_du":
        raise ValueError("The sole adverse route-metric mean is no longer P6 J_delta_u")

    source_rows = []
    for row in ci.itertuples():
        source_rows.append(
            {
                "record_type": "aggregate_effect",
                "metric": row.metric,
                "n_pairs": row.n_pairs,
                "g0_mean": row.g0_mean,
                "fusion_mean": row.fusion_mean,
                "effect_mtcn_minus_fusion": row.estimate,
                "ci95_low": row.ci95_low,
                "ci95_high": row.ci95_high,
                "claim_status": row.claim_status,
            }
        )
    for row in route_ordered.itertuples():
        source_rows.append(
            {
                "record_type": "route_mean_effect",
                "path_id": str(row.path_id),
                "route_label": ROUTE_LABELS[str(row.path_id)],
                "metric": str(row.metric),
                "n_pairs": row.n_pairs,
                "g0_mean": row.g0_mean,
                "fusion_mean": row.fusion_mean,
                "effect_mtcn_minus_fusion": row.mean_improvement,
                "improved_count": row.improved_count,
                "degraded_count": row.degraded_count,
            }
        )
    source_path = source_dir / "fig09_node44r1_formal_summary_source_data.csv"
    pd.DataFrame(source_rows).to_csv(source_path, index=False)

    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    outer = fig.add_gridspec(2, 1, height_ratios=[0.92, 1.72], left=0.17, right=0.985, bottom=0.13, top=0.91, hspace=0.58)
    top = outer[0].subgridspec(1, 3, wspace=0.52)
    bottom = outer[1].subgridspec(1, 3, wspace=0.52)
    top_axes = [fig.add_subplot(top[0, index]) for index in range(3)]
    bottom_axes = [fig.add_subplot(bottom[0, index]) for index in range(3)]

    for index, metric in enumerate(METRICS):
        axis = top_axes[index]
        row = ci[ci["metric"] == metric].iloc[0]
        estimate = float(row["estimate"])
        low = float(row["ci95_low"])
        high = float(row["ci95_high"])
        supported = row["claim_status"] == "SUPPORTED"
        axis.axvspan(0, max(high, estimate) * 1.35 if max(high, estimate) > 0 else 1, color=GREEN, alpha=0.045, lw=0)
        axis.axvline(0, color=BLACK, lw=0.7)
        axis.errorbar(estimate, 0, xerr=np.array([[estimate - low], [high - estimate]]), fmt="o" if supported else "D", ms=5.2, lw=1.35, capsize=3.0, color=GREEN if supported else BLUE, markerfacecolor=GREEN if supported else "white", markeredgewidth=1.0)
        axis.set_xlim(*padded_limits(np.array([low, high, estimate])))
        axis.set_ylim(-0.65, 0.65)
        axis.set_yticks([])
        axis.xaxis.set_major_locator(mpl.ticker.MaxNLocator(nbins=3, prune="both"))
        axis.spines["left"].set_visible(False)
        axis.set_title(METRIC_TITLES[metric], pad=5)
        axis.set_xlabel(f"Effect ({METRIC_UNITS[metric]})")
        axis.text(0.5, 0.96, row["claim_status"].title(), transform=axis.transAxes, ha="center", va="top", fontsize=6.5, color=GREEN if supported else BLUE, fontweight="bold")
        precision = 5 if metric != "j_du" else 5
        axis.text(0.56, 0.80, f"Effect {estimate:.{precision}f}\n95% CI [{low:.{precision}f}, {high:.{precision}f}]", transform=axis.transAxes, ha="center", va="top", fontsize=6.5, linespacing=1.0, color=BLACK)
    panel_label(top_axes[0], "a", x=-0.38)
    fig.text(0.58, 0.952, "MTCN-minus-Fusion effect; positive favors Fusion", ha="center", va="center", fontsize=6.5, color=BLACK)

    y = np.arange(len(ROUTE_ORDER))
    for index, metric in enumerate(METRICS):
        axis = bottom_axes[index]
        metric_rows = route_ordered[route_ordered["metric"].astype(str) == metric].copy()
        metric_rows["path_id"] = metric_rows["path_id"].astype(str)
        metric_rows = metric_rows.set_index("path_id").loc[ROUTE_ORDER].reset_index()
        values = metric_rows["mean_improvement"].to_numpy(float)
        axis.axvline(0, color=BLACK, lw=0.7)
        for row_index, value in enumerate(values):
            axis.plot([0, value], [row_index, row_index], color=LIGHT, lw=1.0, zorder=1)
            if value > 0:
                color, marker, face = BLUE, "o", BLUE
            elif value < 0:
                color, marker, face = RED, "X", RED
            else:
                color, marker, face = GRAY, "s", "white"
            axis.scatter(value, row_index, s=28, color=color, marker=marker, facecolor=face, edgecolor=color, linewidth=0.9, zorder=3)
        axis.set_xlim(*padded_limits(values))
        axis.set_ylim(len(ROUTE_ORDER) - 0.5, -0.5)
        axis.xaxis.set_major_locator(mpl.ticker.MaxNLocator(nbins=3, prune="both"))
        axis.set_yticks(y)
        if index == 0:
            axis.set_yticklabels([ROUTE_LABELS[path] for path in ROUTE_ORDER])
        else:
            axis.set_yticklabels([])
            axis.tick_params(axis="y", length=0)
        axis.set_title(METRIC_TITLES[metric], pad=5)
        axis.set_xlabel(f"Route mean effect ({METRIC_UNITS[metric]})")
        axis.spines["left"].set_visible(False)
    panel_label(bottom_axes[0], "b", x=-0.38)
    legend_handles = [
        Line2D([], [], color=BLUE, marker="o", linestyle="none", markersize=4.5, label="Favors Fusion"),
        Line2D([], [], color=GRAY, marker="s", markerfacecolor="white", linestyle="none", markersize=4.5, label="Unchanged"),
        Line2D([], [], color=RED, marker="X", linestyle="none", markersize=4.5, label="Adverse"),
    ]
    bottom_axes[1].legend(handles=legend_handles, loc="lower center", bbox_to_anchor=(0.5, 1.12), ncol=3, handletextpad=0.4, columnspacing=1.1)

    stem = "fig09_node44r1_formal_summary"
    svg_path = output_dir / f"{stem}.svg"
    pdf_path = output_dir / f"{stem}.pdf"
    tiff_path = output_dir / f"{stem}.tiff"
    png_path = output_dir / f"{stem}.png"
    fig.savefig(svg_path)
    fig.savefig(pdf_path)
    fig.savefig(tiff_path, dpi=600, pil_kwargs={"compression": "tiff_lzw"})
    fig.savefig(png_path, dpi=300)
    qa = audit_figure(fig, svg_path)
    plt.close(fig)
    previews = qa_previews(png_path, qa_dir, stem)

    png_size = Image.open(png_path).size
    tiff_image = Image.open(tiff_path)
    tiff_size = tiff_image.size
    pdf_bytes = pdf_path.read_bytes()
    pdf_type3_count = pdf_bytes.count(b"/Subtype /Type3")
    pdf_fontfile2_count = pdf_bytes.count(b"/FontFile2")
    pdf_tounicode_count = pdf_bytes.count(b"/ToUnicode")
    tiff_compression = str(tiff_image.info.get("compression", ""))
    expected_png = np.array([WIDTH_MM / 25.4 * 300, HEIGHT_MM / 25.4 * 300])
    expected_tiff = np.array([WIDTH_MM / 25.4 * 600, HEIGHT_MM / 25.4 * 600])
    if np.max(np.abs(np.asarray(png_size) - expected_png)) > 1 or np.max(np.abs(np.asarray(tiff_size) - expected_tiff)) > 1:
        raise ValueError(f"Raster dimensions changed: PNG {png_size}, TIFF {tiff_size}")
    distances = colorblind_distances([BLUE, RED, GRAY])
    qa.update(
        {
            "status": "PASS",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "png_pixels_300dpi": list(png_size),
            "tiff_pixels_600dpi": list(tiff_size),
            "pdf_type3_font_count": pdf_type3_count,
            "pdf_embedded_truetype_font_count": pdf_fontfile2_count,
            "pdf_tounicode_map_count": pdf_tounicode_count,
            "tiff_compression": tiff_compression,
            "colorblind_minimum_pair_distance": distances,
            "redundant_encodings": "Favorable, unchanged, and adverse route means use distinct color, marker shape, and fill; aggregate status uses fill and label.",
            "grayscale_preview": str(previews["grayscale"].relative_to(root)).replace("\\", "/"),
            "deuteranopia_preview": str(previews["deuteranopia"].relative_to(root)).replace("\\", "/"),
            "numeric_reconstruction": {
                "matched_pairs": len(pairs),
                "model_seeds": int(pairs["model_seed"].nunique()),
                "routes": int(pairs["path_id"].nunique()),
                "route_mean_max_abs_reconstruction_error": max_route_error,
                "favorable_route_metric_means": favorable_count,
                "unchanged_route_metric_means": unchanged_count,
                "adverse_route_metric_means": adverse_count,
                "sole_adverse_mean": "P6 J_delta_u",
                "fusion_safety_failure_count": decision["fusion_safety_failure_count"],
                "overall_joint_rule_status": decision["status"],
                "safety_summary_rows": len(safety),
            },
        }
    )
    if qa["minimum_font_pt"] < 6.5 or qa["text_overflow_count"] or qa["cross_axes_text_overlap_count"] or not qa["svg_text_editable"] or pdf_type3_count or pdf_fontfile2_count < 1 or pdf_tounicode_count < 1 or tiff_compression != "tiff_lzw" or min(distances.values()) < 0.08:
        qa["status"] = "FAIL"
        raise ValueError(f"Figure QA failed: {qa}")

    qa_path = qa_dir / f"{stem}_qa.json"
    qa_path.write_text(json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    inputs = [ci_path, route_path, pairs_path, decision_path, safety_path]
    outputs = [svg_path, pdf_path, tiff_path, png_path]
    manifest = {
        "figure_id": "Fig09_node44r1_formal_summary",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "nature_figure_contract": str((figure_dir / "figure_contract.md").relative_to(root)).replace("\\", "/"),
        "frozen_inputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in inputs],
        "source_data": {"file": str(source_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(source_path), "rows": len(source_rows)},
        "outputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in outputs],
        "qa": {"file": str(qa_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(qa_path), "status": qa["status"]},
    }
    (figure_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"figure": manifest["figure_id"], "status": qa["status"], "outputs": [str(path) for path in outputs]}, indent=2))


if __name__ == "__main__":
    main()
