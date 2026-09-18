function summary = run_TCN_v3_guarded_base_full(seeds, force)
%RUN_TCN_V3_GUARDED_BASE_FULL 复跑 V3 TCN baseline，保护主任务基座选模。
%
% 该入口固定使用 V3 数据集和 auto screen 中表现最好的 base_comp_flat120
% 参数，但新增 base_selection_start_epoch=45，避免第 8-13 轮这类过早
% checkpoint 被 combine_base_and_turn_best 锁定为主任务基座。
%
% 示例：
%   init_project;
%   run_TCN_v3_guarded_base_full();
%   run_TCN_v3_guarded_base_full([42 73 101], true);  % 强制重训

if nargin < 1 || isempty(seeds)
    seeds = [11 21 42 73 101];
end
if nargin < 2
    force = false;
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
dataset_file = fullfile(root, 'data', 'tcn', 'TCN_dataset_v3_transition_rich.mat');
out_root = results_dir(fullfile('tcn', 'experiments', 'transition_rich_v3_guarded_base'));
if ~exist(out_root, 'dir')
    mkdir(out_root);
end

rows = repmat(local_empty_row(), numel(seeds), 1);
for i = 1:numel(seeds)
    seed = seeds(i);
    cfg = TCN_recommended_cfg('production_current');
    cfg = local_apply_guarded_flat120(cfg);
    cfg.seed = seed;
    cfg.verbose = false;
    cfg.input_file = dataset_file;

    run_tag = sprintf('transition_rich_v3_guarded_base_comp_flat120_seed%d', seed);
    cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', run_tag));
    cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', run_tag));
    cfg.log_dir = fullfile(out_root, 'base_comp_flat120_guard45', sprintf('seed%d', seed));
    cfg.report_file = fullfile(cfg.log_dir, 'TCN_train_report.md');

    if exist(cfg.meta_file, 'file') == 2 && ~force
        meta = local_load_meta(cfg.meta_file);
        status = "loaded";
    else
        [~, meta] = TCN_train(cfg);
        status = "trained";
    end

    rows(i) = local_row_from_meta(seed, meta, cfg, status);
    fprintf(['[TCN v3 guarded] seed=%d %s | score=%.4f pass=%d ' ...
        'main=%.4f flat=%.4f slope=%.4f turnT=%.4f theta=%.4f base_epoch=%d\n'], ...
        seed, status, rows(i).score, rows(i).pass, rows(i).acc_main, ...
        rows(i).flat_recall, rows(i).slope_recall, rows(i).acc_turn_transition, ...
        rows(i).theta_mae_deg, rows(i).base_best_epoch);

    local_release_gpu();
end

T = struct2table(rows);
summary = struct();
summary.dataset_file = dataset_file;
summary.table = T;
summary.csv_file = fullfile(out_root, 'TCN_v3_guarded_base_full_summary.csv');
summary.report_file = fullfile(out_root, 'TCN_v3_guarded_base_full_summary.md');
writetable(T, summary.csv_file);
local_write_md(summary.report_file, summary);

fprintf('[TCN v3 guarded] summary: %s\n', summary.csv_file);
disp(T);
end

function cfg = local_apply_guarded_flat120(cfg)
cfg.class_weight_method = 'sqrt_inverse';
cfg.main_class_multipliers = [1.20 1.00 0.95];
cfg.main_neg_slope_weight = 2.0;
cfg.main_pos_slope_weight = 1.0;
cfg.theta_neg_weight = 2.0;
cfg.lambda_theta = 0.35;
cfg.lambda_theta_flat = 0.20;

cfg.base_best_metric = 'composite';
cfg.combine_base_and_turn_best = true;
cfg.best_metric = 'turn_priority';
cfg.base_selection_start_epoch = 45;
cfg.selection_start_epoch = 64;
cfg.early_stop_min_epochs = 75;

cfg.select_main_error_weight = 0.95;
cfg.select_turn_error_weight = 0.15;
cfg.select_theta_weight = 0.35;
cfg.select_theta_ref_deg = 3.0;
cfg.select_downhill_error_weight = 0.25;
cfg.select_main_floor = 0.93;
cfg.select_theta_floor_deg = 1.20;
cfg.turn_priority_main_penalty_weight = 35.0;
cfg.turn_priority_theta_penalty_weight = 0.25;
end

