function result = run_a2_benchmark(case_id, mode)
%RUN_A2_BENCHMARK Execute one isolated A2 runtime cell.
if nargin < 2 || isempty(mode), mode = 'formal'; end
case_id = char(case_id); mode = lower(char(mode));
tools_dir = fileparts(mfilename('fullpath'));
target = fileparts(tools_dir);
project_root = fileparts(fileparts(fileparts(fileparts(target))));
addpath(tools_dir, '-begin');
addpath(fullfile(project_root,'src','core'));
addpath(fullfile(project_root,'src','ModernTCN'));
addpath(fullfile(project_root,'src','gru'));
addpath(fullfile(project_root,'src','TCN'));
addpath(fullfile(project_root,'src','mpc'));
addpath(fullfile(project_root,'src','lpv'));
addpath(tools_dir, '-begin');
maxNumCompThreads(1);

is_formal = strcmp(mode,'formal');
if is_formal && isempty(getenv('A2_EXCLUSIVE_TOKEN'))
    error('A2:ExclusiveTokenMissing','Formal timing must be launched by invoke_a2.ps1.');
end
if is_formal, warmup_count=500; formal_count=10000; else, warmup_count=2; formal_count=5; end

snapshot = local_read_json(fullfile(target,'00_protocol_lock','protocol_snapshot.json'));
envm = local_read_json(fullfile(target,'03_environment','environment_manifest.json'));
inventory = readtable(fullfile(target,'01_inventory','input_artifact_registry.csv'), TextType='string');
dataset_file = fullfile(project_root, strrep(snapshot.dataset.file,'/','\'));
S = load(dataset_file, 'dataset');
dataset = S.dataset;
Xtest = single(dataset.X_test);
scaler_mean = single(dataset.scaler.mean(:).');
scaler_std = single(dataset.scaler.std(:).');
paths = local_paths(project_root);

[scope, method_id, interface_kind] = local_case_identity(case_id);
ctx = struct(); state = []; trace = [];
switch case_id
    case 'core_inference__modern_tcn_delta_bank_124'
        ctx.predictor = ModernTCN_load_predictor(42, paths.delta_onnx);
        ctx.inputs = local_delta_bank(Xtest, [1 2 4], 5);
        ctx.runtime_import_learnable_count = local_count_learnables(ctx.predictor.net);
        ctx.param_count = 145202;
    case 'core_inference__modern_tcn_22d'
        ctx.predictor = ModernTCN_load_predictor(42, paths.modern22_onnx);
        ctx.inputs = Xtest;
        ctx.runtime_import_learnable_count = local_count_learnables(ctx.predictor.net);
        ctx.param_count = 118538;
    case 'core_inference__gru_22d'
        q=load(paths.gru_model,'model'); ctx.model=q.model; ctx.inputs=Xtest;
        ctx.param_count = local_count_model(ctx.model);
    case 'core_inference__tcn_22d'
        ctx.predictor=TCN_load_predictor(paths.tcn_model); ctx.inputs=Xtest;
        ctx.param_count = local_count_learnables(ctx.predictor.net) + local_count_numeric_struct(ctx.predictor.heads);
    case {'end_to_end_update__modern_tcn_delta_bank_124','end_to_end_update__modern_tcn_22d', ...
          'end_to_end_update__gru_22d','end_to_end_update__tcn_22d','full_cycle__slope_estimation_mpc'}
        trace = local_load_trace(project_root);
        [state, ctx] = local_init_online(case_id, paths, dataset_file, project_root);
        prime_count = min(300,size(trace.y_raw,1));
        for k=1:prime_count, [state,ctx] = local_online_step(case_id,state,ctx,trace.y_raw(k,:).'); end
        if strcmp(case_id,'full_cycle__slope_estimation_mpc'), ctx.mpc=local_init_mpc(paths); end
    case 'mpc_solve__effective_controller'
        trace=local_load_trace(project_root); ctx.mpc=local_init_mpc(paths); ctx.param_count=0;
    case 'preprocess__normalization_delta_bank_124'
        ctx.raw = Xtest .* reshape(scaler_std,1,1,[]) + reshape(scaler_mean,1,1,[]);
        ctx.mean=scaler_mean; ctx.std=scaler_std; ctx.param_count=0;
    otherwise
        error('A2:UnknownCase','Unknown or not-yet-eligible case: %s',case_id);
end

overhead = zeros(formal_count,1);
for i=1:formal_count, t=tic; overhead(i)=toc(t)*1000; end
last=[]; %#ok<NASGU>
for i=1:warmup_count
    idx=local_index(i,ctx,trace);
    if strcmp(case_id,'mpc_solve__effective_controller')
        sample=local_trace_sample(trace,idx);
        [ctx.mpc,prepared]=a2_mpc_prepare(ctx.mpc,sample,[]);
        [ctx.mpc,last,info]=a2_mpc_solve(ctx.mpc,prepared); %#ok<ASGLU>
    else
        [state,ctx,last] = local_execute(case_id,idx,state,ctx,trace);
    end
end
latency=zeros(formal_count,1);
input_index=zeros(formal_count,1);
for i=1:formal_count
    idx=local_index(i,ctx,trace); input_index(i)=idx;
    if strcmp(case_id,'mpc_solve__effective_controller')
        sample=local_trace_sample(trace,idx);
        [ctx.mpc,prepared]=a2_mpc_prepare(ctx.mpc,sample,[]);
        t=tic; [ctx.mpc,last,info]=a2_mpc_solve(ctx.mpc,prepared); latency(i)=toc(t)*1000; %#ok<ASGLU>
    else
        t=tic; [state,ctx,last]=local_execute(case_id,idx,state,ctx,trace); latency(i)=toc(t)*1000;
    end
end
if any(~isfinite(latency)), error('A2:NonfiniteLatency','Nonfinite timing sample in %s',case_id); end

result=struct();
result.task_id='A2'; result.protocol_id=snapshot.protocol_id; result.case_id=case_id;
result.case_status='COMPLETE'; result.method_id=method_id; result.model_seed=42;
if strcmp(method_id,'effective_controller'), result.controller_id='effective_controller'; result.model_seed=NaN; end
if ~isempty(trace), result.path_id='A0_SIX_PATH_CONCATENATED'; end
result.plant_revision=snapshot.plant_revision;
result.effective_config_sha256=snapshot.source_config_sha256;
result.component_id=method_id; result.benchmark_scope=scope; result.batch_size=1;
result.warmup_count=warmup_count; result.formal_count=formal_count;
result.environment_sha256=envm.environment_sha256;
result.p50_ms=prctile(latency,50); result.p95_ms=prctile(latency,95);
result.p99_ms=prctile(latency,99); result.max_ms=max(latency);
result.over_10ms_rate=mean(latency>10.0);
result.meets_p95_10ms=result.p95_ms<=10; result.meets_p99_10ms=result.p99_ms<=10;
result.zero_overrun=result.over_10ms_rate==0;
result.timer_overhead_p50_ms=prctile(overhead,50); result.timer_overhead_max_ms=max(overhead);
result.parameter_count=double(local_field(ctx,'param_count',0));
result.runtime_import_learnable_count=double(local_field(ctx,'runtime_import_learnable_count',result.parameter_count));
result.dataset_file=dataset_file; result.dataset_sha256=snapshot.dataset.sha256;
result.execution_backend='MATLAB_R2024b_CPU_SINGLE_THREAD'; result.input_interface=interface_kind;
[result.model_file,result.model_sha256,result.model_file_bytes,result.source_file,result.source_file_sha256,result.source_file_bytes] = local_artifacts(method_id,inventory,paths);

if is_formal
    raw_file=fullfile(target,'04_phase1','raw_timing',[case_id '.csv']);
    writetable(table((1:formal_count).',input_index,latency,latency>10, ...
        'VariableNames',{'iteration','input_index','latency_ms','over_10ms'}),raw_file);
    result.raw_timing_file=raw_file;
    case_file=fullfile(target,'04_phase1','cases',[case_id '.json']);
else
    case_file=fullfile(target,'04_phase1','logs',['smoke_' case_id '.json']);
end
local_write_json(case_file,result);
fprintf('A2 case %s (%s): p95=%.6f ms, max=%.6f ms\n',case_id,mode,result.p95_ms,result.max_ms);
end

function value=local_read_json(file)
fid=fopen(file,'rb');
if fid<0, error('A2:JsonOpenFailed','Cannot open JSON file: %s',file); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes=fread(fid,inf,'*uint8').';
if numel(bytes)>=3 && isequal(bytes(1:3),uint8([239 187 191]))
    bytes=bytes(4:end);
end
value=jsondecode(native2unicode(bytes,'UTF-8'));
end

function [state,ctx,out]=local_execute(case_id,idx,state,ctx,trace)
out=[];
switch case_id
    case {'core_inference__modern_tcn_delta_bank_124','core_inference__modern_tcn_22d'}
        out=ModernTCN_predict_window(ctx.predictor,squeeze(ctx.inputs(idx,:,:)));
    case 'core_inference__gru_22d'
        [a,b,c,d]=GRU_infer(squeeze(ctx.inputs(idx,:,:)),ctx.model); out={a,b,c,d}; %#ok<NASGU>
    case 'core_inference__tcn_22d'
        out=TCN_predict_window(ctx.predictor,squeeze(ctx.inputs(idx,:,:)));
    case {'end_to_end_update__modern_tcn_delta_bank_124','end_to_end_update__modern_tcn_22d', ...
          'end_to_end_update__gru_22d','end_to_end_update__tcn_22d'}
        [state,ctx,out]=local_online_step(case_id,state,ctx,trace.y_raw(idx,:).');
    case 'preprocess__normalization_delta_bank_124'
        x=(squeeze(ctx.raw(idx,:,:))-ctx.mean)./(ctx.std+single(1e-8));
        out=local_delta_bank(reshape(x,1,size(x,1),size(x,2)),[1 2 4],5);
    case 'full_cycle__slope_estimation_mpc'
        [state,ctx,out]=local_online_step(case_id,state,ctx,trace.y_raw(idx,:).');
        theta=local_field(out,'theta_sched',local_field(out,'theta_hat',0));
        sample=local_trace_sample(trace,idx);
        [ctx.mpc,prepared]=a2_mpc_prepare(ctx.mpc,sample,theta);
        [ctx.mpc,u,info]=a2_mpc_solve(ctx.mpc,prepared); out.u=u; out.info=info;
    otherwise
        error('A2:BadExecutionCase','Unsupported execution case.');
end
end

function [state,ctx]=local_init_online(case_id,paths,dataset_file,project_root)
ctx=struct(); params=parameters();
switch case_id
    case {'end_to_end_update__modern_tcn_delta_bank_124','full_cycle__slope_estimation_mpc'}
        cfg=struct('seed',42,'dataset_file',dataset_file,'onnx_file',paths.delta_onnx);
        state=ModernTCN_state_classifier('init',params,cfg); ctx.runtime_import_learnable_count=local_count_learnables(state.predictor.net); ctx.param_count=145202;
    case 'end_to_end_update__modern_tcn_22d'
        cfg=struct('seed',42,'dataset_file',dataset_file,'onnx_file',paths.modern22_onnx);
        state=ModernTCN_state_classifier('init',params,cfg); ctx.runtime_import_learnable_count=local_count_learnables(state.predictor.net); ctx.param_count=118538;
    case 'end_to_end_update__gru_22d'
        q=load(paths.gru_model,'model'); state=GRU_state_classifier('init',params,q.model); ctx.param_count=local_count_model(q.model);
    case 'end_to_end_update__tcn_22d'
        cfg=struct('seed',42,'dataset_file',dataset_file,'model_file',paths.tcn_model);
        state=TCN_state_classifier('init',params,cfg); ctx.param_count=local_count_learnables(state.predictor.net)+local_count_numeric_struct(state.predictor.heads);
    otherwise
        error('A2:BadOnlineCase','Unsupported online case.');
end
ctx.project_root=project_root;
end

function [state,ctx,out]=local_online_step(case_id,state,ctx,y)
switch case_id
    case {'end_to_end_update__modern_tcn_delta_bank_124','end_to_end_update__modern_tcn_22d','full_cycle__slope_estimation_mpc'}
        [state,out]=ModernTCN_state_classifier('update',state,double(y));
    case 'end_to_end_update__gru_22d'
        [state,out]=GRU_state_classifier('update',state,double(y));
    case 'end_to_end_update__tcn_22d'
        [state,out]=TCN_state_classifier('update',state,double(y));
end
end

function trace=local_load_trace(project_root)
registry_file=fullfile(project_root,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','01_A1_algorithm_comparison','04_closed_loop','reused_case_registry.csv');
lines=readlines(registry_file,Encoding='UTF-8'); lines=lines(2:end); lines=lines(strlength(lines)>0);
rows=split(lines,','); method_col=rows(:,1); seed_col=str2double(rows(:,2));
rows=rows(method_col=="modern_tcn_delta_bank_124" & seed_col==42,:);
[~,order]=sort(rows(:,3)); rows=rows(order,:);
if size(rows,1)~=6,error('A2:TraceRegistryMismatch','Expected six seed42 delta-bank traces, found %d.',size(rows,1));end
trace=struct('y_raw',[],'y_meas',[],'v_ref',[],'omega_ref',[],'theta_ref',[]);
for i=1:size(rows,1)
    q=load(char(rows(i,6)),'logsout'); logs=q.logsout;
    y=local_signal(logs,'diag.y_raw'); ey=local_signal(logs,'diag.e_y'); ep=local_signal(logs,'diag.e_psi'); ev=local_signal(logs,'diag.e_v'); eo=local_signal(logs,'diag.e_omega');
    vr=local_signal(logs,'diag.v_ref'); wr=local_signal(logs,'diag.omega_ref'); th=local_signal(logs,'diag.theta_ref');
    n=min([size(y,1),numel(ey),numel(ep),numel(ev),numel(eo),numel(vr),numel(wr),numel(th)]); keep=(101:n).';
    valid=all(isfinite(y(keep,:)),2)&isfinite(ey(keep))&isfinite(ep(keep))&isfinite(ev(keep))&isfinite(eo(keep))&isfinite(vr(keep))&isfinite(wr(keep))&isfinite(th(keep)); keep=keep(valid);
    trace.y_raw=[trace.y_raw;double(y(keep,:))]; %#ok<AGROW>
    trace.y_meas=[trace.y_meas;double([ey(keep),ep(keep),ev(keep),eo(keep)])]; %#ok<AGROW>
    trace.v_ref=[trace.v_ref;double(vr(keep))]; trace.omega_ref=[trace.omega_ref;double(wr(keep))]; trace.theta_ref=[trace.theta_ref;double(th(keep))]; %#ok<AGROW>
end
end

function x=local_signal(logs,name)
e=logs.get(name); if isempty(e), error('A2:MissingSignal','Missing signal %s',name); end
x=squeeze(e.Values.Data); if isvector(x),x=x(:);end
end

function s=local_trace_sample(trace,idx)
s=struct('y_meas',trace.y_meas(idx,:).','v_ref',trace.v_ref(idx),'omega_ref',trace.omega_ref(idx),'theta_ref',trace.theta_ref(idx));
end

function ctx=local_init_mpc(paths)
a=load(paths.lpv_db,'db'); b=load(paths.ctrl,'ctrl'); m=load(paths.maps,'maps_best');
ctx=struct(); ctx.db=a.db; ctx.ctrl=b.ctrl; names=fieldnames(m.maps_best);
for i=1:numel(names),ctx.ctrl.maps.(names{i})=m.maps_best.(names{i});end
ctx.ctrl.mpcobj.Weights.OutputVariables=[100 100 15 3]; ctx.ctrl.mpcobj.Weights.ManipulatedVariables=[3e-5 3e-5]; ctx.ctrl.mpcobj.Weights.ManipulatedVariablesRate=[1e-3 1e-3];
ctx.xmpc=mpcstate(ctx.ctrl.mpcobj); ctx.params=parameters(); ctx.rho_prev=[1;0;0];
end

function idx=local_index(i,ctx,trace)
if ~isempty(trace) && isfield(trace,'y_raw') && ~isempty(trace.y_raw), n=size(trace.y_raw,1);
elseif isfield(ctx,'inputs'),n=size(ctx.inputs,1); elseif isfield(ctx,'raw'),n=size(ctx.raw,1); else,n=1;end
idx=1+mod(i-1,n);
end

function Xaug=local_delta_bank(X,lags,clipv)
[n,t,f]=size(X); Xaug=zeros(n,t,f*(numel(lags)+1),'single'); Xaug(:,:,1:f)=single(X);
for j=1:numel(lags), lag=lags(j); prev=single(X); prev(:,lag+1:end,:)=single(X(:,1:end-lag,:)); d=min(clipv,max(-clipv,single(X)-prev)); Xaug(:,:,j*f+(1:f))=d; end
end

function [scope,method,interface]=local_case_identity(id)
if startsWith(id,'core_inference__'),scope='core_inference';method=extractAfter(id,'core_inference__');interface='preloaded_window';
elseif startsWith(id,'end_to_end_update__'),scope='end_to_end_update';method=extractAfter(id,'end_to_end_update__');interface='single_y_raw_frame';
elseif startsWith(id,'mpc_solve__'),scope='mpc_solve';method=extractAfter(id,'mpc_solve__');interface='prepared_adaptive_mpc_call';
elseif startsWith(id,'full_cycle__'),scope='full_cycle';method=extractAfter(id,'full_cycle__');interface='single_y_raw_to_control_update';
else,scope='end_to_end_update';method='normalization_delta_bank_124';interface='raw_128x22_window';end
scope=char(scope);method=char(method);interface=char(interface);
end

function p=local_paths(root)
p=struct();
p.delta_onnx=fullfile(root,'results','modern_tcn_metric_rebuild','25_lag_representation_repair','03_onnx_and_smoke','delta_bank_124','seed42','modern_tcn_delta_bank_124_seed42.onnx');
p.modern22_onnx=fullfile(root,'results','modern_tcn_metric_rebuild','32_four_algorithm_10seed_closed_loop','01_modern_fixed_onnx','seed42','modern_fixed_seed42.onnx');
p.gru_model=fullfile(root,'results','modern_tcn_metric_rebuild','34_gru_10seed_comparator','01_train_gru_10seed','models','GRU_model_gru10_full_gru_v5_plantfix_passive17_plus_all5_seed42.mat');
p.tcn_model=fullfile(root,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','01_A1_algorithm_comparison','02_models','models','TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed42.mat');
p.lpv_db=fullfile(root,'results','paper','agv_model_parameter_correction_workflow','04_lpv_database','lin_agv_db_agv_physics_v2_plantfix.mat');
p.maps=fullfile(root,'results','paper','agv_model_parameter_correction_workflow','06_mpc_retuning','maps_best_agv_physics_v2_plantfix_stage1.mat');
p.ctrl=fullfile(root,'data','models','ctrl.mat');
end

function [mf,mh,mb,sf,sh,sb]=local_artifacts(method,inv,paths)
mf='';mh='';mb=0;sf='';sh='';sb=0;
if strcmp(method,'modern_tcn_delta_bank_124') || strcmp(method,'slope_estimation_mpc')
    r=inv(inv.artifact_id=="modern_tcn_delta_bank_124",:); d=inv(inv.artifact_id=="modern_tcn_delta_bank_124_onnx",:); mf=char(r.path(1));mh=char(r.actual_sha256(1));mb=double(r.bytes(1));sf=paths.delta_onnx;sh=char(d.actual_sha256(1));sb=double(d.bytes(1));
elseif strcmp(method,'modern_tcn_22d')
    r=inv(inv.artifact_id=="modern_tcn_22d",:); d=inv(inv.artifact_id=="modern_tcn_22d_onnx",:); mf=char(r.path(1));mh=char(r.actual_sha256(1));mb=double(r.bytes(1));sf=paths.modern22_onnx;sh=char(d.actual_sha256(1));sb=double(d.bytes(1));
elseif strcmp(method,'gru_22d') || strcmp(method,'tcn_22d')
    r=inv(inv.artifact_id==string(method),:);mf=char(r.path(1));mh=char(r.actual_sha256(1));mb=double(r.bytes(1));sf=mf;sh=mh;sb=mb;
elseif strcmp(method,'effective_controller')
    r=inv(inv.artifact_id=="frozen_controller_cache",:);sf=char(r.path(1));sh=char(r.actual_sha256(1));sb=double(r.bytes(1));
else
    r=inv(inv.artifact_id=="a0_dataset",:);sf=char(r.path(1));sh=char(r.actual_sha256(1));sb=double(r.bytes(1));
end
end

function n=local_count_learnables(net)
n=0; if isprop(net,'Learnables'),L=net.Learnables;for i=1:height(L),n=n+numel(L.Value{i});end,end
end
function n=local_count_model(model)
n=0;if isfield(model,'feature_net'),n=n+local_count_learnables(model.feature_net);end;if isfield(model,'heads'),n=n+local_count_numeric_struct(model.heads);end
end
function n=local_count_numeric_struct(s)
n=0;if ~isstruct(s),return,end;f=fieldnames(s);for i=1:numel(f),v=s.(f{i});if isnumeric(v)||isa(v,'dlarray'),n=n+numel(v);elseif isstruct(v),n=n+local_count_numeric_struct(v);end,end
end
function v=local_field(s,name,fallback)
if isstruct(s)&&isfield(s,name)&&~isempty(s.(name)),v=s.(name);else,v=fallback;end
end
function local_write_json(file,s)
fid=fopen(file,'w','n','UTF-8');if fid<0,error('A2:WriteFailed','Cannot write %s',file);end;c=onCleanup(@()fclose(fid));fwrite(fid,jsonencode(s,PrettyPrint=true),'char'); %#ok<NASGU>
end
