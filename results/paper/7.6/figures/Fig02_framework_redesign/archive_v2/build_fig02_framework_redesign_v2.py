"""Build the redesigned overall perception--control framework figure.

The drawing is intentionally icon-led and organized into offline and online
layers.  It is derived only from the implementation described in
paper_v4_final_candidate.tex; the unrelated reference figure contributes the
visual grammar (layering, pictograms, and restrained labels), not content.
"""

from __future__ import annotations

from pathlib import Path
import math

import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
from matplotlib.patches import (
    Arc,
    Circle,
    FancyArrowPatch,
    FancyBboxPatch,
    Polygon,
    Rectangle,
)
from matplotlib.transforms import Affine2D


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output"

COL = {
    "ink": "#263238",
    "muted": "#66727A",
    "line": "#455A64",
    "panel": "#FBFCFD",
    "offline": "#7B858C",
    "blue": "#3E78B2",
    "blue_fill": "#EDF4FA",
    "teal": "#2A9D8F",
    "teal_fill": "#ECF7F5",
    "navy": "#0F4C81",
    "navy_fill": "#EDF3F8",
    "orange": "#D28E2B",
    "orange_fill": "#FCF5E9",
    "green": "#2A7F74",
    "green_fill": "#EDF6F3",
    "gray_fill": "#F0F2F3",
    "red": "#B24A47",
}


def setup_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
            "font.size": 6.4,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "axes.linewidth": 0.7,
            "savefig.facecolor": "white",
            "figure.facecolor": "white",
        }
    )


def text(ax, x, y, s, *, size=6.2, color=None, weight="normal", ha="center", va="center", z=20, **kw):
    return ax.text(
        x,
        y,
        s,
        fontsize=size,
        color=color or COL["ink"],
        fontweight=weight,
        ha=ha,
        va=va,
        zorder=z,
        **kw,
    )


def band(ax, x, y, w, h, title, subtitle, *, dashed=False):
    box = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.0,rounding_size=1.5",
        facecolor="white",
        edgecolor=COL["offline"] if dashed else COL["navy"],
        linewidth=1.15,
        linestyle=(0, (4.0, 2.5)) if dashed else "solid",
        zorder=0,
    )
    ax.add_patch(box)
    text(ax, x + 2.0, y + h - 1.5, title, size=7.2, weight="bold", ha="left")
    text(ax, x + w - 2.0, y + h - 1.5, subtitle, size=5.6, color=COL["muted"], ha="right")


def arrow(ax, start, end, *, color=None, lw=1.55, dashed=False, scale=11, z=8, connectionstyle="arc3"):
    arr = FancyArrowPatch(
        start,
        end,
        arrowstyle="-|>",
        mutation_scale=scale,
        linewidth=lw,
        color=color or COL["line"],
        linestyle=(0, (4.0, 2.6)) if dashed else "solid",
        shrinkA=0,
        shrinkB=0,
        connectionstyle=connectionstyle,
        zorder=z,
    )
    ax.add_patch(arr)
    return arr


def poly_arrow(ax, pts, *, color=None, lw=1.55, dashed=False, scale=11, z=8):
    c = color or COL["line"]
    ls = (0, (4.0, 2.6)) if dashed else "solid"
    for a, b in zip(pts[:-2], pts[1:-1]):
        ax.plot([a[0], b[0]], [a[1], b[1]], color=c, lw=lw, ls=ls, zorder=z)
    arrow(ax, pts[-2], pts[-1], color=c, lw=lw, dashed=dashed, scale=scale, z=z)


