function analysis = analyze_compare_mamba2_gru_imu_stats(cfg)
% =============================
% 文件名：analyze_compare_mamba2_gru_imu_stats.m
% 版本号：V1.1（统计分析与报告输出）
% 最后修改时间：2026-04-17
% 作者：LPV-MPC Project
% 功能描述：
%   对 run_compare_mamba2_gru_imu_batch 产出的 case_rows 进行统计分析，
%   自动输出：
%   1) 按控制器汇总表（均值/标准差/分位数）
%   2) Friedman 多组检验
%   3) 两两 Wilcoxon 符号秩检验 + Holm 校正
%   4) 效应量（配对 Cohen's d、Cliff's delta）
%   5) 图形（箱线图 + CDF）与 Markdown 报告
%
% 使用方法：
%   analysis = analyze_compare_mamba2_gru_imu_stats();
%   analysis = analyze_compare_mamba2_gru_imu_stats(cfg);
%
% 输入 cfg 字段：
%   cfg.input_mat   : case_rows.mat 完整路径（可省略，自动取最新）
%   cfg.controllers : 控制器顺序（默认 Mamba2/GRU/IMU）
%   cfg.metrics     : 分析指标列表
%
% 输出：
%   - analysis 结构体
%   - analysis_summary.mat / analysis_report.md / *.csv / plot_*.png
% =============================

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_apply_defaults(cfg, root);

if ~exist(cfg.input_mat, 'file')
    error('Input file not found: %s', cfg.input_mat);
end

S = load(cfg.input_mat);
if isfield(S, 'T') && istable(S.T)
    T = S.T;
elseif isfield(S, 'results') && isfield(S.results, 'rows')
    T = struct2table(S.results.rows);
else
    error('Invalid input file format. Expected T table or results.rows.');
end

ok = strcmp(T.status, 'ok');
T = T(ok, :);
if isempty(T)
    error('No successful cases found in input table.');
end

T.case_key = strcat(T.path_name, '|d', arrayfun(@num2str, T.disturbance_level, 'UniformOutput', false), ...
    '|s', arrayfun(@num2str, T.seed, 'UniformOutput', false));

in_dir = fileparts(cfg.input_mat);
out_dir = fullfile(fileparts(in_dir), 'analysis');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

summary_tbl = local_group_summary(T, cfg.controllers, cfg.metrics);
[pair_tbl, friedman_tbl] = local_stats_tables(T, cfg.controllers, cfg.metrics);

writetable(summary_tbl, fullfile(out_dir, 'summary_by_controller.csv'));
writetable(friedman_tbl, fullfile(out_dir, 'friedman_results.csv'));
writetable(pair_tbl, fullfile(out_dir, 'pairwise_signrank_holm.csv'));

local_plot_box_and_cdf(T, cfg.controllers, cfg.metrics, out_dir);

analysis = struct();
analysis.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
analysis.input_mat = cfg.input_mat;
analysis.out_dir = out_dir;
analysis.controllers = cfg.controllers;
analysis.metrics = cfg.metrics;
analysis.n_ok_cases = height(T);
analysis.summary_tbl = summary_tbl;
analysis.friedman_tbl = friedman_tbl;
analysis.pair_tbl = pair_tbl;

save(fullfile(out_dir, 'analysis_summary.mat'), 'analysis', '-v7.3');
local_write_markdown_report(analysis, fullfile(out_dir, 'analysis_report.md'));

fprintf('\n[analyze] done: %s\n', out_dir);

end

function cfg = local_apply_defaults(cfg, root)
if ~isfield(cfg, 'controllers') || isempty(cfg.controllers)
    cfg.controllers = {'Mamba2', 'GRU', 'IMU'};
end
if ~isfield(cfg, 'metrics') || isempty(cfg.metrics)
    cfg.metrics = {'ey_rmse', 'epsi_rmse', 'ev_rmse', 'eomega_rmse', ...
                   'j_du', 'viol_rate', 'timeout_rate'};
end
if ~isfield(cfg, 'input_mat') || isempty(cfg.input_mat)
    cfg.input_mat = local_pick_latest_case_rows(root);
end
end

function path_mat = local_pick_latest_case_rows(root)
base_dir = fullfile(root, 'results', 'compare', 'mamba2_gru_imu');
if ~exist(base_dir, 'dir')
    error('No compare result folder found: %s', base_dir);
end

files = dir(fullfile(base_dir, '**', 'raw', 'case_rows.mat'));
if isempty(files)
    error('No case_rows.mat found under %s', base_dir);
end

[~, idx] = max([files.datenum]);
path_mat = fullfile(files(idx).folder, files(idx).name);
end

