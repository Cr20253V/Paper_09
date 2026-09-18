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
from matplotlib.colors import LinearSegmentedColormap, Normalize, to_rgb
from PIL import Image


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 100.0
BLUE = "#0072B2"
ORANGE = "#D55E00"
GREEN = "#009E73"
RED = "#B24A47"
GRAY = "#6E6E6E"
BLACK = "#222222"
ERROR_SCALE_CMAP = LinearSegmentedColormap.from_list(
    "paper_blue_error_scale",
    ["#F2F5F7", "#B9CCDA", "#4C78A8", "#0F4C81"],
)


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
            "lines.solid_capstyle": "round",
        }
    )


def panel_label(ax: mpl.axes.Axes, label: str, x: float = -0.15) -> None:
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


def save_qa_previews(png_path: Path, qa_dir: Path, stem: str) -> dict[str, str]:
    image = np.asarray(Image.open(png_path).convert("RGB"), dtype=float) / 255.0
    gray = np.clip(image @ np.array([0.2126, 0.7152, 0.0722]), 0, 1)
    gray_rgb = np.repeat(gray[..., None], 3, axis=2)
    gray_path = qa_dir / f"{stem}_grayscale.png"
    Image.fromarray(np.uint8(np.round(gray_rgb * 255))).save(gray_path, dpi=(300, 300))
    deutan = np.array(
        [[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]
    )
    simulated = np.clip(image @ deutan.T, 0, 1)
    deutan_path = qa_dir / f"{stem}_deuteranopia.png"
    Image.fromarray(np.uint8(np.round(simulated * 255))).save(deutan_path, dpi=(300, 300))
    return {"grayscale": str(gray_path), "deuteranopia": str(deutan_path)}


def save_pdf(fig: mpl.figure.Figure, pdf_path: Path) -> None:
    temp_path = pdf_path.with_name(f".{pdf_path.stem}.tmp.pdf")
    try:
        fig.savefig(temp_path)
        payload = temp_path.read_bytes()
        if pdf_path.exists():
            # Windows PDF viewers may allow shared writes but reject direct truncation.
            with pdf_path.open("r+b") as handle:
                handle.seek(0)
                handle.write(payload)
                handle.truncate()
        else:
            temp_path.replace(pdf_path)
    finally:
        temp_path.unlink(missing_ok=True)


def audit_figure(fig: mpl.figure.Figure, svg_path: Path) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_box = fig.bbox
    texts = [artist for artist in fig.findobj(mpl.text.Text) if artist.get_visible() and artist.get_text().strip()]
    font_sizes = [float(artist.get_fontsize()) for artist in texts]
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
                overlaps.append(
                    {
                        "left": left_artist.get_text(),
                        "left_box": list(left_box.bounds),
                        "right": right_artist.get_text(),
                        "right_box": list(right_box.bounds),
                    }
                )
    svg_text = svg_path.read_text(encoding="utf-8")
    svg_text_count = len(re.findall(r"<text(?:\s|>)", svg_text))
    return {
        "minimum_font_pt": min(font_sizes),
        "text_overflow_count": len(overflow),
        "text_overflow": overflow,
        "cross_axes_text_overlap_count": len(overlaps),
        "cross_axes_text_overlaps": overlaps,
        "svg_text_elements": svg_text_count,
        "svg_text_editable": svg_text_count > 0,
    }


def color_distance_under_deficiency(first: str, second: str) -> dict[str, float]:
    colors = np.array([to_rgb(first), to_rgb(second)])
    matrices = {
        "protanopia": np.array([[0.152, 1.053, -0.205], [0.115, 0.786, 0.099], [-0.004, -0.048, 1.052]]),
        "deuteranopia": np.array([[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]),
    }
    return {
        name: float(np.linalg.norm(np.clip(colors @ matrix.T, 0, 1)[0] - np.clip(colors @ matrix.T, 0, 1)[1]))
        for name, matrix in matrices.items()
    }


def main() -> None:
    root = project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    source_dir = figure_dir / "source_data"
    output_dir = figure_dir / "output"
    qa_dir = figure_dir / "qa"
    for directory in (source_dir, output_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    frozen = root / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/06_uncertainty_calibration_v3"
    config_path = frozen / "selected_fusion_config.json"
    moments_path = frozen / "empirical_quality_uncertainty_tables.json"
    candidates_path = frozen / "candidate_table.csv"
    gain_path = frozen / "quality_gain_audit.csv"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    moments = json.loads(moments_path.read_text(encoding="utf-8"))
    candidates = pd.read_csv(candidates_path)
    gain = pd.read_csv(gain_path)

    if config["tables"] != moments["tables"]:
        raise ValueError("Frozen moment tables disagree")
    selected = config["selected"]
    if not np.isclose(selected["Kmax"], 0.5) or not selected["qualified"]:
        raise ValueError("Registered Kmax=0.5 selection changed")
    if not np.isclose(selected["K_raw_spread"], selected["K_raw_p95"] - selected["K_raw_p05"], atol=1e-12):
        raise ValueError("Kraw spread reconstruction failed")
    if not np.isclose(selected["K_eff_spread"], selected["K_eff_p95"] - selected["K_eff_p05"], atol=1e-12):
        raise ValueError("Keff spread reconstruction failed")
    expected = {0.3: False, 0.4: True, 0.5: True}
    observed = {float(row.Kmax): bool(row.qualified) for row in candidates.itertuples()}
    if observed != expected:
        raise ValueError(f"Candidate qualification changed: {observed}")
    failed_03 = json.loads(candidates.loc[np.isclose(candidates["Kmax"], 0.3), "failed_gates"].iloc[0].replace("'", '"'))
    if failed_03 != ["K_eff_spread"]:
        raise ValueError("Kmax=0.3 failure reason changed")

    regimes = config["quality_model"]["regime_order"]
    regime_labels = ["Flat steady", "Slope steady", "Flat transition", "Slope transition"]
    quality_labels = ["Low", "Medium", "High"]
    p_mtcn = np.asarray(moments["tables"]["P_tcn_total"], dtype=float)
    p_observer = np.asarray(moments["tables"]["P_observer_total"], dtype=float)
    if p_mtcn.shape != (4, 3) or p_observer.shape != (4, 3):
        raise ValueError("Expected four-regime by three-excitation moment tables")
    error_mtcn = np.rad2deg(np.sqrt(p_mtcn))
    error_observer = np.rad2deg(np.sqrt(p_observer))
    gain_selected = gain[np.isclose(gain["Kmax"], 0.5)].sort_values("quality_bin")
    if list(gain_selected["quality_bin"]) != [1, 2, 3]:
        raise ValueError("Selected gain audit is incomplete")

    source_rows = []
    for source_name, values in (("ModernTCN-delta", error_mtcn), ("Qualified observer", error_observer)):
        for r_index, regime in enumerate(regimes):
            for q_index, quality in enumerate(quality_labels):
                source_rows.append(
                    {
                        "record_type": "error_scale",
                        "source": source_name,
                        "regime": regime,
                        "excitation_bin": quality,
                        "error_scale_deg": values[r_index, q_index],
                    }
                )
    for row in gain_selected.itertuples():
        source_rows.append(
            {
                "record_type": "gain_quantiles",
                "Kmax": row.Kmax,
                "excitation_bin": quality_labels[int(row.quality_bin) - 1],
                "K_raw_p05": row.K_raw_p05,
                "K_raw_p50": row.K_raw_p50,
                "K_raw_p95": row.K_raw_p95,
                "K_eff_p05": row.K_eff_p05,
                "K_eff_p50": row.K_eff_p50,
                "K_eff_p95": row.K_eff_p95,
                "sample_count": row.sample_count,
            }
        )
    for row in candidates.itertuples():
        source_rows.append(
            {
                "record_type": "candidate",
                "Kmax": row.Kmax,
                "mae_ratio": row.mae_ratio,
                "K_eff_spread": row.K_eff_spread,
                "qualified": bool(row.qualified),
                "selected": bool(np.isclose(row.Kmax, selected["Kmax"])),
            }
        )
    source_path = source_dir / "fig07_node44r1_gain_calibration_source_data.csv"
    pd.DataFrame(source_rows).to_csv(source_path, index=False)

    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    outer = fig.add_gridspec(1, 3, width_ratios=[1.58, 1.15, 1.08], left=0.12, right=0.985, bottom=0.16, top=0.92, wspace=0.44)

    heat_grid = outer[0].subgridspec(1, 2, wspace=0.10)
    ax_a1 = fig.add_subplot(heat_grid[0, 0])
    ax_a2 = fig.add_subplot(heat_grid[0, 1])
    norm = Normalize(vmin=float(min(error_mtcn.min(), error_observer.min())), vmax=float(max(error_mtcn.max(), error_observer.max())))
    for axis, values, title in ((ax_a1, error_mtcn, "ModernTCN-delta"), (ax_a2, error_observer, "Qualified observer")):
        image = axis.imshow(values, cmap=ERROR_SCALE_CMAP, norm=norm, aspect="auto")
        axis.set_title(title, pad=4)
        axis.set_xticks(range(3), quality_labels)
        axis.set_xlabel("Observer excitation")
        axis.set_yticks(range(4))
        axis.tick_params(length=0)
        for r_index in range(4):
            for q_index in range(3):
                rgba = image.cmap(image.norm(values[r_index, q_index]))
                luminance = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2]
                axis.text(q_index, r_index, f"{values[r_index, q_index]:.2f}", ha="center", va="center", color="white" if luminance < 0.48 else BLACK, fontsize=6.5)
    ax_a1.set_yticklabels(regime_labels)
    ax_a2.set_yticklabels([])
    panel_label(ax_a1, "a", x=-0.43)
    colorbar = fig.colorbar(image, ax=[ax_a1, ax_a2], orientation="horizontal", fraction=0.06, pad=0.17, aspect=25)
    colorbar.set_label("Empirical total-error scale (deg)", labelpad=2)
    colorbar.ax.tick_params(labelsize=6.5, length=2)

    ax_b = fig.add_subplot(outer[1])
    x = np.arange(3, dtype=float)
    for offset, prefix, label, color, marker in ((-0.07, "K_raw", "Kraw", BLUE, "o"), (0.07, "K_eff", "Keff", ORANGE, "s")):
        median = gain_selected[f"{prefix}_p50"].to_numpy(float)
        low = gain_selected[f"{prefix}_p05"].to_numpy(float)
        high = gain_selected[f"{prefix}_p95"].to_numpy(float)
        ax_b.errorbar(x + offset, median, yerr=np.vstack([median - low, high - median]), fmt=marker, ms=4.2, lw=1.1, capsize=2.5, color=color, markerfacecolor="white" if prefix == "K_raw" else color, markeredgewidth=0.9, label=label)
    ax_b.axhline(0.5, color=BLACK, lw=0.8, ls=(0, (4, 2)), label="Kmax = 0.5")
    ax_b.set_xticks(x, quality_labels)
    ax_b.set_xlabel("Observer excitation")
    ax_b.set_ylabel("Gain")
    ax_b.set_ylim(0.0, 0.78)
    ax_b.set_yticks([0.0, 0.2, 0.4, 0.6])
    ax_b.legend(loc="upper left", handlelength=2.0, borderaxespad=0.2)
    ax_b.set_title("Selected candidate: P05-P50-P95", pad=4)
    panel_label(ax_b, "b", x=-0.22)

    candidate_grid = outer[2].subgridspec(2, 1, hspace=0.42)
    ax_c1 = fig.add_subplot(candidate_grid[0, 0])
    ax_c2 = fig.add_subplot(candidate_grid[1, 0], sharex=ax_c1)
    k_values = candidates["Kmax"].to_numpy(float)
    qualified = candidates["qualified"].astype(bool).to_numpy()
    colors = [GREEN if item else RED for item in qualified]
    markers = ["o" if item else "X" for item in qualified]
    for k_value, value, color, marker in zip(k_values, candidates["mae_ratio"], colors, markers):
        ax_c1.scatter(k_value, value, s=30, color=color, marker=marker, zorder=3)
    ax_c1.plot(k_values, candidates["mae_ratio"], color=GRAY, lw=0.8, zorder=1)
    ax_c1.axhline(0.95, color=BLACK, lw=0.7, ls=(0, (3, 2)))
    ax_c1.set_ylabel("MAE ratio")
    ax_c1.set_ylim(0.875, 0.958)
    ax_c1.tick_params(axis="x", labelbottom=False)
    ax_c1.set_title("Frozen candidate qualification", pad=4)
    panel_label(ax_c1, "c", x=-0.28)
    for k_value, value, color, marker in zip(k_values, candidates["K_eff_spread"], colors, markers):
        ax_c2.scatter(k_value, value, s=30, color=color, marker=marker, zorder=3)
    ax_c2.plot(k_values, candidates["K_eff_spread"], color=GRAY, lw=0.8, zorder=1)
    ax_c2.axhline(0.02, color=BLACK, lw=0.7, ls=(0, (3, 2)))
    ax_c2.set_ylabel("Keff spread")
    ax_c2.set_xlabel("Gain cap Kmax")
    ax_c2.set_xticks(k_values, [f"{value:.1f}" for value in k_values])
    ax_c2.set_ylim(0.0, 0.235)
    ax_c2.annotate("Selected", xy=(0.5, float(candidates.loc[np.isclose(candidates["Kmax"], 0.5), "K_eff_spread"].iloc[0])), xytext=(0.43, 0.17), fontsize=6.5, color=BLACK, arrowprops={"arrowstyle": "-", "lw": 0.7, "color": BLACK})
    ax_c2.text(0.02, 0.96, "circle: qualified\nX: failed", transform=ax_c2.transAxes, va="top", ha="left", fontsize=6.5, color=GRAY)

    stem = "fig07_node44r1_gain_calibration"
    svg_path = output_dir / f"{stem}.svg"
    pdf_path = output_dir / f"{stem}.pdf"
    tiff_path = output_dir / f"{stem}.tiff"
    png_path = output_dir / f"{stem}.png"
    fig.savefig(svg_path)
    save_pdf(fig, pdf_path)
    fig.savefig(tiff_path, dpi=600, pil_kwargs={"compression": "tiff_lzw"})
    fig.savefig(png_path, dpi=300)
    qa = audit_figure(fig, svg_path)
    plt.close(fig)
    previews = save_qa_previews(png_path, qa_dir, stem)

    png_image = Image.open(png_path)
    tiff_image = Image.open(tiff_path)
    pdf_bytes = pdf_path.read_bytes()
    pdf_type3_count = pdf_bytes.count(b"/Subtype /Type3")
    pdf_fontfile2_count = pdf_bytes.count(b"/FontFile2")
    pdf_tounicode_count = pdf_bytes.count(b"/ToUnicode")
    tiff_compression = str(tiff_image.info.get("compression", ""))
    expected_png = np.array([WIDTH_MM / 25.4 * 300, HEIGHT_MM / 25.4 * 300])
    expected_tiff = np.array([WIDTH_MM / 25.4 * 600, HEIGHT_MM / 25.4 * 600])
    if np.max(np.abs(np.asarray(png_image.size) - expected_png)) > 1 or np.max(np.abs(np.asarray(tiff_image.size) - expected_tiff)) > 1:
        raise ValueError(f"Raster dimensions changed: PNG {png_image.size}, TIFF {tiff_image.size}")
    color_distances = color_distance_under_deficiency(BLUE, ORANGE)
    qa.update(
        {
            "status": "PASS",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "png_pixels_300dpi": list(png_image.size),
            "tiff_pixels_600dpi": list(tiff_image.size),
            "pdf_type3_font_count": pdf_type3_count,
            "pdf_embedded_truetype_font_count": pdf_fontfile2_count,
            "pdf_tounicode_map_count": pdf_tounicode_count,
            "tiff_compression": tiff_compression,
            "colorblind_pair_distance": color_distances,
            "continuous_palette": {
                "panel": "a",
                "name": ERROR_SCALE_CMAP.name,
                "colors": ["#F2F5F7", "#B9CCDA", "#4C78A8", "#0F4C81"],
                "semantics": "A shared light-to-dark error-magnitude scale aligned with the manuscript blue family.",
            },
            "redundant_encodings": "Kraw/Keff use distinct color, marker shape, and fill; qualification uses color and marker shape.",
            "grayscale_preview": str(Path(previews["grayscale"]).relative_to(root)).replace("\\", "/"),
            "deuteranopia_preview": str(Path(previews["deuteranopia"]).relative_to(root)).replace("\\", "/"),
            "numeric_reconstruction": {
                "K_raw_spread": selected["K_raw_spread"],
                "K_eff_spread": selected["K_eff_spread"],
                "K_eff_below_cap_fraction": selected["K_eff_below_cap_fraction"],
                "selected_Kmax": selected["Kmax"],
                "qualified_candidates": candidates.loc[candidates["qualified"].astype(bool), "Kmax"].tolist(),
            },
        }
    )
    if qa["minimum_font_pt"] < 6.5 or qa["text_overflow_count"] or qa["cross_axes_text_overlap_count"] or not qa["svg_text_editable"] or pdf_type3_count or pdf_fontfile2_count < 1 or pdf_tounicode_count < 1 or tiff_compression != "tiff_lzw" or min(color_distances.values()) < 0.1:
        qa["status"] = "FAIL"
        raise ValueError(f"Figure QA failed: {qa}")

    qa_path = qa_dir / f"{stem}_qa.json"
    qa_path.write_text(json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    input_paths = [config_path, moments_path, candidates_path, gain_path]
    output_paths = [svg_path, pdf_path, tiff_path, png_path]
    manifest = {
        "figure_id": "Fig07_node44r1_gain_calibration",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "nature_figure_contract": str((figure_dir / "figure_contract.md").relative_to(root)).replace("\\", "/"),
        "frozen_inputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in input_paths],
        "source_data": {"file": str(source_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(source_path), "rows": len(source_rows)},
        "outputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in output_paths],
        "qa": {"file": str(qa_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(qa_path), "status": qa["status"]},
    }
    (figure_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"figure": manifest["figure_id"], "status": qa["status"], "outputs": [str(path) for path in output_paths]}, indent=2))


if __name__ == "__main__":
    main()
