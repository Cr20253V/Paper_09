function result = run_closed_loop_robustness_experiment(cfg)
%RUN_CLOSED_LOOP_ROBUSTNESS_EXPERIMENT Run disturbance robustness benchmark.
%
% Default experiment:
%   paths: compact long_updown and sharp_turn_transition
%   controllers: ModernTCN, GRU, TCN
%   disturbance levels:
%     0 -> nominal, reused from multipath_closed_loop if available
%     1 -> moderate measurement noise + plant parameter perturbation
%     2 -> strong measurement noise + plant parameter perturbation

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_defaults(cfg, root);
local_ensure_dir(cfg.out_root);

if cfg.generate_paths
    gen_closed_loop_eval_paths(cfg.path_gen_cfg);
end

cases = local_build_cases(cfg);
if isempty(cases)
    error('run_closed_loop_robustness:NoCases', 'No robustness cases configured.');
end

fprintf('\n[robustness] output root: %s\n', cfg.out_root);
fprintf('[robustness] cases=%d, controllers=%d\n\n', ...
    numel(cases), numel(cfg.controllers));

case_rows = repmat(local_case_row(), numel(cases), 1);
for i = 1:numel(cases)
    one = cases(i);
    fprintf('[robustness] %d/%d %s | d=%d | seed=%d\n', ...
        i, numel(cases), one.path_tag, one.disturbance_level, one.seed);

    row = local_case_row();
    row.case_tag = string(one.case_tag);
    row.path_tag = string(one.path_tag);
    row.path_file = string(one.path_file);
    row.disturbance_level = one.disturbance_level;
    row.seed = one.seed;
    row.out_dir = string(one.out_dir);

    try
        if one.disturbance_level == 0 && cfg.reuse_nominal
            [ok, row] = local_reuse_nominal(row, cfg, one.path_tag);
            if ok
                fprintf('[robustness] reused nominal result: %s\n', row.summary_file);
                row.status = "reused";
                case_rows(i) = row;
                local_write_case_rows(case_rows(1:i), cfg.out_root);
                continue;
            end
        end

        local_ensure_dir(one.out_dir);
        [params, ff_rt, dist_meta] = local_make_disturbance( ...
            one.disturbance_level, one.seed, cfg);

        row.noise_scale = dist_meta.noise_scale;
        row.process_scale = dist_meta.process_scale;
        row.noise_enabled = dist_meta.enable_noise;
        row.noise_signature = dist_meta.noise_signature;
        row.process_signature = dist_meta.process_signature;

        outputs = struct();
        for c = 1:numel(cfg.controllers)
            ctrl = cfg.controllers{c};
            model_name = cfg.model_map.(ctrl);
            out_file = fullfile(one.out_dir, sprintf('%s_out.mat', ctrl));
            sim_cfg = struct();
            sim_cfg.params_override = params;
            sim_cfg.ff_rt_override = ff_rt;
            sim_cfg.robustness_case = struct( ...
                'case_tag', one.case_tag, ...
                'disturbance_level', one.disturbance_level, ...
                'seed', one.seed, ...
                'noise_scale', dist_meta.noise_scale, ...
                'process_scale', dist_meta.process_scale);
            run_closed_loop_model_once(model_name, one.path_file, out_file, sim_cfg);
            outputs.(ctrl) = out_file;
        end

        cmp = compare_tcn_gru_modern_closed_loop_out( ...
            outputs.ModernTCN, outputs.GRU, outputs.TCN, ...
            one.path_file, one.out_dir, "ModernTCN", [], ...
            sprintf('Robustness closed-loop comparison: %s', one.case_tag), ...
            cfg.file_prefix); %#ok<NASGU>

        row.modern_file = string(outputs.ModernTCN);
        row.gru_file = string(outputs.GRU);
        row.tcn_file = string(outputs.TCN);
        row.summary_file = string(fullfile(one.out_dir, [cfg.file_prefix '_summary.csv']));
        row.rank_file = string(fullfile(one.out_dir, [cfg.file_prefix '_rank.csv']));
        row.report_file = string(fullfile(one.out_dir, [cfg.file_prefix '_report.md']));
        row.status = "ok";
    catch ME
        row.status = "error";
        row.message = string(ME.message);
        if cfg.stop_on_error
            rethrow(ME);
        end
        warning('run_closed_loop_robustness:CaseFailed', ...
            '%s failed: %s', one.case_tag, ME.message);
    end

    case_rows(i) = row;
    local_write_case_rows(case_rows(1:i), cfg.out_root);
end

