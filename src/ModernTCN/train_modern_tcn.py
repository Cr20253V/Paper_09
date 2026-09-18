"""训练 ModernTCN-small，并输出与 TCN/GRU baseline 对齐的测试指标。

使用方式：
    python ModernTCN/train_modern_tcn.py --seed 42

重要约束：
    1. 默认读取 data/tcn/ModernTCN_dataset_v4_industrial.mat。
    2. 不重新划分 split，不重新拟合 scaler。
    3. 多 seed 实验建议通过 results/modern_tcn/scripts 下的脚本统一启动。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader

from modern_tcn_data import AGVWindowDataset, class_weights, find_project_root, load_modern_tcn_dataset
from modern_tcn_lag_features import (
    PASSIVE22_FEATURE_NAMES,
    augment_split_by_metadata,
    augmented_feature_names,
    augmentation_block_stats,
    build_input_augmentation_metadata,
    effective_input_dim_from_metadata,
    fit_input_augmentation_metadata,
)
from modern_tcn_metrics import compute_metrics, metric_row, multitask_loss_components, seed42_gate, selection_score
from modern_tcn_model import (
    ModernTCNConfig,
    ModernTCNDualKernelConfig,
    ModernTCNFullConfig,
    ModernTCNGroupedConfig,
    ModernTCNModeThetaConfig,
    ModernTCNPhysicsGroupGateConfig,
    build_model_from_config,
    build_model_from_checkpoint_dict,
    normalize_model_family,
)


FULL_DEFAULT_DATASET = (
    Path("data")
    / "tcn"
    / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v4b_weakcombo_rebalanced_passive17_plus_all5.mat"
)

PLANTFIX_22D_DATASET = (
    Path("data")
    / "tcn"
    / "ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
)


TASK_NAMES = ("main", "turn", "theta")


class DynamicLossController(torch.nn.Module):
    """E1 loss-only controller. Fixed mode preserves the existing loss exactly."""

    def __init__(
        self,
        mode: str,
        gradnorm_alpha: float = 1.5,
        s_range: float = 0.25,
        s_prior_lambda: float = 0.0,
    ) -> None:
        super().__init__()
        self.mode = _normalize_loss_mode(mode)
        self.gradnorm_alpha = float(gradnorm_alpha)
        self.s_range = float(s_range)
        self.s_prior_lambda = float(s_prior_lambda)
        self.gradnorm_initial_losses: Optional[torch.Tensor] = None
        self.last_gradnorm_stats: Dict[str, float] = {}
        if self.mode == "uncertainty_weighting":
            self.log_vars = torch.nn.Parameter(torch.zeros(3, dtype=torch.float32))
        elif self.mode == "bounded_uncertainty":
            self.raw_s = torch.nn.Parameter(torch.zeros(3, dtype=torch.float32))
        elif self.mode == "gradnorm":
            self.log_task_weights = torch.nn.Parameter(torch.zeros(3, dtype=torch.float32))

    def has_parameters(self) -> bool:
        return any(True for _ in self.parameters())

    def extra_state(self) -> Dict[str, object]:
        state: Dict[str, object] = {"loss_mode": self.mode, "gradnorm_alpha": self.gradnorm_alpha}
        if self.mode == "uncertainty_weighting":
            s = self.log_vars.detach().cpu()
            w = torch.exp(-self.log_vars.detach()).cpu()
            for idx, name in enumerate(TASK_NAMES):
                state[f"s_{name}"] = float(s[idx])
                state[f"weight_{name}"] = float(w[idx])
        elif self.mode == "bounded_uncertainty":
            s = self.bounded_s().detach().cpu()
            w = torch.exp(-self.bounded_s().detach()).cpu()
            raw = self.raw_s.detach().cpu()
            state["s_range"] = float(self.s_range)
            state["s_prior_lambda"] = float(self.s_prior_lambda)
            for idx, name in enumerate(TASK_NAMES):
                state[f"raw_s_{name}"] = float(raw[idx])
                state[f"s_{name}"] = float(s[idx])
                state[f"weight_{name}"] = float(w[idx])
        elif self.mode == "gradnorm":
            w = self.gradnorm_weights().detach().cpu()
            for idx, name in enumerate(TASK_NAMES):
                state[f"task_weight_{name}"] = float(w[idx])
            if self.gradnorm_initial_losses is not None:
                init = self.gradnorm_initial_losses.detach().cpu()
                for idx, name in enumerate(TASK_NAMES):
                    state[f"initial_loss_{name}"] = float(init[idx])
        return state

    def bounded_s(self) -> torch.Tensor:
        if self.mode != "bounded_uncertainty":
            raise RuntimeError("bounded_s called outside bounded_uncertainty mode")
        return self.s_range * torch.tanh(self.raw_s)

    def gradnorm_weights(self) -> torch.Tensor:
        if self.mode != "gradnorm":
            raise RuntimeError("gradnorm_weights called outside gradnorm mode")
        return 3.0 * torch.softmax(self.log_task_weights, dim=0)

    def compute_loss(
        self,
        components: Dict[str, torch.Tensor],
        model: torch.nn.Module,
        compute_gradnorm_aux: bool = True,
    ) -> Tuple[torch.Tensor, Dict[str, object], Optional[torch.Tensor]]:
        task_losses = torch.stack(
            [
                components["loss_main_bundle"],
                components["loss_turn_bundle"],
                components["loss_theta_bundle"],
            ]
        )
        if self.mode == "fixed":
            return components["loss_total"], {"loss_mode": self.mode}, None
        if self.mode == "uncertainty_weighting":
            weights = torch.exp(-self.log_vars)
            loss = (weights * task_losses + self.log_vars).sum()
            stats = {"loss_mode": self.mode}
            for idx, name in enumerate(TASK_NAMES):
                stats[f"s_{name}"] = float(self.log_vars[idx].detach().cpu())
                stats[f"weight_{name}"] = float(weights[idx].detach().cpu())
            return loss, stats, None
        if self.mode == "bounded_uncertainty":
            s = self.bounded_s()
            weights = torch.exp(-s)
            prior = self.s_prior_lambda * torch.sum(s.pow(2))
            loss = (weights * task_losses + s).sum() + prior
            stats = {"loss_mode": self.mode, "bounded_s_prior": float(prior.detach().cpu())}
            raw_s = self.raw_s.detach().cpu()
            for idx, name in enumerate(TASK_NAMES):
                stats[f"raw_s_{name}"] = float(raw_s[idx])
                stats[f"s_{name}"] = float(s[idx].detach().cpu())
                stats[f"weight_{name}"] = float(weights[idx].detach().cpu())
            return loss, stats, None
        if self.mode == "gradnorm":
            return self._gradnorm_loss(task_losses, model, compute_aux=compute_gradnorm_aux)
        raise ValueError(f"unknown loss mode: {self.mode}")

    def _gradnorm_loss(
        self,
        task_losses: torch.Tensor,
        model: torch.nn.Module,
        compute_aux: bool = True,
    ) -> Tuple[torch.Tensor, Dict[str, object], Optional[torch.Tensor]]:
        if self.gradnorm_initial_losses is None:
            self.gradnorm_initial_losses = task_losses.detach().clamp_min(1e-8)
        weights = self.gradnorm_weights()
        weighted_losses = weights * task_losses
        total = (weights.detach() * task_losses).sum()
        stats = {"loss_mode": self.mode, "gradnorm_unstable": False}
        for idx, name in enumerate(TASK_NAMES):
            stats[f"task_weight_{name}"] = float(weights[idx].detach().cpu())
            stats[f"initial_loss_{name}"] = float(self.gradnorm_initial_losses[idx].detach().cpu())
        if not compute_aux:
            for name in TASK_NAMES:
                stats[f"grad_norm_{name}"] = self.last_gradnorm_stats.get(f"grad_norm_{name}", float("nan"))
            stats["gradnorm_loss"] = self.last_gradnorm_stats.get("gradnorm_loss", float("nan"))
            return total, stats, None
        shared_params = _gradnorm_shared_parameters(model)
        grad_norms: List[torch.Tensor] = []
        for loss_i in weighted_losses:
            grads = torch.autograd.grad(
                loss_i,
                shared_params,
                retain_graph=True,
                create_graph=True,
                allow_unused=True,
            )
            grad_norms.append(_grad_norm_from_tensors(grads, loss_i))
        grad_norm_tensor = torch.stack(grad_norms)
        with torch.no_grad():
            relative_losses = task_losses.detach().clamp_min(1e-8) / self.gradnorm_initial_losses.to(task_losses.device)
            inverse_train_rate = relative_losses / relative_losses.mean().clamp_min(1e-8)
            target = grad_norm_tensor.detach().mean() * torch.pow(inverse_train_rate, self.gradnorm_alpha)
        gradnorm_loss = torch.nn.functional.l1_loss(grad_norm_tensor, target, reduction="sum")
        unstable = bool(
            (not torch.isfinite(total.detach()))
            or (not torch.isfinite(gradnorm_loss.detach()))
            or (not torch.isfinite(grad_norm_tensor.detach()).all())
            or (not torch.isfinite(weights.detach()).all())
        )
        stats["gradnorm_loss"] = float(gradnorm_loss.detach().cpu())
        stats["gradnorm_unstable"] = unstable
        for idx, name in enumerate(TASK_NAMES):
            stats[f"grad_norm_{name}"] = float(grad_norm_tensor[idx].detach().cpu())
        self.last_gradnorm_stats = {
            "gradnorm_loss": float(stats["gradnorm_loss"]),
            "grad_norm_main": float(stats["grad_norm_main"]),
            "grad_norm_turn": float(stats["grad_norm_turn"]),
            "grad_norm_theta": float(stats["grad_norm_theta"]),
        }
        return total, stats, gradnorm_loss


def _normalize_loss_mode(mode: object) -> str:
    text = str(mode or "fixed").strip().lower()
    if text == "baseline":
        return "fixed"
    if text not in {"fixed", "uncertainty_weighting", "bounded_uncertainty", "gradnorm"}:
        raise ValueError(f"未知 loss_mode: {mode}")
    return text


def _gradnorm_shared_parameters(model: torch.nn.Module) -> List[torch.nn.Parameter]:
    if hasattr(model, "stem"):
        params = [p for p in model.stem.parameters() if p.requires_grad]
        if params:
            return params
    for param in model.parameters():
        if param.requires_grad:
            return [param]
    raise RuntimeError("GradNorm requires at least one trainable model parameter")


def _grad_norm_from_tensors(grads: Tuple[Optional[torch.Tensor], ...], reference: torch.Tensor) -> torch.Tensor:
    pieces = [g.reshape(-1) for g in grads if g is not None]
    if not pieces:
        return reference.new_zeros(())
    return torch.norm(torch.cat(pieces), p=2)


def _should_update_gradnorm(loss_controller: DynamicLossController, epoch: int, batch_idx: int, interval: int) -> bool:
    if loss_controller.mode != "gradnorm":
        return False
    if interval <= 0:
        return batch_idx == 1
    step_idx = (epoch - 1) * 1_000_000 + batch_idx
    return step_idx % interval == 1


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ModernTCN-small / ModernTCNFull 第一阶段训练脚本")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument(
        "--model-family",
        "--model_family",
        dest="model_family",
        type=str,
        default="small",
        choices=["small", "full", "small_gffn", "small_dualkernel", "small_physics_group_gate", "small_mode_theta"],
    )
    p.add_argument("--init-checkpoint", "--init_checkpoint", dest="init_checkpoint", type=str, default="")
    p.add_argument("--baseline-checkpoint", "--baseline_checkpoint", dest="baseline_checkpoint", type=str, default="")
    p.add_argument("--dataset-file", "--dataset_file", dest="dataset_file", type=str, default="")
    p.add_argument("--output-root", "--output_root", dest="output_root", type=str, default="")
    p.add_argument("--run-tag", "--run_tag", dest="run_tag", type=str, default="")
    p.add_argument("--no-overwrite", "--no_overwrite", dest="no_overwrite", action="store_true")
    p.add_argument(
        "--input-augment",
        "--input_augment",
        dest="input_augment",
        type=str,
        default="none",
        choices=["none", "delta_lag", "lag_stack", "delta_bank", "mixed_lag_delta", "physics_residual_8"],
        help="Optional Python-side input augmentation. Default none preserves the 22D dataset path.",
    )
    p.add_argument("--delta-lag", "--delta_lag", dest="delta_lag", type=int, default=1)
    p.add_argument("--delta-pad", "--delta_pad", dest="delta_pad", type=str, default="zero", choices=["zero"])
    p.add_argument("--lag-steps", "--lag_steps", dest="lag_steps", type=int, nargs="+", default=[1, 2, 4])
    p.add_argument("--lag-pad", "--lag_pad", dest="lag_pad", type=str, default="edge", choices=["edge"])
    p.add_argument("--delta-clip-abs", "--delta_clip_abs", dest="delta_clip_abs", type=float, default=5.0)
    p.add_argument(
        "--freeze-mode",
        "--freeze_mode",
        dest="freeze_mode",
        type=str,
        default="none",
        choices=["none", "trunk", "early_blocks"],
    )
    p.add_argument("--freeze-early-blocks", "--freeze_early_blocks", dest="freeze_early_blocks", type=int, default=3)
    p.add_argument(
        "--loss-mode",
        "--loss_mode",
        dest="loss_mode",
        type=str,
        default="fixed",
        choices=["fixed", "baseline", "uncertainty_weighting", "bounded_uncertainty", "gradnorm"],
        help="E1 loss-only mode. fixed/baseline exactly preserves the existing loss formula.",
    )
    p.add_argument(
        "--preserve-mode",
        "--preserve_mode",
        dest="preserve_mode",
        type=str,
        default="none",
        choices=["none", "baseline"],
    )
    p.add_argument("--lambda-preserve-main", "--lambda_preserve_main", dest="lambda_preserve_main", type=float, default=0.0)
    p.add_argument("--lambda-preserve-turn", "--lambda_preserve_turn", dest="lambda_preserve_turn", type=float, default=0.0)
    p.add_argument("--lambda-preserve-theta", "--lambda_preserve_theta", dest="lambda_preserve_theta", type=float, default=0.0)
    p.add_argument("--s-range", "--s_range", dest="s_range", type=float, default=0.25)
    p.add_argument("--lambda-s-prior", "--lambda_s_prior", dest="lambda_s_prior", type=float, default=0.01)
    p.add_argument("--gradnorm-alpha", "--gradnorm_alpha", dest="gradnorm_alpha", type=float, default=1.5)
    p.add_argument("--gradnorm-update-interval", "--gradnorm_update_interval", dest="gradnorm_update_interval", type=int, default=0)
    p.add_argument("--loss-weight-lr", "--loss_weight_lr", dest="loss_weight_lr", type=float, default=1e-3)
    p.add_argument("--epochs", type=int, default=120)
    p.add_argument("--batch-size", "--batch_size", dest="batch_size", type=int, default=256)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", "--weight_decay", dest="weight_decay", type=float, default=1e-4)
    p.add_argument("--patience", type=int, default=25)
    p.add_argument("--min-epochs", type=int, default=30)
    p.add_argument("--channels", type=int, default=64)
    p.add_argument("--dmodel", type=int, default=None)
    p.add_argument("--blocks", type=int, default=5)
    p.add_argument("--kernel-size", "--kernel_size", dest="kernel_size", type=int, default=31)
    p.add_argument("--patch-size", "--patch_size", dest="patch_size", type=int, default=None)
    p.add_argument("--patch-stride", "--patch_stride", dest="patch_stride", type=int, default=None)
    p.add_argument("--dims", type=str, default=None)
    p.add_argument("--stage-blocks", "--stage_blocks", dest="stage_blocks", type=str, default=None)
    p.add_argument("--large-kernels", "--large_kernels", dest="large_kernels", type=str, default=None)
    p.add_argument("--small-kernels", "--small_kernels", dest="small_kernels", type=str, default=None)
    p.add_argument("--large-kernel", "--large_kernel", dest="large_kernel", type=int, default=None)
    p.add_argument("--small-kernel", "--small_kernel", dest="small_kernel", type=int, default=None)
    p.add_argument("--dual-branch-scale", "--dual_branch_scale", dest="dual_branch_scale", type=float, default=None)
    p.add_argument(
        "--small-branch-init",
        "--small_branch_init",
        dest="small_branch_init",
        type=str,
        default=None,
        choices=["default", "zero"],
    )
    p.add_argument(
        "--temporal-padding",
        "--temporal_padding",
        dest="temporal_padding",
        type=str,
        default="same",
        choices=["same", "causal"],
        help="Temporal convolution padding mode. 默认 same，causal 仅用于因果消融实验。",
    )
    p.add_argument("--dropout", type=float, default=0.15)
    p.add_argument("--ffn-ratio", "--ffn_ratio", dest="ffn_ratio", type=int, default=None)
    p.add_argument("--layer-scale-init", "--layer_scale_init", dest="layer_scale_init", type=float, default=None)
    p.add_argument("--branch-channels", "--branch_channels", dest="branch_channels", type=int, default=None)
    p.add_argument("--branch-kernel", "--branch_kernel", dest="branch_kernel", type=int, default=None)
    p.add_argument("--alpha-init", "--alpha_init", dest="alpha_init", type=float, default=None)
    p.add_argument("--gate-hidden", "--gate_hidden", dest="gate_hidden", type=int, default=None)
    p.add_argument("--physics-group-spec", "--physics_group_spec", dest="physics_group_spec", type=str, default=None)
    p.add_argument("--physics-group-names", "--physics_group_names", dest="physics_group_names", type=str, default=None)
    p.add_argument("--physics-group-indices", "--physics_group_indices", dest="physics_group_indices", type=str, default=None)
    p.add_argument("--theta-gate-detach", "--theta_gate_detach", dest="theta_gate_detach", action="store_true", default=None)
    p.add_argument("--no-theta-gate-detach", "--no_theta_gate_detach", dest="theta_gate_detach", action="store_false")
    p.add_argument("--flat-theta-reg-lambda", "--flat_theta_reg_lambda", dest="flat_theta_reg_lambda", type=float, default=None)
    p.add_argument("--theta-expert-hidden", "--theta_expert_hidden", dest="theta_expert_hidden", type=int, default=None)
    p.add_argument("--command-dropout-prob", "--command_dropout_prob", dest="command_dropout_prob", type=float, default=0.0)
    p.add_argument("--command-dropout-start-index", "--command_dropout_start_index", dest="command_dropout_start_index", type=int, default=-1)
    p.add_argument("--command-dropout-feature-count", "--command_dropout_feature_count", dest="command_dropout_feature_count", type=int, default=0)
    p.add_argument(
        "--command-dropout-mode",
        "--command_dropout_mode",
        dest="command_dropout_mode",
        type=str,
        default="window_block",
        choices=["window_block", "time_block", "channel_block"],
        help="训练期命令特征 dropout。只作用于 train batch，验证/测试/导出不启用。",
    )
    p.add_argument("--turn-head-source", "--turn_head_source", dest="turn_head_source", type=str, default="full", choices=["full", "inputstats", "kinematic_stats"])
    p.add_argument("--lambda-turn", type=float, default=0.05)
    p.add_argument("--lambda-theta", type=float, default=0.35)
    p.add_argument("--lambda-theta-flat", type=float, default=0.20)
    p.add_argument(
        "--theta-flat-loss-mode",
        type=str,
        default="near_zero",
        choices=["near_zero", "true_zero", "near_flat", "main_flat", "none"],
    )
    p.add_argument("--theta-flat-zero-tol-deg", type=float, default=0.3)
    p.add_argument("--lambda-theta-near-flat", type=float, default=0.0)
    p.add_argument("--theta-near-flat-deg", type=float, default=0.5)
    p.add_argument("--lambda-theta-error-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-near-flat-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-true-zero-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-active-excess", type=float, default=0.0)
    p.add_argument("--lambda-theta-small-neg", type=float, default=0.0)
    p.add_argument("--lambda-theta-small-neg-excess", type=float, default=0.0)
    p.add_argument("--lambda-turn-release", type=float, default=0.0)
    p.add_argument("--lambda-false-turn-straight", type=float, default=0.0)
    p.add_argument("--lambda-transition-focal", "--lambda_transition_focal", dest="lambda_transition_focal", type=float, default=0.0)
    p.add_argument("--lambda-stall-focal", "--lambda_stall_focal", dest="lambda_stall_focal", type=float, default=0.0)
    p.add_argument("--lambda-theta-smooth", "--lambda_theta_smooth", dest="lambda_theta_smooth", type=float, default=0.0)
    p.add_argument("--focal-gamma", "--focal_gamma", dest="focal_gamma", type=float, default=2.0)
    p.add_argument(
        "--theta-smooth-mode",
        "--theta_smooth_mode",
        dest="theta_smooth_mode",
        type=str,
        default="off",
        choices=["off", "none", "disabled"],
        help="E2 theta smoothness is disabled unless a future dataset exposes reliable adjacent window order.",
    )
    p.add_argument("--theta-excess-target-deg", type=float, default=1.0)
    p.add_argument("--theta-flat-excess-target-deg", type=float, default=0.5)
    p.add_argument("--theta-small-neg-min-deg", type=float, default=-4.0)
    p.add_argument("--theta-small-neg-max-deg", type=float, default=-2.0)
    p.add_argument("--theta-gate-mode", type=str, default="none", choices=["none", "main_slope_prob"])
    p.add_argument("--theta-gate-power", type=float, default=1.0)
    p.add_argument("--theta-gate-floor", type=float, default=0.0)
    p.add_argument("--theta-neg-weight", type=float, default=1.0)
    p.add_argument("--theta-pos-weight", type=float, default=1.0)
    p.add_argument("--main-class-multipliers", "--main_class_multipliers", dest="main_class_multipliers", type=float, nargs=3, default=None)
    p.add_argument("--turn-class-weight-method", "--turn_class_weight_method", dest="turn_class_weight_method", type=str, default=None, choices=["none", "inverse", "sqrt_inverse"])
    p.add_argument("--main-class-weight-method", "--main_class_weight_method", dest="main_class_weight_method", type=str, default=None, choices=["none", "inverse", "sqrt_inverse"])
    p.add_argument("--main-neg-slope-weight", "--main_neg_slope_weight", dest="main_neg_slope_weight", type=float, default=None)
    p.add_argument("--main-pos-slope-weight", "--main_pos_slope_weight", dest="main_pos_slope_weight", type=float, default=None)
    p.add_argument("--turn-transition-weight", type=float, default=1.0)
    p.add_argument("--turn-class-multipliers", type=float, nargs=3, default=[1.00, 1.10, 1.00])
    p.add_argument("--select-turn-weight", type=float, default=0.30)
    p.add_argument("--select-turn-transition-weight", type=float, default=1.00)
    p.add_argument("--select-turn-transition-target", type=float, default=0.75)
    p.add_argument("--select-turn-left-weight", type=float, default=0.00)
    p.add_argument("--select-turn-left-target", type=float, default=0.80)
    p.add_argument("--select-turn-lr-weight", type=float, default=0.00)
    p.add_argument("--select-turn-lr-target", type=float, default=0.80)
    p.add_argument("--select-stall-weight", "--select_stall_weight", dest="select_stall_weight", type=float, default=0.0)
    p.add_argument("--select-stall-target", "--select_stall_target", dest="select_stall_target", type=float, default=0.70)
    p.add_argument("--select-theta-weight", type=float, default=0.15)
    p.add_argument("--select-theta-ref-deg", type=float, default=5.0)
    p.add_argument("--select-theta-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-flat-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-flat-peak-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-peak-target-deg", type=float, default=3.0)
    p.add_argument("--select-theta-near-flat-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-near-flat-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-true-zero-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-true-zero-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-extreme-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-extreme-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-edge-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-edge-p95-target-deg", type=float, default=1.2)
    p.add_argument("--select-theta-small-nonzero-p95-weight", type=float, default=0.0)
    p.add_argument("--select-theta-small-nonzero-p95-target-deg", type=float, default=1.0)
    p.add_argument("--select-theta-flat-bias-weight", type=float, default=0.0)
    p.add_argument("--select-theta-flat-bias-target-deg", type=float, default=0.2)
    p.add_argument("--device", type=str, default="auto", choices=["auto", "cpu", "cuda"])
    p.add_argument("--num-workers", "--num_workers", dest="num_workers", type=int, default=0)
    p.add_argument("--limit-train", "--limit_train", dest="limit_train", type=int, default=0, help="仅用于 smoke test，正式实验必须为 0。")
    p.add_argument("--limit-val", "--limit_val", dest="limit_val", type=int, default=0, help="仅用于 smoke test，正式实验必须为 0。")
    p.add_argument("--limit-test", "--limit_test", dest="limit_test", type=int, default=0, help="仅用于 smoke test，正式实验必须为 0。")
    p.add_argument("--dry-run", "--dry_run", dest="dry_run", action="store_true", help="只读取数据并跑一次前向，不保存训练结果。")
    return p.parse_args()


def main() -> Dict[str, object]:
    args = parse_args()
    return train_one_seed(args)


def train_one_seed(args: argparse.Namespace) -> Dict[str, object]:
    root = find_project_root()
    model_family = normalize_model_family(getattr(args, "model_family", "small"))
    run_tag = getattr(args, "run_tag", "") or _default_run_tag(model_family, args.seed)
    output_root = _resolve_output_root(root, getattr(args, "output_root", ""), model_family)
    out_dir = output_root / run_tag
    dataset_file = _resolve_dataset_file(root, getattr(args, "dataset_file", ""), model_family)

    if getattr(args, "no_overwrite", False) and out_dir.exists() and any(out_dir.iterdir()):
        raise FileExistsError(f"--no-overwrite enabled and output directory already exists: {out_dir}")

    _set_seed(args.seed)
    device = _select_device(getattr(args, "device", "auto"))
    data = load_modern_tcn_dataset(
        dataset_file=dataset_file,
        limit_train=getattr(args, "limit_train", 0),
        limit_val=getattr(args, "limit_val", 0),
        limit_test=getattr(args, "limit_test", 0),
    )
    train_split = data["train"]
    val_split = data["val"]
    test_split = data["test"]
    contract = data["contract"]
    raw_feat_names = list(data["feat_names"])
    input_augmentation = _build_input_augmentation_metadata(args, contract, raw_feat_names)
    input_augmentation = fit_input_augmentation_metadata(input_augmentation, train_split.X, data["scaler"])
    if input_augmentation["input_augment"] != "none":
        train_split = augment_split_by_metadata(train_split, input_augmentation)
        val_split = augment_split_by_metadata(val_split, input_augmentation)
        test_split = augment_split_by_metadata(test_split, input_augmentation)
        active_feat_names = augmented_feature_names(raw_feat_names, input_augmentation)
        input_augmentation["feature_names"] = active_feat_names
        input_augmentation["split_augment_stats"] = {
            "train": augmentation_block_stats(train_split, input_augmentation["raw_input_dim"]),
            "val": augmentation_block_stats(val_split, input_augmentation["raw_input_dim"]),
            "test": augmentation_block_stats(test_split, input_augmentation["raw_input_dim"]),
        }
    else:
        active_feat_names = raw_feat_names
        input_augmentation["feature_names"] = active_feat_names

    cfg = _build_config(args, contract, model_family)
    model = build_model_from_config(cfg, model_family).to(device)
    init_state: Dict[str, object] = {}
    init_checkpoint = getattr(args, "init_checkpoint", "")
    baseline_checkpoint = getattr(args, "baseline_checkpoint", "")
    if init_checkpoint:
        init_state.update(_apply_init_checkpoint(model, init_checkpoint, model_family))
    loss_mode = _normalize_loss_mode(getattr(args, "loss_mode", "fixed"))
    loss_controller = DynamicLossController(
        loss_mode,
        getattr(args, "gradnorm_alpha", 1.5),
        s_range=getattr(args, "s_range", 0.25),
        s_prior_lambda=getattr(args, "lambda_s_prior", 0.01),
    ).to(device)
    frozen_components = _freeze_model_for_mode(model, getattr(args, "freeze_mode", "none"), getattr(args, "freeze_early_blocks", 3))
    if baseline_checkpoint:
        _load_checkpoint_for_init(Path(baseline_checkpoint))

    # smoke test 只验证数据契约和模型维度，不写任何模型文件。
    if getattr(args, "dry_run", False):
        xb = torch.from_numpy(train_split.X[:4]).float().to(device)
        with torch.no_grad():
            outputs = model(xb)
        print(f"[ModernTCN {model_family} dry-run] 数据和模型前向检查通过")
        print(f"  X: {tuple(xb.shape)}")
        print(f"  logits_main/logits_turn/theta: {[tuple(o.shape) for o in outputs]}")
        return {"status": "dry_run_ok"}

    out_dir.mkdir(parents=True, exist_ok=True)
    file_prefix = _file_prefix(model_family, args.seed)
    checkpoint_file = out_dir / f"{file_prefix}.pt"
    summary_csv = out_dir / f"{file_prefix}_summary.csv"
    history_csv = out_dir / f"{file_prefix}_history.csv"
    report_file = out_dir / _report_file_name(model_family)
    config_json = out_dir / "config.json"
    config_md = out_dir / "config.md"
    git_hash_file = out_dir / "git_hash.txt"
    contract_copy_file = out_dir / "dataset_contract_copy.json"
    feature_names_file = out_dir / "feature_names.txt"
    train_log_file = out_dir / "train_log.txt"
    metrics_val_csv = out_dir / "metrics_val.csv"
    metrics_test_csv = out_dir / "metrics_test.csv"

    train_loader = DataLoader(
        AGVWindowDataset(train_split),
        batch_size=getattr(args, "batch_size", 256),
        shuffle=True,
        num_workers=getattr(args, "num_workers", 0),
        pin_memory=(device.type == "cuda"),
    )
    val_loader = DataLoader(AGVWindowDataset(val_split), batch_size=getattr(args, "batch_size", 256), shuffle=False, num_workers=0)
    test_loader = DataLoader(AGVWindowDataset(test_split), batch_size=getattr(args, "batch_size", 256), shuffle=False, num_workers=0)

    class_w_main = class_weights(
        train_split.y_main,
        3,
        cfg.main_class_weight_method,
        list(cfg.main_class_multipliers),
    ).to(device)
    class_w_turn = class_weights(
        train_split.y_turn,
        3,
        cfg.turn_class_weight_method,
        list(cfg.turn_class_multipliers),
    ).to(device)

    baseline_snapshot: Dict[str, Any] = {}
    preserve_model = None
    baseline_val_snapshot: Dict[str, Any] = {}
    if baseline_checkpoint:
        baseline_ckpt = _load_checkpoint_for_init(Path(baseline_checkpoint))
        preserve_model = build_model_from_checkpoint_dict(baseline_ckpt).to(device)
        preserve_model.eval()
        if str(getattr(args, "preserve_mode", "none") or "none").lower() == "baseline":
            with torch.no_grad():
                b_loss, b_logits_main, b_logits_turn, b_theta, _b_parts = _predict_full(
                    preserve_model, val_loader, val_split, device, class_w_main, class_w_turn, cfg, None
                )
            baseline_val_snapshot = {
                "loss": b_loss,
                "logits_main": torch.from_numpy(b_logits_main),
                "logits_turn": torch.from_numpy(b_logits_turn),
                "theta_hat": torch.from_numpy(b_theta),
            }
        baseline_snapshot = {
            "baseline_checkpoint": str(Path(baseline_checkpoint)),
            "baseline_family": normalize_model_family(baseline_ckpt.get("model_family", "small")),
        }

    runtime_state = {
        "freeze_mode": getattr(args, "freeze_mode", "none"),
        "freeze_early_blocks": getattr(args, "freeze_early_blocks", 3),
        "preserve_mode": getattr(args, "preserve_mode", "none"),
        "lambda_preserve_main": getattr(args, "lambda_preserve_main", 0.0),
        "lambda_preserve_turn": getattr(args, "lambda_preserve_turn", 0.0),
        "lambda_preserve_theta": getattr(args, "lambda_preserve_theta", 0.0),
        "s_range": getattr(args, "s_range", 0.25),
        "lambda_s_prior": getattr(args, "lambda_s_prior", 0.01),
    }

    trainable_params = _selected_parameters(model)
    if not trainable_params:
        raise RuntimeError("no trainable parameters selected")
    opt = torch.optim.AdamW(trainable_params, lr=getattr(args, "lr", 1e-3), weight_decay=getattr(args, "weight_decay", 1e-4))
    loss_opt = (
        torch.optim.AdamW(loss_controller.parameters(), lr=getattr(args, "loss_weight_lr", 1e-3), weight_decay=0.0)
        if loss_controller.has_parameters()
        else None
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(getattr(args, "epochs", 120), 1))

    print(f"[ModernTCN {model_family}] 第一阶段训练开始")
    print(f"  seed={args.seed}, device={device}, out={out_dir}")
    print(f"  dataset={contract.dataset_file}")
    print(f"  train/val/test={len(train_split.X)}/{len(val_split.X)}/{len(test_split.X)}")
    print(
        f"  input_augment={input_augmentation['input_augment']}, "
        f"raw_input_dim={input_augmentation['raw_input_dim']}, "
        f"model_input_dim={cfg.input_dim}"
    )
    print(f"  model_family={model_family}")
    print(f"  loss_mode={loss_controller.mode}")
    print(f"  freeze_mode={getattr(args, 'freeze_mode', 'none')}")
    print(f"  trainable_params={sum(p.numel() for p in trainable_params)}")
    if init_state:
        print(f"  init_checkpoint={init_state.get('init_checkpoint', '')}")
    if baseline_checkpoint:
        print(f"  baseline_checkpoint={baseline_checkpoint}")
    if model_family == "full":
        print(
            f"  full patch={cfg.patch_size}/{cfg.patch_stride}, dims={cfg.dims}, "
            f"stage_blocks={cfg.stage_blocks}, large_kernels={cfg.large_kernels}"
        )
    elif model_family == "small_gffn":
        print(
            f"  grouped dmodel={cfg.dmodel}, blocks={cfg.blocks}, kernel={cfg.kernel_size}, "
            f"ffn_ratio={cfg.ffn_ratio}, layer_scale_init={cfg.layer_scale_init:g}"
        )
    elif model_family == "small_dualkernel":
        print(
            f"  dual-kernel channels={cfg.channels}, blocks={cfg.blocks}, large={cfg.large_kernel}, "
            f"small={cfg.small_kernel}, branch_scale={cfg.dual_branch_scale:g}, "
            f"small_branch_init={cfg.small_branch_init}, layer_scale_init={cfg.layer_scale_init:g}"
        )
    elif model_family == "small_mode_theta":
        print(
            f"  mode-theta channels={cfg.channels}, blocks={cfg.blocks}, kernel={cfg.kernel_size}, "
            f"theta_gate_detach={cfg.theta_gate_detach}, flat_theta_reg_lambda={cfg.flat_theta_reg_lambda:g}, "
            f"theta_expert_hidden={cfg.theta_expert_hidden}"
        )
    else:
        print(
            f"  model channels={cfg.channels}, blocks={cfg.blocks}, kernel={cfg.kernel_size}, "
            f"temporal_padding={cfg.temporal_padding}"
        )
    if cfg.command_dropout_prob > 0:
        print(
            "  command_dropout="
            f"prob={cfg.command_dropout_prob:g}, start={cfg.command_dropout_start_index}, "
            f"count={cfg.command_dropout_feature_count}, mode={cfg.command_dropout_mode}"
        )

    best_score = math.inf
    best_epoch = 0
    best_state = None
    best_val_metrics: Dict[str, object] = {}
    patience_count = 0
    history_rows = []
    t0 = time.time()

    if getattr(args, "epochs", 120) <= 0:
        with torch.no_grad():
            test_loss, logits_main, logits_turn, theta_hat, test_parts = _predict_full(
                model, test_loader, test_split, device, class_w_main, class_w_turn, cfg, loss_controller
            )
        test_metrics = compute_metrics(logits_main, logits_turn, theta_hat, test_split, test_loss)
        test_metrics.update(test_parts)
        best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        best_val_metrics = dict(test_metrics)
        best_epoch = 0
        best_score = selection_score(test_metrics, cfg)
        history_rows = []
    else:
        for epoch in range(1, getattr(args, "epochs", 120) + 1):
            train_stats = _train_epoch(
                model,
                train_loader,
                opt,
                loss_opt,
                loss_controller,
                preserve_model,
                epoch,
                device,
                class_w_main,
                class_w_turn,
                cfg,
                getattr(args, "gradnorm_update_interval", 0),
            )
            if bool(train_stats.get("gradnorm_unstable", False)):
                raise FloatingPointError(f"GradNorm unstable at epoch {epoch}: {train_stats}")
            scheduler.step()
            val_loss, val_logits_main, val_logits_turn, val_theta, val_parts = _predict_full(
                model, val_loader, val_split, device, class_w_main, class_w_turn, cfg, loss_controller
            )
            val_metrics = compute_metrics(val_logits_main, val_logits_turn, val_theta, val_split, val_loss)
            val_metrics.update(val_parts)
            if getattr(args, "preserve_mode", "none") == "baseline" and baseline_checkpoint and baseline_val_snapshot:
                preserve = _preservation_loss(
                    {
                        "logits_main": val_logits_main,
                        "logits_turn": val_logits_turn,
                        "theta_hat": val_theta,
                    },
                    baseline_val_snapshot,
                    {
                        "y_main": torch.from_numpy(val_split.y_main),
                        "y_turn": torch.from_numpy(val_split.y_turn),
                        "y_theta": torch.from_numpy(val_split.y_theta),
                        "mask_theta": torch.from_numpy(val_split.mask_theta),
                    },
                    cfg,
                )
                val_metrics["preserve_loss"] = float(preserve.detach().cpu()) if torch.is_tensor(preserve) else float(preserve)
            score = selection_score(val_metrics, cfg)
            model_state = _model_extra_state(model)
            loop_loss_state = {**loss_controller.extra_state(), **runtime_state}
            history_rows.append(
                _history_row(
                    epoch,
                    opt.param_groups[0]["lr"],
                    train_stats,
                    val_metrics,
                    score,
                    loop_loss_state,
                    model_state,
                )
            )

            if score < best_score:
                best_score = score
                best_epoch = epoch
                best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
                best_val_metrics = dict(val_metrics)
                patience_count = 0
            else:
                patience_count += 1

            if epoch == 1 or epoch % 5 == 0 or epoch == getattr(args, "epochs", 120):
                print(
                    f"  epoch {epoch:03d} | train={train_stats['loss_optimized']:.4f} val={val_metrics['loss_total']:.4f} "
                    f"main={val_metrics['acc_main']:.4f} turn={val_metrics['acc_turn']:.4f} "
                    f"turnL={val_metrics['turn_left_recall']:.4f} turnT={val_metrics['acc_turn_transition']:.4f} "
                    f"theta={val_metrics['theta_mae_deg']:.4f} score={score:.4f}"
                )

            if epoch >= getattr(args, "min_epochs", 30) and patience_count >= getattr(args, "patience", 25):
                print(f"[ModernTCN] 早停：epoch={epoch}, best_epoch={best_epoch}")
                break

    if best_state is None:
        raise RuntimeError("训练未产生有效 checkpoint。")

    model.load_state_dict(best_state)
    test_loss, logits_main, logits_turn, theta_hat, test_parts = _predict_full(
        model, test_loader, test_split, device, class_w_main, class_w_turn, cfg, loss_controller
    )
    test_metrics = compute_metrics(logits_main, logits_turn, theta_hat, test_split, test_loss)
    test_metrics.update(test_parts)
    e3_val_gate_stats = _collect_gate_statistics(model, val_loader, val_split, device, prefix="val")
    e3_test_gate_stats = _collect_gate_statistics(model, test_loader, test_split, device, prefix="test")
    if e3_val_gate_stats:
        best_val_metrics.update(e3_val_gate_stats)
    if e3_test_gate_stats:
        test_metrics.update(e3_test_gate_stats)
    train_seconds = time.time() - t0

    dynamic_loss_state = loss_controller.extra_state()
    model_extra_state = _model_extra_state(model)
    loss_state_for_history = {**dynamic_loss_state, **runtime_state}
    torch.save(
        {
            "model_family": model_family,
            "loss_mode": loss_controller.mode,
            "model_state": best_state,
            "loss_controller_state": loss_controller.state_dict(),
            "dynamic_loss_state": dynamic_loss_state,
            "model_extra_state": model_extra_state,
            "model_config": cfg.to_dict(),
            "seed": args.seed,
            "best_epoch": best_epoch,
            "best_val_score": best_score,
            "best_val_metrics": best_val_metrics,
            "test_metrics": test_metrics,
            "contract": contract.__dict__,
            "input_augmentation": input_augmentation,
            "feat_names": active_feat_names,
            "raw_feat_names": raw_feat_names,
            "scaler": data["scaler"],
            "train_seconds": train_seconds,
        },
        checkpoint_file,
    )

    paths = {"checkpoint_file": str(checkpoint_file), "report_file": str(report_file)}
    row = metric_row(args.seed, best_epoch, test_metrics, paths)
    row["model"] = _model_label(model_family)
    _augment_row_with_model_state(row, model_extra_state, test_metrics)
    _write_csv(summary_csv, [row])
    _write_csv(history_csv, history_rows)
    val_row = metric_row(args.seed, best_epoch, best_val_metrics, paths)
    val_row["model"] = _model_label(model_family)
    _augment_row_with_model_state(val_row, model_extra_state, best_val_metrics)
    _write_csv(metrics_val_csv, [val_row])
    _write_csv(metrics_test_csv, [row])
    _write_run_metadata(
        root=root,
        out_dir=out_dir,
        args=args,
        cfg=cfg,
        contract=contract.__dict__,
        feat_names=active_feat_names,
        model_family=model_family,
        run_tag=run_tag,
        loss_state=loss_state_for_history,
        model_state=model_extra_state,
        input_augmentation=input_augmentation,
        files={
            "config_json": config_json,
            "config_md": config_md,
            "git_hash_file": git_hash_file,
            "contract_copy_file": contract_copy_file,
            "feature_names_file": feature_names_file,
            "train_log_file": train_log_file,
        },
    )
    _write_gate_statistics(out_dir, model_extra_state, best_val_metrics, test_metrics)
    _write_report(
        report_file,
        args,
        cfg,
        contract.__dict__,
        row,
        test_metrics,
        best_val_metrics,
        train_seconds,
        model_family,
        model_extra_state,
        input_augmentation,
    )

    print(f"[ModernTCN {model_family}] 训练完成")
    print(f"  checkpoint: {checkpoint_file}")
    print(f"  summary: {summary_csv}")
    print(f"  report: {report_file}")
    print(
        f"  test main={test_metrics['acc_main']:.4f}, turnT={test_metrics['acc_turn_transition']:.4f}, "
        f"turnL={test_metrics['turn_left_recall']:.4f}, theta={test_metrics['theta_mae_deg']:.4f}, flat={test_metrics['flat_recall']:.4f}, "
        f"slope={test_metrics['slope_recall']:.4f}"
    )

    if args.seed == 42:
        passed, failures = seed42_gate(test_metrics)
        print(f"  seed42 gate pass={int(passed)}")
        for msg in failures:
            print(f"    - {msg}")

    return {
        "checkpoint_file": str(checkpoint_file),
        "summary_csv": str(summary_csv),
        "report_file": str(report_file),
        "test_metrics": test_metrics,
        "best_epoch": best_epoch,
        "loss_mode": loss_controller.mode,
        "model_extra_state": model_extra_state,
        "runtime_state": runtime_state,
    }


def _default_run_tag(model_family: str, seed: int) -> str:
    if model_family == "full":
        return f"modern_tcn_full_v4b_seed{seed}"
    if model_family == "small_physics_group_gate":
        return f"pg_alpha0_seed{seed}"
    if model_family == "small_mode_theta":
        return f"mode_theta_detach_flatreg000_seed{seed}"
    if model_family == "small_dualkernel":
        return f"dual_k31_s5_seed{seed}"
    if model_family == "small_gffn":
        return f"gffn_d4_k31_seed{seed}"
    return f"modern_tcn_v4_industrial_seed{seed}"


def _result_dir_name(model_family: str) -> str:
    if model_family == "full":
        return "modern_tcn_full"
    if model_family == "small_dualkernel":
        return "modern_tcn_ablation/exp2_dual_kernel"
    if model_family == "small_gffn":
        return "modern_tcn_ablation/exp1_grouped_ffn"
    if model_family == "small_physics_group_gate":
        return "modern_tcn_sci_innovation/03_physics_group_gate"
    if model_family == "small_mode_theta":
        return "modern_tcn_sci_innovation/04_mode_conditioned_theta"
    return "modern_tcn"


def _file_prefix(model_family: str, seed: int) -> str:
    if model_family == "full":
        return f"modern_tcn_full_seed{seed}"
    if model_family == "small_dualkernel":
        return f"modern_tcn_dualkernel_seed{seed}"
    if model_family == "small_gffn":
        return f"modern_tcn_gffn_seed{seed}"
    if model_family == "small_physics_group_gate":
        return f"modern_tcn_pg_seed{seed}"
    if model_family == "small_mode_theta":
        return f"modern_tcn_mode_theta_seed{seed}"
    return f"modern_tcn_seed{seed}"


def _report_file_name(model_family: str) -> str:
    if model_family == "full":
        return "ModernTCNFull_train_report.md"
    if model_family == "small_dualkernel":
        return "ModernTCNDualKernel_train_report.md"
    if model_family == "small_gffn":
        return "ModernTCNGrouped_train_report.md"
    if model_family == "small_physics_group_gate":
        return "ModernTCNPhysicsGroupGate_train_report.md"
    if model_family == "small_mode_theta":
        return "ModernTCNModeTheta_train_report.md"
    return "ModernTCN_train_report.md"


def _model_label(model_family: str) -> str:
    if model_family == "small_gffn":
        return "ModernTCN-small-gffn"
    if model_family == "small_dualkernel":
        return "ModernTCN-small-dualkernel"
    if model_family == "small_physics_group_gate":
        return "PG-ModernTCN-small"
    if model_family == "small_mode_theta":
        return "ModernTCN-small-mode-theta"
    if model_family == "full":
        return "ModernTCNFull"
    return "ModernTCN-small"


def _resolve_output_root(root: Path, output_root_arg: str, model_family: str) -> Path:
    if output_root_arg:
        path = Path(output_root_arg)
        return path if path.is_absolute() else root / path
    return root / "results" / _result_dir_name(model_family)


def _resolve_dataset_file(root: Path, dataset_arg: str, model_family: str) -> Optional[Path]:
    if dataset_arg:
        path = Path(dataset_arg)
        return path if path.is_absolute() else root / path
    if model_family == "small_dualkernel":
        return root / PLANTFIX_22D_DATASET
    if model_family == "small_physics_group_gate":
        return root / PLANTFIX_22D_DATASET
    if model_family == "small_mode_theta":
        return root / PLANTFIX_22D_DATASET
    if model_family == "full":
        return root / FULL_DEFAULT_DATASET
    return None


def _arg(args: argparse.Namespace, name: str, default):
    value = getattr(args, name, default)
    return default if value is None else value


def _tuple_arg(args: argparse.Namespace, name: str, default: Tuple[int, ...]) -> Tuple[int, ...]:
    value = getattr(args, name, None)
    if value is None:
        return tuple(default)
    if isinstance(value, (tuple, list)):
        return tuple(int(x) for x in value)
    parts = [item.strip() for item in str(value).split(",") if item.strip()]
    if not parts:
        raise ValueError(f"{name} must contain at least one integer.")
    return tuple(int(item) for item in parts)


def _str_tuple_arg(args: argparse.Namespace, name: str, default: Tuple[str, ...]) -> Tuple[str, ...]:
    value = getattr(args, name, None)
    if value is None:
        return tuple(default)
    if isinstance(value, (tuple, list)):
        return tuple(str(x) for x in value)
    parts = [item.strip() for item in str(value).split(",") if item.strip()]
    if not parts:
        raise ValueError(f"{name} must contain at least one value.")
    return tuple(parts)


def _nested_int_tuple_arg(args: argparse.Namespace, name: str, default: Tuple[Tuple[int, ...], ...]) -> Tuple[Tuple[int, ...], ...]:
    value = getattr(args, name, None)
    if value is None:
        return tuple(tuple(int(i) for i in group) for group in default)
    if isinstance(value, (tuple, list)):
        return tuple(tuple(int(i) for i in group) for group in value)
    groups = []
    for group_text in str(value).split(";"):
        group_text = group_text.strip()
        if not group_text:
            continue
        groups.append(tuple(int(item.strip()) for item in group_text.split(",") if item.strip()))
    if not groups:
        raise ValueError(f"{name} must contain at least one index group.")
    return tuple(groups)


def _build_config(args: argparse.Namespace, contract, model_family: str) -> ModernTCNConfig:
    if model_family == "full":
        base = ModernTCNFullConfig()
    elif model_family == "small_dualkernel":
        base = ModernTCNDualKernelConfig()
    elif model_family == "small_gffn":
        base = ModernTCNGroupedConfig()
    elif model_family == "small_physics_group_gate":
        base = ModernTCNPhysicsGroupGateConfig()
    elif model_family == "small_mode_theta":
        base = ModernTCNModeThetaConfig()
    else:
        base = ModernTCNConfig()
    common = {
        "input_dim": _effective_input_dim(args, contract),
        "seq_len": contract.seq_len,
        "channels": _arg(args, "channels", base.channels),
        "blocks": _arg(args, "blocks", base.blocks),
        "kernel_size": _arg(args, "kernel_size", base.kernel_size),
        "temporal_padding": _arg(args, "temporal_padding", base.temporal_padding),
        "dropout": _arg(args, "dropout", base.dropout),
        "command_dropout_prob": _arg(args, "command_dropout_prob", base.command_dropout_prob),
        "command_dropout_start_index": _arg(
            args, "command_dropout_start_index", base.command_dropout_start_index
        ),
        "command_dropout_feature_count": _arg(
            args, "command_dropout_feature_count", base.command_dropout_feature_count
        ),
        "command_dropout_mode": _arg(args, "command_dropout_mode", base.command_dropout_mode),
        "turn_head_source": _arg(args, "turn_head_source", base.turn_head_source),
        "lambda_turn": _arg(args, "lambda_turn", base.lambda_turn),
        "lambda_theta": _arg(args, "lambda_theta", base.lambda_theta),
        "lambda_theta_flat": _arg(args, "lambda_theta_flat", base.lambda_theta_flat),
        "theta_flat_loss_mode": _arg(args, "theta_flat_loss_mode", base.theta_flat_loss_mode),
        "theta_flat_zero_tol_deg": _arg(args, "theta_flat_zero_tol_deg", base.theta_flat_zero_tol_deg),
        "lambda_theta_near_flat": _arg(args, "lambda_theta_near_flat", base.lambda_theta_near_flat),
        "theta_near_flat_deg": _arg(args, "theta_near_flat_deg", base.theta_near_flat_deg),
        "lambda_theta_error_excess": _arg(args, "lambda_theta_error_excess", base.lambda_theta_error_excess),
        "lambda_theta_flat_excess": _arg(args, "lambda_theta_flat_excess", base.lambda_theta_flat_excess),
        "lambda_theta_near_flat_excess": _arg(
            args, "lambda_theta_near_flat_excess", base.lambda_theta_near_flat_excess
        ),
        "lambda_theta_true_zero_excess": _arg(args, "lambda_theta_true_zero_excess", base.lambda_theta_true_zero_excess),
        "lambda_theta_active_excess": _arg(args, "lambda_theta_active_excess", base.lambda_theta_active_excess),
        "lambda_theta_small_neg": _arg(args, "lambda_theta_small_neg", base.lambda_theta_small_neg),
        "lambda_theta_small_neg_excess": _arg(args, "lambda_theta_small_neg_excess", base.lambda_theta_small_neg_excess),
        "lambda_turn_release": _arg(args, "lambda_turn_release", base.lambda_turn_release),
        "lambda_false_turn_straight": _arg(args, "lambda_false_turn_straight", base.lambda_false_turn_straight),
        "lambda_transition_focal": _arg(args, "lambda_transition_focal", base.lambda_transition_focal),
        "lambda_stall_focal": _arg(args, "lambda_stall_focal", base.lambda_stall_focal),
        "lambda_theta_smooth": _arg(args, "lambda_theta_smooth", base.lambda_theta_smooth),
        "focal_gamma": _arg(args, "focal_gamma", base.focal_gamma),
        "theta_smooth_mode": _arg(args, "theta_smooth_mode", base.theta_smooth_mode),
        "theta_excess_target_deg": _arg(args, "theta_excess_target_deg", base.theta_excess_target_deg),
        "theta_flat_excess_target_deg": _arg(args, "theta_flat_excess_target_deg", base.theta_flat_excess_target_deg),
        "theta_true_zero_tol_deg": _arg(args, "theta_true_zero_tol_deg", base.theta_true_zero_tol_deg),
        "theta_small_neg_min_deg": _arg(args, "theta_small_neg_min_deg", base.theta_small_neg_min_deg),
        "theta_small_neg_max_deg": _arg(args, "theta_small_neg_max_deg", base.theta_small_neg_max_deg),
        "theta_gate_mode": _arg(args, "theta_gate_mode", base.theta_gate_mode),
        "theta_gate_power": _arg(args, "theta_gate_power", base.theta_gate_power),
        "theta_gate_floor": _arg(args, "theta_gate_floor", base.theta_gate_floor),
        "main_class_multipliers": tuple(_arg(args, "main_class_multipliers", base.main_class_multipliers)),
        "turn_class_multipliers": tuple(_arg(args, "turn_class_multipliers", base.turn_class_multipliers)),
        "main_class_weight_method": _arg(args, "main_class_weight_method", base.main_class_weight_method),
        "turn_class_weight_method": _arg(args, "turn_class_weight_method", base.turn_class_weight_method),
        "main_neg_slope_weight": _arg(args, "main_neg_slope_weight", base.main_neg_slope_weight),
        "main_pos_slope_weight": _arg(args, "main_pos_slope_weight", base.main_pos_slope_weight),
        "theta_neg_weight": _arg(args, "theta_neg_weight", 1.0),
        "theta_pos_weight": _arg(args, "theta_pos_weight", base.theta_pos_weight),
        "turn_transition_weight": _arg(args, "turn_transition_weight", base.turn_transition_weight),
        "select_turn_weight": _arg(args, "select_turn_weight", base.select_turn_weight),
        "select_turn_transition_weight": _arg(
            args, "select_turn_transition_weight", base.select_turn_transition_weight
        ),
        "select_turn_transition_target": _arg(
            args, "select_turn_transition_target", base.select_turn_transition_target
        ),
        "select_turn_left_weight": _arg(args, "select_turn_left_weight", base.select_turn_left_weight),
        "select_turn_left_target": _arg(args, "select_turn_left_target", base.select_turn_left_target),
        "select_turn_lr_weight": _arg(args, "select_turn_lr_weight", base.select_turn_lr_weight),
        "select_turn_lr_target": _arg(args, "select_turn_lr_target", base.select_turn_lr_target),
        "select_stall_weight": _arg(args, "select_stall_weight", base.select_stall_weight),
        "select_stall_target": _arg(args, "select_stall_target", base.select_stall_target),
        "select_theta_weight": _arg(args, "select_theta_weight", base.select_theta_weight),
        "select_theta_ref_deg": _arg(args, "select_theta_ref_deg", base.select_theta_ref_deg),
        "select_theta_p95_weight": _arg(args, "select_theta_p95_weight", base.select_theta_p95_weight),
        "select_theta_p95_target_deg": _arg(args, "select_theta_p95_target_deg", base.select_theta_p95_target_deg),
        "select_theta_flat_p95_weight": _arg(
            args, "select_theta_flat_p95_weight", base.select_theta_flat_p95_weight
        ),
        "select_theta_flat_p95_target_deg": _arg(
            args, "select_theta_flat_p95_target_deg", base.select_theta_flat_p95_target_deg
        ),
        "select_theta_near_flat_p95_weight": _arg(
            args, "select_theta_near_flat_p95_weight", base.select_theta_near_flat_p95_weight
        ),
        "select_theta_near_flat_p95_target_deg": _arg(
            args, "select_theta_near_flat_p95_target_deg", base.select_theta_near_flat_p95_target_deg
        ),
        "select_theta_true_zero_p95_weight": _arg(
            args, "select_theta_true_zero_p95_weight", base.select_theta_true_zero_p95_weight
        ),
        "select_theta_true_zero_p95_target_deg": _arg(
            args, "select_theta_true_zero_p95_target_deg", base.select_theta_true_zero_p95_target_deg
        ),
        "select_theta_flat_peak_weight": _arg(
            args, "select_theta_flat_peak_weight", base.select_theta_flat_peak_weight
        ),
        "select_theta_flat_peak_target_deg": _arg(
            args, "select_theta_flat_peak_target_deg", base.select_theta_flat_peak_target_deg
        ),
        "select_theta_small_neg_p95_weight": _arg(
            args, "select_theta_small_neg_p95_weight", base.select_theta_small_neg_p95_weight
        ),
        "select_theta_small_neg_p95_target_deg": _arg(
            args, "select_theta_small_neg_p95_target_deg", base.select_theta_small_neg_p95_target_deg
        ),
        "select_theta_extreme_p95_weight": _arg(
            args, "select_theta_extreme_p95_weight", base.select_theta_extreme_p95_weight
        ),
        "select_theta_extreme_p95_target_deg": _arg(
            args, "select_theta_extreme_p95_target_deg", base.select_theta_extreme_p95_target_deg
        ),
        "select_theta_edge_p95_weight": _arg(args, "select_theta_edge_p95_weight", base.select_theta_edge_p95_weight),
        "select_theta_edge_p95_target_deg": _arg(
            args, "select_theta_edge_p95_target_deg", base.select_theta_edge_p95_target_deg
        ),
        "select_theta_small_nonzero_p95_weight": _arg(
            args, "select_theta_small_nonzero_p95_weight", base.select_theta_small_nonzero_p95_weight
        ),
        "select_theta_small_nonzero_p95_target_deg": _arg(
            args, "select_theta_small_nonzero_p95_target_deg", base.select_theta_small_nonzero_p95_target_deg
        ),
        "select_theta_flat_bias_weight": _arg(args, "select_theta_flat_bias_weight", base.select_theta_flat_bias_weight),
        "select_theta_flat_bias_target_deg": _arg(
            args, "select_theta_flat_bias_target_deg", base.select_theta_flat_bias_target_deg
        ),
        "freeze_mode": _arg(args, "freeze_mode", base.freeze_mode),
        "freeze_early_blocks": _arg(args, "freeze_early_blocks", base.freeze_early_blocks),
        "preserve_mode": _arg(args, "preserve_mode", base.preserve_mode),
        "lambda_preserve_main": _arg(args, "lambda_preserve_main", base.lambda_preserve_main),
        "lambda_preserve_turn": _arg(args, "lambda_preserve_turn", base.lambda_preserve_turn),
        "lambda_preserve_theta": _arg(args, "lambda_preserve_theta", base.lambda_preserve_theta),
        "s_range": _arg(args, "s_range", base.s_range),
        "lambda_s_prior": _arg(args, "lambda_s_prior", base.lambda_s_prior),
    }
    if model_family == "full":
        common.update(
            {
                "patch_size": _arg(args, "patch_size", base.patch_size),
                "patch_stride": _arg(args, "patch_stride", base.patch_stride),
                "dims": _tuple_arg(args, "dims", base.dims),
                "stage_blocks": _tuple_arg(args, "stage_blocks", base.stage_blocks),
                "large_kernels": _tuple_arg(args, "large_kernels", base.large_kernels),
                "small_kernels": _tuple_arg(args, "small_kernels", base.small_kernels),
                "ffn_ratio": _arg(args, "ffn_ratio", base.ffn_ratio),
                "layer_scale_init": _arg(args, "layer_scale_init", base.layer_scale_init),
            }
        )
        return ModernTCNFullConfig(**common)
    if model_family == "small_dualkernel":
        common.update(
            {
                "large_kernel": _arg(args, "large_kernel", base.large_kernel),
                "small_kernel": _arg(args, "small_kernel", base.small_kernel),
                "dual_branch_scale": _arg(args, "dual_branch_scale", base.dual_branch_scale),
                "small_branch_init": _arg(args, "small_branch_init", base.small_branch_init),
                "layer_scale_init": _arg(args, "layer_scale_init", base.layer_scale_init),
            }
        )
        return ModernTCNDualKernelConfig(**common)
    if model_family == "small_gffn":
        common.update(
            {
                "dmodel": _arg(args, "dmodel", base.dmodel),
                "ffn_ratio": _arg(args, "ffn_ratio", base.ffn_ratio),
                "layer_scale_init": _arg(args, "layer_scale_init", base.layer_scale_init),
            }
        )
        return ModernTCNGroupedConfig(**common)
    if model_family == "small_physics_group_gate":
        common.update(
            {
                "branch_channels": _arg(args, "branch_channels", base.branch_channels),
                "branch_kernel": _arg(args, "branch_kernel", base.branch_kernel),
                "alpha_init": _arg(args, "alpha_init", base.alpha_init),
                "gate_hidden": _arg(args, "gate_hidden", base.gate_hidden),
                "physics_group_spec": _arg(args, "physics_group_spec", base.physics_group_spec),
                "physics_group_names": _str_tuple_arg(args, "physics_group_names", base.physics_group_names),
                "physics_group_indices": _nested_int_tuple_arg(
                    args, "physics_group_indices", base.physics_group_indices
                ),
            }
        )
        return ModernTCNPhysicsGroupGateConfig(**common)
    if model_family == "small_mode_theta":
        common.update(
            {
                "theta_gate_detach": bool(_arg(args, "theta_gate_detach", base.theta_gate_detach)),
                "flat_theta_reg_lambda": _arg(args, "flat_theta_reg_lambda", base.flat_theta_reg_lambda),
                "theta_expert_hidden": _arg(args, "theta_expert_hidden", base.theta_expert_hidden),
            }
        )
        return ModernTCNModeThetaConfig(**common)
    return ModernTCNConfig(**common)


def _effective_input_dim(args: argparse.Namespace, contract) -> int:
    if str(getattr(args, "input_augment", "none") or "none").strip().lower() == "physics_residual_8":
        feat_names = PASSIVE22_FEATURE_NAMES
    else:
        feat_names = [f"f{i}" for i in range(int(contract.input_dim))]
    metadata = _build_input_augmentation_metadata(args, contract, feat_names)
    return effective_input_dim_from_metadata(metadata, int(contract.input_dim))


def _build_input_augmentation_metadata(args: argparse.Namespace, contract, feat_names: List[str]) -> Dict[str, object]:
    return build_input_augmentation_metadata(
        getattr(args, "input_augment", "none"),
        int(contract.input_dim),
        int(contract.seq_len),
        contract.feature_contract,
        feat_names,
        delta_lag=int(getattr(args, "delta_lag", 1)),
        delta_pad=str(getattr(args, "delta_pad", "zero") or "zero"),
        lag_steps=getattr(args, "lag_steps", [1, 2, 4]),
        lag_pad=str(getattr(args, "lag_pad", "edge") or "edge"),
        delta_clip_abs=float(getattr(args, "delta_clip_abs", 5.0)),
    )


def _load_checkpoint_for_init(checkpoint_path: Path) -> Dict[str, object]:
    if not checkpoint_path.exists():
        raise FileNotFoundError(f"init checkpoint not found: {checkpoint_path}")
    ckpt = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    if not isinstance(ckpt, dict) or "model_state" not in ckpt or "model_config" not in ckpt:
        raise ValueError(f"invalid checkpoint format: {checkpoint_path}")
    return ckpt


def _apply_init_checkpoint(model: torch.nn.Module, init_checkpoint: str, expected_family: str) -> Dict[str, object]:
    if not init_checkpoint:
        return {}
    ckpt = _load_checkpoint_for_init(Path(init_checkpoint))
    family = normalize_model_family(ckpt.get("model_family", "small"))
    if family != expected_family:
        raise ValueError(f"init checkpoint model_family={family} mismatch expected={expected_family}")
    cfg = dict(ckpt.get("model_config", {}))
    model_cfg = getattr(model, "cfg", None)
    if model_cfg is not None:
        for key in ("input_dim", "seq_len", "channels", "blocks", "kernel_size", "temporal_padding", "dropout", "turn_head_source"):
            if key in cfg and hasattr(model_cfg, key):
                lhs = getattr(model_cfg, key)
                rhs = cfg[key]
                if lhs != rhs:
                    raise ValueError(f"init checkpoint config mismatch for {key}: {lhs} != {rhs}")
    missing, unexpected = model.load_state_dict(ckpt["model_state"], strict=False)
    if missing:
        raise ValueError(f"init checkpoint missing keys: {sorted(missing)[:8]}")
    if unexpected:
        raise ValueError(f"init checkpoint unexpected keys: {sorted(unexpected)[:8]}")
    return {
        "init_checkpoint": str(Path(init_checkpoint)),
        "init_checkpoint_family": family,
        "init_checkpoint_seed": ckpt.get("seed", None),
        "init_checkpoint_best_epoch": ckpt.get("best_epoch", None),
    }


def _freeze_model_for_mode(model: torch.nn.Module, freeze_mode: str, freeze_early_blocks: int) -> list[str]:
    freeze_mode = str(freeze_mode or "none").lower()
    if freeze_mode not in {"none", "trunk", "early_blocks"}:
        raise ValueError(f"unknown freeze_mode: {freeze_mode}")
    frozen: list[str] = []
    for p in model.parameters():
        p.requires_grad = True
    if freeze_mode == "none":
        return frozen
    if hasattr(model, "stem"):
        for p in model.stem.parameters():
            p.requires_grad = False
            frozen.append("stem")
    if hasattr(model, "blocks"):
        blocks = list(model.blocks)
        limit = len(blocks) if freeze_mode == "trunk" else max(0, min(int(freeze_early_blocks), len(blocks)))
        for idx, block in enumerate(blocks[:limit]):
            for p in block.parameters():
                p.requires_grad = False
            frozen.append(f"block_{idx}")
    if freeze_mode == "trunk":
        if hasattr(model, "main_head"):
            for p in model.main_head.parameters():
                p.requires_grad = True
        if hasattr(model, "turn_head"):
            for p in model.turn_head.parameters():
                p.requires_grad = True
        if hasattr(model, "theta_head"):
            for p in model.theta_head.parameters():
                p.requires_grad = True
    return frozen


def _model_extra_state(model) -> Dict[str, object]:
    if hasattr(model, "e3_state"):
        try:
            return dict(model.e3_state())
        except Exception:
            return {}
    if hasattr(model, "e4_state"):
        try:
            return dict(model.e4_state())
        except Exception:
            return {}
    return {}


def _selected_parameters(model: torch.nn.Module) -> list[torch.nn.Parameter]:
    return [p for p in model.parameters() if p.requires_grad]


def _baseline_prediction_snapshot(model: torch.nn.Module, loader, device, class_w_main, class_w_turn, cfg) -> Dict[str, Any]:
    loss, logits_main, logits_turn, theta_hat, parts = _predict_full(
        model, loader, loader.dataset.split, device, class_w_main, class_w_turn, cfg
    )
    return {
        "loss": loss,
        "logits_main": logits_main,
        "logits_turn": logits_turn,
        "theta_hat": theta_hat,
    }


def _preservation_loss(
    current: Dict[str, torch.Tensor],
    baseline: Dict[str, torch.Tensor],
    batch: Dict[str, torch.Tensor],
    cfg,
) -> torch.Tensor:
    mode = str(getattr(cfg, "preserve_mode", "none") or "none").lower()
    if mode in {"", "none"}:
        ref = current["logits_main"]
        if not torch.is_tensor(ref):
            ref = torch.as_tensor(ref)
        return ref.new_zeros(())
    ref = current.get("logits_main")
    if torch.is_tensor(ref):
        device = ref.device
    else:
        ref_base = baseline.get("logits_main")
        device = ref_base.device if torch.is_tensor(ref_base) else torch.device("cpu")

    def _ensure_tensor(value):
        if isinstance(value, dict):
            raise TypeError("preservation loss expects tensor snapshots only")
        if torch.is_tensor(value):
            return value.to(device)
        return torch.as_tensor(value, device=device)

    current = {k: _ensure_tensor(v) for k, v in current.items()}
    baseline = {k: _ensure_tensor(v) for k, v in baseline.items()}
    batch = {k: _ensure_tensor(v) for k, v in batch.items()}
    main_mask = torch.argmax(baseline["logits_main"], dim=1).eq(batch["y_main"])
    turn_mask = torch.argmax(baseline["logits_turn"], dim=1).eq(batch["y_turn"])
    theta_limit = torch.deg2rad(torch.tensor(0.8, device=device))
    theta_mask = torch.abs(baseline["theta_hat"].reshape(-1) - batch["y_theta"].reshape(-1)) <= theta_limit
    loss = current["logits_main"].new_zeros(())
    if float(getattr(cfg, "lambda_preserve_main", 0.0)) > 0.0 and torch.any(main_mask):
        loss = loss + float(getattr(cfg, "lambda_preserve_main", 0.0)) * F.kl_div(
            F.log_softmax(current["logits_main"][main_mask], dim=1),
            F.softmax(baseline["logits_main"][main_mask], dim=1),
            reduction="batchmean",
        )
    if float(getattr(cfg, "lambda_preserve_turn", 0.0)) > 0.0 and torch.any(turn_mask):
        loss = loss + float(getattr(cfg, "lambda_preserve_turn", 0.0)) * F.kl_div(
            F.log_softmax(current["logits_turn"][turn_mask], dim=1),
            F.softmax(baseline["logits_turn"][turn_mask], dim=1),
            reduction="batchmean",
        )
    if float(getattr(cfg, "lambda_preserve_theta", 0.0)) > 0.0 and torch.any(theta_mask):
        loss = loss + float(getattr(cfg, "lambda_preserve_theta", 0.0)) * F.huber_loss(
            current["theta_hat"][theta_mask].reshape(-1),
            baseline["theta_hat"][theta_mask].reshape(-1),
            reduction="mean",
        )
    return loss


def _train_epoch(
    model,
    loader,
    opt,
    loss_opt,
    loss_controller,
    preserve_model,
    epoch: int,
    device,
    class_w_main,
    class_w_turn,
    cfg,
    gradnorm_update_interval: int = 0,
) -> Dict[str, float]:
    model.train()
    loss_controller.train()
    if preserve_model is not None:
        preserve_model.eval()
    sums: Dict[str, float] = {}
    total_n = 0
    for batch_idx, batch in enumerate(loader, start=1):
        preserve_batch = _to_device(batch, device)
        batch = _apply_command_feature_dropout(preserve_batch, cfg)
        opt.zero_grad(set_to_none=True)
        if loss_opt is not None:
            loss_opt.zero_grad(set_to_none=True)
        logits_main, logits_turn, theta_hat, extra_outputs = _forward_with_optional_experts(model, batch["X"])
        fixed_loss, components = multitask_loss_components(
            logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg, extra_outputs=extra_outputs
        )
        preserve_loss = logits_main.new_zeros(())
        if str(getattr(cfg, "preserve_mode", "none") or "none").lower() == "baseline" and preserve_model is not None:
            with torch.no_grad():
                base_logits_main, base_logits_turn, base_theta, _ = _forward_with_optional_experts(
                    preserve_model, preserve_batch["X"]
                )
            preserve_loss = _preservation_loss(
                {
                    "logits_main": logits_main,
                    "logits_turn": logits_turn,
                    "theta_hat": theta_hat,
                },
                {
                    "logits_main": base_logits_main,
                    "logits_turn": base_logits_turn,
                    "theta_hat": base_theta,
                },
                preserve_batch,
                cfg,
            )
        compute_gradnorm_aux = _should_update_gradnorm(loss_controller, epoch, batch_idx, gradnorm_update_interval)
        loss, dynamic_stats, aux_loss = loss_controller.compute_loss(
            components, model, compute_gradnorm_aux=compute_gradnorm_aux
        )
        if torch.is_tensor(preserve_loss):
            loss = loss + preserve_loss
        loss.backward(retain_graph=aux_loss is not None)
        if aux_loss is not None and loss_opt is not None:
            torch.autograd.backward(aux_loss, inputs=list(loss_controller.parameters()))
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        opt.step()
        if loss_opt is not None:
            loss_opt.step()
        n = int(batch["X"].shape[0])
        total_n += n
        _accumulate(sums, "loss_optimized", loss, n)
        _accumulate(sums, "loss_total", fixed_loss, n)
        _accumulate(sums, "loss_preserve", preserve_loss, n)
        for key, value in components.items():
            _accumulate(sums, key, value, n)
        for key, value in dynamic_stats.items():
            if isinstance(value, (int, float, bool)):
                _accumulate_float(sums, key, float(value), n)
    return {key: value / max(total_n, 1) for key, value in sums.items()}


def _apply_command_feature_dropout(batch: Dict[str, torch.Tensor], cfg: ModernTCNConfig) -> Dict[str, torch.Tensor]:
    prob = float(getattr(cfg, "command_dropout_prob", 0.0) or 0.0)
    if prob <= 0.0:
        return batch
    if not (0.0 <= prob < 1.0):
        raise ValueError(f"command_dropout_prob 必须在 [0,1) 内，实际 {prob}")

    x = batch["X"]
    start = int(getattr(cfg, "command_dropout_start_index", -1) or -1)
    count = int(getattr(cfg, "command_dropout_feature_count", 0) or 0)
    end = start + count
    if start < 0 or count <= 0 or end > int(x.shape[2]):
        raise ValueError(
            "command dropout 配置与输入维度不匹配："
            f"start={start}, count={count}, input_dim={int(x.shape[2])}"
        )

    mode = str(getattr(cfg, "command_dropout_mode", "window_block") or "window_block").lower()
    if mode == "window_block":
        keep = (torch.rand((x.shape[0], 1, 1), device=x.device) >= prob).to(dtype=x.dtype)
    elif mode == "time_block":
        keep = (torch.rand((x.shape[0], x.shape[1], 1), device=x.device) >= prob).to(dtype=x.dtype)
    elif mode == "channel_block":
        keep = (torch.rand((x.shape[0], 1, count), device=x.device) >= prob).to(dtype=x.dtype)
    else:
        raise ValueError(f"未知 command_dropout_mode: {mode}")

    x_drop = x.clone()
    x_drop[:, :, start:end] = x_drop[:, :, start:end] * keep
    out = dict(batch)
    out["X"] = x_drop
    return out


def _forward_with_optional_experts(model, x: torch.Tensor):
    if hasattr(model, "forward_experts"):
        details = model.forward_experts(x)
        return details["logits_main"], details["logits_turn"], details["theta_hat"], details
    logits_main, logits_turn, theta_hat = model(x)
    return logits_main, logits_turn, theta_hat, None


@torch.no_grad()
def _predict_full(
    model,
    loader,
    split,
    device,
    class_w_main,
    class_w_turn,
    cfg,
    loss_controller=None,
) -> Tuple[float, np.ndarray, np.ndarray, np.ndarray, Dict[str, float]]:
    model.eval()
    if loss_controller is not None:
        loss_controller.eval()
    logits_main_all = []
    logits_turn_all = []
    theta_all = []
    loss_sum = 0.0
    n_sum = 0
    part_sums: Dict[str, float] = {}
    for batch in loader:
        batch = _to_device(batch, device)
        logits_main, logits_turn, theta_hat, extra_outputs = _forward_with_optional_experts(model, batch["X"])
        loss, parts = multitask_loss_components(
            logits_main, logits_turn, theta_hat, batch, class_w_main, class_w_turn, cfg, extra_outputs=extra_outputs
        )
        n = int(batch["X"].shape[0])
        loss_sum += float(loss.detach().cpu()) * n
        n_sum += n
        for key, value in parts.items():
            _accumulate(part_sums, key, value, n)
        logits_main_all.append(logits_main.detach().cpu().numpy())
        logits_turn_all.append(logits_turn.detach().cpu().numpy())
        theta_all.append(theta_hat.detach().cpu().numpy())
    return (
        loss_sum / max(n_sum, 1),
        np.concatenate(logits_main_all, axis=0),
        np.concatenate(logits_turn_all, axis=0),
        np.concatenate(theta_all, axis=0).reshape(-1),
        {key: value / max(n_sum, 1) for key, value in part_sums.items()},
    )


@torch.no_grad()
def _collect_gate_statistics(model, loader, split, device, prefix: str) -> Dict[str, object]:
    if not hasattr(model, "collect_gate_weights") or not hasattr(model, "e3_state"):
        return {}
    group_names = [str(x) for x in model.e3_state().get("physics_group_names", [])]
    if not group_names:
        return {}
    gates = []
    for batch in loader:
        batch = _to_device(batch, device)
        gate = model.collect_gate_weights(batch["X"])
        gates.append(gate.detach().cpu().numpy())
    if not gates:
        return {}
    arr = np.concatenate(gates, axis=0)
    y_main = np.asarray(split.y_main).reshape(-1)
    transition = np.asarray(split.turn_transition).reshape(-1).astype(bool)
    finite = bool(np.isfinite(arr).all())
    eps = 1e-12
    entropy = -np.sum(arr * np.log(np.clip(arr, eps, 1.0)), axis=1)
    max_mean = float(np.max(arr.mean(axis=0))) if arr.size else float("nan")
    single_collapse = bool(finite and (max_mean >= 0.98 or float(np.mean(entropy)) < 0.05))

    detail: Dict[str, object] = {
        "prefix": prefix,
        "stat_label_policy": "true label for main class; dataset turn_transition mask for transition",
        "group_names": group_names,
        "all_finite": finite,
        "single_collapse": single_collapse,
        "mean_entropy": float(np.mean(entropy)) if entropy.size else float("nan"),
        "overall": _gate_group_summary(arr, group_names),
        "by_main_true": {
            "flat": _gate_group_summary(arr[y_main == 0], group_names),
            "stall": _gate_group_summary(arr[y_main == 1], group_names),
            "slope": _gate_group_summary(arr[y_main == 2], group_names),
        },
        "turn_transition": _gate_group_summary(arr[transition], group_names),
    }
    flat = detail["by_main_true"]["flat"]
    stall = detail["by_main_true"]["stall"]
    slope = detail["by_main_true"]["slope"]
    transition_summary = detail["turn_transition"]
    idx = {name: i for i, name in enumerate(group_names)}
    overall_mean = arr.mean(axis=0)

    def group_mean(summary: Dict[str, object], name: str) -> float:
        value = summary.get(name, {}).get("mean", float("nan")) if isinstance(summary.get(name, {}), dict) else float("nan")
        try:
            return float(value)
        except Exception:
            return float("nan")

    yaw_delta = (
        group_mean(transition_summary, "yaw_steering") - float(overall_mean[idx["yaw_steering"]])
        if "yaw_steering" in idx
        else float("nan")
    )
    drive_delta = (
        group_mean(stall, "drive_current_load") - float(overall_mean[idx["drive_current_load"]])
        if "drive_current_load" in idx
        else float("nan")
    )
    vel_delta = (
        abs(group_mean(slope, "velocity_acceleration") - group_mean(flat, "velocity_acceleration"))
        if "velocity_acceleration" in idx
        else float("nan")
    )
    interpretability_score = int((yaw_delta > 0.0) if np.isfinite(yaw_delta) else False)
    interpretability_score += int((drive_delta > 0.0) if np.isfinite(drive_delta) else False)
    interpretability_score += int((vel_delta > 0.01) if np.isfinite(vel_delta) else False)
    detail["interpretability"] = {
        "yaw_transition_minus_overall": yaw_delta,
        "drive_stall_minus_overall": drive_delta,
        "velocity_slope_flat_abs_delta": vel_delta,
        "score_0_to_3": interpretability_score,
    }

    out: Dict[str, object] = {
        f"{prefix}_gate_all_finite": finite,
        f"{prefix}_gate_single_collapse": single_collapse,
        f"{prefix}_gate_mean_entropy": detail["mean_entropy"],
        f"{prefix}_gate_interpretability_score": interpretability_score,
        f"{prefix}_gate_yaw_transition_minus_overall": yaw_delta,
        f"{prefix}_gate_drive_stall_minus_overall": drive_delta,
        f"{prefix}_gate_velocity_slope_flat_abs_delta": vel_delta,
        f"{prefix}_gate_detail": detail,
    }
    for group_idx, name in enumerate(group_names):
        out[f"{prefix}_gate_{name}_mean"] = float(arr[:, group_idx].mean())
        out[f"{prefix}_gate_{name}_std"] = float(arr[:, group_idx].std())
    return out


def _gate_group_summary(arr: np.ndarray, group_names: List[str]) -> Dict[str, object]:
    if arr.size == 0:
        return {name: {"n": 0, "mean": float("nan"), "std": float("nan")} for name in group_names}
    return {
        name: {
            "n": int(arr.shape[0]),
            "mean": float(arr[:, idx].mean()),
            "std": float(arr[:, idx].std()),
        }
        for idx, name in enumerate(group_names)
    }


def _model_extra_state(model) -> Dict[str, object]:
    if hasattr(model, "e3_state"):
        try:
            return dict(model.e3_state())
        except Exception:
            return {}
    if hasattr(model, "e4_state"):
        try:
            return dict(model.e4_state())
        except Exception:
            return {}
    return {}


def _augment_row_with_model_state(row: Dict[str, object], model_state: Dict[str, object], metrics: Dict[str, object]) -> None:
    if not model_state:
        return
    row["alpha_final"] = model_state.get("alpha", float("nan"))
    row["physics_group_names"] = json.dumps(model_state.get("physics_group_names", []), ensure_ascii=False)
    row["physics_group_indices"] = json.dumps(model_state.get("physics_group_indices", []), ensure_ascii=False)
    if "theta_gate_detach" in model_state:
        row["theta_gate_detach"] = model_state.get("theta_gate_detach")
        row["flat_theta_reg_lambda"] = model_state.get("flat_theta_reg_lambda", float("nan"))
        row["theta_expert_hidden"] = model_state.get("theta_expert_hidden", 0)
    for key, value in metrics.items():
        if key.endswith("_gate_detail"):
            row[f"{key}_json"] = json.dumps(value, ensure_ascii=False)
        elif "_gate_" in key and isinstance(value, (int, float, bool, np.floating)):
            row[key] = value


def _write_gate_statistics(
    out_dir: Path,
    model_state: Dict[str, object],
    val_metrics: Dict[str, object],
    test_metrics: Dict[str, object],
) -> None:
    if not model_state:
        return
    payload = {
        "model_extra_state": model_state,
        "val": val_metrics.get("val_gate_detail", {}),
        "test": test_metrics.get("test_gate_detail", {}),
    }
    (out_dir / "physics_gate_statistics.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _accumulate(sums: Dict[str, float], key: str, value: torch.Tensor, n: int) -> None:
    sums[key] = sums.get(key, 0.0) + float(value.detach().cpu()) * n


def _accumulate_float(sums: Dict[str, float], key: str, value: float, n: int) -> None:
    sums[key] = sums.get(key, 0.0) + value * n


def _to_device(batch: Dict[str, torch.Tensor], device: torch.device) -> Dict[str, torch.Tensor]:
    return {k: v.to(device, non_blocking=True) for k, v in batch.items()}


def _set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True


def _select_device(mode: str) -> torch.device:
    if mode == "cuda":
        return torch.device("cuda")
    if mode == "cpu":
        return torch.device("cpu")
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def _history_row(
    epoch: int,
    lr: float,
    train_stats: Dict[str, float],
    val_metrics: Dict[str, object],
    score: float,
    loss_state: Dict[str, object],
    model_state: Dict[str, object],
) -> Dict[str, object]:
    row = {
        "epoch": epoch,
        "lr": lr,
        "loss_mode": loss_state.get("loss_mode", "fixed"),
        "freeze_mode": loss_state.get("freeze_mode", "none"),
        "freeze_early_blocks": loss_state.get("freeze_early_blocks", float("nan")),
        "preserve_mode": loss_state.get("preserve_mode", "none"),
        "lambda_preserve_main": loss_state.get("lambda_preserve_main", float("nan")),
        "lambda_preserve_turn": loss_state.get("lambda_preserve_turn", float("nan")),
        "lambda_preserve_theta": loss_state.get("lambda_preserve_theta", float("nan")),
        "s_range": loss_state.get("s_range", float("nan")),
        "lambda_s_prior": loss_state.get("lambda_s_prior", float("nan")),
        "train_loss": train_stats.get("loss_optimized", float("nan")),
        "train_loss_fixed_total": train_stats.get("loss_total", float("nan")),
        "train_loss_main": train_stats.get("loss_main_bundle", train_stats.get("loss_main", float("nan"))),
        "train_loss_turn": train_stats.get("loss_turn_bundle", train_stats.get("loss_turn", float("nan"))),
        "train_loss_theta": train_stats.get("loss_theta_bundle", train_stats.get("loss_theta", float("nan"))),
        "train_loss_main_base": train_stats.get("loss_main_bundle_base", train_stats.get("loss_main", float("nan"))),
        "train_loss_turn_base": train_stats.get("loss_turn_bundle_base", train_stats.get("loss_turn", float("nan"))),
        "train_loss_theta_base": train_stats.get("loss_theta_bundle_base", train_stats.get("loss_theta", float("nan"))),
        "train_loss_preserve": train_stats.get("loss_preserve", float("nan")),
        "train_loss_main_raw": train_stats.get("loss_main", float("nan")),
        "train_loss_turn_raw": train_stats.get("loss_turn", float("nan")),
        "train_loss_theta_raw": train_stats.get("loss_theta", float("nan")),
        "train_loss_transition_focal_raw": train_stats.get("loss_transition_focal_raw", float("nan")),
        "train_loss_transition_focal_weighted": train_stats.get("loss_transition_focal_weighted", float("nan")),
        "train_loss_stall_focal_raw": train_stats.get("loss_stall_focal_raw", float("nan")),
        "train_loss_stall_focal_weighted": train_stats.get("loss_stall_focal_weighted", float("nan")),
        "train_loss_theta_smooth": train_stats.get("loss_theta_smooth", float("nan")),
        "train_loss_flat_theta_expert_reg": train_stats.get("loss_flat_theta_expert_reg", float("nan")),
        "train_loss_flat_theta_expert_reg_weighted": train_stats.get(
            "loss_flat_theta_expert_reg_weighted", float("nan")
        ),
        "val_loss": val_metrics["loss_total"],
        "val_loss_main": val_metrics.get("loss_main_bundle", val_metrics.get("loss_main", float("nan"))),
        "val_loss_turn": val_metrics.get("loss_turn_bundle", val_metrics.get("loss_turn", float("nan"))),
        "val_loss_theta": val_metrics.get("loss_theta_bundle", val_metrics.get("loss_theta", float("nan"))),
        "val_loss_main_base": val_metrics.get("loss_main_bundle_base", val_metrics.get("loss_main", float("nan"))),
        "val_loss_turn_base": val_metrics.get("loss_turn_bundle_base", val_metrics.get("loss_turn", float("nan"))),
        "val_loss_theta_base": val_metrics.get("loss_theta_bundle_base", val_metrics.get("loss_theta", float("nan"))),
        "val_loss_preserve": val_metrics.get("preserve_loss", float("nan")),
        "val_loss_main_raw": val_metrics.get("loss_main", float("nan")),
        "val_loss_turn_raw": val_metrics.get("loss_turn", float("nan")),
        "val_loss_theta_raw": val_metrics.get("loss_theta", float("nan")),
        "val_loss_transition_focal_raw": val_metrics.get("loss_transition_focal_raw", float("nan")),
        "val_loss_transition_focal_weighted": val_metrics.get("loss_transition_focal_weighted", float("nan")),
        "val_loss_stall_focal_raw": val_metrics.get("loss_stall_focal_raw", float("nan")),
        "val_loss_stall_focal_weighted": val_metrics.get("loss_stall_focal_weighted", float("nan")),
        "val_loss_theta_smooth": val_metrics.get("loss_theta_smooth", float("nan")),
        "val_loss_flat_theta_expert_reg": val_metrics.get("loss_flat_theta_expert_reg", float("nan")),
        "val_loss_flat_theta_expert_reg_weighted": val_metrics.get(
            "loss_flat_theta_expert_reg_weighted", float("nan")
        ),
        "val_score": score,
        "val_acc_main": val_metrics["acc_main"],
        "val_acc_turn": val_metrics["acc_turn"],
        "val_main_confidence_mean": val_metrics.get("main_confidence_mean", float("nan")),
        "val_turn_confidence_mean": val_metrics.get("turn_confidence_mean", float("nan")),
        "val_main_low_conf_0p60_ratio": val_metrics.get("main_low_conf_0p60_ratio", float("nan")),
        "val_turn_low_conf_0p60_ratio": val_metrics.get("turn_low_conf_0p60_ratio", float("nan")),
        "val_turn_left_recall": val_metrics["turn_left_recall"],
        "val_turn_right_recall": val_metrics["turn_right_recall"],
        "val_acc_turn_transition": val_metrics["acc_turn_transition"],
        "val_theta_mae_deg": val_metrics["theta_mae_deg"],
        "val_theta_abs_le_10_p95_abs_err_deg": val_metrics["theta_abs_le_10_p95_abs_err_deg"],
        "val_theta_neg_10_8_p95_abs_err_deg": val_metrics["theta_neg_10_8_p95_abs_err_deg"],
        "val_theta_pos_8_10_p95_abs_err_deg": val_metrics["theta_pos_8_10_p95_abs_err_deg"],
        "val_theta_abs_le_8_p95_abs_err_deg": val_metrics["theta_abs_le_8_p95_abs_err_deg"],
        "val_theta_neg_8_6_p95_abs_err_deg": val_metrics["theta_neg_8_6_p95_abs_err_deg"],
        "val_theta_pos_6_8_p95_abs_err_deg": val_metrics["theta_pos_6_8_p95_abs_err_deg"],
        "val_theta_neg_2_0p5_p95_abs_err_deg": val_metrics["theta_neg_2_0p5_p95_abs_err_deg"],
        "val_theta_pos_0p5_2_p95_abs_err_deg": val_metrics["theta_pos_0p5_2_p95_abs_err_deg"],
        "val_theta_flat_abs_p95_deg": val_metrics["theta_flat_abs_p95_deg"],
        "val_theta_flat_bias_deg": val_metrics["theta_flat_bias_deg"],
        "val_theta_near_flat_abs_p95_deg": val_metrics["theta_near_flat_abs_p95_deg"],
        "val_theta_true_zero_abs_p95_deg": val_metrics["theta_true_zero_abs_p95_deg"],
        "val_flat_recall": val_metrics["flat_recall"],
        "val_stall_recall": val_metrics["stall_recall"],
        "val_slope_recall": val_metrics["slope_recall"],
        "val_flat_as_stall_ratio": val_metrics.get("flat_as_stall_ratio", float("nan")),
        "val_stall_as_flat_ratio": val_metrics.get("stall_as_flat_ratio", float("nan")),
        "val_cm_main": val_metrics.get("cm_main", "[]"),
        "val_cm_turn": val_metrics.get("cm_turn", "[]"),
    }
    if model_state:
        row["alpha"] = model_state.get("alpha", float("nan"))
    for key in [
        "s_main",
        "s_turn",
        "s_theta",
        "raw_s_main",
        "raw_s_turn",
        "raw_s_theta",
        "weight_main",
        "weight_turn",
        "weight_theta",
        "bounded_s_prior",
        "s_range",
        "s_prior_lambda",
        "task_weight_main",
        "task_weight_turn",
        "task_weight_theta",
        "initial_loss_main",
        "initial_loss_turn",
        "initial_loss_theta",
    ]:
        row[key] = loss_state.get(key, train_stats.get(key, float("nan")))
    for key in ["grad_norm_main", "grad_norm_turn", "grad_norm_theta", "gradnorm_loss", "gradnorm_unstable"]:
        row[key] = train_stats.get(key, float("nan"))
    return row


def _write_csv(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _git_hash(root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(root),
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return "unknown"


def _write_run_metadata(
    root: Path,
    out_dir: Path,
    args: argparse.Namespace,
    cfg: ModernTCNConfig,
    contract: Dict[str, object],
    feat_names,
    model_family: str,
    run_tag: str,
    loss_state: Dict[str, object],
    model_state: Dict[str, object],
    input_augmentation: Dict[str, object],
    files: Dict[str, Path],
) -> None:
    git_hash = _git_hash(root)
    config = {
        "model_family": model_family,
        "loss_mode": loss_state.get("loss_mode", _normalize_loss_mode(getattr(args, "loss_mode", "fixed"))),
        "dynamic_loss_state": loss_state,
        "model_extra_state": model_state,
        "theta_smooth_status": "disabled_contract_limited",
        "run_tag": run_tag,
        "output_dir": str(out_dir),
        "cli_args": vars(args),
        "model_config": cfg.to_dict(),
        "dataset_contract": contract,
        "input_augmentation": input_augmentation,
        "input_augment": input_augmentation.get("input_augment", "none"),
        "raw_input_dim": input_augmentation.get("raw_input_dim"),
        "augmented_input_dim": input_augmentation.get("augmented_input_dim"),
        "delta_lag": input_augmentation.get("delta_lag"),
        "delta_pad": input_augmentation.get("delta_pad"),
        "lag_steps": input_augmentation.get("lag_steps"),
        "lag_pad": input_augmentation.get("lag_pad"),
        "delta_clip_abs": input_augmentation.get("delta_clip_abs"),
        "raw_feature_contract": input_augmentation.get("raw_feature_contract"),
        "feature_names": list(feat_names),
        "git_hash": git_hash,
        "python": sys.version,
        "torch_version": torch.__version__,
    }
    files["config_json"].write_text(json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8")
    files["contract_copy_file"].write_text(json.dumps(contract, indent=2, ensure_ascii=False), encoding="utf-8")
    files["feature_names_file"].write_text("\n".join(str(x) for x in feat_names) + "\n", encoding="utf-8")
    files["git_hash_file"].write_text(git_hash + "\n", encoding="utf-8")
    with files["config_md"].open("w", encoding="utf-8") as f:
        f.write(f"# ModernTCN run config\n\n")
        f.write(f"- model_family: `{model_family}`\n")
        f.write(f"- loss_mode: `{loss_state.get('loss_mode', _normalize_loss_mode(getattr(args, 'loss_mode', 'fixed')) )}`\n")
        f.write(f"- run_tag: `{run_tag}`\n")
        f.write(f"- output_dir: `{out_dir}`\n")
        f.write(f"- git_hash: `{git_hash}`\n")
        f.write(f"- dataset: `{contract.get('dataset_file', '')}`\n")
        f.write(f"- raw_input: `[batch,{contract.get('seq_len')},{contract.get('input_dim')}]`\n")
        f.write(f"- model_input: `[batch,{cfg.seq_len},{cfg.input_dim}]`\n")
        f.write(f"- input_augment: `{input_augmentation.get('input_augment', 'none')}`\n\n")
        f.write("## Model Config\n\n```json\n")
        f.write(json.dumps(cfg.to_dict(), indent=2, ensure_ascii=False))
        f.write("\n```\n")
        f.write("\n## Input Augmentation\n\n```json\n")
        f.write(json.dumps(input_augmentation, indent=2, ensure_ascii=False))
        f.write("\n```\n")
        f.write("\n## Dynamic Loss State\n\n```json\n")
        f.write(json.dumps(loss_state, indent=2, ensure_ascii=False))
        f.write("\n```\n")
        if model_state:
            f.write("\n## Model Extra State\n\n```json\n")
            f.write(json.dumps(model_state, indent=2, ensure_ascii=False))
            f.write("\n```\n")
    with files["train_log_file"].open("w", encoding="utf-8") as f:
        f.write("Training log placeholder. Console logs are not captured by train_one_seed API.\n")
        f.write(f"summary_csv: `{out_dir / (_file_prefix(model_family, args.seed) + '_summary.csv')}`\n")
        f.write(f"history_csv: `{out_dir / (_file_prefix(model_family, args.seed) + '_history.csv')}`\n")


def _write_report(
    path: Path,
    args: argparse.Namespace,
    cfg: ModernTCNConfig,
    contract: Dict[str, object],
    row: Dict[str, object],
    test_metrics: Dict[str, object],
    val_metrics: Dict[str, object],
    train_seconds: float,
    model_family: str,
    model_state: Dict[str, object],
    input_augmentation: Dict[str, object],
) -> None:
    passed, failures = seed42_gate(test_metrics) if args.seed == 42 else (False, [])
    with path.open("w", encoding="utf-8") as f:
        if model_family == "full":
            title = "ModernTCNFull v0 第一阶段训练报告"
        elif model_family == "small_dualkernel":
            title = "ModernTCN dual-kernel small 第一阶段训练报告"
        elif model_family == "small_gffn":
            title = "ModernTCN grouped-FFN small 第一阶段训练报告"
        elif model_family == "small_physics_group_gate":
            title = "PG-ModernTCN-small physics-group residual gate 训练报告"
        elif model_family == "small_mode_theta":
            title = "ModernTCN-small mode-conditioned theta experts 训练报告"
        else:
            title = "ModernTCN-small 第一阶段训练报告"
        f.write(f"# {title}\n\n")
        f.write("## 固定约束\n\n")
        f.write(f"- model_family: `{model_family}`\n")
        f.write(f"- loss_mode: `{_normalize_loss_mode(getattr(args, 'loss_mode', 'fixed'))}`\n")
        f.write(f"- dataset: `{contract['dataset_file']}`\n")
        f.write(f"- vehicle: `{contract.get('vehicle_type', '')}`; active=`{contract.get('active_drive_steer_wheels', '')}`; passive=`{contract.get('passive_support_wheels', '')}`\n")
        f.write(f"- feature_policy: `{contract.get('feature_policy', '')}`\n")
        f.write(f"- label_time_policy: `{contract.get('label_time_policy', '')}`, horizon_steps={contract.get('horizon_steps', 0)}\n")
        f.write("- split: 使用 MAT 文件已有 run-level split，不重划分。\n")
        f.write("- scaler: 使用 MAT 文件已有归一化后 X，不重新拟合。\n")
        f.write(f"- confidence_policy: `{contract.get('confidence_policy', '')}`\n")
        f.write(f"- raw_input: `[batch, time={contract['seq_len']}, feature={contract['input_dim']}]`\n")
        f.write(f"- model_input: `[batch, time={cfg.seq_len}, feature={cfg.input_dim}]`\n")
        f.write(f"- input_augment: `{input_augmentation.get('input_augment', 'none')}`\n")
        f.write("- output: `logits_main`, `logits_turn`, `theta_hat`\n\n")
        if input_augmentation.get("input_augment") != "none":
            f.write("## Input Augmentation\n\n")
            f.write(f"- method: `{input_augmentation.get('method', '')}`\n")
            if input_augmentation.get("delta_lag") is not None:
                f.write(f"- delta_lag: `{input_augmentation.get('delta_lag')}`\n")
                f.write(f"- delta_pad: `{input_augmentation.get('delta_pad')}`\n")
            if input_augmentation.get("lag_steps") is not None:
                f.write(f"- lag_steps: `{input_augmentation.get('lag_steps')}`\n")
                f.write(f"- lag_pad: `{input_augmentation.get('lag_pad')}`\n")
            if input_augmentation.get("delta_clip_abs") is not None:
                f.write(f"- delta_clip_abs: `{input_augmentation.get('delta_clip_abs')}`\n")
            f.write(f"- augmented_input_dim: `{input_augmentation.get('augmented_input_dim')}`\n")
            f.write("- MATLAB/Simulink: `not executed in this offline run`\n\n")
        if model_family == "small_physics_group_gate":
            f.write("## E3 Physics-Group Residual Gate\n\n")
            f.write("- residual insertion: trunk-level `[B, channels, T]`, before original small readout and heads.\n")
            f.write("- gate statistics policy: true main labels and dataset `turn_transition` mask.\n")
            f.write("- alpha0 note: alpha_init=0.0 can warm up slowly because the branch is initially gated by alpha.\n")
            f.write(f"- alpha_final: `{float(model_state.get('alpha', float('nan'))):.8f}`\n")
            f.write(f"- physics_group_names: `{model_state.get('physics_group_names', [])}`\n\n")
        if model_family == "small_mode_theta":
            f.write("## E4 Mode-Conditioned Theta Experts\n\n")
            f.write("- theta fusion: `sum(softmax(main_logits) * theta_experts)`.\n")
            f.write(f"- theta_gate_detach: `{bool(model_state.get('theta_gate_detach', True))}`\n")
            f.write(f"- flat_theta_reg_lambda: `{float(model_state.get('flat_theta_reg_lambda', float('nan'))):.6f}`\n")
            f.write(f"- theta_expert_hidden: `{int(model_state.get('theta_expert_hidden', 0))}`\n\n")
        f.write("## E2 hard-sample focal settings\n\n")
        theta_smooth_status = "disabled_contract_limited"
        f.write(f"- lambda_transition_focal: `{float(getattr(args, 'lambda_transition_focal', 0.0))}`\n")
        f.write(f"- lambda_stall_focal: `{float(getattr(args, 'lambda_stall_focal', 0.0))}`\n")
        f.write(f"- lambda_theta_smooth: `{float(getattr(args, 'lambda_theta_smooth', 0.0))}`\n")
        f.write(f"- focal_gamma: `{float(getattr(args, 'focal_gamma', 2.0))}`\n")
        f.write(f"- theta_smooth_mode: `{getattr(args, 'theta_smooth_mode', 'off')}`\n")
        f.write(f"- theta_smooth_status: `{theta_smooth_status}`\n\n")
        f.write("## 配置\n\n")
        f.write("```json\n")
        f.write(json.dumps(cfg.to_dict(), indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("## 测试集指标\n\n")
        f.write("| metric | value |\n|---|---:|\n")
        for key in [
            "acc_main",
            "acc_turn",
            "acc_turn_pure",
            "acc_turn_transition",
            "main_confidence_mean",
            "main_low_conf_0p60_ratio",
            "main_low_conf_0p70_ratio",
            "turn_confidence_mean",
            "turn_low_conf_0p60_ratio",
            "turn_low_conf_0p70_ratio",
            "turn_right_recall",
            "turn_straight_recall",
            "turn_left_recall",
            "theta_mae_deg",
            "theta_abs_le_10_p95_abs_err_deg",
            "theta_neg_10_8_p95_abs_err_deg",
            "theta_pos_8_10_p95_abs_err_deg",
            "theta_abs_le_8_p95_abs_err_deg",
            "theta_neg_8_6_p95_abs_err_deg",
            "theta_pos_6_8_p95_abs_err_deg",
            "theta_neg_2_0p5_p95_abs_err_deg",
            "theta_pos_0p5_2_p95_abs_err_deg",
            "theta_flat_abs_p95_deg",
            "theta_flat_bias_deg",
            "theta_near_flat_abs_p95_deg",
            "theta_true_zero_abs_p95_deg",
            "theta_near_flat_bias_deg",
            "theta_flat_turn_abs_p95_deg",
            "flat_recall",
            "stall_recall",
            "slope_recall",
            "flat_as_stall_ratio",
            "stall_as_flat_ratio",
            "uphill_recall",
            "downhill_recall",
        ]:
            f.write(f"| {key} | {float(row[key]):.4f} |\n")
        f.write("\n## 混淆矩阵\n\n")
        f.write("### main: rows truth flat/stall/slope, columns pred flat/stall/slope\n\n")
        f.write("```json\n")
        f.write(json.dumps(test_metrics.get("cm_main", []), indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("### turn: rows truth right/straight/left, columns pred right/straight/left\n\n")
        f.write("```json\n")
        f.write(json.dumps(test_metrics.get("cm_turn", []), indent=2, ensure_ascii=False))
        f.write("\n```\n\n")
        f.write("## Loss scale\n\n")
        f.write("| component | value |\n|---|---:|\n")
        for key in [
            "loss_main_bundle_base",
            "loss_turn_bundle_base",
            "loss_theta_bundle_base",
            "loss_transition_focal_raw",
            "loss_transition_focal_weighted",
            "loss_stall_focal_raw",
            "loss_stall_focal_weighted",
            "loss_theta_smooth",
            "loss_flat_theta_expert_reg",
            "loss_flat_theta_expert_reg_weighted",
        ]:
            f.write(f"| test_{key} | {float(test_metrics.get(key, float('nan'))):.6f} |\n")
        f.write(f"\n- best_epoch: {row['best_epoch']}\n")
        f.write(f"- train_seconds: {train_seconds:.1f}\n\n")
        if model_state:
            f.write("## E3 Gate Statistics\n\n")
            f.write("| metric | value |\n|---|---:|\n")
            for key in [
                "test_gate_all_finite",
                "test_gate_single_collapse",
                "test_gate_mean_entropy",
                "test_gate_interpretability_score",
                "test_gate_yaw_transition_minus_overall",
                "test_gate_drive_stall_minus_overall",
                "test_gate_velocity_slope_flat_abs_delta",
            ]:
                value = test_metrics.get(key, float("nan"))
                if isinstance(value, bool):
                    f.write(f"| {key} | {value} |\n")
                else:
                    f.write(f"| {key} | {float(value):.6f} |\n")
            f.write("\n```json\n")
            f.write(json.dumps(test_metrics.get("test_gate_detail", {}), indent=2, ensure_ascii=False))
            f.write("\n```\n\n")
        f.write("## 置信度分桶\n\n")
        _write_confidence_bins(f, "main", test_metrics)
        _write_confidence_bins(f, "turn", test_metrics)
        if args.seed == 42:
            f.write("## seed42 进入三 seed 判定\n\n")
            f.write(f"- pass: `{int(passed)}`\n")
            if failures:
                for msg in failures:
                    f.write(f"- {msg}\n")
            else:
                f.write("- seed42 已满足进入 `[42, 73, 101]` 的最低门槛。\n")
        f.write("\n## 验证集最佳点\n\n")
        f.write("```json\n")
        f.write(json.dumps(val_metrics, indent=2, ensure_ascii=False))
        f.write("\n```\n")


def _write_confidence_bins(f, prefix: str, metrics: Dict[str, object]) -> None:
    f.write(f"### {prefix}\n\n")
    f.write("| confidence bin | n | error rate | mean confidence |\n|---|---:|---:|---:|\n")
    for row in metrics.get(f"{prefix}_confidence_bins", []):
        f.write(
            f"| {row['bin']} | {int(row['n'])} | "
            f"{float(row['error_rate']):.4f} | {float(row['mean_confidence']):.4f} |\n"
        )
    f.write("\n")


if __name__ == "__main__":
    main()
