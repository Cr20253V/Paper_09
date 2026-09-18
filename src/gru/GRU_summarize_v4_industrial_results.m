function summary = GRU_summarize_v4_industrial_results(cfg)
%GRU_SUMMARIZE_V4_INDUSTRIAL_RESULTS Summarize existing GRU V4 meta files.
%
% This function is read-only with respect to trained models. It scans
% data/models/GRU_meta_gru_v4_industrial_<case>_seed*.mat and writes a
% per-seed CSV plus a group summary. It is useful when some seeds are run
% with a smaller batch size after an out-of-memory interruption.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
if ~isfield(cfg, 'cases') || isempty(cfg.cases)
    cfg.cases = {'inputstats_hidden96'};
end
if ischar(cfg.cases) || isstring(cfg.cases)
    cfg.cases = cellstr(cfg.cases);
end
if ~isfield(cfg, 'seeds') || isempty(cfg.seeds)
    cfg.seeds = [11 21 42 73 101];
end
if ~isfield(cfg, 'output_dir') || isempty(cfg.output_dir)
    cfg.output_dir = results_dir(fullfile('gru', 'train_logs_v4_industrial'));
end
if exist(cfg.output_dir, 'dir') ~= 7
    mkdir(cfg.output_dir);
end

rows = repmat(local_empty_row(), 0, 1);
for ic = 1:numel(cfg.cases)
    case_name = char(cfg.cases{ic});
    for iseed = 1:numel(cfg.seeds)
        seed = cfg.seeds(iseed);
        meta_file = fullfile(root, 'data', 'models', ...
            sprintf('GRU_meta_gru_v4_industrial_%s_seed%d.mat', case_name, seed));
        if exist(meta_file, 'file') ~= 2
            row = local_empty_row();
            row.case_name = string(case_name);
            row.seed = seed;
            row.status = "missing";
        else
            S = load(meta_file, 'meta');
            row = local_row_from_meta(case_name, meta_file, S.meta);
        end
        rows(end+1) = row; %#ok<AGROW>
    end
end

T = struct2table(rows);
G = local_group_summary(T);

summary = struct();
summary.cfg = cfg;
summary.per_seed = T;
summary.group_summary = G;
summary.output_file = fullfile(cfg.output_dir, 'GRU_v4_industrial_existing_meta_summary.csv');
summary.group_file = fullfile(cfg.output_dir, 'GRU_v4_industrial_existing_meta_group_summary.csv');
summary.report_file = fullfile(cfg.output_dir, 'GRU_v4_industrial_existing_meta_report.md');

writetable(T, summary.output_file);
writetable(G, summary.group_file);
local_write_report(summary.report_file, summary);

fprintf('[GRU V4 summarize] wrote:\n');
fprintf('  per-seed: %s\n', summary.output_file);
fprintf('  group   : %s\n', summary.group_file);
fprintf('  report  : %s\n', summary.report_file);
disp(G);
end

function row = local_empty_row()
row = struct('model', "GRU", 'case_name', "", 'seed', NaN, 'status', "", ...
    'best_epoch', NaN, 'train_seconds', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'hidden_size', NaN, 'num_layers', NaN, 'head_pooling', "", ...
    'turn_head_type', "", 'turn_head_source', "", 'lambda_turn', NaN, ...
    'batch_size', NaN, 'model_file', "", 'meta_file', "", 'report_file', "");
end

function row = local_row_from_meta(case_name, meta_file, meta)
m = meta.test_metrics;
cfg = meta.cfg;
row = local_empty_row();
row.case_name = string(case_name);
row.seed = local_cfg(cfg, 'seed', NaN);
row.status = "ok";
row.best_epoch = meta.best_epoch;
row.train_seconds = meta.train_seconds;
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
row.flat_as_slope = m.cm_main(1, 3) / max(sum(m.cm_main(1, :)), 1);
row.hidden_size = local_cfg(cfg, 'hidden_size', NaN);
row.num_layers = local_cfg(cfg, 'num_layers', NaN);
row.head_pooling = string(local_cfg(cfg, 'head_pooling', ''));
row.turn_head_type = string(local_cfg(cfg, 'turn_head_type', ''));
row.turn_head_source = string(local_cfg(cfg, 'turn_head_source', ''));
row.lambda_turn = local_cfg(cfg, 'lambda_turn', NaN);
row.batch_size = local_cfg(cfg, 'batch_size', NaN);
row.model_file = string(local_cfg(cfg, 'model_file', ''));
row.meta_file = string(meta_file);
row.report_file = string(local_cfg(cfg, 'report_file', ''));
end

function G = local_group_summary(T)
ok = strcmp(T.status, "ok");
T = T(ok, :);
if isempty(T)
    G = table();
    return;
end
metrics = {'acc_main','acc_turn','acc_turn_pure','acc_turn_transition', ...
    'theta_mae_deg','flat_recall','stall_recall','slope_recall', ...
    'uphill_recall','downhill_recall','flat_as_slope'};
cases = unique(T.case_name, 'stable');
rows = repmat(struct('case_name', "", 'n', 0), numel(cases), 1);
for i = 1:numel(cases)
    rows(i).case_name = cases(i);
    m = T(T.case_name == cases(i), :);
    rows(i).n = height(m);
    for j = 1:numel(metrics)
        name = metrics{j};
        rows(i).([name '_mean']) = mean(m.(name), 'omitnan');
        rows(i).([name '_std']) = std(m.(name), 'omitnan');
    end
end
G = struct2table(rows);
end

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('GRU:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# GRU V4 Existing Meta Summary\n\n');
fprintf(fid, '- cases: `%s`\n', strjoin(summary.cfg.cases, ', '));
fprintf(fid, '- seeds: `%s`\n', mat2str(summary.cfg.seeds));
fprintf(fid, '- per-seed CSV: `%s`\n', summary.output_file);
fprintf(fid, '- group CSV: `%s`\n\n', summary.group_file);
fprintf(fid, '## Group Summary\n\n');
local_write_table(fid, summary.group_summary);
fprintf(fid, '\n## Per Seed\n\n');
local_write_table(fid, summary.per_seed);
end

function local_write_table(fid, T)
if isempty(T) || height(T) == 0
    fprintf(fid, '_No rows._\n');
    return;
end
names = T.Properties.VariableNames;
fprintf(fid, '| %s |\n', strjoin(names, ' | '));
fprintf(fid, '|%s|\n', strjoin(repmat({'---'}, 1, numel(names)), '|'));
for i = 1:height(T)
    vals = cell(1, numel(names));
    for j = 1:numel(names)
        v = T.(names{j})(i);
        if isnumeric(v)
            vals{j} = char(local_num_to_str(v));
        elseif iscell(v)
            vals{j} = char(string(v{1}));
        else
            vals{j} = char(string(v));
        end
    end
    fprintf(fid, '| %s |\n', strjoin(vals, ' | '));
end
end

function s = local_num_to_str(v)
if isscalar(v)
    if isnan(v)
        s = "NaN";
    elseif abs(v - round(v)) < 1e-12 && abs(v) < 1e6
        s = string(sprintf('%.0f', v));
    else
        s = string(sprintf('%.6g', v));
    end
else
    s = string(mat2str(v));
end
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function v = local_cfg(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
