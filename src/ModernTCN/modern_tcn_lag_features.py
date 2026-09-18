"""Input augmentation helpers for ModernTCN experiments."""

from __future__ import annotations

from dataclasses import replace
from typing import Dict, Iterable, List, Sequence

import numpy as np

from modern_tcn_data import SplitArrays


PHYSICS_RESIDUAL_MODE = "physics_residual_8"
SUPPORTED_INPUT_AUGMENTS = {
    "none",
    "delta_lag",
    "lag_stack",
    "delta_bank",
    "mixed_lag_delta",
    PHYSICS_RESIDUAL_MODE,
}

PASSIVE22_FEATURE_NAMES = [
    "gyro_z",
    "I_lf",
    "I_rr",
    "omega_wheel_lf",
    "omega_wheel_rr",
    "delta_lf",
    "delta_rr",
    "v_hat",
    "dv_hat_dt",
    "ws_imbalance",
    "I_sum",
    "I_diff_signed",
    "I_diff_abs",
    "kappa_proxy",
    "accel_per_current",
    "dv_hat_dt_lp",
    "accel_x_wheel",
    "I_drive_signed",
    "current_per_accel",
    "drive_load_proxy",
    "a_hp",
    "yaw_consistency_error",
]

PHYSICS_SOURCE_FEATURE_NAMES = ["gyro_z", "I_lf", "I_rr", "v_hat", "dv_hat_dt_lp"]
PHYSICS_FORBIDDEN_SOURCE_FEATURES = ["accel_x", "gyro_y", "theta_ground", "y_raw(:,9)", "y_raw(:,10)", "y_raw(:,16)"]
PHYSICS_RESIDUAL_FEATURE_NAMES = [
    "phys_F_long_norm",
    "phys_F_diff_norm",
    "phys_F_res_norm",
    "phys_F_res_ema_tau03",
    "phys_F_res_ema_tau08",
    "phys_yaw_drive_accel",
    "phys_yaw_residual",
    "phys_yaw_res_ema_tau03",
]

DEFAULT_PHYSICS_PARAMS = {
    "Ts": 0.01,
    "mass": 200.0,
    "W": 0.8,
    "Iz": 16.67,
    "wheel_radius": 0.15,
    "wheel_inertia": 0.0135,
    "motor_torque_constant": 1.21,
    "motor_inertia": 17.7e-4,
    "gear_ratio": 10.0,
    "gear_efficiency": 0.9,
    "rolling_resistance": 0.015,
    "air_density": 1.225,
    "drag_coefficient_area": 0.5,
    "gravity": 9.81,
    "yaw_accel_tau": 0.10,
}


def normalize_input_augment(value: object) -> str:
    mode = str(value or "none").strip().lower()
    if mode not in SUPPORTED_INPUT_AUGMENTS:
        raise ValueError(f"unknown input augmentation: {mode}")
    return mode


def normalize_lag_steps(steps: Iterable[object] | None, default: Sequence[int] = (1, 2, 4)) -> List[int]:
    raw_steps = list(default if steps is None else steps)
    out: List[int] = []
    for item in raw_steps:
        step = int(item)
        if step <= 0:
            raise ValueError(f"lag steps must be positive, got {step}")
        if step not in out:
            out.append(step)
    if not out:
        raise ValueError("lag_steps must not be empty")
    return out


