from __future__ import annotations

import hashlib
import json
import math
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


def relpath(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


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
            "legend.fontsize": 6.2,
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


def replay_rkf_fusion(
    debug: pd.DataFrame,
    rkf_debug: pd.DataFrame,
    selected: dict,
) -> pd.DataFrame:
    tables = selected["tables"]
    kmax = float(selected["selected"]["Kmax"])
    floor = np.deg2rad(0.02) ** 2
    correction_step = np.deg2rad(5.0) * 0.01
    correction_limit = np.deg2rad(0.5)
    innovation_gate = np.deg2rad(2.0)

    theta_tcn = debug["theta_tcn"].to_numpy(float)
    theta_rkf = rkf_debug["theta_rkf"].to_numpy(float)
    confidence = np.clip(debug["conf_main"].to_numpy(float), 0.0, 1.0)
    regime = debug["regime_index"].to_numpy(int) - 1
    quality_bin = debug["quality_bin"].to_numpy(int) - 1
    tcn_ready = debug["tcn_ready"].to_numpy(bool)
    observer_valid = rkf_debug["observer_valid"].to_numpy(bool)

    count = len(debug)
    values = {
        name: np.zeros(count, dtype=float)
        for name in (
            "rkf_grade_rad",
            "fused_grade_rad",
            "K_eff",
            "Kmax",
            "target_correction_rad",
            "applied_correction_rad",
            "NIS",
        )
    }
    flags = {
        name: np.zeros(count, dtype=bool)
        for name in ("fallback", "rate_limit_active", "nis_downweight", "nis_reject")
    }
    reasons: list[str] = []
    correction = 0.0

    for index in range(count):
        r = int(regime[index])
        q = int(quality_bin[index])
        if not (0 <= r < 4 and 0 <= q < 3):
            raise ValueError(f"Invalid regime/quality index at update {index + 1}")

        pbase = max(float(tables["P_tcn_total"][r][q]), floor)
        pobs = max(float(tables["P_observer_total"][r][q]), floor)
        inflation = 2.0 - confidence[index]
        ptcn = inflation * pbase
        cross_error = math.sqrt(inflation) * float(tables["cross_error_total"][r][q])
        bound = 0.95 * math.sqrt(ptcn * pobs)
        cross_error = float(np.clip(cross_error, -bound, bound))

        innovation = theta_rkf[index] - theta_tcn[index]
        innovation_variance = max(ptcn + pobs - 2.0 * cross_error, floor)
        nis = innovation**2 / innovation_variance
        kraw = (ptcn - cross_error) / innovation_variance
        nis_weight = 1.0 if nis <= 9.0 else math.sqrt(9.0 / nis)

        reason_parts = []
        if not tcn_ready[index]:
            reason_parts.append("TCN_NOT_READY")
        if not observer_valid[index]:
            reason_parts.append("RKF_INVALID")
        if abs(innovation) > innovation_gate:
            reason_parts.append("ABS_INNOVATION_GATE")
        if nis > 25.0:
            reason_parts.append("NIS_REJECT")
        fallback = bool(reason_parts)
        previous = correction

        if fallback:
            correction = 0.0
            keff = 0.0
            target = 0.0
            rate_limited = False
            fused = theta_tcn[index]
        else:
            keff = min(kmax, max(0.0, kraw)) * nis_weight
            target = float(np.clip(keff * innovation, -correction_limit, correction_limit))
            delta = target - previous
            rate_limited = abs(delta) > correction_step
            correction = previous + float(np.clip(delta, -correction_step, correction_step))
            fused = theta_tcn[index] + correction

        values["rkf_grade_rad"][index] = theta_rkf[index]
        values["fused_grade_rad"][index] = fused
        values["K_eff"][index] = keff
        values["Kmax"][index] = kmax
        values["target_correction_rad"][index] = target
        values["applied_correction_rad"][index] = correction
        values["NIS"][index] = nis
        flags["fallback"][index] = fallback
        flags["rate_limit_active"][index] = rate_limited
        flags["nis_downweight"][index] = nis > 9.0
        flags["nis_reject"][index] = nis > 25.0
        reasons.append("|".join(reason_parts) if reason_parts else "NONE")

    replay = pd.DataFrame({**values, **flags})
    replay["fallback_reason"] = reasons
    return replay


def qa_previews(png_path: Path, qa_dir: Path, stem: str) -> dict[str, Path]:
    image = np.asarray(Image.open(png_path).convert("RGB"), dtype=float) / 255.0
    gray = np.clip(image @ np.array([0.2126, 0.7152, 0.0722]), 0, 1)
    gray_path = qa_dir / f"{stem}_grayscale.png"
    Image.fromarray(np.uint8(np.round(np.repeat(gray[..., None], 3, axis=2) * 255))).save(
        gray_path, dpi=(300, 300)
    )
    matrix = np.array(
        [[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]
    )
    simulated = np.clip(image @ matrix.T, 0, 1)
    deutan_path = qa_dir / f"{stem}_deuteranopia.png"
    Image.fromarray(np.uint8(np.round(simulated * 255))).save(deutan_path, dpi=(300, 300))
    return {"grayscale": gray_path, "deuteranopia": deutan_path}


def audit_figure(fig: mpl.figure.Figure, svg_path: Path) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_box = fig.bbox
    texts = [
        artist
        for artist in fig.findobj(mpl.text.Text)
        if artist.get_visible() and artist.get_text().strip()
    ]
    overflow = []
    boxes = []
    for artist in texts:
        box = artist.get_window_extent(renderer=renderer)
        boxes.append((artist, box))
        if (
            box.x0 < figure_box.x0 - 2
            or box.y0 < figure_box.y0 - 2
            or box.x1 > figure_box.x1 + 2
            or box.y1 > figure_box.y1 + 2
        ):
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
                overlaps.append((left_artist.get_text(), right_artist.get_text()))
    return {
        "minimum_font_pt": min(float(artist.get_fontsize()) for artist in texts),
        "text_overflow_count": len(overflow),
        "text_overflow": overflow,
        "cross_axes_text_overlap_count": len(overlaps),
        "cross_axes_text_overlaps": overlaps,
        "svg_text_elements": len(re.findall(r"<text(?:\s|>)", svg_path.read_text(encoding="utf-8"))),
    }


def colorblind_distances(colors: list[str]) -> dict[str, float]:
    values = np.asarray([to_rgb(color) for color in colors])
    matrices = {
        "protanopia": np.array(
            [[0.152, 1.053, -0.205], [0.115, 0.786, 0.099], [-0.004, -0.048, 1.052]]
        ),
        "deuteranopia": np.array(
            [[0.367, 0.861, -0.228], [0.280, 0.673, 0.047], [-0.012, 0.043, 0.969]]
        ),
    }
    result = {}
    for name, matrix in matrices.items():
        transformed = np.clip(values @ matrix.T, 0, 1)
        distances = [
            np.linalg.norm(transformed[left] - transformed[right])
            for left in range(len(colors))
            for right in range(left + 1, len(colors))
        ]
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

    original_case = (
        root
        / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/11_formal_six_path/cases/ADAPTIVE/s42/p02_sharp_turn_transition"
    )
    rkf_case = (
        root
        / "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/15_rkf_ra_covariance_sensitivity/ra_x2_qg_x05/04_rkf_closed_loop/cases/p02_sharp_turn_transition"
    )
    selected_path = (
        root
        / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/06_uncertainty_calibration_v3/selected_fusion_config.json"
    )
    original_trace_path = original_case / "trace.csv"
    original_debug_path = original_case / "node44r1_runtime_debug.csv"
    rkf_trace_path = rkf_case / "trace.csv"
    rkf_debug_path = rkf_case / "rkf_runtime_debug.csv"
    rkf_manifest_path = rkf_case / "case_manifest.json"

    original_trace = pd.read_csv(original_trace_path)
    original_debug = pd.read_csv(original_debug_path)
    rkf_trace = pd.read_csv(rkf_trace_path)
    rkf_debug = pd.read_csv(rkf_debug_path)
    rkf_manifest = json.loads(rkf_manifest_path.read_text(encoding="utf-8"))
    selected = json.loads(selected_path.read_text(encoding="utf-8"))

    if len(original_trace) != 5201 or len(original_debug) != 5200:
        raise ValueError("Original Fig08 P2 record length changed")
    if len(rkf_trace) != 5201 or len(rkf_debug) != 5200:
        raise ValueError("RKF P2 record length changed")
    if rkf_manifest["path_id"] != "p02_sharp_turn_transition":
        raise ValueError("RKF source is not P2")
    if float(rkf_manifest["accel_measurement_covariance_scale"]) != 2.0:
        raise ValueError("RKF source is not Ra x2")
    if float(rkf_manifest["gyro_process_covariance_scale"]) != 0.5:
        raise ValueError("RKF source is not Qg x0.5")
    if not np.array_equal(original_trace["t_s"].to_numpy(float), rkf_trace["t_s"].to_numpy(float)):
        raise ValueError("Original and RKF time arrays differ")
    if not np.array_equal(
        original_trace["theta_true"].to_numpy(float), rkf_trace["theta_true"].to_numpy(float)
    ):
        raise ValueError("Original and RKF truth arrays differ")
    if not np.array_equal(rkf_debug["step"].to_numpy(int), np.arange(1, 5201)):
        raise ValueError("RKF update index changed")

    replay = replay_rkf_fusion(original_debug, rkf_debug, selected)
    time = original_trace["t_s"].to_numpy(float)[1:]
    source = pd.DataFrame(
        {
            "t_s": time,
            "reference_grade_deg": np.rad2deg(original_trace["theta_true"].to_numpy(float)[1:]),
            "mtcn_delta_grade_deg": np.rad2deg(original_debug["theta_tcn"].to_numpy(float)),
            "rkf_ra_x2_qg_x05_grade_deg": np.rad2deg(replay["rkf_grade_rad"].to_numpy(float)),
            "fused_grade_deg": np.rad2deg(replay["fused_grade_rad"].to_numpy(float)),
            "K_eff": replay["K_eff"].to_numpy(float),
            "Kmax": replay["Kmax"].to_numpy(float),
            "target_correction_deg": np.rad2deg(replay["target_correction_rad"].to_numpy(float)),
            "applied_correction_deg": np.rad2deg(replay["applied_correction_rad"].to_numpy(float)),
            "NIS": replay["NIS"].to_numpy(float),
            "fallback": replay["fallback"].to_numpy(int),
            "rate_limit_active": replay["rate_limit_active"].to_numpy(int),
            "fallback_reason": replay["fallback_reason"].astype(str),
        }
    )
    source_path = source_dir / "fig08_rkf_ra_x2_qg_x05_mechanism_trace_source_data.csv"
    source.to_csv(source_path, index=False)

    configure_style()
    fig, axes = plt.subplots(
        4,
        1,
        figsize=(WIDTH_MM * MM, HEIGHT_MM * MM),
        sharex=True,
        gridspec_kw={"height_ratios": [1.55, 0.78, 0.98, 0.82], "hspace": 0.42},
    )
    fig.subplots_adjust(left=0.095, right=0.985, bottom=0.105, top=0.89)
    fallback = source["fallback"].to_numpy(bool)
    for axis in axes:
        shade_fallback(axis, time, fallback)
        axis.set_xlim(time[0], time[-1])
        axis.tick_params(direction="out")

    axes[0].plot(time, source["reference_grade_deg"], color=BLACK, lw=1.35, label="Reference")
    axes[0].plot(
        time,
        source["mtcn_delta_grade_deg"],
        color=BLUE,
        lw=0.9,
        ls=(0, (4, 2)),
        label="ModernTCN-delta",
    )
    axes[0].plot(
        time,
        source["rkf_ra_x2_qg_x05_grade_deg"],
        color=ORANGE,
        lw=0.85,
        ls=(0, (1, 1.5)),
        label="Qualified observer",
    )
    axes[0].plot(time, source["fused_grade_deg"], color=GREEN, lw=1.05, label="Fused replay")
    axes[0].set_ylabel("Grade (deg)")
    axes[0].set_yticks([-5, 0, 5])
    handles, labels = axes[0].get_legend_handles_labels()
    handles.append(Patch(facecolor=FALLBACK, edgecolor="none", label="Fallback"))
    labels.append("Fallback")
    axes[0].legend(
        handles,
        labels,
        loc="lower center",
        bbox_to_anchor=(0.5, 1.08),
        ncol=5,
        handlelength=2.25,
        columnspacing=1.0,
    )
    panel_label(axes[0], "a")

    axes[1].plot(time, source["K_eff"], color=GREEN, lw=1.0)
    axes[1].axhline(0.5, color=BLACK, lw=0.75, ls=(0, (4, 2)))
    axes[1].text(51.6, 0.515, "Kmax", ha="right", va="bottom", fontsize=6.5, color=BLACK)
    axes[1].set_ylabel("Effective gain")
    axes[1].set_ylim(-0.03, 0.57)
    axes[1].set_yticks([0, 0.25, 0.5], labels=["0", "0.25", "0.5"])
    panel_label(axes[1], "b")

    axes[2].plot(
        time,
        source["target_correction_deg"],
        color=ORANGE,
        lw=0.8,
        ls=(0, (3, 2)),
        label="Target",
    )
    axes[2].plot(
        time,
        source["applied_correction_deg"],
        color=BLUE,
        lw=1.0,
        label="Applied",
    )
    rate_active = source["rate_limit_active"].to_numpy(bool)
    axes[2].scatter(
        time[rate_active],
        source.loc[rate_active, "applied_correction_deg"],
        s=8,
        marker="|",
        color=RED,
        linewidths=0.8,
        label="Rate limit",
        zorder=4,
    )
    axes[2].axhline(0.5, color=GRAY, lw=0.6, ls=(0, (2, 2)))
    axes[2].axhline(-0.5, color=GRAY, lw=0.6, ls=(0, (2, 2)))
    axes[2].axhline(0, color=BLACK, lw=0.45)
    axes[2].set_ylabel("Correction (deg)")
    axes[2].set_ylim(-0.58, 0.58)
    axes[2].set_yticks([-0.5, 0, 0.5], labels=["-0.5", "0", "0.5"])
    axes[2].legend(
        loc="lower center",
        bbox_to_anchor=(0.5, 1.015),
        ncol=3,
        handlelength=2.0,
        columnspacing=1.0,
    )
    panel_label(axes[2], "c")

    axes[3].plot(time, source["NIS"], color=BLUE, lw=0.9)
    axes[3].axhline(9, color=ORANGE, lw=0.7, ls=(0, (4, 2)))
    axes[3].axhline(25, color=RED, lw=0.7, ls=(0, (2, 2)))
    axes[3].set_yscale("symlog", linthresh=1.0, linscale=0.9, base=10)
    nis_top = max(30.0, float(np.nanmax(source["NIS"])) * 1.08)
    axes[3].set_ylim(0, nis_top)
    axes[3].set_yticks([0, 1, 9, 25], labels=["0", "1", "9", "25"])
    axes[3].set_ylabel("NIS")
    axes[3].set_xlabel("Time (s)")
    axes[3].set_xticks(np.arange(0, 51, 10))
    axes[3].text(51.6, 9.5, "downweight", ha="right", va="bottom", fontsize=6.5, color=ORANGE)
    axes[3].text(51.6, 25.5, "reject", ha="right", va="bottom", fontsize=6.5, color=RED)
    panel_label(axes[3], "d")

    stem = "fig08_rkf_ra_x2_qg_x05_mechanism_trace"
    svg_path = output_dir / f"{stem}.svg"
    pdf_path = output_dir / f"{stem}.pdf"
    tiff_path = output_dir / f"{stem}.tiff"
    png_path = output_dir / f"{stem}.png"
    fig.savefig(svg_path)
    fig.savefig(pdf_path)
    fig.savefig(tiff_path, dpi=600, pil_kwargs={"compression": "tiff_lzw"})
    fig.savefig(png_path, dpi=300)
    artist_qa = audit_figure(fig, svg_path)
    plt.close(fig)
    previews = qa_previews(png_path, qa_dir, stem)

    identity_error = float(
        np.max(
            np.abs(
                source.loc[fallback, "fused_grade_deg"].to_numpy(float)
                - source.loc[fallback, "mtcn_delta_grade_deg"].to_numpy(float)
            )
        )
    )
    fallback_reasons = source.loc[fallback, "fallback_reason"].value_counts().to_dict()
    png_size = Image.open(png_path).size
    tiff_image = Image.open(tiff_path)
    tiff_size = tiff_image.size
    distances = colorblind_distances([BLUE, ORANGE, GREEN])
    qa = {
        "status": "PASS",
        "candidate_scope": "RKF observer substitution with offline Node44R1 fusion replay; not inserted in manuscript",
        "fixed_case": "P2 Sharp-turn transition, ModernTCN seed 42, RKF sensor seed 4631",
        "rkf_configuration": {"R_a_scale": 2.0, "Q_g_scale": 0.5},
        "alignment": {
            "runtime_updates": len(source),
            "time_start_s": float(time[0]),
            "time_end_s": float(time[-1]),
            "time_exact": True,
            "truth_exact": True,
        },
        "replay": {
            "fallback_count": int(fallback.sum()),
            "fallback_reasons": fallback_reasons,
            "rate_limit_count": int(rate_active.sum()),
            "nis_downweight_count": int(replay["nis_downweight"].sum()),
            "nis_reject_count": int(replay["nis_reject"].sum()),
            "maximum_NIS": float(source["NIS"].max()),
            "fallback_identity_max_abs_deg": identity_error,
            "maximum_abs_correction_deg": float(np.max(np.abs(source["applied_correction_deg"]))),
        },
        "artist_checks": artist_qa,
        "output_checks": {
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "png_pixels_300dpi": list(png_size),
            "tiff_pixels_600dpi": list(tiff_size),
            "tiff_compression": str(tiff_image.info.get("compression", "")),
            "colorblind_minimum_pair_distance": distances,
            "grayscale_preview": relpath(previews["grayscale"], root),
            "deuteranopia_preview": relpath(previews["deuteranopia"], root),
        },
        "paper_tex_modified": False,
        "existing_figure_modified": False,
    }
    if (
        artist_qa["minimum_font_pt"] < 6.2
        or artist_qa["text_overflow_count"]
        or artist_qa["cross_axes_text_overlap_count"]
        or artist_qa["svg_text_elements"] == 0
        or identity_error > 1e-12
        or png_size != (2161, 1322)
        or tiff_size != (4322, 2645)
        or str(tiff_image.info.get("compression", "")) != "tiff_lzw"
        or min(distances.values()) < 0.08
    ):
        qa["status"] = "FAIL"
    qa_path = qa_dir / f"{stem}_qa.json"
    qa_path.write_text(json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    if qa["status"] != "PASS":
        raise ValueError(f"Figure QA failed: {qa}")

    inputs = [
        original_trace_path,
        original_debug_path,
        rkf_trace_path,
        rkf_debug_path,
        rkf_manifest_path,
        selected_path,
    ]
    outputs = [pdf_path, svg_path, png_path, tiff_path]
    manifest = {
        "figure_id": "Fig08_rkf_ra_x2_qg_x05_mechanism_trace",
        "status": "CANDIDATE_NOT_INSERTED_IN_TEX",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "method": "RKF observer substitution followed by offline replay of the frozen Node44R1 fusion contract",
        "frozen_inputs": [
            {"file": relpath(path, root), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in inputs
        ],
        "source_data": {
            "file": relpath(source_path, root),
            "rows": len(source),
            "sha256": sha256(source_path),
        },
        "outputs": [
            {"file": relpath(path, root), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in outputs
        ],
        "qa": {"file": relpath(qa_path, root), "status": qa["status"], "sha256": sha256(qa_path)},
        "paper_tex_modified": False,
        "existing_figure_modified": False,
    }
    manifest_path = figure_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"figure": manifest["figure_id"], "status": qa["status"], "outputs": [str(path) for path in outputs]}, indent=2))


if __name__ == "__main__":
    main()
