function summary = TCN_pg_auto_experiment_pipeline(cfg)
%TCN_PG_AUTO_EXPERIMENT_PIPELINE 自动扫 physics-guided TCN 关键权重。
%
% 该流水线只面向 PG-TCN 的小范围诊断：lambda_phy、lambda_smooth、
% turn_transition_weight 以及 staged turn finetune。第一阶段结果表明
% 非 staged PG-base 会显著损伤主工况，因此默认围绕当前已验证的
% staged TCN 基座做保守搜索。

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
    fprintf('\n[TCN PG sweep] %d/%d %s\n', i, numel(cases), c.case_name);
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
        fprintf('[TCN PG sweep] skip existing: %s\n', train_cfg.meta_file);
    else
        [~, meta] = TCN_train(train_cfg);
    end
    rows(i) = local_row_from_meta(c, train_cfg, meta);
end

T = struct2table(rows);
T = sortrows(T, {'pg_score','production_score'}, {'ascend','ascend'});

summary = struct();
summary.cfg = cfg;
summary.cases = cases;
summary.table = T;
summary.best = T(1, :);
summary.output_file = fullfile(cfg.base_log_dir, 'TCN_pg_auto_experiment_pipeline_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'TCN_pg_auto_experiment_pipeline_report.md');
writetable(T, summary.output_file);
local_write_report(summary.report_file, summary);

fprintf('\n[TCN PG sweep] done\n');
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
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('tcn', 'experiments', cfg.run_tag));
end
if ~isfield(cfg, 'case_filter'); cfg.case_filter = {}; end
if ~isfield(cfg, 'base_modes'); cfg.base_modes = {'production_current'}; end
if ~isfield(cfg, 'seeds'); cfg.seeds = 42; end
if ~isfield(cfg, 'lambda_phys'); cfg.lambda_phys = [0 0.001 0.002 0.005]; end
if ~isfield(cfg, 'lambda_smooths'); cfg.lambda_smooths = [0 0.001 0.003]; end
if ~isfield(cfg, 'turn_transition_weights'); cfg.turn_transition_weights = [1.0 1.25]; end
if ~isfield(cfg, 'use_staged_options'); cfg.use_staged_options = true; end
if ~isfield(cfg, 'score_main_floor'); cfg.score_main_floor = 0.92; end
if ~isfield(cfg, 'score_slope_floor'); cfg.score_slope_floor = 0.88; end
if ~isfield(cfg, 'score_turn_floor'); cfg.score_turn_floor = 0.89; end
if ~isfield(cfg, 'score_transition_floor'); cfg.score_transition_floor = 0.60; end
if ischar(cfg.case_filter) || isstring(cfg.case_filter)
    cfg.case_filter = cellstr(cfg.case_filter);
end
if ischar(cfg.base_modes) || isstring(cfg.base_modes)
    cfg.base_modes = cellstr(cfg.base_modes);
end
cfg.seeds = cfg.seeds(:)';
end

