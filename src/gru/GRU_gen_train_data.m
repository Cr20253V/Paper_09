% =============================
% 文件名：GRU_gen_train_data.m
% 版本号：V6.0（迁移至 industrial_lite 复合路径）
% 最后修改时间：2026-04-14
% 作者：LPV-MPC Project
% 功能描述：
%   基于 GRU_DataGen.slx 生成 GRU 训练数据集
%   V6.0：迁移至 150s industrial_lite 复合路径（与 Mamba 对齐）
%         采样周期改为 0.01s
%         事件注入采用黄金区单事件 + 额外区域事件
%         路径生成使用 gen_agv_ref_path_v1
%
% 输出：
%   - data: 结构体，保存至 cfg.output_file
%       .runs(k): 每回合数据（k=1..N_total）
%           .scene       : 场景名称（字符串）
%           .t           : 时间向量 [Nx1] [s]
%           .u           : 控制输入 [Nx2]=[F_cmd, omega_cmd]
%           .y_raw       : 原始输出 [Nx34]
%           .label_main  : 主分类标签 [Nx1]∈{1,2,3} (flat/stall/slope)
%           .label_turn  : 转弯状态标签 [Nx1]∈{-1,0,+1}
%           .theta       : 坡度角真值 [Nx1] [rad]
%
% 依赖：
%   - parameters.m
%   - gen_agv_ref_path_v1.m
%   - GRU_DataGen.slx (Simulink 模型)
%
% 备注：
%   - 标签优先级：stall→slope→flat
%   - 事件注入：黄金区(10-50s)单事件 + 额外区域事件(25%概率)
% =============================

%% ==================== 配置区域 ====================

root = project_root();
data_gru_dir = fullfile(root, 'data', 'gru');
if ~exist(data_gru_dir, 'dir')
    mkdir(data_gru_dir);
end

cfg = struct();
cfg.scenes = {'industrial_lite'};

cfg.num_runs = 240;
cfg.num_runs_per_scene = struct('industrial_lite', 240);

cfg.T_end = 150;
cfg.Ts = 0.01;                   % 采样周期 [s]（与 Mamba 对齐）
cfg.seed = 42;
cfg.model_name = 'GRU_DataGen';
cfg.expected_y_dim = 34;
cfg.verbose = true;

cfg.output_file = fullfile(data_gru_dir, 'GRU_train_data_full.mat');

% 噪声配置（与 Mamba 对齐）
cfg.noise_on = true;
cfg.noise_profile = struct();
cfg.noise_profile.mode = 'mixed';
cfg.noise_profile.clean_ratio = 0.30;
cfg.noise_profile.noisy_scales = [1.0, 1.5];
cfg.noise_profile.noisy_probs = [0.7, 0.3];

% 路径参数随机化（与 Mamba 对齐）
cfg.path_rand = struct();
cfg.path_rand.v_cruise_range = [0.9, 1.1];
cfg.path_rand.slope_angle_pure_grid_deg = 0.0:0.1:10.0;
cfg.path_rand.slope_angle_composite_ratio = [0.55, 0.85];
cfg.path_rand.turn_scale_pure_fixed = 1.0;
cfg.path_rand.turn_scale_composite_fixed = 1.9;
cfg.path_rand.transition_time_range = [1.2, 2.2];
cfg.path_rand.omega_limit_range = [0.14, 0.30];
cfg.path_rand.v_turn_ref_range = [0.08, 0.14];
cfg.path_rand.v_slope_ref_range_deg = [5, 9];

% 事件注入配置（与 Mamba 对齐）
cfg.event_cfg = struct();
cfg.event_cfg.golden_zone = [10, 50];
cfg.event_cfg.primary_types = {'slip', 'load_change', 'stall'};
cfg.event_cfg.primary_probs = [0.34, 0.33, 0.33];

cfg.event_cfg.slip = struct( ...
    'duration_range', [1.5, 3.0], ...
    'gamma_range', [0.35, 0.75] ...
);
cfg.event_cfg.load_change = struct( ...
    'duration_range', [2.0, 4.0], ...
    'load_range', [80, 170] ...
);
cfg.event_cfg.stall = struct( ...
    'duration_range', [2.0, 3.2], ...
    'load_range', [210, 320] ...
);

