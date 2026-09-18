function metrics = node53_v6_evaluate_case(out_file,path_file,path_id,out_dir,debug_file,model_seed,sensor_seed)
%NODE53_V6_EVALUATE_CASE Metrics and truth-free runtime safety audit for one case.
root=project_root(); addpath(genpath(fullfile(root,'src'))); addpath(fileparts(mfilename('fullpath')));
a3=fullfile(root,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','03_A3_slope_scheduling_necessity','02_tools'); addpath(a3);
metrics=evaluate_a3_case(out_file,path_file,'NODE53_V6_EXPLORATORY_FUSION',path_id,out_dir);
T=readtable(debug_file); runtime=node53_v6_runtime_config(root,'EXPLORATORY',model_seed); audit=node53_v6_reconstruct_audit(T,runtime.fusion);
required={'t_s','F_cmd','omega_cmd','F_limit_lo','F_limit_hi','omega_limit_lo','omega_limit_hi'}; trace=readtable(fullfile(out_dir,'trace.csv'));
if ~all(ismember(required,trace.Properties.VariableNames)); error('node53:v6TraceSchema','Required control trace fields are missing.'); end
idx=find(trace.t_s>=0.5); if numel(idx)<2; error('node53:v6TraceLength','Fewer than two evaluated trace rows.'); end
flags={'fallback','innovation_gate_flag','nis_downweight_flag','nis_reject_flag','Kmax_cap_flag','rate_limit_flag','observer_valid','tcn_ready','v6_gate'};
for i=1:numel(flags); metrics.([flags{i} '_count'])=sum(logical(T.(flags{i}))); metrics.([flags{i} '_fraction'])=mean(logical(T.(flags{i}))); end
valid=~logical(T.fallback); metrics.valid_nonfallback_count=sum(valid);
nis=T.NIS(isfinite(T.NIS)); kr=T.K_raw(valid&isfinite(T.K_raw)); ke=T.K_eff(valid&isfinite(T.K_eff));
metrics.NIS_p50=local_percentile(nis,50); metrics.NIS_p95=local_percentile(nis,95); metrics.NIS_p99=local_percentile(nis,99);
metrics.K_raw_p05=local_percentile(kr,5); metrics.K_raw_p95=local_percentile(kr,95); metrics.K_eff_p05=local_percentile(ke,5); metrics.K_eff_p95=local_percentile(ke,95);
metrics.fallback_theta_identity_max_abs=local_max_abs(T.theta_fused(logical(T.fallback))-T.theta_tcn(logical(T.fallback)));
metrics.fallback_correction_max_abs=local_max_abs(T.correction(logical(T.fallback)));
normal=~logical(T.fallback); step=deg2rad(5)*0.01;
metrics.normal_rate_limit_excess_max=local_max([0; abs(T.correction(normal)-T.correction_prev(normal))-step]);
metrics.normal_correction_limit_excess_max=local_max([0; abs(T.correction(normal))-deg2rad(0.5)]);
metrics.psd_min_eigenvalue=min([T.P_tcn;T.P_fuzzyakf_total;T.S;T.min_covariance_eigenvalue],[],'omitnan');
metrics.nonfinite_diagnostic_count=sum(any(~isfinite(table2array(T)),2));
post_init=T.step>100; metrics.observer_invalid_after_init_count=sum(post_init & ~logical(T.observer_valid));
metrics.v6_gate_consistency_count=sum(logical(T.v6_gate) ~= (T.p_help>=runtime.fusion.p_help_threshold));
metrics.log_reconstruction_status=audit.status; metrics.random_sensor_noise=true; metrics.sensor_seed_pairing_only=true;
truth=local_interp(trace.t_s,trace.theta_true,double(T.step-1)*runtime.fusion.Ts); base=T.theta_tcn;
active=~logical(T.fallback)&isfinite(truth); fused=T.theta_fused; ebase=abs(base-truth); efused=abs(fused-truth);
metrics.active_improve_fraction=local_fraction(efused(active)<ebase(active)); metrics.active_degrade_fraction=local_fraction(efused(active)>ebase(active));
metrics.active_fraction=mean(active); metrics.qualification_failed=true; metrics.formal_claim_allowed=false; metrics.runtime_truth_read=false;
metrics.safety_failure_count = double(~strcmp(audit.status,'PASS_NODE53_V6_LOG_RECONSTRUCTION')) + ...
    double(metrics.fallback_theta_identity_max_abs>1e-12) + double(metrics.fallback_correction_max_abs>1e-12) + ...
    double(metrics.normal_rate_limit_excess_max>1e-10) + double(metrics.normal_correction_limit_excess_max>1e-10) + ...
    double(metrics.psd_min_eigenvalue < -1e-12) + double(metrics.nonfinite_diagnostic_count>0) + ...
    double(metrics.observer_invalid_after_init_count>0) + double(metrics.v6_gate_consistency_count>0) + ...
    double(metrics.constraint_violation_rate>0) + double(metrics.timeout_count>0) + double(metrics.solver_fail_count>0);
metrics.safety_status=local_status(metrics.safety_failure_count==0); metrics.model_seed=double(model_seed); metrics.sensor_seed=double(sensor_seed);
metrics.protocol_id='node53_v6_exploratory_six_path_seed42_v1'; metrics.case_id=sprintf('NODE53_V6_EXPLORATORY__%s__seed%d',path_id,model_seed);
local_json(fullfile(out_dir,'case_metrics.json'),metrics);
end
function y=local_interp(t,x,ti), if isempty(t)||isempty(x); y=nan(size(ti)); else; y=interp1(t,x,ti,'linear','extrap'); end, end
function y=local_percentile(x,p), x=x(isfinite(x)); if isempty(x); y=NaN; else; y=prctile(x,p); end, end
function y=local_max_abs(x), x=x(isfinite(x)); if isempty(x); y=0; else; y=max(abs(x)); end, end
function y=local_max(x), x=x(isfinite(x)); if isempty(x); y=0; else; y=max(x); end, end
function y=local_fraction(x), if isempty(x); y=NaN; else; y=mean(x); end, end
function s=local_status(tf), if tf; s='PASS_NODE53_V6_CASE_SAFETY'; else; s='FAIL_NODE53_V6_CASE_SAFETY'; end, end
function local_json(file,value), fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
