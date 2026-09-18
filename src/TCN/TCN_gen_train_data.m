function data = TCN_gen_train_data(cfg)
% =============================
% 文件名：TCN_gen_train_data.m
% 版本号：V1.1
% 最后修改时间：2026-04-25
% 作者：LPV-MPC Project
%
% 功能描述：
%   基于 TCN/ModernTCN 路径集合和 GRU_DataGen.slx 生成 TCN/GRU 共享训练母集。
%   本脚本落实 Physics_Guided_Multi_task_TCN_Implementation_Guide.md
%   第 3.1/3.2 节要求：增加动态过渡样本，避免只用 150 s 长路径训练。
%
% 输入 cfg（可选）：
%   cfg.path_pattern       : 训练路径匹配模式，默认 data/paths/path_train_tcn_*.mat
%   cfg.num_runs_per_path  : 每条路径重复仿真次数，默认 4
%   cfg.num_runs_by_path   : 可选 [num_paths x 1]，逐路径覆盖重复次数
%   cfg.output_file        : 输出 mat 文件，默认 data/tcn/TCN_train_data_full.mat
%   cfg.model_name         : 仿真模型名，默认 GRU_DataGen
%   cfg.seed               : 随机种子，默认 20260424
%   cfg.noise_on           : 是否启用混合噪声，默认 true
%   cfg.verbose            : 是否打印详细日志，默认 true
%
% 输出 data：
%   data.runs(k).scene       : 路径/场景名称
%   data.runs(k).path_file   : 当前 run 使用的路径文件
%   data.runs(k).t           : 时间向量 [N x 1]
%   data.runs(k).u           : 控制输入 [N x 2] = [F_cmd, omega_cmd]
%   data.runs(k).y_raw       : 原始输出 [N x 34]
%   data.runs(k).label_main  : 主工况标签 [N x 1], 1=flat, 2=stall, 3=slope
%   data.runs(k).label_turn  : 转弯标签 [N x 1], -1=right, 0=straight, 1=left
%   data.runs(k).theta       : 坡度角真值 [N x 1] [rad]
%   data.runs(k).y_theta_ground : 坡度角真值，兼容 Mamba/GRU 派生流程
%   data.runs(k).label_slip / label_load_change / label_stall : 辅助动态扰动标签
%
% 与后续流程的关系：
%   - 本脚本输出的是未窗口化的连续 run 母集。
%   - TCN_prepare_dataset.m 负责滑窗、归一化和 run-level split。
%   - GRU 对照组应复用同一母集或同一 split，避免数据差异影响结论。
%
% 自检机制：
%   1. 仿真前检查路径文件、ref 字段、采样周期和短路径时长。
%   2. 仿真后检查 y_raw/u/theta 维度、NaN/Inf、输出长度。
%   3. 全量保存前检查标签分布、事件覆盖、过渡窗口覆盖、每类样本占比。
%   4. 生成 data/tcn/TCN_train_data_report.md，便于快速定位问题。
%
% 使用方法：
%   init_project;
%   data = TCN_gen_train_data();
%
% 冒烟测试：
%   cfg = struct('num_runs_per_path', 1, 'max_paths', 2);
%   data = TCN_gen_train_data(cfg);
% =============================

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

%% 0. 初始化与默认配置
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_apply_defaults(cfg, root);
rng(cfg.seed, 'twister');

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

params = parameters();
if abs(params.Ts - cfg.Ts) > 1e-12
    warning('TCN_gen_train_data:TsMismatch', ...
        'cfg.Ts=%.4f, parameters().Ts=%.4f. 使用 parameters().Ts。', cfg.Ts, params.Ts);
    cfg.Ts = params.Ts;
end

path_files = local_discover_path_files(cfg);
if isempty(path_files)
    error('未找到 TCN 训练路径。请先运行 src/paths/gen_tcn_training_paths.m');
end
num_runs_by_path = local_resolve_runs_by_path(cfg, path_files);

if cfg.verbose
    fprintf('\n========== TCN 训练母集生成 ==========\n');
    fprintf('模型: %s\n', cfg.model_name);
    fprintf('路径数: %d\n', numel(path_files));
    if all(num_runs_by_path == num_runs_by_path(1))
        fprintf('每路径 runs: %d\n', num_runs_by_path(1));
    else
        fprintf('每路径 runs: mixed [%d, %d], total=%d\n', ...
            min(num_runs_by_path), max(num_runs_by_path), sum(num_runs_by_path));
    end
    fprintf('输出: %s\n', cfg.output_file);
    fprintf('=====================================\n\n');
end

%% 1. 加载并准备 Simulink 模型
skip_gru_preload_cleanup = [];
if cfg.skip_gru_model_preload
    [had_skip_gru_preload, old_skip_gru_preload] = local_set_base_var('preload_skip_gru_model', true);
    skip_gru_preload_cleanup = onCleanup(@() local_restore_base_var( ...
        'preload_skip_gru_model', had_skip_gru_preload, old_skip_gru_preload)); %#ok<NASGU>
end
if ~bdIsLoaded(cfg.model_name)
    load_system(cfg.model_name);
end
original_model_settings = local_capture_model_settings(cfg.model_name);
restore_model_settings = onCleanup(@() local_restore_model_settings(cfg.model_name, original_model_settings));
local_prepare_runtime_workspace(cfg.model_name, cfg.verbose);

%% 2. 批量仿真
N_total = sum(num_runs_by_path);
data = struct();
data.runs = struct('scene', {}, 'path_file', {}, 't', {}, 'u', {}, 'theta', {}, ...
                   'y_raw', {}, 'label_main', {}, 'label_turn', {}, ...
                   'label_slip', {}, 'label_stall', {}, 'label_load_change', {}, ...
                   'y_theta_ground', {}, 'meta', {});