cfg.event_cfg.extra_zone = struct();
cfg.event_cfg.extra_zone.enable = true;
cfg.event_cfg.extra_zone.prob = 0.25;
cfg.event_cfg.extra_zone.targets = {'pure_turn', 'pure_slope', 'composite'};
cfg.event_cfg.extra_zone.type_probs = [0.45, 0.25, 0.30];

%% ==================== 初始化 ====================

rng(cfg.seed);
params = parameters();

scenes = cfg.scenes;
N_scenes = numel(scenes);
scene_runs = zeros(1, N_scenes);
for i = 1:N_scenes
    scene_runs(i) = get_scene_runs(scenes{i}, cfg.num_runs, cfg.num_runs_per_scene);
end
N_total = sum(scene_runs);

data = struct();
data.runs = struct('scene', {}, 't', {}, 'u', {}, 'y_raw', {}, ...
                   'label_main', {}, 'label_turn', {}, 'theta', {}, 'meta', {});

if ~bdIsLoaded(cfg.model_name)
    if cfg.verbose
        fprintf('正在加载 Simulink 模型: %s\n', cfg.model_name);
    end
    load_system(cfg.model_name);
end

% 刷新运行时工作区，避免遗留参数导致维度冲突
prepare_runtime_workspace_local(cfg.model_name, cfg.verbose);

%% ==================== 批量生成数据 ====================

run_idx = 0;
for s_idx = 1:N_scenes
    scene = scenes{s_idx};
    runs_this_scene = scene_runs(s_idx);

    if cfg.verbose
        fprintf('\n========================================\n');
        fprintf('场景 [%d/%d]: %s\n', s_idx, N_scenes, scene);
        fprintf('========================================\n');
    end

    for run = 1:runs_this_scene
        run_idx = run_idx + 1;

        if cfg.verbose
            fprintf('  回合 [%d/%d] (总进度: %d/%d)... ', run, runs_this_scene, run_idx, N_total);
        end

        try
            % 1. 生成参考路径和注入信号
            [ref_path, inj_signal, inject_info, T_end_run] = ...
                generate_reference_path_local(scene, params, cfg, run_idx);

            % 2. 解析噪声配置
            [enable_noise_run, noise_std_scale, noise_variant] = ...
                resolve_noise_profile_local(cfg.noise_profile, cfg.noise_on);

            params_sim = params;
            params_sim.enable_noise = enable_noise_run;
            if enable_noise_run
                noise_std_scale = max(noise_std_scale, 0);
                params_sim.current_noise_std = params.current_noise_std * noise_std_scale;
                params_sim.wheel_speed_noise_std = params.wheel_speed_noise_std * noise_std_scale;
                params_sim.disturbance_noise_std = params.disturbance_noise_std * noise_std_scale;
            else
                noise_std_scale = 0;
            end

            % 3. 配置 Simulink 模型
            set_param(cfg.model_name, 'StopTime', num2str(T_end_run));
            set_param(cfg.model_name, 'FixedStep', num2str(cfg.Ts));

            assignin('base', 'params', params_sim);
            assignin('base', 'ref_path', ref_path);
            assignin('base', 'inj_signal', inj_signal);

            % 4. 运行仿真（静默模式）
            warning('off', 'all');
            sim_out = sim(cfg.model_name, 'ReturnWorkspaceOutputs', 'on', ...
                         'SimulationMode', 'normal', 'CaptureErrors', 'on');
            warning('on', 'all');

            % 5. 提取信号
            [t, y_raw, u, theta] = extract_signals_from_sim(sim_out);
            N = length(t);

            % 6. 数据验证
            if size(y_raw, 1) ~= N || size(y_raw, 2) ~= cfg.expected_y_dim
                error('y_raw 维度错误: 期望 [%d×%d], 实际 [%d×%d]', ...
                    N, cfg.expected_y_dim, size(y_raw, 1), size(y_raw, 2));
            end
            if size(u, 1) ~= N || size(u, 2) ~= 2
                error('u 维度错误: 期望 [%d×2], 实际 [%d×%d]', N, size(u, 1), size(u, 2));
            end

            % 7. 生成标签
            [label_main, label_turn] = generate_labels( ...
                t, y_raw, theta, ref_path.omega_ref, inject_info, cfg.Ts);

            % 8. 保存当前回合数据
            data.runs(run_idx).scene = scene;
            data.runs(run_idx).t = t;
            data.runs(run_idx).u = u;
            data.runs(run_idx).y_raw = y_raw;
            data.runs(run_idx).label_main = label_main;
            data.runs(run_idx).label_turn = label_turn;
            data.runs(run_idx).theta = theta;
            data.runs(run_idx).meta.inject_info = inject_info;
            data.runs(run_idx).meta.path_params = ref_path.meta;
            data.runs(run_idx).meta.noise = struct( ...
                'enable_noise', enable_noise_run, ...
                'std_scale', noise_std_scale, ...
                'variant', noise_variant);

            if cfg.verbose
                fprintf('✓ (N=%d, flat=%d, stall=%d, slope=%d)\n', ...
                    N, sum(label_main==1), sum(label_main==2), sum(label_main==3));
            end

        catch ME
            if cfg.verbose
                fprintf('✗ 失败: %s\n', ME.message);
            end
            warning('GRU_gen_train_data:SimFailed', ...
                '场景 %s 回合 %d 仿真失败: %s', scene, run, ME.message);
            continue;
        end
    end
