function summary = run_TCN_GRU_transition_rich_v2_baseline(seed, do_prepare, do_train)
%RUN_TCN_GRU_TRANSITION_RICH_V2_BASELINE 训练 v2 共享数据集上的 TCN/GRU baseline。
%
% 示例:
%   init_project;
%   summary = run_TCN_GRU_transition_rich_v2_baseline(42, true, true);

if nargin < 1 || isempty(seed)
    seed = 42;
end
if nargin < 2
    do_prepare = true;
end
if nargin < 3
    do_train = true;
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
run_tag = sprintf('transition_rich_v2_seed%d', seed);
dataset_file = fullfile(root, 'data', 'tcn', 'TCN_dataset_v2_transition_rich.mat');
out_dir = results_dir(fullfile('tcn', 'experiments', run_tag));
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

if do_prepare
    prep_cfg = struct();
    prep_cfg.output_file = dataset_file;
    prep_cfg.scaler_file = fullfile(root, 'data', 'tcn', 'TCN_scaler_v2_transition_rich.mat');
    prep_cfg.split_file = fullfile(root, 'data', 'tcn', 'TCN_GRU_shared_run_split_v2_transition_rich.mat');
    prep_cfg.report_file = fullfile(root, 'data', 'tcn', 'TCN_prepare_dataset_v2_transition_rich_report.md');
    TCN_prepare_dataset_v2_transition_rich(prep_cfg);
end

rows = repmat(local_empty_row(), 2, 1);

tcn_cfg = TCN_recommended_cfg('production_current');
tcn_cfg.seed = seed;
tcn_cfg.verbose = false;
tcn_cfg.input_file = dataset_file;
tcn_cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s_staged.mat', run_tag));
tcn_cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s_staged.mat', run_tag));
tcn_cfg.log_dir = fullfile(out_dir, 'tcn_staged');
tcn_cfg.report_file = fullfile(tcn_cfg.log_dir, 'TCN_train_report.md');
if do_train
    [~, tcn_meta] = TCN_train(tcn_cfg);
else
    tcn_meta = local_load_meta(tcn_cfg.meta_file);
end
rows(1) = local_row_from_meta("TCN", seed, tcn_meta, tcn_cfg);

gru_cfg = GRU_recommended_cfg('inputstats_hidden96');
gru_cfg.num_layers = 2;
gru_cfg.lambda_turn = 0.05;
gru_cfg.seed = seed;
gru_cfg.verbose = false;
gru_cfg.input_file = dataset_file;
gru_cfg.model_file = fullfile(root, 'data', 'models', sprintf('GRU_model_%s_h96_l2_inputstats.mat', run_tag));
gru_cfg.meta_file = fullfile(root, 'data', 'models', sprintf('GRU_meta_%s_h96_l2_inputstats.mat', run_tag));
gru_cfg.log_dir = fullfile(out_dir, 'gru_h96_l2_inputstats');
gru_cfg.report_file = fullfile(gru_cfg.log_dir, 'GRU_train_report.md');
if do_train
    [~, gru_meta] = GRU_train(gru_cfg);
else
    gru_meta = local_load_meta(gru_cfg.meta_file);
end
rows(2) = local_row_from_meta("GRU", seed, gru_meta, gru_cfg);

T = struct2table(rows);
summary = struct();
summary.run_tag = run_tag;
summary.dataset_file = dataset_file;
summary.table = T;
summary.csv_file = fullfile(out_dir, 'TCN_GRU_transition_rich_v2_summary.csv');
summary.report_file = fullfile(out_dir, 'TCN_GRU_transition_rich_v2_summary.md');
writetable(T, summary.csv_file);
local_write_md(summary.report_file, summary);

fprintf('[transition-rich v2] summary: %s\n', summary.csv_file);
disp(T);
end

function meta = local_load_meta(meta_file)
if exist(meta_file, 'file') ~= 2
    error('run_TCN_GRU_transition_rich_v2_baseline:MissingMeta', ...
        'Meta file not found: %s', meta_file);
end
S = load(meta_file, 'meta');
meta = S.meta;
end

function row = local_empty_row()
row = struct('model', "", 'seed', NaN, 'best_epoch', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(model_name, seed, meta, cfg)
m = meta.test_metrics;
row = local_empty_row();
row.model = model_name;
row.seed = seed;
row.best_epoch = meta.best_epoch;
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
    warning('run_TCN_GRU_transition_rich_v2_baseline:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = summary.table;
fprintf(fid, '# TCN/GRU Transition-Rich v2 Baseline\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.dataset_file);
fprintf(fid, '- csv: `%s`\n\n', summary.csv_file);
fprintf(fid, '| model | seed | epoch | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.model(i), T.seed(i), T.best_epoch(i), T.acc_main(i), T.acc_turn(i), ...
        T.acc_turn_pure(i), T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i));
end
end
