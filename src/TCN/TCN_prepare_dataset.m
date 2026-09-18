function dataset = TCN_prepare_dataset(cfg)
%TCN_PREPARE_DATASET 将 TCN/GRU 共享训练母集预处理为窗口化数据集。
%
% 功能说明：
%   读取 data/tcn/TCN_train_data_full.mat 中的 data.runs，将连续仿真
%   回合转换为固定长度时序窗口，供 TCN_train.m 训练使用。该脚本也为
%   后续 GRU 对照组提供同一训练母集、同一 run-level split 和同一输入
%   特征集合，避免由于数据切分不同造成不公平比较。
%
% 处理流程：
%   1. 从每个 run 的 y_raw 中提取 22 维 passive17_plus_all5 输入特征。
%   2. 以 seq_len/stride 在每个 run 内滑窗，不跨 run 生成窗口。
%   3. 主工况默认取窗口末端标签；转弯可单独使用末端、多数投票或
%      末端稳定片段多数投票，并记录窗口纯度供诊断和训练降权。
%   4. 按 run-level 做 train/val/test 切分，禁止相邻窗口泄漏。
%   4. 默认使用 stratified_run_level_v1，使正/负坡、左右转和扰动事件
%      在三个 split 中尽量均衡。
%   5. 仅使用训练集窗口计算 z-score 归一化统计量。
%   6. 保存 dataset、scaler、共享 split 文件和预处理报告。
%
% 关键 cfg：
%   cfg.input_file       : 默认 data/tcn/TCN_train_data_full.mat。
%   cfg.output_file      : 默认 data/tcn/TCN_dataset_processed.mat。
%   cfg.scaler_file      : 默认 data/tcn/TCN_scaler.mat。
%   cfg.split_file       : 默认 data/tcn/TCN_GRU_shared_run_split.mat。
%   cfg.contract_file    : 默认与 output_file 同目录，记录固定数据契约 JSON。
%   cfg.seq_len          : 默认 128。
%   cfg.stride           : 默认 64。
%   cfg.skip_initial_sec : 默认 1.0，短路径训练不建议使用旧 GRU 的 10s。
%   cfg.turn_label_strategy : 默认 'tail_majority'，可选 'end' / 'majority'。
%   cfg.turn_tail_sec       : tail_majority 使用的窗口尾部时长，默认 0.50s。
%   cfg.turn_min_purity     : 转弯 loss 样本权重的纯度阈值，默认 0.70。
%   cfg.transition_rich     : true 时使用过渡段密集滑窗、稳态稀疏滑窗。
%
% 输出 dataset：
%   dataset.X_train/val/test           : [窗口数, seq_len, 22]。
%   dataset.y_main_*                   : 主工况标签 1/2/3。
%   dataset.y_turn_*                   : 转弯标签 -1/0/1。
%   dataset.y_theta_*                  : 坡度角监督值 [rad]。
%   dataset.y_slip/y_stall/y_load_*    : 辅助动态扰动标签。
%   dataset.split_info                 : 共享 run-level 切分信息。
%
% 使用示例：
%   init_project;
%   dataset = TCN_prepare_dataset();

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_defaults(cfg, root);
local_assert_output_paths_preflight(cfg);

if cfg.verbose
    fprintf('\n========== TCN Dataset Preprocess ==========\n');
    fprintf('Input : %s\n', cfg.input_file);
    fprintf('Output: %s\n', cfg.output_file);
    fprintf('seq_len=%d, stride=%d, skip_initial_sec=%.2f\n', ...
        cfg.seq_len, cfg.stride, cfg.skip_initial_sec);
    fprintf('===========================================\n\n');
end

if ~exist(cfg.input_file, 'file')
    error('TCN_prepare_dataset:MissingInput', 'Input file not found: %s', cfg.input_file);
end
S = load(cfg.input_file, 'data');
if ~isfield(S, 'data') || ~isfield(S.data, 'runs')
    error('TCN_prepare_dataset:InvalidInput', 'Input must contain data.runs.');
end
data = S.data;

params = parameters();
if isfield(data, 'meta') && isfield(data.meta, 'Ts')
    Ts = data.meta.Ts;
else
    Ts = params.Ts;
end
cfg.Ts = Ts;

[features_by_run, labels_by_run, feat_names, run_table, feature_contract] = local_extract_runs(data, params, Ts, cfg);
[X_all, labels_all] = local_make_windows(features_by_run, labels_by_run, cfg);
split_info = local_get_or_make_split(labels_all, run_table, cfg);

idx_train = find(ismember(labels_all.run_id, split_info.runs_train));
idx_val = find(ismember(labels_all.run_id, split_info.runs_val));
idx_test = find(ismember(labels_all.run_id, split_info.runs_test));

if cfg.theta_balance_after_split
    [idx_train, split_info.theta_balance_train] = local_balance_theta_indices(idx_train, labels_all, cfg, cfg.seed + 101);
    [idx_val, split_info.theta_balance_val] = local_balance_theta_indices(idx_val, labels_all, cfg, cfg.seed + 102);
    [idx_test, split_info.theta_balance_test] = local_balance_theta_indices(idx_test, labels_all, cfg, cfg.seed + 103);
end
if cfg.turn_balance_after_split
    [idx_train, split_info.turn_balance_train] = local_balance_turn_indices(idx_train, labels_all, cfg, cfg.seed + 201);
    [idx_val, split_info.turn_balance_val] = local_balance_turn_indices(idx_val, labels_all, cfg, cfg.seed + 202);
    [idx_test, split_info.turn_balance_test] = local_balance_turn_indices(idx_test, labels_all, cfg, cfg.seed + 203);
end
if cfg.theta_balance_after_split && cfg.turn_balance_after_split
    [idx_train, split_info.theta_rebalance_train] = local_balance_theta_indices(idx_train, labels_all, cfg, cfg.seed + 301);
    [idx_val, split_info.theta_rebalance_val] = local_balance_theta_indices(idx_val, labels_all, cfg, cfg.seed + 302);
    [idx_test, split_info.theta_rebalance_test] = local_balance_theta_indices(idx_test, labels_all, cfg, cfg.seed + 303);
end

rng(cfg.seed, 'twister');
idx_train = idx_train(randperm(numel(idx_train)));
idx_val = idx_val(randperm(numel(idx_val)));
idx_test = idx_test(randperm(numel(idx_test)));

local_assert_no_split_leakage(labels_all.run_id, idx_train, idx_val, idx_test);

X_train = X_all(idx_train, :, :);
X_val = X_all(idx_val, :, :);
X_test = X_all(idx_test, :, :);

feat_dim = size(X_all, 3);
scaler = struct();
X_train_flat = reshape(X_train, [], feat_dim);
scaler.mean = mean(X_train_flat, 1);
scaler.std = std(X_train_flat, 0, 1);
scaler.std(scaler.std < 1e-8) = 1.0;
scaler.tau_accel_lp = cfg.tau_accel_lp;
scaler.tau_diff = cfg.tau_diff;
scaler.feature_contract = feature_contract.feature_contract;
scaler.feature_names = feature_contract.feature_names;
scaler.feature_policy = local_get_field(feature_contract, ...
    'feature_policy', 'imu_free_passive17_plus_all5');

norm_fn = @(X) (X - reshape(scaler.mean, 1, 1, [])) ./ reshape(scaler.std, 1, 1, []);

dataset = struct();
dataset.X_train = norm_fn(X_train);
dataset.X_val = norm_fn(X_val);
dataset.X_test = norm_fn(X_test);

dataset.y_main_train = labels_all.y_main(idx_train);
dataset.y_main_val = labels_all.y_main(idx_val);
dataset.y_main_test = labels_all.y_main(idx_test);

dataset.main_purity_train = labels_all.main_purity(idx_train);
dataset.main_purity_val = labels_all.main_purity(idx_val);
dataset.main_purity_test = labels_all.main_purity(idx_test);

dataset.main_transition_train = labels_all.main_transition(idx_train);
dataset.main_transition_val = labels_all.main_transition(idx_val);
dataset.main_transition_test = labels_all.main_transition(idx_test);

dataset.main_sample_weight_train = labels_all.main_sample_weight(idx_train);
dataset.main_sample_weight_val = labels_all.main_sample_weight(idx_val);
dataset.main_sample_weight_test = labels_all.main_sample_weight(idx_test);

dataset.y_turn_train = labels_all.y_turn(idx_train);
dataset.y_turn_val = labels_all.y_turn(idx_val);
dataset.y_turn_test = labels_all.y_turn(idx_test);

dataset.turn_purity_train = labels_all.turn_purity(idx_train);
dataset.turn_purity_val = labels_all.turn_purity(idx_val);
dataset.turn_purity_test = labels_all.turn_purity(idx_test);

dataset.turn_transition_train = labels_all.turn_transition(idx_train);
dataset.turn_transition_val = labels_all.turn_transition(idx_val);
dataset.turn_transition_test = labels_all.turn_transition(idx_test);

dataset.turn_sample_weight_train = labels_all.turn_sample_weight(idx_train);
dataset.turn_sample_weight_val = labels_all.turn_sample_weight(idx_val);
dataset.turn_sample_weight_test = labels_all.turn_sample_weight(idx_test);

dataset.y_theta_train = labels_all.y_theta(idx_train);
dataset.y_theta_val = labels_all.y_theta(idx_val);
dataset.y_theta_test = labels_all.y_theta(idx_test);

