function summary = run_TCN_v3_selection_stability_screen(seeds, config_names, force)
%RUN_TCN_V3_SELECTION_STABILITY_SCREEN 筛选 V3 TCN base 选模稳定性。
%
% 目标：
%   固定 TCN_dataset_v3_transition_rich.mat；
%   不改路径/数据；
%   不继续 guard45；
%   比较 base_comp_flat120 在不同 base_best_metric 下是否能稳定保住
%   flat/slope/theta/turn-transition 折中。
%
% 推荐先跑：
%   init_project;
%   run_TCN_v3_selection_stability_screen(42);
%
% 若 seed42 有候选通过，再跑：
%   run_TCN_v3_selection_stability_screen([42 73 101], {'候选名'});

if nargin < 1 || isempty(seeds)
    seeds = 42;
end
if nargin < 2
    config_names = {};
end
if nargin < 3
    force = false;
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
dataset_file = fullfile(root, 'data', 'tcn', 'TCN_dataset_v3_transition_rich.mat');
out_root = results_dir(fullfile('tcn', 'experiments', 'transition_rich_v3_selection_stability'));
if ~exist(out_root, 'dir')
    mkdir(out_root);
end

candidates = local_filter_candidates(local_candidate_set(), config_names);
rows = repmat(local_empty_row(), numel(candidates) * numel(seeds), 1);
ri = 0;
for ci = 1:numel(candidates)
    cand = candidates(ci);
    for si = 1:numel(seeds)
        seed = seeds(si);
        cfg = TCN_recommended_cfg('production_current');
        cfg = local_apply_candidate(cfg, cand);
        cfg.seed = seed;
        cfg.verbose = false;
        cfg.input_file = dataset_file;

        run_tag = sprintf('transition_rich_v3_select_stability_%s_seed%d', cand.name, seed);
        cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', run_tag));
        cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', run_tag));
        cfg.log_dir = fullfile(out_root, cand.name, sprintf('seed%d', seed));
        cfg.report_file = fullfile(cfg.log_dir, 'TCN_train_report.md');

        if exist(cfg.meta_file, 'file') == 2 && ~force
            meta = local_load_meta(cfg.meta_file);
            status = "loaded";
        else
            [~, meta] = TCN_train(cfg);
            status = "trained";
        end

        ri = ri + 1;
        rows(ri) = local_row_from_meta(cand.name, seed, meta, cfg, status);
        fprintf(['[TCN v3 select-stability] %-28s seed=%d %s | score=%.4f pass=%d ' ...
            'main=%.4f flat=%.4f slope=%.4f turnT=%.4f theta=%.4f base_epoch=%d\n'], ...
            cand.name, seed, status, rows(ri).score, rows(ri).pass, ...
            rows(ri).acc_main, rows(ri).flat_recall, rows(ri).slope_recall, ...
            rows(ri).acc_turn_transition, rows(ri).theta_mae_deg, rows(ri).base_best_epoch);

        local_release_gpu();
    end
end

T = struct2table(rows);
summary = struct();
summary.dataset_file = dataset_file;
summary.table = T;
summary.csv_file = fullfile(out_root, 'TCN_v3_selection_stability_summary.csv');
summary.report_file = fullfile(out_root, 'TCN_v3_selection_stability_summary.md');
writetable(T, summary.csv_file);
local_write_md(summary.report_file, summary);

fprintf('[TCN v3 select-stability] summary: %s\n', summary.csv_file);
disp(T);
end

function candidates = local_candidate_set()
candidates = repmat(local_candidate_template(), 5, 1);
candidates(1) = local_candidate('flat120_comp_ref', ...
    'composite', [1.20 1.00 0.95], 0.90, 0.90, 0.90, 3.0, 1.5, 3.0);
candidates(2) = local_candidate('flat120_base_main_guard', ...
    'main_guard', [1.20 1.00 0.95], 0.90, 0.90, 0.90, 3.0, 1.5, 3.0);
candidates(3) = local_candidate('flat120_comp_guard_s090', ...
    'composite_guarded', [1.20 1.00 0.95], 0.90, 0.90, 0.90, 3.0, 1.5, 3.0);
candidates(4) = local_candidate('flat115_comp_guard_s092', ...
    'composite_guarded', [1.15 1.00 0.95], 0.90, 0.90, 0.92, 3.0, 1.5, 4.0);
candidates(5) = local_candidate('flat110_slope100_guard', ...
    'composite_guarded', [1.10 1.00 1.00], 0.90, 0.90, 0.92, 3.0, 1.5, 4.0);
