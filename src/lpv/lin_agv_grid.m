function db = lin_agv_grid(params, grid, opts)
% =============================
% 文件名：lin_agv_grid.m
% 路径：S-Function_14/lin_agv_grid.m
% 版本号：V1.0
% 最后修改时间：2025-10-03
% 作者：Auto-generated
% 功能描述：
%   在调度变量网格 ρ=[v, ω, θ] 上对AGV路径坐标系误差动力学进行线性化
%   生成离散LPV模型表 A(ρ), B(ρ), C(ρ), D(ρ), E(ρ)
%   重要说明：
%     - 表内矩阵为离散时间模型（由lin_agv_at_point一步差分得到）
%     - 无需再调用c2d转换
%     - 直接用于MPC预测模型
% 输入参数：
%   - params：参数结构体（来自 parameters.m）
%   - grid：网格定义结构体，包含
%       - V_grid：速度网格点 (Nv×1), 单位：m/s
%       - W_grid：角速度网格点（有符号，单调递增）(Nw×1), 单位：rad/s
%       - T_grid：坡度角网格点 (Nt×1), 单位：rad
%   - opts：可选参数结构体，包含
%       - coord：坐标系类型 ('path', 默认), 单位：-
%       - disc：离散化方法 ('zoh', 默认 或 'foh'), 单位：-
%       - keep_E：是否导出扰动通道E(ρ) (true, 默认), 单位：-
%       - export_mat：导出文件路径 ('lin/plant_grid.mat', 默认), 单位：-
% 输出参数：
%   - db：数据库结构体，包含
%       - grid：网格定义 (V, W, T)
%       - A：状态矩阵数组 (Nv×Nw×Nt×nx×nx)
%       - B：输入矩阵数组 (Nv×Nw×Nt×nx×nu)
%       - C：输出矩阵数组 (Nv×Nw×Nt×ny×nx)
%       - D：直通矩阵数组 (Nv×Nw×Nt×ny×nu)
%       - E：扰动矩阵数组 (Nv×Nw×Nt×nx×nd)（可选）
%       - Ts：采样周期
%       - nx, nu, ny, nd：维度信息
%       - meta：元数据
% 依赖：
%   - lin_agv_at_point.m：单点线性化内核
%   - state_eq.m：非线性状态转移方程
%   - parameters.m：参数定义
% 备注：
%   - 网格点数建议：Nv=3-5, Nw=3-5, Nt=3-5
%   - 总线性化次数：Nv × Nw × Nt
%   - 坐标系：路径坐标系误差 (e_y, e_psi, e_v, e_omega)
%   - 每个网格点对应一个局部线性模型
% =============================

%% 参数检查与默认值设置
if nargin < 3
    opts = struct();
end

% 默认选项
if ~isfield(opts, 'coord'), opts.coord = 'path'; end
if ~isfield(opts, 'disc'), opts.disc = 'zoh'; end
if ~isfield(opts, 'keep_E'), opts.keep_E = true; end
if ~isfield(opts, 'export_mat'), opts.export_mat = 'plant_grid.mat'; end

% 检查网格定义
if ~isfield(grid, 'V_grid') || ~isfield(grid, 'W_grid') || ~isfield(grid, 'T_grid')
    error('lin_agv_grid:InvalidGrid', '网格定义必须包含 V_grid, W_grid, T_grid 字段');
end

V_grid = grid.V_grid(:);  % 列向量
W_grid = grid.W_grid(:);
T_grid = grid.T_grid(:);

Nv = length(V_grid);
Nw = length(W_grid);
Nt = length(T_grid);

fprintf('========== AGV网格线性化开始 ==========\n');
fprintf('网格尺寸: Nv=%d, Nw=%d, Nt=%d\n', Nv, Nw, Nt);
fprintf('总线性化点数: %d\n', Nv*Nw*Nt);
fprintf('坐标系: %s\n', opts.coord);
fprintf('离散化方法: %s\n', opts.disc);
fprintf('==========================================\n\n');

%% 初始化存储数组
% 状态空间维度（固定）
nx = 4;  % [e_y, e_psi, e_v, e_omega]
nu = 2;  % [F_cmd, omega_cmd]
ny = 4;  % 输出 = 状态
nd = 1;  % [theta]

% 预分配矩阵数组
A_array = zeros(Nv, Nw, Nt, nx, nx);
B_array = zeros(Nv, Nw, Nt, nx, nu);
C_array = zeros(Nv, Nw, Nt, ny, nx);
D_array = zeros(Nv, Nw, Nt, ny, nu);
if opts.keep_E
    E_array = zeros(Nv, Nw, Nt, nx, nd);
