function upd = mpc_update_from_rho(rho, db, maps)
% =============================
% 文件名：mpc_update_from_rho.m
% 路径：S-Function_14/mpc_update_from_rho.m
% 版本号：V1.3
% 最后修改时间：2025-11-19
% 作者：Auto-generated
% 功能描述：
%   根据当前调度变量 ρ=[v, ω, θ]（ω保留符号）进行三线性插值
%   输出更新后的预测模型矩阵 (A,B,C,D,E) 和可选的权重/约束
%   包含场景自适应权重调度：
%     - 方案B：转弯场景（基于|ω|）增强横向跟踪（q_y）
%     - 方案C：坡度场景（基于|θ|）增强纵向速度保持（q_v、R(1)、dR(1)）
% 输入参数：
%   - rho：当前调度变量 [v; omega; theta] (3×1), 单位：m/s, rad/s, rad
%       注意：omega 保留符号（正为左转，负为右转）
%   - db：LPV模型数据库（来自 lin_agv_grid.m）
%   - maps：权重/约束映射表（来自 mpc_setup_single_interp.m 或 maps_best.mat）
%       方案B配置：omega_threshold, q_y_gain_max, transition_width
%       方案C配置：theta_threshold, q_v_gain_max, theta_transition_width,
%                  R_F_gain_max_uphill, R_F_gain_max_downhill,
%                  dR_F_gain_max_uphill, dR_F_gain_max_downhill
% 输出参数：
%   - upd：更新结构体，包含
%       - A：状态矩阵 (4×4)
%       - B：输入矩阵（MV部分，4×2）
%       - C：输出矩阵 (4×4)
%       - D：直通矩阵（MV部分，4×2）
%       - E：扰动矩阵（MD部分，4×1）
%       - Bv：MD影响矩阵（=E，用于Adaptive MPC，4×1）
%       - Dv：MD直通矩阵（通常为零，4×1）
%       - Q, R, dR：插值后的权重（按维度映射）
%       - umin, umax：插值后的约束（可选）
%       - rho_n：归一化调度变量 [0,1]^3
%       - indices：插值顶点索引 (8×3)
%       - weights：插值权重 (8×1)
% 依赖：
%   - 无（纯数值计算）
% 备注：
%   - 三线性插值：在3D网格的8个顶点之间插值
%   - 边界处理：超出网格范围时饱和到边界值
%   - 数值稳定性：权重归一化确保和为1
%   - MD通道：upd.Bv对应E(ρ)矩阵，用于坡度角前馈
%   - Adaptive MPC使用：plant.B←upd.B, plant.Bv←upd.Bv
%   - 权重插值：upd.Q/R/dR仅供参考，需Simulink显式使用（如外部权重端口）
%   - 权重开关：maps.enable_weight_interp可控制是否计算权重插值
% =============================

%% 提取网格信息
V_grid = db.grid.V;
W_grid = db.grid.W;
T_grid = db.grid.T;

Nv = db.Nv;
Nw = db.Nw;
Nt = db.Nt;

nx = db.nx;
nu = db.nu;
ny = db.ny;
nd = db.nd;

%% 归一化调度变量到 [0, 1]^3
v = rho(1);
omega = rho(2);  % 保留符号
theta = rho(3);

% 饱和到网格范围
v = max(min(v, V_grid(end)), V_grid(1));
omega = max(min(omega, W_grid(end)), W_grid(1));
theta = max(min(theta, T_grid(end)), T_grid(1));

% 使用maps中的归一化函数（统一接口）
% 断言：确保maps中rho_min/rho_max维度正确
if isfield(maps, 'rho_min')
    assert(all(size(maps.rho_min) == [3, 1]), 'rho_min size must be [3 1]');
end
if isfield(maps, 'rho_max')
    assert(all(size(maps.rho_max) == [3, 1]), 'rho_max size must be [3 1]');
end

% 统一使用内置线性归一化（移除了函数句柄）
if Nv > 1
    v_n = (v - V_grid(1)) / (V_grid(end) - V_grid(1));
