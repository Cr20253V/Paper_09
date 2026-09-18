%% PreLoadFcn - 自动路径兼容版 V3.4 (2026-01-22)
% 修复内容：
%   - 检测旧 ctrl.mat 的 Np 不匹配时强制重建
%   - 步骤编号连续化 (0-5)
%   - 修正 ctrl.meta 字段名为 Np/Nc
%   - 创建新控制器后自动保存 ctrl.mat

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║     LPVMPC_AGV 模型初始化 (PreLoadFcn, V3.4, 2026-01-22)   ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

%% Bootstrap path + 目录配置
init_project();
root = project_root();
data_dir = fullfile(root, 'data');
data_models_dir = fullfile(data_dir, 'models');
data_paths_dir = fullfile(data_dir, 'paths');
data_gru_dir = fullfile(data_dir, 'gru');
results_root = results_dir('');
results_paths = struct( ...
    'root', results_root, ...
    'simulink', results_dir('simulink'), ...
    'closed_loop', results_dir('closed_loop'), ...
    'paths', results_dir('paths'), ...
    'gru_logs', results_dir('gru/sim'));
env_paths = struct('root', root, 'data', data_dir, 'models', data_models_dir, ...
    'paths', data_paths_dir, 'gru', data_gru_dir, 'results', results_paths);

assignin('base', 'results_paths', results_paths);
assignin('base', 'env_paths', env_paths);

mw = get_param(bdroot, 'ModelWorkspace');
mw.assignin('results_paths', results_paths);
mw.assignin('env_paths', env_paths);
% Do not save ModelWorkspace during PreLoadFcn; this can block load_system in batch mode.

preload_model_name = '';
try
    preload_model_name = bdroot;
catch
    preload_model_name = '';
end

skip_gru_model = false;
if ~isempty(preload_model_name)
    skip_gru_model = contains(lower(preload_model_name), 'imu');
end
if evalin('base', 'exist(''preload_skip_gru_model'', ''var'')==1')
    skip_gru_model = logical(evalin('base', 'preload_skip_gru_model'));
end

% ThetaModeSelect uses this scalar when the IMU baseline model is run:
%   1 -> nominal theta=0, 2 -> IMU estimate, 3 -> oracle true theta.
if evalin('base', 'exist(''theta_mode'', ''var'')==0')
    assignin('base', 'theta_mode', 2);
end
theta_mode = double(evalin('base', 'theta_mode'));
assignin('base', 'theta_mode', theta_mode);
mw.assignin('theta_mode', theta_mode);

runtime_override = local_runtime_override_from_base();
runtime_override_active = ~isempty(runtime_override);

%% ===== 目标预测时域配置 =====
TARGET_NP = 150;  % 1.5s 预测时域（P0 oracle-MPC）
TARGET_NC = 30;   % 0.3s 控制时域（P0 oracle-MPC）
if runtime_override_active
    TARGET_NP = runtime_override.Np;
    TARGET_NC = runtime_override.Nc;
end

%% 步骤0：加载基础参数
fprintf('[步骤 0/5] 加载基础参数...\n');
try
    params = parameters();
    fprintf('  ✓ parameters() 加载成功 (Ts=%.3fs, m=%.1fkg, L=%.2fm)\n', ...
        params.Ts, params.mass, params.L);
catch ME
    warning('[PreLoadFcn] parameters() 失败: %s', ME.message);
    params = struct('Ts',0.05,'mass',100,'gravity',9.81, ...
        'rolling_resistance',0.015,'air_density',1.225, ...
        'drag_coefficient_area',0.5,'L',2.0);
end
assignin('base','params',params);
mw.assignin('params',params);

ff_rt = struct('m',params.mass,'g',params.gravity, ...
    'c_r',params.rolling_resistance,'rho',params.air_density, ...
    'CdA',params.drag_coefficient_area);
v_ff_nom = 1.0;
assignin('base','ff_rt',ff_rt);
assignin('base','v_ff_nom',v_ff_nom);
mw.assignin('ff_rt',ff_rt);
mw.assignin('v_ff_nom',v_ff_nom);
fprintf('\n');

