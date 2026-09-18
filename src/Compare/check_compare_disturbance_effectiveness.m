function report = check_compare_disturbance_effectiveness(cfg)
% =============================
% 文件名：check_compare_disturbance_effectiveness.m
% 版本号：V1.1（扰动生效体检）
% 最后修改时间：2026-04-19
% 作者：LPV-MPC Project
% 功能描述：
%   对批跑结果进行“扰动是否生效”一致性检查。
%   以 controller + path_name + seed 为分组，在 disturbance_level 维度上
%   观察核心指标变化幅度，识别“不同扰动等级但指标几乎不变”的可疑分组。
%
% 使用方法：
%   report = check_compare_disturbance_effectiveness();
%   report = check_compare_disturbance_effectiveness(cfg);
%
% 输入 cfg 字段：
%   cfg.input_mat              : case_rows.mat 路径（优先）
%   cfg.input_csv              : case_rows.csv 路径
%   cfg.out_dir                : 输出目录（默认 <run_dir>/analysis）
%   cfg.metrics                : 检查指标列表
%   cfg.group_fields           : 分组字段，默认 {'controller','path_name','seed'}
%   cfg.min_disturbance_levels : 最小扰动等级数（默认 2）
%   cfg.abs_tol                : 绝对变化阈值（默认 1e-12）
%   cfg.rel_tol                : 相对变化阈值（默认 1e-7）
%   cfg.skip_zero_flat         : 忽略全零平坦指标（默认 true）
%   cfg.zero_tol               : 判定全零阈值（默认 1e-12）
%   cfg.metric_zero_tol        : 指标近零阈值覆盖（struct，默认 viol_rate=1e-3）
%
% 输出：
%   - disturbance_effectiveness_detail.csv
%   - disturbance_effectiveness_summary.csv
%   - disturbance_effectiveness_report.md
%   - disturbance_effectiveness.mat
% =============================

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_apply_defaults(cfg, root);

[T, input_path] = local_load_case_table(cfg);
if isempty(T)
    error('Input table is empty.');
end

required_fields = {'controller', 'path_name', 'seed', 'disturbance_level', 'status'};
for i = 1:numel(required_fields)
    f = required_fields{i};
    if ~ismember(f, T.Properties.VariableNames)
        error('Required field missing in case rows: %s', f);
    end
end

ok_mask = strcmpi(local_as_cellstr(T.status), 'ok');
T = T(ok_mask, :);
if isempty(T)
    error('No successful (status=ok) case rows found.');
end

metrics = cfg.metrics(ismember(cfg.metrics, T.Properties.VariableNames));
if isempty(metrics)
    error('No valid metrics found in input.');
end

[detail_tbl, summary_tbl, flagged_tbl] = local_check_disturbance_effect(T, metrics, cfg);

if ~exist(cfg.out_dir, 'dir')
    mkdir(cfg.out_dir);
end

detail_csv = fullfile(cfg.out_dir, 'disturbance_effectiveness_detail.csv');
summary_csv = fullfile(cfg.out_dir, 'disturbance_effectiveness_summary.csv');
report_md = fullfile(cfg.out_dir, 'disturbance_effectiveness_report.md');
report_mat = fullfile(cfg.out_dir, 'disturbance_effectiveness.mat');

writetable(detail_tbl, detail_csv);
writetable(summary_tbl, summary_csv);
local_write_markdown(report_md, input_path, detail_tbl, summary_tbl, flagged_tbl, cfg);

report = struct();
report.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
report.input_path = input_path;
report.out_dir = cfg.out_dir;
report.metrics = metrics;
report.detail_tbl = detail_tbl;
report.summary_tbl = summary_tbl;
report.flagged_tbl = flagged_tbl;
report.detail_csv = detail_csv;
report.summary_csv = summary_csv;
report.report_md = report_md;
save(report_mat, 'report', '-v7.3');

checked_n = sum(strcmpi(local_as_cellstr(detail_tbl.check_status), 'checked'));
flagged_n = sum(detail_tbl.invariant_flag & strcmpi(local_as_cellstr(detail_tbl.check_status), 'checked'));
fprintf('\n[dist-check] input: %s\n', input_path);
fprintf('[dist-check] checked rows: %d, flagged invariant rows: %d\n', checked_n, flagged_n);
fprintf('[dist-check] report: %s\n', report_md);

end

function cfg = local_apply_defaults(cfg, root)
if ~isfield(cfg, 'input_mat')
    cfg.input_mat = '';
