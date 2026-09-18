function result = ModernTCN_matlab_full_testset_eval(seeds, max_windows, cfg_user)
%MODERNTCN_MATLAB_FULL_TESTSET_EVAL 用 MATLAB 导入的 ONNX 模型重跑完整测试集。
%
% 功能说明：
%   该脚本是 PyTorch -> ONNX -> MATLAB 链路进入 Simulink 前的离线总检查。
%   它会读取当前推荐数据集中的 X_test 和标签，逐个 seed 导入对应 ONNX，
%   用 MATLAB dlnetwork 对测试窗口做推理，然后重新计算 acc_main、
%   acc_turn、acc_turn_transition、theta_mae_deg、flat/stall/slope recall 等
%   指标，并和 Python 训练阶段保存的 summary.csv 做对照。
%
% 为什么需要这一步：
%   之前的 consistency check 只验证少量样本的数值输出是否一致；本脚本验证
%   完整测试集上的标签映射、输出顺序、argmax/softmax 后处理、转弯过渡掩码、
%   theta mask 和指标统计是否都和 Python 端一致。
%
% 用法：
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'ModernTCN'));
%
%   % 快速 smoke test，只跑推荐 seed 的前 16 个测试窗口：
%   ModernTCN_matlab_full_testset_eval([], 16);
%
%   % 正式运行 5 seed 完整测试集：
%   result = ModernTCN_matlab_full_testset_eval();
%
% 输入：
%   seeds       : 可选，默认 [11 21 42 73 101]。
%   max_windows : 可选，默认 0 表示完整 X_test；大于 0 时只跑前 max_windows
%                 个窗口，用于快速检查脚本是否可运行。
%
% 输出：
%   result : 结构体，包含 per-seed 表、汇总表、输出文件路径和是否通过。

if nargin < 2 || isempty(max_windows)
    max_windows = 0;
end
if nargin < 3 || isempty(cfg_user)
    cfg_user = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
default_cfg = ModernTCN_default_config(root);
if nargin < 1 || isempty(seeds)
    seeds = default_cfg.seed;
end
cfg = local_cfg(root, max_windows, cfg_user, default_cfg);
if exist(cfg.output_dir, 'dir') ~= 7
    mkdir(cfg.output_dir);
end

dataset_file = cfg.dataset_file;
if exist(dataset_file, 'file') ~= 2
    error('ModernTCN:MissingDataset', '找不到数据集: %s', dataset_file);
end
S = load(dataset_file, 'dataset');
dataset = S.dataset;
data = local_make_test_data(dataset, max_windows);

rows = repmat(local_empty_row(), numel(seeds), 1);
diff_rows = repmat(local_empty_diff_row(), numel(seeds) * numel(cfg.metric_names), 1);
diff_k = 0;

fprintf('[ModernTCN MATLAB full-test] dataset: %s\n', dataset_file);
fprintf('[ModernTCN MATLAB full-test] windows: %d / %d\n', data.n, size(dataset.X_test, 1));

for i = 1:numel(seeds)
    seed = seeds(i);
    fprintf('\n[ModernTCN MATLAB full-test] seed %d (%d/%d)\n', seed, i, numel(seeds));
    onnx_file = local_onnx_file(root, cfg, seed);
    if exist(onnx_file, 'file') ~= 2
        error('ModernTCN:MissingONNX', '找不到 ONNX 文件: %s', onnx_file);
    end

    tic_seed = tic;
    net = local_import_modern_tcn_onnx(onnx_file, root);
    pred = local_predict_dataset(net, data.X);
    metrics = local_compute_metrics(pred, data);
    elapsed = toc(tic_seed);

    rows(i) = local_row_from_metrics(seed, metrics, elapsed, onnx_file, cfg);
    rows(i).n_windows = data.n;
    local_save_seed_outputs(cfg, seed, pred, metrics, elapsed, onnx_file);

    if cfg.compare_with_python
        py = local_read_python_summary(root, seed, cfg);
        for m = 1:numel(cfg.metric_names)
            name = cfg.metric_names{m};
            diff_k = diff_k + 1;
            diff_rows(diff_k) = local_diff_row(seed, name, rows(i).(name), py.(name), cfg.metric_abs_tol);
        end
    end

    fprintf(['  main=%.4f turn=%.4f turnT=%.4f theta=%.4f deg | ' ...
        'flat=%.4f stall=%.4f slope=%.4f | %.1f s\n'], ...
        rows(i).acc_main, rows(i).acc_turn, rows(i).acc_turn_transition, rows(i).theta_mae_deg, ...
        rows(i).flat_recall, rows(i).stall_recall, rows(i).slope_recall, elapsed);
