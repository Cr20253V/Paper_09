function preloadfcn_gru(mode)
% PreLoadFcn - standalone learned-model preload.
% Design goal:
%   - Do not call preloadfcn_v2/preloadfcn_v1.
%   - Keep the same 0-5 initialization flow as v2.
%   - Only differ at Step 4 by selecting the frozen GRU or ModernTCN model.

if nargin < 1 || isempty(mode)
    mode = 'gru';
end
mode = lower(char(mode));
if ~ismember(mode, {'gru', 'modern_tcn', 'tcn'})
    error('preloadfcn_gru:BadMode', 'Unknown preload mode: %s', mode);
end

switch mode
    case 'modern_tcn'
        title_text = 'LPVMPC_AGV preload (ModernTCN standalone)';
    case 'tcn'
        title_text = 'LPVMPC_AGV preload (TCN standalone)';
    otherwise
        title_text = 'LPVMPC_AGV preload (GRU standalone)';
end

fprintf('\n');
fprintf('============================================================\n');
fprintf('%s\n', title_text);
fprintf('============================================================\n\n');

%% Bootstrap path + directory config
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

%% Target horizons
TARGET_NP = 150;
TARGET_NC = 30;
runtime_override = local_runtime_override_from_base();
runtime_override_active = ~isempty(runtime_override);
if runtime_override_active
    TARGET_NP = runtime_override.Np;
    TARGET_NC = runtime_override.Nc;
end

%% Step 0: Load basic params
fprintf('[Step 0/5] Load basic parameters...\n');
try
    params = parameters();
    fprintf('  OK parameters() (Ts=%.3fs, m=%.1fkg, L=%.2fm)\n', ...
        params.Ts, params.mass, params.L);
catch ME
    warning('preloadfcn_gru:ParametersFailed', '%s', ME.message);
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

%% Step 1: Load LPV database
fprintf('[Step 1/5] Load LPV database...\n');
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
            fprintf('  OK file loaded: %s\n', db_files{i});
            break;
        catch ME
            fprintf('  WARN load failed %s: %s\n', db_files{i}, ME.message);
        end
    end
end

if isempty(S)
    error('[PreLoadFcn] LPV database not found.');
end

if isfield(S,'db') && isstruct(S.db)
    db_data = S.db;
    fprintf('  use db struct format\n');
elseif all(isfield(S, {'A','B','C','D','E'}))
    db_data = S;
    fprintf('  use top-level field format\n');
else
    error('[PreLoadFcn] Unrecognized DB format (fields: %s)', strjoin(fieldnames(S), ', '));
end

req = {'A','B','C','D','E','Ts','grid'};
missing = req(~isfield(db_data, req));
if ~isempty(missing)
    error('[PreLoadFcn] DB missing fields: %s', strjoin(missing, ', '));
end

A=db_data.A; B=db_data.B; C=db_data.C; D=db_data.D; E=db_data.E;
Ts=db_data.Ts; grid=db_data.grid;
nx=size(A,4); nu=size(B,5); ny=size(C,4); nd=size(E,5);
Nv=size(A,1); Nw=size(A,2); Nt=size(A,3);

fprintf('  OK grid %d x %d x %d, nx=%d, nu=%d, nd=%d, Ts=%.3fs\n', ...
    Nv, Nw, Nt, nx, nu, nd, Ts);

db_rt = struct('A',A,'B',B,'C',C,'D',D,'E',E, ...
    'grid',grid,'Ts',Ts,'nx',nx,'nu',nu,'ny',ny,'nd',nd, ...
    'Nv',Nv,'Nw',Nw,'Nt',Nt);
assignin('base','db_rt',db_rt);
assignin(mw,'db_rt',db_rt);
fprintf('\n');

%% Step 2: Create MPCPlantBus
fprintf('[Step 2/5] Create MPCPlantBus...\n');
nu_md = nu + nd;
samplePlant = struct('A',zeros(nx,nx),'B',zeros(nx,nu_md), ...
    'C',zeros(ny,nx),'D',zeros(ny,nu_md),'U',zeros(nu_md,1), ...
    'X',zeros(nx,1),'Y',zeros(ny,1),'DX',zeros(nx,1),'Ts',Ts);
info = Simulink.Bus.createObject(samplePlant);
assignin('base','MPCPlantBus', evalin('base', info.busName));
if ~strcmp(info.busName,'MPCPlantBus')
    evalin('base', sprintf('clear %s;', info.busName));
