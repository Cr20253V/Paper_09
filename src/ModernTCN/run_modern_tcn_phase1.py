"""ModernTCN 第一阶段执行入口。

默认流程：
    1. 训练 seed42。
    2. 导出 seed42 ONNX。
    3. 如果安装了 onnxruntime，则自动做 PyTorch vs ONNXRuntime 一致性检查。
    4. seed42 过门槛且指定 --auto-three-seed 时，再训练 [73,101]。

MATLAB 导入 ONNX 的检查需要在 MATLAB 中运行 ModernTCN_check_matlab_onnx.m。
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

from modern_tcn_metrics import seed42_gate
from train_modern_tcn import train_one_seed


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN 第一阶段流水线")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--dataset-file", type=str, default="")
    p.add_argument("--auto-three-seed", action="store_true", help="seed42 过线后自动补跑 73 和 101。")
    p.add_argument("--skip-export", action="store_true")
    p.add_argument("--run-tag", type=str, default="")
    p.add_argument("--epochs", type=int, default=120)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--turn-head-source", type=str, default="full", choices=["full", "inputstats", "kinematic_stats"])
    p.add_argument("--lambda-turn", type=float, default=0.05)
    p.add_argument("--turn-transition-weight", type=float, default=1.0)
    p.add_argument("--turn-class-multipliers", type=float, nargs=3, default=[1.00, 1.10, 1.00])
    p.add_argument("--select-turn-weight", type=float, default=0.30)
    p.add_argument("--select-turn-transition-weight", type=float, default=1.00)
    p.add_argument("--select-turn-left-weight", type=float, default=0.00)
    p.add_argument("--select-turn-left-target", type=float, default=0.80)
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    return p.parse_args()


def main() -> None:
    args = parse_args()
    seeds = [args.seed]
    seed42_pass = False

    for seed in seeds:
        train_args = argparse.Namespace(
            seed=seed,
            dataset_file=args.dataset_file,
            run_tag=_seed_run_tag(args, seed),
            epochs=args.epochs,
            batch_size=args.batch_size,
            lr=1e-3,
            weight_decay=1e-4,
            patience=25,
            min_epochs=30,
            channels=64,
            blocks=5,
            kernel_size=31,
            dropout=0.15,
            turn_head_source=args.turn_head_source,
            lambda_turn=args.lambda_turn,
            turn_transition_weight=args.turn_transition_weight,
            turn_class_multipliers=args.turn_class_multipliers,
            select_turn_weight=args.select_turn_weight,
            select_turn_transition_weight=args.select_turn_transition_weight,
            select_turn_left_weight=args.select_turn_left_weight,
            select_turn_left_target=args.select_turn_left_target,
            device=args.device,
            num_workers=0,
            limit_train=0,
            limit_val=0,
            limit_test=0,
            dry_run=False,
        )
        result = train_one_seed(train_args)
        metrics = result["test_metrics"]
        if seed == 42:
            seed42_pass, failures = seed42_gate(metrics)
            if not seed42_pass:
                print("[ModernTCN phase1] seed42 未过线，不自动进入三 seed。")
                for msg in failures:
                    print(f"  - {msg}")

        if not args.skip_export:
            _export_and_check(Path(result["checkpoint_file"]))

    if args.auto_three_seed and seed42_pass:
        print("[ModernTCN phase1] seed42 已过线，开始补跑 seeds=[73,101]")
        for seed in [73, 101]:
            extra_args = argparse.Namespace(**{**vars(args), "seed": seed})
            extra_train_args = argparse.Namespace(
                seed=seed,
                dataset_file=args.dataset_file,
                run_tag=_seed_run_tag(args, seed),
                epochs=args.epochs,
                batch_size=args.batch_size,
                lr=1e-3,
                weight_decay=1e-4,
                patience=25,
                min_epochs=30,
                channels=64,
                blocks=5,
                kernel_size=31,
                dropout=0.15,
                turn_head_source=args.turn_head_source,
                lambda_turn=args.lambda_turn,
                turn_transition_weight=args.turn_transition_weight,
                turn_class_multipliers=args.turn_class_multipliers,
                select_turn_weight=args.select_turn_weight,
                select_turn_transition_weight=args.select_turn_transition_weight,
                select_turn_left_weight=args.select_turn_left_weight,
                select_turn_left_target=args.select_turn_left_target,
                device=args.device,
                num_workers=0,
                limit_train=0,
                limit_val=0,
                limit_test=0,
                dry_run=False,
            )
            result = train_one_seed(extra_train_args)
            if not args.skip_export:
                _export_and_check(Path(result["checkpoint_file"]))


def _seed_run_tag(args: argparse.Namespace, seed: int) -> str:
    if not args.run_tag:
        return f"transition_rich_v3_seed{seed}"
    if args.auto_three_seed:
        return f"{args.run_tag}_seed{seed}"
    return args.run_tag


def _export_and_check(checkpoint: Path) -> None:
    if importlib.util.find_spec("onnx") is None:
        print("[ModernTCN phase1] 缺少 onnx，已跳过 ONNX 导出。请先运行：python -m pip install onnx onnxruntime")
        return
    if importlib.util.find_spec("onnxscript") is None:
        print("[ModernTCN phase1] 缺少 onnxscript，已跳过 ONNX 导出。请先运行：python -m pip install onnxscript")
        return
    script_dir = Path(__file__).resolve().parent
    export_cmd = [sys.executable, str(script_dir / "export_modern_tcn_onnx.py"), "--checkpoint", str(checkpoint)]
    subprocess.run(export_cmd, check=True)
    onnx_file = checkpoint.with_suffix(".onnx")
    sample_file = checkpoint.with_name(checkpoint.stem + "_pytorch_reference.mat")
    check_cmd = [
        sys.executable,
        str(script_dir / "check_onnxruntime_consistency.py"),
        "--onnx-file",
        str(onnx_file),
        "--sample-file",
        str(sample_file),
    ]
    # onnxruntime 可能尚未安装；此处不阻断训练结果，只提示用户按 README 手动安装后补跑。
    if importlib.util.find_spec("onnxruntime") is None:
        print("[ModernTCN phase1] 缺少 onnxruntime，已跳过 PyTorch vs ONNXRuntime 检查。")
        return
    try:
        subprocess.run(check_cmd, check=True)
    except subprocess.CalledProcessError:
        print("[ModernTCN phase1] ONNXRuntime 检查未完成，请按 README 安装 onnx/onnxruntime 后补跑。")


if __name__ == "__main__":
    main()
