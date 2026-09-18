"""Fig. 1 (illustrated variant): device-icon style framework, mimicking the
hardware-testbed diagram language: pictorial objects, bold name + role
labels, thick dashed colored signal arrows with inline text, bottom legend.
Palette follows shared/style.py. Canvas unit = 0.1 inch.
"""

from __future__ import annotations

import matplotlib.pyplot as plt
from matplotlib.patches import (FancyBboxPatch, FancyArrowPatch, Rectangle,
                                Circle, Polygon)

PALETTE = {
    "truth": "#222222", "fusion": "#0F4C81", "mtcn": "#4C78A8",
    "imu": "#2A9D8F", "zero_slope": "#8A8A8A", "oracle": "#D28E2B",
    "warning": "#B24A47", "green": "#2A7F74",
}


def style():
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "Helvetica", "DejaVu Sans", "Liberation Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["savefig.facecolor"] = "white"
    plt.rcParams["figure.facecolor"] = "white"


def darr(ax, pts, color, *, lw=2.0, ms=13, dash=(5, 2.6), zorder=3):
    for a, b in zip(pts[:-2], pts[1:-1]):
        ax.plot([a[0], b[0]], [a[1], b[1]], color=color, lw=lw,
                ls=(0, dash), zorder=zorder, solid_capstyle="butt")
    ax.add_patch(FancyArrowPatch(pts[-2], pts[-1], arrowstyle="-|>",
                 mutation_scale=ms, lw=lw, color=color, linestyle=(0, dash),
                 zorder=zorder, shrinkA=0, shrinkB=0))


def txt(ax, x, y, s, *, fs=6.4, color="#222222", ha="center", bold=False,
        z=6):
    ax.text(x, y, s, fontsize=fs, color=color, ha=ha, va="center",
            fontweight="bold" if bold else "normal", zorder=z)


def name_role(ax, x, y, name, roles, *, above=False, name_fs=7.6, role_fs=6.2):
    dy = 1.9
    ys = [y + (len(roles)) * dy] + [y + (len(roles) - 1 - i) * dy
                                    for i in range(len(roles))]
    if above:
        txt(ax, x, ys[0], name, fs=name_fs, bold=True)
        for i, r in enumerate(roles):
            txt(ax, x, ys[i + 1], r, fs=role_fs, color="#333333")
    else:
        txt(ax, x, y, name, fs=name_fs, bold=True)
        for i, r in enumerate(roles):
            txt(ax, x, y - (i + 1) * dy, r, fs=role_fs, color="#333333")


# ----------------------------- icons ---------------------------------------

def icon_agv(ax, cx, cy, s=1.0):
    """Top-view AGV: body, four wheels, LF/RR steered, heading arrow."""
    w, h = 10.5 * s, 7.6 * s
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.0,rounding_size=1.1", lw=1.3,
                 edgecolor="#4A4A4A", facecolor="#E9E9E9", zorder=3))
    ww, wh = 2.6 * s, 1.15 * s
    import matplotlib.transforms as mtr
    for (dx, dy, steer) in [(-w * 0.30, h * 0.52, 22), (w * 0.30, -h * 0.52, 22),
                            (w * 0.30, h * 0.52, 0), (-w * 0.30, -h * 0.52, 0)]:
        r = Rectangle((cx + dx - ww / 2, cy + dy - wh / 2), ww, wh,
                      facecolor="#3A3A3A", edgecolor="none", zorder=4)
        t = mtr.Affine2D().rotate_deg_around(cx + dx, cy + dy, steer) + ax.transData
        r.set_transform(t)
        ax.add_patch(r)
    ax.add_patch(FancyArrowPatch((cx - 2.4 * s, cy), (cx + 3.0 * s, cy),
                 arrowstyle="-|>", mutation_scale=11, lw=1.4,
                 color="#4A4A4A", zorder=5))
    txt(ax, cx - w / 2 + 1.15, cy + h / 2 - 1.0, "LF", fs=4.6, color="#555555")
    txt(ax, cx + w / 2 - 1.15, cy - h / 2 + 1.0, "RR", fs=4.6, color="#555555")


def icon_chip_net(ax, cx, cy, color, s=1.0):
    """Neural-network chip for ModernTCN."""
    w, h = 9.4 * s, 6.6 * s
    for i in range(7):
        px = cx - w / 2 + (i + 0.5) * w / 7
        ax.plot([px, px], [cy + h / 2, cy + h / 2 + 0.9], color="#777777",
                lw=1.0, zorder=2)
        ax.plot([px, px], [cy - h / 2 - 0.9, cy - h / 2], color="#777777",
                lw=1.0, zorder=2)
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.0,rounding_size=0.6", lw=1.3,
                 edgecolor=color, facecolor="#F3F6FA", zorder=3))
    cols = [(-3.0, (-1.7, 0.0, 1.7)), (0.0, (-2.2, -0.75, 0.75, 2.2)),
            (3.0, (-1.7, 0.0, 1.7))]
    for (x1, ys1), (x2, ys2) in zip(cols[:-1], cols[1:]):
        for y1 in ys1:
            for y2 in ys2:
                ax.plot([cx + x1 * s, cx + x2 * s], [cy + y1 * s, cy + y2 * s],
                        color=color, lw=0.5, alpha=0.55, zorder=4)
    for x0, ys0 in cols:
        for y0 in ys0:
            ax.add_patch(Circle((cx + x0 * s, cy + y0 * s), 0.52 * s,
                         facecolor="white", edgecolor=color, lw=1.0, zorder=5))


