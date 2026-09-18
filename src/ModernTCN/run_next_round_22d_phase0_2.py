"""Phase 0-2 executor for the ModernTCN_v4 next-round 22D workflow.

This script is intentionally limited to evidence locking, baseline offline
diagnosis, and seq256 dataset construction. It does not train, export ONNX,
or call MATLAB/Simulink.
"""

from __future__ import annotations

import csv
import json
import math
import shutil
import subprocess
import sys
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import h5py
import numpy as np
import torch
from torch.utils.data import DataLoader

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "ModernTCN"))

from modern_tcn_data import AGVWindowDataset, class_weights, load_modern_tcn_dataset
from modern_tcn_metrics import compute_metrics, multitask_loss
from modern_tcn_model import build_model_from_checkpoint_dict


BASELINE_DATASET = ROOT / "data" / "tcn" / (
    "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5.mat"
)
BASELINE_CONTRACT = ROOT / "data" / "tcn" / (
    "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5_contract.json"
)
BASELINE_TRAIN_DATA = ROOT / "data" / "tcn" / (
    "ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5.mat"
)
BASELINE_SPLIT = ROOT / "data" / "tcn" / (
    "ModernTCN_shared_run_split_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5.mat"
)
BASELINE_SNAPSHOT = ROOT / "results" / "modern_tcn_ablation" / "_baseline_snapshot"
BASELINE_MANIFEST = BASELINE_SNAPSHOT / "baseline_artifact_manifest.json"
BASELINE_METRICS = BASELINE_SNAPSHOT / "baseline_offline_metrics.csv"
OUT_ROOT = ROOT / "results" / "modern_tcn_next_round_22d"
SEQ256_DATASET = ROOT / "data" / "tcn" / (
    "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5_seq256.mat"
)
SEQ256_CONTRACT = ROOT / "data" / "tcn" / (
    "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5_seq256_contract.json"
)
SEQ256_SCALER = ROOT / "data" / "tcn" / (
    "ModernTCN_scaler_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5_seq256.mat"
)
SEQ256_REPORT = ROOT / "data" / "tcn" / (
    "ModernTCN_prepare_dataset_agv_dualsteer_theta10_uniform_conf_h0_"
    "v5_plantfix_passive17_plus_all5_seq256_report.md"
)

FEATURE_NAMES = [
    "gyro_z",
    "I_lf",
    "I_rr",
    "omega_wheel_lf",
    "omega_wheel_rr",
    "delta_lf",
    "delta_rr",
    "v_hat",
    "dv_hat_dt",
    "ws_imbalance",
    "I_sum",
    "I_diff_signed",
    "I_diff_abs",
    "kappa_proxy",
    "accel_per_current",
    "dv_hat_dt_lp",
    "accel_x_wheel",
    "I_drive_signed",
    "current_per_accel",
    "drive_load_proxy",
    "a_hp",
    "yaw_consistency_error",
]


def main() -> None:
    _ensure_dirs()
    manifest = _load_json(BASELINE_MANIFEST)
    baseline_contract = _load_json(BASELINE_CONTRACT)
    _phase0(manifest, baseline_contract)
    _phase1(manifest)
    _phase2_build_seq256(manifest, baseline_contract)
    _phase2_validate_seq256(manifest, baseline_contract)
    _write_master_summary()


def _ensure_dirs() -> None:
    for rel in (
        "00_evidence_lock",
        "01_error_diagnosis",
        "02_seq256_dataset",
        "02_engineering_preflight",
    ):
        (OUT_ROOT / rel).mkdir(parents=True, exist_ok=True)


def _phase0(manifest: Dict[str, object], contract: Dict[str, object]) -> None:
    out_dir = OUT_ROOT / "00_evidence_lock"
    file_rows = []
    checks = [
        "results/modern_tcn_ablation/_baseline_snapshot/baseline_identity.md",
        "results/modern_tcn_ablation/_baseline_snapshot/baseline_offline_metrics.csv",
        "results/modern_tcn_ablation/ABLATION_CLEANUP_SUMMARY.md",
        "results/modern_tcn_ablation/exp1_grouped_ffn/grouped_ffn_final_report.md",
        "results/modern_tcn_ablation/exp2_dual_kernel/dual_kernel_final_report.md",
        "results/modern_tcn_ablation/exp3_patch_full_densepatch_continuation/continuation_report.md",
    ]
    for rel in checks:
        p = ROOT / rel
        stat = p.stat() if p.exists() else None
        file_rows.append(
            {
                "path": rel,
                "exists": int(p.exists()),
                "size_bytes": stat.st_size if stat else "",
                "modified_time": datetime.fromtimestamp(stat.st_mtime).isoformat(sep=" ", timespec="seconds")
                if stat
                else "",
            }
        )
    _write_csv(out_dir / "file_existence_check.csv", file_rows)

    baseline_rows = _read_csv(BASELINE_METRICS)
    baseline_row = baseline_rows[0] if baseline_rows else {}
    git_hash = _git(["rev-parse", "HEAD"])
    current_git = _git(["status", "--short"])
    text = [
        "# Phase 0 Evidence Lock",
        "",
        f"- generated_at: `{_now()}`",
        f"- current_git_hash: `{git_hash}`",
        f"- baseline_snapshot_dir: `{_rel(BASELINE_SNAPSHOT)}`",
        f"- baseline_dataset: `{_rel(Path(str(manifest['dataset'])))}`",
        f"- baseline_dataset_contract: `{_rel(Path(str(manifest['dataset_contract'])))}`",
        f"- baseline_checkpoint: `{_rel(Path(str(manifest['checkpoint'])))}`",
        f"- baseline_onnx: `{_rel(Path(str(manifest['onnx'])))}`",
        "- fixed_contract: `agv_physics_v2_plantfix / passive17_plus_all5 / input_dim=22 / seq_len=128`",
        "- retained_champion: `turn_l020_tt25_tcm14_stw055_slrw060_seed101`",
        "",
        "## Baseline Offline Metrics",
        "",
    ]
    for key in (
        "acc_main",
        "acc_turn",
        "acc_turn_transition",
        "theta_mae_deg",
        "flat_recall",
        "stall_recall",
        "slope_recall",
        "theta_abs_le_10_p95_abs_err_deg",
    ):
        if key in baseline_row:
            text.append(f"- {key}: `{baseline_row[key]}`")
    text.extend(
        [
            "",
            "## Previous Ablation Decisions",
            "",
            "- `exp1_grouped_ffn`: NO_PROMOTION; do not expand failed seeds.",
            "- `exp2_dual_kernel`: NO_PROMOTION / STOP_NO_MULTISEED; do not reuse failed checkpoints.",
            "- `exp3_patch_full`: NO_PROMOTION; full128/densepatch evidence remains offline-only.",
            "",
            "## Isolation Statement",
            "",
            "- This first round writes new evidence under `results/modern_tcn_next_round_22d/` plus the explicit seq256 dataset files.",
            "- No baseline retraining, ONNX export, MATLAB import, Simulink, or closed-loop execution is permitted in this round.",
            "- `.pt/.onnx/.mat/log/cache` artifacts are not intended for commit by default.",
            "",
            "## Git Status At Lock",
            "",
            "```text",
            current_git or "(clean)",
            "```",
        ]
    )
    (out_dir / "evidence_lock.md").write_text("\n".join(text) + "\n", encoding="utf-8")

    contract_check = _check_baseline_contract(manifest, contract)
    (out_dir / "current_22d_seq128_contract_check.md").write_text(contract_check, encoding="utf-8")