def module_card(ax, cx, cy, w, h, title, subtitle, color, *, section=None):
    ax.add_patch(
        FancyBboxPatch(
            (cx - w / 2, cy - h / 2),
            w,
            h,
            boxstyle="round,pad=0.0,rounding_size=0.9",
            facecolor="white",
            edgecolor=color,
            linewidth=1.25,
            zorder=4,
        )
    )
    title_lines = title.split("\n")
    for i, line in enumerate(title_lines):
        text(ax, cx, cy + h / 2 - 0.72 - i * 0.78, line, size=4.9, weight="bold", z=7)
    subtitle_lines = subtitle.split("\n")
    for i, line in enumerate(subtitle_lines):
        text(ax, cx, cy - h / 2 + 0.78 + (len(subtitle_lines) - 1 - i) * 0.72,
             line, size=3.95, color=COL["muted"], z=7)


def icon_dataset(ax, cx, cy, s=1.0):
    for i, c in enumerate(["#D9E7F4", "#BDD3E8", "#A6C4DF"]):
        dx, dy = i * 0.55 * s, i * 0.45 * s
        ax.add_patch(Rectangle((cx - 3.0 * s + dx, cy - 2.0 * s + dy), 5.7 * s, 3.8 * s,
                               facecolor=c, edgecolor=COL["line"], lw=0.65, zorder=3 + i))
    xs = [cx - 2.0 * s, cx - 1.2 * s, cx - 0.2 * s, cx + 0.8 * s, cx + 1.7 * s]
    ys = [cy - 0.55 * s, cy + 0.25 * s, cy - 0.1 * s, cy + 0.75 * s, cy + 0.2 * s]
    ax.plot(xs, ys, color=COL["blue"], lw=1.0, zorder=8)
    for x, y in zip(xs, ys):
        ax.add_patch(Circle((x, y), 0.12 * s, color=COL["blue"], zorder=9))


def icon_model(ax, cx, cy, s=1.0):
    # Sloped road and compact AGV glyph.
    ax.plot([cx - 3.3 * s, cx + 3.4 * s], [cy - 1.7 * s, cy + 1.0 * s], color=COL["line"], lw=1.2, zorder=3)
    body = FancyBboxPatch((cx - 1.8 * s, cy - 0.2 * s), 3.4 * s, 1.8 * s,
                          boxstyle="round,pad=0.0,rounding_size=0.35",
                          facecolor=COL["gray_fill"], edgecolor=COL["line"], lw=0.8, zorder=5)
    body.set_transform(Affine2D().rotate_deg_around(cx, cy + 0.7 * s, 22) + ax.transData)
    ax.add_patch(body)
    for dx in (-1.15, 1.05):
        ax.add_patch(Circle((cx + dx * s, cy - 0.2 * s + (dx + 1.15) * 0.42 * s), 0.43 * s,
                            facecolor=COL["ink"], edgecolor="white", lw=0.4, zorder=7))
    ax.add_patch(Arc((cx - 2.2 * s, cy - 0.7 * s), 2.4 * s, 2.0 * s, theta1=5, theta2=33,
                     color=COL["orange"], lw=1.0, zorder=8))
    text(ax, cx - 2.6 * s, cy + 0.15 * s, r"$\theta$", size=5.0, color=COL["orange"])


def icon_workstation(ax, cx, cy, s=1.0):
    ax.add_patch(FancyBboxPatch((cx - 3.1 * s, cy - 1.2 * s), 6.2 * s, 4.2 * s,
                               boxstyle="round,pad=0.0,rounding_size=0.45",
                               facecolor="#F7F8F9", edgecolor=COL["line"], lw=0.85, zorder=4))
    ax.add_patch(Rectangle((cx - 2.5 * s, cy - 0.55 * s), 5.0 * s, 2.75 * s,
                           facecolor="#DDE8F1", edgecolor="none", zorder=5))
    for j, c in enumerate([COL["blue"], COL["navy"], COL["orange"]]):
        ax.add_patch(Rectangle((cx - 2.0 * s, cy + (1.25 - 0.8 * j) * s), (2.5 + 0.85 * j) * s,
                               0.32 * s, facecolor=c, edgecolor="none", zorder=6))
    ax.add_patch(Polygon([(cx - 3.8 * s, cy - 2.0 * s), (cx + 3.8 * s, cy - 2.0 * s),
                          (cx + 3.0 * s, cy - 1.2 * s), (cx - 3.0 * s, cy - 1.2 * s)],
                         facecolor="#D9DDDF", edgecolor=COL["line"], lw=0.75, zorder=4))