else
    v_n = 0;
end
if Nw > 1
    w_n = (omega - W_grid(1)) / (W_grid(end) - W_grid(1));
else
    w_n = 0;
end
if Nt > 1
    t_n = (theta - T_grid(1)) / (T_grid(end) - T_grid(1));
else
    t_n = 0;
end
rho_n = [v_n; w_n; t_n];

%% 定位网格单元（找到包围当前点的8个顶点）
% 支持任意单调网格（均匀/非均匀）
% 使用二分查找定位左端点

if Nv > 1
    % 查找最后一个 <= v 的索引
    i_low = find(V_grid <= v, 1, 'last');
    if isempty(i_low), i_low = 1; end
    i_low = max(1, min(Nv-1, i_low));
else
    i_low = 1;
end

if Nw > 1
    j_low = find(W_grid <= omega, 1, 'last');
    if isempty(j_low), j_low = 1; end
    j_low = max(1, min(Nw-1, j_low));
else
    j_low = 1;
end

if Nt > 1
    k_low = find(T_grid <= theta, 1, 'last');
    if isempty(k_low), k_low = 1; end
    k_low = max(1, min(Nt-1, k_low));
else
    k_low = 1;
end

i_high = min(i_low + 1, Nv);
j_high = min(j_low + 1, Nw);
k_high = min(k_low + 1, Nt);

%% 计算局部归一化坐标 ξ, η, ζ ∈ [0, 1]
if Nv > 1 && any(V_grid(i_high) > V_grid(i_low))
    xi = (v - V_grid(i_low)) / (V_grid(i_high) - V_grid(i_low));
else
    xi = 0;
end

if Nw > 1 && any(W_grid(j_high) > W_grid(j_low))
    eta = (omega - W_grid(j_low)) / (W_grid(j_high) - W_grid(j_low));
else
    eta = 0;
end

if Nt > 1 && any(T_grid(k_high) > T_grid(k_low))
    zeta = (theta - T_grid(k_low)) / (T_grid(k_high) - T_grid(k_low));
else
    zeta = 0;
end

% 饱和到 [0, 1]
xi = max(0, min(1, xi));
eta = max(0, min(1, eta));
zeta = max(0, min(1, zeta));

%% 三线性插值权重（8个顶点）
% 顶点编号：(i, j, k) -> 权重 w
% (i_low,  j_low,  k_low)  -> (1-xi)(1-eta)(1-zeta)
% (i_high, j_low,  k_low)  -> xi(1-eta)(1-zeta)
% (i_low,  j_high, k_low)  -> (1-xi)eta(1-zeta)
% (i_high, j_high, k_low)  -> xi*eta*(1-zeta)
% (i_low,  j_low,  k_high) -> (1-xi)(1-eta)zeta
% (i_high, j_low,  k_high) -> xi(1-eta)zeta
% (i_low,  j_high, k_high) -> (1-xi)eta*zeta
% (i_high, j_high, k_high) -> xi*eta*zeta

w = zeros(8, 1);
w(1) = (1-xi) * (1-eta) * (1-zeta);
w(2) = xi * (1-eta) * (1-zeta);
w(3) = (1-xi) * eta * (1-zeta);
w(4) = xi * eta * (1-zeta);
w(5) = (1-xi) * (1-eta) * zeta;
w(6) = xi * (1-eta) * zeta;
w(7) = (1-xi) * eta * zeta;
w(8) = xi * eta * zeta;

% 归一化（确保和为1，数值稳定性）
w = w / sum(w);

%% 顶点索引
indices = [
    i_low,  j_low,  k_low;
    i_high, j_low,  k_low;
    i_low,  j_high, k_low;
    i_high, j_high, k_low;
    i_low,  j_low,  k_high;
    i_high, j_low,  k_high;
    i_low,  j_high, k_high;
    i_high, j_high, k_high
];

