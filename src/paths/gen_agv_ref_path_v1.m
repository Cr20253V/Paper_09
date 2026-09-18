function ref = gen_agv_ref_path_v1(params, opts)
% =============================
% 文件名：gen_agv_ref_path_v1.m
% 版本号：V4.0
% 最后修改时间：2026-03-10
% 作者：LPV-MPC Project
% 功能描述：
%   按用户指定的功能分区布局生成训练路径（非闭环）。
%
%   功能分区：
%   | 时间段    | 功能区     | 形状         | 状态                           |
%   |-----------|------------|--------------|--------------------------------|
%   | 0-10s     | 启动区     | 直线         | 加速                           |
%   | 10-50s    | 黄金测试区 | 直行向右     | ω=0, θ=0                       |
%   | 50-78s    | 纯转弯区   | S弯向下      | 延长转弯区，降低ω峰值与切换频率  |
%   | 78-98s    | 纯坡度区   | 坡度直线向左 | 隔离→上坡→过渡→下坡→过渡       |
%   | 98-118s   | 复合区     | 直线向左     | 平地隔离→坡度+转弯耦合         |
%   | 118-150s  | 闭环区     | 平缓弧线     | 单段50°/25s弧线+减速停车         |
% =============================

%% 输入参数处理
if nargin < 1
    error('gen_agv_ref_path:MissingParams', '需要提供 params 参数');
end
if nargin < 2
    opts = struct();
end

T_end = getFieldOrDefault(opts, 'T_end', 150.0);
v_cruise = getFieldOrDefault(opts, 'v_cruise', 1.0);
% 方案3：降低坡度段突变性。将纯坡度区与复合区分开配置，默认较旧版本更平缓。
slope_angle_pure = getFieldOrDefault(opts, 'slope_angle_pure', deg2rad(8.0));
slope_angle_composite = getFieldOrDefault(opts, 'slope_angle_composite', deg2rad(6.0));
rho_filter_tau = getFieldOrDefault(opts, 'rho_filter_tau', 0.4);
theta_filter_tau = getFieldOrDefault(opts, 'theta_filter_tau', 0.9);
omega_filter_tau = getFieldOrDefault(opts, 'omega_filter_tau', 0.6);
omega_limit = getFieldOrDefault(opts, 'omega_limit', 0.18);
turn_scale_pure = getFieldOrDefault(opts, 'turn_scale_pure', 1.0);
turn_scale_composite = getFieldOrDefault(opts, 'turn_scale_composite', 1.0);

% 方案A：速度参考与曲率/坡度耦合，提升动态可实现性
v_turn_ref = getFieldOrDefault(opts, 'v_turn_ref', 0.10);                   % |omega| 归一化参考 [rad/s]
v_turn_coupling_gain = getFieldOrDefault(opts, 'v_turn_coupling_gain', 0.25); % 转向降速强度 [0,1]←降低
v_slope_ref = getFieldOrDefault(opts, 'v_slope_ref', deg2rad(6.0));         % |theta| 归一化参考 [rad]
v_slope_coupling_gain = getFieldOrDefault(opts, 'v_slope_coupling_gain', 0.20);% 坡度降速强度 [0,1]←降低
v_min_ratio = getFieldOrDefault(opts, 'v_min_ratio', 0.55);                 % 非减速段最低巡航比例←提高
v_coupling_tau = getFieldOrDefault(opts, 'v_coupling_tau', 1.5);            % 降速调度平滑时间常数←增大


Ts = params.Ts;
transition_time = getFieldOrDefault(opts, 'transition_time', 1.8);
closure_turn_angle_deg = getFieldOrDefault(opts, 'closure_turn_angle_deg', 50.0);
closure_turn_end = getFieldOrDefault(opts, 'closure_turn_end', 143.0);
closure_speed_scale = getFieldOrDefault(opts, 'closure_speed_scale', 0.7);

%% 定义路径段落
segments = struct();
seg_idx = 0;

% ===== 区域1: 启动区 (0-10s) =====
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 0;
segments(seg_idx).t_end = 10;
segments(seg_idx).type = 'accel';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '启动区-加速';

% ===== 区域2: 黄金测试区 (10-50s) =====
% 直行向右，ω=0, θ=0
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 10;
segments(seg_idx).t_end = 50;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '黄金测试区-纯直线';

% ===== 区域3: 纯转弯区 (50-78s) =====
% 形状: 连续左转回头（少分段），降低 omega_ref 人为波动

