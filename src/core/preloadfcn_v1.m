%% PreLoadFcn - 自动路径兼容版 V3.0 (2025-12-10)
fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║     LPVMPC_AGV 模型初始化 (PreLoadFcn, V3.0, 2025-12-10)   ║\n');
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
assignin(mw, 'results_paths', results_paths);
assignin(mw, 'env_paths', env_paths);
% Do not save ModelWorkspace during PreLoadFcn; this can block load_system in batch mode.

%% 步骤0：加载基础参数
fprintf('[步骤 0/6] 加载基础参数...\n');
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
assignin(mw,'params',params);

ff_rt = struct('m',params.mass,'g',params.gravity, ...
    'c_r',params.rolling_resistance,'rho',params.air_density, ...
    'CdA',params.drag_coefficient_area);
v_ff_nom = 1.0;
assignin('base','ff_rt',ff_rt);
assignin('base','v_ff_nom',v_ff_nom);
assignin(mw,'ff_rt',ff_rt);
assignin(mw,'v_ff_nom',v_ff_nom);
fprintf('\n');

%% 步骤1：载入 LPV 数据库
fprintf('[步骤 1/6] 加载 LPV 数据库...\n');
base_names = {'lin_agv_db.mat','plant_grid_test.mat','plant_grid.mat'};
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
assignin(mw,'db_rt',db_rt);
fprintf('\n');

%% 步骤2：创建 MPCPlantBus
fprintf('[步骤 2/6] 创建 MPCPlantBus...\n');
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

%% 步骤3：加载 maps_best / ctrl
fprintf('[步骤 3/6] 加载 maps_best / ctrl...\n');
base_dirs_mb = {data_models_dir, root, ''};
maps_files = {};
for d = 1:numel(base_dirs_mb)
    if isempty(base_dirs_mb{d})
        maps_files{end+1} = 'maps_best.mat'; %#ok<AGROW>
    else
        maps_files{end+1} = fullfile(base_dirs_mb{d}, 'maps_best.mat'); %#ok<AGROW>
    end
end
maps_files = unique(maps_files, 'stable');

maps_best = [];
maps_loaded = false;
for i = 1:numel(maps_files)
    if exist(maps_files{i}, 'file')
        try
            Tm = load(maps_files{i});
            if isfield(Tm,'maps_best')
                maps_best = Tm.maps_best;
                maps_loaded = true;
                fprintf('  ✓ maps_best 加载成功 (%s)\n', maps_files{i});
                if isfield(maps_best,'version')
                    fprintf('    - 版本: %s\n', maps_best.version);
                end
                if isfield(maps_best,'timestamp')
                    fprintf('    - 时间: %s\n', maps_best.timestamp);
                end
            end
            break;
        catch ME
            fprintf('  ⚠ 加载 %s 失败: %s\n', maps_files{i}, ME.message);
        end
    end
end
if ~maps_loaded
    fprintf('  ⚠ 未找到 maps_best.mat，使用默认权重\n');
end

ctrl = [];
ctrl_source = '未创建';
base_dirs_ctrl = {data_models_dir, root};
ctrl_files = {};
for d = 1:numel(base_dirs_ctrl)
    ctrl_files{end+1} = fullfile(base_dirs_ctrl{d}, 'ctrl.mat'); %#ok<AGROW>
end
ctrl_files = unique(ctrl_files, 'stable');

for i = 1:numel(ctrl_files)
    if exist(ctrl_files{i}, 'file')
        try
            Tc = load(ctrl_files{i});
            if isfield(Tc,'ctrl')
                ctrl = Tc.ctrl;
                ctrl_source = ctrl_files{i};
                fprintf('  ✓ 从 %s 加载 ctrl\n', ctrl_source);
                break;
            end
        catch ME
            fprintf('  ⚠ 加载 %s 失败: %s\n', ctrl_files{i}, ME.message);
        end
    end
end

if isempty(ctrl) && exist('mpc_setup_single_interp','file')==2
    fprintf('  → 创建新控制器...\n');
    if maps_loaded && all(isfield(maps_best, {'Q_range','R_range','dR_range'}))
        Q_base = mean(maps_best.Q_range,1);
        R_base = mean(maps_best.R_range,1);
        dR_base = mean(maps_best.dR_range,1);
        fprintf('    使用 maps_best 权重\n');
    else
        Q_base = [3,8,1,1];
        R_base = [1e-3,1e-3];
        dR_base = [1e-2,1e-2];
        fprintf('    使用默认权重\n');
    end
    mpc_opts = struct('Np',30,'Nc',10,'Q',Q_base,'R',R_base,'dR',dR_base);
    ctrl = mpc_setup_single_interp(db_rt, mpc_opts);
    ctrl_source = '新创建';
    fprintf('  ✓ 控制器创建成功 (P=%.2fs, M=%.2fs)\n', ...
        ctrl.meta.prediction_horizon_sec, ctrl.meta.control_horizon_sec);
end

