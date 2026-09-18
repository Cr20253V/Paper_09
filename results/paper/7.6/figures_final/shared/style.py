"""Shared publication style for the manuscript figures."""

from __future__ import annotations

import matplotlib.pyplot as plt


PALETTE = {
    "truth": "#222222",
    "fusion": "#0F4C81",
    "mtcn": "#4C78A8",
    "imu": "#2A9D8F",
    "zero_slope": "#8A8A8A",
    "oracle": "#D28E2B",
    "gru": "#C07A2D",
    "tcn": "#8064A2",
    "warning": "#B24A47",
    "start": "#2A7F74",
    "end": "#C62828",
    "direction": "#1565C0",
    "invalid": "#D9D9D9",
    "grid": "#E6E6E6",
}


def apply_publication_style() -> None:
    """Apply the fixed journal-width style before creating a figure."""
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = [
        "Arial",
        "Helvetica",
        "DejaVu Sans",
        "Liberation Sans",
    ]
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42
    plt.rcParams["font.size"] = 7.0
    plt.rcParams["axes.labelsize"] = 7.0
    plt.rcParams["axes.titlesize"] = 7.0
    plt.rcParams["axes.linewidth"] = 0.65
    plt.rcParams["axes.spines.right"] = False
    plt.rcParams["axes.spines.top"] = False
    plt.rcParams["xtick.labelsize"] = 6.2
    plt.rcParams["ytick.labelsize"] = 6.2
    plt.rcParams["xtick.major.width"] = 0.6
    plt.rcParams["ytick.major.width"] = 0.6
    plt.rcParams["xtick.major.size"] = 2.4
    plt.rcParams["ytick.major.size"] = 2.4
    plt.rcParams["legend.frameon"] = False
    plt.rcParams["lines.solid_capstyle"] = "round"
    plt.rcParams["savefig.facecolor"] = "white"
    plt.rcParams["figure.facecolor"] = "white"


def add_panel_label(ax, label: str, *, x: float = -0.16, y: float = 1.02) -> None:
    """Add a compact panel label at the upper-left of an axes."""
    ax.text(
        x,
        y,
        label,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=8.0,
        fontweight="bold",
        color=PALETTE["truth"],
        clip_on=False,
    )
