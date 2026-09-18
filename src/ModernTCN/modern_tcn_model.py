"""ONNX 友好的 ModernTCN-small 多任务模型。

第一版不直接照搬官方 ModernTCN 的全部组件，而是保留其核心思想：
大核 depthwise temporal convolution + pointwise channel mixing + residual。
这样导出的 ONNX 主要由 Conv1d、BatchNorm、ReLU、Linear、Mean、Concat、
Reshape/Transpose 等标准算子构成，便于后续导入 MATLAB R2024b。
"""

from __future__ import annotations

from dataclasses import dataclass, asdict, fields
from typing import Dict, List, Tuple

import torch
from torch import nn


@dataclass
class ModernTCNConfig:
    """ModernTCN-small 的默认训练与结构配置。"""

    input_dim: int = 22
    seq_len: int = 128
    channels: int = 64
    blocks: int = 5
    kernel_size: int = 31
    temporal_padding: str = "same"
    dropout: float = 0.15
    command_dropout_prob: float = 0.0
    command_dropout_start_index: int = -1
    command_dropout_feature_count: int = 0
    command_dropout_mode: str = "window_block"
    expansion: int = 2
    readout_input_stats: bool = True
    turn_head_source: str = "full"
    turn_feature_indices: Tuple[int, ...] = (0, 3, 4, 5, 6, 7, 8, 9, 13, 21)
    lambda_turn: float = 0.05
    lambda_theta: float = 0.35
    lambda_theta_flat: float = 0.20
    theta_flat_loss_mode: str = "near_zero"
    theta_flat_zero_tol_deg: float = 0.3
    lambda_theta_near_flat: float = 0.0
    theta_near_flat_deg: float = 0.5
    lambda_theta_error_excess: float = 0.0
    lambda_theta_flat_excess: float = 0.0
    lambda_theta_near_flat_excess: float = 0.0
    lambda_theta_true_zero_excess: float = 0.0
    lambda_theta_active_excess: float = 0.0
    lambda_theta_small_neg: float = 0.0
    lambda_theta_small_neg_excess: float = 0.0
    lambda_turn_release: float = 0.0
    lambda_false_turn_straight: float = 0.0
    lambda_transition_focal: float = 0.0
    lambda_stall_focal: float = 0.0
    lambda_theta_smooth: float = 0.0
    focal_gamma: float = 2.0
    theta_smooth_mode: str = "off"
    theta_excess_target_deg: float = 1.0
    theta_flat_excess_target_deg: float = 0.5
    theta_true_zero_tol_deg: float = 1e-4
    theta_small_neg_min_deg: float = -4.0
    theta_small_neg_max_deg: float = -2.0
    theta_gate_mode: str = "none"
    theta_gate_power: float = 1.0
    theta_gate_floor: float = 0.0
    main_class_multipliers: Tuple[float, float, float] = (1.20, 1.00, 0.95)
    turn_class_multipliers: Tuple[float, float, float] = (1.00, 1.10, 1.00)
    main_class_weight_method: str = "sqrt_inverse"
    turn_class_weight_method: str = "sqrt_inverse"
    main_neg_slope_weight: float = 2.0
    main_pos_slope_weight: float = 1.0
    theta_neg_weight: float = 2.0
    theta_pos_weight: float = 1.0
    turn_transition_weight: float = 1.0
    select_turn_weight: float = 0.30
    select_turn_transition_weight: float = 1.00
    select_turn_transition_target: float = 0.75
    select_turn_left_weight: float = 0.00
    select_turn_left_target: float = 0.80
    select_turn_lr_weight: float = 0.00
    select_turn_lr_target: float = 0.80
    select_stall_weight: float = 0.00
    select_stall_target: float = 0.70
    select_theta_weight: float = 0.15
    select_theta_ref_deg: float = 5.0
    select_theta_p95_weight: float = 0.0
    select_theta_p95_target_deg: float = 1.0
    select_theta_flat_p95_weight: float = 0.0
    select_theta_flat_p95_target_deg: float = 1.0
    select_theta_near_flat_p95_weight: float = 0.0
    select_theta_near_flat_p95_target_deg: float = 1.0
    select_theta_true_zero_p95_weight: float = 0.0
    select_theta_true_zero_p95_target_deg: float = 1.0
    select_theta_flat_peak_weight: float = 0.0
    select_theta_flat_peak_target_deg: float = 3.0
    select_theta_small_neg_p95_weight: float = 0.0
    select_theta_small_neg_p95_target_deg: float = 1.0
    select_theta_extreme_p95_weight: float = 0.0
    select_theta_extreme_p95_target_deg: float = 1.0
    select_theta_edge_p95_weight: float = 0.0
    select_theta_edge_p95_target_deg: float = 1.2
    select_theta_small_nonzero_p95_weight: float = 0.0
    select_theta_small_nonzero_p95_target_deg: float = 1.0
    select_theta_flat_bias_weight: float = 0.0
    select_theta_flat_bias_target_deg: float = 0.2
    freeze_mode: str = "none"
    freeze_early_blocks: int = 3
    preserve_mode: str = "none"
    lambda_preserve_main: float = 0.0
    lambda_preserve_turn: float = 0.0
    lambda_preserve_theta: float = 0.0
    s_range: float = 0.25
    lambda_s_prior: float = 0.01

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)


@dataclass
class ModernTCNFullConfig(ModernTCNConfig):
    """ModernTCNFull v0 的默认训练与结构配置。"""

    patch_size: int = 16
    patch_stride: int = 4
    dims: Tuple[int, ...] = (32, 64)
    stage_blocks: Tuple[int, ...] = (2, 2)
    large_kernels: Tuple[int, ...] = (15, 9)
    small_kernels: Tuple[int, ...] = (5, 3)
    ffn_ratio: int = 2
    layer_scale_init: float = 1e-2


@dataclass
class ModernTCNGroupedConfig(ModernTCNConfig):
    """Grouped pointwise ConvFFN small variant for 22D ablation."""

    dmodel: int = 4
    ffn_ratio: int = 2
    layer_scale_init: float = 1e-2


@dataclass
class ModernTCNDualKernelConfig(ModernTCNConfig):
    """Dual temporal-kernel small variant for the 22D plantfix ablation."""

    large_kernel: int = 31
    small_kernel: int = 5
    dual_branch_scale: float = 0.5
    small_branch_init: str = "default"
    layer_scale_init: float = 1e-2


