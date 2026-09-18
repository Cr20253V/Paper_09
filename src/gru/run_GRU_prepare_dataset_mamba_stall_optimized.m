% =============================
% 文件名：run_GRU_prepare_dataset_mamba_stall_optimized.m
% 版本号：V1.0（GRU stall_optimized 预处理一键脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   生成 stall_optimized 消融分支数据集：
%   - 复现 Mamba run-level 划分（mamba_like）
%   - 开启训练集重采样（stall 过采样 + flat 受限欠采样）
%   - 输出使用 _mamba_opt 后缀，避免覆盖 strict 基线产物
%
% 使用方法：
%   直接运行脚本：run('src/gru/run_GRU_prepare_dataset_mamba_stall_optimized.m')
%
% 输出：
%   - data/gru/GRU_dataset_processed_mamba_opt.mat
%   - data/gru/GRU_scaler_mamba_opt.mat
%   - data/gru/GRU_run_split_mamba_opt.mat
%
% 依赖：
%   - project_root.m
%   - src/gru/GRU_prepare_dataset.m
%   - data/mamba/Mamba_train_data_full.mat
% =============================

root = project_root();

cfg = struct();

% -------- 数据源（母集） --------
cfg.dataset_source = 'mamba';
cfg.input_file = fullfile(root, 'data', 'mamba', 'Mamba_train_data_full.mat');

% -------- 与 Mamba export 对齐的核心超参 --------
cfg.seq_len = 128;
cfg.stride = 64;
cfg.skip_initial_sec = 0.0;

% -------- 划分配置 --------
cfg.train_ratio = 0.80;
cfg.val_ratio = 0.10;
cfg.test_ratio = 0.10;
cfg.seed = 42;
cfg.split_policy = 'mamba_like';

% -------- stall_optimized（消融分支） --------
cfg.enable_train_resampling = true;
cfg.resample_stall_multiplier = 3.0;
cfg.resample_stall_target_min = 900;
cfg.resample_flat_max_ratio = 30.0;

% -------- 输出文件（opt 后缀） --------
cfg.save_split_file = true;
cfg.split_file = fullfile(root, 'data', 'gru', 'GRU_run_split_mamba_opt.mat');
cfg.output_file = fullfile(root, 'data', 'gru', 'GRU_dataset_processed_mamba_opt.mat');
cfg.scaler_file = fullfile(root, 'data', 'gru', 'GRU_scaler_mamba_opt.mat');

cfg.verbose = true;

run(fullfile(root, 'src', 'gru', 'GRU_prepare_dataset.m'));
