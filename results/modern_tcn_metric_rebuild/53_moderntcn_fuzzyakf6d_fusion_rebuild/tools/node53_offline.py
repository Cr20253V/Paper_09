from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import h5py
import numpy as np

from node53_common import NODE, NODE43, RAW, SPLIT, load_protocol, sha256, write_csv, write_json
from node53_fuzzyakf6_estimator import replay as fuzzy_replay

TS = 0.01
G = 9.81
SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
FLOOR = np.deg2rad(0.02) ** 2


def split_ids() -> dict[str, list[int]]:
    value = json.loads(SPLIT.read_text(encoding="utf-8"))
    if value.get("status") != "PASS_SPLIT_AUDIT":
        raise RuntimeError("split audit is not passed")
    return {k: [int(v) for v in value["run_ids"][k]] for k in ("train", "validation", "test")}


def raw_run(run_id: int) -> dict[str, np.ndarray]:
    with h5py.File(RAW, "r") as raw:
        runs = raw["data/runs"]
        i = run_id - 1
        t = np.asarray(raw[runs["t"][i, 0]], dtype=float).reshape(-1)
        y = np.asarray(raw[runs["y_raw"][i, 0]], dtype=float)
        truth = np.asarray(raw[runs["y_theta_ground"][i, 0]], dtype=float).reshape(-1)
    if y.shape[0] == 34:
        y = y.T
    n = min(len(t), y.shape[0], len(truth))
    return {"time": t[:n], "y_raw": y[:n, :34], "truth": truth[:n]}


def keyed_randn(seed: int, k: int, ch: int, lane: int) -> float:
    def u(l: int) -> float:
        v = (seed + 1664525 * (k + 1) + 1013904223 * ch + 69069 * l) & 0xFFFFFFFF
        v ^= (v << 13) & 0xFFFFFFFF
        v ^= v >> 17
        v ^= (v << 5) & 0xFFFFFFFF
        return (float(v & 0xFFFFFFFF) + 0.5) / 4294967296.0
    return math.sqrt(-2 * math.log(max(u(lane), np.finfo(float).tiny))) * math.cos(2 * math.pi * u(2 if lane == 1 else 1))


def sensor_stream(run: dict[str, np.ndarray], seed: int = 4631) -> np.ndarray:
    y = run["y_raw"]; n = len(run["truth"]); pitch = run["truth"]
    body = np.zeros(n); rate = np.zeros(n); wn = 2 * math.pi * 3.0
    for k in range(1, n):
        acc = wn * wn * (pitch[k - 1] - body[k - 1]) - 2 * 0.9 * wn * rate[k - 1]
        rate[k] = np.clip(rate[k - 1] + TS * acc, -np.deg2rad(30), np.deg2rad(30)); body[k] = body[k - 1] + TS * rate[k]
    long_acc = np.r_[np.diff(y[:, 7]) / TS, 0.0] if n > 1 else np.zeros(1)
    lat_acc = y[:, 7] * y[:, 10]
    delta = np.deg2rad(0.15); c, s = math.cos(delta), math.sin(delta); ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    raw = np.zeros((n, 6)); previous = raw.copy(); aa = np.exp(-2 * math.pi * 15 * TS); gg = np.exp(-2 * math.pi * 25 * TS)
    for k in range(n):
        specific = np.array([y[k, 8] + G * math.sin(body[k]), y[k, 33], G * math.cos(body[k])])
        accel = ry @ specific + np.array([0.03, 0.02, -0.02]) + np.array([0.05 * keyed_randn(seed, k, ch + 1, 1) for ch in range(3)])
        gyro = np.array([0.0, rate[k], y[k, 10]]) + np.array([0.0, 0.00035, 0.0]) + np.array([0.002 * keyed_randn(seed, k, ch + 4, 1) for ch in range(3)])
        current = np.r_[accel, gyro]
        if k: current[:3] = aa * previous[k - 1, :3] + (1 - aa) * current[:3]; current[3:] = gg * previous[k - 1, 3:] + (1 - gg) * current[3:]
        raw[k] = current; previous[k] = current
    return raw


