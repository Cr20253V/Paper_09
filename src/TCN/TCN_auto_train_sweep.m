function summary = TCN_auto_train_sweep(cfg)
%TCN_AUTO_TRAIN_SWEEP 自动扫描 TCN 关键训练配置并汇总测试指标。
%
% 功能说明：
%   对若干组 TCN_train.m 配置进行串行完整训练，每组模型和报告使用独立
%   文件名保存。脚本会读取每次训练返回的 meta.test_metrics，汇总主工况、
%   转弯、上坡/下坡 recall、坡度 MAE 和综合评分，帮助快速判断下一步
%   应该调训练权重、预处理还是数据生成。
%
% 默认扫描内容：
%   - main_neg_slope_weight：负坡 slope 主分类样本权重。
%   - select_downhill_error_weight：复合选模中下坡 recall 惩罚权重。
%   - lambda_turn：转弯分类损失权重。
%   - turn_class_weight_method：转弯类别权重策略。
%
% 使用示例：
%   init_project;
%   summary = TCN_auto_train_sweep();
%
% 注意：
%   完整扫描会多次训练 TCN，耗时明显长于单次训练。若只想快速验证流程，
%   可设置 cfg.max_epochs = 5 或 cfg.use_gpu = false。

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
if ~isfield(cfg, 'run_tag'); cfg.run_tag = datestr(now, 'yyyymmdd_HHMMSS'); end
if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 80; end
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 64; end
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'neg_weights'); cfg.neg_weights = [2.0 3.0 4.0]; end
if ~isfield(cfg, 'downhill_weights'); cfg.downhill_weights = [0.05 0.15 0.25]; end
if ~isfield(cfg, 'lambda_turns'); cfg.lambda_turns = 0.30; end
if ~isfield(cfg, 'turn_weight_methods'); cfg.turn_weight_methods = {'sqrt_inverse'}; end
if ischar(cfg.turn_weight_methods) || isstring(cfg.turn_weight_methods)
    cfg.turn_weight_methods = cellstr(cfg.turn_weight_methods);
end
if ~isfield(cfg, 'base_log_dir')
    cfg.base_log_dir = results_dir(fullfile('tcn', 'sweeps', cfg.run_tag));
end
if ~exist(cfg.base_log_dir, 'dir')
    mkdir(cfg.base_log_dir);
end

rows = repmat(local_empty_row(), ...
    numel(cfg.neg_weights) * numel(cfg.downhill_weights) * ...
    numel(cfg.lambda_turns) * numel(cfg.turn_weight_methods), 1);
idx = 0;

for i = 1:numel(cfg.neg_weights)
    for j = 1:numel(cfg.downhill_weights)
        for p = 1:numel(cfg.lambda_turns)
            for q = 1:numel(cfg.turn_weight_methods)
        idx = idx + 1;
        turn_method = char(cfg.turn_weight_methods{q});
        case_name = sprintf('neg%.1f_down%.2f_turn%.2f_%s', ...
            cfg.neg_weights(i), cfg.downhill_weights(j), cfg.lambda_turns(p), turn_method);
        case_name = strrep(case_name, '.', 'p');
        case_name = regexprep(case_name, '[^A-Za-z0-9_]+', '_');
        case_dir = fullfile(cfg.base_log_dir, case_name);
        if ~exist(case_dir, 'dir')
            mkdir(case_dir);
        end

        train_cfg = struct();
        train_cfg.mode = 'physics_guided';
        train_cfg.max_epochs = cfg.max_epochs;
        train_cfg.batch_size = cfg.batch_size;
        train_cfg.use_gpu = cfg.use_gpu;
        train_cfg.verbose = cfg.verbose;
        train_cfg.main_neg_slope_weight = cfg.neg_weights(i);
        train_cfg.select_downhill_error_weight = cfg.downhill_weights(j);
        train_cfg.lambda_turn = cfg.lambda_turns(p);
        train_cfg.turn_class_weight_method = turn_method;
        train_cfg = local_copy_optional(train_cfg, cfg, { ...
            'best_metric', 'select_main_floor', 'select_theta_floor_deg', ...
            'select_downhill_floor', 'select_turn_error_weight', ...
            'turn_head_type', 'turn_head_hidden', 'turn_head_source', ...
            'turn_class_multipliers', 'turn_priority_main_penalty_weight', ...
            'turn_priority_theta_penalty_weight', 'turn_priority_downhill_penalty_weight', ...
            'turn_priority_loss_weight', 'turn_finetune_start_epoch', ...
            'turn_finetune_lambda_turn', 'turn_finetune_disable_other_losses', ...
            'selection_start_epoch', 'base_selection_start_epoch', 'early_stop_min_epochs', ...
            'base_best_metric', 'combine_base_and_turn_best', ...
            'grad_clip_mode', 'use_focal_loss', ...
            'focal_gamma_turn', 'lambda_theta', 'lambda_theta_flat', 'lambda_aux'});
        train_cfg.model_file = fullfile(root, 'data', 'models', sprintf('TCN_model_%s.mat', case_name));
        train_cfg.meta_file = fullfile(root, 'data', 'models', sprintf('TCN_meta_%s.mat', case_name));
        train_cfg.log_dir = case_dir;
        train_cfg.report_file = fullfile(case_dir, 'TCN_train_report.md');

        fprintf('\n[TCN sweep] %d/%d %s\n', idx, numel(rows), case_name);
        [~, meta] = TCN_train(train_cfg);
        rows(idx) = local_row_from_meta(case_name, train_cfg, meta);
            end
        end
    end
