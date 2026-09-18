function result = run_A1_closed_loop_manual(method, cfg)
%RUN_A1_CLOSED_LOOP_MANUAL Resumable frozen GRU/TCN six-path runner.
% method: 'gru', 'tcn', or 'all'. Formal full-length execution is default.
% For implementation smoke only: cfg=struct('smoke',true).
if nargin < 1 || isempty(method); method = 'all'; end
if nargin < 2 || ~isstruct(cfg); cfg = struct(); end
method = lower(char(method));
if ~ismember(method, {'gru','tcn','all'}); error('A1:BadMethod','method must be gru, tcn, or all'); end
smoke = local_cfg(cfg, 'smoke', false);
dry_run = local_cfg(cfg, 'dry_run', false);
worker_tag = local_safe_tag(local_cfg(cfg, 'worker_tag', 'serial'));
cache_tag = local_safe_tag(local_cfg(cfg, 'cache_tag', 's'));
status_suffix = local_safe_tag(local_cfg(cfg, 'status_suffix', ''));
init_project(); root = project_root();
task_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '01_A1_algorithm_comparison');
% Keep these paths extremely short. Simulink appends a long slprj/_sfprj
% hierarchy and Windows MATLAB can otherwise exceed MAX_PATH during build.
cache_dir = fullfile(task_root, 'w', 'c', cache_tag);
codegen_dir = fullfile(task_root, 'w', 'g', cache_tag);
local_mkdir(cache_dir); local_mkdir(codegen_dir);
Simulink.fileGenControl('set','CacheFolder',cache_dir,'CodeGenFolder',codegen_dir,'createDir',true);

