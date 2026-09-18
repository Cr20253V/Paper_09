function result = run_a3_experiment(phase)
%RUN_A3_EXPERIMENT Run A3 smoke/determinism or the complete 18-case grid.
if nargin<1||isempty(phase), phase='full'; end
phase=lower(char(phase));
init_project(); root=project_root();
a3=fullfile(root,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','03_A3_slope_scheduling_necessity');
tools=fullfile(a3,'02_tools'); addpath(tools);
addpath(fullfile(root,'results','modern_tcn_metric_rebuild','36_moderntcn_imu_fusion','tools'));
cache=fullfile(a3,'c'); if exist(cache,'dir')~=7,mkdir(cache);end
Simulink.fileGenControl('set','CacheFolder',cache,'CodeGenFolder',cache);

create_a3_isolated_model(false);
model_file=fullfile(a3,'00_protocol_lock','a3.slx');
[~,model_name]=fileparts(model_file);
runtime=local_runtime(root);
params=parameters();
if isfield(params,'enable_noise'), params.enable_noise=false; end

paths=local_paths(root);
controllers={ ...
    struct('id','ZS_LPV_MPC','mode',1), ...
    struct('id','IMU_LPV_MPC','mode',2), ...
    struct('id','Oracle_LPV_MPC','mode',3)};
if strcmp(phase,'smoke')
    jobs={controllers{1},paths(3),2.0,'zs'; controllers{2},paths(3),2.0,'imu_a'; ...
        controllers{3},paths(3),2.0,'oracle'; controllers{2},paths(3),2.0,'imu_b'};
else
    jobs=cell(numel(controllers)*numel(paths),4); k=0;
    for c=1:numel(controllers),for p=1:numel(paths),k=k+1;jobs(k,:)={controllers{c},paths(p),[],''};end,end
end

rows=repmat(struct('case_id','','status','','attempt_dir','','message',''),size(jobs,1),1);
for j=1:size(jobs,1)
    ctrl=jobs{j,1}; p=jobs{j,2}; stop_override=jobs{j,3}; suffix=jobs{j,4};
    if strcmp(phase,'smoke')
        case_root=fullfile(a3,'03_cases','_smoke',[ctrl.id '__' p.id '__' suffix]);
        case_id=[ctrl.id '__' p.id '__' suffix];
    else
        case_root=fullfile(a3,'03_cases',ctrl.id,p.id); case_id=[ctrl.id '__' p.id];
    end
    if exist(case_root,'dir')~=7,mkdir(case_root);end
    local_case_manifest(case_root,case_id,ctrl,p,phase,model_file);
    [attempt_dir,attempt_no]=local_next_attempt(case_root);
    mkdir(attempt_dir); log_file=fullfile(attempt_dir,'run.log');
    diary(log_file); diary on;
    fprintf('\n[A3] START case=%s attempt=%d %s\n',case_id,attempt_no,char(datetime('now')));
    tic_case=tic;
    try
        assignin('base','a3_theta_mode',double(ctrl.mode));
        clear A3_Causal_IMU_Theta_sim node36_causal_imu_slope_estimator
        out_file=fullfile(attempt_dir,'case_out.mat');
        cfg=struct('model_file',model_file,'params_override',params, ...
            'mpc_runtime_override',runtime);
        if ~isempty(stop_override),cfg.stop_time_override=stop_override;end
        run_closed_loop_model_once(model_name,p.file,out_file,cfg);
        metrics=evaluate_a3_case(out_file,p.file,ctrl.id,p.id,attempt_dir);
        receipt=struct('task_id','A3','case_id',case_id,'attempt',attempt_no, ...
            'status',metrics.case_status,'elapsed_wall_s',toc(tic_case), ...
            'output_mat',out_file,'trace_csv',fullfile(attempt_dir,'trace.csv'), ...
            'case_metrics',fullfile(attempt_dir,'case_metrics.json'), ...
            'completed_at',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX')));
        local_json(fullfile(attempt_dir,'attempt_receipt.json'),receipt);
        rows(j)=struct('case_id',case_id,'status',metrics.case_status,'attempt_dir',attempt_dir,'message','');
        fprintf('[A3] END case=%s status=%s wall=%.1fs\n',case_id,metrics.case_status,receipt.elapsed_wall_s);
    catch ME
        receipt=struct('task_id','A3','case_id',case_id,'attempt',attempt_no,'status','FAILED', ...
            'elapsed_wall_s',toc(tic_case),'error_identifier',ME.identifier,'error_message',ME.message, ...
            'stack',{arrayfun(@(x)struct('file',x.file,'name',x.name,'line',x.line),ME.stack)}, ...
            'completed_at',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX')));
        local_json(fullfile(attempt_dir,'attempt_receipt.json'),receipt);
        rows(j)=struct('case_id',case_id,'status','FAILED','attempt_dir',attempt_dir,'message',ME.message);
        fprintf(2,'[A3] FAILED case=%s: %s\n',case_id,ME.getReport('extended','hyperlinks','off'));
    end
    diary off;
end

if strcmp(phase,'smoke')
    local_determinism_check(a3);
    out_summary=fullfile(a3,'00_protocol_lock','smoke_run_summary.json');
else
    out_summary=fullfile(a3,'04_summary','full_run_execution_summary.json');
end
result=struct('task_id','A3','phase',phase,'rows',rows,'complete',sum(strcmp({rows.status},'COMPLETE')), ...
    'failed',sum(strcmp({rows.status},'FAILED')),'finished_at',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX')));
local_json(out_summary,result);
fprintf('[A3] phase=%s complete=%d failed=%d summary=%s\n',phase,result.complete,result.failed,out_summary);
end

function runtime=local_runtime(root)
mf=fullfile(root,'results','paper','agv_model_parameter_correction_workflow','06_mpc_retuning','maps_best_agv_physics_v2_plantfix_stage1.mat');
db=fullfile(root,'results','paper','agv_model_parameter_correction_workflow','04_lpv_database','lin_agv_db_agv_physics_v2_plantfix.mat');
S=load(mf,'maps_best');
runtime=struct('id','A3_A0_frozen_Np150_Nc30_plantfix','Np',150,'Nc',30, ...
    'Q',[100 100 15 3],'R',[3e-5 3e-5],'dR',[1e-3 1e-3], ...
    'umin',[-600;-1.2],'umax',[600;1.2],'dumin',[-400;-0.9],'dumax',[400;0.9], ...
    'ymin',[-1;-.5;-.5;-.3],'ymax',[1;.5;.5;.3], ...
    'soft_weight_pos',3000,'soft_weight_yaw',3000,'maps_template',S.maps_best,'db_file',db);
end

function paths=local_paths(root)
data={ ...
 'p01_factory_logistics_showcase','data/paths/path_factory_logistics_showcase_theta10_v10.mat','4291e3ad60a5e3dbb79ae60f115c53bc6db71447309c758b97bf539f56e58670'; ...
 'p02_sharp_turn_transition','data/paths/path_closed_loop_sharp_turn_transition_theta10_v1.mat','c5c5f33077067f1c98bd319d199cc4f4096aa6fa309f8d692c5662882e5d1f68'; ...
 'p03_long_updown','data/paths/path_closed_loop_long_updown_theta10_v1.mat','ab82393620a90964d3973f42bec9bcdb8ac0733db5db08670d152fded5ca2e08'; ...
 'p04_soft_updown_straight_turn','data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat','0ceee80c3e6883f803df538a0e3519d2ac14966ab70af5c17e9514dd50fa895d'; ...
 'p05_factory_flat_logistics','data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat','8817d10f891dfc8956d676081c946c68714043e541c31ba54c4656fd09d8687e'; ...
 'p06_downhill_after_turn','data/paths/factory_targeted_eval/path_factory_target_downhill_straight_after_turn_v1.mat','c929727187cf8ae08030636e47d2b0a465d2cddaa68f0b8b8b0b8a5ad630ece8'};
paths=repmat(struct('id','','file','','sha256',''),size(data,1),1);
for i=1:size(data,1),paths(i)=struct('id',data{i,1},'file',fullfile(root,strrep(data{i,2},'/',filesep)),'sha256',data{i,3});end
end

function [dirpath,n]=local_next_attempt(case_root)
n=1; while exist(fullfile(case_root,sprintf('attempt_%03d',n)),'dir')==7,n=n+1;end
dirpath=fullfile(case_root,sprintf('attempt_%03d',n));
end

function local_case_manifest(case_root,case_id,ctrl,p,phase,model_file)
s=struct('task_id','A3','protocol_id','A0_paper_final_unified_protocol_v1','case_id',case_id, ...
 'phase',phase,'controller_id',ctrl.id,'theta_mode',ctrl.mode,'path_id',p.id,'path_file',p.file, ...
 'path_sha256',p.sha256,'model_file',model_file,'plant_revision','agv_physics_v2_plantfix', ...
 'sensor_noise_seed',[],'process_disturbance_seed',[],'noise_enabled',false);
local_json(fullfile(case_root,'case_manifest.json'),s);
end

function local_determinism_check(a3)
a=fullfile(a3,'03_cases','_smoke','IMU_LPV_MPC__p03_long_updown__imu_a','attempt_001','trace.csv');
b=fullfile(a3,'03_cases','_smoke','IMU_LPV_MPC__p03_long_updown__imu_b','attempt_001','trace.csv');
s=struct('status','FAIL_MISSING_TRACES','trace_a',a,'trace_b',b,'max_abs_theta_imu_difference_rad',NaN);
if exist(a,'file')==2&&exist(b,'file')==2
    A=readtable(a);B=readtable(b); n=min(height(A),height(B));
    s.max_abs_theta_imu_difference_rad=max(abs(A.theta_imu_raw(1:n)-B.theta_imu_raw(1:n)),[],'omitnan');
    if s.max_abs_theta_imu_difference_rad<=1e-12,s.status='PASS_DETERMINISTIC';else,s.status='FAIL_NONDETERMINISTIC';end
end
local_json(fullfile(a3,'00_protocol_lock','imu_determinism_check.json'),s);
end

function local_json(file,s)
fid=fopen(file,'w','n','UTF-8');c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(s,'PrettyPrint',true,'ConvertInfAndNaN',true));
end