end

%% ==================== 保存全局元数据 ====================

data.meta = struct();
data.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
data.meta.version = 'V6.0';
data.meta.author = 'LPV-MPC Project';
data.meta.model_name = cfg.model_name;
data.meta.scenes = scenes;
data.meta.num_runs_per_scene = scene_runs;
data.meta.T_end = cfg.T_end;
data.meta.Ts = cfg.Ts;
data.meta.seed = cfg.seed;
data.meta.expected_y_dim = cfg.expected_y_dim;
data.meta.event_cfg = cfg.event_cfg;
data.meta.path_rand = cfg.path_rand;
data.meta.noise_profile = cfg.noise_profile;

if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('数据生成完成！总回合数: %d\n', run_idx);
    fprintf('正在保存到: %s\n', cfg.output_file);
end

save(cfg.output_file, 'data', '-v7.3');

if cfg.verbose
    fprintf('✓ 保存成功！\n');
    fprintf('========================================\n');
end

%% ==================== 子函数 ====================

function [t, y_raw, u, theta] = extract_signals_from_sim(sim_out)
% 从 Simulink.SimulationOutput 中提取 t/y_raw/u/theta
if ~isa(sim_out, 'Simulink.SimulationOutput')
    error('sim output is not Simulink.SimulationOutput');
end

% 检查仿真是否出错
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

if ~isstruct(sim_out.y_raw1) || ~isfield(sim_out.y_raw1, 'signals')
    error('y_raw1 format invalid');
end
y_raw = sim_out.y_raw1.signals.values;

if ~isstruct(sim_out.u1) || ~isfield(sim_out.u1, 'signals')
    error('u1 format invalid');
end
u = sim_out.u1.signals.values;

if ~isstruct(sim_out.theta1) || ~isfield(sim_out.theta1, 'signals')
    error('theta1 format invalid');
end
theta = sim_out.theta1.signals.values;
end


function [ref_path, inj_signal, inject_info, T_end_scene] = ...
    generate_reference_path_local(scene, params, cfg, run_idx)
% 生成 150s 工业分区路径 + 事件注入信号
%
% 与 Mamba_gen_train_data.m 中的同名函数逻辑一致：
%   1) 调用 gen_agv_ref_path_v1 生成路径
%   2) 黄金区(10-50s)每回合注入单事件（slip/load_change/stall）
%   3) 以 25% 概率在其他区域额外注入异常
%   4) 输出注入信号 inj_signal（两通道：slip_gamma/stall_load）

opts = struct();
T_end_scene = cfg.T_end;

opts.T_end = T_end_scene;
opts.path_type = scene;
opts.v_cruise = cfg.path_rand.v_cruise_range(1) + diff(cfg.path_rand.v_cruise_range) * rand();

% 坡度角：从网格中轮转选择（保证覆盖均匀）
theta_grid = cfg.path_rand.slope_angle_pure_grid_deg(:)';
if isempty(theta_grid)
    theta_grid = 8.0;
