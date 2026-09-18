function sys = lin_agv_at_point(x0, u0, theta0, params)
% =============================
% 文件名：lin_agv_at_point.m
% 路径：S-Function_14/lin_agv_at_point.m
% 版本号：V1.0
% 最后修改时间：2025-10-03
% 作者：Auto-generated
% 功能描述：
%   在指定工作点对AGV路径坐标系误差动力学进行线性化
%   输出离散状态空间模型 (A,B,C,D,E)
% 输入参数：
%   - x0：工作点状态向量 [X Y psi v omega delta_lf delta_rr beta] (8×1), 单位：m, rad, m/s, rad/s, rad, rad, rad
%   - u0：工作点输入向量 [F_cmd omega_cmd] (2×1), 单位：N, rad/s
%   - theta0：工作点坡度角 (标量), 单位：rad
%   - params：参数结构体 (来自 parameters.m)
% 输出参数：
%   - sys：结构体，包含
%     - A：状态矩阵 (4×4)，路径坐标系误差状态 [e_y, e_psi, e_v, e_omega]
%     - B：输入矩阵 (4×2)，输入 [F_cmd, omega_cmd]
%     - C：输出矩阵 (4×4)，输出 = 状态
%     - D：直通矩阵 (4×2)，通常为零
%     - E：扰动矩阵 (4×1)，扰动 [theta]
%     - x0, u0, theta0：工作点
%     - v0, omega0：工作点速度和角速度（用于路径坐标转换）
%     - meta：元数据
% 依赖：
%   - state_eq.m：非线性状态转移方程
%   - output_eq.m：非线性输出方程
%   - parameters.m：参数定义
% 备注：
%   - 线性化方法：数值有限差分
%   - 坐标系：路径坐标系误差 (e_y, e_psi, e_v, e_omega)
%   - 状态维度：nx=4
%   - 输入维度：nu=2
%   - 扰动维度：nd=1
% =============================

%% 提取工作点信息
X0 = x0(1); Y0 = x0(2); psi0 = x0(3); v0 = x0(4);
omega0 = x0(5); delta_lf0 = x0(6); delta_rr0 = x0(7); beta0 = x0(8);

F_cmd0 = u0(1);
omega_cmd0 = u0(2);

%% 定义路径坐标系误差状态（最小集）
% 状态: x_e = [e_y, e_psi, e_v, e_omega]^T  (4×1)
% 输入: u = [F_cmd, omega_cmd]^T  (2×1)
% 扰动: d = [theta]  (1×1)

nx = 4;  % 状态维度
nu = 2;  % 输入维度
nd = 1;  % 扰动维度

%% 数值线性化参数（针对不同量纲的自适应扰动）
% 对应8维全状态：[X, Y, psi, v, omega, delta_lf, delta_rr, beta]
epsilon_x = [1e-3; 1e-3; 1e-4; 1e-3; 1e-4; 1e-4; 1e-4; 1e-4];  % 状态扰动量
epsilon_u = [0.1; 1e-3];  % 输入扰动量 [F_cmd, omega_cmd]
epsilon_theta = 1e-4;  % 坡度扰动量

% 误差状态扰动量（从epsilon_x提取对应分量）
epsilon_e = [epsilon_x(2); epsilon_x(3); epsilon_x(4); epsilon_x(5)];  % [e_y, e_psi, e_v, e_omega]

%% 定义全状态到误差状态的提取函数
% 假设参考轨迹在工作点处：X_ref=X0, Y_ref=Y0, psi_ref=psi0, v_ref=v0, omega_ref=omega0
% 路径坐标系误差（路径法向-切向坐标系）
% e_y = (Y - Y_ref)*cos(psi_ref) - (X - X_ref)*sin(psi_ref)  (横向误差)
% e_psi = psi - psi_ref  (航向误差)
% e_v = v - v_ref  (速度误差)
% e_omega = omega - omega_ref  (角速度误差)

% 参考值（工作点即为参考点）
X_ref = X0; Y_ref = Y0; psi_ref = psi0; v_ref = v0; omega_ref = omega0;

% 角度归一化辅助函数（替代wrapToPi，提高兼容性）
wrap_pi = @(a) atan2(sin(a), cos(a));

