function ref = gen_agv_ref_path(path_type, params, opts)
% =============================
% 文件名：gen_agv_ref_path.m
% 版本号：V1.4
% 最后修改时间：2025-12-29
% 作者：LPV-MPC Project
% 功能描述：
%   为AGV生成多种场景的参考轨迹数据，所有路径前3s匀速直行：
%   - 'straight'           : 平地直线行驶
%   - 'straight_turn'      : 直线后左转（等价于 straight_left_turn）
%   - 'straight_left_turn' : 直线后左转
%   - 'straight_right_turn': 直线后右转
%   - 'slope'              : 坡度直线行驶（3s后启用坡度）
%   - 'bumpy'              : 颠簸直线行驶（3s后启用颠簸）
%   - 's_curve'            : 直行后S弯（右转后左转）
%   - 'multi_turn_left'    : 变半径左转（5m→10m→20m）
%   - 'multi_turn_right'   : 变半径右转（5m→10m→20m）
%
% 输入参数：
%   - path_type : 字符串，路径类型（见上述）
%   - params    : 结构体，来自 parameters.m，至少包含 Ts
%   - opts      : 可选参数结构体
%
% 输出参数：
%   - ref : 结构体，包含参考轨迹数据
% =============================

%% 输入参数处理
if nargin < 3
    opts = struct();
end

% 默认参数
T_end = getFieldOrDefault(opts, 'T_end', 120.0);
R = getFieldOrDefault(opts, 'R', 10.0);
v0 = getFieldOrDefault(opts, 'v0', 1.0);
theta_slope = getFieldOrDefault(opts, 'theta_slope', deg2rad(5));
bumpy_amp = getFieldOrDefault(opts, 'bumpy_amp', deg2rad(5));
rho_filter_tau = getFieldOrDefault(opts, 'rho_filter_tau', 0.4);
turn_transition = getFieldOrDefault(opts, 'turn_transition', 0.4);
turn_direction = getFieldOrDefault(opts, 'turn_direction', 'left');

% 固定参数：所有路径前 t_straight_init 秒匀速直行
t_straight_init = 3.0;  % [s] 初始直行时间

% 采样周期
Ts = params.Ts;

% 生成时间向量
t = (0:Ts:T_end)';
N = length(t);

%% 根据路径类型生成轨迹
switch lower(path_type)
    case 'straight'
        [X, Y, psi, v, omega, theta] = gen_straight(t, v0);
        
    case 'straight_turn'
        [X, Y, psi, v, omega, theta] = gen_straight_turn(t, v0, R, turn_transition, Ts, 'left', t_straight_init);

    case 'straight_left_turn'
        [X, Y, psi, v, omega, theta] = gen_straight_turn(t, v0, R, turn_transition, Ts, 'left', t_straight_init);

    case 'straight_right_turn'
        [X, Y, psi, v, omega, theta] = gen_straight_turn(t, v0, R, turn_transition, Ts, 'right', t_straight_init);
        
    case 'slope'
        [X, Y, psi, v, omega, theta] = gen_slope(t, v0, theta_slope, t_straight_init);
        
    case 'bumpy'
        [X, Y, psi, v, omega, theta] = gen_bumpy(t, v0, bumpy_amp, t_straight_init);
    
    case 's_curve'
        [X, Y, psi, v, omega, theta] = gen_s_curve(t, v0, 5.0, t_straight_init, pi/2);
        
    case 'multi_turn_left'
        [X, Y, psi, v, omega, theta] = gen_multi_turn(t, v0, Ts, t_straight_init, 'left');
        
    case 'multi_turn_right'
        [X, Y, psi, v, omega, theta] = gen_multi_turn(t, v0, Ts, t_straight_init, 'right');
        
    otherwise
        error('gen_agv_ref_path:InvalidType', ...
              '未知的路径类型: %s。支持类型: straight, straight_left_turn, straight_right_turn, slope, bumpy, s_curve, multi_turn_left, multi_turn_right', path_type);
end

%% 构建路径坐标系误差参考（设为0，便于MPC跟踪）
e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);

%% 构建调度变量 rho = [v, omega, theta]（均为有符号）并滤波
rho_raw = [v, omega, theta];
rho = applyFirstOrderFilter(rho_raw, Ts, rho_filter_tau);

%% 构建输出结构体
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

