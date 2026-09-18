"""读取固定 ModernTCN 数据集，并保持 MATLAB 侧已有 split/scaler 不变。

本文件默认读取 `data/tcn/ModernTCN_dataset_v4_industrial.mat` 中已经生成好的
窗口、标签、样本权重和元信息。这里不能重新划分 train/val/test，也不能
重新拟合 scaler；Python 端训练必须直接使用 MAT 文件里的归一化后 X。
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import h5py
import numpy as np
import torch
from torch.utils.data import Dataset


DATASET_RELATIVE_PATH = Path("data") / "tcn" / "ModernTCN_dataset_v4_industrial.mat"


@dataclass(frozen=True)
class ModernTCNContract:
    """记录第一阶段实验必须锁定的数据契约。"""

    dataset_file: str
    seq_len: int
    input_dim: int
    output_contract: str
    split_policy: str
    scaler_policy: str
    vehicle_type: str = "diagonal_dual_steer_drive_agv"
    active_drive_steer_wheels: str = "LF,RR"
    passive_support_wheels: str = "RF,LR"
    feature_policy: str = "keep_current_algorithm_inputs_unchanged"
    feature_contract: str = "passive17_plus_all5"
    label_time_policy: str = "current_window_end"
    horizon_steps: int = 0
    horizon_seconds: float = 0.0
    confidence_policy: str = "derive_classification_confidence_from_softmax_and_export"


@dataclass
class SplitArrays:
    """单个 split 的全部训练/评估数组。"""

    X: np.ndarray
    y_main: np.ndarray
    y_turn: np.ndarray
    y_theta: np.ndarray
    mask_theta: np.ndarray
    main_weight: np.ndarray
    turn_weight: np.ndarray
    theta_weight: np.ndarray
    turn_purity: np.ndarray
    turn_transition: np.ndarray
    run_id: np.ndarray


class AGVWindowDataset(Dataset):
    """PyTorch Dataset，直接封装 MAT 文件中的窗口数据。"""

    def __init__(self, split: SplitArrays) -> None:
        self.split = split

    def __len__(self) -> int:
        return int(self.split.X.shape[0])

    def __getitem__(self, idx: int) -> Dict[str, torch.Tensor]:
        # 这里保持输入格式为 [time, feature]，模型内部再转成 Conv1d 需要的 [B, C, T]。
        return {
            "X": torch.from_numpy(self.split.X[idx]).float(),
            "y_main": torch.tensor(self.split.y_main[idx], dtype=torch.long),
            "y_turn": torch.tensor(self.split.y_turn[idx], dtype=torch.long),
            "y_theta": torch.tensor(self.split.y_theta[idx], dtype=torch.float32),
            "mask_theta": torch.tensor(self.split.mask_theta[idx], dtype=torch.float32),
            "main_weight": torch.tensor(self.split.main_weight[idx], dtype=torch.float32),
            "turn_weight": torch.tensor(self.split.turn_weight[idx], dtype=torch.float32),
            "theta_weight": torch.tensor(self.split.theta_weight[idx], dtype=torch.float32),
            "turn_purity": torch.tensor(self.split.turn_purity[idx], dtype=torch.float32),
            "turn_transition": torch.tensor(self.split.turn_transition[idx], dtype=torch.bool),
            "run_id": torch.tensor(self.split.run_id[idx], dtype=torch.float32),
        }


def find_project_root(start: Optional[Path] = None) -> Path:
    """从当前文件向上寻找项目根目录。"""

    if start is None:
        start = Path(__file__).resolve()
    start = start.resolve()
    candidates: Iterable[Path] = (start, *start.parents)
    for p in candidates:
        if (p / "init_project.m").exists() and (p / "data" / "tcn").exists():
            return p
    raise FileNotFoundError("无法定位项目根目录：未找到 init_project.m 和 data/tcn。")


def default_dataset_file(project_root: Optional[Path] = None) -> Path:
    """返回当前默认 ModernTCN 数据集路径。"""

    root = project_root or find_project_root()
    return root / DATASET_RELATIVE_PATH


def load_modern_tcn_dataset(
    dataset_file: Optional[Path] = None,
    limit_train: int = 0,
    limit_val: int = 0,
    limit_test: int = 0,
) -> Dict[str, object]:
    """读取固定 ModernTCN 数据集。

    MATLAB v7.3 MAT 文件本质上是 HDF5；数值数组在 HDF5 中维度顺序和 MATLAB
    `size(dataset.X_train) == [N, 128, 19]` 相反，因此这里显式转回
    `[window, time, feature]`。
    """

    dataset_file = Path(dataset_file) if dataset_file else default_dataset_file()
    if not dataset_file.exists():
        raise FileNotFoundError(f"找不到固定 ModernTCN 数据集：{dataset_file}")

    with h5py.File(dataset_file, "r") as f:
        root = f["dataset"]
        train = _read_split(root, "train", limit_train)
        val = _read_split(root, "val", limit_val)
        test = _read_split(root, "test", limit_test)
        feat_names = _read_feat_names(f, root)
        scaler = _read_scaler(root)

        shape_seq_len = int(train.X.shape[1])
        shape_input_dim = int(train.X.shape[2])
        derived_feature_contract = _read_dataset_feature_contract(root, feat_names)
        meta_seq_len = _read_optional_meta_int(root, "seq_len", shape_seq_len)
        meta_input_dim = _read_optional_meta_int(root, "input_dim", shape_input_dim)
        if meta_seq_len != shape_seq_len:
            raise ValueError(f"ModernTCN dataset meta.seq_len={meta_seq_len} 与 X shape seq_len={shape_seq_len} 不一致")
        if meta_input_dim != shape_input_dim:
            raise ValueError(f"ModernTCN dataset meta.input_dim={meta_input_dim} 与 X shape input_dim={shape_input_dim} 不一致")
        feature_contract = _read_optional_meta_string(root, "feature_contract", derived_feature_contract)
        if feature_contract != derived_feature_contract:
            raise ValueError(
                f"ModernTCN dataset meta.feature_contract={feature_contract} 与特征列推断={derived_feature_contract} 不一致"
            )
        feature_policy = _feature_policy_for_contract(feature_contract)
        contract = ModernTCNContract(
            dataset_file=str(dataset_file),
            seq_len=shape_seq_len,
            input_dim=shape_input_dim,
            output_contract="logits_main3_logits_turn3_theta1",
            split_policy="use_existing_run_level_split_from_mat",
            scaler_policy="use_existing_normalized_X_and_existing_scaler_only",
            feature_policy=feature_policy,
            feature_contract=feature_contract,
            label_time_policy=_read_optional_meta_string(root, "label_time_policy", "current_window_end"),
            horizon_steps=_read_optional_meta_int(root, "horizon_steps", 0),
            horizon_seconds=_read_optional_meta_float(root, "horizon_seconds", 0.0),
        )

    _check_contract(contract)
    return {
        "train": train,
        "val": val,
        "test": test,
        "feat_names": feat_names,
        "scaler": scaler,
        "contract": contract,
    }


def class_weights(labels: np.ndarray, num_classes: int, method: str, multipliers: List[float]) -> torch.Tensor:
    """复刻 MATLAB baseline 中的类别权重计算方式。"""

    labels = np.asarray(labels).reshape(-1)
    counts = np.array([(labels == i).sum() for i in range(num_classes)], dtype=np.float64)
    counts_safe = np.maximum(counts, 1.0)
    method = method.lower()
    if method == "inverse":
        w = 1.0 / counts_safe
    elif method == "sqrt_inverse":
        w = 1.0 / np.sqrt(counts_safe)
    elif method == "balanced":
        w = counts.sum() / (num_classes * counts_safe)
    else:
        w = np.ones(num_classes, dtype=np.float64)
    w[counts == 0] = 0.0
    if np.any(w > 0):
        w = w / np.mean(w[w > 0])
    else:
        w = np.ones(num_classes, dtype=np.float64)
    w = w * np.asarray(multipliers, dtype=np.float64)
    if np.any(w > 0):
        w = w / np.mean(w[w > 0])
    return torch.tensor(w, dtype=torch.float32)


def _read_split(root: h5py.Group, split_name: str, limit: int) -> SplitArrays:
    X = _read_h5_array(root[f"X_{split_name}"])
    # MATLAB 主工况标签为 1/2/3；PyTorch CE 使用 0/1/2。
    y_main = _read_vector(root[f"y_main_{split_name}"]).astype(np.int64) - 1
    # MATLAB 转弯标签为 -1/0/1；PyTorch CE 使用 0/1/2。
    y_turn = _read_vector(root[f"y_turn_{split_name}"]).astype(np.int64) + 1
    y_theta = _read_vector(root[f"y_theta_{split_name}"]).astype(np.float32)
    mask_theta = _read_vector(root[f"mask_theta_{split_name}"]).astype(np.float32)
    main_weight = _read_vector(root[f"main_sample_weight_{split_name}"]).astype(np.float32)
    turn_weight = _read_vector(root[f"turn_sample_weight_{split_name}"]).astype(np.float32)
    theta_weight = _read_vector(root[f"theta_sample_weight_{split_name}"]).astype(np.float32)
    turn_purity = _read_vector(root[f"turn_purity_{split_name}"]).astype(np.float32)
    turn_transition = _read_vector(root[f"turn_transition_{split_name}"]).astype(bool)
    run_id = _read_vector(root[f"run_id_{split_name}"]).astype(np.float32)

    if limit and limit > 0:
        sl = slice(0, int(limit))
        X = X[sl]
        y_main = y_main[sl]
        y_turn = y_turn[sl]
        y_theta = y_theta[sl]
        mask_theta = mask_theta[sl]
        main_weight = main_weight[sl]
        turn_weight = turn_weight[sl]
        theta_weight = theta_weight[sl]
        turn_purity = turn_purity[sl]
        turn_transition = turn_transition[sl]
        run_id = run_id[sl]

    return SplitArrays(
        X=X,
        y_main=y_main,
        y_turn=y_turn,
        y_theta=y_theta,
        mask_theta=mask_theta,
        main_weight=main_weight,
        turn_weight=turn_weight,
        theta_weight=theta_weight,
        turn_purity=turn_purity,
        turn_transition=turn_transition,
        run_id=run_id,
    )


def _read_h5_array(ds: h5py.Dataset) -> np.ndarray:
    raw = np.asarray(ds, dtype=np.float32)
    if raw.ndim != 3:
        raise ValueError(f"期望 3D 窗口数组，实际 shape={raw.shape}")
    return np.transpose(raw, (2, 1, 0)).copy()


def _read_vector(ds: h5py.Dataset) -> np.ndarray:
    return np.asarray(ds).reshape(-1).copy()


def _read_scaler(root: h5py.Group) -> Dict[str, np.ndarray]:
    scaler_group = root["scaler"]
    return {
        "mean": _read_vector(scaler_group["mean"]).astype(np.float32),
        "std": _read_vector(scaler_group["std"]).astype(np.float32),
    }


def _read_feat_names(f: h5py.File, root: h5py.Group) -> List[str]:
    names: List[str] = []
    refs = np.asarray(root["feat_names"]).reshape(-1)
    for ref in refs:
        names.append(_decode_matlab_char(f[ref]))
    return names


def _decode_matlab_char(ds: h5py.Dataset) -> str:
    raw = np.asarray(ds).reshape(-1)
    return "".join(chr(int(c)) for c in raw if int(c) != 0)


def _check_contract(contract: ModernTCNContract) -> None:
    allowed_seq_len = {128, 256}
    if contract.seq_len not in allowed_seq_len:
        allowed = "/".join(str(x) for x in sorted(allowed_seq_len))
        raise ValueError(f"ModernTCN 第一阶段仅允许 seq_len={allowed}，实际为 {contract.seq_len}")
    expected = {
        "passive17_plus_all5": 22,
        "passive17_plus_all5_cmdresp_lite_v1": 30,
        "passive17_plus_all5_cmdresp_lag1_only_v1": 24,
    }
    if contract.feature_contract in expected:
        need = expected[contract.feature_contract]
        if contract.input_dim != need:
            raise ValueError(
                f"ModernTCN {contract.feature_contract} 要求 input_dim={need}，实际为 {contract.input_dim}"
            )
    else:
        raise ValueError(f"未知 ModernTCN feature contract={contract.feature_contract} 不受支持")
    if contract.label_time_policy != "current_window_end":
        raise ValueError(
            f"ModernTCN 当前模型固定为 label_time_policy=current_window_end，实际为 {contract.label_time_policy}"
        )
    if contract.horizon_steps != 0:
        raise ValueError(f"ModernTCN 当前模型固定为当前状态估计 horizon_steps=0，实际为 {contract.horizon_steps}")


def _read_optional_meta_int(root: h5py.Group, field_name: str, default: int) -> int:
    value = _read_optional_meta_scalar(root, field_name, default)
    return int(round(float(value)))


def _read_optional_meta_float(root: h5py.Group, field_name: str, default: float) -> float:
    value = _read_optional_meta_scalar(root, field_name, default)
    return float(value)


def _read_optional_meta_scalar(root: h5py.Group, field_name: str, default: float) -> float:
    meta = root.get("meta")
    if meta is None or field_name not in meta:
        return default
    return float(np.asarray(meta[field_name]).reshape(-1)[0])


def _read_optional_meta_string(root: h5py.Group, field_name: str, default: str) -> str:
    meta = root.get("meta")
    if meta is None or field_name not in meta:
        return default
    ds = meta[field_name]
    if not isinstance(ds, h5py.Dataset):
        return default
    return _decode_matlab_char(ds)


def _read_dataset_feature_contract(root: h5py.Group, feat_names: List[str]) -> str:
    if len(feat_names) == 30 and "F_cmd_lag1" in feat_names:
        return "passive17_plus_all5_cmdresp_lite_v1"
    if len(feat_names) == 24 and "F_cmd_lag1" in feat_names and "omega_cmd_lag1" in feat_names:
        return "passive17_plus_all5_cmdresp_lag1_only_v1"
    return "passive17_plus_all5"


def _feature_policy_for_contract(feature_contract: str) -> str:
    if feature_contract == "passive17_plus_all5_cmdresp_lite_v1":
        return "plan_b_lite_history_command_response"
    if feature_contract == "passive17_plus_all5_cmdresp_lag1_only_v1":
        return "plan_b_lag1_only_history_command_response"
    return "keep_current_algorithm_inputs_unchanged"