function cases = local_build_cases(cfg)
cases = struct('case_name', {}, 'phase', {}, 'train_cfg', {});
for ib = 1:numel(cfg.base_modes)
    base_mode = char(cfg.base_modes{ib});
    base = TCN_recommended_cfg(base_mode);
    base.max_epochs = cfg.max_epochs;
    base.batch_size = cfg.batch_size;
    base.use_gpu = cfg.use_gpu;
    base.verbose = cfg.verbose;
    base.lambda_aux = 0.15;
    base.lambda_pitch_consistency = 0.00;

    for ip = 1:numel(cfg.lambda_phys)
        for is = 1:numel(cfg.lambda_smooths)
            for iw = 1:numel(cfg.turn_transition_weights)
                for istaged = 1:numel(cfg.use_staged_options)
                    for iseed = 1:numel(cfg.seeds)
                train_cfg = local_merge_cfg(base, struct( ...
                    'seed', cfg.seeds(iseed), ...
                    'lambda_phy', cfg.lambda_phys(ip), ...
                    'lambda_smooth', cfg.lambda_smooths(is), ...
                    'turn_transition_weight', cfg.turn_transition_weights(iw), ...
                    'score_cfg', struct( ...
                        'main_floor', cfg.score_main_floor, ...
                        'slope_floor', cfg.score_slope_floor, ...
                        'turn_floor', cfg.score_turn_floor, ...
                        'transition_floor', cfg.score_transition_floor)));
                if cfg.use_staged_options(istaged)
                    train_cfg.turn_finetune_start_epoch = 64;
                    train_cfg.turn_finetune_lambda_turn = 0.50;
                    train_cfg.turn_finetune_disable_other_losses = true;
                    train_cfg.base_best_metric = 'composite';
                    train_cfg.combine_base_and_turn_best = true;
                    train_cfg.best_metric = 'turn_priority';
                    train_cfg.selection_start_epoch = 64;
                    train_cfg.early_stop_min_epochs = 75;
                    phase = 'pg_staged';
                    staged_name = 'staged';
                else
                    train_cfg.turn_finetune_start_epoch = inf;
                    train_cfg.combine_base_and_turn_best = false;
                    train_cfg.best_metric = 'composite';
                    train_cfg.selection_start_epoch = 1;
                    train_cfg.early_stop_min_epochs = min(45, max(30, floor(0.5 * cfg.max_epochs)));
                    phase = 'pg_base';
                    staged_name = 'base';
                end
                seed_suffix = '';
                if numel(cfg.seeds) > 1
                    seed_suffix = sprintf('_seed%d', cfg.seeds(iseed));
                end
                case_name = sprintf('%s_phy%.3f_smooth%.3f_trans%.2f_%s%s', ...
                    base_mode, cfg.lambda_phys(ip), cfg.lambda_smooths(is), ...
                    cfg.turn_transition_weights(iw), staged_name, seed_suffix);
                cases(end+1) = local_case(local_clean_name(case_name), phase, train_cfg); %#ok<AGROW>
                    end
                end
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
    keys = {'max_epochs','batch_size','use_gpu','seed','lambda_phy','lambda_smooth', ...
        'turn_transition_weight','turn_finetune_start_epoch','best_metric', ...
        'combine_base_and_turn_best'};
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
row = struct('case_name', "", 'phase', "", 'best_epoch', NaN, ...
    'base_best_epoch', NaN, 'pg_score', NaN, 'production_score', NaN, ...
    'main_score', NaN, 'acc_main', NaN, 'acc_turn', NaN, ...
    'acc_turn_pure', NaN, 'acc_turn_transition', NaN, ...
    'theta_mae_deg', NaN, 'flat_recall', NaN, 'stall_recall', NaN, ...
    'slope_recall', NaN, 'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'flat_as_slope', NaN, 'lambda_phy', NaN, 'lambda_smooth', NaN, ...
    'turn_transition_weight', NaN, 'seed', NaN, 'staged', false, ...
    'model_file', "", 'report_file', "");
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
row.lambda_phy = local_get_cfg(train_cfg, 'lambda_phy', NaN);
row.lambda_smooth = local_get_cfg(train_cfg, 'lambda_smooth', NaN);
row.turn_transition_weight = local_get_cfg(train_cfg, 'turn_transition_weight', NaN);
row.seed = local_get_cfg(train_cfg, 'seed', NaN);
row.staged = isfinite(local_get_cfg(train_cfg, 'turn_finetune_start_epoch', inf));
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
score_cfg = local_get_cfg(train_cfg, 'score_cfg', struct());
main_floor = local_get_cfg(score_cfg, 'main_floor', 0.92);
slope_floor = local_get_cfg(score_cfg, 'slope_floor', 0.88);
turn_floor = local_get_cfg(score_cfg, 'turn_floor', 0.89);
transition_floor = local_get_cfg(score_cfg, 'transition_floor', 0.60);
row.pg_score = row.production_score ...
    + 3.00 * max(0, main_floor - row.acc_main) ...
    + 2.00 * max(0, slope_floor - row.slope_recall) ...
    + 0.50 * max(0, turn_floor - row.acc_turn) ...
    + 0.30 * max(0, 0.80 - row.stall_recall) ...
    + 0.30 * max(0, transition_floor - row.acc_turn_transition) ...
    + 0.03 * max(0, row.theta_mae_deg - 0.80);
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
    error('TCN_pg_auto_experiment_pipeline:ReportFailed', 'Cannot write report: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# TCN PG 自动实验流水线报告\n\n');
fprintf(fid, '- 生成时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- 输出 CSV: `%s`\n\n', summary.output_file);
T = summary.table;
fprintf(fid, '| case | phase | seed | pg score | prod score | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | phy | smooth | trans w | staged |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %s | %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.2f | %d |\n', ...
        T.case_name(i), T.phase(i), T.seed(i), T.pg_score(i), T.production_score(i), ...
        T.acc_main(i), T.acc_turn(i), T.acc_turn_pure(i), T.acc_turn_transition(i), ...
        T.theta_mae_deg(i), T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.lambda_phy(i), ...
        T.lambda_smooth(i), T.turn_transition_weight(i), T.staged(i));
end
end
