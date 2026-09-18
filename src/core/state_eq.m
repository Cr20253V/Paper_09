function x_next = state_eq(x, u, theta_ground, params)
% =========================================================================
% 文件名：state_eq.m
% 功能描述：对角式双舵轮AGV状态转移方程 - 实现车辆动力学模型的时间步进
% 输入参数：
%   x: 当前时刻状态向量 [X Y psi v omega delta_lf delta_rr beta] (8×1)
%       其中：X-全局X坐标[m], Y-全局Y坐标[m], psi-航向角[rad]
%             v-纵向速度[m/s], omega-横摆角速度[rad/s]
%             delta_lf-左前轮转向角[rad], delta_rr-右后轮转向角[rad]
%             beta-质心侧偏角[rad]
%   u: 控制输入向量 [F_cmd omega_cmd] (2×1)
%       F_cmd-总驱动力指令[N], omega_cmd-期望横摆角速度[rad/s]
%   theta_ground: 地面坡度角[rad] (标量)
%   params: 包含所有车辆参数的结体体
% 输出参数：
%   x_next: 下一时刻状态向量 (8×1)
% =========================================================================

%% 提取状态变量 - 从状态向量中分解各个状态分量
X = x(1); Y = x(2); psi = x(3); v = x(4);
omega = x(5); delta_lf = x(6); delta_rr = x(7); beta = x(8);

%% 提取控制输入 - 从输入向量分解控制指令
F_cmd = u(1);      % 总驱动力指令[N]
omega_cmd = u(2);  % 期望横摆角速度指令[rad/s]

%% 直接从参数结构体获取车辆参数 - 提高代码可读性和维护性
Ts = params.Ts;                          % 采样时间[s]
m = params.mass;                         % 车辆总质量[kg]
I_z = params.Iz;                         % 绕Z轴的转动惯量[kg·m²]
L = params.L;                            % 轴距[m]
W = params.W;                            % 轮距[m]
h_cg = params.h_cg;                      % 质心高度[m]
r = params.wheel_radius;                 % 车轮半径[m]
n = params.gear_ratio;                   % 传动比
eta = params.gear_efficiency;            % 传动效率
k_t = params.motor_torque_constant;      % 电机转矩常数[N·m/A]
mu = params.friction_coefficient;        % 路面摩擦系数
c_r = params.rolling_resistance;         % 滚动阻力系数
rho = params.air_density;                % 空气密度[kg/m³]
CdA = params.drag_coefficient_area;      % 风阻系数×迎风面积[m²]
C_af = params.front_cornering_stiffness; % 前轮侧偏刚度[N/rad]
C_ar = params.rear_cornering_stiffness;  % 后轮侧偏刚度[N/rad]
C_yaw_damping = getfield_default(params, 'yaw_damping', 250.0);
beta_damping = getfield_default(params, 'sideslip_damping', 0.0);
beta_low_speed_damping = getfield_default(params, 'sideslip_low_speed_damping', 1.0);
delta_max = params.max_steering_angle;   % 最大转向角限制[rad]
delta_dot_max = params.max_steering_rate;% 最大转向速率[rad/s]
tau_delta = params.steering_time_constant;% 转向系统时间常数[s]
current_limit = params.current_limit;    % 电机电流限制[A]
accel_limit = params.max_acceleration;   % 最大加速度限制[m/s²]
g = params.gravity;                      % 重力加速度[m/s²]
min_omega_threshold = params.min_angular_velocity_threshold; % 最小角速度阈值[rad/s]
low_speed_thresh = params.low_speed_threshold; % 低速阈值[m/s]

%% === 转向几何计算：按 ICR 约束 (tanδ 关系) 生成目标角 ===
if abs(omega_cmd) < min_omega_threshold || v < low_speed_thresh
    % 低速/小指令：维持直行
    delta_lf_target = 0; delta_rr_target = 0;