end
assignin('base','plant_ic', samplePlant);
fprintf('  OK MPCPlantBus created (nu_md=%d = %d MV + %d MD)\n\n', nu_md, nu, nd);

%% Step 3: Load BO maps / build ctrl
fprintf('[Step 3/5] Load BO maps / ctrl...\n');
bo_results_dir = fullfile(results_root, 'bo_results');
workflow_mpc_dir = fullfile(root, 'results', 'paper', ...
    'agv_model_parameter_correction_workflow', '06_mpc_retuning', ...
    'p0_oracle_retuning_20260602_033639');
base_dirs_mb = {workflow_mpc_dir, bo_results_dir, data_models_dir, root, ''};
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

            if isfield(Tm, 'best')
                if isfield(Tm.best, 'ctrl_maps')
                    maps_best = Tm.best.ctrl_maps;
                    maps_best.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
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
                fprintf('  OK BO maps loaded (%s)\n', fname);
                break;
            end
        catch ME
            fprintf('  WARN map load failed %s: %s\n', maps_files{i}, ME.message);
        end
    end
end
if ~maps_loaded
    fprintf('  WARN no phase2_best/phase1_best found, use defaults\n');
end

if runtime_override_active
    maps_best = local_apply_runtime_override_to_maps(maps_best, runtime_override, db_rt);
    maps_loaded = true;
    maps_source_file = '[runtime_override]';
    fprintf('  use runtime MPC override: %s\n', runtime_override.id);
end

ctrl = [];
ctrl_source = 'not created';
ctrl_file_path = fullfile(data_models_dir, 'ctrl.mat');

if ~runtime_override_active && exist(ctrl_file_path, 'file')
    try
        Tc = load(ctrl_file_path);
        if isfield(Tc, 'ctrl')
            if isfield(Tc.ctrl, 'meta') && isfield(Tc.ctrl.meta, 'Np') && isfield(Tc.ctrl.meta, 'Nc')
                old_Np = Tc.ctrl.meta.Np;
                old_Nc = Tc.ctrl.meta.Nc;
                if old_Np == TARGET_NP && old_Nc == TARGET_NC
                    ctrl = Tc.ctrl;
                    ctrl_source = ctrl_file_path;
                    fprintf('  OK ctrl loaded (Np=%d, Nc=%d)\n', old_Np, old_Nc);
                else
                    fprintf('  WARN old ctrl Np=%d, Nc=%d, rebuild target Np=%d, Nc=%d\n', ...
                        old_Np, old_Nc, TARGET_NP, TARGET_NC);
                end
            else
                fprintf('  WARN ctrl.meta.Np/meta.Nc missing, rebuild\n');
            end
        end
    catch ME
        fprintf('  WARN ctrl load failed: %s\n', ME.message);
    end
end

if isempty(ctrl) && exist('mpc_setup_single_interp','file')==2
    fprintf('  create new ctrl (Np=%d, Nc=%d)...\n', TARGET_NP, TARGET_NC);

    if runtime_override_active
        Q_base = runtime_override.Q;
        R_base = runtime_override.R;
        dR_base = runtime_override.dR;
        fprintf('    use runtime override weights\n');
    elseif maps_loaded && all(isfield(maps_best, {'Q_range','R_range','dR_range'}))
        Q_base = mean(maps_best.Q_range, 1);
        R_base = mean(maps_best.R_range, 1);
        dR_base = mean(maps_best.dR_range, 1);
        fprintf('    use optimized BO weights\n');
    else
        Q_base = [100, 100, 15, 3];
        R_base = [3e-5, 3e-5];
        dR_base = [1e-3, 1e-3];
        fprintf('    use P0 oracle-MPC defaults\n');
    end

    mpc_opts = struct('Np', TARGET_NP, 'Nc', TARGET_NC, ...
                      'Q', Q_base, 'R', R_base, 'dR', dR_base);
    if runtime_override_active
        mpc_opts = local_apply_runtime_override_to_mpc_opts(mpc_opts, runtime_override);
    end

    ctrl = mpc_setup_single_interp(db_rt, mpc_opts);
    ctrl_source = 'created';
    fprintf('  OK ctrl created (P=%.2fs, M=%.2fs)\n', ...
        ctrl.meta.prediction_horizon_sec, ctrl.meta.control_horizon_sec);

    if runtime_override_active
        fprintf('  runtime override active, skip ctrl.mat write\n');
    else
        try
            save(ctrl_file_path, 'ctrl');
            fprintf('  saved ctrl.mat\n');
        catch ME
            fprintf('  WARN save ctrl.mat failed: %s\n', ME.message);
        end
    end