if maps_loaded && ~isempty(ctrl)
    fields = {'Q_range','R_range','dR_range','alpha_Q','beta_Q', ...
        'alpha_R','beta_R','alpha_dR','beta_dR', ...
        'scale_umin_lo','scale_umin_hi','scale_umax_lo','scale_umax_hi'};
    copied = 0;
    for i = 1:numel(fields)
        if isfield(maps_best, fields{i})
            ctrl.maps.(fields{i}) = maps_best.(fields{i});
            copied = copied + 1;
        end
    end
    fprintf('  → 已将 %d 个 maps_best 字段写入 ctrl.maps\n', copied);
end

if ~isempty(ctrl)
    assignin('base','ctrl',ctrl);
else
    warning('[PreLoadFcn] 无法创建/加载 ctrl');
end
fprintf('\n');

%% 步骤4：直接加载参考路径到基础工作区
% fprintf('[步骤 4/6] 加载路径参考数据（ref_* 格式）...\n');
% 
% path_types = {'straight','turn','straight_left_turn','straight_right_turn','slope','bumpy', ...
%               's_curve','s_shape'};
% path_refs = struct();
% paths_loaded = 0;
% 
% for i = 1:numel(path_types)
%     name = path_types{i};
%     file_path = fullfile(data_paths_dir, sprintf('path_%s.mat', name));
%     if ~exist(file_path,'file')
%         fprintf('  ⚠ 缺少路径文件: %s\n', file_path);
%         continue;
%     end
% 
%     try
%         data = load(file_path);
%         if ~isfield(data,'ref')
%             error('文件缺少 ref 结构');
%         end
%         ref = data.ref;
%         var_name = sprintf('ref_%s', name);
% 
%         % 写入 Base Workspace（兼容旧流程）
%         assignin('base', var_name, ref);
%         % 如需模型工作区可同步写入
%         assignin(mw, var_name, ref);
% 
%         % 记录到 path_refs 结构
%         path_refs.(name) = ref;
% 
%         paths_loaded = paths_loaded + 1;
%         fprintf('  ✓ %s: 已加载 (%s → %s)\n', name, file_path, var_name);
%     catch ME
%         fprintf('  ❌ 加载 %s 失败: %s\n', name, ME.message);
%     end
% end
% 
% assignin('base','path_refs',path_refs);
% assignin(mw,'path_refs',path_refs);
% try, save(mw); catch, end
% fprintf('  → 路径数据加载 %d/%d\n\n', paths_loaded, numel(path_types));
%% 步骤5：加载 GRU 模型
fprintf('[步骤 5/6] 加载 GRU 模型...\n');
gru_model = [];
gru_scaler = [];

base_dirs_gru = {data_models_dir, data_gru_dir, root};
gru_files = {};
for d = 1:numel(base_dirs_gru)
    gru_files{end+1} = fullfile(base_dirs_gru{d}, 'GRU_model.mat'); %#ok<AGROW>
end
gru_files = unique(gru_files, 'stable');

for i = 1:numel(gru_files)
    if exist(gru_files{i},'file')
        Sg = load(gru_files{i});
        if isfield(Sg,'model')
            gru_model = Sg.model;
            fprintf('  ✓ GRU_model 加载成功 (%s)\n', gru_files{i});
            if isfield(gru_model,'seq_len')
                fprintf('    - 序列长度: %d\n', gru_model.seq_len);
            end
            if isfield(gru_model,'scaler')
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
        if exist(scaler_files{i},'file')
            Ss = load(scaler_files{i});
            if isfield(Ss,'scaler')
                gru_scaler = Ss.scaler;
                fprintf('  ✓ GRU_scaler 加载成功 (%s)\n', scaler_files{i});
                break;
            end
        end
    end
end

assignin('base','gru_model',gru_model);
if ~isempty(gru_scaler)
    assignin('base','gru_scaler',gru_scaler);
end
fprintf('\n');

%% 步骤6：总结
fprintf('[步骤 6/6] 初始化总结\n');
fprintf('  ════════════════════════════════════════════════\n');
fprintf('  ✓ 基础参数:     已加载\n');
fprintf('  ✓ LPV 数据库:   %s (%d×%d×%d)\n', loaded_db_file, Nv, Nw, Nt);
fprintf('  ✓ MPCPlantBus:  已创建\n');
% fprintf('  ✓ 路径数据:     %d/%d\n', paths_loaded, numel(path_types));
fprintf('  ✓ GRU 模型:     就绪\n');
if maps_loaded
    fprintf('  ✓ maps_best:    已加载\n');
else
    fprintf('  ⚠ maps_best:    未加载\n');
end
if ~isempty(ctrl)
    fprintf('  ✓ MPC 控制器:   %s\n', ctrl_source);
else
    fprintf('  ❌ MPC 控制器:  未创建\n');
end
fprintf('  ════════════════════════════════════════════════\n');

if maps_loaded && ~isempty(ctrl)
    fprintf('\n✓ 初始化成功！使用优化权重与 GRU 调度\n');
elseif ~isempty(ctrl)
    fprintf('\n⚠ 初始化完成，使用默认权重\n');
else
    fprintf('\n❌ 初始化失败，请检查上方日志\n');
end
fprintf('\n[PreLoadFcn] 完成\n\n');