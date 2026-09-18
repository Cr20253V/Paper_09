from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.ticker import FormatStrFormatter
from PIL import Image, ImageOps
from pypdf import PdfReader


MM = 1.0 / 25.4
WIDTH_MM = 183.0
HEIGHT_MM = 90.0
DPI = 600
OUTPUT_STEM = "fig07_fusion_closed_loop_effects"

RAW_COLOR = "#8FB3CC"
ROUTE_COLOR = "#0072B2"
OVERALL_COLOR = "#003B63"
ZERO_COLOR = "#8A8A8A"
GRID_COLOR = "#E5E5E5"
TEXT_COLOR = "#333333"

ROUTES = (
    ("p01_factory_logistics_showcase", "P1 Factory logistics", 6.0),
    ("p02_sharp_turn_transition", "P2 Sharp-turn transition", 5.0),
    ("p03_long_updown", "P3 Long up/down", 4.0),
    ("p04_soft_updown_straight_turn", "P4 Mild grade and turn", 3.0),
    ("p05_factory_flat_logistics", "P5 Flat logistics", 2.0),
    ("p06_downhill_after_turn", "P6 Downhill after turn", 1.0),
)

METRICS = (
    {
        "id": "ey_rmse",
        "panel": "a",
        "title": "Lateral-error RMS",
        "unit": "m",
        "effect_column": "effect_moderntcn_minus_fusion_ey_rmse",
        "baseline_column": "moderntcn_ey_rmse",
        "fusion_column": "fusion_ey_rmse",
        "xlim": (-0.021, 0.121),
        "xticks": (-0.02, 0.00, 0.04, 0.08, 0.12),
        "formatter": "%.2f",
    },
    {
        "id": "epsi_rmse",
        "panel": "b",
        "title": "Heading-error RMS",
        "unit": "rad",
        "effect_column": "effect_moderntcn_minus_fusion_epsi_rmse",
        "baseline_column": "moderntcn_epsi_rmse",
        "fusion_column": "fusion_epsi_rmse",
        "xlim": (-0.008, 0.062),
        "xticks": (0.00, 0.02, 0.04, 0.06),
        "formatter": "%.3f",
    },
    {
        "id": "j_du",
        "panel": "c",
        "title": "Input-increment index",
        "unit": "",
        "effect_column": "effect_moderntcn_minus_fusion_j_du",
        "baseline_column": "moderntcn_j_du",
        "fusion_column": "fusion_j_du",
        "xlim": (-0.82, 1.52),
        "xticks": (-0.5, 0.0, 0.5, 1.0, 1.5),
        "formatter": "%.1f",
    },
)


def configure_style() -> None:
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans", "Liberation Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42
    plt.rcParams["font.size"] = 7.0
    plt.rcParams["axes.labelsize"] = 6.8
    plt.rcParams["axes.titlesize"] = 7.2
    plt.rcParams["xtick.labelsize"] = 6.2
    plt.rcParams["ytick.labelsize"] = 6.2
    plt.rcParams["legend.fontsize"] = 6.2
    plt.rcParams["axes.linewidth"] = 0.65
    plt.rcParams["xtick.major.width"] = 0.65
    plt.rcParams["ytick.major.width"] = 0.65
    plt.rcParams["xtick.major.size"] = 3.0
    plt.rcParams["ytick.major.size"] = 0.0
    plt.rcParams["axes.spines.top"] = False
    plt.rcParams["axes.spines.right"] = False
    plt.rcParams["figure.facecolor"] = "white"
    plt.rcParams["axes.facecolor"] = "white"
    plt.rcParams["savefig.facecolor"] = "white"


