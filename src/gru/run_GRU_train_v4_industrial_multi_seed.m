function summary = run_GRU_train_v4_industrial_multi_seed(cfg)
%RUN_GRU_TRAIN_V4_INDUSTRIAL_MULTI_SEED Train GRU on the ModernTCN V4 dataset.
%
% Default run:
%   2 configurations x 5 seeds on data/tcn/ModernTCN_dataset_v4_industrial.mat.
% Artifacts are written with v4_industrial names and do not overwrite the
% existing GRU baseline files.
%
% Usage:
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'gru'));
%   summary = run_GRU_train_v4_industrial_multi_seed();
%
% Smoke example:
%   cfg = struct('seeds', 42, 'cases', {{'baseline'}}, 'max_epochs', 2, ...
%                'run_tag', 'gru_v4_industrial_smoke', 'skip_existing', false);
%   summary = run_GRU_train_v4_industrial_multi_seed(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_defaults(cfg, root);

if exist(cfg.base_log_dir, 'dir') ~= 7
    mkdir(cfg.base_log_dir);
end
GRU_check_v4_dataset_contract(cfg.input_file);

cases = local_build_cases(cfg);
rows = repmat(local_empty_row(), numel(cases) * numel(cfg.seeds), 1);
row_k = 0;

for ic = 1:numel(cases)
    case_cfg = cases(ic).train_cfg;
    case_name = cases(ic).case_name;
    for iseed = 1:numel(cfg.seeds)
        seed = cfg.seeds(iseed);
        row_k = row_k + 1;
        artifact = local_clean_name(sprintf('%s_%s_seed%d', cfg.run_tag, case_name, seed));
        case_dir = fullfile(cfg.base_log_dir, sprintf('%s_seed%d', case_name, seed));
        if exist(case_dir, 'dir') ~= 7
            mkdir(case_dir);
        end

        train_cfg = local_merge_cfg(case_cfg, struct( ...
            'seed', seed, ...
            'input_file', cfg.input_file, ...
            'model_file', fullfile(root, 'data', 'models', sprintf('GRU_model_%s.mat', artifact)), ...
            'meta_file', fullfile(root, 'data', 'models', sprintf('GRU_meta_%s.mat', artifact)), ...
            'log_dir', case_dir, ...
            'report_file', fullfile(case_dir, 'GRU_train_report.md'), ...
            'case_name', case_name));

        fprintf('\n[GRU V4] case=%s seed=%d (%d/%d)\n', ...
            case_name, seed, row_k, numel(rows));
        try
            if cfg.skip_existing && exist(train_cfg.meta_file, 'file') == 2 && ...
                    local_existing_meta_matches(train_cfg.meta_file, train_cfg)
                S = load(train_cfg.meta_file, 'meta');
                meta = S.meta;
                fprintf('[GRU V4] skip existing: %s\n', train_cfg.meta_file);
            else
                [~, meta] = GRU_train(train_cfg);
            end
            rows(row_k) = local_row_from_meta(case_name, train_cfg, meta, "");
        catch ME
            warning('GRU:TrainFailed', 'case=%s seed=%d failed: %s', ...
                case_name, seed, ME.message);
            rows(row_k) = local_failed_row(case_name, train_cfg, ME);
        end
        local_write_incremental_summary(cfg, rows(1:row_k));
    end
end

rows = rows(1:row_k);
T = struct2table(rows);
T = sortrows(T, {'case_name','seed'});
G = local_group_summary(T);

summary = struct();
summary.cfg = cfg;
summary.cases = cases;
summary.per_seed = T;
summary.group_summary = G;
summary.output_file = fullfile(cfg.base_log_dir, 'GRU_v4_industrial_multi_seed_summary.csv');
summary.group_file = fullfile(cfg.base_log_dir, 'GRU_v4_industrial_group_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'GRU_v4_industrial_multi_seed_report.md');

writetable(T, summary.output_file);
writetable(G, summary.group_file);
local_write_report(summary.report_file, summary);

fprintf('\n[GRU V4] done\n');
fprintf('  per-seed: %s\n', summary.output_file);
fprintf('  group   : %s\n', summary.group_file);
fprintf('  report  : %s\n', summary.report_file);
disp(G);
end

function cfg = local_defaults(cfg, root)
if ~isfield(cfg, 'run_tag'); cfg.run_tag = 'gru_v4_industrial'; end
if ~isfield(cfg, 'input_file')
    cfg.input_file = fullfile(root, 'data', 'tcn', 'ModernTCN_dataset_v4_industrial.mat');
end
if ~isfield(cfg, 'seeds'); cfg.seeds = [11 21 42 73 101]; end
if ~isfield(cfg, 'cases'); cfg.cases = {'inputstats_hidden96','baseline'}; end
if ischar(cfg.cases) || isstring(cfg.cases); cfg.cases = cellstr(cfg.cases); end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 60; end
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 128; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'skip_existing'); cfg.skip_existing = true; end
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('gru', 'train_logs_v4_industrial'));
end
end

