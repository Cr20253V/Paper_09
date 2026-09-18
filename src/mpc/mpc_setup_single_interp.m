function ctrl = mpc_setup_single_interp(db, opts)
% =============================
% 文件名：mpc_setup_single_interp.m
% 路径：S-Function_14/mpc_setup_single_interp.m
% 版本号：V1.1
% 最后修改时间：2025-10-25
% 作者：Auto-generated
% 功能描述：
%   创建单一自适应MPC控制器，支持在线模型插值和权重/约束调整
%   基于LPV模型数据库构建初始MPC对象
% 输入参数：
%   - db：LPV模型数据库（来自 lin_agv_grid.m），包含
%       - A, B, C, D, E：线性化矩阵数组 (Nv×Nw×Nt×...)
%       - grid：网格定义 {V, W, T}
%       - Ts：采样周期
%   - opts：设计选项结构体，包含
%       - Np：预测时域（步数），默认 20
%       - Nc：控制时域（步数），默认 5
%       - Q：输出权重对角元素 [q_y, q_psi, q_v, q_omega]，默认 [3, 8, 1, 1]
%       - R：输入权重对角元素 [r_F, r_omega]，默认 [1e-3, 1e-3]
%       - dR：输入变化率权重对角元素 [r_dF, r_domega]，默认 [1e-2, 1e-2]
%       - umin：输入下界 [Fmin, omegamin]，默认 [-600, -1.2]
%       - umax：输入上界 [Fmax, omegamax]，默认 [600, 1.2]
%       - dumin：输入变化率下界，默认 [-400, -0.9]
%       - dumax：输入变化率上界，默认 [400, 0.9]
%       - ymin：输出下界（软约束），默认 [-0.5, -0.3, -0.5, -0.3]
%       - ymax：输出上界（软约束），默认 [0.5, 0.3, 0.5, 0.3]
%       - soft_weight_pos：位置（e_y）软约束权重，默认 1e4
%       - soft_weight_yaw：航向（e_psi）软约束权重，默认 1e4
% 输出参数：
%   - ctrl：控制器结构体，包含
%       - mpcobj：MATLAB MPC对象（含2个MV + 1个MD）
%       - db：模型数据库引用
%       - opts：设计选项
%       - maps：权重/约束映射表（用于在线更新）
%       - meta：元数据（含has_md标志）
% 依赖：
%   - Model Predictive Control Toolbox
%   - lin_agv_grid.m 产物
% 备注：
%   - 基准模型选择：网格中心点或指定工作点
%   - 支持 Adaptive MPC 在线模型更新
%   - 建议预测时域：Np ≈ 2.0-3.0s，控制时域：Nc ≈ 0.5-1.0s
%   - MD通道：theta（坡度角），用于前馈补偿
%   - 名义模型：B_aug第3列为零占位，自适应时由E(ρ)替换
% =============================

%% 参数检查与默认值
if nargin < 2
    opts = struct();
end

% 检查MPC Toolbox
if ~license('test', 'mpc_toolbox')
    error('mpc_setup_single_interp:NoToolbox', ...
        '需要 Model Predictive Control Toolbox');
end

% 提取采样周期和维度
Ts = db.Ts;
nx = db.nx;
nu = db.nu;
ny = db.ny;

% 默认预测/控制时域（根据采样周期自适应）
if ~isfield(opts, 'Np'), opts.Np = round(1.6 / Ts); end  % 1.6秒预测时域，回稳并保留适度提前量
if ~isfield(opts, 'Nc'), opts.Nc = round(0.6 / Ts); end  % 0.6秒控制时域，避免动作过慢

% 默认权重（提高横向跟踪优先级）
if ~isfield(opts, 'Q'), opts.Q = [15.293, 28.737, 5.076, 2.9918]; end  % [e_y, e_psi, e_v, e_omega]，提高 q_y 和 q_psi
if ~isfield(opts, 'R'), opts.R = [1e-3, 1e-3]; end  % [F_cmd, omega_cmd]
if ~isfield(opts, 'dR'), opts.dR = [1e-2, 1e-2]; end  % 速率权重

