function report = TCN_diagnose_dataset(cfg)
%TCN_DIAGNOSE_DATASET 诊断 TCN 数据集可分性、窗口纯度和传统模型基线。
%
% 功能说明：
%   读取 TCN_train_data_full.mat 与 TCN_dataset_processed.mat，统计滑窗标签
%   纯度，并用同一窗口数据构造简单统计特征训练传统分类器。该脚本不替代
%   TCN_train.m，只用于判断性能瓶颈来自数据/标签/预处理，还是来自 TCN
%   模型结构与训练策略。
%
% 诊断内容：
%   1. 窗口纯度：主工况与转弯标签在窗口内的一致比例，并统计转弯过渡窗口。
%   2. 主工况/转弯传统基线：last/mean/std/max/min 统计特征 + bagged trees。
%   3. 可选 ECOC 基线：若当前 MATLAB 环境支持 fitcecoc，则一并输出。
%   4. 输出 Markdown 报告，便于和 TCN_train_report.md 对照。
%
% 使用示例：
%   init_project;
%   report = TCN_diagnose_dataset();

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
if ~isfield(cfg, 'raw_file'); cfg.raw_file = fullfile(root, 'data', 'tcn', 'TCN_train_data_full.mat'); end
if ~isfield(cfg, 'dataset_file'); cfg.dataset_file = fullfile(root, 'data', 'tcn', 'TCN_dataset_processed.mat'); end
if ~isfield(cfg, 'report_file'); cfg.report_file = fullfile(results_dir('tcn/diagnostics'), 'TCN_dataset_diagnosis_report.md'); end
if ~isfield(cfg, 'num_trees'); cfg.num_trees = 150; end

Sraw = load(cfg.raw_file, 'data');
Sds = load(cfg.dataset_file, 'dataset');
data = Sraw.data;
dataset = Sds.dataset;

purity = local_window_purity(data, dataset);
[bag_acc, bag_cm] = local_bagged_tree_baseline(dataset, cfg, 'main');
[bag_turn_acc, bag_turn_cm] = local_bagged_tree_baseline(dataset, cfg, 'turn');
[ecoc_acc, ecoc_cm, ecoc_msg] = local_ecoc_baseline(dataset);

report = struct();
report.raw_file = cfg.raw_file;
report.dataset_file = cfg.dataset_file;
report.report_file = cfg.report_file;
report.purity = purity;
report.bagged_tree_acc = bag_acc;
report.bagged_tree_cm = bag_cm;
report.bagged_tree_turn_acc = bag_turn_acc;
report.bagged_tree_turn_cm = bag_turn_cm;
report.ecoc_acc = ecoc_acc;
report.ecoc_cm = ecoc_cm;
report.ecoc_msg = ecoc_msg;

local_write_report(cfg.report_file, report);

fprintf('[TCN diagnose] report: %s\n', cfg.report_file);
fprintf('[TCN diagnose] purity mean=%.3f, low<0.8=%.2f%%\n', ...
    purity.main.mean_all, 100 * purity.main.low_purity_ratio_all);
fprintf('[TCN diagnose] bagged trees main acc=%.4f\n', bag_acc);
fprintf('[TCN diagnose] bagged trees turn acc=%.4f\n', bag_turn_acc);
if isfinite(ecoc_acc)
    fprintf('[TCN diagnose] ECOC main acc=%.4f\n', ecoc_acc);
else
    fprintf('[TCN diagnose] ECOC skipped: %s\n', ecoc_msg);
end
end

function purity = local_window_purity(data, dataset)
seq_len = dataset.meta.seq_len;
stride = dataset.meta.stride;
skip_steps = round(dataset.meta.skip_initial_sec / dataset.meta.Ts);

main_vals = [];
main_end_labels = [];
turn_vals = [];
turn_end_labels = [];
turn_majority_labels = [];
turn_transition = [];
theta_ranges = [];

