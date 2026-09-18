% =============================
% 文件名：run_GRU_train_mamba_control.m
% 版本号：V1.0（GRU 对照组训练一键脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   一键启动 GRU 对照组训练（experiment_mode='mamba_control'），
%   不改动 Mamba 训练流程，仅在 GRU 侧完成可复现实验配置。
%   本脚本作为推荐默认入口，配合 strict 同分布数据使用。
%
%   主要行为：
%   1) 指定输入数据为 GRU_dataset_processed.mat（建议由 mamba_compare 预处理脚本生成）
%   2) 输出文件使用 *_mamba_control 命名，避免覆盖默认 GRU 模型
%   3) 固定随机种子 seed=42，默认 max_epochs=30（可按实验预算调整）
%   4) 默认使用 class_weight_method='sqrt_inverse' 优化 stall 精度-召回平衡
%   5) 调用 src/gru/GRU_train.m 执行正式训练流程
%
% 使用方法：
%   直接运行脚本：run('src/gru/run_GRU_train_mamba_control.m')
%
% 输出：
%   - data/models/GRU_model_mamba_control.mat
%   - data/models/GRU_meta_mamba_control.mat
%   - results/gru/train_logs_mamba_control/
%
% 依赖：
%   - project_root.m
%   - results_dir.m
%   - src/gru/GRU_train.m
%   - data/gru/GRU_dataset_processed.mat
%
% 备注：
%   - 若未先生成对照组预处理数据，请先运行 run_GRU_prepare_dataset_mamba_compare.m（默认 strict）。
%   - 若做 stall_optimized 消融，请改用 run_GRU_train_mamba_control_stall_optimized.m。
%   - 本脚本为入口脚本，训练细节以 GRU_train.m 内 cfg 与日志输出为准。
% =============================

root = project_root();

cfg = struct();
cfg.experiment_mode = 'mamba_control';

% 输入数据：建议先运行 run_GRU_prepare_dataset_mamba_compare.m 生成
cfg.input_file = fullfile(root, 'data', 'gru', 'GRU_dataset_processed.mat');

% 输出命名：避免覆盖默认 GRU 模型
cfg.model_file = fullfile(root, 'data', 'models', 'GRU_model_mamba_control.mat');
cfg.meta_file = fullfile(root, 'data', 'models', 'GRU_meta_mamba_control.mat');
cfg.log_dir = results_dir('gru/train_logs_mamba_control');

% 与 Mamba 对照组保持可复现
cfg.seed = 42;

% stall 权重优化：相对 balanced 更稳健，抑制过度权重导致的误报
cfg.use_class_weights = true;
cfg.class_weight_method = 'sqrt_inverse';

% 你可按实验预算调整；mamba_control 默认是 30 轮
cfg.max_epochs = 30;

cfg.verbose = true;
cfg.use_gpu = true;

run(fullfile(root, 'src', 'gru', 'GRU_train.m'));
