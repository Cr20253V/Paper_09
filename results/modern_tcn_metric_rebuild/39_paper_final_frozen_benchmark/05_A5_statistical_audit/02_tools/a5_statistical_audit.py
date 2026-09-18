#!/usr/bin/env python3
"""Frozen A5 statistical utilities and phase-2 readiness validator.

This module never runs simulations or rewrites A1--A4 artifacts.  It provides
the paired bootstrap, grid auditing, claim-decision, and source discovery
primitives frozen during A5 phase 1.  Phase 2 may write only below the A5
directory supplied to the CLI.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence

import numpy as np


BOOTSTRAP_ITERATIONS = 10_000
BOOTSTRAP_SEED = 20_260_715
CI_PERCENTILES = (2.5, 97.5)
CLOSED_LOOP_PRIMARY = ("ey_rmse", "epsi_rmse", "j_du")
TASK_IDS = ("A1", "A2", "A3", "A4")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def require_output_within(path: Path, a5_root: Path) -> None:
    if not is_relative_to(path, a5_root):
        raise ValueError(f"Refusing write outside A5 root: {path}")


def finite_float(value: Any) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def percentile_ci(samples: np.ndarray) -> tuple[float, float]:
    clean = np.asarray(samples, dtype=float)
    clean = clean[np.isfinite(clean)]
    if clean.size == 0:
        return math.nan, math.nan
    lo, hi = np.percentile(clean, CI_PERCENTILES)
    return float(lo), float(hi)


def paired_seed_bootstrap(
    effects_by_seed: Mapping[int, float],
    *,
    iterations: int = BOOTSTRAP_ITERATIONS,
    random_seed: int = BOOTSTRAP_SEED,
    statistic: Callable[[np.ndarray], float] = np.mean,
) -> dict[str, float]:
    """Bootstrap paired seed-level effects; positive always favors target."""
    seeds = sorted(effects_by_seed)
    if not seeds or any(not finite_float(effects_by_seed[s]) for s in seeds):
        raise ValueError("Seed effects must be non-empty and finite")
    values = np.asarray([float(effects_by_seed[s]) for s in seeds], dtype=float)
    rng = np.random.default_rng(random_seed)
    draws = np.empty(iterations, dtype=float)
    for idx in range(iterations):
        sampled = rng.integers(0, len(values), size=len(values))
        draws[idx] = float(statistic(values[sampled]))
    lo, hi = percentile_ci(draws)
    return {
        "estimate": float(statistic(values)),
        "bootstrap_mean": float(np.mean(draws)),
        "ci95_low": lo,
        "ci95_high": hi,
        "iterations": int(iterations),
        "random_seed": int(random_seed),
    }


def hierarchical_paired_bootstrap(
    effects: Mapping[tuple[int, str], float],
    *,
    iterations: int = BOOTSTRAP_ITERATIONS,
    random_seed: int = BOOTSTRAP_SEED,
) -> dict[str, float]:
    """Resample model seeds, then paths within each sampled seed.

    The input is already a paired target-vs-comparator effect for each
    (model_seed, path_id), so method pairing cannot be broken by resampling.
    """
    by_seed: dict[int, dict[str, float]] = defaultdict(dict)
    for (seed, path_id), value in effects.items():
        if path_id in by_seed[int(seed)]:
            raise ValueError(f"Duplicate effect for seed={seed}, path={path_id}")
        if not finite_float(value):
            raise ValueError(f"Non-finite effect for seed={seed}, path={path_id}")
        by_seed[int(seed)][str(path_id)] = float(value)
    seeds = sorted(by_seed)
    if not seeds:
        raise ValueError("No hierarchical effects")
    path_sets = {tuple(sorted(rows)) for rows in by_seed.values()}
    if len(path_sets) != 1:
        raise ValueError("All seeds must have the same complete path set")
    paths = list(next(iter(path_sets)))
    rng = np.random.default_rng(random_seed)
    draws = np.empty(iterations, dtype=float)
    for idx in range(iterations):
        sampled_seeds = rng.choice(seeds, size=len(seeds), replace=True)
        sampled_values: list[float] = []
        for seed in sampled_seeds:
            sampled_paths = rng.choice(paths, size=len(paths), replace=True)
            sampled_values.extend(by_seed[int(seed)][str(path)] for path in sampled_paths)
        draws[idx] = float(np.mean(sampled_values))
    raw = np.asarray(list(effects.values()), dtype=float)
    lo, hi = percentile_ci(draws)
    return {
        "estimate": float(np.mean(raw)),
        "bootstrap_mean": float(np.mean(draws)),
        "ci95_low": lo,
        "ci95_high": hi,
        "iterations": int(iterations),
        "random_seed": int(random_seed),
        "n_seeds": len(seeds),
        "n_paths": len(paths),
    }


def paired_path_bootstrap(
    effects_by_path: Mapping[str, float],
    *,
    iterations: int = BOOTSTRAP_ITERATIONS,
    random_seed: int = BOOTSTRAP_SEED,
) -> dict[str, float]:
    """Paired route-only bootstrap for deterministic A3 controllers."""
    paths = sorted(effects_by_path)
    if not paths or any(not finite_float(effects_by_path[p]) for p in paths):
        raise ValueError("Path effects must be non-empty and finite")
    values = np.asarray([float(effects_by_path[p]) for p in paths], dtype=float)
    rng = np.random.default_rng(random_seed)
    draws = np.empty(iterations, dtype=float)
    for idx in range(iterations):
        draws[idx] = float(np.mean(values[rng.integers(0, len(values), len(values))]))
    lo, hi = percentile_ci(draws)
    return {
        "estimate": float(np.mean(values)),
        "bootstrap_mean": float(np.mean(draws)),
        "ci95_low": lo,
        "ci95_high": hi,
        "iterations": int(iterations),
        "random_seed": int(random_seed),
        "n_paths": len(paths),
    }


def lower_is_better_effect(target: float, comparator: float) -> dict[str, float]:
    target_value = float(target)
    comparator_value = float(comparator)
    absolute = comparator_value - target_value
    relative = math.nan if comparator_value == 0 else 100.0 * absolute / comparator_value
    ratio = math.nan if comparator_value == 0 else target_value / comparator_value
    return {"absolute_effect": absolute, "relative_effect_pct": relative, "ratio": ratio}


def audit_expected_grid(
    expected_rows: Sequence[Mapping[str, Any]],
    observed_rows: Sequence[Mapping[str, Any]],
    *,
    key_fields: Sequence[str],
    required_finite_fields: Sequence[str] = (),
) -> dict[str, Any]:
    """Outer-grid audit that retains every missing, duplicate, and extra key."""

    def key(row: Mapping[str, Any]) -> tuple[str, ...]:
        return tuple(str(row.get(field, "")) for field in key_fields)

    expected_keys = [key(row) for row in expected_rows]
    observed_keys = [key(row) for row in observed_rows]
    expected_set, observed_set = set(expected_keys), set(observed_keys)
    duplicates = sorted(k for k, count in Counter(observed_keys).items() if count > 1)
    missing = sorted(expected_set - observed_set)
    unexpected = sorted(observed_set - expected_set)
    invalid: list[dict[str, Any]] = []
    for row in observed_rows:
        bad = [field for field in required_finite_fields if not finite_float(row.get(field))]
        if bad:
            invalid.append({"key": key(row), "nonfinite_fields": bad})
    complete = not missing and not unexpected and not duplicates and not invalid
    return {
        "complete": complete,
        "expected_count": len(expected_keys),
        "observed_count": len(observed_keys),
        "unique_observed_count": len(observed_set),
        "missing": missing,
        "unexpected": unexpected,
        "duplicates": duplicates,
        "invalid": invalid,
    }


def primary_claim_decision(
    ci_by_metric: Mapping[str, tuple[float, float]],
    *,
    required_metrics: Sequence[str] = CLOSED_LOOP_PRIMARY,
    safety_gate_failed: bool = False,
    complete_grid: bool = True,
) -> str:
    if not complete_grid:
        return "INCOMPLETE_GRID"
    if safety_gate_failed:
        return "NOT_SUPPORTED_SAFETY_GATE"
    missing = [metric for metric in required_metrics if metric not in ci_by_metric]
    if missing:
        return "INCONCLUSIVE_MISSING_PRIMARY"
    intervals = [ci_by_metric[metric] for metric in required_metrics]
    if any(not finite_float(lo) or not finite_float(hi) for lo, hi in intervals):
        return "INCONCLUSIVE_NONFINITE_CI"
    if all(float(lo) > 0 for lo, _ in intervals):
        return "SUPPORTED_ALL_PRIMARY"
    if any(float(hi) < 0 for _, hi in intervals):
        return "NOT_SUPPORTED_PRIMARY_DEGRADATION"
    return "INCONCLUSIVE"


def pair_deterministic_reference(
    learning_rows: Sequence[Mapping[str, Any]],
    reference_rows: Sequence[Mapping[str, Any]],
    *,
    path_field: str = "path_id",
) -> list[tuple[Mapping[str, Any], Mapping[str, Any]]]:
    """Pair one deterministic reference row per path without cloning its unit."""
    reference = {str(row[path_field]): row for row in reference_rows}
    if len(reference) != len(reference_rows):
        raise ValueError("Deterministic reference must have exactly one row per path")
    pairs = []
    for row in learning_rows:
        path_id = str(row[path_field])
        if path_id not in reference:
            raise ValueError(f"Missing deterministic reference for path={path_id}")
        pairs.append((row, reference[path_id]))
    return pairs


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def discover_source_manifests(node39_root: Path, a5_root: Path) -> dict[str, list[Path]]:
    found: dict[str, list[Path]] = {task: [] for task in TASK_IDS}
    if not node39_root.is_dir():
        return found
    candidates = list(node39_root.rglob("source_manifest.json")) + list(node39_root.rglob("run_manifest.json"))
    for path in sorted(set(candidates)):
        if is_relative_to(path, a5_root):
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        task_id = str(payload.get("task_id", "")).upper()
        if task_id in found:
            found[task_id].append(path)
    return found


def phase2_readiness(node39_root: Path, a5_root: Path) -> dict[str, Any]:
    discovered = discover_source_manifests(node39_root, a5_root)
    blockers = []
    for task_id in TASK_IDS:
        paths = discovered[task_id]
        if not paths:
            blockers.append({"task_id": task_id, "reason": "SOURCE_MANIFEST_MISSING"})
        elif len(paths) > 1:
            blockers.append(
                {"task_id": task_id, "reason": "MULTIPLE_SOURCE_MANIFESTS", "paths": [str(p) for p in paths]}
            )
    return {
        "status": "READY" if not blockers else "WAITING_FOR_A1_A4",
        "sources": {task: [str(path) for path in paths] for task, paths in discovered.items()},
        "blockers": blockers,
    }


def self_check() -> dict[str, Any]:
    seed_effects = {seed: float(seed) / 100 for seed in range(1, 11)}
    first = paired_seed_bootstrap(seed_effects, iterations=200)
    second = paired_seed_bootstrap(seed_effects, iterations=200)
    hierarchy = {(seed, f"p{path}"): seed + path / 10 for seed in range(1, 11) for path in range(1, 7)}
    h1 = hierarchical_paired_bootstrap(hierarchy, iterations=200)
    h2 = hierarchical_paired_bootstrap(hierarchy, iterations=200)
    return {
        "paired_bootstrap_deterministic": first == second,
        "hierarchical_bootstrap_deterministic": h1 == h2,
        "claim_rule": primary_claim_decision({metric: (0.01, 0.2) for metric in CLOSED_LOOP_PRIMARY}),
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="A5 frozen statistical audit utility")
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--readiness", action="store_true")
    parser.add_argument("--node39-root", type=Path)
    parser.add_argument("--a5-root", type=Path)
    args = parser.parse_args(argv)
    if args.self_check:
        result = self_check()
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if all(value is True or value == "SUPPORTED_ALL_PRIMARY" for value in result.values()) else 1
    if args.readiness:
        if args.node39_root is None or args.a5_root is None:
            parser.error("--readiness requires --node39-root and --a5-root")
        print(json.dumps(phase2_readiness(args.node39_root, args.a5_root), indent=2, ensure_ascii=False))
        return 0
    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
