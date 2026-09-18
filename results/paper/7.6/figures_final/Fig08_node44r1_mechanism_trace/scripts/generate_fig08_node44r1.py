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
from matplotlib.patches import Patch
from PIL import Image


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 112.0
BLACK = "#222222"
BLUE = "#0072B2"
ORANGE = "#D55E00"
GREEN = "#009E73"
RED = "#B24A47"
GRAY = "#767676"
FALLBACK = "#D9D9D9"


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


def panel_label(ax: mpl.axes.Axes, label: str) -> None:
    artist = ax.text(
        -0.075,
        1.02,
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


def shade_fallback(ax: mpl.axes.Axes, time: np.ndarray, fallback: np.ndarray) -> None:
    ax.fill_between(
        time,
        0,
        1,
        where=fallback,
        transform=ax.get_xaxis_transform(),
        step="post",
        color=FALLBACK,
        alpha=0.62,
        linewidth=0,
        zorder=0,
    )


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
                overlaps.append(
                    {
                        "left": left_artist.get_text(),
                        "left_axes": list(left_artist.axes.get_position().bounds) if left_artist.axes is not None else None,
                        "left_box": list(left_box.bounds),
                        "right": right_artist.get_text(),
                        "right_axes": list(right_artist.axes.get_position().bounds) if right_artist.axes is not None else None,
                        "right_box": list(right_box.bounds),
                    }
                )
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

    case_dir = root / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/11_formal_six_path/cases/ADAPTIVE/s42/p02_sharp_turn_transition"
    trace_path = case_dir / "trace.csv"
    debug_path = case_dir / "node44r1_runtime_debug.csv"
    manifest_path = case_dir / "case_manifest.json"
    metrics_path = case_dir / "case_metrics.json"
    trace = pd.read_csv(trace_path)
    debug = pd.read_csv(debug_path)
    case_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))

    required_trace = {"t_s", "theta_true"}
    required_debug = {"step", "theta_tcn", "theta_imu", "theta_fused", "K_eff", "Kmax", "correction_prev", "correction", "target_correction", "NIS", "fallback", "rate_limit_flag", "reset_flag", "fallback_reason"}
    if not required_trace.issubset(trace) or not required_debug.issubset(debug):
        raise ValueError("Frozen trace/debug schema is incomplete")
    if case_manifest["path_id"] != "p02_sharp_turn_transition" or int(case_manifest["model_seed"]) != 42:
        raise ValueError("Mechanism case is not fixed P2/model seed 42")
    if len(trace) != 5201 or len(debug) != 5200:
        raise ValueError("Expected 5201 trace samples and 5200 runtime updates")
    if not np.array_equal(debug["step"].to_numpy(int), np.arange(1, 5201)):
        raise ValueError("Runtime update index changed")
    time = trace["t_s"].to_numpy(float)[1:]
    if not np.allclose(time, debug["step"].to_numpy(float) * 0.01, rtol=0, atol=1e-12):
        raise ValueError("Trace/debug time alignment failed")

    fallback = debug["fallback"].to_numpy(bool)
    reset = debug["reset_flag"].to_numpy(bool)
    correction = debug["correction"].to_numpy(float)
    correction_prev = debug["correction_prev"].to_numpy(float)
    identity_error = np.max(np.abs(debug.loc[fallback, "theta_fused"].to_numpy(float) - debug.loc[fallback, "theta_tcn"].to_numpy(float)))
    fallback_correction = np.max(np.abs(correction[fallback]))
    normal_rate_deg_s = np.abs(np.rad2deg(correction[~reset] - correction_prev[~reset])) / 0.01
    max_normal_rate = float(normal_rate_deg_s.max())
    if identity_error > 1e-12 or fallback_correction > 1e-12:
        raise ValueError("Exact fallback identity reconstruction failed")
    if max_normal_rate > 5.0 + 1e-10:
        raise ValueError(f"Normal correction rate exceeds 5 deg/s: {max_normal_rate}")
    expected_counts = {
        "fallback_count": int(fallback.sum()),
        "rate_limit_flag_count": int(debug["rate_limit_flag"].sum()),
        "sign_change_flag_count": int(debug["sign_change_flag"].sum()),
    }
    for key, value in expected_counts.items():
        if int(metrics[key]) != value:
            raise ValueError(f"Frozen {key} does not match debug reconstruction")

    source = pd.DataFrame(
        {
            "t_s": time,
            "reference_grade_deg": np.rad2deg(trace["theta_true"].to_numpy(float)[1:]),
            "mtcn_delta_grade_deg": np.rad2deg(debug["theta_tcn"].to_numpy(float)),
            "qualified_observer_grade_deg": np.rad2deg(debug["theta_imu"].to_numpy(float)),
            "fused_grade_deg": np.rad2deg(debug["theta_fused"].to_numpy(float)),
            "K_eff": debug["K_eff"].to_numpy(float),
            "Kmax": debug["Kmax"].to_numpy(float),
            "target_correction_deg": np.rad2deg(debug["target_correction"].to_numpy(float)),
            "applied_correction_deg": np.rad2deg(correction),
            "NIS": debug["NIS"].to_numpy(float),
            "fallback": fallback.astype(int),
            "rate_limit_active": debug["rate_limit_flag"].to_numpy(int),
            "fallback_reason": debug["fallback_reason"].fillna("").astype(str),
        }
    )
    source_path = source_dir / "fig08_node44r1_mechanism_trace_source_data.csv"
    source.to_csv(source_path, index=False)

    configure_style()
    fig, axes = plt.subplots(4, 1, figsize=(WIDTH_MM * MM, HEIGHT_MM * MM), sharex=True, gridspec_kw={"height_ratios": [1.55, 0.78, 0.98, 0.82], "hspace": 0.32})
    fig.subplots_adjust(left=0.095, right=0.985, bottom=0.105, top=0.89)
    for axis in axes:
        shade_fallback(axis, time, fallback)
        axis.set_xlim(time[0], time[-1])
        axis.tick_params(direction="out")

    axes[0].plot(time, source["reference_grade_deg"], color=BLACK, lw=1.35, label="Reference")
    axes[0].plot(time, source["mtcn_delta_grade_deg"], color=BLUE, lw=0.9, ls=(0, (4, 2)), label="ModernTCN-delta")
    axes[0].plot(time, source["qualified_observer_grade_deg"], color=ORANGE, lw=0.85, ls=(0, (1, 1.5)), label="Qualified observer")
    axes[0].plot(time, source["fused_grade_deg"], color=GREEN, lw=1.05, label="Fused")
    axes[0].set_ylabel("Grade (deg)")
    axes[0].set_yticks([-5, 0, 5])
    handles, labels = axes[0].get_legend_handles_labels()
    handles.append(Patch(facecolor=FALLBACK, edgecolor="none", label="Fallback"))
    labels.append("Fallback")
    axes[0].legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, 1.08), ncol=5, handlelength=2.4, columnspacing=1.25)
    panel_label(axes[0], "a")

    axes[1].plot(time, source["K_eff"], color=GREEN, lw=1.0)
    axes[1].axhline(0.5, color=BLACK, lw=0.75, ls=(0, (4, 2)))
    axes[1].text(51.6, 0.515, "Kmax", ha="right", va="bottom", fontsize=6.5, color=BLACK)
    axes[1].set_ylabel("Effective gain")
    axes[1].set_ylim(-0.03, 0.57)
    axes[1].set_yticks([0, 0.25, 0.5], labels=["0", "0.25", "0.5"])
    panel_label(axes[1], "b")

    axes[2].plot(time, source["target_correction_deg"], color=ORANGE, lw=0.8, ls=(0, (3, 2)), label="Target")
    axes[2].plot(time, source["applied_correction_deg"], color=BLUE, lw=1.0, label="Applied")
    rate_active = source["rate_limit_active"].to_numpy(bool)
    axes[2].scatter(time[rate_active], source.loc[rate_active, "applied_correction_deg"], s=8, marker="|", color=RED, linewidths=0.8, label="Rate limit", zorder=4)
    axes[2].axhline(0.5, color=GRAY, lw=0.6, ls=(0, (2, 2)))
    axes[2].axhline(-0.5, color=GRAY, lw=0.6, ls=(0, (2, 2)))
    axes[2].axhline(0, color=BLACK, lw=0.45)
    axes[2].set_ylabel("Correction (deg)")
    axes[2].set_ylim(-0.58, 0.58)
    axes[2].set_yticks([-0.5, 0, 0.5], labels=["-0.5", "0", "0.5"])
    axes[2].legend(loc="upper right", ncol=3, handlelength=2.0, columnspacing=1.0)
    panel_label(axes[2], "c")

    axes[3].plot(time, source["NIS"], color=BLUE, lw=0.9)
    axes[3].axhline(9, color=ORANGE, lw=0.7, ls=(0, (4, 2)))
    axes[3].axhline(25, color=RED, lw=0.7, ls=(0, (2, 2)))
    axes[3].set_yscale("symlog", linthresh=1.0, linscale=0.9, base=10)
    axes[3].set_ylim(0, 30)
    axes[3].set_yticks([0, 1, 9], labels=["0", "1", "9"])
    axes[3].set_ylabel("NIS")
    axes[3].set_xlabel("Time (s)")
    axes[3].set_xticks(np.arange(0, 51, 10))
    axes[3].text(51.6, 9.5, "downweight", ha="right", va="bottom", fontsize=6.5, color=ORANGE)
    axes[3].text(51.6, 25.5, "reject", ha="right", va="bottom", fontsize=6.5, color=RED)
    panel_label(axes[3], "d")

    stem = "fig08_node44r1_mechanism_trace"
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
    distances = colorblind_distances([BLUE, ORANGE, GREEN])
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
            "redundant_encodings": "All four grade traces use distinct line style and color; fallback uses neutral shading; rate-limit activity uses marker shape.",
            "grayscale_preview": str(previews["grayscale"].relative_to(root)).replace("\\", "/"),
            "deuteranopia_preview": str(previews["deuteranopia"].relative_to(root)).replace("\\", "/"),
            "numeric_reconstruction": {
                "fixed_case": "P2 Sharp-turn transition, model seed 42",
                "runtime_updates": len(debug),
                "fallback_count": int(fallback.sum()),
                "rate_limit_count": int(debug["rate_limit_flag"].sum()),
                "sign_change_count": int(debug["sign_change_flag"].sum()),
                "fallback_identity_max_abs_rad": float(identity_error),
                "fallback_correction_max_abs_rad": float(fallback_correction),
                "maximum_normal_correction_rate_deg_s": max_normal_rate,
                "maximum_NIS": float(debug["NIS"].max()),
            },
        }
    )
    if qa["minimum_font_pt"] < 6.5 or qa["text_overflow_count"] or qa["cross_axes_text_overlap_count"] or not qa["svg_text_editable"] or pdf_type3_count or pdf_fontfile2_count < 1 or pdf_tounicode_count < 1 or tiff_compression != "tiff_lzw" or min(distances.values()) < 0.08:
        qa["status"] = "FAIL"
        raise ValueError(f"Figure QA failed: {qa}")

    qa_path = qa_dir / f"{stem}_qa.json"
    qa_path.write_text(json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    inputs = [trace_path, debug_path, manifest_path, metrics_path]
    outputs = [svg_path, pdf_path, tiff_path, png_path]
    manifest = {
        "figure_id": "Fig08_node44r1_mechanism_trace",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "nature_figure_contract": str((figure_dir / "figure_contract.md").relative_to(root)).replace("\\", "/"),
        "frozen_inputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in inputs],
        "source_data": {"file": str(source_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(source_path), "rows": len(source)},
        "outputs": [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256(path)} for path in outputs],
        "qa": {"file": str(qa_path.relative_to(root)).replace("\\", "/"), "sha256": sha256(qa_path), "status": qa["status"]},
    }
    (figure_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"figure": manifest["figure_id"], "status": qa["status"], "outputs": [str(path) for path in outputs]}, indent=2))


if __name__ == "__main__":
    main()