% 全状态到误差状态的映射函数
full_to_error = @(x_full) [
    (x_full(2) - Y_ref) * cos(psi_ref) - (x_full(1) - X_ref) * sin(psi_ref);  % e_y
    wrap_pi(x_full(3) - psi_ref);  % e_psi
    x_full(4) - v_ref;  % e_v
    x_full(5) - omega_ref  % e_omega
];

%% 计算工作点的误差状态（应该接近零）
x_e0 = full_to_error(x0);

%% 离散线性化：基准状态转移
x_next_0 = state_eq_ref(x0, u0, theta0, params);
x_e_next_0 = full_to_error(x_next_0);

%% 离散线性化：B_d 矩阵（输入雅可比）
% 方法：数值有限差分（一步差分，步长=params.Ts）

B_d = zeros(nx, nu);
for j = 1:nu
    u_plus = u0;
    u_plus(j) = u_plus(j) + epsilon_u(j);
    
    u_minus = u0;
    u_minus(j) = u_minus(j) - epsilon_u(j);
    
    x_next_plus = state_eq_ref(x0, u_plus, theta0, params);
    x_next_minus = state_eq_ref(x0, u_minus, theta0, params);
    
    x_e_next_plus = full_to_error(x_next_plus);
    x_e_next_minus = full_to_error(x_next_minus);
    
    % 数值导数（相对于基准状态）
    B_d(:, j) = (x_e_next_plus - x_e_next_minus) / (2 * epsilon_u(j));
end

%% 离散线性化：E_d 矩阵（扰动雅可比）
% 方法：数值有限差分（一步差分，步长=params.Ts）

theta_plus = theta0 + epsilon_theta;
theta_minus = theta0 - epsilon_theta;

x_next_plus = state_eq_ref(x0, u0, theta_plus, params);
x_next_minus = state_eq_ref(x0, u0, theta_minus, params);

x_e_next_plus = full_to_error(x_next_plus);
x_e_next_minus = full_to_error(x_next_minus);

E_d(:, 1) = (x_e_next_plus - x_e_next_minus) / (2 * epsilon_theta);

%% 离散线性化：A_d 矩阵（状态雅可比）
% 离散模型：x_e(k+1) = A_d * x_e(k) + B_d * u(k) + E_d * d(k)
% 方法：数值有限差分（一步差分，步长=params.Ts）
% 说明：通过state_eq前向一步，捕获离散动力学的雅可比

A_d = zeros(nx, nx);
for j = 1:4  % 对误差状态的4个分量扰动
    % 使用分量化扰动量（针对不同量纲）
    d_err = epsilon_e(j);  % 从epsilon_x提取对应分量
    
    % 反向映射：误差状态 -> 全状态（考虑参考航向的几何投影）
    x_pert = x0;
    if j == 1  % e_y（横向误差）
        % 沿法向扰动：考虑参考航向psi_ref
        x_pert(1) = x_pert(1) - d_err * sin(psi_ref);  % X -= d*sin(psi_ref)
        x_pert(2) = x_pert(2) + d_err * cos(psi_ref);  % Y += d*cos(psi_ref)
    elseif j == 2  % e_psi（航向误差）
        x_pert(3) = x_pert(3) + d_err;  % psi扰动
    elseif j == 3  % e_v（速度误差）
        x_pert(4) = x_pert(4) + d_err;  % v扰动
    elseif j == 4  % e_omega（角速度误差）
        x_pert(5) = x_pert(5) + d_err;  % omega扰动
    end
    
    x_next_pert = state_eq_ref(x_pert, u0, theta0, params);
    x_e_next_pert = full_to_error(x_next_pert);
    
    A_d(:, j) = (x_e_next_pert - x_e_next_0) / d_err;
end

%% 几何耦合修正（可选，经验补偿）
% 注意：A_d已通过"一步差分（步长=Ts）"自动捕获几何耦合
% 此项为可选的经验增强，建议先关闭测试基础模型性能
enhance_kappa_coupling = false;  % 开关：是否手工增强曲率耦合

