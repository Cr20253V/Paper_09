function x_next = state_eq_ref_train_data(x, u, theta_ground, params, slip_gamma, stall_load)
%STATE_EQ_REF_TRAIN_DATA 训练数据生成专用 AGV 状态更新方程。
%
% 功能说明：
%   本函数与 output_eq_ref_train_data.m 配套使用，保持 8 状态 AGV
%   动力学契约，同时在训练数据生成阶段注入低附着滑移和外加纵向负载。
%   这些注入项用于构造 TCN 技术方案中要求的动态过渡样本，不用于正式
%   闭环控制主模型。
%
% 输入：
%   x            : 8 维车辆状态 [X,Y,psi,v,omega,delta_lf,delta_rr,beta]。
%   u            : 控制输入 [F_cmd, omega_cmd]。
%   theta_ground : 地面坡度角 [rad]。
%   params       : 车辆、轮胎、电机和采样周期参数。
%   slip_gamma   : 附着系数缩放，<1 表示低附着/滑移扰动。
%   stall_load   : 外加纵向负载 [N]，用于 load/stall 事件。
%
% 输出：
%   x_next       : 下一采样时刻 8 维车辆状态。

if nargin < 5 || isempty(slip_gamma)
    slip_gamma = 1.0;
end
if nargin < 6 || isempty(stall_load)
    stall_load = 0.0;
end

slip_gamma = sat(slip_gamma, 0.10, 1.20);
stall_load = max(0.0, stall_load);

X = x(1); Y = x(2); psi = x(3); v = x(4);
omega = x(5); delta_lf = x(6); delta_rr = x(7); beta = x(8);

F_cmd = u(1);
omega_cmd = u(2);

Ts = params.Ts;
m = params.mass;
I_z = params.Iz;
L = params.L;
W = params.W;
r = params.wheel_radius;
n = params.gear_ratio;
eta = params.gear_efficiency;
k_t = params.motor_torque_constant;
mu = max(params.friction_coefficient * slip_gamma, 0.05);
rho = params.air_density;
CdA = params.drag_coefficient_area;
C_af = params.front_cornering_stiffness;
C_ar = params.rear_cornering_stiffness;
C_yaw_damping = getfield_default(params, 'yaw_damping', 250.0);
beta_damping = getfield_default(params, 'sideslip_damping', 0.0);
beta_low_speed_damping = getfield_default(params, 'sideslip_low_speed_damping', 1.0);
delta_max = params.max_steering_angle;
delta_dot_max = params.max_steering_rate;
tau_delta = params.steering_time_constant;
current_limit = params.current_limit;
g = params.gravity;
min_omega_threshold = params.min_angular_velocity_threshold;
low_speed_thresh = params.low_speed_threshold;

if abs(omega_cmd) < min_omega_threshold || v < low_speed_thresh
    delta_lf_target = 0;
    delta_rr_target = 0;
else
    e_omega = omega_cmd - omega;
    if abs(omega) > abs(omega_cmd) * 1.2 && sign(omega) == sign(omega_cmd)
        delta_scale = max(abs(omega_cmd) / max(abs(omega), 1e-6), 0.1);
    else
        delta_scale = 1.0;
    end

    w_icr = omega;
    if abs(w_icr) < min_omega_threshold
        w_icr = omega_cmd;
    end
    R_cmd = (v / max(abs(w_icr), 1e-6)) * sign(w_icr);
    denom_lf = signed_min_abs(R_cmd - W / 2, 1e-6);
    denom_rr = signed_min_abs(R_cmd + W / 2, 1e-6);
    delta_lf_target = atan((L / 2) / denom_lf) * delta_scale;
    delta_rr_target = -atan((L / 2) / denom_rr) * delta_scale;
end

delta_lf_dot = (delta_lf_target - delta_lf) / max(tau_delta, Ts);
delta_rr_dot = (delta_rr_target - delta_rr) / max(tau_delta, Ts);
delta_lf_dot = sat(delta_lf_dot, -delta_dot_max, delta_dot_max);
delta_rr_dot = sat(delta_rr_dot, -delta_dot_max, delta_dot_max);
delta_lf_new = sat(delta_lf + Ts * delta_lf_dot, -delta_max, delta_max);
delta_rr_new = sat(delta_rr + Ts * delta_rr_dot, -delta_max, delta_max);