def project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "src").is_dir() and (parent / "results").is_dir():
            return parent
    raise RuntimeError("Could not locate the project root")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_inputs(root: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[Path]]:
    report_dir = root / (
        "results/modern_tcn_metric_rebuild/53_moderntcn_fuzzyakf6d_fusion_rebuild/"
        "08_formal_six_path_exploratory_v7/reports"
    )
    input_paths = [
        report_dir / "v7_formal_paired_comparison.csv",
        report_dir / "v7_paired_path_summary.csv",
        report_dir / "v7_paired_bootstrap_statistics.csv",
    ]
    for path in input_paths:
        if not path.is_file():
            raise FileNotFoundError(path)
    cases = pd.read_csv(input_paths[0])
    paths = pd.read_csv(input_paths[1])
    bootstrap = pd.read_csv(input_paths[2])
    return cases, paths, bootstrap, input_paths


def validate_inputs(cases: pd.DataFrame, paths: pd.DataFrame, bootstrap: pd.DataFrame) -> dict[str, object]:
    required_case_columns = {"path_id", "model_seed"}
    for metric in METRICS:
        required_case_columns.update(
            {metric["baseline_column"], metric["fusion_column"], metric["effect_column"]}
        )
    missing = sorted(required_case_columns.difference(cases.columns))
    if missing:
        raise ValueError(f"Missing case columns: {missing}")

    route_ids = [route[0] for route in ROUTES]
    seed_counts = cases.groupby("path_id")["model_seed"].nunique().to_dict()
    if len(cases) != 60 or set(cases["path_id"]) != set(route_ids):
        raise ValueError("Expected exactly 60 cases over the six declared routes")
    if any(seed_counts.get(route_id) != 10 for route_id in route_ids):
        raise ValueError(f"Expected ten unique seeds per route, found {seed_counts}")

    checks: list[dict[str, object]] = []
    expected = {
        "ey_rmse": (0.00743795860826913, 0.0024534443018867213, 0.015266875549689226, 36, 16, 8),
        "epsi_rmse": (0.002833728050356859, 0.0006449527656079343, 0.006146541285137416, 29, 16, 15),
        "j_du": (0.2569162006037781, -0.013485858639532562, 0.9333310961460866, 24, 16, 20),
    }
    for metric in METRICS:
        metric_id = str(metric["id"])
        effect = cases[str(metric["effect_column"])].to_numpy(dtype=float)
        recomputed = (
            cases[str(metric["baseline_column"])].to_numpy(dtype=float)
            - cases[str(metric["fusion_column"])].to_numpy(dtype=float)
        )
        effect_matches = bool(np.allclose(effect, recomputed, rtol=0.0, atol=1e-14))
        route_rows = paths.loc[paths["metric"] == metric_id].set_index("path_id")
        route_matches = all(
            np.isclose(
                cases.loc[cases["path_id"] == route_id, str(metric["effect_column"])].mean(),
                route_rows.loc[route_id, "effect_moderntcn_minus_fusion_mean"],
                rtol=0.0,
                atol=1e-13,
            )
            for route_id in route_ids
        )
        overall = bootstrap.loc[bootstrap["metric"] == metric_id].iloc[0]
        exp_mean, exp_low, exp_high, exp_wins, exp_ties, exp_losses = expected[metric_id]
        positive = int(np.sum(effect > 0.0))
        ties = int(np.sum(effect == 0.0))
        negative = int(np.sum(effect < 0.0))
        overall_matches = bool(
            np.isclose(effect.mean(), overall["effect_moderntcn_minus_fusion_mean"], atol=1e-13)
            and np.isclose(overall["effect_moderntcn_minus_fusion_mean"], exp_mean, atol=1e-13)
            and np.isclose(overall["ci95_low"], exp_low, atol=1e-13)
            and np.isclose(overall["ci95_high"], exp_high, atol=1e-13)
            and (positive, ties, negative) == (exp_wins, exp_ties, exp_losses)
            and (positive, ties, negative)
            == (int(overall["case_wins"]), int(overall["case_ties"]), int(overall["case_losses"]))
        )
        checks.append(
            {
                "metric": metric_id,
                "effect_equals_moderntcn_minus_fusion": effect_matches,
                "route_means_match": bool(route_matches),
                "overall_and_interval_match": overall_matches,
                "wins_ties_losses": [positive, ties, negative],
            }
        )
    if not all(
        item["effect_equals_moderntcn_minus_fusion"]
        and item["route_means_match"]
        and item["overall_and_interval_match"]
        for item in checks
    ):
        raise ValueError(f"Numeric validation failed: {checks}")
    return {
        "case_rows": len(cases),
        "route_count": cases["path_id"].nunique(),
        "seed_count": cases["model_seed"].nunique(),
        "metric_checks": checks,
        "status": "PASS",
    }


