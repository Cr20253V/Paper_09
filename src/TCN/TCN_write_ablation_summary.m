function T = TCN_write_ablation_summary(output_dir)
%TCN_WRITE_ABLATION_SUMMARY 汇总当前 TCN/GRU/PG-TCN 消融结论。
%
% 该脚本不重新训练模型，只读取当前已经冻结的临时最优结果和
% PG-TCN 多 seed 确认结果，生成论文阶段用的对照表。

if nargin < 1 || isempty(output_dir)
    output_dir = results_dir(fullfile('tcn', 'experiments', 'ablation_summary_current'));
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

rows = local_empty_row();
rows(1) = local_tcn_best_row();

gru_csv = fullfile(project_root(), 'results', 'gru', 'experiments', ...
    'gru_fair_v1', 'GRU_auto_experiment_pipeline_summary.csv');
if exist(gru_csv, 'file') == 2
    rows(end+1) = local_gru_best_row(gru_csv);
else
    rows(end+1) = local_gru_fallback_row();
end

pg_csv = fullfile(project_root(), 'results', 'tcn', 'experiments', ...
    'pg_confirm_v3', 'TCN_pg_auto_experiment_pipeline_summary.csv');
if exist(pg_csv, 'file') == 2
    pg = readtable(pg_csv, 'TextType', 'string');
    pg_phy = pg(pg.lambda_phy > 0, :);
    pg_ctrl = pg(pg.lambda_phy == 0, :);
    if ~isempty(pg_phy)
        [~, idx] = min(pg_phy.pg_score);
        rows(end+1) = local_pg_table_row(pg_phy(idx, :), "PG-TCN", ... %#ok<AGROW>
            "best_single_phy0p005", "single");
        rows(end+1) = local_pg_mean_row(pg_phy, "PG-TCN", ... %#ok<AGROW>
            "mean_phy0p005_seed5", "mean");
    end
    if ~isempty(pg_ctrl)
        rows(end+1) = local_pg_mean_row(pg_ctrl, "TCN-control", ... %#ok<AGROW>
            "mean_phy0_seed5", "mean");
    end
end

T = struct2table(rows);
csv_file = fullfile(output_dir, 'TCN_GRU_PG_ablation_summary.csv');
md_file = fullfile(output_dir, 'TCN_GRU_PG_ablation_summary.md');
writetable(T, csv_file);
local_write_md(md_file, T, csv_file);

fprintf('[TCN ablation] wrote: %s\n', csv_file);
fprintf('[TCN ablation] wrote: %s\n', md_file);
end

