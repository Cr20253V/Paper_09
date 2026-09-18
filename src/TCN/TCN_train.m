function [model, meta] = TCN_train(cfg)
%TCN_TRAIN 训练 AGV 状态估计与 LPV-MPC 调度用的多任务 TCN。
%
% 功能说明：
%   读取 TCN_prepare_dataset.m 生成的窗口化数据集，训练因果膨胀卷积
%   TCN。模型面向 AGV 路径跟踪中的在线状态估计和 LPV-MPC 调度，可
%   输出主工况、转弯方向、坡度角以及动态扰动辅助标签。
%
% 训练任务：
%   1. 主工况分类：flat / stall / slope，对应标签 1 / 2 / 3。
%   2. 转弯分类：right / straight / left，对应标签 -1 / 0 / 1。
%   3. 坡度角回归：theta_ground，单位 rad。
%   4. 辅助二分类：slip、stall、load_change，用于增强过渡状态识别。
%
% 物理引导设计：
%   - 在带坡度监督的样本上计算主要坡度回归损失。
%   - 仅对 true-zero / very-near-zero 样本增加 theta=0 约束，避免把小坡度
%     flat 窗口的 raw theta 强行压成 0。
%   - 对负坡样本加权，避免正坡样本占优时模型不输出负坡或不判为 slope。
%   - 分类/回归头默认使用 last + mean + max 时间池化读出，保留窗口内统计线索。
%   - 可选 focal loss，用于强化 flat/slope 和少数 stall 样本的学习权重。
%   - pitch consistency 可选，默认关闭，避免 IMU 积分偏置主导回归头。
%
% 关键 cfg：
%   cfg.input_file   : 默认 data/tcn/TCN_dataset_processed.mat。
%   cfg.model_file   : 默认 data/models/TCN_model.mat。
%   cfg.meta_file    : 默认 data/models/TCN_meta.mat。
%   cfg.mode         : 'physics_guided' 或 'vanilla'。
%   cfg.best_metric  : 'composite' / 'turn_priority' / 'main_guard' / 'loss'，默认 composite。
%
% 输出：
%   model.feature_net : TCN 特征提取网络。
%   model.heads       : 多任务输出头参数。
%   model.scaler      : 归一化参数，用于部署和推理。
%   meta              : 训练配置、训练历史和测试指标。

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_defaults(cfg, root);
rng(cfg.seed, 'twister');

if ~exist(cfg.log_dir, 'dir')
    mkdir(cfg.log_dir);
end

if cfg.verbose
    fprintf('\n========== TCN 多任务训练 ==========\n');
    fprintf('模式: %s\n', cfg.mode);
    fprintf('输入: %s\n', cfg.input_file);
    fprintf('模型: %s\n', cfg.model_file);
    fprintf('============================================\n\n');
end

if ~exist(cfg.input_file, 'file')
    error('TCN_train:MissingDataset', 'Dataset not found: %s', cfg.input_file);
end
S = load(cfg.input_file, 'dataset');
dataset = S.dataset;
local_check_dataset(dataset);

if cfg.use_gpu && canUseGPU()
    exec_env = 'gpu';
else
    exec_env = 'cpu';
end

X_train = permute(dataset.X_train, [3, 2, 1]);
X_val = permute(dataset.X_val, [3, 2, 1]);
X_test = permute(dataset.X_test, [3, 2, 1]);

Y.train = local_make_targets(dataset, 'train');
Y.val = local_make_targets(dataset, 'val');
Y.test = local_make_targets(dataset, 'test');

n_train = size(X_train, 3);
n_val = size(X_val, 3);
input_size = size(X_train, 1);
cfg.input_size = input_size;

class_weights_main = local_class_weights(Y.train.main, 1:3, cfg.class_weight_method);
class_weights_main = class_weights_main .* cfg.main_class_multipliers(:);
if any(class_weights_main > 0)
    class_weights_main = class_weights_main / mean(class_weights_main(class_weights_main > 0));
end
class_weights_turn = local_class_weights(Y.train.turn_cls, 1:3, cfg.turn_class_weight_method);
class_weights_turn = class_weights_turn .* cfg.turn_class_multipliers(:);
if any(class_weights_turn > 0)
    class_weights_turn = class_weights_turn / mean(class_weights_turn(class_weights_turn > 0));
end

if strcmp(exec_env, 'gpu')
    class_weights_main = gpuArray(class_weights_main);
    class_weights_turn = gpuArray(class_weights_turn);
end

feature_net = local_build_tcn(input_size, cfg);
head_size = local_head_feature_size(cfg);
turn_head_size = local_turn_head_feature_size(head_size, cfg);
heads = local_init_heads(head_size, turn_head_size, cfg, exec_env);

if cfg.verbose
    fprintf('[数据]\n');
    fprintf('  训练/验证/测试窗口数: %d / %d / %d\n', ...
        size(dataset.X_train,1), size(dataset.X_val,1), size(dataset.X_test,1));
    fprintf('  输入: feat_dim=%d, seq_len=%d\n', input_size, size(X_train,2));
    fprintf('  执行环境: %s\n', exec_env);
    fprintf('[模型]\n');
    fprintf('  blocks=%d, filters=%d, kernel=%d, dropout=%.2f\n', ...
        cfg.num_blocks, cfg.num_filters, cfg.kernel_size, cfg.dropout);
    fprintf('  head pooling: %s\n', cfg.head_pooling);
    fprintf('  近似感受野: %d steps (%.2f s)\n', ...
        local_receptive_field(cfg), local_receptive_field(cfg) * dataset.meta.Ts);
end

opt = struct();
opt.iter = 0;
opt.avg = [];
opt.avgSq = [];
best = struct('val_loss', inf, 'selection_score', inf, 'feature_net', [], 'heads', [], 'epoch', 0);
base_best = struct('val_loss', inf, 'selection_score', inf, 'feature_net', [], 'heads', [], 'epoch', 0);
history = local_empty_history();
patience_count = 0;

num_batches = ceil(n_train / cfg.batch_size);
tic_train = tic;

for epoch = 1:cfg.max_epochs
    lr = local_lr(cfg, epoch);
    order = randperm(n_train);
    acc = local_epoch_accumulator();

    for b = 1:num_batches
        i0 = (b - 1) * cfg.batch_size + 1;
        i1 = min(b * cfg.batch_size, n_train);
        idx = order(i0:i1);

        Xb = dlarray(X_train(:,:,idx), 'CBT');
        Tb = local_batch_targets(Y.train, idx, exec_env);
        if strcmp(exec_env, 'gpu')
            Xb = gpuArray(Xb);
        end

        cfg_epoch = local_epoch_cfg(cfg, epoch);
        [losses, grads] = dlfeval(@local_model_gradients, ...
            feature_net, heads, Xb, Tb, dataset.scaler, cfg_epoch, ...
            class_weights_main, class_weights_turn);

        if local_is_turn_finetune_epoch(cfg, epoch)
            grads = local_keep_turn_head_grads_only(grads);
        end
        grads = local_clip_gradients(grads, cfg.grad_clip, cfg);
        opt.iter = opt.iter + 1;
        [feature_net, heads, opt] = local_adam_update(feature_net, heads, grads, opt, lr);
        acc = local_accumulate(acc, losses);
    end

    train_losses = local_average_acc(acc, num_batches);
    cfg_epoch = local_epoch_cfg(cfg, epoch);
    val_metrics = local_evaluate(feature_net, heads, X_val, Y.val, dataset.scaler, cfg_epoch, ...
        class_weights_main, class_weights_turn, exec_env);

    history = local_append_history(history, epoch, lr, train_losses, val_metrics);

    if cfg.verbose && (epoch == 1 || mod(epoch, cfg.print_every) == 0 || epoch == cfg.max_epochs)
        fprintf(['轮次 %03d/%03d | lr=%.2e | 训练 %.4f | 验证 %.4f | ' ...
            '主类准确率 %.3f | 转弯准确率 %.3f | 坡度MAE %.3f deg\n'], ...
            epoch, cfg.max_epochs, lr, train_losses.total, val_metrics.total, ...
            val_metrics.acc_main, val_metrics.acc_turn, rad2deg(val_metrics.mae_theta));
    end

    selection_score = local_selection_score(val_metrics, cfg);
    if epoch >= cfg.base_selection_start_epoch && epoch < cfg.turn_finetune_start_epoch
        base_cfg = cfg;
        base_cfg.best_metric = cfg.base_best_metric;
        base_score = local_selection_score(val_metrics, base_cfg);
        if base_score < base_best.selection_score - cfg.min_delta
            base_best.val_loss = val_metrics.total;
            base_best.selection_score = base_score;
            base_best.feature_net = feature_net;
            base_best.heads = heads;
            base_best.epoch = epoch;
        end
    end
    if epoch >= cfg.selection_start_epoch && selection_score < best.selection_score - cfg.min_delta
        best.val_loss = val_metrics.total;
        best.selection_score = selection_score;
        best.feature_net = feature_net;
        best.heads = heads;
        best.epoch = epoch;
        patience_count = 0;
    else
        patience_count = patience_count + 1;
    end

    if epoch >= cfg.early_stop_min_epochs && patience_count >= cfg.patience
        if cfg.verbose
            fprintf('[TCN] 第 %d 轮早停，最佳轮次: %d\n', epoch, best.epoch);
        end
        break;
    end
end