[N_lf, ~, ~, N_rr, F_rolling_total] = compute_load_transfer_train(F_cmd, omega, v, theta_ground, params);

F_wheel_max = current_limit * k_t * (eta * n) / max(r, 1e-6);
F_cmd_eff = sat_sym(F_cmd, 2 * F_wheel_max);

Lf = L / 2;
Lr = L / 2;
alpha_f = (beta + Lf * omega / max(abs(v), low_speed_thresh)) - delta_lf_new;
alpha_r = (beta - Lr * omega / max(abs(v), low_speed_thresh)) - delta_rr_new;
Fy_f = sat(-C_af * alpha_f, -mu * N_lf, mu * N_lf);
Fy_r = sat(-C_ar * alpha_r, -mu * N_rr, mu * N_rr);

W_drive = max(N_lf + N_rr, 1e-6);
w_lf = N_lf / W_drive;
w_rr = N_rr / W_drive;
if abs(omega_cmd) < min_omega_threshold && abs(omega) < min_omega_threshold
    w_lf = 0.5;
    w_rr = 0.5;
end

if v < low_speed_thresh || abs(omega_cmd) < min_omega_threshold
    Delta_Fx = 0;
else
    omega_dot_desired = sat_sym(50.0 * (omega_cmd - omega), 10.0);
    Delta_Fx = 2 * I_z * omega_dot_desired / max(W, 1e-3);
    Delta_Fx = sat_sym(Delta_Fx, 0.5 * mu * (N_lf + N_rr));
end

Fx_lf_cmd = F_cmd_eff * w_lf + Delta_Fx / 2;
Fx_rr_cmd = F_cmd_eff * w_rr - Delta_Fx / 2;

Fx_lf_allow = mu * N_lf * sqrt(max(1 - (Fy_f / max(mu * N_lf, 1e-6))^2, 0));
Fx_rr_allow = mu * N_rr * sqrt(max(1 - (Fy_r / max(mu * N_rr, 1e-6))^2, 0));
F_drive_lf = sign(Fx_lf_cmd) * min(abs(Fx_lf_cmd), Fx_lf_allow);
F_drive_rr = sign(Fx_rr_cmd) * min(abs(Fx_rr_cmd), Fx_rr_allow);

F_slope = m * g * sin(theta_ground);
wheel_inertia = getfield_default(params, 'wheel_inertia', 0.0);
motor_inertia = getfield_default(params, 'motor_inertia', 0.0);
m_eff_total = m + 2 * (wheel_inertia + motor_inertia * n^2) / max(r^2, 1e-6);

s_k = [X; Y; psi; v; omega; beta];
delta_lf_mid = (delta_lf + delta_lf_new) / 2;
delta_rr_mid = (delta_rr + delta_rr_new) / 2;

core = @(s, dl, dr) continuous_core_train(s, dl, dr, F_drive_lf, F_drive_rr, ...
    F_rolling_total, F_slope, stall_load, m_eff_total, I_z, Lf, Lr, ...
    low_speed_thresh, C_af, C_ar, mu, N_lf, N_rr, W, C_yaw_damping, ...
    beta_damping, beta_low_speed_damping, rho, CdA);

k1 = core(s_k, delta_lf, delta_rr);
k2 = core(s_k + 0.5 * Ts * k1, delta_lf_mid, delta_rr_mid);
k3 = core(s_k + 0.5 * Ts * k2, delta_lf_mid, delta_rr_mid);
k4 = core(s_k + Ts * k3, delta_lf_new, delta_rr_new);
s_new = s_k + (Ts / 6) * (k1 + 2 * k2 + 2 * k3 + k4);

X_new = s_new(1);
Y_new = s_new(2);
psi_new = normalize_angle(s_new(3));
v_new = max(0, s_new(4));
omega_new = s_new(5);
beta_new = sat(s_new(6), -deg2rad(15), deg2rad(15));

x_next = [X_new; Y_new; psi_new; v_new; omega_new; delta_lf_new; delta_rr_new; beta_new];

end