def build_input_augmentation_metadata(
    input_augment: object,
    raw_input_dim: int,
    seq_len: int,
    feature_contract: object,
    feat_names: Sequence[object],
    *,
    delta_lag: int = 1,
    delta_pad: str = "zero",
    lag_steps: Iterable[object] | None = None,
    lag_pad: str = "edge",
    delta_clip_abs: float = 5.0,
) -> Dict[str, object]:
    mode = normalize_input_augment(input_augment)
    raw_input_dim = int(raw_input_dim)
    seq_len = int(seq_len)
    raw_names = [str(name) for name in feat_names]
    if raw_input_dim != len(raw_names):
        raise ValueError(f"feature name count {len(raw_names)} does not match raw input_dim {raw_input_dim}")

    metadata: Dict[str, object] = {
        "input_augment": mode,
        "raw_input_dim": raw_input_dim,
        "augmented_input_dim": raw_input_dim,
        "raw_feature_contract": str(feature_contract),
        "raw_feature_names": raw_names,
        "raw_seq_len": seq_len,
    }
    if mode == "none":
        metadata["feature_names"] = raw_names
        return metadata

    _require_plantfix_22d(raw_input_dim, feature_contract, mode)
    if mode == "delta_lag":
        lag = int(delta_lag)
        _validate_lag(lag, seq_len)
        pad = str(delta_pad or "zero").lower()
        if pad != "zero":
            raise ValueError("delta_lag experiment only supports delta_pad=zero")
        metadata.update(
            {
                "delta_lag": lag,
                "delta_pad": pad,
                "augmented_input_dim": raw_input_dim * 2,
                "method": "[x_t, x_t - x_{t-m}]",
                "normalization": "delta_from_normalized_X_without_extra_scaler",
            }
        )
    elif mode == PHYSICS_RESIDUAL_MODE:
        _require_physics_feature_names(raw_names)
        metadata.update(
            {
                "augmented_input_dim": raw_input_dim + len(PHYSICS_RESIDUAL_FEATURE_NAMES),
                "method": "22D raw-window plant residual block: current-to-force, load residual, and yaw residual causal EMA features",
                "normalization": "physics_features_from_unnormalized_22D_then_train_split_standardized",
                "physics_feature_names": list(PHYSICS_RESIDUAL_FEATURE_NAMES),
                "source_feature_names": list(PHYSICS_SOURCE_FEATURE_NAMES),
                "forbidden_source_features": list(PHYSICS_FORBIDDEN_SOURCE_FEATURES),
                "physics_params": dict(DEFAULT_PHYSICS_PARAMS),
                "physics_ema_taus": [0.3, 0.8],
                "physics_clip_abs": 8.0,
                "requires_raw_feature_scaler": True,
                "fit_policy": "fit_added_feature_scaler_on_train_split_only",
            }
        )
    else:
        steps = normalize_lag_steps(lag_steps)
        for step in steps:
            _validate_lag(step, seq_len)
        pad = str(lag_pad or "edge").lower()
        if pad != "edge":
            raise ValueError("Node25 lag representations only support lag_pad=edge")
        clip = float(delta_clip_abs)
        if not np.isfinite(clip) or clip <= 0:
            raise ValueError(f"delta_clip_abs must be positive and finite, got {clip}")

        if mode == "lag_stack":
            multiplier = 1 + len(steps)
            method = "[x_t, x_{t-lag_steps}]"
            normalization = "lagged_normalized_X_edge_pad"
        elif mode == "delta_bank":
            multiplier = 1 + len(steps)
            method = "[x_t, clipped(x_t - x_{t-lag_steps})]"
            normalization = "delta_from_normalized_X_edge_pad_clipped"
        else:
            multiplier = 1 + len(steps) * 2
            method = "[x_t, x_{t-lag_steps}, clipped(x_t - x_{t-lag_steps})]"
            normalization = "mixed_lagged_and_delta_from_normalized_X_edge_pad_clipped"

        metadata.update(
            {
                "lag_steps": steps,
                "lag_pad": pad,
                "delta_clip_abs": clip,
                "augmented_input_dim": raw_input_dim * multiplier,
                "method": method,
                "normalization": normalization,
            }
        )
    metadata["feature_names"] = augmented_feature_names(raw_names, metadata)
    return metadata


def effective_input_dim_from_metadata(metadata: Dict[str, object], fallback_input_dim: int) -> int:
    try:
        return int(metadata.get("augmented_input_dim", fallback_input_dim))
    except (TypeError, ValueError):
        return int(fallback_input_dim)


def fit_input_augmentation_metadata(
    metadata: Dict[str, object],
    train_X: np.ndarray,
    raw_scaler: Dict[str, object],
) -> Dict[str, object]:
    """Fit any train-only statistics needed by an augmentation mode."""

    mode = normalize_input_augment(metadata.get("input_augment", "none"))
    if mode != PHYSICS_RESIDUAL_MODE:
        return metadata
    X_arr = np.asarray(train_X, dtype=np.float32)
    if X_arr.ndim != 3:
        raise ValueError(f"expected train_X [N,T,F], got {X_arr.shape}")
    raw_dim = int(metadata.get("raw_input_dim", X_arr.shape[-1]))
    if X_arr.shape[-1] != raw_dim:
        raise ValueError(f"train_X feature dim {X_arr.shape[-1]} does not match raw_input_dim {raw_dim}")
    raw_mean = _vector_from(raw_scaler.get("mean"), raw_dim, "raw scaler mean")
    raw_std = _vector_from(raw_scaler.get("std"), raw_dim, "raw scaler std")
    raw_std = np.where(np.abs(raw_std) < 1e-8, 1.0, raw_std).astype(np.float32)
    physics_raw = compute_physics_residual_features(X_arr, metadata, raw_mean, raw_std)
    flat = physics_raw.reshape(-1, physics_raw.shape[-1])
    feat_mean = np.mean(flat, axis=0).astype(np.float32)
    feat_std = np.std(flat, axis=0).astype(np.float32)
    feat_std = np.where(feat_std < 1e-6, 1.0, feat_std).astype(np.float32)
    fitted = dict(metadata)
    fitted.update(
        {
            "raw_feature_mean": _float_list(raw_mean),
            "raw_feature_std": _float_list(raw_std),
            "physics_feature_mean": _float_list(feat_mean),
            "physics_feature_std": _float_list(feat_std),
            "physics_feature_std_floor": 1e-6,
        }
    )
    return fitted


