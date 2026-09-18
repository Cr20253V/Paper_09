function summary = TCN_auto_experiment_pipeline(cfg)
%TCN_AUTO_EXPERIMENT_PIPELINE 自动执行 TCN 主工况恢复与转弯增强实验。
%
% 功能说明：
%   当前 TCN 实验已经证明转弯头可通过 inputstats+MLP 提升到 90% 左右，
%   但主工况基座在若干配置下掉到 85%~88%。本脚本用于批量运行有
%   明确目的的候选配置，避免手工反复试验：
%     1. main_recovery：优先恢复主工况/坡度的基座配置。
%     2. turn_enhanced：在可接受基座上测试 inputstats 转弯头。
%     3. staged_combo：主任务基座 + 转弯头微调的组合 checkpoint。
%
% 使用示例：
%   init_project;
%   cfg = struct;
%   cfg.max_epochs = 90;
%   cfg.batch_size = 64;
%   cfg.use_gpu = true;
%   summary = TCN_auto_experiment_pipeline(cfg);

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
    fprintf('\n[TCN pipeline] %d/%d %s\n', i, numel(cases), c.case_name);
    case_dir = fullfile(cfg.base_log_dir, c.case_name);
    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end

    artifact_name = local_clean_name(sprintf('%s_%s', cfg.run_tag, c.case_name));
    train_cfg = local_merge_cfg(c.train_cfg, struct( ...
        'model_file', fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', artifact_name)), ...
        'meta_file', fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', artifact_name)), ...
        'log_dir', case_dir, ...
        'report_file', fullfile(case_dir, 'TCN_train_report.md')));

    if cfg.skip_existing && exist(train_cfg.meta_file, 'file') && local_existing_meta_matches(train_cfg.meta_file, train_cfg)
        S = load(train_cfg.meta_file, 'meta');
        meta = S.meta;
        fprintf('[TCN pipeline] skip existing: %s\n', train_cfg.meta_file);
    else
        [~, meta] = TCN_train(train_cfg);
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
summary.output_file = fullfile(cfg.base_log_dir, 'TCN_auto_experiment_pipeline_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'TCN_auto_experiment_pipeline_report.md');
writetable(T, summary.output_file);
local_write_report(summary.report_file, summary);

if cfg.promote_best
    local_promote_best(summary.best);
end

fprintf('\n[TCN pipeline] done\n');
fprintf('  summary: %s\n', summary.output_file);
fprintf('  report : %s\n', summary.report_file);
disp(T);
end

function cfg = local_defaults(cfg)
if ~isfield(cfg, 'run_tag'); cfg.run_tag = datestr(now, 'yyyymmdd_HHMMSS'); end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 90; end
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 64; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'skip_existing'); cfg.skip_existing = true; end
if ~isfield(cfg, 'promote_best'); cfg.promote_best = false; end
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('tcn', 'experiments', cfg.run_tag));
end
if ~isfield(cfg, 'case_filter'); cfg.case_filter = {}; end
if ~isfield(cfg, 'main_recovery_neg_weights'); cfg.main_recovery_neg_weights = [2.0 4.0]; end
if ~isfield(cfg, 'main_recovery_downhill_weights'); cfg.main_recovery_downhill_weights = [0.15 0.25]; end
if ~isfield(cfg, 'main_recovery_lambda_turns'); cfg.main_recovery_lambda_turns = [0.00 0.05 0.10 0.20]; end
if ~isfield(cfg, 'main_recovery_grad_clip_modes'); cfg.main_recovery_grad_clip_modes = {'global','separate'}; end
if ~isfield(cfg, 'main_recovery_turn_heads'); cfg.main_recovery_turn_heads = {'linear_readout'}; end
if ischar(cfg.case_filter) || isstring(cfg.case_filter)
    cfg.case_filter = cellstr(cfg.case_filter);
end
end

function cases = local_build_cases(cfg)
base = struct();
base.mode = 'physics_guided';
base.max_epochs = cfg.max_epochs;
base.batch_size = cfg.batch_size;
base.use_gpu = cfg.use_gpu;
base.verbose = cfg.verbose;
base.head_pooling = 'last_mean_max_inputstats';
base.turn_class_weight_method = 'none';
base.best_metric = 'composite';
base.grad_clip_mode = 'global';
base.main_neg_slope_weight = 4.0;
base.select_downhill_error_weight = 0.25;
base.lambda_turn = 0.20;

cases = struct('case_name', {}, 'phase', {}, 'train_cfg', {});