function ds = continuous_core_train(s, delta_lf, delta_rr, Fx_lf, Fx_rr, ...
    F_rolling_total, F_slope, stall_load, m_eff_total, I_z, Lf, Lr, ...
    low_speed_thresh, C_af, C_ar, mu, N_lf, N_rr, W, C_yaw_damping, ...
    beta_damping, beta_low_speed_damping, rho, CdA)

psi = s(3); v = s(4); omega = s(5); beta = s(6);

F_aero = 0.5 * rho * CdA * v^2 * sign(v);
F_drag = F_rolling_total + F_aero;

alpha_f = (beta + Lf * omega / max(abs(v), low_speed_thresh)) - delta_lf;
alpha_r = (beta - Lr * omega / max(abs(v), low_speed_thresh)) - delta_rr;
Fy_f = sat(-C_af * alpha_f, -mu * N_lf, mu * N_lf);
Fy_r = sat(-C_ar * alpha_r, -mu * N_rr, mu * N_rr);

F_drive_actual = Fx_lf + Fx_rr;
Mz_drive = (W / 2) * (Fx_lf - Fx_rr);
v_dot = (F_drive_actual - F_drag - F_slope - stall_load) / max(m_eff_total, 1e-6);
if v_dot < 0 && v <= 0
    v_dot = 0;
end

Mz_tire = Fy_f * Lf - Fy_r * Lr;
Mz_damping = -C_yaw_damping * omega;
omega_dot = sat_sym((Mz_tire + Mz_drive + Mz_damping) / max(I_z, 1e-6), 5.0);

if abs(v) < low_speed_thresh
    beta_dot = -beta_low_speed_damping * beta;
else
    beta_dot = (Fy_f + Fy_r) / (m_eff_total * max(abs(v), low_speed_thresh / 10)) - omega - beta_damping * beta;
end
beta_dot = sat_sym(beta_dot, deg2rad(10));

psi_dot = omega;
X_dot = v * cos(psi + beta);
Y_dot = v * sin(psi + beta);
ds = [X_dot; Y_dot; psi_dot; v_dot; omega_dot; beta_dot];
end

function [N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer_train(F_cmd, omega, v, theta_g, params)
m = params.mass;
g = params.gravity;
h_cg = params.h_cg;
W = params.W;
L = params.L;
c_r = params.rolling_resistance;
accel_limit = params.max_acceleration;

F_rolling_est = c_r * m * g * cos(theta_g);
F_aero_est = 0.5 * getfield_default(params, 'air_density', 1.225) ...
    * getfield_default(params, 'drag_coefficient_area', 0.5) * v^2 * sign(v);
F_slope_est = m * g * sin(theta_g);
a_long = sat((F_cmd - F_rolling_est - F_aero_est - F_slope_est) / max(m, 1e-6), ...
    -accel_limit, accel_limit);
Delta_long = m * a_long * (h_cg / max(L, 1e-6));

if abs(v) > 1e-3 && abs(omega) > 1e-6
    a_lat = abs(v * omega);
    Delta_lat = m * a_lat * (h_cg / max(W, 1e-6));
else
    Delta_lat = 0;
end
sgn_turn = sign(omega);

W_total = m * g * cos(theta_g);
N_front_base = W_total / 2 - Delta_long / 2;
N_rear_base = W_total / 2 + Delta_long / 2;
Delta_lat_front = sgn_turn * Delta_lat / 2;
Delta_lat_rear = sgn_turn * Delta_lat / 2;

N_lf = max(0, N_front_base / 2 - Delta_lat_front / 2);
N_rf = max(0, N_front_base / 2 + Delta_lat_front / 2);
N_lr = max(0, N_rear_base / 2 - Delta_lat_rear / 2);
N_rr = max(0, N_rear_base / 2 + Delta_lat_rear / 2);
F_rolling_total = c_r * (N_lf + N_rf + N_lr + N_rr);
end

function y = sat(x, xmin, xmax)
y = min(max(x, xmin), xmax);
end

function y = sat_sym(x, xmax)
y = min(max(x, -xmax), xmax);
end

function y = signed_min_abs(x, eps_value)
if x == 0
    y = eps_value;
else
    y = sign(x) * max(abs(x), eps_value);
end
end

function a = normalize_angle(a)
a = atan2(sin(a), cos(a));
end

function v = getfield_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
