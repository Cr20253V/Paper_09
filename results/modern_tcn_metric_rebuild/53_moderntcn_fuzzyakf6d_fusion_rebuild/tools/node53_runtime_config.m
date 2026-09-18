function cfg=node53_runtime_config(root,group,model_seed)
%NODE53_RUNTIME_CONFIG Load frozen Node53 runtime contract.
if nargin<1||isempty(root);root=project_root();end;if nargin<2||isempty(group);group='G0';end;if nargin<3||isempty(model_seed);model_seed=1;end
node43tools=fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools');if isempty(which('node43r2_runtime_config'));addpath(node43tools);end
cfg=node43r2_runtime_config(root,'G0',model_seed,4631);node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');cfg.protocol_id='node53_moderntcn_delta_fuzzyakf6d_fusion_rebuild_v1';cfg.group=upper(char(group));cfg.estimator=jsondecode(fileread(fullfile(node,'02_fuzzyakf6','R2_06_FuzzyAKF6D.json')));
selected=jsondecode(fileread(fullfile(node,'selected_fusion_config.json')));
if ~isfield(selected,'tables')||~isfield(selected,'quality_model')||~isfield(selected,'selected')||isempty(selected.selected)
    error('node53:Selection','Node53 development selection is not frozen; runtime stages are locked.');
end
t=selected.tables;cfg.quality_model=selected.quality_model;cfg.sensor=struct('Ts',0.01,'g',9.81,'sensor_seed',4631,'accel_bandwidth_hz',15,'gyro_bandwidth_hz',25,'accel_noise_std_mps2',[0.05 0.05 0.05],'gyro_noise_std_radps',[0.002 0.002 0.002],'accel_bias_mps2',[0.03 0.02 -0.02],'gyro_bias_radps',[0 0.00035 0],'mount_pitch_error_rad',deg2rad(0.15),'body_pitch_natural_frequency_hz',3,'body_pitch_damping_ratio',0.9,'body_pitch_rate_limit_radps',deg2rad(30));
floorv=deg2rad(0.02)^2;cfg.fusion=struct('group',cfg.group,'Ts',0.01,'Kmax',double(selected.selected.Kmax),'quality_intercept',0.5,'quality_slope',0.3,'quality_floor',0.1,'innovation_gate',deg2rad(2),'correction_limit',deg2rad(0.5),'correction_rate_limit',deg2rad(5),'conf_inflation_gain',1,'flat_threshold',deg2rad(1.3),'transition_rate_threshold',deg2rad(1),'quality_edges',[0.5 0.8],'P_tcn_total',double(t.P_tcn_total),'P_fuzzyakf_total',double(t.P_fuzzyakf_total),'cross_error_total',double(t.cross_error_total),'variance_floor',floorv,'S_floor',floorv,'correlation_clip',0.95,'nis_downweight',9,'nis_reject',25);cfg.governance=struct('runtime_truth_read',false,'paper_write_allowed',false,'sensor_seed',4631);
end