end
if ~isfield(cfg, 'input_csv')
    cfg.input_csv = '';
end

if ~isfield(cfg, 'metrics') || isempty(cfg.metrics)
    cfg.metrics = {'ey_rmse', 'epsi_rmse', 'ev_rmse', 'eomega_rmse', 'j_du', 'viol_rate'};
end
if ~isfield(cfg, 'group_fields') || isempty(cfg.group_fields)
    cfg.group_fields = {'controller', 'path_name', 'seed'};
end
if ~isfield(cfg, 'min_disturbance_levels') || isempty(cfg.min_disturbance_levels)
    cfg.min_disturbance_levels = 2;
end
if ~isfield(cfg, 'abs_tol') || isempty(cfg.abs_tol)
    cfg.abs_tol = 1e-12;
end
if ~isfield(cfg, 'rel_tol') || isempty(cfg.rel_tol)
    cfg.rel_tol = 1e-7;
end
if ~isfield(cfg, 'skip_zero_flat')
    cfg.skip_zero_flat = true;
end
if ~isfield(cfg, 'zero_tol') || isempty(cfg.zero_tol)
    cfg.zero_tol = 1e-12;
end
if ~isfield(cfg, 'metric_zero_tol') || isempty(cfg.metric_zero_tol)
    % 对近零概率类指标采用更实用的平坦判定阈值，减少无意义误报。
    cfg.metric_zero_tol = struct('viol_rate', 1e-3);
end

if ~isfield(cfg, 'out_dir') || isempty(cfg.out_dir)
    if isfield(cfg, 'input_mat') && ~isempty(cfg.input_mat)
        raw_dir = fileparts(cfg.input_mat);
        run_dir = fileparts(raw_dir);
        cfg.out_dir = fullfile(run_dir, 'analysis');
    elseif isfield(cfg, 'input_csv') && ~isempty(cfg.input_csv)
        raw_dir = fileparts(cfg.input_csv);
        run_dir = fileparts(raw_dir);
        cfg.out_dir = fullfile(run_dir, 'analysis');
    else
        latest_mat = local_pick_latest_case_rows_mat(root);
        raw_dir = fileparts(latest_mat);
        run_dir = fileparts(raw_dir);
        cfg.out_dir = fullfile(run_dir, 'analysis');
    end
end
end

function [T, input_path] = local_load_case_table(cfg)
if isfield(cfg, 'input_mat') && ~isempty(cfg.input_mat) && exist(cfg.input_mat, 'file')
    S = load(cfg.input_mat);
    if isfield(S, 'T') && istable(S.T)
        T = S.T;
        input_path = cfg.input_mat;
        return;
    end
    if isfield(S, 'results') && isfield(S.results, 'rows')
        T = struct2table(S.results.rows);
        input_path = cfg.input_mat;
        return;
    end
    error('Invalid input MAT format: %s', cfg.input_mat);
end

if isfield(cfg, 'input_csv') && ~isempty(cfg.input_csv) && exist(cfg.input_csv, 'file')
    T = readtable(cfg.input_csv);
    input_path = cfg.input_csv;
    return;
end

latest_mat = local_pick_latest_case_rows_mat(project_root());
S = load(latest_mat);
if isfield(S, 'T') && istable(S.T)
    T = S.T;
elseif isfield(S, 'results') && isfield(S.results, 'rows')
    T = struct2table(S.results.rows);
else
    error('Invalid latest MAT format: %s', latest_mat);
end
input_path = latest_mat;
end

function mat_path = local_pick_latest_case_rows_mat(root)
base_dir = fullfile(root, 'results', 'compare', 'mamba2_gru_imu');
if ~exist(base_dir, 'dir')
    error('No compare result folder found: %s', base_dir);
end
files = dir(fullfile(base_dir, '**', 'raw', 'case_rows.mat'));
if isempty(files)
    error('No case_rows.mat found under %s', base_dir);
end
[~, idx] = max([files.datenum]);
mat_path = fullfile(files(idx).folder, files(idx).name);
end

function [detail_tbl, summary_tbl, flagged_tbl] = local_check_disturbance_effect(T, metrics, cfg)
group_fields = cfg.group_fields;
for i = 1:numel(group_fields)
    if ~ismember(group_fields{i}, T.Properties.VariableNames)
        error('Group field missing: %s', group_fields{i});
    end
end