@dataclass
class ModernTCNPhysicsGroupGateConfig(ModernTCNConfig):
    """AGV physics-group residual gate variant for SCI E3."""

    branch_channels: int = 16
    branch_kernel: int = 31
    alpha_init: float = 0.0
    gate_hidden: int = 32
    physics_group_spec: str = "default_22d_agv"
    physics_group_names: Tuple[str, ...] = (
        "yaw_steering",
        "drive_current_load",
        "velocity_acceleration",
        "wheel_imbalance",
    )
    physics_group_indices: Tuple[Tuple[int, ...], ...] = (
        (0, 5, 6, 13, 21),
        (1, 2, 10, 11, 12, 17, 19, 18, 14),
        (7, 8, 15, 16, 20),
        (3, 4, 9),
    )


@dataclass
class ModernTCNModeThetaConfig(ModernTCNConfig):
    """Mode-conditioned theta expert variant for SCI E4."""

    theta_gate_detach: bool = True
    flat_theta_reg_lambda: float = 0.0
    theta_expert_hidden: int = 0


class CausalDepthwiseConv1d(nn.Module):
    """Depthwise causal Conv1d with ONNX-friendly Conv + Slice semantics."""

    def __init__(self, channels: int, kernel_size: int) -> None:
        super().__init__()
        if kernel_size < 1:
            raise ValueError("kernel_size 必须 >= 1。")
        self.trim = kernel_size - 1
        self.conv = nn.Conv1d(
            channels,
            channels,
            kernel_size,
            padding=self.trim,
            groups=channels,
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.conv(x)
        if self.trim == 0:
            return y
        return y[..., : x.size(-1)]


class ModernTCNBlock(nn.Module):
    """大核 depthwise conv + pointwise MLP 的残差块。"""

    def __init__(
        self,
        channels: int,
        kernel_size: int,
        dropout: float,
        expansion: int,
        temporal_padding: str = "same",
    ) -> None:
        super().__init__()
        hidden = int(channels * expansion)
        temporal_padding = str(temporal_padding).lower()
        if temporal_padding == "same":
            if kernel_size % 2 != 1:
                raise ValueError("same padding 模式下 kernel_size 必须为奇数。")
            padding = kernel_size // 2
            self.depthwise = nn.Conv1d(channels, channels, kernel_size, padding=padding, groups=channels)
        elif temporal_padding == "causal":
            self.depthwise = CausalDepthwiseConv1d(channels, kernel_size)
        else:
            raise ValueError(f"未知 temporal_padding: {temporal_padding}")
        self.temporal_padding = temporal_padding
        self.bn1 = nn.BatchNorm1d(channels)
        self.pw1 = nn.Conv1d(channels, hidden, kernel_size=1)
        self.pw2 = nn.Conv1d(hidden, channels, kernel_size=1)
        self.bn2 = nn.BatchNorm1d(channels)
        self.act = nn.ReLU(inplace=False)
        self.drop = nn.Dropout(dropout)
        # layer_scale 是常数形状参数，导出 ONNX 后只对应 Mul，MATLAB 侧更容易处理。
        self.layer_scale = nn.Parameter(torch.ones(1, channels, 1) * 1e-2)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = x
        y = self.depthwise(x)
        y = self.bn1(y)
        y = self.act(y)
        y = self.pw1(y)
        y = self.act(y)
        y = self.drop(y)
        y = self.pw2(y)
        y = self.bn2(y)
        y = self.drop(y)
        return residual + y * self.layer_scale


class ModernTCNDualKernelBlock(nn.Module):
    """Small-model temporal block with parallel large/small depthwise kernels."""

    def __init__(
        self,
        channels: int,
        large_kernel: int,
        small_kernel: int,
        dropout: float,
        expansion: int,
        dual_branch_scale: float,
        small_branch_init: str,
        layer_scale_init: float,
    ) -> None:
        super().__init__()
        if large_kernel < 1 or large_kernel % 2 != 1:
            raise ValueError("large_kernel 必须为正奇数。")
        if small_kernel < 1 or small_kernel % 2 != 1:
            raise ValueError("small_kernel 必须为正奇数。")
        if channels < 1:
            raise ValueError("channels 必须 >= 1。")
        small_branch_init = str(small_branch_init or "default").lower()
        if small_branch_init not in {"default", "zero"}:
            raise ValueError(f"未知 small_branch_init: {small_branch_init}")

        hidden = int(channels * expansion)
        self.large_branch = nn.Conv1d(
            channels,
            channels,
            kernel_size=large_kernel,
            padding=large_kernel // 2,
            groups=channels,
        )
        self.small_branch = nn.Conv1d(
            channels,
            channels,
            kernel_size=small_kernel,
            padding=small_kernel // 2,
            groups=channels,
        )
        if small_branch_init == "zero":
            nn.init.zeros_(self.small_branch.weight)
            if self.small_branch.bias is not None:
                nn.init.zeros_(self.small_branch.bias)

        self.dual_branch_scale = float(dual_branch_scale)
        self.temporal_bn = nn.BatchNorm1d(channels)
        self.pw1 = nn.Conv1d(channels, hidden, kernel_size=1)
        self.pw2 = nn.Conv1d(hidden, channels, kernel_size=1)
        self.bn2 = nn.BatchNorm1d(channels)
        self.act = nn.ReLU(inplace=False)
        self.drop = nn.Dropout(dropout)
        self.layer_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = x
        y = (self.large_branch(x) + self.small_branch(x)) * self.dual_branch_scale
        y = self.temporal_bn(y)
        y = self.act(y)
        y = self.pw1(y)
        y = self.act(y)
        y = self.drop(y)
        y = self.pw2(y)
        y = self.bn2(y)
        y = self.drop(y)
        return residual + y * self.layer_scale


class ModernTCNSmall(nn.Module):
    """固定输入 `[batch, time=128, features=22]` 的三输出多任务网络。"""

    def __init__(self, cfg: ModernTCNConfig) -> None:
        super().__init__()
        self.cfg = cfg
        self.stem = nn.Sequential(
            nn.Conv1d(cfg.input_dim, cfg.channels, kernel_size=1),
            nn.BatchNorm1d(cfg.channels),
            nn.ReLU(inplace=False),
        )
        self.blocks = nn.ModuleList(
            [
                ModernTCNBlock(
                    cfg.channels,
                    cfg.kernel_size,
                    cfg.dropout,
                    cfg.expansion,
                    temporal_padding=cfg.temporal_padding,
                )
                for _ in range(cfg.blocks)
            ]
        )
        feature_dim = cfg.channels * 3
        if cfg.readout_input_stats:
            feature_dim += cfg.input_dim * 5
        input_stats_dim = cfg.input_dim * 5
        turn_source = cfg.turn_head_source.lower()
        if turn_source == "full":
            turn_dim = feature_dim
        elif turn_source == "inputstats":
            turn_dim = input_stats_dim
        elif turn_source == "kinematic_stats":
            turn_indices = self._make_turn_stats_indices(cfg.input_dim, cfg.turn_feature_indices)
            self.register_buffer("turn_stats_indices", turn_indices, persistent=False)
            turn_dim = int(turn_indices.numel())
        else:
            raise ValueError(f"未知 turn_head_source: {cfg.turn_head_source}")
        self.turn_head_source = turn_source

        # 三个任务头严格对应 MATLAB 端后处理契约。
        self.main_head = nn.Linear(feature_dim, 3)
        self.turn_head = nn.Sequential(
            nn.Linear(turn_dim, 64),
            nn.ReLU(inplace=False),
            nn.Linear(64, 3),
        )
        self.theta_head = nn.Linear(feature_dim, 1)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        # x: [B, T, F]；Conv1d 使用 [B, F, T]。
        x_ct = x.transpose(1, 2)
        z = self.stem(x_ct)
        for block in self.blocks:
            z = block(z)

        h_last = z[:, :, -1]
        h_mean = z.mean(dim=2)
        h_max = z.amax(dim=2)
        pieces = [h_last, h_mean, h_max]
        input_stats = self._input_stats(x_ct)
        if self.cfg.readout_input_stats:
            pieces.append(input_stats)
        h = torch.cat(pieces, dim=1)
        logits_main = self.main_head(h)
        if self.turn_head_source == "full":
            h_turn = h
        elif self.turn_head_source == "inputstats":
            h_turn = input_stats
        else:
            h_turn = input_stats.index_select(1, self.turn_stats_indices)
        logits_turn = self.turn_head(h_turn)
        theta_hat = self.theta_head(h)
        theta_hat = self._apply_theta_gate(theta_hat, logits_main)
        return logits_main, logits_turn, theta_hat

    def _apply_theta_gate(self, theta_hat: torch.Tensor, logits_main: torch.Tensor) -> torch.Tensor:
        """Optionally suppress theta when the main head is confident the window is flat/stall."""

        mode = str(getattr(self.cfg, "theta_gate_mode", "none")).lower()
        if mode in ("", "none"):
            return theta_hat
        if mode != "main_slope_prob":
            raise ValueError(f"未知 theta_gate_mode: {self.cfg.theta_gate_mode}")
        slope_prob = torch.softmax(logits_main, dim=1)[:, 2:3]
        floor = float(getattr(self.cfg, "theta_gate_floor", 0.0))
        power = float(getattr(self.cfg, "theta_gate_power", 1.0))
        gate = floor + (1.0 - floor) * torch.pow(torch.clamp(slope_prob, min=1e-6), power)
        return theta_hat * gate

    @staticmethod
    def _input_stats(x_ct: torch.Tensor) -> torch.Tensor:
        """复用窗口级统计线索，但仍只来自同一输入窗口。"""

        x_last = x_ct[:, :, -1]
        x_mean = x_ct.mean(dim=2)
        x_std = torch.sqrt(torch.mean((x_ct - x_mean.unsqueeze(2)) ** 2, dim=2) + 1e-8)
        x_max = x_ct.amax(dim=2)
        x_min = x_ct.amin(dim=2)
        return torch.cat([x_last, x_mean, x_std, x_max, x_min], dim=1)

    @staticmethod
    def _make_turn_stats_indices(input_dim: int, feature_indices: Tuple[int, ...]) -> torch.Tensor:
        """Return gather indices for [last, mean, std, max, min] input stats."""

        idx = []
        for stat_block in range(5):
            base = stat_block * input_dim
            idx.extend(base + int(i) for i in feature_indices)
        return torch.tensor(idx, dtype=torch.long)


class ModernTCNDualKernelSmall(ModernTCNSmall):
    """Dual-kernel temporal branch with the same I/O contract as ModernTCNSmall."""

    def __init__(self, cfg: ModernTCNDualKernelConfig) -> None:
        if str(cfg.temporal_padding).lower() != "same":
            raise ValueError("small_dualkernel 第一阶段只支持 same padding。")
        super().__init__(cfg)
        self.blocks = nn.ModuleList(
            [
                ModernTCNDualKernelBlock(
                    cfg.channels,
                    cfg.large_kernel,
                    cfg.small_kernel,
                    cfg.dropout,
                    cfg.expansion,
                    cfg.dual_branch_scale,
                    cfg.small_branch_init,
                    cfg.layer_scale_init,
                )
                for _ in range(cfg.blocks)
            ]
        )


class PhysicsGroupTemporalBranch(nn.Module):
    """Lightweight temporal branch for one physics feature group."""

    def __init__(self, group_dim: int, channels: int, branch_channels: int, kernel_size: int) -> None:
        super().__init__()
        if group_dim < 1:
            raise ValueError("physics group_dim must be >= 1")
        if branch_channels < 1:
            raise ValueError("branch_channels must be >= 1")
        if kernel_size < 1 or kernel_size % 2 != 1:
            raise ValueError("branch_kernel must be a positive odd integer")
        self.net = nn.Sequential(
            nn.Conv1d(group_dim, branch_channels, kernel_size=1),
            nn.BatchNorm1d(branch_channels),
            nn.ReLU(inplace=False),
            nn.Conv1d(
                branch_channels,
                branch_channels,
                kernel_size=kernel_size,
                padding=kernel_size // 2,
                groups=branch_channels,
            ),
            nn.BatchNorm1d(branch_channels),
            nn.ReLU(inplace=False),
            nn.Conv1d(branch_channels, channels, kernel_size=1),
            nn.BatchNorm1d(channels),
            nn.ReLU(inplace=False),
        )

    def forward(self, x_ct: torch.Tensor) -> torch.Tensor:
        return self.net(x_ct)


class ModernTCNPhysicsGroupGateSmall(ModernTCNSmall):
    """ModernTCN-small with trunk-level AGV physics-group residual gate."""

    def __init__(self, cfg: ModernTCNPhysicsGroupGateConfig) -> None:
        if str(cfg.temporal_padding).lower() != "same":
            raise ValueError("small_physics_group_gate 第一阶段只支持 same padding。")
        super().__init__(cfg)
        self.cfg = cfg
        self.group_names = tuple(str(x) for x in cfg.physics_group_names)
        self.group_indices = tuple(tuple(int(i) for i in group) for group in cfg.physics_group_indices)
        self._validate_groups(cfg.input_dim)
        self.group_branches = nn.ModuleList(
            [
                PhysicsGroupTemporalBranch(
                    len(indices),
                    cfg.channels,
                    int(cfg.branch_channels),
                    int(cfg.branch_kernel),
                )
                for indices in self.group_indices
            ]
        )
        for idx, indices in enumerate(self.group_indices):
            self.register_buffer(
                f"physics_group_indices_{idx}",
                torch.tensor(indices, dtype=torch.long),
                persistent=False,
            )
        n_groups = len(self.group_indices)
        gate_in = int(cfg.channels) * n_groups
        self.physics_gate = nn.Sequential(
            nn.Linear(gate_in, int(cfg.gate_hidden)),
            nn.ReLU(inplace=False),
            nn.Linear(int(cfg.gate_hidden), n_groups),
        )
        self.alpha = nn.Parameter(torch.tensor(float(cfg.alpha_init), dtype=torch.float32))
        self._last_gate_weights = None

    def _validate_groups(self, input_dim: int) -> None:
        if len(self.group_names) != len(self.group_indices):
            raise ValueError("physics_group_names and physics_group_indices length mismatch")
        if not self.group_indices:
            raise ValueError("small_physics_group_gate requires at least one non-empty group")
        seen: List[int] = []
        for name, indices in zip(self.group_names, self.group_indices):
            if not indices:
                raise ValueError(f"physics group {name} is empty; omit empty groups from the gate")
            for idx in indices:
                if idx < 0 or idx >= input_dim:
                    raise ValueError(f"physics group {name} index {idx} is outside input_dim={input_dim}")
                seen.append(idx)
        if len(seen) != len(set(seen)):
            raise ValueError("physics group indices contain duplicates")

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if not torch.jit.is_tracing() and x.ndim != 3:
            raise ValueError(f"ModernTCNPhysicsGroupGateSmall 期望输入 [B,T,F]，实际 ndim={x.ndim}")
        x_ct = x.transpose(1, 2)
        z = self.stem(x_ct)
        for block in self.blocks:
            z = block(z)

        group_z = []
        group_pooled = []
        for idx, branch in enumerate(self.group_branches):
            indices = getattr(self, f"physics_group_indices_{idx}")
            x_group = x_ct.index_select(1, indices)
            z_group = branch(x_group)
            group_z.append(z_group)
            group_pooled.append(z_group.mean(dim=2))
        gate_logits = self.physics_gate(torch.cat(group_pooled, dim=1))
        gate_weights = torch.softmax(gate_logits, dim=1)
        z_phys = torch.zeros_like(z)
        for idx, z_group in enumerate(group_z):
            z_phys = z_phys + gate_weights[:, idx].reshape(-1, 1, 1) * z_group
        z = z + self.alpha * z_phys
        if not torch.jit.is_tracing():
            self._last_gate_weights = gate_weights.detach()

        h_last = z[:, :, -1]
        h_mean = z.mean(dim=2)
        h_max = z.amax(dim=2)
        pieces = [h_last, h_mean, h_max]
        input_stats = self._input_stats(x_ct)
        if self.cfg.readout_input_stats:
            pieces.append(input_stats)
        h = torch.cat(pieces, dim=1)
        logits_main = self.main_head(h)
        if self.turn_head_source == "full":
            h_turn = h
        elif self.turn_head_source == "inputstats":
            h_turn = input_stats
        else:
            h_turn = input_stats.index_select(1, self.turn_stats_indices)
        logits_turn = self.turn_head(h_turn)
        theta_hat = self.theta_head(h)
        theta_hat = self._apply_theta_gate(theta_hat, logits_main)
        return logits_main, logits_turn, theta_hat

    @torch.no_grad()
    def collect_gate_weights(self, x: torch.Tensor) -> torch.Tensor:
        was_training = self.training
        self.eval()
        x_ct = x.transpose(1, 2)
        group_pooled = []
        for idx, branch in enumerate(self.group_branches):
            indices = getattr(self, f"physics_group_indices_{idx}")
            group_pooled.append(branch(x_ct.index_select(1, indices)).mean(dim=2))
        gate_weights = torch.softmax(self.physics_gate(torch.cat(group_pooled, dim=1)), dim=1)
        if was_training:
            self.train()
        return gate_weights

    def e3_state(self) -> Dict[str, object]:
        return {
            "alpha": float(self.alpha.detach().cpu()),
            "physics_group_names": list(self.group_names),
            "physics_group_indices": [list(x) for x in self.group_indices],
        }


class ModernTCNModeThetaSmall(ModernTCNSmall):
    """ModernTCN-small with mode-conditioned theta experts."""

    def __init__(self, cfg: ModernTCNModeThetaConfig) -> None:
        super().__init__(cfg)
        self.cfg = cfg
        feature_dim = int(self.theta_head.in_features)
        self.theta_flat_head = self._make_theta_expert(feature_dim, cfg)
        self.theta_stall_head = self._make_theta_expert(feature_dim, cfg)
        self.theta_slope_head = self._make_theta_expert(feature_dim, cfg)
        del self.theta_head

    @staticmethod
    def _make_theta_expert(feature_dim: int, cfg: ModernTCNModeThetaConfig) -> nn.Module:
        hidden = int(getattr(cfg, "theta_expert_hidden", 0) or 0)
        if hidden <= 0:
            return nn.Linear(feature_dim, 1)
        return nn.Sequential(
            nn.Linear(feature_dim, hidden),
            nn.ReLU(inplace=False),
            nn.Linear(hidden, 1),
        )

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        logits_main, logits_turn, theta_hat, _ = self._forward_impl(x, detach_override=None, include_details=False)
        return logits_main, logits_turn, theta_hat

    def forward_experts(self, x: torch.Tensor, detach_override: bool | None = None) -> Dict[str, torch.Tensor]:
        logits_main, logits_turn, theta_hat, details = self._forward_impl(
            x,
            detach_override=detach_override,
            include_details=True,
        )
        details["logits_main"] = logits_main
        details["logits_turn"] = logits_turn
        details["theta_hat"] = theta_hat
        return details

    def _forward_impl(
        self,
        x: torch.Tensor,
        detach_override: bool | None,
        include_details: bool,
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, Dict[str, torch.Tensor]]:
        x_ct = x.transpose(1, 2)
        z = self.stem(x_ct)
        for block in self.blocks:
            z = block(z)

        h_last = z[:, :, -1]
        h_mean = z.mean(dim=2)
        h_max = z.amax(dim=2)
        pieces = [h_last, h_mean, h_max]
        input_stats = self._input_stats(x_ct)
        if self.cfg.readout_input_stats:
            pieces.append(input_stats)
        h = torch.cat(pieces, dim=1)

        logits_main = self.main_head(h)
        if self.turn_head_source == "full":
            h_turn = h
        elif self.turn_head_source == "inputstats":
            h_turn = input_stats
        else:
            h_turn = input_stats.index_select(1, self.turn_stats_indices)
        logits_turn = self.turn_head(h_turn)

        theta_flat = self.theta_flat_head(h)
        theta_stall = self.theta_stall_head(h)
        theta_slope = self.theta_slope_head(h)
        main_prob = torch.softmax(logits_main, dim=1)
        detach = bool(getattr(self.cfg, "theta_gate_detach", True)) if detach_override is None else bool(detach_override)
        gate_prob = main_prob.detach() if detach else main_prob
        experts = torch.cat([theta_flat, theta_stall, theta_slope], dim=1)
        contributions = experts * gate_prob
        theta_hat = contributions.sum(dim=1, keepdim=True)
        theta_hat = self._apply_theta_gate(theta_hat, logits_main)

        details: Dict[str, torch.Tensor] = {}
        if include_details:
            details = {
                "theta_flat": theta_flat,
                "theta_stall": theta_stall,
                "theta_slope": theta_slope,
                "theta_experts": experts,
                "main_prob": main_prob,
                "gate_prob": gate_prob,
                "theta_contributions": contributions,
                "theta_gate_detach": torch.tensor(detach, device=x.device),
            }
        return logits_main, logits_turn, theta_hat, details

    def e4_state(self) -> Dict[str, object]:
        return {
            "theta_gate_detach": bool(getattr(self.cfg, "theta_gate_detach", True)),
            "flat_theta_reg_lambda": float(getattr(self.cfg, "flat_theta_reg_lambda", 0.0)),
            "theta_expert_hidden": int(getattr(self.cfg, "theta_expert_hidden", 0)),
        }


class ModernTCNFullProjection(nn.Module):
    """对每个变量独立做 stage 之间的通道投影。"""

    def __init__(self, nvars: int, dim_in: int, dim_out: int) -> None:
        super().__init__()
        self.nvars = int(nvars)
        self.dim_in = int(dim_in)
        self.dim_out = int(dim_out)
        self.proj = nn.Conv1d(dim_in, dim_out, kernel_size=1)
        self.bn = nn.BatchNorm1d(dim_out)
        self.act = nn.ReLU(inplace=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        bsz, _, tokens = x.shape
        y = x.reshape(bsz, self.nvars, self.dim_in, tokens).reshape(bsz * self.nvars, self.dim_in, tokens)
        y = self.proj(y)
        y = self.bn(y)
        y = self.act(y)
        return y.reshape(bsz, self.nvars, self.dim_out, tokens).reshape(bsz, self.nvars * self.dim_out, tokens)


class ModernTCNGroupedBlock(nn.Module):
    """Temporal depthwise conv + variable FFN + channel FFN with sub-residuals."""

    def __init__(
        self,
        nvars: int,
        dmodel: int,
        kernel_size: int,
        ffn_ratio: int,
        dropout: float,
        layer_scale_init: float,
    ) -> None:
        super().__init__()
        if kernel_size < 1 or kernel_size % 2 != 1:
            raise ValueError("kernel_size 必须为正奇数。")
        if nvars < 1 or dmodel < 1:
            raise ValueError("nvars 和 dmodel 必须 >= 1。")
        if ffn_ratio < 1:
            raise ValueError("ffn_ratio 必须 >= 1。")
        self.nvars = int(nvars)
        self.dmodel = int(dmodel)
        channels = self.nvars * self.dmodel
        hidden = channels * int(ffn_ratio)

        self.temporal = nn.Conv1d(
            channels,
            channels,
            kernel_size=kernel_size,
            padding=kernel_size // 2,
            groups=channels,
        )
        self.temporal_bn = nn.BatchNorm1d(channels)

        self.var_ffn_1 = nn.Conv1d(channels, hidden, kernel_size=1, groups=self.nvars)
        self.var_ffn_2 = nn.Conv1d(hidden, channels, kernel_size=1, groups=self.nvars)
        self.var_bn = nn.BatchNorm1d(channels)

        self.channel_ffn_1 = nn.Conv1d(channels, hidden, kernel_size=1, groups=self.dmodel)
        self.channel_ffn_2 = nn.Conv1d(hidden, channels, kernel_size=1, groups=self.dmodel)
        self.channel_bn = nn.BatchNorm1d(channels)

        self.act = nn.ReLU(inplace=False)
        self.drop = nn.Dropout(dropout)
        self.temporal_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))
        self.var_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))
        self.channel_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.temporal(x)
        y = self.temporal_bn(y)
        y = self.act(y)
        y = self.drop(y)
        x = x + y * self.temporal_scale

        y = self.var_ffn_1(x)
        y = self.act(y)
        y = self.drop(y)
        y = self.var_ffn_2(y)
        y = self.var_bn(y)
        y = self.drop(y)
        x = x + y * self.var_scale

        y = self._var_major_to_channel_major(x)
        y = self.channel_ffn_1(y)
        y = self.act(y)
        y = self.drop(y)
        y = self.channel_ffn_2(y)
        y = self._channel_major_to_var_major(y)
        y = self.channel_bn(y)
        y = self.drop(y)
        return x + y * self.channel_scale

    def _var_major_to_channel_major(self, x: torch.Tensor) -> torch.Tensor:
        bsz, _, tokens = x.shape
        return (
            x.reshape(bsz, self.nvars, self.dmodel, tokens)
            .permute(0, 2, 1, 3)
            .contiguous()
            .reshape(bsz, self.dmodel * self.nvars, tokens)
        )

    def _channel_major_to_var_major(self, x: torch.Tensor) -> torch.Tensor:
        bsz, _, tokens = x.shape
        return (
            x.reshape(bsz, self.dmodel, self.nvars, tokens)
            .permute(0, 2, 1, 3)
            .contiguous()
            .reshape(bsz, self.nvars * self.dmodel, tokens)
        )


