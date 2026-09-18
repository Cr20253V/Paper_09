function results = run_compare_mamba2_gru_imu_batch(cfg)
% =============================
% 文件名：run_compare_mamba2_gru_imu_batch.m
% 版本号：V1.1（批量闭环对比执行器）
% 最后修改时间：2026-04-17
% 作者：LPV-MPC Project
% 功能描述：
%   对 Mamba2 / GRU / IMU 三配置执行闭环批量仿真。
%   按 控制器 x 路径 x 扰动等级 x 随机种子 生成完整矩阵。
%
% 使用方法：
%   results = run_compare_mamba2_gru_imu_batch();
%   results = run_compare_mamba2_gru_imu_batch(cfg);
%
% 关键约束：
%   - 本脚本独立运行，不调用 test_simulink_closed_loop.m。
%   - 依赖各模型自身 PreLoadFcn 已正确完成控制器/模型加载。
%
% 输入 cfg（常用字段）：
%   cfg.controllers        : {'Mamba2','GRU','IMU'}
%   cfg.path_mode          : segmented / full150 / hybrid（仅在未显式给 path_files 时生效）
%   cfg.path_files         : 路径文件列表（*.mat，内部含 ref）
%   cfg.disturbance_levels : 扰动等级，默认 [0 1 2]
%   cfg.seeds              : 随机种子数组
%   cfg.mamba_ai_backend   : Mamba 后端（tcp_service / matlab_stub）
%   cfg.save_timeseries    : 是否保存每个 case 的时序数据
%
% 输出：
%   results 结构体，以及以下文件：
%   - results/.../raw/case_rows.mat
%   - results/.../raw/case_rows.csv
%   - results/.../raw/summary_by_controller.csv
% =============================

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_apply_defaults(cfg, root);

cases = local_build_cases(cfg);
if isempty(cases)
    error('No simulation cases were built. Check cfg.controllers / cfg.path_files / cfg.seeds.');
end

% 为避免模型已加载导致 PreLoadFcn 不触发，引入可选的预关闭步骤。
if cfg.force_close_loaded_models
    loaded_names = unique({cases.model_name});
    for kk = 1:numel(loaded_names)
        one = loaded_names{kk};
        if bdIsLoaded(one)
            close_system(one, 0);
        end
    end
end

run_id = ['compare_' datestr(now, 'yyyymmdd_HHMMSS')];
run_dir = results_dir(fullfile('compare', 'mamba2_gru_imu', run_id));
raw_dir = fullfile(run_dir, 'raw');
if ~exist(raw_dir, 'dir')
    mkdir(raw_dir);
end

fprintf('\n[compare] run_id = %s\n', run_id);
fprintf('[compare] output = %s\n', run_dir);
fprintf('[compare] total cases = %d\n\n', numel(cases));

rows = repmat(local_row_template(), numel(cases), 1);