%% 步骤1：载入 LPV 数据库
fprintf('[步骤 1/5] 加载 LPV 数据库...\n');
base_names = {'lin_agv_db.mat', 'plant_grid_test.mat', 'plant_grid.mat'};
base_dirs = {data_models_dir, root, ''};
db_files = {};
for d = 1:numel(base_dirs)
    for n = 1:numel(base_names)
        if isempty(base_dirs{d})
            db_files{end+1} = base_names{n}; %#ok<AGROW>
        else
            db_files{end+1} = fullfile(base_dirs{d}, base_names{n}); %#ok<AGROW>
        end
    end
end
db_files = unique(db_files, 'stable');
if runtime_override_active && isfield(runtime_override, 'db_file') && ...
        ~isempty(runtime_override.db_file)
    db_files = [{char(string(runtime_override.db_file))}, db_files];
    db_files = unique(db_files, 'stable');
end

S = [];
loaded_db_file = '';
for i = 1:numel(db_files)
    if exist(db_files{i}, 'file')
        try
            S = load(db_files{i});
            loaded_db_file = db_files{i};
            fprintf('  ✓ 文件加载成功: %s\n', db_files{i});
            break;
        catch ME
            fprintf('  ⚠ 尝试加载 %s 失败: %s\n', db_files{i}, ME.message);
        end
    end
end

if isempty(S)
    error('[PreLoadFcn] ❌ 未找到 LPV 数据库文件（请先运行 lin_agv_grid 或 test_lpvmpc_workflow）');
end

if isfield(S,'db') && isstruct(S.db)
    db_data = S.db;
    fprintf('  → 使用 db 结构体格式\n');
elseif all(isfield(S, {'A','B','C','D','E'}))
    db_data = S;
    fprintf('  → 使用顶层字段格式\n');
else
    error('[PreLoadFcn] 数据库格式无法识别 (字段: %s)', strjoin(fieldnames(S), ', '));
end

req = {'A','B','C','D','E','Ts','grid'};
missing = req(~isfield(db_data, req));
if ~isempty(missing)
    error('[PreLoadFcn] ❌ 数据库缺少字段: %s', strjoin(missing, ', '));
end

A=db_data.A; B=db_data.B; C=db_data.C; D=db_data.D; E=db_data.E;
Ts=db_data.Ts; grid=db_data.grid;
nx=size(A,4); nu=size(B,5); ny=size(C,4); nd=size(E,5);
Nv=size(A,1); Nw=size(A,2); Nt=size(A,3);

fprintf('  ✓ 网格: %d×%d×%d (总 %d 点), nx=%d, nu=%d, nd=%d, Ts=%.3fs\n', ...
    Nv, Nw, Nt, Nv*Nw*Nt, nx, nu, nd, Ts);

db_rt = struct('A',A,'B',B,'C',C,'D',D,'E',E, ...
    'grid',grid,'Ts',Ts,'nx',nx,'nu',nu,'ny',ny,'nd',nd, ...
    'Nv',Nv,'Nw',Nw,'Nt',Nt);
assignin('base','db_rt',db_rt);
mw.assignin('db_rt',db_rt);
fprintf('\n');

%% 步骤2：创建 MPCPlantBus
fprintf('[步骤 2/5] 创建 MPCPlantBus...\n');
nu_md = nu + nd;
samplePlant = struct('A',zeros(nx,nx),'B',zeros(nx,nu_md), ...
    'C',zeros(ny,nx),'D',zeros(ny,nu_md),'U',zeros(nu_md,1), ...
    'X',zeros(nx,1),'Y',zeros(ny,1),'DX',zeros(nx,1),'Ts',Ts);
info = Simulink.Bus.createObject(samplePlant);
assignin('base','MPCPlantBus', eval(info.busName));
if ~strcmp(info.busName,'MPCPlantBus')
    eval(sprintf('clear %s;', info.busName));
end
assignin('base','plant_ic', samplePlant);
fprintf('  ✓ MPCPlantBus 创建成功 (nu_md=%d = %d MV + %d MD)\n\n', nu_md, nu, nd);

%% 步骤3：加载优化权重 (Phase 2 > Phase 1) / 创建控制器
fprintf('[步骤 3/5] 加载优化权重 / ctrl...\n');

