"""Fig. 1: Overall framework (v7 layout).

Bands top->bottom: perception / fusion / control / plant+offline.
Full 7.16 in width at 1:1; fonts sized for print legibility.
Style palette follows shared/style.py. Canvas unit = 0.1 inch.
"""

from __future__ import annotations

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

PALETTE = {
    "truth": "#222222", "fusion": "#0F4C81", "mtcn": "#4C78A8",
    "imu": "#2A9D8F", "zero_slope": "#8A8A8A", "oracle": "#D28E2B",
    "warning": "#B24A47", "grid": "#E6E6E6",
}


def apply_publication_style():
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "Helvetica", "DejaVu Sans", "Liberation Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42
    plt.rcParams["font.size"] = 7.0
    plt.rcParams["savefig.facecolor"] = "white"
    plt.rcParams["figure.facecolor"] = "white"


def tint(hex_color, alpha):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (1 - alpha * (1 - r), 1 - alpha * (1 - g), 1 - alpha * (1 - b))


def box(ax, x, y, w, h, title, lines, color, *, title_fs=7.4, body_fs=6.6,
        lw=1.0, fill=0.10, dashed=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle="round,pad=0.0,rounding_size=0.8",
                 linewidth=lw, edgecolor=color, facecolor=tint(color, fill),
                 linestyle=(0, (4, 2.4)) if dashed else "solid", zorder=3))
    n = len(lines)
    ty = y + h - 1.45 if n else y + h / 2
    ax.text(x + w / 2, ty, title, ha="center", va="center", fontsize=title_fs,
            fontweight="bold", color=PALETTE["truth"], zorder=4)
    if n:
        ax.text(x + w / 2, y + (h - 2.9) / 2 - 0.1, "\n".join(lines),
                ha="center", va="center", fontsize=body_fs, color="#333333",
                zorder=4, linespacing=1.35)
    return (x, y, w, h)


def E(b):
    x, y, w, h = b
    return {"l": (x, y + h / 2), "r": (x + w, y + h / 2),
            "t": (x + w / 2, y + h), "b": (x + w / 2, y)}


def seg_arrow(ax, pts, *, color="#444444", lw=1.15, dashed=False, zorder=2):
    ls = (0, (3.4, 2.3)) if dashed else "-"
    for a, b in zip(pts[:-2], pts[1:-1]):
        ax.plot([a[0], b[0]], [a[1], b[1]], color=color, lw=lw, ls=ls,
                zorder=zorder, solid_capstyle="round")
    ax.add_patch(FancyArrowPatch(pts[-2], pts[-1], arrowstyle="-|>",
                 mutation_scale=8.5, linewidth=lw, color=color, linestyle=ls,
                 zorder=zorder, shrinkA=0.0, shrinkB=0.0))


def label(ax, x, y, text, *, fs=6.4, color="#333333", ha="center", va="center",
          rot=0):
    ax.text(x, y, text, fontsize=fs, color=color, ha=ha, va=va, rotation=rot,
            rotation_mode="anchor", zorder=5)


def zone(ax, x, y, w, h, title, color, *, right=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle="round,pad=0.0,rounding_size=1.1",
                 linewidth=0.8, edgecolor=color, facecolor=tint(color, 0.045),
                 zorder=1))
    tx = x + w - 1.3 if right else x + 1.3
    ax.text(tx, y + h - 1.35, title, fontsize=6.6, fontweight="bold",
            color=color, ha="right" if right else "left", va="center", zorder=4)