for k = 1:numel(data.runs)
    labels_main = data.runs(k).label_main(skip_steps+1:end);
    labels_turn = data.runs(k).label_turn(skip_steps+1:end);
    theta = data.runs(k).theta(skip_steps+1:end);
    N = numel(labels_main);
    if N < seq_len
        continue;
    end
    for start_idx = 1:stride:(N - seq_len + 1)
        end_idx = start_idx + seq_len - 1;
        w_main = labels_main(start_idx:end_idx);
        main_end_label = labels_main(end_idx);
        main_vals(end+1, 1) = mean(w_main == main_end_label); %#ok<AGROW>
        main_end_labels(end+1, 1) = main_end_label; %#ok<AGROW>

        w_turn = labels_turn(start_idx:end_idx);
        turn_end_label = labels_turn(end_idx);
        turn_majority_label = local_majority_label(w_turn);
        turn_vals(end+1, 1) = mean(w_turn == turn_end_label); %#ok<AGROW>
        turn_end_labels(end+1, 1) = turn_end_label; %#ok<AGROW>
        turn_majority_labels(end+1, 1) = turn_majority_label; %#ok<AGROW>
        turn_transition(end+1, 1) = numel(unique(w_turn(:))) > 1; %#ok<AGROW>
        theta_ranges(end+1, 1) = range(theta(start_idx:end_idx)); %#ok<AGROW>
    end
end

purity = struct();
purity.main = struct();
purity.main.n_windows = numel(main_vals);
purity.main.mean_all = mean(main_vals);
purity.main.median_all = median(main_vals);
purity.main.low_purity_ratio_all = mean(main_vals < 0.8);
purity.main.by_class = zeros(3, 4);
for c = 1:3
    m = main_end_labels == c;
    purity.main.by_class(c, :) = [sum(m), mean(main_vals(m)), mean(main_vals(m) < 0.8), rad2deg(mean(theta_ranges(m)))];
end

purity.turn = struct();
purity.turn.n_windows = numel(turn_vals);
purity.turn.mean_all = mean(turn_vals);
purity.turn.median_all = median(turn_vals);
purity.turn.low_purity_ratio_all = mean(turn_vals < 0.8);
purity.turn.transition_ratio_all = mean(turn_transition ~= 0);
purity.turn.end_vs_majority_diff_ratio = mean(turn_end_labels ~= turn_majority_labels);
purity.turn.by_class = zeros(3, 5);
turn_labels = [-1, 0, 1];
for i = 1:numel(turn_labels)
    m = turn_end_labels == turn_labels(i);
    purity.turn.by_class(i, :) = [sum(m), mean(turn_vals(m)), mean(turn_vals(m) < 0.8), ...
        mean(turn_transition(m) ~= 0), mean(turn_majority_labels(m) ~= turn_end_labels(m))];
end
end

function label = local_majority_label(x)
labels = [-1, 0, 1];
counts = arrayfun(@(v) sum(x == v), labels);
mx = max(counts);
ties = labels(counts == mx);
if numel(ties) == 1
    label = ties;
elseif any(ties == x(end))
    label = x(end);
elseif any(ties == 0)
    label = 0;
else
    label = ties(1);
end
end

function [acc, cm] = local_bagged_tree_baseline(dataset, cfg, task)
X_train = local_window_stats(dataset.X_train);
X_test = local_window_stats(dataset.X_test);
switch lower(char(task))
    case 'main'
        y_train = dataset.y_main_train(:);
        y_test = dataset.y_main_test(:);
        order = [1 2 3];
    case 'turn'
        y_train = dataset.y_turn_train(:);
        y_test = dataset.y_turn_test(:);
        order = [-1 0 1];
    otherwise
        error('TCN_diagnose_dataset:BadTask', 'Unknown baseline task: %s', task);
end

M = fitcensemble(X_train, y_train, 'Method', 'Bag', ...
    'NumLearningCycles', cfg.num_trees, 'Learners', 'tree');
pred = predict(M, X_test);
acc = mean(pred == y_test);
cm = confusionmat(y_test, pred, 'Order', order);
end

function [acc, cm, msg] = local_ecoc_baseline(dataset)
acc = NaN;
cm = NaN(3, 3);
msg = '';
try
    X_train = local_window_stats(dataset.X_train);
    X_test = local_window_stats(dataset.X_test);
    y_train = dataset.y_main_train(:);
    y_test = dataset.y_main_test(:);
    M = fitcecoc(X_train, y_train);
    pred = predict(M, X_test);
    acc = mean(pred == y_test);
    cm = confusionmat(y_test, pred, 'Order', [1 2 3]);
catch ME
    msg = ME.message;
end
end

function F = local_window_stats(X)
F = [squeeze(X(:, end, :)), ...
     squeeze(mean(X, 2)), ...
     squeeze(std(X, 0, 2)), ...
     squeeze(max(X, [], 2)), ...
     squeeze(min(X, [], 2))];
