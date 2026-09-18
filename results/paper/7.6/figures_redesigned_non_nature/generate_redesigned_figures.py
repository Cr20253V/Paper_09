"""Generate a coherent non-Nature redesign of the experimental figure set.

The script uses the frozen manuscript data and exports editable PDF/SVG plus
high-resolution PNG/TIFF. It intentionally keeps the redesign separate from the
current ``figures_final`` workspace so the alternatives can be compared safely.
"""

from __future__ import annotations

import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import h5py
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import TwoSlopeNorm
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from PIL import Image
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT / "results/paper/7.6/figures_redesigned_non_nature"
OUTPUT = WORKSPACE / "output"
SOURCE = WORKSPACE / "source_data"
MM = 1 / 25.4

STYLE_DIR = ROOT / "results/paper/7.6/figures_final/shared"
sys.path.insert(0, str(STYLE_DIR))
from style import PALETTE, add_panel_label, apply_publication_style  # noqa: E402


COLORS = {
    **PALETTE,
    "delta": "#1F5A85",
    "base": "#6A91B8",
    "good": "#2166AC",
    "neutral": "#F4F4F2",
    "bad": "#B44A4A",
    "grid_dark": "#D7D7D7",
}

SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]

ROUTES6 = [
    ("P1", "Factory logistics", "data/paths/path_factory_logistics_showcase_theta10_v10.mat", True),
    ("P2", "Sharp-turn transition", "data/paths/path_closed_loop_sharp_turn_transition_theta10_v1.mat", False),
    ("P3", "Long up/down slope", "data/paths/path_closed_loop_long_updown_theta10_v1.mat", True),
    ("P4", "Soft slope-turn", "data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat", True),
    ("P5", "Flat logistics", "data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat", False),
    ("P6", "Downhill recovery", "data/paths/factory_targeted_eval/path_factory_target_downhill_straight_after_turn_v1.mat", False),
]

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

METHODS = ["ZS_LPV_MPC", "IMU_LPV_MPC", "MTCN_LPV_MPC", "Fusion_LPV_MPC", "Oracle_LPV_MPC"]
METHOD_LABELS = {
    "ZS_LPV_MPC": "Zero grade",
    "IMU_LPV_MPC": "Causal IMU",
    "MTCN_LPV_MPC": "ModernTCN",
    "Fusion_LPV_MPC": "Adaptive fusion",
    "Oracle_LPV_MPC": "Oracle",
}
METHOD_STYLE = {
    "ZS_LPV_MPC": (COLORS["zero_slope"], (0, (1.2, 1.6)), 0.85),
    "IMU_LPV_MPC": (COLORS["imu"], (0, (4, 2)), 0.9),
    "MTCN_LPV_MPC": (COLORS["mtcn"], "-", 1.0),
    "Fusion_LPV_MPC": (COLORS["fusion"], "-", 1.35),
    "Oracle_LPV_MPC": (COLORS["oracle"], (0, (5, 1.5, 1, 1.5)), 0.95),
}


def setup() -> None:
    apply_publication_style()
    plt.rcParams.update(
        {
            "font.size": 7.2,
            "axes.labelsize": 7.4,
            "axes.titlesize": 7.6,
            "xtick.labelsize": 6.4,
            "ytick.labelsize": 6.4,
            "legend.fontsize": 6.6,
            "axes.grid": False,
        }
    )
    OUTPUT.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(parents=True, exist_ok=True)


def clean(ax, *, grid: str | None = "y") -> None:
    ax.spines["left"].set_color("#555555")
    ax.spines["bottom"].set_color("#555555")
    ax.tick_params(direction="out", pad=1.5)
    if grid:
        ax.grid(axis=grid, color=COLORS["grid"], linewidth=0.45, zorder=0)
        ax.set_axisbelow(True)


def save(fig, stem: str) -> list[str]:
    fig.canvas.draw()
    saved = []
    for ext, kwargs in {
        "pdf": {},
        "svg": {},
        "png": {"dpi": 300},
        "tiff": {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}},
    }.items():
        path = OUTPUT / f"{stem}.{ext}"
        fig.savefig(path, facecolor="white", **kwargs)
        saved.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    plt.close(fig)
    return saved


def decimate(frame: pd.DataFrame, max_points: int = 2200) -> pd.DataFrame:
    if len(frame) <= max_points:
        return frame
    idx = np.unique(np.linspace(0, len(frame) - 1, max_points).astype(int))
    return frame.iloc[idx]