G = unique(T(:, group_fields), 'rows', 'stable');
rows = repmat(local_detail_template(group_fields), height(G) * numel(metrics), 1);
idx = 0;

for g = 1:height(G)
    mask = true(height(T), 1);
    for k = 1:numel(group_fields)
        f = group_fields{k};
        mask = mask & local_equal_mask(T.(f), G.(f)(g));
    end
    Tg = T(mask, :);
    d_levels = unique(Tg.disturbance_level);

    for m = 1:numel(metrics)
        idx = idx + 1;
        metric = metrics{m};

        r = local_detail_template(group_fields);
        for k = 1:numel(group_fields)
            f = group_fields{k};
            r.(f) = G.(f)(g);
        end
        r.metric = metric;
        r.n_rows = height(Tg);
        r.n_disturbance_levels = numel(d_levels);

        vals = NaN(numel(d_levels), 1);
        for d = 1:numel(d_levels)
            dm = (Tg.disturbance_level == d_levels(d));
            vd = Tg.(metric)(dm);
            vd = vd(isfinite(vd));
            if ~isempty(vd)
                vals(d) = median(vd);
            end
        end

        valid = isfinite(vals);
        r.n_valid_levels = sum(valid);

        if r.n_valid_levels >= cfg.min_disturbance_levels
            vv = vals(valid);
            vmin = min(vv);
            vmax = max(vv);
            vrange = vmax - vmin;
            scale = max(median(abs(vv)), 1);
            rel_range = vrange / scale;

            r.value_min = vmin;
            r.value_max = vmax;
            r.value_range = vrange;
            r.rel_range = rel_range;

            metric_zero_tol = local_metric_zero_tol(cfg, metric);
            is_zero_flat = max(abs(vv)) <= metric_zero_tol;
            if cfg.skip_zero_flat && is_zero_flat
                r.invariant_flag = false;
                r.check_status = 'flat_zero_ignored';
            else
                r.invariant_flag = (vrange <= cfg.abs_tol) || (rel_range <= cfg.rel_tol);
                r.check_status = 'checked';
            end
        else
            r.value_min = NaN;
            r.value_max = NaN;
            r.value_range = NaN;
            r.rel_range = NaN;
            r.invariant_flag = false;
            r.check_status = 'insufficient';
        end

        rows(idx) = r;
    end
end

rows = rows(1:idx);
detail_tbl = struct2table(rows);

flag_m = detail_tbl.invariant_flag & strcmpi(local_as_cellstr(detail_tbl.check_status), 'checked');
flagged_tbl = detail_tbl(flag_m, :);

[summary_tbl] = local_summary_by_controller_metric(detail_tbl);
end

function summary_tbl = local_summary_by_controller_metric(detail_tbl)
controllers = unique(local_as_cellstr(detail_tbl.controller), 'stable');
metrics = unique(local_as_cellstr(detail_tbl.metric), 'stable');
rows = repmat(struct('controller', '', 'metric', '', 'n_groups_checked', 0, ...
    'n_invariant', 0, 'invariant_ratio', NaN), numel(controllers) * numel(metrics), 1);
idx = 0;

for i = 1:numel(controllers)
    for k = 1:numel(metrics)
        idx = idx + 1;
        c = controllers{i};
        m = metrics{k};

        cm = strcmpi(local_as_cellstr(detail_tbl.controller), c) & ...
             strcmpi(local_as_cellstr(detail_tbl.metric), m) & ...
             strcmpi(local_as_cellstr(detail_tbl.check_status), 'checked');

        n_checked = sum(cm);
        n_inv = sum(detail_tbl.invariant_flag(cm));

        rows(idx).controller = c;
        rows(idx).metric = m;
        rows(idx).n_groups_checked = n_checked;
        rows(idx).n_invariant = n_inv;
        if n_checked > 0
            rows(idx).invariant_ratio = n_inv / n_checked;
        else
            rows(idx).invariant_ratio = NaN;
        end
    end
end

summary_tbl = struct2table(rows(1:idx));
end

function local_write_markdown(md_file, input_path, detail_tbl, summary_tbl, flagged_tbl, cfg)
fid = fopen(md_file, 'w');
if fid < 0
    error('Cannot open markdown file for writing: %s', md_file);
end
cleaner = onCleanup(@() fclose(fid));

checked_mask = strcmpi(local_as_cellstr(detail_tbl.check_status), 'checked');
checked_n = sum(checked_mask);
flagged_n = sum(detail_tbl.invariant_flag & checked_mask);