end
theta_idx = mod(max(1, round(run_idx)) - 1, numel(theta_grid)) + 1;
theta_pure_deg = theta_grid(theta_idx);
ratio = cfg.path_rand.slope_angle_composite_ratio(1) + ...
    diff(cfg.path_rand.slope_angle_composite_ratio) * rand();

opts.slope_angle_pure = deg2rad(theta_pure_deg);
opts.slope_angle_composite = deg2rad(theta_pure_deg * ratio);
opts.turn_scale_pure = cfg.path_rand.turn_scale_pure_fixed;
opts.turn_scale_composite = cfg.path_rand.turn_scale_composite_fixed;
opts.transition_time = cfg.path_rand.transition_time_range(1) + ...
    diff(cfg.path_rand.transition_time_range) * rand();
opts.omega_limit = cfg.path_rand.omega_limit_range(1) + ...
    diff(cfg.path_rand.omega_limit_range) * rand();
opts.v_turn_ref = cfg.path_rand.v_turn_ref_range(1) + ...
    diff(cfg.path_rand.v_turn_ref_range) * rand();
opts.v_slope_ref = deg2rad(cfg.path_rand.v_slope_ref_range_deg(1) + ...
    diff(cfg.path_rand.v_slope_ref_range_deg) * rand());

ref_path = gen_agv_ref_path_v1(params, opts);

%% 事件注入
inject_info = struct();
inject_info.slip_injected = false;
inject_info.stall_injected = false;
inject_info.load_change_injected = false;
inject_info.slip_windows = [];
inject_info.slip_gammas = [];
inject_info.stall_windows = [];
inject_info.stall_loads = [];
inject_info.load_change_windows = [];
inject_info.load_changes = [];

zones = ref_path.meta.zones;
golden = cfg.event_cfg.golden_zone;
Ts_ref = params.Ts;

% 每回合黄金区单事件
primary_type = sample_event_type_local(cfg.event_cfg.primary_types, cfg.event_cfg.primary_probs);
[p_start, p_end] = sample_window_in_zone_local(golden, cfg.event_cfg.(primary_type).duration_range, Ts_ref);

inject_info.primary_event = struct('type', primary_type, 'window', [p_start, p_end]);
inject_info = apply_event_to_inject_info_local(inject_info, primary_type, [p_start, p_end], cfg.event_cfg);

% 额外区域事件（25% 概率）
inject_info.extra_zone_event_added = false;
if cfg.event_cfg.extra_zone.enable && rand() < cfg.event_cfg.extra_zone.prob
    zname = cfg.event_cfg.extra_zone.targets{randi(numel(cfg.event_cfg.extra_zone.targets))};
    zwin = zones.(zname);
    etype = sample_event_type_local(cfg.event_cfg.primary_types, cfg.event_cfg.extra_zone.type_probs);
    [e_start, e_end] = sample_window_in_zone_local(zwin, cfg.event_cfg.(etype).duration_range, Ts_ref);
    inject_info = apply_event_to_inject_info_local(inject_info, etype, [e_start, e_end], cfg.event_cfg);
    inject_info.extra_zone_event_added = true;
    inject_info.extra_zone_event = struct('zone', zname, 'type', etype, 'window', [e_start, e_end]);
end

%% 构建注入信号时序
t = ref_path.t;
N = numel(t);
slip_gamma_vec = ones(N, 1);
stall_load_vec = zeros(N, 1);

if inject_info.slip_injected && ~isempty(inject_info.slip_windows)
    for w = 1:size(inject_info.slip_windows, 1)
        ww = inject_info.slip_windows(w, :);
        m = t >= ww(1) & t <= ww(2);
        slip_gamma_vec(m) = inject_info.slip_gammas(w);
    end
end

if inject_info.stall_injected && ~isempty(inject_info.stall_windows)
    for w = 1:size(inject_info.stall_windows, 1)
        ww = inject_info.stall_windows(w, :);
        m = t >= ww(1) & t <= ww(2);
        stall_load_vec(m) = inject_info.stall_loads(w);
    end
end

if inject_info.load_change_injected && ~isempty(inject_info.load_change_windows)
    for w = 1:size(inject_info.load_change_windows, 1)
        ww = inject_info.load_change_windows(w, :);
        m = t >= ww(1) & t <= ww(2);
        stall_load_vec(m) = stall_load_vec(m) + inject_info.load_changes(w);
    end
