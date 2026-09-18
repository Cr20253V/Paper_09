function summary = GRU_auto_experiment_pipeline(cfg)
%GRU_AUTO_EXPERIMENT_PIPELINE 小范围运行 GRU 公平对照实验。
%
% 使用示例:
%   init_project;
%   cfg = struct('run_tag','gru_baseline_v1','max_epochs',60,'use_gpu',true);
%   summary = GRU_auto_experiment_pipeline(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_defaults(cfg);
if ~exist(cfg.base_log_dir, 'dir')
    mkdir(cfg.base_log_dir);
end

cases = local_build_cases(cfg);
rows = repmat(local_empty_row(), numel(cases), 1);

for i = 1:numel(cases)
    c = cases(i);
    fprintf('\n[GRU pipeline] %d/%d %s\n', i, numel(cases), c.case_name);
    case_dir = fullfile(cfg.base_log_dir, c.case_name);
    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end

    artifact_name = local_clean_name(sprintf('%s_%s', cfg.run_tag, c.case_name));
    train_cfg = local_merge_cfg(c.train_cfg, struct( ...
        'model_file', fullfile(root, 'data', 'models', sprintf('GRU_model_%s.mat', artifact_name)), ...
        'meta_file', fullfile(root, 'data', 'models', sprintf('GRU_meta_%s.mat', artifact_name)), ...
        'log_dir', case_dir, ...
        'report_file', fullfile(case_dir, 'GRU_train_report.md')));

    if cfg.skip_existing && exist(train_cfg.meta_file, 'file') && local_existing_meta_matches(train_cfg.meta_file, train_cfg)
        S = load(train_cfg.meta_file, 'meta');
        meta = S.meta;
        fprintf('[GRU pipeline] skip existing: %s\n', train_cfg.meta_file);
    else
        [~, meta] = GRU_train(train_cfg);
    end
    rows(i) = local_row_from_meta(c, train_cfg, meta);
end

T = struct2table(rows);
T = sortrows(T, {'production_score','main_score'}, {'ascend','ascend'});

summary = struct();
summary.cfg = cfg;
summary.cases = cases;
summary.table = T;
summary.best = T(1, :);
summary.output_file = fullfile(cfg.base_log_dir, 'GRU_auto_experiment_pipeline_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'GRU_auto_experiment_pipeline_report.md');
summary.compare_file = fullfile(cfg.base_log_dir, 'TCN_GRU_fair_compare_summary.csv');
writetable(T, summary.output_file);
local_write_report(summary.report_file, summary);
local_write_tcn_gru_compare(summary.compare_file, summary.best);

fprintf('\n[GRU pipeline] done\n');
fprintf('  summary: %s\n', summary.output_file);
fprintf('  report : %s\n', summary.report_file);
fprintf('  compare: %s\n', summary.compare_file);
disp(T);
end

function cfg = local_defaults(cfg)
if ~isfield(cfg, 'run_tag'); cfg.run_tag = datestr(now, 'yyyymmdd_HHMMSS'); end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 60; end
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 64; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'skip_existing'); cfg.skip_existing = true; end
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('gru', 'experiments', cfg.run_tag));
end
if ~isfield(cfg, 'case_filter'); cfg.case_filter = {}; end
if ~isfield(cfg, 'hidden_sizes'); cfg.hidden_sizes = [64 96]; end
if ~isfield(cfg, 'num_layers_list'); cfg.num_layers_list = [1 2]; end
if ~isfield(cfg, 'lambda_turns'); cfg.lambda_turns = [0.05 0.10 0.20]; end
if ~isfield(cfg, 'head_poolings'); cfg.head_poolings = {'last_mean','last_mean_inputstats'}; end
if ischar(cfg.case_filter) || isstring(cfg.case_filter)
    cfg.case_filter = cellstr(cfg.case_filter);
end
end

function cases = local_build_cases(cfg)
base = GRU_recommended_cfg('baseline');
base.max_epochs = cfg.max_epochs;
base.batch_size = cfg.batch_size;
base.use_gpu = cfg.use_gpu;
base.verbose = cfg.verbose;

cases = struct('case_name', {}, 'phase', {}, 'train_cfg', {});
for ih = 1:numel(cfg.hidden_sizes)
    for il = 1:numel(cfg.num_layers_list)
        for it = 1:numel(cfg.lambda_turns)
            for ip = 1:numel(cfg.head_poolings)
                pooling = cfg.head_poolings{ip};
                train_cfg = local_merge_cfg(base, struct( ...
                    'hidden_size', cfg.hidden_sizes(ih), ...
                    'num_layers', cfg.num_layers_list(il), ...
                    'lambda_turn', cfg.lambda_turns(it), ...
                    'head_pooling', pooling));
                if contains(pooling, 'inputstats')
                    train_cfg.turn_head_type = 'mlp';
                    train_cfg.turn_head_source = 'inputstats';
                    train_cfg.turn_head_hidden = 64;
                else
                    train_cfg.turn_head_type = 'linear';
                    train_cfg.turn_head_source = 'readout';
                end
                case_name = sprintf('h%d_l%d_turn%.2f_%s', ...
                    cfg.hidden_sizes(ih), cfg.num_layers_list(il), cfg.lambda_turns(it), pooling);
                cases(end+1) = local_case(local_clean_name(case_name), 'grid', train_cfg); %#ok<AGROW>
            end
        end
    end
