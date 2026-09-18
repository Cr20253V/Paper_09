from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import SEEDS, build_quality_model, build_tables, keys, load_case, replay_one, split_ids
from node53_stage4_supervised_gate_v6 import OUT, FEATURE_NAMES, fusion_metrics_v6, fit_fold_model, preregistered_candidates


FINAL_MODEL = OUT / "models/final_train_validation_hist_gradient_boosting.joblib"
FINAL_AUDIT = OUT / "final_model_training_audit.json"
FINAL_CONFIG = OUT / "selected_fusion_config_final_train_validation.json"
QUALIFICATION = OUT / "offline_qualification_v6.json"
STOP = OUT / "STOP_NODE53_V6_QUALIFICATION_FAILED.json"


def freeze_final() -> int:
    if FINAL_CONFIG.is_file() and FINAL_MODEL.is_file() and FINAL_AUDIT.is_file():
        return 0
    items = keys(); quality_model = build_quality_model(items); tables, table_audit = build_tables(items, quality_model); model, audit = fit_fold_model(99, items, quality_model)
    import joblib
    FINAL_MODEL.parent.mkdir(parents=True, exist_ok=True); joblib.dump(model, FINAL_MODEL)
    audit.update({"status": "PASS_NODE53_V6_FINAL_TRAIN_VALIDATION_MODEL", "training_scope": "71 train + 15 validation runs", "test_read": False, "formal_read": False, "model_path": str(FINAL_MODEL), "model_sha256": sha256(FINAL_MODEL), "table_psd": bool(table_audit["psd"]), "feature_names": FEATURE_NAMES})
    write_json(FINAL_AUDIT, audit)
    selected = json.loads((OUT / "selection_decision.json").read_text(encoding="utf-8"))["selected"]
    if not selected:
        raise RuntimeError("Node53 v6 has no selected development candidate")
    write_json(FINAL_CONFIG, {"status": "FROZEN_NODE53_V6_FINAL_TRAIN_VALIDATION_CONFIG", "selected": selected, "tables": tables, "quality_model": quality_model, "supervised_gate": {"model_family": "HistGradientBoostingClassifier", "feature_names": FEATURE_NAMES, "model_path": str(FINAL_MODEL), "model_sha256": sha256(FINAL_MODEL), "training_audit": str(FINAL_AUDIT)}, "test_read": False, "formal_read": False, "runtime_truth_read": False})
    return 0


def qualify_once() -> int:
    if QUALIFICATION.is_file():
        raise RuntimeError("Node53 v6 qualification is already finalized; test split is read-once")
    if not FINAL_CONFIG.is_file() or not FINAL_MODEL.is_file():
        raise FileNotFoundError("Run freeze_final before qualify_once")
    import joblib
    value = json.loads(FINAL_CONFIG.read_text(encoding="utf-8")); selected = value["selected"]; tables = value["tables"]; quality_model = value["quality_model"]; model = joblib.load(FINAL_MODEL); rows: list[dict[str, Any]] = []; diagnostics: list[dict[str, np.ndarray]] = []
    ids = split_ids()["test"]
    for run_id in ids:
        replay_path = replay_one("test", run_id)
        for seed in SEEDS:
            case = load_case("test", run_id, seed); metrics, diag = fusion_metrics_v6(case, tables, selected, quality_model, model); metrics["r2_06_mae_deg"] = float(np.rad2deg(np.mean(np.abs(case["theta_imu"] - case["truth"])))); diagnostics.append(diag); rows.append({"split": "test", "run_id": run_id, "model_seed": seed, **metrics, "replay_sha256": sha256(replay_path)})
    mean_fusion = sum(x["fused_mae_deg"] for x in rows) / len(rows); mean_tcn = sum(x["baseline_mae_deg"] for x in rows) / len(rows); mean_r2 = sum(x["r2_06_mae_deg"] for x in rows) / len(rows); raw = np.concatenate([d["K_raw"] for d in diagnostics if d["K_raw"].size]); eff = np.concatenate([d["K_eff"] for d in diagnostics if d["K_eff"].size]); cap = np.concatenate([d["cap"] for d in diagnostics if d["cap"].size])
    gates = {"mae_ratio": mean_fusion / mean_tcn <= 0.95, "active_fraction": np.mean([x["active_fraction"] for x in rows]) >= 0.10, "active_improve_fraction": np.mean([x["active_improve_fraction"] for x in rows]) >= 0.60, "active_degrade_fraction": np.mean([x["active_degrade_fraction"] for x in rows]) <= 0.05, "K_raw_spread": np.percentile(raw, 95) - np.percentile(raw, 5) >= 0.02 if raw.size else False, "K_eff_spread": np.percentile(eff, 95) - np.percentile(eff, 5) >= 0.02 if eff.size else False, "cap_fraction": np.mean(cap) < 0.95 if cap.size else False, "below_cap_fraction": np.mean(eff <= float(selected["Kmax"]) - 0.01) >= 0.05 if eff.size else False}
    passed = bool(all(gates.values())); result = {"status": "PASS_NODE53_V6_ONE_TIME_TEST_QUALIFICATION" if passed else "STOP_NODE53_V6_QUALIFICATION_FAILED", "classification": "EXPLORATORY_NONQUALIFIED_R2_06_FUSION_REBUILD", "test_read_count": 1, "test_run_count": len(ids), "test_case_count": len(rows), "mean_fusion_mae_deg": mean_fusion, "mean_moderntcn_mae_deg": mean_tcn, "mean_r2_06_mae_deg": mean_r2, "fusion_vs_moderntcn_ratio": mean_fusion / mean_tcn, "fusion_vs_r2_06_ratio": mean_fusion / mean_r2, "simultaneously_beats_both_sources_at_0p95": bool(mean_fusion <= 0.95 * mean_tcn and mean_fusion <= 0.95 * mean_r2), "gates": gates, "formal_allowed": passed, "rows": rows, "test_read_scope": "single v6 final configuration read"}
    write_json(QUALIFICATION, result)
    if not passed: write_json(STOP, result)
    return 0 if passed else 2


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("freeze", "qualify"):
        raise SystemExit("usage: node53_v6_freeze_and_qualify.py freeze|qualify")
    return freeze_final() if sys.argv[1] == "freeze" else qualify_once()


if __name__ == "__main__":
    raise SystemExit(main())