% 搜索路径：优先看 results/bo_results
bo_results_dir = fullfile(results_root, 'bo_results');
workflow_mpc_dir = fullfile(root, 'results', 'paper', ...
    'agv_model_parameter_correction_workflow', '06_mpc_retuning', ...
    'p0_oracle_retuning_20260602_033639');
base_dirs_mb = {workflow_mpc_dir, bo_results_dir, data_models_dir, root, ''};

% 优先级：phase2_best > phase1_best
maps_names = {'maps_best_agv_physics_v2_p0_oracle.mat', 'phase2_best.mat', 'phase1_best.mat'};

maps_files = {};
for d = 1:numel(base_dirs_mb)
    for n = 1:numel(maps_names)
        if isempty(base_dirs_mb{d})
            maps_files{end+1} = maps_names{n}; %#ok<AGROW>
        else
            maps_files{end+1} = fullfile(base_dirs_mb{d}, maps_names{n}); %#ok<AGROW>
        end
    end
end
maps_files = unique(maps_files, 'stable');

maps_best = [];
maps_loaded = false;
maps_source_file = '';
for i = 1:numel(maps_files)
    if exist(maps_files{i}, 'file')
        try
            Tm = load(maps_files{i});
            
            % 提取权重数据（兼容 best 或 maps_best 结构）
            if isfield(Tm, 'best')
                if isfield(Tm.best, 'ctrl_maps')
                    maps_best = Tm.best.ctrl_maps;
                    maps_best.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
                    [~, fname, ~] = fileparts(maps_files{i});
                    maps_best.version = fname;
                elseif isfield(Tm.best, 'Q_range')
                    maps_best = Tm.best;
                end
            elseif isfield(Tm, 'maps_best')
                maps_best = Tm.maps_best;
            end
            
            if ~isempty(maps_best)
                maps_loaded = true;
                maps_source_file = maps_files{i};
                [~, fname, ~] = fileparts(maps_files{i});
                fprintf('  ✓ 权重加载成功 (%s)\n', fname);
                break;
            end
        catch ME
            fprintf('  ⚠ 加载 %s 失败: %s\n', maps_files{i}, ME.message);
        end
    end
end
if ~maps_loaded
    fprintf('  ⚠ 未找到 phase2_best.mat 或 phase1_best.mat，将使用默认权重\n');
end

if runtime_override_active
    maps_best = local_apply_runtime_override_to_maps(maps_best, runtime_override, db_rt);
    maps_loaded = true;
    maps_source_file = '[runtime_override]';
    fprintf('  → 使用运行时候选 override: %s\n', runtime_override.id);
end

% 尝试加载现有 ctrl.mat（带 Np 版本检查）
ctrl = [];
ctrl_source = '未创建';
ctrl_file_path = fullfile(data_models_dir, 'ctrl.mat');

if ~runtime_override_active && exist(ctrl_file_path, 'file')
    try
        Tc = load(ctrl_file_path);
        if isfield(Tc, 'ctrl')
            % 检查 Np/Nc 是否匹配目标值
            if isfield(Tc.ctrl, 'meta') && isfield(Tc.ctrl.meta, 'Np') && isfield(Tc.ctrl.meta, 'Nc')
                old_Np = Tc.ctrl.meta.Np;
                old_Nc = Tc.ctrl.meta.Nc;
                if old_Np == TARGET_NP && old_Nc == TARGET_NC
                    ctrl = Tc.ctrl;
                    ctrl_source = ctrl_file_path;
                    fprintf('  ✓ 从 ctrl.mat 加载控制器 (Np=%d, Nc=%d)\n', old_Np, old_Nc);
                else
                    fprintf('  ⚠ 发现旧 ctrl.mat (Np=%d, Nc=%d)，需重建 (目标 Np=%d, Nc=%d)\n', ...
                        old_Np, old_Nc, TARGET_NP, TARGET_NC);
                end
            else
                fprintf('  ⚠ ctrl.mat 缺少 meta.Np/meta.Nc 信息，需重建\n');
            end
        end
    catch ME
        fprintf('  ⚠ 加载 ctrl.mat 失败: %s\n', ME.message);
    end
end

