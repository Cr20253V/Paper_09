function [plant, y_wt, u_wt, du_wt, ecr_wt, umin, umax] = UpdatePlantModel(rho, db_rt, MPC_idx, ff_rt, v_ff_nom, label_vec)
%#codegen
% =========================================================================
% UpdatePlantModel - 使用 P0 oracle-MPC 最优参数 + Nominal 前馈
%
% 版本：V2.0（2026-04-06）
%
% 说明：
% 1) Q/R/dR 核心权重区间与 P0 离线 oracle 整定保持一致；
% 2) 场景自适应参数与 maps_best_agv_physics_v2_p0_oracle.mat 保持一致；
% 3) plant.U 注入 [F_eq; omega_ref; theta] 名义工作点，与 LPV 线性化一致；
% 4) V2：新增 label_vec=[label_main; label_slip] 输入，接入 Mamba2 分类输出：
%       - label_main==2 (stall)：放宽 F_cmd 约束，防止 MPC 因力限制求解失败
%       - label_slip==1 (slip) ：降低 F_cmd 上限，减少向打滑轮的驱动力输入
%
% 接口：
%   [plant, y_wt, u_wt, du_wt, ecr_wt, umin, umax] = ...
%       UpdatePlantModel(rho, db_rt, MPC_idx, ff_rt, v_ff_nom, label_vec)
%
% 输入：
%   rho      (3×1)  调度变量 [v_f; omega_f; theta_f]（来自 RhoFilter 输出）
%   db_rt           LPV 模型数据库（来自 lin_agv_db.mat）
%   MPC_idx         保留（未使用，兼容旧接口）
%   ff_rt           前馈参数结构体（含 m/g/c_r 字段）
%   v_ff_nom        保留（未使用，兼容旧接口）
%   label_vec (2×1) 分类标签 [label_main; label_slip]
%                   label_main: 1=flat, 2=stall, 3=slope
%                   label_slip:  0=normal, 1=slip
%
% 输出：plant, y_wt, u_wt, du_wt, ecr_wt, umin, umax（接 Adaptive MPC 各端口）
% =========================================================================

% 保留接口兼容
unused = MPC_idx; %#ok<NASGU>
unused = v_ff_nom; %#ok<NASGU>

coder.extrinsic('evalin');

%% ==================== Persistent 状态（标签迟滞功能）====================
persistent stall_on stall_on_cnt stall_off_cnt slope_on slope_on_cnt slope_off_cnt

% 初始化：stall 迟滞滤波状态
if isempty(stall_on)
    stall_on      = false;
    stall_on_cnt  = 0;
    stall_off_cnt = 0;
end

% 初始化：slope 迟滞滤波状态
if isempty(slope_on)
    slope_on      = false;
    slope_on_cnt  = 0;
    slope_off_cnt = 0;
end

%% ==================== 基于 P0 oracle 结果构建 maps_local ====================
% 当前读取来源：
% - results/.../p0_oracle_retuning_20260602_033639/maps_best_agv_physics_v2_p0_oracle.mat
% - 最优候选：Np=150, Nc=30, Q=[100,100,15,3], R=[3e-5,3e-5], dR=[1e-3,1e-3]

Q_range_bo = [ ...
50.0, 50.0, 7.5, 1.5; ...
150.0, 150.0, 22.5, 4.5];

R_range_bo = [ ...
1.5e-5, 1.5e-5; ...
4.5e-5, 4.5e-5];

dR_range_bo = [ ...
5.0e-4, 5.0e-4; ...
1.5e-3, 1.5e-3];