dataset.theta_range_train = labels_all.theta_range(idx_train);
dataset.theta_range_val = labels_all.theta_range(idx_val);
dataset.theta_range_test = labels_all.theta_range(idx_test);

dataset.theta_transition_train = labels_all.theta_transition(idx_train);
dataset.theta_transition_val = labels_all.theta_transition(idx_val);
dataset.theta_transition_test = labels_all.theta_transition(idx_test);

dataset.theta_sample_weight_train = labels_all.theta_sample_weight(idx_train);
dataset.theta_sample_weight_val = labels_all.theta_sample_weight(idx_val);
dataset.theta_sample_weight_test = labels_all.theta_sample_weight(idx_test);

dataset.mask_theta_train = local_theta_supervision_mask(dataset.y_main_train, dataset.y_theta_train, cfg);
dataset.mask_theta_val = local_theta_supervision_mask(dataset.y_main_val, dataset.y_theta_val, cfg);
dataset.mask_theta_test = local_theta_supervision_mask(dataset.y_main_test, dataset.y_theta_test, cfg);

% 保留辅助标签，用于 physics-guided multi-task TCN 的滑移/堵转/负载输出头。
dataset.y_slip_train = labels_all.y_slip(idx_train);
dataset.y_slip_val = labels_all.y_slip(idx_val);
dataset.y_slip_test = labels_all.y_slip(idx_test);

dataset.y_stall_train = labels_all.y_stall(idx_train);
dataset.y_stall_val = labels_all.y_stall(idx_val);
dataset.y_stall_test = labels_all.y_stall(idx_test);

dataset.y_load_change_train = labels_all.y_load_change(idx_train);
dataset.y_load_change_val = labels_all.y_load_change(idx_val);
dataset.y_load_change_test = labels_all.y_load_change(idx_test);

dataset.run_id_train = labels_all.run_id(idx_train);
dataset.run_id_val = labels_all.run_id(idx_val);
dataset.run_id_test = labels_all.run_id(idx_test);

dataset.scaler = scaler;
dataset.feat_names = feat_names;
dataset.run_table = run_table;
dataset.split_info = split_info;

dataset.meta = struct();
dataset.meta.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
dataset.meta.source_file = cfg.input_file;
dataset.meta.output_file = cfg.output_file;
dataset.meta.Ts = Ts;
dataset.meta.seq_len = cfg.seq_len;
dataset.meta.stride = cfg.stride;
dataset.meta.skip_initial_sec = cfg.skip_initial_sec;
dataset.meta.turn_label_strategy = cfg.turn_label_strategy;
dataset.meta.turn_tail_sec = cfg.turn_tail_sec;
dataset.meta.turn_min_purity = cfg.turn_min_purity;
dataset.meta.turn_ambiguous_weight = cfg.turn_ambiguous_weight;
dataset.meta.transition_rich = cfg.transition_rich;
dataset.meta.steady_stride = cfg.steady_stride;
dataset.meta.transition_stride = cfg.transition_stride;
dataset.meta.transition_context_sec = cfg.transition_context_sec;
dataset.meta.main_min_purity = cfg.main_min_purity;
dataset.meta.main_ambiguous_weight = cfg.main_ambiguous_weight;
dataset.meta.theta_transition_range_deg = cfg.theta_transition_range_deg;
dataset.meta.theta_transition_weight = cfg.theta_transition_weight;
dataset.meta.theta_event_range_deg = cfg.theta_event_range_deg;
dataset.meta.theta_event_window_sec = cfg.theta_event_window_sec;
dataset.meta.theta_mask_strategy = cfg.theta_mask_strategy;
dataset.meta.theta_split_edges_deg = cfg.theta_split_edges_deg;
dataset.meta.theta_balance_after_split = cfg.theta_balance_after_split;
dataset.meta.theta_balance_max_imbalance = cfg.theta_balance_max_imbalance;
dataset.meta.turn_balance_after_split = cfg.turn_balance_after_split;
dataset.meta.turn_balance_min_lr_balance = cfg.turn_balance_min_lr_balance;
dataset.meta.feature_contract = scaler.feature_contract;
dataset.meta.feature_policy = scaler.feature_policy;
dataset.meta.feature_extractor = cfg.feature_extractor;
if isfield(data, 'meta') && isfield(data.meta, 'plant_revision')
    dataset.meta.plant_revision = data.meta.plant_revision;
end
dataset.meta.no_new_inputs = local_get_field(feature_contract, 'no_new_inputs', true);
dataset.meta.base_feature_contract = local_get_field(feature_contract, ...
    'base_feature_contract', feature_contract.feature_contract);
dataset.meta.plan_branch = local_get_field(feature_contract, 'plan_branch', 'Plan A passive-only');
dataset.meta.input_dim = numel(feat_names);
dataset.meta.vehicle_type = 'diagonal_dual_steer_drive_agv';
dataset.meta.active_drive_steer_wheels = {'LF', 'RR'};
dataset.meta.passive_support_wheels = {'RF', 'LR'};
dataset.meta.label_time_policy = 'current_window_end';
dataset.meta.horizon_steps = cfg.horizon_steps;
dataset.meta.horizon_seconds = cfg.horizon_steps * Ts;
dataset.meta.confidence_policy = 'derive_classification_confidence_from_softmax_and_export';
dataset.meta.split_strategy = 'run_level_no_window_leakage';
dataset.meta.split_file = cfg.split_file;
dataset.meta.contract_file = cfg.contract_file;
dataset.meta.overwrite = cfg.overwrite;
dataset.meta.train_ratio = cfg.train_ratio;
dataset.meta.val_ratio = cfg.val_ratio;
dataset.meta.test_ratio = cfg.test_ratio;
dataset.meta.label_map_main = struct('flat', 1, 'stall', 2, 'slope', 3);
dataset.meta.label_map_turn = struct('right', -1, 'straight', 0, 'left', 1);
dataset.meta.self_check = local_collect_stats(dataset);
dataset.contract = local_dataset_contract(dataset);

local_self_check(dataset, cfg);

local_assert_output_paths_safe(cfg, dataset);

out_dir = fileparts(cfg.output_file);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
save(cfg.output_file, 'dataset', '-v7.3');

scaler_data = struct('scaler', scaler, 'feat_names', {feat_names}, ...
    'seq_len', cfg.seq_len, 'stride', cfg.stride, 'Ts', Ts, ...
    'feature_contract', scaler.feature_contract, ...
    'feature_extractor', cfg.feature_extractor);
save(cfg.scaler_file, '-struct', 'scaler_data');

local_write_report(cfg.report_file, dataset);
local_write_contract(cfg.contract_file, dataset.contract);

if cfg.verbose
    fprintf('\n[TCN] Preprocess done.\n');
    fprintf('  Train windows: %d\n', size(dataset.X_train, 1));
    fprintf('  Val windows  : %d\n', size(dataset.X_val, 1));
    fprintf('  Test windows : %d\n', size(dataset.X_test, 1));
    fprintf('  Feature dim  : %d\n', size(dataset.X_train, 3));
    fprintf('  Saved dataset: %s\n', cfg.output_file);
    fprintf('  Saved scaler : %s\n', cfg.scaler_file);
    fprintf('  Saved report : %s\n', cfg.report_file);
    fprintf('  Saved contract: %s\n', cfg.contract_file);
end
end

function cfg = local_defaults(cfg, root)
data_tcn_dir = fullfile(root, 'data', 'tcn');
if ~isfield(cfg, 'input_file') || isempty(cfg.input_file)
    cfg.input_file = fullfile(data_tcn_dir, 'TCN_train_data_full.mat');
end
if ~isfield(cfg, 'output_file') || isempty(cfg.output_file)
    cfg.output_file = fullfile(data_tcn_dir, 'TCN_dataset_processed.mat');
end
if ~isfield(cfg, 'scaler_file') || isempty(cfg.scaler_file)
    cfg.scaler_file = fullfile(data_tcn_dir, 'TCN_scaler.mat');
end
if ~isfield(cfg, 'contract_file') || isempty(cfg.contract_file)
    [out_dir, out_name] = fileparts(cfg.output_file);
    cfg.contract_file = fullfile(out_dir, [out_name '_contract.json']);
end
if ~isfield(cfg, 'split_file') || isempty(cfg.split_file)
    cfg.split_file = fullfile(data_tcn_dir, 'TCN_GRU_shared_run_split.mat');
end
if ~isfield(cfg, 'report_file') || isempty(cfg.report_file)
    cfg.report_file = fullfile(data_tcn_dir, 'TCN_prepare_dataset_report.md');