for i = 1:numel(cases)
    one = cases(i);
    fprintf('[%4d/%4d] %-6s | %s | d=%d | seed=%d\n', ...
        i, numel(cases), one.controller, one.path_name, one.disturbance_level, one.seed);

    t0 = tic;
    row = local_row_template();
    row.case_index = i;
    row.controller = one.controller;
    row.model_name = one.model_name;
    row.path_name = one.path_name;
    row.path_file = one.path_file;
    row.disturbance_level = one.disturbance_level;
    row.seed = one.seed;

    try
        [ref, ref_file] = local_load_ref(one.path_file);
        row.ref_file = ref_file;

        if ~exist(one.model_file, 'file')
            error('Missing model file: %s', one.model_file);
        end

        if ~bdIsLoaded(one.model_name)
            load_system(one.model_file);
        end

        params = parameters();
        [params, ff_rt, dist_meta] = local_apply_disturbance(params, one.disturbance_level, one.seed, cfg);
        row.disturbance_scale = dist_meta.scale;
        row.disturbance_noise_scale = dist_meta.noise_scale;
        row.disturbance_process_scale = dist_meta.process_scale;
        row.noise_enabled = dist_meta.enable_noise;
        row.noise_signature = dist_meta.noise_signature;
        row.process_signature = dist_meta.process_signature;

        % Allow explicit backend switch for Mamba2 if user needs stub mode.
        if strcmpi(one.controller, 'Mamba2')
            params.ai_backend = cfg.mamba_ai_backend;
            params.mamba_server_host = cfg.mamba_host;
            params.mamba_server_port = cfg.mamba_port;
            params.mamba_conn_timeout = cfg.mamba_conn_timeout;
            params.mamba_read_timeout = cfg.mamba_read_timeout;
        end

        stop_time = num2str(ref.t(end));

        simIn = Simulink.SimulationInput(one.model_name);
        simIn = simIn.setModelParameter('StopTime', stop_time);
        % 写入 base + model workspace，兼容不同模型的变量解析策略。
        simIn = local_set_variable_dual(simIn, one.model_name, 'params', params);
        % 兼容 S-Function 参数表达式写成 `parameters` 的模型（如 GRU 基线模型）。
        simIn = local_set_variable_dual(simIn, one.model_name, 'parameters', params);
        simIn = local_set_variable_dual(simIn, one.model_name, 'ff_rt', ff_rt);
        simIn = local_set_variable_dual(simIn, one.model_name, 'ref', ref);
        simIn = local_set_variable_dual(simIn, one.model_name, 'compare_seed', one.seed);
        simIn = local_set_variable_dual(simIn, one.model_name, 'compare_disturbance_level', one.disturbance_level);
        simIn = simIn.setPreSimFcn(@(in) local_pre_sim(in, one.seed));

        simOut = sim(simIn);
        if isprop(simOut, 'ErrorMessage') && ~isempty(simOut.ErrorMessage)
            error('Simulation error: %s', simOut.ErrorMessage);
        end

        logs = simOut.logsout;
        if isempty(logs)
            error('logsout is empty. Ensure signal logging is enabled in model.');
        end

        metrics = local_compute_metrics(logs, ref, cfg);

        row.status = 'ok';
        row.message = '';
        row.n_samples = metrics.n_samples;
        row.ey_rmse = metrics.ey_rmse;
        row.ey_peak = metrics.ey_peak;
        row.epsi_rmse = metrics.epsi_rmse;
        row.epsi_peak = metrics.epsi_peak;
        row.ev_rmse = metrics.ev_rmse;
        row.eomega_rmse = metrics.eomega_rmse;
        row.j_du = metrics.j_du;
        row.viol_rate = metrics.viol_rate;
        row.F_sat_pct = metrics.F_sat_pct;
        row.omega_sat_pct = metrics.omega_sat_pct;
        row.realtime_p50_ms = metrics.realtime_p50_ms;
        row.realtime_p95_ms = metrics.realtime_p95_ms;
        row.realtime_p99_ms = metrics.realtime_p99_ms;
        row.timeout_rate = metrics.timeout_rate;

        if cfg.save_timeseries
            ts_file = fullfile(raw_dir, sprintf('timeseries_case_%04d.mat', i));
            t = metrics.t; %#ok<NASGU>
            e_y = metrics.e_y; %#ok<NASGU>
            e_psi = metrics.e_psi; %#ok<NASGU>
            v = metrics.v; %#ok<NASGU>
            omega = metrics.omega; %#ok<NASGU>
            F_cmd = metrics.F_cmd; %#ok<NASGU>
            omega_cmd = metrics.omega_cmd; %#ok<NASGU>
            save(ts_file, 't', 'e_y', 'e_psi', 'v', 'omega', 'F_cmd', 'omega_cmd');
            row.timeseries_file = ts_file;
        end

    catch ME
        row.status = 'error';
        row.message = ME.message;
    end

    row.elapsed_sec = toc(t0);
    rows(i) = row;

    if mod(i, cfg.save_every) == 0 || i == numel(cases)
        partial.results = struct();
        partial.results.run_id = run_id;
        partial.results.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        partial.results.cfg = cfg;
        partial.results.rows = rows(1:i);
        partial_file = fullfile(raw_dir, 'case_rows_partial.mat');
        save(partial_file, '-struct', 'partial');
    end
end

results = struct();
results.run_id = run_id;
results.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
results.cfg = cfg;
results.rows = rows;

