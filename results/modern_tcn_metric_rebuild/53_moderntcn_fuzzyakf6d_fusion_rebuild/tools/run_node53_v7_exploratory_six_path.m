function result = run_node53_v7_exploratory_six_path(root,cfg)
%RUN_NODE53_V7_EXPLORATORY_SIX_PATH Resumable six-path, one-seed V7 runner.
if nargin<1||isempty(root); root=project_root(); end; if nargin<2; cfg=struct(); end
tools=fileparts(mfilename('fullpath')); addpath(genpath(fullfile(root,'src'))); addpath(tools,'-begin');
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','43_fusion_offline_recalibration_and_6path_retest','tools'));
if isfield(cfg,'model_seeds') && ~isempty(cfg.model_seeds)
    seeds=double(cfg.model_seeds(:).'); allowed=[1 7 11 21 42 73 101 202 340 520];
    if any(~ismember(seeds,allowed))||numel(unique(seeds))~=numel(seeds); error('node53:v7Seeds','model_seeds must be unique members of the fixed ten-seed list.'); end
    one=rmfield(cfg,'model_seeds'); receipts=cell(numel(seeds),1);
    for k=1:numel(seeds); one.model_seed=seeds(k); receipts{k}=run_node53_v7_exploratory_six_path(root,one); end
    if local_get(cfg,'dry_run',false); multi_status='PASS_NODE53_V7_MULTI_SEED_SIX_PATH_PREFLIGHT'; else; multi_status='COMPLETE_NODE53_V7_MULTI_SEED_SIX_PATH_RECEIPT'; end
    result=struct('status',multi_status,'model_seeds',seeds,'seed_count',numel(seeds),'case_count',6*numel(seeds),'receipts',{receipts},'formal_claim_allowed',false);
    node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild','08_formal_six_path_exploratory_v7'); local_json(fullfile(node,'v7_multi_seed_receipt.json'),result); return;
end
model_seed=local_get(cfg,'model_seed',42); spec=node53_v7_exploratory_spec(root,model_seed); reuse=local_get(cfg,'reuse_existing',false); dry=local_get(cfg,'dry_run',false); short=local_get(cfg,'short_test',false); only=char(local_get(cfg,'path_id',''));
rows=local_preflight(root,spec); writetable(rows,fullfile(spec.output_root,sprintf('preflight_v7_seed%d.csv',spec.model_seed)));
if dry; result=struct('status','PASS_NODE53_V7_EXPLORATORY_PREFLIGHT','case_count',height(rows),'ready_count',sum(rows.status=="READY"),'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed); local_json(fullfile(spec.output_root,'preflight_v7.json'),result); return; end
if short
    short_path=spec.path_files{1}; out_dir=fullfile(spec.output_root,'short_test',sprintf('seed%d',spec.model_seed),'p01_factory_logistics_showcase'); if exist(out_dir,'dir')~=7; mkdir(out_dir); end
    runtime=node53_v7_runtime_config(root,spec.group,spec.model_seed); p=parameters(); p.enable_noise=false; p.random_seed=spec.model_seed; p.node53_sensor=runtime.sensor; assignin('base','params',p); assignin('base','parameters',p); assignin('base','node53_runtime_cfg',runtime); assignin('base','preload_skip_gru_model',true);
    simcfg=struct('model_file',spec.model_file,'params_override',p,'modern_tcn_sim_cfg',runtime.tcn,'stop_time_override',3.0); run_closed_loop_model_once(local_model_name(spec.model_file),short_path,fullfile(out_dir,'out.mat'),simcfg); saved=node53_v7_save_debug(out_dir); node53_v7_evaluate_case(fullfile(out_dir,'out.mat'),short_path,'p01_factory_logistics_showcase',out_dir,saved.csv_file,spec.model_seed,spec.sensor_seed);
    result=struct('status','COMPLETE_NODE53_V7_EXPLORATORY_SHORT_TEST','case_dir',out_dir,'stop_time_s',3.0); local_json(fullfile(spec.output_root,'short_test_status.json'),result); return;
end
if ~exist(spec.model_file,'file'); error('node53:v7RunnerModel','Build the V7 model before running cases.'); end
selected=rows; if ~isempty(only); selected=rows(rows.path_id==string(only),:); if height(selected)~=1; error('node53:v7PathId','Unknown or duplicate path id: %s',only); end; end
statuses=strings(height(selected),1); actual=strings(height(selected),1);
for i=1:height(selected)
    try [statuses(i),actual(i)]=local_run_case(root,spec,selected(i,:),reuse); catch err; statuses(i)="FAILED"; actual(i)=selected.case_dir(i); local_json(fullfile(char(selected.case_dir(i)),'run_error.json'),local_error_payload(err)); end
end
selected.status=statuses; selected.actual_case_dir=actual; progress=fullfile(spec.output_root,sprintf('progress_v7_seed%d.csv',spec.model_seed)); writetable(selected,progress); result=local_summary(spec,selected); local_json(fullfile(spec.output_root,sprintf('v7_six_path_receipt_seed%d.json',spec.model_seed)),result);
end
function rows=local_preflight(root,spec)
n=numel(spec.path_ids); path_id=strings(n,1); path_name=strings(n,1); path_file=strings(n,1); case_dir=strings(n,1); status=strings(n,1); path_sha=strings(n,1); onnx=strings(n,1); onnx_sha=strings(n,1); case_key=strings(n,1);
runtime=node53_v7_runtime_config(root,spec.group,spec.model_seed); onnx_file=char(runtime.tcn.onnx_file);
for i=1:n; path_id(i)=spec.path_ids{i}; path_name(i)=spec.path_names{i}; path_file(i)=spec.path_files{i}; case_dir(i)=fullfile(spec.case_root,spec.path_ids{i}); case_key(i)=sprintf('%s|%d|%s',spec.group,spec.model_seed,spec.path_ids{i}); path_sha(i)=node43_sha256(spec.path_files{i}); onnx(i)=onnx_file; onnx_sha(i)=node43_sha256(onnx_file); if exist(spec.path_files{i},'file')==2&&exist(onnx_file,'file')==2&&exist(spec.model_file,'file')==2; status(i)="READY"; else; status(i)="MISSING"; end, end
rows=table(path_id,path_name,path_file,case_dir,case_key,status,path_sha,onnx,onnx_sha);
end
function [status,actual_dir]=local_run_case(root,spec,row,reuse)
runtime=node53_v7_runtime_config(root,spec.group,spec.model_seed); worker_model_file=local_worker_model_file(root,spec.model_file); out_dir=char(row.case_dir); files=local_files(out_dir); fp=local_fingerprint(root,spec,char(row.path_file),runtime,worker_model_file);
if reuse
    [found,reuse_dir]=local_find_reusable(out_dir,fp,spec);
    if found; status="REUSED"; actual_dir=string(reuse_dir); return; end
end
if exist(out_dir,'dir')==7; out_dir=fullfile(out_dir,'attempts',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))); end; if exist(out_dir,'dir')~=7; mkdir(out_dir); end
assignin('base','node53_runtime_cfg',runtime); assignin('base','preload_skip_gru_model',true); p=parameters(); p.enable_noise=false; p.random_seed=spec.model_seed; p.node53_sensor=runtime.sensor; assignin('base','params',p); assignin('base','parameters',p);
simcfg=struct('model_file',worker_model_file,'params_override',p,'modern_tcn_sim_cfg',runtime.tcn);
run_closed_loop_model_once(local_model_name(spec.model_file),char(row.path_file),fullfile(out_dir,'out.mat'),simcfg); saved=node53_v7_save_debug(out_dir);
metrics=node53_v7_evaluate_case(fullfile(out_dir,'out.mat'),char(row.path_file),char(row.path_id),out_dir,saved.csv_file,spec.model_seed,spec.sensor_seed);
manifest=struct('status','COMPLETE','classification',spec.classification,'protocol_id',spec.protocol_id,'fingerprint',fp,'model_seed',spec.model_seed,'sensor_seed',spec.sensor_seed,'path_id',char(row.path_id),'path_file',char(row.path_file),'path_sha256',node43_sha256(char(row.path_file)),'model_file',worker_model_file,'model_sha256',node43_sha256(worker_model_file),'canonical_model_file',spec.model_file,'canonical_model_sha256',node43_sha256(spec.model_file),'onnx_file',char(runtime.tcn.onnx_file),'onnx_sha256',node43_sha256(char(runtime.tcn.onnx_file)),'v7_config',spec.v7_config,'v7_config_sha256',node43_sha256(spec.v7_config),'v7_export',spec.v7_export,'v7_export_sha256',node43_sha256(spec.v7_export),'estimator_config_sha256',node43_sha256(spec.estimator_config),'output_sha256',node43_sha256(fullfile(out_dir,'out.mat')),'debug_sha256',node43_sha256(saved.csv_file),'debug_mat_sha256',node43_sha256(saved.mat_file),'trace_sha256',node43_sha256(fullfile(out_dir,'trace.csv')),'normalized_trace_sha256',node43_sha256(fullfile(out_dir,'normalized_trace.mat')),'metrics_sha256',node43_sha256(fullfile(out_dir,'case_metrics.json')),'safety_status',char(metrics.safety_status),'runtime_truth_read',false,'formal_claim_allowed',false);
local_json(fullfile(out_dir,'case_manifest.json'),manifest); status="RAN"; actual_dir=string(out_dir);
end
function tf=local_reusable(manifest,files,fp,spec)
tf=exist(manifest,'file')==2&&all([exist(files.out,'file')==2,exist(files.debug,'file')==2,exist(files.debug_mat,'file')==2,exist(files.trace,'file')==2,exist(files.normalized,'file')==2,exist(files.metrics,'file')==2]); if ~tf; return; end
try m=jsondecode(fileread(manifest)); tf=strcmp(char(m.status),'COMPLETE')&&strcmp(char(m.fingerprint),fp)&&m.model_seed==spec.model_seed&&m.sensor_seed==spec.sensor_seed&&strcmp(char(m.output_sha256),node43_sha256(files.out))&&strcmp(char(m.debug_sha256),node43_sha256(files.debug))&&strcmp(char(m.metrics_sha256),node43_sha256(files.metrics)); catch; tf=false; end
end
function [tf,d]=local_find_reusable(base,fp,spec)
tf=false; d=base; files=local_files(base);
if local_reusable(files.manifest,files,fp,spec); tf=true; return; end
items=dir(fullfile(base,'attempts','**','case_manifest.json'));
if isempty(items); return; end
[~,order]=sort([items.datenum],'descend'); items=items(order);
for k=1:numel(items)
    candidate=items(k).folder; files=local_files(candidate);
    if local_reusable(files.manifest,files,fp,spec); tf=true; d=candidate; return; end