end

function c = local_candidate_template()
c = struct('name', '', 'base_best_metric', 'composite', ...
    'main_class_multipliers', [1.20 1.00 0.95], ...
    'guard_flat_floor', 0.90, ...
    'guard_stall_floor', 0.90, ...
    'guard_slope_floor', 0.90, ...
    'guard_flat_weight', 3.0, ...
    'guard_stall_weight', 1.5, ...
    'guard_slope_weight', 3.0);
end

function c = local_candidate(name, base_metric, main_mult, flat_floor, stall_floor, slope_floor, flat_w, stall_w, slope_w)
c = local_candidate_template();
c.name = name;
c.base_best_metric = base_metric;
c.main_class_multipliers = main_mult;
c.guard_flat_floor = flat_floor;
c.guard_stall_floor = stall_floor;
c.guard_slope_floor = slope_floor;
c.guard_flat_weight = flat_w;
c.guard_stall_weight = stall_w;
c.guard_slope_weight = slope_w;
end

function cfg = local_apply_candidate(cfg, cand)
cfg.class_weight_method = 'sqrt_inverse';
cfg.main_class_multipliers = cand.main_class_multipliers;
cfg.main_neg_slope_weight = 2.0;
cfg.main_pos_slope_weight = 1.0;
cfg.theta_neg_weight = 2.0;
cfg.lambda_theta = 0.35;
cfg.lambda_theta_flat = 0.20;

cfg.base_best_metric = cand.base_best_metric;
cfg.combine_base_and_turn_best = true;
cfg.best_metric = 'turn_priority';
cfg.base_selection_start_epoch = 1;
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

cfg.composite_guard_flat_floor = cand.guard_flat_floor;
cfg.composite_guard_stall_floor = cand.guard_stall_floor;
cfg.composite_guard_slope_floor = cand.guard_slope_floor;
cfg.composite_guard_flat_penalty_weight = cand.guard_flat_weight;
cfg.composite_guard_stall_penalty_weight = cand.guard_stall_weight;
cfg.composite_guard_slope_penalty_weight = cand.guard_slope_weight;

cfg.main_guard_flat_floor = cand.guard_flat_floor;
cfg.main_guard_stall_floor = cand.guard_stall_floor;
cfg.main_guard_slope_floor = cand.guard_slope_floor;
cfg.main_guard_flat_penalty_weight = cand.guard_flat_weight;
cfg.main_guard_stall_penalty_weight = cand.guard_stall_weight;
cfg.main_guard_slope_penalty_weight = cand.guard_slope_weight;
cfg.main_guard_acc_error_weight = 1.0;
cfg.main_guard_theta_weight = 0.10;
cfg.main_guard_turn_weight = 0.05;
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
    error('run_TCN_v3_selection_stability_screen:BadConfig', ...
        'Unknown config(s): %s', strjoin(missing, ', '));
end
candidates = all_candidates(keep);
end

function row = local_empty_row()
row = struct('config', "", 'seed', NaN, 'status', "", ...
    'best_epoch', NaN, 'base_best_epoch', NaN, 'score', NaN, 'pass', false, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'base_best_metric', "", 'best_metric', "", ...
    'main_class_multipliers', "", 'main_neg_slope_weight', NaN, ...
    'guard_flat_floor', NaN, 'guard_slope_floor', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(config_name, seed, meta, cfg, status)
m = meta.test_metrics;
row = local_empty_row();
row.config = string(config_name);
row.seed = seed;
row.status = status;
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
row.main_class_multipliers = sprintf('[%.2f %.2f %.2f]', cfg.main_class_multipliers);
row.main_neg_slope_weight = cfg.main_neg_slope_weight;
row.guard_flat_floor = cfg.composite_guard_flat_floor;
row.guard_slope_floor = cfg.composite_guard_slope_floor;
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
    warning('run_TCN_v3_selection_stability_screen:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = summary.table;
fprintf(fid, '# TCN v3 Selection Stability Summary\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.dataset_file);
fprintf(fid, '- csv: `%s`\n\n', summary.csv_file);
fprintf(fid, '| config | seed | status | score | pass | base epoch | main | flat | slope | turnT | theta |\n');
fprintf(fid, '|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %d | %s | %.4f | %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.config(i), T.seed(i), T.status(i), T.score(i), T.pass(i), ...
        T.base_best_epoch(i), T.acc_main(i), T.flat_recall(i), ...
        T.slope_recall(i), T.acc_turn_transition(i), T.theta_mae_deg(i));
end
end
