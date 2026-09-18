function result=create_node53_model(root)
%CREATE_NODE53_MODEL Clone and patch the frozen Node51 model inside Node53.
if nargin<1||isempty(root);root=project_root();end
tools=fileparts(mfilename('fullpath'));addpath(tools);addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));node53_configure_filegen(root);
node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');
source=fullfile(root,'results','modern_tcn_metric_rebuild','51_moderntcn_rkf_highrisk_suppression_rebuild','05_model_freeze','LPVMPC_AGV_ModernTCN_RKFFusion_Node51.slx');
target=fullfile(node,'06_model_freeze','LPVMPC_AGV_ModernTCN_FuzzyAKF6DFusion_Node53.slx');audit=fullfile(node,'06_model_freeze','model_build_audit.json');
if exist(source,'file')~=2;error('node53:SourceModel','Node51 frozen model is missing.');end
if exist(fullfile(node,'offline_qualification.json'),'file')~=2;error('node53:Qualification','offline_qualification.json is required.');end
q=jsondecode(fileread(fullfile(node,'offline_qualification.json')));if ~strcmp(char(q.status),'PASS_NODE53_ONE_TIME_TEST_QUALIFICATION');error('node53:Qualification','Qualification gate did not pass.');end
source_sha=node43_sha256(source);
if exist(target,'file')==2
 if exist(audit,'file')~=2;error('node53:ModelExists','Unregistered Node53 model exists.');end
 old=jsondecode(fileread(audit));if strcmp(char(old.source_sha256),source_sha)&&strcmp(char(old.model_sha256),node43_sha256(target));result=old;return;end
 error('node53:ModelExists','Node53 model differs; refusing overwrite.');
end
copyfile(source,target);[~,model]=fileparts(target);load_system(target);cleanup=onCleanup(@()local_close(model));
plant=find_system(model,'LookUnderMasks','all','FollowLinks','on','FunctionName','agv_model_sfunc_node51_rkf');if numel(plant)~=1;error('node53:PlantBlock','Expected one Node51 plant block.');end
set_param(plant{1},'FunctionName','agv_model_sfunc_node53_fuzzyakf6d');rt=sfroot;charts=rt.find('-isa','Stateflow.EMChart');selector=[];guard=[];
for k=1:numel(charts);if strcmp(bdroot(charts(k).Path),model)&&strcmp(charts(k).Name,'ModernTCN_State_Classifier');selector=charts(k);end;if strcmp(bdroot(charts(k).Path),model)&&strcmp(charts(k).Name,'ThetaScheduleGuard');guard=charts(k);end;end
if isempty(selector)||isempty(guard);error('node53:ModelChart','Required charts are missing.');end
guard_script=char(guard.Script);selector.Script=sprintf(['function [theta_hat,label_main,label_turn,conf_main] = Node53_State_Selector(legacy_frame,imu_packet,reset)\n' '%%#codegen\n[theta_hat,label_main,label_turn,conf_main] = ModernTCN_FuzzyAKF6DFusion_Node53_sim(legacy_frame,imu_packet,reset);\nend\n']);
drawnow;save_system(model);set_param(model,'SimulationCommand','update');save_system(model);
if ~contains(guard_script,'deg2rad(1.3)')||~contains(guard_script,'deg2rad(10)');error('node53:GuardContract','Guard contract differs.');end
clear cleanup
result=struct('status','PASS_NODE53_MODEL_BUILD','source_model',source,'source_sha256',source_sha,'model_file',target,'model_sha256',node43_sha256(target),'plant_function','agv_model_sfunc_node53_fuzzyakf6d','selector_function','ModernTCN_FuzzyAKF6DFusion_Node53_sim','sensor_port_dimension',6,'vehicle_dynamics_changed',false,'mpc_changed',false,'runtime_truth_read',false,'guard_deadband_deg',1.3,'guard_clip_deg',[-10 10]);
local_json(audit,result);local_json(fullfile(node,'model_freeze.json'),result);
end
function local_close(model),if bdIsLoaded(model);close_system(model,0);end;end
function local_json(file,value),fid=fopen(file,'w','n','UTF-8');c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));end