end
if ~isfield(cfg, 'reuse_split_file'); cfg.reuse_split_file = true; end
if ~isfield(cfg, 'split_strategy'); cfg.split_strategy = 'stratified'; end
if ~isfield(cfg, 'split_search_trials'); cfg.split_search_trials = 8000; end
if ~isfield(cfg, 'seq_len'); cfg.seq_len = 128; end
if ~isfield(cfg, 'stride'); cfg.stride = 64; end
if ~isfield(cfg, 'transition_rich'); cfg.transition_rich = false; end
if ~isfield(cfg, 'steady_stride'); cfg.steady_stride = max(cfg.stride, 128); end
if ~isfield(cfg, 'transition_stride'); cfg.transition_stride = max(1, min(cfg.stride, 16)); end
if ~isfield(cfg, 'transition_context_sec'); cfg.transition_context_sec = 1.00; end
if ~isfield(cfg, 'skip_initial_sec'); cfg.skip_initial_sec = 1.0; end
if ~isfield(cfg, 'train_ratio'); cfg.train_ratio = 0.70; end
if ~isfield(cfg, 'val_ratio'); cfg.val_ratio = 0.15; end
if ~isfield(cfg, 'test_ratio'); cfg.test_ratio = 0.15; end
if ~isfield(cfg, 'seed'); cfg.seed = 42; end
if ~isfield(cfg, 'tau_accel_lp'); cfg.tau_accel_lp = 0.4; end
if ~isfield(cfg, 'tau_diff'); cfg.tau_diff = 0.3; end
if ~isfield(cfg, 'turn_label_strategy'); cfg.turn_label_strategy = 'tail_majority'; end
if ~isfield(cfg, 'turn_tail_sec'); cfg.turn_tail_sec = 0.50; end
if ~isfield(cfg, 'turn_min_purity'); cfg.turn_min_purity = 0.70; end
if ~isfield(cfg, 'turn_ambiguous_weight'); cfg.turn_ambiguous_weight = 0.50; end
if ~isfield(cfg, 'main_min_purity'); cfg.main_min_purity = 0.80; end
if ~isfield(cfg, 'main_ambiguous_weight'); cfg.main_ambiguous_weight = 0.65; end
if ~isfield(cfg, 'theta_transition_range_deg'); cfg.theta_transition_range_deg = 1.50; end
if ~isfield(cfg, 'theta_transition_weight'); cfg.theta_transition_weight = 0.75; end
if ~isfield(cfg, 'theta_event_range_deg'); cfg.theta_event_range_deg = 0.30; end
if ~isfield(cfg, 'theta_event_window_sec'); cfg.theta_event_window_sec = 0.50; end
if ~isfield(cfg, 'theta_mask_strategy'); cfg.theta_mask_strategy = 'main_slope'; end
if ~isfield(cfg, 'theta_split_edges_deg'); cfg.theta_split_edges_deg = -10:1:10; end
if ~isfield(cfg, 'theta_split_bin_weight'); cfg.theta_split_bin_weight = 12.0; end
if ~isfield(cfg, 'theta_split_low_bin_penalty'); cfg.theta_split_low_bin_penalty = 45.0; end
if ~isfield(cfg, 'theta_split_imbalance_penalty'); cfg.theta_split_imbalance_penalty = 25.0; end
if ~isfield(cfg, 'theta_split_min_ratio_of_target'); cfg.theta_split_min_ratio_of_target = 0.65; end
if ~isfield(cfg, 'theta_split_target_imbalance'); cfg.theta_split_target_imbalance = 1.35; end
if ~isfield(cfg, 'theta_balance_after_split'); cfg.theta_balance_after_split = false; end
if ~isfield(cfg, 'theta_balance_max_imbalance'); cfg.theta_balance_max_imbalance = 1.45; end
if ~isfield(cfg, 'turn_balance_after_split'); cfg.turn_balance_after_split = false; end
if ~isfield(cfg, 'turn_balance_min_lr_balance'); cfg.turn_balance_min_lr_balance = 0.90; end
if ~isfield(cfg, 'horizon_steps'); cfg.horizon_steps = 0; end
if cfg.horizon_steps ~= 0
    error('TCN_prepare_dataset:HorizonUnsupported', ...
        ['当前数据集契约固定为 horizon_steps=0（窗口末端当前状态监督）。' ...
         '如需未来预判，请另建 horizon 数据集，避免与当前 GRU/ModernTCN 结果混用。']);
end
if ~isfield(cfg, 'feature_extractor') || isempty(cfg.feature_extractor)
    cfg.feature_extractor = 'passive';
end
if ~isfield(cfg, 'cmd_stats_window_sec'); cfg.cmd_stats_window_sec = 0.2; end
if ~isfield(cfg, 'overwrite'); cfg.overwrite = true; end
if ~isfield(cfg, 'protected_existing_files'); cfg.protected_existing_files = {}; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'min_windows_per_split'); cfg.min_windows_per_split = 1; end
end

function [features_by_run, labels_by_run, feat_names, run_table, feature_contract] = local_extract_runs(data, params, Ts, cfg)
[feat_names, feature_contract] = local_feature_contract(cfg);
feature_cfg = struct('tau_diff', cfg.tau_diff, ...
    'tau_accel_lp', cfg.tau_accel_lp, ...
    'cmd_stats_window_sec', cfg.cmd_stats_window_sec);

features_by_run = cell(numel(data.runs), 1);
labels_by_run = cell(numel(data.runs), 1);
run_table = struct('run_id', {}, 'scene', {}, 'path_file', {}, 'n_raw', {}, 'n_used', {});

for k = 1:numel(data.runs)
    run = data.runs(k);
    y_raw = run.y_raw;
    if size(y_raw, 2) < 18
        error('TCN_prepare_dataset:BadYRaw', 'run %d y_raw needs at least 18 columns.', k);
    end

    N0 = size(y_raw, 1);
    skip_steps = min(N0 - 1, max(0, round(cfg.skip_initial_sec / Ts)));
    idx = (skip_steps + 1):N0;
    y_raw = y_raw(idx, :);
    N = size(y_raw, 1);

    features_by_run{k} = local_extract_features_for_run(run, y_raw, idx, params, Ts, feature_cfg, cfg);

    labels = struct();
    labels.y_main = run.label_main(idx);
    labels.y_turn = run.label_turn(idx);
    labels.y_theta = local_select_theta(run, idx);
    labels.y_slip = local_get_label(run, 'label_slip', idx);
    labels.y_stall = local_get_label(run, 'label_stall', idx);
    labels.y_load_change = local_get_label(run, 'label_load_change', idx);
    labels_by_run{k} = labels;

    run_table(k).run_id = k;
    run_table(k).scene = local_get_field(run, 'scene', sprintf('run_%03d', k));
    run_table(k).path_file = local_get_field(run, 'path_file', '');
    run_table(k).n_raw = N0;
    run_table(k).n_used = N;
end
end

function [X_all, labels_all] = local_make_windows(features_by_run, labels_by_run, cfg)
feat_dim = size(features_by_run{find(~cellfun(@isempty, features_by_run), 1)}, 2);
starts_by_run = cell(numel(features_by_run), 1);
n_win_total = 0;
for k = 1:numel(features_by_run)
    N = size(features_by_run{k}, 1);
    if N >= cfg.seq_len
        starts_by_run{k} = local_window_starts(labels_by_run{k}, N, cfg);
        n_win_total = n_win_total + numel(starts_by_run{k});
    end
end
if n_win_total <= 0
    error('TCN_prepare_dataset:NoWindows', 'No windows generated. Check seq_len/stride/skip_initial_sec.');
end

X_all = zeros(n_win_total, cfg.seq_len, feat_dim);
labels_all = struct();
labels_all.y_main = zeros(n_win_total, 1);
labels_all.y_turn = zeros(n_win_total, 1);
labels_all.y_theta = zeros(n_win_total, 1);
labels_all.y_slip = zeros(n_win_total, 1);
labels_all.y_stall = zeros(n_win_total, 1);
labels_all.y_load_change = zeros(n_win_total, 1);
labels_all.run_id = zeros(n_win_total, 1);
labels_all.main_purity = zeros(n_win_total, 1);
labels_all.main_transition = false(n_win_total, 1);
labels_all.main_sample_weight = ones(n_win_total, 1);
labels_all.turn_purity = zeros(n_win_total, 1);
labels_all.turn_transition = false(n_win_total, 1);
labels_all.turn_sample_weight = ones(n_win_total, 1);
labels_all.theta_range = zeros(n_win_total, 1);
labels_all.theta_transition = false(n_win_total, 1);
labels_all.theta_sample_weight = ones(n_win_total, 1);

w = 0;
tail_len = max(1, min(cfg.seq_len, round(cfg.turn_tail_sec / local_get_Ts_from_cfg(cfg))));
for k = 1:numel(features_by_run)
    F = features_by_run{k};
    L = labels_by_run{k};
    N = size(F, 1);
    if N < cfg.seq_len
        continue;
    end
    for ii = 1:numel(starts_by_run{k})
        start_idx = starts_by_run{k}(ii);
        end_idx = start_idx + cfg.seq_len - 1;
        w = w + 1;
        X_all(w, :, :) = F(start_idx:end_idx, :);

        % 当前状态监督：每个窗口的标签取窗口末端时刻。
        main_window = L.y_main(start_idx:end_idx);
        main_label = L.y_main(end_idx);
        [main_purity, main_transition] = local_main_window_quality(main_window, main_label);
        labels_all.y_main(w) = main_label;
        turn_window = L.y_turn(start_idx:end_idx);
        [turn_label, turn_purity, turn_transition] = local_turn_window_label(turn_window, cfg, tail_len);
        theta_window = L.y_theta(start_idx:end_idx);
        theta_range = range(theta_window);
        theta_transition = theta_range >= deg2rad(cfg.theta_transition_range_deg);
        labels_all.y_turn(w) = turn_label;
        labels_all.y_theta(w) = L.y_theta(end_idx);
        labels_all.y_slip(w) = L.y_slip(end_idx);
        labels_all.y_stall(w) = L.y_stall(end_idx);
        labels_all.y_load_change(w) = L.y_load_change(end_idx);
        labels_all.run_id(w) = k;
        labels_all.main_purity(w) = main_purity;
        labels_all.main_transition(w) = main_transition;
        if main_purity < cfg.main_min_purity
            labels_all.main_sample_weight(w) = cfg.main_ambiguous_weight;
        end
        labels_all.turn_purity(w) = turn_purity;
        labels_all.turn_transition(w) = turn_transition;
        if turn_purity < cfg.turn_min_purity
            labels_all.turn_sample_weight(w) = cfg.turn_ambiguous_weight;
        end
        labels_all.theta_range(w) = theta_range;
        labels_all.theta_transition(w) = theta_transition;
        if theta_transition
            labels_all.theta_sample_weight(w) = cfg.theta_transition_weight;
        end
    end
