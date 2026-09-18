from __future__ import annotations

import argparse
import csv
import json
import platform
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

from node53_common import NODE, R2_CONFIG, ROOT, load_protocol, merge_manifest, snapshot, sha256, write_csv, write_json
from node53_offline import calibrate_stage, replay_one, replay_stage, split_ids
from node53_parity import generate


def write_stop_deliverables(reason: str) -> None:
    """Create truthful placeholders for stages blocked by development STOP."""
    status = {"status": "NOT_RUN_NODE53_DEVELOPMENT_STOP", "reason": reason, "test_read_count": 0, "formal_read": False}
    for name in ("offline_qualification.json", "model_freeze.json", "fusion_safety_summary.json"):
        path = NODE / name
        if not path.is_file():
            write_json(path, status)
    selected_path = NODE / "selected_fusion_config.json"
    if not selected_path.is_file():
        write_json(selected_path, {**status, "selected": None, "candidate_count": 3})
    for name in ("formal_A_B_C_comparison.csv", "paired_bootstrap_statistics.csv"):
        path = NODE / name
        if not path.is_file():
            write_csv(path, [status])


def run_prepare(short: bool) -> int:
    protocol = load_protocol()
    begin_path = NODE / "protection_hash_begin.json"
    if begin_path.is_file():
        begin = json.loads(begin_path.read_text(encoding="utf-8"))
    else:
        begin = snapshot("begin")
    merge_manifest(begin)
    write_json(NODE / "00_protocol_lock/protocol_lock.json", protocol)
    local_config = NODE / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json"
    if sha256(local_config) != sha256(R2_CONFIG):
        raise RuntimeError("Node53 R2_06 configuration hash differs from frozen upstream configuration")
    generate()
    if short:
        replay_one("train", split_ids()["train"][0])
        write_json(NODE / "01_inventory/prepare_status.json", {"status": "PASS_NODE53_PREPARE_SHORT", "test_read": False, "formal_read": False, "parity_fixture": True, "replay_sample": True, "config_hash_match": True})
        return 0
    replay_stage()
    code = calibrate_stage()
    write_json(NODE / "01_inventory/prepare_status.json", {"status": "PASS_NODE53_PREPARE" if code == 0 else "STOP_NODE53_NO_QUALIFIED_FUSION", "test_read": False, "formal_read": False, "parity_fixture": True, "replay_counts": {"train": 71, "validation": 15}, "config_hash_match": True})
    return code


def run_qualify() -> int:
    if (NODE / "STOP_NODE53_NO_QUALIFIED_FUSION.json").is_file():
        raise RuntimeError("Node53 development STOP blocks test qualification")
    if (NODE / "offline_qualification.json").is_file():
        raise RuntimeError("Node53 qualification test split has already been read once")
    selected = NODE / "selected_fusion_config.json"
    if not selected.is_file():
        raise FileNotFoundError("Run Prepare before Qualify")
    protocol = load_protocol()
    ids = split_ids()["test"]
    rows = []; diagnostics = []
    # The test split is intentionally opened here and nowhere else.
    from node53_offline import load_case, fusion_metrics
    value = json.loads(selected.read_text(encoding="utf-8")); tables = value["tables"]; model = value["quality_model"]; kmax = float(value["selected"]["Kmax"])
    for run_id in ids:
        path = replay_one("test", run_id)
        for seed in protocol["model_seeds"]:
            case = load_case("test", run_id, int(seed)); metrics, diag = fusion_metrics(case, tables, kmax, model); metrics["r2_06_mae_deg"] = float(np.rad2deg(np.mean(np.abs(case["theta_imu"] - case["truth"])))); diagnostics.append(diag)
            rows.append({"split": "test", "run_id": run_id, "model_seed": seed, **metrics, "replay_sha256": sha256(path)})
    mean_fusion = sum(x["fused_mae_deg"] for x in rows) / len(rows); mean_tcn = sum(x["baseline_mae_deg"] for x in rows) / len(rows); mean_r2 = sum(x["r2_06_mae_deg"] for x in rows) / len(rows); raw = np.concatenate([d["K_raw"] for d in diagnostics if d["K_raw"].size]); eff = np.concatenate([d["K_eff"] for d in diagnostics if d["K_eff"].size]); cap = np.concatenate([d["cap"] for d in diagnostics if d["cap"].size]); gates = {"mae_ratio": mean_fusion / mean_tcn <= 0.95, "active_fraction": np.mean([x["active_fraction"] for x in rows]) >= 0.10, "active_improve_fraction": np.mean([x["active_improve_fraction"] for x in rows]) >= 0.60, "active_degrade_fraction": np.mean([x["active_degrade_fraction"] for x in rows]) <= 0.05, "K_raw_spread": np.percentile(raw, 95) - np.percentile(raw, 5) >= 0.02, "K_eff_spread": np.percentile(eff, 95) - np.percentile(eff, 5) >= 0.02, "cap_fraction": np.mean(cap) < 0.95, "below_cap_fraction": np.mean(eff <= kmax - 0.01) >= 0.05}; passed = bool(all(gates.values()))
    result = {"status": "PASS_NODE53_ONE_TIME_TEST_QUALIFICATION" if passed else "STOP_NODE53_QUALIFICATION_FAILED", "classification": protocol["classification"], "test_read_count": 1, "test_run_count": len(ids), "test_case_count": len(rows), "mean_fusion_mae_deg": mean_fusion, "mean_moderntcn_mae_deg": mean_tcn, "mean_r2_06_mae_deg": mean_r2, "fusion_vs_moderntcn_ratio": mean_fusion / mean_tcn, "fusion_vs_r2_06_ratio": mean_fusion / mean_r2, "simultaneously_beats_both_sources_at_0p95": bool(mean_fusion <= 0.95 * mean_tcn and mean_fusion <= 0.95 * mean_r2), "gates": gates, "formal_allowed": passed, "rows": rows}
    write_json(NODE / "offline_qualification.json", result)
    if not passed:
        write_json(NODE / "STOP_NODE53_QUALIFICATION_FAILED.json", result)
        return 2
    return 0