% 默认约束
if ~isfield(opts, 'umin'), opts.umin = [-600; -1.2]; end  % [N, rad/s]，诊断性放宽转向角速度约束
if ~isfield(opts, 'umax'), opts.umax = [600; 1.2]; end
if ~isfield(opts, 'dumin'), opts.dumin = [-400; -0.9]; end  % [N/step, (rad/s)/step]，同步放宽转向角速度变化率约束
if ~isfield(opts, 'dumax'), opts.dumax = [400; 0.9]; end
if ~isfield(opts, 'ymin'), opts.ymin = [-1.0; -0.5; -0.5; -0.3]; end  % [m, rad, m/s, rad/s]，放宽 e_y 和 e_psi
if ~isfield(opts, 'ymax'), opts.ymax = [1.0; 0.5; 0.5; 0.3]; end
if ~isfield(opts, 'soft_weight_pos'), opts.soft_weight_pos = 3e3; end  % 位置软约束惩罚，避免过度保守
if ~isfield(opts, 'soft_weight_yaw'), opts.soft_weight_yaw = 3e3; end  % 航向软约束惩罚

fprintf('========== MPC控制器设计 ==========\n');
fprintf('采样周期: %.3f s\n', Ts);
fprintf('预测时域: Np = %d 步 (%.2f s)\n', opts.Np, opts.Np * Ts);
fprintf('控制时域: Nc = %d 步 (%.2f s)\n', opts.Nc, opts.Nc * Ts);
fprintf('状态维度: nx = %d\n', nx);
fprintf('输入维度: nu = %d\n', nu);
fprintf('输出维度: ny = %d\n', ny);
fprintf('===================================\n\n');

%% 选择基准工作点（网格中心或指定点）
Nv = db.Nv;
Nw = db.Nw;
Nt = db.Nt;

% 选择中心点索引
i_center = ceil(Nv / 2);
j_center = ceil(Nw / 2);
k_center = ceil(Nt / 2);

% 提取基准模型矩阵
A0 = squeeze(db.A(i_center, j_center, k_center, :, :));
B0 = squeeze(db.B(i_center, j_center, k_center, :, :));
C0 = squeeze(db.C(i_center, j_center, k_center, :, :));
D0 = squeeze(db.D(i_center, j_center, k_center, :, :));

% 提取E0矩阵（测量扰动：坡度角theta）
if isfield(db, 'E')
    E0 = squeeze(db.E(i_center, j_center, k_center, :, :));
    has_md = true;
else
    E0 = [];
    has_md = false;
    warning('mpc_setup:NoMD', '数据库中未找到E矩阵，MD通道将不可用');
end

v_center = db.grid.V(i_center);
omega_center = db.grid.W(j_center);
theta_center = db.grid.T(k_center);

fprintf('========== 基准工作点 ==========\n');
fprintf('v0 = %.2f m/s\n', v_center);
fprintf('ω0 = %.3f rad/s（有符号）\n', omega_center);
fprintf('θ0 = %.2f°\n', rad2deg(theta_center));
fprintf('================================\n\n');

%% 创建离散状态空间模型（扩展为2×MV + 1×MD）
% 名义模型输入：[F_cmd, omega_cmd, theta_md]（3个输入）
% 其中前2个是操纵变量MV，第3个是测量扰动MD

if has_md
    % 扩展B、D矩阵：追加MD列（初始用零占位）
    B_aug = [B0, zeros(nx, 1)];  % [nx × 3]，第3列留给MD（名义为零）
    D_aug = [D0, zeros(ny, 1)];  % [ny × 3]
else
    % 无MD时保持原样
    B_aug = B0;
    D_aug = D0;
end

plant = ss(A0, B_aug, C0, D_aug, Ts);

% 设置信号名称（便于调试和可视化）
plant.StateName = {'e_y', 'e_psi', 'e_v', 'e_omega'};
if has_md
    plant.InputName = {'F_cmd', 'omega_cmd', 'theta_md'};
else
    plant.InputName = {'F_cmd', 'omega_cmd'};
end
plant.OutputName = {'y_e_y', 'y_e_psi', 'y_e_v', 'y_e_omega'};

%% 设置输入分组（在创建MPC前）
if has_md
    % 使用InputGroup属性声明输入分组
    plant = setmpcsignals(plant, 'MV', [1 2], 'MD', 3);
    fprintf('========== 输入分组 ==========\n');
    fprintf('MV (操纵变量): [1:2] = [F_cmd, omega_cmd]\n');
    fprintf('MD (测量扰动): [3] = [theta]\n');
    fprintf('==============================\n\n');
end