%% 插值模型矩阵 A, B, C, D, E
% 为代码生成固定返回尺寸（与数据库一致：nx=4, nu=2, ny=4, nd=1）
A_interp = zeros(4, 4);
B_interp = zeros(4, 2);
C_interp = zeros(4, 4);
D_interp = zeros(4, 2);
E_interp = zeros(4, 1);

for p = 1:8
    i = indices(p, 1);
    j = indices(p, 2);
    k = indices(p, 3);
    
    A_interp = A_interp + w(p) * squeeze(db.A(i, j, k, :, :));
    B_interp = B_interp + w(p) * squeeze(db.B(i, j, k, :, :));
    C_interp = C_interp + w(p) * squeeze(db.C(i, j, k, :, :));
    D_interp = D_interp + w(p) * squeeze(db.D(i, j, k, :, :));
    
    if isfield(db, 'E')
        E_interp = E_interp + w(p) * squeeze(db.E(i, j, k, :, :));
    end
end

%% 插值权重/约束（按维度映射）
% 根据 rho_n 各分量分别映射权重和约束
% 注意：权重插值需要Simulink中显式使用（如外部权重端口），否则仅作为参考

% 检查是否启用权重插值
if isfield(maps, 'enable_weight_interp')
    enable_weight_interp = maps.enable_weight_interp;
else
    enable_weight_interp = true;  % 默认启用（但Adaptive MPC不会自动应用）
end

% 形状参数与因子（可选，代码生成安全）
% 注意：在代码生成路径中，禁止对不存在的结构体字段求值
has_shape = false;
if isfield(maps,'alpha_Q') && isfield(maps,'beta_Q') && ...
        isfield(maps,'alpha_R') && isfield(maps,'beta_R') && ...
        isfield(maps,'alpha_dR') && isfield(maps,'beta_dR')
    has_shape = true;
end
has_factor = false;
if isfield(maps, 'enable_factor')
    has_factor = maps.enable_factor;
end

% 将 rho_n 裁剪到 [0,1]
rho_n = max(0, min(1, rho_n));

% 通用的形状映射函数：在 [alpha,beta] 内线性过渡，外侧夹紧（每个分量独立）
shape_map = @(x, a, b) max(0, min(1, (x - a) ./ max(b - a, eps)));

% 计算调度因子（代码生成路径不依赖 maps.factor_* 字段）
if coder.target('MATLAB')
    if has_factor
        fy   = sum(maps.factor_y(:)       .* rho_n(:));
        fpsi = sum(maps.factor_psi(:)     .* rho_n(:));
        fv   = sum(maps.factor_v(:)       .* rho_n(:));
        fomega = sum(maps.factor_omega(:) .* rho_n(:));
        fR_F   = sum(maps.factor_R_F(:)   .* rho_n(:));
        fR_w   = sum(maps.factor_R_omega(:).* rho_n(:));
        fdR_F  = sum(maps.factor_dR_F(:)  .* rho_n(:));
        fdR_w  = sum(maps.factor_dR_omega(:).* rho_n(:));
    else
        % 退化为默认线性组合
        fy   = 0.3*rho_n(1) + 0.2*rho_n(2) + 0.5*rho_n(3);
        fpsi = 0.1*rho_n(1) + 0.7*rho_n(2) + 0.2*rho_n(3);
        fv   = 0.8*rho_n(1) + 0.1*rho_n(2) + 0.1*rho_n(3);
        fomega = 0.2*rho_n(1) + 0.6*rho_n(2) + 0.2*rho_n(3);
        fR_F   = 0.6*rho_n(1) + 0.3*rho_n(2) + 0.1*rho_n(3);
        fR_w   = 0.2*rho_n(1) + 0.7*rho_n(2) + 0.1*rho_n(3);
        fdR_F  = 0.5*rho_n(1) + 0.3*rho_n(2) + 0.2*rho_n(3);
        fdR_w  = 0.2*rho_n(1) + 0.6*rho_n(2) + 0.2*rho_n(3);
    end