def augment_array_by_metadata(X: np.ndarray, metadata: Dict[str, object]) -> np.ndarray:
    mode = normalize_input_augment(metadata.get("input_augment", "none"))
    X_arr = np.asarray(X, dtype=np.float32)
    if mode == "none":
        return X_arr.astype(np.float32, copy=False)
    if X_arr.ndim != 3:
        raise ValueError(f"expected [N,T,F], got {X_arr.shape}")
    if mode == "delta_lag":
        return augment_with_delta_lag(
            X_arr,
            lag=int(metadata.get("delta_lag", 1)),
            pad=str(metadata.get("delta_pad", "zero")),
        )
    if mode == PHYSICS_RESIDUAL_MODE:
        raw_dim = int(metadata.get("raw_input_dim", X_arr.shape[-1]))
        raw_mean = _vector_from(metadata.get("raw_feature_mean"), raw_dim, "raw_feature_mean")
        raw_std = _vector_from(metadata.get("raw_feature_std"), raw_dim, "raw_feature_std")
        physics_dim = len(PHYSICS_RESIDUAL_FEATURE_NAMES)
        feat_mean = _vector_from(metadata.get("physics_feature_mean"), physics_dim, "physics_feature_mean")
        feat_std = _vector_from(metadata.get("physics_feature_std"), physics_dim, "physics_feature_std")
        feat_std = np.where(np.abs(feat_std) < 1e-8, 1.0, feat_std).astype(np.float32)
        physics_raw = compute_physics_residual_features(X_arr, metadata, raw_mean, raw_std)
        physics_norm = (physics_raw - feat_mean.reshape(1, 1, -1)) / feat_std.reshape(1, 1, -1)
        clip_abs = float(metadata.get("physics_clip_abs", 8.0))
        if np.isfinite(clip_abs) and clip_abs > 0:
            physics_norm = np.clip(physics_norm, -clip_abs, clip_abs)
        return np.concatenate([X_arr, physics_norm.astype(np.float32, copy=False)], axis=-1).astype(np.float32, copy=False)
    steps = normalize_lag_steps(metadata.get("lag_steps", [1, 2, 4]))
    pad = str(metadata.get("lag_pad", "edge") or "edge").lower()
    if pad != "edge":
        raise ValueError("only lag_pad=edge is supported for Node25 lag representations")
    clip = float(metadata.get("delta_clip_abs", 5.0))
    lagged = [_lagged_edge(X_arr, step) for step in steps]
    if mode == "lag_stack":
        return np.concatenate([X_arr] + lagged, axis=-1).astype(np.float32, copy=False)
    deltas = [_clip_delta(X_arr - lag_item, clip) for lag_item in lagged]
    if mode == "delta_bank":
        return np.concatenate([X_arr] + deltas, axis=-1).astype(np.float32, copy=False)
    return np.concatenate([X_arr] + lagged + deltas, axis=-1).astype(np.float32, copy=False)


def augment_split_by_metadata(split: SplitArrays, metadata: Dict[str, object]) -> SplitArrays:
    return replace(split, X=augment_array_by_metadata(split.X, metadata))