for iw = 1:numel(cfg.main_recovery_neg_weights)
    for idw = 1:numel(cfg.main_recovery_downhill_weights)
        for ilt = 1:numel(cfg.main_recovery_lambda_turns)
            for ig = 1:numel(cfg.main_recovery_grad_clip_modes)
                for ih = 1:numel(cfg.main_recovery_turn_heads)
                    [turn_head_type, turn_head_source] = local_parse_turn_head(cfg.main_recovery_turn_heads{ih});
                    case_name = sprintf('main_neg%.1f_down%.2f_turn%.2f_%s_%s', ...
                        cfg.main_recovery_neg_weights(iw), ...
                        cfg.main_recovery_downhill_weights(idw), ...
                        cfg.main_recovery_lambda_turns(ilt), ...
                        cfg.main_recovery_grad_clip_modes{ig}, ...
                        cfg.main_recovery_turn_heads{ih});
                    case_name = local_clean_name(case_name);
                    cases(end+1) = local_case(case_name, 'main_recovery', local_merge_cfg(base, struct( ...
                        'turn_head_type', turn_head_type, ...
                        'turn_head_source', turn_head_source, ...
                        'main_neg_slope_weight', cfg.main_recovery_neg_weights(iw), ...
                        'select_downhill_error_weight', cfg.main_recovery_downhill_weights(idw), ...
                        'lambda_turn', cfg.main_recovery_lambda_turns(ilt), ...
                        'grad_clip_mode', cfg.main_recovery_grad_clip_modes{ig}, ...
                        'best_metric', 'composite'))); %#ok<AGROW>
                end
            end
        end
    end
end

cases(end+1) = local_case('turn_inputstats_composite', 'turn_enhanced', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.10 1.0], ...
    'lambda_turn', 0.05)));

cases(end+1) = local_case('turn_inputstats_lam010', 'turn_enhanced', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.10 1.0], ...
    'lambda_turn', 0.10)));

cases(end+1) = local_case('turn_inputstats_lam020', 'turn_enhanced', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.00 1.0], ...
    'lambda_turn', 0.20)));

cases(end+1) = local_case('staged_bestbase_inputstats_turn_lam050', 'staged_combo', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.10 1.0], ...
    'lambda_turn', 0.05, ...
    'turn_finetune_start_epoch', 64, ...
    'turn_finetune_lambda_turn', 0.50, ...
    'turn_finetune_disable_other_losses', true, ...
    'base_best_metric', 'composite', ...
    'combine_base_and_turn_best', true, ...
    'best_metric', 'turn_priority', ...
    'selection_start_epoch', 60, ...
    'early_stop_min_epochs', 75, ...
    'select_main_floor', 0.92, ...
    'select_theta_floor_deg', 1.20, ...
    'select_downhill_floor', 0.80)));

cases(end+1) = local_case('staged_bestbase_inputstats_turn_lam030', 'staged_combo', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.00 1.0], ...
    'lambda_turn', 0.10, ...
    'turn_finetune_start_epoch', 64, ...
    'turn_finetune_lambda_turn', 0.30, ...
    'turn_finetune_disable_other_losses', true, ...
    'base_best_metric', 'composite', ...
    'combine_base_and_turn_best', true, ...
    'best_metric', 'turn_priority', ...
    'selection_start_epoch', 64, ...
    'early_stop_min_epochs', 75, ...
    'select_main_floor', 0.92, ...
    'select_theta_floor_deg', 1.20, ...
    'select_downhill_floor', 0.80)));

cases(end+1) = local_case('pg_full_inputstats_turn_lam050', 'physics_guided_full', local_merge_cfg(base, struct( ...
    'turn_head_type', 'mlp', ...
    'turn_head_source', 'inputstats', ...
    'turn_head_hidden', 64, ...
    'turn_class_multipliers', [1.0 1.10 1.0], ...
    'lambda_turn', 0.05, ...
    'lambda_theta', 0.35, ...
    'lambda_theta_flat', 0.20, ...
    'lambda_aux', 0.15, ...
    'lambda_phy', 0.002, ...
    'lambda_smooth', 0.003, ...
    'turn_transition_weight', 1.25, ...
    'phy_pitch_threshold_deg', 1.00, ...
    'phy_turn_signal_threshold', 0.010, ...
    'phy_turn_gyro_weight', 0.25, ...
    'phy_theta_mag_weight', 0.25, ...
    'turn_finetune_start_epoch', 64, ...
    'turn_finetune_lambda_turn', 0.50, ...
    'turn_finetune_disable_other_losses', true, ...
    'base_best_metric', 'composite', ...
    'combine_base_and_turn_best', true, ...
    'best_metric', 'turn_priority', ...
    'selection_start_epoch', 64, ...
    'early_stop_min_epochs', 75, ...
    'select_main_floor', 0.92, ...
    'select_theta_floor_deg', 1.20, ...
    'select_downhill_floor', 0.80)));

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
c = struct();
c.case_name = case_name;
c.phase = phase;
c.train_cfg = train_cfg;
end