end
end

function starts = local_window_starts(L, N, cfg)
last_start = N - cfg.seq_len + 1;
if last_start < 1
    starts = [];
    return;
end
if ~cfg.transition_rich
    starts = 1:cfg.stride:last_start;
    return;
end

steady_starts = 1:cfg.steady_stride:last_start;
transition_candidates = 1:cfg.transition_stride:last_start;
event_mask = local_event_mask(L, cfg);
keep_transition = false(size(transition_candidates));
for i = 1:numel(transition_candidates)
    s = transition_candidates(i);
    keep_transition(i) = any(event_mask(s:(s + cfg.seq_len - 1)));
end
starts = unique([steady_starts, transition_candidates(keep_transition), last_start]);
end

function event_mask = local_event_mask(L, cfg)
N = numel(L.y_main);
event_mask = false(N, 1);
main_change = [false; diff(L.y_main(:)) ~= 0];
turn_change = [false; diff(L.y_turn(:)) ~= 0];
theta_change = [false; abs(diff(L.y_theta(:))) >= deg2rad(0.20)];
theta_smooth_change = local_theta_smooth_change_mask(L.y_theta(:), cfg);
event_idx = find(main_change | turn_change | theta_change | theta_smooth_change);
buf = max(0, round(cfg.transition_context_sec / local_get_Ts_from_cfg(cfg)));
for i = 1:numel(event_idx)
    i0 = max(1, event_idx(i) - buf);
    i1 = min(N, event_idx(i) + buf);
    event_mask(i0:i1) = true;
end
end

function [feat_names, feature_contract] = local_feature_contract(cfg)
switch lower(char(cfg.feature_extractor))
    case {'passive','passive17_plus_all5'}
        feat_names = extract_passive_features('names');
        feature_contract = extract_passive_features('contract');
    case {'command_response','cmdresp_lite','cmdresp_lite_v1','plan_b_lite'}
        feat_names = extract_command_response_features('names');
        feature_contract = extract_command_response_features('contract');
    case {'cmdresp_lag1_only','cmdresp_lag1_only_v1','plan_b_lag1_only'}
        feat_names = extract_command_response_lag1_features('names');
        feature_contract = extract_command_response_lag1_features('contract');
    otherwise
        error('TCN_prepare_dataset:BadFeatureExtractor', ...
            'Unknown feature_extractor: %s', char(cfg.feature_extractor));
end
end

function features = local_extract_features_for_run(run, y_raw, idx, params, Ts, feature_cfg, cfg)
switch lower(char(cfg.feature_extractor))
    case {'passive','passive17_plus_all5'}
        features = extract_passive_features('batch', y_raw, params, Ts, feature_cfg);
    case {'command_response','cmdresp_lite','cmdresp_lite_v1','plan_b_lite'}
        if ~isfield(run, 'u') || size(run.u, 2) < 2 || size(run.u, 1) < max(idx)
            error('TCN_prepare_dataset:MissingCommand', ...
                'Command-response features require run.u(:,1:2) for every y_raw row.');
        end
        u_cmd = run.u(idx, 1:2);
        features = extract_command_response_features('batch', y_raw, u_cmd, params, Ts, feature_cfg);
    case {'cmdresp_lag1_only','cmdresp_lag1_only_v1','plan_b_lag1_only'}
        if ~isfield(run, 'u') || size(run.u, 2) < 2 || size(run.u, 1) < max(idx)
            error('TCN_prepare_dataset:MissingCommand', ...
                'Command-response features require run.u(:,1:2) for every y_raw row.');
        end
        u_cmd = run.u(idx, 1:2);
        features = extract_command_response_lag1_features('batch', y_raw, u_cmd, params, Ts, feature_cfg);
    otherwise
        error('TCN_prepare_dataset:BadFeatureExtractor', ...
            'Unknown feature_extractor: %s', char(cfg.feature_extractor));
end
end

function m = local_theta_smooth_change_mask(theta, cfg)
theta = theta(:);
N = numel(theta);
m = false(N, 1);
if ~isfield(cfg, 'theta_event_range_deg') || ~isfinite(cfg.theta_event_range_deg) ...
        || cfg.theta_event_range_deg <= 0
    return;
end
Ts = local_get_Ts_from_cfg(cfg);
half_win = max(1, round(cfg.theta_event_window_sec / Ts));
local_range = movmax(theta, [half_win, half_win]) - movmin(theta, [half_win, half_win]);
m = local_range >= deg2rad(cfg.theta_event_range_deg);
end

function [purity, transition] = local_main_window_quality(main_window, label)
purity = mean(main_window == label);
transition = numel(unique(main_window(:))) > 1;
end

function Ts = local_get_Ts_from_cfg(cfg)
if isfield(cfg, 'Ts') && ~isempty(cfg.Ts)
    Ts = cfg.Ts;
else
    Ts = parameters().Ts;
end
end

function [label, purity, transition] = local_turn_window_label(turn_window, cfg, tail_len)
switch lower(char(cfg.turn_label_strategy))
    case 'end'
        label = turn_window(end);
    case 'majority'
        label = local_majority_label(turn_window);
    case 'tail_majority'
        tail = turn_window((numel(turn_window) - tail_len + 1):end);
        label = local_majority_label(tail);
    otherwise
        error('TCN_prepare_dataset:BadTurnStrategy', ...
            'Unknown turn_label_strategy: %s', cfg.turn_label_strategy);
end
purity = mean(turn_window == label);
transition = numel(unique(turn_window(:))) > 1;
end

function label = local_majority_label(x)
labels = [-1, 0, 1];
counts = arrayfun(@(v) sum(x == v), labels);
mx = max(counts);
ties = labels(counts == mx);
if isscalar(ties)
    label = ties;
elseif any(ties == x(end))
    label = x(end);
elseif any(ties == 0)
    label = 0;
else
    label = ties(1);
end
end

function split_info = local_get_or_make_split(labels_all, run_table, cfg)
run_id_all = labels_all.run_id;
strategy_name = local_split_strategy_name(cfg);
if cfg.reuse_split_file && exist(cfg.split_file, 'file')
    S = load(cfg.split_file, 'split_info');
    old_split = S.split_info;
    if isfield(old_split, 'strategy') && strcmpi(old_split.strategy, strategy_name)
        split_info = old_split;
        local_validate_split(split_info, unique(run_id_all));
        return;
    end
end

unique_runs = unique(run_id_all);

switch lower(char(cfg.split_strategy))
    case 'stratified'
        [runs_train, runs_val, runs_test, split_score, run_feature_table] = ...
            local_make_stratified_split(labels_all, unique_runs, cfg);
    case 'random'
        rng(cfg.seed, 'twister');
        run_perm = unique_runs(randperm(numel(unique_runs)));
        n_train = floor(numel(run_perm) * cfg.train_ratio);
        n_val = floor(numel(run_perm) * cfg.val_ratio);
        runs_train = sort(run_perm(1:n_train));
        runs_val = sort(run_perm(n_train+1:n_train+n_val));
        runs_test = sort(run_perm(n_train+n_val+1:end));
        split_score = NaN;
        run_feature_table = [];
    otherwise
        error('TCN_prepare_dataset:BadSplitStrategy', 'Unknown split_strategy: %s', cfg.split_strategy);
end

split_info = struct();
split_info.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
split_info.seed = cfg.seed;
split_info.train_ratio = cfg.train_ratio;
split_info.val_ratio = cfg.val_ratio;
split_info.test_ratio = cfg.test_ratio;
split_info.runs_train = runs_train;
split_info.runs_val = runs_val;
split_info.runs_test = runs_test;
split_info.seq_len = cfg.seq_len;
split_info.stride = cfg.stride;
split_info.skip_initial_sec = cfg.skip_initial_sec;
split_info.strategy = strategy_name;
split_info.theta_mask_strategy = cfg.theta_mask_strategy;
split_info.theta_split_edges_deg = cfg.theta_split_edges_deg;
split_info.score = split_score;
split_info.run_table = run_table;
split_info.run_feature_table = run_feature_table;

split_dir = fileparts(cfg.split_file);
if ~isempty(split_dir) && ~exist(split_dir, 'dir')
    mkdir(split_dir);
end
save(cfg.split_file, 'split_info');
end

function strategy_name = local_split_strategy_name(cfg)
switch lower(char(cfg.split_strategy))
    case 'stratified'
        if strcmpi(char(cfg.theta_mask_strategy), 'main_slope')
            strategy_name = 'stratified_run_level_v2_theta_1deg';
        else
            strategy_name = sprintf('stratified_run_level_v2_theta_%s_1deg', char(cfg.theta_mask_strategy));
        end
    case 'random'
        if strcmpi(char(cfg.theta_mask_strategy), 'main_slope')
            strategy_name = 'run_level_random';
        else
            strategy_name = sprintf('run_level_random_theta_%s', char(cfg.theta_mask_strategy));
        end
    otherwise
        strategy_name = char(cfg.split_strategy);
