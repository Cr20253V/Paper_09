from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree

import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from PIL import Image, ImageOps


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 100.0
DPI = 600
BENCHMARK_WARMUP_S = 0.5
OUTPUT_STEM = "fig05_representative_four_estimator_trace"

METHODS = (
    {
        "id": "modern_tcn_delta_bank_124",
        "label": "ModernTCN-delta",
        "column": "modern_tcn_delta_deg",
        "color": "#0072B2",
        "linestyle": "-",
        "linewidth": 1.15,
        "zorder": 5,
        "relative_path": Path(
            "results/modern_tcn_metric_rebuild/30_rhofmd_lag_rescreen/"
            "04_full_closed_loop/db124/s73/"
            "path_closed_loop_sharp_turn_transition_theta10_v1/"
            "delta_bank_124_seed73_out.mat"
        ),
    },
    {
        "id": "modern_tcn_22d",
        "label": "ModernTCN-22D",
        "column": "modern_tcn_22d_deg",
        "color": "#D55E00",
        "linestyle": (0, (6.0, 2.2)),
        "linewidth": 0.95,
        "zorder": 4,
        "relative_path": Path(
            "results/modern_tcn_metric_rebuild/32_four_algorithm_10seed_closed_loop/"
            "02_modern_fixed_full_closed_loop/"
            "path_closed_loop_sharp_turn_transition_theta10_v1/"
            "modern_fixed_seed73_out.mat"
        ),
    },
    {
        "id": "gru_22d",
        "label": "GRU-22D",
        "column": "gru_22d_deg",
        "color": "#009E73",
        "linestyle": (0, (5.0, 2.0, 1.2, 2.0)),
        "linewidth": 0.90,
        "zorder": 3,
        "relative_path": Path(
            "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
            "01_A1_algorithm_comparison/04_closed_loop/raw/gru_22d/seed73/"
            "path_closed_loop_sharp_turn_transition_theta10_v1/"
            "gru_22d_seed73_out.mat"
        ),
    },
    {
        "id": "tcn_22d",
        "label": "TCN-22D",
        "column": "tcn_22d_deg",
        "color": "#CC79A7",
        "linestyle": (0, (1.2, 1.8)),
        "linewidth": 0.90,
        "zorder": 2,
        "relative_path": Path(
            "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
            "01_A1_algorithm_comparison/04_closed_loop/raw/tcn_22d/seed73/"
            "path_closed_loop_sharp_turn_transition_theta10_v1/"
            "tcn_22d_seed73_out.mat"
        ),
    },
)


def configure_style() -> None:
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans", "Liberation Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42
    plt.rcParams["font.size"] = 7.0
    plt.rcParams["axes.labelsize"] = 7.0
    plt.rcParams["axes.titlesize"] = 7.2
    plt.rcParams["xtick.labelsize"] = 6.3
    plt.rcParams["ytick.labelsize"] = 6.3
    plt.rcParams["legend.fontsize"] = 6.2
    plt.rcParams["axes.linewidth"] = 0.65
    plt.rcParams["xtick.major.width"] = 0.65
    plt.rcParams["ytick.major.width"] = 0.65
    plt.rcParams["xtick.major.size"] = 3.0
    plt.rcParams["ytick.major.size"] = 3.0
    plt.rcParams["axes.spines.top"] = False
    plt.rcParams["axes.spines.right"] = False
    plt.rcParams["figure.facecolor"] = "white"
    plt.rcParams["axes.facecolor"] = "white"
    plt.rcParams["savefig.facecolor"] = "white"


def find_project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "src").is_dir() and (parent / "results").is_dir():
            return parent
    raise RuntimeError("Could not locate the project root")


def decode_matlab_char(dataset: h5py.Dataset) -> str:
    values = np.asarray(dataset[...]).ravel(order="F")
    if values.dtype != np.uint16 or dataset.attrs.get("MATLAB_empty", 0):
        return ""
    return "".join(chr(int(value)) for value in values if int(value) > 0)


def read_sigstream_record(handle: h5py.File, record_index: int) -> np.ndarray:
    record = handle["#sigstream#"][str(record_index)]
    sample_size = int(np.asarray(record["#sampleSize#"])[0])
    length = int(np.asarray(record["#length#"])[0])
    if sample_size != 8:
        raise ValueError(f"Expected float64 samples, found {sample_size}-byte samples")
    payload = np.asarray(record["#data#"], dtype=np.uint8).tobytes()
    data = np.frombuffer(payload, dtype="<f8").copy()
    if data.size != length:
        raise ValueError(f"Signal length mismatch: metadata={length}, payload={data.size}")
    return data


