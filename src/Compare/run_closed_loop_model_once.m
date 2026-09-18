function out_file = run_closed_loop_model_once(model_name, path_file, out_file, cfg)
%RUN_CLOSED_LOOP_MODEL_ONCE Run one Simulink closed-loop model and save logsout.
%
% This helper intentionally saves an in-memory
% Simulink.SimulationData.Dataset, not a DatasetRef.  That keeps the output
% MAT file portable and readable by comparison scripts.

if nargin < 1 || isempty(model_name)
    model_name = 'LPVMPC_AGV_simulink_Modern_TCN';
end
if nargin < 2 || isempty(path_file)
    path_file = fullfile(local_project_root(), 'data', 'paths', ...
        'path_modern_tcn_demo_loop_v1.mat');
end
if nargin < 3 || isempty(out_file)
    [~, path_tag, ~] = fileparts(path_file);
    out_file = fullfile(local_project_root(), 'results', 'compare', ...
        'modern_tcn_gru_closed_loop', sprintf('%s_%s_out.mat', model_name, path_tag));
end
if nargin < 4
    cfg = struct();
end

root = local_project_root();
if exist('init_project', 'file') == 2
    init_project();
end

S = load(path_file, 'ref');
ref = S.ref;
if isfield(cfg, 'stop_time_override') && ~isempty(cfg.stop_time_override)
    stop_time_value = min(double(cfg.stop_time_override), double(ref.t(end)));
else
    stop_time_value = double(ref.t(end));
end
stop_time = num2str(stop_time_value);

out_dir = fileparts(out_file);
if ~isempty(out_dir) && exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end

if contains(model_name, 'Modern_TCN', 'IgnoreCase', true)
    clear ModernTCN_State_Classifier_sim ModernTCN_state_classifier ModernTCN_load_predictor
    if ~isfield(cfg, 'modern_tcn_sim_cfg')
        evalin('base', 'clear modern_tcn_sim_cfg');
    end
elseif contains(model_name, 'GRU', 'IgnoreCase', true)
    clear GRU_State_Classifier_gru_sim GRU_state_classifier GRU_load_default_to_base
    if ~isfield(cfg, 'gru_sim_cfg')
        evalin('base', 'clear gru_sim_cfg');
    end
elseif contains(model_name, 'TCN', 'IgnoreCase', true)
    clear TCN_State_Classifier_sim TCN_state_classifier TCN_load_predictor
    if ~isfield(cfg, 'tcn_sim_cfg')
        evalin('base', 'clear tcn_sim_cfg');
    end
end

assignin('base', 'ref', ref);
if isfield(cfg, 'modern_tcn_sim_cfg')
    assignin('base', 'modern_tcn_sim_cfg', cfg.modern_tcn_sim_cfg);
end
if isfield(cfg, 'gru_sim_cfg')
    assignin('base', 'gru_sim_cfg', cfg.gru_sim_cfg);
end
if isfield(cfg, 'tcn_sim_cfg')
    assignin('base', 'tcn_sim_cfg', cfg.tcn_sim_cfg);
end
if isfield(cfg, 'params_override') && ~isempty(cfg.params_override)
    assignin('base', 'params', cfg.params_override);
    assignin('base', 'parameters', cfg.params_override);
end
if isfield(cfg, 'ff_rt_override') && ~isempty(cfg.ff_rt_override)
    assignin('base', 'ff_rt', cfg.ff_rt_override);
end
if isfield(cfg, 'mpc_runtime_maps') && ~isempty(cfg.mpc_runtime_maps)
    assignin('base', 'mpc_runtime_maps', cfg.mpc_runtime_maps);
    local_assign_runtime_map_scalars(cfg.mpc_runtime_maps);
else
    evalin('base', 'clear mpc_runtime_maps');
    local_clear_runtime_map_scalars();
end
if isfield(cfg, 'mpc_runtime_override') && ~isempty(cfg.mpc_runtime_override)
    assignin('base', 'mpc_runtime_override', cfg.mpc_runtime_override);
else
    evalin('base', 'clear mpc_runtime_override');
end
if isfield(cfg, 'mpc_runtime_omega_cmd_clip') && ~isempty(cfg.mpc_runtime_omega_cmd_clip)
    assignin('base', 'mpc_runtime_omega_cmd_clip', double(cfg.mpc_runtime_omega_cmd_clip));
else
    evalin('base', 'clear mpc_runtime_omega_cmd_clip');
end

model_file = fullfile(root, 'simulink', [model_name '.slx']);
if isfield(cfg, 'model_file') && ~isempty(cfg.model_file)
    model_file = char(cfg.model_file);
    [~, model_name, ~] = fileparts(model_file);
end
if exist(model_file, 'file') ~= 2 && exist(model_file, 'file') ~= 4
    error('run_closed_loop_model_once:MissingModel', ...
        'Model file not found: %s', model_file);
end

load_system(model_file);
cleanup = onCleanup(@() local_close_model(model_name));

simIn = Simulink.SimulationInput(model_name);
simIn = simIn.setModelParameter('StopTime', stop_time);
simIn = local_set_variable_dual(simIn, model_name, 'ref', ref);
if isfield(cfg, 'modern_tcn_sim_cfg')
    simIn = local_set_variable_dual(simIn, model_name, ...
        'modern_tcn_sim_cfg', cfg.modern_tcn_sim_cfg);
end
if isfield(cfg, 'gru_sim_cfg')
    simIn = local_set_variable_dual(simIn, model_name, ...
        'gru_sim_cfg', cfg.gru_sim_cfg);
end
if isfield(cfg, 'tcn_sim_cfg')
    simIn = local_set_variable_dual(simIn, model_name, ...
        'tcn_sim_cfg', cfg.tcn_sim_cfg);
