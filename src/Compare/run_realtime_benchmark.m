function result = run_realtime_benchmark(cfg)
%RUN_REALTIME_BENCHMARK Summarize ModernTCN closed-loop timing metrics.
%
% This script combines:
%   1) ONNXRuntime single-window timing written by benchmark_modern_tcn_onnx_runtime.py
%   2) MATLAB online replay timing for ModernTCN_state_classifier('update', ...)
%   3) MPC solve-time samples already logged as diag_solve_time_ms
%   4) Simulink wall-time metadata from existing closed-loop outputs

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_defaults(cfg, root);
local_ensure_dir(cfg.out_root);

params = parameters();
Ts = local_field_or_default(params, 'Ts', 0.01);
Ts_ms = 1000 * double(Ts);

fprintf('[realtime] output root: %s\n', cfg.out_root);
fprintf('[realtime] Ts = %.6g ms\n', Ts_ms);

[replay_raw, replay_summary] = local_run_matlab_replay(cfg, params, Ts_ms);
[mpc_raw, mpc_summary, wall_summary] = local_collect_closed_loop_timing(cfg, Ts_ms);
onnx_summary = local_read_onnx_summary(cfg.onnx_summary_file, Ts_ms);
summary = local_build_summary(onnx_summary, replay_summary, mpc_summary, wall_summary, Ts_ms);

raw_replay_file = fullfile(cfg.out_root, 'realtime_matlab_replay_raw.csv');
replay_summary_file = fullfile(cfg.out_root, 'realtime_matlab_replay_summary.csv');
mpc_raw_file = fullfile(cfg.out_root, 'realtime_mpc_solve_raw.csv');
mpc_summary_file = fullfile(cfg.out_root, 'realtime_mpc_solve_summary.csv');
wall_summary_file = fullfile(cfg.out_root, 'realtime_simulink_wall_summary.csv');
summary_file = fullfile(cfg.out_root, 'realtime_summary.csv');
report_file = fullfile(cfg.out_root, 'realtime_report.md');
mat_file = fullfile(cfg.out_root, 'realtime_result.mat');

if ~isempty(replay_raw), writetable(replay_raw, raw_replay_file); end
if ~isempty(replay_summary), writetable(replay_summary, replay_summary_file); end
if ~isempty(mpc_raw), writetable(mpc_raw, mpc_raw_file); end
if ~isempty(mpc_summary), writetable(mpc_summary, mpc_summary_file); end
if ~isempty(wall_summary), writetable(wall_summary, wall_summary_file); end
if ~isempty(summary), writetable(summary, summary_file); end

result = struct();
result.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.cfg = cfg;
result.Ts = Ts;
result.Ts_ms = Ts_ms;
result.onnx_summary = onnx_summary;
result.replay_raw = replay_raw;
result.replay_summary = replay_summary;
result.mpc_raw = mpc_raw;
result.mpc_summary = mpc_summary;
result.wall_summary = wall_summary;
result.summary = summary;
result.summary_file = summary_file;
result.report_file = report_file;
result.mat_file = mat_file;

save(mat_file, 'result', '-v7.3');
local_write_report(report_file, result);

fprintf('[realtime] summary: %s\n', summary_file);
fprintf('[realtime] report:  %s\n', report_file);
end

function cfg = local_defaults(cfg, root)
cfg.out_root = local_cfg(cfg, 'out_root', ...
    fullfile(root, 'results', 'compare', 'realtime_benchmark'));
cfg.warmup_sec = local_cfg(cfg, 'warmup_sec', 1.0);
cfg.predict_warmup_count = local_cfg(cfg, 'predict_warmup_count', 20);
cfg.max_replay_steps = local_cfg(cfg, 'max_replay_steps', 0);
cfg.onnx_summary_file = local_cfg(cfg, 'onnx_summary_file', ...
    fullfile(cfg.out_root, 'realtime_onnx_runtime_summary.csv'));

default_files = { ...
    fullfile(root, 'results', 'compare', 'multipath_closed_loop', ...
        'path_closed_loop_long_updown_theta10_v1', 'ModernTCN_out.mat')
    fullfile(root, 'results', 'compare', 'multipath_closed_loop', ...
        'path_closed_loop_sharp_turn_transition_theta10_v1', 'ModernTCN_out.mat')};