class ModernTCNGroupedSmall(nn.Module):
    """Grouped ConvFFN small model with the same I/O contract as ModernTCNSmall."""

    def __init__(self, cfg: ModernTCNGroupedConfig) -> None:
        super().__init__()
        self.cfg = cfg
        self.nvars = int(cfg.input_dim)
        self.dmodel = int(cfg.dmodel)
        channels = self.nvars * self.dmodel
        self.var_embed = nn.Sequential(
            nn.Conv1d(1, self.dmodel, kernel_size=1),
            nn.BatchNorm1d(self.dmodel),
            nn.ReLU(inplace=False),
        )
        self.blocks = nn.ModuleList(
            [
                ModernTCNGroupedBlock(
                    self.nvars,
                    self.dmodel,
                    cfg.kernel_size,
                    cfg.ffn_ratio,
                    cfg.dropout,
                    cfg.layer_scale_init,
                )
                for _ in range(cfg.blocks)
            ]
        )

        feature_dim = channels * 3
        if cfg.readout_input_stats:
            feature_dim += cfg.input_dim * 5
        input_stats_dim = cfg.input_dim * 5
        turn_source = cfg.turn_head_source.lower()
        if turn_source == "full":
            turn_dim = feature_dim
        elif turn_source == "inputstats":
            turn_dim = input_stats_dim
        elif turn_source == "kinematic_stats":
            turn_indices = ModernTCNSmall._make_turn_stats_indices(cfg.input_dim, cfg.turn_feature_indices)
            self.register_buffer("turn_stats_indices", turn_indices, persistent=False)
            turn_dim = int(turn_indices.numel())
        else:
            raise ValueError(f"未知 turn_head_source: {cfg.turn_head_source}")
        self.turn_head_source = turn_source

        self.main_head = nn.Linear(feature_dim, 3)
        self.turn_head = nn.Sequential(
            nn.Linear(turn_dim, 64),
            nn.ReLU(inplace=False),
            nn.Linear(64, 3),
        )
        self.theta_head = nn.Linear(feature_dim, 1)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if not torch.jit.is_tracing() and x.ndim != 3:
            raise ValueError(f"ModernTCNGroupedSmall 期望输入 [B,T,F]，实际 ndim={x.ndim}")
        bsz, seq_len, nvars = x.shape
        if not torch.jit.is_tracing() and (seq_len != self.cfg.seq_len or nvars != self.cfg.input_dim):
            raise ValueError(
                f"ModernTCNGroupedSmall 输入 shape 不匹配，期望 [B,{self.cfg.seq_len},{self.cfg.input_dim}]，"
                f"实际 {tuple(x.shape)}"
            )

        x_ct = x.transpose(1, 2)
        z = self.var_embed(x_ct.reshape(bsz * self.nvars, 1, self.cfg.seq_len))
        z = z.reshape(bsz, self.nvars, self.dmodel, self.cfg.seq_len).reshape(
            bsz, self.nvars * self.dmodel, self.cfg.seq_len
        )
        for block in self.blocks:
            z = block(z)

        h_last = z[:, :, -1]
        h_mean = z.mean(dim=2)
        h_max = z.amax(dim=2)
        pieces = [h_last, h_mean, h_max]
        input_stats = ModernTCNSmall._input_stats(x_ct)
        if self.cfg.readout_input_stats:
            pieces.append(input_stats)
        h = torch.cat(pieces, dim=1)
        logits_main = self.main_head(h)
        if self.turn_head_source == "full":
            h_turn = h
        elif self.turn_head_source == "inputstats":
            h_turn = input_stats
        else:
            h_turn = input_stats.index_select(1, self.turn_stats_indices)
        logits_turn = self.turn_head(h_turn)
        theta_hat = self.theta_head(h)
        theta_hat = ModernTCNSmall._apply_theta_gate(self, theta_hat, logits_main)
        return logits_main, logits_turn, theta_hat