%% 创建MPC对象
mpcobj = mpc(plant, Ts, opts.Np, opts.Nc);

%% 设置权重
% 输出权重（跟踪误差惩罚）
mpcobj.Weights.OutputVariables = opts.Q;

% 输入权重（控制努力惩罚）
mpcobj.Weights.ManipulatedVariables = opts.R;

% 输入变化率权重（平滑性惩罚）
mpcobj.Weights.ManipulatedVariablesRate = opts.dR;

fprintf('========== 权重设置 ==========\n');
fprintf('输出权重 Q = [%.2f, %.2f, %.2f, %.2f]\n', opts.Q(1), opts.Q(2), opts.Q(3), opts.Q(4));
fprintf('输入权重 R = [%.3e, %.3e]\n', opts.R(1), opts.R(2));
fprintf('速率权重 dR = [%.3e, %.3e]\n', opts.dR(1), opts.dR(2));
fprintf('==============================\n\n');

%% 设置约束
% 输入幅值约束（仅对MV设置，不包括MD）
% 注意：nu=db.nu=2，表示MV个数，不是size(B_aug,2)=3
for i = 1:nu  % nu=2，只循环MV
    mpcobj.MV(i).Min = opts.umin(i);
    mpcobj.MV(i).Max = opts.umax(i);
    mpcobj.MV(i).RateMin = opts.dumin(i);
    mpcobj.MV(i).RateMax = opts.dumax(i);
end

% 输出约束（软约束：e_y 和 e_psi，分别设置权重）
% e_y（位置误差）
mpcobj.OV(1).Min = opts.ymin(1);
mpcobj.OV(1).Max = opts.ymax(1);
mpcobj.OV(1).MinECR = opts.soft_weight_pos;  % 位置误差软约束权重
mpcobj.OV(1).MaxECR = opts.soft_weight_pos;

% e_psi（航向误差）
mpcobj.OV(2).Min = opts.ymin(2);
mpcobj.OV(2).Max = opts.ymax(2);
mpcobj.OV(2).MinECR = opts.soft_weight_yaw;  % 航向误差软约束权重
mpcobj.OV(2).MaxECR = opts.soft_weight_yaw;

% 速度和角速度误差约束（建议不约束或使用软约束，避免不可行）
for i = 3:4
    % 方案1：不约束（推荐，避免求解不可行）
    mpcobj.OV(i).Min = -Inf;
    mpcobj.OV(i).Max = Inf;
    
    % 方案2（可选）：软约束，打开下面注释
    % mpcobj.OV(i).Min = opts.ymin(i);
    % mpcobj.OV(i).Max = opts.ymax(i);
    % mpcobj.OV(i).MinECR = 1e2;  % 较小的软约束权重
    % mpcobj.OV(i).MaxECR = 1e2;
end

fprintf('========== 约束设置 ==========\n');
fprintf('输入约束:\n');
fprintf('  F_cmd ∈ [%.1f, %.1f] N\n', opts.umin(1), opts.umax(1));
fprintf('  omega_cmd ∈ [%.2f, %.2f] rad/s\n', opts.umin(2), opts.umax(2));
fprintf('输入速率约束:\n');
fprintf('  ΔF ∈ [%.1f, %.1f] N/step\n', opts.dumin(1), opts.dumax(1));
fprintf('  Δω ∈ [%.2f, %.2f] (rad/s)/step\n', opts.dumin(2), opts.dumax(2));
fprintf('输出软约束:\n');
fprintf('  e_y ∈ [%.2f, %.2f] m (软约束权重: %.1e)\n', opts.ymin(1), opts.ymax(1), opts.soft_weight_pos);
fprintf('  e_psi ∈ [%.2f, %.2f] rad (软约束权重: %.1e)\n', opts.ymin(2), opts.ymax(2), opts.soft_weight_yaw);
fprintf('  e_v, e_omega：不约束（避免求解不可行）\n');
fprintf('==============================\n\n');

%% 构建权重/约束映射表（用于在线更新）
% 映射函数：rho_n ∈ [0,1]^3 → 权重/约束
% 这里提供一个简单的线性插值示例

% 定义调度变量的归一化范围
rho_min = [db.grid.V(1); db.grid.W(1); db.grid.T(1)];
rho_max = [db.grid.V(end); db.grid.W(end); db.grid.T(end)];