end

% 向后兼容字段
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


function [label_main, label_turn] = generate_labels( ...
    t, y_raw, theta, omega_ref, inject_info, Ts)
% 事后生成标签（3 类主分类 + 转弯状态）
%
% 标签优先级：stall → slope → flat
%   1: flat, 2: stall, 3: slope
%
% 策略：注入窗口 ground truth 为主，启发式补充

N = length(t);
label_main = ones(N, 1);  % 默认 flat (1)

% 1) Stall 标注（最高优先级）：基于注入窗口 ground truth
if isfield(inject_info, 'stall_injected') && inject_info.stall_injected
    if isfield(inject_info, 'stall_windows') && ~isempty(inject_info.stall_windows)
        wins = inject_info.stall_windows;
    elseif isfield(inject_info, 'stall_window')
        wins = inject_info.stall_window;
    else
        wins = [];
    end
    for w = 1:size(wins, 1)
        m = t >= wins(w, 1) & t <= wins(w, 2);
        label_main(m) = 2;  % stall
    end
end

% 2) Slope 标注（次高优先级，不覆盖 stall）
theta_slope_thresh = deg2rad(2.0);
m_slope = abs(theta) >= theta_slope_thresh & label_main == 1;
label_main(m_slope) = 3;  % slope

% 3) 启发式 stall 补充（仅当 label_main==1 即 flat 时）
I_sum = abs(y_raw(:, 12)) + abs(y_raw(:, 13));
omega_l = abs(y_raw(:, 17));
omega_r = abs(y_raw(:, 18));
v_meas = y_raw(:, 4);
heur_stall = (I_sum > 12) & (omega_l < 0.1) & (omega_r < 0.1) & (v_meas < 0.20);
heur_stall = apply_dwell(heur_stall, max(1, round(0.8 / Ts)));
label_main(heur_stall & label_main == 1) = 2;

% 转弯标签：基于 omega_ref + 驻留时间滤波
omega_turn_thresh = 0.05;
raw_turn = zeros(N, 1);
raw_turn(omega_ref > omega_turn_thresh) = 1;
raw_turn(omega_ref < -omega_turn_thresh) = -1;
label_turn = apply_turn_dwell(raw_turn, max(1, round(0.40 / Ts)));
end


function out = apply_turn_dwell(raw_turn, dwell_steps)
% 对左右转标签分别做持续时间过滤
N = numel(raw_turn);
out = zeros(N, 1);
for sgn = [-1, 1]
    mask = (raw_turn == sgn);
    mask = apply_dwell(mask, dwell_steps);
    out(mask) = sgn;
end
end


function m2 = apply_dwell(m, dwell_steps)
% 布尔序列驻留过滤，仅保留长度>=dwell_steps的连续片段
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


function event_type = sample_event_type_local(type_list, probs)
% 从候选事件类型中按概率采样
if nargin < 2 || isempty(probs)
    probs = ones(1, numel(type_list)) / numel(type_list);
else
    probs = probs(:)' / sum(probs);
end
cs = cumsum(probs);
r = rand();
idx = find(r <= cs, 1, 'first');
if isempty(idx)
    idx = numel(type_list);
end
event_type = type_list{idx};
end


function [t_start, t_end] = sample_window_in_zone_local(zone, dur_range, Ts)
% 在指定 zone 内随机采样事件窗口
z0 = zone(1);
z1 = zone(2);
dur = dur_range(1) + (dur_range(2) - dur_range(1)) * rand();
dur = max(dur, Ts);
if z1 - z0 <= dur + Ts
    t_start = z0;
    t_end = z1;
    return;
end
t_start = z0 + (z1 - z0 - dur) * rand();
t_end = t_start + dur;
end