def _check_baseline_contract(manifest: Dict[str, object], contract: Dict[str, object]) -> str:
    failures = []
    if int(manifest.get("input_dim", -1)) != 22:
        failures.append("manifest input_dim != 22")
    if int(manifest.get("seq_len", -1)) != 128:
        failures.append("manifest seq_len != 128")
    if manifest.get("feature_contract") != "passive17_plus_all5":
        failures.append("manifest feature_contract mismatch")
    plant = manifest.get("plant_revision")
    if plant != "agv_physics_v2_plantfix":
        failures.append("manifest plant_revision mismatch")
    if int(contract.get("input_dim", -1)) != 22:
        failures.append("contract input_dim != 22")
    if int(contract.get("seq_len", -1)) != 128:
        failures.append("contract seq_len != 128")
    if contract.get("feature_contract") != "passive17_plus_all5":
        failures.append("contract feature_contract mismatch")
    if int(contract.get("horizon_steps", -1)) != 0:
        failures.append("contract horizon_steps != 0")
    if contract.get("label_time_policy") != "current_window_end":
        failures.append("contract label_time_policy mismatch")
    if contract.get("plant_revision", {}).get("id") != "agv_physics_v2_plantfix":
        failures.append("contract plant_revision.id mismatch")
    if list(contract.get("feature_names", [])) != FEATURE_NAMES:
        failures.append("contract feature_names differ from expected 22D order")
    status = "PASS" if not failures else "FAIL"
    lines = [
        "# Current 22D seq128 Contract Check",
        "",
        f"- generated_at: `{_now()}`",
        f"- status: `{status}`",
        f"- dataset: `{_rel(BASELINE_DATASET)}`",
        f"- contract_json: `{_rel(BASELINE_CONTRACT)}`",
        "",
        "| field | expected | observed |",
        "|---|---:|---:|",
        f"| input_dim | 22 | {manifest.get('input_dim')} |",
        f"| seq_len | 128 | {manifest.get('seq_len')} |",
        f"| feature_contract | passive17_plus_all5 | {manifest.get('feature_contract')} |",
        f"| plant_revision | agv_physics_v2_plantfix | {manifest.get('plant_revision')} |",
        f"| horizon_steps | 0 | {contract.get('horizon_steps')} |",
        f"| label_time_policy | current_window_end | {contract.get('label_time_policy')} |",
        "",
    ]
    if failures:
        lines.extend(["## Failures", "", *[f"- {x}" for x in failures], ""])
        fail_path = OUT_ROOT / "00_evidence_lock" / "failure_report.md"
        fail_path.write_text("\n".join(lines), encoding="utf-8")
        raise SystemExit(f"Phase 0 contract check failed: {failures}")
    lines.append("The frozen seq128 baseline contract is valid for Phase 1 diagnosis.")
    return "\n".join(lines) + "\n"


def _phase1(manifest: Dict[str, object]) -> None:
    out_dir = OUT_ROOT / "01_error_diagnosis"
    data = load_modern_tcn_dataset(BASELINE_DATASET)
    test_split = data["test"]
    ckpt_path = Path(str(manifest["checkpoint"]))
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    model = build_model_from_checkpoint_dict(ckpt)
    model.eval()
    cfg = type("Cfg", (), dict(ckpt["model_config"]))()
    device = torch.device("cpu")
    loader = DataLoader(AGVWindowDataset(test_split), batch_size=256, shuffle=False, num_workers=0)
    class_w_main = class_weights(
        data["train"].y_main,
        3,
        getattr(cfg, "main_class_weight_method", "balanced"),
        list(getattr(cfg, "main_class_multipliers", (1.0, 1.0, 1.0))),
    )
    class_w_turn = class_weights(
        data["train"].y_turn,
        3,
        getattr(cfg, "turn_class_weight_method", "balanced"),
        list(getattr(cfg, "turn_class_multipliers", (1.0, 1.0, 1.0))),
    )
    logits_main, logits_turn, theta_hat, loss_total = _predict_full(
        model, loader, device, class_w_main, class_w_turn, cfg
    )
    metrics = compute_metrics(logits_main, logits_turn, theta_hat, test_split, loss_total)
    _write_predictions(out_dir / "baseline_seq128_predictions.csv", test_split, logits_main, logits_turn, theta_hat)
    _write_matrix(out_dir / "baseline_main_confusion_matrix.csv", metrics["cm_main"], ["flat", "stall", "slope"])
    _write_matrix(out_dir / "baseline_turn_confusion_matrix.csv", metrics["cm_turn"], ["right", "straight", "left"])
    _write_classification_report(out_dir / "baseline_classification_report.md", test_split, logits_main, logits_turn, theta_hat, metrics)
    _write_distribution_reports(out_dir, data)
    _write_theta_error_reports(out_dir, test_split, logits_main, logits_turn, theta_hat, metrics)
    _write_diagnosis_summary(out_dir, data, test_split, logits_main, logits_turn, theta_hat, metrics)


def _predict_full(model, loader, device, class_w_main, class_w_turn, cfg):
    all_main = []
    all_turn = []
    all_theta = []
    total_loss = 0.0
    total_n = 0
    with torch.no_grad():
        for batch in loader:
            x = batch["X"].to(device)
            outputs = model(x)
            logits_main, logits_turn, theta = outputs
            batch_dev = {k: v.to(device) for k, v in batch.items()}
            loss, _ = multitask_loss(logits_main, logits_turn, theta, batch_dev, class_w_main, class_w_turn, cfg)
            n = x.shape[0]
            total_loss += float(loss.cpu()) * n
            total_n += n
            all_main.append(logits_main.cpu().numpy())
            all_turn.append(logits_turn.cpu().numpy())
            all_theta.append(theta.reshape(-1).cpu().numpy())
    return (
        np.concatenate(all_main, axis=0),
        np.concatenate(all_turn, axis=0),
        np.concatenate(all_theta, axis=0),
        total_loss / max(total_n, 1),
    )


def _write_predictions(path: Path, split, logits_main, logits_turn, theta_hat):
    prob_main = _softmax(logits_main)
    prob_turn = _softmax(logits_turn)
    pred_main = prob_main.argmax(axis=1)
    pred_turn = prob_turn.argmax(axis=1) - 1
    rows = []
    y_main = split.y_main.reshape(-1)
    y_turn = split.y_turn.reshape(-1) - 1
    y_theta = split.y_theta.reshape(-1)
    for i in range(len(y_main)):
        rows.append(
            {
                "test_row": i + 1,
                "run_id": int(split.run_id[i]),
                "y_main": int(y_main[i]),
                "pred_main": int(pred_main[i]),
                "main_correct": int(y_main[i] == pred_main[i]),
                "main_confidence": float(prob_main[i].max()),
                "y_turn": int(y_turn[i]),
                "pred_turn": int(pred_turn[i]),
                "turn_correct": int(y_turn[i] == pred_turn[i]),
                "turn_confidence": float(prob_turn[i].max()),
                "turn_transition": int(split.turn_transition[i]),
                "turn_purity": float(split.turn_purity[i]),
                "theta_true_rad": float(y_theta[i]),
                "theta_true_deg": float(np.rad2deg(y_theta[i])),
                "theta_hat_rad": float(theta_hat[i]),
                "theta_hat_deg": float(np.rad2deg(theta_hat[i])),
                "theta_abs_err_deg": float(abs(np.rad2deg(theta_hat[i] - y_theta[i]))),
                "mask_theta": int(split.mask_theta[i]),
            }
        )
    _write_csv(path, rows)


def _write_matrix(path: Path, matrix, labels: List[str]) -> None:
    rows = []
    m = np.asarray(matrix, dtype=int)
    for i, label in enumerate(labels):
        row = {"true": label}
        for j, pred in enumerate(labels):
            row[f"pred_{pred}"] = int(m[i, j])
        rows.append(row)
    _write_csv(path, rows)


