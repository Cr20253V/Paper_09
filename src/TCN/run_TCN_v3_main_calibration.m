function summary = run_TCN_v3_main_calibration(seeds, calib_names, do_train)
%RUN_TCN_V3_MAIN_CALIBRATION 在固定 V3 数据集上做 TCN 主工况校准。
%
% 该脚本只训练 TCN，不重训 GRU，不修改 V3 数据集。目标是修正
% transition-rich v3 中暴露出的 flat/slope 主工况边界问题。
%
% 示例：
%   init_project;
%   run_TCN_v3_main_calibration([42 101 73], {'sqrt_mild','flat_guard'}, true);

if nargin < 1 || isempty(seeds)
    seeds = [42 101 73];
end
if nargin < 2 || isempty(calib_names)
    calib_names = {'sqrt_mild', 'flat_guard', 'main_guard'};
end
if nargin < 3
    do_train = true;
end
if ischar(calib_names) || isstring(calib_names)
    calib_names = cellstr(calib_names);
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
dataset_file = fullfile(root, 'data', 'tcn', 'TCN_dataset_v3_transition_rich.mat');
out_root = results_dir(fullfile('tcn', 'experiments', 'transition_rich_v3_calibration'));
if ~exist(out_root, 'dir')
    mkdir(out_root);
end

rows = repmat(local_empty_row(), numel(seeds) * numel(calib_names), 1);
ri = 0;
for ci = 1:numel(calib_names)
    calib_name = char(calib_names{ci});
    for si = 1:numel(seeds)
        seed = seeds(si);
        cfg = TCN_recommended_cfg('production_current');
        cfg = local_apply_calibration(cfg, calib_name);
        cfg.seed = seed;
        cfg.verbose = false;
        cfg.input_file = dataset_file;

        run_tag = sprintf('transition_rich_v3_%s_seed%d', calib_name, seed);
        cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', run_tag));
        cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', run_tag));
        cfg.log_dir = fullfile(out_root, calib_name, sprintf('seed%d', seed));
        cfg.report_file = fullfile(cfg.log_dir, 'TCN_train_report.md');

        if do_train
            [~, meta] = TCN_train(cfg);
        else
            meta = local_load_meta(cfg.meta_file);
        end

        ri = ri + 1;
        rows(ri) = local_row_from_meta(calib_name, seed, meta, cfg);
        fprintf('[TCN v3 calibration] %s seed=%d done: main=%.4f turn=%.4f theta=%.4f slope=%.4f flat=%.4f\n', ...
            calib_name, seed, rows(ri).acc_main, rows(ri).acc_turn, ...
            rows(ri).theta_mae_deg, rows(ri).slope_recall, rows(ri).flat_recall);
    end
end

T = struct2table(rows);
summary = struct();
summary.dataset_file = dataset_file;
summary.table = T;
summary.csv_file = fullfile(out_root, 'TCN_v3_main_calibration_summary.csv');
summary.report_file = fullfile(out_root, 'TCN_v3_main_calibration_summary.md');
writetable(T, summary.csv_file);
local_write_md(summary.report_file, summary);

fprintf('[TCN v3 calibration] summary: %s\n', summary.csv_file);
disp(T);
end