T = struct2table(rows);
summary_tbl = local_summary_table(T, cfg.metric_fields);

save(fullfile(raw_dir, 'case_rows.mat'), 'results', 'T', 'summary_tbl', '-v7.3');
writetable(T, fullfile(raw_dir, 'case_rows.csv'));
writetable(summary_tbl, fullfile(raw_dir, 'summary_by_controller.csv'));

fprintf('\n[compare] done: %s\n', fullfile(raw_dir, 'case_rows.mat'));

end

function in = local_pre_sim(in, seed)
rng(double(seed), 'twister');
in = in.setVariable('rng_seed_runtime', double(seed));
end

function simIn = local_set_variable_dual(simIn, model_name, var_name, var_value)
% 同时写入 base 与 model workspace，避免 callback 或 block 仅从其一读取变量。
simIn = simIn.setVariable(var_name, var_value);
simIn = simIn.setVariable(var_name, var_value, 'Workspace', model_name);
end

function cfg = local_apply_defaults(cfg, root)
% 默认值集中定义：方便后续做全量/冒烟切换。
if ~isfield(cfg, 'controllers') || isempty(cfg.controllers)
    cfg.controllers = {'Mamba2', 'GRU', 'IMU'};
end
if ~isfield(cfg, 'model_dir') || isempty(cfg.model_dir)
    cfg.model_dir = fullfile(root, 'simulink');
end
if ~isfield(cfg, 'model_map') || ~isstruct(cfg.model_map)
    cfg.model_map = struct();
end
if ~isfield(cfg.model_map, 'Mamba2')
    cfg.model_map.Mamba2 = 'LPVMPC_AGV_simulink_Mamba';
end
if ~isfield(cfg.model_map, 'GRU')
    cfg.model_map.GRU = local_pick_existing_model_name(cfg.model_dir, ...
        {'LPVMPC_AGV_simulink_GRU', 'LPVMPC_AGV_simulink'});
end
if ~isfield(cfg.model_map, 'IMU')
    cfg.model_map.IMU = 'LPVMPC_AGV_simulink_IMU';
end

if ~isfield(cfg, 'path_mode') || isempty(cfg.path_mode)
    % segmented: 快速覆盖多类工况（默认）
    % full150  : 与 150s 工业路径训练分布更一致
    % hybrid   : 150s 主路径 + 少量典型分段
    cfg.path_mode = 'segmented';
end

if ~isfield(cfg, 'path_files') || isempty(cfg.path_files)
    cfg.path_files = local_default_path_files(root, cfg.path_mode);
end

if ~isfield(cfg, 'disturbance_levels') || isempty(cfg.disturbance_levels)
    cfg.disturbance_levels = [0 1 2];
end
if ~isfield(cfg, 'seeds') || isempty(cfg.seeds)
    % 默认给全量，主入口可覆盖为冒烟 (1:3)
    cfg.seeds = 1:10;
end
if ~isfield(cfg, 'save_every') || isempty(cfg.save_every)
    cfg.save_every = 10;
end
if ~isfield(cfg, 'save_timeseries') || isempty(cfg.save_timeseries)
    cfg.save_timeseries = false;
end
if ~isfield(cfg, 'ignore_initial_sec') || isempty(cfg.ignore_initial_sec)
    cfg.ignore_initial_sec = 0.5;
end
if ~isfield(cfg, 'force_bound') || isempty(cfg.force_bound)
    cfg.force_bound = [-600, 600];
end
if ~isfield(cfg, 'omega_bound') || isempty(cfg.omega_bound)
    cfg.omega_bound = [-1.2, 1.2];
end
if ~isfield(cfg, 'disturbance_scale') || isempty(cfg.disturbance_scale)
    % index by level+1 for levels 0,1,2
    cfg.disturbance_scale = [0.0, 1.0, 1.5];
end
if ~isfield(cfg, 'disturbance_mode') || isempty(cfg.disturbance_mode)
    % noise_only: 仅缩放测量噪声；hybrid: 噪声+植物参数微扰（默认）。
    cfg.disturbance_mode = 'hybrid';
