from __future__ import annotations

import json
from typing import Any

import numpy as np

from node53_common import NODE, write_json
from node53_offline import FLOOR, G, SEEDS, TS, keys, load_case

OUT = NODE / "04_fusion_calibration/iterations/03_failure_diagnostics"
FEATURES = ("one_minus_accel_weight", "accel_norm_deviation", "abs_innovation", "nis", "gyro_vibration_feature")


def empty() -> dict[str, float]:
    return {"count": 0, "direction_helpful": 0, "proxy_active": 0, "proxy_improve": 0, "proxy_degrade": 0, "base_abs_sum": 0.0, "proxy_abs_sum": 0.0}


def add(store: list[dict[str, float]], index: np.ndarray, valid: np.ndarray, helpful: np.ndarray, active: np.ndarray, improve: np.ndarray, degrade: np.ndarray, base: np.ndarray, proxy: np.ndarray) -> None:
    for i, row in enumerate(store):
        use = valid & (index == i)
        row["count"] += int(np.sum(use)); row["direction_helpful"] += int(np.sum(use & helpful)); row["proxy_active"] += int(np.sum(use & active)); row["proxy_improve"] += int(np.sum(use & improve)); row["proxy_degrade"] += int(np.sum(use & degrade)); row["base_abs_sum"] += float(np.sum(base[use])); row["proxy_abs_sum"] += float(np.sum(proxy[use]))


