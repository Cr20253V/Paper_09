#!/usr/bin/env python3
"""Create the frozen A3 inventory and protocol snapshot before any long run."""
from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(r"E:\Matlab\Simulink\S-Function_16")
OUT = ROOT / r"results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\03_A3_slope_scheduling_necessity"
A0_REL = r"results\paper\7.6\A0_论文最终统一实验配置_20260715.json"
A0 = ROOT / A0_REL


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, obj: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def artifact(role: str, rel: str, expected_sha: str, reusable: bool = True, note: str = "") -> dict:
    p = ROOT / rel
    actual = sha256(p) if p.is_file() else None
    return {
        "role": role,
        "path": rel.replace("\\", "/"),
        "absolute_path": str(p),
        "exists": p.is_file(),
        "expected_sha256": expected_sha,
        "actual_sha256": actual,
        "sha256_match": bool(actual and actual.lower() == expected_sha.lower()),
        "reusable": reusable,
        "note": note,
    }


def main() -> None:
    a0 = json.loads(A0.read_text(encoding="utf-8-sig"))
    a0_hash = sha256(A0)
    expected_a0 = "1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911"
    if a0_hash != expected_a0:
        raise RuntimeError(f"A0 hash mismatch: {a0_hash}")

    for rel in ["00_protocol_lock", "01_inventory", "02_tools", "03_cases", "04_summary", "05_logs", "c"]:
        (OUT / rel).mkdir(parents=True, exist_ok=True)

    controllers = [
        {"controller_id": "ZS_LPV_MPC", "theta_source": "constant_zero", "mode": 1},
        {"controller_id": "IMU_LPV_MPC", "theta_source": "node36_causal_imu_raw", "mode": 2},
        {"controller_id": "Oracle_LPV_MPC", "theta_source": "true_slope", "mode": 3},
    ]

    duration = {
        "p01_factory_logistics_showcase": (245.82, 24583),
        "p02_sharp_turn_transition": (52.00, 5201),
        "p03_long_updown": (44.00, 4401),
        "p04_soft_updown_straight_turn": (56.00, 5601),
        "p05_factory_flat_logistics": (190.00, 19001),
        "p06_downhill_after_turn": (38.00, 3801),
    }

    registry = [
        artifact("A0 frozen protocol", A0_REL, expected_a0, note="authoritative protocol"),
        artifact("A0 Chinese protocol explanation", r"results\paper\7.6\A0_论文最终统一实验配置说明_20260715.md", "44155532ef770dbb5c4817006caa80213cb2ede7390ee8dbcc75085425058173"),
        artifact("experiment audit and writing outline", r"results\paper\7.6\后续三章实验审计与写作大纲_20260715.md", "a8a0c7a736afcb54812cd419a3a31f716eac2820a1c5fed68c85b9636191b8bc"),
        artifact("plant revision definition", a0["plant"]["revision_definition"], a0["plant"]["revision_definition_sha256"]),
    ]
    registry += [artifact("plant source chain", x["file"], x["sha256"]) for x in a0["plant"]["closed_loop_s_function_chain"]]
    registry += [
        artifact("LPV database", a0["lpv_mpc"]["lpv_database_file"], a0["lpv_mpc"]["lpv_database_sha256"]),
        artifact("MPC maps", a0["lpv_mpc"]["maps_file"], a0["lpv_mpc"]["maps_sha256"]),
        artifact("controller cache", a0["lpv_mpc"]["controller_cache_file"], a0["lpv_mpc"]["controller_cache_sha256"]),
        artifact("preload entrypoint", a0["lpv_mpc"]["effective_entrypoint"], "3b1b6e697887bb80158f02d44db9296df60e0f6afed93d2102fb684432c614d9"),
        artifact("Node26 synchronous rho_f model shell", r"simulink\LPVMPC_AGV_simulink_Modern_TCN_44_rhofmd.slx", "cc5e6416683b4993d4a01d2cdf9fb0ce662aa5504633c79c2868084661d39bba"),
        artifact("Node36 causal IMU estimator", r"results\modern_tcn_metric_rebuild\36_moderntcn_imu_fusion\tools\node36_causal_imu_slope_estimator.m", "420b562774bd414d3f01452dbcb122a0017b3bf36d9582aa09d0b3b47bdf0c05"),
        artifact("Node36 frozen estimator config", r"results\modern_tcn_metric_rebuild\36_moderntcn_imu_fusion\tools\node36_fusion_cfg.m", "d9ff0939039dea63f8da9a8b52ee7373851884ccb37d7828bc5dbb7d52799026"),
        artifact("Node36 legality decision", r"results\modern_tcn_metric_rebuild\36_moderntcn_imu_fusion\01_imu_signal_legality_audit\imu_signal_legality_decision.json", "13140745b21247cdf5307761a27ee5e758e1d4579664aa100983574b014d10b5"),
        artifact("Node10 closed-loop thresholds", a0["evaluation"]["node10_threshold_profiles"]["closed_loop"]["file"], a0["evaluation"]["node10_threshold_profiles"]["closed_loop"]["sha256"]),
        artifact("A5 A3 case schema", r"results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\05_A5_statistical_audit\00_protocol_lock\input_schemas\a3_closed_loop_case.schema.json", sha256(ROOT / r"results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\05_A5_statistical_audit\00_protocol_lock\input_schemas\a3_closed_loop_case.schema.json")),
    ]
    registry += [artifact("A0 closed-loop path", p["file"], p["sha256"]) for p in a0["closed_loop_paths"]]
    mismatches = [r for r in registry if not r["sha256_match"]]
    if mismatches:
        raise RuntimeError("Frozen input hash mismatch: " + ", ".join(r["path"] for r in mismatches))

    config = {
        "task_id": "A3",
        "protocol_id": a0["protocol_id"],
        "status": "FROZEN_BEFORE_RESULT_INSPECTION",
        "created_date": "2026-07-15",
        "write_root": str(OUT),
        "sample_time_s": a0["lpv_mpc"]["sample_time_s"],
        "initialization_exclusion_s": 0.5,
        "plant_revision": a0["plant"]["revision_id"],
        "lpv_mpc": a0["lpv_mpc"],
        "controllers": controllers,
        "noise": {"enable_noise": False, "sensor_noise_seed": None, "process_disturbance_seed": None, "repeats": 1},
        "imu_estimator": {
            "implementation": "results/modern_tcn_metric_rebuild/36_moderntcn_imu_fusion/tools/node36_causal_imu_slope_estimator.m",
            "outer_node36_g1_deadzone_or_limiter": False,
            "cf_alpha": 0.98, "cf_alpha_dynamic": 0.995, "a_long_alpha": 0.90,
            "a_long_correction_gain": 0.60, "accel_norm_gate": 2.5,
            "dynamic_accel_gate": 1.2, "lateral_accel_gate": 1.5,
            "theta_abs_limit_deg": 12.0, "r_max_deg_s": 8.0,
        },
        "common_scheduler_chain": "selected theta source -> unchanged Node26 RhoFilter -> rho_f(:,3) -> UpdatePlantModel and MD",
        "classifier_policy": "fixed label_main=1, label_turn=0, conf_main=1 for all modes",
        "paths": a0["closed_loop_paths"],
        "metrics": {
            "tracking": ["ey_rmse", "ey_peak", "epsi_rmse", "epsi_peak", "xy_rmse", "xy_peak", "ev_rmse", "ev_peak"],
            "control": ["j_du", "omega_cmd_rms"],
            "slope": ["theta_sched_mae_deg", "theta_delay_s", "theta_step_p95_deg", "theta_rate_p95_deg_s", "theta_rate_max_deg_s", "theta_total_variation_deg"],
            "safety": ["constraint_violation_rate", "force_saturation_rate", "omega_saturation_rate", "dynamic_force_limit_hit_rate", "solver_fail_count", "timeout_count"],
            "timeout_threshold_ms": 10.0,
            "force_saturation_threshold_N": 595.0,
            "omega_saturation_threshold_rad_s": 0.60,
            "delay_search_window_s": 2.0,
        },
        "statistics": {"bootstrap_iterations": 10000, "bootstrap_seed": 20260715, "pairing_unit": "path", "effect": "comparator_minus_target"},
        "dataset_context": {"file": a0["dataset"]["file"], "sha256": a0["dataset"]["sha256"], "used_in_A3": False},
    }
    write_json(OUT / "00_protocol_lock" / "protocol_snapshot.json", {"a0_file": A0_REL.replace("\\", "/"), "a0_sha256": a0_hash, "protocol": a0})
    write_json(OUT / "00_protocol_lock" / "effective_config.json", config)
    cfg_hash = sha256(OUT / "00_protocol_lock" / "effective_config.json")
    write_json(OUT / "00_protocol_lock" / "gate_applicability.json", {
        "task_id": "A3", "node10_closed_loop_threshold_profile": a0["evaluation"]["node10_threshold_profiles"]["closed_loop"],
        "applicable": ["unstable", "constraint_penalty_ratio", "constraint_violation_abs_increase", "omega_cmd_rms_ratio", "j_du_ratio"],
        "not_applicable": {"classification_accuracy": "A3 changes only controller slope source", "recall": "no learned classifier is evaluated", "offline_boundary_gate": "closed-loop controller-source experiment"},
        "zero_baseline_ratio_policy": "UNEVALUABLE_ZERO_BASELINE; never coerced to PASS"
    })

    matrix = []
    missing = []
    for c in controllers:
        for p in a0["closed_loop_paths"]:
            sec, n = duration[p["path_id"]]
            case_id = f'{c["controller_id"]}__{p["path_id"]}'
            row = {
                "case_id": case_id, "controller_id": c["controller_id"], "theta_source": c["theta_source"],
                "mode": c["mode"], "path_id": p["path_id"], "path_file": p["file"], "path_sha256": p["sha256"],
                "simulation_duration_s": f"{sec:.2f}", "expected_samples": n, "repeat": 1,
                "sensor_noise_seed": "", "process_disturbance_seed": "", "status_before_run": "MISSING"
            }
            matrix.append(row)
            missing.append({"case_id": case_id, "reason": "No formal A3 result exists under the unique write root", "required": True})

    write_csv(OUT / "01_inventory" / "input_artifact_registry.csv", registry)
    write_csv(OUT / "01_inventory" / "planned_run_matrix.csv", matrix)
    write_csv(OUT / "01_inventory" / "missing_cases.csv", missing)
    write_json(OUT / "01_inventory" / "reusable_results.json", {
        "directly_reusable": [r for r in registry if r["reusable"]],
        "non_reusable_performance_results": [
            {"artifact": "2026-05 three-mode comparison", "reason": "plant revision is not agv_physics_v2_plantfix"},
            {"artifact": "plantfix Stage1 results", "reason": "1 s/51-sample smoke only; modes are identical and not formal A3 evidence"}
        ]
    })
    write_json(OUT / "01_inventory" / "expected_outputs.json", {
        "case_count": 18, "per_controller_samples": 62588, "per_controller_simulation_s": 625.82,
        "total_samples": 187764, "total_simulation_s": 1877.46,
        "per_case": ["case_manifest.json", "attempt_001/case_out.mat", "attempt_001/trace.csv", "attempt_001/case_metrics.json", "attempt_001/run.log", "attempt_001/attempt_receipt.json"],
        "summary": ["a3_case_table.csv", "a3_case_table.jsonl", "controller_summary.csv", "paired_effects.csv", "bootstrap_ci.json", "safety_gates.csv", "worst_cases.csv"],
        "top_level": ["source_manifest.json", "run_manifest.json", "artifact_manifest.json", "decision.json", "receipt.json", "task_status.json", "README.md"]
    })
    write_json(OUT / "run_manifest.json", {
        "task_id": "A3", "protocol_id": a0["protocol_id"], "phase": "PREFLIGHT_INVENTORY_COMPLETE",
        "effective_config": "00_protocol_lock/effective_config.json", "effective_config_sha256": cfg_hash,
        "planned_cases": 18, "completed_cases": 0, "failed_cases": 0,
        "created_at": datetime.now(timezone.utc).isoformat(), "write_root": str(OUT)
    })
    print(json.dumps({"target": str(OUT), "effective_config_sha256": cfg_hash, "artifacts_verified": len(registry), "planned_cases": len(matrix)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