function summary_tbl = local_group_summary(T, controllers, metrics)
rows = repmat(struct(), numel(controllers), 1);
for i = 1:numel(controllers)
    c = controllers{i};
    m = strcmp(T.controller, c);
    rows(i).controller = c;
    rows(i).n_cases = sum(m);
    for k = 1:numel(metrics)
        f = metrics{k};
        if ~ismember(f, T.Properties.VariableNames)
            rows(i).([f '_mean']) = NaN;
            rows(i).([f '_std']) = NaN;
            rows(i).([f '_median']) = NaN;
            rows(i).([f '_p25']) = NaN;
            rows(i).([f '_p75']) = NaN;
            continue;
        end
        v = T.(f)(m);
        rows(i).([f '_mean']) = local_nanmean(v);
        rows(i).([f '_std']) = local_nanstd(v);
        rows(i).([f '_median']) = local_percentile(v, 50);
        rows(i).([f '_p25']) = local_percentile(v, 25);
        rows(i).([f '_p75']) = local_percentile(v, 75);
    end
end
summary_tbl = struct2table(rows);
end

function [pair_tbl, friedman_tbl] = local_stats_tables(T, controllers, metrics)
% 对每个指标做：
%   - Friedman（>=3 个配对样本）
%   - 两两 signrank + Holm
pair_rows = [];
friedman_rows = [];

for k = 1:numel(metrics)
    metric = metrics{k};
    if ~ismember(metric, T.Properties.VariableNames)
        continue;
    end

    [X, case_keys] = local_build_paired_matrix(T, controllers, metric);
    n_pair = size(X, 1);

    fr = struct();
    fr.metric = metric;
    fr.n_paired_cases = n_pair;
    fr.friedman_p = NaN;

    if n_pair >= 3
        try
            fr.friedman_p = friedman(X, 1, 'off');
        catch
            fr.friedman_p = NaN;
        end
    end
    friedman_rows = [friedman_rows; fr]; %#ok<AGROW>

    pvals = [];
    pair_idx = [];
    temp_pairs = [];

    for i = 1:numel(controllers)
        for j = i+1:numel(controllers)
            a = X(:, i);
            b = X(:, j);
            valid = isfinite(a) & isfinite(b);
            a = a(valid);
            b = b(valid);
            d = a - b;

            pr = struct();
            pr.metric = metric;
            pr.ctrl_a = controllers{i};
            pr.ctrl_b = controllers{j};
            pr.n = numel(d);
            pr.p_raw = NaN;
            pr.p_holm = NaN;
            pr.cohen_d_paired = NaN;
            pr.cliff_delta = NaN;
            pr.median_diff_a_minus_b = NaN;

            if pr.n >= 3
                try
                    pr.p_raw = signrank(a, b);
                catch
                    pr.p_raw = NaN;
                end
                pr.cohen_d_paired = local_cohen_d_paired(d);
                pr.cliff_delta = local_cliff_from_diff(d);
                pr.median_diff_a_minus_b = local_percentile(d, 50);
            end

            temp_pairs = [temp_pairs; pr]; %#ok<AGROW>
            pair_idx = [pair_idx; numel(temp_pairs)]; %#ok<AGROW>
            pvals = [pvals; pr.p_raw]; %#ok<AGROW>
        end
    end

    p_holm = local_holm_adjust(pvals);
    for ii = 1:numel(pair_idx)
        temp_pairs(pair_idx(ii)).p_holm = p_holm(ii);
    end

    pair_rows = [pair_rows; temp_pairs]; %#ok<AGROW>

    % Keep case_keys used so the variable is not optimized away in old MATLAB.
    if isempty(case_keys)
        % no-op
    end
end

pair_tbl = struct2table(pair_rows);
friedman_tbl = struct2table(friedman_rows);
end

function [X, case_keys] = local_build_paired_matrix(T, controllers, metric)
% 将同一 case_key 下各控制器指标对齐为配对矩阵：
% X(row, col) = 指标值（row: 同场景同种子；col: 控制器）
all_keys = unique(T.case_key, 'stable');
X = NaN(numel(all_keys), numel(controllers));

for r = 1:numel(all_keys)
    key = all_keys{r};
    tk = T(strcmp(T.case_key, key), :);
    for c = 1:numel(controllers)
        m = strcmp(tk.controller, controllers{c});
        vals = tk.(metric)(m);
        if isempty(vals)
            X(r, c) = NaN;
        else
            X(r, c) = vals(1);
        end
    end
end

valid_row = all(isfinite(X), 2);
X = X(valid_row, :);
case_keys = all_keys(valid_row);
end

function p_adj = local_holm_adjust(pvals)
p_adj = NaN(size(pvals));
valid = isfinite(pvals);
if ~any(valid)
    return;
end

pv = pvals(valid);
[ps, ord] = sort(pv);
m = numel(ps);
adj_sorted = NaN(size(ps));
for i = 1:m
    adj_sorted(i) = min(1, (m - i + 1) * ps(i));
end

% Enforce monotonicity
for i = 2:m
    if adj_sorted(i) < adj_sorted(i-1)
        adj_sorted(i) = adj_sorted(i-1);
    end
