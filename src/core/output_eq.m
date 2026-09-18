function y = output_eq(x, u, theta_ground, params)
% =============================
% 文件名：output_eq.m
% 功能描述：对角式双舵轮AGV输出方程
% 输入参数：
%   x: 状态向量 [X Y psi v omega delta_lf delta_rr beta] (8×1)
%   u: 输入向量 [F_cmd omega_cmd] (2×1)
%   theta_ground: 地面坡度角 (标量)
%   params: 参数结构体
% 输出参数：
%   y: 输出向量 (31×1) - V4.2扩展版本
%      [1-8]   基本状态变量：X, Y, psi, v, omega, delta_lf, delta_rr, beta
%      [9-11]  IMU测量：accel_x_meas, gyro_y_meas, gyro_z_meas
%      [12-13] 电流估计：I_meas_lf, I_meas_rr
%      [14-15] 扰动力估计：F_dist_calc_lf, F_dist_calc_rr
%      [16]    地面角度：theta_ground
%      [17-18] 轮速：omega_wheel_lf, omega_wheel_rr
%      [19-27] AI算法专用输出：载荷信息、轮胎利用率、运动状态（含前后侧偏角）
%      [28-31] 扩展诊断信息：slip_flag, stall_flag, N_lf, N_rr
% =============================

%% 提取状态变量
X = x(1); Y = x(2); psi = x(3); v = x(4);
omega = x(5); delta_lf = x(6); delta_rr = x(7); beta = x(8);

%% 提取输入
F_cmd = u(1);
omega_cmd = u(2);

%% 直接获取参数（从parameters.m结构体）
Ts = params.Ts;
m = params.mass;
I_z = params.Iz;
L = params.L;
W = params.W;
h_cg = params.h_cg;
r = params.wheel_radius;
n = params.gear_ratio;
eta = params.gear_efficiency;
k_t = params.motor_torque_constant;
mu = params.friction_coefficient;
c_r = params.rolling_resistance;
rho = params.air_density;
CdA = params.drag_coefficient_area;
C_af = params.front_cornering_stiffness;
C_ar = params.rear_cornering_stiffness;
delta_max = params.max_steering_angle;
delta_dot_max = params.max_steering_rate;
tau_delta = params.steering_time_constant;
current_limit = params.current_limit;
accel_limit = params.max_acceleration;
g = params.gravity;
min_omega_threshold = params.min_angular_velocity_threshold;
low_speed_thresh = params.low_speed_threshold;

% 噪声参数
enable_noise = params.enable_noise;
current_noise_std = params.current_noise_std;
wheel_speed_noise_std = params.wheel_speed_noise_std;
dist_noise_std = params.disturbance_noise_std;
noise_factor = double(enable_noise);

% 初始化随机数生成器（确保可复现，只在第一次调用时设置）
persistent seeded;
if enable_noise && params.random_seed > 0 && isempty(seeded)
    rng(params.random_seed);
    seeded = true;
end

%% === 几何：对角式转向目标（严格 ICR 约束，使用测量ω抑制增益放大） ===
if abs(omega_cmd) < min_omega_threshold || v < low_speed_thresh
    delta_lf_target = 0; delta_rr_target = 0;
else
    % ICR 坐标（车辆坐标系）：用测量ω替代命令ω，避免 v↓ 时目标舵角被放大
    w_icr = omega;  % 使用测量值
    R_cmd = (v / max(abs(w_icr),1e-6)) * sign(w_icr);
    x_c = 0.0; y_c = R_cmd;
    % 公式：tan(delta_lf)=(L/2-x_c)/(y_c - W/2)，tan(delta_rr)=-(x_c+L/2)/(y_c+W/2)
    delta_lf_target = atan2((L/2 - x_c), (y_c - W/2));
    delta_rr_target = -atan2((x_c + L/2), (y_c + W/2));
end

% NOTE(open-loop test): 观测侧不更新/不预测转角，仅读取状态中的
% delta_lf/delta_rr。原“舵机一阶”计算对输出无影响，已移除以避免误读。