else
    % 代码生成路径：使用固定线性组合（不访问 maps.factor_* 字段）
    fy   = 0.3*rho_n(1) + 0.2*rho_n(2) + 0.5*rho_n(3);
    fpsi = 0.1*rho_n(1) + 0.7*rho_n(2) + 0.2*rho_n(3);
    fv   = 0.8*rho_n(1) + 0.1*rho_n(2) + 0.1*rho_n(3);
    fomega = 0.2*rho_n(1) + 0.6*rho_n(2) + 0.2*rho_n(3);
    fR_F   = 0.6*rho_n(1) + 0.3*rho_n(2) + 0.1*rho_n(3);
    fR_w   = 0.2*rho_n(1) + 0.7*rho_n(2) + 0.1*rho_n(3);
    fdR_F  = 0.5*rho_n(1) + 0.3*rho_n(2) + 0.2*rho_n(3);
    fdR_w  = 0.2*rho_n(1) + 0.6*rho_n(2) + 0.2*rho_n(3);
end

% 若开启形状参数，则在 [alpha,beta] 内对上述系数再次做一次过渡（仅 MATLAB 仿真路径）
if coder.target('MATLAB') && has_shape
    % Q 的四个分量按各自形状过渡
    fy     = shape_map(fy,     maps.alpha_Q(1),  maps.beta_Q(1));
    fpsi   = shape_map(fpsi,   maps.alpha_Q(2),  maps.beta_Q(2));
    fv     = shape_map(fv,     maps.alpha_Q(3),  maps.beta_Q(3));
    fomega = shape_map(fomega, maps.alpha_Q(4),  maps.beta_Q(4));
    % R 两个分量
    fR_F   = shape_map(fR_F,   maps.alpha_R(1),  maps.beta_R(1));
    fR_w   = shape_map(fR_w,   maps.alpha_R(2),  maps.beta_R(2));
    % dR 两个分量
    fdR_F  = shape_map(fdR_F,  maps.alpha_dR(1), maps.beta_dR(1));
    fdR_w  = shape_map(fdR_w,  maps.alpha_dR(2), maps.beta_dR(2));
end