stats = local_init_stats();
run_idx = 0;

for pidx = 1:numel(path_files)
    path_file = path_files{pidx};
    ref = local_load_and_check_ref(path_file, cfg);
    [~, scene_name] = fileparts(path_file);

    for rep = 1:num_runs_by_path(pidx)
        run_idx = run_idx + 1;
        if cfg.verbose
            fprintf('[%03d/%03d] %s | rep=%d ... ', run_idx, N_total, scene_name, rep);
        end

        try
            params_sim = local_configure_noise(params, cfg);
            [inj_signal, inject_info] = local_build_injection_signal(ref, cfg, run_idx, rep);

            set_param(cfg.model_name, 'StopTime', num2str(ref.t(end)));
            set_param(cfg.model_name, 'FixedStep', num2str(cfg.Ts));

            % GRU_DataGen.slx 现有 From Workspace / S-Function 链路读取这些变量。
            assignin('base', 'params', params_sim);
            assignin('base', 'ref_path', ref);
            assignin('base', 'inj_signal', inj_signal);

            warning('off', 'all');
            sim_out = sim(cfg.model_name, 'ReturnWorkspaceOutputs', 'on', ...
                'SimulationMode', 'normal', 'CaptureErrors', 'on');
            warning('on', 'all');

            [t, y_raw, u, theta] = local_extract_signals_from_sim(sim_out, cfg);
            local_check_run_arrays(t, y_raw, u, theta, cfg);

            labels = local_generate_labels(t, y_raw, theta, ref.omega_ref, inject_info, cfg, params_sim);

            data.runs(run_idx).scene = scene_name;
            data.runs(run_idx).path_file = path_file;
            data.runs(run_idx).t = t;
            data.runs(run_idx).u = u;
            data.runs(run_idx).theta = theta;
            data.runs(run_idx).y_raw = y_raw;
            data.runs(run_idx).label_main = labels.label_main;
            data.runs(run_idx).label_turn = labels.label_turn;
            data.runs(run_idx).label_slip = labels.label_slip;
            data.runs(run_idx).label_stall = labels.label_stall;
            data.runs(run_idx).label_load_change = labels.label_load_change;
            data.runs(run_idx).y_theta_ground = theta;
            data.runs(run_idx).meta = struct();
            data.runs(run_idx).meta.path_meta = ref.meta;
            data.runs(run_idx).meta.inject_info = inject_info;
            data.runs(run_idx).meta.noise = params_sim.noise_meta;
            data.runs(run_idx).meta.dynamic_windows = local_get_dynamic_windows(ref);

            stats = local_update_stats(stats, data.runs(run_idx), cfg);

            if cfg.verbose
                fprintf('ok N=%d | flat=%d stall=%d slope=%d turn=%d slip=%d load=%d\n', ...
                    numel(t), sum(labels.label_main==1), sum(labels.label_main==2), ...
                    sum(labels.label_main==3), sum(labels.label_turn~=0), ...
                    sum(labels.label_slip==1), sum(labels.label_load_change==1));
            end

        catch ME
            warning('on', 'all');
            stats.failed_runs = stats.failed_runs + 1;
            stats.failure_messages{end+1, 1} = sprintf('%s rep=%d: %s', scene_name, rep, ME.message);
            if cfg.verbose
                fprintf('failed: %s\n', ME.message);
            end
            if cfg.fail_fast
                rethrow(ME);
            end
        end
    end
end

% 删除空 run（失败情况下可能存在跳号）
valid_mask = arrayfun(@(r) isfield(r, 't') && ~isempty(r.t), data.runs);
data.runs = data.runs(valid_mask);

%% 3. 全局自检与保存
stats = local_finalize_stats(stats, data, cfg);
local_dataset_self_check(data, stats, cfg);

data.meta = struct();
data.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
data.meta.version = 'TCN_DATA_V1.0';
data.meta.author = 'LPV-MPC Project';
data.meta.model_name = cfg.model_name;
data.meta.Ts = cfg.Ts;
data.meta.path_pattern = cfg.path_pattern;
data.meta.num_paths = numel(path_files);
data.meta.num_runs_per_path = cfg.num_runs_per_path;
data.meta.num_runs_by_path = num_runs_by_path(:);
data.meta.num_runs_schedule = local_runs_schedule_name(cfg);
data.meta.total_runs_planned = sum(num_runs_by_path);
data.meta.seed = cfg.seed;
data.meta.expected_y_dim = cfg.expected_y_dim;
data.meta.label_map_main = struct('flat', 1, 'stall', 2, 'slope', 3);
data.meta.label_map_turn = struct('right', -1, 'straight', 0, 'left', 1);
data.meta.event_cfg = cfg.event_cfg;
data.meta.noise_profile = cfg.noise_profile;
if isfield(cfg, 'plant_revision') && ~isempty(cfg.plant_revision)
    data.meta.plant_revision = cfg.plant_revision;
elseif exist('agv_plant_revision', 'file') == 2
    data.meta.plant_revision = agv_plant_revision(params);
end
data.meta.self_check = stats;
data.meta.notes = ['TCN/GRU shared training mother dataset. ' ...
                   'Designed to increase transition-rich samples for TCN/GRU fair comparison.'];

if cfg.verbose
    fprintf('\n保存 TCN 训练母集: %s\n', cfg.output_file);
end
save(cfg.output_file, 'data', '-v7.3');

report_file = local_default_report_file(cfg);
local_write_report(report_file, data, stats, cfg);

if cfg.verbose
    fprintf('自检报告: %s\n', report_file);
    fprintf('有效 runs: %d, 失败 runs: %d\n', numel(data.runs), stats.failed_runs);
    fprintf('=====================================\n');
