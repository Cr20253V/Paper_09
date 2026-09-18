from pathlib import Path
import sys

shared = Path(__file__).resolve().parents[2] / "shared"
sys.path.insert(0, str(shared))
from final_figure_pipeline import run_figure

if __name__ == "__main__":
    run_figure("Fig08")