%% === 载荷转移 & 滚阻 ===
[N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer(F_cmd, omega, v, theta_ground, params);

%% === 电机/传动限制推算到车轮牵引上限 ===
F_wheel_max = current_limit * k_t * (eta * n) / max(r,1e-6);  % 单驱动轮
num_drive_wheels = 2; % lf & rr
F_cmd_max_total = num_drive_wheels * F_wheel_max;
F_cmd_eff = sat_sym(F_cmd, F_cmd_max_total);

%% === 侧偏角（简单自行车模型的近似，用β作为全车质心侧滑角） ===
% 轮侧偏角近似：alpha_f = delta_lf - (v_y + Lf*omega)/v_x ≈ delta_lf - (beta + Lf*omega/v)
%               alpha_r = - (beta - Lr*omega/v)
Lf = L/2; Lr = L/2; % 对称
v_x = max(v * cos(beta), 1e-3);
alpha_f = (beta + Lf*omega/max(v,1e-3)) - delta_lf;
alpha_r = (beta - Lr*omega/max(v,1e-3)) - delta_rr; % 对角式双舵轮，后轮也有转向

% 线性侧偏刚度 + 软饱和（限幅到μN）
Fy_f_lin = -C_af * alpha_f;
Fy_r_lin = -C_ar * alpha_r;
Fy_f_max = mu * N_lf;
Fy_r_max = mu * N_rr;
% 侧向力限幅（支持光滑限幅）
use_smooth = params.use_smooth_saturation;
if use_smooth
    smooth_gain = params.smooth_gain;
    Fy_f = sat_smooth(Fy_f_lin, -Fy_f_max, Fy_f_max, smooth_gain);
    Fy_r = sat_smooth(Fy_r_lin, -Fy_r_max, Fy_r_max, smooth_gain);
else
Fy_f = sat(Fy_f_lin, -Fy_f_max, Fy_f_max);
Fy_r = sat(Fy_r_lin, -Fy_r_max, Fy_r_max);
end

%% === 牵引力分配：按法向载荷比例 + 偏航控制 + 摩擦椭圆限幅 ===
% 修正：只在两个驱动轮（左前+右后）之间按载荷比例分配
W_drive = N_lf + N_rr;  % 驱动轮总载荷（非全车总重）
w_lf = N_lf / max(W_drive,1e-6);  % 左前轮在驱动轮中的载荷占比
w_rr = N_rr / max(W_drive,1e-6);  % 右后轮在驱动轮中的载荷占比

% 直线/低曲率时等分扭矩，使观测与动力学一致
if (abs(omega_cmd) < min_omega_threshold) && (abs(omega) < min_omega_threshold)
    w_lf = 0.5;
    w_rr = 0.5;
end

% 恢复：观测侧与动力学保持一致的偏航力差估算（仅用于拆算分配，不闭环）
K_omega_p = 50.0;
e_omega = omega_cmd - omega;
omega_dot_desired = K_omega_p * e_omega;
omega_dot_max = 10.0;
omega_dot_desired = sat_sym(omega_dot_desired, omega_dot_max);
Mz_needed = I_z * omega_dot_desired;
Delta_Fx = 2 * Mz_needed / max(W, 1e-3);
Delta_Fx_max = max(abs(F_cmd_eff), 10) * 0.5;
Delta_Fx = sat_sym(Delta_Fx, Delta_Fx_max);

% 驱动力分配：基础（载荷比例）+ 偏航控制（力差）
Fx_lf_cmd = F_cmd_eff * w_lf + Delta_Fx/2;
Fx_rr_cmd = F_cmd_eff * w_rr - Delta_Fx/2;

% 摩擦椭圆：sqrt((Fx/μN)^2 + (Fy/μN)^2) <= 1
Fx_lf_allow = mu * N_lf * sqrt(max(1 - (Fy_f/max(mu*N_lf,1e-6))^2, 0));
Fx_rr_allow = mu * N_rr * sqrt(max(1 - (Fy_r/max(mu*N_rr,1e-6))^2, 0));
F_drive_lf = sign(Fx_lf_cmd) * min(abs(Fx_lf_cmd), Fx_lf_allow);
F_drive_rr = sign(Fx_rr_cmd) * min(abs(Fx_rr_cmd), Fx_rr_allow);

% 合力/合力矩
F_drive_total = F_drive_lf + F_drive_rr;

% 空气阻力 + 滚动阻力 + 坡度分量
F_aero = 0.5 * rho * CdA * v^2 * sign(v);
F_drag = F_rolling_total + F_aero;
F_slope = m * g * sin(theta_ground);

% 有效质量（加入旋转惯量等效）
wheel_inertia = params.wheel_inertia;
motor_inertia = params.motor_inertia;
m_eff_total = m + 2*(wheel_inertia + motor_inertia*n^2)/(r^2);

%% === 计算测量量 ===

% [9-11] IMU测量（添加噪声）
accel_x_base = (F_drive_total - F_drag - F_slope) / max(m_eff_total,1e-6);
accel_x_meas = accel_x_base + noise_factor * 0.1 * randn;
gyro_y_meas = 0 + noise_factor * 0.01 * randn; % 俯仰角速度（添加小噪声）
gyro_z_meas = omega + noise_factor * 0.02 * randn;

% [17-18] 轮速（基于ICR几何/低速保护）
if abs(omega) > min_omega_threshold && abs(v) > 1e-4
    R = v / omega; sgn = sign(omega); x_c = 0; y_c = R*sgn;
    r_lf = sqrt((x_c - L/2)^2 + (y_c - W/2*sgn)^2);
    r_rr = sqrt((x_c + L/2)^2 + (y_c + W/2*sgn)^2);
    v_lf = (r_lf / max(abs(R),1e-6)) * v;
    v_rr = (r_rr / max(abs(R),1e-6)) * v;
else
    v_lf = v * cos(beta);
    v_rr = v * cos(beta);
end
omega_wheel_lf = v_lf / max(r,1e-6) + noise_factor * wheel_speed_noise_std * randn;
omega_wheel_rr = v_rr / max(r,1e-6) + noise_factor * wheel_speed_noise_std * randn;

% [12-13] 电流估计（车轮侧力矩映射回电机电流）
I_meas_lf = F_drive_lf * r / max(n*eta*k_t,1e-6) + noise_factor * current_noise_std * randn;
I_meas_rr = F_drive_rr * r / max(n*eta*k_t,1e-6) + noise_factor * current_noise_std * randn;

% [14-15] 扰动观测（净外力残差的简单估计）：
F_inertia_total = m_eff_total * accel_x_meas;
W_total = m*g*cos(theta_ground);  % 补充定义W_total（全车重量，用于扰动估计分配）
w_ratio_lf = N_lf / max(W_total,1e-6);
w_ratio_rr = N_rr / max(W_total,1e-6);
F_inertia_lf = F_inertia_total * w_ratio_lf; F_inertia_rr = F_inertia_total * w_ratio_rr;
F_slope_lf = F_slope * w_ratio_lf; F_slope_rr = F_slope * w_ratio_rr;
F_rolling_lf = c_r * N_lf; F_rolling_rr = c_r * N_rr;
F_motor_actual_lf = F_drive_lf; F_motor_actual_rr = F_drive_rr;
F_dist_calc_lf = F_motor_actual_lf - F_rolling_lf - F_inertia_lf - F_slope_lf + noise_factor*dist_noise_std*randn;
F_dist_calc_rr = F_motor_actual_rr - F_rolling_rr - F_inertia_rr - F_slope_rr + noise_factor*dist_noise_std*randn;

%% 计算额外的AI算法输出变量
% 载荷分配信息
load_ratio_front = (N_lf + N_rf) / max(W_total, 1e-6);
load_ratio_rear = (N_lr + N_rr) / max(W_total, 1e-6);
load_transfer_lateral = abs(N_lf - N_rf) / max(N_lf + N_rf, 1e-6);

% 轮胎利用率（摩擦椭圆）
tire_utilization_lf = sqrt((F_drive_lf/max(mu*N_lf,1e-6))^2 + (Fy_f/max(mu*N_lf,1e-6))^2);
tire_utilization_rr = sqrt((F_drive_rr/max(mu*N_rr,1e-6))^2 + (Fy_r/max(mu*N_rr,1e-6))^2);

% 运动状态指标
lateral_accel = v * omega; % 横向加速度估计 [m/s^2] - 修正量纲错误
slip_angle_front = alpha_f;
slip_angle_rear = alpha_r;

% 驱动状态
drive_force_asymmetry = abs(F_drive_lf - F_drive_rr) / max(F_drive_lf + F_drive_rr, 1e-6);

% 二元状态标志
slip_flag = double(max(tire_utilization_lf, tire_utilization_rr) > 0.98); % 打滑标志
total_current = I_meas_lf + I_meas_rr;
motor_current_limit_total = 2 * current_limit;
stall_flag = double(v < low_speed_thresh && total_current > 0.8 * motor_current_limit_total); % 堵转标志

%% 汇总输出（31×1）- 为AI算法提供丰富信息
y = [
    % [1-8] 基本状态变量
    X; Y; psi; v; omega; delta_lf; delta_rr; beta;
    % [9-11] IMU测量
    accel_x_meas; gyro_y_meas; gyro_z_meas;
    % [12-13] 电流估计
    I_meas_lf; I_meas_rr;
    % [14-15] 扰动力估计
    F_dist_calc_lf; F_dist_calc_rr;
    % [16] 地面角度
    theta_ground;
    % [17-18] 轮速
    omega_wheel_lf; omega_wheel_rr;
    % [19-26] AI算法专用输出
    load_ratio_front; load_ratio_rear; load_transfer_lateral;  % 载荷信息
    tire_utilization_lf; tire_utilization_rr;                 % 轮胎利用率
    lateral_accel; slip_angle_front; slip_angle_rear; drive_force_asymmetry; % 运动状态
    % [28-31] 扩展诊断信息
    slip_flag; stall_flag;                                     % 二元状态标志
    N_lf; N_rr                                                 % 法向载荷 (Fz)
];

end

%% =========================== 工具函数 ====================================
function y = sat(x, xmin, xmax)
y = min(max(x, xmin), xmax);
end

function y = sat_sym(x, xmax)
y = min(max(x, -xmax), xmax);
end

function y = sat_smooth(x, xmin, xmax, k)
% 光滑限幅函数：sat(x,a,b) ≈ a + (b-a)*(tanh(k*(x-a)/(b-a))+1)/2
% k: 光滑增益，越大越接近硬限幅
if nargin < 4
    k = 30.0; % 默认增益
end
if xmax <= xmin
    y = (xmin + xmax) / 2;
    return;
end
x_norm = (x - xmin) / (xmax - xmin); % 归一化到[0,1]
y_norm = (tanh(k * (x_norm - 0.5)) + 1) / 2; % 光滑S曲线
y = xmin + (xmax - xmin) * y_norm;
end

function [N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer(F_cmd, omega, v, theta_g, params)
% 基于纵向/横向加速度的简化载荷转移 + 坡度影响
m = params.mass;
g = params.gravity;
h_cg = params.h_cg;
W = params.W;
L = params.L;
c_r = params.rolling_resistance;
accel_limit = params.max_acceleration;

% 纵向加速度（使用指令近似，以避免环依赖；也可改为用上一拍估计）
a_long = sat(F_cmd/m, -accel_limit, accel_limit) - g*sin(theta_g);
Delta_long = m * a_long * (h_cg/L); % 前后轴载荷转移

% 横向加速度（用 omega,v 估）
% RF/LR 为万向支撑轮，只参与垂向支撑；侧向/偏航动力主要由 LF/RR 舵驱轮承担。
% 载荷转移幅值取 |v*omega|，方向由 sign(omega) 单独决定，避免右转时被夹到近零。
if abs(v) > 1e-3 && abs(omega) > 1e-6
    a_lat = abs(v * omega);
    Delta_lat = m * a_lat * (h_cg/max(W,1e-6));
else
    Delta_lat = 0;
end
sgn_turn = sign(omega);

% 轴基础载荷（坡度影响投影到总重）
W_total = m * g * cos(theta_g);
N_front_base = W_total/2 - Delta_long/2;
N_rear_base = W_total/2 + Delta_long/2;

% 横向分配到轴
Delta_lat_front = sgn_turn * Delta_lat/2;
Delta_lat_rear = sgn_turn * Delta_lat/2;

% 四轮法向载荷
N_lf = max(0, N_front_base/2 - Delta_lat_front/2);
N_rf = max(0, N_front_base/2 + Delta_lat_front/2);
N_lr = max(0, N_rear_base/2 - Delta_lat_rear/2);
N_rr = max(0, N_rear_base/2 + Delta_lat_rear/2);

% 滚动阻力（基于实时载荷）
F_rolling_total = c_r * (N_lf + N_rf + N_lr + N_rr);
end