function row = local_empty_row()
row = struct('model', "", 'role', "", 'case_name', "", 'summary_type', "", ...
    'seed', NaN, 'n_seeds', NaN, 'best_epoch', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'lambda_phy', NaN, 'lambda_smooth', NaN, ...
    'turn_transition_weight', NaN, 'decision', "", ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_tcn_best_row()
row = local_empty_row();
row.model = "TCN";
row.role = "main";
row.case_name = "staged_bestbase_inputstats_turn_lam050";
row.summary_type = "frozen_single";
row.seed = NaN;
row.n_seeds = 1;
row.best_epoch = 60;
row.acc_main = 0.9303;
row.acc_turn = 0.8989;
row.acc_turn_pure = 0.9257;
row.acc_turn_transition = 0.6341;
row.theta_mae_deg = 0.7380;
row.flat_recall = 0.9585;
row.stall_recall = 0.7778;
row.slope_recall = 0.9012;
row.uphill_recall = 0.9173;
row.downhill_recall = 0.8276;
row.decision = "mainline temporary best";
row.model_file = "data/models/TCN_model_staged_bestbase_v1_staged_bestbase_inputstats_turn_lam050.mat";
row.meta_file = "data/models/TCN_meta_staged_bestbase_v1_staged_bestbase_inputstats_turn_lam050.mat";
row.report_file = "results/tcn/experiments/staged_bestbase_v1/staged_bestbase_inputstats_turn_lam050/TCN_train_report.md";
end

function row = local_gru_best_row(gru_csv)
G = readtable(gru_csv, 'TextType', 'string');
[~, idx] = min(G.production_score);
g = G(idx, :);
row = local_empty_row();
row.model = "GRU";
row.role = "fair_baseline";
row.case_name = g.case_name;
row.summary_type = "grid_best_single";
row.seed = local_get_table_value(g, 'seed', NaN);
row.n_seeds = 1;
row.best_epoch = g.best_epoch;
row.acc_main = g.acc_main;
row.acc_turn = g.acc_turn;
row.acc_turn_pure = g.acc_turn_pure;
row.acc_turn_transition = g.acc_turn_transition;
row.theta_mae_deg = g.theta_mae_deg;
row.flat_recall = g.flat_recall;
row.stall_recall = g.stall_recall;
row.slope_recall = g.slope_recall;
row.uphill_recall = g.uphill_recall;
row.downhill_recall = g.downhill_recall;
row.decision = "GRU temporary best";
row.model_file = g.model_file;
row.meta_file = g.meta_file;
row.report_file = g.report_file;
end

function row = local_gru_fallback_row()
row = local_empty_row();
row.model = "GRU";
row.role = "fair_baseline";
row.case_name = "h96_l2_turn0p05_last_mean_inputstats";
row.summary_type = "reported_single";
row.n_seeds = 1;
row.best_epoch = 48;
row.acc_main = 0.9483;
row.acc_turn = 0.8831;
row.acc_turn_pure = 0.9134;
row.acc_turn_transition = 0.5854;
row.theta_mae_deg = 0.4156;
row.flat_recall = 0.9623;
row.stall_recall = 0.6667;
row.slope_recall = 0.9568;
row.uphill_recall = 0.9774;
row.downhill_recall = 0.8621;
row.decision = "GRU temporary best";
end

function row = local_pg_table_row(t, model_name, case_name, summary_type)
row = local_empty_row();
row.model = model_name;
row.role = "ablation";
row.case_name = case_name;
row.summary_type = summary_type;
row.seed = t.seed;
row.n_seeds = 1;
row.best_epoch = t.best_epoch;
row.acc_main = t.acc_main;
row.acc_turn = t.acc_turn;
row.acc_turn_pure = t.acc_turn_pure;
row.acc_turn_transition = t.acc_turn_transition;
row.theta_mae_deg = t.theta_mae_deg;
row.flat_recall = t.flat_recall;
row.stall_recall = t.stall_recall;
row.slope_recall = t.slope_recall;
row.uphill_recall = t.uphill_recall;
row.downhill_recall = t.downhill_recall;
row.lambda_phy = t.lambda_phy;
row.lambda_smooth = t.lambda_smooth;
row.turn_transition_weight = t.turn_transition_weight;
row.decision = "ablation only";
row.model_file = t.model_file;
row.report_file = t.report_file;
end

function row = local_pg_mean_row(T, model_name, case_name, summary_type)
row = local_empty_row();
row.model = model_name;
row.role = "ablation";
row.case_name = case_name;
row.summary_type = summary_type;
row.n_seeds = height(T);
row.acc_main = mean(T.acc_main, 'omitnan');
row.acc_turn = mean(T.acc_turn, 'omitnan');
row.acc_turn_pure = mean(T.acc_turn_pure, 'omitnan');
row.acc_turn_transition = mean(T.acc_turn_transition, 'omitnan');
row.theta_mae_deg = mean(T.theta_mae_deg, 'omitnan');
row.flat_recall = mean(T.flat_recall, 'omitnan');
row.stall_recall = mean(T.stall_recall, 'omitnan');
row.slope_recall = mean(T.slope_recall, 'omitnan');
row.uphill_recall = mean(T.uphill_recall, 'omitnan');
row.downhill_recall = mean(T.downhill_recall, 'omitnan');
row.lambda_phy = mean(T.lambda_phy, 'omitnan');
row.lambda_smooth = mean(T.lambda_smooth, 'omitnan');
row.turn_transition_weight = mean(T.turn_transition_weight, 'omitnan');
row.decision = "ablation only; not mainline";
row.report_file = "results/tcn/experiments/pg_confirm_v3/TCN_pg_auto_experiment_pipeline_report.md";
end

function v = local_get_table_value(T, field_name, default_value)
if any(strcmp(T.Properties.VariableNames, field_name))
    v = T.(field_name);
else
    v = default_value;
end
end

function local_write_md(md_file, T, csv_file)
fid = fopen(md_file, 'w');
if fid < 0
    error('TCN_write_ablation_summary:ReportFailed', 'Cannot write %s', md_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# TCN / GRU / PG-TCN 当前消融汇总\n\n');
fprintf(fid, '- CSV: `%s`\n', csv_file);
fprintf(fid, '- 结论: 当前主线保留 staged TCN；GRU 作为公平对照；PG-TCN 作为消融实验，不作为主线模型。\n\n');
fprintf(fid, '| model | role | case | type | seed | n | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | decision |\n');
fprintf(fid, '|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %s | %s | %s | %.0f | %.0f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %s |\n', ...
        T.model(i), T.role(i), T.case_name(i), T.summary_type(i), ...
        T.seed(i), T.n_seeds(i), T.acc_main(i), T.acc_turn(i), ...
        T.acc_turn_pure(i), T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.decision(i));
end
end