end

if diff_k == 0
    diff_rows = repmat(local_empty_diff_row(), 0, 1);
else
    diff_rows = diff_rows(1:diff_k);
end

T = struct2table(rows);
T_summary = local_summary_table(T, cfg.metric_names);
T_diff = struct2table(diff_rows);

per_seed_csv = fullfile(cfg.output_dir, 'ModernTCN_v1_matlab_full_testset_per_seed.csv');
summary_csv = fullfile(cfg.output_dir, 'ModernTCN_v1_matlab_full_testset_summary.csv');
diff_csv = fullfile(cfg.output_dir, 'ModernTCN_v1_matlab_full_testset_python_diff.csv');
report_file = fullfile(cfg.output_dir, 'ModernTCN_v1_matlab_full_testset_report.md');

writetable(T, per_seed_csv);
writetable(T_summary, summary_csv);
if ~isempty(diff_rows)
    writetable(T_diff, diff_csv);
else
    diff_csv = "";
end
local_write_report(report_file, cfg, dataset_file, T, T_summary, T_diff);

result = struct();
result.per_seed = T;
result.summary = T_summary;
result.diff = T_diff;
result.output_dir = cfg.output_dir;
result.per_seed_csv = per_seed_csv;
result.summary_csv = summary_csv;
result.diff_csv = diff_csv;
result.report_file = report_file;
result.pass = local_overall_pass(T_diff, cfg);

fprintf('\n[ModernTCN MATLAB full-test] done | pass=%d\n', result.pass);
fprintf('  per-seed: %s\n', per_seed_csv);
fprintf('  summary : %s\n', summary_csv);
if strlength(string(diff_csv)) > 0
    fprintf('  diff    : %s\n', diff_csv);
end
fprintf('  report  : %s\n', report_file);
end

function cfg = local_cfg(root, max_windows, cfg_user, default_cfg)
cfg = struct();
cfg.max_windows = max_windows;
cfg.dataset_file = default_cfg.dataset_file;
cfg.run_tag = default_cfg.run_tag;
cfg.onnx_file = '';
cfg.metric_abs_tol = 1e-4;
cfg.metric_names = {'acc_main','acc_turn','acc_turn_pure','acc_turn_transition', ...
    'theta_mae_deg','flat_recall','stall_recall','slope_recall', ...
    'uphill_recall','downhill_recall', ...
    'theta_abs_le_8_mae_deg','theta_abs_le_8_p95_abs_err_deg', ...
    'theta_abs_le_10_mae_deg','theta_abs_le_10_p95_abs_err_deg', ...
    'theta_pos_8_10_mae_deg','theta_pos_8_10_p95_abs_err_deg','theta_pos_8_10_bias_deg', ...
    'theta_neg_10_8_mae_deg','theta_neg_10_8_p95_abs_err_deg','theta_neg_10_8_bias_deg', ...
    'theta_pos_6_8_mae_deg','theta_pos_6_8_p95_abs_err_deg','theta_pos_6_8_bias_deg', ...
    'theta_neg_8_6_mae_deg','theta_neg_8_6_p95_abs_err_deg','theta_neg_8_6_bias_deg'};
cfg.compare_with_python = max_windows <= 0;
if max_windows > 0
    cfg.output_dir = fullfile(root, 'results', 'modern_tcn', sprintf('matlab_full_testset_smoke_n%d', max_windows));
else
    cfg.output_dir = fullfile(root, 'results', 'modern_tcn', 'matlab_full_testset');
end
if isstruct(cfg_user)
    names = fieldnames(cfg_user);
    for i = 1:numel(names)
        cfg.(names{i}) = cfg_user.(names{i});
    end