end
if ~isfield(cfg, 'disturbance_process_scale') || isempty(cfg.disturbance_process_scale)
    % index by level+1 for levels 0,1,2
    cfg.disturbance_process_scale = [0.0, 0.35, 0.70];
end
if ~isfield(cfg, 'sample_time') || isempty(cfg.sample_time)
    p = parameters();
    cfg.sample_time = p.Ts;
end
if ~isfield(cfg, 'mamba_ai_backend') || isempty(cfg.mamba_ai_backend)
    cfg.mamba_ai_backend = 'tcp_service';
end
if ~isfield(cfg, 'mamba_host') || isempty(cfg.mamba_host)
    % 与 Mamba_state_classifier 的默认值保持一致
    cfg.mamba_host = '172.31.248.4';
end
if ~isfield(cfg, 'mamba_port') || isempty(cfg.mamba_port)
    cfg.mamba_port = 5009;
end
if ~isfield(cfg, 'mamba_conn_timeout') || isempty(cfg.mamba_conn_timeout)
    cfg.mamba_conn_timeout = 3.0;
end
if ~isfield(cfg, 'mamba_read_timeout') || isempty(cfg.mamba_read_timeout)
    cfg.mamba_read_timeout = 25.0;
end
if ~isfield(cfg, 'metric_fields') || isempty(cfg.metric_fields)
    cfg.metric_fields = {'ey_rmse', 'epsi_rmse', 'ev_rmse', 'eomega_rmse', 'j_du', 'viol_rate'};
end
if ~isfield(cfg, 'force_close_loaded_models')
    cfg.force_close_loaded_models = true;
end
end

function cases = local_build_cases(cfg)
cases = struct('controller', {}, 'model_name', {}, 'model_file', {}, ...
    'path_name', {}, 'path_file', {}, 'seed', {}, 'disturbance_level', {});

idx = 0;
for i = 1:numel(cfg.controllers)
    ctrl_name = cfg.controllers{i};
    if ~isfield(cfg.model_map, ctrl_name)
        error('Missing model_map.%s', ctrl_name);
    end
    model_name = cfg.model_map.(ctrl_name);
    model_file = fullfile(cfg.model_dir, [model_name '.slx']);

    for p = 1:numel(cfg.path_files)
        path_file = cfg.path_files{p};
        [~, path_name, ~] = fileparts(path_file);
        for d = 1:numel(cfg.disturbance_levels)
            dlev = cfg.disturbance_levels(d);
            for s = 1:numel(cfg.seeds)
                seed = cfg.seeds(s);
                idx = idx + 1;
                cases(idx).controller = ctrl_name; %#ok<AGROW>
                cases(idx).model_name = model_name; %#ok<AGROW>
                cases(idx).model_file = model_file; %#ok<AGROW>
                cases(idx).path_name = path_name; %#ok<AGROW>
                cases(idx).path_file = path_file; %#ok<AGROW>
                cases(idx).seed = seed; %#ok<AGROW>
                cases(idx).disturbance_level = dlev; %#ok<AGROW>
            end
        end
    end
end
end

function [ref, ref_file] = local_load_ref(path_file)
if ~exist(path_file, 'file')
    error('Path file not found: %s', path_file);
end

S = load(path_file);
if ~isfield(S, 'ref')
    error('Path file has no ref variable: %s', path_file);
end
ref = S.ref;
ref_file = path_file;

req = {'t','X_ref','Y_ref','psi_ref','v_ref','omega_ref'};
for i = 1:numel(req)
    if ~isfield(ref, req{i})
        error('ref is missing field %s in %s', req{i}, path_file);
    end
end

if any(~isfinite(ref.t)) || any(diff(ref.t) <= 0)
    error('ref.t is not strictly increasing in %s', path_file);
end
end

function [params, ff_rt, meta] = local_apply_disturbance(params, level, seed, cfg)
% 扰动策略：默认采用“噪声 + 植物参数微扰”的混合注入。
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

ff_rt = struct('m', params.mass, ...
               'g', params.gravity, ...
               'c_r', params.rolling_resistance, ...
               'rho', params.air_density, ...
               'CdA', params.drag_coefficient_area);