if isempty(best.feature_net)
    best.val_loss = val_metrics.total;
    best.selection_score = local_selection_score(val_metrics, cfg);
    best.feature_net = feature_net;
    best.heads = heads;
    best.epoch = epoch;
end

if cfg.combine_base_and_turn_best && ~isempty(base_best.feature_net) && ~isempty(best.feature_net)
    feature_net = base_best.feature_net;
    heads = local_copy_turn_head(base_best.heads, best.heads);
    final_epoch = best.epoch;
    final_base_epoch = base_best.epoch;
else
    feature_net = best.feature_net;
    heads = best.heads;
    final_epoch = best.epoch;
    final_base_epoch = NaN;
end
test_metrics = local_evaluate(feature_net, heads, X_test, Y.test, dataset.scaler, cfg, ...
    class_weights_main, class_weights_turn, exec_env);

model = struct();
model.feature_net = feature_net;
model.heads = local_gather_heads(heads);
model.scaler = dataset.scaler;
model.feat_names = dataset.feat_names;
model.cfg = cfg;
model.input_format = 'CBT';
model.output_contract = 'main3_turn3_theta_aux3';

meta = struct();
meta.created_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
meta.mode = cfg.mode;
meta.dataset_meta = dataset.meta;
meta.cfg = cfg;
meta.history = history;
meta.best_epoch = final_epoch;
meta.base_best_epoch = final_base_epoch;
meta.best_val_loss = best.val_loss;
meta.best_selection_score = best.selection_score;
meta.base_best_val_loss = base_best.val_loss;
meta.base_best_selection_score = base_best.selection_score;
meta.test_metrics = test_metrics;
meta.train_seconds = toc(tic_train);
meta.receptive_field_steps = local_receptive_field(cfg);
meta.receptive_field_seconds = local_receptive_field(cfg) * dataset.meta.Ts;

save(cfg.model_file, 'model', '-v7.3');
save(cfg.meta_file, 'meta');
local_write_training_report(cfg, meta, test_metrics);

if cfg.verbose
    fprintf('\n[TCN] 训练完成。\n');
    fprintf('  最佳轮次: %d\n', best.epoch);
    fprintf('  测试主类/转弯准确率: %.3f / %.3f\n', test_metrics.acc_main, test_metrics.acc_turn);
    fprintf('  测试坡度 MAE: %.3f deg\n', rad2deg(test_metrics.mae_theta));
    fprintf('  模型已保存: %s\n', cfg.model_file);
    fprintf('  元信息已保存: %s\n', cfg.meta_file);
end
end

function cfg = local_defaults(cfg, root)
data_tcn_dir = fullfile(root, 'data', 'tcn');
data_models_dir = fullfile(root, 'data', 'models');
if ~isfield(cfg, 'input_file'); cfg.input_file = fullfile(data_tcn_dir, 'TCN_dataset_processed.mat'); end
if ~isfield(cfg, 'model_file'); cfg.model_file = fullfile(data_models_dir, 'TCN_model.mat'); end
if ~isfield(cfg, 'meta_file'); cfg.meta_file = fullfile(data_models_dir, 'TCN_meta.mat'); end
if ~isfield(cfg, 'log_dir'); cfg.log_dir = results_dir('tcn/train_logs'); end
if ~isfield(cfg, 'report_file'); cfg.report_file = fullfile(cfg.log_dir, 'TCN_train_report.md'); end
if ~isfield(cfg, 'mode'); cfg.mode = 'physics_guided'; end

if ~isfield(cfg, 'num_blocks'); cfg.num_blocks = 6; end
if ~isfield(cfg, 'num_filters'); cfg.num_filters = 96; end
if ~isfield(cfg, 'kernel_size'); cfg.kernel_size = 3; end
if ~isfield(cfg, 'dropout'); cfg.dropout = 0.15; end

if ~isfield(cfg, 'batch_size'); cfg.batch_size = 64; end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 80; end
if ~isfield(cfg, 'initial_lr'); cfg.initial_lr = 1e-3; end
if ~isfield(cfg, 'lr_schedule'); cfg.lr_schedule = 'cosine'; end
if ~isfield(cfg, 'grad_clip'); cfg.grad_clip = 5.0; end
if ~isfield(cfg, 'grad_clip_mode'); cfg.grad_clip_mode = 'separate'; end
if ~isfield(cfg, 'patience'); cfg.patience = 12; end
if ~isfield(cfg, 'min_delta'); cfg.min_delta = 1e-4; end
if ~isfield(cfg, 'early_stop_min_epochs'); cfg.early_stop_min_epochs = 0; end
if ~isfield(cfg, 'selection_start_epoch'); cfg.selection_start_epoch = 1; end
if ~isfield(cfg, 'base_selection_start_epoch'); cfg.base_selection_start_epoch = 1; end

if ~isfield(cfg, 'lambda_turn'); cfg.lambda_turn = 0.30; end
if ~isfield(cfg, 'turn_finetune_start_epoch'); cfg.turn_finetune_start_epoch = inf; end
if ~isfield(cfg, 'turn_finetune_lambda_turn'); cfg.turn_finetune_lambda_turn = cfg.lambda_turn; end
if ~isfield(cfg, 'turn_finetune_disable_other_losses'); cfg.turn_finetune_disable_other_losses = true; end
if ~isfield(cfg, 'lambda_theta'); cfg.lambda_theta = 0.35; end
if ~isfield(cfg, 'lambda_theta_flat'); cfg.lambda_theta_flat = 0.20; end
if ~isfield(cfg, 'theta_flat_loss_mode'); cfg.theta_flat_loss_mode = 'near_zero'; end
if ~isfield(cfg, 'theta_flat_zero_tol_deg'); cfg.theta_flat_zero_tol_deg = 0.3; end
if ~isfield(cfg, 'theta_near_flat_deg'); cfg.theta_near_flat_deg = 0.5; end
if ~isfield(cfg, 'lambda_aux'); cfg.lambda_aux = 0.15; end
if ~isfield(cfg, 'lambda_pitch_consistency'); cfg.lambda_pitch_consistency = 0.00; end
if ~isfield(cfg, 'lambda_phy'); cfg.lambda_phy = 0.00; end
if ~isfield(cfg, 'lambda_smooth'); cfg.lambda_smooth = 0.00; end
if ~isfield(cfg, 'turn_transition_weight'); cfg.turn_transition_weight = 1.00; end
if ~isfield(cfg, 'phy_pitch_threshold_deg'); cfg.phy_pitch_threshold_deg = 1.00; end
if ~isfield(cfg, 'phy_turn_signal_threshold'); cfg.phy_turn_signal_threshold = 0.010; end
if ~isfield(cfg, 'phy_turn_gyro_weight'); cfg.phy_turn_gyro_weight = 0.25; end
if ~isfield(cfg, 'phy_theta_mag_weight'); cfg.phy_theta_mag_weight = 0.25; end
if ~isfield(cfg, 'smooth_feature_weight'); cfg.smooth_feature_weight = 1.00; end
if ~isfield(cfg, 'theta_neg_weight'); cfg.theta_neg_weight = 2.0; end
if ~isfield(cfg, 'theta_pos_weight'); cfg.theta_pos_weight = 1.0; end
if ~isfield(cfg, 'main_neg_slope_weight'); cfg.main_neg_slope_weight = 4.0; end
if ~isfield(cfg, 'main_pos_slope_weight'); cfg.main_pos_slope_weight = 1.0; end
if ~isfield(cfg, 'head_pooling'); cfg.head_pooling = 'last_mean_max_inputstats'; end
if ~isfield(cfg, 'turn_head_type'); cfg.turn_head_type = 'mlp'; end
if ~isfield(cfg, 'turn_head_hidden'); cfg.turn_head_hidden = 64; end
if ~isfield(cfg, 'turn_head_source'); cfg.turn_head_source = 'inputstats'; end
if ~isfield(cfg, 'main_class_multipliers'); cfg.main_class_multipliers = [1.0, 1.0, 1.0]; end
if ~isfield(cfg, 'turn_class_multipliers'); cfg.turn_class_multipliers = [1.0, 1.0, 1.0]; end
if ~isfield(cfg, 'use_focal_loss'); cfg.use_focal_loss = false; end
if ~isfield(cfg, 'focal_gamma_main'); cfg.focal_gamma_main = 1.0; end
if ~isfield(cfg, 'focal_gamma_turn'); cfg.focal_gamma_turn = 0.5; end
if ~isfield(cfg, 'best_metric'); cfg.best_metric = 'composite'; end
if ~isfield(cfg, 'base_best_metric'); cfg.base_best_metric = 'composite'; end
if ~isfield(cfg, 'combine_base_and_turn_best'); cfg.combine_base_and_turn_best = false; end
if ~isfield(cfg, 'select_main_error_weight'); cfg.select_main_error_weight = 0.45; end
if ~isfield(cfg, 'select_turn_error_weight'); cfg.select_turn_error_weight = 0.15; end
if ~isfield(cfg, 'select_theta_weight'); cfg.select_theta_weight = 0.15; end
if ~isfield(cfg, 'select_downhill_error_weight'); cfg.select_downhill_error_weight = 0.25; end
if ~isfield(cfg, 'select_theta_ref_deg'); cfg.select_theta_ref_deg = 5.0; end
if ~isfield(cfg, 'select_main_floor'); cfg.select_main_floor = 0.93; end
if ~isfield(cfg, 'select_theta_floor_deg'); cfg.select_theta_floor_deg = 1.20; end
if ~isfield(cfg, 'select_downhill_floor'); cfg.select_downhill_floor = 0.80; end
if ~isfield(cfg, 'turn_priority_main_penalty_weight'); cfg.turn_priority_main_penalty_weight = 20.0; end
if ~isfield(cfg, 'turn_priority_theta_penalty_weight'); cfg.turn_priority_theta_penalty_weight = 0.25; end
if ~isfield(cfg, 'turn_priority_downhill_penalty_weight'); cfg.turn_priority_downhill_penalty_weight = 0.60; end
if ~isfield(cfg, 'turn_priority_loss_weight'); cfg.turn_priority_loss_weight = 0.02; end
if ~isfield(cfg, 'composite_guard_flat_floor'); cfg.composite_guard_flat_floor = 0.90; end
if ~isfield(cfg, 'composite_guard_stall_floor'); cfg.composite_guard_stall_floor = 0.90; end
if ~isfield(cfg, 'composite_guard_slope_floor'); cfg.composite_guard_slope_floor = 0.90; end
if ~isfield(cfg, 'composite_guard_flat_penalty_weight'); cfg.composite_guard_flat_penalty_weight = 3.0; end
if ~isfield(cfg, 'composite_guard_stall_penalty_weight'); cfg.composite_guard_stall_penalty_weight = 1.5; end
if ~isfield(cfg, 'composite_guard_slope_penalty_weight'); cfg.composite_guard_slope_penalty_weight = 3.0; end
if ~isfield(cfg, 'main_guard_flat_floor'); cfg.main_guard_flat_floor = 0.90; end
if ~isfield(cfg, 'main_guard_stall_floor'); cfg.main_guard_stall_floor = 0.90; end
if ~isfield(cfg, 'main_guard_slope_floor'); cfg.main_guard_slope_floor = 0.90; end
if ~isfield(cfg, 'main_guard_flat_penalty_weight'); cfg.main_guard_flat_penalty_weight = 4.0; end
if ~isfield(cfg, 'main_guard_stall_penalty_weight'); cfg.main_guard_stall_penalty_weight = 1.5; end
if ~isfield(cfg, 'main_guard_slope_penalty_weight'); cfg.main_guard_slope_penalty_weight = 2.0; end
if ~isfield(cfg, 'main_guard_acc_error_weight'); cfg.main_guard_acc_error_weight = 1.0; end
if ~isfield(cfg, 'main_guard_theta_weight'); cfg.main_guard_theta_weight = 0.10; end
if ~isfield(cfg, 'main_guard_turn_weight'); cfg.main_guard_turn_weight = 0.05; end
if strcmpi(cfg.mode, 'vanilla')
    cfg.lambda_aux = 0;
    cfg.lambda_pitch_consistency = 0;
    cfg.lambda_phy = 0;
    cfg.lambda_smooth = 0;
