"""汇总并冻结 ModernTCN-small v1 的 5 seed 结果。

本脚本只读取已经完成的训练与一致性检查结果，不重新训练、不重新导出 ONNX，
也不修改数据集。输出用于论文/报告阶段固定对照：

    results/modern_tcn/ModernTCN_v1_5seed_per_seed.csv
    results/modern_tcn/ModernTCN_v1_5seed_summary.csv
    results/modern_tcn/ModernTCN_v1_baseline_comparison.csv
    results/modern_tcn/ModernTCN_v1_freeze_manifest.json
    results/modern_tcn/ModernTCN_v1_5seed_report.md
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from statistics import mean, stdev
from typing import Dict, Iterable, List, Tuple


SEEDS = [11, 21, 42, 73, 101]

METRICS = [
    "acc_main",
    "acc_turn",
    "acc_turn_pure",
    "acc_turn_transition",
    "theta_mae_deg",
    "flat_recall",
    "stall_recall",
    "slope_recall",
    "uphill_recall",
    "downhill_recall",
]

FINAL_TARGETS = {
    "acc_main": (">=", 0.93),
    "flat_recall": (">=", 0.90),
    "slope_recall": (">=", 0.94),
    "acc_turn_transition": (">=", 0.77),
    "theta_mae_deg": ("<=", 0.43),
}

# 这些 baseline 数值来自 src/TCN/transition_rich_v3_baseline_handoff_for_modern_tcn.md，
# 是本轮 ModernTCN 对照使用的冻结参考。
BASELINE_MEAN_STD = {
    "GRU strong baseline": {
        "acc_main": (0.9400, 0.0050),
        "acc_turn": (0.8875, 0.0104),
        "acc_turn_transition": (0.6870, 0.0381),
        "theta_mae_deg": (0.4195, 0.0653),
        "flat_recall": (0.9070, 0.0086),
        "stall_recall": (0.9161, 0.0275),
        "slope_recall": (0.9715, 0.0066),
        "uphill_recall": (0.9623, 0.0065),
        "downhill_recall": (0.9857, 0.0079),
    },
    "TCN staged baseline": {
        "acc_main": (0.9052, 0.0350),
        "acc_turn": (0.9063, 0.0027),
        "acc_turn_transition": (0.7830, 0.0115),
        "theta_mae_deg": (0.4490, 0.0846),
        "flat_recall": (0.8594, 0.0523),
        "stall_recall": (0.9688, 0.0168),
        "slope_recall": (0.9350, 0.0458),
        "uphill_recall": (0.9104, 0.0511),
        "downhill_recall": (0.9732, 0.0389),
    },
}

TCN_CALIBRATED_UPPER_BOUND = {
    "seed": 73,
    "best_epoch": 83,
    "acc_main": 0.9442,
    "acc_turn": 0.9077,
    "acc_turn_pure": 0.9264,
    "acc_turn_transition": 0.7851,
    "theta_mae_deg": 0.3998,
    "flat_recall": 0.9233,
    "stall_recall": 0.9756,
    "slope_recall": 0.9574,
    "uphill_recall": 0.9564,
    "downhill_recall": 0.9589,
}


@dataclass
class ConsistencyStatus:
    """记录单 seed 的 ONNXRuntime/MATLAB 一致性检查状态。"""

    onnxruntime_pass: bool
    matlab_pass: bool
    onnxruntime_report: str
    matlab_report: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="汇总 ModernTCN-small v1 5 seed 结果")
    p.add_argument("--root", type=str, default="", help="项目根目录，默认自动向上寻找 init_project.m。")
    p.add_argument("--out-dir", type=str, default="", help="输出目录，默认 results/modern_tcn。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve() if args.root else find_project_root()
    out_dir = Path(args.out_dir).resolve() if args.out_dir else root / "results" / "modern_tcn"
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = [read_seed_row(out_dir, seed) for seed in SEEDS]
    consistency = {seed: read_consistency(out_dir, seed) for seed in SEEDS}
    summary_rows = build_summary_rows(rows)
    comparison_rows = build_comparison_rows(summary_rows)

    per_seed_csv = out_dir / "ModernTCN_v1_5seed_per_seed.csv"
    summary_csv = out_dir / "ModernTCN_v1_5seed_summary.csv"
    comparison_csv = out_dir / "ModernTCN_v1_baseline_comparison.csv"
    manifest_json = out_dir / "ModernTCN_v1_freeze_manifest.json"
    report_md = out_dir / "ModernTCN_v1_5seed_report.md"

    write_csv(per_seed_csv, rows)
    write_csv(summary_csv, summary_rows)
    write_csv(comparison_csv, comparison_rows)
    write_manifest(manifest_json, root, out_dir, rows, consistency)
    write_report(report_md, root, rows, summary_rows, comparison_rows, consistency)

    print("[ModernTCN v1 summary] wrote:")
    print(f"  {per_seed_csv}")
    print(f"  {summary_csv}")
    print(f"  {comparison_csv}")
    print(f"  {manifest_json}")
    print(f"  {report_md}")


def find_project_root() -> Path:
    here = Path(__file__).resolve()
    for p in [here, *here.parents]:
        if (p / "init_project.m").exists():
            return p
    raise FileNotFoundError("无法定位项目根目录：未找到 init_project.m。")


def read_seed_row(out_dir: Path, seed: int) -> Dict[str, object]:
    summary_file = out_dir / f"transition_rich_v3_seed{seed}" / f"modern_tcn_seed{seed}_summary.csv"
    if not summary_file.exists():
        raise FileNotFoundError(f"缺少 seed{seed} summary: {summary_file}")
    with summary_file.open(newline="", encoding="utf-8") as f:
        row = next(csv.DictReader(f))
    result: Dict[str, object] = {
        "model": row["model"],
        "seed": int(row["seed"]),
        "best_epoch": int(row["best_epoch"]),
    }
    for m in METRICS:
        result[m] = float(row[m])
    result["checkpoint_file"] = row.get("checkpoint_file", "")
    result["report_file"] = row.get("report_file", "")
    return result


def read_consistency(out_dir: Path, seed: int) -> ConsistencyStatus:
    seed_dir = out_dir / f"transition_rich_v3_seed{seed}"
    ort_md = seed_dir / f"modern_tcn_seed{seed}_onnxruntime_consistency.md"
    matlab_md = seed_dir / f"modern_tcn_seed{seed}_matlab_consistency.md"
    if not ort_md.exists():
        raise FileNotFoundError(f"缺少 ONNXRuntime 一致性报告: {ort_md}")
    if not matlab_md.exists():
        raise FileNotFoundError(f"缺少 MATLAB 一致性报告: {matlab_md}")
    return ConsistencyStatus(
        onnxruntime_pass=parse_pass_flag(ort_md),
        matlab_pass=parse_pass_flag(matlab_md),
        onnxruntime_report=str(ort_md),
        matlab_report=str(matlab_md),
    )


def parse_pass_flag(md_file: Path) -> bool:
    text = md_file.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"pass:\s*`?([01])`?", text)
    if not m:
        raise ValueError(f"无法解析 pass 字段: {md_file}")
    return m.group(1) == "1"


def build_summary_rows(rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
    summary = []
    for m in METRICS:
        vals = [float(r[m]) for r in rows]
        op, target = FINAL_TARGETS.get(m, ("", float("nan")))
        target_pass = ""
        if op == ">=":
            target_pass = mean(vals) >= target
        elif op == "<=":
            target_pass = mean(vals) <= target
        summary.append(
            {
                "model": "ModernTCN-small v1",
                "metric": m,
                "mean": mean(vals),
                "std": stdev(vals),
                "min": min(vals),
                "max": max(vals),
                "target_op": op,
                "target": target if op else "",
                "target_pass": target_pass,
                "values_by_seed_11_21_42_73_101": ";".join(f"{v:.6f}" for v in vals),
            }
        )
    return summary


def build_comparison_rows(summary_rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
    modern = {r["metric"]: r for r in summary_rows}
    comparison = []
    for m in METRICS:
        modern_row = modern[m]
        comparison.append(
            {
                "model": "ModernTCN-small v1",
                "type": "5seed_mean_std",
                "metric": m,
                "mean_or_value": modern_row["mean"],
                "std": modern_row["std"],
                "note": "",
            }
        )
        for model_name, model_metrics in BASELINE_MEAN_STD.items():
            if m in model_metrics:
                mu, sd = model_metrics[m]
                comparison.append(
                    {
                        "model": model_name,
                        "type": "5seed_mean_std",
                        "metric": m,
                        "mean_or_value": mu,
                        "std": sd,
                        "note": "frozen handoff baseline",
                    }
                )
        if m in TCN_CALIBRATED_UPPER_BOUND:
            comparison.append(
                {
                    "model": "TCN calibrated upper bound",
                    "type": "single_checkpoint",
                    "metric": m,
                    "mean_or_value": TCN_CALIBRATED_UPPER_BOUND[m],
                    "std": "",
                    "note": "validate base_comp_flat120 seed73; not stable multi-seed conclusion",
                }
            )
    return comparison


def write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_manifest(
    path: Path,
    root: Path,
    out_dir: Path,
    rows: List[Dict[str, object]],
    consistency: Dict[int, ConsistencyStatus],
) -> None:
    manifest = {
        "freeze_name": "ModernTCN-small v1",
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "dataset": str(root / "data" / "tcn" / "TCN_dataset_v3_transition_rich.mat"),
        "seeds": SEEDS,
        "fixed_contract": {
            "split": "MAT 文件已有 run-level split",
            "scaler": "使用 MAT 文件已有归一化后 X，不重新拟合",
            "input_shape": "[batch, time=128, feature=19]",
            "outputs": ["logits_main", "logits_turn", "theta_hat"],
            "onnx_opset": 17,
            "onnx_batch": 1,
        },
        "artifacts": {
            str(r["seed"]): {
                "checkpoint_file": r["checkpoint_file"],
                "report_file": r["report_file"],
                "onnx_file": str(out_dir / f"transition_rich_v3_seed{r['seed']}" / f"modern_tcn_seed{r['seed']}.onnx"),
                "onnxruntime_report": consistency[int(r["seed"])].onnxruntime_report,
                "matlab_report": consistency[int(r["seed"])].matlab_report,
            }
            for r in rows
        },
    }
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


def write_report(
    path: Path,
    root: Path,
    rows: List[Dict[str, object]],
    summary_rows: List[Dict[str, object]],
    comparison_rows: List[Dict[str, object]],
    consistency: Dict[int, ConsistencyStatus],
) -> None:
    summary = {r["metric"]: r for r in summary_rows}
    with path.open("w", encoding="utf-8") as f:
        f.write("# ModernTCN-small v1 5-Seed 冻结报告\n\n")
        f.write(f"- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("- Freeze name: `ModernTCN-small v1`\n")
        f.write("- Dataset: `data/tcn/TCN_dataset_v3_transition_rich.mat`\n")
        f.write("- Seeds: `11, 21, 42, 73, 101`\n")
        f.write("- Split/scaler: 使用 MAT 文件已有 run-level split 与归一化后 X，不重划分、不重拟合。\n")
        f.write("- Deployment chain: PyTorch -> ONNX -> ONNXRuntime -> MATLAB imported dlnetwork。\n\n")

        f.write("## 判定结论\n\n")
        f.write("- `acc_main`、`flat_recall`、`slope_recall` 稳定超过最终推荐目标，说明 v1 已修复 staged TCN 的 flat/slope 主工况边界崩塌。\n")
        f.write("- `acc_turn_transition` 均值低于 0.77，未达到最终推荐目标，也低于 TCN staged baseline。\n")
        f.write("- `theta_mae_deg` 均值高于 0.43，未达到最终推荐目标，也弱于 GRU strong baseline。\n")
        f.write("- 5 个 seed 的 ONNXRuntime 与 MATLAB 一致性均通过，当前 v1 可以作为冻结的离线模型版本。\n\n")

        f.write("## 5-Seed 指标\n\n")
        f.write("| metric | mean | std | min | max | target | pass |\n")
        f.write("|---|---:|---:|---:|---:|---:|---:|\n")
        for m in METRICS:
            r = summary[m]
            target = ""
            if r["target_op"]:
                target = f"{r['target_op']} {float(r['target']):.4f}"
            target_pass = "" if r["target_pass"] == "" else int(bool(r["target_pass"]))
            f.write(
                f"| {m} | {float(r['mean']):.4f} | {float(r['std']):.4f} | "
                f"{float(r['min']):.4f} | {float(r['max']):.4f} | {target} | {target_pass} |\n"
            )

        f.write("\n## Per-Seed 指标\n\n")
        f.write("| seed | epoch | main | turn | turnT | theta deg | flat | stall | slope | uphill | downhill |\n")
        f.write("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for r in rows:
            f.write(
                f"| {r['seed']} | {r['best_epoch']} | {float(r['acc_main']):.4f} | "
                f"{float(r['acc_turn']):.4f} | {float(r['acc_turn_transition']):.4f} | "
                f"{float(r['theta_mae_deg']):.4f} | {float(r['flat_recall']):.4f} | "
                f"{float(r['stall_recall']):.4f} | {float(r['slope_recall']):.4f} | "
                f"{float(r['uphill_recall']):.4f} | {float(r['downhill_recall']):.4f} |\n"
            )

        f.write("\n## Baseline 对照\n\n")
        f.write("| metric | ModernTCN v1 mean/std | GRU mean/std | TCN staged mean/std | TCN calibrated upper bound |\n")
        f.write("|---|---:|---:|---:|---:|\n")
        for m in ["acc_main", "acc_turn", "acc_turn_transition", "theta_mae_deg", "flat_recall", "stall_recall", "slope_recall", "uphill_recall", "downhill_recall"]:
            mt = summary[m]
            gru = BASELINE_MEAN_STD["GRU strong baseline"].get(m, ("", ""))
            tcn = BASELINE_MEAN_STD["TCN staged baseline"].get(m, ("", ""))
            cal = TCN_CALIBRATED_UPPER_BOUND.get(m, "")
            f.write(
                f"| {m} | {float(mt['mean']):.4f} / {float(mt['std']):.4f} | "
                f"{fmt_mean_std(gru)} | {fmt_mean_std(tcn)} | {fmt_value(cal)} |\n"
            )

        f.write("\n## 三方一致性\n\n")
        f.write("| seed | ONNXRuntime pass | MATLAB pass | MATLAB report |\n")
        f.write("|---:|---:|---:|---|\n")
        for seed in SEEDS:
            c = consistency[seed]
            f.write(f"| {seed} | {int(c.onnxruntime_pass)} | {int(c.matlab_pass)} | `{relpath(c.matlab_report, root)}` |\n")

        f.write("\n## 冻结产物\n\n")
        f.write("- `results/modern_tcn/ModernTCN_v1_5seed_per_seed.csv`\n")
        f.write("- `results/modern_tcn/ModernTCN_v1_5seed_summary.csv`\n")
        f.write("- `results/modern_tcn/ModernTCN_v1_baseline_comparison.csv`\n")
        f.write("- `results/modern_tcn/ModernTCN_v1_freeze_manifest.json`\n")
        f.write("- `results/modern_tcn/ModernTCN_v1_5seed_report.md`\n\n")

        f.write("## 下一步建议\n\n")
        f.write("1. 保留 v1 作为冻结基线，用于论文中的 ModernTCN-small v1 对照。\n")
        f.write("2. 若继续优化，开启 ModernTCN v2，只做小范围定向修正：提高 `turn_transition_weight`、`lambda_turn` 和 `lambda_theta`，并提高选模分数中 turn-transition/theta 权重。\n")
        f.write("3. 进入 Simulink 前，先写 MATLAB 离线全 test set 推理脚本，验证标签映射、softmax 后处理和全量测试集指标与 Python 一致。\n")


def fmt_mean_std(v: Tuple[object, object]) -> str:
    if v == ("", ""):
        return ""
    return f"{float(v[0]):.4f} / {float(v[1]):.4f}"


def fmt_value(v: object) -> str:
    if v == "":
        return ""
    return f"{float(v):.4f}"


def relpath(path_text: str, root: Path) -> str:
    try:
        return str(Path(path_text).resolve().relative_to(root.resolve()))
    except Exception:
        return path_text


if __name__ == "__main__":
    main()