def artifact_tag(ax, cx, cy, w, title, subtitle, color):
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - 2.05), w, 4.1,
                               boxstyle="round,pad=0.0,rounding_size=0.65",
                               facecolor="white", edgecolor=color, lw=1.05, zorder=4))
    ax.add_patch(Circle((cx - w / 2 + 1.8, cy), 0.75, facecolor=color, edgecolor="none", zorder=5))
    text(ax, cx - w / 2 + 1.8, cy, title[0], size=5.3, color="white", weight="bold")
    text(ax, cx - w / 2 + 3.0, cy + 0.62, title, size=5.1, weight="bold", ha="left")
    text(ax, cx - w / 2 + 3.0, cy - 0.72, subtitle, size=4.65, color=COL["muted"], ha="left")


def icon_sensor_bus(ax, cx, cy, s=1.0):
    ax.add_patch(FancyBboxPatch((cx - 3.1 * s, cy - 4.1 * s), 6.2 * s, 8.2 * s,
                               boxstyle="round,pad=0.0,rounding_size=0.85",
                               facecolor=COL["gray_fill"], edgecolor=COL["line"], lw=1.0, zorder=4))
    # CAN bus rails.
    ax.plot([cx - 1.9 * s, cx + 1.9 * s], [cy + 1.75 * s, cy + 1.75 * s], color=COL["blue"], lw=1.0, zorder=6)
    ax.plot([cx - 1.9 * s, cx + 1.9 * s], [cy + 0.85 * s, cy + 0.85 * s], color=COL["blue"], lw=1.0, zorder=6)
    for x in (-1.6, 0, 1.6):
        ax.add_patch(Circle((cx + x * s, cy + 1.3 * s), 0.36 * s, facecolor="white", edgecolor=COL["blue"], lw=0.8, zorder=7))
    # IMU triad.
    o = (cx, cy - 1.6 * s)
    ax.add_patch(Circle(o, 0.32 * s, facecolor=COL["teal"], edgecolor="none", zorder=7))
    arrow(ax, o, (cx + 1.65 * s, cy - 1.6 * s), color=COL["teal"], lw=0.8, scale=7, z=7)
    arrow(ax, o, (cx, cy - 0.05 * s), color=COL["teal"], lw=0.8, scale=7, z=7)
    arrow(ax, o, (cx - 1.15 * s, cy - 2.75 * s), color=COL["teal"], lw=0.8, scale=7, z=7)
    text(ax, cx, cy - 4.95 * s, "Onboard sensing", size=6.5, weight="bold")
    text(ax, cx, cy - 6.25 * s, "CAN + yaw gyro + six-axis IMU", size=4.9, color=COL["muted"])


def icon_delta_bank(ax, cx, cy, s=1.0):
    colors = ["#E7EEF6", "#D6E5F2", "#C2D9EC", "#ACCBE4"]
    labels = [r"$z$", r"$\Delta_1$", r"$\Delta_2$", r"$\Delta_4$"]
    for i in range(4):
        x = cx - 3.4 * s + i * 1.8 * s
        ax.add_patch(FancyBboxPatch((x, cy - 2.4 * s), 1.45 * s, 4.8 * s,
                                   boxstyle="round,pad=0.0,rounding_size=0.28",
                                   facecolor=colors[i], edgecolor=COL["blue"], lw=0.65, zorder=5))
        for j in range(5):
            yy = cy - 1.5 * s + j * 0.75 * s
            ax.plot([x + 0.28 * s, x + 1.17 * s], [yy, yy], color=COL["blue"], lw=0.38, alpha=0.75, zorder=6)
        text(ax, x + 0.72 * s, cy + 3.0 * s, labels[i], size=4.8, color=COL["blue"])