end

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
    fprintf('  copied %d BO map fields to ctrl.maps\n', copied);
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
    ctrl.meta.sync_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    if runtime_override_active
        fprintf('  runtime override active, skip ctrl.mat map write\n');
    else
        try
            save(ctrl_file_path, 'ctrl');
            fprintf('  saved ctrl.mat after P0 map injection\n');
        catch ME
            fprintf('  WARN save ctrl.mat after map injection failed: %s\n', ME.message);
        end
    end
end

if ~isempty(ctrl)
    runtime_maps = local_codegen_runtime_maps(ctrl.maps);
    assignin('base', 'ctrl', ctrl);
    assignin('base', 'mpcobj', ctrl.mpcobj);
    assignin('base', 'maps', ctrl.maps);
    assignin('base', 'mpc_runtime_maps', runtime_maps);
    assignin(mw, 'ctrl', ctrl);
    assignin(mw, 'mpcobj', ctrl.mpcobj);
    assignin(mw, 'maps', ctrl.maps);
    assignin(mw, 'mpc_runtime_maps', runtime_maps);
    local_assign_runtime_map_scalars(runtime_maps, mw);
else
    warning('[PreLoadFcn] Unable to create/load ctrl');
end
fprintf('\n');

%% Step 4: Load/configure learned model
if strcmp(mode, 'modern_tcn')
    fprintf('[Step 4/5] Configure ModernTCN model...\n');
    modern_tcn_cfg = ModernTCN_default_config(root);
    if evalin('base', 'exist(''modern_tcn_sim_cfg'', ''var'')==1')
        external_cfg = evalin('base', 'modern_tcn_sim_cfg');
        if isstruct(external_cfg)
            modern_tcn_cfg = merge_struct_fields(modern_tcn_cfg, external_cfg);
            fprintf('  use external modern_tcn_sim_cfg override\n');
        end
    end
    if exist(modern_tcn_cfg.dataset_file, 'file') ~= 2
        error('[PreLoadFcn] ModernTCN dataset not found: %s', modern_tcn_cfg.dataset_file);
    end
    if exist(modern_tcn_cfg.onnx_file, 'file') ~= 2
        error('[PreLoadFcn] ModernTCN ONNX not found: %s', modern_tcn_cfg.onnx_file);
    end

    assignin('base', 'modern_tcn_sim_cfg', modern_tcn_cfg);
    assignin('base', 'modern_tcn_default_cfg', modern_tcn_cfg);
    assignin(mw, 'modern_tcn_sim_cfg', modern_tcn_cfg);
    assignin(mw, 'modern_tcn_default_cfg', modern_tcn_cfg);

    info = struct();
    info.seed = modern_tcn_cfg.seed;
    info.run_tag = modern_tcn_cfg.run_tag;
    info.dataset_file = modern_tcn_cfg.dataset_file;
    info.onnx_file = modern_tcn_cfg.onnx_file;
    info.time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    assignin('base', 'modern_tcn_preload_info', info);
    assignin(mw, 'modern_tcn_preload_info', info);
    active_model_label = 'ModernTCN model';
    fprintf('  OK ModernTCN config frozen: seed=%d\n', modern_tcn_cfg.seed);
    fprintf('  ONNX: %s\n', modern_tcn_cfg.onnx_file);
    fprintf('  dataset: %s\n', modern_tcn_cfg.dataset_file);