end

if ~isfield(cfg, 'class_weight_method'); cfg.class_weight_method = 'balanced'; end
if ~isfield(cfg, 'turn_class_weight_method'); cfg.turn_class_weight_method = 'sqrt_inverse'; end
if ~isfield(cfg, 'seed'); cfg.seed = 42; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'print_every'); cfg.print_every = 1; end
end

function local_check_dataset(dataset)
req = {'X_train','X_val','X_test','y_main_train','y_turn_train','y_theta_train', ...
    'mask_theta_train','scaler','feat_names','meta'};
for i = 1:numel(req)
    if ~isfield(dataset, req{i})
        error('TCN_train:BadDataset', 'Dataset missing field %s.', req{i});
    end
end
if size(dataset.X_train, 3) ~= numel(dataset.feat_names)
    error('TCN_train:FeatureMismatch', 'Feature dimension does not match feat_names.');
end
end

function cfg_epoch = local_epoch_cfg(cfg, epoch)
cfg_epoch = cfg;
if local_is_turn_finetune_epoch(cfg, epoch)
    cfg_epoch.lambda_turn = cfg.turn_finetune_lambda_turn;
    if cfg.turn_finetune_disable_other_losses
        cfg_epoch.lambda_theta = 0;
        cfg_epoch.lambda_theta_flat = 0;
        cfg_epoch.lambda_aux = 0;
        cfg_epoch.lambda_pitch_consistency = 0;
        cfg_epoch.lambda_phy = 0;
        cfg_epoch.lambda_smooth = 0;
    end
end
end

function tf = local_is_turn_finetune_epoch(cfg, epoch)
tf = isfinite(cfg.turn_finetune_start_epoch) && epoch >= cfg.turn_finetune_start_epoch;
end

function grads = local_keep_turn_head_grads_only(grads)
for i = 1:height(grads.net)
    grads.net.Value{i} = grads.net.Value{i} * 0;
end
names = fieldnames(grads.heads);
for i = 1:numel(names)
    name = names{i};
    if ~startsWith(name, 'turn_')
        grads.heads.(name) = grads.heads.(name) * 0;
    end
end
end

function heads = local_copy_turn_head(base_heads, turn_heads)
heads = base_heads;
names = fieldnames(turn_heads);
for i = 1:numel(names)
    name = names{i};
    if startsWith(name, 'turn_')
        heads.(name) = turn_heads.(name);
    end
end
end

function T = local_make_targets(dataset, split_name)
T = struct();
T.main = dataset.(sprintf('y_main_%s', split_name));
T.turn = dataset.(sprintf('y_turn_%s', split_name));
T.turn_cls = T.turn + 2;
T.turn_weight = local_get_dataset_field(dataset, ...
    sprintf('turn_sample_weight_%s', split_name), ones(size(T.turn)));
T.turn_purity = local_get_dataset_field(dataset, ...
    sprintf('turn_purity_%s', split_name), NaN(size(T.turn)));
T.turn_transition = local_get_dataset_field(dataset, ...
    sprintf('turn_transition_%s', split_name), false(size(T.turn)));
T.main_weight = local_get_dataset_field(dataset, ...
    sprintf('main_sample_weight_%s', split_name), ones(size(T.main)));
T.main_purity = local_get_dataset_field(dataset, ...
    sprintf('main_purity_%s', split_name), NaN(size(T.main)));
T.main_transition = local_get_dataset_field(dataset, ...
    sprintf('main_transition_%s', split_name), false(size(T.main)));
T.theta = dataset.(sprintf('y_theta_%s', split_name));
T.mask_theta = dataset.(sprintf('mask_theta_%s', split_name));
T.theta_weight = local_get_dataset_field(dataset, ...
    sprintf('theta_sample_weight_%s', split_name), ones(size(T.theta)));
T.theta_transition = local_get_dataset_field(dataset, ...
    sprintf('theta_transition_%s', split_name), false(size(T.theta)));
T.slip = local_get_dataset_field(dataset, sprintf('y_slip_%s', split_name), zeros(size(T.main)));
T.stall = local_get_dataset_field(dataset, sprintf('y_stall_%s', split_name), zeros(size(T.main)));
T.load_change = local_get_dataset_field(dataset, sprintf('y_load_change_%s', split_name), zeros(size(T.main)));
end

function y = local_get_dataset_field(dataset, field_name, default_value)
if isfield(dataset, field_name)
    y = dataset.(field_name);
else
    y = default_value;
end
end

function Tb = local_batch_targets(T, idx, exec_env)
fields = {'main','turn_cls','turn_weight','turn_transition','main_weight', ...
    'theta','mask_theta','theta_weight','slip','stall','load_change'};
Tb = struct();
for i = 1:numel(fields)
    f = fields{i};
    Tb.(f) = T.(f)(idx);
    if strcmp(exec_env, 'gpu')
        Tb.(f) = gpuArray(Tb.(f));
    end
end
end

function net = local_build_tcn(input_size, cfg)
layers = [
    sequenceInputLayer(input_size, 'Name', 'input', 'Normalization', 'none')
];
for b = 1:cfg.num_blocks
    d = 2^(b-1);
    layers = [
        layers
        convolution1dLayer(cfg.kernel_size, cfg.num_filters, ...
            'Padding', 'causal', 'DilationFactor', d, 'Name', sprintf('tcn_conv_%d', b))
        layerNormalizationLayer('Name', sprintf('tcn_ln_%d', b))
        reluLayer('Name', sprintf('tcn_relu_%d', b))
        dropoutLayer(cfg.dropout, 'Name', sprintf('tcn_dropout_%d', b))
    ]; %#ok<AGROW>
end
net = dlnetwork(layers);
end

function heads = local_init_heads(hidden_size, turn_hidden_size, cfg, exec_env)
scale = 0.02;
heads = struct();
heads.main_W = dlarray(randn(3, hidden_size) * scale);
heads.main_b = dlarray(zeros(3, 1));
heads.theta_W = dlarray(randn(1, hidden_size) * scale);
heads.theta_b = dlarray(0);
heads.slip_W = dlarray(randn(1, hidden_size) * scale);
heads.slip_b = dlarray(0);
heads.stall_W = dlarray(randn(1, hidden_size) * scale);
heads.stall_b = dlarray(0);
heads.load_W = dlarray(randn(1, hidden_size) * scale);
heads.load_b = dlarray(0);

