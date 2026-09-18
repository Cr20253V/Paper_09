function result = verify_node53_v7_exploratory_model(root)
%VERIFY_NODE53_V7_EXPLORATORY_MODEL Static structure and truth-boundary audit.
if nargin < 1 || isempty(root); root = project_root(); end
tools = fileparts(mfilename('fullpath')); addpath(tools); addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));
node53_configure_filegen(root); spec = node53_v7_exploratory_spec(root);
if exist(spec.model_file,'file') ~= 2; error('node53:v7MissingModel','V7 model is not built.'); end
assignin('base','preload_skip_gru_model',true);
[~,model] = fileparts(spec.model_file); load_system(spec.model_file); cleanup = onCleanup(@()close_system(model,0));
plant = find_system(model,'LookUnderMasks','all','FollowLinks','on','FunctionName','agv_model_sfunc_node53_fuzzyakf6d');
rt = sfroot; selector_ok = false; guard_ok = false; charts = rt.find('-isa','Stateflow.EMChart');
for k = 1:numel(charts)
    if strcmp(bdroot(charts(k).Path),model) && strcmp(charts(k).Name,'ModernTCN_State_Classifier')
        selector_ok = contains(char(charts(k).Script),'ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim');
    end
    if strcmp(bdroot(charts(k).Path),model) && strcmp(charts(k).Name,'ThetaScheduleGuard')
        script = char(charts(k).Script); guard_ok = contains(script,'deg2rad(1.3)') && contains(script,'deg2rad(10)');
    end
end
runtime = node53_v7_runtime_config(root,'EXPLORATORY',spec.model_seed);
truth_names = {'theta_ground','truth','road_pitch_truth','theta_true','ground_truth'};
runtime_source_files = {fullfile(tools,'node53_v7_runtime_selector.m'),fullfile(tools,'node53_v7_runtime_features.m'),fullfile(tools,'node53_v7_uncertainty_fusion.m'),fullfile(tools,'node53_v7_predict_help.m'),fullfile(tools,'ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim.m')};
truth_hits = false(size(runtime_source_files));
for i=1:numel(runtime_source_files)
    text = fileread(runtime_source_files{i});
    for j=1:numel(truth_names); truth_hits(i)=truth_hits(i)||contains(lower(text),lower(truth_names{j})); end
end
passed = numel(plant)==1 && selector_ok && guard_ok && ~any(truth_hits) && ...
    runtime.governance.runtime_truth_read==false && runtime.governance.formal_claim_allowed==false;
result = struct('status',local_status(passed),'protocol_id',spec.protocol_id,'plant_count',numel(plant), ...
    'selector_ok',selector_ok,'guard_ok',guard_ok,'runtime_truth_read',false,'runtime_truth_token_hits',truth_hits, ...
    'sensor_port_dimension',6,'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed,'Kmax',runtime.fusion.Kmax, ...
    'p_help_threshold',runtime.fusion.p_help_threshold,'slope_entry_deg',rad2deg(runtime.fusion.slope_entry), ...
    'slope_exit_deg',rad2deg(runtime.fusion.slope_exit),'innovation_min_deg',rad2deg(runtime.fusion.innovation_min), ...
    'qualification_bypassed',true,'formal_claim_allowed',false);
if ~passed; error('node53:v7ModelStructure','V7 exploratory model structure audit failed.'); end
local_json(fullfile(spec.output_root,'config','model_structure_audit.json'),result);
end
function x=local_status(tf), if tf; x='PASS_NODE53_V7_EXPLORATORY_MODEL_STRUCTURE'; else; x='FAIL_NODE53_V7_EXPLORATORY_MODEL_STRUCTURE'; end, end
function local_json(file,value), fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
