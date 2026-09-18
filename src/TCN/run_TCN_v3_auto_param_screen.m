function summary = run_TCN_v3_auto_param_screen(screen_cfg)
%RUN_TCN_V3_AUTO_PARAM_SCREEN 自动化筛选 V3 TCN baseline 校准参数。
%
% 目标：
%   固定 TCN_dataset_v3_transition_rich.mat，不再改路径/数据集；
%   用阶段化流程筛选 TCN baseline 的主工况/theta/转弯折中参数。
%
% 推荐流程：
%   init_project;
%   run_TCN_v3_auto_param_screen(struct('stage','probe'));
%   run_TCN_v3_auto_param_screen(struct('stage','confirm'));
%   run_TCN_v3_auto_param_screen(struct('stage','validate'));
%   run_TCN_v3_auto_param_screen(struct('stage','full'));
%
% 阶段：
%   probe    : seed42 短训练筛配置，只看 main/theta 潜力。
%   confirm  : 自动选 probe 前 top_k 个配置，用 seeds [42 101] 完整训练。
%   validate : 自动选 confirm 最优配置，用 seed73 验证。
%   full     : 自动选 validate/confirm 最优配置，用五个 seeds 完整训练。

if nargin < 1 || ~isstruct(screen_cfg)
    screen_cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
stage = lower(string(local_cfg(screen_cfg, 'stage', 'probe')));
force = logical(local_cfg(screen_cfg, 'force', false));
do_train = logical(local_cfg(screen_cfg, 'do_train', true));
top_k = local_cfg(screen_cfg, 'top_k', 2);

dataset_file = local_cfg(screen_cfg, 'dataset_file', ...
    fullfile(root, 'data', 'tcn', 'TCN_dataset_v3_transition_rich.mat'));
out_root = local_cfg(screen_cfg, 'out_root', ...
    results_dir(fullfile('tcn', 'experiments', 'transition_rich_v3_auto_screen')));
if ~exist(out_root, 'dir')
    mkdir(out_root);
end

all_candidates = local_candidate_set();
[candidates, seeds, probe_mode] = local_stage_plan(stage, screen_cfg, all_candidates, out_root, top_k);

rows = repmat(local_empty_row(), numel(candidates) * numel(seeds), 1);
ri = 0;
for ci = 1:numel(candidates)
    cand = candidates(ci);
    for si = 1:numel(seeds)
        seed = seeds(si);
        cfg = TCN_recommended_cfg('production_current');
        cfg = local_apply_candidate(cfg, cand, probe_mode, screen_cfg);
        cfg.seed = seed;
        cfg.verbose = logical(local_cfg(screen_cfg, 'verbose_train', false));
        cfg.input_file = dataset_file;

        run_tag = sprintf('transition_rich_v3_auto_%s_%s_seed%d', stage, cand.name, seed);
        cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', run_tag));
        cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', run_tag));
        cfg.log_dir = fullfile(out_root, char(stage), cand.name, sprintf('seed%d', seed));
        cfg.report_file = fullfile(cfg.log_dir, 'TCN_train_report.md');

        if exist(cfg.meta_file, 'file') == 2 && ~force
            meta = local_load_meta(cfg.meta_file);
            status = "loaded";
        elseif do_train
            [~, meta] = TCN_train(cfg);
            status = "trained";
        else
            error('run_TCN_v3_auto_param_screen:MissingMeta', ...
                'Meta file not found and do_train=false: %s', cfg.meta_file);
        end

        ri = ri + 1;
        rows(ri) = local_row_from_meta(stage, cand.name, seed, meta, cfg, status, probe_mode);
        fprintf('[auto-screen:%s] %-22s seed=%d %s | score=%.4f pass=%d main=%.4f flat=%.4f slope=%.4f turnT=%.4f theta=%.4f\n', ...
            stage, cand.name, seed, status, rows(ri).score, rows(ri).pass, ...
            rows(ri).acc_main, rows(ri).flat_recall, rows(ri).slope_recall, ...
            rows(ri).acc_turn_transition, rows(ri).theta_mae_deg);

        local_release_gpu();
    end
end

T = struct2table(rows);
summary = struct();
summary.stage = stage;
summary.dataset_file = dataset_file;
summary.table = T;
summary.csv_file = fullfile(out_root, sprintf('TCN_v3_auto_%s_summary.csv', stage));
summary.report_file = fullfile(out_root, sprintf('TCN_v3_auto_%s_summary.md', stage));
writetable(T, summary.csv_file);
local_write_md(summary.report_file, summary);

fprintf('[auto-screen:%s] summary: %s\n', stage, summary.csv_file);
disp(T);
end