def icon_network_chip(ax, cx, cy, s=1.0):
    w, h = 7.2 * s, 5.7 * s
    for i in range(6):
        px = cx - w / 2 + (i + 0.5) * w / 6
        ax.plot([px, px], [cy + h / 2, cy + h / 2 + 0.75 * s], color=COL["muted"], lw=0.65, zorder=3)
        ax.plot([px, px], [cy - h / 2 - 0.75 * s, cy - h / 2], color=COL["muted"], lw=0.65, zorder=3)
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                               boxstyle="round,pad=0.0,rounding_size=0.65",
                               facecolor=COL["blue_fill"], edgecolor=COL["blue"], lw=1.15, zorder=4))
    cols = [(-2.25, [-1.2, 0, 1.2]), (0, [-1.7, -0.55, 0.55, 1.7]), (2.25, [-1.2, 0, 1.2])]
    for (x1, ys1), (x2, ys2) in zip(cols[:-1], cols[1:]):
        for y1 in ys1:
            for y2 in ys2:
                ax.plot([cx + x1 * s, cx + x2 * s], [cy + y1 * s, cy + y2 * s],
                        color=COL["blue"], lw=0.35, alpha=0.55, zorder=5)
    for xx, ys in cols:
        for yy in ys:
            ax.add_patch(Circle((cx + xx * s, cy + yy * s), 0.35 * s,
                                facecolor="white", edgecolor=COL["blue"], lw=0.75, zorder=6))


def icon_observer(ax, cx, cy, s=1.0):
    ax.add_patch(FancyBboxPatch((cx - 3.6 * s, cy - 2.65 * s), 7.2 * s, 5.3 * s,
                               boxstyle="round,pad=0.0,rounding_size=0.7",
                               facecolor=COL["teal_fill"], edgecolor=COL["teal"], lw=1.15, zorder=4))
    ax.add_patch(Circle((cx - 0.65 * s, cy + 0.15 * s), 1.45 * s,
                        facecolor="white", edgecolor=COL["teal"], lw=0.95, zorder=5))
    ax.plot([cx - 0.65 * s, cx + 0.25 * s], [cy + 0.15 * s, cy + 1.05 * s],
            color=COL["teal"], lw=1.0, zorder=6)
    for j in range(3):
        ax.add_patch(Rectangle((cx + 1.25 * s, cy + (0.9 - 0.9 * j) * s),
                               (1.45 - 0.3 * j) * s, 0.28 * s,
                               facecolor=COL["teal"], edgecolor="none", zorder=6))


def icon_fusion(ax, cx, cy, s=1.0):
    ax.add_patch(FancyBboxPatch((cx - 4.2 * s, cy - 2.8 * s), 8.4 * s, 5.6 * s,
                               boxstyle="round,pad=0.0,rounding_size=0.8",
                               facecolor=COL["navy_fill"], edgecolor=COL["navy"], lw=1.25, zorder=4))
    # Primary blue lane and smaller auxiliary teal correction.
    arrow(ax, (cx - 3.1 * s, cy + 0.65 * s), (cx + 2.8 * s, cy + 0.65 * s),
          color=COL["blue"], lw=1.25, scale=8, z=6)
    arrow(ax, (cx - 2.6 * s, cy - 1.05 * s), (cx - 0.25 * s, cy - 0.1 * s),
          color=COL["teal"], lw=1.0, scale=7, z=6)
    ax.add_patch(Circle((cx, cy + 0.65 * s), 0.58 * s, facecolor="white",
                        edgecolor=COL["navy"], lw=0.85, zorder=7))
    text(ax, cx, cy + 0.65 * s, "+", size=6.5, color=COL["navy"], weight="bold")
    # Gate / fallback mark.
    ax.add_patch(Rectangle((cx + 1.1 * s, cy - 1.5 * s), 1.65 * s, 0.55 * s,
                           facecolor=COL["red"], edgecolor="none", zorder=6))
    text(ax, cx + 1.9 * s, cy - 1.22 * s, "gate", size=3.9, color="white", weight="bold")