end

% 工作点信息存储（用于调试和验证）
workpoints = struct('v', zeros(Nv, Nw, Nt), ...
                    'omega', zeros(Nv, Nw, Nt), ...
                    'theta', zeros(Nv, Nw, Nt), ...
                    'kappa', zeros(Nv, Nw, Nt));

%% 网格线性化主循环
tic;
total_points = Nv * Nw * Nt;
current_point = 0;

for i = 1:Nv
    for j = 1:Nw
        for k = 1:Nt
            current_point = current_point + 1;
            
            % 提取当前网格点参数
            v_star = V_grid(i);
            omega_star = W_grid(j);  % 保留符号
            theta_star = T_grid(k);
            
            % 曲率计算（用于工作点设置，保留符号）
            kappa_star = omega_star / max(v_star, 1e-3);
            
            % 构造工作点状态向量
            % 假设在平衡点：直线或匀速转弯，参考误差为零
            X0 = 0; Y0 = 0; psi0 = 0;  % 位置和航向（相对坐标）
            v0 = v_star;
            omega0 = omega_star;  % 保留符号（可正可负）
            
            % 转向角计算（对角式 LF/RR 舵驱几何）
            % RF/LR 为万向支撑轮，只参与垂向支撑；工作点舵角应与
            % state_eq_ref 的 ICR 约束一致，而不是单轨等角近似。
            L = params.L;  % 轴距
            W = params.W;  % 轮距
            if abs(omega_star) > 1e-6 && abs(v_star) > 1e-6
                R_star = (v_star / max(abs(omega_star), 1e-6)) * sign(omega_star);
                denom_lf = signed_min_abs(R_star - W / 2, 1e-6);
                denom_rr = signed_min_abs(R_star + W / 2, 1e-6);
                delta_lf0 = atan((L / 2) / denom_lf);
                delta_rr0 = -atan((L / 2) / denom_rr);
            else
                delta_lf0 = 0;
                delta_rr0 = 0;
            end
            
            beta0 = 0;  % 假设平衡点侧滑角为零
            
            x0 = [X0; Y0; psi0; v0; omega0; delta_lf0; delta_rr0; beta0];
            
            % 构造工作点输入向量
            % F_cmd：平衡驱动力（克服阻力和坡度）
            % 参数来源：与parameters.m中定义一致
            m = params.mass;                         % 质量[kg]
            g = params.gravity;                      % 重力加速度[m/s^2]
            c_r = params.rolling_resistance;         % 滚阻系数[-]
            rho_air = params.air_density;            % 空气密度[kg/m^3]
            CdA = params.drag_coefficient_area;      % 风阻系数×面积[m^2]
            
            F_rolling = c_r * m * g * cos(theta_star);  % 滚动阻力[N]
            F_aero = 0.5 * rho_air * CdA * v_star^2;    % 空气阻力[N]
            F_slope = m * g * sin(theta_star);           % 坡度阻力[N]
            F_cmd0 = F_rolling + F_aero + F_slope;       % 平衡驱动力[N]
            
            omega_cmd0 = omega0;  % 角速度指令 = 当前角速度
            
            u0 = [F_cmd0; omega_cmd0];
            theta0 = theta_star;
            
            % 记录工作点信息
            workpoints.v(i, j, k) = v_star;
            workpoints.omega(i, j, k) = omega_star;  % 有符号
            workpoints.theta(i, j, k) = theta_star;
            workpoints.kappa(i, j, k) = kappa_star;
            
            % 调用单点线性化函数
            try
                sys = lin_agv_at_point(x0, u0, theta0, params);
                
                % 存储线性化结果
                A_array(i, j, k, :, :) = sys.A;
                B_array(i, j, k, :, :) = sys.B;
                C_array(i, j, k, :, :) = sys.C;
                D_array(i, j, k, :, :) = sys.D;
                if opts.keep_E
                    E_array(i, j, k, :, :) = sys.E;
                end
                
                % 进度显示
                if mod(current_point, 5) == 0 || current_point == total_points
                    elapsed = toc;
                    eta = elapsed / current_point * (total_points - current_point);
                    fprintf('[%3d/%3d] v=%.2f, ω=%.3f, θ=%.2f° | 进度: %5.1f%% | ETA: %.1fs\n', ...
                        current_point, total_points, v_star, omega_star, ...
                        rad2deg(theta_star), 100*current_point/total_points, eta);
                end
                
            catch ME
                fprintf('警告: 线性化失败 at (i=%d, j=%d, k=%d): %s\n', i, j, k, ME.message);
                % 填充单位矩阵和零矩阵（防止数组出错）
                A_array(i, j, k, :, :) = eye(nx);
                B_array(i, j, k, :, :) = zeros(nx, nu);
                C_array(i, j, k, :, :) = eye(ny, nx);
                D_array(i, j, k, :, :) = zeros(ny, nu);
                if opts.keep_E
                    E_array(i, j, k, :, :) = zeros(nx, nd);
                end
            end
        end
    end