end
if isfield(cfg, 'params_override') && ~isempty(cfg.params_override)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'params', cfg.params_override);
    simIn = local_set_variable_dual(simIn, model_name, ...
        'parameters', cfg.params_override);
end
if isfield(cfg, 'ff_rt_override') && ~isempty(cfg.ff_rt_override)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'ff_rt', cfg.ff_rt_override);
end
if isfield(cfg, 'mpc_runtime_maps') && ~isempty(cfg.mpc_runtime_maps)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'mpc_runtime_maps', cfg.mpc_runtime_maps);
    simIn = local_set_runtime_map_scalars(simIn, model_name, cfg.mpc_runtime_maps);
end
if isfield(cfg, 'mpc_runtime_override') && ~isempty(cfg.mpc_runtime_override)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'mpc_runtime_override', cfg.mpc_runtime_override);
end
if isfield(cfg, 'mpc_runtime_omega_cmd_clip') && ~isempty(cfg.mpc_runtime_omega_cmd_clip)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'mpc_runtime_omega_cmd_clip', double(cfg.mpc_runtime_omega_cmd_clip));
end
if isfield(cfg, 'robustness_case') && ~isempty(cfg.robustness_case)
    simIn = local_set_variable_dual(simIn, model_name, ...
        'robustness_case', cfg.robustness_case);
end

fprintf('[closed-loop] sim %s, path=%s, StopTime=%s\n', ...
    model_name, path_file, stop_time);
simOut = sim(simIn);

logsout = local_materialize_dataset(simOut.logsout);
SimulationMetadata = simOut.SimulationMetadata; %#ok<NASGU>
local_save_closed_loop_output(out_file, logsout, SimulationMetadata);
fprintf('[closed-loop] saved: %s\n', out_file);
end

function local_save_closed_loop_output(out_file, logsout, SimulationMetadata)
out_dir = fileparts(out_file);
if ~isempty(out_dir) && exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
if exist(out_file, 'file') == 2
    d = dir(out_file);
    if ~isempty(d) && d.bytes == 0
        delete(out_file);
    end
end

% Keep the temporary MAT path short on Windows; nested output directories can
% make tempname(out_dir) exceed practical path limits during save().
tmp_file = [tempname(tempdir) '.mat'];
cleanup = onCleanup(@() local_delete_if_exists(tmp_file));
save(tmp_file, 'logsout', 'SimulationMetadata', '-v7.3');
if exist(out_file, 'file') == 2
    delete(out_file);
end
movefile(tmp_file, out_file, 'f');
delete(cleanup);
end

function local_delete_if_exists(file)
if exist(file, 'file') == 2
    delete(file);
end
end

function logsout = local_materialize_dataset(logs)
if isa(logs, 'Simulink.SimulationData.Dataset')
    logsout = logs;
    return;
end

if isa(logs, 'Simulink.SimulationData.DatasetRef')
    logsout = Simulink.SimulationData.Dataset;
    for i = 1:logs.numElements
        logsout = logsout.addElement(logs.get(i));
    end
    return;
end

error('run_closed_loop_model_once:BadLogsout', ...
    'Unsupported logsout class: %s', class(logs));
end

function simIn = local_set_variable_dual(simIn, model_name, var_name, var_value)
simIn = simIn.setVariable(var_name, var_value);
simIn = simIn.setVariable(var_name, var_value, 'Workspace', model_name);
end

function simIn = local_set_runtime_map_scalars(simIn, model_name, runtime_maps)
fields = local_runtime_map_scalar_fields();
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
    simIn = local_set_variable_dual(simIn, model_name, ...
        ['mpc_runtime_' field_name], value);
end
end

function local_assign_runtime_map_scalars(runtime_maps)
fields = local_runtime_map_scalar_fields();
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
    assignin('base', ['mpc_runtime_' field_name], value);
end
end

function local_clear_runtime_map_scalars()
fields = local_runtime_map_scalar_fields();
for i = 1:numel(fields)
    evalin('base', sprintf('clear mpc_runtime_%s', fields{i}));
end
end

function fields = local_runtime_map_scalar_fields()
fields = {'enable_weight_interp', 'Q_range', 'R_range', 'dR_range', ...
    'alpha_Q', 'beta_Q', 'alpha_R', 'beta_R', 'alpha_dR', 'beta_dR', ...
    'scale_umin_lo', 'scale_umin_hi', 'scale_umax_lo', 'scale_umax_hi', ...
    'rho_min', 'rho_max', 'tau', 'omega_threshold', 'q_y_gain_max', ...
    'q_psi_gain_max', 'q_omega_gain_max', ...
    'q_y_slope_gain_max', 'q_psi_slope_gain_max', ...
    'q_omega_slope_gain_max', ...
    'transition_width', 'theta_threshold', 'q_v_gain_max', ...
    'theta_transition_width', 'R_F_gain_max_uphill', ...
    'R_F_gain_max_downhill', 'dR_F_gain_max_uphill', ...
    'dR_F_gain_max_downhill', ...
    'vref_sched_enable', 'vref_slope_enable', ...
    'vref_turn_recovery_enable', 'vref_theta_threshold', ...
    'vref_theta_transition_width', 'vref_uphill_scale_min', ...
    'vref_downhill_scale_min', 'vref_turn_omega_threshold', ...
    'vref_turn_omega_width', 'vref_turn_hold_time', ...
    'vref_turn_scale_min', 'vref_min', ...
    'vref_tau_down', 'vref_tau_up', ...
    'umin_range', 'umax_range'};
end

function local_close_model(model_name)
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    this_file = mfilename('fullpath');
    root = fileparts(fileparts(fileparts(this_file)));
end
end
