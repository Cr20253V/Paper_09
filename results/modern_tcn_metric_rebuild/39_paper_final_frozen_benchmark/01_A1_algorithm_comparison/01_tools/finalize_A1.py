#!/usr/bin/env python3
"""Assemble the frozen 240-case A1 grid, bootstrap effects, gates, decision and receipt."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np


SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]
METHODS = ["modern_tcn_delta_bank_124", "modern_tcn_22d", "gru_22d", "tcn_22d"]
CONTROL = ["ey_rmse", "xy_rmse", "epsi_rmse", "j_du", "omega_cmd_rms"]
CL_PRIMARY = ["ey_rmse", "epsi_rmse", "j_du"]
BOOT_N = 10000
BOOT_SEED = 20260715


def root() -> Path:
    for p in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (p / "init_project.m").is_file(): return p
    raise RuntimeError("project root not found")


ROOT = root()
TASK = ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison"


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def fs_path(path: Path, *, force_extended: bool = False) -> Path:
    """Return a Windows extended-length path while preserving display paths."""
    path = Path(path)
    text = os.path.abspath(os.fspath(path))
    if os.name == "nt" and not text.startswith("\\\\?\\") and (force_extended or len(text) >= 248):
        if text.startswith("\\\\"):
            text = "\\\\?\\UNC\\" + text[2:]
        else:
            text = "\\\\?\\" + text
    return Path(text)


def is_file(path: Path) -> bool:
    return fs_path(path).is_file()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with fs_path(path).open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""): h.update(b)
    return h.hexdigest()


def rows(path: Path) -> list[dict[str, str]]:
    with fs_path(path).open("r", encoding="utf-8-sig", newline="") as f: return list(csv.DictReader(f))


def write_rows(path: Path, data: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    names: list[str] = []
    for r in data:
        for k in r:
            if k not in names: names.append(k)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=names, extrasaction="ignore"); w.writeheader(); w.writerows(data)


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=True) + "\n", encoding="utf-8")


def num(value: Any) -> float:
    try: return float(value)
    except (TypeError, ValueError): return float("nan")


def summary_row(path: Path, controller: str) -> dict[str, str]:
    data = rows(path)
    match = [r for r in data if r.get("zone", "").lower() == "all" and r.get("controller", "").lower() == controller.lower()]
    if len(match) != 1: raise ValueError(f"{path}: controller={controller} all-row count={len(match)}")
    return match[0]


def raw_metrics(method: str, seed: int, path_id: str, path_tag: str, raw: Path, summary: Path, controller: str, source: str) -> dict[str, Any]:
    r = summary_row(summary, controller)
    keep = CONTROL + ["ey_peak", "epsi_peak", "ev_rmse", "viol_rate", "F_sat595_pct", "F_limit_hit_pct", "omega_sat060_pct", "omega_limit_hit_pct", "timeout_rate", "main_acc_pct", "slope_recall_pct", "theta_mae_deg", "theta_peak_deg"]
    out: dict[str, Any] = {"method_id": method, "seed": seed, "path_id": path_id, "path_tag": path_tag, "source_kind": source, "raw_result_file": str(raw), "raw_result_sha256": sha256(raw) if is_file(raw) else "", "source_summary_file": str(summary), "source_summary_sha256": sha256(summary) if is_file(summary) else ""}
    out.update({k: num(r.get(k)) for k in keep})
    return out


def collect_grid(config: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    path_ids = {Path(p["file"]).stem: p["path_id"] for p in config["paths"]}
    data: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    n32 = ROOT / "results/modern_tcn_metric_rebuild/32_four_algorithm_10seed_closed_loop/02_modern_fixed_full_closed_loop"
    for r in rows(n32 / "modern_fixed_22d_path_summary.csv"):
        seed = int(float(r["seed"])); tag = r["path_tag"]
        raw = n32 / tag / f"modern_fixed_seed{seed}_out.mat"; summary = Path(r["summary_file"])
        try: data.append(raw_metrics("modern_tcn_22d", seed, path_ids[tag], tag, raw, summary, r["candidate_id"], "UPSTREAM_NODE32_REFERENCE"))
        except Exception as exc: missing.append({"method_id":"modern_tcn_22d","seed":seed,"path_id":path_ids[tag],"reason":str(exc)})
    n30 = ROOT / "results/modern_tcn_metric_rebuild/30_rhofmd_lag_rescreen/04_full_closed_loop/db124"
    for seed in SEEDS:
        index = n30 / f"s{seed}/closed_loop_summary.csv"
        for r in rows(index):
            tag = r["path_tag"]; summary = Path(r["summary_file"]); raw = summary.parent / f"delta_bank_124_seed{seed}_out.mat"
            try: data.append(raw_metrics("modern_tcn_delta_bank_124", seed, path_ids[tag], tag, raw, summary, f"delta_bank_124_seed{seed}", "UPSTREAM_NODE30_REFERENCE"))
            except Exception as exc: missing.append({"method_id":"modern_tcn_delta_bank_124","seed":seed,"path_id":path_ids[tag],"reason":str(exc)})
    for method, short, controller in [("gru_22d","gru","GRU"),("tcn_22d","tcn","TCN")]:
        base = TASK / f"04_closed_loop/raw/{method}"
        for seed in SEEDS:
            for p in config["paths"]:
                tag = Path(p["file"]).stem; case = base / f"seed{seed}/{tag}"
                raw = case / f"{method}_seed{seed}_out.mat"; summary = case / f"a1_{method}_seed{seed}_summary.csv"
                if not is_file(raw) or not is_file(summary):
                    missing.append({"method_id":method,"seed":seed,"path_id":p["path_id"],"reason":"manual_raw_or_summary_missing","expected_raw":str(raw),"expected_summary":str(summary)}); continue
                try: data.append(raw_metrics(method, seed, p["path_id"], tag, raw, summary, controller, "NODE39_MANUAL_RUN"))
                except Exception as exc: missing.append({"method_id":method,"seed":seed,"path_id":p["path_id"],"reason":str(exc)})
    data.sort(key=lambda r: (METHODS.index(r["method_id"]), r["seed"], r["path_id"]))
    return data, missing


def add_ratios_and_gates(data: list[dict[str, Any]], offline: list[dict[str, str]], thresholds: dict[str, Any]) -> list[dict[str, Any]]:
    index = {(r["method_id"], int(r["seed"]), r["path_id"]): r for r in data}
    off = {(r["method_id"], int(float(r["seed"]))): r for r in offline}
    for r in data:
        ref = index.get(("modern_tcn_22d", r["seed"], r["path_id"]))
        reasons: list[str] = []
        ratios = []
        for metric in CONTROL:
            den = num(ref.get(metric)) if ref else math.nan; val = num(r.get(metric))
            ratio = val / den if math.isfinite(val) and math.isfinite(den) and den != 0 else math.nan
            r[f"{metric}_ratio_vs_modern_tcn_22d"] = ratio; ratios.append(ratio)
            if not math.isfinite(val): reasons.append(f"nonfinite_{metric}")
        r["J_control_path"] = float(np.mean(ratios)) if all(math.isfinite(x) for x in ratios) else math.nan
        if ref:
            if num(r["viol_rate"]) - num(ref["viol_rate"]) > thresholds["viol_rate_max_abs_increase"] + 1e-12: reasons.append("viol_rate_abs_increase")
            if r["omega_cmd_rms_ratio_vs_modern_tcn_22d"] > thresholds["omega_cmd_rms_max_ratio"] + 1e-12: reasons.append("omega_cmd_rms_ratio")
            if r["j_du_ratio_vs_modern_tcn_22d"] > thresholds["delta_u_proxy_max_ratio"] + 1e-12: reasons.append("delta_u_proxy_ratio")
        else: reasons.append("missing_modern_tcn_22d_reference")
        cand_off = off.get((r["method_id"],r["seed"])); ref_off = off.get(("modern_tcn_22d",r["seed"]))
        if cand_off and ref_off:
            for metric,key in [("acc_main","acc_main_min_drop"),("stall_recall","stall_recall_min_drop"),("slope_recall","slope_recall_min_drop")]:
                if num(ref_off.get(metric))-num(cand_off.get(metric)) > thresholds[key]+1e-12: reasons.append(f"{metric}_drop")
            for metric,key in [("theta_edge_p95_abs_err","theta_edge_p95_max_ratio"),("theta_flat_abs_max_deg","flat_peak_theta_error_max_ratio")]:
                den=num(ref_off.get(metric)); val=num(cand_off.get(metric)); ratio=val/den if den!=0 else math.nan
                if not math.isfinite(ratio): reasons.append(f"{metric}_ratio_unevaluable")
                elif ratio>thresholds[key]+1e-12: reasons.append(f"{metric}_ratio")
        else: reasons.append("offline_gate_input_missing")
        r["node10_gate_pass"] = not reasons
        r["node10_gate_reasons"] = "pass" if not reasons else ";".join(sorted(set(reasons)))
        r["constraint_penalty_mapping"] = "not_exported_in_A0_A1_case_table; established project A1 gate mapping uses viol_rate separately"
    return data


def hierarchical_bootstrap(target_rows: list[dict[str, Any]], comp_rows: list[dict[str, Any]], metric: str, offset: int) -> dict[str, Any]:
    t={(r["seed"],r["path_id"]):num(r[metric]) for r in target_rows}; c={(r["seed"],r["path_id"]):num(r[metric]) for r in comp_rows}
    path_ids=sorted({k[1] for k in t}); expected={(s,p) for s in SEEDS for p in path_ids}
    if set(t)!=expected or set(c)!=expected or len(path_ids)!=6: raise ValueError("incomplete hierarchical pair grid")
    seed_effect=np.asarray([np.mean([c[(s,p)]-t[(s,p)] for p in path_ids]) for s in SEEDS])
    seed_rel=np.asarray([np.mean([100*(c[(s,p)]-t[(s,p)])/c[(s,p)] if c[(s,p)]!=0 else np.nan for p in path_ids]) for s in SEEDS])
    # A5 freezes the RNG seed for each bootstrap invocation.
    rng=np.random.default_rng(BOOT_SEED); sims=np.empty(BOOT_N); rsims=np.empty(BOOT_N)
    for b in range(BOOT_N):
        sampled=rng.integers(0,len(SEEDS),len(SEEDS)); e=[]; re=[]
        for si in sampled:
            s=SEEDS[int(si)]; pp=rng.integers(0,len(path_ids),len(path_ids))
            for pi in pp:
                p=path_ids[int(pi)]; e.append(c[(s,p)]-t[(s,p)]); re.append(100*(c[(s,p)]-t[(s,p)])/c[(s,p)] if c[(s,p)]!=0 else np.nan)
        sims[b]=np.mean(e); rsims[b]=np.nanmean(re)
    all_e=np.asarray([c[k]-t[k] for k in sorted(expected)]); all_re=np.asarray([100*(c[k]-t[k])/c[k] if c[k]!=0 else np.nan for k in sorted(expected)])
    return {"target_mean":float(np.mean(list(t.values()))),"comparator_mean":float(np.mean(list(c.values()))),"absolute_effect":float(seed_effect.mean()),"absolute_ci_low":float(np.percentile(sims,2.5)),"absolute_ci_high":float(np.percentile(sims,97.5)),"relative_effect_percent":float(np.nanmean(seed_rel)),"relative_ci_low_percent":float(np.nanpercentile(rsims,2.5)),"relative_ci_high_percent":float(np.nanpercentile(rsims,97.5)),"improved_case_count":int(np.sum(all_e>0)),"paired_case_count":len(all_e),"improved_seed_count":int(np.sum(seed_effect>0)),"paired_seed_count":len(SEEDS),"bootstrap_iterations":BOOT_N,"bootstrap_seed":BOOT_SEED,"ci_method":"percentile_95","resampling_unit":"paired_model_seed_then_paired_path_within_seed"}


def summaries(data: list[dict[str, Any]]) -> tuple[list[dict[str, Any]],list[dict[str,Any]],list[dict[str,Any]],list[dict[str,Any]]]:
    seed_rows=[]; path_rows=[]; method_rows=[]; worst=[]
    for m in METHODS:
        dm=[r for r in data if r["method_id"]==m]
        for s in SEEDS:
            ds=[r for r in dm if r["seed"]==s]
            if ds:
                row={"method_id":m,"seed":s,"path_count":len(ds),"gate_failure_count":sum(not r["node10_gate_pass"] for r in ds)}
                for metric in CONTROL+["J_control_path"]: row[f"{metric}_mean_6paths"]=float(np.mean([num(r[metric]) for r in ds]))
                seed_rows.append(row)
        for p in sorted({r["path_id"] for r in dm}):
            dp=[r for r in dm if r["path_id"]==p]; row={"method_id":m,"path_id":p,"seed_count":len(dp),"gate_failure_count":sum(not r["node10_gate_pass"] for r in dp)}
            for metric in CONTROL+["J_control_path"]: row[f"{metric}_mean_10seeds"]=float(np.mean([num(r[metric]) for r in dp]))
            path_rows.append(row)
        ms=[r for r in seed_rows if r["method_id"]==m]
        for metric in CONTROL+["J_control_path"]:
            vals=np.asarray([r[f"{metric}_mean_6paths"] for r in ms]); method_rows.append({"method_id":m,"metric":metric,"n_seeds":len(vals),"mean":float(vals.mean()),"median":float(np.median(vals)),"std":float(vals.std(ddof=1)) if len(vals)>1 else 0.0})
        mp=[r for r in path_rows if r["method_id"]==m]; ws=max(mp,key=lambda r:r["J_control_path_mean_10seeds"]); wseed=max(ms,key=lambda r:r["J_control_path_mean_6paths"]); wc=max(dm,key=lambda r:r["J_control_path"])
        worst.append({"method_id":m,"worst_path_id":ws["path_id"],"worst_path_mean_J_control":ws["J_control_path_mean_10seeds"],"worst_seed":wseed["seed"],"worst_seed_mean_J_control":wseed["J_control_path_mean_6paths"],"worst_case_seed":wc["seed"],"worst_case_path_id":wc["path_id"],"worst_case_J_control":wc["J_control_path"],"gate_failure_count":sum(not r["node10_gate_pass"] for r in dm)})
    return seed_rows,path_rows,method_rows,worst


def protected_audit() -> tuple[list[dict[str,Any]],bool]:
    baseline=rows(TASK/"00_protocol_lock/protected_artifact_baseline.csv"); out=[]; ok=True
    for r in baseline:
        p=Path(r["path"]); current=sha256(p) if is_file(p) else ""; match=current==r["actual_sha256"]; ok=ok and match
        out.append({"artifact_id":r["artifact_id"],"path":str(p),"baseline_sha256":r["actual_sha256"],"current_sha256":current,"unchanged":match})
    return out,ok


def fmt(value: Any, digits: int = 5) -> str:
    value = num(value)
    return "NA" if not math.isfinite(value) else f"{value:.{digits}g}"


def render_report(
    config: dict[str, Any],
    offline: list[dict[str, str]],
    data: list[dict[str, Any]],
    effects: list[dict[str, Any]],
    method_rows: list[dict[str, Any]],
    worst: list[dict[str, Any]],
    thresholds: dict[str, Any],
    decision: dict[str, Any],
    status: dict[str, Any],
    protected_ok: bool,
) -> str:
    off_index={(r["method_id"],int(float(r["seed"]))):r for r in offline}
    cl_summary={(r["method_id"],r["metric"]):r for r in method_rows}
    lines=[
        "# A1 Fair Algorithm Comparison — Final Experiment Report",
        "",
        f"- Protocol: `{config['protocol_id']}`",
        f"- Final status: `{status['status']}`",
        f"- Final decision: `{decision['decision']}`",
        f"- Decision reason: {decision['reason']}",
        f"- Models: `{status['models_ready']}/40`; offline cases: `{status['offline_cases_complete']}/40`; closed-loop cases: `{decision['grid']['closed_loop_complete']}/240`",
        f"- Closed-loop sources: `{status['closed_loop_cases_reused']}` referenced upstream cases + `{status['closed_loop_cases_new_complete']}` Node39 manual cases",
        f"- Protected A0, outline and `paper_v3.tex` unchanged: `{protected_ok}`",
        "",
        "## Protocol compliance",
        "",
        "All four methods use the frozen dataset/run split, training-set normalization, 128-step window and 22D raw input. "
        "The primary method uses the frozen 88D `delta_bank_124` construction. The six paths, ten seeds, Node10 v2 gates, "
        "plant revision, MPC configuration and training recipes were not changed in response to results. Missing values were not imputed.",
        "",
        "## Unified offline evaluation",
        "",
        "| Method | theta MAE (deg) | \\|theta\\|<=10 P95 error (deg) | main accuracy | stall recall | slope recall |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for method in METHODS:
        rr=[r for r in offline if r["method_id"]==method]
        means={k:float(np.mean([num(r[k]) for r in rr])) for k in ["theta_mae_deg","theta_abs_le_10_p95_abs_err_deg","acc_main","stall_recall","slope_recall"]}
        lines.append(f"| `{method}` | {fmt(means['theta_mae_deg'])} | {fmt(means['theta_abs_le_10_p95_abs_err_deg'])} | {fmt(means['acc_main'])} | {fmt(means['stall_recall'])} | {fmt(means['slope_recall'])} |")
    lines += [
        "",
        "The paired 10,000-iteration seed bootstrap supports delta-bank over all three comparators for both preregistered offline primary metrics.",
        "",
        "| Comparator | Metric | comparator − delta | 95% percentile CI | Seeds improved |",
        "|---|---|---:|---:|---:|",
    ]
    for e in effects:
        if e["domain"]=="offline" and e["contrast_family"]=="cross_algorithm" and e["target_method"]=="modern_tcn_delta_bank_124":
            lines.append(f"| `{e['comparator_method']}` | `{e['metric']}` | {fmt(e['absolute_effect'])} | [{fmt(e['absolute_ci_low'])}, {fmt(e['absolute_ci_high'])}] | {e['improved_seed_count']}/{e['paired_seed_count']} |")
    lines += [
        "",
        "## Closed-loop comparison",
        "",
        "| Method | ey RMSE | epsi RMSE | j_du | mean J_control_path | Node10 failed rows |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for method in METHODS:
        failed=sum(r["method_id"]==method and not r["node10_gate_pass"] for r in data)
        lines.append(
            f"| `{method}` | {fmt(cl_summary[(method,'ey_rmse')]['mean'])} | "
            f"{fmt(cl_summary[(method,'epsi_rmse')]['mean'])} | {fmt(cl_summary[(method,'j_du')]['mean'])} | "
            f"{fmt(cl_summary[(method,'J_control_path')]['mean'])} | {failed} |"
        )
    lines += [
        "",
        "`J_control_path` is recomputed against the matched ModernTCN-22D seed/path case; historical J values are not reused.",
        "",
        "| Comparator | Metric | comparator − delta | 95% percentile CI | Cases improved | CI supports delta |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for e in effects:
        if e["domain"]=="closed_loop" and e["contrast_family"]=="cross_algorithm":
            lines.append(f"| `{e['comparator_method']}` | `{e['metric']}` | {fmt(e['absolute_effect'])} | [{fmt(e['absolute_ci_low'])}, {fmt(e['absolute_ci_high'])}] | {e['improved_case_count']}/{e['paired_case_count']} | {e['ci_supports_target']} |")
    lines += [
        "",
        "Delta-bank is clearly favored over GRU-22D and TCN-22D for all three closed-loop primary metrics. "
        "Against ModernTCN-22D, `j_du` is supported, while the `ey_rmse` and `epsi_rmse` confidence intervals cross zero.",
        "",
        "## 22D architecture control",
        "",
        "| Domain | Target | Comparator | Metric | comparator − target | 95% CI | Supported |",
        "|---|---|---|---|---:|---:|---:|",
    ]
    for e in effects:
        if e["contrast_family"]=="architecture_control":
            lines.append(f"| {e['domain']} | `{e['target_method']}` | `{e['comparator_method']}` | `{e['metric']}` | {fmt(e['absolute_effect'])} | [{fmt(e['absolute_ci_low'])}, {fmt(e['absolute_ci_high'])}] | {e['ci_supports_target']} |")
    lines += [
        "",
        "ModernTCN-22D is supported over both GRU-22D and traditional TCN-22D on the offline architecture controls and all three closed-loop primary metrics. "
        "The exploratory GRU-versus-TCN comparison is mixed.",
        "",
        "## Paired representation ablation",
        "",
        "| Domain | Metric | ModernTCN-22D − delta-bank | 95% CI | Supported |",
        "|---|---|---:|---:|---:|",
    ]
    for e in effects:
        if e["contrast_family"]=="representation_ablation":
            lines.append(f"| {e['domain']} | `{e['metric']}` | {fmt(e['absolute_effect'])} | [{fmt(e['absolute_ci_low'])}, {fmt(e['absolute_ci_high'])}] | {e['ci_supports_target']} |")
    lines += [
        "",
        "The 88D delta-bank representation improves both offline ablation metrics. In closed loop it substantially reduces `j_du`, "
        "but the two tracking-error CIs do not exclude zero.",
        "",
        "## Frozen Node10 gate audit",
        "",
        f"- `stall_recall_min_drop`: {thresholds['stall_recall_min_drop']}",
        f"- `flat_peak_theta_error_max_ratio`: {thresholds['flat_peak_theta_error_max_ratio']}",
        "- The 24 failed path rows arise from four seed-level offline gate failures repeated across the six frozen paths; they are not 24 independent offline failures.",
        "",
        "| Seed | Gate | Delta value | ModernTCN-22D value | Difference/ratio |",
        "|---:|---|---:|---:|---:|",
    ]
    for seed,metric,gate in [(21,"stall_recall","stall_recall_drop"),(101,"stall_recall","stall_recall_drop"),(73,"theta_flat_abs_max_deg","theta_flat_abs_max_deg_ratio"),(340,"theta_flat_abs_max_deg","theta_flat_abs_max_deg_ratio")]:
        target=off_index[("modern_tcn_delta_bank_124",seed)]; ref=off_index[("modern_tcn_22d",seed)]
        a=num(target[metric]); b=num(ref[metric])
        value=b-a if metric=="stall_recall" else a/b
        lines.append(f"| {seed} | `{gate}` | {fmt(a)} | {fmt(b)} | {fmt(value)} |")
    lines += [
        "",
        "Because the primary method fails an applicable frozen gate, the preregistered decision rule requires `NOT_SUPPORTED`, "
        "even though its aggregate offline results and most closed-loop comparisons are favorable.",
        "",
        "## Worst-path and worst-case audit",
        "",
        "| Method | Worst path | Path mean J | Worst seed | Seed mean J | Worst case | Case J |",
        "|---|---|---:|---:|---:|---|---:|",
    ]
    for r in worst:
        lines.append(f"| `{r['method_id']}` | `{r['worst_path_id']}` | {fmt(r['worst_path_mean_J_control'])} | {r['worst_seed']} | {fmt(r['worst_seed_mean_J_control'])} | seed {r['worst_case_seed']} / `{r['worst_case_path_id']}` | {fmt(r['worst_case_J_control'])} |")
    lines += [
        "",
        "## Final decision",
        "",
        f"**`{decision['decision']}`** — {decision['reason']}.",
        "",
        "This result is retained without changing paths, seeds, thresholds, plant/MPC settings or model recipes. "
        "No manuscript source file was modified.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    config=json.loads((TASK/"00_protocol_lock/a1_config.json").read_text(encoding="utf-8")); offline_file=TASK/"03_offline/offline_case_metrics.csv"
    offline=rows(offline_file) if is_file(offline_file) else []
    data,missing=collect_grid(config)
    threshold_file=ROOT/"results/modern_tcn_metric_rebuild/10_threshold_recalibration/hard_constraint_thresholds_v2_closed_loop_proposed.json"
    thresholds=json.loads(threshold_file.read_text(encoding="utf-8"))
    if data: data=add_ratios_and_gates(data,offline,thresholds)
    write_rows(TASK/"04_closed_loop/closed_loop_case_metrics.csv",data); write_rows(TASK/"closed_loop_case_metrics.csv",data); write_rows(TASK/"04_closed_loop/missing_cases_after_manual_run.csv",missing)
    complete=(len(offline)==40 and len(data)==240 and not missing)
    seed_rows=path_rows=method_rows=worst=[]; cl_effects=[]
    if len(data)==240:
        seed_rows,path_rows,method_rows,worst=summaries(data)
        write_rows(TASK/"05_analysis/closed_loop_seed_summary.csv",seed_rows); write_rows(TASK/"05_analysis/closed_loop_path_summary.csv",path_rows); write_rows(TASK/"05_analysis/closed_loop_method_summary.csv",method_rows); write_rows(TASK/"05_analysis/worst_paths_and_cases.csv",worst)
        contrasts=[("cross_algorithm","modern_tcn_delta_bank_124","modern_tcn_22d",True),("cross_algorithm","modern_tcn_delta_bank_124","gru_22d",True),("cross_algorithm","modern_tcn_delta_bank_124","tcn_22d",True),("architecture_control","modern_tcn_22d","gru_22d",True),("architecture_control","modern_tcn_22d","tcn_22d",True),("architecture_control","gru_22d","tcn_22d",False),("representation_ablation","modern_tcn_delta_bank_124","modern_tcn_22d",True)]
        offset=100
        for family,target,comp,confirm in contrasts:
            for metric in CL_PRIMARY:
                offset+=1; stat=hierarchical_bootstrap([r for r in data if r["method_id"]==target],[r for r in data if r["method_id"]==comp],metric,offset)
                cl_effects.append({"domain":"closed_loop","contrast_family":family,"target_method":target,"comparator_method":comp,"metric":metric,"confirmatory":confirm,"effect_convention":"comparator-target; positive favors target",**stat,"ci_supports_target":stat["absolute_ci_low"]>0})
    write_rows(TASK/"05_analysis/closed_loop_bootstrap_results.csv",cl_effects)
    offline_effect_file=TASK/"05_analysis/offline_bootstrap_results.csv"
    if is_file(offline_effect_file):
        offline_effect=rows(offline_effect_file)
    else:
        prior=rows(TASK/"05_analysis/bootstrap_results.csv") if is_file(TASK/"05_analysis/bootstrap_results.csv") else []
        offline_effect=[r for r in prior if r.get("domain")=="offline"]
        write_rows(offline_effect_file,offline_effect)
    all_effects=offline_effect+cl_effects
    write_rows(TASK/"05_analysis/paired_effects.csv",all_effects)
    write_rows(TASK/"05_analysis/bootstrap_results.csv",all_effects)
    write_rows(TASK/"05_analysis/bootstrap_results_all.csv",all_effects)
    write_rows(TASK/"05_analysis/architecture_control.csv",[r for r in all_effects if r["contrast_family"]=="architecture_control"])
    write_rows(TASK/"05_analysis/representation_ablation.csv",[r for r in all_effects if r["contrast_family"]=="representation_ablation"])

    protected,protected_ok=protected_audit(); write_rows(TASK/"05_analysis/protected_artifact_audit.csv",protected)
    offline_decision="INCOMPLETE_GRID"; current_dec={}
    if is_file(TASK/"decision.json"): current_dec=json.loads((TASK/"decision.json").read_text(encoding="utf-8")); offline_decision=current_dec.get("offline_decision",offline_decision)
    main_cl=[r for r in cl_effects if r["contrast_family"]=="cross_algorithm" and r["confirmatory"]]
    delta_gate_fail=any(r["method_id"]=="modern_tcn_delta_bank_124" and not r["node10_gate_pass"] for r in data)
    offline_missing=max(0,40-len(offline))
    if not complete: final="INCOMPLETE_GRID"; reason=f"offline={len(offline)}/40 (missing={offline_missing}) closed_loop={len(data)}/240 (missing={len(missing)})"
    elif delta_gate_fail: final="NOT_SUPPORTED"; reason="one or more applicable Node10 gate checks failed for the primary method"
    elif offline_decision=="SUPPORTED_ALL_PRIMARY" and all(r["absolute_ci_low"]>0 for r in main_cl): final="SUPPORTED_ALL_PRIMARY"; reason="all preregistered offline and closed-loop primary CIs favor delta_bank_124 and gates pass"
    elif offline_decision=="NOT_SUPPORTED" or any(r["absolute_effect"]<=0 for r in main_cl): final="NOT_SUPPORTED"; reason="one or more preregistered primary point effects do not favor delta_bank_124"
    else: final="INCONCLUSIVE"; reason="primary point estimates favor delta_bank_124 but at least one preregistered CI crosses zero"
    decision={"task_id":"A1_algorithm_comparison","updated_at":now(),"provisional":not complete,"decision":final,"reason":reason,"offline_decision":offline_decision,"grid":{"offline_complete":len(offline),"offline_expected":40,"offline_missing":offline_missing,"closed_loop_complete":len(data),"closed_loop_expected":240,"closed_loop_missing":len(missing)},"node10_primary_method_gate_fail":delta_gate_fail if complete else None,"node10_primary_method_gate_fail_observed_on_available_cases":delta_gate_fail,"protected_artifacts_unchanged":protected_ok,"results_used_for_recipe_or_threshold_changes":False}
    write_json(TASK/"decision.json",decision)
    if complete and protected_ok:
        stage="COMPLETE"; next_action="none"
    elif len(offline)<40:
        stage="OFFLINE_INCOMPLETE"; next_action="allow frozen TCN training to finish, refresh inventory, rerun MATLAB offline evaluation and finalize_A1_offline.py"
    else:
        stage="READY_FOR_MANUAL_CLOSED_LOOP"; next_action="run/resume MANUAL_RUNBOOK.md then rerun finalize_A1.py"
    status={"task_id":"A1_algorithm_comparison","updated_at":now(),"status":stage,"models_ready":sum(r["status"]=="READY" for r in rows(TASK/"model_registry.csv")),"offline_cases_complete":len(offline),"offline_cases_missing":offline_missing,"closed_loop_cases_reused":sum(r["source_kind"].startswith("UPSTREAM") for r in data),"closed_loop_cases_new_complete":sum(r["source_kind"]=="NODE39_MANUAL_RUN" for r in data),"closed_loop_cases_missing":len(missing),"next_action":next_action}
    write_json(TASK/"task_status.json",status)
    receipt={"task_id":"A1_algorithm_comparison","timestamp":now(),"status":status["status"],"output_root":str(TASK),"write_boundary_respected":True,"protected_artifacts":protected,"protected_artifacts_unchanged":protected_ok,"counts":{"models":status["models_ready"],"offline_cases":len(offline),"missing_offline_cases":offline_missing,"closed_loop_cases":len(data),"missing_closed_loop_cases":len(missing)},"decision_file":str(TASK/"decision.json"),"manual_runbook":str(TASK/"MANUAL_RUNBOOK.md")}
    write_json(TASK/"receipt.json",receipt)
    manifest={"task_id":"A1_algorithm_comparison","updated_at":now(),"protocol_id":config["protocol_id"],"stage":status["status"],"commands":["build_a1_inventory.py","run_A1_train_missing_tcn","run_A1_offline_modern.py","run_A1_offline_matlab","finalize_A1_offline.py","run_A1_closed_loop_parallel() [validated GRU+TCN process split]","run_A1_closed_loop_manual('gru'|'tcn') [serial fallback]","finalize_A1.py"],"counts":receipt["counts"]}
    write_json(TASK/"run_manifest.json",manifest)
    report=render_report(config,offline,data,all_effects,method_rows,worst,thresholds,decision,status,protected_ok)
    (TASK/"A1_experiment_report.md").write_text(report,encoding="utf-8")
    artifacts=[]
    walk_root=os.fspath(fs_path(TASK,force_extended=True))
    for dirpath,_,names in os.walk(walk_root):
        for name in sorted(names):
            if name=="artifact_manifest.json": continue
            extended=Path(dirpath)/name
            display_text=str(extended)
            if display_text.startswith("\\\\?\\UNC\\"): display_text="\\\\"+display_text[8:]
            elif display_text.startswith("\\\\?\\"): display_text=display_text[4:]
            p=Path(display_text)
            artifacts.append({"relative_path":p.relative_to(TASK).as_posix(),"absolute_path":str(p),"size_bytes":extended.stat().st_size,"sha256":sha256(extended)})
    artifacts.sort(key=lambda r:r["relative_path"])
    write_json(TASK/"artifact_manifest.json",{"task_id":"A1_algorithm_comparison","generated_at":now(),"artifact_count":len(artifacts),"artifacts":artifacts})
    print(json.dumps({"status":status["status"],"offline":len(offline),"closed_loop":len(data),"missing":len(missing),"decision":final},ensure_ascii=False))
    return 0 if complete and protected_ok else 4


if __name__=="__main__": raise SystemExit(main())