def export_source_data(
    figure_dir: Path, cases: pd.DataFrame, paths: pd.DataFrame, bootstrap: pd.DataFrame
) -> list[Path]:
    source_dir = figure_dir / "source_data"
    source_dir.mkdir(parents=True, exist_ok=True)
    route_label = {route_id: label for route_id, label, _ in ROUTES}
    long_frames: list[pd.DataFrame] = []
    for metric in METRICS:
        frame = cases[
            [
                "path_id",
                "model_seed",
                str(metric["baseline_column"]),
                str(metric["fusion_column"]),
                str(metric["effect_column"]),
            ]
        ].copy()
        frame.columns = ["path_id", "model_seed", "moderntcn", "fusion", "effect_moderntcn_minus_fusion"]
        frame.insert(0, "metric", metric["id"])
        frame.insert(1, "panel", metric["panel"])
        frame.insert(2, "metric_label", metric["title"])
        frame.insert(3, "unit", metric["unit"])
        frame.insert(5, "path_label", frame["path_id"].map(route_label))
        long_frames.append(frame)
    effects_long = pd.concat(long_frames, ignore_index=True)

    route_summary = paths.copy()
    route_summary.insert(2, "path_label", route_summary["path_id"].map(route_label))
    overall = bootstrap.copy()
    title_map = {str(metric["id"]): str(metric["title"]) for metric in METRICS}
    unit_map = {str(metric["id"]): str(metric["unit"]) for metric in METRICS}
    overall.insert(1, "metric_label", overall["metric"].map(title_map))
    overall.insert(2, "unit", overall["metric"].map(unit_map))

    outputs = [
        source_dir / "fig07_effects_long.csv",
        source_dir / "fig07_route_summary.csv",
        source_dir / "fig07_overall_bootstrap.csv",
    ]
    effects_long.to_csv(outputs[0], index=False)
    route_summary.to_csv(outputs[1], index=False)
    overall.to_csv(outputs[2], index=False)
    return outputs


def style_axis(axis: plt.Axes, show_ylabels: bool) -> None:
    axis.set_ylim(-0.62, 6.52)
    axis.set_yticks([route[2] for route in ROUTES] + [0.0])
    if show_ylabels:
        axis.set_yticklabels([route[1] for route in ROUTES] + ["Overall"])
    axis.tick_params(axis="x", colors=TEXT_COLOR, direction="out")
    axis.tick_params(axis="y", colors=TEXT_COLOR, pad=4)
    axis.spines["left"].set_color("#555555")
    axis.spines["bottom"].set_color("#555555")
    axis.xaxis.grid(True, color=GRID_COLOR, linewidth=0.45, zorder=0)
    axis.axhline(0.58, color="#C9C9C9", linewidth=0.6, zorder=0)
    for index, (_, _, y_value) in enumerate(ROUTES):
        if index % 2 == 1:
            axis.axhspan(y_value - 0.43, y_value + 0.43, color="#F7F9FA", zorder=-2)
        axis.axhline(y_value - 0.5, color="#F0F0F0", linewidth=0.4, zorder=-1)
    axis.set_axisbelow(True)
    if show_ylabels:
        labels = axis.get_yticklabels()
        labels[-1].set_fontweight("bold")
        labels[-1].set_color(OVERALL_COLOR)


