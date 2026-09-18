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
            "font.size": 7.0,
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
    text(ax, x + w - 2.0, y + h - 1.5, subtitle, size=5.6, color=COL["muted"], ha="right",
         bbox=dict(boxstyle="round,pad=0.10", facecolor="white", edgecolor="none", alpha=0.97))


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


def icon_sensor_bus(ax, cx, cy, s=1.0, *, show_labels=True):
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
    if show_labels:
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
        text(ax, cx + dx * s, cy + dy * s, label, size=max(2.9, 4.5 * s),
             color="#7A5310", weight="bold")


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
    # The vehicle points right: active steering wheels are left-front
    # (top-right) and right-rear (bottom-left) in this top-view convention.
    wheel_specs = [(-2.3, 2.7, 0, False), (2.3, 2.7, 22, True),
                   (-2.3, -2.7, 22, True), (2.3, -2.7, 0, False)]
    for dx, dy, ang, active in wheel_specs:
        r = Rectangle((cx + dx * s - 0.85 * s, cy + dy * s - 0.3 * s), 1.7 * s, 0.6 * s,
                      facecolor=COL["orange"] if active else COL["ink"], edgecolor="none", zorder=6)
        r.set_transform(Affine2D().rotate_deg_around(cx + dx * s, cy + dy * s, ang) + ax.transData)
        ax.add_patch(r)
    arrow(ax, (cx - 1.9 * s, cy), (cx + 2.25 * s, cy), color=COL["line"], lw=1.1, scale=9, z=7)
    text(ax, cx + 2.65 * s, cy + 1.75 * s, "LF", size=4.2, color="#8A5B0A", weight="bold")
    text(ax, cx - 2.55 * s, cy - 1.75 * s, "RR", size=4.2, color="#8A5B0A", weight="bold")


def callout(ax, x, y, w, h, title, lines, color):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                               boxstyle="round,pad=0.12,rounding_size=0.65",
                               facecolor="white", edgecolor=color, lw=0.9, zorder=10,
                               path_effects=[pe.SimplePatchShadow(offset=(0.35, -0.35), alpha=0.10), pe.Normal()]))
    text(ax, x + 1.0, y + h - 1.1, title, size=5.0, color=color, weight="bold", ha="left")
    for i, line in enumerate(lines):
        text(ax, x + 1.0, y + h - 2.35 - i * 1.05, line, size=4.45, color=COL["muted"], ha="left")


def tile(ax, cx, cy, w, h, title, subtitle, color, *, frame=True):
    """Module card with reserved header, icon, and footer zones."""
    if frame:
        ax.add_patch(FancyBboxPatch(
            (cx - w / 2, cy - h / 2), w, h,
            boxstyle="round,pad=0.0,rounding_size=0.75",
            facecolor="white", edgecolor=color, linewidth=1.15, zorder=3))
        ax.plot([cx - w / 2 + 0.55, cx + w / 2 - 0.55],
                [cy + h / 2 - 1.8, cy + h / 2 - 1.8],
                color=color, lw=0.45, alpha=0.4, zorder=7)
    title_lines = str(title).split("\n")
    for i, line in enumerate(title_lines):
        text(ax, cx, cy + h / 2 - 0.72 - i * 0.72, line,
             size=5.05, weight="bold", z=9)
    if subtitle:
        text(ax, cx, cy - h / 2 + 0.72, subtitle, size=4.05,
             color=COL["muted"], z=9)


def compact_artifact(ax, cx, cy, w, title, subtitle, color, letter):
    """Compact offline artifact card sized to contain both text lines."""
    h = 4.8
    ax.add_patch(FancyBboxPatch(
        (cx - w / 2, cy - h / 2), w, h,
        boxstyle="round,pad=0.0,rounding_size=0.65",
        facecolor="white", edgecolor=color, lw=1.05, zorder=4))
    ax.add_patch(Circle((cx - w / 2 + 1.6, cy), 0.68,
                        facecolor=color, edgecolor="none", zorder=5))
    text(ax, cx - w / 2 + 1.6, cy, letter, size=4.8,
         color="white", weight="bold")
    text(ax, cx - w / 2 + 2.75, cy + 0.68, title,
         size=5.0, weight="bold", ha="left")
    text(ax, cx - w / 2 + 2.75, cy - 0.68, subtitle,
         size=4.1, color=COL["muted"], ha="left")


def signal_tag(ax, x, y, label, color, *, ha="center", rotation=0):
    """Concise signal label placed only beside its corresponding line."""
    text(ax, x, y, label, size=4.2, color=color, weight="bold", ha=ha, z=30,
         rotation=rotation,
         bbox=dict(boxstyle="round,pad=0.12", facecolor="white",
                   edgecolor="none", alpha=0.97))


def floating_module(ax, cx, cy, title, subtitle, color, icon_fn, *, icon_scale=0.55,
                    title_y=3.7, subtitle_y=-3.4):
    """Icon-led module without a surrounding card."""
    icon_fn(ax, cx, cy, icon_scale)
    text(ax, cx, cy + title_y, title, size=5.2, weight="bold", color=color)
    if subtitle:
        text(ax, cx, cy + subtitle_y, subtitle, size=4.0, color=COL["muted"])


