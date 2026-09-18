function [J, report] = Cost_Function(params, db, cfg, scenes)
% =============================
% 文件名：Cost_Function.m
% 版本号：V2.4
% 最后修改时间：2025-11-20
% 作者：LPV-MPC Project
% 功能描述：
%   复现 Adaptive MPC 闭环，输出加权代价 J 和详细报告
% 输入参数：
%   - params : parameters() 返回的结构体
%   - db     : LPV 数据库（允许为空，内部生成3×3×3默认网格）
%   - cfg    : 结构体，包含权重/范围/滤波/罚值/超参（可选字段见下）
%   - scenes : 结构体，场景权重（字段：turn/slope/straight_turn/bumpy/straight）
% 输出参数：
%   - J      : 总加权代价（若任一场景失败，J >= 1e6）
%   - report : 详细报告（各场景指标、RMSE、Δu、约束违反、求解时间统计、失败次数）
% 依赖：
%   - mpc_setup_single_interp.m / mpc_update_from_rho.m
%   - gen_agv_ref_path.m / state_eq_ref.m / output_eq_ref.m
% 备注：
%   - 统一ρ为有符号：rho=[v; omega; theta]
%   - 颠簸默认幅值 0.2 rad
%   - API 调用：[u, Info] = mpcmoveAdaptive(mpcobj, xmpc, plant_model, Nominal, y_meas, r_ref, md)
%     其中 plant_model 每步更新，Nominal.U 为 3×1（2 MV + 1 MD）
%   - 成功判定：Info.QPCode == 'feasible' 或 'optimal'
%   - V2.3更新：移除前馈力F_eq，MPC直接输出完整控制力（包含阻力补偿）
% =============================

%% 默认配置
if nargin < 4 || isempty(scenes)
    % 默认场景权重（共 5 个场景）
    scenes = struct('straight_left_turn',0.25,'straight_right_turn',0.25,...
                    'slope',0.15,'bumpy',0.20,'straight',0.15);
end
if nargin < 3 || isempty(cfg)
    cfg = struct();
end

if ~isfield(cfg,'tau'), cfg.tau = 0.4; end                    % ρ滤波时间常数
if ~isfield(cfg,'ey_max'), cfg.ey_max = 1.0; end              % 放宽以匹配 MPC 约束
if ~isfield(cfg,'epsi_max'), cfg.epsi_max = 0.5; end          % 放宽以匹配 MPC 约束
if ~isfield(cfg,'ev_max'), cfg.ev_max = 0.5; end
if ~isfield(cfg,'eomega_max'), cfg.eomega_max = 0.3; end
if ~isfield(cfg,'dF_max'), cfg.dF_max = 400; end
if ~isfield(cfg,'dw_max'), cfg.dw_max = 0.9; end  % 与实际 Δω 约束上界对齐（MV.RateMax=0.9，之前0.4高估平滑惩罚2.25倍）
if ~isfield(cfg,'w_ev'), cfg.w_ev = 0.45; end     % 上坡优先保速：提高速度误差项权重
if ~isfield(cfg,'stall_theta_th'), cfg.stall_theta_th = 0.03; end
if ~isfield(cfg,'stall_vref_th'), cfg.stall_vref_th = 0.30; end
if ~isfield(cfg,'stall_ratio_w'), cfg.stall_ratio_w = 2.0; end
if ~isfield(cfg,'stall_lowrate_w'), cfg.stall_lowrate_w = 1.5; end
if ~isfield(cfg,'debug'), cfg.debug = false; end
if ~isfield(cfg,'rethrow_scene_errors'), cfg.rethrow_scene_errors = false; end
if ~isfield(cfg,'store_trace'), cfg.store_trace = false; end

% 安全范围（log10 映射防止负权重）
clip = @(x,lo,hi) min(hi,max(lo,x));