% 构建From Workspace兼容格式
ref.time = t;
ref.signals.values = [X, Y, psi, v, omega, theta, e_y_ref, e_psi_ref, e_v_ref];
ref.signals.dimensions = 9;

% 元数据
ref.meta.path_type = path_type;
ref.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ref.meta.version = 'V1.4';
ref.meta.author = 'LPV-MPC Project';
ref.meta.params.T_end = T_end;
ref.meta.params.R = R;
ref.meta.params.v0 = v0;
ref.meta.params.theta_slope = theta_slope;
ref.meta.params.bumpy_amp = bumpy_amp;
ref.meta.params.rho_filter_tau = rho_filter_tau;
ref.meta.params.turn_transition = turn_transition;
ref.meta.params.t_straight_init = t_straight_init;
ref.meta.params.Ts = Ts;

end

%% ========== 子函数：各路径类型生成器 ==========

function [X, Y, psi, v, omega, theta] = gen_straight(t, v0)
% 直线路径：匀速直线运动
N = length(t);

X = v0 * t;
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);
end

function [X, Y, psi, v, omega, theta] = gen_straight_turn(t, v0, R, t_trans, Ts, direction, t_straight_init)
% 直线+转弯路径：前 t_straight_init 秒直线，后续圆弧，曲率S曲线平滑过渡
N = length(t);

if nargin < 7 || isempty(t_straight_init)
    t_straight_init = 3.0;
end
if nargin < 6 || isempty(direction)
    direction = 'left';
end
dir_sign = 1;
if strcmpi(direction, 'right')
    dir_sign = -1;
end

% 切换时间点
t_switch = t_straight_init;
omega_max = dir_sign * (v0 / R);

% 初始化
X = zeros(N, 1);
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);

% 计算 omega（过渡段用余弦S曲线）
for i = 1:N
    if t(i) <= t_switch
        omega(i) = 0;
    elseif t(i) <= t_switch + t_trans
        tau = (t(i) - t_switch) / t_trans;
        omega(i) = omega_max * 0.5 * (1 - cos(pi * tau));
    else
        omega(i) = omega_max;
    end
end

% 积分 omega 得到 psi
for i = 2:N
    psi(i) = psi(i-1) + omega(i-1) * Ts;
end

% 根据 psi 计算 X, Y
X(1) = 0;
Y(1) = 0;
for i = 2:N
    ds = v0 * Ts;
    X(i) = X(i-1) + ds * cos(psi(i-1));
    Y(i) = Y(i-1) + ds * sin(psi(i-1));
end
end

function [X, Y, psi, v, omega, theta] = gen_slope(t, v0, theta_slope, t_straight_init)
% 坡度直线路径：前 t_straight_init 秒平地，之后固定坡度
N = length(t);

if nargin < 4 || isempty(t_straight_init)
    t_straight_init = 3.0;
end

X = v0 * t;
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);

% 坡度：前 t_straight_init 秒为0，之后为 theta_slope
theta = zeros(N, 1);
for i = 1:N
    if t(i) > t_straight_init
        theta(i) = theta_slope;
    end
end
end

function [X, Y, psi, v, omega, theta] = gen_bumpy(t, v0, bumpy_amp, t_straight_init)
% 颠簸直线路径：前 t_straight_init 秒平地，之后坡度振荡
N = length(t);

if nargin < 4 || isempty(t_straight_init)
    t_straight_init = 3.0;
end

X = v0 * t;
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);

theta = zeros(N, 1);
for i = 1:N
    if t(i) > t_straight_init
        theta(i) = bumpy_amp * sin(t(i) - t_straight_init);
    end
end
end

function [X, Y, psi, v, omega, theta] = gen_s_curve(t, v0, R, t_straight, turn_angle)
% S弯路径：先直行，再右转后左转
N = length(t);
if N < 2
    error('gen_s_curve:TimeVectorTooShort', '时间向量长度至少为2');
end

Ts = t(2) - t(1);
t_straight = max(0, t_straight);
remaining = max(t(end) - t_straight, 0);
turn_angle = max(0, abs(turn_angle));
if turn_angle == 0
    turn_angle = pi/2;
end
omega_mag = v0 / max(R, eps);
t_arc_nominal = turn_angle / omega_mag;
t_arc = min(t_arc_nominal, remaining / 2);
t2 = t_straight + t_arc;
t3 = t2 + t_arc;

X = zeros(N, 1);
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);

