function result = create_a3_isolated_model(force)
%CREATE_A3_ISOLATED_MODEL Copy and patch the Node26 model inside A3 only.

if nargin < 1, force = false; end
root = project_root();
a3 = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '03_A3_slope_scheduling_necessity');
src = fullfile(root, 'simulink', 'LPVMPC_AGV_simulink_Modern_TCN_44_rhofmd.slx');
dst = fullfile(a3, '00_protocol_lock', 'a3.slx');
audit_file = fullfile(a3, '00_protocol_lock', 'isolated_model_structure_audit.json');
cache = fullfile(a3, 'c');
if exist(cache, 'dir') ~= 7, mkdir(cache); end
Simulink.fileGenControl('set', 'CacheFolder', cache, 'CodeGenFolder', cache);

if ~force && ismember(exist(dst, 'file'), [2 4]) && exist(audit_file, 'file') == 2
    result = jsondecode(fileread(audit_file));
    if isfield(result, 'status') && strcmp(result.status, 'PASS')
        fprintf('[A3 model] reuse audited isolated model: %s\n', dst);
        return;
    end
end

if ~ismember(exist(src, 'file'), [2 4])
    error('A3:MissingSourceModel', 'Missing source model: %s', src);
end
if force || ~ismember(exist(dst, 'file'), [2 4])
    copyfile(src, dst, 'f');
end

% Keep even the first load on an explicit runtime override, avoiding shared
% controller-cache writes by preloadfcn_v2 after the model is patched.
runtime = local_runtime_override(root);
assignin('base', 'mpc_runtime_override', runtime);
assignin('base', 'a3_theta_mode', 1.0);

[~, model] = fileparts(dst);
load_system(dst);
cleanup = onCleanup(@() local_close(model)); %#ok<NASGU>
set_param(model, 'PreLoadFcn', 'preloadfcn_v2');

rt = sfroot;
charts = rt.find('-isa', 'Stateflow.EMChart');
classifier_path = '';
guard_path = '';
rho_path = '';
update_path = '';
guard_parameter_present = false;
for i = 1:numel(charts)
    chart = charts(i);
    if ~strcmp(bdroot(chart.Path), model), continue; end
    script = char(chart.Script);
    if contains(script, 'ModernTCN_State_Classifier_sim') || contains(script, 'A3_Causal_IMU_Theta_sim')
        chart.Script = sprintf([ ...
            'function [theta_hat, label_main, label_turn, conf_main] = ModernTCN_State_Classifier(y_raw, reset)\n' ...
            '%%#codegen\n' ...
            'coder.extrinsic(''A3_Causal_IMU_Theta_sim'');\n' ...
            'theta_hat = 0.0;\n' ...
            'theta_hat = A3_Causal_IMU_Theta_sim(y_raw, reset);\n' ...
            'label_main = 1.0;\nlabel_turn = 0.0;\nconf_main = 1.0;\nend\n']);
        classifier_path = chart.Path;
    elseif contains(script, 'function theta_sched = ThetaScheduleGuard')
        chart.Script = sprintf([ ...
            'function theta_sched = ThetaScheduleGuard(theta_ref, theta_hat, gru_vec)\n' ...
            '%%#codegen\n' ...
            '%% A3 frozen mode: 1=ZS, 2=causal IMU, 3=Oracle. gru_vec is intentionally unused.\n' ...
            'mode = round(double(a3_theta_mode(1)));\n' ...
            'theta_lim = deg2rad(12.0);\n' ...
            'theta_ref_scalar = double(theta_ref(1));\n' ...
            'theta_hat_scalar = double(theta_hat(1));\n' ...
            'theta_sched = 0.0;\n' ...
            'if mode == 1\n' ...
            '    theta_sched = 0.0;\n' ...
            'elseif mode == 2\n' ...
            '    theta_sched = min(theta_lim, max(-theta_lim, theta_hat_scalar));\n' ...
            'elseif mode == 3\n' ...
            '    theta_sched = min(theta_lim, max(-theta_lim, theta_ref_scalar));\n' ...
            'else\n' ...
            '    theta_sched = 0.0;\n' ...
            'end\nend\n']);
        local_ensure_parameter(chart, 'a3_theta_mode');
        local_set_guard_shapes(chart);
        guard_parameter_present = ~isempty(chart.find('-isa','Stateflow.Data', ...
            'Name','a3_theta_mode'));
        guard_path = chart.Path;
    elseif strcmp(chart.Name, 'RhoFilter')
        rho_path = chart.Path;
    elseif strcmp(chart.Name, 'UpdatePlantModel')
        update_path = chart.Path;
    end