switch lower(char(cfg.turn_head_type))
    case 'linear'
        heads.turn_W = dlarray(randn(3, turn_hidden_size) * scale);
        heads.turn_b = dlarray(zeros(3, 1));
    case 'mlp'
        h = cfg.turn_head_hidden;
        heads.turn_W1 = dlarray(randn(h, turn_hidden_size) * sqrt(2 / max(turn_hidden_size, 1)));
        heads.turn_b1 = dlarray(zeros(h, 1));
        heads.turn_W2 = dlarray(randn(3, h) * sqrt(2 / max(h, 1)));
        heads.turn_b2 = dlarray(zeros(3, 1));
    otherwise
        error('TCN_train:BadTurnHead', '未知 turn_head_type: %s', cfg.turn_head_type);
end

if strcmp(exec_env, 'gpu')
    names = fieldnames(heads);
    for i = 1:numel(names)
        heads.(names{i}) = gpuArray(heads.(names{i}));
    end
end
end

function head_size = local_head_feature_size(cfg)
switch lower(char(cfg.head_pooling))
    case 'last'
        head_size = cfg.num_filters;
    case 'last_mean_max'
        head_size = cfg.num_filters * 3;
    case 'last_mean_max_inputstats'
        head_size = cfg.num_filters * 3 + cfg.input_size * 5;
    otherwise
        error('TCN_train:BadHeadPooling', '未知 head_pooling: %s', cfg.head_pooling);
end
end

function turn_head_size = local_turn_head_feature_size(head_size, cfg)
switch lower(char(cfg.turn_head_source))
    case 'readout'
        turn_head_size = head_size;
    case 'inputstats'
        turn_head_size = cfg.input_size * 5;
    otherwise
        error('TCN_train:BadTurnHeadSource', '未知 turn_head_source: %s', cfg.turn_head_source);
end
end

function [losses, grads] = local_model_gradients(net, heads, X, T, scaler, cfg, class_w_main, class_w_turn)
pred = local_forward(net, heads, X, cfg);

main_sample_w = local_main_sample_weights(T.main, T.theta, cfg) .* reshape(T.main_weight, [], 1);
loss_main = local_weighted_ce(pred.prob_main, T.main, class_w_main, ...
    cfg.focal_gamma_main, cfg.use_focal_loss, main_sample_w);
turn_sample_w = local_turn_sample_weights(T.turn_weight, T.turn_transition, cfg);
loss_turn = local_weighted_ce(pred.prob_turn, T.turn_cls, class_w_turn, ...
    cfg.focal_gamma_turn, cfg.use_focal_loss, turn_sample_w);
loss_theta = local_weighted_theta_mse(pred.theta, T.theta, T.mask_theta, cfg, T.theta_weight);
flat_zero_mask = local_theta_flat_zero_mask(T.main, T.theta, T.mask_theta, cfg);
loss_theta_flat = local_masked_mse(pred.theta, zeros(size(T.theta), 'like', T.theta), flat_zero_mask);

loss_aux = local_bce_logits(pred.slip_logit, T.slip) ...
    + local_bce_logits(pred.stall_logit, T.stall) ...
    + local_bce_logits(pred.load_logit, T.load_change);
loss_aux = loss_aux / 3;

loss_pitch = local_pitch_consistency_loss(pred.theta, X, scaler);
loss_phy = local_physics_consistency_loss(pred, X, scaler, cfg);
loss_smooth = local_feature_smoothness_loss(pred, cfg);

total = loss_main + cfg.lambda_turn * loss_turn ...
    + cfg.lambda_theta * loss_theta ...
    + cfg.lambda_theta_flat * loss_theta_flat ...
    + cfg.lambda_aux * loss_aux ...
    + cfg.lambda_pitch_consistency * loss_pitch ...
    + cfg.lambda_phy * loss_phy ...
    + cfg.lambda_smooth * loss_smooth;

losses = struct('total', total, 'main', loss_main, 'turn', loss_turn, ...
    'theta', loss_theta, 'theta_flat', loss_theta_flat, ...
    'aux', loss_aux, 'pitch', loss_pitch, 'phy', loss_phy, 'smooth', loss_smooth);

grad_net = dlgradient(total, net.Learnables);
grad_heads = struct();
head_names = fieldnames(heads);
for i = 1:numel(head_names)
    grad_heads.(head_names{i}) = dlgradient(total, heads.(head_names{i}));
end
grads = struct('net', grad_net, 'heads', grad_heads);
end

function pred = local_forward(net, heads, X, cfg, inference_mode)
if nargin < 5
    inference_mode = false;
end
if inference_mode
    Z = predict(net, X);
else
    Z = forward(net, X);
end
[H, H_inputstats] = local_temporal_readout(Z, X, cfg);
H_turn = local_turn_readout(H, H_inputstats, cfg);

logits_main = heads.main_W * H + heads.main_b;
logits_turn = local_turn_logits(heads, H_turn, cfg);
theta = heads.theta_W * H + heads.theta_b;
slip_logit = heads.slip_W * H + heads.slip_b;
stall_logit = heads.stall_W * H + heads.stall_b;
load_logit = heads.load_W * H + heads.load_b;

pred = struct();
pred.logits_main = logits_main;
pred.logits_turn = logits_turn;
pred.prob_main = softmax(logits_main, 'DataFormat', 'CB');
pred.prob_turn = softmax(logits_turn, 'DataFormat', 'CB');
pred.theta = reshape(theta, [], 1);
pred.slip_logit = reshape(slip_logit, [], 1);
pred.stall_logit = reshape(stall_logit, [], 1);
pred.load_logit = reshape(load_logit, [], 1);
pred.Z = Z;
end

function H_turn = local_turn_readout(H, H_inputstats, cfg)
switch lower(char(cfg.turn_head_source))
    case 'readout'
        H_turn = H;
    case 'inputstats'
        H_turn = H_inputstats;
    otherwise
        error('TCN_train:BadTurnHeadSource', '未知 turn_head_source: %s', cfg.turn_head_source);
end
end

function logits = local_turn_logits(heads, H_turn, cfg)
switch lower(char(cfg.turn_head_type))
    case 'linear'
        logits = heads.turn_W * H_turn + heads.turn_b;
    case 'mlp'
        A = max(heads.turn_W1 * H_turn + heads.turn_b1, 0);
        logits = heads.turn_W2 * A + heads.turn_b2;
    otherwise
        error('TCN_train:BadTurnHead', '未知 turn_head_type: %s', cfg.turn_head_type);
end
end

function [H, H_inputstats] = local_temporal_readout(Z, X, cfg)
H_inputstats = local_input_stats_readout(X);
switch lower(char(cfg.head_pooling))
    case 'last'
        H = Z(:, end, :);
    case 'last_mean_max'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max);
    case 'last_mean_max_inputstats'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max, H_inputstats);
    otherwise
        error('TCN_train:BadHeadPooling', '未知 head_pooling: %s', cfg.head_pooling);
end
H = reshape(H, size(H,1), []);
H_inputstats = reshape(H_inputstats, size(H_inputstats,1), []);
end

function H = local_input_stats_readout(X)
X_last = X(:, end, :);
X_mean = mean(X, 2);
X_std = sqrt(mean((X - X_mean).^2, 2) + 1e-8);
X_max = max(X, [], 2);
X_min = min(X, [], 2);
H = cat(1, X_last, X_mean, X_std, X_max, X_min);
end

function loss = local_weighted_ce(prob, labels, class_weights, focal_gamma, use_focal, sample_weights)
if nargin < 4 || isempty(focal_gamma)
    focal_gamma = 0;
end
if nargin < 5 || isempty(use_focal)
    use_focal = false;
end
if nargin < 6 || isempty(sample_weights)
    sample_weights = ones(numel(labels), 1);
end
sample_weights = dlarray(reshape(sample_weights, [], 1));
B = numel(labels);
loss = dlarray(0);
weight_sum = dlarray(0);
for i = 1:B
    c = labels(i);
    pt = prob(c, i);
    focal_factor = 1;
    if use_focal && focal_gamma > 0
        focal_factor = (1 - pt).^focal_gamma;
    end
    w = class_weights(c) * sample_weights(i);
    loss = loss - w * focal_factor * log(pt + 1e-8);
    weight_sum = weight_sum + w;
end
loss = loss / (weight_sum + 1e-8);
end

function w = local_main_sample_weights(main_labels, theta, cfg)
main_labels = reshape(main_labels, [], 1);
theta = reshape(theta, [], 1);
w = ones(size(theta), 'like', theta);
w(main_labels == 3 & theta < 0) = cfg.main_neg_slope_weight;
w(main_labels == 3 & theta > 0) = cfg.main_pos_slope_weight;
end

function mask = local_theta_flat_zero_mask(main_labels, theta, mask_theta, cfg)
main_labels = reshape(main_labels, [], 1);
theta = reshape(theta, [], 1);
mask_theta = reshape(mask_theta, [], 1);
mode = lower(char(cfg.theta_flat_loss_mode));
switch mode
    case {'', 'none', 'off'}
        mask = zeros(size(theta), 'like', theta);
    case {'main_flat', 'flat', 'legacy'}
        mask = double(main_labels == 1) .* mask_theta;
    case {'near_flat', 'theta_near_flat'}
        mask = double(abs(theta) <= deg2rad(cfg.theta_near_flat_deg)) .* mask_theta;
    case {'true_zero', 'zero'}
        mask = double(abs(theta) <= deg2rad(1e-4)) .* mask_theta;
    case {'near_zero', 'very_near_zero'}
        mask = double(abs(theta) <= deg2rad(cfg.theta_flat_zero_tol_deg)) .* mask_theta;
    otherwise
        error('TCN_train:BadThetaFlatLossMode', ...
            '未知 theta_flat_loss_mode: %s', cfg.theta_flat_loss_mode);