function inject_info = apply_event_to_inject_info_local(inject_info, event_type, window, event_cfg)
% 将事件写入注入信息结构（支持 slip / load_change / stall）
switch lower(event_type)
    case 'slip'
        inject_info.slip_injected = true;
        gamma = event_cfg.slip.gamma_range(1) + diff(event_cfg.slip.gamma_range) * rand();
        inject_info.slip_windows = [inject_info.slip_windows; window];
        inject_info.slip_gammas = [inject_info.slip_gammas; gamma];

    case 'stall'
        inject_info.stall_injected = true;
        load_val = event_cfg.stall.load_range(1) + diff(event_cfg.stall.load_range) * rand();
        inject_info.stall_windows = [inject_info.stall_windows; window];
        inject_info.stall_loads = [inject_info.stall_loads; load_val];

    case 'load_change'
        inject_info.load_change_injected = true;
        load_val = event_cfg.load_change.load_range(1) + diff(event_cfg.load_change.load_range) * rand();
        inject_info.load_change_windows = [inject_info.load_change_windows; window];
        inject_info.load_changes = [inject_info.load_changes; load_val];

    otherwise
        error('unknown event type: %s', event_type);
end
end


function n = get_scene_runs(scene, default_runs, per_scene)
% 读取场景 run 数，支持 per-scene 覆盖
if isstruct(per_scene) && isfield(per_scene, scene)
    n = per_scene.(scene);
else
    n = default_runs;
end
n = max(1, round(n));
end


function [enable_noise, std_scale, variant] = resolve_noise_profile_local(profile, noise_on)
% 根据噪声策略决定本次 run 的噪声开关与噪声倍率
mode = get_field(profile, 'mode', 'match');
if strcmpi(mode, 'match')
    enable_noise = logical(noise_on);
    std_scale = double(enable_noise);
    variant = ternary(enable_noise, 'match_noisy', 'match_clean');
    if enable_noise && std_scale == 0
        std_scale = 1.0;
    end
    return;
end

clean_ratio = get_field(profile, 'clean_ratio', 0.3);
scales = get_field(profile, 'noisy_scales', [1.0]);
probs = get_field(profile, 'noisy_probs', []);

if rand() < clean_ratio
    enable_noise = false;
    std_scale = 0;
    variant = 'mixed_clean';
    return;
end

enable_noise = true;
if isempty(scales)
    scales = [1.0];
end
if isempty(probs)
    probs = ones(size(scales)) / numel(scales);
else
    probs = probs(:)';
    probs = probs / sum(probs);
end

r = rand();
cs = cumsum(probs);
idx = find(r <= cs, 1, 'first');
if isempty(idx)
    idx = numel(scales);
end
std_scale = scales(idx);
variant = sprintf('mixed_noisy_x%.2f', std_scale);
end


function v = get_field(s, name, default_v)
% 安全读取结构体字段
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = default_v;
end
end


function out = ternary(cond, a, b)
% 三元表达式辅助函数
if cond
    out = a;
else
    out = b;
end
end


function prepare_runtime_workspace_local(model_name, verbose)
% 在数据生成前刷新模型运行时依赖
if nargin < 2
    verbose = false;
end

if verbose
    fprintf('正在准备运行时工作区: %s\n', model_name);
end

% 初始化项目路径
if exist('init_project', 'file') == 2
    try
        init_project();
    catch ME
        if verbose
            fprintf('  init_project skipped: %s\n', ME.message);
        end
    end
end

% 执行 preload 函数，确保 ctrl/maps 参数一致
if exist('preloadfcn_v2', 'file') == 2
    try
        evalin('base', 'preloadfcn_v2');
    catch ME
        warning('GRU_gen_train_data:PreloadFailed', ...
            'preloadfcn_v2 failed: %s', ME.message);
    end
elseif exist('preloadfcn_v1', 'file') == 2
    try
        evalin('base', 'preloadfcn_v1');
    catch ME
        warning('GRU_gen_train_data:PreloadFailed', ...
            'preloadfcn_v1 failed: %s', ME.message);
    end
else
    if verbose
        fprintf('  preload function not found, continue with current base workspace.\n');
    end
end

% 补充 MPC_idx（Simulink 编译器需要）
if ~evalin('base', 'exist(''MPC_idx'',''var'')')
    try
        db_tmp = evalin('base', 'db_rt');
        MPC_idx_val = [ceil(db_tmp.Nv/2), ceil(db_tmp.Nw/2), ceil(db_tmp.Nt/2), 1];
    catch
        MPC_idx_val = [6, 8, 11, 1];
    end
    assignin('base', 'MPC_idx', MPC_idx_val);
    if verbose
        fprintf('  → 已补充 MPC_idx = [%s] 到 base workspace\n', num2str(MPC_idx_val));
    end
end
end