meta = struct();
meta.scale = noise_scale;
meta.noise_scale = noise_scale;
meta.process_scale = proc_scale;
meta.enable_noise = logical(params.enable_noise);
meta.noise_signature = local_noise_signature(params);
meta.process_signature = local_process_signature(params);
end

function sig = local_noise_signature(params)
fields = {'current_noise_std', 'wheel_speed_noise_std', 'disturbance_noise_std', ...
          'v_noise_std', 'psi_noise_std', 'omega_noise_std'};
acc = 0.0;
for i = 1:numel(fields)
    f = fields{i};
    if isfield(params, f) && isnumeric(params.(f))
        vv = params.(f);
        vv = vv(isfinite(vv));
        if ~isempty(vv)
            acc = acc + sum(abs(vv(:)));
        end
    end
end
sig = acc;
end

function sig = local_process_signature(params)
fields = {'mass', 'friction_coefficient', 'rolling_resistance', 'air_density', ...
          'drag_coefficient_area', 'front_cornering_stiffness', 'rear_cornering_stiffness'};
acc = 0.0;
for i = 1:numel(fields)
    f = fields{i};
    if isfield(params, f) && isnumeric(params.(f))
        vv = params.(f);
        vv = vv(isfinite(vv));
        if ~isempty(vv)
            acc = acc + sum(abs(vv(:)));
        end
    end
end
sig = acc;
end

function params = local_apply_process_disturbance(params, proc_scale)
% 对植物关键参数施加温和但可观测的微扰，提升扰动等级可分辨性。
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
if numel(scale_table) >= 3 && any(level == [0, 1, 2])
    scale = scale_table(level + 1);
else
    scale = 1.0 + 0.25 * double(level);
end
end

function metrics = local_compute_metrics(logs, ref, cfg)
% 统一指标口径：主指标 + 实时性 + 约束/饱和指标。
[t, e_y] = local_get_signal(logs, {'e_y', 'ey', 'diag.e_y'});
[~, e_psi_raw] = local_get_signal(logs, {'e_psi', 'epsi', 'diag.e_psi'});

if isempty(t) || isempty(e_y) || isempty(e_psi_raw)
    error('Required signals are missing: e_y / e_psi');
end

e_psi = local_align_to_time(e_psi_raw, t, t);

[tf, F_cmd_raw] = local_get_signal(logs, {'F_cmd', 'F', 'u1', 'diag.F_cmd'});
[to, omega_cmd_raw] = local_get_signal(logs, {'omega_cmd', 'w_cmd', 'u2', 'diag.omega_cmd'});
[tv, v_raw] = local_get_signal(logs, {'v', 'v_meas', 'diag.v'});
[tw, omega_raw] = local_get_signal(logs, {'omega', 'omega_meas', 'diag.omega'});
[tev, ev_raw] = local_get_signal(logs, {'e_v', 'ev', 'diag.e_v'});
[tew, eomega_raw] = local_get_signal(logs, {'e_omega', 'eomega', 'diag.e_omega', 'diag.eomega'});
[ts, solve_ms_raw] = local_get_signal(logs, {'solve_time_ms', 'mpc_solve_time_ms', 'solve_time', 'diag.solve_time_ms', 'diag.mpc_solve_time_ms'});

F_cmd = local_align_to_time(F_cmd_raw, tf, t);
omega_cmd = local_align_to_time(omega_cmd_raw, to, t);
v = local_align_to_time(v_raw, tv, t);
omega = local_align_to_time(omega_raw, tw, t);
solve_ms = local_align_to_time(solve_ms_raw, ts, t);

mask = t > cfg.ignore_initial_sec;
if nnz(mask) < 3
    mask = true(size(t));
end

dt = diff(t(mask));
if isempty(dt)
    dt = cfg.sample_time;
end

ey = e_y(mask);
epsi = e_psi(mask);

metrics = struct();
metrics.t = t;
metrics.e_y = e_y;
metrics.e_psi = e_psi;
metrics.v = v;
metrics.omega = omega;
metrics.F_cmd = F_cmd;
metrics.omega_cmd = omega_cmd;
metrics.n_samples = nnz(mask);

