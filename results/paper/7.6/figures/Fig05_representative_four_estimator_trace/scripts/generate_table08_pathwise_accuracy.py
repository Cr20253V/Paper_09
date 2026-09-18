from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from generate_fig05_representative_trace import (
    BENCHMARK_WARMUP_S,
    METHODS,
    find_project_root,
    matlab_prctile,
    read_compressed_timeseries,
)


CASE_METRICS_RELATIVE = Path(
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/"
    "01_A1_algorithm_comparison/04_closed_loop/closed_loop_case_metrics.csv"
)

PATHS = (
    ("p01_factory_logistics_showcase", "P1 Factory logistics"),
    ("p02_sharp_turn_transition", "P2 Sharp-turn transition"),
    ("p03_long_updown", "P3 Long up/down slope"),
    ("p04_soft_updown_straight_turn", "P4 Mild slope-turn coupling"),
    ("p05_factory_flat_logistics", "P5 Flat factory logistics"),
    ("p06_downhill_after_turn", "P6 Downhill recovery"),
)


def validate_inventory(cases: pd.DataFrame) -> None:
    required = {"method_id", "seed", "path_id", "raw_result_file", "theta_mae_deg"}
    missing = required.difference(cases.columns)
    if missing:
        raise ValueError(f"Missing case-metric columns: {sorted(missing)}")

    expected_methods = {str(method["id"]) for method in METHODS}
    expected_paths = {path_id for path_id, _ in PATHS}
    expected_seeds = {1, 7, 11, 21, 42, 73, 101, 202, 340, 520}
    if len(cases) != 240:
        raise ValueError(f"Expected 240 closed-loop rows, found {len(cases)}")
    if set(cases["method_id"]) != expected_methods:
        raise ValueError("Unexpected method inventory")
    if set(cases["path_id"]) != expected_paths:
        raise ValueError("Unexpected route inventory")
    if set(cases["seed"].astype(int)) != expected_seeds:
        raise ValueError("Unexpected seed inventory")
    counts = cases.groupby(["method_id", "path_id"]).size()
    if not counts.eq(10).all():
        raise ValueError("Every method-route cell must contain ten seeds")


def compute_case_metrics(cases: pd.DataFrame) -> tuple[pd.DataFrame, float]:
    method_labels = {str(method["id"]): str(method["label"]) for method in METHODS}
    path_labels = dict(PATHS)
    rows: list[dict[str, object]] = []
    maximum_mae_difference = 0.0

    for index, row in cases.iterrows():
        raw_path = Path(str(row["raw_result_file"]))
        if not raw_path.is_file():
            raise FileNotFoundError(raw_path)
        estimate_time, estimate_rad = read_compressed_timeseries(raw_path, "diag.theta_hat")
        truth_time, truth_rad = read_compressed_timeseries(raw_path, "diag.theta_ground")
        truth_aligned = np.interp(estimate_time, truth_time, truth_rad)
        absolute_error = np.abs(np.rad2deg(estimate_rad - truth_aligned))
        benchmark_mask = estimate_time >= BENCHMARK_WARMUP_S - 1e-12
        recomputed_mae = float(absolute_error[benchmark_mask].mean())
        frozen_mae = float(row["theta_mae_deg"])
        difference = abs(recomputed_mae - frozen_mae)
        maximum_mae_difference = max(maximum_mae_difference, difference)
        if difference > 2e-9:
            raise ValueError(
                f"MAE mismatch for {raw_path}: frozen={frozen_mae}, recomputed={recomputed_mae}"
            )
        rows.append(
            {
                "method_id": row["method_id"],
                "method_label": method_labels[str(row["method_id"])],
                "seed": int(row["seed"]),
                "path_id": row["path_id"],
                "path_label": path_labels[str(row["path_id"])],
                "n_samples": int(estimate_time.size),
                "duration_s": float(estimate_time[-1] - estimate_time[0]),
                "mae_deg": frozen_mae,
                "p95_abs_error_deg": matlab_prctile(absolute_error, 95.0),
                "raw_result_file": str(raw_path),
            }
        )
        if (index + 1) % 40 == 0:
            print(f"Processed {index + 1}/240 cases")

    return pd.DataFrame(rows), maximum_mae_difference