end
end
function f=local_files(d), f=struct('out',fullfile(d,'out.mat'),'debug',fullfile(d,'node53_v7_runtime_debug.csv'),'debug_mat',fullfile(d,'node53_v7_runtime_debug.mat'),'trace',fullfile(d,'trace.csv'),'normalized',fullfile(d,'normalized_trace.mat'),'metrics',fullfile(d,'case_metrics.json'),'manifest',fullfile(d,'case_manifest.json')); end
function fp=local_fingerprint(root,spec,path,runtime,model_file), if nargin<5||isempty(model_file); model_file=spec.model_file; end, deps={spec.v7_config,spec.v7_export,spec.estimator_config,fullfile(fileparts(mfilename('fullpath')),'node53_v7_runtime_config.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v7_runtime_selector.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v7_uncertainty_fusion.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v7_runtime_features.m'),fullfile(fileparts(mfilename('fullpath')),'node53_v7_predict_help.m'),model_file,path,runtime.tcn.onnx_file}; fp=node43_sha256(spec.protocol_id,jsonencode(runtime),deps{:}); end
function model_file=local_worker_model_file(root,source_model_file)
model_file=source_model_file;
worker='serial';
try worker=evalin('base','node53_worker_id'); catch; worker='serial'; end
worker=regexprep(char(string(worker)),'[^A-Za-z0-9_-]','_');
if isempty(worker)||strcmpi(worker,'serial'); return; end
node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');
dest_dir=fullfile(node,'06_model_freeze','v7_exploratory','worker_models',worker);
if exist(dest_dir,'dir')~=7; mkdir(dest_dir); end
[~,name,ext]=fileparts(source_model_file);
dest=fullfile(dest_dir,[name '_' worker ext]);
needs_copy=exist(dest,'file')~=2;
if ~needs_copy
    try needs_copy=~strcmp(node43_sha256(dest),node43_sha256(source_model_file)); catch; needs_copy=true; end