for i = 1:N
    if t(i) <= t_straight
        omega(i) = 0;
    elseif t(i) <= t2
        omega(i) = -omega_mag;  % 右转
    elseif t(i) <= t3
        omega(i) = omega_mag;   % 左转
    else
        omega(i) = 0;
    end
end

for k = 2:N
    psi(k) = psi(k-1) + omega(k-1) * Ts;
    X(k) = X(k-1) + v0 * Ts * cos(psi(k-1));
    Y(k) = Y(k-1) + v0 * Ts * sin(psi(k-1));
end
end

function [X, Y, psi, v, omega, theta] = gen_multi_turn(t, v0, Ts, t_straight_init, direction)
% 变半径转弯路径：0-3s直行，3-10s R=5m，10-15s R=10m，15-20s R=20m
% 半径切换时使用S曲线平滑过渡
N = length(t);

if nargin < 5 || isempty(direction)
    direction = 'left';
end
dir_sign = 1;
if strcmpi(direction, 'right')
    dir_sign = -1;
end

% 时间节点
t1 = t_straight_init;  % 3s: 直行结束
t2 = 10.0;             % 10s: R=5m 结束
t3 = 15.0;             % 15s: R=10m 结束
% t4 = 20.0            % 20s: R=20m 结束

% 半径序列（确保 omega = v/R 在 LPV 网格范围 [-0.2, 0.2] 内）
R1 = 6.67;  % 3-10s: omega ≈ 0.15 rad/s
R2 = 10.0;  % 10-15s: omega = 0.1 rad/s
R3 = 20.0;  % 15-20s: omega = 0.05 rad/s

% 过渡时间（半径切换的平滑过渡）
t_trans = 0.5;  % 0.5s 过渡期

% 初始化
X = zeros(N, 1);
Y = zeros(N, 1);
psi = zeros(N, 1);
v = v0 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);

% 计算 omega（基于当前半径）
for i = 1:N
    ti = t(i);
    
    if ti <= t1
        % 直行段
        omega(i) = 0;
    elseif ti <= t1 + t_trans
        % 直行→R1 过渡
        tau = (ti - t1) / t_trans;
        omega_target = dir_sign * v0 / R1;
        omega(i) = omega_target * 0.5 * (1 - cos(pi * tau));
    elseif ti <= t2 - t_trans
        % R1 恒定段
        omega(i) = dir_sign * v0 / R1;
    elseif ti <= t2 + t_trans
        % R1→R2 过渡
        omega1 = dir_sign * v0 / R1;
        omega2 = dir_sign * v0 / R2;
        tau = (ti - (t2 - t_trans)) / (2 * t_trans);
        omega(i) = omega1 + (omega2 - omega1) * 0.5 * (1 - cos(pi * tau));
    elseif ti <= t3 - t_trans
        % R2 恒定段
        omega(i) = dir_sign * v0 / R2;
    elseif ti <= t3 + t_trans
        % R2→R3 过渡
        omega2 = dir_sign * v0 / R2;
        omega3 = dir_sign * v0 / R3;
        tau = (ti - (t3 - t_trans)) / (2 * t_trans);
        omega(i) = omega2 + (omega3 - omega2) * 0.5 * (1 - cos(pi * tau));
    else
        % R3 恒定段
        omega(i) = dir_sign * v0 / R3;
    end
end

% 积分 omega 得到 psi
for i = 2:N
    psi(i) = psi(i-1) + omega(i-1) * Ts;
end

% 根据 psi 计算 X, Y
X(1) = 0;
Y(1) = 0;
for i = 2:N
    ds = v0 * Ts;
    X(i) = X(i-1) + ds * cos(psi(i-1));
    Y(i) = Y(i-1) + ds * sin(psi(i-1));
end
end

%% ========== 工具函数 ==========

function rho_filtered = applyFirstOrderFilter(rho_raw, Ts, tau)
% 对调度变量应用一阶低通滤波器
[N, dim] = size(rho_raw);
alpha = Ts / (Ts + tau);
rho_filtered = zeros(N, dim);
rho_filtered(1, :) = rho_raw(1, :);

for k = 2:N
    rho_filtered(k, :) = alpha * rho_raw(k, :) + (1 - alpha) * rho_filtered(k-1, :);
end
end

function value = getFieldOrDefault(s, fieldname, default_value)
% 安全获取结构体字段，若不存在则返回默认值
if isfield(s, fieldname)
    value = s.(fieldname);
else
    value = default_value;
end
end