[summary_table, rank_table] = local_collect_tables(case_rows, cfg.controllers);
aggregate_table = local_aggregate_tables(summary_table, rank_table);

summary_file = fullfile(cfg.out_root, 'robustness_closed_loop_summary.csv');
rank_file = fullfile(cfg.out_root, 'robustness_closed_loop_rank.csv');
aggregate_file = fullfile(cfg.out_root, 'robustness_closed_loop_aggregate.csv');
report_file = fullfile(cfg.out_root, 'robustness_closed_loop_report.md');
mat_file = fullfile(cfg.out_root, 'robustness_closed_loop_result.mat');

if ~isempty(summary_table)
    writetable(summary_table, summary_file);
end
if ~isempty(rank_table)
    writetable(rank_table, rank_file);
end
if ~isempty(aggregate_table)
    writetable(aggregate_table, aggregate_file);
end

result = struct();
result.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.cfg = cfg;
result.case_rows = case_rows;
result.summary_table = summary_table;
result.rank_table = rank_table;
result.aggregate_table = aggregate_table;
result.summary_file = summary_file;
result.rank_file = rank_file;
result.aggregate_file = aggregate_file;
result.report_file = report_file;
result.mat_file = mat_file;

save(mat_file, 'result', '-v7.3');
local_write_report(report_file, result);

fprintf('\n[robustness] done\n');
fprintf('[robustness] aggregate: %s\n', aggregate_file);
fprintf('[robustness] report:    %s\n', report_file);
end

function cfg = local_defaults(cfg, root)
cfg.out_root = local_cfg(cfg, 'out_root', ...
    fullfile(root, 'results', 'compare', 'robustness_closed_loop'));
cfg.generate_paths = local_cfg(cfg, 'generate_paths', true);
cfg.path_gen_cfg = local_cfg(cfg, 'path_gen_cfg', struct());
if ~isfield(cfg.path_gen_cfg, 'include_mixed')
    cfg.path_gen_cfg.include_mixed = false;
end

default_paths = { ...
    fullfile(root, 'data', 'paths', 'path_closed_loop_long_updown_theta10_v1.mat')
    fullfile(root, 'data', 'paths', 'path_closed_loop_sharp_turn_transition_theta10_v1.mat')};
cfg.path_files = local_cfg(cfg, 'path_files', default_paths);
cfg.controllers = local_cfg(cfg, 'controllers', {'ModernTCN','GRU','TCN'});
cfg.disturbance_levels = local_cfg(cfg, 'disturbance_levels', [0 1 2]);
cfg.seeds = local_cfg(cfg, 'seeds', 21);
cfg.reuse_nominal = local_cfg(cfg, 'reuse_nominal', true);
cfg.stop_on_error = local_cfg(cfg, 'stop_on_error', true);
cfg.disturbance_mode = local_cfg(cfg, 'disturbance_mode', 'hybrid');
cfg.disturbance_scale = local_cfg(cfg, 'disturbance_scale', [0.0 1.0 1.5]);
cfg.disturbance_process_scale = local_cfg(cfg, 'disturbance_process_scale', [0.0 0.35 0.70]);
cfg.file_prefix = local_cfg(cfg, 'file_prefix', 'robustness_tcn_gru_modern');

cfg.model_map = struct();
cfg.model_map.ModernTCN = 'LPVMPC_AGV_simulink_Modern_TCN';
cfg.model_map.GRU = 'LPVMPC_AGV_simulink_GRU';
cfg.model_map.TCN = 'LPVMPC_AGV_simulink_TCN';
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

function cases = local_build_cases(cfg)
cases = repmat(struct('case_tag', '', 'path_tag', '', 'path_file', '', ...
    'disturbance_level', NaN, 'seed', NaN, 'out_dir', ''), 0, 1);
for p = 1:numel(cfg.path_files)
    path_file = cfg.path_files{p};
    [~, path_tag] = fileparts(path_file);
    for d = 1:numel(cfg.disturbance_levels)
        level = cfg.disturbance_levels(d);
        if level == 0
            seeds = 0;
        else
            seeds = cfg.seeds;
        end
        for s = 1:numel(seeds)
            seed = seeds(s);
            case_tag = sprintf('%s_d%d_seed%d', path_tag, level, seed);
            out_dir = fullfile(cfg.out_root, path_tag, sprintf('d%d_seed%d', level, seed));
            cases(end+1) = struct('case_tag', case_tag, 'path_tag', path_tag, ... %#ok<AGROW>
                'path_file', path_file, 'disturbance_level', level, ...
                'seed', seed, 'out_dir', out_dir);
        end
    end