if enable_weight_interp && isfield(maps, 'Q_range')
    Q_min = maps.Q_range(1, :);
    Q_max = maps.Q_range(2, :);
    Q_interp = Q_min + [fy; fpsi; fv; fomega]' .* (Q_max - Q_min);
    
    % ====== 方案B：场景自适应权重调度（基于角速度） ======
    % 策略：转弯时（|omega|大）自动提高横向跟踪权重 q_y
    % 
    % 设计参数（可在 maps 中配置，或使用默认值）:
    %   - omega_threshold: 判定"转弯"的角速度阈值 [rad/s]
    %   - q_y_gain_max: 最大增益系数（转弯时 q_y 放大倍数）
    %   - transition_width: 过渡带宽度（平滑切换）
    
    % 提取配置（带默认值）
    if isfield(maps, 'omega_threshold')
        omega_thresh = maps.omega_threshold;
    else
        omega_thresh = 0.15;  % 默认：|omega|>0.15 rad/s 视为转弯
    end
    
    if isfield(maps, 'q_y_gain_max')
        gain_max = maps.q_y_gain_max;
    else
        gain_max = 1.8;  % 默认：转弯时 q_y 放大 1.8 倍
    end
    
    if isfield(maps, 'transition_width')
        trans_width = maps.transition_width;
    else
        trans_width = 0.05;  % 默认：±0.05 rad/s 过渡带
    end
    
    % 计算自适应增益（平滑过渡，避免抖动）
    omega_abs = abs(omega);  % 使用角速度绝对值
    
    if omega_abs <= (omega_thresh - trans_width)
        % 直线区域：使用基准权重
        turn_level = 0.0;
    elseif omega_abs >= (omega_thresh + trans_width)
        % 转弯区域：使用最大增益
        turn_level = 1.0;
    else
        % 过渡区域：平滑插值（三次 Hermite 曲线）
        s = (omega_abs - (omega_thresh - trans_width)) / (2 * trans_width);
        turn_level = 3*s^2 - 2*s^3;  % smooth step
    end
    q_y_gain = 1.0 + (gain_max - 1.0) * turn_level;
    
    % 应用增益到 q_y（仅放大，不缩小）
    Q_interp(1) = Q_interp(1) * q_y_gain;
    
    % 可选：转弯时提高航向/角速度误差权重。默认增益为1.0，保持旧行为。
    if isfield(maps, 'q_psi_gain_max')
        q_psi_gain_max = maps.q_psi_gain_max;
    else
        q_psi_gain_max = 1.0;
    end
    if isfield(maps, 'q_omega_gain_max')
        q_omega_gain_max = maps.q_omega_gain_max;
    else
        q_omega_gain_max = 1.0;
    end
    Q_interp(2) = Q_interp(2) * (1.0 + (q_psi_gain_max - 1.0) * turn_level);
    Q_interp(4) = Q_interp(4) * (1.0 + (q_omega_gain_max - 1.0) * turn_level);
    
    % ====== 方案B 结束 ======
    
    % ====== 方案C：坡度(颠簿)场景自适应权重调度 ======
    % 策略：上坡/下坡时（|theta|大）提高纵向速度跟踪精度和控制平滑性
    %       增强 q_v, R(1), dR(1)，上坡/下坡采用不对称增益
    % 
    % 设计参数（可在 maps 中配置，或使用默认值）:
    %   - theta_threshold: 判定"坡度行驶"的坡度阈值 [rad]，默认2°与GRU对齐
    %   - theta_transition_width: 过渡带宽度 [rad]，默认±1°
    %   - q_v_gain_max: q_v最大增益（上坡/下坡共用）
    %   - R_F_gain_max_uphill/downhill: R(1)增益（上坡/下坡分别配置）
    %   - dR_F_gain_max_uphill/downhill: dR(1)增益（上坡/下坡分别配置）
    
    % 提取坡度阈值和过渡带（整个方案C共用）
    if isfield(maps, 'theta_threshold')
        theta_thresh = maps.theta_threshold;
    else
        theta_thresh = 0.035;  % 默认：|theta|>2° (≈0.035 rad)
    end
    
    if isfield(maps, 'theta_transition_width')
        theta_trans_width = maps.theta_transition_width;
    else
        theta_trans_width = 0.017;  % 默认：±1° (≈0.017 rad)
    end
    
    theta_abs = abs(theta);  % 坡度绝对值
    
    % 提取 q_v 增益配置
    if isfield(maps, 'q_v_gain_max')
        q_v_gain_max = maps.q_v_gain_max;
    else
        q_v_gain_max = 1.5;  % 默认：坡度行驶时 q_v 放大 1.5 倍
    end
    
    % 计算 q_v 增益（平滑过渡）
    if theta_abs <= (theta_thresh - theta_trans_width)
        q_v_gain = 1.0;
    elseif theta_abs >= (theta_thresh + theta_trans_width)
        q_v_gain = q_v_gain_max;
    else
        s = (theta_abs - (theta_thresh - theta_trans_width)) / (2 * theta_trans_width);
        q_v_gain = 1.0 + (q_v_gain_max - 1.0) * (3*s^2 - 2*s^3);
    end
    
    % 应用增益到 q_v（第3个元素）
    Q_interp(3) = Q_interp(3) * q_v_gain;

    % 可选：坡度段同时增强横向/航向跟踪。默认增益为1.0，保持旧行为。
    if theta_abs <= (theta_thresh - theta_trans_width)
        slope_level = 0.0;
    elseif theta_abs >= (theta_thresh + theta_trans_width)
        slope_level = 1.0;
    else
        s = (theta_abs - (theta_thresh - theta_trans_width)) / (2 * theta_trans_width);
        slope_level = 3*s^2 - 2*s^3;
    end
    if isfield(maps, 'q_y_slope_gain_max')
        q_y_slope_gain_max = maps.q_y_slope_gain_max;
    else
        q_y_slope_gain_max = 1.0;
    end
    if isfield(maps, 'q_psi_slope_gain_max')
        q_psi_slope_gain_max = maps.q_psi_slope_gain_max;
    else
        q_psi_slope_gain_max = 1.0;
    end
    if isfield(maps, 'q_omega_slope_gain_max')
        q_omega_slope_gain_max = maps.q_omega_slope_gain_max;
    else
        q_omega_slope_gain_max = 1.0;
    end
    Q_interp(1) = Q_interp(1) * (1.0 + (q_y_slope_gain_max - 1.0) * slope_level);
    Q_interp(2) = Q_interp(2) * (1.0 + (q_psi_slope_gain_max - 1.0) * slope_level);
    Q_interp(4) = Q_interp(4) * (1.0 + (q_omega_slope_gain_max - 1.0) * slope_level);
    
    % ====== 方案C (Q部分) 结束 ======
