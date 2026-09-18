from __future__ import annotations

from pathlib import Path


def find_project_root() -> Path:
    here = Path(__file__).resolve()
    marker = Path("results/paper/7.6/A0_论文最终统一实验配置_20260715.json")
    for parent in here.parents:
        if (parent / marker).is_file():
            return parent
    raise RuntimeError("Cannot locate the S-Function_16 project root")


ROOT = find_project_root()
A2_ROOT = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/02_A2_realtime_benchmark"
ORT_ROOT = A2_ROOT / "07_same_backend_onnxruntime"
TOOLS = ORT_ROOT / "02_tools"
DERIVED = ORT_ROOT / "03_derived_models"
VALIDATION = ORT_ROOT / "04_validation"
FORMAL = ORT_ROOT / "05_formal"
SUMMARY = ORT_ROOT / "06_summary"

A1_ROOT = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison"
A1_REGISTRY = A1_ROOT / "model_registry.csv"
DATASET = ROOT / "data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"

MODERN_DELTA_ONNX = ROOT / "results/modern_tcn_metric_rebuild/25_lag_representation_repair/03_onnx_and_smoke/delta_bank_124/seed42/modern_tcn_delta_bank_124_seed42.onnx"
MODERN_22D_ONNX = ROOT / "results/modern_tcn_metric_rebuild/32_four_algorithm_10seed_closed_loop/01_modern_fixed_onnx/seed42/modern_fixed_seed42.onnx"

TCN_FEATURE_ONNX = DERIVED / "tcn_22d_seed42_feature.onnx"
TCN_HEADS_MAT = DERIVED / "tcn_22d_seed42_heads.mat"
TCN_FULL_ONNX = DERIVED / "tcn_22d_seed42_full.onnx"
GRU_FEATURE_ONNX = DERIVED / "gru_22d_seed42_feature.onnx"
GRU_HEADS_MAT = DERIVED / "gru_22d_seed42_heads.mat"
GRU_FULL_ONNX = DERIVED / "gru_22d_seed42_full.onnx"
NATIVE_REFERENCE = VALIDATION / "matlab_native_reference_seed42.mat"

EXPECTED_PARENT_SHA = {
    "modern_tcn_delta_bank_124": "d49238d2a90803a4abbc8ca65f822b3f65f4f77b62be3b9f10227b9e038895f7",
    "modern_tcn_22d": "4cd19cdbaf399c6abb03e0de5c1a020d4b540d27914488f521e58eb22d6f2704",
    "gru_22d": "e1da71edde44e33d37c904a2d2f49e07ba02a7ef570ec61f7c90e91cc35268e3",
    "tcn_22d": "ec896bd7480a99759e586bb8ec759772b4a457d182689aa41fdbb93ec24150c4",
}

EXPECTED_EXISTING_ONNX_SHA = {
    "modern_tcn_delta_bank_124": "45e1fc805ca93c2572d85bf4d90744b7f486b0bddbd7503cd44e9c2b1ee4835e",
    "modern_tcn_22d": "bad282e477990865a2f9598926d1015b39b79312991415a459db1cba362fe4fd",
}

PARAM_COUNTS = {
    "modern_tcn_delta_bank_124": 145202,
    "modern_tcn_22d": 118538,
    "gru_22d": 99276,
    "tcn_22d": 156396,
}


def ensure_output_dirs() -> None:
    for path in (DERIVED, VALIDATION, FORMAL / "runs", SUMMARY, ORT_ROOT / "03_environment", ORT_ROOT / "logs"):
        path.mkdir(parents=True, exist_ok=True)