default_files = default_files(cellfun(@(p) exist(p, 'file') == 2, default_files));
if isempty(default_files)
    d = dir(fullfile(root, 'results', 'compare', '**', 'ModernTCN_out.mat'));
    default_files = arrayfun(@(x) fullfile(x.folder, x.name), d, 'UniformOutput', false);
end
cfg.closed_loop_files = local_cfg(cfg, 'closed_loop_files', default_files);
if ischar(cfg.closed_loop_files) || isstring(cfg.closed_loop_files)
    cfg.closed_loop_files = cellstr(cfg.closed_loop_files);
end
cfg.replay_file = local_cfg(cfg, 'replay_file', cfg.closed_loop_files{1});
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

function [raw_table, summary_table] = local_run_matlab_replay(cfg, params, Ts_ms)
raw_table = table();
summary_table = table();
if isempty(cfg.replay_file) || exist(cfg.replay_file, 'file') ~= 2
    warning('run_realtime_benchmark:MissingReplay', ...
        'Replay file not found: %s', string(cfg.replay_file));
    return;
end

S = load(cfg.replay_file, 'logsout');
yts = local_get_signal(S.logsout, 'diag.y_raw');
if isempty(yts)
    warning('run_realtime_benchmark:MissingYRaw', ...
        'diag.y_raw not found in %s', cfg.replay_file);
    return;
end

t = double(yts.Time(:));
Y = local_timeseries_rows(yts.Data, numel(t));
n = size(Y, 1);
if cfg.max_replay_steps > 0
    n = min(n, cfg.max_replay_steps);
    Y = Y(1:n, :);
    t = t(1:n);
end

clear ModernTCN_state_classifier ModernTCN_load_predictor ModernTCN_predict_window
init_timer = tic;
state = ModernTCN_state_classifier('init', params);
init_ms = 1000 * toc(init_timer);

elapsed_ms = nan(n, 1);
did_predict = false(n, 1);
ready = false(n, 1);
buffer_count = nan(n, 1);
predict_index = nan(n, 1);
predict_count = 0;

for i = 1:n
    yi = double(Y(i, :)).';
    one_timer = tic;
    [state, out] = ModernTCN_state_classifier('update', state, yi);
    elapsed_ms(i) = 1000 * toc(one_timer);
    if isstruct(out) && isfield(out, 'debug')
        dbg = out.debug;
        if isfield(dbg, 'did_predict'), did_predict(i) = logical(dbg.did_predict); end
        if isfield(dbg, 'ready'), ready(i) = logical(dbg.ready); end
        if isfield(dbg, 'buffer_count'), buffer_count(i) = double(dbg.buffer_count); end
    end
    if did_predict(i)
        predict_count = predict_count + 1;
        predict_index(i) = predict_count;
    end
end

raw_table = table( ...
    repmat(string(cfg.replay_file), n, 1), (1:n).', t(:), elapsed_ms, ...
    did_predict, ready, buffer_count, predict_index, ...
    'VariableNames', {'source_file','step_index','time_s','elapsed_ms', ...
    'did_predict','ready','buffer_count','predict_index'});

warm_mask = t(:) >= double(cfg.warmup_sec);
predict_steady_mask = warm_mask & did_predict & ...
    predict_index > double(cfg.predict_warmup_count);
rows = repmat(local_stats_row("", [], Ts_ms), 0, 1);
rows(end+1) = local_stats_row("matlab_replay_update_all", elapsed_ms(warm_mask), Ts_ms); %#ok<AGROW>
rows(end+1) = local_stats_row("matlab_replay_update_predict_all", ...
    elapsed_ms(warm_mask & did_predict), Ts_ms); %#ok<AGROW>
rows(end+1) = local_stats_row("matlab_replay_update_predict_steady", ...
    elapsed_ms(predict_steady_mask), Ts_ms); %#ok<AGROW>
rows(end+1) = local_stats_row("matlab_replay_init_once", init_ms, Ts_ms); %#ok<AGROW>
summary_table = struct2table(rows);
summary_table.source_file = repmat(string(cfg.replay_file), height(summary_table), 1);
summary_table.warmup_sec = repmat(double(cfg.warmup_sec), height(summary_table), 1);
summary_table.predict_warmup_count = repmat(double(cfg.predict_warmup_count), height(summary_table), 1);
end

function [raw_table, summary_table, wall_table] = local_collect_closed_loop_timing(cfg, Ts_ms)
raw_table = table();
summary_table = table();
wall_table = table();

all_values = [];
all_sources = strings(0, 1);
all_t = [];
wall_rows = repmat(local_wall_row(), 0, 1);