elseif strcmp(mode, 'tcn')
    fprintf('[Step 4/5] Configure TCN model...\n');
    tcn_cfg = TCN_default_config(root);
    if evalin('base', 'exist(''tcn_sim_cfg'', ''var'')==1')
        external_cfg = evalin('base', 'tcn_sim_cfg');
        if isstruct(external_cfg)
            tcn_cfg = merge_struct_fields(tcn_cfg, external_cfg);
            fprintf('  use external tcn_sim_cfg override\n');
        end
    end
    if exist(tcn_cfg.dataset_file, 'file') ~= 2
        error('[PreLoadFcn] TCN dataset not found: %s', tcn_cfg.dataset_file);
    end
    if exist(tcn_cfg.model_file, 'file') ~= 2
        error('[PreLoadFcn] TCN model not found: %s', tcn_cfg.model_file);
    end

    assignin('base', 'tcn_sim_cfg', tcn_cfg);
    assignin('base', 'tcn_default_cfg', tcn_cfg);
    assignin(mw, 'tcn_sim_cfg', tcn_cfg);
    assignin(mw, 'tcn_default_cfg', tcn_cfg);

    info = struct();
    info.seed = tcn_cfg.seed;
    info.case_name = tcn_cfg.case_name;
    info.run_tag = tcn_cfg.run_tag;
    info.dataset_file = tcn_cfg.dataset_file;
    info.model_file = tcn_cfg.model_file;
    info.meta_file = tcn_cfg.meta_file;
    info.time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    assignin('base', 'tcn_preload_info', info);
    assignin(mw, 'tcn_preload_info', info);
    active_model_label = 'TCN model';
    fprintf('  OK TCN config frozen: seed=%d\n', tcn_cfg.seed);
    fprintf('  model: %s\n', tcn_cfg.model_file);
    fprintf('  dataset: %s\n', tcn_cfg.dataset_file);
else
    fprintf('[Step 4/5] Load GRU model...\n');
    gru_cfg = GRU_default_config(root);
    if evalin('base', 'exist(''gru_sim_cfg'', ''var'')==1')
        external_cfg = evalin('base', 'gru_sim_cfg');
        if isstruct(external_cfg)
            gru_cfg = merge_struct_fields(gru_cfg, external_cfg);
            fprintf('  use external gru_sim_cfg override\n');
        end
    end
    model_candidates = {
        gru_cfg.model_file
        fullfile(data_models_dir, 'GRU_model_gru_v4_industrial_inputstats_hidden96_seed101.mat')
        fullfile(data_models_dir, 'GRU_model_gru_v4_industrial_inputstats_hidden96_seed21.mat')
        fullfile(data_models_dir, 'GRU_model_gru_v4_industrial_inputstats_hidden96_seed42.mat')
        fullfile(data_models_dir, 'GRU_model_mamba_control_strict.mat')
        fullfile(data_models_dir, 'GRU_model_mamba_control.mat')
        fullfile(data_models_dir, 'GRU_model.mat')
        fullfile(data_gru_dir, 'GRU_model.mat')
        fullfile(root, 'GRU_model.mat')
    };
    model_candidates = unique(model_candidates, 'stable');

    meta_candidates = {
        gru_cfg.meta_file
        fullfile(data_models_dir, 'GRU_meta_gru_v4_industrial_inputstats_hidden96_seed101.mat')
        fullfile(data_models_dir, 'GRU_meta_gru_v4_industrial_inputstats_hidden96_seed21.mat')
        fullfile(data_models_dir, 'GRU_meta_gru_v4_industrial_inputstats_hidden96_seed42.mat')
        fullfile(data_models_dir, 'GRU_meta_mamba_control_strict.mat')
        fullfile(data_models_dir, 'GRU_meta_mamba_control.mat')
        fullfile(data_models_dir, 'GRU_meta.mat')
    };
    meta_candidates = unique(meta_candidates, 'stable');

    scaler_candidates = {
        fullfile(data_gru_dir, 'GRU_scaler.mat')
        fullfile(data_models_dir, 'GRU_scaler.mat')
        fullfile(root, 'GRU_scaler.mat')
    };
    scaler_candidates = unique(scaler_candidates, 'stable');

    model_file = pick_first_existing(model_candidates);
    if isempty(model_file)
        error('[PreLoadFcn] No GRU model file found.');
    end

    Sg = load(model_file);
    gru_model = extract_preferred_field(Sg, {'gru_model', 'model', 'net'});
    assignin('base', 'gru_model', gru_model);
    assignin(mw, 'gru_model', gru_model);
    fprintf('  OK GRU model loaded: %s\n', model_file);

    meta_file = pick_first_existing(meta_candidates);
    if ~isempty(meta_file)
        Sm = load(meta_file);
        gru_meta = extract_preferred_field(Sm, {'gru_meta', 'meta'});
        assignin('base', 'gru_meta', gru_meta);
        assignin(mw, 'gru_meta', gru_meta);
        fprintf('  OK GRU meta loaded: %s\n', meta_file);
    end

    gru_scaler = [];
    if isstruct(gru_model) && isfield(gru_model, 'scaler')
        gru_scaler = gru_model.scaler;
    end
    if isempty(gru_scaler)
        scaler_file = pick_first_existing(scaler_candidates);
        if ~isempty(scaler_file)
            Ss = load(scaler_file);
            if isfield(Ss, 'scaler')
                gru_scaler = Ss.scaler;
                fprintf('  OK GRU scaler loaded: %s\n', scaler_file);
            end
        end
    end
    if ~isempty(gru_scaler)
        assignin('base', 'gru_scaler', gru_scaler);
        assignin(mw, 'gru_scaler', gru_scaler);
    end

    info = struct();
    info.seed = gru_cfg.seed;
    info.case_name = gru_cfg.case_name;
    info.run_tag = gru_cfg.run_tag;
    info.dataset_file = gru_cfg.dataset_file;
    info.model_file = model_file;
    info.meta_file = meta_file;
    info.time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    assignin('base', 'gru_preload_info', info);
    assignin(mw, 'gru_preload_info', info);
    active_model_label = 'GRU model';
    fprintf('  OK GRU config frozen: seed=%d\n', gru_cfg.seed);
    fprintf('  dataset: %s\n', gru_cfg.dataset_file);