% 权重映射：根据速度和角速度调整权重（示例）
% Q: 低速时增大位置权重，高速时增大速度权重
% R: 转弯时增大角速度权重
maps = struct();
maps.rho_min = rho_min;
maps.rho_max = rho_max;

% 权重插值范围（示例：Q可根据rho变化）
maps.Q_range = [opts.Q * 0.5; opts.Q * 1.5];  % [min; max]
maps.R_range = [opts.R * 0.5; opts.R * 1.5];
maps.dR_range = [opts.dR * 0.5; opts.dR * 1.5];

% 形状参数（归一化域[0,1]上的阈值区间，alpha<=beta）；若不使用则等于[0,1]
maps.alpha_Q = zeros(1,4);    % [q_y q_psi q_v q_omega]
maps.beta_Q  = ones(1,4);
maps.alpha_R = zeros(1,2);    % [r_F r_omega]
maps.beta_R  = ones(1,2);
maps.alpha_dR = zeros(1,2);   % [r_dF r_domega]
maps.beta_dR  = ones(1,2);

% 因子权重（v,omega,theta三维的线性组合系数，和为1；默认启用与否由 enable_factor 控制）
maps.enable_factor = false;
maps.factor_y      = [0.3 0.2 0.5];   % 影响 q_y
maps.factor_psi    = [0.1 0.7 0.2];   % 影响 q_psi
maps.factor_v      = [0.8 0.1 0.1];   % 影响 q_v
maps.factor_omega  = [0.2 0.6 0.2];   % 影响 q_omega
maps.factor_R_F    = [0.6 0.3 0.1];   % 影响 r_F
maps.factor_R_omega= [0.2 0.7 0.1];   % 影响 r_omega
maps.factor_dR_F   = [0.5 0.3 0.2];   % 影响 r_dF
maps.factor_dR_omega=[0.2 0.6 0.2];   % 影响 r_domega

% 约束缩放（随 |omega| 的幅值插值，标量或1×2向量；最终按元素缩放）
maps.scale_umin_lo = ones(1,2);  % |omega|=0 时的 umin 缩放
maps.scale_umin_hi = ones(1,2);  % |omega|=max 时的 umin 缩放
maps.scale_umax_lo = ones(1,2);  % |omega|=0 时的 umax 缩放
maps.scale_umax_hi = ones(1,2);  % |omega|=max 时的 umax 缩放

% 权重插值开关（保持启用；注意需要外部端口接入或回调覆盖权重）
maps.enable_weight_interp = true;  % 启用：允许随ρ调度权重/约束（需外部端口接入）

% ρ归一化函数
% 注意：为代码生成兼容，移除函数句柄 normalize_fn；在 mpc_update_from_rho.m 内使用内置归一化
% maps.normalize_fn 已移除

% 约束插值范围（向后兼容：保留线性范围定义，不与 scale_* 冲突）
maps.umin_range = [ (1.20*opts.umin).'; (1.00*opts.umin).' ];  % [min_row; max_row]
maps.umax_range = [ (1.00*opts.umax).'; (1.20*opts.umax).' ];

% 输出约束范围（供在线调整，可选）
maps.ey_max = abs(opts.ymax(1));      % 横向误差最大值[m]
maps.epsi_max = abs(opts.ymax(2));    % 航向误差最大值[rad]
maps.ev_max = abs(opts.ymax(3));      % 速度误差最大值[m/s]
maps.eomega_max = abs(opts.ymax(4));  % 角速度误差最大值[rad/s]

% ====== 方案B：场景自适应权重调度配置（新增） ======
% 转弯时自动提高横向跟踪权重 q_y，改善转弯精度
% 可通过 Bayesian_Optimization 优化这些参数
maps.omega_threshold = 0.15;    % 角速度阈值 [rad/s]，|omega|>0.15 判定为转弯
maps.q_y_gain_max = 2.5;        % 转弯时 q_y 最大增益系数（放大倍数，针对0.37rad/s增强）
maps.q_psi_gain_max = 1.0;      % 默认保持旧行为；实验可在转弯时增强航向权重
maps.q_omega_gain_max = 1.0;    % 默认保持旧行为；实验可在转弯时增强角速度误差权重
maps.q_y_slope_gain_max = 1.0;  % 默认保持旧行为；实验可在坡度段增强横向权重
maps.q_psi_slope_gain_max = 1.0; % 默认保持旧行为；实验可在坡度段增强航向权重
maps.q_omega_slope_gain_max = 1.0; % 默认保持旧行为；实验可在坡度段增强角速度误差权重
maps.transition_width = 0.05;   % 过渡带宽度 [rad/s]，平滑切换避免抖动
% 说明：
%   - |omega| < (threshold - width)：直线，q_y_gain = 1.0
%   - |omega| > (threshold + width)：转弯，q_y_gain = gain_max
%   - 中间区域：三次 Hermite 平滑过渡
% ====== 方案B 结束 ======