else
    % 角速度误差抑制（比例缩放，保持两轮几何比不变）
    e_omega = omega_cmd - omega;  % 角速度跟踪误差[rad/s]
    if abs(omega) > abs(omega_cmd) * 1.2 && sign(omega) == sign(omega_cmd)
        delta_scale = max(omega_cmd / max(abs(omega), 1e-6), 0.1);
    else
        delta_scale = 1.0;
    end

    % ICR 坐标（车辆质心坐标系）：改用测量ω（或与命令加权的ω）计算
    % 目的：避免在 v 下降或跟踪误差较大时，把目标舵角放大
    w_icr = omega;  % 如需更强前馈，可用 w_icr = 0.7*omega + 0.3*omega_cmd;
    R_cmd = (v / max(abs(w_icr),1e-6)) * sign(w_icr); % 带符号半径[m]
    x_c = 0.0;                      % 对称转弯，ICR 在 y 轴上
    y_c = R_cmd;                    % ICR y 坐标（可正可负）

    % 几何约束：
    % tan(delta_lf) = (L/2 - x_c) / (y_c - W/2)
    % tan(delta_rr) = -(x_c + L/2) / (y_c + W/2)
    delta_lf_geom = atan2((L/2 - x_c), (y_c - W/2));
    delta_rr_geom = -atan2((x_c + L/2), (y_c + W/2));

    % 误差缩放（不破坏两轮几何比例）
    delta_lf_target = delta_lf_geom * delta_scale;
    delta_rr_target = delta_rr_geom * delta_scale;

    % 取消额外的“安全夹紧”：由执行器限幅 delta_max 与速率限幅保障
    % 这样可避免稳态曲率下目标转角长期贴住 15° 而过大
end

%% === 舵机动力学模拟：一阶惯性 + 速率限制 + 角度限制 ===
% 转向系统动力学：一阶惯性环节模拟转向执行器响应
delta_lf_dot = (delta_lf_target - delta_lf)/max(tau_delta,Ts);
delta_rr_dot = (delta_rr_target - delta_rr)/max(tau_delta,Ts);

% 转向速率限制 - 模拟转向执行器的物理限制
delta_lf_dot = sat(delta_lf_dot, -delta_dot_max, delta_dot_max);
delta_rr_dot = sat(delta_rr_dot, -delta_dot_max, delta_dot_max);

% 转向角更新 + 角度限制
delta_lf_new = sat(delta_lf + Ts*delta_lf_dot, -delta_max, delta_max);
delta_rr_new = sat(delta_rr + Ts*delta_rr_dot, -delta_max, delta_max);