def main():
    apply_publication_style()
    fig = plt.figure(figsize=(7.16, 4.9))
    ax = fig.add_axes([0.0, 0.0, 1.0, 1.0])
    ax.set_xlim(0, 71.6)
    ax.set_ylim(0, 49.0)
    ax.axis("off")

    C_MT, C_FU, C_IMU = PALETTE["mtcn"], PALETTE["fusion"], PALETTE["imu"]
    C_CTL, C_PLANT, C_OFF = PALETTE["oracle"], "#666666", "#9A9A9A"

    # ---------- zones (top -> bottom) ----------
    zone(ax, 2.6, 36.6, 67.6, 11.4, "ONLINE TEMPORAL PERCEPTION  (Sec. III-A to III-C)", C_MT)
    zone(ax, 2.6, 23.0, 67.6, 11.4, "UNCERTAINTY-ADAPTIVE GRADE FUSION  (Sec. III-D)", C_FU)
    zone(ax, 2.6, 9.4, 67.6, 11.4, "GRADE-SCHEDULED LPV-MPC  (Sec. III-E)", C_CTL, right=True)

    # ---------- perception row ----------
    b_feat = box(ax, 4.2, 37.6, 20.0, 7.6, "22-D feature construction",
                 ["kinematic, drive, and", "consistency channels"], C_MT)
    b_delta = box(ax, 27.6, 37.6, 18.0, 7.6, "Delta-lag window",
                  ["normalization, lags {1, 2, 4},", r"$128\times88$ history $\mathbf{Z}_k$"], C_MT)
    b_net = box(ax, 49.4, 37.6, 18.6, 7.6, "ModernTCN estimator",
                ["large-kernel depthwise", r"conv ($K{=}31$), 5 blocks"], C_MT)
    seg_arrow(ax, [E(b_feat)["r"], E(b_delta)["l"]])
    label(ax, 25.9, 42.5, r"$\mathbf{s}_k$")
    seg_arrow(ax, [E(b_delta)["r"], E(b_net)["l"]])

    # ---------- fusion row ----------
    b_obs = box(ax, 6.4, 24.0, 20.0, 7.6, "Force-balance observer",
                ["longitudinal force balance,", "validity check"], C_IMU)
    b_fus = box(ax, 36.4, 24.0, 27.6, 7.6, "Uncertainty-adaptive fusion",
                ["calibrated error moments, bounded", "correction, guard + scheduling filter"], C_FU)
    seg_arrow(ax, [E(b_obs)["r"], E(b_fus)["l"]], color=C_IMU, lw=1.25)
    label(ax, 31.4, 28.8, r"$\hat\theta_k^{\mathrm{IMU}}$", color=C_IMU)

    # ModernTCN -> fusion
    xnet = E(b_net)["b"][0]
    seg_arrow(ax, [(xnet, 37.6), (xnet, 31.6)], color=C_MT, lw=1.25)
    label(ax, xnet + 1.0, 35.6, r"$\hat\theta_k^{\mathrm{MTCN}},\ c_k^{\mathrm{main}}$",
          color=C_MT, ha="left")

    # ---------- control row ----------
    b_sched = box(ax, 4.2, 10.4, 21.0, 7.6, "Synchronized scheduling",
                  [r"$\varrho_k=[v_k,\ \omega_k,\ \theta_k^{\mathrm{sch}}]$,",
                   r"$d_k$, $F_{eq,k}$, weights, bounds"], C_CTL)
    b_lpv = box(ax, 29.2, 10.4, 17.6, 7.6, "LPV database",
                [r"$11\times15\times25$ models,", "trilinear interpolation"], C_CTL)
    b_mpc = box(ax, 50.6, 10.4, 17.4, 7.6, "Constrained MPC",
                [r"QP, $N_p{=}150$, $N_c{=}30$,", r"$u_k=[F_{cmd},\ \omega_{cmd}]$"], C_CTL)
    seg_arrow(ax, [E(b_sched)["r"], E(b_lpv)["l"]], color=C_CTL, lw=1.25)
    label(ax, 27.2, 15.3, r"$\varrho_k$", color="#8A5A17")
    seg_arrow(ax, [E(b_lpv)["r"], E(b_mpc)["l"]], color=C_CTL, lw=1.25)

    # fusion -> scheduling
    xf = 50.2
    seg_arrow(ax, [(xf, 24.0), (xf, 21.0), (14.7, 21.0), (14.7, 18.0)],
              color=C_FU, lw=1.3)
    label(ax, xf + 1.0, 21.9, r"$\theta_k^{\mathrm{sch}}$", color=C_FU, ha="left")

    # ---------- bottom band: plant + offline ----------
    b_plant = box(ax, 2.6, 1.2, 44.0, 5.6, "AGV plant  (Sec. II)",
                  ["diagonal dual-steering-wheel vehicle;  road grade "
                   r"$\theta_k$ as an exogenous input"],
                  C_PLANT, fill=0.06, title_fs=7.2, body_fs=6.4)
    box(ax, 50.4, 1.2, 19.8, 5.6, "Offline  (Sec. IV)",
        ["dataset (102 runs), training (10 seeds),", "fusion calibration; deployed online"],
        C_OFF, fill=0.0, title_fs=6.8, body_fs=6.0, lw=0.9, dashed=True)

    # MPC -> plant
    seg_arrow(ax, [(59.3, 10.4), (59.3, 8.2), (44.0, 8.2), (44.0, 6.8)],
              lw=1.3)
    label(ax, 58.3, 8.9, r"$u_k$", ha="right")

    # plant -> scheduling (v, omega)
    seg_arrow(ax, [(10.0, 6.8), (10.0, 10.4)], color="#777777", lw=1.15)
    label(ax, 11.0, 8.5, r"$v_k,\ \omega_k$", fs=6.2, color="#666666", ha="left")

    # plant -> sensor rail (left) -> features and observer
    rail_x = 1.5
    seg_arrow(ax, [(2.6, 4.0), (rail_x, 4.0), (rail_x, 41.4), (4.2, 41.4)],
              lw=1.25)
    seg_arrow(ax, [(rail_x, 27.8), (6.4, 27.8)], lw=1.25)
    ax.plot([rail_x], [27.8], marker="o", markersize=2.6, color="#444444",
            zorder=5)
    label(ax, 0.62, 24.0,
          r"onboard measurements  ($\omega_g$, $\omega_w$, $i$, $\delta$, $a_x$)",
          fs=6.2, rot=90, ha="center")

    fig.savefig("/home/claude/fig01/output/fig01_overall_framework.pdf")
    fig.savefig("/home/claude/fig01/output/fig01_overall_framework.png", dpi=300)
    print("saved v7")


if __name__ == "__main__":
    main()