function tf = local_existing_meta_matches(meta_file, train_cfg)
tf = false;
try
    S = load(meta_file, 'meta');
    if ~isfield(S, 'meta') || ~isfield(S.meta, 'cfg')
        return;
    end
    old = S.meta.cfg;
    keys = {'max_epochs','batch_size','use_gpu','main_neg_slope_weight', ...
        'select_downhill_error_weight','lambda_turn','turn_head_type', ...
        'turn_head_source','grad_clip_mode','best_metric','lambda_phy', ...
        'lambda_smooth','turn_transition_weight'};
    for i = 1:numel(keys)
        k = keys{i};
        if isfield(train_cfg, k)
            if ~isfield(old, k) || ~isequaln(old.(k), train_cfg.(k))
                return;
            end
        end
    end
    tf = true;
catch
    tf = false;
end
end

function [turn_head_type, turn_head_source] = local_parse_turn_head(spec)
switch lower(char(spec))
    case 'linear_readout'
        turn_head_type = 'linear';
        turn_head_source = 'readout';
    case 'mlp_inputstats'
        turn_head_type = 'mlp';
        turn_head_source = 'inputstats';
    case 'mlp_readout'
        turn_head_type = 'mlp';
        turn_head_source = 'readout';
    otherwise
        error('TCN_auto_experiment_pipeline:BadTurnHeadSpec', 'Unknown turn head spec: %s', spec);
end
end

function name = local_clean_name(name)
name = strrep(name, '.', 'p');
name = regexprep(name, '[^A-Za-z0-9_]+', '_');
end

function dst = local_merge_cfg(a, b)
dst = a;
names = fieldnames(b);
for i = 1:numel(names)
    dst.(names{i}) = b.(names{i});
end
end

function row = local_empty_row()
row = struct('case_name', "", 'phase', "", 'best_epoch', NaN, ...
    'base_best_epoch', NaN, 'production_score', NaN, 'main_score', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'acc_turn_pure', NaN, ...
    'acc_turn_transition', NaN, 'theta_mae_deg', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'turn_head_type', "", 'turn_head_source', "", 'lambda_turn', NaN, ...
    'grad_clip_mode', "", 'model_file', "", 'report_file', "");
end

function row = local_row_from_meta(c, train_cfg, meta)
m = meta.test_metrics;
row = local_empty_row();
row.case_name = string(c.case_name);
row.phase = string(c.phase);
row.best_epoch = meta.best_epoch;
row.base_best_epoch = local_get_metric(meta, 'base_best_epoch');
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
row.turn_head_type = string(local_get_cfg(train_cfg, 'turn_head_type', ''));
row.turn_head_source = string(local_get_cfg(train_cfg, 'turn_head_source', ''));
row.lambda_turn = local_get_cfg(train_cfg, 'lambda_turn', NaN);
row.grad_clip_mode = string(local_get_cfg(train_cfg, 'grad_clip_mode', ''));
row.model_file = string(train_cfg.model_file);
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

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    error('TCN_auto_experiment_pipeline:ReportFailed', '无法写入报告: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# TCN 自动实验流水线报告\n\n');
fprintf(fid, '- 生成时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- 输出 CSV: `%s`\n\n', summary.output_file);

T = summary.table;
fprintf(fid, '| case | phase | prod score | main score | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | flat->slope | head | source | turn w |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %s | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.3f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %s | %s | %.3f |\n', ...
        T.case_name(i), T.phase(i), T.production_score(i), T.main_score(i), ...
        T.acc_main(i), T.acc_turn(i), T.acc_turn_pure(i), T.acc_turn_transition(i), ...
        T.theta_mae_deg(i), T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.flat_as_slope(i), ...
        T.turn_head_type(i), T.turn_head_source(i), T.lambda_turn(i));
end
end

function local_promote_best(best_row)
model_file = char(best_row.model_file(1));
case_name = char(best_row.case_name(1));
copyfile(model_file, fullfile(project_root(), 'data', 'models', 'TCN_model.mat'));
meta_file = strrep(model_file, 'TCN_model_', 'TCN_meta_');
copyfile(meta_file, fullfile(project_root(), 'data', 'models', 'TCN_meta.mat'));
fprintf('[TCN pipeline] promoted best model: %s\n', case_name);
end