fprintf(fid, '# Disturbance Effectiveness Check Report\n\n');
fprintf(fid, '- Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- Input: %s\n', input_path);
fprintf(fid, '- Group fields: %s\n', strjoin(cfg.group_fields, ', '));
fprintf(fid, '- Metrics: %s\n', strjoin(cfg.metrics, ', '));
fprintf(fid, '- Thresholds: abs_tol=%.3e, rel_tol=%.3e\n', cfg.abs_tol, cfg.rel_tol);
fprintf(fid, '- Checked rows: %d\n', checked_n);
fprintf(fid, '- Flagged invariant rows: %d\n\n', flagged_n);

fprintf(fid, '## Summary by Controller and Metric\n\n');
local_write_md_table(fid, summary_tbl);

fprintf(fid, '\n## Flagged Rows (Top 30)\n\n');
if isempty(flagged_tbl)
    fprintf(fid, 'No flagged rows.\n');
else
    keep_cols = intersect({'controller', 'path_name', 'seed', 'metric', 'value_min', ...
        'value_max', 'value_range', 'rel_range'}, flagged_tbl.Properties.VariableNames, 'stable');
    top_n = min(30, height(flagged_tbl));
    local_write_md_table(fid, flagged_tbl(1:top_n, keep_cols));
end
end

function local_write_md_table(fid, T)
if isempty(T)
    fprintf(fid, '(empty)\n');
    return;
end

vars = T.Properties.VariableNames;
fprintf(fid, '| %s |\n', strjoin(vars, ' | '));
fprintf(fid, '|%s|\n', strjoin(repmat({'---'}, 1, numel(vars)), '|'));

for i = 1:height(T)
    vals = cell(1, numel(vars));
    for j = 1:numel(vars)
        v = T{i, j};
        if iscell(v)
            v = v{1};
        end
        if isstring(v)
            vals{j} = char(v);
        elseif ischar(v)
            vals{j} = v;
        elseif isnumeric(v)
            if isempty(v) || ~isfinite(v)
                vals{j} = 'NaN';
            elseif abs(v) >= 1e4 || abs(v) < 1e-3
                vals{j} = sprintf('%.6e', v);
            else
                vals{j} = sprintf('%.6g', v);
            end
        elseif islogical(v)
            vals{j} = mat2str(v);
        else
            vals{j} = '(n/a)';
        end
    end
    fprintf(fid, '| %s |\n', strjoin(vals, ' | '));
end
end

function m = local_equal_mask(col, scalar_val)
if iscell(col)
    c = local_as_cellstr(col);
    s = local_as_cellstr(scalar_val);
    m = strcmp(c, s{1});
elseif isstring(col)
    m = (col == string(scalar_val));
elseif ischar(col)
    m = strcmp(cellstr(col), char(scalar_val));
else
    m = (col == scalar_val);
end
end

function c = local_as_cellstr(v)
if iscell(v)
    c = cellfun(@local_scalar_to_char, v, 'UniformOutput', false);
elseif isstring(v)
    c = cellstr(v);
elseif ischar(v)
    c = cellstr(v);
elseif isnumeric(v)
    c = arrayfun(@num2str, v, 'UniformOutput', false);
else
    c = cellstr(string(v));
end
end

function s = local_scalar_to_char(v)
if isstring(v)
    s = char(v);
elseif ischar(v)
    s = v;
elseif isnumeric(v)
    s = num2str(v);
else
    s = char(string(v));
end
end

function r = local_detail_template(group_fields)
r = struct();
for i = 1:numel(group_fields)
    r.(group_fields{i}) = '';
end
r.metric = '';
r.n_rows = 0;
r.n_disturbance_levels = 0;
r.n_valid_levels = 0;
r.value_min = NaN;
r.value_max = NaN;
r.value_range = NaN;
r.rel_range = NaN;
r.invariant_flag = false;
r.check_status = 'unchecked';
end

function tol = local_metric_zero_tol(cfg, metric)
tol = cfg.zero_tol;
if ~isfield(cfg, 'metric_zero_tol') || ~isstruct(cfg.metric_zero_tol)
    return;
end

fns = fieldnames(cfg.metric_zero_tol);
for i = 1:numel(fns)
    if strcmpi(fns{i}, metric)
        tv = cfg.metric_zero_tol.(fns{i});
        if isnumeric(tv) && isscalar(tv) && isfinite(tv) && tv >= 0
            tol = tv;
        end
        return;
    end
end
end