end
end

function loss = local_masked_mse(pred, target, mask)
pred = reshape(pred, [], 1);
target = dlarray(reshape(target, [], 1));
mask = dlarray(reshape(mask, [], 1));
loss = sum(((pred - target) .* mask).^2) / (sum(mask) + 1e-8);
end

function loss = local_weighted_theta_mse(pred, target, mask, cfg, sample_weights)
if nargin < 5 || isempty(sample_weights)
    sample_weights = ones(size(target), 'like', target);
end
pred = reshape(pred, [], 1);
target = dlarray(reshape(target, [], 1));
mask = dlarray(reshape(mask, [], 1));
sample_weights = dlarray(reshape(sample_weights, [], 1));
w = dlarray(ones(size(target), 'like', extractdata(target)));
w = w + (cfg.theta_neg_weight - 1) * double(target < 0);
w = w + (cfg.theta_pos_weight - 1) * double(target > 0);
wm = w .* mask .* sample_weights;
loss = sum(((pred - target).^2) .* wm) / (sum(wm) + 1e-8);
end

function w = local_turn_sample_weights(base_weight, turn_transition, cfg)
base_weight = reshape(base_weight, [], 1);
turn_transition = reshape(turn_transition, [], 1);
w = base_weight .* (1 + (cfg.turn_transition_weight - 1) * double(turn_transition));
end

function loss = local_bce_logits(logits, target)
target = dlarray(reshape(target, [], 1));
loss = mean(max(logits, 0) - logits .* target + log(1 + exp(-abs(logits))));
end

function loss = local_pitch_consistency_loss(theta_pred, X, scaler)
if numel(scaler.mean) < 19
    loss = dlarray(0);
    return;
end
pitch_norm = reshape(X(19, end, :), [], 1);
pitch_est = pitch_norm * scaler.std(19) + scaler.mean(19);
loss = mean((theta_pred - pitch_est).^2);
end

function loss = local_physics_consistency_loss(pred, X, scaler, cfg)
loss_theta = local_theta_pitch_sign_loss(pred.theta, X, scaler, cfg);
loss_turn = local_turn_observable_loss(pred.prob_turn, X, scaler, cfg);
loss = loss_theta + loss_turn;
end

function loss = local_theta_pitch_sign_loss(theta_pred, X, scaler, cfg)
if numel(scaler.mean) < 19
    loss = dlarray(0);
    return;
end
pitch_est = local_denorm_feature(X, 19, scaler, 'last');
pitch_mask = double(abs(pitch_est) >= deg2rad(cfg.phy_pitch_threshold_deg));
theta_pred = reshape(theta_pred, [], 1);
pitch_est = reshape(pitch_est, [], 1);
pitch_mask = dlarray(reshape(pitch_mask, [], 1));
sign_violation = max(-theta_pred .* pitch_est, 0);
sign_loss = sum((sign_violation.^2) .* pitch_mask) / (sum(pitch_mask) + 1e-8);
mag_loss = sum(((theta_pred - pitch_est).^2) .* pitch_mask) / (sum(pitch_mask) + 1e-8);
loss = sign_loss + cfg.phy_theta_mag_weight * mag_loss;
end

function loss = local_turn_observable_loss(prob_turn, X, scaler, cfg)
if numel(scaler.mean) < 17
    loss = dlarray(0);
    return;
end
kappa_mean = local_denorm_feature(X, 17, scaler, 'mean');
gyro_mean = local_denorm_feature(X, 2, scaler, 'mean');
turn_signal = kappa_mean + cfg.phy_turn_gyro_weight * gyro_mean;
right_mask = double(turn_signal < -cfg.phy_turn_signal_threshold);
left_mask = double(turn_signal > cfg.phy_turn_signal_threshold);
sample_w = (right_mask + left_mask) .* min(abs(turn_signal) / cfg.phy_turn_signal_threshold, 3.0);
prob_right = reshape(prob_turn(1, :), [], 1);
prob_left = reshape(prob_turn(3, :), [], 1);
loss_vec = -right_mask .* log(prob_right + 1e-8) - left_mask .* log(prob_left + 1e-8);
loss = sum(loss_vec .* sample_w) / (sum(sample_w) + 1e-8);
end

function x = local_denorm_feature(X, feature_idx, scaler, reduce_mode)
switch lower(char(reduce_mode))
    case 'last'
        x = reshape(X(feature_idx, end, :), [], 1);
    case 'mean'
        x = reshape(mean(X(feature_idx, :, :), 2), [], 1);
    otherwise
        error('TCN_train:BadReduceMode', 'Unknown reduce mode: %s', reduce_mode);
end
x = x * scaler.std(feature_idx) + scaler.mean(feature_idx);
end

function loss = local_feature_smoothness_loss(pred, cfg)
if ~isfield(pred, 'Z') || size(pred.Z, 2) < 2
    loss = dlarray(0);
    return;
end
dZ = pred.Z(:, 2:end, :) - pred.Z(:, 1:end-1, :);
loss = cfg.smooth_feature_weight * mean(dZ(:).^2);
end

function w = local_class_weights(y, labels, method)
counts = zeros(numel(labels), 1);
for i = 1:numel(labels)
    counts(i) = sum(y == labels(i));
end
counts_safe = max(counts, 1);
switch lower(method)
    case 'inverse'
        w = 1 ./ counts_safe;
    case 'sqrt_inverse'
        w = 1 ./ sqrt(counts_safe);
    case 'balanced'
        w = sum(counts) ./ (numel(labels) * counts_safe);
    otherwise
        w = ones(numel(labels), 1);
end
w(counts == 0) = 0;
if any(w > 0)
    w = w / mean(w(w > 0));
else
    w = ones(numel(labels), 1);
end
end

function lr = local_lr(cfg, epoch)
switch lower(cfg.lr_schedule)
    case 'cosine'
        lr = cfg.initial_lr * 0.5 * (1 + cos(pi * (epoch - 1) / cfg.max_epochs));
    otherwise
        lr = cfg.initial_lr;
end
end

function score = local_selection_score(val_metrics, cfg)
switch lower(char(cfg.best_metric))
    case 'loss'
        score = val_metrics.total;
    case 'composite'
        theta_norm = val_metrics.mae_theta / max(deg2rad(cfg.select_theta_ref_deg), 1e-6);
        if isfield(val_metrics, 'downhill') && isfield(val_metrics.downhill, 'slope_recall') ...
                && isfinite(val_metrics.downhill.slope_recall)
            downhill_error = 1 - val_metrics.downhill.slope_recall;
        else
            downhill_error = 0;
        end
        score = val_metrics.total ...
            + cfg.select_main_error_weight * (1 - val_metrics.acc_main) ...
            + cfg.select_turn_error_weight * (1 - val_metrics.acc_turn) ...
            + cfg.select_theta_weight * theta_norm ...
            + cfg.select_downhill_error_weight * downhill_error;
    case 'composite_guarded'
        theta_norm = val_metrics.mae_theta / max(deg2rad(cfg.select_theta_ref_deg), 1e-6);
        if isfield(val_metrics, 'downhill') && isfield(val_metrics.downhill, 'slope_recall') ...
                && isfinite(val_metrics.downhill.slope_recall)
            downhill_error = 1 - val_metrics.downhill.slope_recall;
        else
            downhill_error = 0;
        end
        recall_main = val_metrics.recall_main(:);
        flat_penalty = max(0, cfg.composite_guard_flat_floor - recall_main(1));
        stall_penalty = max(0, cfg.composite_guard_stall_floor - recall_main(2));
        slope_penalty = max(0, cfg.composite_guard_slope_floor - recall_main(3));
        score = val_metrics.total ...
            + cfg.select_main_error_weight * (1 - val_metrics.acc_main) ...
            + cfg.select_turn_error_weight * (1 - val_metrics.acc_turn) ...
            + cfg.select_theta_weight * theta_norm ...
            + cfg.select_downhill_error_weight * downhill_error ...
            + cfg.composite_guard_flat_penalty_weight * flat_penalty ...
            + cfg.composite_guard_stall_penalty_weight * stall_penalty ...
            + cfg.composite_guard_slope_penalty_weight * slope_penalty;
    case 'turn_priority'
        theta_mae_deg = rad2deg(val_metrics.mae_theta);
        main_penalty = max(0, cfg.select_main_floor - val_metrics.acc_main);
        theta_penalty = max(0, theta_mae_deg - cfg.select_theta_floor_deg) / max(cfg.select_theta_floor_deg, 1e-6);
        if isfield(val_metrics, 'downhill') && isfield(val_metrics.downhill, 'slope_recall') ...
                && isfinite(val_metrics.downhill.slope_recall)
            downhill_penalty = max(0, cfg.select_downhill_floor - val_metrics.downhill.slope_recall);
        else
            downhill_penalty = 0;
        end
        score = (1 - val_metrics.acc_turn) ...
            + cfg.turn_priority_main_penalty_weight * main_penalty ...
            + cfg.turn_priority_theta_penalty_weight * theta_penalty ...
            + cfg.turn_priority_downhill_penalty_weight * downhill_penalty ...
            + cfg.turn_priority_loss_weight * val_metrics.total;
    case 'main_guard'
        theta_norm = val_metrics.mae_theta / max(deg2rad(cfg.select_theta_ref_deg), 1e-6);
        recall_main = val_metrics.recall_main(:);
        flat_penalty = max(0, cfg.main_guard_flat_floor - recall_main(1));
        stall_penalty = max(0, cfg.main_guard_stall_floor - recall_main(2));
        slope_penalty = max(0, cfg.main_guard_slope_floor - recall_main(3));
        score = val_metrics.total ...
            + cfg.main_guard_acc_error_weight * (1 - val_metrics.acc_main) ...
            + cfg.main_guard_flat_penalty_weight * flat_penalty ...
            + cfg.main_guard_stall_penalty_weight * stall_penalty ...
            + cfg.main_guard_slope_penalty_weight * slope_penalty ...
            + cfg.main_guard_theta_weight * theta_norm ...
            + cfg.main_guard_turn_weight * (1 - val_metrics.acc_turn);
    otherwise
        error('TCN_train:BadBestMetric', '未知 best_metric: %s', cfg.best_metric);