end

total_time = toc;
fprintf('\n========== 线性化完成 ==========\n');
fprintf('总耗时: %.2f 秒\n', total_time);
fprintf('平均每点: %.3f 秒\n', total_time / total_points);
fprintf('================================\n\n');

%% 稳定性校验（可选）
fprintf('========== 稳定性校验 ==========\n');
unstable_count = 0;
% 判定规则：|lambda|>1+tol 判为不稳定；|lambda|-1<=tol 记为边界/积分器
marginal_count = 0;
tol_unstable = 1e-6;
for i = 1:Nv
    for j = 1:Nw
        for k = 1:Nt
            A_local = squeeze(A_array(i, j, k, :, :));
            eigs_A = eig(A_local);
            max_eig = max(abs(eigs_A));
            
            if max_eig > 1.0 + tol_unstable
                unstable_count = unstable_count + 1;
                if unstable_count <= 5  % 只显示前5个
                    fprintf('警告: 不稳定点 (i=%d,j=%d,k=%d): max|eig|=%.6f\n', ...
                        i, j, k, max_eig);
                end
            elseif abs(max_eig - 1.0) <= tol_unstable
                marginal_count = marginal_count + 1; % 积分器/边界
            end
        end
    end
end
fprintf('不稳定点数量: %d / %d\n', unstable_count, total_points);
fprintf('边界(含积分器)点数量: %d / %d\n', marginal_count, total_points);
fprintf('================================\n\n');

%% 组装输出数据库
db = struct();
db.grid.V = V_grid;
db.grid.W = W_grid;
db.grid.T = T_grid;
db.Ts = params.Ts;

db.A = A_array;
db.B = B_array;
db.C = C_array;
db.D = D_array;
if opts.keep_E
    db.E = E_array;
end

db.nx = nx;
db.nu = nu;
db.ny = ny;
db.nd = nd;

db.Nv = Nv;
db.Nw = Nw;
db.Nt = Nt;

db.workpoints = workpoints;

% 元数据
db.meta.version = 'V1.2';
db.meta.generated_by = 'lin_agv_grid.m';
db.meta.generated_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
db.meta.model_semantics = 'discrete';  % 表内矩阵为离散时间模型
db.meta.discretization_note = 'lin_agv_at_point返回离散模型，本函数不再c2d';
db.meta.steer_model = 'diagonal-lf-rr-icr-with-caster-support';  % RF/LR 为万向支撑轮
db.meta.steer_assumption = 'delta_lf=atan((L/2)/(R-W/2)), delta_rr=-atan((L/2)/(R+W/2)), R=v/omega';
db.meta.coordinate = opts.coord;
db.meta.discretization = opts.disc;
db.meta.total_time = total_time;
db.meta.unstable_count = unstable_count;
db.meta.marginal_count = marginal_count;
db.meta.states = 'e_y[m], e_psi[rad], e_v[m/s], e_omega[rad/s]';
db.meta.inputs = 'F_cmd[N], omega_cmd[rad/s]';
db.meta.outputs = 'e_y[m], e_psi[rad], e_v[m/s], e_omega[rad/s]';
db.meta.scheduling = 'rho=[v, omega, theta], omega signed';  % 调度变量说明
if opts.keep_E
    db.meta.disturbances = 'theta[rad]';
end

%% 导出到文件
if ~isempty(opts.export_mat)
    % 创建目录（如果不存在）
    [export_dir, ~, ~] = fileparts(opts.export_mat);
    if ~isempty(export_dir) && ~exist(export_dir, 'dir')
        mkdir(export_dir);
    end
    
    fprintf('========== 导出结果 ==========\n');
    fprintf('保存到: %s\n', opts.export_mat);
    save(opts.export_mat, '-struct', 'db', '-v7.3');
    fprintf('文件大小: %.2f MB\n', dir(opts.export_mat).bytes / 1e6);
    fprintf('==============================\n\n');
end

fprintf('========== 网格线性化流程结束 ==========\n\n');

end

function y = signed_min_abs(x, eps_value)
if x == 0
    y = eps_value;
else
    y = sign(x) * max(abs(x), eps_value);
end
end