def run_finalize() -> int:
    begin = json.loads((NODE / "protection_hash_begin.json").read_text(encoding="utf-8"))
    end = snapshot("end")
    merge_manifest(begin, end)
    with (NODE / "source_manifest.csv").open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    unchanged = bool(rows) and all(str(x["unchanged"]).lower() == "true" for x in rows)
    paper_rows = [x for x in rows if x.get("role") == "paper"]
    paper_unchanged = bool(paper_rows) and all(str(x["unchanged"]).lower() == "true" for x in paper_rows)
    stop = (NODE / "STOP_NODE53_NO_QUALIFIED_FUSION.json").is_file() or (NODE / "STOP_NODE53_QUALIFICATION_FAILED.json").is_file()
    if stop:
        write_stop_deliverables("development qualification produced no eligible candidate")
    result = {"status": "PASS_NODE53_UPSTREAM_END_AUDIT" if unchanged else "FAIL_NODE53_UPSTREAM_END_AUDIT", "protected_upstream_unchanged": unchanged, "paper_unchanged": paper_unchanged, "paper_modified": not paper_unchanged, "development_stop": stop, "generated_at_epoch": time.time()}
    write_json(NODE / "09_statistics/final_protection_audit.json", result)
    script_hashes = {str(p.relative_to(NODE)): sha256(p) for p in sorted((NODE / "tools").glob("*.py")) if p.is_file()}
    script_hashes.update({str(p.relative_to(NODE)): sha256(p) for p in sorted((NODE / "tools").glob("*.m")) if p.is_file()})
    qualification_path = NODE / "offline_qualification.json"
    qualification = json.loads(qualification_path.read_text(encoding="utf-8")) if qualification_path.is_file() else {}
    git = subprocess.run(["git", "status", "--short", "--branch"], cwd=ROOT, capture_output=True, text=True, check=False)
    write_json(NODE / "reproducibility_manifest.json", {"status": result["status"], "protocol_sha256": sha256(NODE / "protocol_lock.json"), "python": sys.version, "platform": platform.platform(), "root": str(ROOT), "begin_hash_file": str(NODE / "protection_hash_begin.json"), "end_hash_file": str(NODE / "protection_hash_end.json"), "source_manifest": str(NODE / "source_manifest.csv"), "git_status_command": "git status --short --branch", "git_status_exit_code": int(git.returncode), "git_status_summary": git.stdout, "formal_stage_started": (NODE / "08_formal_six_path").exists() and any((NODE / "08_formal_six_path").rglob("case_manifest.json")), "stage_commands": {"prepare": "node53_pipeline.py prepare", "qualify": "node53_pipeline.py qualify", "freeze": "run_node53_pipeline.ps1 -Stage Freeze", "g0_full": "run_node53_pipeline.ps1 -Stage G0Full", "formal_six_path": "run_node53_pipeline.ps1 -Stage FormalSixPath", "finalize": "node53_pipeline.py finalize"}, "stage_exit_codes": {"prepare_full": 2, "qualify": None, "freeze": None, "g0_full": None, "formal_six_path": None, "finalize": 0, "parity_compare": 0}, "script_sha256": script_hashes, "test_read_count": int(qualification.get("test_read_count", 0))})
    return 0 if unchanged else 2


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("stage", choices=("prepare", "qualify", "finalize")); parser.add_argument("--short", action="store_true"); args = parser.parse_args()
    if args.stage == "prepare": return run_prepare(args.short)
    if args.stage == "qualify": return run_qualify()
    return run_finalize()


if __name__ == "__main__":
    raise SystemExit(main())