def icon_chip_imu(ax, cx, cy, color, s=1.0):
    """Sensor chip for the force-balance observer."""
    w, h = 7.6 * s, 6.2 * s
    for i in range(5):
        py = cy - h / 2 + (i + 0.5) * h / 5
        ax.plot([cx - w / 2 - 0.9, cx - w / 2], [py, py], color="#777777",
                lw=1.0, zorder=2)
        ax.plot([cx + w / 2, cx + w / 2 + 0.9], [py, py], color="#777777",
                lw=1.0, zorder=2)
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.0,rounding_size=0.6", lw=1.3,
                 edgecolor=color, facecolor="#F0F7F6", zorder=3))
    ax.add_patch(Circle((cx, cy + 0.4), 1.5 * s, facecolor="none",
                 edgecolor=color, lw=1.1, zorder=4))
    ax.plot([cx, cx + 1.05 * s], [cy + 0.4, cy + 1.45 * s], color=color,
            lw=1.1, zorder=5)
    txt(ax, cx, cy - 2.05 * s, r"$ma_x = F_d - F_r - mg\sin\theta$",
        fs=4.4, color=color)


def icon_hub(ax, cx, cy, color, s=1.0):
    """Switch-like fusion hub."""
    w, h = 12.5 * s, 4.6 * s
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.0,rounding_size=0.55", lw=1.4,
                 edgecolor=color, facecolor="#EFF3F8", zorder=3))
    for i in range(6):
        px = cx - w / 2 + 1.3 + i * 1.35
        ax.add_patch(Rectangle((px, cy + 0.35), 0.95, 1.0,
                     facecolor="white", edgecolor=color, lw=0.8, zorder=4))
    for i in range(4):
        ax.add_patch(Circle((cx - w / 2 + 1.6 + i * 1.15, cy - 1.25), 0.28,
                     facecolor=color, edgecolor="none", zorder=4))
    txt(ax, cx + w / 2 - 2.6, cy - 1.2, r"$\oplus$", fs=8.5, color=color)


def icon_ecu(ax, cx, cy, color, s=1.0):
    """Finned edge-controller box for LPV-MPC."""
    w, h = 11.5 * s, 7.0 * s
    for i in range(9):
        px = cx - w / 2 + 0.8 + i * (w - 1.6) / 8
        ax.add_patch(Rectangle((px - 0.32, cy + h / 2), 0.64, 1.15,
                     facecolor="#C8C8C8", edgecolor="#8A8A8A", lw=0.5,
                     zorder=2))
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.0,rounding_size=0.7", lw=1.4,
                 edgecolor=color, facecolor="#FBF4E8", zorder=3))
    ax.add_patch(Rectangle((cx - w / 2 + 1.0, cy - h / 2 + 0.8), 2.3, 1.4,
                 facecolor="white", edgecolor="#8A8A8A", lw=0.7, zorder=4))
    ax.add_patch(Rectangle((cx - w / 2 + 3.8, cy - h / 2 + 0.8), 1.5, 1.4,
                 facecolor="white", edgecolor="#8A8A8A", lw=0.7, zorder=4))
    txt(ax, cx, cy + 1.0, "LPV database + QP", fs=5.4, color="#7A5310")


def icon_laptop(ax, cx, cy, s=1.0):
    w, h = 7.6 * s, 4.6 * s
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2 + 1.1), w, h - 1.1,
                 boxstyle="round,pad=0.0,rounding_size=0.4", lw=1.2,
                 edgecolor="#4A4A4A", facecolor="#F2F2F2", zorder=3))
    ax.add_patch(Rectangle((cx - w / 2 + 0.7, cy - h / 2 + 1.75), w - 1.4,
                 h - 2.5, facecolor="#BFD4E6", edgecolor="none", zorder=4))
    ax.add_patch(Polygon([(cx - w / 2 - 1.0, cy - h / 2), (cx + w / 2 + 1.0, cy - h / 2),
                          (cx + w / 2, cy - h / 2 + 1.1), (cx - w / 2, cy - h / 2 + 1.1)],
                 facecolor="#D9D9D9", edgecolor="#4A4A4A", lw=1.0, zorder=3))


# ----------------------------- figure ---------------------------------------

