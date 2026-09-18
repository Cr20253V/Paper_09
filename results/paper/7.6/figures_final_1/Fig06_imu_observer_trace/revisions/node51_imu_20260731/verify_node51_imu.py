from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[7]
MTCN_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair/"
    "11_formal_six_path/cases/ADAPTIVE/s42/p02_sharp_turn_transition"
)
BASELINE_RKF_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/"
    "15_rkf_ra_covariance_sensitivity/ra_x2_qg_x05/04_rkf_closed_loop/"
    "cases/p02_sharp_turn_transition"
)
NODE51_RKF_CASE = ROOT / (
    "results/modern_tcn_metric_rebuild/51_moderntcn_rkf_highrisk_suppression_rebuild/"
    "08_formal_six_path/cases/ADAPTIVE/s42/p02_sharp_turn_transition"
)


def calculate(rkf_case: Path, debug_name: str) -> dict[str, float | int | bool]:
    mtcn_trace = pd.read_csv(MTCN_CASE / "trace.csv")
    mtcn_debug = pd.read_csv(MTCN_CASE / "node44r1_runtime_debug.csv")
    rkf_trace = pd.read_csv(rkf_case / "trace.csv")
    rkf_debug = pd.read_csv(rkf_case / debug_name)

    assert len(mtcn_trace) == len(rkf_trace) == 5201
    assert len(mtcn_debug) == len(rkf_debug) == 5200
    assert np.array_equal(rkf_trace["t_s"].to_numpy(), mtcn_trace["t_s"].to_numpy())
    assert np.array_equal(
        rkf_trace["theta_true"].to_numpy(), mtcn_trace["theta_true"].to_numpy()
    )
    assert np.array_equal(rkf_debug["step"].to_numpy(dtype=int), np.arange(1, 5201))

    truth = np.rad2deg(rkf_trace["theta_true"].to_numpy()[1:])
    rkf_error = np.abs(np.rad2deg(rkf_debug["theta_rkf"].to_numpy()) - truth)
    mtcn_error = np.abs(np.rad2deg(mtcn_debug["theta_tcn"].to_numpy()) - truth)
    evaluated = rkf_trace["t_s"].to_numpy()[1:] >= 0.5
    difference = rkf_error[evaluated] - mtcn_error[evaluated]
    return {
        "rkf_mae_deg": float(rkf_error[evaluated].mean()),
        "mtcn_mae_deg": float(mtcn_error[evaluated].mean()),
        "rkf_win_pct": float(100 * np.mean(difference < -0.1)),
        "mtcn_win_pct": float(100 * np.mean(difference > 0.1)),
        "near_tie_pct": float(100 * np.mean(np.abs(difference) <= 0.1)),
        "time_truth_exact": True,
        "evaluated_samples": int(evaluated.sum()),
    }


result = {
    "baseline": calculate(BASELINE_RKF_CASE, "rkf_runtime_debug.csv"),
    "modified": calculate(NODE51_RKF_CASE, "node51_runtime_debug.csv"),
}
print(json.dumps(result, separators=(",", ":")))