maps_local = struct( ...
    'enable_weight_interp', true, ...
    'Q_range', Q_range_bo, ...
    'R_range', R_range_bo, ...
    'dR_range', dR_range_bo, ...
    'alpha_Q', [0, 0, 0, 0], ...
    'beta_Q', [1, 1, 1, 1], ...
    'alpha_R', [0, 0], ...
    'beta_R', [1, 1], ...
    'alpha_dR', [0, 0], ...
    'beta_dR', [1, 1], ...
    'scale_umin_lo', [1, 1], ...
    'scale_umin_hi', [1, 1], ...
    'scale_umax_lo', [1, 1], ...
    'scale_umax_hi', [1, 1], ...
    'rho_min', [0.02; -1.2; -0.20943951023932], ...
    'rho_max', [1.2; 1.2; 0.20943951023932], ...
    'tau', 0.35, ...
    'omega_threshold', 0.15, ...
    'q_y_gain_max', 2.5, ...
    'transition_width', 0.05, ...
    'theta_threshold', 0.035, ...
    'q_v_gain_max', 5.0, ...
    'theta_transition_width', 0.017, ...
    'R_F_gain_max_uphill', 1.0, ...
    'R_F_gain_max_downhill', 1.2, ...
    'dR_F_gain_max_uphill', 1.0, ...
    'dR_F_gain_max_downhill', 1.2, ...
    'umin_range', [-720, -1.44; -600, -1.2], ...
    'umax_range', [ 600, 1.2; 720, 1.44] ...
);

maps_local = local_apply_runtime_maps_from_base(maps_local);
maps_local = local_apply_runtime_scalar_maps_from_base(maps_local);
maps_local = local_apply_runtime_override_from_base(maps_local, db_rt);

%% ==================== 调度变量预处理 ====================
% rho 已由上游 RhoFilter 处理，离线 Cost_Function 也只使用一层 tau=0.35s 滤波。
% 这里不再追加 omega LPF，避免 Simulink 闭环和离线 oracle 使用不同调度点。
rho_upd = rho;

%% ==================== 在线插値：模型/权重/约束 ====================
upd = mpc_update_from_rho(rho_upd, db_rt, maps_local);

%% ==================== Mamba2 分类标签覆盖（V2 新增）====================
% label_vec = [label_main; label_slip]
% label_main: 1=flat, 2=stall, 3=slope
% label_slip:  0=normal, 1=slip
lbl_main = label_vec(1);
lbl_slip  = label_vec(2);

% --- stall 非对称迟滞滤波（解决 2↔3 快速切换导致约束抖动的问题）---
% 问题根因：Mamba 在坡道爬坡时 label_main 每 0.05s 在 2(stall)↔3(slope) 之间切换，
%   导致 UpdatePlantModel 对 umin/umax 每 5 步交替放宽/还原，MPC 求解状态抖动。
% 修复：非对称迟滞滤波（ON 阈值小、OFF 阈值大）
%   - 需要连续 20 步 (0.2s) 检测到 stall 才激活（防误判干扰 MPC）
%   - 需要连续 50 步 (0.5s) 未检测到 stall 才退出（防止进/出护振荡）
STALL_ON_THRESH  = 20;
STALL_OFF_THRESH = 50;

if lbl_main == 2
    stall_on_cnt  = stall_on_cnt + 1;
    stall_off_cnt = 0;
    if stall_on_cnt >= STALL_ON_THRESH
        stall_on = true;
    end
else
    stall_off_cnt = stall_off_cnt + 1;
    stall_on_cnt  = 0;
    if stall_off_cnt >= STALL_OFF_THRESH
        stall_on = false;
    end
end

% 稳定化后的有效判断标志
lbl_main_eff = lbl_main;
if stall_on
    lbl_main_eff = 2;  % 持续保持 stall 激活（stall 优先级最高）
end

% --- slope 非对称迟滞滤波（防止 slope(3)↔flat(1) 高频切换）---
% 问题根因：Mamba 在坡道入/出边界处 label_main 在 1(flat)↔3(slope) 间高频跳变，
%   导致下游消费者（约束调度、scope 显示）收到噪声信号，引起 e_omega 脉冲尖峰。
% 参数选择：slope 比 stall 更保守（OFF 阈值更大），坡道行驶时间较长，
%   错误延迟退出坡道判断的代价低于错误进入坡道判断。
SLOPE_ON_THRESH  = 30;   % 连续 30 步 (0.3s) 检测到 slope 才激活
SLOPE_OFF_THRESH = 80;   % 连续 80 步 (0.8s) 未检测到 slope 才退出