%% === 载荷转移计算 & 滚动阻力计算 ===
[N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer(F_cmd, omega, v, theta_ground, params);

%% === 电机/传动系统限制推算到车轮牵引力上限 ===
% 计算单个驱动轮的最大牵引力（基于电机电流限制）
F_wheel_max = current_limit * k_t * (eta * n) / max(r,1e-6);  % 单驱动轮最大牵引力[N]

% 计算总驱动轮的最大牵引力（对角式：左前+右后两个驱动轮）
num_drive_wheels = 2; % 驱动轮数量：lf & rr
F_cmd_max_total = num_drive_wheels * F_wheel_max;

% 应用牵引力限制到指令值
F_cmd_eff = sat_sym(F_cmd, F_cmd_max_total);

%% === 轮胎侧偏角计算（基于简化自行车模型） ===
% 车辆几何参数：假设质心位于轴距中心
Lf = L/2; Lr = L/2; % 前后轴到质心的距离[m]

% 侧偏刚度：使用标称值（取消转弯增强的临时放大）
% C_af, C_ar 已由 parameters.m 提供

% 纵向速度分量（防止除零）
v_x = max(v * cos(beta), 1e-3);

% 前轮侧偏角（标准符号）：alpha_f = (beta + Lf*omega/v) - delta_lf
alpha_f = (beta + Lf*omega/max(v,low_speed_thresh)) - delta_lf_new;

% 后轮侧偏角（标准符号）：alpha_r = (beta - Lr*omega/v) - delta_rr
alpha_r = (beta - Lr*omega/max(v,low_speed_thresh)) - delta_rr_new;   % 对角式双舵轮，后轮也有转向

% 线性侧偏力计算 + 软饱和（限幅到摩擦圆边界）
Fy_f_lin = -C_af * alpha_f;  % 前轮线性侧偏力[N]
Fy_r_lin = -C_ar * alpha_r;  % 后轮线性侧偏力[N]

% 基于垂向载荷计算最大侧向力（摩擦圆限制）
Fy_f_max = mu * N_lf;  % 前轮最大侧向力[N]
Fy_r_max = mu * N_rr;  % 后轮最大侧向力[N]

% 应用侧向力饱和限制
Fy_f = sat(Fy_f_lin, -Fy_f_max, Fy_f_max);
Fy_r = sat(Fy_r_lin, -Fy_r_max, Fy_r_max);

%% === 牵引力分配策略：按法向载荷比例 + 偏航控制 ===
% 驱动轮总垂向载荷（仅考虑两个驱动轮：左前+右后）
W_drive = N_lf + N_rr;  % 驱动轮总载荷[N]

% 计算各驱动轮在总驱动载荷中的权重比例
w_lf = N_lf / max(W_drive,1e-6);  % 左前轮载荷占比
w_rr = N_rr / max(W_drive,1e-6);  % 右后轮载荷占比

% 直线/低曲率时等分扭矩，抑制对角驱动导致的偏航力矩
if (abs(omega_cmd) < min_omega_threshold) && (abs(omega) < min_omega_threshold)
    w_lf = 0.5;
    w_rr = 0.5;
end

% 偏航控制：根据角速度误差产生驱动力差以实现横摆控制
e_omega = omega_cmd - omega;  % 角速度跟踪误差[rad/s]

% 横摆角速度保护：防止角速度爆炸式增长
omega_max = 2.0;  % 最大角速度限制 [rad/s]（远大于目标0.1 rad/s）

if v < low_speed_thresh || abs(omega_cmd) < min_omega_threshold
    % 低速/小指令：关断偏航力差，避免原地自旋
    Delta_Fx = 0;
else
    if abs(omega) > omega_max
        % 情况：角速度超限 - 施加强制制动力矩进行保护
        omega_sign = sign(omega);
        Mz_brake = -omega_sign * I_z * 50.0;  % 强制制动力矩[Nm]
        Delta_Fx = 2 * Mz_brake / max(W, 1e-3); % 所需的驱动力差[N]
    else
        % 恢复：正常P控制产生偏航力差
        K_omega_p = 50.0;
        omega_dot_desired = K_omega_p * e_omega; % 期望角加速度[rad/s²]
        omega_dot_max = 10.0;                    % 最大角加速度 [rad/s²]
        omega_dot_desired = sat_sym(omega_dot_desired, omega_dot_max);
        Mz_needed = I_z * omega_dot_desired;     % 所需偏航力矩 [Nm]
        Delta_Fx = 2 * Mz_needed / max(W, 1e-3); % 所需驱动力差 [N]
        Delta_Fx_max = max(abs(F_cmd_eff), 10) * 0.5; % 驱动力差限幅
        Delta_Fx = sat_sym(Delta_Fx, Delta_Fx_max);
    end
end

% 驱动力分配：基础分配（按载荷比例）+ 偏航控制（力差调整）
Fx_lf_cmd = F_cmd_eff * w_lf + Delta_Fx/2;  % 左前轮指令驱动力[N]
Fx_rr_cmd = F_cmd_eff * w_rr - Delta_Fx/2;  % 右后轮指令驱动力[N]

%% === 摩擦椭圆限幅：确保合力不超过轮胎-路面摩擦极限 ===
% 获取是否使用光滑限幅的标志
use_smooth = params.use_smooth_saturation;

if use_smooth
    % 光滑版本限幅：使用softplus函数替代max(·,0)，提高数值稳定性
    smooth_gain = params.smooth_gain;
    
    % 计算各轮胎在摩擦椭圆中的可用纵向力余量
    term_lf = softplus(1 - (Fy_f/max(mu*N_lf,1e-6))^2, smooth_gain);
    term_rr = softplus(1 - (Fy_r/max(mu*N_rr,1e-6))^2, smooth_gain);
    
    Fx_lf_allow = mu * N_lf * sqrt(term_lf);  % 左前轮允许的最大纵向力[N]
    Fx_rr_allow = mu * N_rr * sqrt(term_rr);  % 右后轮允许的最大纵向力[N]
    
    % 应用光滑限幅到指令驱动力
    F_drive_lf = sat_smooth(Fx_lf_cmd, -Fx_lf_allow, Fx_lf_allow, smooth_gain);
    F_drive_rr = sat_smooth(Fx_rr_cmd, -Fx_rr_allow, Fx_rr_allow, smooth_gain);
else
    % 硬限幅版本：传统的摩擦椭圆限制
    Fx_lf_allow = mu * N_lf * sqrt(max(1 - (Fy_f/max(mu*N_lf,1e-6))^2, 0));
    Fx_rr_allow = mu * N_rr * sqrt(max(1 - (Fy_r/max(mu*N_rr,1e-6))^2, 0));
    
    F_drive_lf = sign(Fx_lf_cmd) * min(abs(Fx_lf_cmd), Fx_lf_allow);
    F_drive_rr = sign(Fx_rr_cmd) * min(abs(Fx_rr_cmd), Fx_rr_allow);
end

% 计算总有效驱动力
F_drive_total = F_drive_lf + F_drive_rr;

% 计算驱动不对称产生的偏航力矩（左右驱动力差异引起）
Mz_drive = (W/2) * (F_drive_lf - F_drive_rr);

% 坡度阻力计算
F_slope = m * g * sin(theta_ground);

% 有效质量计算（包含旋转部件的等效质量）
wheel_inertia = params.wheel_inertia;    % 车轮转动惯量[kg·m²]
motor_inertia = params.motor_inertia;    % 电机转动惯量[kg·m²]
m_eff_total = m + 2*(wheel_inertia + motor_inertia*n^2)/(r^2); % 总有效质量[kg]

%% === RK4数值积分（转向角线性插值 + 动态空气阻力计算） ===
% 提取核心状态变量用于RK4积分
s_k = [X; Y; psi; v; omega; beta];

% 转向角中点值（用于RK4中间步骤的线性插值）
delta_lf_mid = (delta_lf + delta_lf_new)/2;
delta_rr_mid = (delta_rr + delta_rr_new)/2;

% 获取光滑限幅参数
use_smooth = params.use_smooth_saturation;
smooth_gain = params.smooth_gain;

% 定义连续动力学核心函数（闭包形式，传入当前计算的所有参数）
CONT_CORE = @(s, dl, dr) continuous_dynamics_core_v2(s, dl, dr, ...
    F_drive_lf, F_drive_rr, F_rolling_total, F_slope, m_eff_total, I_z, Lf, Lr, ...
    low_speed_thresh, C_af, C_ar, mu, N_lf, N_rr, W, use_smooth, smooth_gain, ...
    C_yaw_damping, beta_damping, beta_low_speed_damping, rho, CdA);  % 传入空气阻力参数用于动态计算

% RK4积分四步计算（使用转向角插值）
k1 = CONT_CORE(s_k, delta_lf, delta_rr);                    % 第一步：使用k时刻转向角
k2 = CONT_CORE(s_k + 0.5*Ts*k1, delta_lf_mid, delta_rr_mid); % 第二步：使用中点转向角
k3 = CONT_CORE(s_k + 0.5*Ts*k2, delta_lf_mid, delta_rr_mid); % 第三步：使用中点转向角
k4 = CONT_CORE(s_k + Ts*k3, delta_lf_new, delta_rr_new);    % 第四步：使用k+1时刻转向角

% RK4最终积分：加权平均
s_new = s_k + (Ts/6)*(k1 + 2*k2 + 2*k3 + k4);

%% 提取新状态并应用保护措施
X_new = s_new(1); Y_new = s_new(2); psi_new = s_new(3);
v_new = s_new(4); omega_new = s_new(5); beta_new = s_new(6);

% 航向角归一化到[-pi, pi]范围
psi_new = normalizeAngle(psi_new);

% 低速保护：防止速度变为负值（车辆不能倒车）
if v_new < 0
    v_new = 0;
end

% 侧偏角限幅保护（防止数值爆炸）
beta_new = sat(beta_new, -deg2rad(15), deg2rad(15));

%% 组装下一时刻完整状态向量
x_next = [X_new; Y_new; psi_new; v_new; omega_new; delta_lf_new; delta_rr_new; beta_new];

end

%% =========================== 连续动力学核心函数 V2（动态空气阻力计算） ===========================
function ds = continuous_dynamics_core_v2(s, delta_lf, delta_rr, Fx_lf, Fx_rr, F_rolling_total, F_slope, ...
    m_eff_total, I_z, Lf, Lr, low_speed_thresh, C_af, C_ar, mu, N_lf, N_rr, W, use_smooth, smooth_gain, ...
    C_yaw_damping, beta_damping, beta_low_speed_damping, rho, CdA)
% 连续动力学核心函数V2 - 用于RK4积分的每个子步，动态计算空气阻力
% 输入参数：
%   s: 状态向量 [X Y psi v omega beta]
%   delta_lf, delta_rr: 当前转向角[rad]
%   Fx_lf, Fx_rr: 预计算的驱动力（已应用摩擦椭圆限幅）[N]
%   F_rolling_total: 总滚动阻力[N]
%   F_slope: 坡度阻力[N]
%   m_eff_total: 总有效质量[kg]
%   I_z: 转动惯量[kg·m²]
%   Lf, Lr: 前后轴到质心距离[m]
%   low_speed_thresh: 低速阈值[m/s]
%   C_af, C_ar: 前后轮侧偏刚度[N/rad]
%   mu: 摩擦系数
%   N_lf, N_rr: 左右驱动轮垂向载荷[N]
%   W: 轮距[m]
%   use_smooth: 是否使用光滑限幅
%   smooth_gain: 光滑限幅增益
%   rho: 空气密度[kg/m³]
%   CdA: 风阻系数×面积[m²]
% 输出参数：
%   ds: 状态导数向量 [X_dot Y_dot psi_dot v_dot omega_dot beta_dot]

% 设置默认参数值
if nargin < 20
    use_smooth = false;
    smooth_gain = 30.0;
end
if nargin < 21 || isempty(C_yaw_damping), C_yaw_damping = 250.0; end
if nargin < 22 || isempty(beta_damping), beta_damping = 0.0; end
if nargin < 23 || isempty(beta_low_speed_damping), beta_low_speed_damping = 1.0; end

% 分解状态向量
X = s(1); Y = s(2); psi = s(3); v = s(4); omega = s(5); beta = s(6);

% 动态计算空气阻力（基于当前瞬时速度）
F_aero = 0.5 * rho * CdA * v^2 * sign(v);  % 空气阻力[N]，与速度平方成正比
F_drag = F_rolling_total + F_aero;          % 总阻力 = 滚动阻力 + 空气阻力

% 重新计算轮胎侧偏角（基于当前状态和转向角）
alpha_f = (beta + Lf*omega/max(abs(v),low_speed_thresh)) - delta_lf;
alpha_r = (beta - Lr*omega/max(abs(v),low_speed_thresh)) - delta_rr;

% 线性侧偏力计算
Fy_f_lin = -C_af * alpha_f;  % 前轮侧偏力[N]
Fy_r_lin = -C_ar * alpha_r;  % 后轮侧偏力[N]

% 侧向力饱和限制（基于摩擦圆原理）
Fy_f_max = mu * N_lf;  % 前轮最大侧向力[N]
Fy_r_max = mu * N_rr;  % 后轮最大侧向力[N]

% 应用侧向力限幅（可选择光滑或硬限幅）
if use_smooth
    Fy_f = sat_smooth(Fy_f_lin, -Fy_f_max, Fy_f_max, smooth_gain);
    Fy_r = sat_smooth(Fy_r_lin, -Fy_r_max, Fy_r_max, smooth_gain);
else
    Fy_f = sat(Fy_f_lin, -Fy_f_max, Fy_f_max);
    Fy_r = sat(Fy_r_lin, -Fy_r_max, Fy_r_max);
end

% 使用预计算的驱动力（避免重复限幅）
F_drive_actual = Fx_lf + Fx_rr;  % 实际总驱动力[N]

% 驱动不对称产生的偏航力矩
Mz_drive = (W/2) * (Fx_lf - Fx_rr);  % [Nm]

% 纵向动力学方程
a_x = (F_drive_actual - F_drag - F_slope) / max(m_eff_total,1e-6); % 纵向加速度[m/s²]

% 低速保护：防止倒车情况下的负加速度
if a_x < 0 && v < 0
    v_dot = 0;  % 速度为负时不允许进一步减速
else
    v_dot = a_x; % 正常加速度
end

% 横摆动力学计算
Mz_tire = Fy_f*Lf - Fy_r*Lr;      % 轮胎侧偏力产生的偏航力矩[Nm]
Mz_total = Mz_tire + Mz_drive;     % 总偏航力矩 = 轮胎力矩 + 驱动力矩

% 横摆阻尼：由 parameters.m 统一配置
C_damping = C_yaw_damping;        % 横摆阻尼系数 [Nm/(rad/s)]
Mz_damping = -C_damping * omega;  % 阻尼力矩（与角速度成正比）[Nm]
Mz_total = Mz_total + Mz_damping; % 包含阻尼的总偏航力矩[Nm]

% 角加速度计算
omega_dot = Mz_total / max(I_z,1e-6);  % [rad/s²]

% 角加速度限幅保护
omega_dot_limit = 5.0;  % 最大角加速度限制 [rad/s²]
omega_dot = sat_sym(omega_dot, omega_dot_limit);

% 侧滑角动力学：正常速度移除强人工阻尼，仅保留可配置数值阻尼
if abs(v) < low_speed_thresh
    % 低速情况：使用温和数值阻尼使侧滑角回零
    beta_dot = -beta_low_speed_damping * beta; 
else
    % 正常速度：基于力学原理的侧滑角动力学 + 可配置数值阻尼
    beta_dot = (Fy_f + Fy_r) / (m_eff_total * max(abs(v),low_speed_thresh/10)) - omega - beta_damping * beta;
end

% 侧滑角变化率限幅
beta_dot_limit = deg2rad(10);  % 限制侧滑角变化率[rad/s]
beta_dot = sat_sym(beta_dot, beta_dot_limit);

% 运动学方程
psi_dot = omega;                           % 航向角变化率[rad/s]
X_dot = v * cos(psi + beta);               % X方向速度[m/s]
Y_dot = v * sin(psi + beta);               % Y方向速度[m/s]

% 组装状态导数向量
ds = [X_dot; Y_dot; psi_dot; v_dot; omega_dot; beta_dot];

% 局部饱和函数定义
    function y = sat(x, xmin, xmax)
        y = min(max(x, xmin), xmax);
    end
end

%% =========================== 连续动力学核心函数（原版，保留兼容性） ===========================
function ds = continuous_dynamics_core(s, delta_lf, delta_rr, Fx_lf, Fx_rr, F_drag, F_slope, ...
    m_eff_total, I_z, Lf, Lr, low_speed_thresh, C_af, C_ar, mu, N_lf, N_rr, W, use_smooth, smooth_gain, ...
    C_yaw_damping, beta_damping, beta_low_speed_damping)
% 连续动力学核心函数（原版）- 用于RK4积分，使用固定的阻力值
% 输入参数说明同V2版本，但F_drag为固定值而非动态计算

% 设置默认参数
if nargin < 20
    use_smooth = false;
    smooth_gain = 30.0;
end
if nargin < 21 || isempty(C_yaw_damping), C_yaw_damping = 250.0; end
if nargin < 22 || isempty(beta_damping), beta_damping = 0.0; end
if nargin < 23 || isempty(beta_low_speed_damping), beta_low_speed_damping = 1.0; end

% 状态分解
X = s(1); Y = s(2); psi = s(3); v = s(4); omega = s(5); beta = s(6);

% 侧偏角计算
alpha_f = delta_lf - (beta + Lf*omega/max(abs(v),1e-3));
alpha_r = delta_rr - (beta - Lr*omega/max(abs(v),1e-3));

% 侧向力计算与限幅
Fy_f_lin = -C_af * alpha_f;
Fy_r_lin = -C_ar * alpha_r;

Fy_f_max = mu * N_lf;
Fy_r_max = mu * N_rr;

if use_smooth
    Fy_f = sat_smooth(Fy_f_lin, -Fy_f_max, Fy_f_max, smooth_gain);
    Fy_r = sat_smooth(Fy_r_lin, -Fy_r_max, Fy_r_max, smooth_gain);
else
    Fy_f = sat(Fy_f_lin, -Fy_f_max, Fy_f_max);
    Fy_r = sat(Fy_r_lin, -Fy_r_max, Fy_r_max);
end

% 驱动力和偏航力矩
F_drive_actual = Fx_lf + Fx_rr;
Mz_drive = (W/2) * (Fx_lf - Fx_rr);

% 纵向动力学
a_x = (F_drive_actual - F_drag - F_slope) / max(m_eff_total,1e-6);

% 低速保护
if a_x < 0 && v < 0
    v_dot = 0;
else
    v_dot = a_x;
end

% 横摆动力学
Mz_tire = Fy_f*Lf - Fy_r*Lr;
Mz_total = Mz_tire + Mz_drive;

% 横摆阻尼
C_damping = C_yaw_damping;
Mz_damping = -C_damping * omega;
Mz_total = Mz_total + Mz_damping;

omega_dot = Mz_total / max(I_z,1e-6);

% 角加速度限幅
omega_dot_limit = 5.0;
omega_dot = sat_sym(omega_dot, omega_dot_limit);

% 侧滑角动力学
if abs(v) < low_speed_thresh
    beta_dot = -beta_low_speed_damping * beta;
else
    beta_dot = (Fy_f + Fy_r) / (m_eff_total * max(abs(v),low_speed_thresh/10)) - omega - beta_damping * beta;
end

% 侧滑角变化率限幅
beta_dot_limit = deg2rad(10);
beta_dot = sat_sym(beta_dot, beta_dot_limit);

% 运动学
psi_dot = omega;
X_dot = v * cos(psi + beta);
Y_dot = v * sin(psi + beta);

% 输出状态导数
ds = [X_dot; Y_dot; psi_dot; v_dot; omega_dot; beta_dot];

% 局部饱和函数
    function y = sat(x, xmin, xmax)
        y = min(max(x, xmin), xmax);
    end
end

%% =========================== 工具函数集 ============================
function y = sat(x, xmin, xmax)
% 标准饱和函数 - 将输入x限制在[xmin, xmax]范围内
% 输入：x-输入值, xmin-最小值, xmax-最大值
% 输出：y-饱和后的值
y = min(max(x, xmin), xmax);
end

function y = sat_sym(x, xmax)
% 对称饱和函数 - 将输入x限制在[-xmax, xmax]范围内
% 输入：x-输入值, xmax-对称的最大绝对值
% 输出：y-饱和后的值
y = min(max(x, -xmax), xmax);
end

function y = sat_smooth(x, xmin, xmax, k)
% 光滑饱和函数 - 使用双曲正切实现光滑限幅
% 输入：x-输入值, xmin-最小值, xmax-最大值, k-光滑增益（越大越接近硬限幅）
% 输出：y-光滑饱和后的值
if nargin < 4
    k = 30.0; % 默认光滑增益
end
if xmax <= xmin
    y = (xmin + xmax) / 2; % 异常情况处理
    return;
end
% 归一化处理 + 双曲正切光滑限幅
x_norm = (x - xmin) / (xmax - xmin);         % 归一化到[0,1]
y_norm = (tanh(k * (x_norm - 0.5)) + 1) / 2; % 光滑S曲线变换
y = xmin + (xmax - xmin) * y_norm;           % 反归一化
end

function y = softplus(x, k)
% 光滑的max(x,0)近似函数 - 提高数值稳定性
% 输入：x-输入值, k-光滑增益（越大越接近max函数）
% 输出：y-光滑处理后的值
if nargin < 2
    k = 30.0; % 默认光滑增益
end
y = (1/k) * log(1 + exp(k * x)); % softplus函数公式
end

function a = normalizeAngle(a)
% 角度归一化函数 - 将角度包装到[-pi, pi]范围内
% 输入：a-输入角度[rad]
% 输出：a-归一化后的角度[rad]
a = atan2(sin(a), cos(a)); % 使用atan2实现稳健的角度归一化
end

function [N_lf, N_rf, N_lr, N_rr, F_rolling_total] = compute_load_transfer(F_cmd, omega, v, theta_g, params)
% 载荷转移计算函数 - 基于纵向/横向加速度的简化载荷转移模型 + 坡度影响
% 输入参数：
%   F_cmd: 驱动力指令[N], omega: 横摆角速度[rad/s], v: 速度[m/s]
%   theta_g: 坡度角[rad], params: 参数结构体
% 输出参数：
%   N_lf, N_rf, N_lr, N_rr: 四轮垂向载荷[N]
%   F_rolling_total: 总滚动阻力[N]

% 提取参数
m = params.mass;         % 质量[kg]
g = params.gravity;      % 重力加速度[m/s²]
h_cg = params.h_cg;      % 质心高度[m]
W = params.W;            % 轮距[m]
L = params.L;            % 轴距[m]
c_r = params.rolling_resistance;     % 滚动阻力系数
accel_limit = params.max_acceleration; % 最大加速度限制[m/s²]

% 纵向加速度估算（避免代数环）
F_rolling_est = c_r * m * g * cos(theta_g);          % 估算滚动阻力[N]
F_aero_est = 0.5 * 1.225 * 0.5 * v^2 * sign(v);     % 估算空气阻力[N]（简化）
F_slope_est = m * g * sin(theta_g);                  % 坡度阻力[N]
F_net_est = F_cmd - F_rolling_est - F_aero_est - F_slope_est; % 净驱动力[N]
a_long = sat(F_net_est/m, -accel_limit, accel_limit); % 纵向加速度[m/s²]（限幅）

% 纵向载荷转移计算
Delta_long = m * a_long * (h_cg/L); % 前后轴载荷转移量[N]

% 横向加速度估算（基于当前运动状态）
% RF/LR 为万向支撑轮，只参与垂向支撑；侧向/偏航动力主要由 LF/RR 舵驱轮承担。
% 载荷转移需要左右转对称：幅值取 |v*omega|，方向单独由 sign(omega) 决定。
if abs(v) > 1e-3 && abs(omega) > 1e-6
    a_lat = abs(v * omega);               % 横向向心加速度幅值[m/s²]
    Delta_lat = m * a_lat * (h_cg/max(W,1e-6)); % 横向载荷转移量[N]
else
    Delta_lat = 0; % 静止或极低速时无横向载荷转移
end

% 转向方向符号
sgn_turn = sign(omega);

% 基础轴载荷计算（考虑坡度影响）
W_total = m * g * cos(theta_g);     % 总垂向载荷（坡度修正）[N]
N_front_base = W_total/2 - Delta_long/2; % 前轴基础载荷[N]
N_rear_base = W_total/2 + Delta_long/2;  % 后轴基础载荷[N]

% 横向载荷分配到各轴
Delta_lat_front = sgn_turn * Delta_lat/2; % 前轴横向转移量[N]
Delta_lat_rear = sgn_turn * Delta_lat/2;  % 后轴横向转移量[N]

% 四轮垂向载荷计算（确保非负）
N_lf = max(0, N_front_base/2 - Delta_lat_front/2); % 左前轮载荷[N]
N_rf = max(0, N_front_base/2 + Delta_lat_front/2); % 右前轮载荷[N]
N_lr = max(0, N_rear_base/2 - Delta_lat_rear/2);   % 左后轮载荷[N]
N_rr = max(0, N_rear_base/2 + Delta_lat_rear/2);   % 右后轮载荷[N]

% 基于实时载荷计算总滚动阻力
F_rolling_total = c_r * (N_lf + N_rf + N_lr + N_rr); % 总滚动阻力[N]
end

function v = getfield_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