def finish(rows: list[dict[str, float]], labels: list[str]) -> list[dict[str, Any]]:
    out = []
    for label, row in zip(labels, rows):
        count = max(int(row["count"]), 1); active = max(int(row["proxy_active"]), 1)
        out.append({"bin": label, **{k: int(v) for k, v in row.items() if k not in ("base_abs_sum", "proxy_abs_sum")}, "direction_helpful_fraction": row["direction_helpful"] / count, "proxy_active_fraction": row["proxy_active"] / count, "proxy_improve_fraction_of_active": row["proxy_improve"] / active, "proxy_degrade_fraction_of_active": row["proxy_degrade"] / active, "proxy_mae_ratio": row["proxy_abs_sum"] / max(row["base_abs_sum"], 1e-15)})
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    frozen = json.loads((NODE / "fusion_covariance_tables.json").read_text(encoding="utf-8")); tables = frozen["tables"]; model = frozen["quality_model"]
    q_edges = np.linspace(0.0, 1.0, 11); innovation_edges = np.array([0.0, 0.1, 0.25, 0.5, 1.0, 2.0, np.inf]); fusion_nis_edges = np.array([0.0, 1.0, 4.0, 9.0, 25.0, np.inf])
    stores = {"quality_decile": [empty() for _ in range(10)], "quality_bin": [empty() for _ in range(3)], "regime": [empty() for _ in range(4)], "innovation_deg": [empty() for _ in range(6)], "fusion_nis": [empty() for _ in range(5)], "dominant_feature": [empty() for _ in range(5)], "quality_bin_x_innovation": [[empty() for _ in range(6)] for _ in range(3)], "quality_bin_x_feature": [[empty() for _ in range(5)] for _ in range(3)]}
    totals = empty(); oracle_active = 0; oracle_abs_sum = 0.0; q_ge_08 = 0; eligible_count = 0
    for split, run_id in keys():
        for seed in SEEDS:
            c = load_case(split, run_id, seed); theta = np.asarray(c["theta_tcn"], float); truth = np.asarray(c["truth"], float); observer = np.asarray(c["theta_imu"], float); innovation = observer - theta; rate = np.diff(theta, prepend=theta[0]) / TS; regime = (np.abs(theta) >= np.deg2rad(1.3)).astype(int) + 2 * (np.abs(rate) >= np.deg2rad(1.0)).astype(int)
            raw_features = [1 - c["accel_weight"], np.abs(c["accel_norm"] - G), np.abs(c["innovation"]), c["nis"], c["gyro_vibration_feature"]]
            parts = np.vstack([np.interp(v, model[name]["values"], model[name]["probabilities"], left=0, right=1) for v, name in zip(raw_features, FEATURES)]); q = np.clip(np.max(parts, axis=0), 0, 1); dominant = np.argmax(parts, axis=0); qbin = np.digitize(q, [0.5, 0.8])
            pt_base = np.asarray(tables["P_tcn_total"], float)[regime, qbin]; pf = np.asarray(tables["P_fuzzyakf_total"], float)[regime, qbin]; cross_base = np.asarray(tables["cross_error_total"], float)[regime, qbin]; inflation = 2 - np.clip(c["conf_main"], 0, 1); pt = np.maximum(pt_base, FLOOR) * inflation; cross = np.clip(cross_base * np.sqrt(inflation), -0.95 * np.sqrt(pt * pf), 0.95 * np.sqrt(pt * pf)); s = np.maximum(pt + pf - 2 * cross, FLOOR); fusion_nis = innovation * innovation / s; kraw = (pt - cross) / s
            eligible = c["ready"].astype(bool) & c["observer_valid"].astype(bool) & np.isfinite(truth) & (np.abs(innovation) <= np.deg2rad(2)) & (fusion_nis <= 25)
            nw = np.ones_like(fusion_nis); high = fusion_nis > 9; nw[high] = np.sqrt(9 / fusion_nis[high]); qw = np.clip(0.5 - 0.3 * q, 0.1, 1); keff = np.minimum(0.9, np.maximum(0, kraw)) * qw * nw; correction = np.clip(keff * innovation, -np.deg2rad(0.5), np.deg2rad(0.5)); correction[~eligible] = 0
            base = np.abs(theta - truth); proxy = np.abs(theta + correction - truth); active = np.abs(correction) >= np.deg2rad(0.05); improve = active & (proxy < base - np.deg2rad(0.10)); degrade = active & (proxy > base + np.deg2rad(0.10)); helpful = innovation * (truth - theta) > 0
            total_index = np.zeros(len(theta), int); add([totals], total_index, np.isfinite(base), helpful, active, improve, degrade, base, proxy)
            add(stores["quality_decile"], np.clip(np.digitize(q, q_edges[1:-1]), 0, 9), eligible, helpful, active, improve, degrade, base, proxy); add(stores["quality_bin"], qbin, eligible, helpful, active, improve, degrade, base, proxy); add(stores["regime"], regime, eligible, helpful, active, improve, degrade, base, proxy); add(stores["innovation_deg"], np.clip(np.digitize(np.rad2deg(np.abs(innovation)), innovation_edges[1:-1]), 0, 5), eligible, helpful, active, improve, degrade, base, proxy); add(stores["fusion_nis"], np.clip(np.digitize(fusion_nis, fusion_nis_edges[1:-1]), 0, 4), eligible, helpful, active, improve, degrade, base, proxy); add(stores["dominant_feature"], dominant, eligible, helpful, active, improve, degrade, base, proxy)
            qidx = np.clip(qbin, 0, 2); iidx = np.clip(np.digitize(np.rad2deg(np.abs(innovation)), innovation_edges[1:-1]), 0, 5)
            for qi in range(3):
                for ii in range(6): add([stores["quality_bin_x_innovation"][qi][ii]], np.zeros(len(theta), int), eligible & (qidx == qi) & (iidx == ii), helpful, active, improve, degrade, base, proxy)
                for fi in range(5): add([stores["quality_bin_x_feature"][qi][fi]], np.zeros(len(theta), int), eligible & (qidx == qi) & (dominant == fi), helpful, active, improve, degrade, base, proxy)
            oracle = eligible & improve; oracle_active += int(np.sum(oracle)); oracle_abs_sum += float(np.sum(np.where(oracle, proxy, base))); q_ge_08 += int(np.sum(q >= 0.8)); eligible_count += int(np.sum(eligible))
    total_count = int(totals["count"]); total_active = max(int(totals["proxy_active"]), 1)
    qxi = [{"quality_bin": qi, "innovation_bins": finish(stores["quality_bin_x_innovation"][qi], ["<0.1", "0.1-0.25", "0.25-0.5", "0.5-1.0", "1.0-2.0", ">=2.0"])} for qi in range(3)]
    qxf = [{"quality_bin": qi, "dominant_features": finish(stores["quality_bin_x_feature"][qi], list(FEATURES))} for qi in range(3)]
    report = {"status": "PASS_NODE53_DEVELOPMENT_FAILURE_DIAGNOSTICS", "scope": "train+validation only", "test_read": False, "formal_read": False, "sample_count": total_count, "eligible_count": eligible_count, "quality_ge_0p8_fraction": q_ge_08 / max(total_count, 1), "samplewise_proxy_C7": {"active_fraction": totals["proxy_active"] / max(total_count, 1), "improve_fraction_of_active": totals["proxy_improve"] / total_active, "degrade_fraction_of_active": totals["proxy_degrade"] / total_active, "mae_ratio": totals["proxy_abs_sum"] / max(totals["base_abs_sum"], 1e-15)}, "truth_oracle_upper_bound": {"active_fraction": oracle_active / max(total_count, 1), "mae_ratio": oracle_abs_sum / max(totals["base_abs_sum"], 1e-15), "note": "samplewise upper bound without correction persistence/rate dynamics"}, "bins": {"quality_decile": finish(stores["quality_decile"], [f"[{i/10:.1f},{(i+1)/10:.1f})" for i in range(10)]), "quality_bin": finish(stores["quality_bin"], ["<0.5", "0.5-0.8", ">=0.8"]), "regime": finish(stores["regime"], ["flat_slow", "slope_slow", "flat_transition", "slope_transition"]), "innovation_deg": finish(stores["innovation_deg"], ["<0.1", "0.1-0.25", "0.25-0.5", "0.5-1.0", "1.0-2.0", ">=2.0"]), "fusion_nis": finish(stores["fusion_nis"], ["<1", "1-4", "4-9", "9-25", ">=25"]), "dominant_feature": finish(stores["dominant_feature"], list(FEATURES)), "quality_bin_x_innovation": qxi, "quality_bin_x_feature": qxf}}
    write_json(OUT / "failure_diagnostics.json", report); print(json.dumps(report, indent=2)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
