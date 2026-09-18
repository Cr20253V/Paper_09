function summary = run_TCN_train_theta10_v2_multi_seed(cfg)
%RUN_TCN_TRAIN_THETA10_V2_MULTI_SEED Train legacy TCN on theta10 uniform V2.
%
% This runner uses the same horizon=0 V2 window dataset as the GRU and
% ModernTCN runs. It keeps theta regression raw and sets the flat-theta
% regularizer to near-zero samples only, so flat-labeled mild slopes are not
% forced to theta_hat=0.
%
% Usage:
%   init_project;
%   summary = run_TCN_train_theta10_v2_multi_seed();
%
% Dry run:
%   cfg = struct('do_train', false);
%   summary = run_TCN_train_theta10_v2_multi_seed(cfg);

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

local_check_dataset_file(cfg.input_file);
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
            'model_file', fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', artifact)), ...
            'meta_file', fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', artifact)), ...
            'log_dir', case_dir, ...
            'report_file', fullfile(case_dir, 'TCN_train_report.md'), ...
            'case_name', case_name));

        fprintf('\n[TCN theta10 V2] case=%s seed=%d (%d/%d)\n', ...
            case_name, seed, row_k, numel(rows));
        if ~cfg.do_train
            rows(row_k) = local_planned_row(case_name, train_cfg);
            local_write_incremental_summary(cfg, rows(1:row_k));
            continue;
        end

        try
            if cfg.skip_existing && exist(train_cfg.meta_file, 'file') == 2 && ...
                    local_existing_meta_matches(train_cfg.meta_file, train_cfg)
                S = load(train_cfg.meta_file, 'meta');
                meta = S.meta;
                fprintf('[TCN theta10 V2] skip existing: %s\n', train_cfg.meta_file);
            else
                [~, meta] = TCN_train(train_cfg);
            end
            rows(row_k) = local_row_from_meta(case_name, train_cfg, meta, "");
        catch ME
            warning('TCN:TrainFailed', 'case=%s seed=%d failed: %s', ...
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
summary.output_file = fullfile(cfg.base_log_dir, 'TCN_theta10_v2_multi_seed_summary.csv');
summary.group_file = fullfile(cfg.base_log_dir, 'TCN_theta10_v2_group_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'TCN_theta10_v2_multi_seed_report.md');

writetable(T, summary.output_file);
writetable(G, summary.group_file);
local_write_report(summary.report_file, summary);

fprintf('\n[TCN theta10 V2] done\n');
fprintf('  per-seed: %s\n', summary.output_file);
fprintf('  group   : %s\n', summary.group_file);
fprintf('  report  : %s\n', summary.report_file);
if ~isempty(G)
    disp(G);
end
end

function cfg = local_defaults(cfg, root)
if ~isfield(cfg, 'run_tag'); cfg.run_tag = 'tcn_theta10_uniform_h0_v2'; end
if ~isfield(cfg, 'input_file')
    cfg.input_file = fullfile(root, 'data', 'tcn', ...
        'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat');
end
if ~isfield(cfg, 'seeds'); cfg.seeds = [11 21 42 73 101]; end
if ~isfield(cfg, 'cases'); cfg.cases = {'tcn96_rawtheta_sym'}; end
if ischar(cfg.cases) || isstring(cfg.cases); cfg.cases = cellstr(cfg.cases); end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 140; end
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 128; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'skip_existing'); cfg.skip_existing = true; end
if ~isfield(cfg, 'do_train'); cfg.do_train = true; end
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('tcn', 'train_logs_theta10_uniform_h0_v2'));
end
end

function cases = local_build_cases(cfg)
cases = struct('case_name', {}, 'train_cfg', {});
for i = 1:numel(cfg.cases)
    name = char(cfg.cases{i});
    switch lower(name)
        case {'tcn96_rawtheta_sym','production_current_rawtheta_sym'}
            c = TCN_recommended_cfg('production_current');
            c.case_name = 'tcn96_rawtheta_sym';
        otherwise
            error('TCN:BadCase', 'Unknown TCN theta10 V2 case: %s', name);
    end

    c.max_epochs = cfg.max_epochs;
    c.batch_size = cfg.batch_size;
    c.use_gpu = cfg.use_gpu;
    c.verbose = cfg.verbose;
    if ~isfield(c, 'num_blocks'); c.num_blocks = 6; end
    if ~isfield(c, 'num_filters'); c.num_filters = 96; end
    if ~isfield(c, 'kernel_size'); c.kernel_size = 3; end
    if ~isfield(c, 'dropout'); c.dropout = 0.15; end
    c.initial_lr = 1e-3;
    c.grad_clip_mode = 'global';
    c.grad_clip = 5.0;
    c.class_weight_method = 'sqrt_inverse';
    c.turn_class_weight_method = 'sqrt_inverse';
    c.main_class_multipliers = [1.00 1.00 1.00];
    c.turn_class_multipliers = [1.08 1.00 1.08];
    c.lambda_turn = 0.08;
    c.lambda_theta = 0.55;
    c.lambda_theta_flat = 0.12;
    c.theta_flat_loss_mode = 'near_zero';
    c.theta_flat_zero_tol_deg = 0.3;
    c.theta_near_flat_deg = 0.5;
    c.lambda_aux = 0.00;
    c.lambda_phy = 0.00;
    c.lambda_smooth = 0.00;
    c.main_neg_slope_weight = 1.0;
    c.main_pos_slope_weight = 1.0;
    c.theta_neg_weight = 1.0;
    c.theta_pos_weight = 1.0;
    c.select_downhill_error_weight = 0.0;
    c.turn_priority_downhill_penalty_weight = 0.0;
    c.select_theta_weight = 0.30;
    c.select_theta_ref_deg = 2.0;
    c.select_theta_floor_deg = 1.00;
    c.turn_transition_weight = 1.25;
    c.base_selection_start_epoch = min(10, max(1, cfg.max_epochs));
    c.selection_start_epoch = min(64, max(1, cfg.max_epochs));
    c.early_stop_min_epochs = min(75, max(1, cfg.max_epochs));
    c.patience = 25;
    c.print_every = 5;

    cases(end+1) = struct('case_name', c.case_name, 'train_cfg', c); %#ok<AGROW>