def augmented_feature_names(feature_names: Sequence[object], metadata: Dict[str, object]) -> List[str]:
    raw = [str(name) for name in feature_names]
    mode = normalize_input_augment(metadata.get("input_augment", "none"))
    if mode == "none":
        return raw
    if mode == "delta_lag":
        return raw + [f"delta_lag{int(metadata.get('delta_lag', 1))}_{name}" for name in raw]
    if mode == PHYSICS_RESIDUAL_MODE:
        return raw + list(PHYSICS_RESIDUAL_FEATURE_NAMES)
    steps = normalize_lag_steps(metadata.get("lag_steps", [1, 2, 4]))
    if mode == "lag_stack":
        return raw + [f"lag{step}_{name}" for step in steps for name in raw]
    if mode == "delta_bank":
        return raw + [f"delta_lag{step}_{name}" for step in steps for name in raw]
    return (
        raw
        + [f"lag{step}_{name}" for step in steps for name in raw]
        + [f"delta_lag{step}_{name}" for step in steps for name in raw]
    )


def augmentation_block_stats(split: SplitArrays, raw_input_dim: int) -> Dict[str, float]:
    block = np.asarray(split.X[..., int(raw_input_dim) :], dtype=np.float32)
    if block.size == 0:
        return {"augment_mean": float("nan"), "augment_std": float("nan"), "augment_p95_abs": float("nan")}
    return {
        "augment_mean": float(np.mean(block)),
        "augment_std": float(np.std(block)),
        "augment_p95_abs": float(np.percentile(np.abs(block), 95)),
    }


def augment_with_delta_lag(X: np.ndarray, lag: int, pad: str = "zero") -> np.ndarray:
    X_arr = np.asarray(X, dtype=np.float32)
    if X_arr.ndim != 3:
        raise ValueError(f"expected [N,T,F], got {X_arr.shape}")
    _, seq_len, _ = X_arr.shape
    lag = int(lag)
    _validate_lag(lag, seq_len)
    if str(pad).lower() != "zero":
        raise ValueError("this experiment only supports zero padding")
    delta = np.zeros_like(X_arr, dtype=np.float32)
    delta[:, lag:, :] = X_arr[:, lag:, :] - X_arr[:, :-lag, :]
    return np.concatenate([X_arr, delta], axis=-1).astype(np.float32, copy=False)


def compute_physics_residual_features(
    X_norm: np.ndarray,
    metadata: Dict[str, object],
    raw_mean: np.ndarray | Sequence[object],
    raw_std: np.ndarray | Sequence[object],
) -> np.ndarray:
    """Compute unstandardized physics residual features from normalized 22D windows."""

    X_arr = np.asarray(X_norm, dtype=np.float32)
    if X_arr.ndim != 3:
        raise ValueError(f"expected [N,T,F], got {X_arr.shape}")
    _require_physics_feature_names(metadata.get("raw_feature_names", PASSIVE22_FEATURE_NAMES))
    raw_dim = int(metadata.get("raw_input_dim", 22))
    if X_arr.shape[-1] != raw_dim:
        raise ValueError(f"physics_residual_8 expects raw feature dim {raw_dim}, got {X_arr.shape[-1]}")
    mean = _vector_from(raw_mean, raw_dim, "raw_mean").reshape(1, 1, -1)
    std = _vector_from(raw_std, raw_dim, "raw_std").reshape(1, 1, -1)
    X_raw = X_arr.astype(np.float32) * std + mean

    params = _physics_params(metadata)
    ts = float(params["Ts"])
    mass = float(params["mass"])
    width = float(params["W"])
    iz = float(params["Iz"])
    radius = float(params["wheel_radius"])
    wheel_inertia = float(params["wheel_inertia"])
    kt = float(params["motor_torque_constant"])
    motor_inertia = float(params["motor_inertia"])
    gear_ratio = float(params["gear_ratio"])
    gear_eff = float(params["gear_efficiency"])
    c_roll = float(params["rolling_resistance"])
    rho = float(params["air_density"])
    cda = float(params["drag_coefficient_area"])
    gravity = float(params["gravity"])
    yaw_tau = float(params["yaw_accel_tau"])

    force_gain = gear_ratio * gear_eff * kt / max(radius, 1e-6)
    force_scale = max(mass * gravity, 1e-6)
    m_eff = mass + 2.0 * (wheel_inertia + motor_inertia * gear_ratio * gear_ratio) / max(radius * radius, 1e-6)

    gyro_z = X_raw[..., 0]
    i_lf = X_raw[..., 1]
    i_rr = X_raw[..., 2]
    v_hat = X_raw[..., 7]
    dv_hat_dt_lp = X_raw[..., 15]

    f_lf = i_lf * force_gain
    f_rr = i_rr * force_gain
    f_long = f_lf + f_rr
    f_diff = f_lf - f_rr
    f_roll = c_roll * mass * gravity
    f_aero = 0.5 * rho * cda * v_hat * v_hat * np.sign(v_hat)
    f_res = (f_long - m_eff * dv_hat_dt_lp - f_roll - f_aero) / force_scale

    yaw_drive_accel = (0.5 * width * f_diff) / max(iz, 1e-6)
    gyro_dot = np.zeros_like(gyro_z, dtype=np.float32)
    gyro_dot[:, 1:] = (gyro_z[:, 1:] - gyro_z[:, :-1]) / max(ts, 1e-6)
    yaw_accel_est = _causal_ema(gyro_dot, ts, yaw_tau, init_zero=True)
    yaw_residual = yaw_accel_est - yaw_drive_accel

    out = np.stack(
        [
            f_long / force_scale,
            f_diff / force_scale,
            f_res,
            _causal_ema(f_res, ts, 0.3),
            _causal_ema(f_res, ts, 0.8),
            yaw_drive_accel,
            yaw_residual,
            _causal_ema(yaw_residual, ts, 0.3),
        ],
        axis=-1,
    )
    if not np.all(np.isfinite(out)):
        raise ValueError("physics_residual_8 produced non-finite values")
    return out.astype(np.float32, copy=False)