def summarize_metric(case_metrics: pd.DataFrame, metric: str) -> pd.DataFrame:
    method_order = [str(method["id"]) for method in METHODS]
    method_labels = {str(method["id"]): str(method["label"]) for method in METHODS}
    records: list[dict[str, object]] = []

    for path_order, (path_id, path_label) in enumerate(PATHS, start=1):
        subset = case_metrics.loc[case_metrics["path_id"] == path_id]
        means: dict[str, float] = {}
        staged: list[dict[str, object]] = []
        for method_id in method_order:
            values = subset.loc[subset["method_id"] == method_id, metric].to_numpy(dtype=float)
            means[method_id] = float(values.mean())
            staged.append(
                {
                    "path_order": path_order,
                    "path_id": path_id,
                    "path_label": path_label,
                    "method_id": method_id,
                    "method_label": method_labels[method_id],
                    "n_seeds": int(values.size),
                    "mean_deg": float(values.mean()),
                    "sd_deg": float(values.std(ddof=1)),
                    "all_paths_definition": "path-specific values over ten seeds",
                }
            )
        best_method = min(means, key=means.get)
        for record in staged:
            record["is_row_best"] = record["method_id"] == best_method
            records.append(record)

    all_path_means: dict[str, float] = {}
    staged = []
    for method_id in method_order:
        method_cases = case_metrics.loc[case_metrics["method_id"] == method_id]
        seed_means = method_cases.groupby("seed", sort=True)[metric].mean().to_numpy(dtype=float)
        all_path_means[method_id] = float(seed_means.mean())
        staged.append(
            {
                "path_order": 7,
                "path_id": "all_paths",
                "path_label": "All paths",
                "method_id": method_id,
                "method_label": method_labels[method_id],
                "n_seeds": int(seed_means.size),
                "mean_deg": float(seed_means.mean()),
                "sd_deg": float(seed_means.std(ddof=1)),
                "all_paths_definition": "six-route mean computed within each seed, then mean and SD over ten seeds",
            }
        )
    best_method = min(all_path_means, key=all_path_means.get)
    for record in staged:
        record["is_row_best"] = record["method_id"] == best_method
        records.append(record)
    return pd.DataFrame(records)


def latex_value(row: pd.Series) -> str:
    value = f"{float(row['mean_deg']):.3f} $\\pm$ {float(row['sd_deg']):.3f}"
    return f"\\textbf{{{value}}}" if bool(row["is_row_best"]) else value


def write_latex_table(mae: pd.DataFrame, p95: pd.DataFrame, destination: Path) -> None:
    method_order = [str(method["id"]) for method in METHODS]

    def panel_rows(summary: pd.DataFrame) -> list[str]:
        rows = []
        for path_order in range(1, 8):
            subset = summary.loc[summary["path_order"] == path_order].set_index("method_id")
            path_label = str(subset.iloc[0]["path_label"])
            values = [latex_value(subset.loc[method_id]) for method_id in method_order]
            if path_order == 7:
                path_label = "\\textbf{All paths}"
            rows.append(f"{path_label} & " + " & ".join(values) + " \\\\")
        return rows

    lines = [
        r"\begin{tabular}{@{}lcccc@{}}",
        r"\toprule",
        r"Path & ModernTCN-delta & ModernTCN-22D & GRU-22D & TCN-22D \\",
        r"\midrule",
        r"\multicolumn{5}{@{}l}{\textit{Panel A: Grade MAE (deg)}} \\",
        r"\addlinespace[1.5pt]",
        *panel_rows(mae),
        r"\midrule",
        r"\multicolumn{5}{@{}l}{\textit{Panel B: P95 absolute error (deg)}} \\",
        r"\addlinespace[1.5pt]",
        *panel_rows(p95),
        r"\bottomrule",
        r"\end{tabular}",
    ]
    destination.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    root = find_project_root()
    figure_dir = Path(__file__).resolve().parents[1]
    source_dir = figure_dir / "source_data"
    qa_dir = figure_dir / "qa"
    source_dir.mkdir(parents=True, exist_ok=True)
    qa_dir.mkdir(parents=True, exist_ok=True)

    case_source = root / CASE_METRICS_RELATIVE
    cases = pd.read_csv(case_source)
    validate_inventory(cases)
    case_metrics, maximum_mae_difference = compute_case_metrics(cases)
    mae_summary = summarize_metric(case_metrics, "mae_deg")
    p95_summary = summarize_metric(case_metrics, "p95_abs_error_deg")

    case_path = source_dir / "table08_closed_loop_case_metrics.csv"
    mae_path = source_dir / "table08_pathwise_mae.csv"
    p95_path = source_dir / "table08_pathwise_p95.csv"
    latex_path = source_dir / "table08_pathwise_accuracy.tex"
    case_metrics.to_csv(case_path, index=False, float_format="%.12g")
    mae_summary.to_csv(mae_path, index=False, float_format="%.12g")
    p95_summary.to_csv(p95_path, index=False, float_format="%.12g")
    write_latex_table(mae_summary, p95_summary, latex_path)

    qa = {
        "status": "PASS",
        "input_rows": int(len(cases)),
        "output_case_rows": int(len(case_metrics)),
        "methods": int(case_metrics["method_id"].nunique()),
        "paths": int(case_metrics["path_id"].nunique()),
        "seeds": int(case_metrics["seed"].nunique()),
        "maximum_mae_recompute_difference_deg": maximum_mae_difference,
        "p95_definition": "MATLAB-compatible prctile(abs(error),95) over each complete closed-loop trace",
        "all_paths_definition": "six-route mean within each seed, followed by mean and sample SD over ten seeds",
        "outputs": [str(case_path), str(mae_path), str(p95_path), str(latex_path)],
    }
    (qa_dir / "table08_pathwise_accuracy_qa.json").write_text(
        json.dumps(qa, indent=2), encoding="ascii"
    )
    print(json.dumps(qa, indent=2))


if __name__ == "__main__":
    main()