class ModernTCNFullBlock(nn.Module):
    """ModernTCNFull v0：大核时间卷积 + 变量内 FFN + 通道维 FFN。"""

    def __init__(
        self,
        nvars: int,
        dmodel: int,
        large_kernel: int,
        small_kernel: int,
        ffn_ratio: int,
        dropout: float,
        layer_scale_init: float,
    ) -> None:
        super().__init__()
        if large_kernel < 1 or large_kernel % 2 != 1:
            raise ValueError("large_kernel 必须为正奇数。")
        if small_kernel < 1 or small_kernel % 2 != 1:
            raise ValueError("small_kernel 必须为正奇数。")
        if ffn_ratio < 1:
            raise ValueError("ffn_ratio 必须 >= 1。")
        self.nvars = int(nvars)
        self.dmodel = int(dmodel)
        channels = self.nvars * self.dmodel
        var_hidden = self.nvars * self.dmodel * int(ffn_ratio)
        channel_hidden = self.dmodel * self.nvars * int(ffn_ratio)

        self.large_temporal = nn.Conv1d(
            channels,
            channels,
            kernel_size=large_kernel,
            padding=large_kernel // 2,
            groups=channels,
        )
        self.small_temporal = nn.Conv1d(
            channels,
            channels,
            kernel_size=small_kernel,
            padding=small_kernel // 2,
            groups=channels,
        )
        self.temporal_bn = nn.BatchNorm1d(channels)

        self.var_ffn_1 = nn.Conv1d(channels, var_hidden, kernel_size=1, groups=self.nvars)
        self.var_ffn_2 = nn.Conv1d(var_hidden, channels, kernel_size=1, groups=self.nvars)
        self.var_bn = nn.BatchNorm1d(channels)

        self.channel_ffn_1 = nn.Conv1d(channels, channel_hidden, kernel_size=1, groups=self.dmodel)
        self.channel_ffn_2 = nn.Conv1d(channel_hidden, channels, kernel_size=1, groups=self.dmodel)
        self.channel_bn = nn.BatchNorm1d(channels)

        self.act = nn.ReLU(inplace=False)
        self.drop = nn.Dropout(dropout)
        self.temporal_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))
        self.var_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))
        self.channel_scale = nn.Parameter(torch.ones(1, channels, 1) * float(layer_scale_init))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.large_temporal(x) + self.small_temporal(x)
        y = self.temporal_bn(y)
        y = self.act(y)
        y = self.drop(y)
        x = x + y * self.temporal_scale

        y = self.var_ffn_1(x)
        y = self.act(y)
        y = self.drop(y)
        y = self.var_ffn_2(y)
        y = self.var_bn(y)
        y = self.drop(y)
        x = x + y * self.var_scale

        y = self._var_major_to_channel_major(x)
        y = self.channel_ffn_1(y)
        y = self.act(y)
        y = self.drop(y)
        y = self.channel_ffn_2(y)
        y = self._channel_major_to_var_major(y)
        y = self.channel_bn(y)
        y = self.drop(y)
        return x + y * self.channel_scale

    def _var_major_to_channel_major(self, x: torch.Tensor) -> torch.Tensor:
        bsz, _, tokens = x.shape
        return (
            x.reshape(bsz, self.nvars, self.dmodel, tokens)
            .permute(0, 2, 1, 3)
            .contiguous()
            .reshape(bsz, self.dmodel * self.nvars, tokens)
        )

    def _channel_major_to_var_major(self, x: torch.Tensor) -> torch.Tensor:
        bsz, _, tokens = x.shape
        return (
            x.reshape(bsz, self.dmodel, self.nvars, tokens)
            .permute(0, 2, 1, 3)
            .contiguous()
            .reshape(bsz, self.nvars * self.dmodel, tokens)
        )