end

end

%% ==================== 本地函数 ====================

function cfg = local_apply_defaults(cfg, root)
if ~isfield(cfg, 'output_dir') || isempty(cfg.output_dir)
    cfg.output_dir = fullfile(root, 'data', 'tcn');
end
if ~isfield(cfg, 'output_file') || isempty(cfg.output_file)
    cfg.output_file = fullfile(cfg.output_dir, 'TCN_train_data_full.mat');
end
if ~isfield(cfg, 'path_pattern') || isempty(cfg.path_pattern)
    cfg.path_pattern = fullfile(root, 'data', 'paths', 'path_train_tcn_*.mat');
end
if ~isfield(cfg, 'num_runs_per_path'); cfg.num_runs_per_path = 4; end
if ~isfield(cfg, 'max_paths'); cfg.max_paths = inf; end
if ~isfield(cfg, 'model_name'); cfg.model_name = 'GRU_DataGen'; end
if ~isfield(cfg, 'expected_y_dim'); cfg.expected_y_dim = 34; end
if ~isfield(cfg, 'Ts'); cfg.Ts = 0.01; end
if ~isfield(cfg, 'seed'); cfg.seed = 20260424; end
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end
if ~isfield(cfg, 'fail_fast'); cfg.fail_fast = false; end
if ~isfield(cfg, 'skip_gru_model_preload'); cfg.skip_gru_model_preload = true; end
if ~isfield(cfg, 'path_duration_warn_range'); cfg.path_duration_warn_range = [10, 45]; end

if ~isfield(cfg, 'noise_on'); cfg.noise_on = true; end
if ~isfield(cfg, 'noise_profile') || ~isstruct(cfg.noise_profile)
    cfg.noise_profile = struct();
end
if ~isfield(cfg.noise_profile, 'clean_ratio'); cfg.noise_profile.clean_ratio = 0.30; end
if ~isfield(cfg.noise_profile, 'noisy_scales'); cfg.noise_profile.noisy_scales = [1.0, 1.5]; end
if ~isfield(cfg.noise_profile, 'noisy_probs'); cfg.noise_profile.noisy_probs = [0.7, 0.3]; end

if ~isfield(cfg, 'event_cfg') || ~isstruct(cfg.event_cfg)
    cfg.event_cfg = struct();
end
if ~isfield(cfg.event_cfg, 'enabled'); cfg.event_cfg.enabled = true; end
if ~isfield(cfg.event_cfg, 'primary_types'); cfg.event_cfg.primary_types = {'slip', 'load_change', 'stall'}; end
if ~isfield(cfg.event_cfg, 'primary_probs'); cfg.event_cfg.primary_probs = [0.30, 0.35, 0.35]; end
if ~isfield(cfg.event_cfg, 'extra_event_prob'); cfg.event_cfg.extra_event_prob = 0.35; end
if ~isfield(cfg.event_cfg, 'window_padding'); cfg.event_cfg.window_padding = 0.15; end
if ~isfield(cfg.event_cfg, 'slip')
    cfg.event_cfg.slip = struct('duration_range', [1.2, 2.4], 'gamma_range', [0.45, 0.78]);
end
if ~isfield(cfg.event_cfg, 'load_change')
    cfg.event_cfg.load_change = struct('duration_range', [1.5, 3.0], 'load_range', [70, 160]);
end
if ~isfield(cfg.event_cfg, 'stall')
    cfg.event_cfg.stall = struct('duration_range', [1.5, 2.8], 'load_range', [210, 310]);
end

if ~isfield(cfg, 'label_cfg') || ~isstruct(cfg.label_cfg)
    cfg.label_cfg = struct();
end
if ~isfield(cfg.label_cfg, 'theta_slope_thresh'); cfg.label_cfg.theta_slope_thresh = deg2rad(2.0); end
if ~isfield(cfg.label_cfg, 'omega_turn_thresh'); cfg.label_cfg.omega_turn_thresh = 0.05; end
if ~isfield(cfg.label_cfg, 'turn_dwell_sec'); cfg.label_cfg.turn_dwell_sec = 0.40; end
if ~isfield(cfg.label_cfg, 'stall_dwell_sec'); cfg.label_cfg.stall_dwell_sec = 0.60; end

if ~isfield(cfg, 'self_check') || ~isstruct(cfg.self_check)
    cfg.self_check = struct();
end
if ~isfield(cfg.self_check, 'min_stall_ratio'); cfg.self_check.min_stall_ratio = 0.005; end
if ~isfield(cfg.self_check, 'min_slope_ratio'); cfg.self_check.min_slope_ratio = 0.05; end
if ~isfield(cfg.self_check, 'min_turn_ratio'); cfg.self_check.min_turn_ratio = 0.05; end
if ~isfield(cfg.self_check, 'min_slip_aux_ratio'); cfg.self_check.min_slip_aux_ratio = 0.01; end
if ~isfield(cfg.self_check, 'min_load_change_aux_ratio'); cfg.self_check.min_load_change_aux_ratio = 0.01; end
if ~isfield(cfg.self_check, 'min_stall_aux_ratio'); cfg.self_check.min_stall_aux_ratio = 0.01; end
if ~isfield(cfg.self_check, 'min_transition_window_hits'); cfg.self_check.min_transition_window_hits = 1; end
end

function report_file = local_default_report_file(cfg)
[~, out_name] = fileparts(cfg.output_file);
if strcmp(out_name, 'TCN_train_data_full')
    report_name = 'TCN_train_data_report.md';
else
    report_name = sprintf('%s_report.md', out_name);
end
report_file = fullfile(cfg.output_dir, report_name);
end