def icon_conditioner(ax, cx, cy, s=1.0):
    shield = Polygon(
        [(cx, cy + 2.6 * s), (cx + 2.65 * s, cy + 1.7 * s), (cx + 2.15 * s, cy - 1.25 * s),
         (cx, cy - 2.8 * s), (cx - 2.15 * s, cy - 1.25 * s), (cx - 2.65 * s, cy + 1.7 * s)],
        closed=True,
        facecolor="#F4F7F9",
        edgecolor=COL["navy"],
        lw=1.1,
        zorder=4,
    )
    ax.add_patch(shield)
    ax.plot([cx - 1.25 * s, cx - 0.25 * s, cx + 0.55 * s, cx + 1.35 * s],
            [cy - 0.5 * s, cy - 0.5 * s, cy + 0.75 * s, cy + 0.75 * s],
            color=COL["navy"], lw=1.05, zorder=6)
    ax.add_patch(Arc((cx, cy), 3.6 * s, 3.6 * s, theta1=205, theta2=335,
                     color=COL["orange"], lw=0.9, zorder=6))


def icon_controller(ax, cx, cy, s=1.0):
    w, h = 9.2 * s, 6.6 * s
    for i in range(7):
        px = cx - w / 2 + 0.75 * s + i * (w - 1.5 * s) / 6
        ax.add_patch(Rectangle((px - 0.28 * s, cy + h / 2), 0.56 * s, 0.85 * s,
                               facecolor="#C9CDD0", edgecolor=COL["muted"], lw=0.35, zorder=3))
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                               boxstyle="round,pad=0.0,rounding_size=0.7",
                               facecolor=COL["orange_fill"], edgecolor=COL["orange"], lw=1.25, zorder=4))
    tags = [("model", -2.8, 1.4), ("$d$", 0, 1.4), ("$F_{eq}$", 2.8, 1.4),
            ("$Q,R$", -1.7, -1.1), ("bounds", 1.7, -1.1)]
    for label, dx, dy in tags:
        ax.add_patch(FancyBboxPatch((cx + dx * s - 1.1 * s, cy + dy * s - 0.55 * s),
                                   2.2 * s, 1.1 * s, boxstyle="round,pad=0.02,rounding_size=0.25",
                                   facecolor="white", edgecolor="#B8872D", lw=0.55, zorder=5))
        text(ax, cx + dx * s, cy + dy * s, label, size=4.15, color="#7A5310", weight="bold")


def icon_route(ax, cx, cy, s=1.0):
    xs = [cx - 3.0 * s, cx - 1.9 * s, cx - 0.6 * s, cx + 0.8 * s, cx + 2.8 * s]
    ys = [cy - 1.5 * s, cy + 0.6 * s, cy + 1.15 * s, cy - 0.9 * s, cy + 1.3 * s]
    ax.plot(xs, ys, color=COL["green"], lw=1.8, zorder=5)
    for x, y in zip(xs, ys):
        ax.add_patch(Circle((x, y), 0.24 * s, facecolor="white", edgecolor=COL["green"], lw=0.8, zorder=6))
    arrow(ax, (cx + 1.7 * s, cy + 0.15 * s), (cx + 2.8 * s, cy + 1.3 * s),
          color=COL["green"], lw=1.0, scale=7, z=7)