end
fprintf('\n');

%% Step 5: Summary
fprintf('[Step 5/5] Summary\n');
fprintf('  ================================================\n');
fprintf('  basic params:   loaded (Ts=%.3fs)\n', params.Ts);
fprintf('  LPV database:   %s (%d x %d x %d)\n', loaded_db_file, Nv, Nw, Nt);
fprintf('  MPCPlantBus:    created\n');
fprintf('  %-15s ready\n', [active_model_label ':']);

if maps_loaded
    [~, fname, ~] = fileparts(maps_source_file);
    fprintf('  BO maps:        loaded (%s)\n', fname);
else
    fprintf('  BO maps:        not loaded (defaults used)\n');
end

if ~isempty(ctrl)
    fprintf('  MPC controller: %s (Np=%d, Nc=%d)\n', ctrl_source, ctrl.meta.Np, ctrl.meta.Nc);
else
    fprintf('  MPC controller: not created\n');
end
fprintf('  ================================================\n');

if maps_loaded && ~isempty(ctrl)
    fprintf('\nInitialization completed (optimized BO maps + %s).\n', active_model_label);
elseif ~isempty(ctrl)
    fprintf('\nInitialization completed (default weights + %s).\n', active_model_label);
else
    fprintf('\nInitialization failed: check logs above.\n');
end

fprintf('\n[preloadfcn_%s] done\n\n', mode);
end

function path_out = pick_first_existing(candidates)
    path_out = '';
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file') == 2
            path_out = candidates{i};
            return;
        end
    end
end

function value = extract_preferred_field(s, preferred_names)
    for i = 1:numel(preferred_names)
        key = preferred_names{i};
        if isfield(s, key)
            value = s.(key);
            return;
        end
    end

    names = fieldnames(s);
    if isempty(names)
        error('preloadfcn_gru:EmptyMat', 'MAT file has no variables.');
    end
    value = s.(names{1});
end

function out = merge_struct_fields(base, override)
    out = base;
    fields = fieldnames(override);
    for i = 1:numel(fields)
        out.(fields{i}) = override.(fields{i});
    end
end

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
        error('preloadfcn_gru:BadRuntimeOverride', ...
            'mpc_runtime_override missing field: %s', required{i});
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

function range = local_center_to_range(center)
center = double(reshape(center, 1, []));
range = [center; center];
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
    value = maps_in.(name);
    if islogical(value)
        runtime_maps.(name) = logical(value);
    elseif isnumeric(value)
        runtime_maps.(name) = double(value);
    end
end
end

function local_assign_runtime_map_scalars(runtime_maps, mw)
if isempty(runtime_maps) || ~isstruct(runtime_maps)
    return;
end
fields = fieldnames(runtime_maps);
for i = 1:numel(fields)
    value = runtime_maps.(fields{i});
    if ~(isnumeric(value) || islogical(value))
        continue;
    end
    var_name = ['mpc_runtime_' fields{i}];
    assignin('base', var_name, value);
    assignin(mw, var_name, value);
end
end