function [candidates, seeds, probe_mode] = local_stage_plan(stage, screen_cfg, all_candidates, out_root, top_k)
switch char(stage)
    case 'probe'
        candidates = local_filter_candidates(all_candidates, local_cfg(screen_cfg, 'configs', {}));
        seeds = local_cfg(screen_cfg, 'seeds', 42);
        probe_mode = true;
    case 'confirm'
        names = local_cfg(screen_cfg, 'configs', {});
        if isempty(names)
            names = local_select_candidate_names(fullfile(out_root, 'TCN_v3_auto_probe_summary.csv'), top_k);
        end
        candidates = local_filter_candidates(all_candidates, names);
        seeds = local_cfg(screen_cfg, 'seeds', [42 101]);
        probe_mode = false;
    case 'validate'
        names = local_cfg(screen_cfg, 'configs', {});
        if isempty(names)
            names = local_select_candidate_names(fullfile(out_root, 'TCN_v3_auto_confirm_summary.csv'), 1);
        end
        candidates = local_filter_candidates(all_candidates, names);
        seeds = local_cfg(screen_cfg, 'seeds', 73);
        probe_mode = false;
    case 'full'
        names = local_cfg(screen_cfg, 'configs', {});
        if isempty(names)
            validate_csv = fullfile(out_root, 'TCN_v3_auto_validate_summary.csv');
            confirm_csv = fullfile(out_root, 'TCN_v3_auto_confirm_summary.csv');
            if exist(validate_csv, 'file') == 2
                names = local_select_candidate_names(validate_csv, 1);
            else
                names = local_select_candidate_names(confirm_csv, 1);
            end
        end
        candidates = local_filter_candidates(all_candidates, names);
        seeds = local_cfg(screen_cfg, 'seeds', [11 21 42 73 101]);
        probe_mode = false;
    otherwise
        error('run_TCN_v3_auto_param_screen:BadStage', 'Unknown stage: %s', stage);
end
end

function candidates = local_candidate_set()
candidates = repmat(local_candidate_template(), 5, 1);
candidates(1) = local_candidate('sqrt_mild_ref', 'main_guard', [1.15 1.00 0.95], 2.0, 0.15, 5.0, 0.45);
candidates(2) = local_candidate('base_comp_t025', 'composite', [1.15 1.00 0.95], 2.0, 0.25, 3.0, 0.80);
candidates(3) = local_candidate('base_comp_t035', 'composite', [1.15 1.00 0.95], 2.0, 0.35, 3.0, 0.90);
candidates(4) = local_candidate('base_comp_t060', 'composite', [1.15 1.00 0.95], 2.0, 0.60, 3.0, 1.10);
candidates(5) = local_candidate('base_comp_flat120', 'composite', [1.20 1.00 0.95], 2.0, 0.35, 3.0, 0.95);
end

function c = local_candidate_template()
c = struct('name', '', 'base_best_metric', 'composite', ...
    'main_class_multipliers', [1.0 1.0 1.0], ...
    'main_neg_slope_weight', 2.0, ...
    'select_theta_weight', 0.15, ...
    'select_theta_ref_deg', 5.0, ...
    'select_main_error_weight', 0.45);
end

function c = local_candidate(name, base_metric, main_mult, neg_weight, theta_weight, theta_ref, main_weight)
c = local_candidate_template();
c.name = name;
c.base_best_metric = base_metric;
c.main_class_multipliers = main_mult;
c.main_neg_slope_weight = neg_weight;
c.select_theta_weight = theta_weight;
c.select_theta_ref_deg = theta_ref;
c.select_main_error_weight = main_weight;
end

function cfg = local_apply_candidate(cfg, cand, probe_mode, screen_cfg)
cfg.class_weight_method = 'sqrt_inverse';
cfg.main_class_multipliers = cand.main_class_multipliers;
cfg.main_neg_slope_weight = cand.main_neg_slope_weight;
cfg.main_pos_slope_weight = 1.0;
cfg.theta_neg_weight = 2.0;
cfg.lambda_theta = 0.35;
cfg.lambda_theta_flat = 0.20;

cfg.base_best_metric = cand.base_best_metric;
cfg.combine_base_and_turn_best = true;
cfg.best_metric = 'turn_priority';
cfg.select_main_error_weight = cand.select_main_error_weight;
cfg.select_turn_error_weight = 0.15;
cfg.select_theta_weight = cand.select_theta_weight;
cfg.select_theta_ref_deg = cand.select_theta_ref_deg;
cfg.select_downhill_error_weight = 0.25;
cfg.select_main_floor = 0.93;
cfg.select_theta_floor_deg = 1.20;
cfg.turn_priority_main_penalty_weight = 35.0;
cfg.turn_priority_theta_penalty_weight = 0.25;

if probe_mode
    cfg.max_epochs = local_cfg(screen_cfg, 'probe_max_epochs', 45);
    cfg.turn_finetune_start_epoch = inf;
    cfg.combine_base_and_turn_best = false;
    cfg.best_metric = 'composite';
    cfg.base_best_metric = 'composite';
    cfg.selection_start_epoch = local_cfg(screen_cfg, 'probe_selection_start_epoch', 15);
    cfg.early_stop_min_epochs = local_cfg(screen_cfg, 'probe_early_stop_min_epochs', 30);
    cfg.patience = local_cfg(screen_cfg, 'probe_patience', 6);