if lbl_main == 3
    slope_on_cnt  = slope_on_cnt + 1;
    slope_off_cnt = 0;
    if slope_on_cnt >= SLOPE_ON_THRESH
        slope_on = true;
    end
else
    slope_off_cnt = slope_off_cnt + 1;
    slope_on_cnt  = 0;
    if slope_off_cnt >= SLOPE_OFF_THRESH
        slope_on = false;
    end
end

% slope 迟滞仅在非 stall 状态下覆盖（stall 优先级更高）
if slope_on && lbl_main_eff == 1
    lbl_main_eff = 3;  % 维持 slope 激活，消除 flat 瞬间误判
end

% --- 堵转（stall）：放宽驱动力上下界，防止 AGV 被困时 MPC 无法输出足够力 ---
% 堵转时摩擦力骤增（外部阻力远超正常值），若约束不放宽 MPC 将持续求解失败
if lbl_main_eff == 2
    stall_f_scale = 1.4;  % F_cmd 约束放宽到 140%
    upd.umin(1) = upd.umin(1) * stall_f_scale;
    upd.umax(1) = upd.umax(1) * stall_f_scale;
end

% --- 打滑（slip）：降低最大驱动力，通过减少驱动扭矩使轮胎恢复牵引力 ---
% 理论依据：轮胎打滑时纵向力已过峰值，继续施力只会增大滑移率
if lbl_slip == 1
    slip_f_scale = 0.65;  % F_cmd 上限降低到 65%
    upd.umax(1) = upd.umax(1) * slip_f_scale;
    % 放宽速度跟踪权重（Q 索引 3 = q_v），允许 AGV 自然减速
    upd.Q(3) = upd.Q(3) * 0.5;
end

%% ==================== 组装 plant（带 Nominal 前馈） ====================
nx = size(upd.A, 1);
ny = size(upd.C, 1);

plant.A = upd.A;

hasE = isfield(upd, 'E') && ~isempty(upd.E);
if hasE
    E_col = upd.E;
else
    E_col = zeros(nx, 1);
end

plant.B = [upd.B, E_col];
plant.C = upd.C;
plant.D = [upd.D, zeros(ny,1)];

% 重力 + 滚阻前馈
m_agv    = ff_rt.m;
g_acc    = ff_rt.g;
c_roll   = ff_rt.c_r;
theta_meas = rho(3);

F_eq = m_agv * g_acc * (sin(theta_meas) + c_roll * cos(theta_meas));

% Nominal: [MV1; MV2; MD]，与 LPV 线性化 u0=[F_eq; omega_ref] 对齐
plant.U  = [F_eq; rho_upd(2); theta_meas];
plant.X  = zeros(nx,1);
plant.Y  = zeros(ny,1);
plant.DX = zeros(nx,1);
plant.Ts = db_rt.Ts;

%% ==================== 输出给 MPC ====================
y_wt  = upd.Q(:);
u_wt  = upd.R(:);
du_wt = upd.dR(:);

ecr_wt = 1e4;
umin = upd.umin(:);
umax = upd.umax(:);

end

function maps_out = local_apply_runtime_maps_from_base(maps_in)
maps_out = maps_in;
coder.extrinsic('evalin');
if coder.target('MATLAB')
    try
        has_maps = evalin('base', 'exist(''mpc_runtime_maps'', ''var'')==1');
    catch
        has_maps = false;
    end
    if has_maps
        try
            runtime_maps = evalin('base', 'mpc_runtime_maps');
            maps_out = local_apply_runtime_maps_struct(maps_out, runtime_maps);
        catch
            % Keep the P0 default maps if the diagnostic maps are malformed.
        end
    end
end
end

function maps_out = local_apply_runtime_scalar_maps_from_base(maps_in)
maps_out = maps_in;
coder.extrinsic('evalin');

