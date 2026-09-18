#!/usr/bin/env python3
from __future__ import annotations

import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from a5_statistical_audit import (
    CLOSED_LOOP_PRIMARY,
    audit_expected_grid,
    hierarchical_paired_bootstrap,
    lower_is_better_effect,
    pair_deterministic_reference,
    paired_seed_bootstrap,
    primary_claim_decision,
    require_output_within,
)


class A5StatisticsTests(unittest.TestCase):
    def test_seed_bootstrap_is_deterministic(self) -> None:
        values = {seed: 0.1 * seed for seed in range(1, 11)}
        self.assertEqual(
            paired_seed_bootstrap(values, iterations=500),
            paired_seed_bootstrap(values, iterations=500),
        )

    def test_hierarchical_bootstrap_is_deterministic_and_complete(self) -> None:
        values = {(seed, f"p{path}"): seed / 10 + path / 100 for seed in range(10) for path in range(6)}
        first = hierarchical_paired_bootstrap(values, iterations=500)
        second = hierarchical_paired_bootstrap(values, iterations=500)
        self.assertEqual(first, second)
        self.assertEqual(first["n_seeds"], 10)
        self.assertEqual(first["n_paths"], 6)

    def test_hierarchical_bootstrap_rejects_incomplete_paths(self) -> None:
        values = {(1, "p1"): 1.0, (1, "p2"): 2.0, (2, "p1"): 3.0}
        with self.assertRaisesRegex(ValueError, "same complete path set"):
            hierarchical_paired_bootstrap(values, iterations=10)

    def test_grid_audit_retains_missing_duplicate_unexpected_nonfinite(self) -> None:
        expected = [{"seed": 1, "path": "p1"}, {"seed": 1, "path": "p2"}]
        observed = [
            {"seed": 1, "path": "p1", "metric": 1.0},
            {"seed": 1, "path": "p1", "metric": 1.0},
            {"seed": 2, "path": "p9", "metric": math.nan},
        ]
        audit = audit_expected_grid(
            expected,
            observed,
            key_fields=("seed", "path"),
            required_finite_fields=("metric",),
        )
        self.assertFalse(audit["complete"])
        self.assertTrue(audit["missing"])
        self.assertTrue(audit["duplicates"])
        self.assertTrue(audit["unexpected"])
        self.assertTrue(audit["invalid"])

    def test_lower_is_better_direction_and_zero_denominator(self) -> None:
        effect = lower_is_better_effect(target=8.0, comparator=10.0)
        self.assertEqual(effect["absolute_effect"], 2.0)
        self.assertEqual(effect["relative_effect_pct"], 20.0)
        zero = lower_is_better_effect(target=1.0, comparator=0.0)
        self.assertTrue(math.isnan(zero["relative_effect_pct"]))

    def test_all_three_primary_metrics_required(self) -> None:
        supported = {metric: (0.01, 0.2) for metric in CLOSED_LOOP_PRIMARY}
        self.assertEqual(primary_claim_decision(supported), "SUPPORTED_ALL_PRIMARY")
        supported["j_du"] = (-0.01, 0.2)
        self.assertEqual(primary_claim_decision(supported), "INCONCLUSIVE")
        supported["j_du"] = (-0.2, -0.01)
        self.assertEqual(primary_claim_decision(supported), "NOT_SUPPORTED_PRIMARY_DEGRADATION")
        self.assertEqual(
            primary_claim_decision({metric: (0.01, 0.2) for metric in CLOSED_LOOP_PRIMARY}, safety_gate_failed=True),
            "NOT_SUPPORTED_SAFETY_GATE",
        )

    def test_deterministic_reference_has_one_unit_per_path(self) -> None:
        learning = [{"seed": seed, "path_id": path} for seed in (1, 7) for path in ("p1", "p2")]
        reference = [{"path_id": "p1"}, {"path_id": "p2"}]
        pairs = pair_deterministic_reference(learning, reference)
        self.assertEqual(len(pairs), 4)
        self.assertEqual(len({id(reference_row) for _, reference_row in pairs}), 2)

    def test_write_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "a5"
            root.mkdir()
            require_output_within(root / "ok.json", root)
            with self.assertRaisesRegex(ValueError, "outside A5"):
                require_output_within(Path(temp) / "outside.json", root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