class ModernTCNFull(nn.Module):
    """ModernTCNFull v0，并行候选模型，输入输出契约与 small 保持一致。"""

    def __init__(self, cfg: ModernTCNFullConfig) -> None:
        super().__init__()
        self.cfg = cfg
        self._validate_config(cfg)
        self.nvars = int(cfg.input_dim)
        self.dims = tuple(int(v) for v in cfg.dims)
        self.patch_stem = nn.Sequential(
            nn.Conv1d(1, self.dims[0], kernel_size=cfg.patch_size, stride=cfg.patch_stride),
            nn.BatchNorm1d(self.dims[0]),
            nn.ReLU(inplace=False),
        )

        stages = []
        prev_dim = self.dims[0]
        for stage_idx, dim in enumerate(self.dims):
            layers = []
            if stage_idx > 0 and prev_dim != dim:
                layers.append(ModernTCNFullProjection(self.nvars, prev_dim, dim))
            for _ in range(int(cfg.stage_blocks[stage_idx])):
                layers.append(
                    ModernTCNFullBlock(
                        self.nvars,
                        dim,
                        int(cfg.large_kernels[stage_idx]),
                        int(cfg.small_kernels[stage_idx]),
                        int(cfg.ffn_ratio),
                        float(cfg.dropout),
                        float(cfg.layer_scale_init),
                    )
                )
            stages.append(nn.Sequential(*layers))
            prev_dim = dim
        self.stages = nn.ModuleList(stages)

        feature_dim = self.nvars * self.dims[-1] * 3
        if cfg.readout_input_stats:
            feature_dim += cfg.input_dim * 5
        input_stats_dim = cfg.input_dim * 5
        turn_source = cfg.turn_head_source.lower()
        if turn_source == "full":
            turn_dim = feature_dim
        elif turn_source == "inputstats":
            turn_dim = input_stats_dim
        elif turn_source == "kinematic_stats":
            turn_indices = ModernTCNSmall._make_turn_stats_indices(cfg.input_dim, cfg.turn_feature_indices)
            self.register_buffer("turn_stats_indices", turn_indices, persistent=False)
            turn_dim = int(turn_indices.numel())
        else:
            raise ValueError(f"未知 turn_head_source: {cfg.turn_head_source}")
        self.turn_head_source = turn_source

        self.main_head = nn.Linear(feature_dim, 3)
        self.turn_head = nn.Sequential(
            nn.Linear(turn_dim, 64),
            nn.ReLU(inplace=False),
            nn.Linear(64, 3),
        )
        self.theta_head = nn.Linear(feature_dim, 1)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if not torch.jit.is_tracing() and x.ndim != 3:
            raise ValueError(f"ModernTCNFull 期望输入 [B,T,F]，实际 ndim={x.ndim}")
        bsz, seq_len, nvars = x.shape
        if not torch.jit.is_tracing() and (seq_len != self.cfg.seq_len or nvars != self.cfg.input_dim):
            raise ValueError(
                f"ModernTCNFull 输入 shape 不匹配，期望 [B,{self.cfg.seq_len},{self.cfg.input_dim}]，"
                f"实际 {tuple(x.shape)}"
            )

        x_ct = x.transpose(1, 2)
        z = self.patch_stem(x_ct.reshape(bsz * self.nvars, 1, self.cfg.seq_len))
        tokens = z.size(-1)
        z = z.reshape(bsz, self.nvars, self.dims[0], tokens).reshape(bsz, self.nvars * self.dims[0], tokens)
        for stage in self.stages:
            z = stage(z)

        h_last = z[:, :, -1]
        h_mean = z.mean(dim=2)
        h_max = z.amax(dim=2)
        pieces = [h_last, h_mean, h_max]
        input_stats = ModernTCNSmall._input_stats(x_ct)
        if self.cfg.readout_input_stats:
            pieces.append(input_stats)
        h = torch.cat(pieces, dim=1)
        logits_main = self.main_head(h)
        if self.turn_head_source == "full":
            h_turn = h
        elif self.turn_head_source == "inputstats":
            h_turn = input_stats
        else:
            h_turn = input_stats.index_select(1, self.turn_stats_indices)
        logits_turn = self.turn_head(h_turn)
        theta_hat = self.theta_head(h)
        theta_hat = ModernTCNSmall._apply_theta_gate(self, theta_hat, logits_main)
        return logits_main, logits_turn, theta_hat

    @staticmethod
    def _validate_config(cfg: ModernTCNFullConfig) -> None:
        n_stage = len(cfg.dims)
        if n_stage == 0:
            raise ValueError("dims 至少需要一个 stage。")
        if len(cfg.stage_blocks) != n_stage or len(cfg.large_kernels) != n_stage or len(cfg.small_kernels) != n_stage:
            raise ValueError("dims/stage_blocks/large_kernels/small_kernels 长度必须一致。")
        if cfg.patch_size < 1 or cfg.patch_stride < 1:
            raise ValueError("patch_size 和 patch_stride 必须 >= 1。")
        if cfg.seq_len < cfg.patch_size:
            raise ValueError("seq_len 必须不小于 patch_size。")
        if any(int(d) < 1 for d in cfg.dims):
            raise ValueError("dims 中每个维度必须 >= 1。")