end

function local_write_report(report_file, report)
out_dir = fileparts(report_file);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
fid = fopen(report_file, 'w');
if fid < 0
    error('TCN_diagnose_dataset:ReportFailed', '无法写入报告: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# TCN 数据集诊断报告\n\n');
fprintf(fid, '- Raw file: `%s`\n', report.raw_file);
fprintf(fid, '- Dataset file: `%s`\n\n', report.dataset_file);

fprintf(fid, '## 窗口纯度\n\n');
fprintf(fid, '### 主工况\n\n');
fprintf(fid, '- 窗口数: %d\n', report.purity.main.n_windows);
fprintf(fid, '- 平均纯度: %.4f\n', report.purity.main.mean_all);
fprintf(fid, '- 中位数纯度: %.4f\n', report.purity.main.median_all);
fprintf(fid, '- 低纯度窗口比例 `<0.8`: %.4f\n\n', report.purity.main.low_purity_ratio_all);
fprintf(fid, '| class | windows | mean purity | low purity ratio | theta range mean deg |\n');
fprintf(fid, '|---|---:|---:|---:|---:|\n');
names = {'flat','stall','slope'};
for c = 1:3
    fprintf(fid, '| %s | %d | %.4f | %.4f | %.4f |\n', names{c}, ...
        report.purity.main.by_class(c, 1), report.purity.main.by_class(c, 2), ...
        report.purity.main.by_class(c, 3), report.purity.main.by_class(c, 4));
end

fprintf(fid, '\n### 转弯方向\n\n');
fprintf(fid, '- 窗口数: %d\n', report.purity.turn.n_windows);
fprintf(fid, '- 平均纯度: %.4f\n', report.purity.turn.mean_all);
fprintf(fid, '- 中位数纯度: %.4f\n', report.purity.turn.median_all);
fprintf(fid, '- 低纯度窗口比例 `<0.8`: %.4f\n', report.purity.turn.low_purity_ratio_all);
fprintf(fid, '- 过渡窗口比例: %.4f\n', report.purity.turn.transition_ratio_all);
fprintf(fid, '- 末端标签与多数标签不一致比例: %.4f\n\n', report.purity.turn.end_vs_majority_diff_ratio);
fprintf(fid, '| class | windows | mean purity | low purity ratio | transition ratio | end != majority |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|\n');
turn_names = {'right','straight','left'};
for c = 1:3
    fprintf(fid, '| %s | %d | %.4f | %.4f | %.4f | %.4f |\n', turn_names{c}, ...
        report.purity.turn.by_class(c, 1), report.purity.turn.by_class(c, 2), ...
        report.purity.turn.by_class(c, 3), report.purity.turn.by_class(c, 4), ...
        report.purity.turn.by_class(c, 5));
end

fprintf(fid, '\n## 传统模型可分性基线\n\n');
fprintf(fid, '- Bagged trees 主工况准确率: %.4f\n', report.bagged_tree_acc);
fprintf(fid, '- Bagged trees 转弯准确率: %.4f\n', report.bagged_tree_turn_acc);
fprintf(fid, '- ECOC 主工况准确率: %.4f\n', report.ecoc_acc);
if ~isempty(report.ecoc_msg)
    fprintf(fid, '- ECOC 备注: `%s`\n', report.ecoc_msg);
end

fprintf(fid, '\n### Bagged Trees 混淆矩阵\n\n');
fprintf(fid, '| true \\ pred | flat | stall | slope |\n|---|---:|---:|---:|\n');
for c = 1:3
    fprintf(fid, '| %s | %d | %d | %d |\n', names{c}, ...
        report.bagged_tree_cm(c, 1), report.bagged_tree_cm(c, 2), report.bagged_tree_cm(c, 3));
end

fprintf(fid, '\n### Bagged Trees 转弯混淆矩阵\n\n');
fprintf(fid, '| true \\ pred | right | straight | left |\n|---|---:|---:|---:|\n');
for c = 1:3
    fprintf(fid, '| %s | %d | %d | %d |\n', turn_names{c}, ...
        report.bagged_tree_turn_cm(c, 1), report.bagged_tree_turn_cm(c, 2), report.bagged_tree_turn_cm(c, 3));
end
end