end
end

function [ok, row] = local_reuse_nominal(row, cfg, path_tag)
ok = false;
reuse_dir = fullfile(project_root(), 'results', 'compare', ...
    'multipath_closed_loop', path_tag);
modern_file = fullfile(reuse_dir, 'ModernTCN_out.mat');
gru_file = fullfile(reuse_dir, 'GRU_out.mat');
tcn_file = fullfile(reuse_dir, 'TCN_out.mat');
if exist(modern_file, 'file') ~= 2 || exist(gru_file, 'file') ~= 2 || ...
        exist(tcn_file, 'file') ~= 2
    return;
end

local_ensure_dir(char(row.out_dir));
compare_tcn_gru_modern_closed_loop_out( ...
    modern_file, gru_file, tcn_file, char(row.path_file), char(row.out_dir), ...
    "ModernTCN", [], ...
    sprintf('Robustness nominal comparison: %s', row.case_tag), ...
    cfg.file_prefix);

row.modern_file = string(modern_file);
row.gru_file = string(gru_file);
row.tcn_file = string(tcn_file);
row.summary_file = string(fullfile(char(row.out_dir), [cfg.file_prefix '_summary.csv']));
row.rank_file = string(fullfile(char(row.out_dir), [cfg.file_prefix '_rank.csv']));
row.report_file = string(fullfile(char(row.out_dir), [cfg.file_prefix '_report.md']));
row.noise_scale = 0;
row.process_scale = 0;
row.noise_enabled = false;
row.noise_signature = 0;
row.process_signature = NaN;
ok = true;
end

function [params, ff_rt, meta] = local_make_disturbance(level, seed, cfg)
params = parameters();
noise_scale = local_disturbance_scale(level, cfg.disturbance_scale);
proc_scale = local_disturbance_scale(level, cfg.disturbance_process_scale);

params.random_seed = double(seed);
if noise_scale <= 0
    params.enable_noise = false;
else
    params.enable_noise = true;
    fields = {'current_noise_std', 'wheel_speed_noise_std', 'disturbance_noise_std', ...
              'v_noise_std', 'psi_noise_std', 'omega_noise_std'};
    for i = 1:numel(fields)
        f = fields{i};
        if isfield(params, f)
            params.(f) = params.(f) * noise_scale;
        end
    end
end

if proc_scale > 0 && strcmpi(cfg.disturbance_mode, 'hybrid')
    params = local_apply_process_disturbance(params, proc_scale);
end

ff_rt = struct('m', params.mass, 'g', params.gravity, ...
    'c_r', params.rolling_resistance, 'rho', params.air_density, ...
    'CdA', params.drag_coefficient_area);

meta = struct();
meta.noise_scale = noise_scale;
meta.process_scale = proc_scale;
meta.enable_noise = logical(params.enable_noise);
meta.noise_signature = local_noise_signature(params);
meta.process_signature = local_process_signature(params);
end

function params = local_apply_process_disturbance(params, proc_scale)
params.mass = params.mass * (1.0 + 0.08 * proc_scale);
params.friction_coefficient = max(0.2, params.friction_coefficient * (1.0 - 0.10 * proc_scale));
params.rolling_resistance = params.rolling_resistance * (1.0 + 0.20 * proc_scale);
params.air_density = params.air_density * (1.0 + 0.25 * proc_scale);
params.drag_coefficient_area = params.drag_coefficient_area * (1.0 + 0.25 * proc_scale);
params.front_cornering_stiffness = params.front_cornering_stiffness * (1.0 - 0.12 * proc_scale);
params.rear_cornering_stiffness = params.rear_cornering_stiffness * (1.0 - 0.12 * proc_scale);
params.max_acceleration = params.max_acceleration * (1.0 - 0.08 * proc_scale);
end

function scale = local_disturbance_scale(level, scale_table)
if numel(scale_table) >= 3 && any(level == [0 1 2])
    scale = scale_table(level + 1);
else
    scale = 1.0 + 0.25 * double(level);
end
end

function sig = local_noise_signature(params)
fields = {'current_noise_std', 'wheel_speed_noise_std', 'disturbance_noise_std', ...
          'v_noise_std', 'psi_noise_std', 'omega_noise_std'};
sig = 0.0;
for i = 1:numel(fields)
    f = fields{i};
    if isfield(params, f) && isnumeric(params.(f))
        v = params.(f);
        v = v(isfinite(v));
        sig = sig + sum(abs(v(:)));
    end
end
end