def main() -> None:
    setup_style()
    OUT.mkdir(parents=True, exist_ok=True)

    fig = plt.figure(figsize=(7.16, 4.35))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 60)
    ax.axis("off")

    # Two-row offline preparation above a compact, orthogonal online loop.
    band(ax, 1.2, 40.8, 97.6, 17.8, "OFFLINE PREPARATION AND DEPLOYMENT",
         "training/validation truth is not used online", dashed=True)
    band(ax, 1.2, 1.3, 97.6, 38.0, "ONLINE PERCEPTION → CONTROL LOOP",
         r"$T_s=0.01$ s · one update per control period", dashed=False)

    # -------------------- offline layer: two aligned rows --------------------
    top_y = 52.3
    for cx, title, subtitle, color in [
        (17.0, "102-run dataset", "run-level train/validation split", COL["blue"]),
        (50.0, "Nonlinear AGV model", "implemented discrete transition", COL["line"]),
        (83.0, "Train · calibrate · linearize", "offline identification pipeline", COL["navy"]),
    ]:
        tile(ax, cx, top_y, 22.0, 6.6, title, subtitle, color)
    icon_dataset(ax, 17.0, 51.8, 0.47)
    icon_model(ax, 50.0, 51.8, 0.47)
    icon_workstation(ax, 83.0, 51.8, 0.47)

    arrow(ax, (28.0, top_y), (39.0, top_y), color=COL["offline"], lw=1.0, scale=8)
    arrow(ax, (61.0, top_y), (72.0, top_y), color=COL["offline"], lw=1.0, scale=8)

    art_y = 44.1
    compact_artifact(ax, 17.0, art_y, 22.0, "Weights + stats", "ModernTCN deployment", COL["blue"], "W")
    compact_artifact(ax, 50.0, art_y, 22.0, "Error moments", r"$P_M, P_O, C$ by regime", COL["navy"], "E")
    compact_artifact(ax, 83.0, art_y, 22.0, "LPV database", "4125 local models", COL["orange"], "L")

    # One orthogonal output bus from the offline pipeline to the three artifacts.
    ax.plot([17.0, 83.0], [48.3, 48.3], color=COL["offline"], lw=0.95, zorder=2)
    ax.plot([83.0, 83.0], [49.0, 48.3], color=COL["offline"], lw=0.95, zorder=2)
    for x in (17.0, 50.0, 83.0):
        arrow(ax, (x, 48.3), (x, 46.5), color=COL["offline"], lw=0.95, scale=7, z=2)

    # -------------------- online layer: compact orthogonal graph --------------------
    floating_module(
        ax, 8.0, 21.0, "Onboard sensing", "CAN · yaw · six-axis IMU", COL["line"],
        lambda a, x, y, s: icon_sensor_bus(a, x, y, s, show_labels=False),
        icon_scale=0.52, title_y=3.9, subtitle_y=-3.7)

    tile(ax, 22.0, 28.0, 11.8, 8.8, "22-D feature bank", r"$z,\Delta_1,\Delta_2,\Delta_4$", COL["blue"])
    icon_delta_bank(ax, 22.0, 27.8, 0.52)

    tile(ax, 37.0, 28.0, 11.8, 8.8, "Lightweight\nModernTCN", "grade + confidence", COL["blue"])
    icon_network_chip(ax, 37.0, 27.3, 0.52)

    tile(ax, 22.0, 14.0, 11.8, 8.2, "Qualified observer", "IMU · innovation qualification", COL["teal"])
    icon_observer(ax, 22.0, 14.0, 0.50)

    tile(ax, 52.5, 21.0, 11.8, 9.0, "Uncertainty-adaptive\nfusion", r"NIS gate · bounded $\pm0.5^\circ$", COL["navy"])
    icon_fusion(ax, 52.5, 20.2, 0.53)

    floating_module(ax, 65.5, 21.0, "Grade conditioning",
                    r"deadband · clip $\pm10^\circ$ · filter", COL["navy"],
                    icon_conditioner, icon_scale=0.72, title_y=3.9, subtitle_y=-3.7)

    tile(ax, 79.5, 21.0, 11.8, 9.0, "Fused-grade LPV-MPC", r"$\rho,d,F_{eq},Q/R,$ bounds", COL["orange"])
    icon_controller(ax, 79.5, 20.8, 0.67)

    floating_module(ax, 93.0, 21.0, "AGV plant", "dual-steering-wheel", COL["line"],
                    icon_agv, icon_scale=0.72, title_y=3.9, subtitle_y=-3.8)

    floating_module(ax, 79.5, 33.0, "Reference path", "motion command", COL["green"],
                    icon_route, icon_scale=0.60, title_y=3.7, subtitle_y=-2.8)

    # Sensor split: horizontal/vertical only.
    ax.plot([9.8, 14.7], [21.0, 21.0], color=COL["blue"], lw=1.45, zorder=8)
    ax.add_patch(Circle((14.7, 21.0), 0.18, facecolor=COL["blue"], edgecolor="white", lw=0.35, zorder=12))
    poly_arrow(ax, [(14.7, 21.0), (14.7, 28.0), (16.1, 28.0)], color=COL["blue"], lw=1.45, scale=9)
    signal_tag(ax, 13.8, 24.6, r"$z_k$", COL["blue"], rotation=90)
    poly_arrow(ax, [(14.7, 21.0), (14.7, 14.0), (16.1, 14.0)], color=COL["teal"], lw=1.45, scale=9)
    signal_tag(ax, 13.8, 17.5, "IMU", COL["teal"], rotation=90)

    arrow(ax, (27.9, 28.0), (31.1, 28.0), color=COL["blue"], lw=1.55, scale=9)
    signal_tag(ax, 29.5, 29.1, r"$X_{128\times88}$", COL["blue"])

    poly_arrow(ax, [(42.9, 28.0), (45.0, 28.0), (45.0, 22.5), (46.6, 22.5)],
               color=COL["blue"], lw=1.6, scale=9)
    signal_tag(ax, 44.3, 25.2, r"$\hat\theta^{M},c^{main}$", COL["blue"], ha="right")

    poly_arrow(ax, [(27.9, 14.0), (44.0, 14.0), (44.0, 19.3), (46.6, 19.3)],
               color=COL["teal"], lw=1.55, scale=9)
    signal_tag(ax, 35.8, 15.0, r"$\hat\theta^{obs},q_{obs}$", COL["teal"])

    arrow(ax, (58.4, 21.0), (63.6, 21.0), color=COL["navy"], lw=1.7, scale=9)
    signal_tag(ax, 60.9, 22.1, r"$\hat\theta^{fus}$", COL["navy"])

    arrow(ax, (67.4, 21.0), (73.6, 21.0), color=COL["navy"], lw=1.75, scale=9)
    signal_tag(ax, 70.5, 22.1, r"$\theta^{sch}$", COL["navy"])

    arrow(ax, (79.5, 31.3), (79.5, 25.5), color=COL["green"], lw=1.4, scale=8)
    signal_tag(ax, 80.3, 28.4, r"$r^{ref}$", COL["green"], ha="left")

    arrow(ax, (85.4, 21.0), (90.3, 21.0), color=COL["orange"], lw=1.7, scale=9)
    signal_tag(ax, 87.9, 22.1, r"$u_k$", "#98600D")

    # Orthogonal closed-loop feedback with a single return line.
    poly_arrow(ax, [(93.0, 19.1), (93.0, 5.7), (8.0, 5.7), (8.0, 17.3)],
               color=COL["green"], lw=1.5, scale=9)
    signal_tag(ax, 50.5, 6.8, r"$y_{k+1}$", COL["green"])

    # Offline deployment: one bend per consumer and no diagonal segments.
    poly_arrow(ax, [(17.0, 41.7), (17.0, 40.0), (37.0, 40.0), (37.0, 32.4)],
               color=COL["offline"], lw=1.0, dashed=True, scale=7, z=2)
    poly_arrow(ax, [(50.0, 41.7), (50.0, 39.8), (52.5, 39.8), (52.5, 25.5)],
               color=COL["offline"], lw=1.0, dashed=True, scale=7, z=2)
    poly_arrow(ax, [(83.0, 41.7), (83.0, 39.6), (82.0, 39.6), (82.0, 25.5)],
               color=COL["offline"], lw=1.0, dashed=True, scale=7, z=2)

    # Compact legend.
    yleg = 2.85
    ax.plot([27.0, 30.0], [yleg, yleg], color=COL["blue"], lw=1.5)
    text(ax, 30.7, yleg, "temporal primary", size=4.0, ha="left", color=COL["muted"])
    ax.plot([42.0, 45.0], [yleg, yleg], color=COL["teal"], lw=1.5)
    text(ax, 45.7, yleg, "observer auxiliary", size=4.0, ha="left", color=COL["muted"])
    ax.plot([57.5, 60.5], [yleg, yleg], color=COL["offline"], lw=1.35, ls=(0, (4, 2.5)))
    text(ax, 61.2, yleg, "offline deployment", size=4.0, ha="left", color=COL["muted"])

    fig.savefig(OUT / "fig02_framework_redesign.svg", bbox_inches="tight", pad_inches=0.025)
    fig.savefig(OUT / "fig02_framework_redesign.pdf", bbox_inches="tight", pad_inches=0.025)
    fig.savefig(OUT / "fig02_framework_redesign.png", dpi=600, bbox_inches="tight", pad_inches=0.025)
    plt.close(fig)
    print(f"saved: {OUT / 'fig02_framework_redesign.svg'}")
    print(f"saved: {OUT / 'fig02_framework_redesign.pdf'}")
    print(f"saved: {OUT / 'fig02_framework_redesign.png'}")


if __name__ == "__main__":
    main()