end
end

function rf = local_receptive_field(cfg)
rf = 1 + (cfg.kernel_size - 1) * sum(2.^(0:cfg.num_blocks-1));
end

function acc = local_epoch_accumulator()
fields = {'total','main','turn','theta','theta_flat','aux','pitch','phy','smooth'};
for i = 1:numel(fields)
    acc.(fields{i}) = 0;
end
end

function acc = local_accumulate(acc, losses)
fields = fieldnames(acc);
for i = 1:numel(fields)
    acc.(fields{i}) = acc.(fields{i}) + double(gather(extractdata(losses.(fields{i}))));
end
end

function avg = local_average_acc(acc, n)
fields = fieldnames(acc);
avg = struct();
for i = 1:numel(fields)
    avg.(fields{i}) = acc.(fields{i}) / max(n, 1);
end
end

function history = local_empty_history()
history = struct('epoch', [], 'lr', [], 'train_total', [], 'val_total', [], ...
    'val_acc_main', [], 'val_acc_turn', [], 'val_mae_theta', [], ...
    'val_acc_turn_pure', [], 'val_acc_turn_transition', []);
end

function history = local_append_history(history, epoch, lr, train_losses, val_metrics)
history.epoch(end+1) = epoch;
history.lr(end+1) = lr;
history.train_total(end+1) = train_losses.total;
history.val_total(end+1) = val_metrics.total;
history.val_acc_main(end+1) = val_metrics.acc_main;
history.val_acc_turn(end+1) = val_metrics.acc_turn;
history.val_mae_theta(end+1) = val_metrics.mae_theta;
history.val_acc_turn_pure(end+1) = local_metric_or_nan(val_metrics, 'acc_turn_pure');
history.val_acc_turn_transition(end+1) = local_metric_or_nan(val_metrics, 'acc_turn_transition');
end

function v = local_metric_or_nan(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function metrics = local_evaluate(net, heads, X, Y, scaler, cfg, class_w_main, class_w_turn, exec_env)
n = size(X, 3);
num_batches = ceil(n / cfg.batch_size);
acc = local_epoch_accumulator();
pred_main_all = zeros(n, 1);
pred_turn_all = zeros(n, 1);
theta_all = zeros(n, 1);

for b = 1:num_batches
    i0 = (b - 1) * cfg.batch_size + 1;
    i1 = min(b * cfg.batch_size, n);
    idx = i0:i1;
    Xb = dlarray(X(:,:,idx), 'CBT');
    Tb = local_batch_targets(Y, idx, exec_env);
    if strcmp(exec_env, 'gpu')
        Xb = gpuArray(Xb);
    end

    pred = local_forward(net, heads, Xb, cfg, true);
    losses = local_eval_losses(pred, Xb, Tb, scaler, cfg, class_w_main, class_w_turn);
    acc = local_accumulate(acc, losses);

    [~, pm] = max(extractdata(gather(pred.prob_main)), [], 1);
    [~, pt] = max(extractdata(gather(pred.prob_turn)), [], 1);
    pred_main_all(idx) = pm(:);
    pred_turn_all(idx) = pt(:);
    theta_all(idx) = extractdata(gather(pred.theta));
end

metrics = local_average_acc(acc, num_batches);
metrics.acc_main = mean(pred_main_all == Y.main);
metrics.acc_turn = mean((pred_turn_all - 2) == Y.turn);
metrics.cm_main = confusionmat(Y.main, pred_main_all, 'Order', [1 2 3]);
metrics.cm_turn = confusionmat(Y.turn, pred_turn_all - 2, 'Order', [-1 0 1]);
metrics.recall_main = diag(metrics.cm_main) ./ max(sum(metrics.cm_main, 2), 1);
metrics.recall_turn = diag(metrics.cm_turn) ./ max(sum(metrics.cm_turn, 2), 1);
metrics.precision_main = diag(metrics.cm_main) ./ max(sum(metrics.cm_main, 1)', 1);
metrics.precision_turn = diag(metrics.cm_turn) ./ max(sum(metrics.cm_turn, 1)', 1);
turn_pred = pred_turn_all - 2;
pure_mask = isfinite(Y.turn_purity) & Y.turn_purity >= 0.8 & ~logical(Y.turn_transition);
transition_mask = logical(Y.turn_transition);
metrics.acc_turn_pure = local_masked_acc(turn_pred, Y.turn, pure_mask);
metrics.acc_turn_transition = local_masked_acc(turn_pred, Y.turn, transition_mask);
metrics.n_turn_pure = sum(pure_mask);
metrics.n_turn_transition = sum(transition_mask);
slope_idx = find(Y.mask_theta == 1);
if isempty(slope_idx)
    metrics.mae_theta = 0;
    metrics.theta_true_range_deg = [NaN NaN];
    metrics.theta_pred_range_deg = [NaN NaN];
    metrics.slope_sign_acc = NaN;
    metrics.uphill = local_empty_slope_submetric();
    metrics.downhill = local_empty_slope_submetric();
else
    metrics.mae_theta = mean(abs(theta_all(slope_idx) - Y.theta(slope_idx)));
    metrics.theta_true_range_deg = rad2deg([min(Y.theta(slope_idx)), max(Y.theta(slope_idx))]);
    metrics.theta_pred_range_deg = rad2deg([min(theta_all(slope_idx)), max(theta_all(slope_idx))]);
    metrics.slope_sign_acc = mean(sign(theta_all(slope_idx)) == sign(Y.theta(slope_idx)));
    metrics.uphill = local_slope_submetric(slope_idx(Y.theta(slope_idx) > 0), ...
        pred_main_all, theta_all, Y.theta);
    metrics.downhill = local_slope_submetric(slope_idx(Y.theta(slope_idx) < 0), ...
        pred_main_all, theta_all, Y.theta);
end
slope_mask = logical(Y.mask_theta(:));
theta_deg = rad2deg(Y.theta(:));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_abs_le_8', theta_all, Y.theta, ...
    slope_mask & abs(theta_deg) <= 8.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_abs_le_10', theta_all, Y.theta, ...
    slope_mask & abs(theta_deg) <= 10.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_pos_8_10', theta_all, Y.theta, ...
    slope_mask & theta_deg >= 8.0 & theta_deg <= 10.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_neg_10_8', theta_all, Y.theta, ...
    slope_mask & theta_deg >= -10.0 & theta_deg <= -8.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_pos_6_8', theta_all, Y.theta, ...
    slope_mask & theta_deg >= 6.0 & theta_deg <= 8.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_neg_8_6', theta_all, Y.theta, ...
    slope_mask & theta_deg >= -8.0 & theta_deg <= -6.0));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_neg_2_0p5', theta_all, Y.theta, ...
    slope_mask & theta_deg >= -2.0 & theta_deg <= -0.5));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_pos_0p5_2', theta_all, Y.theta, ...
    slope_mask & theta_deg >= 0.5 & theta_deg <= 2.0));
metrics = local_merge_struct(metrics, local_theta_zone('theta_flat', theta_all, Y.theta, Y.main == 1));
metrics = local_merge_struct(metrics, local_theta_zone('theta_near_flat', theta_all, Y.theta, abs(theta_deg) <= 0.5));
metrics = local_merge_struct(metrics, local_theta_zone('theta_true_zero', theta_all, Y.theta, abs(theta_deg) <= 1e-6));
end

function s = local_empty_slope_submetric()
s = struct('n', 0, 'slope_recall', NaN, 'theta_mae_deg', NaN, ...
    'theta_sign_acc', NaN, 'pred_theta_range_deg', [NaN NaN], ...
    'true_theta_range_deg', [NaN NaN]);
end

function acc = local_masked_acc(pred, truth, mask)
if ~any(mask)
    acc = NaN;
else
    acc = mean(pred(mask) == truth(mask));
end
end

function s = local_slope_submetric(idx, pred_main_all, theta_all, theta_true)
s = local_empty_slope_submetric();
s.n = numel(idx);
if isempty(idx)
    return;
end
s.slope_recall = mean(pred_main_all(idx) == 3);
s.theta_mae_deg = rad2deg(mean(abs(theta_all(idx) - theta_true(idx))));
s.theta_sign_acc = mean(sign(theta_all(idx)) == sign(theta_true(idx)));
s.pred_theta_range_deg = rad2deg([min(theta_all(idx)), max(theta_all(idx))]);
s.true_theta_range_deg = rad2deg([min(theta_true(idx)), max(theta_true(idx))]);
end