end
end

function [runs_train, runs_val, runs_test, best_score, run_feature_table] = local_make_stratified_split(labels_all, unique_runs, cfg)
run_feature_table = local_run_feature_table(labels_all, unique_runs, cfg);
n_runs = numel(unique_runs);
n_train = floor(n_runs * cfg.train_ratio);
n_val = floor(n_runs * cfg.val_ratio);

rng(cfg.seed, 'twister');
best_score = inf;
best_perm = [];

% 随机搜索前先加入一个确定性分组初值，保证切分可复现。
candidate_count = max(1, cfg.split_search_trials);
for trial = 1:candidate_count
    perm = unique_runs(randperm(n_runs));
    tr = perm(1:n_train);
    va = perm(n_train+1:n_train+n_val);
    te = perm(n_train+n_val+1:end);
    score = local_split_score(run_feature_table, tr, va, te, cfg);
    if score < best_score
        best_score = score;
        best_perm = perm;
    end
end

runs_train = sort(best_perm(1:n_train));
runs_val = sort(best_perm(n_train+1:n_train+n_val));
runs_test = sort(best_perm(n_train+n_val+1:end));
end

function T = local_run_feature_table(labels_all, unique_runs, cfg)
base_names = {'n','flat','stall','slope','turn_right','turn_straight','turn_left', ...
    'main_transition','turn_transition','theta_transition', ...
    'slip','stall_aux','load_change','theta_pos','theta_neg','theta_zero', ...
    'theta_small_pos','theta_small_neg','theta_mid_pos','theta_mid_neg', ...
    'theta_high_pos','theta_high_neg','theta_abs_sum'};
theta_bin_names = local_theta_bin_feature_names(cfg);
names = [base_names, theta_bin_names];
T = array2table(zeros(numel(unique_runs), numel(names)), 'VariableNames', names);
T.run_id = unique_runs(:);
T = movevars(T, 'run_id', 'Before', 1);
for i = 1:numel(unique_runs)
    rid = unique_runs(i);
    m = labels_all.run_id == rid;
    theta = labels_all.y_theta(m);
    y_main = labels_all.y_main(m);
    slope_mask = y_main == 3;
    theta_mask = local_theta_supervision_mask(y_main, theta, cfg) == 1;
    theta_deg = rad2deg(theta);
    T.n(i) = nnz(m);
    T.flat(i) = sum(labels_all.y_main(m) == 1);
    T.stall(i) = sum(labels_all.y_main(m) == 2);
    T.slope(i) = sum(slope_mask);
    T.turn_right(i) = sum(labels_all.y_turn(m) == -1);
    T.turn_straight(i) = sum(labels_all.y_turn(m) == 0);
    T.turn_left(i) = sum(labels_all.y_turn(m) == 1);
    T.main_transition(i) = sum(labels_all.main_transition(m) ~= 0);
    T.turn_transition(i) = sum(labels_all.turn_transition(m) ~= 0);
    T.theta_transition(i) = sum(labels_all.theta_transition(m) ~= 0);
    T.slip(i) = sum(labels_all.y_slip(m) == 1);
    T.stall_aux(i) = sum(labels_all.y_stall(m) == 1);
    T.load_change(i) = sum(labels_all.y_load_change(m) == 1);
    T.theta_pos(i) = sum(theta_mask & theta > 0);
    T.theta_neg(i) = sum(theta_mask & theta < 0);
    T.theta_zero(i) = sum(theta_mask & abs(theta_deg) <= 1e-9);
    T.theta_small_pos(i) = sum(theta_mask & theta_deg > 0 & theta_deg < 2);
    T.theta_small_neg(i) = sum(theta_mask & theta_deg < 0 & theta_deg > -2);
    T.theta_mid_pos(i) = sum(theta_mask & theta_deg >= 2 & theta_deg < 6);
    T.theta_mid_neg(i) = sum(theta_mask & theta_deg <= -2 & theta_deg > -6);
    T.theta_high_pos(i) = sum(theta_mask & theta_deg >= 6);
    T.theta_high_neg(i) = sum(theta_mask & theta_deg <= -6);
    T.theta_abs_sum(i) = sum(abs(theta(theta_mask)));
    theta_bin_counts = local_theta_split_bin_counts(theta_deg, theta_mask, cfg.theta_split_edges_deg);
    for bi = 1:numel(theta_bin_names)
        T.(theta_bin_names{bi})(i) = theta_bin_counts(bi);
    end
end
end

function names = local_theta_bin_feature_names(cfg)
n_bins = max(0, numel(cfg.theta_split_edges_deg) - 1);
names = arrayfun(@(i) sprintf('theta_bin_%02d', i), 1:n_bins, 'UniformOutput', false);
end