end
end

function local_check_dataset_file(input_file)
if exist(input_file, 'file') ~= 2
    error('TCN:MissingDataset', 'Dataset not found: %s', input_file);
end
info = whos('-file', input_file);
names = {info.name};
if ~ismember('dataset', names)
    error('TCN:BadDatasetFile', 'Dataset file does not contain variable `dataset`: %s', input_file);
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
        'num_blocks','num_filters','kernel_size','dropout','head_pooling', ...
        'turn_head_type','turn_head_source','lambda_turn','lambda_theta', ...
        'lambda_theta_flat','theta_flat_loss_mode','theta_flat_zero_tol_deg', ...
        'theta_neg_weight','theta_pos_weight','main_neg_slope_weight', ...
        'main_pos_slope_weight','best_metric'};
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
row = struct('model', "TCN", 'case_name', "", 'seed', NaN, 'status', "", ...
    'best_epoch', NaN, 'base_best_epoch', NaN, 'train_seconds', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'turn_right_recall', NaN, 'turn_left_recall', NaN, ...
    'theta_mae_deg', NaN, 'theta_abs_le_10_p95_abs_err_deg', NaN, ...
    'theta_neg_10_8_p95_abs_err_deg', NaN, 'theta_pos_8_10_p95_abs_err_deg', NaN, ...
    'theta_neg_8_6_p95_abs_err_deg', NaN, 'theta_pos_6_8_p95_abs_err_deg', NaN, ...
    'theta_neg_2_0p5_p95_abs_err_deg', NaN, 'theta_pos_0p5_2_p95_abs_err_deg', NaN, ...
    'theta_near_flat_abs_p95_deg', NaN, 'theta_flat_abs_p95_deg', NaN, ...
    'theta_flat_bias_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'num_blocks', NaN, 'num_filters', NaN, 'kernel_size', NaN, 'head_pooling', "", ...
    'turn_head_type', "", 'turn_head_source', "", 'lambda_turn', NaN, ...
    'lambda_theta', NaN, 'lambda_theta_flat', NaN, 'theta_flat_loss_mode', "", ...
    'model_file', "", 'meta_file', "", 'report_file', "", 'error_message', "");
end

function row = local_planned_row(case_name, train_cfg)
row = local_empty_row();
row.case_name = string(case_name);
row.seed = train_cfg.seed;
row.status = "planned";
row = local_fill_cfg_fields(row, train_cfg);
end