metrics.ey_rmse = local_rms(ey);
metrics.ey_peak = local_nanmax(abs(ey));
metrics.epsi_rmse = local_rms(epsi);
metrics.epsi_peak = local_nanmax(abs(epsi));

if ~isempty(v)
    v_ref = interp1(ref.t(:), ref.v_ref(:), t, 'linear', 'extrap');
    ev = v - v_ref;
    metrics.ev_rmse = local_rms(ev(mask));
elseif ~isempty(ev_raw)
    ev = local_align_to_time(ev_raw, tev, t);
    metrics.ev_rmse = local_rms(ev(mask));
else
    metrics.ev_rmse = NaN;
end

if ~isempty(omega)
    w_ref = interp1(ref.t(:), ref.omega_ref(:), t, 'linear', 'extrap');
    eomega = omega - w_ref;
    metrics.eomega_rmse = local_rms(eomega(mask));
elseif ~isempty(eomega_raw)
    eomega = local_align_to_time(eomega_raw, tew, t);
    metrics.eomega_rmse = local_rms(eomega(mask));
else
    metrics.eomega_rmse = NaN;
end

if ~isempty(F_cmd) && ~isempty(omega_cmd)
    Fm = F_cmd(mask);
    Om = omega_cmd(mask);
    dF = diff(Fm) ./ dt;
    dO = diff(Om) ./ dt;
    metrics.j_du = local_nanmean(dF.^2 + dO.^2);

    viol_F = (Fm < cfg.force_bound(1)) | (Fm > cfg.force_bound(2));
    viol_O = (Om < cfg.omega_bound(1)) | (Om > cfg.omega_bound(2));
    metrics.viol_rate = local_nanmean(double(viol_F | viol_O));

    metrics.F_sat_pct = 100.0 * local_nanmean(double(abs(Fm) >= 0.99 * max(abs(cfg.force_bound))));
    metrics.omega_sat_pct = 100.0 * local_nanmean(double(abs(Om) >= 0.99 * max(abs(cfg.omega_bound))));
else
    metrics.j_du = NaN;
    metrics.viol_rate = NaN;
    metrics.F_sat_pct = NaN;
    metrics.omega_sat_pct = NaN;
end

if ~isempty(solve_ms)
    sm = solve_ms(mask);
    metrics.realtime_p50_ms = local_percentile(sm, 50);
    metrics.realtime_p95_ms = local_percentile(sm, 95);
    metrics.realtime_p99_ms = local_percentile(sm, 99);
    metrics.timeout_rate = local_nanmean(double(sm > (cfg.sample_time * 1000.0)));
else
    metrics.realtime_p50_ms = NaN;
    metrics.realtime_p95_ms = NaN;
    metrics.realtime_p99_ms = NaN;
    metrics.timeout_rate = NaN;
end
end

function [t, x] = local_get_signal(logs, alias)
t = [];
x = [];
names = local_logs_element_names(logs);
for i = 1:numel(alias)
    if ~isempty(names) && ~any(strcmpi(alias{i}, names))
        continue;
    end
    try
        sig = logs.get(alias{i});
    catch
        sig = [];
    end
    if ~isempty(sig)
        try
            t = sig.Values.Time(:);
            x = squeeze(sig.Values.Data);
            x = x(:);
            return;
        catch
            t = [];
            x = [];
        end
    end
end
end

function names = local_logs_element_names(logs)
% 先取日志元素名，避免 logs.get(不存在名) 触发 warning 干扰批跑日志。
try
    names = getElementNames(logs);
    if isstring(names)
        names = cellstr(names);
    elseif ischar(names)
        names = {names};
    end
    return;
catch
end

try
    n = logs.numElements;
    names = cell(1, n);
    for ii = 1:n
        names{ii} = logs{ii}.Name; %#ok<AGROW>
    end
    return;
catch
end

names = {};
end

function files = local_default_path_files(root, path_mode)
paths_dir = fullfile(root, 'data', 'paths');
mode = lower(strtrim(string(path_mode)));