function out = local_merge_struct(out, add)
names = fieldnames(add);
for i = 1:numel(names)
    out.(names{i}) = add.(names{i});
end
end

function m = local_theta_error_zone(prefix, theta_hat, theta_true, mask)
mask = logical(mask(:));
m = struct();
if ~any(mask)
    m.([prefix '_mae_deg']) = NaN;
    m.([prefix '_rmse_deg']) = NaN;
    m.([prefix '_p95_abs_err_deg']) = NaN;
    m.([prefix '_max_abs_err_deg']) = NaN;
    m.([prefix '_bias_deg']) = NaN;
    m.([prefix '_n']) = 0;
    return;
end
err_deg = rad2deg(theta_hat(mask) - theta_true(mask));
m.([prefix '_mae_deg']) = mean(abs(err_deg), 'omitnan');
m.([prefix '_rmse_deg']) = sqrt(mean(err_deg.^2, 'omitnan'));
m.([prefix '_p95_abs_err_deg']) = prctile(abs(err_deg), 95);
m.([prefix '_max_abs_err_deg']) = max(abs(err_deg));
m.([prefix '_bias_deg']) = mean(err_deg, 'omitnan');
m.([prefix '_n']) = sum(mask);
end

function m = local_theta_zone(prefix, theta_hat, theta_true, mask)
mask = logical(mask(:));
m = struct();
if ~any(mask)
    m.([prefix '_mae_deg']) = NaN;
    m.([prefix '_abs_p95_deg']) = NaN;
    m.([prefix '_abs_max_deg']) = NaN;
    m.([prefix '_bias_deg']) = NaN;
    m.([prefix '_n']) = 0;
    return;
end
err = theta_hat(mask) - theta_true(mask);
abs_theta_deg = abs(rad2deg(theta_hat(mask)));
m.([prefix '_mae_deg']) = rad2deg(mean(abs(err), 'omitnan'));
m.([prefix '_abs_p95_deg']) = prctile(abs_theta_deg, 95);
m.([prefix '_abs_max_deg']) = max(abs_theta_deg);
m.([prefix '_bias_deg']) = rad2deg(mean(err, 'omitnan'));
m.([prefix '_n']) = sum(mask);
end

function losses = local_eval_losses(pred, X, T, scaler, cfg, class_w_main, class_w_turn)
main_sample_w = local_main_sample_weights(T.main, T.theta, cfg) .* reshape(T.main_weight, [], 1);
loss_main = local_weighted_ce(pred.prob_main, T.main, class_w_main, ...
    cfg.focal_gamma_main, cfg.use_focal_loss, main_sample_w);
turn_sample_w = local_turn_sample_weights(T.turn_weight, T.turn_transition, cfg);
loss_turn = local_weighted_ce(pred.prob_turn, T.turn_cls, class_w_turn, ...
    cfg.focal_gamma_turn, cfg.use_focal_loss, turn_sample_w);
loss_theta = local_weighted_theta_mse(pred.theta, T.theta, T.mask_theta, cfg, T.theta_weight);
flat_zero_mask = local_theta_flat_zero_mask(T.main, T.theta, T.mask_theta, cfg);
loss_theta_flat = local_masked_mse(pred.theta, zeros(size(T.theta), 'like', T.theta), flat_zero_mask);
loss_aux = (local_bce_logits(pred.slip_logit, T.slip) ...
    + local_bce_logits(pred.stall_logit, T.stall) ...
    + local_bce_logits(pred.load_logit, T.load_change)) / 3;
loss_pitch = local_pitch_consistency_loss(pred.theta, X, scaler);
loss_phy = local_physics_consistency_loss(pred, X, scaler, cfg);
loss_smooth = local_feature_smoothness_loss(pred, cfg);
total = loss_main + cfg.lambda_turn * loss_turn ...
    + cfg.lambda_theta * loss_theta ...
    + cfg.lambda_theta_flat * loss_theta_flat ...
    + cfg.lambda_aux * loss_aux ...
    + cfg.lambda_pitch_consistency * loss_pitch ...
    + cfg.lambda_phy * loss_phy ...
    + cfg.lambda_smooth * loss_smooth;
losses = struct('total', total, 'main', loss_main, 'turn', loss_turn, ...
    'theta', loss_theta, 'theta_flat', loss_theta_flat, ...
    'aux', loss_aux, 'pitch', loss_pitch, 'phy', loss_phy, 'smooth', loss_smooth);
end

function grads = local_clip_gradients(grads, threshold, cfg)
if nargin < 3 || ~isfield(cfg, 'grad_clip_mode')
    mode = 'global';
else
    mode = lower(char(cfg.grad_clip_mode));
end
switch mode
    case 'global'
        grads = local_clip_gradients_global(grads, threshold);
    case 'separate'
        grads.net = local_clip_learnable_table(grads.net, threshold);
        names = fieldnames(grads.heads);
        for i = 1:numel(names)
            grads.heads.(names{i}) = local_clip_array(grads.heads.(names{i}), threshold);
        end
    otherwise
        error('TCN_train:BadGradClipMode', '未知 grad_clip_mode: %s', cfg.grad_clip_mode);
end
end

function grads = local_clip_gradients_global(grads, threshold)
norm_sq = dlarray(0);
for i = 1:height(grads.net)
    g = grads.net.Value{i};
    norm_sq = norm_sq + sum(g(:).^2);
end
names = fieldnames(grads.heads);
for i = 1:numel(names)
    g = grads.heads.(names{i});
    norm_sq = norm_sq + sum(g(:).^2);
end
norm_val = sqrt(norm_sq);
if double(gather(extractdata(norm_val))) <= threshold
    return;
end
scale = threshold / norm_val;
for i = 1:height(grads.net)
    grads.net.Value{i} = grads.net.Value{i} * scale;
end
for i = 1:numel(names)
    grads.heads.(names{i}) = grads.heads.(names{i}) * scale;
end
end

function T = local_clip_learnable_table(T, threshold)
norm_sq = dlarray(0);
for i = 1:height(T)
    g = T.Value{i};
    norm_sq = norm_sq + sum(g(:).^2);
end
norm_val = sqrt(norm_sq);
if double(gather(extractdata(norm_val))) <= threshold
    return;
end
scale = threshold / norm_val;
for i = 1:height(T)
    T.Value{i} = T.Value{i} * scale;
end
end

function g = local_clip_array(g, threshold)
norm_val = sqrt(sum(g(:).^2));
if double(gather(extractdata(norm_val))) <= threshold
    return;
end
g = g * (threshold / norm_val);
end

function [net, heads, opt] = local_adam_update(net, heads, grads, opt, lr)
beta1 = 0.9;
beta2 = 0.999;
epsv = 1e-8;

if isempty(opt.avg)
    opt.avg.net = grads.net;
    opt.avg.net.Value(:) = {0};
    opt.avgSq.net = grads.net;
    opt.avgSq.net.Value(:) = {0};
    names = fieldnames(heads);
    for i = 1:numel(names)
        opt.avg.heads.(names{i}) = 0;
        opt.avgSq.heads.(names{i}) = 0;
    end
end

learnables = net.Learnables;
for i = 1:height(learnables)
    g = grads.net.Value{i};
    opt.avg.net.Value{i} = beta1 * opt.avg.net.Value{i} + (1 - beta1) * g;
    opt.avgSq.net.Value{i} = beta2 * opt.avgSq.net.Value{i} + (1 - beta2) * (g.^2);
    mhat = opt.avg.net.Value{i} / (1 - beta1^opt.iter);
    vhat = opt.avgSq.net.Value{i} / (1 - beta2^opt.iter);
    learnables.Value{i} = learnables.Value{i} - lr * mhat ./ (sqrt(vhat) + epsv);
end
net.Learnables = learnables;

names = fieldnames(heads);
for i = 1:numel(names)
    name = names{i};
    g = grads.heads.(name);
    opt.avg.heads.(name) = beta1 * opt.avg.heads.(name) + (1 - beta1) * g;
    opt.avgSq.heads.(name) = beta2 * opt.avgSq.heads.(name) + (1 - beta2) * (g.^2);
    mhat = opt.avg.heads.(name) / (1 - beta1^opt.iter);
    vhat = opt.avgSq.heads.(name) / (1 - beta2^opt.iter);
    heads.(name) = heads.(name) - lr * mhat ./ (sqrt(vhat) + epsv);
end
end

function heads = local_gather_heads(heads)
names = fieldnames(heads);
for i = 1:numel(names)
    heads.(names{i}) = gather(heads.(names{i}));
end
end

