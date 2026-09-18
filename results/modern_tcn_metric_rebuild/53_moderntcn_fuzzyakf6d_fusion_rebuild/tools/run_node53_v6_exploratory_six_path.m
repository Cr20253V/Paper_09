function result = run_node53_v6_exploratory_six_path(root,cfg)
%RUN_NODE53_V6_EXPLORATORY_SIX_PATH Resumable six-path, one-seed V6 runner.
if nargin<1||isempty(root); root=project_root(); end; if nargin<2; cfg=struct(); end
tools=fileparts(mfilename('fullpath')); addpath(tools); addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));
spec=node53_v6_exploratory_spec(root); reuse=local_get(cfg,'reuse_existing',false); dry=local_get(cfg,'dry_run',false); short=local_get(cfg,'short_test',false); only=char(local_get(cfg,'path_id',''));
rows=local_preflight(root,spec); writetable(rows,fullfile(spec.output_root,'preflight_v6.csv'));
if dry; result=struct('status','PASS_NODE53_V6_EXPLORATORY_PREFLIGHT','case_count',height(rows),'ready_count',sum(rows.status=="READY"),'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed); local_json(fullfile(spec.output_root,'preflight_v6.json'),result); return; end
if short
    short_path=spec.path_files{1}; out_dir=fullfile(spec.output_root,'short_test','seed42','p01_factory_logistics_showcase'); if exist(out_dir,'dir')~=7; mkdir(out_dir); end
    runtime=node53_v6_runtime_config(root,spec.group,spec.model_seed); p=parameters(); p.enable_noise=false; p.random_seed=spec.model_seed; p.node53_sensor=runtime.sensor; assignin('base','params',p); assignin('base','parameters',p); assignin('base','node53_runtime_cfg',runtime); assignin('base','preload_skip_gru_model',true);
    simcfg=struct('model_file',spec.model_file,'params_override',p,'modern_tcn_sim_cfg',runtime.tcn,'stop_time_override',3.0); run_closed_loop_model_once(local_model_name(spec.model_file),short_path,fullfile(out_dir,'out.mat'),simcfg); saved=node53_v6_save_debug(out_dir); node53_v6_evaluate_case(fullfile(out_dir,'out.mat'),short_path,'p01_factory_logistics_showcase',out_dir,saved.csv_file,spec.model_seed,spec.sensor_seed);
    result=struct('status','COMPLETE_NODE53_V6_EXPLORATORY_SHORT_TEST','case_dir',out_dir,'stop_time_s',3.0); local_json(fullfile(spec.output_root,'short_test_status.json'),result); return;
end
if ~exist(spec.model_file,'file'); error('node53:v6RunnerModel','Build the V6 model before running cases.'); end
selected=rows; if ~isempty(only); selected=rows(rows.path_id==string(only),:); if height(selected)~=1; error('node53:v6PathId','Unknown or duplicate path id: %s',only); end; end
statuses=strings(height(selected),1); actual=strings(height(selected),1);
for i=1:height(selected)
    try [statuses(i),actual(i)]=local_run_case(root,spec,selected(i,:),reuse); catch err; statuses(i)="FAILED"; actual(i)=selected.case_dir(i); local_json(fullfile(char(selected.case_dir(i)),'run_error.json'),struct('identifier',err.identifier,'message',err.message)); end
end
selected.status=statuses; selected.actual_case_dir=actual; progress=fullfile(spec.output_root,'progress_v6.csv'); writetable(selected,progress); result=local_summary(spec,selected); local_json(fullfile(spec.output_root,'v6_six_path_receipt.json'),result);
end
function rows=local_preflight(root,spec)
n=numel(spec.path_ids); path_id=strings(n,1); path_name=strings(n,1); path_file=strings(n,1); case_dir=strings(n,1); status=strings(n,1); path_sha=strings(n,1); onnx=strings(n,1); onnx_sha=strings(n,1); case_key=strings(n,1);
runtime=node53_v6_runtime_config(root,spec.group,spec.model_seed); onnx_file=char(runtime.tcn.onnx_file);
for i=1:n; path_id(i)=spec.path_ids{i}; path_name(i)=spec.path_names{i}; path_file(i)=spec.path_files{i}; case_dir(i)=fullfile(spec.case_root,spec.path_ids{i}); case_key(i)=sprintf('%s|%d|%s',spec.group,spec.model_seed,spec.path_ids{i}); path_sha(i)=node43_sha256(spec.path_files{i}); onnx(i)=onnx_file; onnx_sha(i)=node43_sha256(onnx_file); if exist(spec.path_files{i},'file')==2&&exist(onnx_file,'file')==2&&exist(spec.model_file,'file')==2; status(i)="READY"; else; status(i)="MISSING"; end, end
rows=table(path_id,path_name,path_file,case_dir,case_key,status,path_sha,onnx,onnx_sha);
end
function [status,actual_dir]=local_run_case(root,spec,row,reuse)
runtime=node53_v6_runtime_config(root,spec.group,spec.model_seed); out_dir=char(row.case_dir); files=local_files(out_dir); fp=local_fingerprint(root,spec,char(row.path_file),runtime);
if reuse&&local_reusable(files.manifest,files,fp,spec); status="REUSED"; actual_dir=string(out_dir); return; end
if exist(out_dir,'dir')==7; out_dir=fullfile(out_dir,'attempts',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))); end; if exist(out_dir,'dir')~=7; mkdir(out_dir); end
assignin('base','node53_runtime_cfg',runtime); assignin('base','preload_skip_gru_model',true); p=parameters(); p.enable_noise=false; p.random_seed=spec.model_seed; p.node53_sensor=runtime.sensor; assignin('base','params',p); assignin('base','parameters',p);
simcfg=struct('model_file',spec.model_file,'params_override',p,'modern_tcn_sim_cfg',runtime.tcn);
run_closed_loop_model_once(local_model_name(spec.model_file),char(row.path_file),fullfile(out_dir,'out.mat'),simcfg); saved=node53_v6_save_debug(out_dir);
metrics=node53_v6_evaluate_case(fullfile(out_dir,'out.mat'),char(row.path_file),char(row.path_id),out_dir,saved.csv_file,spec.model_seed,spec.sensor_seed);
manifest=struct('status','COMPLETE','classification',spec.classification,'protocol_id',spec.protocol_id,'fingerprint',fp,'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed,'path_id',char(row.path_id),'path_file',char(row.path_file),'path_sha256',node43_sha256(char(row.path_file)),'model_file',spec.model_file,'model_sha256',node43_sha256(spec.model_file),'onnx_file',char(runtime.tcn.onnx_file),'onnx_sha256',node43_sha256(char(runtime.tcn.onnx_file)),'v6_config',spec.v6_config,'v6_config_sha256',node43_sha256(spec.v6_config),'v6_export',spec.v6_export,'v6_export_sha256',node43_sha256(spec.v6_export),'estimator_config_sha256',node43_sha256(spec.estimator_config),'output_sha256',node43_sha256(fullfile(out_dir,'out.mat')),'debug_sha256',node43_sha256(saved.csv_file),'debug_mat_sha256',node43_sha256(saved.mat_file),'trace_sha256',node43_sha256(fullfile(out_dir,'trace.csv')),'normalized_trace_sha256',node43_sha256(fullfile(out_dir,'normalized_trace.mat')),'metrics_sha256',node43_sha256(fullfile(out_dir,'case_metrics.json')),'safety_status',char(metrics.safety_status),'runtime_truth_read',false,'formal_claim_allowed',false);
local_json(fullfile(out_dir,'case_manifest.json'),manifest); status="RAN"; actual_dir=string(out_dir);
end
function tf=local_reusable(manifest,files,fp,spec)
tf=exist(manifest,'file')==2&&all([exist(files.out,'file')==2,exist(files.debug,'file')==2,exist(files.debug_mat,'file')==2,exist(files.trace,'file')==2,exist(files.normalized,'file')==2,exist(files.metrics,'file')==2]); if ~tf; return; end
try m=jsondecode(fileread(manifest)); tf=strcmp(char(m.status),'COMPLETE')&&strcmp(char(m.fingerprint),fp)&&m.model_seed==spec.model_seed&&m.sensor_seed==spec.sensor_seed&&strcmp(char(m.output_sha256),node43_sha256(files.out))&&strcmp(char(m.debug_sha256),node43_sha256(files.debug))&&strcmp(char(m.metrics_sha256),node43_sha256(files.metrics)); catch; tf=false; end
end
function f=local_files(d), f=struct('out',fullfile(d,'out.mat'),'debug',fullfile(d,'node53_v6_runtime_debug.csv'),'debug_mat',fullfile(d,'node53_v6_runtime_debug.mat'),'trace',fullfile(d,'trace.csv'),'normalized',fullfile(d,'normalized_trace.mat'),'metrics',fullfile(d,'case_metrics.json'),'manifest',fullfile(d,'case_manifest.json')); end
function fp=local_fingerprint(root,spec,path,runtime), deps={spec.v6_config,spec.v6_export,spec.estimator_config,fullfile(fileparts(mfilename('fullpath')),'node53_v6_runtime_config.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v6_runtime_selector.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v6_uncertainty_fusion.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v6_runtime_features.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v6_predict_help.m'),spec.model_file,path,runtime.tcn.onnx_file}; fp=node43_sha256(spec.protocol_id,jsonencode(runtime),deps{:}); end
function x=local_model_name(file), [~,x]=fileparts(file); end
function result=local_summary(spec,rows)
metrics_rows={}; csv_rows=struct([]); safety=struct('case_count',height(rows),'ran_count',sum(rows.status=="RAN"),'reused_count',sum(rows.status=="REUSED"),'failed_count',sum(rows.status=="FAILED"),'safety_pass_count',0,'safety_failure_count',0,'all_outputs_complete',false,'qualification_failed',true,'formal_claim_allowed',false);
for i=1:height(rows)
    d=char(rows.actual_case_dir(i)); mf=fullfile(d,'case_metrics.json');
    if exist(mf,'file')~=2; continue; end
    m=jsondecode(fileread(mf)); metrics_rows{end+1,1}=m;
    row=struct('path_id',local_char(m,'path_id',''), ...
        'model_seed',local_num(m,'model_seed',NaN), ...
        'sensor_seed',local_num(m,'sensor_seed',NaN), ...
        'case_status',local_char(m,'case_status','UNKNOWN'), ...
        'safety_status',local_char(m,'safety_status','UNKNOWN'), ...
        'theta_sched_mae_deg',local_num(m,'theta_sched_mae_deg',NaN), ...
        'ey_rmse',local_num(m,'ey_rmse',NaN), ...
        'epsi_rmse',local_num(m,'epsi_rmse',NaN), ...
        'xy_rmse',local_num(m,'xy_rmse',NaN), ...
        'j_du',local_num(m,'j_du',NaN), ...
        'omega_cmd_rms',local_num(m,'omega_cmd_rms',NaN), ...
        'active_fraction',local_num(m,'active_fraction',NaN), ...
        'active_improve_fraction',local_num(m,'active_improve_fraction',NaN), ...
        'active_degrade_fraction',local_num(m,'active_degrade_fraction',NaN), ...
        'fallback_fraction',local_num(m,'fallback_fraction',NaN), ...
        'safety_failure_count',local_num(m,'safety_failure_count',NaN), ...
        'case_dir',d);
    if isempty(csv_rows)
        csv_rows=row;
    else
        csv_rows(end+1,1)=row;
    end
    if strcmp(local_char(m,'safety_status','UNKNOWN'),'PASS_NODE53_V6_CASE_SAFETY')
        safety.safety_pass_count=safety.safety_pass_count+1;
    else
        safety.safety_failure_count=safety.safety_failure_count+1;
    end
end
safety.all_outputs_complete=(safety.ran_count+safety.reused_count)==6; local_json(fullfile(spec.output_root,'v6_six_path_safety_summary.json'),safety); local_json(fullfile(spec.output_root,'v6_six_path_metrics.json'),metrics_rows); if ~isempty(csv_rows); writetable(struct2table(csv_rows),fullfile(spec.output_root,'v6_six_path_metrics.csv')); end; result=struct('status','COMPLETE_NODE53_V6_EXPLORATORY_SIX_PATH_RECEIPT','protocol_id',spec.protocol_id,'case_count',6,'ran_count',safety.ran_count,'reused_count',safety.reused_count,'failed_count',safety.failed_count,'safety_pass_count',safety.safety_pass_count,'safety_failure_count',safety.safety_failure_count,'metrics_file',fullfile(spec.output_root,'v6_six_path_metrics.json'),'safety_file',fullfile(spec.output_root,'v6_six_path_safety_summary.json'),'formal_claim_allowed',false);
end
function v=local_get(s,n,d), if isfield(s,n)&&~isempty(s.(n)); v=s.(n); else; v=d; end, end
function v=local_num(s,n,d), if isfield(s,n)&&~isempty(s.(n))&&isnumeric(s.(n))&&isscalar(s.(n)); v=double(s.(n)); else; v=d; end, end
function v=local_char(s,n,d), if isfield(s,n)&&~isempty(s.(n)); v=char(string(s.(n))); else; v=d; end, end
function local_json(file,value), d=fileparts(file); if exist(d,'dir')~=7; mkdir(d); end; fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