if enhance_kappa_coupling
    kappa0 = omega0 / max(abs(v0), 1e-3);  % 工作点曲率（保留符号）
    if abs(kappa0) > 1e-4  % 仅在转弯时添加耦合
        % A_d(1,2)：e_psi 对 e_y 的一阶耦合（经验补偿）
        % 离散化后：e_y(k+1) = e_y(k) + Ts*v0*(e_psi + kappa0*...)
        A_d(1, 2) = A_d(1, 2) + params.Ts * v0 * kappa0 * 0.5;
    end
end

%% 数值稳健化：极点抑制（仅在|λ|>1时收缩不稳定模态）
% 说明：参数修正后，高侧偏刚度与低速有限差分会把横摆/侧滑局部
% 离散极点推到单位圆外。MPC 的预测模型需要数值稳定，因此这里
% 只裁剪不稳定特征值，避免对所有状态施加统一对角泄露而破坏
% 位置/航向/速度通道的尺度。
tol_unstable = 1e-6;   % 不稳定判据容差
target_mod  = 0.9990;  % 更保守的目标谱半径
eigA = eig(A_d);
rhoA = max(abs(eigA));
if rhoA > 1.0 + tol_unstable
    try
        [V, D] = eig(A_d);
        lam = diag(D);
        for ii = 1:numel(lam)
            if abs(lam(ii)) > target_mod
                lam(ii) = target_mod * lam(ii) / abs(lam(ii));
            end
        end
        A_stab = real(V * diag(lam) / V);
        if all(isfinite(A_stab(:))) && max(abs(eig(A_stab))) <= target_mod + 1e-6
            A_d = A_stab;
        else
            A_d = local_stabilize_by_diagonal_modes(A_d, target_mod);
        end
    catch
        A_d = local_stabilize_by_diagonal_modes(A_d, target_mod);
    end
end

%% 输出矩阵（输出 = 状态）
C = eye(nx);
D = zeros(nx, nu);

%% 组装输出结构体（离散模型）
sys.A = A_d;  % 离散状态矩阵
sys.B = B_d;  % 离散输入矩阵
sys.C = C;    % 输出矩阵
sys.D = D;    % 直通矩阵
sys.E = E_d;  % 离散扰动矩阵
sys.Ts = params.Ts;

% 工作点信息
sys.x0 = x0;
sys.u0 = u0;
sys.theta0 = theta0;
sys.v0 = v0;
sys.omega0 = omega0;

% 状态空间维度
sys.nx = nx;
sys.nu = nu;
sys.nd = nd;

% 元数据
sys.meta.version = 'V1.2';
sys.meta.generated_by = 'lin_agv_at_point.m';
sys.meta.generated_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
sys.meta.method = 'numerical_finite_difference_one_step';
sys.meta.model_semantics = 'discrete';  % 明确标注为离散模型
sys.meta.discretization_note = '一步差分线性化（步长Ts=params.Ts），直接捕获离散动力学';
sys.meta.coordinate = 'path_error';
sys.meta.states = 'e_y[m], e_psi[rad], e_v[m/s], e_omega[rad/s]';
sys.meta.inputs = 'F_cmd[N], omega_cmd[rad/s]';
sys.meta.disturbances = 'theta[rad]';
sys.meta.geometric_projection = 'e_y mapped to (X,Y) via psi_ref';
sys.meta.kappa_coupling = enhance_kappa_coupling;

% 有效范围说明
sys.valid_range.v = [max(v0-0.3, 0.5), v0+0.3];  % 速度有效范围 ±0.3 m/s
sys.valid_range.omega = [omega0-0.1, omega0+0.1];  % 角速度有效范围 ±0.1 rad/s
sys.valid_range.theta = [theta0-deg2rad(5), theta0+deg2rad(5)];  % 坡度有效范围 ±5°

end

function A = local_stabilize_by_diagonal_modes(A, target_mod)
% Fallback for nearly defective local models: clip only unstable diagonal
% modes and keep off-diagonal coupling unchanged.
for ii = 1:min(size(A))
    if abs(A(ii, ii)) > target_mod
        A(ii, ii) = target_mod * sign(A(ii, ii));
        if A(ii, ii) == 0
            A(ii, ii) = target_mod;
        end
    end
end
end