end
if needs_copy
    copyfile(source_model_file,dest,'f');
end
model_file=dest;
end
function x=local_model_name(file), [~,x]=fileparts(file); end
function result=local_summary(spec,rows)
metrics_rows={}; csv_rows=struct([]); safety=struct('case_count',height(rows),'ran_count',sum(rows.status=="RAN"),'reused_count',sum(rows.status=="REUSED"),'failed_count',sum(rows.status=="FAILED"),'safety_pass_count',0,'safety_failure_count',0,'all_outputs_complete',false,'qualification_bypassed',true,'formal_claim_allowed',false);
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
    if strcmp(local_char(m,'safety_status','UNKNOWN'),'PASS_NODE53_V7_CASE_SAFETY')
        safety.safety_pass_count=safety.safety_pass_count+1;
    else
        safety.safety_failure_count=safety.safety_failure_count+1;
    end
end
suffix=sprintf('_seed%d',spec.model_seed); safety_file=fullfile(spec.output_root,['v7_six_path_safety_summary' suffix '.json']); metrics_json=fullfile(spec.output_root,['v7_six_path_metrics' suffix '.json']); metrics_csv=fullfile(spec.output_root,['v7_six_path_metrics' suffix '.csv']);
safety.all_outputs_complete=(safety.ran_count+safety.reused_count)==6; local_json(safety_file,safety); local_json(metrics_json,metrics_rows); if ~isempty(csv_rows); writetable(struct2table(csv_rows),metrics_csv); end; result=struct('status','COMPLETE_NODE53_V7_EXPLORATORY_SIX_PATH_RECEIPT','protocol_id',spec.protocol_id,'model_seed',spec.model_seed,'case_count',6,'ran_count',safety.ran_count,'reused_count',safety.reused_count,'failed_count',safety.failed_count,'safety_pass_count',safety.safety_pass_count,'safety_failure_count',safety.safety_failure_count,'metrics_file',metrics_json,'safety_file',safety_file,'formal_claim_allowed',false);
end
function v=local_get(s,n,d), if isfield(s,n)&&~isempty(s.(n)); v=s.(n); else; v=d; end, end
function v=local_num(s,n,d), if isfield(s,n)&&~isempty(s.(n))&&isnumeric(s.(n))&&isscalar(s.(n)); v=double(s.(n)); else; v=d; end, end
function v=local_char(s,n,d), if isfield(s,n)&&~isempty(s.(n)); v=char(string(s.(n))); else; v=d; end, end
function payload=local_error_payload(err), stack=struct('file',{},'name',{},'line',{}); for k=1:numel(err.stack); stack(k).file=err.stack(k).file; stack(k).name=err.stack(k).name; stack(k).line=err.stack(k).line; end, payload=struct('identifier',err.identifier,'message',err.message,'stack',stack); end
function local_json(file,value), d=fileparts(file); if exist(d,'dir')~=7; mkdir(d); end; fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true)); end