_TUPLE_CONFIG_FIELDS = {
    "main_class_multipliers",
    "turn_class_multipliers",
    "turn_feature_indices",
    "dims",
    "stage_blocks",
    "large_kernels",
    "small_kernels",
    "physics_group_names",
    "physics_group_indices",
}


def normalize_model_family(model_family: object) -> str:
    """将 checkpoint/CLI 中的模型族名称规范化，缺省保持 small。"""

    family = str(model_family or "small").strip().lower()
    aliases = {
        "modern_tcn": "small",
        "moderntcn": "small",
        "modern_tcn_small": "small",
        "moderntcnsmall": "small",
        "modern_tcn_full": "full",
        "moderntcnfull": "full",
        "modern_tcn_grouped": "small_gffn",
        "moderntcngrouped": "small_gffn",
        "modern_tcn_gffn": "small_gffn",
        "gffn": "small_gffn",
        "modern_tcn_dualkernel": "small_dualkernel",
        "modern_tcn_dual_kernel": "small_dualkernel",
        "moderntcndualkernel": "small_dualkernel",
        "dualkernel": "small_dualkernel",
        "dual_kernel": "small_dualkernel",
        "modern_tcn_physics_group_gate": "small_physics_group_gate",
        "modern_tcn_pg": "small_physics_group_gate",
        "pg_modern_tcn_small": "small_physics_group_gate",
        "physics_group_gate": "small_physics_group_gate",
        "modern_tcn_mode_theta": "small_mode_theta",
        "mode_theta": "small_mode_theta",
        "mode_conditioned_theta": "small_mode_theta",
    }
    family = aliases.get(family, family)
    if family not in {"small", "full", "small_gffn", "small_dualkernel", "small_physics_group_gate", "small_mode_theta"}:
        raise ValueError(f"未知 model_family: {model_family}")
    return family


