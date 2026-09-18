from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from node53_common import NODE, sha256, write_csv, write_json
from node53_offline import SEEDS, build_quality_model, build_tables, fold_index, fusion_metrics, keys, load_case

OUT = NODE / "04_fusion_calibration/iterations/02_expanded_kmax"
KMAX = (0.6, 0.7, 0.8, 0.9)


def summarize(spec: dict[str, Any], metrics: list[dict[str, Any]], diagnostics: list[dict[str, np.ndarray]], folds: list[float]) -> dict[str, Any]:
    total = max(sum(int(x["sample_count"]) for x in metrics), 1)
    active = sum(int(x["active_count"]) for x in metrics)
    improve = sum(int(x["improve_count"]) for x in metrics)
    degrade = sum(int(x["degrade_count"]) for x in metrics)
    base = sum(float(x["baseline_mae_deg"]) * int(x["sample_count"]) for x in metrics) / total
    fused = sum(float(x["fused_mae_deg"]) * int(x["sample_count"]) for x in metrics) / total
    raw = np.concatenate([x["K_raw"] for x in diagnostics if x["K_raw"].size])
    eff = np.concatenate([x["K_eff"] for x in diagnostics if x["K_eff"].size])
    cap = np.concatenate([x["cap"] for x in diagnostics if x["cap"].size])
    row = {
        **spec,
        "baseline_mae_deg": float(base),
        "fused_mae_deg": float(fused),
        "mae_ratio": float(fused / max(base, 1e-15)),
        "sample_count": total,
        "active_count": active,
        "improve_count": improve,
        "degrade_count": degrade,
        "active_fraction": active / total,
        "active_improve_fraction": improve / max(active, 1),
        "active_degrade_fraction": degrade / max(active, 1),
        "K_raw_p95_p05": float(np.percentile(raw, 95) - np.percentile(raw, 5)) if raw.size else 0.0,
        "K_eff_p95_p05": float(np.percentile(eff, 95) - np.percentile(eff, 5)) if eff.size else 0.0,
        "cap_fraction": float(np.mean(cap)) if cap.size else 1.0,
        "below_cap_fraction": float(np.mean(eff <= spec["Kmax"] - 0.01)) if eff.size else 0.0,
        "fold_mae_ratios": folds,
    }
    gates = {
        "mae_ratio": row["mae_ratio"] <= 0.95,
        "active_fraction": row["active_fraction"] >= 0.10,
        "active_improve_fraction": row["active_improve_fraction"] >= 0.60,
        "active_degrade_fraction": row["active_degrade_fraction"] <= 0.05,
        "K_raw_p95_p05": row["K_raw_p95_p05"] >= 0.02,
        "K_eff_p95_p05": row["K_eff_p95_p05"] >= 0.02,
        "cap_fraction": row["cap_fraction"] < 0.95,
        "below_cap_fraction": row["below_cap_fraction"] >= 0.05,
        "cv_fold_mae_ratio": not folds or max(folds) <= 1.0,
    }
    row["failed_gates"] = [name for name, passed in gates.items() if not passed]
    row["qualified"] = not row["failed_gates"]
    return row


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    items = keys()
    specs = [{"candidate_id": f"C{i + 4}", "Kmax": k, "quality_intercept": 0.5, "quality_slope": 0.3, "quality_floor": 0.1} for i, k in enumerate(KMAX)]
    pooled = {s["candidate_id"]: {"metrics": [], "diagnostics": [], "folds": []} for s in specs}
    fold_rows: list[dict[str, Any]] = []
    for fold in range(3):
        fit = [x for x in items if fold_index(x) != fold]
        held = [x for x in items if fold_index(x) == fold]
        model = build_quality_model(fit)
        tables, _ = build_tables(fit, model)
        local = {s["candidate_id"]: {"metrics": [], "diagnostics": []} for s in specs}
        for split, run_id in held:
            for seed in SEEDS:
                case = load_case(split, run_id, seed)
                for spec in specs:
                    metric, diag = fusion_metrics(case, tables, spec["Kmax"], model)
                    local[spec["candidate_id"]]["metrics"].append(metric)
                    local[spec["candidate_id"]]["diagnostics"].append(diag)
        for spec in specs:
            item = local[spec["candidate_id"]]
            summary = summarize(spec, item["metrics"], item["diagnostics"], [])
            pooled[spec["candidate_id"]]["metrics"].extend(item["metrics"])
            pooled[spec["candidate_id"]]["diagnostics"].extend(item["diagnostics"])
            pooled[spec["candidate_id"]]["folds"].append(summary["mae_ratio"])
            fold_rows.append({"fold": fold, "fit_runs": len(fit), "held_runs": len(held), **summary})
    rows = [summarize(s, pooled[s["candidate_id"]]["metrics"], pooled[s["candidate_id"]]["diagnostics"], pooled[s["candidate_id"]]["folds"]) for s in specs]
    qualified = [r for r in rows if r["qualified"]]
    selected = sorted(qualified, key=lambda r: (r["mae_ratio"], r["active_degrade_fraction"], r["candidate_id"]))[0] if qualified else None
    tables_report = json.loads((NODE / "fusion_covariance_tables.json").read_text(encoding="utf-8"))
    amendment = OUT / "protocol_amendment.json"
    report = {
        "status": "PASS_NODE53_STAGE4_V2_SELECTION" if selected else "STOP_NODE53_STAGE4_V2_NO_QUALIFIED_FUSION",
        "candidate_count": len(rows),
        "candidate_scope": "expanded Kmax 0.6-0.9",
        "selected": selected,
        "candidates": rows,
        "fold_count": 3,
        "development_run_count": len(items),
        "quality_model_source": "Node53 v1 frozen train+validation ECDF; unchanged",
        "tables_source": "Node53 v1 frozen train+validation covariance tables; unchanged",
        "test_read": False,
        "formal_read": False,
        "previous_stage4_selection_sha256": sha256(NODE / "selection_decision.json"),
        "amendment_sha256": sha256(amendment),
    }
    write_csv(OUT / "fusion_candidate_table.csv", rows)
    write_csv(OUT / "cv_fold_metrics.csv", fold_rows)
    write_json(OUT / "selection_decision.json", report)
    if selected:
        write_json(OUT / "selected_fusion_config.json", {"status": "FROZEN_NODE53_STAGE4_V2_SELECTION", "selected": selected, "tables": tables_report["tables"], "quality_model": tables_report["quality_model"], "test_read": False, "formal_read": False})
    else:
        write_json(OUT / "STOP_NODE53_STAGE4_V2_NO_QUALIFIED_FUSION.json", report)
    print(json.dumps({"status": report["status"], "selected": selected, "rows": rows}, indent=2))
    return 0 if selected else 2


if __name__ == "__main__":
    raise SystemExit(main())
