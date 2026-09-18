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
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle
from PIL import Image


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 88.0

BLUE = "#21689A"
ORANGE = "#D97721"
TEAL = "#3B9C91"
DEEP_TEAL = "#087C75"
FAILED = "#777777"
GRAY = "#6A6A6A"
LIGHT_GRAY = "#D5D9DC"
BLACK = "#222222"
QUALIFIED_BG = "#EAF4F2"

ERROR_CMAP = LinearSegmentedColormap.from_list(
    "paper_blue_error_scale",
    ["#F4F7F8", "#B9CDDA", "#5E89AD", "#174E78"],
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


def relative(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


def configure_style() -> None:
    mpl.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 7.4,
            "xtick.labelsize": 6.8,
            "ytick.labelsize": 6.8,
            "legend.fontsize": 6.6,
            "axes.linewidth": 0.7,
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


def panel_label(ax: mpl.axes.Axes, label: str, x: float = -0.17, y: float = 1.10) -> None:
    artist = ax.text(
        x,
        y,
        label,
        transform=ax.transAxes,
        fontsize=8.5,
        fontweight="bold",
        ha="left",
        va="bottom",
        color=BLACK,
        clip_on=False,
    )
    artist.set_gid("panel_label")


def save_pdf(fig: mpl.figure.Figure, pdf_path: Path) -> None:
    temp_path = pdf_path.with_name(f".{pdf_path.stem}.tmp.pdf")
    try:
        fig.savefig(temp_path)
        payload = temp_path.read_bytes()
        if pdf_path.exists():
            with pdf_path.open("r+b") as handle:
                handle.seek(0)
                handle.write(payload)
                handle.truncate()
        else:
            temp_path.replace(pdf_path)
    finally:
        temp_path.unlink(missing_ok=True)


def save_qa_previews(png_path: Path, qa_dir: Path, stem: str) -> dict[str, Path]:
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
    Image.fromarray(np.uint8(np.round(simulated * 255))).save(
        deutan_path, dpi=(300, 300)
    )
    return {"grayscale": gray_path, "deuteranopia": deutan_path}


def color_distance_under_deficiency(first: str, second: str) -> dict[str, float]:
    colors = np.array([to_rgb(first), to_rgb(second)])
    matrices = {
        "protanopia": np.array(
            [[0.152, 1.053, -0.205], [0.115, 0.786, 0.099], [-0.004, -0.048, 1.052]]
        ),
        "deuteranopia": np.array(
            [[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]
        ),
    }
    return {
        name: float(
            np.linalg.norm(
                np.clip(colors @ matrix.T, 0, 1)[0]
                - np.clip(colors @ matrix.T, 0, 1)[1]
            )
        )
        for name, matrix in matrices.items()
    }


def audit_figure(fig: mpl.figure.Figure, svg_path: Path) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_box = fig.bbox
    texts = [
        artist
        for artist in fig.findobj(mpl.text.Text)
        if artist.get_visible() and artist.get_text().strip()
    ]
    font_sizes = [float(artist.get_fontsize()) for artist in texts]
    overflow = []
    for artist in texts:
        box = artist.get_window_extent(renderer=renderer)
        if (
            box.x0 < figure_box.x0 - 2
            or box.y0 < figure_box.y0 - 2
            or box.x1 > figure_box.x1 + 2
            or box.y1 > figure_box.y1 + 2
        ):
            overflow.append(artist.get_text())
    svg_text = svg_path.read_text(encoding="utf-8")
    return {
        "minimum_font_pt": min(font_sizes),
        "text_overflow_count": len(overflow),
        "text_overflow": overflow,
        "svg_text_elements": len(re.findall(r"<text(?:\s|>)", svg_text)),
        "svg_text_editable": bool(re.search(r"<text(?:\s|>)", svg_text)),
    }


def validate_inputs(
    config: dict[str, object], candidates: pd.DataFrame, gain: pd.DataFrame
) -> None:
    selected = config["selected"]
    if not np.isclose(selected["Kmax"], 0.5) or not selected["qualified"]:
        raise ValueError("Registered Kmax=0.5 selection changed")
    expected = {0.3: False, 0.4: True, 0.5: True}
    observed = {
        float(row.Kmax): bool(row.qualified) for row in candidates.itertuples()
    }
    if observed != expected:
        raise ValueError(f"Candidate qualification changed: {observed}")
    failed_03 = json.loads(
        candidates.loc[np.isclose(candidates["Kmax"], 0.3), "failed_gates"]
        .iloc[0]
        .replace("'", '"')
    )
    if failed_03 != ["K_eff_spread"]:
        raise ValueError("Kmax=0.3 failure reason changed")
    selected_gain = gain[np.isclose(gain["Kmax"], 0.5)].sort_values("quality_bin")
    if list(selected_gain["quality_bin"]) != [1, 2, 3]:
        raise ValueError("Selected gain audit is incomplete")


def build_source_data(
    source_path: Path,
    regimes: list[str],
    regime_labels: list[str],
    error_mtcn: np.ndarray,
    error_observer: np.ndarray,
    gain_selected: pd.DataFrame,
    candidates: pd.DataFrame,
) -> int:
    excitation_labels = ["Low", "Medium", "High"]
    rows: list[dict[str, object]] = []
    for index, (regime, label) in enumerate(zip(regimes, regime_labels)):
        rows.append(
            {
                "record_type": "error_scale",
                "source": "ModernTCN-delta",
                "regime": regime,
                "regime_label": label,
                "excitation_bin": "Not conditioned",
                "error_scale_deg": error_mtcn[index],
            }
        )
        for excitation_index, excitation in enumerate(excitation_labels):
            rows.append(
                {
                    "record_type": "error_scale",
                    "source": "Qualified observer",
                    "regime": regime,
                    "regime_label": label,
                    "excitation_bin": excitation,
                    "error_scale_deg": error_observer[index, excitation_index],
                }
            )
    for row in gain_selected.itertuples():
        rows.append(
            {
                "record_type": "gain_quantiles",
                "Kmax": row.Kmax,
                "excitation_bin": excitation_labels[int(row.quality_bin) - 1],
                "sample_count": row.sample_count,
                "K_raw_p05": row.K_raw_p05,
                "K_raw_p50": row.K_raw_p50,
                "K_raw_p95": row.K_raw_p95,
                "K_eff_p05": row.K_eff_p05,
                "K_eff_p50": row.K_eff_p50,
                "K_eff_p95": row.K_eff_p95,
                "cap_fraction": row.cap_fraction,
            }
        )
    for row in candidates.itertuples():
        rows.append(
            {
                "record_type": "candidate",
                "Kmax": row.Kmax,
                "mae_ratio": row.mae_ratio,
                "K_eff_spread": row.K_eff_spread,
                "active_fraction": row.active,
                "improve_fraction": row.improve,
                "degrade_fraction": row.degrade,
                "qualified": bool(row.qualified),
                "selected": bool(np.isclose(row.Kmax, 0.5)),
            }
        )
    pd.DataFrame(rows).to_csv(source_path, index=False)
    return len(rows)


def draw_figure(
    error_mtcn: np.ndarray,
    error_observer: np.ndarray,
    gain_selected: pd.DataFrame,
    candidates: pd.DataFrame,
    selected: dict[str, object],
) -> mpl.figure.Figure:
    configure_style()
    fig = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    grid = fig.add_gridspec(
        1,
        3,
        width_ratios=[1.26, 1.42, 1.10],
        left=0.105,
        right=0.985,
        bottom=0.19,
        top=0.80,
        wspace=0.48,
    )

    # Panel a: a single matrix prevents observer-excitation bins from being
    # incorrectly attributed to the regime-only ModernTCN calibration.
    ax_a = fig.add_subplot(grid[0])
    matrix = np.column_stack([error_mtcn, error_observer])
    norm = Normalize(vmin=float(matrix.min()), vmax=float(matrix.max()))
    image = ax_a.imshow(matrix, cmap=ERROR_CMAP, norm=norm, aspect="auto")
    regime_labels = [
        "Flat steady",
        "Slope steady",
        "Flat transition",
        "Slope transition",
    ]
    ax_a.set_yticks(np.arange(4), regime_labels)
    ax_a.set_xticks(
        np.arange(4),
        ["ModernTCN-\ndelta", "Low", "Medium", "High"],
    )
    ax_a.tick_params(length=0, pad=3)
    ax_a.spines[:].set_visible(False)
    for row in range(4):
        for column in range(4):
            rgba = image.cmap(image.norm(matrix[row, column]))
            luminance = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2]
            ax_a.text(
                column,
                row,
                f"{matrix[row, column]:.2f}",
                ha="center",
                va="center",
                fontsize=6.8,
                color="white" if luminance < 0.47 else BLACK,
            )
    ax_a.axvline(0.5, color="white", lw=2.2)
    ax_a.text(
        0,
        1.035,
        "Learned source",
        transform=ax_a.get_xaxis_transform(),
        ha="center",
        va="bottom",
        color=GRAY,
        fontsize=6.6,
    )
    ax_a.text(
        2,
        1.035,
        "Observer excitation",
        transform=ax_a.get_xaxis_transform(),
        ha="center",
        va="bottom",
        color=GRAY,
        fontsize=6.6,
    )
    ax_a.set_title("Conditioned source-error scale", pad=22)
    panel_label(ax_a, "a", x=-0.30, y=1.18)
    colorbar = fig.colorbar(
        image,
        ax=ax_a,
        orientation="horizontal",
        fraction=0.07,
        pad=0.18,
        aspect=24,
    )
    colorbar.set_label(r"$\sqrt{\mathrm{E}[e^2]}$ (deg)", labelpad=2)
    colorbar.ax.tick_params(labelsize=6.6, length=2)
    colorbar.outline.set_linewidth(0.6)

    # Panel b: selected-candidate sample quantiles, not confidence intervals.
    ax_b = fig.add_subplot(grid[1])
    y = np.array([2.0, 1.0, 0.0])
    offsets = {"K_raw": 0.10, "K_eff": -0.10}
    styles = {
        "K_raw": (BLUE, "o", "white", r"$K^{\mathrm{raw}}$"),
        "K_eff": (ORANGE, "s", ORANGE, r"$K^{\mathrm{eff}}$"),
    }
    for prefix in ("K_raw", "K_eff"):
        color, marker, face, label = styles[prefix]
        median = gain_selected[f"{prefix}_p50"].to_numpy(float)
        low = gain_selected[f"{prefix}_p05"].to_numpy(float)
        high = gain_selected[f"{prefix}_p95"].to_numpy(float)
        ax_b.errorbar(
            median,
            y + offsets[prefix],
            xerr=np.vstack([median - low, high - median]),
            fmt=marker,
            ms=4.7,
            lw=1.2,
            capsize=2.6,
            color=color,
            markerfacecolor=face,
            markeredgecolor=color,
            markeredgewidth=1.0,
            label=label,
            zorder=3,
        )
    ax_b.axvline(
        0.5,
        color=BLACK,
        lw=0.8,
        ls=(0, (4, 2)),
        zorder=1,
    )
    ax_b.text(
        0.5,
        2.47,
        r"cap $K_{\max}=0.5$",
        ha="center",
        va="top",
        fontsize=6.5,
        color=BLACK,
    )
    counts = gain_selected["sample_count"].astype(int).to_numpy()
    ax_b.set_yticks(y, ["", "", ""])
    for y_value, label in zip(
        y,
        [
            f"Low  (n={counts[0]:,})",
            f"Medium  (n={counts[1]:,})",
            f"High  (n={counts[2]:,})",
        ],
    ):
        ax_b.text(
            0.018,
            y_value,
            label,
            ha="left",
            va="center",
            fontsize=6.7,
            color=BLACK,
        )
    ax_b.set_xlim(0.0, 0.76)
    ax_b.set_ylim(-0.64, 2.55)
    ax_b.set_xticks([0.0, 0.2, 0.4, 0.6])
    ax_b.set_xlabel("Fusion gain")
    ax_b.legend(
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=2,
        handletextpad=0.5,
        columnspacing=1.2,
    )
    ax_b.text(
        0.02,
        -0.50,
        "64.49% capped; 35.37% at least 0.01 below cap",
        ha="left",
        va="center",
        fontsize=6.35,
        color=GRAY,
    )
    ax_b.set_title("Selected cap: gain quantiles", pad=23)
    panel_label(ax_b, "b", x=-0.24, y=1.18)

    # Panel c: discrete candidates are not connected. The selected annotation
    # is tied to validation MAE ranking rather than to maximum gain spread.
    ax_c = fig.add_subplot(grid[2])
    x_gate = 0.02
    y_gate = 0.95
    x_min, x_max = 0.005, 0.235
    y_min, y_max = 0.882, 0.956
    ax_c.add_patch(
        Rectangle(
            (x_gate, y_min),
            x_max - x_gate,
            y_gate - y_min,
            facecolor=QUALIFIED_BG,
            edgecolor="none",
            zorder=0,
        )
    )
    ax_c.axvline(x_gate, color=GRAY, lw=0.8, ls=(0, (3, 2)), zorder=1)
    ax_c.axhline(y_gate, color=GRAY, lw=0.8, ls=(0, (3, 2)), zorder=1)
    for row in candidates.itertuples():
        kmax = float(row.Kmax)
        x_value = float(row.K_eff_spread)
        y_value = float(row.mae_ratio)
        if np.isclose(kmax, 0.3):
            ax_c.scatter(
                x_value,
                y_value,
                s=44,
                marker="X",
                color=FAILED,
                zorder=4,
            )
            ax_c.annotate(
                "0.3 failed\nspread gate",
                (x_value, y_value),
                xytext=(0.037, 0.929),
                textcoords="data",
                ha="left",
                va="center",
                fontsize=6.4,
                color=FAILED,
                arrowprops={"arrowstyle": "-", "lw": 0.65, "color": FAILED},
            )
        elif np.isclose(kmax, 0.4):
            ax_c.scatter(
                x_value,
                y_value,
                s=42,
                marker="o",
                color=TEAL,
                edgecolor="white",
                linewidth=0.7,
                zorder=4,
            )
            ax_c.annotate(
                "0.4 qualified",
                (x_value, y_value),
                xytext=(0.096, 0.910),
                textcoords="data",
                ha="right",
                va="center",
                fontsize=6.4,
                color=GRAY,
            )
        else:
            ax_c.scatter(
                x_value,
                y_value,
                s=82,
                marker="o",
                facecolor="white",
                edgecolor=DEEP_TEAL,
                linewidth=1.2,
                zorder=4,
            )
            ax_c.scatter(
                x_value,
                y_value,
                s=34,
                marker="o",
                color=DEEP_TEAL,
                zorder=5,
            )
            ax_c.annotate(
                "0.5 selected\nlowest qualified MAE ratio",
                (x_value, y_value),
                xytext=(0.205, 0.894),
                textcoords="data",
                ha="right",
                va="bottom",
                fontsize=6.4,
                color=DEEP_TEAL,
                arrowprops={"arrowstyle": "-", "lw": 0.7, "color": DEEP_TEAL},
            )
    ax_c.text(
        0.023,
        y_max - 0.002,
        "spread gate 0.02",
        ha="left",
        va="top",
        fontsize=6.2,
        color=GRAY,
    )
    ax_c.text(
        x_max - 0.002,
        y_gate - 0.001,
        "MAE gate 0.95",
        ha="right",
        va="top",
        fontsize=6.2,
        color=GRAY,
    )
    ax_c.set_xlim(x_min, x_max)
    ax_c.set_ylim(y_min, y_max)
    ax_c.set_xticks([0.02, 0.10, 0.20])
    ax_c.set_yticks([0.89, 0.91, 0.93, 0.95])
    ax_c.set_xlabel(r"$K^{\mathrm{eff}}$ P95-P05 spread")
    ax_c.set_ylabel("Fusion / ModernTCN MAE ratio")
    ax_c.set_title("Candidate qualification", pad=23)
    panel_label(ax_c, "c", x=-0.25, y=1.18)

    return fig


def main() -> None:
    root = project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    source_dir = figure_dir / "source_data"
    output_dir = figure_dir / "output"
    qa_dir = figure_dir / "qa"
    for directory in (source_dir, output_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    frozen = (
        root
        / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/06_uncertainty_calibration_v3"
    )
    config_path = frozen / "selected_fusion_config.json"
    moments_path = frozen / "empirical_quality_uncertainty_tables.json"
    candidates_path = frozen / "candidate_table.csv"
    gain_path = frozen / "quality_gain_audit.csv"

    config = json.loads(config_path.read_text(encoding="utf-8"))
    moments = json.loads(moments_path.read_text(encoding="utf-8"))
    candidates = pd.read_csv(candidates_path)
    gain = pd.read_csv(gain_path)
    validate_inputs(config, candidates, gain)

    if config["tables"] != moments["tables"]:
        raise ValueError("Frozen moment tables disagree")
    regimes = config["quality_model"]["regime_order"]
    p_mtcn = np.asarray(moments["tables"]["P_tcn_total"], dtype=float)
    p_observer = np.asarray(moments["tables"]["P_observer_total"], dtype=float)
    if p_mtcn.shape != (4, 3) or p_observer.shape != (4, 3):
        raise ValueError("Expected four-regime by three-excitation moment tables")
    if not np.allclose(p_mtcn, p_mtcn[:, [0]]):
        raise ValueError("ModernTCN moment table is no longer regime-only")

    error_mtcn = np.rad2deg(np.sqrt(p_mtcn[:, 0]))
    error_observer = np.rad2deg(np.sqrt(p_observer))
    gain_selected = gain[np.isclose(gain["Kmax"], 0.5)].sort_values("quality_bin")
    selected = config["selected"]

    source_path = source_dir / "fig07_node44r1_gain_calibration_source_data.csv"
    source_rows = build_source_data(
        source_path,
        regimes,
        ["Flat steady", "Slope steady", "Flat transition", "Slope transition"],
        error_mtcn,
        error_observer,
        gain_selected,
        candidates,
    )

    fig = draw_figure(
        error_mtcn,
        error_observer,
        gain_selected,
        candidates,
        selected,
    )
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
    expected_png = np.array([WIDTH_MM / 25.4 * 300, HEIGHT_MM / 25.4 * 300])
    expected_tiff = np.array([WIDTH_MM / 25.4 * 600, HEIGHT_MM / 25.4 * 600])
    if np.max(np.abs(np.asarray(png_image.size) - expected_png)) > 1:
        raise ValueError(f"PNG dimensions changed: {png_image.size}")
    if np.max(np.abs(np.asarray(tiff_image.size) - expected_tiff)) > 1:
        raise ValueError(f"TIFF dimensions changed: {tiff_image.size}")

    pdf_bytes = pdf_path.read_bytes()
    color_distances = color_distance_under_deficiency(BLUE, ORANGE)
    qa.update(
        {
            "status": "PASS",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "png_pixels_300dpi": list(png_image.size),
            "tiff_pixels_600dpi": list(tiff_image.size),
            "pdf_type3_font_count": pdf_bytes.count(b"/Subtype /Type3"),
            "pdf_embedded_truetype_font_count": pdf_bytes.count(b"/FontFile2"),
            "pdf_tounicode_map_count": pdf_bytes.count(b"/ToUnicode"),
            "tiff_compression": str(tiff_image.info.get("compression", "")),
            "raw_effective_color_distance": color_distances,
            "redundant_encodings": (
                "Kraw/Keff use color, marker shape, and fill; candidate states use "
                "marker shape, fill, outline, and direct labels."
            ),
            "statistics": {
                "interval_definition": "validation-sample P05-P50-P95 quantiles; not confidence intervals",
                "valid_nonfallback_samples": int(selected["valid_nonfallback_samples"]),
                "candidate_cases": int(selected["case_count"]),
                "selected_Kmax": float(selected["Kmax"]),
                "Kmax_cap_fraction": float(selected["Kmax_cap_fraction"]),
                "K_eff_below_cap_fraction": float(
                    selected["K_eff_below_cap_fraction"]
                ),
            },
            "grayscale_preview": relative(previews["grayscale"], root),
            "deuteranopia_preview": relative(previews["deuteranopia"], root),
        }
    )
    if (
        qa["minimum_font_pt"] < 6.0
        or qa["text_overflow_count"]
        or not qa["svg_text_editable"]
        or qa["pdf_type3_font_count"]
        or qa["pdf_embedded_truetype_font_count"] < 1
        or qa["pdf_tounicode_map_count"] < 1
        or qa["tiff_compression"] != "tiff_lzw"
        or min(color_distances.values()) < 0.1
    ):
        qa["status"] = "FAIL"

    qa_path = qa_dir / f"{stem}_qa.json"
    qa_path.write_text(json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    if qa["status"] != "PASS":
        raise ValueError(f"Figure QA failed: {qa}")

    input_paths = [config_path, moments_path, candidates_path, gain_path]
    output_paths = [svg_path, pdf_path, tiff_path, png_path]
    manifest = {
        "figure_id": "Fig07_node44r1_gain_calibration",
        "variant": "figures_final_1 redesign",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "figure_contract": relative(figure_dir / "figure_contract.md", root),
        "frozen_inputs": [
            {"file": relative(path, root), "sha256": sha256(path)}
            for path in input_paths
        ],
        "source_data": {
            "file": relative(source_path, root),
            "sha256": sha256(source_path),
            "rows": source_rows,
        },
        "outputs": [
            {"file": relative(path, root), "sha256": sha256(path)}
            for path in output_paths
        ],
        "qa": {
            "file": relative(qa_path, root),
            "sha256": sha256(qa_path),
            "status": qa["status"],
        },
    }
    manifest_path = figure_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "figure": manifest["figure_id"],
                "status": qa["status"],
                "outputs": [str(path) for path in output_paths],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