for i = 1:numel(cfg.closed_loop_files)
    file = cfg.closed_loop_files{i};
    if exist(file, 'file') ~= 2
        warning('run_realtime_benchmark:MissingClosedLoopFile', ...
            'Closed-loop output not found: %s', file);
        continue;
    end
    S = load(file, 'logsout', 'SimulationMetadata');
    sts = local_get_signal(S.logsout, 'diag_solve_time_ms');
    if ~isempty(sts)
        vals = double(sts.Data(:));
        t = double(sts.Time(:));
        if numel(t) ~= numel(vals)
            t = (0:numel(vals)-1).' * (Ts_ms / 1000);
        end
        mask = isfinite(vals) & t >= double(cfg.warmup_sec);
        vals = vals(mask);
        t = t(mask);
        all_values = [all_values; vals(:)]; %#ok<AGROW>
        all_sources = [all_sources; repmat(string(file), numel(vals), 1)]; %#ok<AGROW>
        all_t = [all_t; t(:)]; %#ok<AGROW>
    end

    if isfield(S, 'SimulationMetadata')
        wall_rows(end+1) = local_extract_wall_row(file, S.SimulationMetadata, S.logsout, Ts_ms); %#ok<AGROW>
    end
end

if ~isempty(all_values)
    raw_table = table(all_sources, all_t, all_values, ...
        'VariableNames', {'source_file','time_s','solve_time_ms'});
    rows = repmat(local_stats_row("", [], Ts_ms), 0, 1);
    rows(end+1) = local_stats_row("mpc_solve_time", all_values, Ts_ms); %#ok<AGROW>
    summary_table = struct2table(rows);
    summary_table.source_file = repmat("aggregate_closed_loop_files", height(summary_table), 1);
    summary_table.warmup_sec = repmat(double(cfg.warmup_sec), height(summary_table), 1);
end

if ~isempty(wall_rows)
    wall_table = struct2table(wall_rows);
end
end

function T = local_read_onnx_summary(summary_file, Ts_ms)
T = table();
if exist(summary_file, 'file') ~= 2
    warning('run_realtime_benchmark:MissingONNXSummary', ...
        'ONNX summary not found: %s', summary_file);
    return;
end
S = readtable(summary_file, 'TextType', 'string');
if isempty(S)
    return;
end
row = local_stats_row("onnxruntime_single_window", S.mean_ms(1), Ts_ms);
row.n = S.n(1);
row.mean_ms = S.mean_ms(1);
row.std_ms = local_table_value(S, 'std_ms', 1, NaN);
row.min_ms = local_table_value(S, 'min_ms', 1, NaN);
row.p50_ms = S.p50_ms(1);
row.p95_ms = S.p95_ms(1);
row.p99_ms = local_table_value(S, 'p99_ms', 1, NaN);
row.max_ms = S.max_ms(1);
row.overrun_rate_vs_Ts = double(row.max_ms > Ts_ms);
row.margin_p95_ms = Ts_ms - row.p95_ms;
row.pass_p95 = row.p95_ms < Ts_ms;
T = struct2table(row);
T.source_file = string(summary_file);
end

function summary = local_build_summary(onnx_summary, replay_summary, mpc_summary, wall_summary, Ts_ms)
rows = repmat(local_summary_row(), 0, 1);

if ~isempty(onnx_summary)
    rows(end+1) = local_summary_from_stats(onnx_summary(1, :), ...
        "onnxruntime_single_window", "python_onnxruntime", Ts_ms); %#ok<AGROW>
end
if ~isempty(replay_summary)
    idx = find(strcmp(string(replay_summary.metric), "matlab_replay_update_predict_steady"), 1);
    if ~isempty(idx)
        rows(end+1) = local_summary_from_stats(replay_summary(idx, :), ...
            "matlab_replay_update_predict_steady", "matlab_replay", Ts_ms); %#ok<AGROW>
    end
    idx = find(strcmp(string(replay_summary.metric), "matlab_replay_update_predict_all"), 1);
    if ~isempty(idx)
        rows(end+1) = local_summary_from_stats(replay_summary(idx, :), ...
            "matlab_replay_update_predict_all", "matlab_replay", Ts_ms); %#ok<AGROW>
    end
    idx = find(strcmp(string(replay_summary.metric), "matlab_replay_update_all"), 1);
    if ~isempty(idx)
        rows(end+1) = local_summary_from_stats(replay_summary(idx, :), ...
            "matlab_replay_update_all", "matlab_replay", Ts_ms); %#ok<AGROW>
    end