%% LPV 数据库准备
if nargin < 2 || isempty(db)
    grid.V_grid = [0.8; 1.0; 1.2];
    grid.W_grid = [-0.2; 0.0; 0.2];      % 有符号 ω
    grid.T_grid = [-0.2; 0.0; 0.2];      % 颠簸幅值匹配 0.2 rad
    lin_opts = struct('coord','path','disc','zoh','keep_E',true,'export_mat','plant_grid.mat');
    db = lin_agv_grid(params, grid, lin_opts);
end

%% 控制器准备（优先使用传入的ctrl，避免重复创建）
if isfield(cfg, 'ctrl') && ~isempty(cfg.ctrl)
    % 使用传入的控制器（来自 Bayesian_Optimization）
    % 注意：cfg.ctrl 已经是独立副本（在 Bayesian_Optimization 中克隆）
    ctrl = cfg.ctrl;
else
    % 创建默认控制器（独立测试时）
    % 与 Simulink 实时入口保持一致：P0 oracle-MPC 候选 Np=150、Nc=30。
    ctrl = mpc_setup_single_interp(db, struct('Np',150,'Nc',30, ...
        'Q',[100, 100, 15, 3], 'R',[3e-5, 3e-5], 'dR',[1e-3, 1e-3]));
end

% 提取 mpcobj（注意：这是引用，后续修改会影响 ctrl.mpcobj）
mpcobj = ctrl.mpcobj;
Ts = db.Ts;

% 如果cfg中提供了maps覆盖，应用到ctrl.maps
% 注意：直接修改 ctrl.maps，但因为 ctrl 是独立副本，不会污染其他评估
if isfield(cfg,'ctrl_maps')
    fns = fieldnames(cfg.ctrl_maps);
    for i=1:numel(fns)
        ctrl.maps.(fns{i}) = cfg.ctrl_maps.(fns{i});
    end
end

% 离线复现器需要给 state_eq_ref 提供当前参考几何。Simulink 入口通过
% base workspace 中的 ref 时间序列完成这一契约；离线路径没有仿真时间，
% 因此在每个积分步注入标量 v_ref/omega_ref，避免转弯 ICR 回退到测量 omega。
inject_ref_for_state_eq = true;
if isfield(cfg, 'inject_ref_for_state_eq')
    inject_ref_for_state_eq = logical(cfg.inject_ref_for_state_eq);
end
had_base_ref = false;
old_base_ref = [];
if inject_ref_for_state_eq
    try
        had_base_ref = evalin('base', 'exist(''ref'', ''var'') ~= 0');
        if had_base_ref
            old_base_ref = evalin('base', 'ref');
        end
    catch
        had_base_ref = false;
    end
    ref_cleanup = onCleanup(@() local_restore_base_ref(had_base_ref, old_base_ref)); %#ok<NASGU>
end

% V2.3：已移除F_eq前馈，以下物理参数不再需要
% m = params.mass;
% g = params.gravity;
% c_r = params.rolling_resistance;
% rho_air = params.air_density;
% CdA = params.drag_coefficient_area;

%% 归一化端点（用于rho滤波初始化）
rho_min = [db.grid.V(1); db.grid.W(1); db.grid.T(1)];
rho_max = [db.grid.V(end); db.grid.W(end); db.grid.T(end)];

%% 场景列表（共 5 个场景）
%% 场景遍历（根据 scenes 结构体的键）
scene_names = fieldnames(scenes);
scene_count = numel(scene_names);

J_total = 0;
report = struct();
report.scene = struct();
report.fail_count = 0;
report.scene_order = scene_names;

% 若启用加载模式，预先加载完整路径
ref_full = [];
if isfield(cfg, 'path_file') && ~isempty(cfg.path_file)
    if exist(cfg.path_file, 'file')
        loaded_data = load(cfg.path_file);
        if isfield(loaded_data, 'ref')
            ref_full = loaded_data.ref;
            % 确保 ref_full 包含 rho (v, omega, theta)
            if ~isfield(ref_full, 'rho')
                % 兼容旧数据：尝试构建 rho
                ref_full.rho = [ref_full.v_ref, ref_full.omega_ref, ref_full.theta_ref];
            end
        else
            error('Cost_Function:InvalidFile', '路径文件 %s 中未找到 ref 变量', cfg.path_file);
        end
    else
        error('Cost_Function:FileNotFound', '未找到路径文件: %s', cfg.path_file);
    end
