function result = run_A1_closed_loop_parallel(cfg)
%RUN_A1_CLOSED_LOOP_PARALLEL Run GRU and TCN grids on two process workers.
% Each worker owns an independent MATLAB base workspace and independent
% Simulink cache/codegen folders. Canonical case outputs and resume checks are
% identical to the serial runner.
if nargin<1||~isstruct(cfg); cfg=struct(); end
smoke=local_cfg(cfg,'smoke',false);
dry_run=local_cfg(cfg,'dry_run',false);
method=lower(char(local_cfg(cfg,'method','all')));
if ~strcmp(method,'all')
    error('A1:UnsafeSameModelParallel', ...
        ['Only cfg.method=''all'' is supported: one GRU worker plus one TCN worker. ' ...
         'Two workers simulating the same model did not reliably return logsout.']);
end
if ~license('test','Distrib_Computing_Toolbox')
    error('A1:ParallelLicense','Parallel Computing Toolbox license unavailable');
end
if ~license('test','Simulink')
    error('A1:SimulinkLicense','Simulink license unavailable');
end

init_project(); root=project_root();
task_root=fullfile(root,'results','modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark','01_A1_algorithm_comparison');
pool=gcp('nocreate');
if isempty(pool)
    fprintf('[A1 parallel] starting two process workers...\n');
    pool=parpool('Processes',2);
elseif pool.NumWorkers~=2
    error('A1:PoolSize', ...
        'Existing pool has %d workers; close it and use a two-worker process pool', ...
        pool.NumWorkers);
end

common=struct('smoke',smoke,'dry_run',dry_run);
if isfield(cfg,'path_subset'); common.path_subset=cfg.path_subset; end
if isfield(cfg,'seed_subset'); common.seed_subset=cfg.seed_subset; end
cfg1=common; cfg1.worker_tag='parallel_gru'; cfg1.cache_tag='g'; cfg1.status_suffix='parallel_gru';
cfg2=common; cfg2.worker_tag='parallel_tcn'; cfg2.cache_tag='t'; cfg2.status_suffix='parallel_tcn';
methods={'gru','tcn'}; labels=["GRU","TCN"];
partition='GRU method / TCN method';

f(1)=parfeval(pool,@run_A1_closed_loop_manual,1,methods{1},cfg1);
f(2)=parfeval(pool,@run_A1_closed_loop_manual,1,methods{2},cfg2);
last=[-1 -1];
heartbeat=0;
fprintf('[A1 parallel] workers submitted: %s\n',partition);
while ~all(strcmp({f.State},'finished'))
    pause(10);
    heartbeat=heartbeat+1;
    counts=[local_progress(task_root,[methods{1} '_22d'],smoke), ...
        local_progress(task_root,[methods{2} '_22d'],smoke)];
    for i=1:2
        if counts(i)~=last(i)||mod(heartbeat,6)==0
            fprintf('[A1 parallel] %s progress: %d case outputs present; state=%s\n', ...
                labels(i),counts(i),f(i).State);
            last(i)=counts(i);
        end
    end
end

parts=cell(1,2); errors=strings(1,2);
for i=1:2
    try
        parts{i}=fetchOutputs(f(i));
    catch ME
        errors(i)=string(getReport(ME,'extended','hyperlinks','off'));
    end
end
rows=repmat(local_empty_row(),0,1);
for i=1:2
    if isempty(parts{i}); continue; end
    one=table2struct(parts{i}.rows);
    rows=[rows; one(:)]; %#ok<AGROW>
end
run_mode='formal';
if dry_run; run_mode='dry_run'; elseif smoke; run_mode='smoke'; end
result=struct('task_id','A1_algorithm_comparison','timestamp',datestr(now,30), ...
    'mode',run_mode,'pool_type','Processes','workers',2, ...
    'worker_partition',partition,'rows',struct2table(rows), ...
    'errors',errors);
failed_case_count=local_failed_count(result.rows);
name='manual_closed_loop_parallel_status';
if dry_run
    name='closed_loop_parallel_dry_run_status';
elseif smoke
    name='closed_loop_parallel_smoke_status';
end
writetable(result.rows,fullfile(task_root,'04_closed_loop',[name '.csv']));
save(fullfile(task_root,'04_closed_loop',[name '.mat']),'result','-v7.3');
fid=fopen(fullfile(task_root,'04_closed_loop',[name '.json']),'w','n','UTF-8');
if fid>=0
    payload=struct('task_id',result.task_id,'timestamp',result.timestamp, ...
        'mode',result.mode,'pool_type',result.pool_type,'workers',result.workers, ...
        'worker_partition',result.worker_partition,'row_count',height(result.rows), ...
        'failed_future_count',sum(strlength(errors)>0), ...
        'failed_case_count',failed_case_count);
    fprintf(fid,'%s\n',jsonencode(payload,'PrettyPrint',true)); fclose(fid);
end
if any(strlength(errors)>0)
    error('A1:ParallelWorkerFailed', ...
        'One or more workers failed. Inspect parallel status MAT and worker partial CSV files.');
end
if failed_case_count>0
    error('A1:ParallelCaseFailed', ...
        '%d parallel cases failed. Inspect the parallel status CSV and per-case failure.txt files.', ...
        failed_case_count);
end
fprintf('[A1 parallel] complete: %d rows, mode=%s\n',height(result.rows),run_mode);
end

function n=local_progress(task_root,method_id,smoke)
if smoke
    base=fullfile(task_root,'04_closed_loop','smoke',method_id);
else
    base=fullfile(task_root,'04_closed_loop','raw',method_id);
end
if exist(base,'dir')~=7; n=0; return; end
d=dir(fullfile(base,'seed*','*',[method_id '_seed*_out.mat']));
n=numel(d);
end
function v=local_cfg(cfg,name,default)
if isfield(cfg,name)&&~isempty(cfg.(name)); v=cfg.(name); else; v=default; end
end
function n=local_failed_count(T)
n=0;
if isempty(T)||~ismember('status',T.Properties.VariableNames); return; end
n=sum(string(T.status)=="failed");
end
function out=ternary(cond,a,b)
if cond; out=a; else; out=b; end
end
function row=local_empty_row()
row=struct('method_id',"",'seed',NaN,'path_id',"",'path_tag',"",'path_file',"", ...
    'model_file',"",'meta_file',"",'matched_modern_22d_file',"",'candidate_file',"", ...
    'summary_file',"",'status',"pending",'message',"",'started_at',"",'finished_at',"");
end
