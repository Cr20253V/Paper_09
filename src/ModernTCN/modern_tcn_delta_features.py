"""Delta-lag input augmentation for ModernTCN experiments.

The augmentation is intentionally Python-only: it operates on the normalized
MAT split arrays after the fixed dataset contract has already been checked.
"""

from __future__ import annotations

from dataclasses import asdict, replace
from typing import Dict, List

import numpy as np

from modern_tcn_data import SplitArrays


def augment_with_delta_lag(X: np.ndarray, lag: int, pad: str = "zero") -> np.ndarray:
    """Return ``[X, X - lag(X, m)]`` for a causal in-window lag.

    Parameters
    ----------
    X:
        Window array shaped ``[N, T, F]``.
    lag:
        Positive lag in time steps. Must be smaller than ``T``.
    pad:
        Only ``"zero"`` is supported. The first ``lag`` delta rows are zero.
    """

    X_arr = np.asarray(X, dtype=np.float32)
    if X_arr.ndim != 3:
        raise ValueError(f"expected [N,T,F], got {X_arr.shape}")
    _, seq_len, _ = X_arr.shape
    lag = int(lag)
    if lag <= 0:
        raise ValueError("delta lag must be positive")
    if lag >= seq_len:
        raise ValueError(f"delta lag must be < seq_len; got lag={lag}, T={seq_len}")
    if str(pad).lower() != "zero":
        raise ValueError("this experiment only supports zero padding")

    delta = np.zeros_like(X_arr, dtype=np.float32)
    delta[:, lag:, :] = X_arr[:, lag:, :] - X_arr[:, :-lag, :]
    return np.concatenate([X_arr, delta], axis=-1).astype(np.float32, copy=False)


def augment_split_arrays(split: SplitArrays, lag: int, pad: str = "zero") -> SplitArrays:
    """Return a split copy with only ``X`` replaced by delta-lag features."""

    return replace(split, X=augment_with_delta_lag(split.X, lag=lag, pad=pad))


def augmented_feature_names(feature_names: List[str]) -> List[str]:
    """Return feature names for ``[raw, delta]`` ordering."""

    raw = [str(name) for name in feature_names]
    return raw + [f"delta_{name}" for name in raw]


def delta_lag_stats(split: SplitArrays, raw_input_dim: int) -> Dict[str, float]:
    """Summarize the appended delta block for audit metadata."""

    delta = np.asarray(split.X[..., raw_input_dim:], dtype=np.float32)
    if delta.size == 0:
        return {"delta_mean": float("nan"), "delta_std": float("nan"), "delta_p95_abs": float("nan")}
    return {
        "delta_mean": float(np.mean(delta)),
        "delta_std": float(np.std(delta)),
        "delta_p95_abs": float(np.percentile(np.abs(delta), 95)),
    }


def delta_lag_metadata(lag: int, pad: str = "zero") -> Dict[str, object]:
    """Return a compact metadata block for 44D bridge scripts."""

    lag = int(lag)
    pad = str(pad)
    return {
        "input_augment": "delta_lag",
        "delta_lag": lag,
        "delta_pad": pad,
        "method": "[x_t, x_t - x_{t-m}]",
        "normalization": "delta_from_normalized_X_without_extra_scaler",
    }


def split_delta_metadata(split: SplitArrays, raw_input_dim: int) -> Dict[str, float]:
    """Backward-compatible alias for the current split delta statistics."""

    return delta_lag_stats(split, raw_input_dim)
