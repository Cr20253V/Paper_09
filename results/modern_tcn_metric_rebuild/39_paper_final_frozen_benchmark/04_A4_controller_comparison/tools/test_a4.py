#!/usr/bin/env python3
"""Focused regression tests for the A4 pipeline."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

import numpy as np
import pandas as pd


HERE = Path(__file__).resolve()
A4 = HERE.parents[1]
RUNNER = HERE.parent / "run_a4.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("run_a4", RUNNER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class A4Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_runner()

    def test_effect_direction(self):
        class Row:
            path_id = "p"
            model_seed = 1
            ey_rmse = 2.0
        target = Row()
        comparator = Row()
        comparator.ey_rmse = 3.0
        result = self.m.effect_row(target, comparator, "ey_rmse")
        self.assertEqual(result["absolute_effect"], 1.0)
        self.assertGreater(result["relative_effect_pct"], 0)

    def test_bootstrap_reproducible(self):
        a5 = self.m.import_a5_module()
        effects = {(seed, path): float(seed + idx) for seed in (1, 2, 3) for idx, path in enumerate(("a", "b"))}
        one = a5.hierarchical_paired_bootstrap(effects, iterations=100, random_seed=42)
        two = a5.hierarchical_paired_bootstrap(effects, iterations=100, random_seed=42)
        self.assertEqual(one, two)

    def test_final_grid(self):
        table = A4 / "02_case_table/five_controller_case_table.csv"
        if not table.exists():
            self.skipTest("pipeline outputs not generated")
        df = pd.read_csv(table)
        self.assertEqual(len(df), 138)
        self.assertTrue(all(np.isfinite(pd.to_numeric(df[m], errors="coerce")).all() for m in self.m.PRIMARY_METRICS))
        self.assertFalse(df["path_id"].astype(str).str.startswith("supp_").any())

    def test_receipt_complete(self):
        receipt = A4 / "receipt.json"
        if not receipt.exists():
            self.skipTest("pipeline outputs not generated")
        data = self.m.load_json(receipt)
        self.assertEqual(data["status"], "COMPLETE")
        self.assertEqual(data["primary_case_count"], 138)


if __name__ == "__main__":
    unittest.main(verbosity=2)