def icon_agv(ax, cx, cy, s=1.0):
    # Top-view dual-steering AGV with active LF and RR highlighted.
    w, h = 7.0 * s, 5.1 * s
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                               boxstyle="round,pad=0.0,rounding_size=0.75",
                               facecolor="#ECEEEF", edgecolor=COL["line"], lw=1.0, zorder=4))
    wheel_specs = [(-2.3, 2.7, 22, True), (2.3, 2.7, 0, False), (-2.3, -2.7, 0, False), (2.3, -2.7, 22, True)]
    for dx, dy, ang, active in wheel_specs:
        r = Rectangle((cx + dx * s - 0.85 * s, cy + dy * s - 0.3 * s), 1.7 * s, 0.6 * s,
                      facecolor=COL["orange"] if active else COL["ink"], edgecolor="none", zorder=6)
        r.set_transform(Affine2D().rotate_deg_around(cx + dx * s, cy + dy * s, ang) + ax.transData)
        ax.add_patch(r)
    arrow(ax, (cx - 1.9 * s, cy), (cx + 2.25 * s, cy), color=COL["line"], lw=1.1, scale=9, z=7)
    text(ax, cx - 2.65 * s, cy + 1.75 * s, "LF", size=4.0, color="#8A5B0A", weight="bold")
    text(ax, cx + 2.55 * s, cy - 1.75 * s, "RR", size=4.0, color="#8A5B0A", weight="bold")


def callout(ax, x, y, w, h, title, lines, color):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                               boxstyle="round,pad=0.12,rounding_size=0.65",
                               facecolor="white", edgecolor=color, lw=0.9, zorder=10,
                               path_effects=[pe.SimplePatchShadow(offset=(0.35, -0.35), alpha=0.10), pe.Normal()]))
    text(ax, x + 1.0, y + h - 1.1, title, size=5.0, color=color, weight="bold", ha="left")
    for i, line in enumerate(lines):
        text(ax, x + 1.0, y + h - 2.35 - i * 1.05, line, size=4.45, color=COL["muted"], ha="left")