config_file = fullfile(task_root, '00_protocol_lock', 'a1_config.json');
a0 = jsondecode(fileread(config_file));
seeds = double(a0.seeds(:).');
paths = a0.paths;
if smoke
    seeds = local_select_seeds(seeds, local_cfg(cfg, 'seed_subset', 21));
    paths = local_select_paths(paths, local_cfg(cfg, 'path_subset', char(paths(1).path_id)));
else
    seeds = local_select_seeds(seeds, local_cfg(cfg, 'seed_subset', []));
    paths = local_select_paths(paths, local_cfg(cfg, 'path_subset', []));
end
methods = {method}; if strcmp(method,'all'); methods = {'gru','tcn'}; end
all_rows = repmat(local_empty_row(),0,1);
for im = 1:numel(methods)
    one = methods{im};
    rows = local_run_method(root, task_root, a0, one, seeds, paths, smoke, dry_run);
    all_rows = [all_rows; rows(:)]; %#ok<AGROW>
end
result = struct('task_id','A1_algorithm_comparison','timestamp',datestr(now,30), ...
    'mode',ternary(smoke,'smoke','formal'),'dry_run',dry_run,'worker_tag',worker_tag, ...
    'cache_tag',cache_tag,'cache_dir',cache_dir,'codegen_dir',codegen_dir, ...
    'rows',struct2table(all_rows));
out_name = ternary(smoke,'closed_loop_smoke_status.csv','manual_closed_loop_status.csv');
if ~isempty(status_suffix); out_name = strrep(out_name,'.csv',['_' status_suffix '.csv']); end
writetable(result.rows, fullfile(task_root,'04_closed_loop',out_name));
save(fullfile(task_root,'04_closed_loop',strrep(out_name,'.csv','.mat')),'result','-v7.3');
end

function rows = local_run_method(root, task_root, a0, method, seeds, paths, smoke, dry_run)
method_id = [method '_22d'];
R = readtable(fullfile(task_root,'model_registry.csv'),'TextType','string');
R = R(R.method_id==string(method_id) & ismember(R.model_seed,seeds),:);
if height(R) ~= numel(seeds); error('A1:ModelRegistry','Expected %d %s models, found %d',numel(seeds),method_id,height(R)); end
if ~all(R.status=="READY"); error('A1:MissingModels','%s has non-ready models; rerun inventory after TCN training',method_id); end
base_root = fullfile(root,'results','modern_tcn_metric_rebuild','32_four_algorithm_10seed_closed_loop','02_modern_fixed_full_closed_loop');
if smoke; out_root=fullfile(task_root,'04_closed_loop','smoke',method_id); else; out_root=fullfile(task_root,'04_closed_loop','raw',method_id); end
local_mkdir(out_root);
rows = repmat(local_empty_row(),numel(seeds)*numel(paths),1); idx=0;
for iseed=1:numel(seeds)
    seed=seeds(iseed); rr=R(R.model_seed==seed,:); model_file=char(rr.model_file(1)); meta_file=char(rr.meta_or_config_file(1));
    local_assert_file(model_file,'model'); local_assert_file(meta_file,'meta');
    for ip=1:numel(paths)
        idx=idx+1; p=paths(ip); path_file=fullfile(root,char(p.file)); [~,path_tag]=fileparts(path_file);
        case_dir=fullfile(out_root,sprintf('seed%d',seed),path_tag); local_mkdir(case_dir);
        candidate_out=fullfile(case_dir,sprintf('%s_seed%d_out.mat',method_id,seed));
        prefix=sprintf('a1_%s_seed%d',method_id,seed);
        summary_file=fullfile(case_dir,[prefix '_summary.csv']);
        rows(idx)=local_empty_row(); rows(idx).method_id=string(method_id); rows(idx).seed=seed;
        rows(idx).path_id=string(p.path_id); rows(idx).path_tag=string(path_tag); rows(idx).path_file=string(path_file);
        rows(idx).model_file=string(model_file); rows(idx).meta_file=string(meta_file);
        rows(idx).candidate_file=string(candidate_out); rows(idx).summary_file=string(summary_file);
        rows(idx).started_at=string(datestr(now,30));
        modern_file=fullfile(base_root,path_tag,sprintf('modern_fixed_seed%d_out.mat',seed));
        rows(idx).matched_modern_22d_file=string(modern_file);
        try
            local_assert_file(path_file,'path'); local_assert_file(modern_file,'matched ModernTCN-22D reference');
            if dry_run
                rows(idx).status="ready"; rows(idx).message="dry_run";
            elseif local_case_complete(candidate_out,summary_file,method)
                rows(idx).status="reused_verified"; fprintf('[A1 closed-loop] reuse %s seed=%d path=%s\n',method_id,seed,path_tag);
            else
                sim_cfg=local_sim_cfg(a0,method,seed,model_file,meta_file);
                if smoke; sim_cfg.stop_time_override=3.0; end
                fprintf('[A1 closed-loop] run %s seed=%d path=%s smoke=%d\n',method_id,seed,path_tag,smoke);
                run_closed_loop_model_once(['LPVMPC_AGV_simulink_' upper(method)],path_file,candidate_out,sim_cfg);
                if strcmp(method,'gru')
                    compare_tcn_gru_modern_closed_loop_out(modern_file,candidate_out,'__skip_tcn__',path_file,case_dir, ...
                        'ModernTCN',[],sprintf('A1 GRU seed%d %s',seed,path_tag),prefix);
                else
                    compare_tcn_gru_modern_closed_loop_out(modern_file,'__skip_gru__',candidate_out,path_file,case_dir, ...
                        'ModernTCN',[],sprintf('A1 TCN seed%d %s',seed,path_tag),prefix);
                end
                if ~local_case_complete(candidate_out,summary_file,method); error('A1:IncompleteCase','Output/schema validation failed'); end
                audit=struct('task_id','A1_algorithm_comparison','mode',ternary(smoke,'smoke','formal'), ...
                    'method_id',method_id,'seed',seed,'path_id',char(p.path_id),'path_file',path_file, ...
                    'path_sha256',char(p.sha256),'model_file',model_file,'meta_file',meta_file, ...
                    'matched_modern_22d_file',modern_file,'candidate_file',candidate_out,'summary_file',summary_file, ...
                    'plant_revision',char(a0.plant.revision_id),'mpc',a0.lpv_mpc,'status','COMPLETE','timestamp',datestr(now,30));
                local_write_json(fullfile(case_dir,'case_manifest.json'),audit);
                rows(idx).status="complete";
            end
        catch ME
            rows(idx).status="failed"; rows(idx).message=string(getReport(ME,'extended','hyperlinks','off'));
            fid=fopen(fullfile(case_dir,'failure.txt'),'w','n','UTF-8'); if fid>=0; fprintf(fid,'%s\n',rows(idx).message); fclose(fid); end
            warning('A1:ClosedLoopFailed','%s seed=%d path=%s: %s',method_id,seed,path_tag,ME.message);
        end
        rows(idx).finished_at=string(datestr(now,30));
        partial=struct2table(rows(1:idx)); writetable(partial,fullfile(out_root,[method_id '_path_runs_partial.csv']));
    end
end
writetable(struct2table(rows),fullfile(out_root,[method_id '_path_runs.csv']));
end

function cfg=local_sim_cfg(a0,method,seed,model_file,meta_file)
cfg=struct(); cfg.params_override=parameters();
est=struct('seed',seed,'dataset_file',fullfile(project_root(),char(a0.dataset.file)), ...
    'model_file',model_file,'meta_file',meta_file,'theta_output_gain',1.0, ...
    'theta_abs_limit',deg2rad(12.0),'theta_rate_limit',deg2rad(5.0),'theta_mpc_deadzone',deg2rad(2.0));
if strcmp(method,'gru'); est.case_name='inputstats_hidden96_l2'; cfg.gru_sim_cfg=est;
else; est.case_name='tcn96_rawtheta_sym'; cfg.tcn_sim_cfg=est; end
end
function tf=local_case_complete(out_file,summary_file,method)
tf=false; if exist(out_file,'file')~=2 || exist(summary_file,'file')~=2; return; end
try
    info=whos('-file',out_file);
    vars=string({info.name}); if ~any(vars=="logsout"); return; end
    T=readtable(summary_file,'TextType','string'); T=T(strcmpi(T.zone,"all"),:);
    tf=any(strcmpi(T.controller,upper(method))) && all(ismember({'ey_rmse','xy_rmse','epsi_rmse','j_du','omega_cmd_rms'},T.Properties.VariableNames));
catch; tf=false; end
end
function v=local_cfg(cfg,name,default)
if isfield(cfg,name)&&~isempty(cfg.(name)); v=cfg.(name); else; v=default; end
end
function seeds=local_select_seeds(all_seeds,subset)
if isempty(subset); seeds=all_seeds; return; end
seeds=double(subset(:).');
if any(~ismember(seeds,all_seeds)); error('A1:BadSeedSubset','seed_subset contains a non-frozen seed'); end
seeds=all_seeds(ismember(all_seeds,seeds));
end
function selected=local_select_paths(paths,subset)
if isempty(subset); selected=paths; return; end
if ischar(subset)||isstring(subset); subset=cellstr(string(subset)); end
want=string(subset(:));
keep=false(numel(paths),1);
for i=1:numel(paths)
    [~,tag]=fileparts(char(paths(i).file));
    keep(i)=any(want==string(paths(i).path_id) | want==string(tag) | want==string(paths(i).file));
end
selected=paths(keep);
if isempty(selected)||numel(selected)~=numel(unique(want))
    error('A1:BadPathSubset','path_subset did not uniquely match frozen paths');
end
end
function tag=local_safe_tag(value)
tag=regexprep(char(string(value)),'[^A-Za-z0-9_-]','_');
end
function local_assert_file(path,label)
if exist(path,'file')~=2 && exist(path,'file')~=4; error('A1:MissingFile','Missing %s: %s',label,path); end
end
function local_mkdir(path)
if exist(path,'dir')~=7; mkdir(path); end
end
function local_write_json(path,data)
fid=fopen(path,'w','n','UTF-8'); if fid<0; error('A1:JsonWrite','Cannot write %s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(data,'PrettyPrint',true));
end
function out=ternary(cond,a,b)
if cond; out=a; else; out=b; end
end
function row=local_empty_row()
row=struct('method_id',"",'seed',NaN,'path_id',"",'path_tag',"",'path_file',"", ...
    'model_file',"",'meta_file',"",'matched_modern_22d_file',"",'candidate_file',"", ...
    'summary_file',"",'status',"pending",'message',"",'started_at',"",'finished_at',"");
end
