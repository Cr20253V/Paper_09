function T = GRU_write_tcn_compare_table(gru_meta_file, output_file)
%GRU_WRITE_TCN_COMPARE_TABLE 将当前 GRU 候选与 TCN 临时候选写成同表。
%
% 使用示例:
%   T = GRU_write_tcn_compare_table( ...
%       'data/models/GRU_meta_gru_baseline_v1_h64_l1_turn0p05_last_mean.mat', ...
%       'results/gru/experiments/gru_baseline_v1/TCN_GRU_fair_compare_summary.csv');

if nargin < 1 || isempty(gru_meta_file)
    gru_meta_file = fullfile(project_root(), 'data', 'models', 'GRU_meta.mat');
end
if nargin < 2 || isempty(output_file)
    output_file = fullfile(results_dir(fullfile('gru', 'experiments')), 'TCN_GRU_fair_compare_summary.csv');
end

S = load(gru_meta_file, 'meta');
meta = S.meta;

tcn = local_empty_row();
tcn.model = "TCN";
tcn.case_name = "staged_bestbase_inputstats_turn_lam050";
tcn.seed = NaN;
tcn.best_epoch = 60;
tcn.acc_main = 0.9303;
tcn.acc_turn = 0.8989;
tcn.acc_turn_pure = 0.9257;
tcn.acc_turn_transition = 0.6341;
tcn.theta_mae_deg = 0.7380;
tcn.flat_recall = 0.9585;
tcn.stall_recall = 0.7778;
tcn.slope_recall = 0.9012;
tcn.uphill_recall = 0.9173;
tcn.downhill_recall = 0.8276;
tcn.model_file = "data/models/TCN_model_staged_bestbase_v1_staged_bestbase_inputstats_turn_lam050.mat";
tcn.meta_file = "data/models/TCN_meta_staged_bestbase_v1_staged_bestbase_inputstats_turn_lam050.mat";
tcn.report_file = "results/tcn/experiments/staged_bestbase_v1/staged_bestbase_inputstats_turn_lam050/TCN_train_report.md";

gru = local_row_from_meta(meta, gru_meta_file);
T = struct2table([tcn; gru]);

out_dir = fileparts(output_file);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
writetable(T, output_file);
local_write_md(strrep(output_file, '.csv', '.md'), T);
end

function row = local_empty_row()
row = struct('model', "", 'case_name', "", 'seed', NaN, 'best_epoch', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(meta, meta_file)
m = meta.test_metrics;
row = local_empty_row();
row.model = "GRU";
row.case_name = string(local_cfg(meta.cfg, 'case_name', local_case_name(meta.cfg)));
row.seed = local_cfg(meta.cfg, 'seed', NaN);
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
row.model_file = string(local_cfg(meta.cfg, 'model_file', ''));
row.meta_file = string(meta_file);
row.report_file = string(local_cfg(meta.cfg, 'report_file', ''));
end

function name = local_case_name(cfg)
name = sprintf('h%d_l%d_turn%.3f_%s', ...
    local_cfg(cfg, 'hidden_size', NaN), ...
    local_cfg(cfg, 'num_layers', NaN), ...
    local_cfg(cfg, 'lambda_turn', NaN), ...
    char(local_cfg(cfg, 'head_pooling', 'unknown')));
name = regexprep(strrep(name, '.', 'p'), '[^A-Za-z0-9_]+', '_');
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function v = local_cfg(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = default_value;
end
end

function local_write_md(md_file, T)
fid = fopen(md_file, 'w');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# TCN vs GRU 公平对照表\n\n');
fprintf(fid, '| model | case | seed | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | model file |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %s | %.0f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | `%s` |\n', ...
        T.model(i), T.case_name(i), T.seed(i), T.acc_main(i), T.acc_turn(i), ...
        T.acc_turn_pure(i), T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.model_file(i));
end
end