else
    Q_interp = [];
end

if enable_weight_interp && isfield(maps, 'R_range')
    R_min = maps.R_range(1, :);
    R_max = maps.R_range(2, :);
    R_interp = R_min + [fR_F; fR_w]' .* (R_max - R_min);
    
    % ====== 方案C：坡度场景下的输入权重调度（R(1)增强）======
    % 提取 R(1) 上坡/下坡增益配置
    if isfield(maps, 'R_F_gain_max_uphill')
        R_F_gain_max_uphill = maps.R_F_gain_max_uphill;
    else
        R_F_gain_max_uphill = 1.0;  % 默认：上坡不额外加重惩罚
    end
    
    if isfield(maps, 'R_F_gain_max_downhill')
        R_F_gain_max_downhill = maps.R_F_gain_max_downhill;
    else
        R_F_gain_max_downhill = 1.2;  % 默认：下坡适度增大R(1)保证平滑
    end
    
    % 根据上坡/下坡选择增益（使用带符号的theta）
    if theta >= 0
        R_F_gain_max = R_F_gain_max_uphill;
    else
        R_F_gain_max = R_F_gain_max_downhill;
    end
    
    % 计算增益（复用Q部分的theta_abs、theta_thresh、theta_trans_width）
    if theta_abs <= (theta_thresh - theta_trans_width)
        R_F_gain = 1.0;
    elseif theta_abs >= (theta_thresh + theta_trans_width)
        R_F_gain = R_F_gain_max;
    else
        s = (theta_abs - (theta_thresh - theta_trans_width)) / (2 * theta_trans_width);
        R_F_gain = 1.0 + (R_F_gain_max - 1.0) * (3*s^2 - 2*s^3);
    end
    
    % 应用增益到 R(1)：保持“增益越大，驱动力惩罚越小”的语义
    R_interp(1) = R_interp(1) / max(R_F_gain, 1e-6);
    
    % ====== 方案C (R部分) 结束 ======
else
    R_interp = [];
end