function row = local_row_from_meta(case_name, train_cfg, meta, error_message)
m = meta.test_metrics;
row = local_empty_row();
row.case_name = string(case_name);
row.seed = train_cfg.seed;
row.status = "ok";
row.best_epoch = meta.best_epoch;
row.base_best_epoch = local_metric(meta, 'base_best_epoch');
row.train_seconds = meta.train_seconds;
row.acc_main = m.acc_main;
row.acc_turn = m.acc_turn;
row.acc_turn_pure = local_metric(m, 'acc_turn_pure');
row.acc_turn_transition = local_metric(m, 'acc_turn_transition');
row.turn_right_recall = m.recall_turn(1);
row.turn_left_recall = m.recall_turn(3);
row.theta_mae_deg = rad2deg(m.mae_theta);
row.theta_abs_le_10_p95_abs_err_deg = local_metric(m, 'theta_abs_le_10_p95_abs_err_deg');
row.theta_neg_10_8_p95_abs_err_deg = local_metric(m, 'theta_neg_10_8_p95_abs_err_deg');
row.theta_pos_8_10_p95_abs_err_deg = local_metric(m, 'theta_pos_8_10_p95_abs_err_deg');
row.theta_neg_8_6_p95_abs_err_deg = local_metric(m, 'theta_neg_8_6_p95_abs_err_deg');
row.theta_pos_6_8_p95_abs_err_deg = local_metric(m, 'theta_pos_6_8_p95_abs_err_deg');
row.theta_neg_2_0p5_p95_abs_err_deg = local_metric(m, 'theta_neg_2_0p5_p95_abs_err_deg');
row.theta_pos_0p5_2_p95_abs_err_deg = local_metric(m, 'theta_pos_0p5_2_p95_abs_err_deg');
row.theta_near_flat_abs_p95_deg = local_metric(m, 'theta_near_flat_abs_p95_deg');
row.theta_flat_abs_p95_deg = local_metric(m, 'theta_flat_abs_p95_deg');
row.theta_flat_bias_deg = local_metric(m, 'theta_flat_bias_deg');
row.flat_recall = m.recall_main(1);
row.stall_recall = m.recall_main(2);
row.slope_recall = m.recall_main(3);
row.uphill_recall = m.uphill.slope_recall;
row.downhill_recall = m.downhill.slope_recall;
row.flat_as_slope = m.cm_main(1, 3) / max(sum(m.cm_main(1, :)), 1);
row = local_fill_cfg_fields(row, train_cfg);
row.error_message = string(error_message);
end

function row = local_failed_row(case_name, train_cfg, ME)
row = local_empty_row();
row.case_name = string(case_name);
row.seed = train_cfg.seed;
row.status = "failed";
row = local_fill_cfg_fields(row, train_cfg);
row.error_message = string(ME.message);
end

function row = local_fill_cfg_fields(row, train_cfg)
row.num_blocks = train_cfg.num_blocks;
row.num_filters = train_cfg.num_filters;
row.kernel_size = train_cfg.kernel_size;
row.head_pooling = string(train_cfg.head_pooling);
row.turn_head_type = string(train_cfg.turn_head_type);
row.turn_head_source = string(train_cfg.turn_head_source);
row.lambda_turn = train_cfg.lambda_turn;
row.lambda_theta = train_cfg.lambda_theta;
row.lambda_theta_flat = train_cfg.lambda_theta_flat;
row.theta_flat_loss_mode = string(train_cfg.theta_flat_loss_mode);
row.model_file = string(train_cfg.model_file);
row.meta_file = string(train_cfg.meta_file);
row.report_file = string(train_cfg.report_file);
end

function G = local_group_summary(T)
ok = strcmp(T.status, "ok");
T = T(ok, :);
metrics = {'acc_main','acc_turn','acc_turn_pure','acc_turn_transition', ...
    'turn_right_recall','turn_left_recall','theta_mae_deg', ...
    'theta_abs_le_10_p95_abs_err_deg','theta_neg_10_8_p95_abs_err_deg', ...
    'theta_pos_8_10_p95_abs_err_deg','theta_neg_2_0p5_p95_abs_err_deg', ...
    'theta_pos_0p5_2_p95_abs_err_deg','flat_recall','stall_recall', ...
    'slope_recall','uphill_recall','downhill_recall','flat_as_slope'};
if isempty(T)
    G = table();
    return;
end

case_names = unique(T.case_name, 'stable');
rows = repmat(struct('case_name', "", 'n', 0), numel(case_names), 1);
for i = 1:numel(case_names)
    rows(i).case_name = case_names(i);
    rows(i).n = nnz(T.case_name == case_names(i));
    m = T(T.case_name == case_names(i), :);
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
out_file = fullfile(cfg.base_log_dir, 'TCN_theta10_v2_multi_seed_summary_partial.csv');
writetable(T, out_file);
end

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    warning('TCN:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# TCN theta10 V2 Multi-Seed Report\n\n');
fprintf(fid, '- dataset: `%s`\n', summary.cfg.input_file);
fprintf(fid, '- run_tag: `%s`\n', summary.cfg.run_tag);
fprintf(fid, '- seeds: `%s`\n', mat2str(summary.cfg.seeds));
fprintf(fid, '- do_train: `%d`\n', double(summary.cfg.do_train));
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
        vals{j} = local_format_value(v);
    end
    fprintf(fid, '| %s |\n', strjoin(vals, ' | '));
end
end

function s = local_format_value(v)
if isstring(v) || ischar(v)
    s = char(string(v));
elseif isnumeric(v) || islogical(v)
    if isscalar(v)
        if isnan(double(v))
            s = 'NaN';
        elseif abs(double(v)) >= 1000
            s = sprintf('%.3f', double(v));
        else
            s = sprintf('%.6g', double(v));
        end
    else
        s = mat2str(v);
    end
else
    s = char(string(v));
end
s = strrep(s, '|', '\|');
end

function v = local_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function out = local_merge_cfg(base, override)
out = base;
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end

function s = local_clean_name(s)
s = regexprep(char(s), '[^\w]+', '_');
s = regexprep(s, '_+', '_');
s = regexprep(s, '^_|_$', '');
end