def read_compressed_timeseries(mat_path: Path, signal_name: str) -> tuple[np.ndarray, np.ndarray]:
    matches: list[tuple[np.ndarray, np.ndarray, str]] = []
    with h5py.File(mat_path, "r") as handle:
        for key, candidate in handle["#refs#"].items():
            if not isinstance(candidate, h5py.Group):
                continue
            if "Name" not in candidate or "Values" not in candidate:
                continue
            if not isinstance(candidate["Name"], h5py.Dataset):
                continue
            if decode_matlab_char(candidate["Name"]) != signal_name:
                continue

            values = candidate["Values"]
            compressed_time = np.asarray(values["CompressedTime"], dtype=float).reshape(-1)
            if compressed_time.size != 3:
                raise ValueError(f"Unexpected compressed time record for {signal_name}")
            start, step, count_float = compressed_time
            count = int(round(count_float))
            record_index = int(np.asarray(values["DataR2"], dtype=float).reshape(-1)[0])
            data = read_sigstream_record(handle, record_index)
            time = start + step * np.arange(count, dtype=float)
            if time.size != data.size:
                raise ValueError(f"Time/data length mismatch for {signal_name}")
            matches.append((time, data, key))

    if not matches:
        raise KeyError(f"Signal {signal_name!r} was not found in {mat_path}")

    # Some runs store both a controller-rate and a slower route copy of the truth.
    # The full-resolution series is the one used for the aligned comparison.
    time, data, _ = max(matches, key=lambda item: item[0].size)
    if not np.isfinite(time).all() or not np.isfinite(data).all():
        raise ValueError(f"Non-finite samples in {signal_name} from {mat_path}")
    return time, data


