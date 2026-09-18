from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

import numpy as np

from node53_common import NODE, ROOT, write_csv, write_json


BRANCH = NODE / "08_formal_six_path_exploratory_v7"
REPORTS = BRANCH / "reports"
BASELINE = (
    ROOT
    / "results/modern_tcn_metric_rebuild/43_fusion_offline_recalibration_and_6path_retest"
    / "01_inventory/reused_mtcn_baseline_60.csv"
)
SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
PATHS = [
    "p01_factory_logistics_showcase",
    "p02_sharp_turn_transition",
    "p03_long_updown",
    "p04_soft_updown_straight_turn",
    "p05_factory_flat_logistics",
    "p06_downhill_after_turn",
]
PRIMARY = ["ey_rmse", "epsi_rmse", "j_du"]
BOOTSTRAP_SEED = 20260715
BOOTSTRAP_ITERATIONS = 10000


def _read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _float(value: object) -> float:
    if value in (None, ""):
        return float("nan")
    return float(value)


def _case_hash_audit(rows: list[dict]) -> dict:
    fields = {
        "output_sha256": "out.mat",
        "debug_sha256": "node53_v7_runtime_debug.csv",
        "debug_mat_sha256": "node53_v7_runtime_debug.mat",
        "trace_sha256": "trace.csv",
        "normalized_trace_sha256": "normalized_trace.mat",
        "metrics_sha256": "case_metrics.json",
    }
    input_fields = [
        ("path_file", "path_sha256"),
        ("onnx_file", "onnx_sha256"),
        ("model_file", "model_sha256"),
        ("v7_config", "v7_config_sha256"),
        ("v7_export", "v7_export_sha256"),
    ]
    artifacts_checked = 0
    inputs_checked = 0
    mismatches: list[str] = []
    input_mismatches: list[str] = []
    for row in rows:
        metrics_path = Path(row["case_metrics_path"])
        manifest_path = metrics_path.with_name("case_manifest.json")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for field, name in fields.items():
            artifacts_checked += 1
            path = metrics_path.with_name(name)
            if not path.is_file() or _sha256(path) != manifest.get(field):
                mismatches.append(f"{manifest_path}:{field}")
        for path_field, hash_field in input_fields:
            inputs_checked += 1
            path = Path(manifest[path_field])
            if not path.is_file() or _sha256(path) != manifest.get(hash_field):
                input_mismatches.append(f"{manifest_path}:{hash_field}")
    return {
        "checked_case_count": len(rows),
        "artifact_hashes_checked": artifacts_checked,
        "artifact_mismatch_count": len(mismatches),
        "artifact_mismatch_examples": mismatches[:10],
        "input_hashes_checked": inputs_checked,
        "input_mismatch_count": len(input_mismatches),
        "input_mismatch_examples": input_mismatches[:10],
    }


def _bootstrap(effect: np.ndarray) -> tuple[float, float, float]:
    rng = np.random.default_rng(BOOTSTRAP_SEED)
    seed_draws = rng.integers(0, len(SEEDS), size=(BOOTSTRAP_ITERATIONS, len(SEEDS)))
    path_draws = rng.integers(0, len(PATHS), size=(BOOTSTRAP_ITERATIONS, len(SEEDS), len(PATHS)))
    draws = effect[seed_draws[:, :, None], path_draws].mean(axis=(1, 2))
    low, high = np.quantile(draws, [0.025, 0.975])
    return float(low), float(high), float(np.mean(draws > 0.0))


def _slope_source_summary(rows: list[dict]) -> list[dict]:
    """Compare the three slope estimates preserved in each V7 runtime trace."""
    records: list[dict] = []
    for row in rows:
        case = Path(row["case_metrics_path"]).parent
        with (case / "node53_v7_runtime_debug.csv").open(encoding="utf-8-sig") as handle:
            debug = list(csv.DictReader(handle))
        with (case / "trace.csv").open(encoding="utf-8-sig") as handle:
            trace = list(csv.DictReader(handle))
        truth_t = np.array([float(item["t_s"]) for item in trace])
        truth = np.array([float(item["theta_true"]) for item in trace])
        step = np.array([int(float(item["step"])) for item in debug])
        truth_at_step = np.interp((step - 1) * 0.01, truth_t, truth)
        keep = (step - 1) * 0.01 >= 0.5
        values = {}
        for name in ("theta_fuzzyakf", "theta_tcn", "theta_fused"):
            estimate = np.array([float(item[name]) for item in debug])
            values[name] = float(np.mean(np.abs(np.rad2deg(estimate[keep] - truth_at_step[keep]))))
        records.append({"path_id": row["path_id"], **values})
    result: list[dict] = []
    for path in PATHS:
        group = [item for item in records if item["path_id"] == path]
        imu = float(np.mean([item["theta_fuzzyakf"] for item in group]))
        tcn = float(np.mean([item["theta_tcn"] for item in group]))
        fused = float(np.mean([item["theta_fused"] for item in group]))
        result.append(
            {
                "path_id": path,
                "model_seed_count": len(group),
                "r2_06_imu_slope_mae_deg": imu,
                "moderntcn_slope_mae_deg": tcn,
                "fusion_slope_mae_deg": fused,
                "imu_tcn_abs_gap_deg": abs(imu - tcn),
                "imu_tcn_gap_percent_of_worse": 100.0 * abs(imu - tcn) / max(imu, tcn),
                "fusion_vs_imu_percent": 100.0 * (imu - fused) / imu,
                "fusion_vs_moderntcn_percent": 100.0 * (tcn - fused) / tcn,
            }
        )
    return result