function cases = local_build_cases(cfg)
cases = struct('case_name', {}, 'train_cfg', {});
for i = 1:numel(cfg.cases)
    name = char(cfg.cases{i});
    switch lower(name)
        case {'baseline','gru_base_last_mean'}
            c = GRU_recommended_cfg('baseline');
            c.case_name = 'baseline';
        case {'inputstats_hidden96','gru_inputstats_hidden96'}
            c = GRU_recommended_cfg('inputstats_hidden96');
            c.case_name = 'inputstats_hidden96';
        otherwise
            error('GRU:BadCase', 'Unknown GRU V4 case: %s', name);
    end

    c.max_epochs = cfg.max_epochs;
    c.batch_size = cfg.batch_size;
    c.use_gpu = cfg.use_gpu;
    c.verbose = cfg.verbose;

    % Match the ModernTCN V4 turn-focused training emphasis where the GRU
    % implementation exposes equivalent knobs.
    c.lambda_turn = 0.08;
    c.lambda_theta = 0.35;
    c.lambda_theta_flat = 0.25;
    c.turn_class_weight_method = 'none';
    c.turn_class_multipliers = [1.15 1.00 1.15];
    c.class_weight_method = 'balanced';
    c.best_metric = 'composite';
    c.select_turn_error_weight = 0.20;
    c.select_theta_weight = 0.20;
    c.select_downhill_error_weight = 0.25;
    c.early_stop_min_epochs = min(20, max(1, cfg.max_epochs));
    c.patience = 12;
    c.print_every = 1;

    cases(end+1) = struct('case_name', c.case_name, 'train_cfg', c); %#ok<AGROW>
end
end

function tf = local_existing_meta_matches(meta_file, train_cfg)
tf = false;
try
    S = load(meta_file, 'meta');
    if ~isfield(S, 'meta') || ~isfield(S.meta, 'cfg')
        return;
    end
    old = S.meta.cfg;
    keys = {'input_file','seed','max_epochs','batch_size','use_gpu', ...
        'hidden_size','num_layers','head_pooling','turn_head_type', ...
        'turn_head_source','lambda_turn','lambda_theta','lambda_theta_flat', ...
        'best_metric'};
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
row = struct('model', "GRU", 'case_name', "", 'seed', NaN, 'status', "", ...
    'best_epoch', NaN, 'train_seconds', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'hidden_size', NaN, 'num_layers', NaN, 'head_pooling', "", ...
    'turn_head_type', "", 'turn_head_source', "", 'lambda_turn', NaN, ...
    'model_file', "", 'meta_file', "", 'report_file', "", 'error_message', "");
end

function row = local_row_from_meta(case_name, train_cfg, meta, error_message)
m = meta.test_metrics;
row = local_empty_row();
row.case_name = string(case_name);
row.seed = train_cfg.seed;
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
row.hidden_size = train_cfg.hidden_size;
row.num_layers = train_cfg.num_layers;
row.head_pooling = string(train_cfg.head_pooling);
row.turn_head_type = string(train_cfg.turn_head_type);
row.turn_head_source = string(train_cfg.turn_head_source);
row.lambda_turn = train_cfg.lambda_turn;
row.model_file = string(train_cfg.model_file);
row.meta_file = string(train_cfg.meta_file);
row.report_file = string(train_cfg.report_file);
row.error_message = string(error_message);
end