has_enable_weight_interp = coder.const(evalin('base', 'exist(''mpc_runtime_enable_weight_interp'', ''var'')==1'));
if has_enable_weight_interp
    maps_out.enable_weight_interp = coder.const(evalin('base', 'logical(mpc_runtime_enable_weight_interp)'));
end

has_Q_range = coder.const(evalin('base', 'exist(''mpc_runtime_Q_range'', ''var'')==1'));
if has_Q_range
    maps_out.Q_range = coder.const(evalin('base', 'double(mpc_runtime_Q_range)'));
end

has_R_range = coder.const(evalin('base', 'exist(''mpc_runtime_R_range'', ''var'')==1'));
if has_R_range
    maps_out.R_range = coder.const(evalin('base', 'double(mpc_runtime_R_range)'));
end

has_dR_range = coder.const(evalin('base', 'exist(''mpc_runtime_dR_range'', ''var'')==1'));
if has_dR_range
    maps_out.dR_range = coder.const(evalin('base', 'double(mpc_runtime_dR_range)'));
end

has_alpha_Q = coder.const(evalin('base', 'exist(''mpc_runtime_alpha_Q'', ''var'')==1'));
if has_alpha_Q
    maps_out.alpha_Q = coder.const(evalin('base', 'double(mpc_runtime_alpha_Q)'));
end

has_beta_Q = coder.const(evalin('base', 'exist(''mpc_runtime_beta_Q'', ''var'')==1'));
if has_beta_Q
    maps_out.beta_Q = coder.const(evalin('base', 'double(mpc_runtime_beta_Q)'));
end

has_alpha_R = coder.const(evalin('base', 'exist(''mpc_runtime_alpha_R'', ''var'')==1'));
if has_alpha_R
    maps_out.alpha_R = coder.const(evalin('base', 'double(mpc_runtime_alpha_R)'));
end

has_beta_R = coder.const(evalin('base', 'exist(''mpc_runtime_beta_R'', ''var'')==1'));
if has_beta_R
    maps_out.beta_R = coder.const(evalin('base', 'double(mpc_runtime_beta_R)'));
end

has_alpha_dR = coder.const(evalin('base', 'exist(''mpc_runtime_alpha_dR'', ''var'')==1'));
if has_alpha_dR
    maps_out.alpha_dR = coder.const(evalin('base', 'double(mpc_runtime_alpha_dR)'));
end

has_beta_dR = coder.const(evalin('base', 'exist(''mpc_runtime_beta_dR'', ''var'')==1'));
if has_beta_dR
    maps_out.beta_dR = coder.const(evalin('base', 'double(mpc_runtime_beta_dR)'));
end

has_scale_umin_lo = coder.const(evalin('base', 'exist(''mpc_runtime_scale_umin_lo'', ''var'')==1'));
if has_scale_umin_lo
    maps_out.scale_umin_lo = coder.const(evalin('base', 'double(mpc_runtime_scale_umin_lo)'));
end

has_scale_umin_hi = coder.const(evalin('base', 'exist(''mpc_runtime_scale_umin_hi'', ''var'')==1'));
if has_scale_umin_hi
    maps_out.scale_umin_hi = coder.const(evalin('base', 'double(mpc_runtime_scale_umin_hi)'));
end

has_scale_umax_lo = coder.const(evalin('base', 'exist(''mpc_runtime_scale_umax_lo'', ''var'')==1'));
if has_scale_umax_lo
    maps_out.scale_umax_lo = coder.const(evalin('base', 'double(mpc_runtime_scale_umax_lo)'));
end

has_scale_umax_hi = coder.const(evalin('base', 'exist(''mpc_runtime_scale_umax_hi'', ''var'')==1'));
if has_scale_umax_hi
    maps_out.scale_umax_hi = coder.const(evalin('base', 'double(mpc_runtime_scale_umax_hi)'));
end

has_rho_min = coder.const(evalin('base', 'exist(''mpc_runtime_rho_min'', ''var'')==1'));
if has_rho_min
    maps_out.rho_min = coder.const(evalin('base', 'double(mpc_runtime_rho_min)'));