end
if ~isempty(mpc_summary)
    rows(end+1) = local_summary_from_stats(mpc_summary(1, :), ...
        "mpc_solve_time", "closed_loop_logsout", Ts_ms); %#ok<AGROW>
end

if ~isempty(onnx_summary) && ~isempty(mpc_summary)
    rows(end+1) = local_cycle_row("cycle_onnxruntime_plus_mpc", ...
        onnx_summary(1, :), mpc_summary(1, :), "p95 sum of ONNXRuntime and MPC", Ts_ms); %#ok<AGROW>
end
if ~isempty(replay_summary) && ~isempty(mpc_summary)
    idx = find(strcmp(string(replay_summary.metric), "matlab_replay_update_predict_steady"), 1);
    if ~isempty(idx)
        rows(end+1) = local_cycle_row("cycle_matlab_replay_plus_mpc", ...
            replay_summary(idx, :), mpc_summary(1, :), "p95 sum of MATLAB replay and MPC", Ts_ms); %#ok<AGROW>
    end
end

if ~isempty(wall_summary)
    row = local_summary_row();
    row.metric = "simulink_wall_per_step";
    row.source = "SimulationMetadata.TimingInfo";
    row.n = height(wall_summary);
    vals = wall_summary.wall_ms_per_step;
    row.mean_ms = mean(vals, 'omitnan');
    row.p50_ms = median(vals, 'omitnan');
    row.p95_ms = max(vals);
    row.max_ms = max(vals);
    row.margin_p95_ms = Ts_ms - row.p95_ms;
    row.pass_p95 = row.p95_ms < Ts_ms;
    row.note = "desktop simulation wall time, not embedded controller compute time";
    rows(end+1) = row; %#ok<AGROW>
end

summary = struct2table(rows);
end

function row = local_stats_row(metric, values, Ts_ms)
values = double(values(:));
values = values(isfinite(values));
row = struct();
row.metric = string(metric);
row.n = numel(values);
row.mean_ms = NaN;
row.std_ms = NaN;
row.min_ms = NaN;
row.p50_ms = NaN;
row.p95_ms = NaN;
row.p99_ms = NaN;
row.max_ms = NaN;
row.overrun_rate_vs_Ts = NaN;
row.margin_p95_ms = NaN;
row.pass_p95 = false;
if isempty(values)
    return;
end
row.mean_ms = mean(values);
row.std_ms = std(values, 0);
row.min_ms = min(values);
row.p50_ms = prctile(values, 50);
row.p95_ms = prctile(values, 95);
row.p99_ms = prctile(values, 99);
row.max_ms = max(values);
row.overrun_rate_vs_Ts = mean(values > Ts_ms);
row.margin_p95_ms = Ts_ms - row.p95_ms;
row.pass_p95 = row.p95_ms < Ts_ms;
end

function row = local_summary_row()
row = struct();
row.metric = "";
row.source = "";
row.n = NaN;
row.mean_ms = NaN;
row.p50_ms = NaN;
row.p95_ms = NaN;
row.max_ms = NaN;
row.overrun_rate_vs_Ts = NaN;
row.margin_p95_ms = NaN;
row.pass_p95 = false;
row.note = "";
end

function row = local_summary_from_stats(T, metric, source, Ts_ms)
row = local_summary_row();
row.metric = string(metric);
row.source = string(source);
row.n = T.n(1);
row.mean_ms = T.mean_ms(1);
row.p50_ms = T.p50_ms(1);
row.p95_ms = T.p95_ms(1);
row.max_ms = T.max_ms(1);
row.overrun_rate_vs_Ts = T.overrun_rate_vs_Ts(1);
row.margin_p95_ms = Ts_ms - row.p95_ms;
row.pass_p95 = row.p95_ms < Ts_ms;
end

function row = local_cycle_row(metric, A, B, note, Ts_ms)
row = local_summary_row();
row.metric = string(metric);
row.source = "computed_sum";
row.n = min(A.n(1), B.n(1));
row.mean_ms = A.mean_ms(1) + B.mean_ms(1);
row.p50_ms = A.p50_ms(1) + B.p50_ms(1);
row.p95_ms = A.p95_ms(1) + B.p95_ms(1);
row.max_ms = A.max_ms(1) + B.max_ms(1);
row.overrun_rate_vs_Ts = NaN;
row.margin_p95_ms = Ts_ms - row.p95_ms;
row.pass_p95 = row.p95_ms < Ts_ms;
row.note = string(note);
end