end

if ~isempty(cfg.case_filter)
    keep = false(1, numel(cases));
    for i = 1:numel(cases)
        keep(i) = any(strcmpi(cases(i).case_name, cfg.case_filter)) || ...
            any(strcmpi(cases(i).phase, cfg.case_filter));
    end
    cases = cases(keep);
end
end

function c = local_case(case_name, phase, train_cfg)
c = struct('case_name', case_name, 'phase', phase, 'train_cfg', train_cfg);
end

function tf = local_existing_meta_matches(meta_file, train_cfg)
tf = false;
try
    S = load(meta_file, 'meta');
    if ~isfield(S, 'meta') || ~isfield(S.meta, 'cfg')
        return;
    end
    old = S.meta.cfg;
    keys = {'max_epochs','batch_size','use_gpu','hidden_size','num_layers', ...
        'lambda_turn','head_pooling','turn_head_type','turn_head_source', ...
        'grad_clip_mode','best_metric'};
    for i = 1:numel(keys)
        k = keys{i};
        if isfield(train_cfg, k) && (~isfield(old, k) || ~isequaln(old.(k), train_cfg.(k)))
            return;
        end
    end
    tf = true;
catch
    tf = false;
end
end

function row = local_empty_row()
row = struct('model', "GRU", 'case_name', "", 'phase', "", 'seed', NaN, ...
    'best_epoch', NaN, 'production_score', NaN, 'main_score', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'hidden_size', NaN, 'num_layers', NaN, 'head_pooling', "", ...
    'turn_head_type', "", 'turn_head_source', "", 'lambda_turn', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(c, train_cfg, meta)
m = meta.test_metrics;
row = local_empty_row();
row.case_name = string(c.case_name);
row.phase = string(c.phase);
row.seed = local_get_cfg(train_cfg, 'seed', NaN);
row.best_epoch = meta.best_epoch;
row.acc_main = m.acc_main;
row.acc_turn = m.acc_turn;
row.acc_turn_pure = local_get_metric(m, 'acc_turn_pure');
row.acc_turn_transition = local_get_metric(m, 'acc_turn_transition');
row.theta_mae_deg = rad2deg(m.mae_theta);
row.flat_recall = m.recall_main(1);
row.stall_recall = m.recall_main(2);
row.slope_recall = m.recall_main(3);
row.uphill_recall = m.uphill.slope_recall;
row.downhill_recall = m.downhill.slope_recall;
row.flat_as_slope = m.cm_main(1, 3) / max(sum(m.cm_main(1, :)), 1);
row.hidden_size = local_get_cfg(train_cfg, 'hidden_size', NaN);
row.num_layers = local_get_cfg(train_cfg, 'num_layers', NaN);
row.head_pooling = string(local_get_cfg(train_cfg, 'head_pooling', ''));
row.turn_head_type = string(local_get_cfg(train_cfg, 'turn_head_type', ''));
row.turn_head_source = string(local_get_cfg(train_cfg, 'turn_head_source', ''));
row.lambda_turn = local_get_cfg(train_cfg, 'lambda_turn', NaN);
row.model_file = string(train_cfg.model_file);
row.meta_file = string(train_cfg.meta_file);
row.report_file = string(train_cfg.report_file);
row.main_score = (1 - row.acc_main) ...
    + 0.20 * max(0, 0.85 - row.uphill_recall) ...
    + 0.20 * max(0, 0.85 - row.downhill_recall) ...
    + 0.04 * row.theta_mae_deg ...
    + 0.20 * row.flat_as_slope;
row.production_score = row.main_score ...
    + 0.25 * max(0, 0.92 - row.acc_main) ...
    + 0.30 * (1 - row.acc_turn);
end

function v = local_get_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function v = local_get_cfg(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = default_value;
end
end

function dst = local_merge_cfg(a, b)
dst = a;
names = fieldnames(b);
for i = 1:numel(names)
    dst.(names{i}) = b.(names{i});
end
end

function name = local_clean_name(name)
name = strrep(name, '.', 'p');
name = regexprep(name, '[^A-Za-z0-9_]+', '_');
end

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    error('GRU_auto_experiment_pipeline:ReportFailed', '无法写入报告: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# GRU 自动实验流水线报告\n\n');
fprintf(fid, '- 生成时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- 输出 CSV: `%s`\n\n', summary.output_file);
local_write_table(fid, summary.table);
end

function local_write_tcn_gru_compare(output_file, best_gru)
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

Ttcn = struct2table(tcn);
T = [Ttcn; best_gru(:, Ttcn.Properties.VariableNames)];
writetable(T, output_file);

md_file = strrep(output_file, '.csv', '.md');
fid = fopen(md_file, 'w');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# TCN vs GRU 公平对照表\n\n');
fprintf(fid, '- TCN 行使用当前交接文档记录的临时最优候选，不代表论文最终结果。\n');
fprintf(fid, '- GRU 行使用本次流水线 production_score 排序后的最佳候选。\n\n');
local_write_table(fid, T);
end

function local_write_table(fid, T)
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