def load_route(path: Path) -> dict[str, np.ndarray]:
    fields = ["t", "X_ref", "Y_ref", "theta_ref", "v_ref"]
    try:
        payload = loadmat(path, squeeze_me=True, struct_as_record=False)
        ref = payload["ref"]
        return {name: np.asarray(getattr(ref, name), dtype=float).squeeze() for name in fields}
    except NotImplementedError:
        with h5py.File(path, "r") as handle:
            return {name: np.asarray(handle["ref"][name], dtype=float).squeeze() for name in fields}


def route_source() -> pd.DataFrame:
    frames = []
    for order, (pid, role, rel, qualitative) in enumerate(ROUTES6, 1):
        raw = load_route(ROOT / rel)
        n = len(raw["t"])
        if any(len(raw[name]) != n for name in raw):
            raise ValueError(f"{pid}: route fields are not aligned")
        if not np.all(np.diff(raw["t"]) > 0):
            raise ValueError(f"{pid}: time is not strictly increasing")
        frames.append(
            pd.DataFrame(
                {
                    "path_id": pid,
                    "path_order": order,
                    "role": role,
                    "qualitative": qualitative,
                    "t_s": raw["t"],
                    "X_ref_m": raw["X_ref"],
                    "Y_ref_m": raw["Y_ref"],
                    "grade_deg": np.rad2deg(raw["theta_ref"]),
                    "speed_mps": raw["v_ref"],
                }
            )
        )
    data = pd.concat(frames, ignore_index=True)
    data.to_csv(SOURCE / "figR1_six_route_atlas.csv", index=False)
    return data


