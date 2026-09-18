function y = output_eq_ref_train_data(x, u, theta_ground, params, slip_gamma, stall_load)
%OUTPUT_EQ_REF_TRAIN_DATA 训练数据生成专用 AGV 输出方程。
%
% 功能说明：
%   本函数由 agv_model_sfunc_train_data.m 间接调用，服务 GRU_DataGen.slx
%   的训练数据仿真。它保持原有被控对象输出契约，并额外暴露滑移、
%   负载/堵转和车辆诊断特征，便于 TCN 多任务头学习动态过渡状态。
%
% 扰动注入：
%   slip_gamma < 1.0 : 降低有效附着，并在轮速/滑移率中形成可观测线索。
%   stall_load > 0   : 施加额外纵向负载 [N]，形成 load/stall 过渡样本。
%
% 输出 y 为 34 x 1：
%   1-8   车辆状态：X,Y,psi,v,omega,delta_lf,delta_rr,beta。
%   9-11  IMU 观测：accel_x, gyro_y, gyro_z。
%   12-13 电机电流估计。
%   14-15 扰动估计。
%   16    theta_ground 坡度角。
%   17-18 轮速。
%   19-27 物理/车辆诊断特征。
%   28-31 slip/stall 标志与 LF/RR 法向载荷。
%   32-34 滑移率与横向加速度测量。

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
c_r = params.rolling_resistance;
rho = params.air_density;
CdA = params.drag_coefficient_area;
C_af = params.front_cornering_stiffness;
C_ar = params.rear_cornering_stiffness;
current_limit = params.current_limit;
g = params.gravity;
min_omega_threshold = params.min_angular_velocity_threshold;
low_speed_thresh = params.low_speed_threshold;

enable_noise = isfield(params, 'enable_noise') && params.enable_noise;
current_noise_std = getfield_default(params, 'current_noise_std', 0.0);
wheel_speed_noise_std = getfield_default(params, 'wheel_speed_noise_std', 0.0);
dist_noise_std = getfield_default(params, 'disturbance_noise_std', 0.0);
noise_factor = double(enable_noise);

persistent seeded theta_ground_prev;
if enable_noise && isfield(params, 'random_seed') && params.random_seed > 0 && isempty(seeded)
    rng(params.random_seed);
    seeded = true;
end