def _lagged_edge(X: np.ndarray, lag: int) -> np.ndarray:
    _, seq_len, _ = X.shape
    _validate_lag(lag, seq_len)
    out = np.empty_like(X, dtype=np.float32)
    out[:, :lag, :] = X[:, :1, :]
    out[:, lag:, :] = X[:, :-lag, :]
    return out


def _clip_delta(delta: np.ndarray, clip_abs: float) -> np.ndarray:
    return np.clip(delta, -float(clip_abs), float(clip_abs)).astype(np.float32, copy=False)


def _causal_ema(x: np.ndarray, ts: float, tau: float, *, init_zero: bool = False) -> np.ndarray:
    x_arr = np.asarray(x, dtype=np.float32)
    if x_arr.ndim != 2:
        raise ValueError(f"expected [N,T] for causal EMA, got {x_arr.shape}")
    tau = max(float(tau), 1e-6)
    alpha = float(ts) / (tau + float(ts))
    out = np.empty_like(x_arr, dtype=np.float32)
    if x_arr.shape[1] == 0:
        return out
    out[:, 0] = 0.0 if init_zero else x_arr[:, 0]
    for t in range(1, x_arr.shape[1]):
        out[:, t] = alpha * x_arr[:, t] + (1.0 - alpha) * out[:, t - 1]
    return out


def _vector_from(value: object, expected_len: int, name: str) -> np.ndarray:
    if value is None:
        raise ValueError(f"missing {name}")
    arr = np.asarray(value, dtype=np.float32).reshape(-1)
    if arr.size != int(expected_len):
        raise ValueError(f"{name} must have length {expected_len}, got {arr.size}")
    if not np.all(np.isfinite(arr)):
        raise ValueError(f"{name} contains non-finite values")
    return arr.astype(np.float32, copy=False)


def _float_list(value: np.ndarray) -> List[float]:
    return [float(x) for x in np.asarray(value, dtype=np.float32).reshape(-1)]


def _physics_params(metadata: Dict[str, object]) -> Dict[str, float]:
    raw = metadata.get("physics_params", {})
    params = dict(DEFAULT_PHYSICS_PARAMS)
    if isinstance(raw, dict):
        for key in params:
            if key in raw:
                params[key] = float(raw[key])
    for key, value in params.items():
        if not np.isfinite(float(value)):
            raise ValueError(f"physics param {key} is not finite: {value}")
    return params


def _validate_lag(lag: int, seq_len: int) -> None:
    if lag <= 0:
        raise ValueError("lag must be positive")
    if lag >= seq_len:
        raise ValueError(f"lag must be < seq_len; got lag={lag}, T={seq_len}")


def _require_plantfix_22d(raw_input_dim: int, feature_contract: object, mode: str) -> None:
    if raw_input_dim != 22 or str(feature_contract) != "passive17_plus_all5":
        raise ValueError(
            f"{mode} experiment requires raw passive17_plus_all5 input_dim=22; "
            f"got feature_contract={feature_contract}, input_dim={raw_input_dim}"
        )


def _require_physics_feature_names(feature_names: Sequence[object]) -> None:
    names = [str(name) for name in feature_names]
    if names != PASSIVE22_FEATURE_NAMES:
        raise ValueError(
            "physics_residual_8 requires exact passive17_plus_all5 feature order; "
            f"got {names}"
        )