end

for s = 1:scene_count
    name = scene_names{s};
    weight_s = scenes.(name);
    
    % 跳过权重为0的场景（节省计算）
    if weight_s <= 0
        continue;
    end

    try
        % === 路径获取逻辑 ===
        if ~isempty(ref_full)
            % [加载模式] 从完整路径切片
            if isfield(cfg, 'zones') && isfield(cfg.zones, name)
                t_range = cfg.zones.(name); % [t_start, t_end]
                
                % 找到时间索引
                idx_mask = (ref_full.t >= t_range(1)) & (ref_full.t < t_range(2));
                if ~any(idx_mask)
                    error('Cost_Function:InvalidZone', '场景 %s 的时间范围 [%.1f, %.1f] 在路径中无数据', ...
                        name, t_range(1), t_range(2));
                end
                
                % 切片函数（本地实现或内联）
                ref = struct();
                fields = fieldnames(ref_full);
                for f = 1:length(fields)
                    fn = fields{f};
                    val = ref_full.(fn);
                    if size(val,1) == length(ref_full.t)
                        ref.(fn) = val(idx_mask, :);
                    else
                        ref.(fn) = val; % 元数据等不切片
                    end
                end
                
                % 重置时间向量从0开始（可选，但为了绘图对应可能更好保留绝对时间？）
                % MPC控制器只关心 dt，绝对时间不影响逻辑
                % 但为了 debug，保留绝对时间 t
                
            else
                error('Cost_Function:ZoneNotDefined', '加载模式下未定义场景 %s 的时间范围(cfg.zones)', name);
            end
            
            % [关键] 初始化状态 x0
            % 使用切片起点的参考值初始化 (假设完美跟踪)
            % x_plant = [X Y psi v omega delta_lf delta_rr beta]
            % 注意：path文件通常不包含 delta/beta，设为0或基于运动学估算
            x0_X = ref.X_ref(1);
            x0_Y = ref.Y_ref(1);
            x0_psi = ref.psi_ref(1);
            x0_v = ref.v_ref(1);
            x0_omega = ref.omega_ref(1);
            
            % 运动学估算转向角 delta = atan(omega * L / max(v, 0.05))
            % 原来直接置0将导致转弯区切片仓真开始时控制器需要悟然建立转向角而产生初始跳变
            if isfield(params,'L') && abs(x0_v) > 0.05
                x0_delta = atan(x0_omega * params.L / x0_v);
            else
                x0_delta = 0;
            end
            x0_beta = 0;  % 质心角不含在路径文件中，保持为0
            
            x_plant = [x0_X; x0_Y; x0_psi; x0_v; x0_omega; x0_delta; x0_delta; x0_beta];
            
        else
            % [生成模式] (Legacy) 调用生成函数
            ref = gen_agv_ref_path(name, params, struct('T_end',120));
            
            % 默认初始状态 (0时刻)
            x_plant = [params.initial_x; params.initial_y; params.initial_heading; ...
                   params.initial_velocity; params.initial_angular_velocity; ...
                   params.initial_front_steering; params.initial_rear_steering; ...
                   params.initial_sideslip];
        end
        
        N = numel(ref.t);

        % MPC状态初始化
        xmpc = mpcstate(mpcobj);

        % 统计量
        ey = zeros(N,1); epsi = zeros(N,1); ev = zeros(N,1); eomega = zeros(N,1);
        u_hist = zeros(N,2); du_hist = zeros(N,2);
        sat_omega = false(N,1);
        solve_ms = zeros(N,1);
        cons_violation = zeros(N,1);
        if cfg.store_trace
            trace = struct();
            trace.t = ref.t(:);
            trace.X = zeros(N,1);
            trace.Y = zeros(N,1);
            trace.psi = zeros(N,1);
            trace.v = zeros(N,1);
            trace.omega = zeros(N,1);
            trace.delta_lf = zeros(N,1);
            trace.delta_rr = zeros(N,1);
            trace.beta = zeros(N,1);
            trace.X_ref = ref.X_ref(:);
            trace.Y_ref = ref.Y_ref(:);
            trace.psi_ref = ref.psi_ref(:);
            trace.v_ref = ref.v_ref(:);
            trace.omega_ref = ref.omega_ref(:);
            trace.theta_ref = ref.theta_ref(:);
            trace.e_y = zeros(N,1);
            trace.e_psi = zeros(N,1);
            trace.e_v = zeros(N,1);
            trace.e_omega = zeros(N,1);
            trace.F_cmd = zeros(N,1);
            trace.omega_cmd = zeros(N,1);
            trace.rho_f = zeros(N,3);
            trace.Nominal_U = zeros(N,3);
            trace.cons_violation = zeros(N,1);
            trace.solve_ms = zeros(N,1);
        else
            trace = [];
        end

        u_prev = [0; 0];
        rho_prev = [ref.v_ref(1); ref.omega_ref(1); ref.theta_ref(1)];
        fail_scene = false;
        first_fail_step = NaN;
        first_fail_reason = '';
        first_fail_qpcode = '';

        for k = 1:N
            %% 1. 从8维状态计算4维路径坐标系误差
            X = x_plant(1); Y = x_plant(2); psi = x_plant(3);
            v = x_plant(4); omega = x_plant(5);
            
            X_ref = ref.X_ref(k); Y_ref = ref.Y_ref(k); psi_ref = ref.psi_ref(k);
            v_ref = ref.v_ref(k); omega_ref = ref.omega_ref(k);
            
            % 全局误差
            ex = X - X_ref;
            ey_global = Y - Y_ref;
            
            % 路径坐标系误差（Frenet坐标转换）
            e_y = -sin(psi_ref)*ex + cos(psi_ref)*ey_global;
            e_psi = wrapToPi(psi - psi_ref);
            e_v = v - v_ref;
            e_omega = omega - omega_ref;
            
            y_meas = [e_y; e_psi; e_v; e_omega];
            
            %% 2. 参考轨迹（误差期望为零）
            r_ref = [0; 0; 0; 0];
            
            %% 3. 测量扰动（坡度角）
            theta_meas = ref.theta_ref(k);
            md = theta_meas;
            
            %% 4. 组装 rho（有符号）并一阶滤波
            rho_cur = [v_ref; omega_ref; theta_meas];
            rho_filter_alpha = Ts / (Ts + cfg.tau);
            rho_f = rho_filter_alpha * rho_cur + (1-rho_filter_alpha) * rho_prev;
            rho_prev = rho_f;
            
            %% 5. 在线插值模型与权重/约束
            upd = mpc_update_from_rho(rho_f, db, ctrl.maps);
            
            % 构造更新后的植物模型（离散状态空间）
            % B矩阵包含 [2个MV列, 1个MD列]
            B_updated = [upd.B, upd.E];  % [4×2] + [4×1] = [4×3]
            D_updated = [upd.D, zeros(4,1)];  % [4×2] + [4×1] = [4×3]
            
            plant_model = ss(upd.A, B_updated, upd.C, D_updated, Ts);
            
            % 构造 Nominal 结构体（工作点，所有为零 = 误差坐标系）
            Nominal = struct();
            Nominal.X = zeros(4,1);   % 状态工作点
            Nominal.Y = zeros(4,1);   % 输出工作点
            Nominal.DX = zeros(4,1);  % 状态导数工作点
            
            % 输入工作点：重力/滚阻补偿和参考角速度前馈。
            % LPV库在 u0=[F_eq; omega_ref] 附近线性化，Adaptive MPC 的
            % Nominal.U 也必须使用同一输入工作点，否则转弯时会丢失
            % omega_cmd 的名义分量，只靠反馈硬追。
            m_agv = params.mass; c_r = params.rolling_resistance; g = params.gravity;
            F_eq = m_agv * g * (sin(md) + c_r * cos(md)); 
            
            Nominal.U = zeros(3,1);   % （2 MV + 1 MD）
            Nominal.U(1) = F_eq;
            if ~isfield(cfg, 'use_omega_nominal') || cfg.use_omega_nominal
                Nominal.U(2) = rho_f(2);
            end
            Nominal.U(3) = md;
            
            % 更新权重（通过修改 mpcobj 属性）
            mpcobj.Weights.OutputVariables = upd.Q;
            mpcobj.Weights.ManipulatedVariables = upd.R;
            mpcobj.Weights.ManipulatedVariablesRate = upd.dR;
            
            % 更新约束
            mpcobj.MV(1).Min = upd.umin(1); mpcobj.MV(1).Max = upd.umax(1);
            mpcobj.MV(2).Min = upd.umin(2); mpcobj.MV(2).Max = upd.umax(2);
            
            %% 6. MPC求解（mpcmoveAdaptive）
            % V2.3：移除F_eq前馈，MPC直接输出完整控制力
            % 使用 evalc 捕获并抑制所有输出（包括 fprintf/disp）
            tic;
            evalc('[u_mpc, Info] = mpcmoveAdaptive(mpcobj, xmpc, plant_model, Nominal, y_meas, r_ref, md);');
            solve_time = toc * 1000;  % ms
            
            % V2.3：直接使用MPC输出，不再叠加前馈力
            u = u_mpc;
            
            %% 8. 检查求解状态
            % 使用 Info.QPCode 判定成功（字符串 'feasible' 或 'optimal'）
            if isfield(Info, 'QPCode')
                qp_success = strcmpi(Info.QPCode, 'feasible') || strcmpi(Info.QPCode, 'optimal');
                if ~qp_success
                    fail_scene = true;
                    first_fail_step = k;
                    first_fail_reason = 'QP solver did not report feasible/optimal';
                    first_fail_qpcode = char(string(Info.QPCode));
                    if cfg.debug
                        fprintf('  [DEBUG] 步%d: QPCode=%s, 求解失败\n', k, Info.QPCode);
                        fprintf('         rho=[%.3f, %.5f, %.5f]\n', rho_f(1), rho_f(2), rho_f(3));
                        fprintf('         y_meas=[%.5f, %.5f, %.5f, %.5f]\n', ...
                            y_meas(1), y_meas(2), y_meas(3), y_meas(4));
                    end
                    break;
                end
            else
                % 回退：若无 QPCode，检查 Cost 是否为有限值
                if ~isfield(Info, 'Cost') || ~isfinite(Info.Cost)
                    fail_scene = true;
                    first_fail_step = k;
                    first_fail_reason = 'MPC move returned no finite cost';
                    first_fail_qpcode = 'missing_or_nonfinite_cost';
                    if cfg.debug
                        fprintf('  [DEBUG] 步%d: 无有效 Info 字段，求解失败\n', k);
                    end
                    break;
                end
            end
            
            %% 9. 约束违反检查
            cons_viol = 0;
            % 输出约束
            if abs(e_y) > cfg.ey_max + 1e-6, cons_viol = cons_viol + abs(e_y) - cfg.ey_max; end
            if abs(e_psi) > cfg.epsi_max + 1e-6, cons_viol = cons_viol + abs(e_psi) - cfg.epsi_max; end
            % MV约束（检查是否命中边界）
            if abs(u(1)) > abs(mpcobj.MV(1).Max) + 1e-6, cons_viol = cons_viol + abs(u(1)) - abs(mpcobj.MV(1).Max); end
            if abs(u(2)) > abs(mpcobj.MV(2).Max) + 1e-6, cons_viol = cons_viol + abs(u(2)) - abs(mpcobj.MV(2).Max); end
            sat_omega(k) = abs(u(2)) >= (abs(mpcobj.MV(2).Max) - 1e-6);
            
            %% 10. 推进Plant状态（使用state_eq_ref）
            x_trace = x_plant;
            if inject_ref_for_state_eq
                ref_step = struct('v_ref', v_ref, 'omega_ref', omega_ref);
                assignin('base', 'ref', ref_step);
            end
            x_plant = state_eq_ref(x_plant, u, theta_meas, params);
            
            %% 11. 记录
            ey(k) = e_y; epsi(k) = e_psi; ev(k) = e_v; eomega(k) = e_omega;
            u_hist(k,:) = u.';
            du_hist(k,:) = (u - u_prev).';
            if cfg.store_trace
                trace.X(k) = X;
                trace.Y(k) = Y;
                trace.psi(k) = psi;
                trace.v(k) = v;
                trace.omega(k) = omega;
                trace.delta_lf(k) = x_trace(6);
                trace.delta_rr(k) = x_trace(7);
                trace.beta(k) = x_trace(8);
                trace.e_y(k) = e_y;
                trace.e_psi(k) = e_psi;
                trace.e_v(k) = e_v;
                trace.e_omega(k) = e_omega;
                trace.F_cmd(k) = u(1);
                trace.omega_cmd(k) = u(2);
                trace.rho_f(k,:) = rho_f.';
                trace.Nominal_U(k,:) = Nominal.U.';
                trace.cons_violation(k) = cons_viol;
                trace.solve_ms(k) = solve_time;
            end
            u_prev = u;
            solve_ms(k) = solve_time;
            cons_violation(k) = cons_viol;
            
            %% 12. 失败判定
            if any(~isfinite([e_y, e_psi, e_v, e_omega])) || any(~isfinite(u))
                fail_scene = true;
                if isnan(first_fail_step)
                    first_fail_step = k;
                    first_fail_reason = 'Non-finite closed-loop signal';
                    first_fail_qpcode = 'nonfinite_signal';
                end
                break;
            end
        end

        % 代价计算
        RMSE = @(z) sqrt(mean(z.^2)); RMS = @(z) sqrt(mean(z.^2));
        J_trk = 1.1*RMSE(ey)/cfg.ey_max + 1.0*RMSE(epsi)/cfg.epsi_max + 0.2*RMSE(eomega)/cfg.eomega_max + cfg.w_ev*RMSE(ev)/cfg.ev_max;
        J_smooth = 0.08*RMS(du_hist(:,1))/cfg.dF_max + 0.07*RMS(du_hist(:,2))/cfg.dw_max;

        % 上坡防停车惩罚：抑制“少出力换低R代价”的伪最优
        theta_seg = ref.theta_ref(1:N);
        v_ref_seg = ref.v_ref(1:N);
        v_act_seg = ev + v_ref_seg;
        uphill_mask = (theta_seg > cfg.stall_theta_th) & (v_ref_seg > cfg.stall_vref_th);
        if any(uphill_mask)
            v_ref_up = v_ref_seg(uphill_mask);
            v_act_up = v_act_seg(uphill_mask);
            stall_ratio = mean(max(0, v_ref_up - v_act_up) ./ max(v_ref_up, 0.2));
            low_speed_rate = mean(v_act_up < 0.5 * v_ref_up);
        else
            stall_ratio = 0.0;
            low_speed_rate = 0.0;
        end
        J_stall = cfg.stall_ratio_w * stall_ratio + cfg.stall_lowrate_w * low_speed_rate;

        % 转向饱和率惩罚（鼓励减少omega_cmd打限）
        sat_rate = mean(sat_omega);
        J_sat = 8.0 * sat_rate;

        % 约束惩罚（L1/L∞ 混合）
        L1 = mean(abs(cons_violation)); Linf = max(abs(cons_violation));
        J_cons = 10*L1 + 50*Linf;

        % 实时惩罚
        avg_ms = mean(solve_ms); max_ms = max(solve_ms);
        J_rt = max(0, (avg_ms - 5.0)/5.0) + (max_ms > 10.0)*0.5;

        J_scene = J_trk + J_smooth + J_cons + J_rt + J_sat + J_stall;

        if fail_scene
            J_scene = 1e6; report.fail_count = report.fail_count + 1; end

        J_total = J_total + weight_s * J_scene;

        % 报告
        valid_n = find(solve_ms > 0, 1, 'last');
        if isempty(valid_n)
            valid_n = 0;
        end
        if valid_n > 0
            u_valid = u_hist(1:valid_n, :);
            du_valid = du_hist(1:valid_n, :);
            ey_valid = ey(1:valid_n);
            epsi_valid = epsi(1:valid_n);
            ev_valid = ev(1:valid_n);
            eomega_valid = eomega(1:valid_n);
            cons_valid = cons_violation(1:valid_n);
            F_limit = max(abs([mpcobj.MV(1).Min, mpcobj.MV(1).Max]));
            omega_limit = max(abs([mpcobj.MV(2).Min, mpcobj.MV(2).Max]));
            F_peak = max(abs(u_valid(:, 1)));
            omega_peak = max(abs(u_valid(:, 2)));
            F_sat_rate = mean(abs(u_valid(:, 1)) >= (F_limit - 1e-6));
            omega_sat_rate = mean(abs(u_valid(:, 2)) >= (omega_limit - 1e-6));
            dF_peak = max(abs(du_valid(:, 1)));
            domega_peak = max(abs(du_valid(:, 2)));
            ey_peak = max(abs(ey_valid));
            epsi_peak = max(abs(epsi_valid));
            ev_peak = max(abs(ev_valid));
            eomega_peak = max(abs(eomega_valid));
            cons_violation_rate = mean(cons_valid > 1e-9);
        else
            F_limit = max(abs([mpcobj.MV(1).Min, mpcobj.MV(1).Max]));
            omega_limit = max(abs([mpcobj.MV(2).Min, mpcobj.MV(2).Max]));
            F_peak = NaN;
            omega_peak = NaN;
            F_sat_rate = NaN;
            omega_sat_rate = NaN;
            dF_peak = NaN;
            domega_peak = NaN;
            ey_peak = NaN;
            epsi_peak = NaN;
            ev_peak = NaN;
            eomega_peak = NaN;
            cons_violation_rate = NaN;
        end
        rep = struct();
        rep.RMSE = struct('ey',RMSE(ey),'epsi',RMSE(epsi),'ev',RMSE(ev),'eomega',RMSE(eomega));
        rep.RMS_du = struct('dF',RMS(du_hist(:,1)),'dw',RMS(du_hist(:,2)));
        rep.peak = struct('ey',ey_peak,'epsi',epsi_peak,'ev',ev_peak,'eomega',eomega_peak);
        rep.cons = struct('L1',L1,'Linf',Linf,'violation_rate',cons_violation_rate);
        rep.sat = struct('omega_rate',sat_rate);
        rep.control = struct('valid_steps',valid_n,'F_peak',F_peak,'omega_peak',omega_peak, ...
            'F_sat_rate',F_sat_rate,'omega_sat_rate',omega_sat_rate, ...
            'F_limit',F_limit,'omega_limit',omega_limit, ...
            'dF_peak',dF_peak,'domega_peak',domega_peak);
        rep.steps = struct('total',N,'valid',valid_n,'completion_ratio',valid_n / max(N, 1), ...
            'first_fail_step',first_fail_step,'first_fail_reason',first_fail_reason, ...
            'first_fail_qpcode',first_fail_qpcode);
        rep.stall = struct('ratio',stall_ratio,'low_speed_rate',low_speed_rate,'J_stall',J_stall);
        rep.solve_ms = struct('avg',avg_ms,'max',max_ms);
        rep.failed = fail_scene;
        if cfg.store_trace
            rep.trace = local_trim_trace(trace, valid_n);
        end
        if isfield(cfg, 'report_zones') && isstruct(cfg.report_zones)
            rep.zones = local_zone_metrics(cfg.report_zones, ref.t(:), valid_n, ...
                ey, epsi, ev, eomega, cons_violation, u_hist);
        else
            rep.zones = struct();
        end
        report.scene.(name) = rep;

    catch ME
        if cfg.rethrow_scene_errors
            rethrow(ME);
        end
        % 场景失败：记大罚，不中断其它场景
        J_total = J_total + weight_s * 1e6;
        report.fail_count = report.fail_count + 1;
        report.scene.(name) = struct('error',ME.message,'failed',true);
    end
