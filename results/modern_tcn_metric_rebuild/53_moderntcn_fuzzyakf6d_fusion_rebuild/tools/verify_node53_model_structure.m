function result=verify_node53_model_structure(root)
if nargin<1||isempty(root);root=project_root();end
node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');model_file=fullfile(node,'06_model_freeze','LPVMPC_AGV_ModernTCN_FuzzyAKF6DFusion_Node53.slx');[~,model]=fileparts(model_file);node53_configure_filegen(root);load_system(model_file);c=onCleanup(@()close_system(model,0));
plant=find_system(model,'LookUnderMasks','all','FollowLinks','on','FunctionName','agv_model_sfunc_node53_fuzzyakf6d');rt=sfroot;charts=rt.find('-isa','Stateflow.EMChart');selector_ok=false;guard_ok=false;
for k=1:numel(charts);if strcmp(bdroot(charts(k).Path),model)&&strcmp(charts(k).Name,'ModernTCN_State_Classifier');selector_ok=contains(char(charts(k).Script),'ModernTCN_FuzzyAKF6DFusion_Node53_sim');end;if strcmp(bdroot(charts(k).Path),model)&&strcmp(charts(k).Name,'ThetaScheduleGuard');guard_ok=contains(char(charts(k).Script),'deg2rad(1.3)')&&contains(char(charts(k).Script),'deg2rad(10)');end;end
passed=numel(plant)==1&&selector_ok&&guard_ok;result=struct('status',local_status(passed),'plant_count',numel(plant),'selector_ok',selector_ok,'guard_ok',guard_ok,'runtime_truth_read',false);if ~passed;error('node53:ModelStructure','Node53 model structure check failed.');end
end
function x=local_status(tf),if tf;x='PASS_NODE53_MODEL_STRUCTURE';else;x='FAIL_NODE53_MODEL_STRUCTURE';end;end