[N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer_train(F_cmd, omega, v, theta_ground, params);

F_wheel_max = current_limit * k_t * (eta * n) / max(r, 1e-6);
F_cmd_eff = sat_sym(F_cmd, 2 * F_wheel_max);

Lf = L / 2;
Lr = L / 2;
alpha_f = (beta + Lf * omega / max(abs(v), low_speed_thresh)) - delta_lf;
alpha_r = (beta - Lr * omega / max(abs(v), low_speed_thresh)) - delta_rr;

Fy_f_lin = -C_af * alpha_f;
Fy_r_lin = -C_ar * alpha_r;
Fy_f = sat(Fy_f_lin, -mu * N_lf, mu * N_lf);
Fy_r = sat(Fy_r_lin, -mu * N_rr, mu * N_rr);

W_drive = max(N_lf + N_rr, 1e-6);
w_lf = N_lf / W_drive;
w_rr = N_rr / W_drive;
if abs(omega_cmd) < min_omega_threshold && abs(omega) < min_omega_threshold
    w_lf = 0.5;
    w_rr = 0.5;
end

K_omega_p = 50.0;
omega_dot_desired = sat_sym(K_omega_p * (omega_cmd - omega), 10.0);
Mz_needed = I_z * omega_dot_desired;
Delta_Fx = 2 * Mz_needed / max(W, 1e-3);
Delta_Fx = sat_sym(Delta_Fx, 0.5 * mu * (N_lf + N_rr));

Fx_lf_cmd = F_cmd_eff * w_lf + Delta_Fx / 2;
Fx_rr_cmd = F_cmd_eff * w_rr - Delta_Fx / 2;

Fx_lf_allow = mu * N_lf * sqrt(max(1 - (Fy_f / max(mu * N_lf, 1e-6))^2, 0));
Fx_rr_allow = mu * N_rr * sqrt(max(1 - (Fy_r / max(mu * N_rr, 1e-6))^2, 0));
F_drive_lf = sign(Fx_lf_cmd) * min(abs(Fx_lf_cmd), Fx_lf_allow);
F_drive_rr = sign(Fx_rr_cmd) * min(abs(Fx_rr_cmd), Fx_rr_allow);
F_drive_total = F_drive_lf + F_drive_rr;

F_aero = 0.5 * rho * CdA * v^2 * sign(v);
F_drag = F_rolling_total + F_aero;
F_slope = m * g * sin(theta_ground);
wheel_inertia = getfield_default(params, 'wheel_inertia', 0.0);
motor_inertia = getfield_default(params, 'motor_inertia', 0.0);
m_eff_total = m + 2 * (wheel_inertia + motor_inertia * n^2) / max(r^2, 1e-6);

accel_x_base = (F_drive_total - F_drag - F_slope - stall_load) / max(m_eff_total, 1e-6);
accel_x_meas = accel_x_base + noise_factor * 0.1 * randn;

if isempty(theta_ground_prev)
    theta_ground_prev = theta_ground;
end
gyro_y_base = (theta_ground - theta_ground_prev) / max(Ts, 1e-6);
theta_ground_prev = theta_ground;
gyro_y_meas = gyro_y_base + noise_factor * 0.01 * randn;
gyro_z_meas = omega + noise_factor * 0.02 * randn;

[v_lf, v_rr] = wheel_linear_speeds(v, omega, beta, L, W, min_omega_threshold);
omega_wheel_lf_base = v_lf / max(r, 1e-6);
omega_wheel_rr_base = v_rr / max(r, 1e-6);
if slip_gamma < 0.95
    slip_spin = (1.0 / max(slip_gamma, 0.1) - 1.0) * 0.04;
    omega_wheel_lf_base = omega_wheel_lf_base * (1.0 + slip_spin);
    omega_wheel_rr_base = omega_wheel_rr_base * (1.0 - 0.5 * slip_spin);
end
omega_wheel_lf = omega_wheel_lf_base + noise_factor * wheel_speed_noise_std * randn;
omega_wheel_rr = omega_wheel_rr_base + noise_factor * wheel_speed_noise_std * randn;

I_meas_lf = F_drive_lf * r / max(n * eta * k_t, 1e-6) + noise_factor * current_noise_std * randn;
I_meas_rr = F_drive_rr * r / max(n * eta * k_t, 1e-6) + noise_factor * current_noise_std * randn;

W_total = max(m * g * cos(theta_ground), 1e-6);
w_ratio_lf = N_lf / W_total;
w_ratio_rr = N_rr / W_total;
F_inertia_total = m_eff_total * accel_x_meas;
F_dist_calc_lf = F_drive_lf - c_r * N_lf - F_inertia_total * w_ratio_lf ...
    - F_slope * w_ratio_lf + noise_factor * dist_noise_std * randn;
F_dist_calc_rr = F_drive_rr - c_r * N_rr - F_inertia_total * w_ratio_rr ...
    - F_slope * w_ratio_rr + noise_factor * dist_noise_std * randn;

load_ratio_front = (N_lf + N_rf) / W_total;
load_ratio_rear = (N_lr + N_rr) / W_total;
load_transfer_lateral = abs(N_lf - N_rf) / max(N_lf + N_rf, 1e-6);
tire_utilization_lf = sqrt((F_drive_lf / max(mu * N_lf, 1e-6))^2 + (Fy_f / max(mu * N_lf, 1e-6))^2);
tire_utilization_rr = sqrt((F_drive_rr / max(mu * N_rr, 1e-6))^2 + (Fy_r / max(mu * N_rr, 1e-6))^2);
lateral_accel = v * omega;
slip_angle_front = alpha_f;
slip_angle_rear = alpha_r;
drive_force_asymmetry = abs(F_drive_lf - F_drive_rr) / max(abs(F_drive_lf) + abs(F_drive_rr), 1e-6);

slip_flag = double((slip_gamma < 0.95) || max(tire_utilization_lf, tire_utilization_rr) > 0.98);
total_current = abs(I_meas_lf) + abs(I_meas_rr);
stall_flag = double((stall_load > 1e-6) || (v < low_speed_thresh && total_current > 1.6 * current_limit));

v_obs_ref = 0.5 * (omega_wheel_lf + omega_wheel_rr) * r;
den_obs = max(abs(v_obs_ref), low_speed_thresh);
slip_ratio_lf = sat((omega_wheel_lf * r - v_obs_ref) / den_obs, -1.0, 1.0);
slip_ratio_rr = sat((omega_wheel_rr * r - v_obs_ref) / den_obs, -1.0, 1.0);
accel_y_base = (Fy_f + Fy_r) / max(m, 1e-6);
accel_y_meas = accel_y_base + noise_factor * 0.1 * randn;

y = [
    X; Y; psi; v; omega; delta_lf; delta_rr; beta;
    accel_x_meas; gyro_y_meas; gyro_z_meas;
    I_meas_lf; I_meas_rr;
    F_dist_calc_lf; F_dist_calc_rr;
    theta_ground;
    omega_wheel_lf; omega_wheel_rr;
    load_ratio_front; load_ratio_rear; load_transfer_lateral;
    tire_utilization_lf; tire_utilization_rr;
    lateral_accel; slip_angle_front; slip_angle_rear; drive_force_asymmetry;
    slip_flag; stall_flag;
    N_lf; N_rr;
    slip_ratio_lf; slip_ratio_rr;
    accel_y_meas
];

end

function [v_lf, v_rr] = wheel_linear_speeds(v, omega, beta, L, W, min_omega_threshold)
if abs(omega) > min_omega_threshold && abs(v) > 1e-4
    R = v / omega;
    sgn = sign(omega);
    y_c = R * sgn;
    r_lf = sqrt((L / 2)^2 + (y_c - W / 2 * sgn)^2);
    r_rr = sqrt((L / 2)^2 + (y_c + W / 2 * sgn)^2);
    v_lf = (r_lf / max(abs(R), 1e-6)) * v;
    v_rr = (r_rr / max(abs(R), 1e-6)) * v;
else
    v_lf = v * cos(beta);
    v_rr = v * cos(beta);
end
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

function v = getfield_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