def matlab_prctile(values: np.ndarray, percentile: float) -> float:
    # MATLAB prctile uses the Hazen plotting-position convention for this vector case.
    return float(np.percentile(values, percentile, method="hazen"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def extract_source_data(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, list[dict[str, object]]]:
    loaded: dict[str, dict[str, np.ndarray]] = {}
    input_records: list[dict[str, object]] = []

    for method in METHODS:
        mat_path = root / method["relative_path"]
        if not mat_path.is_file():
            raise FileNotFoundError(mat_path)
        estimate_time, estimate_rad = read_compressed_timeseries(mat_path, "diag.theta_hat")
        truth_time, truth_rad = read_compressed_timeseries(mat_path, "diag.theta_ground")
        truth_aligned_rad = np.interp(estimate_time, truth_time, truth_rad)
        loaded[str(method["id"])] = {
            "time": estimate_time,
            "estimate": estimate_rad,
            "truth": truth_aligned_rad,
        }
        input_records.append(
            {
                "method_id": method["id"],
                "file": relative_path(mat_path, root),
                "bytes": mat_path.stat().st_size,
                "sha256": sha256_file(mat_path),
            }
        )

    base = loaded[str(METHODS[0]["id"])]
    common_time = base["time"]
    truth_deg = np.rad2deg(base["truth"])
    source = pd.DataFrame({"time_s": common_time, "reference_grade_deg": truth_deg})
    metric_rows: list[dict[str, object]] = []

    for method in METHODS:
        item = loaded[str(method["id"])]
        if item["time"].size != common_time.size or not np.allclose(
            item["time"], common_time, atol=1e-12, rtol=0
        ):
            estimate_rad = np.interp(common_time, item["time"], item["estimate"])
            method_truth_rad = np.interp(common_time, item["time"], item["truth"])
        else:
            estimate_rad = item["estimate"]
            method_truth_rad = item["truth"]

        truth_difference_deg = np.max(np.abs(np.rad2deg(method_truth_rad) - truth_deg))
        if truth_difference_deg > 1e-9:
            raise ValueError(
                f"Reference grade mismatch for {method['label']}: {truth_difference_deg:.3e} deg"
            )

        estimate_deg = np.rad2deg(estimate_rad)
        source[str(method["column"])] = estimate_deg
        absolute_error = np.abs(estimate_deg - truth_deg)
        benchmark_mask = common_time >= BENCHMARK_WARMUP_S - 1e-12
        metric_rows.append(
            {
                "method_id": method["id"],
                "method_label": method["label"],
                "n_full_trace": int(common_time.size),
                "duration_s": float(common_time[-1] - common_time[0]),
                "mae_benchmark_deg": float(absolute_error[benchmark_mask].mean()),
                "mae_benchmark_start_s": BENCHMARK_WARMUP_S,
                "mae_full_trace_deg": float(absolute_error.mean()),
                "p95_abs_error_full_trace_deg": matlab_prctile(absolute_error, 95.0),
                "peak_abs_error_full_trace_deg": float(absolute_error.max()),
            }
        )

    return source, pd.DataFrame(metric_rows), input_records


def style_axis(axis: plt.Axes) -> None:
    axis.grid(True, color="#E5E5E5", linewidth=0.45, zorder=0)
    axis.set_axisbelow(True)
    axis.spines["left"].set_color("#555555")
    axis.spines["bottom"].set_color("#555555")
    axis.tick_params(colors="#333333", direction="out")


def add_metrics_box(axis: plt.Axes, metrics: pd.DataFrame) -> plt.Axes:
    box = axis.inset_axes([0.66, 0.485, 0.325, 0.455])
    box.set_facecolor((1.0, 1.0, 1.0, 0.94))
    for spine in box.spines.values():
        spine.set_visible(True)
        spine.set_linewidth(0.55)
        spine.set_edgecolor("#B8B8B8")
    box.set_xticks([])
    box.set_yticks([])
    box.set_xlim(0, 1)
    box.set_ylim(0, 1)
    box.text(
        0.05,
        0.91,
        "Case-level error (deg)",
        fontsize=6.2,
        fontweight="bold",
        va="center",
    )
    box.text(0.16, 0.74, "Method", fontsize=6.0, fontweight="bold", va="center")
    box.text(
        0.76,
        0.74,
        "MAE",
        fontsize=6.0,
        fontweight="bold",
        ha="right",
        va="center",
    )
    box.text(0.95, 0.74, "P95", fontsize=6.0, fontweight="bold", ha="right", va="center")
    box.plot([0.05, 0.95], [0.665, 0.665], color="#CFCFCF", linewidth=0.5)

    row_y = [0.54, 0.39, 0.24, 0.09]
    for y, method in zip(row_y, METHODS):
        row = metrics.loc[metrics["method_id"] == method["id"]].iloc[0]
        box.plot(
            [0.05, 0.13],
            [y, y],
            color=method["color"],
            linestyle=method["linestyle"],
            linewidth=max(float(method["linewidth"]), 1.0),
            solid_capstyle="butt",
        )
        box.text(
            0.16,
            y,
            str(method["label"]),
            fontsize=6.0,
            fontweight="semibold" if method["id"] == METHODS[0]["id"] else "normal",
            color=method["color"] if method["id"] == METHODS[0]["id"] else "#333333",
            va="center",
        )
        box.text(
            0.76,
            y,
            f"{float(row['mae_benchmark_deg']):.3f}",
            fontsize=6.0,
            fontweight="semibold" if method["id"] == METHODS[0]["id"] else "normal",
            color=method["color"] if method["id"] == METHODS[0]["id"] else "#333333",
            ha="right",
            va="center",
        )
        box.text(
            0.95,
            y,
            f"{float(row['p95_abs_error_full_trace_deg']):.3f}",
            fontsize=6.0,
            fontweight="semibold" if method["id"] == METHODS[0]["id"] else "normal",
            color=method["color"] if method["id"] == METHODS[0]["id"] else "#333333",
            ha="right",
            va="center",
        )
        if y > row_y[-1]:
            box.plot([0.05, 0.95], [y - 0.075, y - 0.075], color="#ECECEC", linewidth=0.4)
    return box


def build_figure(source: pd.DataFrame, metrics: pd.DataFrame) -> tuple[plt.Figure, list[plt.Axes]]:
    configure_style()
    figure, axes = plt.subplots(
        2,
        1,
        figsize=(WIDTH_MM * MM, HEIGHT_MM * MM),
        sharex=True,
        gridspec_kw={
            "left": 0.085,
            "right": 0.985,
            "bottom": 0.14,
            "top": 0.84,
            "hspace": 0.16,
            "height_ratios": [1.08, 1.0],
        },
    )
    grade_axis, error_axis = axes
    time = source["time_s"].to_numpy(dtype=float)
    truth = source["reference_grade_deg"].to_numpy(dtype=float)

    grade_axis.plot(time, truth, color="#222222", linewidth=1.35, zorder=7)
    for method in METHODS:
        estimate = source[str(method["column"])].to_numpy(dtype=float)
        grade_axis.plot(
            time,
            estimate,
            color=method["color"],
            linestyle=method["linestyle"],
            linewidth=method["linewidth"],
            zorder=method["zorder"],
        )
        error_axis.plot(
            time,
            np.abs(estimate - truth),
            color=method["color"],
            linestyle=method["linestyle"],
            linewidth=method["linewidth"],
            zorder=method["zorder"],
        )

    for axis in axes:
        style_axis(axis)
        axis.set_xlim(float(time[0]), float(time[-1]))
        axis.set_xticks(np.arange(0, 51, 10))

    grade_margin = 0.7
    grade_axis.set_ylim(
        min(float(source.drop(columns="time_s").min().min()) - grade_margin, -6.5),
        max(float(source.drop(columns="time_s").max().max()) + grade_margin, 6.5),
    )
    error_max = max(
        float(np.abs(source[str(method["column"])] - source["reference_grade_deg"]).max())
        for method in METHODS
    )
    error_axis.set_ylim(0, max(3.6, np.ceil((error_max + 0.15) * 2) / 2))
    error_axis.set_yticks(np.arange(0, error_axis.get_ylim()[1] + 0.01, 1.0))

    grade_axis.set_ylabel("Grade (deg)")
    error_axis.set_ylabel("Absolute error (deg)")
    error_axis.set_xlabel("Time (s)")
    grade_axis.set_title("Grade-estimation trajectories", loc="left", fontweight="bold", pad=4)
    error_axis.set_title("Absolute grade-estimation error", loc="left", fontweight="bold", pad=4)
    grade_axis.text(
        1.0,
        1.035,
        "P2 Sharp-turn transition | model seed 73",
        transform=grade_axis.transAxes,
        ha="right",
        va="bottom",
        fontsize=6.3,
        color="#555555",
    )
    grade_axis.text(
        -0.065,
        1.025,
        "(a)",
        transform=grade_axis.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.0,
        fontweight="bold",
        clip_on=False,
    )
    error_axis.text(
        -0.065,
        1.025,
        "(b)",
        transform=error_axis.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.0,
        fontweight="bold",
        clip_on=False,
    )

    legend_handles = [Line2D([], [], color="#222222", linewidth=1.35, label="Reference grade")]
    legend_handles.extend(
        Line2D(
            [],
            [],
            color=method["color"],
            linestyle=method["linestyle"],
            linewidth=max(float(method["linewidth"]), 1.0),
            label=str(method["label"]),
        )
        for method in METHODS
    )
    figure.legend(
        handles=legend_handles,
        loc="upper center",
        bbox_to_anchor=(0.535, 0.965),
        ncol=5,
        frameon=False,
        handlelength=2.5,
        columnspacing=1.25,
        handletextpad=0.55,
    )
    metrics_box = add_metrics_box(error_axis, metrics)
    return figure, [grade_axis, error_axis, metrics_box]


def inspect_artists(figure: plt.Figure, axes: list[plt.Axes]) -> dict[str, object]:
    figure.canvas.draw()
    renderer = figure.canvas.get_renderer()
    figure_box = figure.bbox
    visible_text = [text for text in figure.findobj(plt.Text) if text.get_visible() and text.get_text()]
    minimum_font = min(float(text.get_fontsize()) for text in visible_text)
    overflow: list[str] = []
    for text in visible_text:
        box = text.get_window_extent(renderer=renderer)
        tolerance = 2.0
        if (
            box.x0 < figure_box.x0 - tolerance
            or box.y0 < figure_box.y0 - tolerance
            or box.x1 > figure_box.x1 + tolerance
            or box.y1 > figure_box.y1 + tolerance
        ):
            overflow.append(text.get_text())
    return {
        "primary_panel_count": 2,
        "axes_count_including_metrics_box": len(axes),
        "minimum_visible_font_pt": round(minimum_font, 2),
        "material_text_overflow_count": len(overflow),
        "material_text_overflow": overflow,
        "status": "PASS" if minimum_font >= 6.0 and not overflow else "FAIL",
    }


def export_figure(figure: plt.Figure, output_dir: Path) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [output_dir / f"{OUTPUT_STEM}.{suffix}" for suffix in ("pdf", "svg", "png")]
    figure.savefig(outputs[0])
    figure.savefig(outputs[1])
    figure.savefig(outputs[2], dpi=DPI)
    return outputs


def inspect_exports(outputs: list[Path], qa_dir: Path) -> dict[str, object]:
    png_path = next(path for path in outputs if path.suffix == ".png")
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    expected_pixels = (round(WIDTH_MM * DPI / 25.4), round(HEIGHT_MM * DPI / 25.4))
    with Image.open(png_path) as image:
        actual_pixels = image.size
        grayscale_path = qa_dir / f"{OUTPUT_STEM}_grayscale.png"
        ImageOps.grayscale(image).save(grayscale_path, dpi=(DPI, DPI))
        gray_array = np.asarray(ImageOps.grayscale(image), dtype=np.uint8)
        nonwhite_fraction = float(np.mean(gray_array < 250))

    svg_root = ElementTree.parse(svg_path).getroot()
    editable_text_elements = sum(1 for element in svg_root.iter() if element.tag.endswith("text"))
    checks = {
        "requested_size_mm": [WIDTH_MM, HEIGHT_MM],
        "png_dpi": DPI,
        "png_pixels": list(actual_pixels),
        "expected_png_pixels": list(expected_pixels),
        "png_size_matches": all(
            abs(actual - expected) <= 1
            for actual, expected in zip(actual_pixels, expected_pixels)
        ),
        "png_nonwhite_fraction": round(nonwhite_fraction, 5),
        "svg_editable_text_elements": editable_text_elements,
        "grayscale_preview": grayscale_path.name,
    }
    checks["status"] = (
        "PASS"
        if checks["png_size_matches"]
        and editable_text_elements > 0
        and nonwhite_fraction > 0.02
        else "FAIL"
    )
    return checks


def write_reports(
    root: Path,
    figure_dir: Path,
    source_path: Path,
    metrics_path: Path,
    input_records: list[dict[str, object]],
    outputs: list[Path],
    artist_checks: dict[str, object],
    export_checks: dict[str, object],
) -> None:
    metrics = pd.read_csv(metrics_path)
    expected = {
        "modern_tcn_delta_bank_124": (0.503778851501989, 1.138207909195833),
        "modern_tcn_22d": (0.693626327628225, 1.768222685185179),
        "gru_22d": (0.806999103372943, 1.940944077804236),
        "tcn_22d": (0.553025983613919, 1.389117448080817),
    }
    numeric_checks = []
    for method_id, (expected_mae, expected_p95) in expected.items():
        row = metrics.loc[metrics["method_id"] == method_id].iloc[0]
        mae_ok = bool(np.isclose(row["mae_benchmark_deg"], expected_mae, atol=1e-12, rtol=0))
        p95_ok = bool(
            np.isclose(row["p95_abs_error_full_trace_deg"], expected_p95, atol=2e-7, rtol=0)
        )
        numeric_checks.append(
            {
                "method_id": method_id,
                "mae_matches": mae_ok,
                "p95_matches": p95_ok,
            }
        )

    status = (
        "PASS"
        if artist_checks["status"] == "PASS"
        and export_checks["status"] == "PASS"
        and all(item["mae_matches"] and item["p95_matches"] for item in numeric_checks)
        else "FAIL"
    )
    output_records = [
        {
            "format": path.suffix[1:],
            "file": relative_path(path, root),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for path in outputs
    ]
    manifest = {
        "figure_id": "Fig05_representative_four_estimator_trace",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib with Python h5py MAT v7.3 extraction",
        "scope": "Figure generation only; no TeX or Table 8 files were modified.",
        "figure_contract": {
            "core_conclusion": "In the complete representative P2 seed-73 run, ModernTCN-delta has the lowest case-level MAE and P95 absolute grade-estimation error among the four estimators.",
            "archetype": "two-panel representative quantitative trace",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "panel_map": {
                "a": "reference grade and four estimator trajectories over the complete route",
                "b": "four absolute-error trajectories with a compact MAE/P95 summary",
            },
        },
        "metric_definitions": {
            "mae_benchmark_deg": "mean absolute error over t >= 0.5 s, matching the frozen closed-loop benchmark convention",
            "p95_abs_error_full_trace_deg": "MATLAB-compatible prctile(abs(error),95) over the complete 0-52 s trace",
        },
        "inputs": input_records,
        "source_data": {
            "timeseries_file": relative_path(source_path, root),
            "timeseries_sha256": sha256_file(source_path),
            "metrics_file": relative_path(metrics_path, root),
            "metrics_sha256": sha256_file(metrics_path),
            "samples": int(pd.read_csv(source_path, usecols=["time_s"]).shape[0]),
        },
        "outputs": output_records,
        "automatic_qa": {
            "status": status,
            "numeric_checks": numeric_checks,
            "artist_checks": artist_checks,
            "export_checks": export_checks,
        },
    }
    manifest_text = json.dumps(manifest, indent=2, ensure_ascii=True)
    (figure_dir / "manifest.json").write_text(manifest_text, encoding="utf-8")
    (figure_dir / "qa" / f"{OUTPUT_STEM}_qa.json").write_text(
        manifest_text, encoding="utf-8"
    )

    rows = []
    for _, row in metrics.iterrows():
        rows.append(
            f"| {row['method_label']} | {row['mae_benchmark_deg']:.5f} | "
            f"{row['p95_abs_error_full_trace_deg']:.4f} | "
            f"{row['peak_abs_error_full_trace_deg']:.5f} |"
        )
    report = "\n".join(
        [
            "# QA Report: Figure 5 Representative Four-Estimator Trace",
            "",
            f"- Overall automatic QA: **{status}**",
            "- Backend: Python/matplotlib; MAT v7.3 extraction used Python/h5py.",
            f"- Final size: {WIDTH_MM:.0f} mm x {HEIGHT_MM:.0f} mm.",
            f"- Raster export: {DPI} dpi PNG.",
            "- Scope: figure, source data, scripts, and QA only; no TeX or table files were modified.",
            "- Trace policy: complete 0-52 s route, no smoothing, no local-window cropping.",
            "- Alignment: all estimators share the same 5201-sample, 0.01-s time axis; reference traces agree exactly.",
            "- Metric policy: MAE uses t >= 0.5 s to match the frozen benchmark; P95 uses the complete trace with MATLAB-compatible prctile.",
            "",
            "| Method | MAE (deg) | P95 abs. error (deg) | Peak abs. error (deg) |",
            "|---|---:|---:|---:|",
            *rows,
            "",
            f"- Minimum visible font: {artist_checks['minimum_visible_font_pt']:.1f} pt.",
            f"- Text overflow count: {artist_checks['material_text_overflow_count']}.",
            f"- Editable SVG text elements: {export_checks['svg_editable_text_elements']}.",
            f"- PNG dimensions: {export_checks['png_pixels'][0]} x {export_checks['png_pixels'][1]} px.",
            "- Grayscale separability is supported by distinct line patterns for all four estimators.",
            "",
            "Visual QA should confirm the metrics box does not obscure a principal transition and that all five legend entries remain readable at final size.",
        ]
    )
    (figure_dir / "QA_REPORT.md").write_text(report + "\n", encoding="utf-8")


def main() -> None:
    root = find_project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    output_dir = figure_dir / "output"
    source_dir = figure_dir / "source_data"
    qa_dir = figure_dir / "qa"
    for directory in (output_dir, source_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    source, metrics, input_records = extract_source_data(root)
    source_path = source_dir / "fig05_p2_seed73_timeseries.csv"
    metrics_path = source_dir / "fig05_p2_seed73_metrics.csv"
    source.to_csv(source_path, index=False, float_format="%.12g")
    metrics.to_csv(metrics_path, index=False, float_format="%.12g")

    figure, axes = build_figure(source, metrics)
    artist_checks = inspect_artists(figure, axes)
    outputs = export_figure(figure, output_dir)
    plt.close(figure)
    export_checks = inspect_exports(outputs, qa_dir)
    write_reports(
        root,
        figure_dir,
        source_path,
        metrics_path,
        input_records,
        outputs,
        artist_checks,
        export_checks,
    )
    print(
        json.dumps(
            {
                "figure": OUTPUT_STEM,
                "outputs": [str(path) for path in outputs],
                "artist_qa": artist_checks["status"],
                "export_qa": export_checks["status"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