end
if local_has_text(cfg.run_tag) && ~isfield(cfg_user, 'output_dir')
    tag = regexprep(char(cfg.run_tag), '[^A-Za-z0-9_\-]+', '_');
    if max_windows > 0
        cfg.output_dir = fullfile(root, 'results', 'modern_tcn', sprintf('matlab_full_testset_%s_smoke_n%d', tag, max_windows));
    else
        cfg.output_dir = fullfile(root, 'results', 'modern_tcn', sprintf('matlab_full_testset_%s', tag));
    end
end
end

function onnx_file = local_onnx_file(root, cfg, seed)
if isfield(cfg, 'onnx_file') && local_has_text(cfg.onnx_file)
    onnx_file = char(cfg.onnx_file);
elseif isfield(cfg, 'run_tag') && local_has_text(cfg.run_tag)
    onnx_file = fullfile(root, 'results', 'modern_tcn', char(cfg.run_tag), ...
        sprintf('modern_tcn_seed%d.onnx', seed));
else
    onnx_file = fullfile(root, 'results', 'modern_tcn', sprintf('modern_tcn_v4_industrial_seed%d', seed), ...
        sprintf('modern_tcn_seed%d.onnx', seed));
end
end

function data = local_make_test_data(dataset, max_windows)
n_total = size(dataset.X_test, 1);
if max_windows > 0
    n = min(max_windows, n_total);
else
    n = n_total;
end
idx = 1:n;
data = struct();
data.X = single(dataset.X_test(idx,:,:));
data.y_main = double(dataset.y_main_test(idx));
data.y_turn = double(dataset.y_turn_test(idx));
data.y_theta = double(dataset.y_theta_test(idx));
data.mask_theta = double(dataset.mask_theta_test(idx));
data.turn_purity = local_field_or_default(dataset, 'turn_purity_test', nan(n_total, 1), idx);
data.turn_transition = logical(local_field_or_default(dataset, 'turn_transition_test', false(n_total, 1), idx));
data.n = n;
data.n_total = n_total;
end

function v = local_field_or_default(s, field_name, default_value, idx)
if isfield(s, field_name)
    raw = s.(field_name);
else
    raw = default_value;
end
v = raw(idx);
v = v(:);
end

function net = local_import_modern_tcn_onnx(onnx_file, root)
layer_root = fullfile(root, 'src', 'ModernTCN', 'generated_layers');
if exist(layer_root, 'dir') ~= 7
    mkdir(layer_root);
end
addpath(layer_root);
old_dir = pwd;
cleanup = onCleanup(@() cd(old_dir));
cd(layer_root);
net = importNetworkFromONNX(onnx_file, Namespace="modern_tcn_onnx_layers");
end

function pred = local_predict_dataset(net, X)
n = size(X, 1);
pred = struct();
pred.logits_main = zeros(n, 3, 'single');
pred.logits_turn = zeros(n, 3, 'single');
pred.theta_hat = zeros(n, 1, 'single');
for i = 1:n
    [lm, lt, th] = local_predict_one(net, X(i,:,:));
    pred.logits_main(i,:) = lm(1,:);
    pred.logits_turn(i,:) = lt(1,:);
    pred.theta_hat(i,:) = th(1,:);
    if mod(i, 500) == 0 || i == n
        fprintf('    predicted %d/%d windows\n', i, n);
    end
end
end

function [logits_main, logits_turn, theta_hat] = local_predict_one(net, X)
% ONNX 输入为 [batch,time,feature]，但不同导入版本可能要求 dlarray 格式。
try
    [logits_main, logits_turn, theta_hat] = predict(net, X);
catch
    try
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(X, "BTC"));
    catch
        Xctb = permute(X, [3 2 1]);
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(Xctb, "CTB"));
    end
end
logits_main = local_to_batch_first(local_extract(logits_main), 3);
logits_turn = local_to_batch_first(local_extract(logits_turn), 3);
theta_hat = local_to_batch_first(local_extract(theta_hat), 1);
end

function A = local_extract(A)
if isa(A, 'dlarray')
    A = gather(extractdata(A));
else
    A = gather(A);
end
end

function A = local_to_batch_first(A, width)
A = squeeze(A);
if size(A, 2) ~= width && size(A, 1) == width
    A = A.';