def main():
    style()
    fig = plt.figure(figsize=(7.16, 4.28))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 71.6)
    ax.set_ylim(7.2, 50.0)
    ax.axis("off")
    C = PALETTE

    # ---------- objects ----------
    icon_agv(ax, 8.75, 28.6)
    name_role(ax, 8.75, 22.4, "AGV plant",
              ["(dual-steering-wheel", "vehicle; road grade", r"$\theta_k$ exogenous)"])

    icon_chip_imu(ax, 24.0, 27.8, C["imu"])
    name_role(ax, 24.0, 22.6, "Force-balance observer",
              ["(validity-checked", "grade estimate)"])

    icon_hub(ax, 40.0, 27.6, C["fusion"])
    name_role(ax, 40.0, 22.6, "Uncertainty-adaptive fusion",
              ["(bounded correction,", "guard + filter)"])

    icon_ecu(ax, 62.0, 27.6, C["oracle"])
    name_role(ax, 62.0, 22.4, "Grade-scheduled LPV-MPC",
              ["(interpolated model, QP,", r"$N_p{=}150$, $N_c{=}30$; scheduled", r"by $v_k$, $\omega_k$, $\theta_k^{\mathrm{sch}}$)"])

    icon_chip_net(ax, 37.0, 40.6, C["mtcn"])
    name_role(ax, 37.0, 45.2, "ModernTCN estimator",
              ["(22-D features + delta bank,", r"$128\times88$ history)"],
              above=True)

    icon_laptop(ax, 59.0, 42.6)
    name_role(ax, 59.0, 47.2, "Offline training and calibration",
              ["(102 runs, 10 seeds)"], above=True)

    # ---------- signal arrows ----------
    # measurements: AGV -> ModernTCN (trunk) and AGV -> observer (branch)
    darr(ax, [(8.75, 32.6), (8.75, 40.6), (31.9, 40.6)], C["oracle"], lw=2.1)
    txt(ax, 20.0, 42.0, "Onboard measurements", fs=6.6, color=C["oracle"],
        bold=True)
    txt(ax, 20.0, 40.6 - 1.35, r"($\omega_g$, $\omega_w$, $i$, $\delta$, $a_x$)",
        fs=6.0, color=C["oracle"])
    darr(ax, [(14.1, 28.6), (14.1, 27.8), (19.2, 27.8)], C["oracle"], lw=2.1)

    # ModernTCN -> fusion
    darr(ax, [(37.0, 36.9), (37.0, 30.2)], C["mtcn"], lw=2.1)
    txt(ax, 38.0, 33.6, r"$\hat\theta_k^{\mathrm{MTCN}},\ c_k^{\mathrm{main}}$",
        fs=6.4, color=C["mtcn"], ha="left")

    # observer -> fusion
    darr(ax, [(28.0, 27.8), (33.6, 27.8)], C["imu"], lw=2.1)
    txt(ax, 30.8, 29.3, r"$\hat\theta_k^{\mathrm{IMU}}$", fs=6.4, color=C["imu"])

    # fusion -> MPC
    darr(ax, [(46.4, 27.6), (56.1, 27.6)], C["fusion"], lw=2.2)
    txt(ax, 51.2, 29.5, "Scheduled grade", fs=6.4, color=C["fusion"], bold=True)
    txt(ax, 51.2, 26.0, r"$\theta_k^{\mathrm{sch}}$", fs=6.4, color=C["fusion"])

    # commands: MPC -> AGV (bottom channel)
    darr(ax, [(67.75, 26.2), (70.6, 26.2), (70.6, 13.6), (2.0, 13.6),
              (2.0, 28.6), (3.3, 28.6)], C["green"], lw=2.2)
    txt(ax, 33.0, 15.0, r"Control commands  $u_k=[F_{cmd},\ \omega_{cmd}]$",
        fs=6.6, color=C["green"], bold=True)

    # offline deployment: laptop -> ModernTCN (weights), laptop -> MPC (tables)
    darr(ax, [(55.0, 42.6), (42.1, 42.6)], "#8A8A8A", lw=1.9, ms=11)
    txt(ax, 48.5, 43.9, "weights", fs=5.8, color="#777777", bold=True)
    darr(ax, [(59.0, 40.0), (59.0, 32.5)], "#8A8A8A", lw=1.9, ms=11)
    txt(ax, 59.9, 36.3, "LPV database", fs=5.8, color="#777777", bold=True,
        ha="left")

    # ---------- legend ----------
    ax.plot([12.0, 16.2], [9.0, 9.0], color=C["fusion"], lw=2.0,
            ls=(0, (5, 2.6)))
    txt(ax, 17.2, 9.0, "Online signal flow (every control period)",
        fs=6.0, ha="left", color="#333333")
    ax.plot([37.6, 41.8], [9.0, 9.0], color="#8A8A8A", lw=1.9,
            ls=(0, (5, 2.6)))
    txt(ax, 42.8, 9.0, "Offline deployment (weights, LPV database)",
        fs=6.0, ha="left", color="#333333")

    fig.savefig("/home/claude/fig01/output/fig01_overall_framework_illustrated.pdf")
    fig.savefig("/home/claude/fig01/output/fig01_overall_framework_illustrated.png",
                dpi=300)
    print("saved illustrated v3")


if __name__ == "__main__":
    main()