if enable_weight_interp && isfield(maps, 'dR_range')
    dR_min = maps.dR_range(1, :);
    dR_max = maps.dR_range(2, :);
    dR_interp = dR_min + [fdR_F; fdR_w]' .* (dR_max - dR_min);
    
    % ====== 方案C：坡度场景下的速率权重调度（dR(1)增强）======
    % 提取 dR(1) 上坡/下坡增益配置
    if isfield(maps, 'dR_F_gain_max_uphill')
        dR_F_gain_max_uphill = maps.dR_F_gain_max_uphill;
    else
        dR_F_gain_max_uphill = 1.0;  % 默认：上坡不额外限制dF变化
    end
    
    if isfield(maps, 'dR_F_gain_max_downhill')
        dR_F_gain_max_downhill = maps.dR_F_gain_max_downhill;
    else
        dR_F_gain_max_downhill = 1.2;  % 默认：下坡适度增大dR(1)保证平滑
    end
    
    % 根据上坡/下坡选择增益（使用带符号的theta）
    if theta >= 0
        dR_F_gain_max = dR_F_gain_max_uphill;
    else
        dR_F_gain_max = dR_F_gain_max_downhill;
    end
    
    % 计算增益（复用Q部分的theta_abs、theta_thresh、theta_trans_width）
    if theta_abs <= (theta_thresh - theta_trans_width)
        dR_F_gain = 1.0;
    elseif theta_abs >= (theta_thresh + theta_trans_width)
        dR_F_gain = dR_F_gain_max;
    else
        s = (theta_abs - (theta_thresh - theta_trans_width)) / (2 * theta_trans_width);
        dR_F_gain = 1.0 + (dR_F_gain_max - 1.0) * (3*s^2 - 2*s^3);
    end
    
    % 应用增益到 dR(1)
    dR_interp(1) = dR_interp(1) * dR_F_gain;
    
    % ====== 方案C (dR部分) 结束 ======
else
    dR_interp = [];
end

% 约束插值：支持两种策略并存（向后兼容）
omega_n = rho_n(2);
if isfield(maps,'umin_range') && isfield(maps,'umax_range')
    umin_interp_range = ((1-omega_n) * maps.umin_range(1,:).' + omega_n * maps.umin_range(2,:).');
    umax_interp_range = ((1-omega_n) * maps.umax_range(1,:).' + omega_n * maps.umax_range(2,:).');
else
    umin_interp_range = [];
    umax_interp_range = [];
end

% 叠加 scale_* 缩放（若提供），按元素乘
if coder.target('MATLAB') && isfield(maps,'scale_umin_lo') && isfield(maps,'scale_umin_hi') && ...
        isfield(maps,'scale_umax_lo') && isfield(maps,'scale_umax_hi')
    scale_umin = (1-omega_n).*maps.scale_umin_lo(:) + omega_n.*maps.scale_umin_hi(:);
    scale_umax = (1-omega_n).*maps.scale_umax_lo(:) + omega_n.*maps.scale_umax_hi(:);
else
    scale_umin = ones(2,1);
    scale_umax = ones(2,1);
end

if ~isempty(umin_interp_range)
    umin_interp = umin_interp_range .* scale_umin;
    umax_interp = umax_interp_range .* scale_umax;
else
    umin_interp = [];
    umax_interp = [];
end

%% 组装输出结构体（适配Adaptive MPC的MD通道）
upd = struct();

% 状态空间矩阵
upd.A = A_interp;   % [4×4] 状态转移矩阵
upd.B = B_interp;   % [4×2] 输入矩阵（仅MV部分）
upd.C = C_interp;   % [4×4] 输出矩阵
upd.D = D_interp;   % [4×2] 直通矩阵（仅MV部分）

% MD通道矩阵（用于Adaptive MPC）
% 说明：Adaptive MPC的model端口读取Bv作为MD通道影响矩阵
%       mpc对象的名义MD列（B_aug第3列）仅用于声明通道，不参与在线更新
upd.E = E_interp;   % [4×1] 扰动矩阵（原始输出，与Bv相同）
upd.Bv = E_interp;  % [4×1] MD影响矩阵（=E，Adaptive MPC专用名称）
upd.Dv = zeros(ny, nd);  % [4×1] MD直通矩阵（通常为零）

% 权重和约束
upd.Q = Q_interp;
upd.R = R_interp;
upd.dR = dR_interp;
upd.umin = umin_interp;
upd.umax = umax_interp;

upd.rho = [v; omega; theta];  % 实际使用的rho（饱和后，omega保留符号）
upd.rho_n = rho_n;
upd.indices = indices;
upd.weights = w;

% 调试信息（可选）
upd.debug.xi = xi;
upd.debug.eta = eta;
upd.debug.zeta = zeta;
upd.debug.i_range = [i_low, i_high];
upd.debug.j_range = [j_low, j_high];
upd.debug.k_range = [k_low, k_high];

end