end

has_rho_max = coder.const(evalin('base', 'exist(''mpc_runtime_rho_max'', ''var'')==1'));
if has_rho_max
    maps_out.rho_max = coder.const(evalin('base', 'double(mpc_runtime_rho_max)'));
end

has_tau = coder.const(evalin('base', 'exist(''mpc_runtime_tau'', ''var'')==1'));
if has_tau
    maps_out.tau = coder.const(evalin('base', 'double(mpc_runtime_tau)'));
end

has_omega_threshold = coder.const(evalin('base', 'exist(''mpc_runtime_omega_threshold'', ''var'')==1'));
if has_omega_threshold
    maps_out.omega_threshold = coder.const(evalin('base', 'double(mpc_runtime_omega_threshold)'));
end

has_q_y_gain_max = coder.const(evalin('base', 'exist(''mpc_runtime_q_y_gain_max'', ''var'')==1'));
if has_q_y_gain_max
    maps_out.q_y_gain_max = coder.const(evalin('base', 'double(mpc_runtime_q_y_gain_max)'));
end

has_transition_width = coder.const(evalin('base', 'exist(''mpc_runtime_transition_width'', ''var'')==1'));
if has_transition_width
    maps_out.transition_width = coder.const(evalin('base', 'double(mpc_runtime_transition_width)'));
end

has_theta_threshold = coder.const(evalin('base', 'exist(''mpc_runtime_theta_threshold'', ''var'')==1'));
if has_theta_threshold
    maps_out.theta_threshold = coder.const(evalin('base', 'double(mpc_runtime_theta_threshold)'));
end

has_q_v_gain_max = coder.const(evalin('base', 'exist(''mpc_runtime_q_v_gain_max'', ''var'')==1'));
if has_q_v_gain_max
    maps_out.q_v_gain_max = coder.const(evalin('base', 'double(mpc_runtime_q_v_gain_max)'));
end

has_theta_transition_width = coder.const(evalin('base', 'exist(''mpc_runtime_theta_transition_width'', ''var'')==1'));
if has_theta_transition_width
    maps_out.theta_transition_width = coder.const(evalin('base', 'double(mpc_runtime_theta_transition_width)'));
end

has_R_F_gain_max_uphill = coder.const(evalin('base', 'exist(''mpc_runtime_R_F_gain_max_uphill'', ''var'')==1'));
if has_R_F_gain_max_uphill
    maps_out.R_F_gain_max_uphill = coder.const(evalin('base', 'double(mpc_runtime_R_F_gain_max_uphill)'));
end

has_R_F_gain_max_downhill = coder.const(evalin('base', 'exist(''mpc_runtime_R_F_gain_max_downhill'', ''var'')==1'));
if has_R_F_gain_max_downhill
    maps_out.R_F_gain_max_downhill = coder.const(evalin('base', 'double(mpc_runtime_R_F_gain_max_downhill)'));
end

has_dR_F_gain_max_uphill = coder.const(evalin('base', 'exist(''mpc_runtime_dR_F_gain_max_uphill'', ''var'')==1'));
if has_dR_F_gain_max_uphill
    maps_out.dR_F_gain_max_uphill = coder.const(evalin('base', 'double(mpc_runtime_dR_F_gain_max_uphill)'));
end

has_dR_F_gain_max_downhill = coder.const(evalin('base', 'exist(''mpc_runtime_dR_F_gain_max_downhill'', ''var'')==1'));
if has_dR_F_gain_max_downhill
    maps_out.dR_F_gain_max_downhill = coder.const(evalin('base', 'double(mpc_runtime_dR_F_gain_max_downhill)'));
end

has_umin_range = coder.const(evalin('base', 'exist(''mpc_runtime_umin_range'', ''var'')==1'));
if has_umin_range
    maps_out.umin_range = coder.const(evalin('base', 'double(mpc_runtime_umin_range)'));
end

