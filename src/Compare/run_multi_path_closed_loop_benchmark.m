function result = run_multi_path_closed_loop_benchmark(cfg)
%RUN_MULTI_PATH_CLOSED_LOOP_BENCHMARK Run supplemental multi-path benchmark.
%
% This is the main automation entry for the supplemental experiment:
%   paths x {ModernTCN, GRU, TCN, LPV-MPC_theta0, LPV-MPC_IMU_theta,
%            LPV-MPC_oracle_theta}
%
% Example full run:
%   result = run_multi_path_closed_loop_benchmark();
%
% Smoke run:
%   cfg = struct('stop_time_override', 2.0, 'path_limit', 1);
%   result = run_multi_path_closed_loop_benchmark(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_defaults(cfg, root);

if cfg.generate_paths
    path_out = gen_closed_loop_eval_paths(cfg.path_gen_cfg);
else
    path_out = struct('path_files', {{}}, 'manifest_table', table());
end

if isempty(cfg.path_files)
    cfg.path_files = path_out.path_files;
end
cfg.path_files = cfg.path_files(:);
if cfg.path_limit > 0
    cfg.path_files = cfg.path_files(1:min(cfg.path_limit, numel(cfg.path_files)));
end
if isempty(cfg.path_files)
    error('run_multi_path_closed_loop:NoPaths', 'No path files configured.');
end

local_ensure_dir(cfg.out_root);

fprintf('\n[multipath] output root: %s\n', cfg.out_root);
fprintf('[multipath] paths: %d, dry_run=%d, stop_time_override=%g\n\n', ...
    numel(cfg.path_files), cfg.dry_run, local_nan_if_empty(cfg.stop_time_override));

path_runs = repmat(local_path_run_row(), numel(cfg.path_files), 1);

for p = 1:numel(cfg.path_files)
    path_file = cfg.path_files{p};
    [~, path_tag] = fileparts(path_file);
    path_dir = fullfile(cfg.out_root, path_tag);
    local_ensure_dir(path_dir);

    path_runs(p).path_tag = string(path_tag);
    path_runs(p).path_file = string(path_file);
    path_runs(p).out_dir = string(path_dir);

    try
        path_role = local_path_role(path_file);
        path_runs(p).role = string(path_role);
        fprintf('[multipath] %d/%d %s (%s)\n', p, numel(cfg.path_files), path_tag, path_role);

        reused = false;
        if cfg.reuse_factory_existing_results && ~cfg.dry_run
            [reused, path_runs(p)] = local_try_reuse_factory_result( ...
                path_runs(p), root, path_tag);
        end
        if ~reused && cfg.reuse_existing_path_results && ~cfg.dry_run
            [reused, path_runs(p)] = local_try_reuse_path_result( ...
                path_runs(p), path_dir);
        end
        if reused
            fprintf('[multipath] reused existing result for %s\n', path_tag);
            path_runs(p).status = "reused";
            local_write_path_runs(path_runs(1:p), cfg.out_root);
            continue;
        end

        learned = local_learned_outputs(path_dir);
        path_runs(p).modern_file = string(learned.ModernTCN);
        path_runs(p).gru_file = string(learned.GRU);
        path_runs(p).tcn_file = string(learned.TCN);

        if ~cfg.dry_run
            if cfg.run_learned
                sim_cfg = struct();
                sim_cfg.stop_time_override = cfg.stop_time_override;
                run_closed_loop_model_once('LPVMPC_AGV_simulink_Modern_TCN', ...
                    path_file, learned.ModernTCN, sim_cfg);
                run_closed_loop_model_once('LPVMPC_AGV_simulink_GRU', ...
                    path_file, learned.GRU, sim_cfg);
                run_closed_loop_model_once('LPVMPC_AGV_simulink_TCN', ...
                    path_file, learned.TCN, sim_cfg);
            else
                local_assert_learned_outputs(learned);
            end

            bcfg = struct();
            bcfg.path_file = path_file;
            bcfg.out_dir = path_dir;
            bcfg.compare_with_learned = true;
            bcfg.learned_outputs = learned;
            bcfg.stop_time_override = cfg.stop_time_override;
            bcfg.stop_on_error = cfg.stop_on_error;
            path_runs(p).baseline_status = "running";
            baseline_result = run_lpvmpc_theta_baseline_experiment(bcfg); %#ok<NASGU>
            path_runs(p).baseline_status = "ok";
        end

        path_runs(p).summary_file = string(fullfile(path_dir, ...
            'tcn_gru_modern_lpvmpc_theta_baseline_summary.csv'));
        path_runs(p).rank_file = string(fullfile(path_dir, ...
            'tcn_gru_modern_lpvmpc_theta_baseline_rank.csv'));
        path_runs(p).report_file = string(fullfile(path_dir, ...
            'tcn_gru_modern_lpvmpc_theta_baseline_report.md'));
        path_runs(p).status = "ok";
    catch ME
        path_runs(p).status = "error";
        path_runs(p).message = string(ME.message);
        if cfg.stop_on_error
            rethrow(ME);
        end
        warning('run_multi_path_closed_loop:PathFailed', ...
            '%s failed: %s', path_tag, ME.message);
    end

    local_write_path_runs(path_runs(1:p), cfg.out_root);
end

[summary_all, rank_all] = local_collect_tables(path_runs);
aggregate_table = local_aggregate_summary(summary_all, rank_all);

summary_file = fullfile(cfg.out_root, 'multipath_closed_loop_summary.csv');
rank_file = fullfile(cfg.out_root, 'multipath_closed_loop_rank.csv');
aggregate_file = fullfile(cfg.out_root, 'multipath_closed_loop_aggregate.csv');
report_file = fullfile(cfg.out_root, 'multipath_closed_loop_report.md');
mat_file = fullfile(cfg.out_root, 'multipath_closed_loop_result.mat');

if ~isempty(summary_all)
    writetable(summary_all, summary_file);
end
if ~isempty(rank_all)
    writetable(rank_all, rank_file);
end
if ~isempty(aggregate_table)
    writetable(aggregate_table, aggregate_file);
end

result = struct();
result.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.cfg = cfg;
result.path_generation = path_out;
result.path_runs = path_runs;
result.summary_table = summary_all;
result.rank_table = rank_all;
result.aggregate_table = aggregate_table;
result.summary_file = summary_file;
result.rank_file = rank_file;
result.aggregate_file = aggregate_file;
result.report_file = report_file;
result.mat_file = mat_file;

save(mat_file, 'result', '-v7.3');
local_write_report(report_file, result);

fprintf('\n[multipath] done\n');
fprintf('[multipath] aggregate: %s\n', aggregate_file);
fprintf('[multipath] report:    %s\n', report_file);
end

function cfg = local_defaults(cfg, root)
cfg.out_root = local_cfg(cfg, 'out_root', ...
    fullfile(root, 'results', 'compare', 'multipath_closed_loop'));
cfg.generate_paths = local_cfg(cfg, 'generate_paths', true);
cfg.path_gen_cfg = local_cfg(cfg, 'path_gen_cfg', struct());
if ~isfield(cfg.path_gen_cfg, 'include_mixed')
    cfg.path_gen_cfg.include_mixed = false;
end
cfg.path_files = local_cfg(cfg, 'path_files', {});
cfg.path_limit = local_cfg(cfg, 'path_limit', 0);
cfg.run_learned = local_cfg(cfg, 'run_learned', true);
cfg.dry_run = local_cfg(cfg, 'dry_run', false);
cfg.stop_time_override = local_cfg(cfg, 'stop_time_override', []);
cfg.stop_on_error = local_cfg(cfg, 'stop_on_error', true);
cfg.reuse_factory_existing_results = local_cfg(cfg, 'reuse_factory_existing_results', true);
cfg.reuse_existing_path_results = local_cfg(cfg, 'reuse_existing_path_results', false);
end

function v = local_cfg(cfg, name, default_value)
if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
    v = cfg.(name);
else
    v = default_value;
end
end

function local_ensure_dir(d)
if exist(d, 'dir') ~= 7
    mkdir(d);
end
end

function x = local_nan_if_empty(v)
if isempty(v)
    x = NaN;
else
    x = double(v);
end
end

function role = local_path_role(path_file)
role = 'unknown';
S = load(path_file, 'ref');
if isfield(S, 'ref') && isfield(S.ref, 'meta')
    if isfield(S.ref.meta, 'role')
        role = char(S.ref.meta.role);
    elseif isfield(S.ref.meta, 'scene')
        role = char(S.ref.meta.scene);
    elseif isfield(S.ref.meta, 'path_type')
        role = char(S.ref.meta.path_type);
    end
end
end

function learned = local_learned_outputs(path_dir)
learned = struct();
learned.ModernTCN = fullfile(path_dir, 'ModernTCN_out.mat');
learned.GRU = fullfile(path_dir, 'GRU_out.mat');
learned.TCN = fullfile(path_dir, 'TCN_out.mat');
end

function [ok, row] = local_try_reuse_factory_result(row, root, path_tag)
ok = false;
if ~strcmp(path_tag, 'path_factory_logistics_showcase_theta10_v3')
    return;
end

reuse_dir = fullfile(root, 'results', 'compare', ...
    'lpvmpc_theta_baseline', path_tag);
summary_file = fullfile(reuse_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_summary.csv');
rank_file = fullfile(reuse_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_rank.csv');
report_file = fullfile(reuse_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_report.md');
if exist(summary_file, 'file') ~= 2 || exist(rank_file, 'file') ~= 2
    return;
end

row.out_dir = string(reuse_dir);
row.summary_file = string(summary_file);
row.rank_file = string(rank_file);
row.report_file = string(report_file);
row.modern_file = string(fullfile(root, 'ModernTCN_out.mat'));
row.gru_file = string(fullfile(root, 'GRU_out.mat'));
row.tcn_file = string(fullfile(root, 'TCN_out.mat'));
row.baseline_status = "reused";
ok = true;
end

function [ok, row] = local_try_reuse_path_result(row, path_dir)
ok = false;
summary_file = fullfile(path_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_summary.csv');
rank_file = fullfile(path_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_rank.csv');
report_file = fullfile(path_dir, 'tcn_gru_modern_lpvmpc_theta_baseline_report.md');
if exist(summary_file, 'file') ~= 2 || exist(rank_file, 'file') ~= 2
    return;
end

row.summary_file = string(summary_file);
row.rank_file = string(rank_file);
row.report_file = string(report_file);
row.modern_file = string(fullfile(path_dir, 'ModernTCN_out.mat'));
row.gru_file = string(fullfile(path_dir, 'GRU_out.mat'));
row.tcn_file = string(fullfile(path_dir, 'TCN_out.mat'));
row.baseline_status = "reused";
ok = true;
end

function local_assert_learned_outputs(learned)
names = fieldnames(learned);
for i = 1:numel(names)
    f = learned.(names{i});
    if exist(f, 'file') ~= 2
        error('run_multi_path_closed_loop:MissingLearnedOutput', ...
            'Missing learned output for %s: %s', names{i}, f);
    end
end
end

function local_write_path_runs(path_runs, out_root)
T = struct2table(path_runs);
writetable(T, fullfile(out_root, 'multipath_closed_loop_path_runs.csv'));
save(fullfile(out_root, 'multipath_closed_loop_path_runs.mat'), 'path_runs');
end

function [summary_all, rank_all] = local_collect_tables(path_runs)
summary_all = table();
rank_all = table();
for i = 1:numel(path_runs)
    if strlength(path_runs(i).summary_file) > 0 && exist(char(path_runs(i).summary_file), 'file') == 2
        T = readtable(char(path_runs(i).summary_file));
        T.path_tag = repmat(path_runs(i).path_tag, height(T), 1);
        T.path_role = repmat(path_runs(i).role, height(T), 1);
        summary_all = [summary_all; T]; %#ok<AGROW>
    end
    if strlength(path_runs(i).rank_file) > 0 && exist(char(path_runs(i).rank_file), 'file') == 2
        R = readtable(char(path_runs(i).rank_file));
        R.path_tag = repmat(path_runs(i).path_tag, height(R), 1);
        R.path_role = repmat(path_runs(i).role, height(R), 1);
        rank_all = [rank_all; R]; %#ok<AGROW>
    end
end

summary_all = local_move_front(summary_all, {'path_tag','path_role'});
rank_all = local_move_front(rank_all, {'path_tag','path_role'});
end

function T = local_move_front(T, names)
if isempty(T)
    return;
end
vars = T.Properties.VariableNames;
front = names(ismember(names, vars));
rest = vars(~ismember(vars, front));
T = T(:, [front, rest]);
end

function A = local_aggregate_summary(S, R)
A = table();
if isempty(S) || ~ismember('controller', S.Properties.VariableNames)
    return;
end

controllers = unique(string(S.controller), 'stable');
rows = repmat(local_agg_row(), numel(controllers), 1);
for i = 1:numel(controllers)
    c = controllers(i);
    mask = string(S.controller) == c;
    rows(i).controller = c;
    rows(i).path_count = nnz(mask);
    rows(i).ey_rmse_mean = local_col_mean(S, 'ey_rmse', mask);
    rows(i).ey_peak_worst = local_col_max(S, 'ey_peak', mask);
    rows(i).epsi_rmse_mean = local_col_mean(S, 'epsi_rmse', mask);
    rows(i).xy_rmse_mean = local_col_mean(S, 'xy_rmse', mask);
    rows(i).j_du_mean = local_col_mean(S, 'j_du', mask);
    rows(i).viol_rate_mean = local_col_mean(S, 'viol_rate', mask);
    rows(i).theta_mae_deg_mean = local_col_mean(S, 'theta_mae_deg', mask);
    rows(i).theta_sched_mae_deg_mean = local_col_mean(S, 'theta_sched_mae_deg', mask);
    rows(i).main_acc_pct_mean = local_col_mean(S, 'main_acc_pct', mask);
    rows(i).turn_acc_pct_mean = local_col_mean(S, 'turn_acc_pct', mask);

    if ~isempty(R) && ismember('controller', R.Properties.VariableNames)
        rmask = string(R.controller) == c;
        rows(i).overall_rank_mean = local_col_mean(R, 'overall_rank', rmask);
        rows(i).overall_rank_worst = local_col_max(R, 'overall_rank', rmask);
        rows(i).overall_rank_sum_mean = local_col_mean(R, 'overall_rank_sum', rmask);
    end
end

A = struct2table(rows);
if ismember('overall_rank_mean', A.Properties.VariableNames)
    A = sortrows(A, {'overall_rank_mean','overall_rank_sum_mean'});
end
end

function row = local_agg_row()
row = struct();
row.controller = "";
row.path_count = NaN;
row.ey_rmse_mean = NaN;
row.ey_peak_worst = NaN;
row.epsi_rmse_mean = NaN;
row.xy_rmse_mean = NaN;
row.j_du_mean = NaN;
row.viol_rate_mean = NaN;
row.theta_mae_deg_mean = NaN;
row.theta_sched_mae_deg_mean = NaN;
row.main_acc_pct_mean = NaN;
row.turn_acc_pct_mean = NaN;
row.overall_rank_mean = NaN;
row.overall_rank_worst = NaN;
row.overall_rank_sum_mean = NaN;
end

function m = local_col_mean(T, name, mask)
if isempty(T) || ~ismember(name, T.Properties.VariableNames) || ~any(mask)
    m = NaN;
    return;
end
x = T.(name);
x = x(mask);
m = mean(x, 'omitnan');
end

function m = local_col_max(T, name, mask)
if isempty(T) || ~ismember(name, T.Properties.VariableNames) || ~any(mask)
    m = NaN;
    return;
end
x = T.(name);
x = x(mask);
m = max(x, [], 'omitnan');
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w', 'n', 'UTF-8');
if fid < 0
    warning('run_multi_path_closed_loop:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Multi-Path Closed-Loop Benchmark\n\n');
fprintf(fid, '- timestamp: `%s`\n', result.timestamp);
fprintf(fid, '- output root: `%s`\n', result.cfg.out_root);
fprintf(fid, '- paths: `%d`\n\n', numel(result.path_runs));

fprintf(fid, '## Path Runs\n\n');
fprintf(fid, '| path | role | status | report |\n');
fprintf(fid, '|---|---|---|---|\n');
for i = 1:numel(result.path_runs)
    r = result.path_runs(i);
    fprintf(fid, '| %s | %s | %s | `%s` |\n', ...
        char(r.path_tag), char(r.role), char(r.status), char(r.report_file));
end

if ~isempty(result.aggregate_table)
    fprintf(fid, '\n## Aggregate Summary\n\n');
    fprintf(fid, '| controller | paths | rank mean | ey rmse mean | xy rmse mean | j_du mean | viol mean | main acc | turn acc |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
    A = result.aggregate_table;
    for i = 1:height(A)
        fprintf(fid, '| %s | %.0f | %.3f | %.5g | %.5g | %.5g | %.5g | %.3f | %.3f |\n', ...
            char(string(A.controller(i))), A.path_count(i), A.overall_rank_mean(i), ...
            A.ey_rmse_mean(i), A.xy_rmse_mean(i), A.j_du_mean(i), ...
            A.viol_rate_mean(i), A.main_acc_pct_mean(i), A.turn_acc_pct_mean(i));
    end
end

if ~isempty(result.rank_table)
    verdict = local_modern_verdict(result.rank_table);
    fprintf(fid, '\n## ModernTCN Check\n\n');
    fprintf(fid, '- ModernTCN better than both GRU and TCN by per-path overall rank: `%d/%d` paths.\n', ...
        verdict.modern_beats_gru_tcn_count, verdict.path_count);
    fprintf(fid, '- Oracle theta is allowed to rank above ModernTCN because it uses true slope.\n');
end
end

function verdict = local_modern_verdict(R)
paths = unique(string(R.path_tag), 'stable');
count = 0;
for i = 1:numel(paths)
    one = R(string(R.path_tag) == paths(i), :);
    m = local_rank_for(one, 'ModernTCN');
    g = local_rank_for(one, 'GRU');
    t = local_rank_for(one, 'TCN');
    if isfinite(m) && isfinite(g) && isfinite(t) && m < g && m < t
        count = count + 1;
    end
end
verdict = struct();
verdict.path_count = numel(paths);
verdict.modern_beats_gru_tcn_count = count;
end

function r = local_rank_for(T, controller)
r = NaN;
mask = strcmp(string(T.controller), controller);
if any(mask) && ismember('overall_rank', T.Properties.VariableNames)
    r = T.overall_rank(find(mask, 1, 'first'));
end
end

function row = local_path_run_row()
row = struct();
row.path_tag = "";
row.role = "";
row.path_file = "";
row.out_dir = "";
row.modern_file = "";
row.gru_file = "";
row.tcn_file = "";
row.summary_file = "";
row.rank_file = "";
row.report_file = "";
row.status = "pending";
row.baseline_status = "";
row.message = "";
end
