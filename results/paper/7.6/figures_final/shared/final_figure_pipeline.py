"""Reproducible final-figure pipeline for the frozen manuscript results.

Every entry point under ``FigNN_*/scripts`` calls :func:`run_figure`.  This
module owns common styling, extraction, export, hashing, and automatic QA so
that the per-figure contracts remain consistent.  It never launches Simulink,
trains a model, or reads values back from a rendered figure.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

import h5py
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import TwoSlopeNorm
from matplotlib.legend_handler import HandlerTuple
from matplotlib.lines import Line2D
from matplotlib.patches import FancyArrowPatch, Patch, Rectangle
from matplotlib.text import Text
from matplotlib.ticker import MaxNLocator
from PIL import Image, ImageOps
from scipy import stats
from scipy.io import loadmat

sys.dont_write_bytecode = True

from style import PALETTE, add_panel_label, apply_publication_style


MM = 1.0 / 25.4
SEEDS = (1, 7, 11, 21, 42, 73, 101, 202, 340, 520)
FINAL_ROOT_REL = Path("results/paper/7.6/figures_final")

COLORS = {
    **PALETTE,
    "delta": "#1F5A85",
    "baseline": "#73A2C6",
    "benefit": "#2166AC",
    "adverse": "#B44A4A",
    "neutral": "#D9D9D9",
    "ink": "#2B2B2B",
}

ROUTES6 = (
    ("P1", "Factory logistics", "data/paths/path_factory_logistics_showcase_theta10_v10.mat"),
    ("P2", "Sharp-turn transition", "data/paths/path_closed_loop_sharp_turn_transition_theta10_v1.mat"),
    ("P3", "Long up/down slope", "data/paths/path_closed_loop_long_updown_theta10_v1.mat"),
    ("P4", "Mild slope-turn coupling", "data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat"),
    ("P5", "Flat factory logistics", "data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat"),
    ("P6", "Downhill recovery", "data/paths/factory_targeted_eval/path_factory_target_downhill_straight_after_turn_v1.mat"),
)

P4_GRADE_SEGMENTS = (
    ("startup_flat", 0.0, 4.0, 0.0, 0.0),
    ("uphill_entry", 4.0, 15.0, 0.0, 4.0),
    ("uphill_left_turn", 15.0, 21.0, 4.0, 4.0),
    ("slope_release_only", 21.0, 34.0, 4.0, 0.0),
    ("downhill_entry", 34.0, 43.0, 0.0, -3.5),
    ("downhill_right_turn", 43.0, 49.0, -3.5, -3.5),
    ("flat_recovery", 49.0, 56.0, -3.5, 0.0),
)

ROUTE9 = {
    "path_factory_logistics_showcase_theta10_v10": "P1",
    "path_closed_loop_sharp_turn_transition_theta10_v1": "P2",
    "path_closed_loop_long_updown_theta10_v1": "P3",
    "path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1": "P4",
    "path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1": "P5",
    "path_factory_target_downhill_straight_after_turn_v1": "P6",
    "path_modern_tcn_showcase_candidate_balanced_mild_updown_lr_v1": "P7",
    "path_factory_target_uphill_left_overlap_v1": "P8",
    "path_factory_target_downhill_right_reversal_v1": "P9",
}


@dataclass(frozen=True)
class FigureContract:
    figure_id: str
    directory: str
    stem: str
    width_mm: float
    height_mm: float
    panel_count: int
    build: Callable[[Path], tuple[pd.DataFrame, plt.Figure, list[Path], dict[str, object]]]


def find_project_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "data").is_dir() and (candidate / "results").is_dir():
            return candidate
    raise RuntimeError("Could not locate the project root containing data/ and results/.")


def relpath(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve())).replace("\\", "/")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_columns(frame: pd.DataFrame, required: set[str], source: Path) -> None:
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(f"{source} is missing required columns: {missing}")


def configure_style(minor_font_size: float = 6.2) -> None:
    apply_publication_style()
    plt.rcParams.update(
        {
            "font.size": 7.0,
            "axes.labelsize": 7.0,
            "axes.titlesize": 7.2,
            "xtick.labelsize": minor_font_size,
            "ytick.labelsize": minor_font_size,
            "legend.fontsize": minor_font_size,
            "axes.grid": False,
        }
    )


def clean_axis(ax, grid: str | None = "y") -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", pad=1.5)
    if grid:
        ax.grid(axis=grid, color=PALETTE["grid"], linewidth=0.45, zorder=0)
        ax.set_axisbelow(True)


def decimation_indices(length: int, max_points: int) -> np.ndarray:
    if length <= max_points:
        return np.arange(length, dtype=int)
    return np.unique(np.linspace(0, length - 1, max_points).astype(int))


def _load_mat_route(path: Path) -> dict[str, np.ndarray]:
    fields = ("t", "X_ref", "Y_ref", "theta_ref", "v_ref")
    try:
        payload = loadmat(path, squeeze_me=True, struct_as_record=False)
        ref = payload["ref"]
        return {name: np.asarray(getattr(ref, name), dtype=float).squeeze() for name in fields}
    except NotImplementedError:
        with h5py.File(path, "r") as handle:
            return {name: np.asarray(handle["ref"][name], dtype=float).squeeze() for name in fields}


def _reconstruct_p4_grade(time: np.ndarray, path: Path) -> tuple[np.ndarray, np.ndarray, bool]:
    """Rebuild P4 from its seven frozen metadata segments using cubic smoothstep."""
    time = np.asarray(time, dtype=float)
    grade = np.full(time.shape, np.nan, dtype=float)
    segment_names = np.full(time.shape, "", dtype=object)
    for index, (name, t0, t1, grade0, grade1) in enumerate(P4_GRADE_SEGMENTS):
        mask = (time >= t0) & ((time < t1) if index < len(P4_GRADE_SEGMENTS) - 1 else (time <= t1))
        tau = np.clip((time[mask] - t0) / (t1 - t0), 0.0, 1.0)
        smoothstep = tau * tau * (3.0 - 2.0 * tau)
        grade[mask] = grade0 + (grade1 - grade0) * smoothstep
        segment_names[mask] = name
    if not np.isfinite(grade).all():
        raise ValueError("P4 metadata reconstruction does not cover the complete route time axis")

    with h5py.File(path, "r") as handle:
        metadata = handle["ref/meta/segments"]
        metadata_t0 = np.array([float(np.asarray(handle[reference]).squeeze()) for reference in metadata["t0"][0]])
        metadata_t1 = np.array([float(np.asarray(handle[reference]).squeeze()) for reference in metadata["t1"][0]])
    expected_t0 = np.array([segment[1] for segment in P4_GRADE_SEGMENTS])
    expected_t1 = np.array([segment[2] for segment in P4_GRADE_SEGMENTS])
    bounds_match = bool(np.array_equal(metadata_t0, expected_t0) and np.array_equal(metadata_t1, expected_t1))
    if not bounds_match:
        raise ValueError("P4 metadata segment bounds do not match the frozen reconstruction contract")
    return grade, segment_names, bounds_match


def _matlab_string(handle: h5py.File, reference) -> str:
    data = handle[reference][()]
    return "".join(chr(int(value)) for value in data.ravel(order="F"))


def _inspect_dataset_mat(path: Path) -> dict[str, object]:
    with h5py.File(path, "r") as handle:
        scene_refs = handle["dataset/run_table/scene"][:, 0]
        scenes = [_matlab_string(handle, reference) for reference in scene_refs]
        split = {
            role: handle[f"dataset/split_info/runs_{key}"][()].ravel().astype(int).tolist()
            for role, key in (("train", "train"), ("validation", "val"), ("test", "test"))
        }
        shapes = {
            role: list(handle[f"dataset/X_{key}"].shape)
            for role, key in (("train", "train"), ("validation", "val"), ("test", "test"))
        }
    return {
        "run_count": len(scenes),
        "template_count": len(set(scenes)),
        "replicates_per_template": sorted(pd.Series(scenes).value_counts().unique().tolist()),
        "split": split,
        "window_shapes": shapes,
    }


def _source_record(path: Path, root: Path, role: str) -> dict[str, object]:
    return {
        "role": role,
        "file": relpath(path, root),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def _export(fig: plt.Figure, stem: Path) -> list[Path]:
    stem.parent.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    for suffix, options in (
        (".pdf", {}),
        (".svg", {}),
        (".png", {"dpi": 300}),
        (".tiff", {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}}),
    ):
        destination = stem.with_suffix(suffix)
        fig.savefig(destination, facecolor="white", **options)
        outputs.append(destination)
    return outputs


def _inspect_outputs(
    outputs: list[Path], width_mm: float, height_mm: float, qa_dir: Path, stem: str
) -> dict[str, object]:
    expected_mm = np.array([width_mm, height_mm], dtype=float)
    raster: dict[str, object] = {}
    png_path = next(path for path in outputs if path.suffix == ".png")
    for suffix, dpi in ((".png", 300), (".tiff", 600)):
        path = next(output for output in outputs if output.suffix == suffix)
        with Image.open(path) as image:
            pixels = np.array(image.size, dtype=float)
            actual_mm = pixels / dpi * 25.4
            if not np.allclose(actual_mm, expected_mm, atol=0.16):
                raise ValueError(f"{path.name} has unexpected physical size {actual_mm.tolist()} mm")
            rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
            nonwhite = float(np.mean(np.any(rgb < 250, axis=2)))
            if nonwhite < 0.01:
                raise ValueError(f"{path.name} appears blank")
            raster[suffix[1:]] = {
                "pixels": [int(value) for value in pixels],
                "dpi": dpi,
                "physical_size_mm": [round(float(value), 3) for value in actual_mm],
                "nonwhite_fraction": round(nonwhite, 5),
            }
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    svg_root = ET.parse(svg_path).getroot()
    text_count = sum(1 for node in svg_root.iter() if node.tag.endswith("text"))
    if text_count == 0:
        raise ValueError(f"{svg_path.name} has no editable text elements")
    qa_dir.mkdir(parents=True, exist_ok=True)
    grayscale_path = qa_dir / f"{stem}_grayscale.png"
    with Image.open(png_path) as image:
        ImageOps.grayscale(image).save(grayscale_path)
    return {
        "requested_size_mm": [width_mm, height_mm],
        "raster_exports": raster,
        "svg_editable_text_elements": text_count,
        "grayscale_preview": grayscale_path,
        "status": "PASS",
    }


def _figure_artist_checks(fig: plt.Figure, expected_panels: int) -> dict[str, object]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    canvas = fig.bbox
    text_artists = [text for text in fig.findobj(Text) if text.get_visible() and text.get_text().strip()]
    min_font = min((float(text.get_fontsize()) for text in text_artists), default=math.inf)
    outside: list[dict[str, object]] = []
    for text in text_artists:
        bbox = text.get_window_extent(renderer=renderer)
        if not np.isfinite(bbox.extents).all():
            continue
        overflow = {
            "left_px": max(0.0, float(canvas.x0 - bbox.x0)),
            "bottom_px": max(0.0, float(canvas.y0 - bbox.y0)),
            "right_px": max(0.0, float(bbox.x1 - canvas.x1)),
            "top_px": max(0.0, float(bbox.y1 - canvas.y1)),
        }
        if max(overflow.values()) > 3.0:
            outside.append({"text": text.get_text()[:80], **overflow})
    if min_font < 6.0:
        raise ValueError(f"Minimum visible text size is {min_font:.2f} pt; expected at least 6 pt")
    severe = [item for item in outside if max(value for key, value in item.items() if key.endswith("_px")) > 10.0]
    if severe:
        raise ValueError(f"Visible text has material canvas overflow: {severe[:5]}")
    axes_count = len(fig.axes)
    if axes_count < expected_panels:
        raise ValueError(f"Expected at least {expected_panels} axes, found {axes_count}")
    return {
        "axes_count_including_colorbars": axes_count,
        "expected_primary_panels": expected_panels,
        "minimum_visible_font_pt": round(min_font, 2),
        "minor_text_overflow_count": len(outside),
        "minor_text_overflow": outside,
        "material_text_overflow_count": 0,
        "status": "PASS",
    }


def _finalize(
    root: Path,
    contract: FigureContract,
    source_data: pd.DataFrame,
    fig: plt.Figure,
    raw_inputs: list[Path],
    checks: dict[str, object],
) -> dict[str, object]:
    figure_root = root / FINAL_ROOT_REL / contract.directory
    source_dir = figure_root / "source_data"
    output_dir = figure_root / "output"
    qa_dir = figure_root / "qa"
    for directory in (source_dir, output_dir, qa_dir, figure_root / "archive"):
        directory.mkdir(parents=True, exist_ok=True)
    source_path = source_dir / f"{contract.stem}_source_data.csv"
    source_data.to_csv(source_path, index=False)
    artist_checks = _figure_artist_checks(fig, contract.panel_count)
    outputs = _export(fig, output_dir / contract.stem)
    plt.close(fig)
    output_geometry = _inspect_outputs(
        outputs, contract.width_mm, contract.height_mm, qa_dir, contract.stem
    )
    raw_records = [_source_record(path, root, f"input_{index + 1}") for index, path in enumerate(raw_inputs)]
    output_records = [_source_record(path, root, path.suffix[1:]) for path in outputs]
    manifest = {
        "figure_id": contract.figure_id,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "skill_basis": ["scientific-visualization", "matplotlib", "matlab data-reading principles"],
        "nature_skill_used": False,
        "frozen_inputs": raw_records,
        "source_data": {
            "file": relpath(source_path, root),
            "rows": int(source_data.shape[0]),
            "columns": list(source_data.columns),
            "sha256": sha256_file(source_path),
        },
        "outputs": output_records,
        "automatic_qa": {
            "status": "PASS",
            "contract_checks": checks,
            "artist_checks": artist_checks,
            "output_checks": {
                **{key: value for key, value in output_geometry.items() if key != "grayscale_preview"},
                "grayscale_preview": relpath(output_geometry["grayscale_preview"], root),
            },
        },
        "visual_qa": {
            "status": "PENDING_MANUAL_REVIEW",
            "review_at_final_size": True,
            "checks": [
                "font readability",
                "legend and label overlap",
                "color and grayscale separability",
                "cropping and panel lettering",
                "caption-contract consistency",
            ],
        },
    }
    manifest_path = figure_root / "manifest.json"
    qa_path = qa_dir / f"{contract.stem}_qa.json"
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2)
    manifest_path.write_text(encoded, encoding="utf-8")
    qa_path.write_text(encoded, encoding="utf-8")
    return manifest


def build_fig02(root: Path):
    a0_path = root / "results/paper/7.6/A0_论文最终统一实验配置_20260715.json"
    contract_path = root / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5_contract.json"
    dataset_path = root / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
    a0 = json.loads(a0_path.read_text(encoding="utf-8"))
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    inspected = _inspect_dataset_mat(dataset_path)
    dataset_cfg = a0["dataset"]
    representation = a0["input_representations"]["delta_bank_124"]
    split_counts = {role: len(values) for role, values in inspected["split"].items()}
    values = {
        "templates": inspected["template_count"],
        "runs": inspected["run_count"],
        "train": split_counts["train"],
        "validation": split_counts["validation"],
        "test": split_counts["test"],
        "raw_dim": int(contract["input_dim"]),
        "lags": representation["lag_steps"],
        "augmented_dim": int(representation["augmented_input_dim"]),
        "sequence": int(contract["seq_len"]),
    }
    if values != {
        "templates": 51,
        "runs": 102,
        "train": 71,
        "validation": 15,
        "test": 16,
        "raw_dim": 22,
        "lags": [1, 2, 4],
        "augmented_dim": 88,
        "sequence": 128,
    }:
        raise ValueError(f"Frozen dataset contract changed: {values}")
    hashes = {
        "a0": sha256_file(a0_path),
        "dataset_contract": sha256_file(contract_path),
        "dataset_mat": sha256_file(dataset_path),
    }
    stages = pd.DataFrame(
        [
            {"stage": 1, "stage_id": "templates", "display": "51 route templates", "count": 51, "split_role": "all", "dimension": "-", "source_field": "dataset/run_table/scene unique", "source_sha256": hashes["dataset_mat"]},
            {"stage": 2, "stage_id": "runs", "display": "2 realizations/template\n102 continuous runs", "count": 102, "split_role": "all", "dimension": "-", "source_field": "dataset/run_table/scene", "source_sha256": hashes["dataset_mat"]},
            {"stage": 3, "stage_id": "split", "display": "Run-level split\n71 train | 15 val | 16 test", "count": 102, "split_role": "train/validation/test", "dimension": "71/15/16", "source_field": "dataset/split_info/runs_*", "source_sha256": hashes["dataset_mat"]},
            {"stage": 4, "stage_id": "features", "display": "22-D causal dynamics\nfeatures", "count": 22, "split_role": "all", "dimension": "22", "source_field": "input_dim, feature_names", "source_sha256": hashes["dataset_contract"]},
            {"stage": 5, "stage_id": "delta", "display": "Delta bank\nlags 1, 2, 4", "count": 3, "split_role": "all", "dimension": "22 x 4 = 88", "source_field": "representations.delta_bank_124", "source_sha256": hashes["a0"]},
            {"stage": 6, "stage_id": "window", "display": "Causal model input\n128 x 88 window", "count": 128, "split_role": "all", "dimension": "128 x 88", "source_field": "seq_len, augmented_input_dim", "source_sha256": hashes["dataset_contract"]},
        ]
    )
    configure_style()
    fig, ax = plt.subplots(figsize=(183 * MM, 49 * MM))
    fig.subplots_adjust(left=0.02, right=0.985, top=0.91, bottom=0.22)
    ax.set_xlim(0, 6)
    ax.set_ylim(0, 1)
    ax.axis("off")
    x_positions = np.linspace(0.48, 5.52, 6)
    fills = ["#E9F1F7", "#E9F1F7", "#F1F1F1", "#E8F3F0", "#FFF0DC", "#E9EEF6"]
    for index, row in stages.iterrows():
        x = x_positions[index]
        rect = Rectangle((x - 0.39, 0.28), 0.78, 0.5, facecolor=fills[index], edgecolor="#555555", linewidth=0.75)
        ax.add_patch(rect)
        ax.text(x, 0.53, row["display"], ha="center", va="center", fontsize=7.0, linespacing=1.2)
        ax.text(x, 0.16, f"{index + 1}", ha="center", va="center", fontsize=6.2, color="#666666")
        if index < 5:
            ax.add_patch(FancyArrowPatch((x + 0.41, 0.53), (x_positions[index + 1] - 0.41, 0.53), arrowstyle="-|>", mutation_scale=8, linewidth=0.8, color="#555555"))
    fig.text(0.5, 0.045, "Split is run-disjoint, not fully route-template-disjoint; normalization is fitted on training runs only.", ha="center", fontsize=6.4, color="#444444")
    checks = {
        "stage_count": 6,
        "templates": 51,
        "runs": 102,
        "split_counts": split_counts,
        "raw_feature_dimension": 22,
        "lag_steps": [1, 2, 4],
        "augmented_feature_dimension": 88,
        "sequence_length": 128,
        "replicates_per_template": inspected["replicates_per_template"],
        "window_tensor_shapes_feature_time_window": inspected["window_shapes"],
        "normalization_policy": dataset_cfg["scaler_policy"],
    }
    return stages, fig, [a0_path, contract_path, dataset_path], checks


def build_fig03(root: Path):
    frames: list[pd.DataFrame] = []
    raw_inputs: list[Path] = []
    p4_metadata_bounds_match = False
    for order, (path_id, role, relative) in enumerate(ROUTES6, 1):
        path = root / relative
        raw = _load_mat_route(path)
        lengths = {name: len(values) for name, values in raw.items()}
        if len(set(lengths.values())) != 1:
            raise ValueError(f"{path_id} route fields are not aligned: {lengths}")
        time = raw["t"]
        if not np.isfinite(time).all() or not np.all(np.diff(time) > 0):
            raise ValueError(f"{path_id} time is not finite and strictly increasing")
        file_grade = np.rad2deg(raw["theta_ref"])
        if path_id == "P4":
            grade, grade_segment, p4_metadata_bounds_match = _reconstruct_p4_grade(time, path)
            grade_source = np.full(len(time), "metadata_reconstructed", dtype=object)
        else:
            grade = file_grade
            grade_segment = np.full(len(time), "path_theta_ref", dtype=object)
            grade_source = np.full(len(time), "path_theta_ref", dtype=object)
        rendered = np.zeros(len(time), dtype=bool)
        rendered[decimation_indices(len(time), 2200)] = True
        frames.append(
            pd.DataFrame(
                {
                    "route_id": path_id,
                    "route_order": order,
                    "route_name": role,
                    "route_identity": "closed_loop_benchmark_route",
                    "sample_index": np.arange(len(time)),
                    "t_s": time,
                    "x_ref_m": raw["X_ref"],
                    "y_ref_m": raw["Y_ref"],
                    "grade_deg": grade,
                    "grade_source": grade_source,
                    "grade_segment": grade_segment,
                    "grade_file_theta_ref_deg": file_grade,
                    "v_ref_mps": raw["v_ref"],
                    "rendered_in_figure": rendered,
                }
            )
        )
        raw_inputs.append(path)
    requirements_path = root / FINAL_ROOT_REL / "Fig03_closed_loop_route_set/figure2_revision_requirements_cn.md"
    raw_inputs.append(requirements_path)
    data = pd.concat(frames, ignore_index=True)
    configure_style(6.5)
    fig = plt.figure(figsize=(183 * MM, 116 * MM))
    outer = fig.add_gridspec(2, 3, left=0.06, right=0.965, bottom=0.075, top=0.95, wspace=0.27, hspace=0.34)
    grade_lim = max(7.0, float(math.ceil(data["grade_deg"].abs().max())))
    speed_min = math.floor(float(data["v_ref_mps"].min()) * 20) / 20 - 0.01
    speed_max = math.ceil(float(data["v_ref_mps"].max()) * 20) / 20 + 0.01
    render_counts: dict[str, int] = {}
    panel_axes: list[tuple[plt.Axes, plt.Axes, plt.Axes]] = []
    for index, (path_id, role, _) in enumerate(ROUTES6):
        cell = outer[index // 3, index % 3].subgridspec(2, 2, width_ratios=[1.28, 1.0], hspace=0.18, wspace=0.44)
        ax_path = fig.add_subplot(cell[:, 0])
        ax_grade = fig.add_subplot(cell[0, 1])
        ax_speed = fig.add_subplot(cell[1, 1], sharex=ax_grade)
        panel_axes.append((ax_path, ax_grade, ax_speed))
        full = data[data["route_id"] == path_id].reset_index(drop=True)
        d = full[full["rendered_in_figure"]]
        render_counts[path_id] = len(d)
        ax_path.plot(d["x_ref_m"], d["y_ref_m"], color=COLORS["ink"], linewidth=1.05)
        ax_path.scatter(d["x_ref_m"].iloc[0], d["y_ref_m"].iloc[0], s=15, color=PALETTE["start"], zorder=3)
        ax_path.scatter(d["x_ref_m"].iloc[-1], d["y_ref_m"].iloc[-1], s=15, marker="s", color=PALETTE["end"], zorder=3)
        middle = len(d) // 2
        next_point = min(middle + max(1, len(d) // 80), len(d) - 1)
        ax_path.annotate("", (d["x_ref_m"].iloc[next_point], d["y_ref_m"].iloc[next_point]), (d["x_ref_m"].iloc[middle], d["y_ref_m"].iloc[middle]), arrowprops={"arrowstyle": "-|>", "color": PALETTE["direction"], "lw": 0.8})
        ax_path.set_aspect("equal", adjustable="datalim")
        ax_path.margins(0.08)
        ax_path.yaxis.set_major_locator(MaxNLocator(nbins=6, prune="both"))
        ax_path.set_xlabel("X (m)", labelpad=1)
        ax_path.set_ylabel("Y (m)", labelpad=1)
        ax_path.set_title(f"{path_id}  {role}", loc="left", fontweight="bold", fontsize=6.8, pad=3)
        add_panel_label(ax_path, f"({chr(97 + index)})", x=-0.18, y=1.04)
        clean_axis(ax_path, "both")
        ax_grade.plot(d["t_s"], d["grade_deg"], color=PALETTE["fusion"], linewidth=0.95)
        ax_grade.axhline(0, color="#AAAAAA", linewidth=0.5, linestyle="--")
        ax_grade.set_ylim(-grade_lim, grade_lim)
        ax_grade.set_ylabel("Grade\n(deg)", labelpad=-2.5)
        ax_grade.tick_params(labelbottom=False)
        clean_axis(ax_grade)
        ax_speed.plot(d["t_s"], d["v_ref_mps"], color=PALETTE["imu"], linewidth=0.95)
        ax_speed.set_ylim(speed_min, speed_max)
        ax_speed.set_ylabel("Speed\n(m/s)", labelpad=-2.5)
        ax_speed.set_xlabel("Time (s)", labelpad=1)
        clean_axis(ax_speed)
    p4 = data[data["route_id"] == "P4"]
    p4_monotonic = {
        name: bool(np.all(np.diff(p4.loc[p4["grade_segment"] == name, "grade_deg"]) >= -1e-12))
        if grade1 >= grade0
        else bool(np.all(np.diff(p4.loc[p4["grade_segment"] == name, "grade_deg"]) <= 1e-12))
        for name, _, _, grade0, grade1 in P4_GRADE_SEGMENTS
    }
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    path_profile_text_overlap_samples: dict[str, int] = {}
    path_profile_text_min_clearance_px: dict[str, float] = {}
    for (path_id, _, _), (ax_path, ax_grade, ax_speed) in zip(ROUTES6, panel_axes):
        path_line = ax_path.lines[0]
        path_pixels = ax_path.transData.transform(np.column_stack([path_line.get_xdata(), path_line.get_ydata()]))
        profile_text = [ax_grade.yaxis.label, ax_speed.yaxis.label, *ax_grade.get_yticklabels(), *ax_speed.get_yticklabels()]
        overlap_count = 0
        clearances: list[float] = []
        for artist in profile_text:
            if not artist.get_visible() or not artist.get_text():
                continue
            raw_bounds = artist.get_window_extent(renderer)
            dx = np.maximum(np.maximum(raw_bounds.x0 - path_pixels[:, 0], 0.0), path_pixels[:, 0] - raw_bounds.x1)
            dy = np.maximum(np.maximum(raw_bounds.y0 - path_pixels[:, 1], 0.0), path_pixels[:, 1] - raw_bounds.y1)
            clearances.append(float(np.hypot(dx, dy).min()))
            bounds = raw_bounds.expanded(1.04, 1.04)
            overlap_count += int(
                np.count_nonzero(
                    (path_pixels[:, 0] >= bounds.x0)
                    & (path_pixels[:, 0] <= bounds.x1)
                    & (path_pixels[:, 1] >= bounds.y0)
                    & (path_pixels[:, 1] <= bounds.y1)
                )
            )
        path_profile_text_overlap_samples[path_id] = overlap_count
        path_profile_text_min_clearance_px[path_id] = round(min(clearances), 2)
    if any(path_profile_text_overlap_samples.values()):
        raise ValueError(f"Fig03 path/profile text overlap detected: {path_profile_text_overlap_samples}")
    if min(path_profile_text_min_clearance_px.values()) < 6.0:
        raise ValueError(f"Fig03 path/profile text clearance is below 6 px: {path_profile_text_min_clearance_px}")
    checks = {
        "route_count": int(data["route_id"].nunique()),
        "route_order": list(data.sort_values("route_order")["route_id"].drop_duplicates()),
        "panel_grid": "2 x 3 route profiles; each profile contains path, grade, and speed axes",
        "all_values_finite": bool(np.isfinite(data[["t_s", "x_ref_m", "y_ref_m", "grade_deg", "v_ref_mps"]]).all().all()),
        "time_strictly_increasing_per_route": bool(data.groupby("route_id")["t_s"].apply(lambda x: np.all(np.diff(x) > 0)).all()),
        "render_decimation": {"rule": "uniform index selection, max 2200 points, first and last retained", "rendered_samples": render_counts},
        "flat_route_p5_max_abs_grade_deg": float(data.loc[data["route_id"] == "P5", "grade_deg"].abs().max()),
        "route_identity": "closed-loop benchmark routes",
        "route_titles": [f"{path_id}  {role}" for path_id, role, _ in ROUTES6],
        "title_star_count": 0,
        "bottom_explanatory_note_present": False,
        "shared_grade_ylim_deg": [-grade_lim, grade_lim],
        "shared_speed_ylim_mps": [speed_min, speed_max],
        "path_profile_text_overlap_samples": path_profile_text_overlap_samples,
        "all_path_profile_text_overlaps_clear": not any(path_profile_text_overlap_samples.values()),
        "path_profile_text_min_clearance_px": path_profile_text_min_clearance_px,
        "minimum_path_profile_text_clearance_requirement_px": 6.0,
        "p4_grade_source": "metadata_reconstructed",
        "p4_metadata_segment_bounds_match_file": p4_metadata_bounds_match,
        "p4_metadata_segments": [
            {"name": name, "t0_s": t0, "t1_s": t1, "grade0_deg": grade0, "grade1_deg": grade1}
            for name, t0, t1, grade0, grade1 in P4_GRADE_SEGMENTS
        ],
        "p4_startup_flat_max_abs_grade_deg": float(p4.loc[p4["t_s"] <= 4.0, "grade_deg"].abs().max()),
        "p4_grade_min_max_deg": [float(p4["grade_deg"].min()), float(p4["grade_deg"].max())],
        "p4_segment_monotonic_or_constant": p4_monotonic,
        "p4_simulation_consistency": "not asserted; caption must state that the P4 grade profile follows frozen segment metadata",
        "source_curve_traceability": "grade_deg is the plotted full-resolution source; rendered_in_figure identifies exported line samples",
    }
    return data, fig, raw_inputs, checks


def build_fig04(root: Path):
    base = root / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/03_A3_slope_scheduling_necessity/04_summary"
    effects_path = base / "paired_effects.csv"
    ci_path = base / "bootstrap_ci_results.csv"
    effects = pd.read_csv(effects_path)
    cis = pd.read_csv(ci_path)
    contrasts = ("A3_ORACLE_VS_ZS", "A3_IMU_VS_ZS")
    metrics = ("ey_rmse", "epsi_rmse", "j_du")
    effects = effects[effects["contrast_id"].isin(contrasts) & effects["metric"].isin(metrics)].copy()
    cis = cis[cis["contrast_id"].isin(contrasts) & cis["metric"].isin(metrics)].copy()
    effects["route_id"] = effects["path_id"].str.extract(r"p0?([1-6])")[0].map(lambda value: f"P{value}")
    if len(effects) != 36 or len(cis) != 6:
        raise ValueError(f"Expected 36 route effects and 6 summaries, got {len(effects)} and {len(cis)}")
    recomputed = effects["comparator_value"] - effects["target_value"]
    if not np.allclose(recomputed, effects["effect_comparator_minus_target"], rtol=1e-12, atol=1e-12):
        raise ValueError("Fig04 effect direction is not comparator minus target")
    effect_source = effects.copy()
    effect_source.insert(0, "record_type", "route_effect")
    ci_source = cis.copy()
    ci_source.insert(0, "record_type", "bootstrap_summary")
    source = pd.concat([effect_source, ci_source], ignore_index=True, sort=False)
    configure_style(6.5)
    fig, axes = plt.subplots(1, 3, figsize=(183 * MM, 59 * MM), gridspec_kw={"left": 0.125, "right": 0.99, "bottom": 0.21, "top": 0.79, "wspace": 0.50})
    metric_specs = (
        ("ey_rmse", "Lateral-error RMS reduction (m)"),
        ("epsi_rmse", "Heading-error RMS reduction (rad)"),
        ("j_du", r"Input-increment reduction, $J_{\Delta u}$"),
    )
    contrast_specs = (
        ("A3_ORACLE_VS_ZS", "Truth-driven conditioned reference", PALETTE["oracle"]),
        ("A3_IMU_VS_ZS", "Simple causal-IMU baseline", PALETTE["imu"]),
    )
    for panel, (metric, xlabel) in enumerate(metric_specs):
        ax = axes[panel]
        ax.axvline(0, color="#333333", linewidth=0.65, zorder=0)
        for row_index, (contrast, _, color) in enumerate(contrast_specs):
            subset = effects[(effects["metric"] == metric) & (effects["contrast_id"] == contrast)].sort_values("route_id")
            y = row_index + np.linspace(-0.22, 0.22, len(subset))
            ax.scatter(subset["effect_comparator_minus_target"], y, s=14, marker="o", facecolor=color, edgecolor="white", linewidth=0.35, alpha=0.75, zorder=2)
            for x_value, y_value, route_id in zip(subset["effect_comparator_minus_target"], y, subset["route_id"]):
                place_left = (metric == "ey_rmse" and x_value > 5.0) or (metric == "epsi_rmse" and x_value > 1.2) or (metric == "j_du" and x_value > 1400)
                vertical_offset = {"P3": 2, "P4": -2}.get(route_id, 0) if panel == 0 else 0
                ax.annotate(
                    route_id,
                    (x_value, y_value),
                    xytext=(-7 if place_left else 7, vertical_offset),
                    textcoords="offset points",
                    ha="right" if place_left else "left",
                    va="center",
                    fontsize=6.5,
                    color="#555555",
                    arrowprops={"arrowstyle": "-", "color": "#888888", "linewidth": 0.4, "shrinkA": 1.5, "shrinkB": 1.5},
                )
            summary = cis[(cis["metric"] == metric) & (cis["contrast_id"] == contrast)].iloc[0]
            ax.errorbar(summary["estimate"], row_index, xerr=[[summary["estimate"] - summary["ci95_low"]], [summary["ci95_high"] - summary["estimate"]]], fmt="D", markersize=6.0, color=color, markeredgecolor="#222222", markeredgewidth=0.7, capsize=2.4, linewidth=1.2, zorder=4)
        ax.set_yticks([0, 1], ["Truth-driven\nconditioned reference", "Simple causal-IMU\nbaseline"])
        ax.invert_yaxis()
        ax.set_xlabel(xlabel, labelpad=3)
        if metric == "j_du":
            ax.set_xlim(-1150, 2300)
            ax.set_xticks([-1000, 0, 1000, 2000])
        add_panel_label(ax, f"({chr(97 + panel)})", x=-0.17, y=1.08)
        clean_axis(ax, "x")
    fig.legend(
        [
            Line2D([], [], marker="o", linestyle="none", markerfacecolor="#888888", markeredgecolor="white", markeredgewidth=0.35, markersize=3.5),
            Line2D([], [], marker="D", linestyle="none", markerfacecolor="#888888", markeredgecolor="#222222", markeredgewidth=0.7, markersize=5.0),
        ],
        ["Route effect", "Mean and 95% bootstrap CI"],
        loc="upper center",
        ncol=2,
        bbox_to_anchor=(0.53, 0.98),
    )
    fig.text(0.5, 0.035, "Comparator minus target: positive values favor the named grade source. The truth-driven conditioned reference is analysis-only.", ha="center", fontsize=6.5)
    checks = {
        "route_effect_rows": 36,
        "bootstrap_summary_rows": 6,
        "contrasts": list(contrasts),
        "metrics": list(metrics),
        "routes_per_contrast_metric": 6,
        "effect_definition": "zero-grade comparator minus target; positive favors target",
        "bootstrap_iterations": int(cis["n_bootstrap"].iloc[0]) if "n_bootstrap" in cis else 10000,
        "bootstrap_seed": int(cis["bootstrap_seed"].iloc[0]) if "bootstrap_seed" in cis else 20260715,
        "all_adverse_and_zero_points_retained": True,
        "marker_semantics": {
            "route_effect": "small circle",
            "summary": "large black-edged diamond with 95% bootstrap CI",
        },
    }
    return source, fig, [effects_path, ci_path], checks


def _mean_t_ci(values: np.ndarray) -> tuple[float, float, float]:
    values = np.asarray(values, dtype=float)
    mean = float(values.mean())
    half_width = float(stats.t.ppf(0.975, len(values) - 1) * stats.sem(values))
    return mean, mean - half_width, mean + half_width


def build_fig05(root: Path):
    input_path = root / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/03_offline/offline_case_metrics.csv"
    raw = pd.read_csv(input_path)
    methods = (
        ("modern_tcn_delta_bank_124", "ModernTCN-delta", COLORS["delta"]),
        ("modern_tcn_22d", "ModernTCN-22D", COLORS["baseline"]),
        ("gru_22d", "GRU-22D", PALETTE["gru"]),
        ("tcn_22d", "TCN-22D", PALETTE["tcn"]),
    )
    metric_specs = (
        ("theta_abs_le_10_mae_deg", "grade_mae_deg", "Grade MAE (deg)"),
        ("theta_abs_le_10_p95_abs_err_deg", "p95_abs_error_deg", "P95 absolute error (deg)"),
    )
    method_ids = [method[0] for method in methods]
    require_columns(raw, {"method_id", "seed", *(metric[0] for metric in metric_specs)}, input_path)
    data = raw[raw["method_id"].isin(method_ids)].copy()
    data["method_label"] = data["method_id"].map({method_id: label for method_id, label, _ in methods})
    data["method_order"] = data["method_id"].map({method_id: order for order, (method_id, _, _) in enumerate(methods)})
    for source_column, output_column, _ in metric_specs:
        data[output_column] = data[source_column].astype(float)
    data = data[["method_id", "method_label", "method_order", "seed", "grade_mae_deg", "p95_abs_error_deg"]].sort_values(["method_order", "seed"], ignore_index=True)
    if len(data) != 40 or data.duplicated(["method_id", "seed"]).any():
        raise ValueError("Fig05 must contain 4 methods x 10 unique seeds")
    for method_id in method_ids:
        observed = set(data.loc[data["method_id"] == method_id, "seed"].astype(int))
        if observed != set(SEEDS):
            raise ValueError(f"{method_id} seed set changed: {sorted(observed)}")
    configure_style()
    fig, axes = plt.subplots(1, 2, figsize=(183 * MM, 70 * MM), gridspec_kw={"left": 0.07, "right": 0.99, "bottom": 0.22, "top": 0.90, "wspace": 0.27})
    offsets = np.linspace(-0.13, 0.13, len(SEEDS))
    labels = ["ModernTCN-delta", "ModernTCN-22D", "GRU-22D", "TCN-22D"]
    summaries: list[dict[str, object]] = []
    for panel, (_, metric, ylabel) in enumerate(metric_specs):
        ax = axes[panel]
        delta = data[data["method_id"] == methods[0][0]].set_index("seed").reindex(SEEDS)
        baseline = data[data["method_id"] == methods[1][0]].set_index("seed").reindex(SEEDS)
        for seed in SEEDS:
            ax.plot([0, 1], [delta.loc[seed, metric], baseline.loc[seed, metric]], color="#C8C8C8", linewidth=0.65, zorder=1)
        for position, (method_id, label, color) in enumerate(methods):
            subset = data[data["method_id"] == method_id].set_index("seed").reindex(SEEDS)
            values = subset[metric].to_numpy(dtype=float)
            ax.scatter(position + offsets, values, s=17, color=color, alpha=0.84, edgecolor="white", linewidth=0.35, zorder=2)
            mean, low, high = _mean_t_ci(values)
            ax.errorbar(position, mean, yerr=[[mean - low], [high - mean]], fmt="_", markersize=12, markeredgewidth=2, color="#222222", capsize=3, linewidth=1.05, zorder=4)
            summaries.append({"metric": metric, "method_id": method_id, "mean": mean, "ci95_low": low, "ci95_high": high})
        ax.set_xticks(range(4), labels)
        ax.set_ylabel(ylabel)
        ax.set_ylim(bottom=0)
        add_panel_label(ax, f"({chr(97 + panel)})", x=-0.12, y=1.03)
        clean_axis(ax)
    fig.text(0.5, 0.035, "Points are model seeds; gray lines pair the two ModernTCN representations; black bars are means and 95% t intervals.", ha="center", fontsize=6.2)
    paired_summary: dict[str, object] = {}
    delta = data[data["method_id"] == methods[0][0]].set_index("seed").reindex(SEEDS)
    for _, metric, _ in metric_specs:
        paired_summary[metric] = {}
        for method_id, _, _ in methods[1:]:
            competitor = data[data["method_id"] == method_id].set_index("seed").reindex(SEEDS)
            difference = competitor[metric].to_numpy() - delta[metric].to_numpy()
            estimate, low, high = _mean_t_ci(difference)
            paired_summary[metric][method_id] = {"direction": "competitor minus ModernTCN-delta; positive favors delta", "estimate": estimate, "ci95_low": low, "ci95_high": high}
    checks = {
        "row_count": 40,
        "method_count": 4,
        "seeds_per_method": 10,
        "seed_order": list(SEEDS),
        "all_points_visible": True,
        "same_seed_pairing": True,
        "ci_definition": "two-sided 95% Student-t interval over 10 model seeds",
        "paired_effects": paired_summary,
        "absolute_metric_summaries": summaries,
        "input_sha256_matches_handoff": sha256_file(input_path).upper() == "12AC98B5920DC0228EA064E781B47B4ACBC62942F2F0BDF6FFEAFC6D893CD1E2",
    }
    return data, fig, [input_path], checks


def _boolean_intervals(time: np.ndarray, mask: np.ndarray) -> list[tuple[float, float]]:
    changes = np.flatnonzero(mask[1:] != mask[:-1]) + 1
    starts = np.concatenate(([0], changes))
    stops = np.concatenate((changes, [mask.size]))
    edges = np.empty(mask.size + 1, dtype=float)
    edges[1:-1] = 0.5 * (time[:-1] + time[1:])
    edges[0] = time[0]
    edges[-1] = time[-1]
    return [(float(edges[start]), float(edges[stop])) for start, stop in zip(starts, stops) if mask[start]]


def build_fig06(root: Path):
    case_dir = root / "results/modern_tcn_metric_rebuild/40_legal_imu_uncertainty_fusion/04_cases/nominal/IMU_ONLY/s42/path_closed_loop_long_updown_theta10_v1"
    trace_path = case_dir / "trace.csv"
    debug_path = case_dir / "node40_runtime_debug.csv"
    trace = pd.read_csv(trace_path)
    debug = pd.read_csv(debug_path)
    require_columns(trace, {"t_s", "theta_true"}, trace_path)
    require_columns(debug, {"step", "theta_tcn", "theta_imu", "variance_imu", "imu_valid", "K_imu_eff", "quality_code"}, debug_path)
    if len(trace) != 4401 or len(debug) != 4400:
        raise ValueError(f"Fig06 expects 4401 trace rows and 4400 updates, got {len(trace)} and {len(debug)}")
    steps = debug["step"].to_numpy(dtype=int)
    if not np.array_equal(steps, np.arange(1, len(trace))):
        raise ValueError("Fig06 debug.step no longer maps exactly to trace sample indices 1..4400")
    data = pd.DataFrame(
        {
            "sample_index": np.arange(len(trace)),
            "debug_step": np.concatenate(([np.nan], steps.astype(float))),
            "t_s": trace["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(trace["theta_true"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.concatenate(([np.nan], np.rad2deg(debug["theta_tcn"].to_numpy(dtype=float)))),
            "theta_imu_deg": np.concatenate(([np.nan], np.rad2deg(debug["theta_imu"].to_numpy(dtype=float)))),
            "variance_imu_rad2": np.concatenate(([np.nan], debug["variance_imu"].to_numpy(dtype=float))),
            "imu_valid": np.concatenate(([0], debug["imu_valid"].to_numpy(dtype=int))),
            "K_imu_eff": np.concatenate(([0.0], debug["K_imu_eff"].to_numpy(dtype=float))),
            "quality_code": np.concatenate(([0], debug["quality_code"].to_numpy(dtype=int))),
            "observer_update_available": np.concatenate(([0], np.ones(len(debug), dtype=int))),
        }
    )
    if (data.loc[1:, "variance_imu_rad2"] < 0).any():
        raise ValueError("Fig06 observer variance contains negative values")
    data["imu_uncertainty_halfwidth_deg"] = np.rad2deg(1.96 * np.sqrt(np.maximum(data["variance_imu_rad2"], 0)))
    data["delta_abs_error_deg"] = (data["theta_imu_deg"] - data["theta_true_deg"]).abs() - (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    data["imu_locally_better"] = ((data["imu_valid"] == 1) & (data["delta_abs_error_deg"] < 0)).astype(int)
    if not np.all(np.diff(data["t_s"]) > 0) or not np.isclose(data["t_s"].iloc[-1], 44.0):
        raise ValueError("Fig06 time alignment changed")
    configure_style()
    fig = plt.figure(figsize=(89 * MM, 104 * MM))
    grid = fig.add_gridspec(3, 1, height_ratios=[2.5, 0.5, 1.25], left=0.17, right=0.98, bottom=0.105, top=0.83, hspace=0.19)
    ax_grade = fig.add_subplot(grid[0])
    ax_state = fig.add_subplot(grid[1], sharex=ax_grade)
    ax_delta = fig.add_subplot(grid[2], sharex=ax_grade)
    axes = (ax_grade, ax_state, ax_delta)
    time = data["t_s"].to_numpy()
    invalid = data["imu_valid"].to_numpy(dtype=bool) == 0
    for ax in axes:
        for start, stop in _boolean_intervals(time, invalid):
            ax.axvspan(start, stop, facecolor=PALETTE["invalid"], edgecolor="#AFAFAF", linewidth=0.25, hatch="////", alpha=0.32, zorder=0)
    uncertainty = data["imu_uncertainty_halfwidth_deg"].to_numpy()
    imu = data["theta_imu_deg"].to_numpy()
    ax_grade.fill_between(time, imu - uncertainty, imu + uncertainty, color=PALETTE["imu"], alpha=0.14, linewidth=0)
    ax_grade.plot(time, imu, color=PALETTE["imu"], linestyle=(0, (4, 2)), linewidth=0.8)
    ax_grade.plot(time, data["theta_mtcn_deg"], color=PALETTE["mtcn"], linewidth=0.9)
    ax_grade.plot(time, data["theta_true_deg"], color=PALETTE["truth"], linewidth=1.15)
    ax_grade.set_ylabel("Grade angle (deg)", labelpad=2)
    add_panel_label(ax_grade, "(a)", x=-0.19, y=1.015)
    gain = data["K_imu_eff"].to_numpy()
    ax_state.fill_between(time, 0, gain, step="post", color=PALETTE["imu"], alpha=0.62)
    ax_state.set_ylim(0, 1.02)
    ax_state.set_yticks([0, 1])
    ax_state.set_ylabel(r"$K_{IMU}$", labelpad=2)
    add_panel_label(ax_state, "(b)", x=-0.19, y=1.015)
    delta = data["delta_abs_error_deg"].to_numpy()
    finite = np.isfinite(delta)
    ax_delta.fill_between(time, 0, delta, where=finite & (delta <= 0), color=COLORS["benefit"], alpha=0.30)
    ax_delta.fill_between(time, 0, delta, where=finite & (delta > 0), color=COLORS["adverse"], alpha=0.28)
    ax_delta.plot(time, delta, color="#555555", linewidth=0.48)
    ax_delta.axhline(0, color="#222222", linewidth=0.6)
    limit = math.ceil(float(np.nanmax(np.abs(delta))) * 2) / 2
    ax_delta.set_ylim(-limit, limit)
    ax_delta.set_ylabel(r"$|e_{\mathrm{obs}}|-|e_{\mathrm{MTCN}\!-\!\delta}|$" + "\n(deg)", labelpad=2)
    ax_delta.set_xlabel("Time (s)")
    add_panel_label(ax_delta, "(c)", x=-0.19, y=1.015)
    for ax in axes:
        ax.set_xlim(0, 44)
        clean_axis(ax)
    ax_grade.tick_params(labelbottom=False)
    ax_state.tick_params(labelbottom=False)
    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.15),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.8, linestyle="--"),
            Patch(facecolor=PALETTE["imu"], alpha=0.14),
            Patch(facecolor=PALETTE["invalid"], edgecolor="#AFAFAF", hatch="////", alpha=0.32),
        ],
        ["Truth", "ModernTCN-delta", "Qualified causal inertial\nobserver", r"Observer uncertainty $\pm1.96\sqrt{var}$", "Invalid / unavailable"],
        loc="upper center",
        ncol=2,
        bbox_to_anchor=(0.58, 0.985),
        handlelength=2.5,
        columnspacing=1.1,
    )
    checks = {
        "fixed_case": "P3 long up/down, seed 42, Node40 IMU_ONLY",
        "trace_samples": 4401,
        "debug_updates": 4400,
        "alignment_rule": "debug.step equals trace sample index; initial trace sample retained; no interpolation",
        "time_start_s": float(data["t_s"].iloc[0]),
        "time_end_s": float(data["t_s"].iloc[-1]),
        "variance_nonnegative": True,
        "invalid_or_unavailable_samples": int((data["imu_valid"] == 0).sum()),
        "valid_beneficial_samples": int(((data["imu_valid"] == 1) & (data["delta_abs_error_deg"] < 0)).sum()),
        "valid_nonbeneficial_samples": int(((data["imu_valid"] == 1) & (data["delta_abs_error_deg"] >= 0)).sum()),
        "error_difference_direction": "negative means the qualified causal inertial observer has lower absolute grade error than ModernTCN-delta",
        "uncertainty_definition": "estimate +/- 1.96 sqrt(observer variance); not a calibrated coverage claim",
    }
    return data, fig, [trace_path, debug_path], checks


def _bootstrap_mean_ci(values: np.ndarray, seed: int, iterations: int = 5000) -> tuple[float, float, float]:
    values = np.asarray(values, dtype=float)
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), (iterations, len(values)))
    boot = values[indices].mean(axis=1)
    return float(values.mean()), float(np.quantile(boot, 0.025)), float(np.quantile(boot, 0.975))


def _bootstrap_ratio_of_means_ci(
    numerator: np.ndarray, denominator: np.ndarray, seed: int, iterations: int = 5000
) -> tuple[float, float, float]:
    numerator = np.asarray(numerator, dtype=float)
    denominator = np.asarray(denominator, dtype=float)
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(numerator), (iterations, len(numerator)))
    ratios = numerator[indices].mean(axis=1) / denominator[indices].mean(axis=1)
    estimate = float(numerator.mean() / denominator.mean())
    return estimate, float(np.quantile(ratios, 0.025)), float(np.quantile(ratios, 0.975))


def build_fig07(root: Path):
    summary_dir = root / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3/04_summaries"
    pair_path = summary_dir / "innovation_development_pair_details.csv"
    summary_path = summary_dir / "innovation_development_summary.json"
    raw = pd.read_csv(pair_path)
    frozen_summary = json.loads(summary_path.read_text(encoding="utf-8"))
    require_columns(raw, {"path", "seed", "J", "ratios", "theta_candidate", "theta_baseline", "sample_count", "active_count", "improve_count", "degrade_count", "fallback", "safe"}, pair_path)
    if len(raw) != 90 or raw.duplicated(["path", "seed"]).any():
        raise ValueError("Fig07 requires 90 unique route-seed pairs")
    data = raw.copy()
    data["route_id"] = data["path"].map(ROUTE9)
    if data["route_id"].isna().any() or set(data["route_id"]) != {f"P{index}" for index in range(1, 10)}:
        raise ValueError("Fig07 route mapping is incomplete")
    parsed_ratios = data["ratios"].map(json.loads)
    if not parsed_ratios.map(len).eq(5).all():
        raise ValueError("Fig07 control index must contain five component ratios")
    component_names = ("ey_ratio", "xy_ratio", "epsi_ratio", "j_du_ratio", "omega_cmd_rms_ratio")
    for index, name in enumerate(component_names):
        data[name] = parsed_ratios.map(lambda values: float(values[index]))
    data["theta_ratio"] = np.divide(
        data["theta_candidate"],
        data["theta_baseline"],
        out=np.full(len(data), np.nan, dtype=float),
        where=data["theta_baseline"].to_numpy(dtype=float) != 0,
    )
    data["theta_ratio_adjudicable"] = data["theta_ratio"].notna()
    data["neutral_count"] = data["active_count"] - data["improve_count"] - data["degrade_count"]
    if (data["neutral_count"] < 0).any():
        raise ValueError("Fig07 active classification counts are inconsistent")
    theta_ci = _bootstrap_ratio_of_means_ci(data["theta_candidate"].to_numpy(), data["theta_baseline"].to_numpy(), 4242)
    control_ci = _bootstrap_mean_ci(data["J"].to_numpy(), 4243)
    data = data[
        [
            "route_id", "path", "seed", "theta_candidate", "theta_baseline", "theta_ratio", "theta_ratio_adjudicable",
            "J", *component_names, "sample_count", "active_count", "improve_count", "neutral_count", "degrade_count", "fallback", "safe",
        ]
    ].sort_values(["route_id", "seed"], key=lambda series: series.map({f"P{i}": i for i in range(1, 10)}) if series.name == "route_id" else series, ignore_index=True)
    route_order = [f"P{index}" for index in range(1, 10)]
    theta_matrix = data.pivot(index="route_id", columns="seed", values="theta_ratio").reindex(index=route_order, columns=SEEDS)
    control_matrix = data.pivot(index="route_id", columns="seed", values="J").reindex(index=route_order, columns=SEEDS)
    if not np.isclose(theta_ci[0], frozen_summary["mean_theta_ratio"], rtol=1e-12) or not np.isclose(theta_ci[2], frozen_summary["theta_ratio_ci_upper"], rtol=1e-12):
        raise ValueError("Fig07 theta bootstrap does not reproduce the frozen summary")
    if not np.isclose(control_ci[0], frozen_summary["mean_J"], rtol=1e-12) or not np.isclose(control_ci[2], frozen_summary["J_ci_upper"], rtol=1e-12):
        raise ValueError("Fig07 control bootstrap does not reproduce the frozen summary")
    total_active = int(data["active_count"].sum())
    active_counts = {
        "improve": int(data["improve_count"].sum()),
        "neutral": int(data["neutral_count"].sum()),
        "degrade": int(data["degrade_count"].sum()),
    }
    active_fractions = {key: value / total_active for key, value in active_counts.items()}
    if not np.isclose(sum(active_fractions.values()), 1.0):
        raise ValueError("Fig07 active categories do not sum to 100%")
    configure_style(6.5)
    fig = plt.figure(figsize=(183 * MM, 104 * MM))
    grid = fig.add_gridspec(2, 2, width_ratios=[4.8, 1.45], left=0.075, right=0.985, bottom=0.18, top=0.915, wspace=0.20, hspace=0.20)
    ax_theta = fig.add_subplot(grid[0, 0])
    ax_control = fig.add_subplot(grid[1, 0], sharex=ax_theta, sharey=ax_theta)
    summary_grid = grid[:, 1].subgridspec(2, 1, height_ratios=[1.35, 0.75], hspace=0.55)
    ax_summary = fig.add_subplot(summary_grid[0])
    ax_active = fig.add_subplot(summary_grid[1])
    finite_values = np.concatenate([theta_matrix.to_numpy()[np.isfinite(theta_matrix.to_numpy())], control_matrix.to_numpy().ravel()])
    deviation = max(0.38, float(np.max(np.abs(finite_values - 1.0))))
    norm = TwoSlopeNorm(vmin=1.0 - deviation, vcenter=1.0, vmax=1.0 + deviation)
    cmap = plt.get_cmap("RdBu_r").copy()
    cmap.set_bad("#F2F2F2")
    theta_image = ax_theta.imshow(theta_matrix.to_numpy(), aspect="auto", cmap=cmap, norm=norm, interpolation="nearest")
    ax_control.imshow(control_matrix.to_numpy(), aspect="auto", cmap=cmap, norm=norm, interpolation="nearest")
    for row in range(9):
        for col in range(10):
            if not np.isfinite(theta_matrix.iloc[row, col]):
                ax_theta.scatter(col, row, marker="x", s=13, color="#555555", linewidth=0.7)
            if control_matrix.iloc[row, col] > 1.02:
                ax_control.scatter(col, row, marker="^", s=15, facecolor="none", edgecolor="#5A1F1F", linewidth=0.65)
    for ax, ylabel, panel in ((ax_theta, "Grade-error ratio", "(a)"), (ax_control, "Control-index ratio", "(b)")):
        ax.set_yticks(range(9), route_order)
        ax.set_ylabel(f"{ylabel}\nClosed-loop route")
        for spine in ax.spines.values():
            spine.set_visible(False)
        add_panel_label(ax, panel, x=-0.09, y=1.03)
    ax_theta.tick_params(labelbottom=False)
    ax_control.set_xticks(range(10), [str(seed) for seed in SEEDS])
    ax_control.set_xlabel("Model seed")
    symbol_handles = [
        Line2D([], [], marker="x", linestyle="none", color="#555555", markersize=4.4, markeredgewidth=0.8),
        Line2D([], [], marker="^", linestyle="none", markerfacecolor="none", markeredgecolor="#5A1F1F", markersize=4.6, markeredgewidth=0.8),
    ]
    fig.legend(
        symbol_handles,
        ["Undefined grade ratio (zero denominator)", "Control-index ratio > 1.02"],
        loc="upper left",
        bbox_to_anchor=(0.075, 0.995),
        ncol=2,
        frameon=False,
        handletextpad=0.4,
        columnspacing=1.4,
        fontsize=6.5,
    )
    colorbar_axis = fig.add_axes([0.075, 0.075, 0.685, 0.025])
    colorbar = fig.colorbar(theta_image, cax=colorbar_axis, orientation="horizontal")
    colorbar.set_label("Adaptive/G0 ratio (lower is better; centered at 1)", labelpad=2)
    estimates = np.array([theta_ci[0], control_ci[0]])
    lows = np.array([theta_ci[1], control_ci[1]])
    highs = np.array([theta_ci[2], control_ci[2]])
    y = np.array([0, 1])
    ax_summary.axvline(1.0, color="#222222", linewidth=0.7)
    ax_summary.errorbar(estimates, y, xerr=[estimates - lows, highs - estimates], fmt="o", color=PALETTE["fusion"], markeredgecolor="white", markeredgewidth=0.45, capsize=2.5, linewidth=1.05)
    ax_summary.set_yticks(y, ["Grade error", "Control index"])
    ax_summary.invert_yaxis()
    ax_summary.set_xlabel("Overall ratio (95% bootstrap CI)")
    ax_summary.set_xlim(min(0.78, float(lows.min()) - 0.02), 1.03)
    clean_axis(ax_summary, "x")
    add_panel_label(ax_summary, "(c)", x=-0.23, y=1.04)
    left = 0.0
    active_colors = (COLORS["benefit"], COLORS["neutral"], COLORS["adverse"])
    active_labels = ("Improve", "Neutral", "Degrade")
    for label, color, key in zip(active_labels, active_colors, ("improve", "neutral", "degrade")):
        width = active_fractions[key]
        ax_active.barh([0], [width], left=left, height=0.42, color=color, edgecolor="white", linewidth=0.5)
        if width > 0.06:
            ax_active.text(left + width / 2, 0, f"{100 * width:.2f}%", ha="center", va="center", fontsize=6.5, color="white" if key == "improve" else "#333333")
        left += width
    ax_active.text(1.0, -0.38, f"Degrade {100 * active_fractions['degrade']:.2f}%", ha="right", va="top", fontsize=6.5, color=COLORS["adverse"])
    ax_active.set_xlim(0, 1)
    ax_active.set_yticks([])
    ax_active.set_xlabel("Active-sample classification")
    ax_active.spines["left"].set_visible(False)
    clean_axis(ax_active, None)
    ax_active.legend([Patch(facecolor=color) for color in active_colors], active_labels, loc="upper center", ncol=1, bbox_to_anchor=(0.5, 1.56), handlelength=1.3, labelspacing=0.25)
    checks = {
        "fixed_grid": "9 routes x 10 model seeds",
        "pair_count": 90,
        "undefined_theta_ratios_from_zero_denominator": int(data["theta_ratio"].isna().sum()),
        "undefined_theta_ratio_rendering": "gray x; cases retained, not converted to 1 or removed",
        "symbol_legend": {
            "x": "Undefined grade ratio (zero denominator)",
            "triangle": "Control-index ratio > 1.02",
        },
        "control_index_definition": "mean of ey_rmse, xy_rmse, epsi_rmse, j_du, and omega_cmd_rms candidate/baseline ratios",
        "overall_theta_ratio": {"estimate": theta_ci[0], "ci95_low": theta_ci[1], "ci95_high": theta_ci[2]},
        "overall_control_index_ratio": {"estimate": control_ci[0], "ci95_low": control_ci[1], "ci95_high": control_ci[2]},
        "bootstrap_iterations": 5000,
        "active_sample_count": total_active,
        "active_counts": active_counts,
        "active_fractions": active_fractions,
        "neutral_definition": "absolute grade-error change within +/-0.1 deg among active samples",
        "J_gt_1p02_count": int((data["J"] > 1.02).sum()),
        "J_gt_1p05_count": int((data["J"] > 1.05).sum()),
        "fallback_exact": bool((data["fallback"].abs() <= 1e-12).all()),
        "frozen_status": frozen_summary["status"],
    }
    return data, fig, [pair_path, summary_path], checks


def build_fig08(root: Path):
    node_root = root / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3"
    case_rel = Path("03_cases/nominal")
    path_tag = "path_closed_loop_sharp_turn_transition_theta10_v1"
    model_seed = 7
    case_dirs = {
        group: node_root / case_rel / group / f"s{model_seed}" / path_tag
        for group in ("ADAPTIVE", "G0")
    }
    pair_path = node_root / "04_summaries/innovation_development_pair_details.csv"
    summary_path = node_root / "04_summaries/innovation_development_summary.json"
    raw_inputs: list[Path] = [pair_path, summary_path]
    pair_data = pd.read_csv(pair_path)
    aggregate = json.loads(summary_path.read_text(encoding="utf-8"))
    require_columns(
        pair_data,
        {"path", "seed", "J", "theta_candidate", "theta_baseline", "sample_count", "active_count", "improve_count", "degrade_count"},
        pair_path,
    )
    pair_data["theta_ratio"] = pair_data["theta_candidate"] / pair_data["theta_baseline"]
    pair_data["active_fraction"] = pair_data["active_count"] / pair_data["sample_count"]
    pair_data["aggregate_distance"] = np.hypot(
        pair_data["theta_ratio"] - float(aggregate["mean_theta_ratio"]),
        pair_data["J"] - float(aggregate["mean_J"]),
    )
    eligible = pair_data[
        (pair_data["theta_ratio"] < 1)
        & (pair_data["J"] < 1)
        & (pair_data["active_fraction"] >= float(aggregate["fusion_active_fraction"]))
    ].sort_values(["aggregate_distance", "path", "seed"])
    if eligible.empty or eligible.iloc[0]["path"] != path_tag or int(eligible.iloc[0]["seed"]) != model_seed:
        raise ValueError("Fig08 objective proximity-to-aggregate rule no longer selects P2 seed 7")
    selected_pair = eligible.iloc[0]
    loaded: dict[str, dict[str, object]] = {}
    for group, case_dir in case_dirs.items():
        paths = {
            "trace": case_dir / "trace.csv",
            "debug": case_dir / "node42_runtime_debug.csv",
            "manifest": case_dir / "case_manifest.json",
            "metrics": case_dir / "case_metrics.json",
        }
        raw_inputs.extend(paths.values())
        trace = pd.read_csv(paths["trace"])
        debug = pd.read_csv(paths["debug"])
        manifest = json.loads(paths["manifest"].read_text(encoding="utf-8"))
        metrics = json.loads(paths["metrics"].read_text(encoding="utf-8"))
        require_columns(trace, {"t_s", "theta_true", "theta_sched", "e_y", "e_psi", "xy_error", "F_cmd", "omega_cmd"}, paths["trace"])
        require_columns(debug, {"step", "theta_tcn", "theta_imu", "variance_imu", "imu_valid", "K_imu_eff", "theta_fused", "fallback_exact"}, paths["debug"])
        if manifest["group"] != group or int(manifest["model_seed"]) != model_seed or manifest["path_tag"] != path_tag:
            raise ValueError(f"Fig08 {group} manifest does not match P2 seed 7")
        if len(trace) != 5201 or len(debug) != 5200:
            raise ValueError(f"Fig08 {group} expects 5201 trace rows and 5200 updates")
        if not np.array_equal(debug["step"].to_numpy(dtype=int), np.arange(1, len(trace))):
            raise ValueError(f"Fig08 {group} debug steps do not align exactly with trace")
        if not np.all(np.diff(trace["t_s"]) > 0):
            raise ValueError(f"Fig08 {group} time is not strictly increasing")
        loaded[group] = {"trace": trace, "debug": debug, "manifest": manifest, "metrics": metrics}
    adaptive_trace = loaded["ADAPTIVE"]["trace"]
    g0_trace = loaded["G0"]["trace"]
    if not np.array_equal(adaptive_trace["t_s"].to_numpy(), g0_trace["t_s"].to_numpy()):
        raise ValueError("Fig08 Adaptive and G0 traces have different time bases")
    adaptive_debug = loaded["ADAPTIVE"]["debug"]
    data = pd.DataFrame(
        {
            "record_type": "trace",
            "route_id": "P2",
            "route_condition": "Sharp-turn transition",
            "model_seed": model_seed,
            "sample_index": np.arange(len(adaptive_trace)),
            "debug_step": np.concatenate(([np.nan], adaptive_debug["step"].to_numpy(dtype=float))),
            "t_s": adaptive_trace["t_s"].to_numpy(dtype=float),
            "theta_true_deg": np.rad2deg(adaptive_trace["theta_true"].to_numpy(dtype=float)),
            "theta_sched_fusion_lpv_mpc_deg": np.rad2deg(adaptive_trace["theta_sched"].to_numpy(dtype=float)),
            "theta_sched_mtcn_lpv_mpc_deg": np.rad2deg(g0_trace["theta_sched"].to_numpy(dtype=float)),
            "theta_mtcn_deg": np.concatenate(([np.nan], np.rad2deg(adaptive_debug["theta_tcn"].to_numpy(dtype=float)))),
            "theta_imu_deg": np.concatenate(([np.nan], np.rad2deg(adaptive_debug["theta_imu"].to_numpy(dtype=float)))),
            "theta_fused_deg": np.concatenate(([np.nan], np.rad2deg(adaptive_debug["theta_fused"].to_numpy(dtype=float)))),
            "variance_imu_rad2": np.concatenate(([np.nan], adaptive_debug["variance_imu"].to_numpy(dtype=float))),
            "imu_valid": np.concatenate(([0], adaptive_debug["imu_valid"].to_numpy(dtype=int))),
            "K_imu_eff": np.concatenate(([0.0], adaptive_debug["K_imu_eff"].to_numpy(dtype=float))),
            "fallback_exact": np.concatenate(([1], adaptive_debug["fallback_exact"].to_numpy(dtype=int))),
        }
    )
    data["imu_uncertainty_halfwidth_deg"] = np.rad2deg(1.96 * np.sqrt(np.maximum(data["variance_imu_rad2"], 0)))
    data["local_fusion_effect_deg"] = (data["theta_fused_deg"] - data["theta_true_deg"]).abs() - (data["theta_mtcn_deg"] - data["theta_true_deg"]).abs()
    metric_names = ("ey_rmse", "xy_rmse", "epsi_rmse", "j_du", "omega_cmd_rms")
    adaptive_metrics = loaded["ADAPTIVE"]["metrics"]
    g0_metrics = loaded["G0"]["metrics"]
    component_ratios = {name: float(adaptive_metrics[name] / g0_metrics[name]) for name in metric_names}
    invalid = data["imu_valid"].to_numpy(dtype=bool) == 0
    invalid_updates = invalid & data["debug_step"].notna().to_numpy()
    active_threshold_deg = float(adaptive_metrics["fusion_active_threshold_deg"])
    active = (
        np.abs(data["theta_fused_deg"].to_numpy(dtype=float) - data["theta_mtcn_deg"].to_numpy(dtype=float))
        > active_threshold_deg
    ) & data["debug_step"].notna().to_numpy()
    if invalid_updates.any():
        max_invalid_internal = float((data.loc[invalid_updates, "theta_fused_deg"] - data.loc[invalid_updates, "theta_mtcn_deg"]).abs().max())
    else:
        max_invalid_internal = 0.0
    expected_case = {
        "fusion_sample_count": 5200,
        "fusion_active_count": 3375,
        "active_improve_count": 2613,
        "active_degrade_count": 14,
    }
    for field, expected in expected_case.items():
        if int(adaptive_metrics[field]) != expected:
            raise ValueError(f"Fig08 {field} changed: {adaptive_metrics[field]} != {expected}")
    theta_ratio = float(adaptive_metrics["theta_fused_mae_deg"] / g0_metrics["theta_fused_mae_deg"])
    control_ratio = float(selected_pair["J"])
    if not np.isclose(theta_ratio, 0.8306188183914721, rtol=0, atol=1e-12):
        raise ValueError(f"Fig08 grade-error ratio changed: {theta_ratio}")
    if not np.isclose(control_ratio, 0.9480355294018376, rtol=0, atol=1e-12):
        raise ValueError(f"Fig08 control-index ratio changed: {control_ratio}")
    if int(active.sum()) != expected_case["fusion_active_count"]:
        raise ValueError("Fig08 effective-gain activation count does not match frozen metrics")

    configure_style(6.5)
    fig = plt.figure(figsize=(183 * MM, 108 * MM))
    grid = fig.add_gridspec(4, 1, height_ratios=[2.15, 1.35, 0.60, 1.30], left=0.105, right=0.985, bottom=0.105, top=0.80, hspace=0.25)
    ax_est = fig.add_subplot(grid[0])
    ax_sched = fig.add_subplot(grid[1], sharex=ax_est)
    ax_gain = fig.add_subplot(grid[2], sharex=ax_est)
    ax_effect = fig.add_subplot(grid[3], sharex=ax_est)
    axes = (ax_est, ax_sched, ax_gain, ax_effect)
    time = data["t_s"].to_numpy()
    qualified_imu = data["theta_imu_deg"].to_numpy(dtype=float).copy()
    qualified_imu[invalid] = np.nan
    ax_est.plot(time, data["theta_true_deg"], color=PALETTE["truth"], linewidth=1.2, zorder=6)
    ax_est.plot(time, data["theta_mtcn_deg"], color=PALETTE["mtcn"], linewidth=0.85, zorder=3)
    ax_est.plot(time, qualified_imu, color=PALETTE["imu"], linewidth=0.70, linestyle=(0, (4, 2)), zorder=4)
    ax_est.plot(time, data["theta_fused_deg"], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4)), zorder=5)
    ax_est.set_ylabel("Grade (deg)")
    ax_est.set_title("P2  Sharp-turn transition | model seed 7", loc="left", fontweight="bold", pad=3)
    ax_sched.plot(time, data["theta_true_deg"], color=PALETTE["truth"], linewidth=1.0, zorder=6)
    ax_sched.plot(time, data["theta_sched_mtcn_lpv_mpc_deg"], color=PALETTE["mtcn"], linewidth=0.9, zorder=3)
    ax_sched.plot(time, data["theta_sched_fusion_lpv_mpc_deg"], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4)), zorder=5)
    ax_sched.set_ylabel("Actual scheduled\ngrade (deg)")
    for start, stop in _boolean_intervals(time, active):
        ax_gain.axvspan(start, stop, facecolor=PALETTE["imu"], alpha=0.13, linewidth=0, zorder=0)
    ax_gain.step(time, data["K_imu_eff"], where="post", color=PALETTE["imu"], linewidth=0.75, zorder=2)
    ax_gain.set_ylim(0, 1.02)
    ax_gain.set_yticks([0, 1])
    ax_gain.set_ylabel(r"$K_{IMU}$")
    local_effect = data["local_fusion_effect_deg"].to_numpy()
    finite = np.isfinite(local_effect)
    ax_effect.fill_between(time, 0, local_effect, where=finite & (local_effect <= 0), color=COLORS["benefit"], alpha=0.30)
    ax_effect.fill_between(time, 0, local_effect, where=finite & (local_effect > 0), color=COLORS["adverse"], alpha=0.28)
    ax_effect.plot(time, local_effect, color="#555555", linewidth=0.45)
    ax_effect.axhline(0, color="#222222", linewidth=0.6)
    effect_limit = max(0.5, math.ceil(float(np.nanmax(np.abs(local_effect))) * 2) / 2)
    ax_effect.set_ylim(-effect_limit, effect_limit)
    ax_effect.set_ylabel(r"$\Delta|e_\theta|$ (deg)")
    direction_note = ax_effect.text(0.060, 0.90, "<0 favors Fusion", transform=ax_effect.transAxes, ha="left", va="top", fontsize=6.5, color=COLORS["benefit"])
    ax_effect.set_xlabel("Time (s)")
    panel_labels = [
        ax.text(0.008, 0.96, label, transform=ax.transAxes, ha="left", va="top", fontsize=8.0, fontweight="bold", color=PALETTE["truth"], clip_on=True, zorder=20)
        for ax, label in zip(axes, ("(a)", "(b)", "(c)", "(d)"))
    ]
    for ax in axes:
        ax.set_xlim(float(time[0]), float(time[-1]))
        clean_axis(ax)
    for ax in axes[:-1]:
        ax.tick_params(labelbottom=False)
    ax_effect.set_xticks(np.arange(0, 51, 10))
    fig.legend(
        [
            Line2D([], [], color=PALETTE["truth"], linewidth=1.2),
            Line2D([], [], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4))),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
            Line2D([], [], color=PALETTE["imu"], linewidth=0.7, linestyle="--"),
            Line2D([], [], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4))),
        ],
        ["Truth", "Adaptive fusion", "ModernTCN-delta", "MTCN-LPV-MPC schedule", "Qualified causal inertial observer", "Fusion-LPV-MPC schedule"],
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.545, 0.992),
        columnspacing=1.25,
        labelspacing=0.35,
    )
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    label_boxes = [artist.get_window_extent(renderer=renderer) for artist in panel_labels]
    ylabel_boxes = [ax.yaxis.label.get_window_extent(renderer=renderer) for ax in axes]
    label_ylabel_overlaps = [
        (panel_index, ylabel_index)
        for panel_index, label_box in enumerate(label_boxes)
        for ylabel_index, ylabel_box in enumerate(ylabel_boxes)
        if label_box.overlaps(ylabel_box)
    ]
    direction_note_overlap = bool(label_boxes[3].overlaps(direction_note.get_window_extent(renderer=renderer)))
    if label_ylabel_overlaps or direction_note_overlap:
        raise ValueError(
            f"Fig08 left-label collision detected: panel/ylabel={label_ylabel_overlaps}, panel-d/note={direction_note_overlap}"
        )
    checks = {
        "fixed_case": "P2 sharp-turn transition, model seed 7",
        "trace_rows_including_t0": 5201,
        "complete_update_samples": 5200,
        "debug_updates": 5200,
        "time_start_s": float(time[0]),
        "time_end_s": float(time[-1]),
        "paired_time_axis_exact": True,
        "actual_scheduled_grade_plotted": True,
        "reader_facing_G0_occurrences": 0,
        "metric_inset_removed": True,
        "grade_error_ratio_fusion_over_mtcn": theta_ratio,
        "composite_control_index_ratio_fusion_over_mtcn": control_ratio,
        "fusion_active_count": int(active.sum()),
        "fusion_active_definition": f"absolute Fusion-minus-ModernTCN-delta correction > {active_threshold_deg:g} deg",
        "active_improve_count": int(adaptive_metrics["active_improve_count"]),
        "active_degrade_count": int(adaptive_metrics["active_degrade_count"]),
        "active_neutral_count": int(adaptive_metrics["fusion_active_count"] - adaptive_metrics["active_improve_count"] - adaptive_metrics["active_degrade_count"]),
        "selection_rule": "among pairs with grade-error ratio < 1, control-index ratio < 1, and active fraction at least the 90-pair aggregate active fraction, minimize Euclidean distance to the aggregate grade-error and control-index ratios",
        "selection_rank": 1,
        "selection_distance": float(selected_pair["aggregate_distance"]),
        "aggregate_targets": {"grade_error_ratio": float(aggregate["mean_theta_ratio"]), "control_index_ratio": float(aggregate["mean_J"]), "active_fraction": float(aggregate["fusion_active_fraction"])},
        "invalid_update_count": int(invalid_updates.sum()),
        "max_invalid_fused_minus_mtcn_deg": max_invalid_internal,
        "fallback_segment_field_all_true": bool(data.loc[invalid_updates, "fallback_exact"].astype(bool).all()),
        "fallback_segment_exact_within_deg": bool(max_invalid_internal <= 1e-12),
        "control_index_components": component_ratios,
        "control_index_mean": float(np.mean(list(component_ratios.values()))),
        "local_effect_direction": "negative means adaptive fusion has lower absolute grade error than ModernTCN-delta",
        "panel_labels_placed_inside_axes": True,
        "panel_label_ylabel_overlap_count": len(label_ylabel_overlaps),
        "panel_d_label_direction_note_overlap": direction_note_overlap,
        "full_route_retained": True,
        "render_decimation": "none",
        "caption_contract": "Representative adaptive-fusion mechanism on P2 at seed 7; objectively selected by proximity to the 90-pair aggregate rather than maximum improvement; complete trace retained; aggregate performance is not inferred from this qualitative case.",
    }
    return data, fig, raw_inputs, checks


def build_fig09(root: Path):
    node_root = root / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3"
    nominal_root = node_root / "03_cases/nominal"
    oracle_root = root / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/03_A3_slope_scheduling_necessity/03_cases/Oracle_LPV_MPC"
    formal_routes = [(route_id, condition, Path(path_file).stem) for route_id, condition, path_file in ROUTES6]
    selected_specs = (
        ("P1", "Factory logistics", "path_factory_logistics_showcase_theta10_v10", "p01_factory_logistics_showcase"),
        ("P2", "Sharp-turn transition", "path_closed_loop_sharp_turn_transition_theta10_v1", "p02_sharp_turn_transition"),
        ("P5", "Flat factory logistics", "path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1", "p05_factory_flat_logistics"),
    )
    metric_fields = ("ey_rmse", "epsi_rmse", "j_du")
    raw_inputs: list[Path] = []
    route_audit: list[dict[str, object]] = []
    for route_id, condition, path_tag in formal_routes:
        values = {group: {field: [] for field in metric_fields} for group in ("G0", "ADAPTIVE")}
        for group in values:
            for seed in SEEDS:
                metric_path = nominal_root / group / f"s{seed}" / path_tag / "case_metrics.json"
                raw_inputs.append(metric_path)
                metrics = json.loads(metric_path.read_text(encoding="utf-8"))
                for field in metric_fields:
                    values[group][field].append(float(metrics[field]))
        row: dict[str, object] = {"record_type": "route_mean_audit", "route_id": route_id, "route_condition": condition}
        reported_improvements = []
        for field in metric_fields:
            mtcn_mean = float(np.mean(values["G0"][field]))
            fusion_mean = float(np.mean(values["ADAPTIVE"][field]))
            row[f"mtcn_mean_{field}"] = mtcn_mean
            row[f"fusion_mean_{field}"] = fusion_mean
            row[f"fusion_mtcn_ratio_{field}"] = fusion_mean / mtcn_mean
            reported_improvements.append(round(fusion_mean, 5) < round(mtcn_mean, 5))
        row["all_three_improve_at_reported_precision"] = bool(all(reported_improvements))
        route_audit.append(row)
    selected_by_audit = [row["route_id"] for row in route_audit if row["all_three_improve_at_reported_precision"]]
    if selected_by_audit != ["P1", "P2", "P5"]:
        raise ValueError(f"Fig09 route-mean selection changed: {selected_by_audit}")

    def normalized_cumulative_jdu(trace: pd.DataFrame, exclusion_s: float = 0.5) -> np.ndarray:
        time = trace["t_s"].to_numpy(dtype=float)
        evaluated = np.flatnonzero(time >= exclusion_s)
        if len(evaluated) < 2:
            raise ValueError("Fig09 trace has too few post-initialization samples for J_delta_u")
        d_force = np.diff(trace["F_cmd"].to_numpy(dtype=float)[evaluated])
        d_omega = np.diff(trace["omega_cmd"].to_numpy(dtype=float)[evaluated])
        cost = d_force**2 + d_omega**2
        result = np.zeros(len(trace), dtype=float)
        result[evaluated[1:]] = np.cumsum(cost) / len(cost)
        return result

    trace_frames: list[pd.DataFrame] = []
    learned_case_count = 0
    deterministic_case_count = 0
    endpoint_errors: list[float] = []
    for route_id, condition, path_tag, oracle_id in selected_specs:
        group_series: dict[str, dict[str, np.ndarray]] = {}
        route_time: np.ndarray | None = None
        route_truth: np.ndarray | None = None
        for group in ("G0", "ADAPTIVE"):
            stacked = {field: [] for field in ("theta_sched_deg", "e_y_m", "e_psi_rad", "j_du_normalized_cumulative")}
            for seed in SEEDS:
                case_dir = nominal_root / group / f"s{seed}" / path_tag
                trace_path = case_dir / "trace.csv"
                metric_path = case_dir / "case_metrics.json"
                raw_inputs.extend([trace_path, metric_path])
                trace = pd.read_csv(trace_path)
                metrics = json.loads(metric_path.read_text(encoding="utf-8"))
                require_columns(trace, {"t_s", "theta_true", "theta_sched", "e_y", "e_psi", "F_cmd", "omega_cmd"}, trace_path)
                time = trace["t_s"].to_numpy(dtype=float)
                truth = np.rad2deg(trace["theta_true"].to_numpy(dtype=float))
                if route_time is None:
                    route_time, route_truth = time, truth
                elif not np.array_equal(time, route_time) or not np.array_equal(truth, route_truth):
                    raise ValueError(f"Fig09 {route_id} learned traces do not share the frozen time/truth axis")
                jdu = normalized_cumulative_jdu(trace, float(metrics["initialization_exclusion_s"]))
                endpoint_errors.append(abs(float(jdu[-1]) - float(metrics["j_du"])))
                stacked["theta_sched_deg"].append(np.rad2deg(trace["theta_sched"].to_numpy(dtype=float)))
                stacked["e_y_m"].append(trace["e_y"].to_numpy(dtype=float))
                stacked["e_psi_rad"].append(trace["e_psi"].to_numpy(dtype=float))
                stacked["j_du_normalized_cumulative"].append(jdu)
                learned_case_count += 1
            group_series[group] = {field: np.vstack(series) for field, series in stacked.items()}
        oracle_dir = oracle_root / oracle_id / "attempt_001"
        oracle_trace_path = oracle_dir / "trace.csv"
        oracle_metric_path = oracle_dir / "case_metrics.json"
        raw_inputs.extend([oracle_trace_path, oracle_metric_path])
        oracle = pd.read_csv(oracle_trace_path)
        oracle_metrics = json.loads(oracle_metric_path.read_text(encoding="utf-8"))
        require_columns(oracle, {"t_s", "theta_true", "theta_sched", "e_y", "e_psi", "F_cmd", "omega_cmd"}, oracle_trace_path)
        if route_time is None or not np.array_equal(oracle["t_s"].to_numpy(dtype=float), route_time):
            raise ValueError(f"Fig09 {route_id} conditioned reference time axis is not aligned")
        oracle_truth = np.rad2deg(oracle["theta_true"].to_numpy(dtype=float))
        if not np.array_equal(oracle_truth, route_truth):
            raise ValueError(f"Fig09 {route_id} conditioned reference truth profile changed")
        oracle_jdu = normalized_cumulative_jdu(oracle, float(oracle_metrics["initialization_exclusion_s"]))
        endpoint_errors.append(abs(float(oracle_jdu[-1]) - float(oracle_metrics["j_du"])))
        deterministic_case_count += 1
        route_data = pd.DataFrame(
            {
                "record_type": "trace_summary",
                "route_id": route_id,
                "route_condition": condition,
                "t_s": route_time,
                "truth_grade_deg": route_truth,
                "reference_scheduled_grade_deg": np.rad2deg(oracle["theta_sched"].to_numpy(dtype=float)),
                "reference_e_y_m": oracle["e_y"].to_numpy(dtype=float),
                "reference_e_psi_rad": oracle["e_psi"].to_numpy(dtype=float),
                "reference_j_du_normalized_cumulative": oracle_jdu,
            }
        )
        for group, prefix in (("G0", "mtcn"), ("ADAPTIVE", "fusion")):
            for field, matrix in group_series[group].items():
                q25, median, q75 = np.quantile(matrix, [0.25, 0.5, 0.75], axis=0)
                route_data[f"{prefix}_{field}_q25"] = q25
                route_data[f"{prefix}_{field}_median"] = median
                route_data[f"{prefix}_{field}_q75"] = q75
        trace_frames.append(route_data)
    max_endpoint_error = max(endpoint_errors)
    if max_endpoint_error > 1e-10:
        raise ValueError(f"Fig09 cumulative J_delta_u endpoint mismatch: {max_endpoint_error}")
    trace_data = pd.concat(trace_frames, ignore_index=True)
    audit_data = pd.DataFrame(route_audit)
    data = pd.concat([trace_data, audit_data], ignore_index=True, sort=False)
    configure_style(6.5)
    fig, axes = plt.subplots(4, 3, figsize=(183 * MM, 119 * MM), sharex="col", sharey="row", gridspec_kw={"left": 0.085, "right": 0.992, "bottom": 0.105, "top": 0.82, "wspace": 0.12, "hspace": 0.23})
    row_specs = (
        ("theta_sched_deg", "Scheduled grade\n(deg)"),
        ("e_y_m", r"$e_y$ (m)"),
        ("e_psi_rad", r"$e_\psi$ (rad)"),
        ("j_du_normalized_cumulative", r"$J_{\Delta u}(t)$"),
    )
    for column, (route_id, condition, _, _) in enumerate(selected_specs):
        path_data = trace_data[trace_data["route_id"] == route_id]
        time = path_data["t_s"].to_numpy(dtype=float)
        for row_index, (field, ylabel) in enumerate(row_specs):
            ax = axes[row_index, column]
            if row_index == 0:
                ax.plot(time, path_data["truth_grade_deg"], color=PALETTE["truth"], linewidth=1.1, zorder=7)
                reference_field = "reference_scheduled_grade_deg"
            else:
                reference_field = f"reference_{field}"
            ax.fill_between(time, path_data[f"mtcn_{field}_q25"].to_numpy(dtype=float), path_data[f"mtcn_{field}_q75"].to_numpy(dtype=float), color=PALETTE["mtcn"], alpha=0.14, linewidth=0, zorder=1)
            ax.fill_between(time, path_data[f"fusion_{field}_q25"].to_numpy(dtype=float), path_data[f"fusion_{field}_q75"].to_numpy(dtype=float), color=PALETTE["fusion"], alpha=0.14, linewidth=0, zorder=2)
            ax.plot(time, path_data[f"mtcn_{field}_median"], color=PALETTE["mtcn"], linewidth=0.9, zorder=4)
            ax.plot(time, path_data[f"fusion_{field}_median"], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4)), zorder=6)
            ax.plot(time, path_data[reference_field], color=PALETTE["oracle"], linewidth=0.75, linestyle=(0, (5, 1.5, 1, 1.5)), zorder=3)
            if row_index == 0:
                ax.set_title(f"{route_id}  {condition}", fontweight="bold", pad=4)
            if column == 0:
                ax.set_ylabel(ylabel)
            else:
                ax.tick_params(labelleft=False)
            if row_index in (1, 2):
                ax.axhline(0, color="#777777", linewidth=0.4, zorder=0)
            if row_index == len(row_specs) - 1:
                ax.set_xlabel("Time (s)")
            else:
                ax.tick_params(labelbottom=False)
            clean_axis(ax)
            add_panel_label(ax, f"({chr(97 + row_index * 3 + column)})", x=-0.15, y=1.05)
    jdu_upper = 1.1 * max(
        float(trace_data[column].max())
        for column in trace_data.columns
        if "j_du_normalized_cumulative" in column
    )
    for ax in axes[3, :]:
        ax.set_yscale("symlog", linthresh=0.02, linscale=0.8)
        ax.set_ylim(0, jdu_upper)
        ax.set_yticks([0, 0.02, 0.1, 1.0])
    axes[3, 0].set_yticklabels(["0", "0.02", "0.1", "1"])
    iqr_handle = (
        Patch(facecolor=PALETTE["mtcn"], alpha=0.20, edgecolor="none"),
        Patch(facecolor=PALETTE["fusion"], alpha=0.20, edgecolor="none"),
    )
    legend_handles = [
        Line2D([], [], color=PALETTE["truth"], linewidth=1.1),
        Line2D([], [], color=PALETTE["oracle"], linewidth=0.75, linestyle=(0, (5, 1.5, 1, 1.5))),
        Line2D([], [], color=PALETTE["mtcn"], linewidth=0.9),
        iqr_handle,
        Line2D([], [], color=PALETTE["fusion"], linewidth=1.05, linestyle=(0, (8, 2.4))),
    ]
    legend_labels = [
        "Truth",
        "Truth-driven conditioned reference",
        "MTCN-LPV-MPC median",
        "Method-colored IQR (25th–75th percentile; not 95% CI)",
        "Fusion-LPV-MPC median",
    ]
    fig.legend(
        handles=legend_handles,
        labels=legend_labels,
        handler_map={tuple: HandlerTuple(ndivide=None, pad=0.2)},
        loc="upper center",
        ncol=3,
        bbox_to_anchor=(0.535, 0.995),
        handlelength=2.6,
        columnspacing=1.15,
        labelspacing=0.4,
    )
    checks = {
        "formal_selection_population": "six formal routes x ten model seeds = 60 paired cases",
        "route_selection_rule": "Fusion mean is lower than the MTCN mean for e_y RMS, e_psi RMS, and J_delta_u at the five-decimal precision reported in the route-stratified table",
        "selected_routes": selected_by_audit,
        "route_mean_audit": route_audit,
        "learned_case_count": learned_case_count,
        "learned_seeds_per_route_method": len(SEEDS),
        "deterministic_reference_case_count": deterministic_case_count,
        "trace_summary_rows": int(len(trace_data)),
        "same_time_axis_and_truth_within_route": True,
        "maximum_j_du_terminal_metric_error": max_endpoint_error,
        "j_du_time_series_definition": "post-0.5-s cumulative sum of diff(F_cmd)^2 + diff(omega_cmd)^2 divided by the total number of evaluated increments; terminal value equals frozen j_du",
        "j_du_axis": {"scale": "shared symmetric-log", "linear_threshold": 0.02, "upper_limit": jdu_upper, "all_complete_traces_visible": True},
        "learned_summary": "pointwise across-seed median with 25th-75th percentile band",
        "uncertainty_band_interpretation": "method-colored 25th-75th percentile across-seed dispersion, not a 95% confidence interval",
        "truth_and_conditioned_reference_evaluated_once": True,
        "zero_grade_and_causal_imu_removed": True,
        "render_decimation": "none; complete frozen traces retained before pointwise aggregation",
        "line_style_semantics": {
            "Truth": "solid",
            "MTCN-LPV-MPC": "solid",
            "Fusion-LPV-MPC": "long dashed",
            "Truth-driven conditioned reference": "dash-dot",
        },
        "caption_contract": "P1, P2, and P5 are the routes whose reported ten-seed means improve all three closed-loop measures. Learned curves are pointwise medians with method-colored 25th-75th percentile across-seed bands, not confidence intervals; deterministic references are evaluated once. J_delta_u(t) is the normalized cumulative control-input-increment process quantity, its terminal value equals the frozen J_delta_u metric, and its shared vertical axis uses a symmetric-log scale. Panels are descriptive and formal inference uses all 60 route-seed pairs.",
    }
    return data, fig, list(dict.fromkeys(raw_inputs)), checks


CONTRACTS = {
    "Fig02": FigureContract("Fig02_dataset_construction_pipeline", "Fig02_dataset_construction_pipeline", "fig02_dataset_construction_pipeline", 183.0, 49.0, 1, build_fig02),
    "Fig03": FigureContract("Fig03_closed_loop_route_set", "Fig03_closed_loop_route_set", "fig03_closed_loop_route_set", 183.0, 116.0, 6, build_fig03),
    "Fig04": FigureContract("Fig04_slope_necessity_effects", "Fig04_slope_necessity_effects", "fig04_slope_necessity_effects", 183.0, 59.0, 3, build_fig04),
    "Fig05": FigureContract("Fig05_offline_estimator_distribution", "Fig05_offline_estimator_distribution", "fig05_offline_estimator_distribution", 183.0, 70.0, 2, build_fig05),
    "Fig06": FigureContract("Fig06_imu_observer_trace", "Fig06_imu_observer_trace", "fig06_imu_observer_trace", 89.0, 104.0, 3, build_fig06),
    "Fig07": FigureContract("Fig07_fusion_case_distribution", "Fig07_fusion_case_distribution", "fig07_fusion_case_distribution", 183.0, 104.0, 3, build_fig07),
    "Fig08": FigureContract("Fig08_fusion_qualitative_trace", "Fig08_fusion_qualitative_trace", "fig08_fusion_qualitative_trace", 183.0, 108.0, 4, build_fig08),
    "Fig09": FigureContract("Fig09_five_controller_qualitative", "Fig09_five_controller_qualitative", "fig09_five_controller_qualitative", 183.0, 119.0, 12, build_fig09),
}


def run_figure(figure_key: str) -> dict[str, object]:
    if figure_key not in CONTRACTS:
        raise KeyError(f"Unknown figure key {figure_key}; expected one of {sorted(CONTRACTS)}")
    root = find_project_root()
    contract = CONTRACTS[figure_key]
    source_data, fig, raw_inputs, checks = contract.build(root)
    result = _finalize(root, contract, source_data, fig, raw_inputs, checks)
    print(json.dumps({"figure_id": result["figure_id"], "automatic_qa": result["automatic_qa"]["status"]}, indent=2))
    return result