has_umax_range = coder.const(evalin('base', 'exist(''mpc_runtime_umax_range'', ''var'')==1'));
if has_umax_range
    maps_out.umax_range = coder.const(evalin('base', 'double(mpc_runtime_umax_range)'));
end
end

function maps_out = local_apply_runtime_override_from_base(maps_in, db_rt)
maps_out = maps_in;
coder.extrinsic('evalin');
if coder.target('MATLAB')
    try
        has_override = evalin('base', 'exist(''mpc_runtime_override'', ''var'')==1');
    catch
        has_override = false;
    end
    if has_override
        try
            runtime_override = evalin('base', 'mpc_runtime_override');
            maps_out = local_apply_runtime_override_maps(maps_out, runtime_override, db_rt);
        catch
            % Keep the P0 default maps if the diagnostic override is malformed.
        end
    end
else
    has_override = coder.const(evalin('base', 'exist(''mpc_runtime_override'', ''var'')==1'));
    if has_override
        % Simulink uses the runtime override through ctrl/mpcobj/maps in
        % SimulationInput. Keeping this branch structurally fixed avoids
        % MATLAB Function output-size inference failures from variable
        % candidate structs.
    end
end
end

function maps_out = local_apply_runtime_maps_struct(maps_in, runtime_maps)
maps_out = maps_in;
if isempty(runtime_maps) || ~isstruct(runtime_maps)
    return;
end

if isfield(runtime_maps, 'enable_weight_interp')
    maps_out.enable_weight_interp = logical(runtime_maps.enable_weight_interp);
end
if isfield(runtime_maps, 'Q_range')
    maps_out.Q_range = double(runtime_maps.Q_range);
end
if isfield(runtime_maps, 'R_range')
    maps_out.R_range = double(runtime_maps.R_range);
end
if isfield(runtime_maps, 'dR_range')
    maps_out.dR_range = double(runtime_maps.dR_range);
end
if isfield(runtime_maps, 'alpha_Q')
    maps_out.alpha_Q = double(runtime_maps.alpha_Q);
end
if isfield(runtime_maps, 'beta_Q')
    maps_out.beta_Q = double(runtime_maps.beta_Q);
end
if isfield(runtime_maps, 'alpha_R')
    maps_out.alpha_R = double(runtime_maps.alpha_R);
end
if isfield(runtime_maps, 'beta_R')
    maps_out.beta_R = double(runtime_maps.beta_R);
end
if isfield(runtime_maps, 'alpha_dR')
    maps_out.alpha_dR = double(runtime_maps.alpha_dR);
end
if isfield(runtime_maps, 'beta_dR')
    maps_out.beta_dR = double(runtime_maps.beta_dR);
end
if isfield(runtime_maps, 'scale_umin_lo')
    maps_out.scale_umin_lo = double(runtime_maps.scale_umin_lo);
end
if isfield(runtime_maps, 'scale_umin_hi')
    maps_out.scale_umin_hi = double(runtime_maps.scale_umin_hi);
end
if isfield(runtime_maps, 'scale_umax_lo')
    maps_out.scale_umax_lo = double(runtime_maps.scale_umax_lo);
end
if isfield(runtime_maps, 'scale_umax_hi')
    maps_out.scale_umax_hi = double(runtime_maps.scale_umax_hi);
end
if isfield(runtime_maps, 'rho_min')
    maps_out.rho_min = double(runtime_maps.rho_min);
end
if isfield(runtime_maps, 'rho_max')
    maps_out.rho_max = double(runtime_maps.rho_max);
end
if isfield(runtime_maps, 'tau')
    maps_out.tau = double(runtime_maps.tau);
end
if isfield(runtime_maps, 'omega_threshold')
    maps_out.omega_threshold = double(runtime_maps.omega_threshold);
end
if isfield(runtime_maps, 'q_y_gain_max')
    maps_out.q_y_gain_max = double(runtime_maps.q_y_gain_max);
end
if isfield(runtime_maps, 'transition_width')
    maps_out.transition_width = double(runtime_maps.transition_width);
