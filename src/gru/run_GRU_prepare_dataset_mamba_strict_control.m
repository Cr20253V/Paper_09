% =============================
% 文件名：run_GRU_prepare_dataset_mamba_strict_control.m
% 版本号：V1.0（GRU 严格同分布对照预处理一键脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   使用 Mamba 母集生成 GRU 训练数据，并保持严格同分布对照设置：
%   - 复现 Mamba run-level 划分（mamba_like）
%   - 关闭训练集重采样（enable_train_resampling=false）
%   - 输出文件使用 strict 后缀，避免覆盖其他实验产物
%
% 使用方法：
%   直接运行脚本：run('src/gru/run_GRU_prepare_dataset_mamba_strict_control.m')
%
% 输出：
%   - data/gru/GRU_dataset_processed_mamba_strict.mat
%   - data/gru/GRU_scaler_mamba_strict.mat
%   - data/gru/GRU_run_split_mamba_strict.mat
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

% -------- 严格同分布对照：关闭重采样 --------
cfg.enable_train_resampling = false;

% -------- 输出文件（strict 后缀） --------
cfg.save_split_file = true;
cfg.split_file = fullfile(root, 'data', 'gru', 'GRU_run_split_mamba_strict.mat');
cfg.output_file = fullfile(root, 'data', 'gru', 'GRU_dataset_processed_mamba_strict.mat');
cfg.scaler_file = fullfile(root, 'data', 'gru', 'GRU_scaler_mamba_strict.mat');

cfg.verbose = true;

run(fullfile(root, 'src', 'gru', 'GRU_prepare_dataset.m'));