function cfg = local_apply_calibration(cfg, calib_name)
switch lower(strtrim(calib_name))
    case 'sqrt_mild'
        cfg.calibration_name = 'sqrt_mild';
        cfg.class_weight_method = 'sqrt_inverse';
        cfg.main_class_multipliers = [1.15, 1.00, 0.95];
        cfg.main_neg_slope_weight = 2.0;
        cfg.main_pos_slope_weight = 1.0;
        cfg.base_best_metric = 'main_guard';
        cfg.best_metric = 'turn_priority';
        cfg.select_main_floor = 0.93;
        cfg.turn_priority_main_penalty_weight = 35.0;
        cfg.main_guard_flat_floor = 0.89;
        cfg.main_guard_stall_floor = 0.90;
        cfg.main_guard_slope_floor = 0.90;
        cfg.main_guard_flat_penalty_weight = 4.0;
        cfg.main_guard_slope_penalty_weight = 2.0;
    case 'flat_guard'
        cfg.calibration_name = 'flat_guard';
        cfg.class_weight_method = 'sqrt_inverse';
        cfg.main_class_multipliers = [1.35, 1.00, 0.80];
        cfg.main_neg_slope_weight = 1.5;
        cfg.main_pos_slope_weight = 0.95;
        cfg.base_best_metric = 'main_guard';
        cfg.best_metric = 'turn_priority';
        cfg.select_main_floor = 0.94;
        cfg.turn_priority_main_penalty_weight = 45.0;
        cfg.main_guard_flat_floor = 0.91;
        cfg.main_guard_stall_floor = 0.90;
        cfg.main_guard_slope_floor = 0.88;
        cfg.main_guard_flat_penalty_weight = 6.0;
        cfg.main_guard_slope_penalty_weight = 1.5;
    case 'main_guard'
        cfg.calibration_name = 'main_guard';
        cfg.class_weight_method = 'sqrt_inverse';
        cfg.main_class_multipliers = [1.25, 1.00, 0.90];
        cfg.main_neg_slope_weight = 2.0;
        cfg.main_pos_slope_weight = 1.0;
        cfg.base_best_metric = 'main_guard';
        cfg.best_metric = 'main_guard';
        cfg.combine_base_and_turn_best = false;
        cfg.selection_start_epoch = 1;
        cfg.early_stop_min_epochs = 65;
        cfg.main_guard_flat_floor = 0.91;
        cfg.main_guard_stall_floor = 0.90;
        cfg.main_guard_slope_floor = 0.90;
        cfg.main_guard_flat_penalty_weight = 5.0;
        cfg.main_guard_slope_penalty_weight = 2.0;
        cfg.main_guard_turn_weight = 0.08;
    otherwise
        error('run_TCN_v3_main_calibration:BadCalibration', ...
            'Unknown calibration config: %s', calib_name);
end
end

function meta = local_load_meta(meta_file)
if exist(meta_file, 'file') ~= 2
    error('run_TCN_v3_main_calibration:MissingMeta', ...
        'Meta file not found: %s', meta_file);
end
S = load(meta_file, 'meta');
meta = S.meta;
end

function row = local_empty_row()
row = struct('config', "", 'seed', NaN, 'best_epoch', NaN, 'base_best_epoch', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'class_weight_method', "", 'main_class_multipliers', "", ...
    'main_neg_slope_weight', NaN, 'main_pos_slope_weight', NaN, ...
    'base_best_metric', "", 'best_metric', "", ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(config_name, seed, meta, cfg)
m = meta.test_metrics;
row = local_empty_row();
row.config = string(config_name);
row.seed = seed;
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
row.class_weight_method = string(cfg.class_weight_method);
row.main_class_multipliers = sprintf('[%.2f %.2f %.2f]', cfg.main_class_multipliers);
row.main_neg_slope_weight = cfg.main_neg_slope_weight;
row.main_pos_slope_weight = cfg.main_pos_slope_weight;
row.base_best_metric = string(cfg.base_best_metric);
row.best_metric = string(cfg.best_metric);
row.model_file = string(cfg.model_file);
row.meta_file = string(cfg.meta_file);
row.report_file = string(cfg.report_file);
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function local_write_md(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('run_TCN_v3_main_calibration:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = summary.table;
fprintf(fid, '# TCN v3 Main Calibration Summary\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.dataset_file);
fprintf(fid, '- csv: `%s`\n\n', summary.csv_file);
fprintf(fid, '| config | seed | epoch | main | flat | stall | slope | turn | turn trans | theta deg | uphill | downhill |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.config(i), T.seed(i), T.best_epoch(i), T.acc_main(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.acc_turn(i), T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.uphill_recall(i), T.downhill_recall(i));
end
end