% 3.1 左转回头主段 (50-69s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 50;
segments(seg_idx).t_end = 69;
segments(seg_idx).type = 'left_turn';
segments(seg_idx).turn_angle = deg2rad(132) * turn_scale_pure;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '纯转弯区-左转主段';

% 3.2 左转收尾对准坡度区 (69-78s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 69;
segments(seg_idx).t_end = 78;
segments(seg_idx).type = 'left_turn';
segments(seg_idx).turn_angle = deg2rad(46) * turn_scale_pure;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '纯转弯区-左转收尾';

% ===== 区域4: 纯坡度区 (78-98s) =====
% 形状: 坡度直线向左
% 状态: 直行隔离→上坡→平坡过渡→下坡

% 4.1 直行隔离 (78-80s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 78;
segments(seg_idx).t_end = 80;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '纯坡度区-隔离直行';

% 4.2 上坡直行 (80-86s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 80;
segments(seg_idx).t_end = 86;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = slope_angle_pure;
segments(seg_idx).desc = '纯坡度区-上坡';

% 4.3 平坡过渡 (86-89s) - 上下坡之间平滑过渡
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 86;
segments(seg_idx).t_end = 89;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '纯坡度区-平坡过渡';

% 4.4 下坡直行 (89-95s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 89;
segments(seg_idx).t_end = 95;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = -slope_angle_pure;
segments(seg_idx).desc = '纯坡度区-下坡';

% 4.5 直行结束过渡 (95-98s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 95;
segments(seg_idx).t_end = 98;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '纯坡度区-结束过渡';

% ===== 区域5: 复合区 (98-118s) =====
% 形状: 左向行进中加入小幅转向过渡，降低突变
% 状态: 小右转过渡→平地隔离→坡度+左转→平坡→坡度+右转→小左转过渡→直行

% 5.1 小右转过渡 (98-100s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 98;
segments(seg_idx).t_end = 100;
segments(seg_idx).type = 'right_turn';
segments(seg_idx).turn_angle = deg2rad(6) * turn_scale_composite;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '复合区-右转过渡';

% 5.2 平地直行隔离 (100-102s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 100;
segments(seg_idx).t_end = 102;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '复合区-平地隔离';

% 5.3 坡度+左转耦合 (102-107s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 102;
segments(seg_idx).t_end = 107;
segments(seg_idx).type = 'left_turn';
segments(seg_idx).turn_angle = deg2rad(8) * turn_scale_composite;
segments(seg_idx).slope = slope_angle_composite;
segments(seg_idx).desc = '复合区-上坡+左转';

% 5.4 平坡过渡 (107-109s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 107;
segments(seg_idx).t_end = 109;
segments(seg_idx).type = 'straight';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '复合区-平坡过渡';

% 5.5 坡度+右转耦合 (109-114s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 109;
segments(seg_idx).t_end = 114;
segments(seg_idx).type = 'right_turn';
segments(seg_idx).turn_angle = deg2rad(8) * turn_scale_composite;
segments(seg_idx).slope = -slope_angle_composite;
segments(seg_idx).desc = '复合区-下坡+右转';

% 5.6 平缓左转过渡到闭环 (114-118s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 114;
segments(seg_idx).t_end = 118;
segments(seg_idx).type = 'left_turn';
segments(seg_idx).turn_angle = deg2rad(6) * turn_scale_composite;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '复合区-左转过渡';

% ===== 区域6: 闭环区 (118-150s) =====
% 目标：单段平缓弧线转向起点方向 + 减速停车，使终点尽量靠近起点。
% 设计：50°/25s ≈ 0.035 rad/s，远低于 omega_limit，不产生饱和。

% 6.1 平缓左转弧线 (118-closure_turn_end)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = 118;
segments(seg_idx).t_end = closure_turn_end;
segments(seg_idx).type = 'left_turn';
segments(seg_idx).turn_angle = deg2rad(closure_turn_angle_deg);
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '闭环区-平缓左转弧线';

% 6.2 减速停车 (closure_turn_end-150s)
seg_idx = seg_idx + 1;
segments(seg_idx).t_start = closure_turn_end;
segments(seg_idx).t_end = 150;
segments(seg_idx).type = 'decel';
segments(seg_idx).turn_angle = 0;
segments(seg_idx).slope = 0;
segments(seg_idx).desc = '闭环区-减速停车';

num_segments = seg_idx;

% 根据最终 T_end 构建时间向量
t = (0:Ts:T_end)';
N = length(t);

%% 生成速度曲线 v(t)
v = buildSpeedProfile(t, segments, v_cruise);

%% 生成角速度曲线 omega(t) 和坡度曲线 theta(t)
[omega, theta] = buildOmegaTheta(t, segments, transition_time, omega_limit);

%% 对角速度进行一阶滤波，抑制尖峰（尽量不改变路径形状）
omega = applyFirstOrderFilter(omega, Ts, omega_filter_tau);
omega = min(max(omega, -omega_limit), omega_limit);

% 强制：闭环区内的直线/减速段保持直线（omega=0），避免滤波尾迹导致末段仍有转弯
for s = 1:length(segments)
    is_closure = ~isempty(strfind(segments(s).desc, '闭环区'));
    if is_closure && (strcmp(segments(s).type, 'straight') || strcmp(segments(s).type, 'decel'))
        mask = (t >= segments(s).t_start) & (t <= segments(s).t_end);
        omega(mask) = 0;
    end
end

%% 对坡度进行一阶滤波，抑制段间抖动
theta = applyFirstOrderFilter(theta, Ts, theta_filter_tau);

%% 速度-曲率-坡度耦合（方案A）
% 在转向/坡度较大时主动降低 v_ref，减少 e_v 大幅下挫与后续失跟踪。
turn_level = min(abs(omega) / max(v_turn_ref, 1e-3), 1.0);
slope_level = min(abs(theta) / max(v_slope_ref, 1e-3), 1.0);
scale_turn = 1.0 - v_turn_coupling_gain * turn_level;
scale_slope = 1.0 - v_slope_coupling_gain * slope_level;
speed_scale = max(scale_turn .* scale_slope, 0.15);

% 闭合区保持几何回归能力：默认不对闭合段做耦合降速（可用 closure_speed_scale 调低）
is_closure = false(N, 1);
for s = 1:num_segments
    if ~isempty(strfind(segments(s).desc, '闭环区'))
        mask = (t >= segments(s).t_start) & (t <= segments(s).t_end);
        is_closure(mask) = true;
    end
end
speed_scale(is_closure) = min(max(closure_speed_scale, 0.4), 1.0);
v_coupled = v .* speed_scale;

% 非减速段设置最低速度底线；减速段保留原有减速语义（可降至接近0）。
is_nondecel = true(N, 1);
for s = 1:num_segments
    is_decel = strcmp(segments(s).type, 'decel') || strcmp(segments(s).type, 'decel_turn');
    if is_decel
        mask = (t >= segments(s).t_start) & (t <= segments(s).t_end);
        is_nondecel(mask) = false;
    end
end
v_floor = v_min_ratio * v_cruise;
v(is_nondecel) = max(v_coupled(is_nondecel), v_floor);
v(~is_nondecel) = min(v(~is_nondecel), v_coupled(~is_nondecel));
v = applyFirstOrderFilter(v, Ts, v_coupling_tau);
v = max(v, 0);

%% 积分得到航向角 psi(t)
psi = zeros(N, 1);
for i = 2:N
    psi(i) = psi(i-1) + omega(i-1) * Ts;
end

%% 积分得到位置 X(t), Y(t)
X = zeros(N, 1);
Y = zeros(N, 1);
for i = 2:N
    ds = v(i-1) * Ts;
    X(i) = X(i-1) + ds * cos(psi(i-1));
    Y(i) = Y(i-1) + ds * sin(psi(i-1));
end



%% 构建输出
e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);

rho_raw = [v, omega, theta];
rho = applyFirstOrderFilter(rho_raw, Ts, rho_filter_tau);

ref.t = t;
ref.X_ref = X;
ref.Y_ref = Y;
ref.psi_ref = psi;
ref.v_ref = v;
ref.omega_ref = omega;
ref.theta_ref = theta;
ref.e_y_ref = e_y_ref;
ref.e_psi_ref = e_psi_ref;
ref.e_v_ref = e_v_ref;
ref.rho = rho;

ref.time = t;
ref.signals.values = [X, Y, psi, v, omega, theta, e_y_ref, e_psi_ref, e_v_ref];
ref.signals.dimensions = 9;

ref.meta.path_type = getFieldOrDefault(opts, 'path_type', 'industrial_lite');
ref.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ref.meta.version = 'V4.0';
ref.meta.params.T_end = T_end;
ref.meta.params.v_cruise = v_cruise;
ref.meta.params.slope_angle_pure = slope_angle_pure;
ref.meta.params.slope_angle_composite = slope_angle_composite;
ref.meta.params.omega_limit = omega_limit;
ref.meta.params.turn_scale_pure = turn_scale_pure;
ref.meta.params.turn_scale_composite = turn_scale_composite;
ref.meta.params.v_turn_ref = v_turn_ref;
ref.meta.params.v_turn_coupling_gain = v_turn_coupling_gain;
ref.meta.params.v_slope_ref = v_slope_ref;
ref.meta.params.v_slope_coupling_gain = v_slope_coupling_gain;
ref.meta.params.v_min_ratio = v_min_ratio;
ref.meta.params.v_coupling_tau = v_coupling_tau;
ref.meta.params.closure_speed_scale = closure_speed_scale;
ref.meta.params.transition_time = transition_time;
ref.meta.params.closure_turn_angle_deg = closure_turn_angle_deg;
ref.meta.params.closure_turn_end = closure_turn_end;
ref.meta.params.Ts = Ts;
ref.meta.segments = segments;
ref.meta.num_segments = num_segments;


ref.meta.zones.startup = [0, 10];
ref.meta.zones.golden_test = [10, 50];
ref.meta.zones.pure_turn = [50, 78];
ref.meta.zones.pure_slope = [78, 98];
ref.meta.zones.composite = [98, 118];
ref.meta.zones.closed_loop = [118, 150];
ref.meta.zones.closure = [118, 150];

end

%% 辅助函数
function idx = findSegmentIndex(t, segments)
idx = 1;
for i = 1:length(segments)
    if t >= segments(i).t_start && t < segments(i).t_end
        idx = i;
        return;
    end
end
idx = length(segments);
end

function rho_filtered = applyFirstOrderFilter(rho_raw, Ts, tau)
[N, dim] = size(rho_raw);
alpha = Ts / (Ts + tau);
rho_filtered = zeros(N, dim);
rho_filtered(1, :) = rho_raw(1, :);
for k = 2:N
    rho_filtered(k, :) = alpha * rho_raw(k, :) + (1 - alpha) * rho_filtered(k-1, :);
end
end

    function v = buildSpeedProfile(t, segments, v_cruise)
    N = length(t);
    v = zeros(N, 1);
    for i = 1:N
        ti = t(i);
        seg_idx = findSegmentIndex(ti, segments);
        seg = segments(seg_idx);
    
        switch seg.type
            case 'accel'
                tau = (ti - seg.t_start) / (seg.t_end - seg.t_start);
                v(i) = v_cruise * 0.5 * (1 - cos(pi * tau));
            case {'decel', 'decel_turn'}
                tau = (ti - seg.t_start) / (seg.t_end - seg.t_start);
                v(i) = v_cruise * 0.5 * (1 + cos(pi * tau));
            otherwise
                v(i) = v_cruise;
        end
    end
    end

    function [omega, theta] = buildOmegaTheta(t, segments, transition_time, omega_limit)
    N = length(t);
    num_segments = length(segments);
    omega = zeros(N, 1);
    theta = zeros(N, 1);

    seg_omega_targets = zeros(num_segments, 1);
    seg_theta_targets = zeros(num_segments, 1);
    seg_transition_time = zeros(num_segments, 1);

    for s = 1:num_segments
        seg_dur = segments(s).t_end - segments(s).t_start;
        seg_theta_targets(s) = segments(s).slope;
        seg_transition_time(s) = min(transition_time, 0.4 * max(seg_dur, 0));
    
        if segments(s).turn_angle ~= 0 && seg_dur > 0
            omega_raw = segments(s).turn_angle / seg_dur;
            if strcmp(segments(s).type, 'right_turn') || strcmp(segments(s).type, 'decel_turn')
                omega_raw = -omega_raw;
            end
            seg_omega_targets(s) = min(max(omega_raw, -omega_limit), omega_limit);
        
            % 采用无超调目标，避免段间补偿导致的峰前波动
        else
            seg_omega_targets(s) = 0;
        end
    end

    for i = 1:N
        ti = t(i);
        seg_idx = findSegmentIndex(ti, segments);
        seg = segments(seg_idx);
        seg_dur = seg.t_end - seg.t_start;
        seg_transition = seg_transition_time(seg_idx);
    
        omega_target = seg_omega_targets(seg_idx);
        theta_target = seg_theta_targets(seg_idx);
    
        if seg_idx > 1
            omega_prev = seg_omega_targets(seg_idx - 1);
            theta_prev = seg_theta_targets(seg_idx - 1);
        else
            omega_prev = omega_target;
            theta_prev = theta_target;
        end
    
        t_in_seg = ti - seg.t_start;
        if seg_transition > 0 && t_in_seg < seg_transition && seg_idx > 1
            tau = t_in_seg / seg_transition;
            blend_in = 0.5 * (1 - cos(pi * tau));
            omega(i) = omega_prev * (1 - blend_in) + omega_target * blend_in;
            theta(i) = theta_prev * (1 - blend_in) + theta_target * blend_in;
        else
            omega(i) = omega_target;
            theta(i) = theta_target;
        end
        omega(i) = min(max(omega(i), -omega_limit), omega_limit);
    end
    end

function value = getFieldOrDefault(s, fieldname, default_value)
if isfield(s, fieldname)
    value = s.(fieldname);
else
    value = default_value;
end
end