def plot_metric(
    axis: plt.Axes,
    metric: dict[str, object],
    cases: pd.DataFrame,
    paths: pd.DataFrame,
    bootstrap: pd.DataFrame,
    seed_offsets: dict[int, float],
) -> None:
    effect_column = str(metric["effect_column"])
    route_summary = paths.loc[paths["metric"] == metric["id"]].set_index("path_id")
    for route_id, _, y_value in ROUTES:
        route_cases = cases.loc[cases["path_id"] == route_id].sort_values("model_seed")
        y_points = np.array([y_value + seed_offsets[int(seed)] for seed in route_cases["model_seed"]])
        effect_values = route_cases[effect_column].to_numpy(dtype=float)
        in_range = effect_values <= float(metric["xlim"][1])
        axis.scatter(
            effect_values[in_range],
            y_points[in_range],
            s=12.0,
            marker="o",
            color=RAW_COLOR,
            alpha=0.48,
            edgecolors="none",
            zorder=3,
        )
        axis.scatter(
            [route_summary.loc[route_id, "effect_moderntcn_minus_fusion_mean"]],
            [y_value],
            s=29.0,
            marker="s",
            color=ROUTE_COLOR,
            edgecolors="white",
            linewidths=0.45,
            zorder=5,
        )
        if not np.all(in_range):
            display_x = float(metric["xlim"][1]) - 0.035
            for value, point_y in zip(effect_values[~in_range], y_points[~in_range]):
                axis.scatter(
                    [display_x],
                    [point_y],
                    s=24.0,
                    marker=">",
                    facecolor=RAW_COLOR,
                    edgecolor=ROUTE_COLOR,
                    linewidth=0.55,
                    alpha=0.88,
                    zorder=6,
                )
                axis.text(
                    display_x - 0.055,
                    point_y,
                    f"{value:.2f}\noff-scale",
                    ha="right",
                    va="center",
                    fontsize=6.0,
                    color="#555555",
                    linespacing=0.9,
                    zorder=7,
                )

    overall = bootstrap.loc[bootstrap["metric"] == metric["id"]].iloc[0]
    mean = float(overall["effect_moderntcn_minus_fusion_mean"])
    low = float(overall["ci95_low"])
    high = float(overall["ci95_high"])
    axis.errorbar(
        mean,
        0.0,
        xerr=np.array([[mean - low], [high - mean]]),
        fmt="D",
        markersize=5.4,
        markerfacecolor=OVERALL_COLOR,
        markeredgecolor="white",
        markeredgewidth=0.5,
        color=OVERALL_COLOR,
        ecolor=OVERALL_COLOR,
        elinewidth=1.25,
        capsize=2.5,
        capthick=1.0,
        zorder=7,
    )