end
if width == 1
    A = reshape(A, [], 1);
end
A = single(A);
end

function metrics = local_compute_metrics(pred, data)
[~, pred_main] = max(pred.logits_main, [], 2); % 1/2/3 = flat/stall/slope
[~, pred_turn_cls] = max(pred.logits_turn, [], 2);
pred_turn = pred_turn_cls - 2; % -1/0/1 = right/straight/left

metrics = struct();
metrics.acc_main = mean(pred_main == data.y_main);
metrics.acc_turn = mean(pred_turn == data.y_turn);
metrics.cm_main = local_confusion_matrix(data.y_main, pred_main, [1 2 3]);
recall = diag(metrics.cm_main) ./ max(sum(metrics.cm_main, 2), 1);
metrics.flat_recall = recall(1);
metrics.stall_recall = recall(2);
metrics.slope_recall = recall(3);

pure_mask = isfinite(data.turn_purity) & data.turn_purity >= 0.8 & ~data.turn_transition;
transition_mask = data.turn_transition;
metrics.acc_turn_pure = local_masked_acc(pred_turn, data.y_turn, pure_mask);
metrics.acc_turn_transition = local_masked_acc(pred_turn, data.y_turn, transition_mask);
metrics.n_turn_pure = sum(pure_mask);
metrics.n_turn_transition = sum(transition_mask);

theta_hat = double(pred.theta_hat(:));
theta_true = double(data.y_theta(:));
slope_idx = find(data.mask_theta == 1);
if isempty(slope_idx)
    metrics.theta_mae_deg = 0;
    metrics.uphill_recall = NaN;
    metrics.downhill_recall = NaN;
else
    metrics.theta_mae_deg = rad2deg(mean(abs(theta_hat(slope_idx) - theta_true(slope_idx))));
    uphill_idx = slope_idx(theta_true(slope_idx) > 0);
    downhill_idx = slope_idx(theta_true(slope_idx) < 0);
    metrics.uphill_recall = local_slope_sub_recall(pred_main, uphill_idx);
    metrics.downhill_recall = local_slope_sub_recall(pred_main, downhill_idx);
end

slope_mask = logical(data.mask_theta(:));
theta_deg = rad2deg(theta_true);
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_abs_le_8', theta_hat, theta_true, ...
    slope_mask & (abs(theta_deg) <= 8.0)));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_abs_le_10', theta_hat, theta_true, ...
    slope_mask & (abs(theta_deg) <= 10.0)));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_pos_8_10', theta_hat, theta_true, ...
    slope_mask & (theta_deg >= 8.0) & (theta_deg <= 10.0)));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_neg_10_8', theta_hat, theta_true, ...
    slope_mask & (theta_deg >= -10.0) & (theta_deg <= -8.0)));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_pos_6_8', theta_hat, theta_true, ...
    slope_mask & (theta_deg >= 6.0) & (theta_deg <= 8.0)));
metrics = local_merge_struct(metrics, local_theta_error_zone('theta_neg_8_6', theta_hat, theta_true, ...
    slope_mask & (theta_deg >= -8.0) & (theta_deg <= -6.0)));
end

function out = local_merge_struct(out, add)
names = fieldnames(add);
for i = 1:numel(names)
    out.(names{i}) = add.(names{i});
end
end

function m = local_theta_error_zone(prefix, theta_hat, theta_true, mask)
mask = logical(mask(:));
if ~any(mask)
    m = struct();
    m.([prefix '_mae_deg']) = NaN;
    m.([prefix '_rmse_deg']) = NaN;
    m.([prefix '_p95_abs_err_deg']) = NaN;
    m.([prefix '_bias_deg']) = NaN;
    m.([prefix '_n']) = 0;
    return;
end
err_deg = rad2deg(theta_hat(mask) - theta_true(mask));
m = struct();
m.([prefix '_mae_deg']) = mean(abs(err_deg), 'omitnan');
m.([prefix '_rmse_deg']) = sqrt(mean(err_deg.^2, 'omitnan'));
m.([prefix '_p95_abs_err_deg']) = prctile(abs(err_deg), 95);
m.([prefix '_bias_deg']) = mean(err_deg, 'omitnan');
m.([prefix '_n']) = sum(mask);
end