def _config_from_dict(cfg_cls, cfg_dict: Dict[str, object]):
    valid_fields = {f.name for f in fields(cfg_cls)}
    filtered = {k: v for k, v in dict(cfg_dict).items() if k in valid_fields}
    for key in _TUPLE_CONFIG_FIELDS:
        if key in filtered and filtered[key] is not None:
            if key == "physics_group_indices":
                filtered[key] = tuple(tuple(int(i) for i in group) for group in filtered[key])
            else:
                filtered[key] = tuple(filtered[key])
    return cfg_cls(**filtered)


def build_model_from_config(cfg: ModernTCNConfig, model_family: object = "small") -> nn.Module:
    """根据模型族和配置实例化模型。"""

    family = normalize_model_family(model_family)
    if family == "small_dualkernel":
        if isinstance(cfg, ModernTCNDualKernelConfig):
            dual_cfg = cfg
        else:
            dual_cfg = _config_from_dict(ModernTCNDualKernelConfig, cfg.to_dict())
        return ModernTCNDualKernelSmall(dual_cfg)
    if family == "small_gffn":
        if isinstance(cfg, ModernTCNGroupedConfig):
            grouped_cfg = cfg
        else:
            grouped_cfg = _config_from_dict(ModernTCNGroupedConfig, cfg.to_dict())
        return ModernTCNGroupedSmall(grouped_cfg)
    if family == "small_physics_group_gate":
        if isinstance(cfg, ModernTCNPhysicsGroupGateConfig):
            pg_cfg = cfg
        else:
            pg_cfg = _config_from_dict(ModernTCNPhysicsGroupGateConfig, cfg.to_dict())
        return ModernTCNPhysicsGroupGateSmall(pg_cfg)
    if family == "small_mode_theta":
        if isinstance(cfg, ModernTCNModeThetaConfig):
            mt_cfg = cfg
        else:
            mt_cfg = _config_from_dict(ModernTCNModeThetaConfig, cfg.to_dict())
        return ModernTCNModeThetaSmall(mt_cfg)
    if family == "full":
        if isinstance(cfg, ModernTCNFullConfig):
            full_cfg = cfg
        else:
            full_cfg = _config_from_dict(ModernTCNFullConfig, cfg.to_dict())
        return ModernTCNFull(full_cfg)
    if isinstance(cfg, ModernTCNFullConfig):
        small_cfg = _config_from_dict(ModernTCNConfig, cfg.to_dict())
    else:
        small_cfg = cfg
    return ModernTCNSmall(small_cfg)


def build_model_from_checkpoint_dict(ckpt: Dict[str, object]) -> nn.Module:
    """按 checkpoint 中的模型族和配置恢复模型结构。"""

    family = normalize_model_family(ckpt.get("model_family", "small"))
    cfg_cls = (
        ModernTCNFullConfig
        if family == "full"
        else ModernTCNDualKernelConfig
        if family == "small_dualkernel"
        else ModernTCNGroupedConfig
        if family == "small_gffn"
        else ModernTCNPhysicsGroupGateConfig
        if family == "small_physics_group_gate"
        else ModernTCNModeThetaConfig
        if family == "small_mode_theta"
        else ModernTCNConfig
    )
    cfg = _config_from_dict(cfg_cls, dict(ckpt["model_config"]))
    model = build_model_from_config(cfg, family)
    model.load_state_dict(ckpt["model_state"])
    return model
