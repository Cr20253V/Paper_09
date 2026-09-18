% =============================
% 文件名：run_GRU_prepare_dataset_mamba_compare.m
% 版本号：V1.0（GRU 对照组预处理一键脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   使用 Mamba 母集一键生成 GRU 训练所需预处理数据，且不修改 Mamba 代码。
%   本脚本面向“GRU 作为对照组、Mamba 作为实验组”的公平对比场景。
%
%   对齐策略：
%   1) 数据源对齐：输入固定为 data/mamba/Mamba_train_data_full.mat
%   2) 滑窗参数对齐：seq_len=128, stride=64
%   3) Run 划分对齐：split_policy='mamba_like'，seed=42，ratio=80/10/10
%   4) 默认分布策略：strict 同分布（关闭重采样）
%      可选：打开 stall_optimized 消融模式
%
% 使用方法：
%   直接运行脚本：run('src/gru/run_GRU_prepare_dataset_mamba_compare.m')
%
% 输出：
%   - data/gru/GRU_dataset_processed.mat
%   - data/gru/GRU_scaler.mat
%   - data/gru/GRU_run_split.mat（当 save_split_file=true）
%
% 依赖：
%   - project_root.m
%   - src/gru/GRU_prepare_dataset.m
%   - data/mamba/Mamba_train_data_full.mat
%
% 备注：
%   - 本脚本默认推荐基线（strict 同分布）。
%   - 若需做消融，可将 `enable_stall_optimization` 改为 true。
%   - 如需参数扫描，可在本脚本中修改 cfg 字段后再运行。
% =============================

root = project_root();

if ~exist('cfg', 'var') || ~isstruct(cfg)
    cfg = struct();
end

% 默认实验画像：strict 基线（推荐）
% true: stall_optimized（消融）
% false: strict 同分布（推荐）
if ~isfield(cfg, 'enable_stall_optimization')
	cfg.enable_stall_optimization = false;
end

% -------- 数据源（母集） --------
cfg.dataset_source = 'mamba';
cfg.input_file = fullfile(root, 'data', 'mamba', 'Mamba_train_data_full.mat');

% -------- 与 Mamba export 对齐的核心超参 --------
cfg.seq_len = 128;
cfg.stride = 64;

% Mamba 的导出脚本默认不跳过起始段；若要严格一致，设为 0
cfg.skip_initial_sec = 0.0;

% Mamba export: train=0.80, val=0.10, test=rest
cfg.train_ratio = 0.80;
cfg.val_ratio = 0.10;
cfg.test_ratio = 0.10;

% Mamba export 固定 rng(42)
cfg.seed = 42;

% 让 GRU 的 run split 复现 Mamba 的 randperm(N_runs) 划分方式
cfg.split_policy = 'mamba_like';

if cfg.enable_stall_optimization
    % stall_optimized（消融分支）
    % 说明：
    %   - stall 过采样：从原始样本提升到 max(multiplier*原始, target_min)
    %   - flat 欠采样：限制为 flat <= flat_max_ratio * min(stall, slope)
    cfg.enable_train_resampling = true;
    cfg.resample_stall_multiplier = 3.0;
    cfg.resample_stall_target_min = 900;
    cfg.resample_flat_max_ratio = 30.0;
else
    % strict 同分布（推荐基线）
    cfg.enable_train_resampling = false;
end

% 可选：保存 run-level split，便于复现实验
cfg.save_split_file = true;
cfg.split_file = fullfile(root, 'data', 'gru', 'GRU_run_split.mat');

% 输出位置（GRU 侧）
cfg.output_file = fullfile(root, 'data', 'gru', 'GRU_dataset_processed.mat');
cfg.scaler_file = fullfile(root, 'data', 'gru', 'GRU_scaler.mat');

cfg.verbose = true;

run(fullfile(root, 'src', 'gru', 'GRU_prepare_dataset.m'));