end

T = struct2table(rows);
T = sortrows(T, 'score', 'ascend');
summary = struct();
summary.cfg = cfg;
summary.table = T;
summary.best = T(1, :);
summary.output_file = fullfile(cfg.base_log_dir, 'TCN_auto_train_sweep_summary.csv');
summary.report_file = fullfile(cfg.base_log_dir, 'TCN_auto_train_sweep_report.md');

writetable(T, summary.output_file);
local_write_report(summary.report_file, summary);
if isfield(cfg, 'promote_best') && cfg.promote_best
    local_promote_best(summary.best);
end

fprintf('\n[TCN sweep] done\n');
fprintf('  summary: %s\n', summary.output_file);
fprintf('  report : %s\n', summary.report_file);
disp(T);
end

function dst = local_copy_optional(dst, src, names)
for i = 1:numel(names)
    name = names{i};
    if isfield(src, name)
        dst.(name) = src.(name);
    end
end
end

function row = local_empty_row()
row = struct('case_name', "", 'neg_weight', NaN, 'downhill_weight', NaN, ...
    'lambda_turn', NaN, 'turn_weight_method', "", ...
    'best_epoch', NaN, 'score', NaN, 'acc_main', NaN, 'acc_turn', NaN, ...
    'acc_turn_pure', NaN, 'acc_turn_transition', NaN, ...
    'theta_mae_deg', NaN, 'flat_recall', NaN, 'stall_recall', NaN, ...
    'slope_recall', NaN, 'uphill_recall', NaN, 'downhill_recall', NaN, ...
    'flat_as_slope', NaN, 'model_file', "", 'report_file', "");
end

function row = local_row_from_meta(case_name, train_cfg, meta)
m = meta.test_metrics;
row = local_empty_row();
row.case_name = string(case_name);
row.neg_weight = train_cfg.main_neg_slope_weight;
row.downhill_weight = train_cfg.select_downhill_error_weight;
row.lambda_turn = train_cfg.lambda_turn;
row.turn_weight_method = string(train_cfg.turn_class_weight_method);
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
row.model_file = string(train_cfg.model_file);
row.report_file = string(train_cfg.report_file);

% 越小越好：优先主工况，其次上下坡均衡、转弯与坡度 MAE。
row.score = (1 - row.acc_main) ...
    + 0.30 * (1 - row.acc_turn) ...
    + 0.30 * max(0, 0.85 - row.uphill_recall) ...
    + 0.30 * max(0, 0.85 - row.downhill_recall) ...
    + 0.04 * row.theta_mae_deg ...
    + 0.20 * row.flat_as_slope;
end

function v = local_get_metric(s, field_name)
if isstruct(s) && isfield(s, field_name)
    v = s.(field_name);
else
    v = NaN;
end
end

function local_write_report(report_file, summary)
fid = fopen(report_file, 'w');
if fid < 0
    error('TCN_auto_train_sweep:ReportFailed', '无法写入报告: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# TCN 自动训练扫描报告\n\n');
fprintf(fid, '- 生成时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- 输出 CSV: `%s`\n\n', summary.output_file);

T = summary.table;
fprintf(fid, '| case | score | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | flat->slope | turn w | turn method |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %.4f | %.4f | %.4f | %.4f | %.4f | %.3f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.3f | %s |\n', ...
        T.case_name(i), T.score(i), T.acc_main(i), T.acc_turn(i), ...
        T.acc_turn_pure(i), T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.flat_as_slope(i), ...
        T.lambda_turn(i), T.turn_weight_method(i));
end
end

function local_promote_best(best_row)
model_file = char(best_row.model_file(1));
case_name = char(best_row.case_name(1));
copyfile(model_file, fullfile(project_root(), 'data', 'models', 'TCN_model.mat'));
meta_file = strrep(model_file, 'TCN_model_', 'TCN_meta_');
copyfile(meta_file, fullfile(project_root(), 'data', 'models', 'TCN_meta.mat'));
fprintf('[TCN sweep] promoted best model: %s\n', case_name);
end