function cm = local_confusion_matrix(truth, pred, labels)
cm = zeros(numel(labels), numel(labels));
for i = 1:numel(truth)
    r = find(labels == truth(i), 1);
    c = find(labels == pred(i), 1);
    if ~isempty(r) && ~isempty(c)
        cm(r, c) = cm(r, c) + 1;
    end
end
end

function acc = local_masked_acc(pred, truth, mask)
if ~any(mask)
    acc = NaN;
else
    acc = mean(pred(mask) == truth(mask));
end
end

function v = local_slope_sub_recall(pred_main, idx)
if isempty(idx)
    v = NaN;
else
    v = mean(pred_main(idx) == 3);
end
end

function row = local_empty_row()
row = struct('model', "ModernTCN-small v1 MATLAB", 'seed', NaN, 'best_epoch', NaN, ...
    'n_windows', NaN, 'elapsed_seconds', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'theta_abs_le_8_mae_deg', NaN, 'theta_abs_le_8_rmse_deg', NaN, ...
    'theta_abs_le_8_p95_abs_err_deg', NaN, 'theta_abs_le_8_bias_deg', NaN, ...
    'theta_abs_le_10_mae_deg', NaN, 'theta_abs_le_10_rmse_deg', NaN, ...
    'theta_abs_le_10_p95_abs_err_deg', NaN, 'theta_abs_le_10_bias_deg', NaN, ...
    'theta_pos_8_10_mae_deg', NaN, 'theta_pos_8_10_rmse_deg', NaN, ...
    'theta_pos_8_10_p95_abs_err_deg', NaN, 'theta_pos_8_10_bias_deg', NaN, ...
    'theta_pos_8_10_n', NaN, ...
    'theta_neg_10_8_mae_deg', NaN, 'theta_neg_10_8_rmse_deg', NaN, ...
    'theta_neg_10_8_p95_abs_err_deg', NaN, 'theta_neg_10_8_bias_deg', NaN, ...
    'theta_neg_10_8_n', NaN, ...
    'theta_pos_6_8_mae_deg', NaN, 'theta_pos_6_8_rmse_deg', NaN, ...
    'theta_pos_6_8_p95_abs_err_deg', NaN, 'theta_pos_6_8_bias_deg', NaN, ...
    'theta_pos_6_8_n', NaN, ...
    'theta_neg_8_6_mae_deg', NaN, 'theta_neg_8_6_rmse_deg', NaN, ...
    'theta_neg_8_6_p95_abs_err_deg', NaN, 'theta_neg_8_6_bias_deg', NaN, ...
    'theta_neg_8_6_n', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'onnx_file', "");
end

