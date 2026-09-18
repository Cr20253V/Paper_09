#!/usr/bin/env python3
"""Build the frozen A1 inventory without copying upstream model/result artifacts."""

from __future__ import annotations

import csv
import hashlib
import json
import os
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
MISSING_TCN_SEEDS = [1, 7, 11, 42, 202, 340, 520]
METHODS = ["modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"]
TASK_REL = Path("results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison")
A5_REL = Path("results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/05_A5_statistical_audit")
A0_REL = Path("results/paper/7.6/A0_论文最终统一实验配置_20260715.json")
A0_EXPLANATION_REL = Path("results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md")
OUTLINE_REL = Path("results/paper/7.6/后续三章实验审计与写作大纲_20260715.md")


def project_root() -> Path:
    here = Path(__file__).resolve()
    for candidate in [here, *here.parents]:
        if (candidate / "init_project.m").is_file() and (candidate / "data/tcn").is_dir():
            return candidate
    raise RuntimeError("Project root not found")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: Iterable[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        names: list[str] = []
        for row in rows:
            for key in row:
                if key not in names:
                    names.append(key)
    else:
        names = list(fieldnames)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=names, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def abs_path(root: Path, value: str) -> Path:
    p = Path(value)
    return p if p.is_absolute() else root / p


def artifact_row(root: Path, artifact_id: str, path: Path, expected_sha: str = "", role: str = "input") -> dict[str, Any]:
    exists = path.is_file()
    actual = sha256(path) if exists else ""
    return {
        "artifact_id": artifact_id,
        "role": role,
        "path": str(path.resolve() if exists else path),
        "exists": exists,
        "expected_sha256": expected_sha,
        "actual_sha256": actual,
        "sha256_match": bool(exists and expected_sha and actual.lower() == expected_sha.lower()) if expected_sha else exists,
        "size_bytes": path.stat().st_size if exists else "",
    }


def model_meta_path(model_file: Path) -> Path | None:
    name = model_file.name
    if name.startswith("GRU_model_"):
        return model_file.with_name(name.replace("GRU_model_", "GRU_meta_", 1))
    if name.startswith("TCN_model_"):
        return model_file.with_name(name.replace("TCN_model_", "TCN_meta_", 1))
    if model_file.suffix.lower() == ".pt":
        candidate = model_file.with_name("config.json")
        return candidate if candidate.is_file() else None
    return None


def expected_tcn_paths(task: Path, seed: int) -> tuple[Path, Path]:
    tag = f"a1_tcn_v5_plantfix_passive17_plus_all5_seed{seed}"
    model_dir = task / "02_models/models"
    return model_dir / f"TCN_model_{tag}.mat", model_dir / f"TCN_meta_{tag}.mat"


def build_model_registry(root: Path, task: Path, dataset_sha: str) -> list[dict[str, Any]]:
    source = root / A5_REL / "01_inventory/model_registry.csv"
    rows = load_csv(source)
    out: list[dict[str, Any]] = []
    for row in rows:
        method = row["method_id"]
        seed = int(row["model_seed"])
        model_file = Path(row["model_file"]) if row.get("model_file") else None
        if method == "tcn_22d" and seed in MISSING_TCN_SEEDS:
            model_file, meta_file = expected_tcn_paths(task, seed)
            source_kind = "NODE39_NEW_TRAINING"
        else:
            meta_file = model_meta_path(model_file) if model_file else None
            source_kind = "UPSTREAM_REFERENCE"
        exists = bool(model_file and model_file.is_file())
        model_hash = sha256(model_file) if exists and model_file else ""
        meta_exists = bool(meta_file and meta_file.is_file())
        out.append({
            "method_id": method,
            "model_seed": seed,
            "expected": True,
            "status": "READY" if exists else "MISSING_TO_TRAIN",
            "source_kind": source_kind,
            "model_file": str(model_file) if model_file else "",
            "model_sha256": model_hash,
            "registered_upstream_sha256": row.get("model_sha256", ""),
            "upstream_sha256_match": bool(model_hash and row.get("model_sha256") and model_hash.lower() == row["model_sha256"].lower()),
            "meta_or_config_file": str(meta_file) if meta_file else "",
            "meta_or_config_exists": meta_exists,
            "meta_or_config_sha256": sha256(meta_file) if meta_exists and meta_file else "",
            "dataset_sha256": dataset_sha,
            "source_index": row.get("source_index", ""),
        })
    return out


def build_reused_closed_loop(root: Path, a0: dict[str, Any]) -> list[dict[str, Any]]:
    path_ids = {Path(p["file"]).stem: p["path_id"] for p in a0["closed_loop_paths"]}
    rows: list[dict[str, Any]] = []
    node32 = root / "results/modern_tcn_metric_rebuild/32_four_algorithm_10seed_closed_loop/02_modern_fixed_full_closed_loop"
    for row in load_csv(node32 / "modern_fixed_22d_path_summary.csv"):
        seed = int(float(row["seed"]))
        tag = row["path_tag"]
        raw = node32 / tag / f"modern_fixed_seed{seed}_out.mat"
        rows.append({
            "method_id": "modern_tcn_22d", "seed": seed, "path_id": path_ids[tag], "path_tag": tag,
            "status": "REUSABLE" if raw.is_file() else "MISSING", "raw_result_file": str(raw),
            "raw_result_sha256": sha256(raw) if raw.is_file() else "", "source_summary_file": row.get("summary_file", ""),
        })
    node30 = root / "results/modern_tcn_metric_rebuild/30_rhofmd_lag_rescreen/04_full_closed_loop/db124"
    for seed in SEEDS:
        summary = node30 / f"s{seed}/closed_loop_summary.csv"
        for row in load_csv(summary):
            tag = row["path_tag"]
            raw = node30 / f"s{seed}/{tag}/delta_bank_124_seed{seed}_out.mat"
            rows.append({
                "method_id": "modern_tcn_delta_bank_124", "seed": seed, "path_id": path_ids[tag], "path_tag": tag,
                "status": "REUSABLE" if raw.is_file() else "MISSING", "raw_result_file": str(raw),
                "raw_result_sha256": sha256(raw) if raw.is_file() else "", "source_summary_file": str(summary),
            })
    return sorted(rows, key=lambda x: (x["method_id"], x["seed"], x["path_id"]))


def main() -> int:
    root = project_root()
    task = root / TASK_REL
    for rel in ["00_protocol_lock", "01_tools", "02_models/models", "02_models/matlab_logs", "03_offline/raw", "04_closed_loop/raw/gru_22d", "04_closed_loop/raw/tcn_22d", "05_analysis", "logs"]:
        (task / rel).mkdir(parents=True, exist_ok=True)

    a0_file = root / A0_REL
    a0 = json.loads(a0_file.read_text(encoding="utf-8"))
    a5_plan_file = root / A5_REL / "00_protocol_lock/analysis_plan.json"
    a5_plan = json.loads(a5_plan_file.read_text(encoding="utf-8"))

    protocol_sources = [
        artifact_row(root, "A0_JSON", a0_file, "1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911"),
        artifact_row(root, "A0_EXPLANATION", root / A0_EXPLANATION_REL),
        artifact_row(root, "PAPER_EXPERIMENT_OUTLINE", root / OUTLINE_REL),
        artifact_row(root, "A5_ANALYSIS_PLAN", a5_plan_file),
    ]
    input_rows = list(protocol_sources)
    dataset = a0["dataset"]
    input_rows.append(artifact_row(root, "DATASET", abs_path(root, dataset["file"]), dataset["sha256"], "data"))
    input_rows.append(artifact_row(root, "DATASET_CONTRACT", abs_path(root, dataset["contract_file"]), dataset["contract_sha256"], "data_contract"))
    for p in a0["closed_loop_paths"]:
        input_rows.append(artifact_row(root, p["path_id"], abs_path(root, p["file"]), p["sha256"], "closed_loop_path"))
    plant = a0["plant"]
    input_rows.append(artifact_row(root, "PLANT_REVISION_DEFINITION", abs_path(root, plant["revision_definition"]), plant["revision_definition_sha256"], "plant"))
    mpc = a0["lpv_mpc"]
    for key, ident in [("lpv_database_file", "LPV_DATABASE"), ("maps_file", "MPC_MAPS"), ("controller_cache_file", "MPC_CONTROLLER_CACHE")]:
        input_rows.append(artifact_row(root, ident, abs_path(root, mpc[key]), mpc[key.replace("file", "sha256")], "mpc"))
    for profile, spec in a0["evaluation"]["node10_threshold_profiles"].items():
        input_rows.append(artifact_row(root, f"NODE10_{profile.upper()}", abs_path(root, spec["file"]), spec["sha256"], "threshold"))
    for name in ["LPVMPC_AGV_simulink_GRU.slx", "LPVMPC_AGV_simulink_TCN.slx"]:
        input_rows.append(artifact_row(root, f"SIMULINK_{Path(name).stem}", root / "simulink" / name, role="simulink_model"))

    global_mismatch = [r for r in input_rows if not r["exists"] or (r["expected_sha256"] and not r["sha256_match"])]
    dataset_sha = dataset["sha256"]
    models = build_model_registry(root, task, dataset_sha)
    reused = build_reused_closed_loop(root, a0)

    missing: list[dict[str, Any]] = []
    for seed in MISSING_TCN_SEEDS:
        missing.append({"case_type": "model", "method_id": "tcn_22d", "seed": seed, "path_id": "", "reason": "missing_model_to_train"})
        missing.append({"case_type": "offline", "method_id": "tcn_22d", "seed": seed, "path_id": "", "reason": "blocked_by_missing_model"})
    for method in ["gru_22d", "tcn_22d"]:
        for seed in SEEDS:
            for p in a0["closed_loop_paths"]:
                missing.append({"case_type": "closed_loop", "method_id": method, "seed": seed, "path_id": p["path_id"], "reason": "formal_case_not_run"})

    planned = [
        {"stage": "model_training", "expected_cases": 7, "reused_cases": 0, "new_cases": 7, "execution_owner": "Codex"},
        {"stage": "offline_unified", "expected_cases": 40, "reused_cases": 0, "new_cases": 40, "execution_owner": "Codex"},
        {"stage": "closed_loop", "expected_cases": 240, "reused_cases": 120, "new_cases": 120, "execution_owner": "User_manual"},
    ]
    expected_outputs = {
        "required": ["README.md", "A1_experiment_report.md", "00_protocol_lock/protocol_snapshot.json", "00_protocol_lock/a1_config.json", "input_artifact_registry.csv", "model_registry.csv", "missing_cases_before_run.csv", "planned_run_matrix.csv", "03_offline/offline_case_metrics.csv", "04_closed_loop/closed_loop_case_metrics.csv", "05_analysis/bootstrap_results.csv", "05_analysis/worst_paths_and_cases.csv", "run_manifest.json", "artifact_manifest.json", "decision.json", "receipt.json", "task_status.json"],
        "raw_offline_case_count": 40, "closed_loop_grid_count": 240, "new_closed_loop_raw_count": 120,
    }
    config = {
        "task_id": "A1_algorithm_comparison", "protocol_id": a0["protocol_id"], "status": "FROZEN",
        "project_root": str(root), "output_root": str(task), "methods": METHODS, "seeds": SEEDS,
        "missing_tcn_seeds": MISSING_TCN_SEEDS, "dataset": dataset, "input_representations": a0["input_representations"],
        "paths": a0["closed_loop_paths"], "plant": plant, "lpv_mpc": mpc, "evaluation": a0["evaluation"],
        "bootstrap": a5_plan["bootstrap"], "effect_convention": a5_plan["effect_convention"], "claim_rules": a5_plan["claim_rules"],
        "manual_closed_loop_methods": ["gru_22d", "tcn_22d"], "reuse_policy": "path_and_sha256_reference_no_copy",
    }
    snapshot = {
        "task_id": "A1_algorithm_comparison", "created_at": now(), "protocol_id": a0["protocol_id"],
        "a0_status": a0["status"], "paper_primary_method": a0["scope"]["paper_primary_method"],
        "protocol_sources": protocol_sources, "global_protocol_check": "PASS" if not global_mismatch else "FAIL",
        "global_mismatches": global_mismatch, "dataset_contract": dataset,
        "frozen_counts": {"methods": 4, "seeds": 10, "paths": 6, "offline_cases": 40, "closed_loop_cases": 240},
    }

    write_json(task / "00_protocol_lock/protocol_snapshot.json", snapshot)
    write_json(task / "00_protocol_lock/a1_config.json", config)
    write_json(task / "00_protocol_lock/expected_outputs.json", expected_outputs)
    write_csv(task / "00_protocol_lock/input_artifact_registry.csv", input_rows)
    write_csv(task / "input_artifact_registry.csv", input_rows)
    write_csv(task / "00_protocol_lock/model_registry.csv", models)
    write_csv(task / "model_registry.csv", models)
    write_csv(task / "00_protocol_lock/missing_cases_before_run.csv", missing)
    write_csv(task / "missing_cases_before_run.csv", missing)
    write_csv(task / "00_protocol_lock/planned_run_matrix.csv", planned)
    write_csv(task / "planned_run_matrix.csv", planned)
    write_csv(task / "04_closed_loop/reused_case_registry.csv", reused)
    protected = [
        artifact_row(root, "A0_JSON", a0_file, role="protected_no_write"),
        artifact_row(root, "A0_EXPLANATION", root / A0_EXPLANATION_REL, role="protected_no_write"),
        artifact_row(root, "PAPER_EXPERIMENT_OUTLINE", root / OUTLINE_REL, role="protected_no_write"),
        artifact_row(root, "PAPER_V3_TEX", root / "results/paper/Latex/paper_v3.tex", role="protected_no_write"),
    ]
    write_csv(task / "00_protocol_lock/protected_artifact_baseline.csv", protected)

    ready_models = sum(r["status"] == "READY" for r in models)
    reusable_cl = sum(r["status"] == "REUSABLE" for r in reused)
    manifest = {
        "task_id": "A1_algorithm_comparison", "created_at": now(), "updated_at": now(),
        "protocol_id": a0["protocol_id"], "output_root": str(task), "stage": "INVENTORY_COMPLETE",
        "counts": {"models_ready": ready_models, "models_expected": 40, "reused_closed_loop_ready": reusable_cl, "reused_closed_loop_expected": 120, "missing_evaluation_cases": 127},
        "commands": [], "host": {"platform": platform.platform(), "python": sys.version, "pid": os.getpid()},
    }
    status = {
        "task_id": "A1_algorithm_comparison", "updated_at": now(),
        "status": "INVENTORY_COMPLETE" if not global_mismatch else "BLOCKED_PROTOCOL_MISMATCH",
        "global_protocol_check": snapshot["global_protocol_check"], "models_ready": ready_models,
        "offline_cases_complete": 0, "closed_loop_cases_reused": reusable_cl, "closed_loop_cases_new_complete": 0,
        "next_action": "train_missing_tcn_seeds" if not global_mismatch else "resolve_protocol_mismatch_without_changing_A0",
    }
    decision = {
        "task_id": "A1_algorithm_comparison", "updated_at": now(), "provisional": True,
        "decision": "INCOMPLETE_GRID", "reason": "TCN seeds 1,7,11,42,202,340,520 and 120 manual closed-loop cases are not yet complete",
        "results_used_for_recipe_or_threshold_changes": False,
    }
    write_json(task / "run_manifest.json", manifest)
    write_json(task / "task_status.json", status)
    write_json(task / "decision.json", decision)

    readme = f"""# A1 Fair Algorithm Comparison\n\n- protocol: `{a0['protocol_id']}`\n- status: `{status['status']}`\n- output boundary: `{task}`\n- paper primary method: `modern_tcn_delta_bank_124`\n- models ready: `{ready_models}/40`\n- reusable closed-loop cases: `{reusable_cl}/120`\n- missing evaluation cases before run: `127` (TCN offline 7 + GRU closed loop 60 + TCN closed loop 60)\n\nAll upstream models and results are referenced by absolute path and SHA256. No upstream artifact is copied or overwritten. Historical Node30/Node32 `J_control_path` values are not used for A1 cross-algorithm normalization; A1 recomputes them against matched ModernTCN-22D seed/path cases.\n"""
    (task / "README.md").write_text(readme, encoding="utf-8")
    print(json.dumps({"status": status["status"], "models_ready": ready_models, "reusable_closed_loop": reusable_cl, "output": str(task)}, ensure_ascii=False))
    return 0 if not global_mismatch else 2


if __name__ == "__main__":
    raise SystemExit(main())