end

save_system(model, dst);

sfunc_blocks = find_system(model, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'BlockType', 'M-S-Function');
sfunc_ok = false;
for i = 1:numel(sfunc_blocks)
    try
        sfunc_ok = sfunc_ok || strcmp(get_param(sfunc_blocks{i}, 'FunctionName'), 'agv_model_sfunc');
    catch
    end
end

result = struct();
result.task_id = 'A3';
result.status = 'PASS';
result.source_model = src;
result.isolated_model = dst;
result.preloadfcn = get_param(model, 'PreLoadFcn');
result.classifier_chart = classifier_path;
result.theta_guard_chart = guard_path;
result.rho_filter_chart = rho_path;
result.update_plant_chart = update_path;
result.guard_parameter_present = guard_parameter_present;
result.plant_sfunc_is_agv_model_sfunc = sfunc_ok;
result.only_mode_dependent_quantity = 'ThetaScheduleGuard input before common RhoFilter';
result.fixed_gru_vec = [1 0 1];
result.theta_sched_log_contract = 'diag.rho_f(:,3)';
result.status = local_status(result);
local_write_json(audit_file, result);
if ~strcmp(result.status, 'PASS')
    error('A3:ModelAuditFailed', 'Isolated model audit failed: %s', result.status);
end
fprintf('[A3 model] PASS: %s\n', dst);
end

function local_ensure_parameter(chart, name)
items = chart.find('-isa', 'Stateflow.Data', 'Name', name);
if isempty(items)
    d = Stateflow.Data(chart);
    d.Name = name;
    d.Scope = 'Parameter';
    d.DataType = 'double';
    d.Props.Array.Size = '[1 1]';
else
    for i = 1:numel(items)
        items(i).Scope = 'Parameter';
        items(i).DataType = 'double';
        items(i).Props.Array.Size = '[1 1]';
    end
end
end

function local_set_guard_shapes(chart)
spec = {'theta_ref','[1 1]'; 'theta_hat','[1 1]'; ...
    'theta_sched','[1 1]'; 'gru_vec','[3 1]'};
for i = 1:size(spec,1)
    item = chart.find('-isa','Stateflow.Data','Name',spec{i,1});
    if isempty(item), continue; end
    item(1).DataType = 'double';
    item(1).Props.Array.Size = spec{i,2};
end
end

function runtime = local_runtime_override(root)
maps_file = fullfile(root, 'results', 'paper', 'agv_model_parameter_correction_workflow', ...
    '06_mpc_retuning', 'maps_best_agv_physics_v2_plantfix_stage1.mat');
db_file = fullfile(root, 'results', 'paper', 'agv_model_parameter_correction_workflow', ...
    '04_lpv_database', 'lin_agv_db_agv_physics_v2_plantfix.mat');
S = load(maps_file, 'maps_best');
runtime = struct('id', 'A3_A0_frozen_Np150_Nc30_plantfix', ...
    'Np', 150, 'Nc', 30, 'Q', [100 100 15 3], ...
    'R', [3e-5 3e-5], 'dR', [1e-3 1e-3], ...
    'umin', [-600; -1.2], 'umax', [600; 1.2], ...
    'dumin', [-400; -0.9], 'dumax', [400; 0.9], ...
    'ymin', [-1; -0.5; -0.5; -0.3], 'ymax', [1; 0.5; 0.5; 0.3], ...
    'soft_weight_pos', 3000, 'soft_weight_yaw', 3000, ...
    'maps_template', S.maps_best, 'db_file', db_file);
end

function status = local_status(s)
if isempty(s.classifier_chart), status = 'FAIL_NO_CLASSIFIER'; return; end
if isempty(s.theta_guard_chart), status = 'FAIL_NO_THETA_GUARD'; return; end
if isempty(s.rho_filter_chart), status = 'FAIL_NO_COMMON_RHOFILTER'; return; end
if isempty(s.update_plant_chart), status = 'FAIL_NO_UPDATEPLANTMODEL'; return; end
if ~s.guard_parameter_present, status = 'FAIL_NO_MODE_PARAMETER'; return; end
if ~s.plant_sfunc_is_agv_model_sfunc, status = 'FAIL_WRONG_PLANT_SFUNCTION'; return; end
if ~strcmp(s.preloadfcn, 'preloadfcn_v2'), status = 'FAIL_WRONG_PRELOAD'; return; end
status = 'PASS';
end

function local_write_json(file, s)
fid = fopen(file, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(s, 'PrettyPrint', true));
end

function local_close(model)
if bdIsLoaded(model), close_system(model, 0); end
end
