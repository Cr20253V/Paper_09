"""Publication schematic for the fused-slope LPV-MPC method section.

The drawing is intentionally code-native and schematic-led. It exposes the
offline discrete-model construction and the online synchronized update paths
without inventing a fusion-network architecture that is still under study.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Polygon, Circle

# Mandatory editable-text configuration for the Python figure track.
plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans", "Liberation Sans"]
plt.rcParams["svg.fonttype"] = "none"
plt.rcParams["pdf.fonttype"] = 42
plt.rcParams["font.size"] = 7.0
plt.rcParams["axes.linewidth"] = 0.7
plt.rcParams["axes.spines.right"] = False
plt.rcParams["axes.spines.top"] = False
plt.rcParams["legend.frameon"] = False


INK = "#273746"
MUTED = "#637381"
GRID = "#D9E0E5"
BLUE = "#486A91"
BLUE_FILL = "#E5EDF5"
TEAL = "#3B817D"
TEAL_FILL = "#E2F0EE"
AMBER = "#A56F2A"
AMBER_FILL = "#F6EDDE"
ROSE = "#9B5A62"
ROSE_FILL = "#F5E7E8"
PURPLE = "#756B98"
PURPLE_FILL = "#ECE9F4"
NEUTRAL_FILL = "#F4F6F7"
WHITE = "#FFFFFF"


def add_box(ax, xy, width, height, text, edge=INK, face=WHITE,
            fontsize=6.5, lw=0.9, radius=0.025, text_color=INK,
            zorder=3):
    x, y = xy
    patch = FancyBboxPatch(
        (x, y), width, height,
        boxstyle=f"round,pad=0.012,rounding_size={radius}",
        linewidth=lw, edgecolor=edge, facecolor=face, zorder=zorder,
    )
    ax.add_patch(patch)
    ax.text(x + width / 2, y + height / 2, text,
            ha="center", va="center", fontsize=fontsize,
            color=text_color, linespacing=1.15, zorder=zorder + 1)
    return patch


def add_arrow(ax, start, end, color=INK, lw=0.9, style="-|>",
              mutation_scale=9, linestyle="-"):
    arrow = FancyArrowPatch(
        start, end, arrowstyle=style, mutation_scale=mutation_scale,
        linewidth=lw, color=color, linestyle=linestyle,
        shrinkA=2, shrinkB=2, zorder=2,
    )
    ax.add_patch(arrow)
    return arrow


def add_panel_label(ax, label):
    ax.text(0.0, 1.02, label, transform=ax.transAxes, ha="left",
            va="bottom", fontsize=8.0, fontweight="bold", color=INK)


def panel_frame(ax):
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.patch.set_facecolor(WHITE)


def draw_offline(ax):
    panel_frame(ax)
    add_panel_label(ax, "a")

    add_box(ax, (0.03, 0.69), 0.27, 0.18,
            "continuous AGV\nmodel\n$\\dot{x}=f_c(x,u,\\theta)$",
            edge=AMBER, face=AMBER_FILL, fontsize=6.0)
    add_box(ax, (0.37, 0.69), 0.25, 0.18,
            "one-step map\nsteering + RK4\n$T_s=0.01$ s",
            edge=BLUE, face=BLUE_FILL, fontsize=6.0)
    add_box(ax, (0.69, 0.69), 0.27, 0.18,
            "error-state map\n$\\mathbf{x}^e=[e_y,e_\\psi,$\n$e_v,e_\\omega]^T$",
            edge=TEAL, face=TEAL_FILL, fontsize=6.0)
    add_arrow(ax, (0.30, 0.78), (0.37, 0.78), color=MUTED)
    add_arrow(ax, (0.62, 0.78), (0.69, 0.78), color=MUTED)

    add_box(ax, (0.17, 0.39), 0.30, 0.16,
            "finite-difference\nJacobians\n$A_d\\in\\mathbb{R}^{4\\times4}$,\n$B_d\\in\\mathbb{R}^{4\\times2}$",
            edge=PURPLE, face=PURPLE_FILL, fontsize=6.0)
    add_box(ax, (0.55, 0.39), 0.30, 0.16,
            "$E_d\\in\\mathbb{R}^{4\\times1}$,\n$C_d=I_4$, $D_d=0$\n(discrete model)",
            edge=PURPLE, face=PURPLE_FILL, fontsize=6.0)
    add_arrow(ax, (0.82, 0.69), (0.67, 0.55), color=PURPLE)
    add_arrow(ax, (0.47, 0.39), (0.55, 0.47), color=PURPLE)

    add_box(ax, (0.26, 0.09), 0.48, 0.15,
            "offline LPV database\n$11\\times15\\times25=4125$\n$\\rho=[v,\\omega,\\theta]^T$",
            edge=BLUE, face=BLUE_FILL, lw=1.1, fontsize=6.0)
    add_arrow(ax, (0.40, 0.39), (0.40, 0.24), color=BLUE)
    add_arrow(ax, (0.68, 0.39), (0.60, 0.24), color=BLUE)


def draw_cube(ax, origin=(0.47, 0.43), scale=0.24):
    """Draw a compact 3-D LPV cell in normalized panel coordinates."""
    ox, oy = origin
    s = scale
    dx, dy = s * 0.74, s * 0.42
    # front and back square corners
    f = [(ox, oy), (ox + s, oy), (ox + s, oy + s), (ox, oy + s)]
    b = [(ox + dx, oy + dy), (ox + s + dx, oy + dy),
         (ox + s + dx, oy + s + dy), (ox + dx, oy + s + dy)]
    ax.add_patch(Polygon(f, closed=True, facecolor=TEAL_FILL,
                         edgecolor=TEAL, linewidth=0.8, zorder=1))
    ax.add_patch(Polygon(b, closed=True, facecolor=BLUE_FILL,
                         edgecolor=BLUE, linewidth=0.8, zorder=1))
    for i in range(4):
        ax.plot([f[i][0], b[i][0]], [f[i][1], b[i][1]],
                color=BLUE, linewidth=0.7, zorder=1)
    # Eight vertices and a current point inside the cell.
    points = f + b
    for px, py in points:
        ax.add_patch(Circle((px, py), radius=0.012, facecolor=WHITE,
                            edgecolor=INK, linewidth=0.6, zorder=3))
    current = (ox + 0.48 * s + 0.35 * dx, oy + 0.53 * s + 0.35 * dy)
    ax.add_patch(Circle(current, radius=0.018, facecolor=ROSE,
                        edgecolor=WHITE, linewidth=0.8, zorder=4))
    ax.text(current[0] + 0.03, current[1] + 0.02,
            r"$\rho_k$", fontsize=6.5, color=ROSE, zorder=5)
    # Axes labels.
    ax.annotate("$v$", xy=(ox + s + dx + 0.025, oy + dy - 0.01),
                xytext=(ox + s + dx + 0.025, oy + dy - 0.01),
                fontsize=6.2, color=INK)
    ax.annotate(r"$\omega$", xy=(ox - 0.04, oy + s + 0.02),
                xytext=(ox - 0.04, oy + s + 0.02), fontsize=6.2, color=INK)
    ax.annotate(r"$\theta$", xy=(ox + dx + 0.03, oy + s + dy + 0.02),
                xytext=(ox + dx + 0.03, oy + s + dy + 0.02),
                fontsize=6.2, color=INK)


def draw_online(ax):
    panel_frame(ax)
    add_panel_label(ax, "b")

    add_box(ax, (0.03, 0.72), 0.20, 0.15,
            "ModernTCN\n$\\hat{\\theta}^{TCN}_k$", edge=BLUE,
            face=BLUE_FILL, fontsize=6.0)
    add_box(ax, (0.03, 0.49), 0.20, 0.15,
            "causal IMU\n$\\hat{\\theta}^{IMU}_k$", edge=TEAL,
            face=TEAL_FILL, fontsize=6.0)
    add_box(ax, (0.29, 0.57), 0.21, 0.22,
            "fusion interface\n(innovation 3)\n$\\hat{\\theta}^{fus}_k$",
            edge=ROSE, face=ROSE_FILL, lw=1.1, fontsize=6.0)
    add_arrow(ax, (0.23, 0.79), (0.29, 0.69), color=BLUE)
    add_arrow(ax, (0.23, 0.57), (0.29, 0.65), color=TEAL)
    add_box(ax, (0.56, 0.59), 0.19, 0.18,
            "conditioning\nRhoFilter\n$\\theta_k^{sch}$",
            edge=AMBER, face=AMBER_FILL, fontsize=6.0)
    add_arrow(ax, (0.50, 0.68), (0.56, 0.68), color=ROSE)
    add_box(ax, (0.80, 0.59), 0.17, 0.18,
            "$\\rho_k=[v_f,\\omega_f,$\n$\\theta_k^{sch}]^T$",
            edge=BLUE, face=BLUE_FILL, fontsize=5.7)
    add_arrow(ax, (0.75, 0.68), (0.80, 0.68), color=AMBER)

    draw_cube(ax, origin=(0.47, 0.14), scale=0.22)
    add_box(ax, (0.76, 0.13), 0.20, 0.16,
            "8-vertex\ninterpolation\n$A_d,B_d,C_d,D_d,E_d$",
            edge=PURPLE, face=PURPLE_FILL, fontsize=5.7)
    add_arrow(ax, (0.88, 0.59), (0.74, 0.36), color=BLUE)
    add_arrow(ax, (0.69, 0.28), (0.76, 0.21), color=PURPLE)
    ax.text(0.50, 0.06, "same synchronized slope value", fontsize=6.1,
            color=ROSE, ha="center", va="center")


def draw_controller(ax):
    panel_frame(ax)
    add_panel_label(ax, "c")

    add_box(ax, (0.03, 0.68), 0.27, 0.17,
            "local model\n$A_d,B_d,C_d,D_d,E_d$",
            edge=BLUE, face=BLUE_FILL, fontsize=6.0)
    add_box(ax, (0.03, 0.43), 0.27, 0.17,
            "MD input\n$\\Delta\\theta_k$",
            edge=ROSE, face=ROSE_FILL, fontsize=6.0)
    add_box(ax, (0.03, 0.18), 0.27, 0.17,
            "feedforward + maps\n$F_{eq}$, $Q_k,R_k,\\Delta R_k$\n$u_{min},u_{max}$",
            edge=AMBER, face=AMBER_FILL, fontsize=5.8)
    add_box(ax, (0.39, 0.45), 0.25, 0.22,
            "constrained LPV-MPC\n$N_p=150$, $N_c=30$\nQP in $\\Delta u$",
            edge=PURPLE, face=PURPLE_FILL, lw=1.1, fontsize=6.0)
    for y in (0.765, 0.515, 0.265):
        add_arrow(ax, (0.30, y), (0.39, 0.56), color=MUTED)
    add_box(ax, (0.73, 0.45), 0.22, 0.22,
            "first command\n$F_{cmd},\\omega_{cmd}$",
            edge=TEAL, face=TEAL_FILL, fontsize=6.0)
    add_arrow(ax, (0.64, 0.56), (0.73, 0.56), color=PURPLE)
    add_box(ax, (0.73, 0.12), 0.22, 0.16,
            "nonlinear AGV\nstate + sensors",
            edge=BLUE, face=BLUE_FILL, fontsize=6.0)
    add_arrow(ax, (0.84, 0.45), (0.84, 0.28), color=TEAL)
    add_arrow(ax, (0.73, 0.20), (0.30, 0.14), color=ROSE,
              linestyle="--")
    ax.text(0.51, 0.08, "causal feedback to the next sample", fontsize=6.0,
            color=MUTED, ha="center", va="center")


def main():
    out_dir = Path(__file__).resolve().parents[2] / "Latex"
    out_dir.mkdir(parents=True, exist_ok=True)
    base = out_dir / "fig_fused_slope_lpv_mpc"

    fig = plt.figure(figsize=(7.22, 3.55), facecolor=WHITE)
    gs = fig.add_gridspec(1, 3, width_ratios=[1.02, 1.05, 1.02],
                          left=0.018, right=0.985, bottom=0.07,
                          top=0.91, wspace=0.08)
    draw_offline(fig.add_subplot(gs[0, 0]))
    draw_online(fig.add_subplot(gs[0, 1]))
    draw_controller(fig.add_subplot(gs[0, 2]))

    fig.savefig(str(base) + ".svg", bbox_inches="tight", pad_inches=0.04)
    fig.savefig(str(base) + ".pdf", bbox_inches="tight", pad_inches=0.04)
    fig.savefig(str(base) + ".tiff", dpi=600, bbox_inches="tight", pad_inches=0.04)
    fig.savefig(str(base) + ".png", dpi=300, bbox_inches="tight", pad_inches=0.04)
    plt.close(fig)

    # Lightweight backend-local QA: verify nonblank raster and editable SVG text.
    from PIL import Image

    image = Image.open(str(base) + ".png").convert("RGB")
    pixels = list(image.getdata())
    nonwhite = sum(1 for p in pixels if min(p) < 245)
    ratio = nonwhite / max(1, len(pixels))
    svg_text = Path(str(base) + ".svg").read_text(encoding="utf-8")
    text_nodes = svg_text.count("<text")
    qa = (f"png_size={image.size}\n"
          f"nonwhite_ratio={ratio:.4f}\n"
          f"svg_text_nodes={text_nodes}\n")
    (base.parent / "fig_fused_slope_lpv_mpc_qa.txt").write_text(qa, encoding="utf-8")
    if ratio < 0.03 or text_nodes < 10:
        raise RuntimeError("Figure QA failed: blank raster or missing editable text")


if __name__ == "__main__":
    main()