end
if isfield(runtime_maps, 'theta_threshold')
    maps_out.theta_threshold = double(runtime_maps.theta_threshold);
end
if isfield(runtime_maps, 'q_v_gain_max')
    maps_out.q_v_gain_max = double(runtime_maps.q_v_gain_max);
end
if isfield(runtime_maps, 'theta_transition_width')
    maps_out.theta_transition_width = double(runtime_maps.theta_transition_width);
end
if isfield(runtime_maps, 'R_F_gain_max_uphill')
    maps_out.R_F_gain_max_uphill = double(runtime_maps.R_F_gain_max_uphill);
end
if isfield(runtime_maps, 'R_F_gain_max_downhill')
    maps_out.R_F_gain_max_downhill = double(runtime_maps.R_F_gain_max_downhill);
end
if isfield(runtime_maps, 'dR_F_gain_max_uphill')
    maps_out.dR_F_gain_max_uphill = double(runtime_maps.dR_F_gain_max_uphill);
end
if isfield(runtime_maps, 'dR_F_gain_max_downhill')
    maps_out.dR_F_gain_max_downhill = double(runtime_maps.dR_F_gain_max_downhill);
end
if isfield(runtime_maps, 'umin_range')
    maps_out.umin_range = double(runtime_maps.umin_range);
end
if isfield(runtime_maps, 'umax_range')
    maps_out.umax_range = double(runtime_maps.umax_range);
end
end

function maps_out = local_apply_runtime_override_maps(maps_in, runtime_override, db_rt)
maps_out = maps_in;
if isempty(runtime_override) || ~isstruct(runtime_override)
    return;
end

if isfield(runtime_override, 'maps_template') && isstruct(runtime_override.maps_template)
    maps_out = local_copy_codegen_safe_map_fields(maps_out, runtime_override.maps_template);
end

if isfield(runtime_override, 'Q') && ~isempty(runtime_override.Q)
    maps_out.Q_range = local_center_to_range(double(reshape(runtime_override.Q, 1, [])));
end
if isfield(runtime_override, 'R') && ~isempty(runtime_override.R)
    maps_out.R_range = local_center_to_range(double(reshape(runtime_override.R, 1, [])));
end
if isfield(runtime_override, 'dR') && ~isempty(runtime_override.dR)
    maps_out.dR_range = local_center_to_range(double(reshape(runtime_override.dR, 1, [])));
end

if nargin >= 3 && isstruct(db_rt) && isfield(db_rt, 'grid')
    maps_out.rho_min = [db_rt.grid.V(1); db_rt.grid.W(1); db_rt.grid.T(1)];
    maps_out.rho_max = [db_rt.grid.V(end); db_rt.grid.W(end); db_rt.grid.T(end)];
end
end

function maps_out = local_copy_codegen_safe_map_fields(maps_in, maps_template)
maps_out = maps_in;
fields = {'enable_weight_interp', 'Q_range', 'R_range', 'dR_range', ...
    'alpha_Q', 'beta_Q', 'alpha_R', 'beta_R', 'alpha_dR', 'beta_dR', ...
    'scale_umin_lo', 'scale_umin_hi', 'scale_umax_lo', 'scale_umax_hi', ...
    'rho_min', 'rho_max', 'tau', 'omega_threshold', 'q_y_gain_max', ...
    'transition_width', 'theta_threshold', 'q_v_gain_max', ...
    'theta_transition_width', 'R_F_gain_max_uphill', ...
    'R_F_gain_max_downhill', 'dR_F_gain_max_uphill', ...
    'dR_F_gain_max_downhill', 'umin_range', 'umax_range'};

for i = 1:numel(fields)
    name = fields{i};
    if ~isfield(maps_template, name)
        continue;
    end
    val = maps_template.(name);
    if islogical(val)
        maps_out.(name) = logical(val);
    elseif isnumeric(val)
        maps_out.(name) = double(val);
    end
end
end

function range = local_center_to_range(center)
range = [center * 0.5; center * 1.5];
end