end

J = J_total;

% 总体失败标记（只要有一个场景失败即置位）
report.failed = report.fail_count > 0;
report.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');

% 可选落盘（使用 results_dir 统一输出路径）
if isfield(cfg,'save_report') && cfg.save_report
    report_dir = results_dir('bo_reports');
    save(fullfile(report_dir, sprintf('bo_report_%s.mat',datestr(now,'yyyymmdd_HHMMSS'))),'J','report');
end

end

function zones = local_zone_metrics(zone_spec, t, valid_n, ey, epsi, ev, eomega, cons_violation, u_hist)
zones = struct();
zone_names = fieldnames(zone_spec);
valid_mask = false(size(t));
valid_mask(1:min(valid_n, numel(t))) = true;

for i = 1:numel(zone_names)
    name = zone_names{i};
    range = zone_spec.(name);
    if numel(range) < 2
        continue;
    end
    mask = valid_mask & t >= range(1) & t < range(2);
    if nnz(mask) < 1
        row = local_empty_zone_metric(range);
    else
        row = struct();
        row.t0 = range(1);
        row.t1 = range(2);
        row.n_samples = nnz(mask);
        row.ey_rmse = local_rms(ey(mask));
        row.ey_peak = max(abs(ey(mask)));
        row.epsi_rmse = local_rms(epsi(mask));
        row.epsi_peak = max(abs(epsi(mask)));
        row.ev_rmse = local_rms(ev(mask));
        row.ev_peak = max(abs(ev(mask)));
        row.eomega_rmse = local_rms(eomega(mask));
        row.eomega_peak = max(abs(eomega(mask)));
        row.cons_Linf = max(abs(cons_violation(mask)));
        row.cons_violation_rate = mean(cons_violation(mask) > 1e-9);
        row.F_peak = max(abs(u_hist(mask, 1)));
        row.omega_peak = max(abs(u_hist(mask, 2)));
    end
    zones.(matlab.lang.makeValidName(name)) = row;
end
end

function row = local_empty_zone_metric(range)
row = struct();
row.t0 = range(1);
row.t1 = range(2);
row.n_samples = 0;
row.ey_rmse = NaN;
row.ey_peak = NaN;
row.epsi_rmse = NaN;
row.epsi_peak = NaN;
row.ev_rmse = NaN;
row.ev_peak = NaN;
row.eomega_rmse = NaN;
row.eomega_peak = NaN;
row.cons_Linf = NaN;
row.cons_violation_rate = NaN;
row.F_peak = NaN;
row.omega_peak = NaN;
end

function trace = local_trim_trace(trace, valid_n)
if isempty(trace) || valid_n <= 0
    return;
end
fields = fieldnames(trace);
for i = 1:numel(fields)
    value = trace.(fields{i});
    if isnumeric(value) && size(value, 1) >= valid_n
        trace.(fields{i}) = value(1:valid_n, :);
    end
end
end

function y = local_rms(x)
if isempty(x)
    y = NaN;
else
    y = sqrt(mean(x(:).^2));
end
end

function local_restore_base_ref(had_ref, old_ref)
try
    if had_ref
        assignin('base', 'ref', old_ref);
    else
        evalin('base', 'clear ref');
    end
catch
end
end