% ====== 方案C：坡度自适应权重调度配置（新增） ======
% 坡道上提高速度跟踪权重 q_v，并调整输入惩罚
maps.theta_threshold = 0.035;       % 坡度阈值 [rad] (约2度)
maps.q_v_gain_max = 5.0;            % 坡道上 q_v 增益 (加强速度保持)
maps.R_F_gain_max_uphill = 1.0;     % 上坡时不增加 R_F (允许大力输出)
maps.theta_transition_width = 0.017; % 过渡带宽度 [rad]
% ====== 方案C 结束 ======

% 断言：确保rho端点与网格一致（稳健性检查）
assert(all(abs(maps.rho_min - [db.grid.V(1); db.grid.W(1); db.grid.T(1)]) < 1e-10), ...
    'maps.rho_min与网格端点不一致');
assert(all(abs(maps.rho_max - [db.grid.V(end); db.grid.W(end); db.grid.T(end)]) < 1e-10), ...
    'maps.rho_max与网格端点不一致');

fprintf('========== 调度映射 ==========\n');
fprintf('rho 范围:\n');
fprintf('  v ∈ [%.2f, %.2f] m/s\n', rho_min(1), rho_max(1));
fprintf('  ω ∈ [%.3f, %.3f] rad/s（有符号）\n', rho_min(2), rho_max(2));
fprintf('  θ ∈ [%.2f, %.2f]°\n', rad2deg(rho_min(3)), rad2deg(rho_max(3)));
if maps.enable_weight_interp
    fprintf('权重插值: 启用 (Q, R, dR 可变; alpha/beta形状, factor=%s)\n', string(maps.enable_factor));
    fprintf('  注意：需Simulink中显式使用（如外部权重端口）或脚本中覆盖\n');
else
    fprintf('权重插值: 禁用（固定权重，推荐用于初期联调）\n');
end
fprintf('约束插值: 支持 scale_* 与范围插值（随 |ω| 调整）\n');
fprintf('==============================\n\n');

%% 设置求解器选项（可选）
% mpcobj.Optimizer.ActiveSetOptions.MaxIter = 50;
% mpcobj.Optimizer.Algorithm = 'active-set';  % 或 'interior-point'

%% 组装输出控制器结构体
ctrl = struct();
ctrl.mpcobj = mpcobj;
ctrl.db = db;  % 保存数据库引用（用于在线更新）
ctrl.opts = opts;
ctrl.maps = maps;

% 元数据
ctrl.meta.version = 'V1.2';
ctrl.meta.generated_by = 'mpc_setup_single_interp.m';
ctrl.meta.generated_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ctrl.meta.base_workpoint = [v_center, omega_center, theta_center];
ctrl.meta.Ts = Ts;
ctrl.meta.Np = opts.Np;
ctrl.meta.Nc = opts.Nc;
ctrl.meta.control_horizon_sec = opts.Nc * Ts;
ctrl.meta.prediction_horizon_sec = opts.Np * Ts;
ctrl.meta.has_md = has_md;
ctrl.meta.mv_signals = 'F_cmd[N], omega_cmd[rad/s]';
if has_md
    ctrl.meta.md_signals = 'theta[rad]';
    ctrl.meta.md_note = '坡度角前馈，提前补偿坡度影响';
end

fprintf('========== MPC控制器创建完成 ==========\n');
fprintf('控制器类型: 单一自适应MPC\n');
fprintf('在线更新: 支持（通过 mpc_update_from_rho.m）\n');
fprintf('误差参考: [0; 0; 0; 0]（误差趋零控制）\n');
fprintf('ref输入契约: Simulink中ref端口必须接[0;0;0;0]\n');
if has_md
    fprintf('测量扰动: theta（坡度角前馈）\n');
    fprintf('扰动补偿: 通过MD通道提前预测坡度影响\n');
end
fprintf('==========================================\n\n');

end