end
end

function candidates = local_filter_candidates(all_candidates, names)
if isempty(names)
    candidates = all_candidates;
    return;
end
if ischar(names) || isstring(names)
    names = cellstr(names);
end
keep = false(numel(all_candidates), 1);
for i = 1:numel(all_candidates)
    keep(i) = any(strcmpi(all_candidates(i).name, names));
end
missing = setdiff(string(names), string({all_candidates.name}));
if ~isempty(missing)
    error('run_TCN_v3_auto_param_screen:BadConfig', ...
        'Unknown config(s): %s', strjoin(missing, ', '));
end
candidates = all_candidates(keep);
end

function names = local_select_candidate_names(csv_file, top_k)
if exist(csv_file, 'file') ~= 2
    error('run_TCN_v3_auto_param_screen:MissingSummary', ...
        'Summary not found. Run previous stage first: %s', csv_file);
end
T = readtable(csv_file, 'TextType', 'string');
configs = unique(T.config, 'stable');
score = zeros(numel(configs), 1);
all_pass = false(numel(configs), 1);
for i = 1:numel(configs)
    m = T.config == configs(i);
    score(i) = mean(T.score(m), 'omitnan');
    all_pass(i) = all(T.pass(m) ~= 0);
end
eligible = all_pass;
if ~any(eligible)
    eligible = true(size(configs));
end
idx = find(eligible);
[~, order] = sort(score(idx), 'ascend');
idx = idx(order);
idx = idx(1:min(top_k, numel(idx)));
names = cellstr(configs(idx));
fprintf('[auto-screen] selected from %s: %s\n', csv_file, strjoin(string(names), ', '));
end

function row = local_empty_row()
row = struct('stage', "", 'config', "", 'seed', NaN, 'status', "", ...
    'probe_mode', false, 'best_epoch', NaN, 'base_best_epoch', NaN, ...
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

function row = local_row_from_meta(stage, config_name, seed, meta, cfg, status, probe_mode)
m = meta.test_metrics;
row = local_empty_row();
row.stage = stage;
row.config = string(config_name);
row.seed = seed;
row.status = status;
row.probe_mode = probe_mode;
row.best_epoch = meta.best_epoch;
if isfield(meta, 'base_best_epoch')
    row.base_best_epoch = meta.base_best_epoch;
end
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
row.score = local_screen_score(row, probe_mode);
row.pass = local_screen_pass(row, probe_mode);
end

function score = local_screen_score(row, probe_mode)
theta_term = min(row.theta_mae_deg, 2.0) / 2.0;
score = 3.0 * (1 - row.acc_main) ...
    + 1.4 * theta_term ...
    + 4.0 * max(0, 0.90 - row.flat_recall) ...
    + 3.0 * max(0, 0.90 - row.slope_recall) ...
    + 1.0 * max(0, 0.90 - row.uphill_recall) ...
    + 1.0 * max(0, 0.90 - row.downhill_recall);
if ~probe_mode
    score = score ...
        + 1.5 * max(0, 0.75 - row.acc_turn_transition) ...
        + 0.4 * (1 - row.acc_turn);
end
end

function pass = local_screen_pass(row, probe_mode)
if probe_mode
    pass = row.acc_main >= 0.86 ...
        && row.flat_recall >= 0.88 ...
        && row.slope_recall >= 0.82 ...
        && row.theta_mae_deg <= 0.95;
else
    pass = row.acc_main >= 0.90 ...
        && row.flat_recall >= 0.90 ...
        && row.slope_recall >= 0.88 ...
        && row.acc_turn_transition >= 0.75 ...
        && row.theta_mae_deg <= 0.70;
end
end

function meta = local_load_meta(meta_file)
S = load(meta_file, 'meta');
meta = S.meta;
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function local_release_gpu()
close all;
if gpuDeviceCount > 0
    reset(gpuDevice);
end
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function local_write_md(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('run_TCN_v3_auto_param_screen:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = summary.table;
fprintf(fid, '# TCN v3 Auto Parameter Screen - %s\n\n', summary.stage);
fprintf(fid, '- dataset: `%s`\n', summary.dataset_file);
fprintf(fid, '- csv: `%s`\n\n', summary.csv_file);
fprintf(fid, '| config | seed | status | score | pass | main | flat | slope | turnT | theta |\n');
fprintf(fid, '|---|---:|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %d | %s | %.4f | %d | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.config(i), T.seed(i), T.status(i), T.score(i), T.pass(i), ...
        T.acc_main(i), T.flat_recall(i), T.slope_recall(i), ...
        T.acc_turn_transition(i), T.theta_mae_deg(i));
end
end