% 如果需要创建新控制器
if isempty(ctrl) && exist('mpc_setup_single_interp','file')==2
    fprintf('  → 创建新控制器 (Np=%d, Nc=%d)...\n', TARGET_NP, TARGET_NC);

    if runtime_override_active
        Q_base = runtime_override.Q;
        R_base = runtime_override.R;
        dR_base = runtime_override.dR;
        fprintf('    使用运行时候选权重\n');
    elseif maps_loaded && all(isfield(maps_best, {'Q_range','R_range','dR_range'}))
        Q_base = mean(maps_best.Q_range, 1);
        R_base = mean(maps_best.R_range, 1);
        dR_base = mean(maps_best.dR_range, 1);
        fprintf('    使用加载的优化权重\n');
    else
        Q_base = [100, 100, 15, 3];
        R_base = [3e-5, 3e-5];
        dR_base = [1e-3, 1e-3];
        fprintf('    使用 P0 oracle-MPC 默认权重\n');
    end
    
    mpc_opts = struct('Np', TARGET_NP, 'Nc', TARGET_NC, ...
                      'Q', Q_base, 'R', R_base, 'dR', dR_base);
    if runtime_override_active
        mpc_opts = local_apply_runtime_override_to_mpc_opts(mpc_opts, runtime_override);
    end
    
    ctrl = mpc_setup_single_interp(db_rt, mpc_opts);
    ctrl_source = '新创建';
    fprintf('  ✓ 控制器创建成功 (P=%.2fs, M=%.2fs)\n', ...
        ctrl.meta.prediction_horizon_sec, ctrl.meta.control_horizon_sec);

    % 保存新创建的控制器
    if ~runtime_override_active
        try
            save(ctrl_file_path, 'ctrl');
            fprintf('  → 已保存新控制器到 ctrl.mat\n');
        catch ME
            fprintf('  ⚠ 保存 ctrl.mat 失败: %s\n', ME.message);
        end
    end
end

% 将优化参数注入控制器 maps
if maps_loaded && ~isempty(ctrl)
    fields = {'Q_range','R_range','dR_range','alpha_Q','beta_Q', ...
        'alpha_R','beta_R','alpha_dR','beta_dR', ...
        'scale_umin_lo','scale_umin_hi','scale_umax_lo','scale_umax_hi', ...
        'rho_min', 'rho_max', 'enable_factor', ...
        'factor_y', 'factor_psi', 'factor_v', 'factor_omega', ...
        'factor_R_F', 'factor_R_omega', 'factor_dR_F', 'factor_dR_omega', ...
        'enable_weight_interp', 'umin_range', 'umax_range', ...
        'ey_max', 'epsi_max', 'ev_max', 'eomega_max', ...
        'omega_threshold', 'q_y_gain_max', 'theta_threshold', 'q_v_gain_max', ...
        'R_F_gain_max_uphill', 'R_F_gain_max_downhill', ...
        'dR_F_gain_max_uphill', 'dR_F_gain_max_downhill', ...
        'transition_width', 'theta_transition_width'};
    
    copied = 0;
    for i = 1:numel(fields)
        if isfield(maps_best, fields{i})
            ctrl.maps.(fields{i}) = maps_best.(fields{i});
            copied = copied + 1;
        end
    end
    fprintf('  → 已将 %d 个优化参数注入 ctrl.maps\n', copied);
    if runtime_override_active
        ctrl.opts.Np = runtime_override.Np;
        ctrl.opts.Nc = runtime_override.Nc;
        ctrl.opts.Q = runtime_override.Q;
        ctrl.opts.R = runtime_override.R;
        ctrl.opts.dR = runtime_override.dR;
        ctrl.opts = local_apply_runtime_override_to_mpc_opts(ctrl.opts, runtime_override);
    else
        ctrl.opts.Np = TARGET_NP;
        ctrl.opts.Nc = TARGET_NC;
        ctrl.opts.Q = [100, 100, 15, 3];
        ctrl.opts.R = [3e-5, 3e-5];
        ctrl.opts.dR = [1e-3, 1e-3];
    end
    ctrl.mpcobj.Weights.OutputVariables = ctrl.opts.Q;
    ctrl.mpcobj.Weights.ManipulatedVariables = ctrl.opts.R;
    ctrl.mpcobj.Weights.ManipulatedVariablesRate = ctrl.opts.dR;
    ctrl.meta.Np = TARGET_NP;
    ctrl.meta.Nc = TARGET_NC;
    if runtime_override_active
        ctrl.meta.sync_source = ['runtime_override:' runtime_override.id];
    else
        ctrl.meta.sync_source = 'p0_oracle_retuning_20260602_033639';
    end
    ctrl.meta.sync_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    if runtime_override_active
        fprintf('  → 运行时 override 激活，跳过 ctrl.mat 回写\n');
    else
        try
            save(ctrl_file_path, 'ctrl');
            fprintf('  → 已保存注入 P0 maps 后的控制器到 ctrl.mat\n');
        catch ME
            fprintf('  ⚠ 保存注入 maps 后的 ctrl.mat 失败: %s\n', ME.message);
        end
    end