function row = local_failed_row(case_name, train_cfg, ME)
row = local_empty_row();
row.case_name = string(case_name);
row.seed = train_cfg.seed;
row.status = "failed";
row.hidden_size = local_cfg(train_cfg, 'hidden_size', NaN);
row.num_layers = local_cfg(train_cfg, 'num_layers', NaN);
row.head_pooling = string(local_cfg(train_cfg, 'head_pooling', ''));
row.turn_head_type = string(local_cfg(train_cfg, 'turn_head_type', ''));
row.turn_head_source = string(local_cfg(train_cfg, 'turn_head_source', ''));
row.lambda_turn = local_cfg(train_cfg, 'lambda_turn', NaN);
row.model_file = string(train_cfg.model_file);
row.meta_file = string(train_cfg.meta_file);
row.report_file = string(train_cfg.report_file);
row.error_message = string(ME.message);
end

function G = local_group_summary(T)
ok = strcmp(T.status, "ok");
T = T(ok, :);
metrics = {'acc_main','acc_turn','acc_turn_pure','acc_turn_transition', ...
    'theta_mae_deg','flat_recall','stall_recall','slope_recall', ...
    'uphill_recall','downhill_recall','flat_as_slope'};
if isempty(T)
    G = table();
    return;
end

cases = unique(T.case_name, 'stable');
rows = repmat(struct('case_name', "", 'n', 0), numel(cases), 1);
for i = 1:numel(cases)
    rows(i).case_name = cases(i);
    rows(i).n = nnz(T.case_name == cases(i));
    m = T(T.case_name == cases(i), :);
    for j = 1:numel(metrics)
        name = metrics{j};
        rows(i).([name '_mean']) = mean(m.(name), 'omitnan');
        rows(i).([name '_std']) = std(m.(name), 'omitnan');
    end
end
G = struct2table(rows);
end

function local_write_incremental_summary(cfg, rows)
T = struct2table(rows);
out_file = fullfile(cfg.base_log_dir, 'GRU_v4_industrial_multi_seed_summary_partial.csv');
writetable(T, out_file);
end

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('GRU:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# GRU V4 Industrial Multi-Seed Report\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.cfg.input_file);
fprintf(fid, '- run_tag: `%s`\n', summary.cfg.run_tag);
fprintf(fid, '- seeds: `%s`\n', mat2str(summary.cfg.seeds));
fprintf(fid, '- per-seed CSV: `%s`\n', summary.output_file);
fprintf(fid, '- group CSV: `%s`\n\n', summary.group_file);

fprintf(fid, '## Group Summary\n\n');
local_write_table(fid, summary.group_summary);
fprintf(fid, '\n## Per Seed\n\n');
local_write_table(fid, summary.per_seed);

mtcn = local_read_modern_tcn_default(summary.cfg);
if ~isempty(mtcn)
    fprintf(fid, '\n## ModernTCN V4 Reference\n\n');
    local_write_table(fid, mtcn);
end
end

function T = local_read_modern_tcn_default(cfg)
root = project_root();
csv_file = fullfile(root, 'results', 'modern_tcn', ...
    'modern_tcn_v4_turn_focus_A_theta_head_B_seed21', ...
    'modern_tcn_seed21_summary.csv');
if exist(csv_file, 'file') ~= 2
    T = table();
    return;
end
T0 = readtable(csv_file);
names = intersect(T0.Properties.VariableNames, ...
    {'seed','acc_main','acc_turn','acc_turn_pure','acc_turn_transition', ...
     'theta_mae_deg','flat_recall','stall_recall','slope_recall', ...
     'uphill_recall','downhill_recall'}, 'stable');
T = T0(:, names);
T.model = repmat("ModernTCN", height(T), 1);
T = movevars(T, 'model', 'Before', 1);
unused = cfg; %#ok<NASGU>
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