function row = local_row_from_metrics(seed, metrics, elapsed, onnx_file, cfg)
row = local_empty_row();
row.seed = seed;
row.n_windows = NaN; % 下方由 cfg/report 记录完整或 smoke 模式，指标表保持简洁。
row.elapsed_seconds = elapsed;
row.acc_main = metrics.acc_main;
row.acc_turn = metrics.acc_turn;
row.acc_turn_pure = metrics.acc_turn_pure;
row.acc_turn_transition = metrics.acc_turn_transition;
row.theta_mae_deg = metrics.theta_mae_deg;
row.theta_abs_le_8_mae_deg = metrics.theta_abs_le_8_mae_deg;
row.theta_abs_le_8_rmse_deg = metrics.theta_abs_le_8_rmse_deg;
row.theta_abs_le_8_p95_abs_err_deg = metrics.theta_abs_le_8_p95_abs_err_deg;
row.theta_abs_le_8_bias_deg = metrics.theta_abs_le_8_bias_deg;
row.theta_abs_le_10_mae_deg = metrics.theta_abs_le_10_mae_deg;
row.theta_abs_le_10_rmse_deg = metrics.theta_abs_le_10_rmse_deg;
row.theta_abs_le_10_p95_abs_err_deg = metrics.theta_abs_le_10_p95_abs_err_deg;
row.theta_abs_le_10_bias_deg = metrics.theta_abs_le_10_bias_deg;
row.theta_pos_8_10_mae_deg = metrics.theta_pos_8_10_mae_deg;
row.theta_pos_8_10_rmse_deg = metrics.theta_pos_8_10_rmse_deg;
row.theta_pos_8_10_p95_abs_err_deg = metrics.theta_pos_8_10_p95_abs_err_deg;
row.theta_pos_8_10_bias_deg = metrics.theta_pos_8_10_bias_deg;
row.theta_pos_8_10_n = metrics.theta_pos_8_10_n;
row.theta_neg_10_8_mae_deg = metrics.theta_neg_10_8_mae_deg;
row.theta_neg_10_8_rmse_deg = metrics.theta_neg_10_8_rmse_deg;
row.theta_neg_10_8_p95_abs_err_deg = metrics.theta_neg_10_8_p95_abs_err_deg;
row.theta_neg_10_8_bias_deg = metrics.theta_neg_10_8_bias_deg;
row.theta_neg_10_8_n = metrics.theta_neg_10_8_n;
row.theta_pos_6_8_mae_deg = metrics.theta_pos_6_8_mae_deg;
row.theta_pos_6_8_rmse_deg = metrics.theta_pos_6_8_rmse_deg;
row.theta_pos_6_8_p95_abs_err_deg = metrics.theta_pos_6_8_p95_abs_err_deg;
row.theta_pos_6_8_bias_deg = metrics.theta_pos_6_8_bias_deg;
row.theta_pos_6_8_n = metrics.theta_pos_6_8_n;
row.theta_neg_8_6_mae_deg = metrics.theta_neg_8_6_mae_deg;
row.theta_neg_8_6_rmse_deg = metrics.theta_neg_8_6_rmse_deg;
row.theta_neg_8_6_p95_abs_err_deg = metrics.theta_neg_8_6_p95_abs_err_deg;
row.theta_neg_8_6_bias_deg = metrics.theta_neg_8_6_bias_deg;
row.theta_neg_8_6_n = metrics.theta_neg_8_6_n;
row.flat_recall = metrics.flat_recall;
row.stall_recall = metrics.stall_recall;
row.slope_recall = metrics.slope_recall;
row.uphill_recall = metrics.uphill_recall;
row.downhill_recall = metrics.downhill_recall;
row.onnx_file = string(onnx_file);

py_summary = local_try_read_python_summary(seed, cfg);
if ~isempty(py_summary)
    row.best_epoch = py_summary.best_epoch;
end
end

function py = local_try_read_python_summary(seed, cfg)
py = [];
try
    root = project_root();
    py = local_read_python_summary(root, seed, cfg);
catch
end
end

function py = local_read_python_summary(root, seed, cfg)
if isfield(cfg, 'run_tag') && local_has_text(cfg.run_tag)
    summary_file = fullfile(root, 'results', 'modern_tcn', char(cfg.run_tag), ...
        sprintf('modern_tcn_seed%d_summary.csv', seed));
else
    summary_file = fullfile(root, 'results', 'modern_tcn', sprintf('modern_tcn_v4_industrial_seed%d', seed), ...
        sprintf('modern_tcn_seed%d_summary.csv', seed));
end

if exist(summary_file, 'file') ~= 2
    error('ModernTCN:MissingPythonSummary', '缺少 Python summary: %s', summary_file);
end
T = readtable(summary_file, TextType="string");
py = struct();
names = T.Properties.VariableNames;
for i = 1:numel(names)
    name = names{i};
    py.(name) = T.(name)(1);
end
end

function tf = local_has_text(v)
tf = ~isempty(v) && strlength(string(v)) > 0;
end

function row = local_empty_diff_row()
row = struct('seed', NaN, 'metric', "", 'matlab_value', NaN, ...
    'python_value', NaN, 'abs_error', NaN, 'pass', false);
end

function row = local_diff_row(seed, metric_name, matlab_value, python_value, tol)
row = local_empty_diff_row();
row.seed = seed;
row.metric = string(metric_name);
row.matlab_value = matlab_value;
row.python_value = python_value;
row.abs_error = abs(matlab_value - python_value);
row.pass = row.abs_error <= tol;
end