end

if ~isempty(ctrl)
    runtime_maps = local_codegen_runtime_maps(ctrl.maps);
    assignin('base','db_rt',db_rt);
    mw.assignin('db_rt',db_rt);
    assignin('base', 'mpc_runtime_maps', runtime_maps);
    mw.assignin('mpc_runtime_maps', runtime_maps);
    local_assign_runtime_map_scalars(runtime_maps, mw);
    assignin('base', 'ctrl', ctrl);
    assignin('base', 'mpcobj', ctrl.mpcobj);
    assignin('base', 'maps', ctrl.maps);
    mw.assignin('ctrl', ctrl);
    mw.assignin('mpcobj', ctrl.mpcobj);
    mw.assignin('maps', ctrl.maps);
else
    warning('[PreLoadFcn] 无法创建/加载 ctrl');
end
fprintf('\n');

%% 步骤4：加载 GRU 模型
gru_model = [];
gru_scaler = [];
gru_status = '跳过（无神经网络基线）';

if skip_gru_model
    fprintf('[步骤 4/5] 跳过 GRU 模型加载...\n');
    if ~isempty(preload_model_name)
        fprintf('  → 当前模型: %s\n', preload_model_name);
    end
    fprintf('  → IMU / nominal / oracle 基线不依赖 GRU_model.mat\n');
else
    fprintf('[步骤 4/5] 加载 GRU 模型...\n');

    base_dirs_gru = {data_models_dir, data_gru_dir, root};
    gru_files = {};
    for d = 1:numel(base_dirs_gru)
        gru_files{end+1} = fullfile(base_dirs_gru{d}, 'GRU_model.mat'); %#ok<AGROW>
    end
    gru_files = unique(gru_files, 'stable');

    for i = 1:numel(gru_files)
        if exist(gru_files{i}, 'file')
            Sg = load(gru_files{i});
            if isfield(Sg, 'model')
                gru_model = Sg.model;
                fprintf('  ✓ GRU_model 加载成功 (%s)\n', gru_files{i});
                if isfield(gru_model, 'seq_len')
                    fprintf('    - 序列长度: %d\n', gru_model.seq_len);
                end
                if isfield(gru_model, 'scaler')
                    gru_scaler = gru_model.scaler;
                end
                break;
            end
        end
    end

    if isempty(gru_model)
        error('[PreLoadFcn] ❌ 未找到 GRU_model.mat');
    end

    scaler_files = {};
    for d = 1:numel(base_dirs_gru)
        scaler_files{end+1} = fullfile(base_dirs_gru{d}, 'GRU_scaler.mat'); %#ok<AGROW>
    end
    scaler_files = unique(scaler_files, 'stable');
    if isempty(gru_scaler)
        for i = 1:numel(scaler_files)
            if exist(scaler_files{i}, 'file')
                Ss = load(scaler_files{i});
                if isfield(Ss, 'scaler')
                    gru_scaler = Ss.scaler;
                    fprintf('  ✓ GRU_scaler 加载成功 (%s)\n', scaler_files{i});
                    break;
                end
            end
        end
    end

    assignin('base', 'gru_model', gru_model);
    if ~isempty(gru_scaler)
        assignin('base', 'gru_scaler', gru_scaler);
    end
    gru_status = '就绪';
end
fprintf('\n');