def build_figure(
    cases: pd.DataFrame, paths: pd.DataFrame, bootstrap: pd.DataFrame
) -> tuple[plt.Figure, list[plt.Axes]]:
    configure_style()
    figure = plt.figure(figsize=(WIDTH_MM * MM, HEIGHT_MM * MM))
    grid = figure.add_gridspec(
        1,
        3,
        width_ratios=[1.0, 1.0, 1.0],
        left=0.165,
        right=0.975,
        bottom=0.175,
        top=0.80,
        wspace=0.30,
    )
    axis_a = figure.add_subplot(grid[0, 0])
    axis_b = figure.add_subplot(grid[0, 1], sharey=axis_a)
    axis_c = figure.add_subplot(grid[0, 2], sharey=axis_a)
    axes = [axis_a, axis_b, axis_c]

    style_axis(axis_a, True)
    for axis in axes[1:]:
        style_axis(axis, False)
        axis.tick_params(axis="y", left=False, labelleft=False)

    seeds = sorted(int(seed) for seed in cases["model_seed"].unique())
    offsets = np.linspace(0.22, -0.22, len(seeds))
    seed_offsets = dict(zip(seeds, offsets))

    for axis, metric in zip(axes, METRICS):
        plot_metric(axis, metric, cases, paths, bootstrap, seed_offsets)
        axis.axvline(0.0, color=ZERO_COLOR, linewidth=0.72, zorder=1)
        axis.set_xlim(*metric["xlim"])
        axis.set_xticks(metric["xticks"])
        axis.xaxis.set_major_formatter(FormatStrFormatter(str(metric["formatter"])))
        axis.set_title(str(metric["title"]), loc="left", fontweight="bold", pad=5)
        axis.text(
            -0.15,
            1.04,
            f"({metric['panel']})",
            transform=axis.transAxes,
            ha="left",
            va="bottom",
            fontsize=8.0,
            fontweight="bold",
            clip_on=False,
        )

    axis_a.set_xlabel("MTCN - Fusion effect (m)")
    axis_b.set_xlabel("MTCN - Fusion effect (rad)")
    axis_c.set_xlabel("MTCN - Fusion effect")

    legend_handles = [
        Line2D(
            [],
            [],
            marker="o",
            linestyle="none",
            markersize=4.0,
            markerfacecolor=RAW_COLOR,
            markeredgecolor="none",
            alpha=0.55,
            label="Route-seed pair (n=60)",
        ),
        Line2D(
            [],
            [],
            marker="s",
            linestyle="none",
            markersize=4.8,
            markerfacecolor=ROUTE_COLOR,
            markeredgecolor="white",
            markeredgewidth=0.45,
            label="Route mean (10 seeds)",
        ),
        Line2D(
            [],
            [],
            marker="D",
            linestyle="-",
            linewidth=1.2,
            markersize=5.0,
            color=OVERALL_COLOR,
            markerfacecolor=OVERALL_COLOR,
            markeredgecolor="white",
            markeredgewidth=0.45,
            label="Overall mean and 95% CI",
        ),
    ]
    figure.legend(
        handles=legend_handles,
        loc="upper center",
        bbox_to_anchor=(0.54, 0.965),
        ncol=3,
        frameon=False,
        columnspacing=1.45,
        handletextpad=0.55,
    )
    return figure, axes


def inspect_artists(figure: plt.Figure) -> dict[str, object]:
    figure.canvas.draw()
    renderer = figure.canvas.get_renderer()
    figure_box = figure.bbox
    visible_text = [item for item in figure.findobj(plt.Text) if item.get_visible() and item.get_text()]
    minimum_font = min(float(item.get_fontsize()) for item in visible_text)
    overflow: list[str] = []
    for item in visible_text:
        box = item.get_window_extent(renderer=renderer)
        tolerance = 2.0
        if (
            box.x0 < figure_box.x0 - tolerance
            or box.y0 < figure_box.y0 - tolerance
            or box.x1 > figure_box.x1 + tolerance
            or box.y1 > figure_box.y1 + tolerance
        ):
            overflow.append(item.get_text())
    status = "PASS" if minimum_font >= 6.0 and not overflow else "FAIL"
    return {
        "primary_panel_count": 3,
        "axes_count": 3,
        "minimum_visible_font_pt": round(minimum_font, 2),
        "material_text_overflow_count": len(overflow),
        "material_text_overflow": overflow,
        "status": status,
    }


def export_figure(figure: plt.Figure, figure_dir: Path) -> list[Path]:
    output_dir = figure_dir / "output"
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [output_dir / f"{OUTPUT_STEM}.{suffix}" for suffix in ("pdf", "svg", "png")]
    figure.savefig(outputs[0])
    figure.savefig(outputs[1])
    figure.savefig(outputs[2], dpi=DPI)
    return outputs


