"""Confidence-aware theta scheduling utilities for SCI E5.

This module is deliberately deployment-side only: it consumes cached baseline
predictions and returns a filtered scheduling signal.  It does not train,
export, or mutate model checkpoints.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, List, Sequence

import numpy as np


@dataclass(frozen=True)
class SchedulingSpec:
    tag: str
    confidence_mode: str
    conf_threshold: float
    delta_theta_max_deg_per_step: float
    offline_only: bool = False


@dataclass(frozen=True)
class SchedulingResult:
    theta_sched_deg: np.ndarray
    confidence: np.ndarray
    c_eff: np.ndarray
    low_conf_flag: np.ndarray
    rate_limit_hit_flag: np.ndarray
    segment_id: np.ndarray
    advisory_step_metrics: bool
    segment_count: int


def softmax_np(logits: np.ndarray) -> np.ndarray:
    z = np.asarray(logits, dtype=np.float64)
    z = z - np.max(z, axis=1, keepdims=True)
    exp_z = np.exp(z)
    return exp_z / np.sum(exp_z, axis=1, keepdims=True)


def confidence_from_logits(logits_main: np.ndarray, logits_turn: np.ndarray, mode: str) -> Dict[str, np.ndarray]:
    prob_main = softmax_np(logits_main)
    prob_turn = softmax_np(logits_turn)
    main_conf = np.max(prob_main, axis=1)
    turn_conf = np.max(prob_turn, axis=1)
    mode_norm = str(mode).strip().lower()
    if mode_norm in {"main_conf", "main"}:
        conf = main_conf
    elif mode_norm in {"main_turn_conf", "mainturn", "main_conf*turn_conf"}:
        conf = main_conf * turn_conf
    elif mode_norm in {"none", "rate_limit_only"}:
        conf = np.ones_like(main_conf)
    else:
        raise ValueError(f"Unknown confidence_mode: {mode}")
    return {
        "confidence": conf.astype(np.float64),
        "main_conf": main_conf.astype(np.float64),
        "turn_conf": turn_conf.astype(np.float64),
        "prob_main": prob_main.astype(np.float64),
        "prob_turn": prob_turn.astype(np.float64),
    }


def contiguous_segments(run_id: Sequence[float]) -> np.ndarray:
    """Return a segment id that resets whenever adjacent run_id changes."""

    run_id_arr = np.asarray(run_id).reshape(-1)
    if run_id_arr.size == 0:
        return np.zeros(0, dtype=np.int64)
    seg = np.zeros(run_id_arr.size, dtype=np.int64)
    current = 0
    for i in range(1, run_id_arr.size):
        if run_id_arr[i] != run_id_arr[i - 1]:
            current += 1
        seg[i] = current
    return seg


def run_ids_are_contiguous(run_id: Sequence[float]) -> bool:
    """Return True only if every run_id appears in a single contiguous block."""

    run_id_arr = np.asarray(run_id).reshape(-1)
    seen_done = set()
    sentinel = object()
    active = sentinel
    for value in run_id_arr:
        key = float(value)
        if key != active:
            if key in seen_done:
                return False
            if active is not sentinel:
                seen_done.add(float(active))
            active = key
    return True


def apply_confidence_scheduling(
    theta_hat_deg: Sequence[float],
    logits_main: np.ndarray,
    logits_turn: np.ndarray,
    run_id: Sequence[float],
    spec: SchedulingSpec,
) -> SchedulingResult:
    """Apply confidence fallback and per-step rate limiting.

    Each contiguous replay segment is initialized from the first raw theta value.
    No state is inherited across run_id changes.
    """

    theta_raw = np.asarray(theta_hat_deg, dtype=np.float64).reshape(-1)
    if theta_raw.size == 0:
        raise ValueError("theta_hat_deg is empty")
    conf_pack = confidence_from_logits(logits_main, logits_turn, spec.confidence_mode)
    confidence = conf_pack["confidence"]
    if confidence.shape[0] != theta_raw.shape[0]:
        raise ValueError("confidence length does not match theta_hat length")
    run_id_arr = np.asarray(run_id).reshape(-1)
    if run_id_arr.shape[0] != theta_raw.shape[0]:
        raise ValueError("run_id length does not match theta_hat length")

    segment_id = contiguous_segments(run_id_arr)
    delta_max = float(spec.delta_theta_max_deg_per_step)
    if not np.isfinite(delta_max) or delta_max <= 0:
        raise ValueError(f"delta_theta_max_deg_per_step must be positive, got {delta_max}")

    theta_sched = np.zeros_like(theta_raw, dtype=np.float64)
    c_eff = np.zeros_like(theta_raw, dtype=np.float64)
    low_conf = np.zeros(theta_raw.size, dtype=bool)
    rate_hit = np.zeros(theta_raw.size, dtype=bool)

    for seg in np.unique(segment_id):
        idx = np.flatnonzero(segment_id == seg)
        if idx.size == 0:
            continue
        first = int(idx[0])
        theta_sched[first] = theta_raw[first]
        if spec.confidence_mode in {"none", "rate_limit_only"}:
            c_eff[first] = 1.0
        else:
            low_conf[first] = confidence[first] < float(spec.conf_threshold)
            c_eff[first] = 0.0 if low_conf[first] else confidence[first]
        for pos in idx[1:]:
            pos = int(pos)
            prev = theta_sched[pos - 1]
            if spec.confidence_mode in {"none", "rate_limit_only"}:
                low_conf[pos] = False
                c = 1.0
            else:
                low_conf[pos] = confidence[pos] < float(spec.conf_threshold)
                c = 0.0 if low_conf[pos] else confidence[pos]
            c_eff[pos] = c
            blended = c * theta_raw[pos] + (1.0 - c) * prev
            delta = blended - prev
            clipped_delta = np.clip(delta, -delta_max, delta_max)
            theta_sched[pos] = prev + clipped_delta
            rate_hit[pos] = bool(abs(delta - clipped_delta) > 1e-12)

    advisory = not run_ids_are_contiguous(run_id_arr)
    return SchedulingResult(
        theta_sched_deg=theta_sched,
        confidence=confidence,
        c_eff=c_eff,
        low_conf_flag=low_conf,
        rate_limit_hit_flag=rate_hit,
        segment_id=segment_id,
        advisory_step_metrics=advisory,
        segment_count=int(np.max(segment_id) + 1),
    )


def step_abs_diffs_by_segment(values: Sequence[float], segment_id: Sequence[int]) -> np.ndarray:
    values_arr = np.asarray(values, dtype=np.float64).reshape(-1)
    seg_arr = np.asarray(segment_id).reshape(-1)
    parts: List[np.ndarray] = []
    for seg in np.unique(seg_arr):
        idx = np.flatnonzero(seg_arr == seg)
        if idx.size >= 2:
            parts.append(np.abs(np.diff(values_arr[idx])))
    if not parts:
        return np.zeros(0, dtype=np.float64)
    return np.concatenate(parts)


def finite_percentile(values: Sequence[float], pct: float) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.percentile(arr, pct))


def finite_mean(values: Sequence[float]) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.mean(arr))


def finite_max(values: Sequence[float]) -> float:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return float("nan")
    return float(np.max(arr))


def confidence_distribution(values: Sequence[float], prefix: str) -> Dict[str, float]:
    arr = np.asarray(values, dtype=np.float64)
    return {
        f"{prefix}_mean": finite_mean(arr),
        f"{prefix}_p10": finite_percentile(arr, 10),
        f"{prefix}_p50": finite_percentile(arr, 50),
        f"{prefix}_p90": finite_percentile(arr, 90),
        f"{prefix}_low_0p60_ratio": float(np.mean(arr < 0.60)),
        f"{prefix}_low_0p70_ratio": float(np.mean(arr < 0.70)),
    }


def row_order_segment_audit(run_id: Sequence[float]) -> Dict[str, object]:
    run_id_arr = np.asarray(run_id).reshape(-1)
    segment_id = contiguous_segments(run_id_arr)
    unique_run_ids = np.unique(run_id_arr)
    per_run_segments = {}
    for rid in unique_run_ids:
        per_run_segments[str(float(rid))] = int(np.unique(segment_id[run_id_arr == rid]).size)
    noncontig = {k: v for k, v in per_run_segments.items() if v > 1}
    return {
        "n_windows": int(run_id_arr.size),
        "n_unique_run_id": int(unique_run_ids.size),
        "n_contiguous_segments": int(np.unique(segment_id).size),
        "run_ids_are_contiguous": len(noncontig) == 0,
        "n_noncontiguous_run_id": int(len(noncontig)),
        "sample_noncontiguous_run_id": dict(list(noncontig.items())[:10]),
        "advisory_step_metrics": len(noncontig) > 0,
        "note": "step and smoothness metrics are advisory when run_id is interleaved",
    }