%% 步骤5：初始化总结
fprintf('[步骤 5/5] 初始化总结\n');
fprintf('  ════════════════════════════════════════════════\n');
fprintf('  ✓ 基础参数:     已加载 (Ts=%.3fs)\n', params.Ts);
fprintf('  ✓ LPV 数据库:   %s (%d×%d×%d)\n', loaded_db_file, Nv, Nw, Nt);
fprintf('  ✓ MPCPlantBus:  已创建\n');
fprintf('  ✓ GRU 模型:     %s\n', gru_status);

if maps_loaded
    [~, fname, ~] = fileparts(maps_source_file);
    fprintf('  ✓ 优化权重:     已加载 (%s)\n', fname);
else
    fprintf('  ⚠ 优化权重:     未加载 (使用默认)\n');
end

if ~isempty(ctrl)
    fprintf('  ✓ MPC 控制器:   %s (Np=%d, Nc=%d)\n', ctrl_source, ...
        ctrl.meta.Np, ctrl.meta.Nc);
else
    fprintf('  ❌ MPC 控制器:  未创建\n');
end
fprintf('  ════════════════════════════════════════════════\n');

% 最终状态判定
if maps_loaded && ~isempty(ctrl)
    if skip_gru_model
        fprintf('\n✓ 初始化成功！使用优化权重，无神经网络基线调度\n');
    else
        fprintf('\n✓ 初始化成功！使用优化权重与 GRU 调度\n');
    end
elseif ~isempty(ctrl)
    fprintf('\n⚠ 初始化完成，使用默认权重\n');
else
    fprintf('\n❌ 初始化失败，请检查上方日志\n');
end

fprintf('\n[PreLoadFcn] 完成\n\n');

function runtime_override = local_runtime_override_from_base()
runtime_override = [];
if evalin('base', 'exist(''mpc_runtime_override'', ''var'')==0')
    return;
end
runtime_override = evalin('base', 'mpc_runtime_override');
if isempty(runtime_override) || ~isstruct(runtime_override)
    runtime_override = [];
    return;
end

required = {'Np', 'Nc', 'Q', 'R', 'dR'};
for i = 1:numel(required)
    if ~isfield(runtime_override, required{i}) || isempty(runtime_override.(required{i}))
        error('[PreLoadFcn] mpc_runtime_override 缺少字段: %s', required{i});
    end
end

if ~isfield(runtime_override, 'id') || isempty(runtime_override.id)
    runtime_override.id = sprintf('candidate_np%d_nc%d', runtime_override.Np, runtime_override.Nc);
end
runtime_override.id = char(string(runtime_override.id));
runtime_override.Np = double(runtime_override.Np);
runtime_override.Nc = double(runtime_override.Nc);
runtime_override.Q = double(reshape(runtime_override.Q, 1, []));
runtime_override.R = double(reshape(runtime_override.R, 1, []));
runtime_override.dR = double(reshape(runtime_override.dR, 1, []));
runtime_override = local_normalize_runtime_override_optional(runtime_override);
if ~isfield(runtime_override, 'maps_template') || isempty(runtime_override.maps_template) || ~isstruct(runtime_override.maps_template)
    runtime_override.maps_template = struct();
end
end

function runtime_override = local_normalize_runtime_override_optional(runtime_override)
vector_fields = {'umin', 'umax', 'dumin', 'dumax', 'ymin', 'ymax'};
for i = 1:numel(vector_fields)
    name = vector_fields{i};
    if isfield(runtime_override, name) && ~isempty(runtime_override.(name))
        runtime_override.(name) = double(runtime_override.(name)(:));
    end
end

scalar_fields = {'soft_weight_pos', 'soft_weight_yaw', 'tau'};
for i = 1:numel(scalar_fields)
    name = scalar_fields{i};
    if isfield(runtime_override, name) && ~isempty(runtime_override.(name))
        runtime_override.(name) = double(runtime_override.(name));
    end
end
end

function opts = local_apply_runtime_override_to_mpc_opts(opts, runtime_override)
optional_fields = {'umin', 'umax', 'dumin', 'dumax', 'ymin', 'ymax', ...
    'soft_weight_pos', 'soft_weight_yaw'};
for i = 1:numel(optional_fields)
    name = optional_fields{i};
    if isfield(runtime_override, name) && ~isempty(runtime_override.(name))
        opts.(name) = runtime_override.(name);
    end