def _write_classification_report(path: Path, split, logits_main, logits_turn, theta_hat, metrics) -> None:
    pred_main = logits_main.argmax(axis=1)
    pred_turn = logits_turn.argmax(axis=1)
    main_rows = _classification_rows(split.y_main.reshape(-1), pred_main, ["flat", "stall", "slope"])
    turn_rows = _classification_rows(split.y_turn.reshape(-1), pred_turn, ["right", "straight", "left"])
    lines = [
        "# Baseline seq128 Classification Report",
        "",
        "Frozen baseline checkpoint and current seq128 test set were used. No baseline retraining was performed.",
        "",
        "## Main Classes",
        "",
        "| class | precision | recall | f1 | support |",
        "|---|---:|---:|---:|---:|",
    ]
    lines.extend(_format_class_rows(main_rows))
    lines.extend(
        [
            "",
            "## Turn Classes",
            "",
            "| class | precision | recall | f1 | support |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    lines.extend(_format_class_rows(turn_rows))
    lines.extend(
        [
            "",
            "## Core Metrics",
            "",
            f"- acc_main: `{metrics['acc_main']:.6f}`",
            f"- acc_turn: `{metrics['acc_turn']:.6f}`",
            f"- acc_turn_transition: `{metrics['acc_turn_transition']:.6f}`",
            f"- theta_mae_deg: `{metrics['theta_mae_deg']:.6f}`",
            f"- flat_recall: `{metrics['flat_recall']:.6f}`",
            f"- stall_recall: `{metrics['stall_recall']:.6f}`",
            f"- slope_recall: `{metrics['slope_recall']:.6f}`",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_distribution_reports(out_dir: Path, data: Dict[str, object]) -> None:
    rows = []
    md = ["# Stall/Slope Sample Distribution", ""]
    for split_name in ("train", "val", "test"):
        split = data[split_name]
        counts = _class_counts(split.y_main, 3)
        rows.append(
            {
                "section": "main_class_counts",
                "split": split_name,
                "flat": counts[0],
                "stall": counts[1],
                "slope": counts[2],
            }
        )
        for cls_id, cls_name in ((1, "stall"), (2, "slope")):
            for rid, count in _run_counts(split.run_id[split.y_main == cls_id]).items():
                rows.append(
                    {
                        "section": f"{cls_name}_run_distribution",
                        "split": split_name,
                        "run_id": rid,
                        "windows": count,
                    }
                )
        for cls_id, cls_name in ((1, "stall"), (2, "slope")):
            lengths = _duration_lengths(split.y_main == cls_id)
            rows.append(
                {
                    "section": f"{cls_name}_duration_summary",
                    "split": split_name,
                    "segments": len(lengths),
                    "min": min(lengths) if lengths else 0,
                    "median": float(np.median(lengths)) if lengths else 0,
                    "p95": float(np.percentile(lengths, 95)) if lengths else 0,
                    "max": max(lengths) if lengths else 0,
                }
            )
        cross = np.zeros((2, 3), dtype=int)
        for is_transition in (0, 1):
            for cls in range(3):
                cross[is_transition, cls] = int(np.sum((split.turn_transition == bool(is_transition)) & (split.y_main == cls)))
        for is_transition, name in ((0, "non_transition"), (1, "transition")):
            rows.append(
                {
                    "section": "turn_transition_x_main",
                    "split": split_name,
                    "turn_transition": name,
                    "flat": int(cross[is_transition, 0]),
                    "stall": int(cross[is_transition, 1]),
                    "slope": int(cross[is_transition, 2]),
                }
            )
    _write_csv(out_dir / "stall_slope_sample_distribution.csv", rows)

    for split_name in ("train", "val", "test"):
        split = data[split_name]
        counts = _class_counts(split.y_main, 3)
        md.extend(
            [
                f"## {split_name}",
                "",
                f"- flat/stall/slope windows: `{counts[0]}/{counts[1]}/{counts[2]}`",
                f"- turn_transition windows: `{int(np.sum(split.turn_transition))}`",
                f"- stall duration segments: `{len(_duration_lengths(split.y_main == 1))}`",
                f"- slope duration segments: `{len(_duration_lengths(split.y_main == 2))}`",
                "",
            ]
        )
    (out_dir / "stall_slope_sample_distribution.md").write_text("\n".join(md), encoding="utf-8")


def _write_theta_error_reports(out_dir: Path, split, logits_main, logits_turn, theta_hat, metrics) -> None:
    y_main = split.y_main.reshape(-1)
    pred_main = logits_main.argmax(axis=1)
    theta_true = split.y_theta.reshape(-1)
    theta_err_deg = np.abs(np.rad2deg(theta_hat - theta_true))
    main_correct = pred_main == y_main
    top_cut = np.percentile(theta_err_deg, 95)
    rows = []
    groups = [
        ("main_correct", main_correct),
        ("main_error", ~main_correct),
        ("flat_to_stall", (y_main == 0) & (pred_main == 1)),
        ("flat_to_slope", (y_main == 0) & (pred_main == 2)),
        ("slope_to_flat", (y_main == 2) & (pred_main == 0)),
        ("slope_to_stall", (y_main == 2) & (pred_main == 1)),
        ("theta_abs_error_top5pct", theta_err_deg >= top_cut),
        ("theta_edge_abs_ge8", split.mask_theta.astype(bool) & (np.abs(np.rad2deg(theta_true)) >= 8.0)),
    ]
    for name, mask in groups:
        rows.append(_theta_group_row(name, mask, y_main, pred_main, theta_err_deg))
    _write_csv(out_dir / "theta_error_vs_main_error.csv", rows)

    lines = [
        "# Theta Error vs Main Error",
        "",
        f"- main correct theta MAE deg: `{_mean(theta_err_deg[main_correct]):.6f}`",
        f"- main error theta MAE deg: `{_mean(theta_err_deg[~main_correct]):.6f}`",
        f"- theta absolute error top 5% cutoff deg: `{top_cut:.6f}`",
        f"- theta_edge_p95_abs_err_deg: `{metrics.get('theta_edge_p95_abs_err', float('nan'))}`",
        "",
        "| group | n | theta_mae_deg | flat | stall | slope | pred_flat | pred_stall | pred_slope |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['group']} | {row['n']} | {float(row['theta_mae_deg']):.6f} | "
            f"{row['true_flat']} | {row['true_stall']} | {row['true_slope']} | "
            f"{row['pred_flat']} | {row['pred_stall']} | {row['pred_slope']} |"
        )
    (out_dir / "theta_error_vs_main_error.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_diagnosis_summary(out_dir: Path, data, split, logits_main, logits_turn, theta_hat, metrics) -> None:
    train = data["train"]
    val = data["val"]
    test = data["test"]
    train_counts = _class_counts(train.y_main, 3)
    val_counts = _class_counts(val.y_main, 3)
    test_counts = _class_counts(test.y_main, 3)
    stall_sparse = min(train_counts[1], val_counts[1], test_counts[1]) < 100
    y_main = split.y_main.reshape(-1)
    pred_main = logits_main.argmax(axis=1)
    theta_deg = np.rad2deg(split.y_theta.reshape(-1))
    slope_errors = (y_main == 2) & (pred_main != 2)
    slope_boundary_ratio = float(np.mean(np.abs(theta_deg[slope_errors]) < 2.5)) if np.any(slope_errors) else 0.0
    transition = split.turn_transition.astype(bool)
    main_acc_transition = float(np.mean(pred_main[transition] == y_main[transition])) if np.any(transition) else float("nan")
    main_acc_non = float(np.mean(pred_main[~transition] == y_main[~transition])) if np.any(~transition) else float("nan")
    theta_err = np.abs(np.rad2deg(theta_hat - split.y_theta.reshape(-1)))
    main_correct = pred_main == y_main
    theta_tradeoff = _mean(theta_err[~main_correct]) > (_mean(theta_err[main_correct]) * 1.5)
    lines = [
        "# Phase 1 Diagnosis Summary",
        "",
        "No baseline retraining was performed. The diagnosis used the frozen retained champion checkpoint and current seq128 test set.",
        "",
        "## Questions",
        "",
        f"1. stall_recall sample sparsity: `{'YES' if stall_sparse else 'PARTIAL'}`. "
        f"Window counts train/val/test stall = `{train_counts[1]}/{val_counts[1]}/{test_counts[1]}`.",
        f"2. slope boundary concentration: `{'YES' if slope_boundary_ratio >= 0.5 else 'NO/PARTIAL'}`. "
        f"Boundary share among slope errors = `{slope_boundary_ratio:.3f}`.",
        f"3. theta/main trade-off signal: `{'YES' if theta_tradeoff else 'NO/PARTIAL'}`. "
        f"Theta MAE main-correct/error = `{_mean(theta_err[main_correct]):.4f}/{_mean(theta_err[~main_correct]):.4f}` deg.",
        f"4. transition vs stable main accuracy: transition/non-transition = `{main_acc_transition:.4f}/{main_acc_non:.4f}`.",
        "5. seq256 necessity: `REASONABLE_TO_TEST`, because longer context can be evaluated without changing 22D features and may clarify boundary/transition sensitivity; Phase 3 remains deferred until Phase 2 validation passes.",
        "",
        "## Core Baseline Metrics Recomputed",
        "",
        f"- acc_main: `{metrics['acc_main']:.6f}`",
        f"- acc_turn_transition: `{metrics['acc_turn_transition']:.6f}`",
        f"- theta_mae_deg: `{metrics['theta_mae_deg']:.6f}`",
        f"- flat/stall/slope recall: `{metrics['flat_recall']:.6f}/{metrics['stall_recall']:.6f}/{metrics['slope_recall']:.6f}`",
    ]
    (out_dir / "diagnosis_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _phase2_build_seq256(manifest: Dict[str, object], baseline_contract: Dict[str, object]) -> None:
    out_dir = OUT_ROOT / "02_engineering_preflight"
    if SEQ256_DATASET.exists():
        raise FileExistsError(f"seq256 dataset already exists; refusing to overwrite: {SEQ256_DATASET}")
    if SEQ256_CONTRACT.exists():
        raise FileExistsError(f"seq256 contract already exists; refusing to overwrite: {SEQ256_CONTRACT}")

    seq128_dry = _dry_load(BASELINE_DATASET)
    dry_lines = [
        "# Phase 2.0 Engineering Preflight",
        "",
        f"- seq128 baseline dry-load: `{seq128_dry}`",
        "- seq_len whitelist: `128/256`",
        "- default dataset path unchanged in `modern_tcn_data.py`.",
        "- `model_family=small` default behavior unchanged; no training was launched.",
    ]
    (out_dir / "seq_len_whitelist_preflight.md").write_text("\n".join(dry_lines) + "\n", encoding="utf-8")

    base = _load_baseline_dataset_h5(BASELINE_DATASET)
    raw_runs = _load_raw_runs_h5(BASELINE_TRAIN_DATA)
    cfg = _seq_cfg(base)
    cfg["seq_len"] = 256
    windows = _build_windows_from_raw(raw_runs, cfg)
    split = base["split"]
    split_windows = _split_windows(windows, split, int(split["seed"]))
    split_windows, balance_info = _apply_split_balancing_and_shuffle(split_windows, cfg, int(split["seed"]))
    scaler = _fit_scaler_from_train(split_windows["train"], base["scaler"])
    normalized = _normalize_splits(split_windows, scaler["mean"], scaler["std"])
    meta = _build_seq256_meta(base, baseline_contract, cfg, split_windows, balance_info)
    contract = _build_seq256_contract(baseline_contract, meta, split_windows)
    _write_seq256_h5(SEQ256_DATASET, normalized, split_windows, scaler, base, split, meta, contract)
    SEQ256_CONTRACT.write_text(json.dumps(contract, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    _write_seq256_scaler_h5(SEQ256_SCALER, scaler, cfg)
    _write_seq256_prepare_report(SEQ256_REPORT, cfg, split_windows, contract, balance_info)


def _phase2_validate_seq256(manifest: Dict[str, object], baseline_contract: Dict[str, object]) -> None:
    out_dir = OUT_ROOT / "02_seq256_dataset"
    data = load_modern_tcn_dataset(SEQ256_DATASET)
    contract = data["contract"]
    failures = []
    if contract.input_dim != 22:
        failures.append("input_dim != 22")
    if contract.seq_len != 256:
        failures.append("seq_len != 256")
    if contract.feature_contract != "passive17_plus_all5":
        failures.append("feature_contract mismatch")
    if list(data["feat_names"]) != list(baseline_contract["feature_names"]):
        failures.append("feature_names do not match baseline")
    seq256_contract = _load_json(SEQ256_CONTRACT)
    if seq256_contract.get("split_file") != baseline_contract.get("split_file"):
        failures.append("split_file differs from baseline")
    if seq256_contract.get("scaler_policy") != "fit_train_only_apply_val_test_online":
        failures.append("scaler_policy mismatch")
    if seq256_contract.get("label_time_policy") != "current_window_end":
        failures.append("label_time_policy mismatch")
    if int(seq256_contract.get("horizon_steps", -1)) != 0:
        failures.append("horizon_steps mismatch")
    leak = _split_leakage_check(data)
    if not leak["pass"]:
        failures.append("run leakage detected")
    rows = [
        {"split": "train", "windows": int(data["train"].X.shape[0]), "unique_runs": len(set(data["train"].run_id.astype(int)))},
        {"split": "val", "windows": int(data["val"].X.shape[0]), "unique_runs": len(set(data["val"].run_id.astype(int)))},
        {"split": "test", "windows": int(data["test"].X.shape[0]), "unique_runs": len(set(data["test"].run_id.astype(int)))},
    ]
    _write_csv(out_dir / "seq256_window_counts.csv", rows)
    snapshot = {
        "dataset": str(SEQ256_DATASET),
        "contract": str(SEQ256_CONTRACT),
        "input_dim": contract.input_dim,
        "seq_len": contract.seq_len,
        "feature_contract": contract.feature_contract,
        "feature_names": data["feat_names"],
        "split_file": seq256_contract.get("split_file"),
        "split_policy": seq256_contract.get("split_policy"),
        "scaler_policy": seq256_contract.get("scaler_policy"),
        "label_time_policy": seq256_contract.get("label_time_policy"),
        "horizon_steps": seq256_contract.get("horizon_steps"),
        "leakage_check": leak,
    }
    (out_dir / "seq256_feature_contract_snapshot.json").write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    lines = [
        "# seq256 Dataset Validation",
        "",
        f"- generated_at: `{_now()}`",
        f"- status: `{'PASS' if not failures else 'FAIL'}`",
        f"- dataset: `{_rel(SEQ256_DATASET)}`",
        f"- contract: `{_rel(SEQ256_CONTRACT)}`",
        f"- source train data: `{_rel(BASELINE_TRAIN_DATA)}`",
        f"- split source reused: `{seq256_contract.get('split_file')}`",
        f"- scaler policy: `{seq256_contract.get('scaler_policy')}`",
        f"- no split leakage: `{int(leak['pass'])}`",
        "",
        "| split | windows | unique_runs |",
        "|---|---:|---:|",
    ]
    for row in rows:
        lines.append(f"| {row['split']} | {row['windows']} | {row['unique_runs']} |")
    if failures:
        lines.extend(["", "## Failures", "", *[f"- {x}" for x in failures]])
        (out_dir / "failure_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        raise SystemExit(f"Phase 2 validation failed: {failures}")
    lines.extend(
        [
            "",
            "Validation passed. Phase 3 training remains deferred and requires a separate seed21 screening plan.",
        ]
    )
    (out_dir / "seq256_dataset_validation.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _load_baseline_dataset_h5(path: Path) -> Dict[str, object]:
    with h5py.File(path, "r") as f:
        d = f["dataset"]
        base = {
            "feature_names": _read_feature_names(f, d["feat_names"]),
            "scaler": {
                "mean": _vec(d["scaler"]["mean"]).astype(np.float64),
                "std": _vec(d["scaler"]["std"]).astype(np.float64),
                "tau_diff": float(_scalar(d["scaler"]["tau_diff"])),
                "tau_accel_lp": float(_scalar(d["scaler"]["tau_accel_lp"])),
            },
            "meta": {
                "Ts": float(_scalar(d["meta"]["Ts"])),
                "stride": int(_scalar(d["meta"]["stride"])),
                "steady_stride": int(_scalar(d["meta"]["steady_stride"])),
                "transition_stride": int(_scalar(d["meta"]["transition_stride"])),
                "transition_context_sec": float(_scalar(d["meta"]["transition_context_sec"])),
                "skip_initial_sec": float(_scalar(d["meta"]["skip_initial_sec"])),
                "turn_tail_sec": float(_scalar(d["meta"]["turn_tail_sec"])),
                "main_min_purity": float(_scalar(d["meta"]["main_min_purity"])),
                "main_ambiguous_weight": float(_scalar(d["meta"]["main_ambiguous_weight"])),
                "turn_min_purity": float(_scalar(d["meta"]["turn_min_purity"])),
                "turn_ambiguous_weight": float(_scalar(d["meta"]["turn_ambiguous_weight"])),
                "theta_transition_range_deg": float(_scalar(d["meta"]["theta_transition_range_deg"])),
                "theta_transition_weight": float(_scalar(d["meta"]["theta_transition_weight"])),
                "theta_event_range_deg": float(_scalar(d["meta"]["theta_event_range_deg"])),
                "theta_event_window_sec": float(_scalar(d["meta"]["theta_event_window_sec"])),
            },
            "split": {
                "runs_train": _vec(d["split_info"]["runs_train"]).astype(int),
                "runs_val": _vec(d["split_info"]["runs_val"]).astype(int),
                "runs_test": _vec(d["split_info"]["runs_test"]).astype(int),
                "seed": int(_scalar(d["split_info"]["seed"])),
                "strategy": _read_char(d["split_info"]["strategy"]),
                "split_file": str(BASELINE_SPLIT),
            },
        }
    return base


def _load_raw_runs_h5(path: Path) -> List[Dict[str, object]]:
    runs = []
    with h5py.File(path, "r") as f:
        root = f["data"]["runs"]
        n = root["y_raw"].shape[0]
        for i in range(n):
            runs.append(
                {
                    "run_id": i + 1,
                    "y_raw": _deref_array(f, root["y_raw"][i, 0]).T,
                    "label_main": _deref_array(f, root["label_main"][i, 0]).reshape(-1),
                    "label_turn": _deref_array(f, root["label_turn"][i, 0]).reshape(-1),
                    "label_slip": _deref_array(f, root["label_slip"][i, 0]).reshape(-1),
                    "label_stall": _deref_array(f, root["label_stall"][i, 0]).reshape(-1),
                    "label_load_change": _deref_array(f, root["label_load_change"][i, 0]).reshape(-1),
                    "theta": _deref_array(f, root["theta"][i, 0]).reshape(-1),
                    "y_theta_ground": _deref_array(f, root["y_theta_ground"][i, 0]).reshape(-1),
                    "scene": _read_ref_string(f, root["scene"][i, 0]),
                    "path_file": _read_ref_string(f, root["path_file"][i, 0]),
                }
            )
    return runs


def _seq_cfg(base: Dict[str, object]) -> Dict[str, object]:
    meta = base["meta"]
    scaler = base["scaler"]
    return {
        "Ts": meta["Ts"],
        "seq_len": 128,
        "stride": meta["stride"],
        "steady_stride": meta["steady_stride"],
        "transition_stride": meta["transition_stride"],
        "transition_context_sec": meta["transition_context_sec"],
        "skip_initial_sec": meta["skip_initial_sec"],
        "turn_tail_sec": meta["turn_tail_sec"],
        "main_min_purity": meta["main_min_purity"],
        "main_ambiguous_weight": meta["main_ambiguous_weight"],
        "turn_min_purity": meta["turn_min_purity"],
        "turn_ambiguous_weight": meta["turn_ambiguous_weight"],
        "theta_transition_range_deg": meta["theta_transition_range_deg"],
        "theta_transition_weight": meta["theta_transition_weight"],
        "theta_event_range_deg": meta["theta_event_range_deg"],
        "theta_event_window_sec": meta["theta_event_window_sec"],
        "theta_mask_strategy": "nonstall_full_range",
        "theta_split_edges_deg": list(range(-10, 11)),
        "theta_balance_after_split": True,
        "theta_balance_max_imbalance": 1.45,
        "turn_balance_after_split": True,
        "turn_balance_min_lr_balance": 0.90,
        "tau_diff": scaler["tau_diff"],
        "tau_accel_lp": scaler["tau_accel_lp"],
    }


def _build_windows_from_raw(raw_runs: List[Dict[str, object]], cfg: Dict[str, object]) -> List[Dict[str, object]]:
    rows = []
    for run in raw_runs:
        y_raw = np.asarray(run["y_raw"], dtype=np.float64)
        n0 = y_raw.shape[0]
        skip = min(n0 - 1, max(0, int(round(cfg["skip_initial_sec"] / cfg["Ts"]))))
        idx = np.arange(skip, n0)
        y_used = y_raw[idx, :]
        features = _extract_passive_features(y_used, cfg)
        labels = {
            "y_main": np.asarray(run["label_main"])[idx],
            "y_turn": np.asarray(run["label_turn"])[idx],
            "y_theta": np.asarray(run["y_theta_ground"])[idx]
            if len(np.asarray(run["y_theta_ground"]).reshape(-1)) >= n0
            else np.asarray(run["theta"])[idx],
            "y_slip": np.asarray(run["label_slip"])[idx],
            "y_stall": np.asarray(run["label_stall"])[idx],
            "y_load_change": np.asarray(run["label_load_change"])[idx],
        }
        starts = _window_starts(labels, len(idx), cfg)
        tail_len = max(1, min(int(cfg["seq_len"]), int(round(cfg["turn_tail_sec"] / cfg["Ts"]))))
        for start in starts:
            end = start + int(cfg["seq_len"])
            main_window = labels["y_main"][start:end]
            y_main = int(labels["y_main"][end - 1])
            main_purity = float(np.mean(main_window == y_main))
            turn_window = labels["y_turn"][start:end]
            y_turn, turn_purity = _turn_label(turn_window, tail_len)
            theta_window = labels["y_theta"][start:end]
            theta_range = float(np.max(theta_window) - np.min(theta_window))
            rows.append(
                {
                    "X": features[start:end, :].astype(np.float64),
                    "run_id": int(run["run_id"]),
                    "start_rel": int(start + 1),
                    "end_rel": int(end),
                    "y_main": y_main,
                    "y_turn": int(y_turn),
                    "y_theta": float(labels["y_theta"][end - 1]),
                    "y_slip": float(labels["y_slip"][end - 1]),
                    "y_stall": float(labels["y_stall"][end - 1]),
                    "y_load_change": float(labels["y_load_change"][end - 1]),
                    "main_purity": main_purity,
                    "main_transition": int(len(set(main_window.astype(int).tolist())) > 1),
                    "main_sample_weight": cfg["main_ambiguous_weight"] if main_purity < cfg["main_min_purity"] else 1.0,
                    "turn_purity": turn_purity,
                    "turn_transition": int(len(set(turn_window.astype(int).tolist())) > 1),
                    "turn_sample_weight": cfg["turn_ambiguous_weight"] if turn_purity < cfg["turn_min_purity"] else 1.0,
                    "theta_range": theta_range,
                    "theta_transition": int(theta_range >= math.radians(cfg["theta_transition_range_deg"])),
                    "theta_sample_weight": cfg["theta_transition_weight"]
                    if theta_range >= math.radians(cfg["theta_transition_range_deg"])
                    else 1.0,
                }
            )
    return rows


def _extract_passive_features(y_raw: np.ndarray, cfg: Dict[str, object]) -> np.ndarray:
    y = np.asarray(y_raw, dtype=np.float64)
    if y.shape[1] < 18:
        raise ValueError("y_raw needs at least 18 columns")
    gyro_z = y[:, 10]
    i_lf = y[:, 11]
    i_rr = y[:, 12]
    omega_lf = y[:, 16]
    omega_rr = y[:, 17]
    delta_lf = y[:, 5]
    delta_rr = y[:, 6]
    r = 0.1
    width = 1.0
    v_hat = r * (omega_lf + omega_rr) / 2.0
    accel_x = np.zeros_like(v_hat)
    accel_x[1:] = np.diff(v_hat) / cfg["Ts"]
    alpha_diff = cfg["Ts"] / (cfg["tau_diff"] + cfg["Ts"])
    alpha_lp = cfg["Ts"] / (cfg["tau_accel_lp"] + cfg["Ts"])
    dv_hat_dt = np.zeros_like(v_hat)
    dv_hat_dt_lp = np.zeros_like(v_hat)
    for i in range(1, len(v_hat)):
        dv_hat_dt[i] = alpha_diff * accel_x[i] + (1 - alpha_diff) * dv_hat_dt[i - 1]
        dv_hat_dt_lp[i] = alpha_lp * dv_hat_dt[i] + (1 - alpha_lp) * dv_hat_dt_lp[i - 1]
    ws_imbalance = np.abs(omega_lf - omega_rr)
    i_sum = np.abs(i_lf) + np.abs(i_rr)
    i_diff_signed = i_lf - i_rr
    i_diff_abs = np.abs(i_lf) - np.abs(i_rr)
    kappa_proxy = (np.tan(delta_lf) - np.tan(delta_rr)) / width
    accel_per_current = dv_hat_dt / np.maximum(i_sum, 0.1)
    i_drive_signed = i_lf + i_rr
    current_per_accel = i_sum / np.maximum(np.abs(dv_hat_dt_lp), 0.05)
    drive_load_proxy = i_drive_signed - dv_hat_dt_lp
    a_hp = accel_x - dv_hat_dt_lp
    yaw_consistency_error = gyro_z - v_hat * kappa_proxy
    return np.column_stack(
        [
            gyro_z,
            i_lf,
            i_rr,
            omega_lf,
            omega_rr,
            delta_lf,
            delta_rr,
            v_hat,
            dv_hat_dt,
            ws_imbalance,
            i_sum,
            i_diff_signed,
            i_diff_abs,
            kappa_proxy,
            accel_per_current,
            dv_hat_dt_lp,
            accel_x,
            i_drive_signed,
            current_per_accel,
            drive_load_proxy,
            a_hp,
            yaw_consistency_error,
        ]
    )


def _window_starts(labels: Dict[str, np.ndarray], n: int, cfg: Dict[str, object]) -> np.ndarray:
    seq_len = int(cfg["seq_len"])
    last_start = n - seq_len
    if last_start < 0:
        return np.array([], dtype=int)
    steady = np.arange(0, last_start + 1, int(cfg["steady_stride"]))
    cand = np.arange(0, last_start + 1, int(cfg["transition_stride"]))
    event_mask = _event_mask(labels, cfg)
    keep = []
    for s in cand:
        if np.any(event_mask[s : s + seq_len]):
            keep.append(s)
    starts = np.unique(np.concatenate([steady, np.asarray(keep, dtype=int), np.asarray([last_start], dtype=int)]))
    return starts.astype(int)


def _event_mask(labels: Dict[str, np.ndarray], cfg: Dict[str, object]) -> np.ndarray:
    y_main = labels["y_main"].reshape(-1)
    y_turn = labels["y_turn"].reshape(-1)
    theta = labels["y_theta"].reshape(-1)
    n = len(y_main)
    change = np.zeros(n, dtype=bool)
    change[1:] |= np.diff(y_main) != 0
    change[1:] |= np.diff(y_turn) != 0
    change[1:] |= np.abs(np.diff(theta)) >= math.radians(0.20)
    half = max(1, int(round(cfg["theta_event_window_sec"] / cfg["Ts"])))
    smooth = np.zeros(n, dtype=bool)
    threshold = math.radians(cfg["theta_event_range_deg"])
    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)
        if np.max(theta[lo:hi]) - np.min(theta[lo:hi]) >= threshold:
            smooth[i] = True
    event_idx = np.flatnonzero(change | smooth)
    out = np.zeros(n, dtype=bool)
    buf = max(0, int(round(cfg["transition_context_sec"] / cfg["Ts"])))
    for i in event_idx:
        out[max(0, i - buf) : min(n, i + buf + 1)] = True
    return out


def _turn_label(window: np.ndarray, tail_len: int) -> Tuple[int, float]:
    tail = window[-tail_len:]
    labels = np.array([-1, 0, 1])
    counts = np.array([np.sum(tail == v) for v in labels])
    mx = counts.max()
    ties = labels[counts == mx]
    if len(ties) == 1:
        label = int(ties[0])
    elif window[-1] in ties:
        label = int(window[-1])
    elif 0 in ties:
        label = 0
    else:
        label = int(ties[0])
    purity = float(np.mean(window == label))
    return label, purity


def _split_windows(rows: List[Dict[str, object]], split: Dict[str, object], seed: int) -> Dict[str, List[Dict[str, object]]]:
    runs_train = set(int(x) for x in split["runs_train"])
    runs_val = set(int(x) for x in split["runs_val"])
    runs_test = set(int(x) for x in split["runs_test"])
    return {
        "train": [r for r in rows if r["run_id"] in runs_train],
        "val": [r for r in rows if r["run_id"] in runs_val],
        "test": [r for r in rows if r["run_id"] in runs_test],
    }


def _apply_split_balancing_and_shuffle(split_windows, cfg, seed):
    out = {}
    info = {}
    for offset, name in enumerate(("train", "val", "test"), start=1):
        rows = list(split_windows[name])
        split_info = {}
        if cfg["theta_balance_after_split"]:
            rows, split_info["theta_balance"] = _balance_theta_rows(rows, cfg, seed + 100 + offset)
        if cfg["turn_balance_after_split"]:
            rows, split_info["turn_balance"] = _balance_turn_rows(rows, cfg, seed + 200 + offset)
        if cfg["theta_balance_after_split"] and cfg["turn_balance_after_split"]:
            rows, split_info["theta_rebalance"] = _balance_theta_rows(rows, cfg, seed + 300 + offset)
        rng = np.random.default_rng(seed)
        perm = rng.permutation(len(rows))
        out[name] = [rows[int(i)] for i in perm]
        info[name] = split_info
    return out, info


def _balance_theta_rows(rows, cfg, seed):
    edges = np.asarray(cfg["theta_split_edges_deg"], dtype=float)
    n_bins = max(0, len(edges) - 1)
    before = [0 for _ in range(n_bins)]
    after = [0 for _ in range(n_bins)]
    info = {"enabled": True, "before": before, "after": after, "cap": None, "kept": len(rows), "dropped": 0}
    if n_bins == 0:
        return rows, info
    theta = np.asarray([float(r["y_theta"]) for r in rows], dtype=float)
    theta_deg = np.rad2deg(theta)
    y_main = np.asarray([int(r["y_main"]) for r in rows], dtype=int)
    theta_mask = _theta_supervision_mask(y_main, theta) == 1
    bin_id = np.zeros(len(rows), dtype=int)
    for bi in range(n_bins):
        if bi == n_bins - 1:
            in_bin = theta_mask & (theta_deg >= edges[bi]) & (theta_deg <= edges[bi + 1])
        else:
            in_bin = theta_mask & (theta_deg >= edges[bi]) & (theta_deg < edges[bi + 1])
        bin_id[in_bin] = bi + 1
        before[bi] = int(np.sum(in_bin))
    active_counts = [x for x in before if x > 0]
    if not active_counts:
        return rows, info
    cap = max(1, int(math.floor(min(active_counts) * float(cfg["theta_balance_max_imbalance"]))))
    keep = np.ones(len(rows), dtype=bool)
    rng = np.random.default_rng(seed)
    for bi in range(1, n_bins + 1):
        members = np.flatnonzero(bin_id == bi)
        if len(members) > cap:
            perm = rng.permutation(members)
            keep[perm[cap:]] = False
    kept_rows = [r for r, k in zip(rows, keep) if k]
    kept_bins = bin_id[keep]
    for bi in range(n_bins):
        after[bi] = int(np.sum(kept_bins == bi + 1))
    info.update({"after": after, "cap": cap, "kept": len(kept_rows), "dropped": len(rows) - len(kept_rows)})
    return kept_rows, info


def _balance_turn_rows(rows, cfg, seed):
    y_turn = np.asarray([int(r["y_turn"]) for r in rows], dtype=int)
    right_idx = np.flatnonzero(y_turn == -1)
    left_idx = np.flatnonzero(y_turn == 1)
    info = {
        "enabled": True,
        "before": [int(len(right_idx)), int(len(left_idx))],
        "after": [int(len(right_idx)), int(len(left_idx))],
        "kept": len(rows),
        "dropped": 0,
    }
    if len(right_idx) == 0 or len(left_idx) == 0:
        return rows, info
    target = max(np.finfo(float).eps, float(cfg["turn_balance_min_lr_balance"]))
    balance = min(len(right_idx), len(left_idx)) / max(len(right_idx), len(left_idx))
    if balance >= target:
        return rows, info
    keep = np.ones(len(rows), dtype=bool)
    rng = np.random.default_rng(seed)
    if len(right_idx) > len(left_idx):
        cap = int(math.floor(len(left_idx) / target))
        drop_pool = rng.permutation(right_idx)
        keep[drop_pool[cap:]] = False
    else:
        cap = int(math.floor(len(right_idx) / target))
        drop_pool = rng.permutation(left_idx)
        keep[drop_pool[cap:]] = False
    kept_rows = [r for r, k in zip(rows, keep) if k]
    y_after = np.asarray([int(r["y_turn"]) for r in kept_rows], dtype=int)
    info.update(
        {
            "after": [int(np.sum(y_after == -1)), int(np.sum(y_after == 1))],
            "kept": len(kept_rows),
            "dropped": len(rows) - len(kept_rows),
        }
    )
    return kept_rows, info


def _fit_scaler_from_train(train_rows, base_scaler):
    x = np.stack([r["X"] for r in train_rows], axis=0)
    flat = x.reshape(-1, x.shape[-1])
    mean = flat.mean(axis=0)
    std = flat.std(axis=0, ddof=0)
    std[std < 1e-8] = 1.0
    return {
        "mean": mean.astype(np.float64),
        "std": std.astype(np.float64),
        "tau_diff": base_scaler["tau_diff"],
        "tau_accel_lp": base_scaler["tau_accel_lp"],
    }


def _normalize_splits(split_windows, mean, std):
    out = {}
    mean = np.asarray(mean, dtype=np.float64).reshape(1, 1, -1)
    std = np.asarray(std, dtype=np.float64).reshape(1, 1, -1)
    for name, rows in split_windows.items():
        x = np.stack([r["X"] for r in rows], axis=0)
        out[name] = (x - mean) / std
    return out


def _build_seq256_meta(base, baseline_contract, cfg, split_windows, balance_info):
    return {
        "created_at": _now(),
        "source_file": str(BASELINE_TRAIN_DATA),
        "output_file": str(SEQ256_DATASET),
        "Ts": cfg["Ts"],
        "seq_len": 256,
        "stride": cfg["stride"],
        "steady_stride": cfg["steady_stride"],
        "transition_stride": cfg["transition_stride"],
        "transition_context_sec": cfg["transition_context_sec"],
        "skip_initial_sec": cfg["skip_initial_sec"],
        "turn_tail_sec": cfg["turn_tail_sec"],
        "main_min_purity": cfg["main_min_purity"],
        "main_ambiguous_weight": cfg["main_ambiguous_weight"],
        "turn_min_purity": cfg["turn_min_purity"],
        "turn_ambiguous_weight": cfg["turn_ambiguous_weight"],
        "theta_transition_range_deg": cfg["theta_transition_range_deg"],
        "theta_transition_weight": cfg["theta_transition_weight"],
        "theta_event_range_deg": cfg["theta_event_range_deg"],
        "theta_event_window_sec": cfg["theta_event_window_sec"],
        "theta_mask_strategy": cfg["theta_mask_strategy"],
        "theta_split_edges_deg": cfg["theta_split_edges_deg"],
        "theta_balance_after_split": cfg["theta_balance_after_split"],
        "theta_balance_max_imbalance": cfg["theta_balance_max_imbalance"],
        "turn_balance_after_split": cfg["turn_balance_after_split"],
        "turn_balance_min_lr_balance": cfg["turn_balance_min_lr_balance"],
        "feature_contract": "passive17_plus_all5",
        "feature_policy": baseline_contract.get("feature_policy", "imu_free_passive17_plus_all5"),
        "feature_extractor": "passive",
        "input_dim": 22,
        "plant_revision": baseline_contract.get("plant_revision", {}),
        "no_new_inputs": True,
        "base_feature_contract": "passive17_plus_all5",
        "plan_branch": "Plan A passive-only",
        "vehicle_type": baseline_contract.get("vehicle_type", "diagonal_dual_steer_drive_agv"),
        "active_drive_steer_wheels": baseline_contract.get("active_drive_steer_wheels", ["LF", "RR"]),
        "passive_support_wheels": baseline_contract.get("passive_support_wheels", ["RF", "LR"]),
        "label_time_policy": "current_window_end",
        "horizon_steps": 0,
        "horizon_seconds": 0,
        "confidence_policy": "derive_classification_confidence_from_softmax_and_export",
        "split_strategy": "run_level_no_window_leakage",
        "split_file": str(BASELINE_SPLIT),
        "contract_file": str(SEQ256_CONTRACT),
        "train_ratio": baseline_contract.get("train_ratio", 0.70),
        "val_ratio": baseline_contract.get("val_ratio", 0.15),
        "test_ratio": baseline_contract.get("test_ratio", 0.15),
        "label_map_main": {"flat": 1, "stall": 2, "slope": 3},
        "label_map_turn": {"right": -1, "straight": 0, "left": 1},
        "self_check": {
            "n_train": len(split_windows["train"]),
            "n_val": len(split_windows["val"]),
            "n_test": len(split_windows["test"]),
            "seq_len": 256,
            "feat_dim": 22,
        },
        "balance_info": balance_info,
    }


def _build_seq256_contract(baseline_contract, meta, split_windows):
    c = dict(baseline_contract)
    c.update(
        {
            "dataset_version": "diag2steer_Ts0p01_seq256_input22_h0_current_confidence",
            "created_at": meta["created_at"],
            "source_file": str(BASELINE_TRAIN_DATA),
            "output_file": str(SEQ256_DATASET),
            "seq_len": 256,
            "input_dim": 22,
            "feature_names": FEATURE_NAMES,
            "feature_contract": "passive17_plus_all5",
            "label_time_policy": "current_window_end",
            "horizon_steps": 0,
            "horizon_seconds": 0,
            "split_policy": "run_level_no_window_leakage",
            "split_file": str(BASELINE_SPLIT),
            "scaler_policy": "fit_train_only_apply_val_test_online",
            "train_windows": len(split_windows["train"]),
            "val_windows": len(split_windows["val"]),
            "test_windows": len(split_windows["test"]),
        }
    )
    return c


def _write_seq256_h5(path, normalized, split_windows, scaler, base, split, meta, contract):
    with h5py.File(path, "w") as f:
        d = f.create_group("dataset")
        for name in ("train", "val", "test"):
            rows = split_windows[name]
            x = normalized[name]
            d.create_dataset(f"X_{name}", data=np.transpose(x, (2, 1, 0)), compression="gzip", compression_opts=4)
            for key in (
                "y_main",
                "main_purity",
                "main_transition",
                "main_sample_weight",
                "y_turn",
                "turn_purity",
                "turn_transition",
                "turn_sample_weight",
                "y_theta",
                "theta_range",
                "theta_transition",
                "theta_sample_weight",
                "y_slip",
                "y_stall",
                "y_load_change",
                "run_id",
            ):
                arr = np.asarray([r[key] for r in rows], dtype=np.float64).reshape(1, -1)
                d.create_dataset(f"{key}_{name}", data=arr)
            mask = _theta_supervision_mask(np.asarray([r["y_main"] for r in rows]), np.asarray([r["y_theta"] for r in rows]))
            d.create_dataset(f"mask_theta_{name}", data=mask.reshape(1, -1))
        _write_string_refs(f, d, "feat_names", FEATURE_NAMES)
        sg = d.create_group("scaler")
        sg.create_dataset("mean", data=np.asarray(scaler["mean"]).reshape(-1, 1))
        sg.create_dataset("std", data=np.asarray(scaler["std"]).reshape(-1, 1))
        sg.create_dataset("tau_accel_lp", data=np.asarray([[scaler["tau_accel_lp"]]]))
        sg.create_dataset("tau_diff", data=np.asarray([[scaler["tau_diff"]]]))
        _write_utf16(sg, "feature_contract", "passive17_plus_all5")
        _write_utf16(sg, "feature_policy", "imu_free_passive17_plus_all5")
        _write_string_refs(f, sg, "feature_names", FEATURE_NAMES)
        mg = d.create_group("meta")
        _write_meta_group(mg, meta)
        cg = d.create_group("contract")
        _write_meta_group(cg, contract)
        sp = d.create_group("split_info")
        _write_split_group(sp, split, seq_len=256)
        rt = d.create_group("run_table")
        run_ids = sorted(set([r["run_id"] for rs in split_windows.values() for r in rs]))
        _write_string_refs(f, rt, "run_id", [str(x) for x in run_ids])
        _write_string_refs(f, rt, "scene", ["" for _ in run_ids])
        _write_string_refs(f, rt, "path_file", ["" for _ in run_ids])
        _write_string_refs(f, rt, "n_raw", ["" for _ in run_ids])
        _write_string_refs(f, rt, "n_used", ["" for _ in run_ids])


def _write_seq256_scaler_h5(path, scaler, cfg):
    with h5py.File(path, "w") as f:
        sg = f.create_group("scaler")
        sg.create_dataset("mean", data=np.asarray(scaler["mean"]).reshape(-1, 1))
        sg.create_dataset("std", data=np.asarray(scaler["std"]).reshape(-1, 1))
        sg.create_dataset("tau_accel_lp", data=np.asarray([[scaler["tau_accel_lp"]]]))
        sg.create_dataset("tau_diff", data=np.asarray([[scaler["tau_diff"]]]))
        _write_utf16(sg, "feature_contract", "passive17_plus_all5")
        _write_utf16(sg, "feature_policy", "imu_free_passive17_plus_all5")
        _write_string_refs(f, sg, "feature_names", FEATURE_NAMES)
        f.create_dataset("seq_len", data=np.asarray([[256.0]]))
        f.create_dataset("stride", data=np.asarray([[cfg["stride"]]]))
        f.create_dataset("Ts", data=np.asarray([[cfg["Ts"]]]))


def _write_seq256_prepare_report(path, cfg, split_windows, contract, balance_info):
    lines = [
        "# ModernTCN seq256 Prepare Dataset Report",
        "",
        f"- Generated: {_now()}",
        f"- Source: `{BASELINE_TRAIN_DATA}`",
        f"- Output: `{SEQ256_DATASET}`",
        f"- Split file reused: `{BASELINE_SPLIT}`",
        f"- Contract file: `{SEQ256_CONTRACT}`",
        "- Split strategy: `reuse baseline run-level split ids`",
        "- Scaler policy: `fit seq256 train windows only; apply val/test/online`",
        "- Feature contract: `passive17_plus_all5`",
        "- Plant revision: `agv_physics_v2_plantfix`",
        "- Label time policy: `current_window_end`, horizon_steps=0",
        "- seq_len: 256",
        f"- steady_stride: {cfg['steady_stride']}",
        f"- transition_stride: {cfg['transition_stride']}",
        f"- transition_context_sec: {cfg['transition_context_sec']:.2f}",
        "- theta_balance_after_split: `1`",
        "- turn_balance_after_split: `1`",
        "- Python builder note: split-level balancing policy was reimplemented from `TCN_prepare_dataset.m`; MATLAB/Simulink was not invoked.",
        "",
        "## Window Counts",
        "",
        "| split | windows |",
        "|---|---:|",
        f"| train | {len(split_windows['train'])} |",
        f"| val | {len(split_windows['val'])} |",
        f"| test | {len(split_windows['test'])} |",
        "",
        "## Balance Drops",
        "",
        "| split | theta dropped | turn dropped | theta rebalance dropped |",
        "|---|---:|---:|---:|",
    ]
    for name in ("train", "val", "test"):
        info = balance_info[name]
        lines.append(
            f"| {name} | {info.get('theta_balance', {}).get('dropped', 0)} | "
            f"{info.get('turn_balance', {}).get('dropped', 0)} | "
            f"{info.get('theta_rebalance', {}).get('dropped', 0)} |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_master_summary() -> None:
    rows = [
        {"phase": "0", "status": "PASS", "artifact": _rel(OUT_ROOT / "00_evidence_lock" / "evidence_lock.md")},
        {"phase": "1", "status": "PASS", "artifact": _rel(OUT_ROOT / "01_error_diagnosis" / "diagnosis_summary.md")},
        {"phase": "2", "status": "PASS", "artifact": _rel(OUT_ROOT / "02_seq256_dataset" / "seq256_dataset_validation.md")},
    ]
    _write_csv(OUT_ROOT / "first_round_phase0_2_summary.csv", rows)
    lines = [
        "# ModernTCN next-round 22D Phase 0-2 Summary",
        "",
        "- Phase 0 evidence lock: PASS",
        "- Phase 1 baseline diagnosis: PASS",
        "- Phase 2 seq256 dataset validation: PASS",
        "- No new training, ONNX export, MATLAB, Simulink, or closed-loop execution was performed.",
        "- Phase 3 seed21 screening remains deferred.",
    ]
    (OUT_ROOT / "FIRST_ROUND_HANDOFF.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _theta_supervision_mask(y_main, y_theta):
    return ((np.asarray(y_main).reshape(-1) != 2) & np.isfinite(np.asarray(y_theta).reshape(-1))).astype(float)


def _split_leakage_check(data):
    train = set(data["train"].run_id.astype(int).tolist())
    val = set(data["val"].run_id.astype(int).tolist())
    test = set(data["test"].run_id.astype(int).tolist())
    return {
        "pass": not ((train & val) or (train & test) or (val & test)),
        "train_val_overlap": sorted(train & val),
        "train_test_overlap": sorted(train & test),
        "val_test_overlap": sorted(val & test),
    }


def _dry_load(path: Path) -> str:
    data = load_modern_tcn_dataset(path, limit_train=4, limit_val=4, limit_test=4)
    c = data["contract"]
    return f"ok input=[4,{c.seq_len},{c.input_dim}] feature_contract={c.feature_contract}"


def _write_meta_group(g, obj):
    for key, value in obj.items():
        if isinstance(value, dict):
            sub = g.create_group(key)
            _write_meta_group(sub, value)
        elif isinstance(value, (list, tuple)):
            if all(isinstance(x, str) for x in value):
                _write_utf16(g, key, ",".join(value))
            else:
                g.create_dataset(key, data=np.asarray(value, dtype=np.float64))
        elif isinstance(value, str):
            _write_utf16(g, key, value)
        elif isinstance(value, bool):
            g.create_dataset(key, data=np.asarray([[1 if value else 0]], dtype=np.uint8))
        elif value is None:
            _write_utf16(g, key, "")
        else:
            g.create_dataset(key, data=np.asarray([[float(value)]], dtype=np.float64))


def _write_split_group(g, split, seq_len: int):
    g.create_dataset("runs_train", data=np.asarray(split["runs_train"], dtype=np.float64).reshape(1, -1))
    g.create_dataset("runs_val", data=np.asarray(split["runs_val"], dtype=np.float64).reshape(1, -1))
    g.create_dataset("runs_test", data=np.asarray(split["runs_test"], dtype=np.float64).reshape(1, -1))
    g.create_dataset("seed", data=np.asarray([[split["seed"]]], dtype=np.float64))
    g.create_dataset("seq_len", data=np.asarray([[seq_len]], dtype=np.float64))
    g.create_dataset("stride", data=np.asarray([[64]], dtype=np.float64))
    g.create_dataset("skip_initial_sec", data=np.asarray([[1.0]], dtype=np.float64))
    _write_utf16(g, "strategy", split["strategy"])
    _write_utf16(g, "generation_time", _now())


def _write_utf16(group, name: str, value: str):
    arr = np.asarray([ord(c) for c in str(value)], dtype=np.uint16).reshape(-1, 1)
    group.create_dataset(name, data=arr)


def _write_string_refs(f, group, name: str, values: List[str]):
    refs = []
    ref_root = f.require_group("#refs#")
    for i, value in enumerate(values):
        ds_name = f"{group.name.strip('/').replace('/', '_')}_{name}_{i:04d}"
        if ds_name in ref_root:
            del ref_root[ds_name]
        ds = ref_root.create_dataset(ds_name, data=np.asarray([ord(c) for c in str(value)], dtype=np.uint16).reshape(-1, 1))
        refs.append(ds.ref)
    dt = h5py.special_dtype(ref=h5py.Reference)
    group.create_dataset(name, data=np.asarray(refs, dtype=dt).reshape(-1, 1))


def _deref_array(f, ref):
    return np.asarray(f[ref])


def _read_ref_string(f, ref) -> str:
    obj = f[ref]
    if isinstance(obj, h5py.Dataset):
        return _read_char(obj)
    return ""


def _read_feature_names(f, ds) -> List[str]:
    refs = np.asarray(ds).reshape(-1)
    return [_read_char(f[ref]) for ref in refs]


def _read_char(ds) -> str:
    raw = np.asarray(ds).reshape(-1)
    return "".join(chr(int(c)) for c in raw if int(c) != 0)


def _vec(ds) -> np.ndarray:
    return np.asarray(ds).reshape(-1)


def _scalar(ds) -> float:
    return float(np.asarray(ds).reshape(-1)[0])


def _load_json(path: Path) -> Dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def _read_csv(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _write_csv(path: Path, rows: List[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    keys = []
    for row in rows:
        for key in row.keys():
            if key not in keys:
                keys.append(key)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)


def _classification_rows(y_true, y_pred, labels):
    rows = []
    y_true = np.asarray(y_true)
    y_pred = np.asarray(y_pred)
    for i, label in enumerate(labels):
        tp = int(np.sum((y_true == i) & (y_pred == i)))
        fp = int(np.sum((y_true != i) & (y_pred == i)))
        fn = int(np.sum((y_true == i) & (y_pred != i)))
        precision = tp / max(tp + fp, 1)
        recall = tp / max(tp + fn, 1)
        f1 = 2 * precision * recall / max(precision + recall, 1e-12)
        rows.append({"class": label, "precision": precision, "recall": recall, "f1": f1, "support": int(np.sum(y_true == i))})
    return rows


def _format_class_rows(rows):
    return [f"| {r['class']} | {r['precision']:.6f} | {r['recall']:.6f} | {r['f1']:.6f} | {r['support']} |" for r in rows]


def _class_counts(labels, n):
    return [int(np.sum(np.asarray(labels).reshape(-1) == i)) for i in range(n)]


def _run_counts(run_ids):
    out = {}
    for rid in np.asarray(run_ids).astype(int).reshape(-1):
        out[int(rid)] = out.get(int(rid), 0) + 1
    return dict(sorted(out.items()))


def _duration_lengths(mask):
    mask = np.asarray(mask, dtype=bool).reshape(-1)
    lengths = []
    i = 0
    while i < len(mask):
        if not mask[i]:
            i += 1
            continue
        j = i
        while j < len(mask) and mask[j]:
            j += 1
        lengths.append(j - i)
        i = j
    return lengths


def _theta_group_row(name, mask, y_main, pred_main, theta_err_deg):
    mask = np.asarray(mask, dtype=bool)
    return {
        "group": name,
        "n": int(np.sum(mask)),
        "theta_mae_deg": _mean(theta_err_deg[mask]),
        "true_flat": int(np.sum(mask & (y_main == 0))),
        "true_stall": int(np.sum(mask & (y_main == 1))),
        "true_slope": int(np.sum(mask & (y_main == 2))),
        "pred_flat": int(np.sum(mask & (pred_main == 0))),
        "pred_stall": int(np.sum(mask & (pred_main == 1))),
        "pred_slope": int(np.sum(mask & (pred_main == 2))),
    }


def _softmax(x):
    x = np.asarray(x)
    x = x - np.max(x, axis=1, keepdims=True)
    ex = np.exp(x)
    return ex / np.sum(ex, axis=1, keepdims=True)


def _mean(x):
    x = np.asarray(x)
    return float(np.mean(x)) if x.size else float("nan")


def _git(args: List[str]) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=ROOT, text=True, stderr=subprocess.STDOUT).strip()
    except Exception as exc:
        return f"git command failed: {exc}"


def _rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve())).replace("\\", "/")
    except Exception:
        return str(path)


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


if __name__ == "__main__":
    main()
