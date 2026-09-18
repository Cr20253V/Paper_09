% =============================
% 文件名：run_GRU_train_mamba_control_strict.m
% 版本号：V1.0（GRU 严格同分布对照训练一键脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   基于 strict 数据集启动 GRU 对照组训练（mamba_control 模式），
%   输出使用 strict 后缀，便于与 stall 优化版并行对比。
%
% 使用方法：
%   直接运行脚本：run('src/gru/run_GRU_train_mamba_control_strict.m')
%
% 输出：
%   - data/models/GRU_model_mamba_control_strict.mat
%   - data/models/GRU_meta_mamba_control_strict.mat
%   - results/gru/train_logs_mamba_control_strict/
%
% 依赖：
%   - project_root.m
%   - results_dir.m
%   - src/gru/GRU_train.m
%   - data/gru/GRU_dataset_processed_mamba_strict.mat
% =============================

root = project_root();

cfg = struct();
cfg.experiment_mode = 'mamba_control';

% 输入数据（strict 同分布）
cfg.input_file = fullfile(root, 'data', 'gru', 'GRU_dataset_processed_mamba_strict.mat');

% 输出命名（strict）
cfg.model_file = fullfile(root, 'data', 'models', 'GRU_model_mamba_control_strict.mat');
cfg.meta_file = fullfile(root, 'data', 'models', 'GRU_meta_mamba_control_strict.mat');
cfg.log_dir = results_dir('gru/train_logs_mamba_control_strict');

% 复现设置
cfg.seed = 42;

% 权重策略（与对照组默认一致）
cfg.use_class_weights = true;
cfg.class_weight_method = 'sqrt_inverse';

% 训练轮数
cfg.max_epochs = 30;

cfg.verbose = true;
cfg.use_gpu = true;

run(fullfile(root, 'src', 'gru', 'GRU_train.m'));