end
end

function maps_out = local_apply_runtime_override_to_maps(maps_in, runtime_override, db_rt)
maps_out = maps_in;
if isempty(maps_out)
    maps_out = struct();
end

if isfield(runtime_override, 'maps_template') && isstruct(runtime_override.maps_template)
    fields = fieldnames(runtime_override.maps_template);
    for i = 1:numel(fields)
        maps_out.(fields{i}) = runtime_override.maps_template.(fields{i});
    end
end

maps_out.enable_weight_interp = true;
maps_out.Q_range = local_center_to_range(runtime_override.Q);
maps_out.R_range = local_center_to_range(runtime_override.R);
maps_out.dR_range = local_center_to_range(runtime_override.dR);
maps_out.rho_min = [db_rt.grid.V(1); db_rt.grid.W(1); db_rt.grid.T(1)];
maps_out.rho_max = [db_rt.grid.V(end); db_rt.grid.W(end); db_rt.grid.T(end)];
maps_out.runtime_override = runtime_override;
end

function runtime_maps = local_codegen_runtime_maps(maps_in)
runtime_maps = struct();
if isempty(maps_in) || ~isstruct(maps_in)
    return;
end

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
    if ~isfield(maps_in, name)
        continue;
    end
    val = maps_in.(name);
    if islogical(val)
        runtime_maps.(name) = logical(val);
    elseif isnumeric(val)
        runtime_maps.(name) = double(val);
    end
end
end

function local_assign_runtime_map_scalars(runtime_maps, mw)
if isempty(runtime_maps) || ~isstruct(runtime_maps)
    return;
end

fields = {'enable_weight_interp', 'Q_range', 'R_range', 'dR_range', ...
    'alpha_Q', 'beta_Q', 'alpha_R', 'beta_R', 'alpha_dR', 'beta_dR', ...
    'scale_umin_lo', 'scale_umin_hi', 'scale_umax_lo', 'scale_umax_hi', ...
    'rho_min', 'rho_max', 'tau', 'omega_threshold', 'q_y_gain_max', ...
    'transition_width', 'theta_threshold', 'q_v_gain_max', ...
    'theta_transition_width', 'R_F_gain_max_uphill', ...
    'R_F_gain_max_downhill', 'dR_F_gain_max_uphill', ...
    'dR_F_gain_max_downhill', 'umin_range', 'umax_range'};

for i = 1:numel(fields)
    field_name = fields{i};
    if ~isfield(runtime_maps, field_name)
        continue;
    end

    value = runtime_maps.(field_name);
    if islogical(value)
        value = logical(value);
    elseif isnumeric(value)
        value = double(value);
    else
        continue;
    end

    var_name = ['mpc_runtime_' field_name];
    assignin('base', var_name, value);
    mw.assignin(var_name, value);
end
end

function runtime_maps = local_initial_runtime_maps(db_rt, runtime_override, runtime_override_active)
runtime_maps = struct( ...
    'enable_weight_interp', true, ...
    'Q_range', [50, 50, 7.5, 1.5; 150, 150, 22.5, 4.5], ...
    'R_range', [1.5e-5, 1.5e-5; 4.5e-5, 4.5e-5], ...
    'dR_range', [5e-4, 5e-4; 1.5e-3, 1.5e-3], ...
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
    'rho_min', [db_rt.grid.V(1); db_rt.grid.W(1); db_rt.grid.T(1)], ...
    'rho_max', [db_rt.grid.V(end); db_rt.grid.W(end); db_rt.grid.T(end)], ...
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
    'umax_range', [600, 1.2; 720, 1.44]);

if runtime_override_active
    runtime_maps.Q_range = local_center_to_range(runtime_override.Q);
    runtime_maps.R_range = local_center_to_range(runtime_override.R);
    runtime_maps.dR_range = local_center_to_range(runtime_override.dR);
    if isfield(runtime_override, 'maps_template') && isstruct(runtime_override.maps_template)
        runtime_maps = local_codegen_runtime_maps(local_apply_runtime_override_to_maps( ...
            runtime_maps, runtime_override, db_rt));
    end
end
end

function range = local_center_to_range(center)
range = [center * 0.5; center * 1.5];
end