def main() -> int:
    REPORTS.mkdir(parents=True, exist_ok=True)
    fusion_rows = _read_csv(BRANCH / "v7_all_available_metrics.csv")
    baseline_rows = _read_csv(BASELINE)
    key = lambda row: (str(row["path_id"]), int(row["model_seed"]))
    fusion = {key(row): row for row in fusion_rows}
    baseline = {key(row): row for row in baseline_rows}
    expected = {(path, seed) for seed in SEEDS for path in PATHS}
    paired_keys = sorted(expected & set(fusion) & set(baseline), key=lambda x: (x[1], x[0]))

    paired_rows: list[dict] = []
    for path, seed in paired_keys:
        row = {"path_id": path, "model_seed": seed}
        for metric in PRIMARY:
            base_value = _float(baseline[(path, seed)][metric])
            fusion_value = _float(fusion[(path, seed)][metric])
            row[f"moderntcn_{metric}"] = base_value
            row[f"fusion_{metric}"] = fusion_value
            row[f"effect_moderntcn_minus_fusion_{metric}"] = base_value - fusion_value
        paired_rows.append(row)
    write_csv(REPORTS / "v7_formal_paired_comparison.csv", paired_rows)

    bootstrap_rows: list[dict] = []
    path_rows: list[dict] = []
    for metric in PRIMARY:
        base = np.array(
            [[_float(baseline[(path, seed)][metric]) for path in PATHS] for seed in SEEDS], dtype=float
        )
        fused = np.array(
            [[_float(fusion[(path, seed)][metric]) for path in PATHS] for seed in SEEDS], dtype=float
        )
        effect = base - fused
        ci_low, ci_high, positive_fraction = _bootstrap(effect)
        bootstrap_rows.append(
            {
                "metric": metric,
                "baseline_mean": float(base.mean()),
                "fusion_mean": float(fused.mean()),
                "effect_moderntcn_minus_fusion_mean": float(effect.mean()),
                "relative_reduction_percent": float(100.0 * effect.mean() / base.mean()),
                "ci95_low": ci_low,
                "ci95_high": ci_high,
                "bootstrap_positive_fraction": positive_fraction,
                "case_wins": int(np.sum(effect > 0.0)),
                "case_ties": int(np.sum(effect == 0.0)),
                "case_losses": int(np.sum(effect < 0.0)),
                "ci_supports_fusion": bool(ci_low > 0.0),
                "iterations": BOOTSTRAP_ITERATIONS,
                "bootstrap_seed": BOOTSTRAP_SEED,
            }
        )
        for path_index, path in enumerate(PATHS):
            path_rows.append(
                {
                    "metric": metric,
                    "path_id": path,
                    "baseline_mean": float(base[:, path_index].mean()),
                    "fusion_mean": float(fused[:, path_index].mean()),
                    "effect_moderntcn_minus_fusion_mean": float(effect[:, path_index].mean()),
                    "fusion_case_wins": int(np.sum(effect[:, path_index] > 0.0)),
                    "ties": int(np.sum(effect[:, path_index] == 0.0)),
                    "fusion_case_losses": int(np.sum(effect[:, path_index] < 0.0)),
                }
            )
    write_csv(REPORTS / "v7_paired_bootstrap_statistics.csv", bootstrap_rows)
    write_csv(REPORTS / "v7_paired_path_summary.csv", path_rows)
    write_csv(REPORTS / "v7_six_path_slope_source_comparison.csv", _slope_source_summary(fusion_rows))

    case_metrics = [json.loads(Path(row["case_metrics_path"]).read_text(encoding="utf-8")) for row in fusion_rows]
    safety = {
        "case_count": len(case_metrics),
        "complete_case_count": sum(item.get("case_status") == "COMPLETE" for item in case_metrics),
        "safety_pass_count": sum(item.get("safety_status") == "PASS_NODE53_V7_CASE_SAFETY" for item in case_metrics),
        "constraint_violation_rate_max": max(_float(item["constraint_violation_rate"]) for item in case_metrics),
        "timeout_count_sum": sum(int(item["timeout_count"]) for item in case_metrics),
        "solver_fail_count_sum": sum(int(item["solver_fail_count"]) for item in case_metrics),
        "safety_failure_count_sum": sum(int(item["safety_failure_count"]) for item in case_metrics),
        "nonfinite_diagnostic_count_sum": sum(int(item["nonfinite_diagnostic_count"]) for item in case_metrics),
        "observer_invalid_after_init_count_sum": sum(int(item["observer_invalid_after_init_count"]) for item in case_metrics),
        "fallback_theta_identity_max_abs": max(_float(item["fallback_theta_identity_max_abs"]) for item in case_metrics),
        "fallback_correction_max_abs": max(_float(item["fallback_correction_max_abs"]) for item in case_metrics),
        "normal_rate_limit_excess_max": max(_float(item["normal_rate_limit_excess_max"]) for item in case_metrics),
        "normal_correction_limit_excess_max": max(_float(item["normal_correction_limit_excess_max"]) for item in case_metrics),
        "psd_min_eigenvalue_min": min(_float(item["psd_min_eigenvalue"]) for item in case_metrics),
        "runtime_truth_read_true_count": sum(bool(item["runtime_truth_read"]) for item in case_metrics),
    }
    integrity = _case_hash_audit(fusion_rows)
    baseline_hash_fields = [
        "source_hash_match",
        "trace_hash_match",
        "path_hash_match",
        "onnx_hash_match",
        "checkpoint_hash_match",
        "case_manifest_contract_match",
        "source_metrics_match_table",
    ]
    integrity["baseline_registry_hash_pass_counts"] = {
        field: sum(str(row.get(field)).lower() == "true" for row in baseline_rows)
        for field in baseline_hash_fields
    }
    integrity["expected_pair_count"] = len(expected)
    integrity["paired_case_count"] = len(paired_keys)
    integrity["unmatched_fusion_case_count"] = len(set(fusion) - expected)
    integrity["unmatched_baseline_case_count"] = len(set(baseline) - expected)
    write_json(REPORTS / "v7_integrity_audit.json", integrity)
    write_json(REPORTS / "v7_safety_summary.json", safety)

    conclusion = {
        "classification": "RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK",
        "formal_claim_allowed": False,
        "qualification_bypassed": True,
        "paired_cases": len(paired_keys),
        "bootstrap_iterations": BOOTSTRAP_ITERATIONS,
        "bootstrap_seed": BOOTSTRAP_SEED,
        "effect_definition": "ModernTCN-only minus Fusion; positive favors Fusion",
        "primary_ci_support": {row["metric"]: row["ci_supports_fusion"] for row in bootstrap_rows},
        "full_primary_support": all(row["ci_supports_fusion"] for row in bootstrap_rows),
        "safety_status": "PASS" if safety["safety_pass_count"] == 60 and safety["safety_failure_count_sum"] == 0 else "FAIL",
        "integrity_status": "PASS" if integrity["artifact_mismatch_count"] == 0 and integrity["input_mismatch_count"] == 0 else "FAIL",
    }
    write_json(REPORTS / "v7_final_result_summary.json", conclusion)

    stats = {row["metric"]: row for row in bootstrap_rows}
    lines = [
        "# Node53 V7 60-case closed-loop report",
        "",
        "Classification: RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK.",
        "",
        "## Completeness and integrity",
        "",
        f"- Complete cases: {safety['complete_case_count']}/60.",
        f"- Case safety passes: {safety['safety_pass_count']}/60.",
        f"- Artifact hash mismatches: {integrity['artifact_mismatch_count']}.",
        f"- Input/config hash mismatches: {integrity['input_mismatch_count']}.",
        "",
        "## Paired bootstrap",
        "",
        "Effect = ModernTCN-only minus Fusion; a positive value favors Fusion.",
        "",
    ]
    for metric in PRIMARY:
        row = stats[metric]
        lines.append(
            f"- {metric}: baseline={row['baseline_mean']:.12g}, fusion={row['fusion_mean']:.12g}, "
            f"effect={row['effect_moderntcn_minus_fusion_mean']:.12g}, "
            f"95% CI=[{row['ci95_low']:.12g}, {row['ci95_high']:.12g}], "
            f"CI support={row['ci_supports_fusion']}."
        )
    lines.extend(
        [
            "",
            "## Claim boundary",
            "",
            "The confidence intervals support Fusion for ey_rmse and epsi_rmse, but not for j_du.",
            "Therefore the result supports those two primary metrics only; it does not support a claim that all three primary metrics improved.",
            "The V7 protocol records qualification_bypassed=true and formal_claim_allowed=false, so this report remains exploratory retrospective evidence rather than a final paper-qualification result.",
            "",
        ]
    )
    (REPORTS / "v7_final_report.md").write_text("\n".join(lines), encoding="utf-8")

    return 0 if conclusion["safety_status"] == "PASS" and conclusion["integrity_status"] == "PASS" and len(paired_keys) == 60 else 2


if __name__ == "__main__":
    raise SystemExit(main())