def plot_route_atlas() -> list[str]:
    data = route_source()
    fig = plt.figure(figsize=(183 * MM, 120 * MM))
    outer = fig.add_gridspec(2, 3, left=0.055, right=0.99, bottom=0.09, top=0.96, wspace=0.25, hspace=0.34)
    grade_lim = max(6.5, math.ceil(data.grade_deg.abs().max()))
    speed_lim = (math.floor(data.speed_mps.min() * 20) / 20 - 0.01, math.ceil(data.speed_mps.max() * 20) / 20 + 0.01)
    for i, (pid, role, _, qualitative) in enumerate(ROUTES6):
        cell = outer[i // 3, i % 3].subgridspec(2, 2, width_ratios=[1.25, 1], hspace=0.18, wspace=0.32)
        ax_xy = fig.add_subplot(cell[:, 0])
        ax_g = fig.add_subplot(cell[0, 1])
        ax_v = fig.add_subplot(cell[1, 1], sharex=ax_g)
        d = decimate(data[data.path_id == pid].reset_index(drop=True))
        ax_xy.plot(d.X_ref_m, d.Y_ref_m, color=COLORS["truth"], lw=1.15)
        ax_xy.scatter(d.X_ref_m.iloc[0], d.Y_ref_m.iloc[0], s=18, color=COLORS["start"], zorder=3)
        ax_xy.scatter(d.X_ref_m.iloc[-1], d.Y_ref_m.iloc[-1], s=18, marker="s", color=COLORS["end"], zorder=3)
        k = len(d) // 2
        k2 = min(k + max(1, len(d) // 80), len(d) - 1)
        ax_xy.annotate("", (d.X_ref_m.iloc[k2], d.Y_ref_m.iloc[k2]), (d.X_ref_m.iloc[k], d.Y_ref_m.iloc[k]), arrowprops={"arrowstyle": "-|>", "color": COLORS["direction"], "lw": 0.9})
        ax_xy.set_aspect("equal", adjustable="datalim")
        ax_xy.margins(0.08)
        ax_xy.set_xlabel("X (m)", labelpad=1)
        ax_xy.set_ylabel("Y (m)", labelpad=1)
        title = f"{pid}{'*' if qualitative else ''}  {role}"
        ax_xy.set_title(title, loc="left", fontweight="bold", pad=4)
        add_panel_label(ax_xy, f"({chr(97 + i)})", x=-0.18, y=1.04)
        clean(ax_xy, grid="both")

        ax_g.plot(d.t_s, d.grade_deg, color=COLORS["fusion"], lw=1.05)
        ax_g.axhline(0, color="#AAAAAA", lw=0.55, ls="--")
        ax_g.set_ylim(-grade_lim, grade_lim)
        ax_g.set_ylabel("Grade\n(deg)", labelpad=2)
        ax_g.tick_params(labelbottom=False)
        clean(ax_g)

        ax_v.plot(d.t_s, d.speed_mps, color=COLORS["imu"], lw=1.05)
        ax_v.set_ylim(*speed_lim)
        ax_v.set_ylabel("Speed\n(m/s)", labelpad=2)
        ax_v.set_xlabel("Time (s)", labelpad=1)
        clean(ax_v)
    fig.text(0.5, 0.012, "* Pre-specified qualitative route", ha="center", fontsize=6.5, color="#555555")
    return save(fig, "figR1_six_route_atlas")


def plot_scheduling_necessity() -> list[str]:
    base = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/03_A3_slope_scheduling_necessity/04_summary"
    effects = pd.read_csv(base / "paired_effects.csv")
    cis = pd.read_csv(base / "bootstrap_ci_results.csv")
    effects = effects[effects.contrast_id.isin(["A3_ORACLE_VS_ZS", "A3_IMU_VS_ZS"])].copy()
    cis = cis[cis.contrast_id.isin(["A3_ORACLE_VS_ZS", "A3_IMU_VS_ZS"])].copy()
    effects["path_short"] = effects.path_id.str.extract(r"p0?([1-6])").iloc[:, 0].map(lambda x: f"P{x}")
    effects.to_csv(SOURCE / "figR2_scheduling_necessity.csv", index=False)
    cis.to_csv(SOURCE / "figR2_scheduling_necessity_ci.csv", index=False)
    metrics = [("ey_rmse", r"Lateral-error RMS reduction (m)"), ("epsi_rmse", r"Heading-error RMS reduction (rad)"), ("j_du", r"Input-increment cost reduction, $J_{\Delta u}$")]
    contrasts = [("A3_ORACLE_VS_ZS", "Oracle vs zero grade", COLORS["oracle"], "D"), ("A3_IMU_VS_ZS", "Causal IMU vs zero grade", COLORS["imu"], "^")]
    fig, axes = plt.subplots(1, 3, figsize=(183 * MM, 58 * MM), gridspec_kw={"left": 0.07, "right": 0.99, "bottom": 0.2, "top": 0.79, "wspace": 0.42})
    for j, (metric, title) in enumerate(metrics):
        ax = axes[j]
        vals = effects[effects.metric == metric]
        ax.axvline(0, color="#333333", lw=0.7, zorder=0)
        for row, (cid, label, color, marker) in enumerate(contrasts):
            d = vals[vals.contrast_id == cid].sort_values("path_short")
            y = row + np.linspace(-0.14, 0.14, len(d))
            ax.scatter(d.effect_comparator_minus_target, y, s=15, marker=marker, facecolor=color, edgecolor="white", lw=0.35, alpha=0.72, zorder=2)
            for x, yy, pid in zip(d.effect_comparator_minus_target, y, d.path_short):
                ax.annotate(pid, (x, yy), xytext=(3, 0), textcoords="offset points", va="center", fontsize=5.4, color="#666666")
            ci = cis[(cis.metric == metric) & (cis.contrast_id == cid)].iloc[0]
            ax.errorbar(ci.estimate, row, xerr=[[ci.estimate - ci.ci95_low], [ci.ci95_high - ci.estimate]], fmt=marker, ms=6.5, color=color, mec="#222222", mew=0.7, capsize=2.5, lw=1.25, zorder=4)
        ax.set_yticks([0, 1], ["Oracle", "Causal IMU"])
        ax.invert_yaxis()
        ax.set_xlabel(title, labelpad=3)
        add_panel_label(ax, f"({chr(97 + j)})", x=-0.16, y=1.08)
        clean(ax, grid="x")
    fig.legend([Line2D([], [], marker="o", ls="none", color="#888888", ms=3.6), Line2D([], [], marker="D", ls="none", color="#333333", ms=5.3)], ["Route effect", "Mean and 95% bootstrap CI"], loc="upper center", ncol=2, bbox_to_anchor=(0.53, 0.97))
    fig.text(0.5, 0.03, "Effects are relative to zero-grade scheduling; positive values favor the named source. Oracle is not deployable.", ha="center", fontsize=6.4)
    return save(fig, "figR2_scheduling_necessity_forest")


def plot_offline_estimators() -> list[str]:
    path = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/03_offline/offline_case_metrics.csv"
    data = pd.read_csv(path)
    data.to_csv(SOURCE / "figR3_offline_estimators.csv", index=False)
    order = ["modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"]
    labels = ["ModernTCN\n+ delta bank", "ModernTCN\n22-D", "GRU\n22-D", "TCN\n22-D"]
    colors = [COLORS["delta"], COLORS["base"], COLORS["gru"], COLORS["tcn"]]
    metrics = [("theta_abs_le_10_mae_deg", "Grade MAE (deg)"), ("theta_abs_le_10_p95_abs_err_deg", "P95 absolute error (deg)")]
    fig, axes = plt.subplots(1, 2, figsize=(183 * MM, 63 * MM), gridspec_kw={"left": 0.07, "right": 0.99, "bottom": 0.22, "top": 0.91, "wspace": 0.28})
    offsets = np.linspace(-0.12, 0.12, len(SEEDS))
    for j, (metric, ylabel) in enumerate(metrics):
        ax = axes[j]
        paired = data[data.method_id.isin(order[:2])].pivot(index="seed", columns="method_id", values=metric).reindex(SEEDS)
        for seed in SEEDS:
            ax.plot([0, 1], [paired.loc[seed, order[0]], paired.loc[seed, order[1]]], color="#C8C8C8", lw=0.65, zorder=1)
        for i, method in enumerate(order):
            d = data[data.method_id == method].set_index("seed").reindex(SEEDS)
            vals = d[metric].to_numpy()
            ax.scatter(i + offsets, vals, s=18, color=colors[i], alpha=0.82, edgecolor="white", lw=0.35, zorder=2)
            mean = vals.mean()
            boots = np.random.default_rng(20260721 + i + 10 * j).choice(vals, (20000, len(vals)), replace=True).mean(axis=1)
            lo, hi = np.percentile(boots, [2.5, 97.5])
            ax.errorbar(i, mean, yerr=[[mean - lo], [hi - mean]], fmt="_", ms=13, mew=2, color="#222222", capsize=3, lw=1.1, zorder=4)
        ax.set_xticks(range(4), labels)
        ax.set_ylabel(ylabel)
        ax.set_ylim(bottom=0)
        add_panel_label(ax, f"({chr(97 + j)})", x=-0.12, y=1.03)
        clean(ax)
    fig.text(0.5, 0.035, "Points are model seeds; gray lines pair the two ModernTCN representations; black bars are mean and 95% bootstrap CI.", ha="center", fontsize=6.3)
    return save(fig, "figR3_offline_estimator_distribution")


def plot_imu_complementarity() -> list[str]:
    path = ROOT / "results/paper/7.6/figures_final/Fig06_imu_observer_trace/source_data/fig06_imu_observer_trace_source_data.csv"
    data = pd.read_csv(path)
    data.to_csv(SOURCE / "figR4_imu_complementarity.csv", index=False)
    t = data.t_s.to_numpy()
    valid = data.imu_valid.fillna(0).to_numpy(bool)
    fig = plt.figure(figsize=(183 * MM, 88 * MM))
    gs = fig.add_gridspec(3, 1, height_ratios=[3.0, 0.55, 1.45], left=0.08, right=0.99, bottom=0.12, top=0.86, hspace=0.15)
    ax0 = fig.add_subplot(gs[0])
    ax1 = fig.add_subplot(gs[1], sharex=ax0)
    ax2 = fig.add_subplot(gs[2], sharex=ax0)
    unc = data.imu_uncertainty_halfwidth_deg.to_numpy(float)
    imu = data.theta_imu_deg.to_numpy(float)
    ax0.fill_between(t, imu - unc, imu + unc, color=COLORS["imu"], alpha=0.13, lw=0)
    ax0.plot(t, imu, color=COLORS["imu"], ls=(0, (4, 2)), lw=0.9)
    ax0.plot(t, data.theta_mtcn_deg, color=COLORS["mtcn"], lw=1.05)
    ax0.plot(t, data.theta_true_deg, color=COLORS["truth"], lw=1.35)
    ax0.set_ylabel("Grade angle (deg)")
    add_panel_label(ax0, "(a)", x=-0.075, y=1.02)
    clean(ax0)

    gain = data.K_imu_eff.fillna(0).to_numpy(float)
    ax1.fill_between(t, 0, gain, step="post", color=COLORS["imu"], alpha=0.55)
    ax1.fill_between(t, 0, 1, where=~valid, step="post", facecolor="#DDDDDD", hatch="////", edgecolor="#BBBBBB", linewidth=0)
    ax1.set_ylim(0, 1.02)
    ax1.set_yticks([0, 1])
    ax1.set_ylabel(r"$K_{IMU}$", labelpad=4)
    add_panel_label(ax1, "(b)", x=-0.075, y=1.02)
    clean(ax1, grid=None)

    delta = data.delta_abs_error_deg.to_numpy(float)
    finite = np.isfinite(delta)
    ax2.fill_between(t, 0, delta, where=finite & (delta <= 0), color=COLORS["good"], alpha=0.32)
    ax2.fill_between(t, 0, delta, where=finite & (delta > 0), color=COLORS["bad"], alpha=0.3)
    ax2.plot(t, delta, color="#555555", lw=0.55)
    ax2.axhline(0, color="#222222", lw=0.65)
    lim = math.ceil(np.nanmax(np.abs(delta)))
    ax2.set_ylim(-lim, lim)
    ax2.set_ylabel(r"$|e_{IMU}|-|e_{MTCN}|$" + "\n(deg)")
    ax2.set_xlabel("Time (s)")
    add_panel_label(ax2, "(c)", x=-0.075, y=1.02)
    clean(ax2)
    ax0.tick_params(labelbottom=False)
    ax1.tick_params(labelbottom=False)
    fig.legend([Line2D([], [], color=COLORS["truth"], lw=1.35), Line2D([], [], color=COLORS["mtcn"], lw=1.05), Line2D([], [], color=COLORS["imu"], lw=0.9, ls="--"), Patch(facecolor=COLORS["imu"], alpha=0.13), Patch(facecolor=COLORS["good"], alpha=0.32), Patch(facecolor=COLORS["bad"], alpha=0.3)], ["Truth", "ModernTCN", "Causal IMU", "Observer uncertainty", "IMU locally better", "ModernTCN locally better"], loc="upper center", ncol=6, bbox_to_anchor=(0.53, 0.98))
    return save(fig, "figR4_imu_source_complementarity")


def plot_fusion_cases() -> list[str]:
    path = ROOT / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3/04_summaries/innovation_development_pair_details.csv"
    data = pd.read_csv(path)
    data["path_id"] = data.path.map(ROUTE9)
    if data.path_id.isna().any() or len(data) != 90:
        raise ValueError("Fusion case table must map exactly to 9 routes x 10 seeds")
    data.to_csv(SOURCE / "figR5_fusion_case_matrix.csv", index=False)
    matrix = data.pivot(index="path_id", columns="seed", values="J").reindex(index=[f"P{i}" for i in range(1, 10)], columns=SEEDS)
    means = matrix.mean(axis=1)
    fig = plt.figure(figsize=(183 * MM, 76 * MM))
    gs = fig.add_gridspec(1, 2, width_ratios=[4.8, 1.25], left=0.07, right=0.98, bottom=0.18, top=0.88, wspace=0.17)
    ax = fig.add_subplot(gs[0])
    axm = fig.add_subplot(gs[1], sharey=ax)
    norm = TwoSlopeNorm(vmin=min(0.64, matrix.min().min()), vcenter=1.0, vmax=max(1.36, matrix.max().max()))
    image = ax.imshow(matrix.to_numpy(), aspect="auto", cmap="RdBu_r", norm=norm, interpolation="nearest")
    for row in range(9):
        for col in range(10):
            value = matrix.iloc[row, col]
            if value > 1.02:
                ax.scatter(col, row, marker="^", s=16, facecolor="none", edgecolor="#5A1F1F", lw=0.7)
    ax.set_xticks(range(10), [str(x) for x in SEEDS], rotation=0)
    ax.set_yticks(range(9), matrix.index)
    ax.set_xlabel("Model seed")
    ax.set_ylabel("Closed-loop route")
    add_panel_label(ax, "(a)", x=-0.08, y=1.04)
    for spine in ax.spines.values():
        spine.set_visible(False)
    cbar = fig.colorbar(image, ax=ax, orientation="horizontal", fraction=0.065, pad=0.16, aspect=35)
    cbar.set_label(r"Paired control-cost ratio, $J_{ctrl}^{fusion}/J_{ctrl}^{G0}$  (lower is better)", labelpad=2)
    cbar.ax.axvline(norm(1.0), color="#222222", lw=0.7)

    y = np.arange(9)
    axm.axvline(1.0, color="#222222", lw=0.7)
    axm.axvline(1.02, color="#777777", lw=0.65, ls="--")
    axm.scatter(means, y, color=COLORS["fusion"], s=23, edgecolor="white", lw=0.45, zorder=3)
    axm.set_xlim(min(0.84, means.min() - 0.02), max(1.08, means.max() + 0.02))
    axm.tick_params(labelleft=False)
    axm.set_xlabel("Route mean")
    add_panel_label(axm, "(b)", x=-0.18, y=1.04)
    clean(axm, grid="x")
    overall = data.J.mean()
    axm.set_title(f"Overall = {overall:.3f}\n18/90 degraded", fontsize=6.6, fontweight="normal", pad=5)
    return save(fig, "figR5_fusion_case_matrix")


def load_fusion_trace() -> pd.DataFrame:
    case = ROOT / "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3/03_cases/nominal/ADAPTIVE/s42/path_factory_logistics_showcase_theta10_v10"
    trace = pd.read_csv(case / "trace.csv")
    debug = pd.read_csv(case / "node42_runtime_debug.csv")
    out = pd.DataFrame({"sample_index": np.arange(len(trace)), "t_s": trace.t_s, "theta_true_deg": np.rad2deg(trace.theta_true), "theta_sched_deg": np.rad2deg(trace.theta_sched)})
    for name in ["theta_tcn", "theta_imu", "theta_fused"]:
        out[f"{name}_deg"] = np.nan
    for name in ["K_imu_eff", "imu_valid", "fallback_exact"]:
        out[name] = 0.0
    idx = debug.step.to_numpy(int)
    if idx.min() < 0 or idx.max() >= len(out):
        raise ValueError("Node42 debug steps do not align with trace indices")
    for name in ["theta_tcn", "theta_imu", "theta_fused"]:
        out.loc[idx, f"{name}_deg"] = np.rad2deg(debug[name].to_numpy(float))
    for name in ["K_imu_eff", "imu_valid", "fallback_exact"]:
        out.loc[idx, name] = debug[name].to_numpy(float)
    for name in ["theta_tcn_deg", "theta_imu_deg", "theta_fused_deg"]:
        out[name] = out[name].bfill(limit=1)
    out["delta_fused_vs_mtcn_deg"] = (out.theta_fused_deg - out.theta_true_deg).abs() - (out.theta_tcn_deg - out.theta_true_deg).abs()
    out.to_csv(SOURCE / "figR6_fusion_trace.csv", index=False)
    return out


def plot_fusion_trace() -> list[str]:
    data = load_fusion_trace()
    d = decimate(data, 4500)
    fig = plt.figure(figsize=(183 * MM, 103 * MM))
    gs = fig.add_gridspec(4, 1, height_ratios=[2.4, 1.35, 0.55, 1.25], left=0.08, right=0.99, bottom=0.1, top=0.88, hspace=0.28)
    axes = [fig.add_subplot(gs[0])]
    axes += [fig.add_subplot(gs[i], sharex=axes[0]) for i in range(1, 4)]
    ax0, ax1, ax2, ax3 = axes
    ax0.plot(d.t_s, d.theta_true_deg, color=COLORS["truth"], lw=1.35)
    ax0.plot(d.t_s, d.theta_tcn_deg, color=COLORS["mtcn"], lw=0.9)
    ax0.plot(d.t_s, d.theta_imu_deg, color=COLORS["imu"], lw=0.75, ls="--", alpha=0.9)
    ax0.plot(d.t_s, d.theta_fused_deg, color=COLORS["fusion"], lw=1.2)
    ax0.set_ylabel("Grade estimate (deg)")
    add_panel_label(ax0, "(a)", x=-0.075, y=1.02)

    ax1.plot(d.t_s, d.theta_true_deg, color=COLORS["truth"], lw=1.0, alpha=0.75)
    ax1.plot(d.t_s, d.theta_fused_deg, color=COLORS["fusion"], lw=1.15)
    ax1.plot(d.t_s, d.theta_sched_deg, color=COLORS["oracle"], lw=0.9, ls=(0, (4, 2)))
    ax1.set_ylabel("Fusion to\nscheduler (deg)")
    add_panel_label(ax1, "(b)", x=-0.075, y=1.02)

    ax2.fill_between(d.t_s, 0, d.K_imu_eff, step="mid", color=COLORS["imu"], alpha=0.65)
    ax2.set_ylim(0, max(1.02, d.K_imu_eff.max() * 1.05))
    ax2.set_yticks([0, 1])
    ax2.set_ylabel(r"$K_{IMU}$")
    add_panel_label(ax2, "(c)", x=-0.075, y=1.02)

    delta = d.delta_fused_vs_mtcn_deg.to_numpy(float)
    ax3.fill_between(d.t_s, 0, delta, where=delta <= 0, color=COLORS["good"], alpha=0.32)
    ax3.fill_between(d.t_s, 0, delta, where=delta > 0, color=COLORS["bad"], alpha=0.3)
    ax3.plot(d.t_s, delta, color="#555555", lw=0.5)
    ax3.axhline(0, color="#222222", lw=0.65)
    lim = math.ceil(np.nanpercentile(np.abs(delta), 99.8) * 2) / 2
    ax3.set_ylim(-lim, lim)
    ax3.set_ylabel(r"$|e_{fusion}|-|e_{MTCN}|$" + "\n(deg)")
    ax3.set_xlabel("Time (s)")
    ax3.text(0.995, 0.94, "(d)", transform=ax3.transAxes, ha="right", va="top", fontsize=8.0, fontweight="bold", color=COLORS["truth"])
    for ax in axes:
        clean(ax)
    for ax in axes[:-1]:
        ax.tick_params(labelbottom=False)
    fig.legend([Line2D([], [], color=COLORS["truth"], lw=1.3), Line2D([], [], color=COLORS["mtcn"], lw=0.9), Line2D([], [], color=COLORS["imu"], lw=0.8, ls="--"), Line2D([], [], color=COLORS["fusion"], lw=1.2), Line2D([], [], color=COLORS["oracle"], lw=0.9, ls="--")], ["Truth", "ModernTCN", "Causal IMU", "Adaptive fusion", "Scheduled grade"], loc="upper center", ncol=5, bbox_to_anchor=(0.53, 0.98))
    return save(fig, "figR6_fusion_full_route_trace")


def controller_source() -> pd.DataFrame:
    case_path = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/04_A4_controller_comparison/02_case_table/five_controller_case_table.csv"
    cases = pd.read_csv(case_path)
    selected_paths = ["p01_factory_logistics_showcase", "p03_long_updown", "p04_soft_updown_straight_turn"]
    frames = []
    for path_id in selected_paths:
        for method in METHODS:
            rows = cases[(cases.path_id == path_id) & (cases.controller_id == method)]
            if method in ["MTCN_LPV_MPC", "Fusion_LPV_MPC"]:
                rows = rows[rows.model_seed == 42]
            else:
                rows = rows[rows.model_seed.isna()]
            if len(rows) != 1:
                raise ValueError(f"Expected one selected case for {path_id}/{method}, found {len(rows)}")
            trace = pd.read_csv(ROOT / rows.iloc[0].trace_file)
            trace = decimate(trace, 1800).copy()
            trace["path_id"] = path_id
            trace["controller_id"] = method
            trace["model_seed"] = 42 if method in ["MTCN_LPV_MPC", "Fusion_LPV_MPC"] else np.nan
            trace["theta_true_deg"] = np.rad2deg(trace.theta_true)
            trace["theta_sched_deg"] = np.rad2deg(trace.theta_sched)
            frames.append(trace[["path_id", "controller_id", "model_seed", "t_s", "theta_true_deg", "theta_sched_deg", "e_y", "e_psi", "F_cmd", "omega_cmd"]])
    out = pd.concat(frames, ignore_index=True)
    out.to_csv(SOURCE / "figR7_five_controller_traces.csv", index=False)
    return out


def plot_controllers() -> list[str]:
    data = controller_source()
    path_order = ["p01_factory_logistics_showcase", "p03_long_updown", "p04_soft_updown_straight_turn"]
    path_labels = ["P1  Factory logistics", "P3  Long up/down slope", "P4  Soft slope-turn"]
    rows = [("theta_sched_deg", "Scheduled grade\n(deg)"), ("e_y", r"$e_y$ (m)"), ("e_psi", r"$e_\psi$ (rad)"), ("F_cmd", r"$F_{cmd}$ (N)"), ("omega_cmd", r"$\omega_{cmd}$ (rad/s)")]
    fig, axes = plt.subplots(5, 3, figsize=(183 * MM, 139 * MM), sharex="col", gridspec_kw={"left": 0.075, "right": 0.99, "bottom": 0.075, "top": 0.9, "wspace": 0.2, "hspace": 0.17})
    for col, (path_id, title) in enumerate(zip(path_order, path_labels)):
        p = data[data.path_id == path_id]
        truth = p[p.controller_id == "Oracle_LPV_MPC"]
        for row, (field, ylabel) in enumerate(rows):
            ax = axes[row, col]
            if row == 0:
                ax.plot(truth.t_s, truth.theta_true_deg, color=COLORS["truth"], lw=1.25, zorder=5)
            for method in METHODS:
                d = p[p.controller_id == method]
                color, ls, lw = METHOD_STYLE[method]
                ax.plot(d.t_s, d[field], color=color, ls=ls, lw=lw, alpha=0.96)
            if row == 0:
                ax.set_title(title, fontweight="bold", pad=5)
            if col == 0:
                ax.set_ylabel(ylabel)
            if field == "e_y":
                ax.set_yscale("symlog", linthresh=0.25, linscale=0.7)
                ax.set_yticks([-10, -1, 0, 1, 10])
                ax.set_yticklabels(["-10", "-1", "0", "1", "10"])
            if row == 4:
                ax.set_xlabel("Time (s)")
            else:
                ax.tick_params(labelbottom=False)
            if col > 0:
                ax.tick_params(labelleft=False)
            clean(ax)
        add_panel_label(axes[0, col], f"({chr(97 + col)})", x=-0.12, y=1.12)
    handles = [Line2D([], [], color=COLORS["truth"], lw=1.25, label="Truth")]
    handles += [Line2D([], [], color=METHOD_STYLE[m][0], ls=METHOD_STYLE[m][1], lw=METHOD_STYLE[m][2], label=METHOD_LABELS[m]) for m in METHODS]
    fig.legend(handles=handles, loc="upper center", ncol=6, bbox_to_anchor=(0.53, 0.985), handlelength=2.3)
    fig.text(0.99, 0.012, "Learning-based controllers use seed 42; oracle is non-deployable.", ha="right", fontsize=6.1, color="#555555")
    return save(fig, "figR7_five_controller_small_multiples")


def audit_outputs(generated: dict[str, list[str]]) -> dict[str, object]:
    expected_rows = {
        "figR1_six_route_atlas.csv": 6,
        "figR2_scheduling_necessity.csv": 36,
        "figR3_offline_estimators.csv": 40,
        "figR4_imu_complementarity.csv": 4401,
        "figR5_fusion_case_matrix.csv": 90,
        "figR6_fusion_trace.csv": 24583,
    }
    source_checks = {}
    for name, expected in expected_rows.items():
        frame = pd.read_csv(SOURCE / name)
        observed = frame.path_id.nunique() if name == "figR1_six_route_atlas.csv" else len(frame)
        if observed != expected:
            raise ValueError(f"{name}: expected {expected}, observed {observed}")
        source_checks[name] = {"expected": expected, "observed": int(observed)}
    controller_data = pd.read_csv(SOURCE / "figR7_five_controller_traces.csv")
    controller_cases = controller_data[["path_id", "controller_id", "model_seed"]].drop_duplicates()
    if len(controller_cases) != 15:
        raise ValueError(f"Controller source must contain 15 route-method cases, got {len(controller_cases)}")
    source_checks["figR7_five_controller_traces.csv"] = {"route_method_cases": 15, "rows": len(controller_data)}

    output_checks = {}
    for figure_id, paths in generated.items():
        by_suffix = {Path(path).suffix: ROOT / path for path in paths}
        if set(by_suffix) != {".pdf", ".svg", ".png", ".tiff"}:
            raise ValueError(f"{figure_id}: incomplete export set")
        with Image.open(by_suffix[".png"]) as image:
            rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
            nonwhite = float(np.mean(np.any(rgb < 250, axis=2)))
            if nonwhite < 0.015:
                raise ValueError(f"{figure_id}: PNG appears blank")
            png_info = {"pixels": list(image.size), "nonwhite_fraction": round(nonwhite, 5)}
        svg_root = ET.parse(by_suffix[".svg"]).getroot()
        text_elements = sum(1 for node in svg_root.iter() if node.tag.endswith("text"))
        if text_elements == 0:
            raise ValueError(f"{figure_id}: SVG has no editable text")
        output_checks[figure_id] = {"png": png_info, "svg_text_elements": text_elements}
    return {"status": "PASS", "source_checks": source_checks, "output_checks": output_checks}


def main() -> None:
    setup()
    generated = {
        "R1_six_route_atlas": plot_route_atlas(),
        "R2_scheduling_necessity": plot_scheduling_necessity(),
        "R3_offline_estimators": plot_offline_estimators(),
        "R4_imu_complementarity": plot_imu_complementarity(),
        "R5_fusion_cases": plot_fusion_cases(),
        "R6_fusion_trace": plot_fusion_trace(),
        "R7_five_controllers": plot_controllers(),
    }
    manifest = {
        "backend": "Python/matplotlib",
        "design_basis": "scientific-visualization and matplotlib skills; no Nature skill",
        "figure_count": len(generated),
        "outputs": generated,
    }
    manifest["qa"] = audit_outputs(generated)
    (WORKSPACE / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