switch mode
    case "full150"
        files = {
            fullfile(paths_dir, 'path_industrial.mat')
            };
    case "hybrid"
        files = {
            fullfile(paths_dir, 'path_industrial.mat')
            fullfile(paths_dir, 'path_s_curve.mat')
            fullfile(paths_dir, 'path_slope.mat')
            };
    otherwise
        files = {
            fullfile(paths_dir, 'path_straight.mat')
            fullfile(paths_dir, 'path_s_curve.mat')
            fullfile(paths_dir, 'path_multi_turn_left.mat')
            fullfile(paths_dir, 'path_multi_turn_right.mat')
            fullfile(paths_dir, 'path_slope.mat')
            fullfile(paths_dir, 'path_industrial_lite.mat')
            };
end

% 若用户选择 full150/hybrid 但工业全程路径缺失，自动回退到 industrial_lite。
for ii = 1:numel(files)
    if strcmpi(files{ii}, fullfile(paths_dir, 'path_industrial.mat')) && ~exist(files{ii}, 'file')
        files{ii} = fullfile(paths_dir, 'path_industrial_lite.mat');
    end
end
end

function model_name = local_pick_existing_model_name(model_dir, candidates)
% 在候选名中优先选择当前工程真实存在的 .slx 文件。
model_name = candidates{1};
for jj = 1:numel(candidates)
    one = candidates{jj};
    if exist(fullfile(model_dir, [one '.slx']), 'file')
        model_name = one;
        return;
    end
end
end

function y = local_align_to_time(x, tx, tref)
if isempty(x) || isempty(tx)
    y = [];
    return;
end
if numel(tx) ~= numel(x)
    n = min(numel(tx), numel(x));
    tx = tx(1:n);
    x = x(1:n);
end
if isempty(tref)
    y = x;
    return;
end

if numel(tx) == numel(tref) && all(abs(tx - tref) < 1e-12)
    y = x;
else
    y = interp1(tx, x, tref, 'linear', 'extrap');
end
end

function r = local_rms(x)
x = x(isfinite(x));
if isempty(x)
    r = NaN;
else
    r = sqrt(mean(x.^2));
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

function v = local_nanmax(x)
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = max(x);
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

function row = local_row_template()
row = struct();
row.case_index = NaN;
row.controller = '';
row.model_name = '';
row.path_name = '';
row.path_file = '';
row.ref_file = '';
row.disturbance_level = NaN;
row.disturbance_scale = NaN;
row.disturbance_noise_scale = NaN;
row.disturbance_process_scale = NaN;
row.noise_enabled = false;
row.noise_signature = NaN;
row.process_signature = NaN;
row.seed = NaN;
row.status = '';
row.message = '';
row.elapsed_sec = NaN;
row.n_samples = NaN;

row.ey_rmse = NaN;
row.ey_peak = NaN;
row.epsi_rmse = NaN;
row.epsi_peak = NaN;
row.ev_rmse = NaN;
row.eomega_rmse = NaN;
row.j_du = NaN;
row.viol_rate = NaN;
row.F_sat_pct = NaN;
row.omega_sat_pct = NaN;
row.realtime_p50_ms = NaN;
row.realtime_p95_ms = NaN;
row.realtime_p99_ms = NaN;
row.timeout_rate = NaN;
row.timeseries_file = '';
end

function summary_tbl = local_summary_table(T, metric_fields)
if isempty(T)
    summary_tbl = table();
    return;
end

ok = strcmp(T.status, 'ok');
T = T(ok, :);
if isempty(T)
    summary_tbl = table();
    return;
end

controllers = unique(T.controller, 'stable');
rows = repmat(struct(), numel(controllers), 1);

for i = 1:numel(controllers)
    c = controllers{i};
    m = strcmp(T.controller, c);
    rows(i).controller = c;
    rows(i).n_cases = sum(m);
    for k = 1:numel(metric_fields)
        f = metric_fields{k};
        v = T.(f)(m);
        rows(i).([f '_mean']) = local_nanmean(v);
        rows(i).([f '_std']) = local_nanstd(v);
        rows(i).([f '_median']) = local_percentile(v, 50);
    end
end

summary_tbl = struct2table(rows);
end

function s = local_nanstd(x)
x = x(isfinite(x));
if numel(x) < 2
    s = NaN;
else
    s = std(x);
end
end