def tcn_prediction(split: str, seed: int, run_id: int) -> dict[str, np.ndarray]:
    path = NODE43 / "02_continuous_replay_cache/predictions" / split / f"seed{seed}" / f"run_{run_id:03d}.npz"
    if not path.is_file():
        raise FileNotFoundError(path)
    with np.load(path, allow_pickle=False) as z:
        return {k: z[k] for k in z.files}


def ecdf(values: np.ndarray) -> dict[str, list[float]]:
    values = np.asarray(values, float); values = values[np.isfinite(values)]
    if values.size == 0: values = np.array([0.0, 1.0])
    q = np.linspace(0, 1, 257); x = np.maximum.accumulate(np.quantile(values, q)); x[0] = min(x[0], 0.0); x[-1] = max(x[-1], x[0] + np.finfo(float).eps)
    return {"values": x.tolist(), "probabilities": q.tolist()}


def replay_one(split: str, run_id: int, seed: int = 1) -> Path:
    out = NODE / f"03_offline_replay/{split}/run_{run_id:03d}.npz"
    out.parent.mkdir(parents=True, exist_ok=True)
    raw = raw_run(run_id); packet = sensor_stream(raw); fuzzy = fuzzy_replay(packet, json.loads((NODE / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json").read_text(encoding="utf-8"))); tcn = tcn_prediction(split, seed, run_id); n = min(len(raw["truth"]), len(tcn["theta_tcn"]), len(packet))
    np.savez_compressed(out, run_id=run_id, time=raw["time"][:n], truth=raw["truth"][:n], packet=packet[:n], theta_tcn=tcn["theta_tcn"][:n], conf_main=tcn["conf_main"][:n], ready=tcn.get("ready", np.arange(n) >= 128)[:n], label_main=tcn.get("label_main", np.zeros(n))[:n], label_turn=tcn.get("label_turn", np.zeros(n))[:n], **{k: v[:n] for k, v in fuzzy.items()})
    return out


def keys(splits: tuple[str, ...] = ("train", "validation")) -> list[tuple[str, int]]:
    ids = split_ids(); return [(s, i) for s in splits for i in ids[s]]


def load_case(split: str, run_id: int, seed: int = 1) -> dict[str, np.ndarray]:
    path = NODE / f"03_offline_replay/{split}/run_{run_id:03d}.npz"
    with np.load(path, allow_pickle=False) as z: case = {k: z[k] for k in z.files}
    prediction = tcn_prediction(split, seed, run_id); n = min(len(case["truth"]), len(prediction["theta_tcn"])); case = {k: (v[:n] if np.ndim(v) else v) for k, v in case.items()}
    for name in ("theta_tcn", "conf_main", "ready", "label_main", "label_turn"):
        if name in prediction: case[name] = prediction[name][:n]
    return case


def fold_index(key: tuple[str, int]) -> int:
    return int.from_bytes(hashlib.sha256(f"{key[0]}:{key[1]}".encode("ascii")).digest()[:8], "big") % 3


def build_quality_model(items: list[tuple[str, int]]) -> dict[str, Any]:
    pools = {k: [] for k in ("one_minus_accel_weight", "accel_norm_deviation", "abs_innovation", "nis", "gyro_vibration_feature")}
    for split, run_id in items:
        c = load_case(split, run_id); pools["one_minus_accel_weight"].append(1 - c["accel_weight"]); pools["accel_norm_deviation"].append(abs(c["accel_norm"] - G)); pools["abs_innovation"].append(abs(c["innovation"])); pools["nis"].append(c["nis"]); pools["gyro_vibration_feature"].append(c["gyro_vibration_feature"])
    return {k: ecdf(np.concatenate(v)) for k, v in pools.items()}


def quality_score(c: dict[str, np.ndarray], model: dict[str, Any]) -> np.ndarray:
    vals = [1 - c["accel_weight"], abs(c["accel_norm"] - G), abs(c["innovation"]), c["nis"], c["gyro_vibration_feature"]]
    parts = [np.interp(v, model[k]["values"], model[k]["probabilities"], left=0, right=1) for v, k in zip(vals, model)]
    return np.clip(np.max(np.vstack(parts), axis=0), 0, 1)


def build_tables(items: list[tuple[str, int]], model: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    cells = [[[] for _ in range(3)] for _ in range(4)]; counts = np.zeros((4, 3), int)
    for split, run_id in items:
        for seed in SEEDS:
            c = load_case(split, run_id, seed); theta = c["theta_tcn"]; rate = np.diff(theta, prepend=theta[0]) / TS; regime = (abs(theta) >= np.deg2rad(1.3)).astype(int) + 2 * (abs(rate) >= np.deg2rad(1.0)).astype(int); q = quality_score(c, model); qbin = np.digitize(q, [0.5, 0.8]); mask = c["ready"].astype(bool) & c["observer_valid"].astype(bool) & np.isfinite(c["truth"])
            for rr in range(4):
                for qq in range(3):
                    use = mask & (regime == rr) & (qbin == qq)
                    if np.any(use):
                        a = theta[use] - c["truth"][use]; b = c["theta_imu"][use] - c["truth"][use]; cells[rr][qq].append((float(np.mean(a * a)), float(np.mean(b * b)), float(np.mean(a * b)), float(np.mean((a - np.mean(a)) * (b - np.mean(b)))), int(use.sum())))
    p_t = np.zeros((4, 3)); p_f = np.zeros((4, 3)); cross = np.zeros((4, 3)); cov = np.zeros((4, 3))
    for rr in range(4):
        for qq in range(3):
            v = np.asarray(cells[rr][qq] or [(0, 0, 0, 0, 0)], float); p_t[rr, qq] = max(FLOOR, np.mean(v[:, 0])); p_f[rr, qq] = max(FLOOR, np.mean(v[:, 1])); cross[rr, qq] = np.mean(v[:, 2]); cov[rr, qq] = np.mean(v[:, 3]); counts[rr, qq] = int(np.sum(v[:, 4]))
    p_f = np.maximum.accumulate(p_f, axis=1); bound = 0.95 * np.sqrt(p_t * p_f); cross = np.clip(cross, -bound, bound); cov = np.clip(cov, -bound, bound)
    tables = {"P_tcn_total": p_t.tolist(), "P_fuzzyakf_total": p_f.tolist(), "cross_error_total": cross.tolist(), "cross_covariance": cov.tolist()}
    audit = {"cell_sample_counts": counts.tolist(), "psd": bool(np.all(p_t * p_f - cross * cross >= -1e-15)), "variance_floor": FLOOR, "table_shape": [4, 3], "source": "Node53 train+validation FuzzyAKF replay"}
    return tables, audit


def fusion_metrics(c: dict[str, np.ndarray], tables: dict[str, Any], kmax: float, model: dict[str, Any]) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    theta = c["theta_tcn"]; truth = c["truth"]; rate = np.diff(theta, prepend=theta[0]) / TS; regime = (abs(theta) >= np.deg2rad(1.3)).astype(int) + 2 * (abs(rate) >= np.deg2rad(1.0)).astype(int); q = quality_score(c, model); qb = np.digitize(q, [0.5, 0.8]); correction = 0.0; fused = theta.copy(); raw = []; eff = []; cap = []; fallback = np.zeros(len(theta), bool)
    for i in range(len(theta)):
        rr, qq = int(regime[i]), int(qb[i]); pt = max(float(tables["P_tcn_total"][rr][qq]), FLOOR) * (2 - float(np.clip(c["conf_main"][i], 0, 1))); pf = max(float(tables["P_fuzzyakf_total"][rr][qq]), FLOOR); cross = float(np.clip(tables["cross_error_total"][rr][qq], -0.95 * math.sqrt(pt * pf), 0.95 * math.sqrt(pt * pf))); innovation = c["theta_imu"][i] - theta[i]; s = max(pt + pf - 2 * cross, FLOOR); nis = innovation * innovation / s; kraw = (pt - cross) / s; bad = (not bool(c["ready"][i])) or (not bool(c["observer_valid"][i])) or abs(innovation) > np.deg2rad(2) or nis > 25; fallback[i] = bad
        if bad: correction = 0.0; continue
        nw = 1.0 if nis <= 9 else math.sqrt(9 / nis); qw = np.clip(0.5 - 0.3 * q[i], 0.1, 1); ke = min(kmax, max(0, kraw)) * qw * nw; target = np.clip(ke * innovation, -np.deg2rad(0.5), np.deg2rad(0.5)); correction += np.clip(target - correction, -np.deg2rad(5) * TS, np.deg2rad(5) * TS); fused[i] = theta[i] + correction; raw.append(kraw); eff.append(ke); cap.append(kraw > kmax)
    base_err = np.abs(theta - truth); fused_err = np.abs(fused - truth); active = np.abs(fused - theta) >= np.deg2rad(0.05); improve = active & (fused_err < base_err - np.deg2rad(0.10)); degrade = active & (fused_err > base_err + np.deg2rad(0.10)); metrics = {"baseline_mae_deg": float(np.rad2deg(np.mean(base_err))), "fused_mae_deg": float(np.rad2deg(np.mean(fused_err))), "mae_ratio": float(np.mean(fused_err) / max(np.mean(base_err), 1e-15)), "sample_count": int(len(theta)), "active_count": int(np.sum(active)), "improve_count": int(np.sum(improve)), "degrade_count": int(np.sum(degrade)), "fallback_count": int(np.sum(fallback)), "active_fraction": float(np.mean(active)), "active_improve_fraction": float(np.sum(improve) / max(np.sum(active), 1)), "active_degrade_fraction": float(np.sum(degrade) / max(np.sum(active), 1))}
    return metrics, {"fused": fused, "K_raw": np.asarray(raw), "K_eff": np.asarray(eff), "cap": np.asarray(cap, bool), "fallback": fallback}


def replay_stage() -> int:
    rows = []
    for split, run_id in keys(("train", "validation")):
        path = replay_one(split, run_id); rows.append({"split": split, "run_id": run_id, "path": str(path), "sha256": sha256(path)})
    write_csv(NODE / "03_offline_replay/replay_manifest.csv", rows); write_json(NODE / "03_offline_replay/replay_status.json", {"status": "PASS_NODE53_TRAIN_VALIDATION_REPLAY", "counts": {"train": 71, "validation": 15}, "test_read": False, "old_rkf_uncertainty_reused": False})
    return 0


def calibrate_stage() -> int:
    items = keys(); specs = [{"candidate_id": f"C{i}", "Kmax": k, "quality_intercept": 0.5, "quality_slope": 0.3, "quality_floor": 0.1} for i, k in enumerate((0.3, 0.4, 0.5), 1)]; pooled = {s["candidate_id"]: {"metrics": [], "diag": [], "fold_ratios": []} for s in specs}; fold_rows = []
    def summarize(spec: dict[str, Any], metrics: list[dict[str, Any]], diagnostics: list[dict[str, np.ndarray]], fold_ratios: list[float]) -> dict[str, Any]:
        # Aggregate moments and gate counts by sample, matching the Node51 contract.
        total = max(sum(int(x.get("sample_count", 0)) for x in metrics), 1)
        active_count = sum(int(x.get("active_count", 0)) for x in metrics)
        improve_count = sum(int(x.get("improve_count", 0)) for x in metrics)
        degrade_count = sum(int(x.get("degrade_count", 0)) for x in metrics)
        base = sum(float(x["baseline_mae_deg"]) * int(x.get("sample_count", 0)) for x in metrics) / total
        fused = sum(float(x["fused_mae_deg"]) * int(x.get("sample_count", 0)) for x in metrics) / total
        raw = np.concatenate([x["K_raw"] for x in diagnostics if x["K_raw"].size]); eff = np.concatenate([x["K_eff"] for x in diagnostics if x["K_eff"].size]); cap = np.concatenate([x["cap"] for x in diagnostics if x["cap"].size])
        active_fraction = active_count / total; improve_fraction = improve_count / max(active_count, 1); degrade_fraction = degrade_count / max(active_count, 1)
        gates = {"mae_ratio": fused / max(base, 1e-15) <= 0.95, "active_fraction": active_fraction >= 0.10, "active_improve_fraction": improve_fraction >= 0.60, "active_degrade_fraction": degrade_fraction <= 0.05, "K_raw_p95_p05": (np.percentile(raw, 95) - np.percentile(raw, 5)) >= 0.02 if raw.size else False, "K_eff_p95_p05": (np.percentile(eff, 95) - np.percentile(eff, 5)) >= 0.02 if eff.size else False, "cap_fraction": np.mean(cap) < 0.95 if cap.size else False, "below_cap_fraction": np.mean(eff <= spec["Kmax"] - 0.01) >= 0.05 if eff.size else False, "cv_fold_mae_ratio": (not fold_ratios or max(fold_ratios) <= 1.0)}
        row = {**spec, "baseline_mae_deg": float(base), "fused_mae_deg": float(fused), "mae_ratio": float(fused / max(base, 1e-15)), "sample_count": int(total), "active_count": int(active_count), "improve_count": int(improve_count), "degrade_count": int(degrade_count), "active_fraction": float(active_fraction), "active_improve_fraction": float(improve_fraction), "active_degrade_fraction": float(degrade_fraction), "K_raw_p95_p05": float(np.percentile(raw, 95) - np.percentile(raw, 5)) if raw.size else 0, "K_eff_p95_p05": float(np.percentile(eff, 95) - np.percentile(eff, 5)) if eff.size else 0, "cap_fraction": float(np.mean(cap)) if cap.size else 1, "below_cap_fraction": float(np.mean(eff <= spec["Kmax"] - 0.01)) if eff.size else 0, "fold_mae_ratios": fold_ratios, "failed_gates": [k for k, v in gates.items() if not v]}; row["qualified"] = not row["failed_gates"]; return row
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]; held = [x for x in items if fold_index(x) == fold]; fold_model = build_quality_model(fit); fold_tables, _ = build_tables(fit, fold_model)
        for spec in specs:
            metrics = []; diagnostics = []
            for split, rid in held:
                for seed in SEEDS:
                    m, d = fusion_metrics(load_case(split, rid, seed), fold_tables, spec["Kmax"], fold_model); metrics.append(m); diagnostics.append(d)
            summary = summarize(spec, metrics, diagnostics, []); pooled[spec["candidate_id"]]["metrics"].extend(metrics); pooled[spec["candidate_id"]]["diag"].extend(diagnostics); pooled[spec["candidate_id"]]["fold_ratios"].append(summary["mae_ratio"]); fold_rows.append({"fold": fold, "fit_runs": len(fit), "held_runs": len(held), **summary})
    rows = [summarize(spec, pooled[spec["candidate_id"]]["metrics"], pooled[spec["candidate_id"]]["diag"], pooled[spec["candidate_id"]]["fold_ratios"]) for spec in specs]
    model = build_quality_model(items); tables, table_audit = build_tables(items, model)
    qualified = [x for x in rows if x["qualified"]]; selected = sorted(qualified, key=lambda x: (x["mae_ratio"], x["active_degrade_fraction"], x["candidate_id"]))[0] if qualified else None; report = {"status": "PASS_NODE53_GROUPED_CV_SELECTION" if selected else "STOP_NODE53_NO_QUALIFIED_FUSION", "candidate_count": 3, "selected": selected, "quality_model": model, "tables": tables, "table_audit": table_audit, "truth_use": {"train": True, "validation": True, "test": False, "formal": False}}
    write_csv(NODE / "04_fusion_calibration/fusion_candidate_table.csv", rows); write_csv(NODE / "04_fusion_calibration/cv_fold_metrics.csv", fold_rows); write_csv(NODE / "fusion_candidate_table.csv", rows); write_json(NODE / "fusion_covariance_tables.json", {"tables": tables, "audit": table_audit, "quality_model": model}); write_json(NODE / "04_fusion_calibration/selection_decision.json", report); write_json(NODE / "selection_decision.json", report)
    if selected: write_json(NODE / "selected_fusion_config.json", {"status": "FROZEN_NODE53_DEVELOPMENT_SELECTION", "selected": selected, "tables": tables, "quality_model": model, "test_read": False}); return 0
    write_json(NODE / "STOP_NODE53_NO_QUALIFIED_FUSION.json", report); return 2


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("stage", choices=("replay", "calibrate")); args = parser.parse_args(); return replay_stage() if args.stage == "replay" else calibrate_stage()


if __name__ == "__main__":
    raise SystemExit(main())