def main() -> None:
    setup_style()
    OUT.mkdir(parents=True, exist_ok=True)

    fig = plt.figure(figsize=(7.16, 4.72))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 66)
    ax.axis("off")

    # Layer framing inspired by the supplied example, with manuscript-specific content.
    band(ax, 1.2, 51.2, 97.6, 13.6, "OFFLINE PREPARATION AND DEPLOYMENT",
         "training/validation truth is not used online", dashed=True)
    band(ax, 1.2, 2.0, 97.6, 47.6, "ONLINE PERCEPTION → CONTROL LOOP",
         r"$T_s=0.01$ s · one update per control period", dashed=False)

    # -------------------- offline layer --------------------
    icon_dataset(ax, 8.4, 57.4, 0.78)
    text(ax, 8.4, 53.7, "102-run dataset", size=5.4, weight="bold")
    text(ax, 8.4, 52.5, "run-level train/validation split", size=4.4, color=COL["muted"])

    icon_model(ax, 23.0, 57.5, 0.78)
    text(ax, 23.0, 53.7, "Nonlinear AGV model", size=5.4, weight="bold")
    text(ax, 23.0, 52.5, "implemented discrete transition", size=4.4, color=COL["muted"])

    icon_workstation(ax, 39.0, 57.6, 0.78)
    text(ax, 39.0, 53.5, "Train · calibrate · linearize", size=5.4, weight="bold")

    arrow(ax, (12.5, 57.6), (34.3, 57.6), color=COL["offline"], lw=1.15, scale=9)
    arrow(ax, (27.2, 57.6), (34.3, 57.6), color=COL["offline"], lw=1.15, scale=9)

    artifact_tag(ax, 57.2, 57.6, 12.0, "Weights + stats", "ModernTCN deployment", COL["blue"])
    artifact_tag(ax, 72.2, 57.6, 12.0, "Error moments", r"$P_M, P_O, C$ by regime", COL["navy"])
    artifact_tag(ax, 88.1, 57.6, 13.5, "LPV database", "4125 local models", COL["orange"])
    ax.plot([43.6, 94.0], [61.0, 61.0], color=COL["offline"], lw=1.0, zorder=2)
    arrow(ax, (43.6, 57.8), (43.6, 61.0), color=COL["offline"], lw=1.0, scale=7, z=2)
    for x in (57.2, 72.2, 88.1):
        arrow(ax, (x, 61.0), (x, 59.9), color=COL["offline"], lw=1.0, scale=7, z=2)

    # -------------------- online layer: sensing and branches --------------------
    icon_sensor_bus(ax, 8.5, 27.3, 0.90)

    icon_delta_bank(ax, 22.0, 36.7, 0.76)
    module_card(ax, 22.0, 37.1, 9.2, 8.1, "22-D features\n+ delta bank",
                r"normalized $[z,\Delta_1,\Delta_2,\Delta_4]$", COL["blue"], section="III-B/C")

    icon_network_chip(ax, 38.0, 36.7, 0.82)
    module_card(ax, 38.0, 37.1, 9.6, 8.1, "Lightweight\nModernTCN",
                "history-only $128\\times88$\ngrade estimator", COL["blue"], section="III-A")

    icon_observer(ax, 38.0, 19.7, 0.84)
    module_card(ax, 38.0, 20.1, 9.6, 7.6, "Qualified observer",
                "bias-compensated\nsix-axis IMU", COL["teal"], section="III-D")

    icon_fusion(ax, 54.6, 28.1, 0.86)
    module_card(ax, 54.6, 28.5, 10.5, 8.4, "Uncertainty-adaptive\nfusion",
                "primary + qualified correction", COL["navy"], section="III-D")
    callout(ax, 49.8, 13.4, 10.0, 7.1, "ASYMMETRIC FUSION",
            ["innovation/NIS gate", r"bounded $\pm0.5^\circ$ correction", "exact fallback to ModernTCN"], COL["navy"])

    icon_conditioner(ax, 68.2, 28.5, 0.88)
    text(ax, 68.2, 23.8, "Grade conditioning", size=6.2, weight="bold")
    text(ax, 68.2, 22.4, r"deadband · clip $\pm10^\circ$ · causal filter", size=4.75, color=COL["muted"])

    icon_controller(ax, 82.2, 28.1, 0.84)
    module_card(ax, 82.2, 28.5, 10.8, 8.7, "Fused-grade-scheduled\nLPV-MPC",
                "$\\rho=[v,\\omega,\\theta^{sch}]$\n$N_p=150$, $N_c=30$", COL["orange"], section="III-E")

    icon_route(ax, 81.9, 42.9, 0.82)
    text(ax, 81.9, 46.3, "Reference path and motion", size=5.3, weight="bold", color=COL["green"])

    icon_agv(ax, 94.0, 28.5, 0.88)
    text(ax, 94.0, 22.3, "AGV plant", size=6.1, weight="bold")
    text(ax, 94.0, 20.9, "dual-steering-wheel", size=4.45, color=COL["muted"])

    # Online signal flow.
    arrow(ax, (11.7, 31.1), (17.3, 37.1), color=COL["blue"], lw=1.55, scale=10)
    text(ax, 14.0, 35.8, "vehicle responses", size=4.75, color=COL["blue"], weight="bold")
    text(ax, 14.0, 34.6, r"$\omega_g,\omega_w,I,\delta$ + derived", size=4.35, color=COL["muted"])

    arrow(ax, (26.7, 37.1), (33.2, 37.1), color=COL["blue"], lw=1.55, scale=10)
    text(ax, 29.9, 38.7, r"$128\times88$ history", size=4.65, color=COL["blue"], weight="bold")

    poly_arrow(ax, [(42.9, 37.1), (45.8, 37.1), (45.8, 31.0), (49.5, 31.0)], color=COL["blue"], lw=1.65, scale=10)
    text(ax, 46.8, 38.6, "primary grade + confidence", size=4.65, color=COL["blue"], weight="bold")
    text(ax, 46.8, 37.3, r"$\hat\theta^{MTCN}, c^{main}$", size=4.6, color=COL["blue"])

    arrow(ax, (11.7, 23.4), (33.2, 20.1), color=COL["teal"], lw=1.55, scale=10)
    text(ax, 20.2, 21.0, "bias-compensated six-axis packet", size=4.65, color=COL["teal"], weight="bold")
    arrow(ax, (42.9, 20.1), (49.5, 26.0), color=COL["teal"], lw=1.55, scale=10)
    text(ax, 46.4, 22.0, "auxiliary grade + quality", size=4.55, color=COL["teal"], weight="bold")
    text(ax, 46.4, 20.8, r"$\hat\theta^{obs}, q_{obs}$", size=4.55, color=COL["teal"])

    arrow(ax, (60.0, 28.5), (65.4, 28.5), color=COL["navy"], lw=1.75, scale=11)
    text(ax, 62.7, 30.1, r"$\hat\theta^{fus}$", size=5.1, color=COL["navy"], weight="bold")
    arrow(ax, (70.8, 28.5), (76.8, 28.5), color=COL["navy"], lw=1.9, scale=11)
    text(ax, 73.8, 30.2, r"single scheduled grade $\theta^{sch}$", size=4.8, color=COL["navy"], weight="bold")

    arrow(ax, (81.9, 40.8), (82.2, 33.1), color=COL["green"], lw=1.45, scale=9)
    text(ax, 83.0, 37.2, r"$r^{ref}$", size=4.8, color=COL["green"], weight="bold", ha="left")

    arrow(ax, (87.7, 28.5), (90.2, 28.5), color=COL["orange"], lw=1.75, scale=11)
    text(ax, 89.0, 30.2, r"$u=[F_{cmd},\omega_{cmd}]$", size=4.55, color="#98600D", weight="bold")

    # Closed-loop feedback channel.
    poly_arrow(ax, [(94.0, 25.5), (94.0, 7.0), (8.5, 7.0), (8.5, 22.7)], color=COL["green"], lw=1.55, scale=10)
    text(ax, 51.0, 8.45, "applied command → plant response → onboard sensing", size=5.0,
         color=COL["green"], weight="bold")

    # Offline deployment arrows to the correct online consumers.
    poly_arrow(ax, [(57.2, 55.4), (57.2, 49.9), (38.0, 49.9), (38.0, 41.3)],
               color=COL["offline"], lw=1.15, dashed=True, scale=8, z=7)
    poly_arrow(ax, [(72.2, 55.4), (72.2, 48.9), (54.6, 48.9), (54.6, 33.0)],
               color=COL["offline"], lw=1.15, dashed=True, scale=8, z=7)
    poly_arrow(ax, [(88.1, 55.4), (88.1, 47.9), (84.0, 47.9), (84.0, 33.2)],
               color=COL["offline"], lw=1.15, dashed=True, scale=8, z=7)

    # Compact legend.
    yleg = 3.5
    ax.plot([26.0, 29.5], [yleg, yleg], color=COL["blue"], lw=1.6)
    text(ax, 30.3, yleg, "temporal primary", size=4.65, ha="left", color=COL["muted"])
    ax.plot([42.0, 45.5], [yleg, yleg], color=COL["teal"], lw=1.6)
    text(ax, 46.3, yleg, "observer auxiliary", size=4.65, ha="left", color=COL["muted"])
    ax.plot([58.2, 61.7], [yleg, yleg], color=COL["offline"], lw=1.4, ls=(0, (4, 2.5)))
    text(ax, 62.5, yleg, "offline deployment", size=4.65, ha="left", color=COL["muted"])

    fig.savefig(OUT / "fig02_framework_redesign.svg", bbox_inches="tight", pad_inches=0.025)
    fig.savefig(OUT / "fig02_framework_redesign.pdf", bbox_inches="tight", pad_inches=0.025)
    fig.savefig(OUT / "fig02_framework_redesign.png", dpi=600, bbox_inches="tight", pad_inches=0.025)
    plt.close(fig)
    print(f"saved: {OUT / 'fig02_framework_redesign.svg'}")
    print(f"saved: {OUT / 'fig02_framework_redesign.pdf'}")
    print(f"saved: {OUT / 'fig02_framework_redesign.png'}")


if __name__ == "__main__":
    main()