def inspect_exports(outputs: list[Path], qa_dir: Path) -> dict[str, object]:
    pdf_path = next(path for path in outputs if path.suffix == ".pdf")
    svg_path = next(path for path in outputs if path.suffix == ".svg")
    png_path = next(path for path in outputs if path.suffix == ".png")
    expected_pixels = (round(WIDTH_MM * DPI / 25.4), round(HEIGHT_MM * DPI / 25.4))

    with Image.open(png_path) as image:
        actual_pixels = image.size
        grayscale_path = qa_dir / f"{OUTPUT_STEM}_grayscale.png"
        grayscale = ImageOps.grayscale(image)
        grayscale.save(grayscale_path, dpi=(DPI, DPI))
        gray_array = np.asarray(grayscale, dtype=np.uint8)
        nonwhite_fraction = float(np.mean(gray_array < 250))

    svg_root = ElementTree.parse(svg_path).getroot()
    editable_text = sum(1 for element in svg_root.iter() if element.tag.endswith("text"))

    reader = PdfReader(str(pdf_path))
    page = reader.pages[0]
    width_pt = float(page.mediabox.width)
    height_pt = float(page.mediabox.height)
    pdf_size_mm = [width_pt * 25.4 / 72.0, height_pt * 25.4 / 72.0]
    pdf_text_chars = len((page.extract_text() or "").strip())

    png_matches = all(abs(actual - expected) <= 1 for actual, expected in zip(actual_pixels, expected_pixels))
    pdf_size_matches = bool(
        abs(pdf_size_mm[0] - WIDTH_MM) < 0.05 and abs(pdf_size_mm[1] - HEIGHT_MM) < 0.05
    )
    status = "PASS" if png_matches and pdf_size_matches and editable_text >= 20 and pdf_text_chars >= 40 else "FAIL"
    return {
        "requested_size_mm": [WIDTH_MM, HEIGHT_MM],
        "png_dpi": DPI,
        "png_pixels": list(actual_pixels),
        "expected_png_pixels": list(expected_pixels),
        "png_size_matches": png_matches,
        "png_nonwhite_fraction": round(nonwhite_fraction, 5),
        "svg_editable_text_elements": editable_text,
        "pdf_page_count": len(reader.pages),
        "pdf_size_mm": [round(value, 3) for value in pdf_size_mm],
        "pdf_size_matches": pdf_size_matches,
        "pdf_extractable_text_characters": pdf_text_chars,
        "grayscale_preview": grayscale_path.name,
        "status": status,
    }


