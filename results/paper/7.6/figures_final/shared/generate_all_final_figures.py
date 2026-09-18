from __future__ import annotations

from final_figure_pipeline import CONTRACTS, run_figure


def main() -> None:
    for figure_key in CONTRACTS:
        result = run_figure(figure_key)
        print(f"{result['figure_id']}: {result['automatic_qa']['status']}")


if __name__ == "__main__":
    main()