function T_summary = local_summary_table(T, metric_names)
rows = repmat(struct('metric', "", 'mean', NaN, 'std', NaN, 'min', NaN, 'max', NaN), numel(metric_names), 1);
for i = 1:numel(metric_names)
    name = metric_names{i};
    vals = T.(name);
    rows(i).metric = string(name);
    rows(i).mean = mean(vals, 'omitnan');
    rows(i).std = std(vals, 'omitnan');
    rows(i).min = min(vals);
    rows(i).max = max(vals);
end
T_summary = struct2table(rows);
end

function local_save_seed_outputs(cfg, seed, pred, metrics, elapsed, onnx_file)
out_file = fullfile(cfg.output_dir, sprintf('modern_tcn_seed%d_matlab_full_testset_outputs.mat', seed));
save(out_file, 'pred', 'metrics', 'elapsed', 'onnx_file', '-v7.3');
end

function pass = local_overall_pass(T_diff, cfg)
if cfg.max_windows > 0
    pass = true;
elseif isempty(T_diff)
    pass = false;
else
    pass = all(T_diff.pass);
end
end

function local_write_report(report_file, cfg, dataset_file, T, T_summary, T_diff)
fid = fopen(report_file, 'w');
if fid < 0
    error('ModernTCN:ReportFailed', '无法写入报告: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN v1 MATLAB Full Test Set Evaluation\n\n');
fprintf(fid, '- Dataset: `%s`\n', dataset_file);
if cfg.max_windows > 0
    fprintf(fid, '- Mode: smoke test, first %d test windows only.\n', cfg.max_windows);
else
    fprintf(fid, '- Mode: full X_test.\n');
end
fprintf(fid, '- Metric diff tolerance vs Python summary: %.1e\n\n', cfg.metric_abs_tol);

fprintf(fid, '## Per-Seed MATLAB Metrics\n\n');
fprintf(fid, '| seed | main | turn | turnT | theta deg | flat | stall | slope | uphill | downhill | seconds |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.1f |\n', ...
        T.seed(i), T.acc_main(i), T.acc_turn(i), T.acc_turn_transition(i), ...
        T.theta_mae_deg(i), T.flat_recall(i), T.stall_recall(i), ...
        T.slope_recall(i), T.uphill_recall(i), T.downhill_recall(i), ...
        T.elapsed_seconds(i));
end

fprintf(fid, '\n## MATLAB Summary Across Requested Seeds\n\n');
fprintf(fid, '| metric | mean | std | min | max |\n');
fprintf(fid, '|---|---:|---:|---:|---:|\n');
for i = 1:height(T_summary)
    fprintf(fid, '| %s | %.4f | %.4f | %.4f | %.4f |\n', ...
        T_summary.metric(i), T_summary.mean(i), T_summary.std(i), ...
        T_summary.min(i), T_summary.max(i));
end

if ~isempty(T_diff)
    fprintf(fid, '\n## MATLAB vs Python Summary Diff\n\n');
    fprintf(fid, '| seed | metric | MATLAB | Python | abs error | pass |\n');
    fprintf(fid, '|---:|---|---:|---:|---:|---:|\n');
    for i = 1:height(T_diff)
        fprintf(fid, '| %d | %s | %.8f | %.8f | %.3g | %d |\n', ...
            T_diff.seed(i), T_diff.metric(i), T_diff.matlab_value(i), ...
            T_diff.python_value(i), T_diff.abs_error(i), T_diff.pass(i));
    end
else
    fprintf(fid, '\n## MATLAB vs Python Summary Diff\n\n');
    fprintf(fid, 'Smoke mode does not compare metrics with full Python summary.\n');
end

fprintf(fid, '\n## Decision\n\n');
if cfg.max_windows > 0
    fprintf(fid, 'This is a smoke test only. Run `ModernTCN_matlab_full_testset_eval()` for the full decision.\n');
elseif local_overall_pass(T_diff, cfg)
    fprintf(fid, 'MATLAB full test set metrics match Python summary within tolerance. The offline MATLAB inference path is ready for MATLAB wrapper design.\n');
else
    fprintf(fid, 'MATLAB full test set metrics do not match Python summary. Inspect the diff table before moving to Simulink.\n');
end
end
