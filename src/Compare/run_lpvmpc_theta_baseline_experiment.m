function result = run_lpvmpc_theta_baseline_experiment(cfg)
%RUN_LPVMPC_THETA_BASELINE_EXPERIMENT Run LPV-MPC theta-source baselines.
%
% Default experiment:
%   - same showcase path as the current ModernTCN/GRU/TCN closed-loop table
%   - same LPV-MPC controller and plant model
%   - theta_mode=1: nominal theta=0
%   - theta_mode=2: IMU theta estimate
%   - theta_mode=3: oracle true theta upper bound
%
% Example:
%   result = run_lpvmpc_theta_baseline_experiment();
%
% Smoke test:
%   cfg = struct('compare_with_learned', false, 'stop_time_override', 0.2);
%   cfg.modes = struct('tag', 'lpvmpc_theta0', 'label', 'LPV-MPC_theta0', 'value', 1);
%   result = run_lpvmpc_theta_baseline_experiment(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_apply_defaults(cfg, root);

S = load(cfg.path_file, 'ref');
if ~isfield(S, 'ref')
    error('run_lpvmpc_theta_baseline:MissingRef', ...
        'Path file has no ref variable: %s', cfg.path_file);
end
ref = S.ref;

if isempty(cfg.stop_time_override)
    stop_time = num2str(ref.t(end));
else
    stop_time = num2str(cfg.stop_time_override);
end

if exist(cfg.out_dir, 'dir') ~= 7
    mkdir(cfg.out_dir);
end

fprintf('\n[theta-baseline] path: %s\n', cfg.path_file);
fprintf('[theta-baseline] output: %s\n', cfg.out_dir);
fprintf('[theta-baseline] StopTime=%s, modes=%d\n\n', stop_time, numel(cfg.modes));

mode_runs = repmat(local_mode_run_template(), numel(cfg.modes), 1);
for i = 1:numel(cfg.modes)
    one = cfg.modes(i);
    fprintf('[theta-baseline] %d/%d %s (theta_mode=%g)\n', ...
        i, numel(cfg.modes), one.label, one.value);

    out_file = fullfile(cfg.out_dir, sprintf('%s_out.mat', one.tag));
    t0 = tic;
    try
        mode_runs(i).tag = string(one.tag);
        mode_runs(i).label = string(one.label);
        mode_runs(i).theta_mode = double(one.value);
        mode_runs(i).file = out_file;

        local_run_one_mode(cfg, ref, stop_time, one.value, out_file);

        mode_runs(i).status = "ok";
        mode_runs(i).elapsed_sec = toc(t0);
        fprintf('[theta-baseline] saved: %s\n', out_file);
    catch ME
        mode_runs(i).status = "error";
        mode_runs(i).message = string(ME.message);
        mode_runs(i).elapsed_sec = toc(t0);
        if cfg.stop_on_error
            rethrow(ME);
        end
        warning('run_lpvmpc_theta_baseline:ModeFailed', ...
            '%s failed: %s', one.label, ME.message);
    end
end

result = struct();
result.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.path_file = cfg.path_file;
result.out_dir = cfg.out_dir;
result.model_name = cfg.model_name;
result.mode_runs = mode_runs;
result.compare = [];

save(fullfile(cfg.out_dir, 'lpvmpc_theta_baseline_runs.mat'), 'result', '-v7.3');

if cfg.compare_with_learned
    ok_mask = arrayfun(@(r) strcmp(char(r.status), 'ok'), mode_runs);
    ok = mode_runs(ok_mask);
    extra_runs = repmat(struct('label', "", 'file', ""), 1, numel(ok));
    for i = 1:numel(ok)
        extra_runs(i).label = ok(i).label;
        extra_runs(i).file = ok(i).file;
    end

    result.compare = compare_tcn_gru_modern_closed_loop_out( ...
        cfg.learned_outputs.ModernTCN, ...
        cfg.learned_outputs.GRU, ...
        cfg.learned_outputs.TCN, ...
        cfg.path_file, ...
        cfg.out_dir, ...
        "ModernTCN", ...
        extra_runs, ...
        'ModernTCN、GRU、TCN 与 LPV-MPC theta 基线闭环对比报告', ...
        'tcn_gru_modern_lpvmpc_theta_baseline');

    save(fullfile(cfg.out_dir, 'lpvmpc_theta_baseline_runs.mat'), 'result', '-v7.3');
end

fprintf('\n[theta-baseline] done: %s\n', cfg.out_dir);
end

function cfg = local_apply_defaults(cfg, root)
if ~isfield(cfg, 'model_name') || isempty(cfg.model_name)
    cfg.model_name = 'LPVMPC_AGV_simulink_IMU';
end
if ~isfield(cfg, 'model_file') || isempty(cfg.model_file)
    cfg.model_file = fullfile(root, 'simulink', [cfg.model_name '.slx']);
end
if ~isfield(cfg, 'path_file') || isempty(cfg.path_file)
    cfg.path_file = fullfile(root, 'data', 'paths', ...
        'path_factory_logistics_showcase_theta10_v3.mat');
end
if ~isfield(cfg, 'out_dir') || isempty(cfg.out_dir)
    [~, path_tag] = fileparts(cfg.path_file);
    cfg.out_dir = fullfile(root, 'results', 'compare', ...
        'lpvmpc_theta_baseline', path_tag);
end
if ~isfield(cfg, 'mode_block') || isempty(cfg.mode_block)
    cfg.mode_block = [cfg.model_name '/Constant4'];
end
if ~isfield(cfg, 'modes') || isempty(cfg.modes)
    cfg.modes = [ ...
        struct('tag', 'lpvmpc_theta0', 'label', 'LPV-MPC_theta0', 'value', 1), ...
        struct('tag', 'lpvmpc_imu_theta', 'label', 'LPV-MPC_IMU_theta', 'value', 2), ...
        struct('tag', 'lpvmpc_oracle_theta', 'label', 'LPV-MPC_oracle_theta', 'value', 3)];
end
if ~isfield(cfg, 'compare_with_learned')
    cfg.compare_with_learned = true;
end
if ~isfield(cfg, 'learned_outputs') || ~isstruct(cfg.learned_outputs)
    cfg.learned_outputs = struct();
end
if ~isfield(cfg.learned_outputs, 'ModernTCN') || isempty(cfg.learned_outputs.ModernTCN)
    cfg.learned_outputs.ModernTCN = fullfile(root, 'ModernTCN_out.mat');
end
if ~isfield(cfg.learned_outputs, 'GRU') || isempty(cfg.learned_outputs.GRU)
    cfg.learned_outputs.GRU = fullfile(root, 'GRU_out.mat');
end
if ~isfield(cfg.learned_outputs, 'TCN') || isempty(cfg.learned_outputs.TCN)
    cfg.learned_outputs.TCN = fullfile(root, 'TCN_out.mat');
end
if ~isfield(cfg, 'stop_time_override')
    cfg.stop_time_override = [];
end
if ~isfield(cfg, 'params_override')
    cfg.params_override = [];
end
if ~isfield(cfg, 'stop_on_error')
    cfg.stop_on_error = true;
end

if exist(cfg.model_file, 'file') ~= 2 && exist(cfg.model_file, 'file') ~= 4
    error('run_lpvmpc_theta_baseline:MissingModel', ...
        'Model file not found: %s', cfg.model_file);
end
end

function local_run_one_mode(cfg, ref, stop_time, theta_mode, out_file)
assignin('base', 'preload_skip_gru_model', true);
assignin('base', 'theta_mode', double(theta_mode));
assignin('base', 'ref', ref);

had_override = evalin('base', 'exist(''mpc_runtime_override'', ''var'')==1');
had_runtime_maps = evalin('base', 'exist(''mpc_runtime_maps'', ''var'')==1');
old_override = [];
old_runtime_maps = [];
if had_override
    old_override = evalin('base', 'mpc_runtime_override');
end
if had_runtime_maps
    old_runtime_maps = evalin('base', 'mpc_runtime_maps');
end
cleanup_override = onCleanup(@() local_restore_base_var('mpc_runtime_override', had_override, old_override)); %#ok<NASGU>
cleanup_runtime_maps = onCleanup(@() local_restore_base_var('mpc_runtime_maps', had_runtime_maps, old_runtime_maps)); %#ok<NASGU>

runtime_override = local_runtime_override(cfg);
if ~isempty(runtime_override)
    assignin('base', 'mpc_runtime_override', runtime_override);
end

filegen_cleanup = [];
if ~isempty(runtime_override)
    filegen_cleanup = local_use_runtime_filegen_dir(cfg, runtime_override); %#ok<NASGU>
end

if bdIsLoaded(cfg.model_name)
    close_system(cfg.model_name, 0);
end
load_system(cfg.model_file);
cleanup = onCleanup(@() local_close_model(cfg.model_name));

ctrl_for_sim = local_ctrl_from_base(runtime_override);
runtime_maps_for_sim = local_runtime_maps_from_base();

simIn = Simulink.SimulationInput(cfg.model_name);
simIn = simIn.setModelParameter('StopTime', stop_time);
simIn = simIn.setVariable('preload_skip_gru_model', true);
simIn = simIn.setVariable('theta_mode', double(theta_mode));
simIn = simIn.setVariable('ref', ref);
simIn = simIn.setVariable('theta_mode', double(theta_mode), 'Workspace', cfg.model_name);
simIn = simIn.setVariable('ref', ref, 'Workspace', cfg.model_name);
if isfield(cfg, 'params_override') && ~isempty(cfg.params_override)
    simIn = simIn.setVariable('params', cfg.params_override);
    simIn = simIn.setVariable('params', cfg.params_override, 'Workspace', cfg.model_name);
    simIn = local_set_agv_sfunc_params_block(simIn, cfg.model_name, 'params');
end
if ~isempty(runtime_override)
    simIn = simIn.setVariable('mpc_runtime_override', runtime_override);
    simIn = simIn.setVariable('mpc_runtime_override', runtime_override, 'Workspace', cfg.model_name);
end
if ~isempty(ctrl_for_sim)
    simIn = local_set_ctrl_variables(simIn, cfg.model_name, ctrl_for_sim);
end
if ~isempty(runtime_maps_for_sim)
    simIn = local_set_runtime_maps(simIn, cfg.model_name, runtime_maps_for_sim);
end
simIn = simIn.setBlockParameter(cfg.mode_block, 'Value', 'theta_mode');

simOut = sim(simIn);
if isprop(simOut, 'ErrorMessage') && ~isempty(simOut.ErrorMessage)
    error('run_lpvmpc_theta_baseline:SimulationError', '%s', simOut.ErrorMessage);
end

logsout = local_materialize_dataset(simOut.logsout);
SimulationMetadata = simOut.SimulationMetadata; %#ok<NASGU>
theta_mode_used = double(theta_mode); %#ok<NASGU>
runtime_override_used = runtime_override; %#ok<NASGU>
local_save_output(out_file, logsout, SimulationMetadata, theta_mode_used, runtime_override_used);
end

function ctrl = local_ctrl_from_base(runtime_override)
ctrl = [];
has_ctrl = evalin('base', 'exist(''ctrl'', ''var'')==1');
if has_ctrl
    ctrl = evalin('base', 'ctrl');
end
if isempty(runtime_override)
    return;
end
if isempty(ctrl)
    error('run_lpvmpc_theta_baseline:MissingRuntimeCtrl', ...
        'Runtime override is active, but PreLoadFcn did not create ctrl.');
end
local_assert_ctrl_matches_override(ctrl, runtime_override);
end

function local_assert_ctrl_matches_override(ctrl, runtime_override)
if ~isfield(ctrl, 'meta') || ~isfield(ctrl.meta, 'Np') || ~isfield(ctrl.meta, 'Nc')
    error('run_lpvmpc_theta_baseline:BadRuntimeCtrl', ...
        'Runtime ctrl is missing meta.Np/meta.Nc.');
end
if ctrl.meta.Np ~= runtime_override.Np || ctrl.meta.Nc ~= runtime_override.Nc
    error('run_lpvmpc_theta_baseline:RuntimeCtrlMismatch', ...
        'Runtime ctrl horizon mismatch: ctrl=(%d,%d), override=(%d,%d).', ...
        ctrl.meta.Np, ctrl.meta.Nc, runtime_override.Np, runtime_override.Nc);
end
end

function simIn = local_set_ctrl_variables(simIn, model_name, ctrl)
simIn = simIn.setVariable('ctrl', ctrl);
simIn = simIn.setVariable('mpcobj', ctrl.mpcobj);
simIn = simIn.setVariable('maps', ctrl.maps);
simIn = simIn.setVariable('ctrl', ctrl, 'Workspace', model_name);
simIn = simIn.setVariable('mpcobj', ctrl.mpcobj, 'Workspace', model_name);
simIn = simIn.setVariable('maps', ctrl.maps, 'Workspace', model_name);
end

function simIn = local_set_agv_sfunc_params_block(simIn, model_name, value_expr)
blocks = find_system(model_name, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'BlockType', 'M-S-Function', 'FunctionName', 'agv_model_sfunc');
for i = 1:numel(blocks)
    simIn = simIn.setBlockParameter(blocks{i}, 'Parameters', value_expr);
end
end

function runtime_maps = local_runtime_maps_from_base()
runtime_maps = [];
has_maps = evalin('base', 'exist(''mpc_runtime_maps'', ''var'')==1');
if has_maps
    runtime_maps = evalin('base', 'mpc_runtime_maps');
end
end

function simIn = local_set_runtime_maps(simIn, model_name, runtime_maps)
simIn = simIn.setVariable('mpc_runtime_maps', runtime_maps);
simIn = simIn.setVariable('mpc_runtime_maps', runtime_maps, 'Workspace', model_name);
simIn = local_set_runtime_map_scalars(simIn, model_name, runtime_maps);
end

function simIn = local_set_runtime_map_scalars(simIn, model_name, runtime_maps)
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
    simIn = simIn.setVariable(var_name, value);
    simIn = simIn.setVariable(var_name, value, 'Workspace', model_name);
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

error('run_lpvmpc_theta_baseline:BadLogsout', ...
    'Unsupported logsout class: %s', class(logs));
end

function row = local_mode_run_template()
row = struct('tag', "", 'label', "", 'theta_mode', NaN, ...
    'file', "", 'status', "pending", 'message', "", 'elapsed_sec', NaN);
end

function local_close_model(model_name)
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
end

function local_save_output(out_file, logsout, SimulationMetadata, theta_mode_used, runtime_override_used)
out_dir = fileparts(out_file);
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
if exist(out_file, 'file') == 2
    delete(out_file);
end
% Keep the temporary MAT path short on Windows; deeply nested run directories
% can make tempname(out_dir) exceed practical path limits during save().
tmp_file = [tempname(tempdir) '.mat'];
cleanup = onCleanup(@() local_delete_if_exists(tmp_file)); %#ok<NASGU>
save(tmp_file, 'logsout', 'SimulationMetadata', 'theta_mode_used', ...
    'runtime_override_used', '-v7.3');
movefile(tmp_file, out_file, 'f');
end

function local_delete_if_exists(file_name)
if exist(file_name, 'file') == 2
    delete(file_name);
end
end

function runtime_override = local_runtime_override(cfg)
runtime_override = [];
if isfield(cfg, 'runtime_override') && ~isempty(cfg.runtime_override)
    runtime_override = cfg.runtime_override;
end
if isfield(cfg, 'candidate') && ~isempty(cfg.candidate)
    if isempty(runtime_override)
        runtime_override = cfg.candidate;
    else
        runtime_override = local_merge_struct(runtime_override, cfg.candidate);
    end
end
if isempty(runtime_override)
    return;
end
runtime_override = local_normalize_runtime_override(runtime_override);
end

function out = local_merge_struct(base, override)
out = base;
if isempty(override) || ~isstruct(override)
    return;
end
fields = fieldnames(override);
for i = 1:numel(fields)
    out.(fields{i}) = override.(fields{i});
end
end

function out = local_normalize_runtime_override(in)
if isempty(in)
    out = [];
    return;
end

required = {'Np', 'Nc', 'Q', 'R', 'dR'};
for i = 1:numel(required)
    if ~isfield(in, required{i}) || isempty(in.(required{i}))
        error('run_lpvmpc_theta_baseline:BadOverride', ...
            'Missing runtime override field: %s', required{i});
    end
end

out = in;
if ~isfield(out, 'id') || isempty(out.id)
    out.id = sprintf('candidate_np%d_nc%d', out.Np, out.Nc);
end
out.id = char(string(out.id));
out.Np = double(out.Np);
out.Nc = double(out.Nc);
out.Q = double(reshape(out.Q, 1, []));
out.R = double(reshape(out.R, 1, []));
out.dR = double(reshape(out.dR, 1, []));
out = local_normalize_override_optional(out);

if numel(out.Q) ~= 4 || numel(out.R) ~= 2 || numel(out.dR) ~= 2
    error('run_lpvmpc_theta_baseline:BadOverrideShape', ...
        'Expected Q(1x4), R(1x2), dR(1x2) in runtime override.');
end

if ~isfield(out, 'maps_template') || isempty(out.maps_template)
    out.maps_template = struct();
end
end

function out = local_normalize_override_optional(out)
vector_fields = {'umin', 'umax', 'dumin', 'dumax', 'ymin', 'ymax'};
for i = 1:numel(vector_fields)
    name = vector_fields{i};
    if isfield(out, name) && ~isempty(out.(name))
        out.(name) = double(out.(name)(:));
    end
end

scalar_fields = {'soft_weight_pos', 'soft_weight_yaw', 'tau'};
for i = 1:numel(scalar_fields)
    name = scalar_fields{i};
    if isfield(out, name) && ~isempty(out.(name))
        out.(name) = double(out.(name));
    end
end
end

function local_restore_base_var(name, had_value, old_value)
if had_value
    assignin('base', name, old_value);
else
    evalin('base', sprintf('clear %s', name));
end
end

function cleanup = local_use_runtime_filegen_dir(cfg, runtime_override)
cleanup = [];
try
    old_cfg = Simulink.fileGenControl('getConfig');
    base_dir = local_runtime_filegen_base_dir(cfg);
    tag = local_safe_filegen_tag(runtime_override.id);
    cache_dir = fullfile(base_dir, tag, 'cache');
    codegen_dir = fullfile(base_dir, tag, 'codegen');
    if exist(cache_dir, 'dir') ~= 7
        mkdir(cache_dir);
    end
    if exist(codegen_dir, 'dir') ~= 7
        mkdir(codegen_dir);
    end
    Simulink.fileGenControl('set', ...
        'CacheFolder', cache_dir, ...
        'CodeGenFolder', codegen_dir, ...
        'createDir', true, ...
        'keepPreviousPath', true);
    cleanup = onCleanup(@() Simulink.fileGenControl('setConfig', 'config', old_cfg));
catch ME
    warning('run_lpvmpc_theta_baseline:RuntimeFileGenDirFailed', ...
        'Could not isolate runtime Simulink file generation directory: %s', ME.message);
end
end

function base_dir = local_runtime_filegen_base_dir(cfg)
if isfield(cfg, 'runtime_filegen_dir') && ~isempty(cfg.runtime_filegen_dir)
    base_dir = char(string(cfg.runtime_filegen_dir));
else
    base_dir = fullfile(tempdir(), 'mpc_rt_fg');
end
end

function tag = local_safe_filegen_tag(id)
tag = regexprep(char(string(id)), '[^A-Za-z0-9_=-]', '_');
if isempty(tag)
    tag = 'candidate';
end
tag = tag(1:min(numel(tag), 80));
end