end

adj = NaN(size(pv));
adj(ord) = adj_sorted;
p_adj(valid) = adj;
end

function d = local_cohen_d_paired(diff_vec)
diff_vec = diff_vec(isfinite(diff_vec));
if numel(diff_vec) < 3
    d = NaN;
    return;
end
sd = std(diff_vec);
if sd <= eps
    d = NaN;
else
    d = mean(diff_vec) / sd;
end
end

function delta = local_cliff_from_diff(diff_vec)
diff_vec = diff_vec(isfinite(diff_vec));
if isempty(diff_vec)
    delta = NaN;
    return;
end
pos = sum(diff_vec > 0);
neg = sum(diff_vec < 0);
delta = (pos - neg) / numel(diff_vec);
end

function local_plot_box_and_cdf(T, controllers, metrics, out_dir)
% 每个指标输出两类图：
% 1) 控制器箱线图
% 2) 经验累积分布函数（CDF）
for k = 1:numel(metrics)
    metric = metrics{k};
    if ~ismember(metric, T.Properties.VariableNames)
        continue;
    end

    figure('Visible', 'off', 'Color', 'w', 'Position', [120 120 1280 480]);

    subplot(1,2,1);
    hold on;
    box_data = [];
    grp = {};
    for i = 1:numel(controllers)
        m = strcmp(T.controller, controllers{i});
        v = T.(metric)(m);
        v = v(isfinite(v));
        box_data = [box_data; v]; %#ok<AGROW>
        grp = [grp; repmat(controllers(i), numel(v), 1)]; %#ok<AGROW>
    end
    if ~isempty(box_data)
        boxplot(box_data, grp, 'Whisker', 1.5);
    end
    title(sprintf('%s boxplot', metric), 'Interpreter', 'none');
    grid on;

    subplot(1,2,2);
    hold on;
    for i = 1:numel(controllers)
        m = strcmp(T.controller, controllers{i});
        v = T.(metric)(m);
        v = v(isfinite(v));
        if isempty(v)
            continue;
        end
        v = sort(v);
        yy = (1:numel(v)) ./ numel(v);
        plot(v, yy, 'LineWidth', 1.6, 'DisplayName', controllers{i});
    end
    title(sprintf('%s CDF', metric), 'Interpreter', 'none');
    legend('Location', 'best');
    grid on;

    saveas(gcf, fullfile(out_dir, sprintf('plot_%s.png', metric)));
    close(gcf);
end
end

function local_write_markdown_report(analysis, report_file)
fid = fopen(report_file, 'w');
if fid < 0
    warning('Failed to open report file: %s', report_file);
    return;
end

fprintf(fid, '# Mamba2-GRU-IMU Comparison Statistical Report\n\n');
fprintf(fid, '- Generated: %s\n', analysis.timestamp);
fprintf(fid, '- Input: %s\n', analysis.input_mat);
fprintf(fid, '- Valid cases: %d\n\n', analysis.n_ok_cases);

fprintf(fid, '## Controller Summary\n\n');
local_write_table_markdown(fid, analysis.summary_tbl);

fprintf(fid, '\n## Friedman Test\n\n');
local_write_table_markdown(fid, analysis.friedman_tbl);

fprintf(fid, '\n## Pairwise Wilcoxon + Holm\n\n');
local_write_table_markdown(fid, analysis.pair_tbl);

fclose(fid);
end

function local_write_table_markdown(fid, T)
if isempty(T)
    fprintf(fid, '_Empty table._\n');
    return;
end

names = T.Properties.VariableNames;
for i = 1:numel(names)
    fprintf(fid, '| %s ', names{i});
end
fprintf(fid, '|\n');

for i = 1:numel(names)
    fprintf(fid, '|---');
end
fprintf(fid, '|\n');

for r = 1:height(T)
    for c = 1:width(T)
        val = T{r,c};
        if iscell(val)
            v = val{1};
        else
            v = val;
        end

        if ischar(v)
            s = v;
        elseif isnumeric(v)
            if isscalar(v)
                s = num2str(v, '%.6g');
            else
                s = '[...]';
            end
        else
            s = '[obj]';
        end
        fprintf(fid, '| %s ', s);
    end
    fprintf(fid, '|\n');
end
end

function m = local_nanmean(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = mean(x);
end
end

function s = local_nanstd(x)
x = x(isfinite(x));
if numel(x) < 2
    s = NaN;
else
    s = std(x);
end
end

function p = local_percentile(x, q)
x = x(isfinite(x));
if isempty(x)
    p = NaN;
    return;
end
x = sort(x(:));
n = numel(x);
if n == 1
    p = x(1);
    return;
end
pos = (q / 100) * (n - 1) + 1;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    p = x(lo);
else
    p = x(lo) + (pos - lo) * (x(hi) - x(lo));
end
end
