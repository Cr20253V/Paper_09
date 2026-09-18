function result = create_node53_v7_exploratory_model(root)
%CREATE_NODE53_V7_EXPLORATORY_MODEL Build an isolated V7 model copy.
if nargin < 1 || isempty(root); root = project_root(); end
tools = fileparts(mfilename('fullpath')); addpath(tools); addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));
node53_configure_filegen(root);
spec = node53_v7_exploratory_spec(root);
assignin('base','preload_skip_gru_model',true);
source = spec.upstream_model; target = spec.model_file; audit_file = spec.model_audit;
if exist(source,'file') ~= 2; error('node53:v7SourceModel','Node51 source model is missing.'); end
source_sha = node43_sha256(source);
if exist(target,'file') == 2
    if exist(audit_file,'file') ~= 2; error('node53:v7ModelExists','Unregistered V7 model exists; refusing overwrite.'); end
    old = jsondecode(fileread(audit_file));
    if strcmp(char(old.source_sha256),source_sha) && strcmp(char(old.model_sha256),node43_sha256(target))
        result = old; return;
    end
    error('node53:v7ModelExists','Existing V7 model hash differs; refusing overwrite.');
end
mkdir(fileparts(target));
runtime = node53_v7_runtime_config(root,'EXPLORATORY',spec.model_seed);
assignin('base','node53_runtime_cfg',runtime);
p = parameters(); p.enable_noise = false; p.random_seed = spec.model_seed; p.node53_sensor = runtime.sensor;
assignin('base','params',p); assignin('base','parameters',p);
S = load(spec.path_files{3},'ref'); assignin('base','ref',S.ref);
copyfile(source,target); [~,model] = fileparts(target); load_system(target); cleanup = onCleanup(@()local_close(model));
plant = find_system(model,'LookUnderMasks','all','FollowLinks','on','FunctionName','agv_model_sfunc_node51_rkf');
if numel(plant) ~= 1; error('node53:v7PlantBlock','Expected one Node51 plant block.'); end
set_param(plant{1},'FunctionName','agv_model_sfunc_node53_fuzzyakf6d');
rt = sfroot; charts = rt.find('-isa','Stateflow.EMChart'); selector = []; guard_script = '';
for k = 1:numel(charts)
    if strcmp(bdroot(charts(k).Path),model) && strcmp(charts(k).Name,'ModernTCN_State_Classifier'); selector = charts(k); end
    if strcmp(bdroot(charts(k).Path),model) && strcmp(charts(k).Name,'ThetaScheduleGuard'); guard_script = char(charts(k).Script); end
end
if isempty(selector) || isempty(guard_script); error('node53:v7ModelChart','Required model charts are missing.'); end
selector.Script = sprintf(['function [theta_hat,label_main,label_turn,conf_main] = Node53_V7_State_Selector(legacy_frame,imu_packet,reset)\n' ...
    '%%#codegen\n[theta_hat,label_main,label_turn,conf_main] = ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim(legacy_frame,imu_packet,reset);\nend\n']);
drawnow; save_system(model); set_param(model,'SimulationCommand','update'); save_system(model);
if ~contains(char(selector.Script),'ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim'); error('node53:v7SelectorPatch','V7 selector patch did not persist.'); end
if ~contains(guard_script,'deg2rad(1.3)') || ~contains(guard_script,'deg2rad(10)'); error('node53:v7GuardContract','Guard contract differs from locked limits.'); end
clear cleanup
result = struct('status','PASS_NODE53_V7_EXPLORATORY_MODEL_BUILD','protocol_id',spec.protocol_id, ...
    'source_model',source,'source_sha256',source_sha,'model_file',target,'model_sha256',node43_sha256(target), ...
    'plant_function','agv_model_sfunc_node53_fuzzyakf6d','selector_function','ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim', ...
    'sensor_port_dimension',6,'vehicle_dynamics_changed',false,'mpc_changed',false,'runtime_truth_read',false, ...
    'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed,'guard_deadband_deg',1.3,'guard_clip_deg',[-10 10], ...
    'qualification_bypassed',true,'classification',spec.classification,'formal_claim_allowed',false);
local_json(audit_file,result); local_json(fullfile(fileparts(audit_file),'model_freeze_exploratory.json'),result);
end
function local_close(model), if bdIsLoaded(model); close_system(model,0); end, end
function local_json(file,value), fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