function counts = local_theta_split_bin_counts(theta_deg, theta_mask, edges_deg)
edges_deg = double(edges_deg(:)');
n_bins = max(0, numel(edges_deg) - 1);
counts = zeros(1, n_bins);
for bi = 1:n_bins
    if bi == n_bins
        in_bin = theta_mask & theta_deg >= edges_deg(bi) & theta_deg <= edges_deg(bi + 1);
    else
        in_bin = theta_mask & theta_deg >= edges_deg(bi) & theta_deg < edges_deg(bi + 1);
    end
    counts(bi) = sum(in_bin);
end
end

function score = local_split_score(T, runs_train, runs_val, runs_test, cfg)
base_feature_names = {'n','flat','stall','slope','turn_right','turn_straight','turn_left', ...
    'main_transition','turn_transition','theta_transition', ...
    'slip','stall_aux','load_change','theta_pos','theta_neg','theta_zero', ...
    'theta_small_pos','theta_small_neg','theta_mid_pos','theta_mid_neg', ...
    'theta_high_pos','theta_high_neg'};
theta_bin_names = local_theta_bin_feature_names(cfg);
feature_names = [base_feature_names, theta_bin_names];
W = [0.5, 1.0, 2.5, 1.5, 1.2, 0.6, 1.2, ...
     1.5, 2.0, 1.5, 2.0, 2.0, 2.0, 3.0, 3.0, 1.5, ...
     4.0, 4.0, 2.0, 2.0, 2.5, 2.5, ...
     repmat(cfg.theta_split_bin_weight, 1, numel(theta_bin_names))];

M = T{:, feature_names};
global_counts = sum(M, 1);
target = [cfg.train_ratio; cfg.val_ratio; cfg.test_ratio] .* global_counts;

split_counts = [
    sum(T{ismember(T.run_id, runs_train), feature_names}, 1)
    sum(T{ismember(T.run_id, runs_val), feature_names}, 1)
    sum(T{ismember(T.run_id, runs_test), feature_names}, 1)
];

den = max(target, 1);
rel_err = (split_counts - target) ./ den;
score = sum((rel_err.^2) .* W, 'all');
score = score + local_theta_split_score(split_counts, target, global_counts, ...
    feature_names, theta_bin_names, cfg);

% 对 val/test 缺失关键少数工况施加更高惩罚。
critical = {'stall','slip','stall_aux','load_change','theta_pos','theta_neg', ...
    'theta_small_pos','theta_small_neg'};
for s = 2:3
    for j = 1:numel(critical)
        col = find(strcmp(feature_names, critical{j}), 1);
        if global_counts(col) > 0 && split_counts(s, col) == 0
            score = score + 100;
        end
    end
end

% 保持验证集和测试集窗口总量接近目标比例。
total_n = global_counts(1);
actual_ratio = split_counts(:,1) / max(total_n, 1);
target_ratio = [cfg.train_ratio; cfg.val_ratio; cfg.test_ratio];
score = score + 10 * sum((actual_ratio - target_ratio).^2);
end

function score = local_theta_split_score(split_counts, target, global_counts, ...
    feature_names, theta_bin_names, cfg)
score = 0;
if isempty(theta_bin_names)
    return;
end
theta_cols = ismember(feature_names, theta_bin_names);
active = global_counts(theta_cols) > 0;
if ~any(active)
    return;
end

for si = 1:3
    counts = split_counts(si, theta_cols);
    target_counts = target(si, theta_cols);
    counts = counts(active);
    target_counts = target_counts(active);

    rel_to_target = counts ./ max(target_counts, 1);
    low = max(0, cfg.theta_split_min_ratio_of_target - rel_to_target);
    score = score + cfg.theta_split_low_bin_penalty * sum(low .^ 2);

    positive_counts = counts(counts > 0);
    if numel(positive_counts) >= 2
        imbalance = max(positive_counts) / max(min(positive_counts), 1);
        excess = max(0, imbalance - cfg.theta_split_target_imbalance);
        score = score + cfg.theta_split_imbalance_penalty * excess ^ 2;
    end

    if si >= 2
        missing = sum(counts == 0);
        score = score + 100.0 * missing;
    end
end
end

function [idx_keep, info] = local_balance_theta_indices(idx, labels_all, cfg, seed)
idx = idx(:);
theta_deg = rad2deg(labels_all.y_theta(idx));
theta_mask = local_theta_supervision_mask(labels_all.y_main(idx), labels_all.y_theta(idx), cfg) == 1;
edges_deg = double(cfg.theta_split_edges_deg(:)');
n_bins = max(0, numel(edges_deg) - 1);
info = struct('enabled', true, 'before', zeros(1, n_bins), ...
    'after', zeros(1, n_bins), 'cap', NaN, 'kept', numel(idx), 'dropped', 0);

if n_bins == 0 || ~any(theta_mask)
    idx_keep = idx;
    return;
end

bin_id = zeros(numel(idx), 1);
for bi = 1:n_bins
    if bi == n_bins
        in_bin = theta_mask & theta_deg >= edges_deg(bi) & theta_deg <= edges_deg(bi + 1);
    else
        in_bin = theta_mask & theta_deg >= edges_deg(bi) & theta_deg < edges_deg(bi + 1);
    end
    bin_id(in_bin) = bi;
    info.before(bi) = sum(in_bin);
end

active_counts = info.before(info.before > 0);
if isempty(active_counts)
    idx_keep = idx;
    return;
end
cap = max(1, floor(min(active_counts) * cfg.theta_balance_max_imbalance));
info.cap = cap;

rng(seed, 'twister');
keep = true(numel(idx), 1);
for bi = 1:n_bins
    members = find(bin_id == bi);
    if numel(members) > cap
        perm = members(randperm(numel(members)));
        keep(perm((cap + 1):end)) = false;
    end
end

idx_keep = idx(keep);
kept_bin_id = bin_id(keep);
for bi = 1:n_bins
    info.after(bi) = sum(kept_bin_id == bi);
end
info.kept = numel(idx_keep);
info.dropped = numel(idx) - numel(idx_keep);
end

function [idx_keep, info] = local_balance_turn_indices(idx, labels_all, cfg, seed)
idx = idx(:);
y_turn = labels_all.y_turn(idx);
right_idx = find(y_turn == -1);
left_idx = find(y_turn == 1);
right_n = numel(right_idx);
left_n = numel(left_idx);
info = struct('enabled', true, 'before', [right_n, left_n], ...
    'after', [right_n, left_n], 'kept', numel(idx), 'dropped', 0);

if right_n == 0 || left_n == 0
    idx_keep = idx;
    return;
end
target = max(eps, cfg.turn_balance_min_lr_balance);
balance = min(right_n, left_n) / max(right_n, left_n);
if balance >= target
    idx_keep = idx;
    return;
end

rng(seed, 'twister');
keep = true(numel(idx), 1);
if right_n > left_n
    cap = floor(left_n / target);
    drop_pool = right_idx(randperm(right_n));
    keep(drop_pool((cap + 1):end)) = false;
else
    cap = floor(right_n / target);
    drop_pool = left_idx(randperm(left_n));
    keep(drop_pool((cap + 1):end)) = false;
end

idx_keep = idx(keep);
y_after = labels_all.y_turn(idx_keep);
info.after = [sum(y_after == -1), sum(y_after == 1)];
info.kept = numel(idx_keep);
info.dropped = numel(idx) - numel(idx_keep);
end

function local_validate_split(split_info, available_runs)
required = {'runs_train', 'runs_val', 'runs_test'};
for i = 1:numel(required)
    if ~isfield(split_info, required{i})
        error('TCN_prepare_dataset:BadSplit', 'Split file missing %s.', required{i});
    end
end
all_split = [split_info.runs_train(:); split_info.runs_val(:); split_info.runs_test(:)];
if numel(unique(all_split)) ~= numel(all_split)
    error('TCN_prepare_dataset:SplitLeakage', 'Split file contains overlapping runs.');
end
if any(~ismember(all_split, available_runs))
    error('TCN_prepare_dataset:SplitMismatch', 'Split file contains run ids unavailable in dataset.');
end
end

function local_assert_no_split_leakage(run_id_all, idx_train, idx_val, idx_test)
r_train = unique(run_id_all(idx_train));
r_val = unique(run_id_all(idx_val));
r_test = unique(run_id_all(idx_test));
if ~isempty(intersect(r_train, r_val)) || ~isempty(intersect(r_train, r_test)) || ~isempty(intersect(r_val, r_test))
    error('TCN_prepare_dataset:RunLeakage', 'A run appears in more than one split.');
end
end

function theta = local_select_theta(run, idx)
if isfield(run, 'y_theta_ground') && numel(run.y_theta_ground) >= max(idx)
    theta = run.y_theta_ground(idx);
elseif isfield(run, 'theta') && numel(run.theta) >= max(idx)
    theta = run.theta(idx);
elseif isfield(run, 'y_raw') && size(run.y_raw, 2) >= 16
    theta = run.y_raw(idx, 16);
else
    error('TCN_prepare_dataset:MissingTheta', 'Run is missing theta labels.');
end
theta = theta(:);
end

function y = local_get_label(run, field_name, idx)
if isfield(run, field_name) && numel(run.(field_name)) >= max(idx)
    y = run.(field_name)(idx);
else
    y = zeros(numel(idx), 1);
end
y = y(:);
end

function value = local_get_field(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
end
end

function value = local_get_dataset_field(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name)
    value = s.(field_name);
else
    value = default_value;
end
end

function stats = local_collect_stats(dataset)
stats = struct();
stats.n_train = size(dataset.X_train, 1);
stats.n_val = size(dataset.X_val, 1);
stats.n_test = size(dataset.X_test, 1);
stats.feat_dim = size(dataset.X_train, 3);
stats.seq_len = size(dataset.X_train, 2);
stats.train_main_counts = local_counts(dataset.y_main_train, 1:3);
stats.val_main_counts = local_counts(dataset.y_main_val, 1:3);
stats.test_main_counts = local_counts(dataset.y_main_test, 1:3);
stats.train_turn_counts = [sum(dataset.y_turn_train == -1), sum(dataset.y_turn_train == 0), sum(dataset.y_turn_train == 1)];
stats.val_turn_counts = [sum(dataset.y_turn_val == -1), sum(dataset.y_turn_val == 0), sum(dataset.y_turn_val == 1)];
stats.test_turn_counts = [sum(dataset.y_turn_test == -1), sum(dataset.y_turn_test == 0), sum(dataset.y_turn_test == 1)];
stats.train_main_purity = local_main_purity_stats(dataset, 'train');
stats.val_main_purity = local_main_purity_stats(dataset, 'val');
stats.test_main_purity = local_main_purity_stats(dataset, 'test');
stats.train_turn_purity = local_turn_purity_stats(dataset, 'train');
stats.val_turn_purity = local_turn_purity_stats(dataset, 'val');
stats.test_turn_purity = local_turn_purity_stats(dataset, 'test');
stats.train_theta_transition = local_theta_transition_stats(dataset, 'train');
stats.val_theta_transition = local_theta_transition_stats(dataset, 'val');
stats.test_theta_transition = local_theta_transition_stats(dataset, 'test');
stats.train_aux_counts = [sum(dataset.y_slip_train == 1), sum(dataset.y_stall_train == 1), sum(dataset.y_load_change_train == 1)];
stats.val_aux_counts = [sum(dataset.y_slip_val == 1), sum(dataset.y_stall_val == 1), sum(dataset.y_load_change_val == 1)];
stats.test_aux_counts = [sum(dataset.y_slip_test == 1), sum(dataset.y_stall_test == 1), sum(dataset.y_load_change_test == 1)];
stats.train_theta_sign_counts = local_theta_sign_counts(dataset.y_theta_train, dataset.mask_theta_train);
stats.val_theta_sign_counts = local_theta_sign_counts(dataset.y_theta_val, dataset.mask_theta_val);
stats.test_theta_sign_counts = local_theta_sign_counts(dataset.y_theta_test, dataset.mask_theta_test);
stats.train_theta_bins = local_theta_bin_counts(dataset.y_theta_train, dataset.mask_theta_train);
stats.val_theta_bins = local_theta_bin_counts(dataset.y_theta_val, dataset.mask_theta_val);
stats.test_theta_bins = local_theta_bin_counts(dataset.y_theta_test, dataset.mask_theta_test);
end

function mask = local_theta_supervision_mask(y_main, theta, cfg)
strategy = lower(char(cfg.theta_mask_strategy));
y_main = y_main(:);
theta = theta(:);
switch strategy
    case {'main_slope','slope'}
        mask = y_main == 3;
    case {'nonstall_full_range','nonstall','full_nonstall'}
        mask = y_main ~= 2;
    case {'all','full_range','all_valid'}
        mask = true(size(theta));
    otherwise
        error('TCN_prepare_dataset:BadThetaMaskStrategy', ...
            'Unknown theta_mask_strategy: %s', cfg.theta_mask_strategy);
end
mask = double(mask & isfinite(theta));
end

function s = local_main_purity_stats(dataset, split_name)
purity = local_get_dataset_field(dataset, sprintf('main_purity_%s', split_name), []);
transition = local_get_dataset_field(dataset, sprintf('main_transition_%s', split_name), []);
weight = local_get_dataset_field(dataset, sprintf('main_sample_weight_%s', split_name), []);
y = dataset.(sprintf('y_main_%s', split_name));
s = struct();
if isempty(purity)
    s.mean = NaN;
    s.low_ratio = NaN;
    s.transition_ratio = NaN;
    s.downweighted_ratio = NaN;
    s.by_class = NaN(3, 4);
    return;
end
s.mean = mean(purity);
s.low_ratio = mean(purity < 0.8);
s.transition_ratio = mean(transition ~= 0);
s.downweighted_ratio = mean(weight < 1);
s.by_class = zeros(3, 4);
for i = 1:3
    m = y == i;
    s.by_class(i, :) = [sum(m), mean(purity(m)), mean(purity(m) < 0.8), mean(transition(m) ~= 0)];
end
end

function s = local_turn_purity_stats(dataset, split_name)
purity = local_get_dataset_field(dataset, sprintf('turn_purity_%s', split_name), []);
transition = local_get_dataset_field(dataset, sprintf('turn_transition_%s', split_name), []);
weight = local_get_dataset_field(dataset, sprintf('turn_sample_weight_%s', split_name), []);
y = dataset.(sprintf('y_turn_%s', split_name));
s = struct();
if isempty(purity)
    s.mean = NaN;
    s.low_ratio = NaN;
    s.transition_ratio = NaN;
    s.downweighted_ratio = NaN;
    s.by_class = NaN(3, 4);
    return;
end
s.mean = mean(purity);
s.low_ratio = mean(purity < 0.8);
s.transition_ratio = mean(transition ~= 0);
s.downweighted_ratio = mean(weight < 1);
s.by_class = zeros(3, 4);
labels = [-1, 0, 1];
for i = 1:numel(labels)
    m = y == labels(i);
    s.by_class(i, :) = [sum(m), mean(purity(m)), mean(purity(m) < 0.8), mean(transition(m) ~= 0)];
end
end

function s = local_theta_transition_stats(dataset, split_name)
theta_range = local_get_dataset_field(dataset, sprintf('theta_range_%s', split_name), []);
transition = local_get_dataset_field(dataset, sprintf('theta_transition_%s', split_name), []);
weight = local_get_dataset_field(dataset, sprintf('theta_sample_weight_%s', split_name), []);
s = struct();
if isempty(theta_range)
    s.range_mean_deg = NaN;
    s.range_p95_deg = NaN;
    s.transition_ratio = NaN;
    s.downweighted_ratio = NaN;
    return;
end
s.range_mean_deg = rad2deg(mean(theta_range));
s.range_p95_deg = rad2deg(prctile(theta_range, 95));
s.transition_ratio = mean(transition ~= 0);
s.downweighted_ratio = mean(weight < 1);
end

function c = local_counts(y, labels)
c = zeros(1, numel(labels));
for i = 1:numel(labels)
    c(i) = sum(y == labels(i));
end
end

function c = local_theta_sign_counts(theta, mask)
m = mask == 1;
c = [sum(theta(m) < 0), sum(abs(theta(m)) <= 1e-12), sum(theta(m) > 0)];
end

function c = local_theta_bin_counts(theta, mask)
theta_deg = rad2deg(theta(:));
m = mask(:) == 1;
edges = [-Inf, -8, -6, -4, -2, 0, 2, 4, 6, 8, Inf];
c = zeros(1, numel(edges) - 1);
for i = 1:(numel(edges) - 1)
    if i == 1
        c(i) = sum(m & theta_deg < edges(i+1));
    elseif i == numel(edges) - 1
        c(i) = sum(m & theta_deg >= edges(i));
    else
        c(i) = sum(m & theta_deg >= edges(i) & theta_deg < edges(i+1));
    end
end
end

function local_self_check(dataset, cfg)
stats = dataset.meta.self_check;
if stats.n_train < cfg.min_windows_per_split || stats.n_val < cfg.min_windows_per_split || stats.n_test < cfg.min_windows_per_split
    error('TCN_prepare_dataset:EmptySplit', 'One split has too few windows.');
end
if any(~isfinite(dataset.X_train(:))) || any(~isfinite(dataset.X_val(:))) || any(~isfinite(dataset.X_test(:)))
    error('TCN_prepare_dataset:BadValues', 'NaN/Inf detected after normalization.');
end
local_assert_no_split_leakage([dataset.run_id_train; dataset.run_id_val; dataset.run_id_test], ...
    (1:numel(dataset.run_id_train))', ...
    numel(dataset.run_id_train) + (1:numel(dataset.run_id_val))', ...
    numel(dataset.run_id_train) + numel(dataset.run_id_val) + (1:numel(dataset.run_id_test))');
end

function local_assert_output_paths_preflight(cfg)
paths = {
    cfg.output_file, ...
    cfg.scaler_file, ...
    cfg.split_file, ...
    cfg.contract_file, ...
    cfg.report_file};
if ~cfg.overwrite
    for i = 1:numel(paths)
        p = paths{i};
        if ~isempty(p) && exist(p, 'file') == 2
            error('TCN_prepare_dataset:OutputExists', ...
                'Output exists and overwrite=false: %s', p);
        end
    end
end
protected = cfg.protected_existing_files;
if ischar(protected) || isstring(protected)
    protected = cellstr(protected);
end
if isempty(protected)
    protected = {};
end
for i = 1:numel(paths)
    p = char(string(paths{i}));
    for j = 1:numel(protected)
        q = char(string(protected{j}));
        if strcmpi(p, q)
            error('TCN_prepare_dataset:ProtectedOutput', ...
                'Refusing to write protected baseline file: %s', p);
        end
    end
end
if local_is_command_response_extractor(cfg.feature_extractor)
    required_tag = local_required_command_response_tag(cfg.feature_extractor);
    for i = 1:numel(paths)
        p = char(string(paths{i}));
        if ~contains(p, required_tag)
            error('TCN_prepare_dataset:UnsafeCommandResponseTag', ...
                'Command-response outputs must include %s in the file name: %s', ...
                required_tag, p);
        end
    end
end
end

function local_assert_output_paths_safe(cfg, dataset)
if isfield(dataset.meta, 'feature_contract') && ...
        contains(char(dataset.meta.feature_contract), 'cmdresp')
    required_tag = local_required_command_response_tag(cfg.feature_extractor);
    if ~contains(char(cfg.output_file), required_tag)
    error('TCN_prepare_dataset:UnsafeCommandResponseTag', ...
        'Command-response outputs must include %s in the file name: %s', ...
        required_tag, cfg.output_file);
    end
end
end

function tf = local_is_command_response_extractor(feature_extractor)
tf = ismember(lower(char(feature_extractor)), ...
    {'command_response','cmdresp_lite','cmdresp_lite_v1','plan_b_lite', ...
     'cmdresp_lag1_only','cmdresp_lag1_only_v1','plan_b_lag1_only'});
end

function tag = local_required_command_response_tag(feature_extractor)
switch lower(char(feature_extractor))
    case {'cmdresp_lag1_only','cmdresp_lag1_only_v1','plan_b_lag1_only'}
        tag = 'cmdresp_lag1_only_v1';
    otherwise
        tag = 'cmdresp_lite_v1';
end
end

function contract = local_dataset_contract(dataset)
meta = dataset.meta;
contract = struct();
contract.dataset_version = local_contract_version(meta);
contract.created_at = meta.created_at;
contract.source_file = meta.source_file;
contract.output_file = meta.output_file;
contract.vehicle_type = meta.vehicle_type;
contract.active_drive_steer_wheels = meta.active_drive_steer_wheels;
contract.passive_support_wheels = meta.passive_support_wheels;
contract.Ts = meta.Ts;
contract.seq_len = meta.seq_len;
contract.input_dim = meta.input_dim;
contract.feature_names = dataset.feat_names(:)';
contract.feature_contract = meta.feature_contract;
contract.feature_policy = meta.feature_policy;
if isfield(meta, 'plant_revision')
    contract.plant_revision = meta.plant_revision;
end
contract.no_new_inputs = meta.no_new_inputs;
contract.feature_extractor = meta.feature_extractor;
contract.base_feature_contract = meta.base_feature_contract;
contract.plan_branch = meta.plan_branch;
contract.label_time_policy = meta.label_time_policy;
contract.horizon_steps = meta.horizon_steps;
contract.horizon_seconds = meta.horizon_seconds;
contract.label_map_main = meta.label_map_main;
contract.label_map_turn = meta.label_map_turn;
contract.split_policy = meta.split_strategy;
contract.split_file = meta.split_file;
contract.scaler_policy = 'fit_train_only_apply_val_test_online';
contract.filter_policy = 'causal_online_replayable_filters_only';
contract.confidence_policy = meta.confidence_policy;
contract.output_contract = 'logits_main3_logits_turn3_theta1_with_softmax_confidence';
contract.train_windows = size(dataset.X_train, 1);
contract.val_windows = size(dataset.X_val, 1);
contract.test_windows = size(dataset.X_test, 1);
end

function version = local_contract_version(meta)
if isfield(meta, 'horizon_steps') && meta.horizon_steps == 0
    horizon_tag = 'h0_current';
else
    horizon_tag = sprintf('h%d', meta.horizon_steps);
end
version = sprintf('diag2steer_Ts%g_seq%d_input%d_%s_confidence', ...
    meta.Ts, meta.seq_len, meta.input_dim, horizon_tag);
version = strrep(version, '.', 'p');
end

function local_write_contract(contract_file, contract)
if isempty(contract_file)
    return;
end
contract_dir = fileparts(contract_file);
if ~isempty(contract_dir) && ~exist(contract_dir, 'dir')
    mkdir(contract_dir);
end
fid = fopen(contract_file, 'w');
if fid < 0
    warning('TCN_prepare_dataset:ContractWriteFailed', 'Cannot write contract: %s', contract_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
try
    payload = jsonencode(contract, 'PrettyPrint', true);
catch
    payload = jsonencode(contract);
end
fprintf(fid, '%s\n', payload);
end

function local_write_report(report_file, dataset)
fid = fopen(report_file, 'w');
if fid < 0
    warning('TCN_prepare_dataset:ReportWriteFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
s = dataset.meta.self_check;
fprintf(fid, '# TCN Prepare Dataset Report\n\n');
fprintf(fid, '- Generated: %s\n', dataset.meta.created_at);
fprintf(fid, '- Source: `%s`\n', dataset.meta.source_file);
fprintf(fid, '- Output: `%s`\n', dataset.meta.output_file);
fprintf(fid, '- Split file: `%s`\n', dataset.meta.split_file);
fprintf(fid, '- Contract file: `%s`\n', dataset.meta.contract_file);
if isfield(dataset, 'split_info') && isfield(dataset.split_info, 'strategy')
    fprintf(fid, '- Split strategy: `%s`\n', dataset.split_info.strategy);
end
if isfield(dataset, 'split_info') && isfield(dataset.split_info, 'score')
    fprintf(fid, '- Split balance score: %.6f\n', dataset.split_info.score);
end
fprintf(fid, '- Feature contract: `%s`\n', dataset.meta.feature_contract);
if isfield(dataset.meta, 'plant_revision') && ...
        isfield(dataset.meta.plant_revision, 'id')
    fprintf(fid, '- Plant revision: `%s`\n', dataset.meta.plant_revision.id);
end
fprintf(fid, '- Vehicle: `%s`, active wheels=`%s`, passive wheels=`%s`\n', ...
    dataset.meta.vehicle_type, strjoin(dataset.meta.active_drive_steer_wheels, ','), ...
    strjoin(dataset.meta.passive_support_wheels, ','));
fprintf(fid, '- Input policy: `%s`, input_dim=%d, no_new_inputs=%d\n', ...
    dataset.meta.feature_policy, dataset.meta.input_dim, double(dataset.meta.no_new_inputs));
fprintf(fid, '- Label time policy: `%s`, horizon_steps=%d, horizon_seconds=%.3f\n', ...
    dataset.meta.label_time_policy, dataset.meta.horizon_steps, dataset.meta.horizon_seconds);
fprintf(fid, '- Confidence policy: `%s`\n', dataset.meta.confidence_policy);
if isfield(dataset.meta, 'theta_mask_strategy')
    fprintf(fid, '- theta_mask_strategy: `%s`\n', dataset.meta.theta_mask_strategy);
end
fprintf(fid, '- seq_len: %d\n', dataset.meta.seq_len);
fprintf(fid, '- stride: %d\n', dataset.meta.stride);
if isfield(dataset.meta, 'transition_rich')
    fprintf(fid, '- transition_rich: %d\n', dataset.meta.transition_rich);
    fprintf(fid, '- steady_stride: %d\n', dataset.meta.steady_stride);
    fprintf(fid, '- transition_stride: %d\n', dataset.meta.transition_stride);
    fprintf(fid, '- transition_context_sec: %.2f\n', dataset.meta.transition_context_sec);
end
fprintf(fid, '- skip_initial_sec: %.2f\n', dataset.meta.skip_initial_sec);
if isfield(dataset.meta, 'turn_label_strategy')
    fprintf(fid, '- turn_label_strategy: `%s`\n', dataset.meta.turn_label_strategy);
    fprintf(fid, '- turn_tail_sec: %.2f\n', dataset.meta.turn_tail_sec);
    fprintf(fid, '- turn_min_purity: %.2f\n', dataset.meta.turn_min_purity);
    fprintf(fid, '- turn_ambiguous_weight: %.2f\n', dataset.meta.turn_ambiguous_weight);
end
fprintf(fid, '\n');

fprintf(fid, '## Window Counts\n\n');
fprintf(fid, '| split | windows |\n|---|---:|\n');
fprintf(fid, '| train | %d |\n', s.n_train);
fprintf(fid, '| val | %d |\n', s.n_val);
fprintf(fid, '| test | %d |\n\n', s.n_test);

fprintf(fid, '## Main Labels\n\n');
fprintf(fid, '| split | flat | stall | slope |\n|---|---:|---:|---:|\n');
fprintf(fid, '| train | %d | %d | %d |\n', s.train_main_counts);
fprintf(fid, '| val | %d | %d | %d |\n', s.val_main_counts);
fprintf(fid, '| test | %d | %d | %d |\n\n', s.test_main_counts);

fprintf(fid, '## Turn Labels\n\n');
fprintf(fid, '| split | right | straight | left |\n|---|---:|---:|---:|\n');
fprintf(fid, '| train | %d | %d | %d |\n', s.train_turn_counts);
fprintf(fid, '| val | %d | %d | %d |\n', s.val_turn_counts);
fprintf(fid, '| test | %d | %d | %d |\n\n', s.test_turn_counts);

fprintf(fid, '## Main Window Purity\n\n');
fprintf(fid, '| split | mean purity | low purity `<0.8` | transition ratio | downweighted ratio |\n|---|---:|---:|---:|---:|\n');
fprintf(fid, '| train | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.train_main_purity.mean, s.train_main_purity.low_ratio, s.train_main_purity.transition_ratio, s.train_main_purity.downweighted_ratio);
fprintf(fid, '| val | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.val_main_purity.mean, s.val_main_purity.low_ratio, s.val_main_purity.transition_ratio, s.val_main_purity.downweighted_ratio);
fprintf(fid, '| test | %.4f | %.4f | %.4f | %.4f |\n\n', ...
    s.test_main_purity.mean, s.test_main_purity.low_ratio, s.test_main_purity.transition_ratio, s.test_main_purity.downweighted_ratio);

fprintf(fid, '## Turn Window Purity\n\n');
fprintf(fid, '| split | mean purity | low purity `<0.8` | transition ratio | downweighted ratio |\n|---|---:|---:|---:|---:|\n');
fprintf(fid, '| train | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.train_turn_purity.mean, s.train_turn_purity.low_ratio, s.train_turn_purity.transition_ratio, s.train_turn_purity.downweighted_ratio);
fprintf(fid, '| val | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.val_turn_purity.mean, s.val_turn_purity.low_ratio, s.val_turn_purity.transition_ratio, s.val_turn_purity.downweighted_ratio);
fprintf(fid, '| test | %.4f | %.4f | %.4f | %.4f |\n\n', ...
    s.test_turn_purity.mean, s.test_turn_purity.low_ratio, s.test_turn_purity.transition_ratio, s.test_turn_purity.downweighted_ratio);

fprintf(fid, '### Turn Purity By Label\n\n');
fprintf(fid, '| split | label | windows | mean purity | low purity `<0.8` | transition ratio |\n|---|---|---:|---:|---:|---:|\n');
turn_names = {'right','straight','left'};
turn_splits = {'train','val','test'};
for si = 1:numel(turn_splits)
    ps = s.(sprintf('%s_turn_purity', turn_splits{si}));
    for ci = 1:numel(turn_names)
        fprintf(fid, '| %s | %s | %d | %.4f | %.4f | %.4f |\n', ...
            turn_splits{si}, turn_names{ci}, ps.by_class(ci, 1), ...
            ps.by_class(ci, 2), ps.by_class(ci, 3), ps.by_class(ci, 4));
    end
end
fprintf(fid, '\n');

fprintf(fid, '## Theta Transition Windows\n\n');
fprintf(fid, '| split | range mean deg | range p95 deg | transition ratio | downweighted ratio |\n|---|---:|---:|---:|---:|\n');
fprintf(fid, '| train | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.train_theta_transition.range_mean_deg, s.train_theta_transition.range_p95_deg, ...
    s.train_theta_transition.transition_ratio, s.train_theta_transition.downweighted_ratio);
fprintf(fid, '| val | %.4f | %.4f | %.4f | %.4f |\n', ...
    s.val_theta_transition.range_mean_deg, s.val_theta_transition.range_p95_deg, ...
    s.val_theta_transition.transition_ratio, s.val_theta_transition.downweighted_ratio);
fprintf(fid, '| test | %.4f | %.4f | %.4f | %.4f |\n\n', ...
    s.test_theta_transition.range_mean_deg, s.test_theta_transition.range_p95_deg, ...
    s.test_theta_transition.transition_ratio, s.test_theta_transition.downweighted_ratio);

fprintf(fid, '## Auxiliary Labels\n\n');
fprintf(fid, '| split | slip | stall | load_change |\n|---|---:|---:|---:|\n');
fprintf(fid, '| train | %d | %d | %d |\n', s.train_aux_counts);
fprintf(fid, '| val | %d | %d | %d |\n', s.val_aux_counts);
fprintf(fid, '| test | %d | %d | %d |\n', s.test_aux_counts);

fprintf(fid, '\n## Slope Sign Coverage\n\n');
fprintf(fid, '| split | negative slope | zero slope | positive slope |\n|---|---:|---:|---:|\n');
fprintf(fid, '| train | %d | %d | %d |\n', s.train_theta_sign_counts);
fprintf(fid, '| val | %d | %d | %d |\n', s.val_theta_sign_counts);
fprintf(fid, '| test | %d | %d | %d |\n', s.test_theta_sign_counts);

fprintf(fid, '\n## Theta Supervision Bins\n\n');
fprintf(fid, '| split | `<-8` | `[-8,-6)` | `[-6,-4)` | `[-4,-2)` | `[-2,0)` | `[0,2)` | `[2,4)` | `[4,6)` | `[6,8)` | `>=8` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
fprintf(fid, '| train | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n', s.train_theta_bins);
fprintf(fid, '| val | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n', s.val_theta_bins);
fprintf(fid, '| test | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n', s.test_theta_bins);
end