function sig = local_process_signature(params)
fields = {'mass', 'friction_coefficient', 'rolling_resistance', ...
          'air_density', 'drag_coefficient_area', ...
          'front_cornering_stiffness', 'rear_cornering_stiffness'};
sig = 0.0;
for i = 1:numel(fields)
    f = fields{i};
    if isfield(params, f) && isnumeric(params.(f))
        v = params.(f);
        v = v(isfinite(v));
        sig = sig + sum(abs(v(:)));
    end
end
end

function local_write_case_rows(case_rows, out_root)
T = struct2table(case_rows);
writetable(T, fullfile(out_root, 'robustness_closed_loop_cases.csv'));
save(fullfile(out_root, 'robustness_closed_loop_cases.mat'), 'case_rows');
end

function [summary_table, rank_table] = local_collect_tables(case_rows, controllers)
summary_table = table();
rank_table = table();
for i = 1:numel(case_rows)
    r = case_rows(i);
    if strlength(r.summary_file) > 0 && exist(char(r.summary_file), 'file') == 2
        S = readtable(char(r.summary_file));
        if ismember('controller', S.Properties.VariableNames)
            S = S(ismember(string(S.controller), string(controllers)), :);
        end
        S.case_tag = repmat(r.case_tag, height(S), 1);
        S.path_tag = repmat(r.path_tag, height(S), 1);
        S.disturbance_level = repmat(r.disturbance_level, height(S), 1);
        S.seed = repmat(r.seed, height(S), 1);
        S.noise_scale = repmat(r.noise_scale, height(S), 1);
        S.process_scale = repmat(r.process_scale, height(S), 1);
        summary_table = [summary_table; S]; %#ok<AGROW>
    end
    if strlength(r.rank_file) > 0 && exist(char(r.rank_file), 'file') == 2
        R = readtable(char(r.rank_file));
        if ismember('controller', R.Properties.VariableNames)
            R = R(ismember(string(R.controller), string(controllers)), :);
        end
        R.case_tag = repmat(r.case_tag, height(R), 1);
        R.path_tag = repmat(r.path_tag, height(R), 1);
        R.disturbance_level = repmat(r.disturbance_level, height(R), 1);
        R.seed = repmat(r.seed, height(R), 1);
        R.noise_scale = repmat(r.noise_scale, height(R), 1);
        R.process_scale = repmat(r.process_scale, height(R), 1);
        rank_table = [rank_table; R]; %#ok<AGROW>
    end
end
summary_table = local_move_front(summary_table, ...
    {'case_tag','path_tag','disturbance_level','seed','noise_scale','process_scale'});
rank_table = local_move_front(rank_table, ...
    {'case_tag','path_tag','disturbance_level','seed','noise_scale','process_scale'});
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

function A = local_aggregate_tables(S, R)
A = table();
if isempty(S)
    return;
end
controllers = unique(string(S.controller), 'stable');
levels = unique(S.disturbance_level, 'stable');
rows = repmat(local_agg_row(), 0, 1);
for l = 1:numel(levels)
    lev = levels(l);
    for c = 1:numel(controllers)
        ctrl = controllers(c);
        mask = S.disturbance_level == lev & string(S.controller) == ctrl;
        if ~any(mask)
            continue;
        end
        row = local_agg_row();
        row.disturbance_level = lev;
        row.controller = ctrl;
        row.case_count = nnz(mask);
        row.ey_rmse_mean = local_col_mean(S, 'ey_rmse', mask);
        row.ey_peak_worst = local_col_max(S, 'ey_peak', mask);
        row.epsi_rmse_mean = local_col_mean(S, 'epsi_rmse', mask);
        row.xy_rmse_mean = local_col_mean(S, 'xy_rmse', mask);
        row.j_du_mean = local_col_mean(S, 'j_du', mask);
        row.viol_rate_mean = local_col_mean(S, 'viol_rate', mask);
        row.theta_mae_deg_mean = local_col_mean(S, 'theta_mae_deg', mask);
        row.main_acc_pct_mean = local_col_mean(S, 'main_acc_pct', mask);
        row.turn_acc_pct_mean = local_col_mean(S, 'turn_acc_pct', mask);
        if ~isempty(R)
            rmask = R.disturbance_level == lev & string(R.controller) == ctrl;
            row.overall_rank_mean = local_col_mean(R, 'overall_rank', rmask);
            row.overall_rank_worst = local_col_max(R, 'overall_rank', rmask);
            row.overall_rank_sum_mean = local_col_mean(R, 'overall_rank_sum', rmask);
        end
        rows(end+1) = row; %#ok<AGROW>
    end