def write_reports(
    root: Path,
    figure_dir: Path,
    input_paths: list[Path],
    source_paths: list[Path],
    outputs: list[Path],
    numeric_checks: dict[str, object],
    artist_checks: dict[str, object],
    export_checks: dict[str, object],
) -> None:
    generated = datetime.now(timezone.utc).isoformat()
    overall_status = "PASS" if all(
        checks["status"] == "PASS" for checks in (numeric_checks, artist_checks, export_checks)
    ) else "FAIL"
    manifest = {
        "figure_id": "Fig07_fusion_closed_loop_effects",
        "generated_utc": generated,
        "backend": "Python/matplotlib",
        "scope": "Figure generation only; no manuscript or table files were modified.",
        "figure_contract": {
            "core_conclusion": (
                "Across 60 matched route-seed pairs, fusion reduces lateral- and heading-error RMS "
                "with paired intervals above zero, while the input-increment point estimate is positive "
                "but its interval crosses zero."
            ),
            "archetype": "three-panel paired-effect quantitative grid",
            "final_size_mm": [WIDTH_MM, HEIGHT_MM],
            "panel_map": {
                "a": "lateral-error RMS paired effects",
                "b": "heading-error RMS paired effects",
                "c": "input-increment paired effects with one explicitly labelled off-scale point",
            },
            "evidence_hierarchy": {
                "hero": "overall paired means and 95% bootstrap intervals",
                "support": "six route means and all 60 route-seed effects",
                "robustness": "exact ties retained at x=0 and route heterogeneity shown directly",
            },
            "reviewer_risk": (
                "A single large positive J_Delta_u effect can compress the central distribution; "
                "an explicitly valued off-scale marker retains it without hiding the interval crossing zero."
            ),
        },
        "inputs": [
            {
                "file": str(path.relative_to(root)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in input_paths
        ],
        "source_data": [
            {
                "file": str(path.relative_to(root)).replace("\\", "/"),
                "rows": len(pd.read_csv(path)),
                "sha256": sha256(path),
            }
            for path in source_paths
        ],
        "outputs": [
            {
                "format": path.suffix.lstrip("."),
                "file": str(path.relative_to(root)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in outputs
        ],
        "automatic_qa": {
            "status": overall_status,
            "numeric_checks": numeric_checks,
            "artist_checks": artist_checks,
            "export_checks": export_checks,
        },
    }
    qa_dir = figure_dir / "qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    qa_json = qa_dir / f"{OUTPUT_STEM}_qa.json"
    qa_json.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (figure_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    metric_lines = []
    for item in numeric_checks["metric_checks"]:
        wins, ties, losses = item["wins_ties_losses"]
        metric_lines.append(f"- `{item['metric']}` wins/ties/losses: {wins}/{ties}/{losses}; all numeric mappings PASS.")
    report_lines = [
        "# Figure 7 QA Report",
        "",
        f"- Overall status: **{overall_status}**",
        "- Backend: Python/matplotlib only.",
        f"- Final size: {WIDTH_MM:.0f} mm x {HEIGHT_MM:.0f} mm.",
        f"- Raster export: {DPI} dpi PNG.",
        "- Scope: figure generation only; manuscript and tables were not modified.",
        "",
        "## Evidence and numeric checks",
        "",
        "- Included 6 routes x 10 seeds = 60 matched pairs for each metric.",
        "- Effect direction is ModernTCN minus Fusion; positive values favor fusion.",
        "- Exact ties remain at x=0; only vertical within-route separation is used.",
        *metric_lines,
        "- The `j_du` overall 95% interval crosses zero and is drawn without warning color.",
        "- Panel (c) uses a labelled off-scale marker for the single distant positive effect while preserving central detail.",
        "",
        "## Layout and export checks",
        "",
        f"- Minimum visible font: {artist_checks['minimum_visible_font_pt']:.1f} pt.",
        f"- Material text overflow count: {artist_checks['material_text_overflow_count']}.",
        f"- PNG dimensions: {export_checks['png_pixels'][0]} x {export_checks['png_pixels'][1]} px.",
        f"- PDF size: {export_checks['pdf_size_mm'][0]:.3f} x {export_checks['pdf_size_mm'][1]:.3f} mm.",
        f"- SVG editable text elements: {export_checks['svg_editable_text_elements']}.",
        f"- PDF extractable text characters: {export_checks['pdf_extractable_text_characters']}.",
        f"- Grayscale preview: `qa/{export_checks['grayscale_preview']}`.",
        "",
        "## Visual language",
        "",
        "- Arial-compatible sans-serif typography, 8-pt bold panel labels, and 6.2-7.2-pt supporting text match the surrounding manuscript figures.",
        "- The established manuscript blue (`#0072B2`) marks route means; lighter gray-blue marks cases and deep blue marks overall intervals.",
        "- Neutral gray zero lines, subtle row bands, and restrained grid lines preserve grayscale legibility.",
        "",
    ]
    (figure_dir / "QA_REPORT.md").write_text("\n".join(report_lines), encoding="utf-8")
    if overall_status != "PASS":
        raise RuntimeError("Automatic QA failed; inspect the QA JSON before using the figure")


def main() -> None:
    root = project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    cases, paths, bootstrap, input_paths = load_inputs(root)
    numeric_checks = validate_inputs(cases, paths, bootstrap)
    source_paths = export_source_data(figure_dir, cases, paths, bootstrap)
    figure, _ = build_figure(cases, paths, bootstrap)
    artist_checks = inspect_artists(figure)
    outputs = export_figure(figure, figure_dir)
    plt.close(figure)
    export_checks = inspect_exports(outputs, figure_dir / "qa")
    write_reports(
        root,
        figure_dir,
        input_paths,
        source_paths,
        outputs,
        numeric_checks,
        artist_checks,
        export_checks,
    )
    print(json.dumps({"status": "PASS", "outputs": [str(path) for path in outputs]}, indent=2))


if __name__ == "__main__":
    main()