function path_files = local_discover_path_files(cfg)
if isfield(cfg, 'path_files') && ~isempty(cfg.path_files)
    if ischar(cfg.path_files) || isstring(cfg.path_files)
        path_files = cellstr(cfg.path_files);
    else
        path_files = cfg.path_files;
    end
    path_files = path_files(:).';
    for i = 1:numel(path_files)
        if exist(path_files{i}, 'file') ~= 2
            error('Configured path file does not exist: %s', path_files{i});
        end
    end
    return;
end
D = dir(cfg.path_pattern);
names = {D.name};
mask = ~contains(names, 'manifest', 'IgnoreCase', true);
D = D(mask);
[~, order] = sort({D.name});
D = D(order);
if isfinite(cfg.max_paths)
    D = D(1:min(numel(D), cfg.max_paths));
end
path_files = arrayfun(@(d) fullfile(d.folder, d.name), D, 'UniformOutput', false);
end

function num_runs_by_path = local_resolve_runs_by_path(cfg, path_files)
n_path = numel(path_files);
if isfield(cfg, 'num_runs_by_path') && ~isempty(cfg.num_runs_by_path)
    num_runs_by_path = double(cfg.num_runs_by_path(:).');
    if numel(num_runs_by_path) ~= n_path
        error('TCN_gen_train_data:BadRunsByPath', ...
            'num_runs_by_path length (%d) must match number of path files (%d).', ...
            numel(num_runs_by_path), n_path);
    end
else
    num_runs_by_path = repmat(double(cfg.num_runs_per_path), 1, n_path);
end
if any(~isfinite(num_runs_by_path)) || any(num_runs_by_path < 0)
    error('TCN_gen_train_data:BadRunsByPath', ...
        'num_runs_by_path must contain finite nonnegative values.');
end
num_runs_by_path = floor(num_runs_by_path);
if all(num_runs_by_path == 0)
    error('TCN_gen_train_data:BadRunsByPath', ...
        'At least one path must have a positive repeat count.');
end
end

function name = local_runs_schedule_name(cfg)
if isfield(cfg, 'num_runs_by_path') && ~isempty(cfg.num_runs_by_path)
    name = 'per_path';
else
    name = 'uniform';
end
end

function ref = local_load_and_check_ref(path_file, cfg)
S = load(path_file);
if ~isfield(S, 'ref')
    error('Path file has no ref variable: %s', path_file);
end
ref = S.ref;
req = {'t','X_ref','Y_ref','psi_ref','v_ref','omega_ref','theta_ref'};
for i = 1:numel(req)
    if ~isfield(ref, req{i})
        error('ref missing field %s in %s', req{i}, path_file);
    end
end
dt = diff(ref.t(:));
if any(dt <= 0)
    error('ref.t is not strictly increasing: %s', path_file);
end
if abs(median(dt) - cfg.Ts) > 1e-9
    error('Path Ts mismatch in %s: median dt=%.6f, cfg.Ts=%.6f', path_file, median(dt), cfg.Ts);
end
T_end = ref.t(end);
if ~isempty(cfg.path_duration_warn_range) && ...
        (T_end < cfg.path_duration_warn_range(1) || T_end > cfg.path_duration_warn_range(2))
    warning('TCN_gen_train_data:PathDuration', ...
        '路径 %s 时长 %.2fs 不在推荐范围 [%.1f, %.1f]s。', ...
        path_file, T_end, cfg.path_duration_warn_range(1), cfg.path_duration_warn_range(2));
end
end

function params_sim = local_configure_noise(params, cfg)
params_sim = params;
params_sim.enable_noise = false;
std_scale = 0;
variant = 'clean';
if cfg.noise_on
    if rand() >= cfg.noise_profile.clean_ratio
        params_sim.enable_noise = true;
        scales = cfg.noise_profile.noisy_scales(:)';
        probs = cfg.noise_profile.noisy_probs(:)';
        probs = probs / sum(probs);
        idx = find(rand() <= cumsum(probs), 1, 'first');
        if isempty(idx), idx = numel(scales); end
        std_scale = scales(idx);
        variant = sprintf('noisy_x%.2f', std_scale);
        params_sim.current_noise_std = params.current_noise_std * std_scale;
        params_sim.wheel_speed_noise_std = params.wheel_speed_noise_std * std_scale;
        params_sim.disturbance_noise_std = params.disturbance_noise_std * std_scale;
        params_sim.v_noise_std = params.v_noise_std * std_scale;
        params_sim.psi_noise_std = params.psi_noise_std * std_scale;
        params_sim.omega_noise_std = params.omega_noise_std * std_scale;
    end
end
params_sim.random_seed = randi(2^31 - 1);
params_sim.noise_meta = struct('enable_noise', params_sim.enable_noise, ...
    'std_scale', std_scale, 'variant', variant, 'random_seed', params_sim.random_seed);
end

function [inj_signal, inject_info] = local_build_injection_signal(ref, cfg, run_idx, rep)
t = ref.t(:);
N = numel(t);
slip_gamma_vec = ones(N, 1);
stall_load_vec = zeros(N, 1);
inject_info = local_empty_inject_info();

if isfield(cfg.event_cfg, 'enabled') && ~cfg.event_cfg.enabled
    inject_info.primary_event = struct('type', 'none', 'window', [NaN, NaN]);
    inject_info.extra_event_added = false;
    inj_signal = struct();
    inj_signal.time = t;
    inj_signal.signals = struct();
    inj_signal.signals.values = [slip_gamma_vec, stall_load_vec];
    inj_signal.signals.dimensions = 2;
    return;
end

windows = local_get_candidate_windows(ref);
if isempty(windows)
    windows = {[max(1, 0.25*t(end)), max(2, 0.45*t(end))]};
end

primary_type = local_sample_type(cfg.event_cfg.primary_types, cfg.event_cfg.primary_probs);
primary_win = windows{mod(run_idx + rep - 2, numel(windows)) + 1};
primary_win = local_sample_subwindow(primary_win, cfg.event_cfg.(primary_type).duration_range, ref.t(end));

inject_info.primary_event = struct('type', primary_type, 'window', primary_win);
inject_info = local_apply_event(inject_info, primary_type, primary_win, cfg.event_cfg);

% 额外事件优先放到不同候选窗口，增加动态过渡样本覆盖。
inject_info.extra_event_added = false;
if rand() < cfg.event_cfg.extra_event_prob && numel(windows) >= 2
    extra_type = local_sample_type(cfg.event_cfg.primary_types, cfg.event_cfg.primary_probs);
    extra_idx = mod(run_idx + rep, numel(windows)) + 1;
    extra_win = local_sample_subwindow(windows{extra_idx}, cfg.event_cfg.(extra_type).duration_range, ref.t(end));
    inject_info = local_apply_event(inject_info, extra_type, extra_win, cfg.event_cfg);
    inject_info.extra_event_added = true;
    inject_info.extra_event = struct('type', extra_type, 'window', extra_win);
end

for i = 1:size(inject_info.slip_windows, 1)
    m = t >= inject_info.slip_windows(i,1) & t <= inject_info.slip_windows(i,2);
    slip_gamma_vec(m) = inject_info.slip_gammas(i);
end
for i = 1:size(inject_info.stall_windows, 1)
    m = t >= inject_info.stall_windows(i,1) & t <= inject_info.stall_windows(i,2);
    stall_load_vec(m) = stall_load_vec(m) + inject_info.stall_loads(i);
end
for i = 1:size(inject_info.load_change_windows, 1)
    m = t >= inject_info.load_change_windows(i,1) & t <= inject_info.load_change_windows(i,2);
    stall_load_vec(m) = stall_load_vec(m) + inject_info.load_changes(i);
end

% 兼容旧脚本字段。
if inject_info.slip_injected
    inject_info.slip_window = inject_info.slip_windows(1, :);
    inject_info.slip_gamma = inject_info.slip_gammas(1);
end
if inject_info.stall_injected
    inject_info.stall_window = inject_info.stall_windows(1, :);
    inject_info.stall_load = inject_info.stall_loads(1);
end
if inject_info.load_change_injected
    inject_info.load_change_window = inject_info.load_change_windows(1, :);
    inject_info.load_change = inject_info.load_changes(1);
end

inj_signal = struct();
inj_signal.time = t;
inj_signal.signals = struct();
inj_signal.signals.values = [slip_gamma_vec, stall_load_vec];
inj_signal.signals.dimensions = 2;
end

function wins = local_get_candidate_windows(ref)
wins = {};
if isfield(ref, 'meta') && isfield(ref.meta, 'recommended_injection_windows')
    rw = ref.meta.recommended_injection_windows;
    if iscell(rw)
        wins = rw;
    elseif isnumeric(rw) && size(rw, 2) == 2
        for i = 1:size(rw, 1)
            wins{end+1} = rw(i, :); %#ok<AGROW>
        end
    end
end
if isempty(wins)
    wins = local_detect_transition_windows(ref);
end
end

function wins = local_detect_transition_windows(ref)
t = ref.t(:);
sig = [ref.v_ref(:), ref.omega_ref(:), ref.theta_ref(:)];
ds = [zeros(1,3); abs(diff(sig))];
score = ds(:,1)/0.05 + ds(:,2)/0.02 + ds(:,3)/deg2rad(0.5);
idx = find(score > 0.1);
wins = {};
if isempty(idx), return; end
segments = local_bool_segments(score > 0.1);
for i = 1:size(segments, 1)
    t0 = max(0, t(segments(i,1)) - 0.8);
    t1 = min(t(end), t(segments(i,2)) + 1.5);
    if t1 - t0 >= 1.0
        wins{end+1} = [t0, t1]; %#ok<AGROW>
    end
end
end

function w = local_sample_subwindow(zone, dur_range, T_end)
z0 = max(0, zone(1));
z1 = min(T_end, zone(2));
dur = dur_range(1) + diff(dur_range) * rand();
dur = min(dur, max(0.2, z1 - z0));
if z1 - z0 <= dur
    w = [z0, z1];
else
    s = z0 + (z1 - z0 - dur) * rand();
    w = [s, s + dur];
end
end

function info = local_empty_inject_info()
info = struct();
info.slip_injected = false;
info.stall_injected = false;
info.load_change_injected = false;
info.slip_windows = zeros(0, 2);
info.slip_gammas = zeros(0, 1);
info.stall_windows = zeros(0, 2);
info.stall_loads = zeros(0, 1);
info.load_change_windows = zeros(0, 2);
info.load_changes = zeros(0, 1);
end

function typ = local_sample_type(types, probs)
probs = probs(:)' / sum(probs);
idx = find(rand() <= cumsum(probs), 1, 'first');
if isempty(idx), idx = numel(types); end
typ = types{idx};
end

function info = local_apply_event(info, typ, win, event_cfg)
switch lower(typ)
    case 'slip'
        info.slip_injected = true;
        gamma = event_cfg.slip.gamma_range(1) + diff(event_cfg.slip.gamma_range) * rand();
        info.slip_windows = [info.slip_windows; win];
        info.slip_gammas = [info.slip_gammas; gamma];
    case 'stall'
        info.stall_injected = true;
        load_val = event_cfg.stall.load_range(1) + diff(event_cfg.stall.load_range) * rand();
        info.stall_windows = [info.stall_windows; win];
        info.stall_loads = [info.stall_loads; load_val];
    case 'load_change'
        info.load_change_injected = true;
        load_val = event_cfg.load_change.load_range(1) + diff(event_cfg.load_change.load_range) * rand();
        info.load_change_windows = [info.load_change_windows; win];
        info.load_changes = [info.load_changes; load_val];
    otherwise
        error('Unknown event type: %s', typ);
end
end

function [t, y_raw, u, theta] = local_extract_signals_from_sim(sim_out, cfg)
if ~isa(sim_out, 'Simulink.SimulationOutput')
    error('sim output is not Simulink.SimulationOutput');
end
try
    sim_err = sim_out.ErrorMessage;
catch
    sim_err = '';
end
if ~isempty(sim_err)
    error('Simulink simulation failed: %s', sim_err);
end
if ~isprop(sim_out, 'tout') || isempty(sim_out.tout)
    error('sim output has no tout');
end
t = sim_out.tout;
y_raw = local_get_timeseries_struct(sim_out, 'y_raw1', cfg.expected_y_dim);
u = local_get_timeseries_struct(sim_out, 'u1', 2);
theta = local_get_timeseries_struct(sim_out, 'theta1', 1);
theta = theta(:);
end

function x = local_get_timeseries_struct(sim_out, name, expected_dim)
if ~isprop(sim_out, name)
    error('sim output missing %s', name);
end
S = sim_out.(name);
if ~isstruct(S) || ~isfield(S, 'signals') || ~isfield(S.signals, 'values')
    error('%s format invalid', name);
end
x = S.signals.values;
if expected_dim == 1
    x = x(:);
elseif size(x, 2) ~= expected_dim
    error('%s dimension mismatch: expected second dim %d, got %d', name, expected_dim, size(x, 2));
end
end

function local_check_run_arrays(t, y_raw, u, theta, cfg)
N = numel(t);
if size(y_raw, 1) ~= N || size(y_raw, 2) ~= cfg.expected_y_dim
    error('y_raw size mismatch: expected [%d x %d], got [%d x %d]', N, cfg.expected_y_dim, size(y_raw,1), size(y_raw,2));
end
if size(u, 1) ~= N || size(u, 2) ~= 2
    error('u size mismatch: expected [%d x 2], got [%d x %d]', N, size(u,1), size(u,2));
end
if numel(theta) ~= N
    error('theta length mismatch: expected %d, got %d', N, numel(theta));
end
if any(~isfinite(y_raw(:))) || any(~isfinite(u(:))) || any(~isfinite(theta(:)))
    error('NaN/Inf detected in simulation outputs');
end
end

function labels = local_generate_labels(t, y_raw, theta, omega_ref, inject_info, cfg, ~)
N = numel(t);
label_main = ones(N, 1);
label_slip = zeros(N, 1);
label_stall = zeros(N, 1);
label_load_change = zeros(N, 1);

% 堵转优先级最高，使用注入窗口真值。
if inject_info.stall_injected
    for i = 1:size(inject_info.stall_windows, 1)
        m = t >= inject_info.stall_windows(i,1) & t <= inject_info.stall_windows(i,2);
        label_main(m) = 2;
        label_stall(m) = 1;
    end
end

% 坡度次优先级，不覆盖堵转。
m_slope = abs(theta(:)) >= cfg.label_cfg.theta_slope_thresh & label_main == 1;
label_main(m_slope) = 3;

% 滑移/负载变化作为辅助标签，不改变主工况层级。
if inject_info.slip_injected
    for i = 1:size(inject_info.slip_windows, 1)
        m = t >= inject_info.slip_windows(i,1) & t <= inject_info.slip_windows(i,2);
        label_slip(m) = 1;
    end
end
if inject_info.load_change_injected
    for i = 1:size(inject_info.load_change_windows, 1)
        m = t >= inject_info.load_change_windows(i,1) & t <= inject_info.load_change_windows(i,2);
        label_load_change(m) = 1;
    end
end

% 启发式 stall 补充，仅补 flat，不覆盖 slope/stall ground truth。
I_sum = abs(y_raw(:, 12)) + abs(y_raw(:, 13));
omega_l = abs(y_raw(:, 17));
omega_r = abs(y_raw(:, 18));
v_meas = y_raw(:, 4);
heur_stall = (I_sum > 12) & (omega_l < 0.1) & (omega_r < 0.1) & (v_meas < 0.20);
heur_stall = local_apply_dwell(heur_stall, max(1, round(cfg.label_cfg.stall_dwell_sec / cfg.Ts)));
label_stall(heur_stall) = 1;
label_main(heur_stall & label_main == 1) = 2;

% 转弯标签基于参考角速度，和 GRU/Mamba 旧流程保持一致。
raw_turn = zeros(N, 1);
raw_turn(omega_ref(:) > cfg.label_cfg.omega_turn_thresh) = 1;
raw_turn(omega_ref(:) < -cfg.label_cfg.omega_turn_thresh) = -1;
label_turn = zeros(N, 1);
for sgn = [-1, 1]
    mask = local_apply_dwell(raw_turn == sgn, max(1, round(cfg.label_cfg.turn_dwell_sec / cfg.Ts)));
    label_turn(mask) = sgn;
end

labels = struct('label_main', label_main, 'label_turn', label_turn, ...
    'label_slip', label_slip, 'label_stall', label_stall, ...
    'label_load_change', label_load_change);
end

function m2 = local_apply_dwell(m, dwell_steps)
N = numel(m);
m2 = false(N, 1);
i = 1;
while i <= N
    if m(i)
        j = i;
        while j <= N && m(j)
            j = j + 1;
        end
        if (j - i) >= dwell_steps
            m2(i:j-1) = true;
        end
        i = j;
    else
        i = i + 1;
    end
end
end

function stats = local_init_stats()
stats = struct();
stats.failed_runs = 0;
stats.failure_messages = {};
stats.total_samples = 0;
stats.main_counts = zeros(1, 3);
stats.turn_counts = zeros(1, 3); % 右转、直行、左转
stats.slip_count = 0;
stats.stall_count = 0;
stats.load_change_count = 0;
stats.slip_run_count = 0;
stats.stall_run_count = 0;
stats.load_change_run_count = 0;
stats.dynamic_window_hits = 0;
stats.runs_with_transition_windows = 0;
stats.path_names = {};
end

function stats = local_update_stats(stats, run, cfg)
N = numel(run.t);
stats.total_samples = stats.total_samples + N;
for lbl = 1:3
    stats.main_counts(lbl) = stats.main_counts(lbl) + sum(run.label_main == lbl);
end
stats.turn_counts(1) = stats.turn_counts(1) + sum(run.label_turn == -1);
stats.turn_counts(2) = stats.turn_counts(2) + sum(run.label_turn == 0);
stats.turn_counts(3) = stats.turn_counts(3) + sum(run.label_turn == 1);
stats.slip_count = stats.slip_count + sum(run.label_slip == 1);
stats.stall_count = stats.stall_count + sum(run.label_stall == 1);
stats.load_change_count = stats.load_change_count + sum(run.label_load_change == 1);
stats.slip_run_count = stats.slip_run_count + double(any(run.label_slip == 1));
stats.stall_run_count = stats.stall_run_count + double(any(run.label_stall == 1));
stats.load_change_run_count = stats.load_change_run_count + double(any(run.label_load_change == 1));
stats.path_names{end+1, 1} = run.scene;

dw = local_get_dynamic_windows_from_meta(run.meta);
if ~isempty(dw)
    stats.runs_with_transition_windows = stats.runs_with_transition_windows + 1;
    hit = 0;
    for i = 1:size(dw, 1)
        m = run.t >= dw(i,1) & run.t <= dw(i,2);
        if nnz(m) >= max(1, round(0.5 / cfg.Ts))
            hit = hit + 1;
        end
    end
    stats.dynamic_window_hits = stats.dynamic_window_hits + hit;
end
end

function stats = local_finalize_stats(stats, data, ~)
stats.valid_runs = numel(data.runs);
if stats.total_samples > 0
    stats.main_ratio = stats.main_counts / stats.total_samples;
    stats.turn_ratio = stats.turn_counts / stats.total_samples;
    stats.slip_ratio = stats.slip_count / stats.total_samples;
    stats.stall_ratio = stats.stall_count / stats.total_samples;
    stats.load_change_ratio = stats.load_change_count / stats.total_samples;
else
    stats.main_ratio = [NaN NaN NaN];
    stats.turn_ratio = [NaN NaN NaN];
    stats.slip_ratio = NaN;
    stats.stall_ratio = NaN;
    stats.load_change_ratio = NaN;
end
stats.unique_paths = unique(stats.path_names);
end

function local_dataset_self_check(data, stats, cfg)
if isempty(data.runs)
    error('No valid runs generated.');
end
if stats.failed_runs > 0
    warning('TCN_gen_train_data:FailedRuns', '%d runs failed. See report for details.', stats.failed_runs);
end
if stats.main_ratio(2) < cfg.self_check.min_stall_ratio
    warning('TCN_gen_train_data:LowStallRatio', 'stall ratio %.4f is below threshold %.4f.', stats.main_ratio(2), cfg.self_check.min_stall_ratio);
end
if stats.main_ratio(3) < cfg.self_check.min_slope_ratio
    warning('TCN_gen_train_data:LowSlopeRatio', 'slope ratio %.4f is below threshold %.4f.', stats.main_ratio(3), cfg.self_check.min_slope_ratio);
end
turn_nonzero_ratio = (stats.turn_counts(1) + stats.turn_counts(3)) / max(stats.total_samples, 1);
if turn_nonzero_ratio < cfg.self_check.min_turn_ratio
    warning('TCN_gen_train_data:LowTurnRatio', 'turn ratio %.4f is below threshold %.4f.', turn_nonzero_ratio, cfg.self_check.min_turn_ratio);
end
if stats.slip_ratio < cfg.self_check.min_slip_aux_ratio
    warning('TCN_gen_train_data:LowSlipAuxRatio', 'slip aux ratio %.4f is below threshold %.4f.', stats.slip_ratio, cfg.self_check.min_slip_aux_ratio);
end
if stats.load_change_ratio < cfg.self_check.min_load_change_aux_ratio
    warning('TCN_gen_train_data:LowLoadChangeAuxRatio', 'load-change aux ratio %.4f is below threshold %.4f.', stats.load_change_ratio, cfg.self_check.min_load_change_aux_ratio);
end
if stats.stall_ratio < cfg.self_check.min_stall_aux_ratio
    warning('TCN_gen_train_data:LowStallAuxRatio', 'stall aux ratio %.4f is below threshold %.4f.', stats.stall_ratio, cfg.self_check.min_stall_aux_ratio);
end
if stats.dynamic_window_hits < cfg.self_check.min_transition_window_hits
    warning('TCN_gen_train_data:LowTransitionCoverage', 'dynamic transition window hits are low: %d.', stats.dynamic_window_hits);
end
end

function local_write_report(report_file, data, stats, cfg)
fid = fopen(report_file, 'w');
if fid < 0
    warning('Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# TCN Training Data Generation Report\n\n');
fprintf(fid, '- Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- Output: `%s`\n', cfg.output_file);
fprintf(fid, '- Model: `%s`\n', cfg.model_name);
if isfield(data, 'meta') && isfield(data.meta, 'plant_revision') && ...
        isfield(data.meta.plant_revision, 'id')
    fprintf(fid, '- Plant revision: `%s`\n', data.meta.plant_revision.id);
end
fprintf(fid, '- Valid runs: %d\n', numel(data.runs));
fprintf(fid, '- Failed runs: %d\n', stats.failed_runs);
fprintf(fid, '- Total samples: %d\n\n', stats.total_samples);

fprintf(fid, '## Label Distribution\n\n');
fprintf(fid, '| label | count | ratio |\n|---|---:|---:|\n');
fprintf(fid, '| flat | %d | %.4f |\n', stats.main_counts(1), stats.main_ratio(1));
fprintf(fid, '| stall | %d | %.4f |\n', stats.main_counts(2), stats.main_ratio(2));
fprintf(fid, '| slope | %d | %.4f |\n', stats.main_counts(3), stats.main_ratio(3));
fprintf(fid, '| turn right | %d | %.4f |\n', stats.turn_counts(1), stats.turn_ratio(1));
fprintf(fid, '| turn straight | %d | %.4f |\n', stats.turn_counts(2), stats.turn_ratio(2));
fprintf(fid, '| turn left | %d | %.4f |\n', stats.turn_counts(3), stats.turn_ratio(3));
fprintf(fid, '| slip aux | %d | %.4f |\n', stats.slip_count, stats.slip_ratio);
fprintf(fid, '| stall aux | %d | %.4f |\n', stats.stall_count, stats.stall_ratio);
fprintf(fid, '| load_change aux | %d | %.4f |\n\n', stats.load_change_count, stats.load_change_ratio);

fprintf(fid, '## Transition Coverage\n\n');
fprintf(fid, '- Runs with dynamic windows: %d\n', stats.runs_with_transition_windows);
fprintf(fid, '- Dynamic window hits: %d\n\n', stats.dynamic_window_hits);

fprintf(fid, '## Event Coverage\n\n');
fprintf(fid, '- Runs with slip labels: %d\n', stats.slip_run_count);
fprintf(fid, '- Runs with stall labels: %d\n', stats.stall_run_count);
fprintf(fid, '- Runs with load-change labels: %d\n\n', stats.load_change_run_count);

if stats.failed_runs > 0
    fprintf(fid, '## Failures\n\n');
    for i = 1:numel(stats.failure_messages)
        fprintf(fid, '- %s\n', stats.failure_messages{i});
    end
    fprintf(fid, '\n');
end

fprintf(fid, '## Paths\n\n');
for i = 1:numel(stats.unique_paths)
    fprintf(fid, '- `%s`\n', stats.unique_paths{i});
end
end

function local_prepare_runtime_workspace(model_name, verbose)
if nargin < 2
    verbose = false;
end
if verbose
    fprintf('[TCN] Preparing runtime workspace for %s\n', model_name);
end
if exist('init_project', 'file') == 2
    init_project();
end
assignin('base', 'preload_skip_gru_model', true);
if exist('preloadfcn_v2', 'file') == 2
    evalin('base', 'preloadfcn_v2');
elseif exist('preloadfcn_v1', 'file') == 2
    evalin('base', 'preloadfcn_v1');
end
if ~evalin('base', 'exist(''MPC_idx'',''var'')')
    assignin('base', 'MPC_idx', [6, 8, 11, 1]);
end
end

function [had_var, old_value] = local_set_base_var(name, value)
had_var = evalin('base', sprintf('exist(''%s'', ''var'')==1', name));
old_value = [];
if had_var
    old_value = evalin('base', name);
end
assignin('base', name, value);
end

function local_restore_base_var(name, had_var, old_value)
if had_var
    assignin('base', name, old_value);
else
    evalin('base', sprintf('clear %s', name));
end
end

function s = local_capture_model_settings(model_name)
s = struct('loaded', bdIsLoaded(model_name), 'stop_time', '', 'fixed_step', '', 'dirty', 'off');
if bdIsLoaded(model_name)
    s.stop_time = get_param(model_name, 'StopTime');
    s.fixed_step = get_param(model_name, 'FixedStep');
    s.dirty = get_param(model_name, 'Dirty');
end
end

function local_restore_model_settings(model_name, s)
try
    if bdIsLoaded(model_name)
        if ~isempty(s.stop_time)
            set_param(model_name, 'StopTime', s.stop_time);
        end
        if ~isempty(s.fixed_step)
            set_param(model_name, 'FixedStep', s.fixed_step);
        end
        set_param(model_name, 'Dirty', s.dirty);
    end
catch ME
    warning('TCN_gen_train_data:RestoreModelSettings', ...
        'Cannot restore model settings for %s: %s', model_name, ME.message);
end
end

function dw = local_get_dynamic_windows(ref)
dw = [];
if isfield(ref, 'meta') && isfield(ref.meta, 'recommended_injection_windows')
    rw = ref.meta.recommended_injection_windows;
    if iscell(rw)
        for i = 1:numel(rw)
            dw = [dw; rw{i}]; %#ok<AGROW>
        end
    elseif isnumeric(rw) && size(rw, 2) == 2
        dw = rw;
    end
end
if isempty(dw)
    wins = local_detect_transition_windows(ref);
    for i = 1:numel(wins)
        dw = [dw; wins{i}]; %#ok<AGROW>
    end
end
end

function dw = local_get_dynamic_windows_from_meta(meta)
dw = [];
if isfield(meta, 'dynamic_windows') && ~isempty(meta.dynamic_windows)
    dw = meta.dynamic_windows;
end
end

function segs = local_bool_segments(m)
N = numel(m);
segs = zeros(0, 2);
i = 1;
while i <= N
    if m(i)
        j = i;
        while j <= N && m(j)
            j = j + 1;
        end
        segs(end+1, :) = [i, j-1]; %#ok<AGROW>
        i = j;
    else
        i = i + 1;
    end
end
end