function row = local_wall_row()
row = struct();
row.source_file = "";
row.num_steps = NaN;
row.execution_wall_s = NaN;
row.total_wall_s = NaN;
row.wall_ms_per_step = NaN;
row.execution_to_model_time_ratio = NaN;
end

function row = local_extract_wall_row(file, meta, logsout, Ts_ms)
row = local_wall_row();
row.source_file = string(file);
row.num_steps = local_num_steps(logsout);
if isprop(meta, 'TimingInfo') || isfield(meta, 'TimingInfo')
    ti = meta.TimingInfo;
    row.execution_wall_s = local_field_or_default(ti, 'ExecutionElapsedWallTime', NaN);
    row.total_wall_s = local_field_or_default(ti, 'TotalElapsedWallTime', NaN);
end
if isfinite(row.execution_wall_s) && row.num_steps > 0
    row.wall_ms_per_step = 1000 * row.execution_wall_s / row.num_steps;
    model_time_s = row.num_steps * Ts_ms / 1000;
    row.execution_to_model_time_ratio = row.execution_wall_s / model_time_s;
end
end

function n = local_num_steps(logsout)
n = NaN;
for i = 1:logsout.numElements
    e = logsout.get(i);
    if isa(e.Values, 'timeseries')
        n = numel(e.Values.Time);
        return;
    end
end
end

function ts = local_get_signal(logsout, name)
ts = [];
if ~isa(logsout, 'Simulink.SimulationData.Dataset')
    return;
end
for i = 1:logsout.numElements
    e = logsout.get(i);
    if strcmp(e.Name, name)
        ts = e.Values;
        return;
    end
end
end

function Y = local_timeseries_rows(data, n_time)
D = squeeze(data);
sz = size(D);
if isvector(D)
    Y = double(D(:));
    return;
end
if sz(1) == n_time
    Y = double(reshape(D, n_time, []));
elseif sz(end) == n_time
    Y = double(reshape(D, [], n_time).');
elseif numel(sz) >= 2 && sz(2) == n_time
    Y = double(reshape(permute(D, [2 1 3:ndims(D)]), n_time, []));
else
    error('run_realtime_benchmark:BadTimeseriesShape', ...
        'Cannot align data shape %s with %d time samples.', mat2str(sz), n_time);
end
end

function v = local_table_value(T, name, row, default_value)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(row);
else
    v = default_value;
end
end

function v = local_field_or_default(s, name, default_value)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    try
        v = s.(name);
    catch
        v = default_value;
    end
end
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w');
if fid < 0
    warning('run_realtime_benchmark:ReportFailed', 'Cannot write %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Real-Time Benchmark\n\n');
fprintf(fid, '- timestamp: `%s`\n', result.timestamp);
fprintf(fid, '- Ts: `%.6g ms`\n', result.Ts_ms);
fprintf(fid, '- output root: `%s`\n\n', result.cfg.out_root);

fprintf(fid, '## Summary\n\n');
local_write_markdown_table(fid, result.summary);

fprintf(fid, '\n## Notes\n\n');
fprintf(fid, '- `onnxruntime_single_window` is pure batch=1 ONNXRuntime inference.\n');
fprintf(fid, '- `matlab_replay_update_predict_steady` replays closed-loop `diag.y_raw` through the MATLAB online wrapper after the sliding window is ready and after the configured first-predict warmup count.\n');
fprintf(fid, '- `mpc_solve_time` comes from `diag_solve_time_ms` in closed-loop logs after the configured warmup period.\n');
fprintf(fid, '- `simulink_wall_per_step` is desktop Simulink wall time and is not used as embedded controller compute time.\n');
end

function local_write_markdown_table(fid, T)
if isempty(T)
    fprintf(fid, '_No timing summary available._\n');
    return;
end
fprintf(fid, '| metric | mean ms | p50 ms | p95 ms | max ms | p95 margin ms | pass p95 |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %.6g | %.6g | %.6g | %.6g | %.6g | %d |\n', ...
        string(T.metric(i)), T.mean_ms(i), T.p50_ms(i), T.p95_ms(i), ...
        T.max_ms(i), T.margin_p95_ms(i), T.pass_p95(i));
end
end
