function result = test_node53_v7_runtime(root)
%TEST_NODE53_V7_RUNTIME Non-simulation unit tests for the V7 MATLAB runtime.
if nargin<1||isempty(root); root=project_root(); end
tools=fileparts(mfilename('fullpath')); addpath(tools); addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));
spec=node53_v7_exploratory_spec(root); cfg=node53_v7_runtime_config(root,'EXPLORATORY',spec.model_seed);
parity=jsondecode(fileread(fullfile(spec.output_root,'config','v7_export_parity.json'))); X=double(parity.fixture.features); expected=double(parity.fixture.expected_probability(:)); actual=zeros(size(expected));
for i=1:size(X,1); actual(i)=node53_v7_predict_help(cfg.v7_model,X(i,:)); end
max_error=max(abs(actual-expected)); export_ok=max_error<=1e-12;
[state,~]=node53_v7_uncertainty_fusion('init',cfg.fusion,[]);
fallback_in=struct('theta_tcn',deg2rad(2),'theta_tcn_rate',0,'conf_main',0.9,'tcn_ready',false,'theta_imu',deg2rad(2.2),'observer_valid',true,'quality_score',0.2,'p_help',0.9,'v7_gate',true);
[state,fallback]=node53_v7_uncertainty_fusion('update',state,fallback_in); fallback_ok=fallback.fallback&&fallback.theta_fused==fallback_in.theta_tcn&&fallback.correction==0;
active_in=fallback_in; active_in.tcn_ready=true; active_in.theta_imu=deg2rad(2.4); [~,active]=node53_v7_uncertainty_fusion('update',state,active_in);
active_ok=~active.fallback&&active.slope_gate&&active.innovation_min_gate&&all(isfinite([active.theta_fused active.correction active.K_raw active.K_eff active.NIS]))&&abs(active.correction)<=deg2rad(0.05)+1e-12&&abs(active.correction)<=cfg.fusion.correction_limit+1e-12;
config_ok=cfg.fusion.Kmax==1.0&&cfg.fusion.p_help_threshold==0.6&&cfg.fusion.slope_entry==deg2rad(0.5)&&cfg.fusion.slope_exit==deg2rad(0.3)&&cfg.fusion.innovation_min==deg2rad(0.25)&&cfg.fusion.conf_inflation_gain==1&&cfg.governance.runtime_truth_read==false&&cfg.governance.formal_claim_allowed==false;
% Regression check: all five runtime-observable risk fields must match the
% canonical names in the frozen V7 quality model JSON.
fuzzy=struct('theta_imu',deg2rad(0.1),'accel_weight',0.8,'accel_norm',cfg.sensor.g,'innovation',deg2rad(0.2), ...
    'nis',1.5,'gyro_vibration_feature',0.05);
[feature_row,feature_aux]=node53_v7_runtime_features(cfg.quality_model,fuzzy,cfg.sensor.g,0,0,0.9);
feature_ok=numel(feature_row)==24&&isfinite(feature_aux.quality_score)&&feature_aux.quality_score>=0&&feature_aux.quality_score<=1;
passed=export_ok&&fallback_ok&&active_ok&&config_ok&&feature_ok; if passed; status='PASS_NODE53_V7_RUNTIME_UNIT_TESTS'; else; status='FAIL_NODE53_V7_RUNTIME_UNIT_TESTS'; end
result=struct('status',status,'export_probability_max_abs_error',max_error,'export_parity',export_ok,'fallback_identity',fallback_ok,'bounded_active_update',active_ok,'frozen_config',config_ok,'runtime_feature_field_mapping',feature_ok,'Kmax',cfg.fusion.Kmax,'p_help_threshold',cfg.fusion.p_help_threshold,'slope_entry_deg',rad2deg(cfg.fusion.slope_entry),'slope_exit_deg',rad2deg(cfg.fusion.slope_exit),'innovation_min_deg',rad2deg(cfg.fusion.innovation_min),'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed,'runtime_truth_read',false);
local_json(fullfile(spec.output_root,'config','runtime_unit_test.json'),result); if ~passed; error('node53:v7RuntimeUnit','V7 runtime unit test failed.'); end
end
function local_json(file,value), fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