function row = local_empty_row()
row = struct('config', "base_comp_flat120_guard45", 'seed', NaN, 'status', "", ...
    'best_epoch', NaN, 'base_best_epoch', NaN, 'base_selection_start_epoch', NaN, ...
    'score', NaN, 'pass', false, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'base_best_metric', "", 'best_metric', "", ...
    'select_theta_weight', NaN, 'select_theta_ref_deg', NaN, ...
    'select_main_error_weight', NaN, 'main_class_multipliers', "", ...
    'main_neg_slope_weight', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(seed, meta, cfg, status)
m = meta.test_metrics;
row = local_empty_row();
row.seed = seed;
row.status = status;
row.best_epoch = meta.best_epoch;
if isfield(meta, 'base_best_epoch')
    row.base_best_epoch = meta.base_best_epoch;
end
row.base_selection_start_epoch = cfg.base_selection_start_epoch;
row.acc_main = m.acc_main;
row.acc_turn = m.acc_turn;
row.acc_turn_pure = local_metric(m, 'acc_turn_pure');
row.acc_turn_transition = local_metric(m, 'acc_turn_transition');
row.theta_mae_deg = rad2deg(m.mae_theta);
row.flat_recall = m.recall_main(1);
row.stall_recall = m.recall_main(2);
row.slope_recall = m.recall_main(3);
row.uphill_recall = m.uphill.slope_recall;
row.downhill_recall = m.downhill.slope_recall;
row.base_best_metric = string(cfg.base_best_metric);
row.best_metric = string(cfg.best_metric);
row.select_theta_weight = cfg.select_theta_weight;
row.select_theta_ref_deg = cfg.select_theta_ref_deg;
row.select_main_error_weight = cfg.select_main_error_weight;
row.main_class_multipliers = sprintf('[%.2f %.2f %.2f]', cfg.main_class_multipliers);
row.main_neg_slope_weight = cfg.main_neg_slope_weight;
row.model_file = string(cfg.model_file);
row.meta_file = string(cfg.meta_file);
row.report_file = string(cfg.report_file);
row.score = local_screen_score(row);
row.pass = local_screen_pass(row);
end

function score = local_screen_score(row)
theta_term = min(row.theta_mae_deg, 2.0) / 2.0;
score = 3.0 * (1 - row.acc_main) ...
    + 1.4 * theta_term ...
    + 4.0 * max(0, 0.90 - row.flat_recall) ...
    + 3.0 * max(0, 0.90 - row.slope_recall) ...
    + 1.0 * max(0, 0.90 - row.uphill_recall) ...
    + 1.0 * max(0, 0.90 - row.downhill_recall) ...
    + 1.5 * max(0, 0.75 - row.acc_turn_transition) ...
    + 0.4 * (1 - row.acc_turn);
end

function pass = local_screen_pass(row)
pass = row.acc_main >= 0.90 ...
    && row.flat_recall >= 0.90 ...
    && row.slope_recall >= 0.88 ...
    && row.acc_turn_transition >= 0.75 ...
    && row.theta_mae_deg <= 0.70;
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function meta = local_load_meta(meta_file)
S = load(meta_file, 'meta');
meta = S.meta;
end

function local_release_gpu()
close all;
if gpuDeviceCount > 0
    reset(gpuDevice);
end
end

function local_write_md(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('run_TCN_v3_guarded_base_full:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = summary.table;
fprintf(fid, '# TCN v3 Guarded Base Full Summary\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.dataset_file);
fprintf(fid, '- csv: `%s`\n\n', summary.csv_file);
fprintf(fid, '| seed | status | score | pass | base epoch | main | flat | slope | turnT | theta |\n');
fprintf(fid, '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %d | %s | %.4f | %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.seed(i), T.status(i), T.score(i), T.pass(i), T.base_best_epoch(i), ...
        T.acc_main(i), T.flat_recall(i), T.slope_recall(i), ...
        T.acc_turn_transition(i), T.theta_mae_deg(i));
end
end