end
A = struct2table(rows);
if ~isempty(A)
    A = sortrows(A, {'disturbance_level','overall_rank_mean','overall_rank_sum_mean'});
end
end

function row = local_agg_row()
row = struct();
row.disturbance_level = NaN;
row.controller = "";
row.case_count = NaN;
row.overall_rank_mean = NaN;
row.overall_rank_worst = NaN;
row.overall_rank_sum_mean = NaN;
row.ey_rmse_mean = NaN;
row.ey_peak_worst = NaN;
row.epsi_rmse_mean = NaN;
row.xy_rmse_mean = NaN;
row.j_du_mean = NaN;
row.viol_rate_mean = NaN;
row.theta_mae_deg_mean = NaN;
row.main_acc_pct_mean = NaN;
row.turn_acc_pct_mean = NaN;
end

function m = local_col_mean(T, name, mask)
if isempty(T) || ~ismember(name, T.Properties.VariableNames) || ~any(mask)
    m = NaN;
else
    m = mean(T.(name)(mask), 'omitnan');
end
end

function m = local_col_max(T, name, mask)
if isempty(T) || ~ismember(name, T.Properties.VariableNames) || ~any(mask)
    m = NaN;
else
    m = max(T.(name)(mask), [], 'omitnan');
end
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w', 'n', 'UTF-8');
if fid < 0
    warning('run_closed_loop_robustness:ReportFailed', ...
        'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Closed-Loop Robustness Benchmark\n\n');
fprintf(fid, '- timestamp: `%s`\n', result.timestamp);
fprintf(fid, '- output root: `%s`\n', result.cfg.out_root);
fprintf(fid, '- controllers: `%s`\n', strjoin(result.cfg.controllers, ', '));
fprintf(fid, '- disturbance levels: `%s`\n\n', mat2str(result.cfg.disturbance_levels));

fprintf(fid, '## Aggregate By Disturbance\n\n');
fprintf(fid, '| d | controller | cases | rank mean | worst rank | ey rmse | xy rmse | j_du | viol | main acc | turn acc |\n');
fprintf(fid, '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
A = result.aggregate_table;
for i = 1:height(A)
    fprintf(fid, '| %d | %s | %.0f | %.3f | %.0f | %.5g | %.5g | %.5g | %.5g | %.3f | %.3f |\n', ...
        A.disturbance_level(i), char(string(A.controller(i))), A.case_count(i), ...
        A.overall_rank_mean(i), A.overall_rank_worst(i), ...
        A.ey_rmse_mean(i), A.xy_rmse_mean(i), A.j_du_mean(i), ...
        A.viol_rate_mean(i), A.main_acc_pct_mean(i), A.turn_acc_pct_mean(i));
end

if ~isempty(result.rank_table)
    verdict = local_modern_verdict(result.rank_table);
    fprintf(fid, '\n## ModernTCN Check\n\n');
    fprintf(fid, '- ModernTCN better than both GRU and TCN by per-case overall rank: `%d/%d` cases.\n', ...
        verdict.modern_beats_gru_tcn_count, verdict.case_count);
end
end

function verdict = local_modern_verdict(R)
keys = unique(string(R.case_tag), 'stable');
count = 0;
for i = 1:numel(keys)
    T = R(string(R.case_tag) == keys(i), :);
    m = local_rank_for(T, 'ModernTCN');
    g = local_rank_for(T, 'GRU');
    t = local_rank_for(T, 'TCN');
    if isfinite(m) && isfinite(g) && isfinite(t) && m < g && m < t
        count = count + 1;
    end
end
verdict = struct('case_count', numel(keys), ...
    'modern_beats_gru_tcn_count', count);
end

function r = local_rank_for(T, controller)
r = NaN;
mask = strcmp(string(T.controller), controller);
if any(mask) && ismember('overall_rank', T.Properties.VariableNames)
    r = T.overall_rank(find(mask, 1, 'first'));
end
end

function row = local_case_row()
row = struct();
row.case_tag = "";
row.path_tag = "";
row.path_file = "";
row.disturbance_level = NaN;
row.seed = NaN;
row.noise_scale = NaN;
row.process_scale = NaN;
row.noise_enabled = false;
row.noise_signature = NaN;
row.process_signature = NaN;
row.out_dir = "";
row.modern_file = "";
row.gru_file = "";
row.tcn_file = "";
row.summary_file = "";
row.rank_file = "";
row.report_file = "";
row.status = "pending";
row.message = "";
end