function local_write_training_report(cfg, meta, test_metrics)
fid = fopen(cfg.report_file, 'w');
if fid < 0
    warning('TCN_train:ReportWriteFailed', 'Cannot write report: %s', cfg.report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# TCN 训练报告\n\n');
fprintf(fid, '- 生成时间: %s\n', meta.created_at);
fprintf(fid, '- 训练模式: `%s`\n', meta.mode);
fprintf(fid, '- 数据集: `%s`\n', cfg.input_file);
fprintf(fid, '- 模型文件: `%s`\n', cfg.model_file);
fprintf(fid, '- 最佳轮次: %d\n', meta.best_epoch);
if isfield(meta, 'base_best_epoch') && isfinite(meta.base_best_epoch)
    fprintf(fid, '- 主任务基座最佳轮次: %d\n', meta.base_best_epoch);
end
fprintf(fid, '- 最佳验证损失: %.6f\n', meta.best_val_loss);
fprintf(fid, '- 最佳选择分数: %.6f\n', meta.best_selection_score);
if isfield(meta, 'base_best_selection_score') && isfinite(meta.base_best_selection_score)
    fprintf(fid, '- 主任务基座选择分数: %.6f\n', meta.base_best_selection_score);
end
fprintf(fid, '- 选模指标: `%s`\n', cfg.best_metric);
fprintf(fid, '- Base best metric: `%s`, combine_base_and_turn_best=%d\n', ...
    cfg.base_best_metric, double(cfg.combine_base_and_turn_best));
fprintf(fid, '- Base selection start epoch: %d\n', cfg.base_selection_start_epoch);
fprintf(fid, '- Composite guard floors [flat stall slope]: [%.3f %.3f %.3f], weights: [%.3f %.3f %.3f]\n', ...
    cfg.composite_guard_flat_floor, cfg.composite_guard_stall_floor, cfg.composite_guard_slope_floor, ...
    cfg.composite_guard_flat_penalty_weight, cfg.composite_guard_stall_penalty_weight, cfg.composite_guard_slope_penalty_weight);
fprintf(fid, '- Head pooling: `%s`\n', cfg.head_pooling);
fprintf(fid, '- Turn head: `%s`, source=`%s`, hidden=%d\n', ...
    cfg.turn_head_type, cfg.turn_head_source, cfg.turn_head_hidden);
if isfinite(cfg.turn_finetune_start_epoch)
    fprintf(fid, '- Turn finetune: start_epoch=%d, lambda_turn=%.3f, disable_other_losses=%d\n', ...
        cfg.turn_finetune_start_epoch, cfg.turn_finetune_lambda_turn, ...
        double(cfg.turn_finetune_disable_other_losses));
end
fprintf(fid, '- Gradient clip: `%s`, threshold=%.3f\n', cfg.grad_clip_mode, cfg.grad_clip);
fprintf(fid, '- 损失权重: 转弯=%.3f, 坡度=%.3f, 平地坡度约束=%.3f, 辅助=%.3f, pitch一致性=%.3f\n', ...
    cfg.lambda_turn, cfg.lambda_theta, cfg.lambda_theta_flat, cfg.lambda_aux, cfg.lambda_pitch_consistency);
fprintf(fid, '- 平地坡度约束模式: `%s`, near-zero tol=%.3f deg\n', ...
    cfg.theta_flat_loss_mode, cfg.theta_flat_zero_tol_deg);
fprintf(fid, '- Physics-guided loss: lambda_phy=%.3f, lambda_smooth=%.3f, turn_transition_weight=%.3f\n', ...
    cfg.lambda_phy, cfg.lambda_smooth, cfg.turn_transition_weight);
fprintf(fid, '- Physics thresholds: pitch=%.3f deg, turn_signal=%.4f, turn_gyro_weight=%.3f, theta_mag_weight=%.3f\n', ...
    cfg.phy_pitch_threshold_deg, cfg.phy_turn_signal_threshold, ...
    cfg.phy_turn_gyro_weight, cfg.phy_theta_mag_weight);
fprintf(fid, '- 坡度符号权重: 负坡=%.3f, 正坡=%.3f\n', ...
    cfg.theta_neg_weight, cfg.theta_pos_weight);
fprintf(fid, '- 主分类 slope 样本权重: 负坡=%.3f, 正坡=%.3f\n', ...
    cfg.main_neg_slope_weight, cfg.main_pos_slope_weight);
fprintf(fid, '- 下坡选模惩罚权重: %.3f\n', cfg.select_downhill_error_weight);
fprintf(fid, '- 类别权重策略: main=`%s`, turn=`%s`\n', ...
    cfg.class_weight_method, cfg.turn_class_weight_method);
fprintf(fid, '- 主工况类别乘子 [flat stall slope]: [%.3f %.3f %.3f]\n', ...
    cfg.main_class_multipliers(1), cfg.main_class_multipliers(2), cfg.main_class_multipliers(3));
fprintf(fid, '- 转弯类别乘子 [right straight left]: [%.3f %.3f %.3f]\n', ...
    cfg.turn_class_multipliers(1), cfg.turn_class_multipliers(2), cfg.turn_class_multipliers(3));
fprintf(fid, '- Focal loss: enable=%d, gamma_main=%.3f, gamma_turn=%.3f\n', ...
    double(cfg.use_focal_loss), cfg.focal_gamma_main, cfg.focal_gamma_turn);
fprintf(fid, '- 感受野: %d steps / %.3f s\n\n', ...
    meta.receptive_field_steps, meta.receptive_field_seconds);

fprintf(fid, '## 测试指标\n\n');
fprintf(fid, '| 指标 | 数值 |\n|---|---:|\n');
fprintf(fid, '| 总损失 | %.6f |\n', test_metrics.total);
fprintf(fid, '| 主工况准确率 | %.4f |\n', test_metrics.acc_main);
fprintf(fid, '| 转弯准确率 | %.4f |\n', test_metrics.acc_turn);
fprintf(fid, '| 转弯纯窗口准确率 | %.4f |\n', test_metrics.acc_turn_pure);
fprintf(fid, '| 转弯过渡窗口准确率 | %.4f |\n', test_metrics.acc_turn_transition);
fprintf(fid, '| 坡度 MAE deg | %.4f |\n', rad2deg(test_metrics.mae_theta));
fprintf(fid, '| |theta|<=10 P95 deg | %.4f |\n', test_metrics.theta_abs_le_10_p95_abs_err_deg);
fprintf(fid, '| [-10,-8] P95 deg | %.4f |\n', test_metrics.theta_neg_10_8_p95_abs_err_deg);
fprintf(fid, '| [8,10] P95 deg | %.4f |\n', test_metrics.theta_pos_8_10_p95_abs_err_deg);
fprintf(fid, '| [-2,-0.5] P95 deg | %.4f |\n', test_metrics.theta_neg_2_0p5_p95_abs_err_deg);
fprintf(fid, '| [0.5,2] P95 deg | %.4f |\n', test_metrics.theta_pos_0p5_2_p95_abs_err_deg);
fprintf(fid, '| near-flat abs P95 deg | %.4f |\n', test_metrics.theta_near_flat_abs_p95_deg);
fprintf(fid, '| flat theta bias deg | %.4f |\n', test_metrics.theta_flat_bias_deg);

fprintf(fid, '\n## 测试集混淆矩阵\n\n');
fprintf(fid, '### 主工况\n\n');
fprintf(fid, '| true \\ pred | flat | stall | slope | recall |\n|---|---:|---:|---:|---:|\n');
names_main = {'flat','stall','slope'};
for i = 1:3
    fprintf(fid, '| %s | %d | %d | %d | %.4f |\n', names_main{i}, ...
        test_metrics.cm_main(i,1), test_metrics.cm_main(i,2), test_metrics.cm_main(i,3), ...
        test_metrics.recall_main(i));
end
fprintf(fid, '\n| pred class | precision |\n|---|---:|\n');
for i = 1:3
    fprintf(fid, '| %s | %.4f |\n', names_main{i}, test_metrics.precision_main(i));
end

fprintf(fid, '\n### 转弯方向\n\n');
fprintf(fid, '| true \\ pred | right | straight | left | recall |\n|---|---:|---:|---:|---:|\n');
names_turn = {'right','straight','left'};
for i = 1:3
    fprintf(fid, '| %s | %d | %d | %d | %.4f |\n', names_turn{i}, ...
        test_metrics.cm_turn(i,1), test_metrics.cm_turn(i,2), test_metrics.cm_turn(i,3), ...
        test_metrics.recall_turn(i));
end
fprintf(fid, '\n| pred class | precision |\n|---|---:|\n');
for i = 1:3
    fprintf(fid, '| %s | %.4f |\n', names_turn{i}, test_metrics.precision_turn(i));
end

fprintf(fid, '\n## 坡度回归范围\n\n');
fprintf(fid, '- Slope 真值范围: [%.3f, %.3f] deg\n', ...
    test_metrics.theta_true_range_deg(1), test_metrics.theta_true_range_deg(2));
fprintf(fid, '- Slope 预测范围: [%.3f, %.3f] deg\n', ...
    test_metrics.theta_pred_range_deg(1), test_metrics.theta_pred_range_deg(2));
fprintf(fid, '- Slope 符号准确率: %.4f\n', test_metrics.slope_sign_acc);

fprintf(fid, '\n## 上坡/下坡子项指标\n\n');
fprintf(fid, '| 子项 | n | slope recall | theta MAE deg | theta sign acc | true theta range deg | pred theta range deg |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|\n');
local_write_slope_submetric(fid, 'uphill', test_metrics.uphill);
local_write_slope_submetric(fid, 'downhill', test_metrics.downhill);
end

function local_write_slope_submetric(fid, name, s)
fprintf(fid, '| %s | %d | %.4f | %.4f | %.4f | [%.3f, %.3f] | [%.3f, %.3f] |\n', ...
    name, s.n, s.slope_recall, s.theta_mae_deg, s.theta_sign_acc, ...
    s.true_theta_range_deg(1), s.true_theta_range_deg(2), ...
    s.pred_theta_range_deg(1), s.pred_theta_range_deg(2));
end
