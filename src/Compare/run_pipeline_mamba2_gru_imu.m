function pipeline = run_pipeline_mamba2_gru_imu(cfg)
% =============================
% 文件名：run_pipeline_mamba2_gru_imu.m
% 版本号：V1.1（端到端自动流水线入口）
% 最后修改时间：2026-04-17
% 作者：LPV-MPC Project
% 功能描述：
%   一键串联并自动执行以下流程：
%   1) GRU 对照组数据预处理
%   2) GRU 对照组训练
%   3) Mamba2/GRU/IMU 批量闭环对比
%   4) 统计分析与报告输出
%   5) 扰动生效体检（识别“扰动等级变化但指标不变”的可疑组）
%
% 设计原则：
%   - 不依赖 test_simulink_closed_loop.m。
%   - 允许在某一步失败后继续执行（可配置 stop_on_error）。
%   - 输出明确“人工待办项”，方便你补齐环境后重跑。
%
% 默认配置（按当前确认）：
%   - Mamba 后端：tcp_service
%   - 执行规模：冒烟（seeds=1:3）
%   - GRU 训练：保持现状（use_gpu=true，max_epochs=30）
%
% 使用方法：
%   1) 直接使用默认冒烟配置：
%      pipeline = run_pipeline_mamba2_gru_imu();
%
%   2) 显式传入配置（推荐，可复现）：
%      cfg = struct();
%      cfg.mamba_ai_backend = 'tcp_service';
%      cfg.require_mamba_tcp = true;
%      cfg.auto_fallback_to_stub = false;
%      cfg.compare_cfg.seeds = 1:3;  % 冒烟
%      pipeline = run_pipeline_mamba2_gru_imu(cfg);
%
% 输出：
%   - results/compare/mamba2_gru_imu/pipeline_reports/pipeline_*.mat
%   - 对比与统计结果见 compare_*/raw 与 compare_*/analysis
% =============================

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

init_project();
root = project_root();
cfg = local_apply_defaults(cfg);

pipeline = struct();
pipeline.start_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pipeline.status = 'running';
pipeline.manual_actions = {};
pipeline.steps = struct();

fprintf('\n[pipeline] start @ %s\n', pipeline.start_time);

%% Step 1: GRU dataset preparation
% 步骤1：准备 GRU 数据（对照组）
pipeline.steps.prepare_gru = local_step_template('prepare_gru');
if cfg.auto_prepare_gru
    t0 = tic;
    try
        strict_data = fullfile(root, 'data', 'gru', 'GRU_dataset_processed.mat');
        if cfg.force_prepare_gru || ~exist(strict_data, 'file')
            fprintf('[pipeline] prepare GRU dataset...\n');
            run(fullfile(root, 'src', 'gru', 'run_GRU_prepare_dataset_mamba_compare.m'));
        else
            fprintf('[pipeline] skip GRU dataset prepare (already exists): %s\n', strict_data);
        end

        if ~exist(strict_data, 'file')
            error('Expected dataset not found after preparation: %s', strict_data);
        end

        pipeline.steps.prepare_gru.ok = true;
        pipeline.steps.prepare_gru.output = strict_data;
    catch ME
        pipeline.steps.prepare_gru.ok = false;
        pipeline.steps.prepare_gru.message = ME.message;
        if cfg.stop_on_error
            error('[pipeline] prepare_gru failed: %s', ME.message);
        end
    end
    pipeline.steps.prepare_gru.elapsed_sec = toc(t0);
else
    pipeline.steps.prepare_gru.ok = true;
    pipeline.steps.prepare_gru.message = 'disabled by cfg.auto_prepare_gru=false';
end

%% Step 2: GRU training
% 步骤2：训练 GRU 对照模型
pipeline.steps.train_gru = local_step_template('train_gru');
if cfg.auto_train_gru
    t0 = tic;
    try
        model_file = fullfile(root, 'data', 'models', 'GRU_model_mamba_control.mat');
        if cfg.force_train_gru || ~exist(model_file, 'file')
            fprintf('[pipeline] train GRU model...\n');
            run(fullfile(root, 'src', 'gru', 'run_GRU_train_mamba_control.m'));
        else
            fprintf('[pipeline] skip GRU training (already exists): %s\n', model_file);
        end

        if ~exist(model_file, 'file')
            error('Expected GRU model not found after training: %s', model_file);
        end

        pipeline.steps.train_gru.ok = true;
        pipeline.steps.train_gru.output = model_file;
    catch ME
        pipeline.steps.train_gru.ok = false;
        pipeline.steps.train_gru.message = ME.message;
        if cfg.stop_on_error
            error('[pipeline] train_gru failed: %s', ME.message);
        end
    end
    pipeline.steps.train_gru.elapsed_sec = toc(t0);
else
    pipeline.steps.train_gru.ok = true;
    pipeline.steps.train_gru.message = 'disabled by cfg.auto_train_gru=false';
end

%% Step 3: Mamba runtime check
% 步骤3：检测 Mamba TCP 服务可达性
pipeline.steps.check_mamba_runtime = local_step_template('check_mamba_runtime');
[tcp_ok, tcp_msg] = local_check_mamba_runtime(cfg.mamba_host, cfg.mamba_port, cfg.mamba_timeout_sec);
pipeline.steps.check_mamba_runtime.ok = tcp_ok;
pipeline.steps.check_mamba_runtime.message = tcp_msg;

mamba_backend = cfg.mamba_ai_backend;
if strcmpi(mamba_backend, 'tcp_service') && ~tcp_ok
    if cfg.auto_fallback_to_stub
        mamba_backend = 'matlab_stub';
        msg = sprintf('Mamba service is unavailable, fallback to matlab_stub backend. host=%s port=%d', cfg.mamba_host, cfg.mamba_port);
        pipeline.manual_actions{end+1} = msg;
        fprintf('[pipeline] WARN: %s\n', msg);
    else
        msg = sprintf(['Mamba service is unavailable. Start service manually and rerun:\n' ...
                       '  cd /mnt/e/Matlab/Simulink/S-Function_16/src/Mamba\n' ...
                       '  python mamba2_online_infer.py --serve --checkpoint <best.pt> --mu-sigma <mu_sigma.npz>']);
        pipeline.manual_actions{end+1} = msg;
        if cfg.require_mamba_tcp
            pipeline.status = 'blocked';
            warning('[pipeline] blocked: %s', msg);
        end
    end
end

%% Step 4: Batch comparison
% 步骤4：按矩阵批量执行闭环仿真
pipeline.steps.run_compare = local_step_template('run_compare');
if cfg.auto_compare && ~strcmp(pipeline.status, 'blocked')
    t0 = tic;
    try
        compare_cfg = cfg.compare_cfg;
        compare_cfg.mamba_ai_backend = mamba_backend;
        compare_cfg.mamba_host = cfg.mamba_host;
        compare_cfg.mamba_port = cfg.mamba_port;
        compare_cfg.mamba_conn_timeout = cfg.mamba_timeout_sec;
        compare_cfg.mamba_read_timeout = 25.0;
        compare_results = run_compare_mamba2_gru_imu_batch(compare_cfg);

        compare_mat = fullfile(results_dir(fullfile('compare', 'mamba2_gru_imu', compare_results.run_id)), 'raw', 'case_rows.mat');
        pipeline.steps.run_compare.ok = true;
        pipeline.steps.run_compare.output = compare_mat;
    catch ME
        pipeline.steps.run_compare.ok = false;
        pipeline.steps.run_compare.message = ME.message;
        if cfg.stop_on_error
            error('[pipeline] run_compare failed: %s', ME.message);
        end
    end
    pipeline.steps.run_compare.elapsed_sec = toc(t0);
else
    pipeline.steps.run_compare.ok = true;
    if strcmp(pipeline.status, 'blocked')
        pipeline.steps.run_compare.message = 'skipped because pipeline is blocked by Mamba runtime requirement';
    else
        pipeline.steps.run_compare.message = 'disabled by cfg.auto_compare=false';
    end
end

%% Step 5: Statistical analysis
% 步骤5：统计检验、图表与报告生成
pipeline.steps.analyze = local_step_template('analyze');
if cfg.auto_analyze && pipeline.steps.run_compare.ok && ~isempty(pipeline.steps.run_compare.output)
    t0 = tic;
    try
        analyze_cfg = cfg.analyze_cfg;
        analyze_cfg.input_mat = pipeline.steps.run_compare.output;
        analysis = analyze_compare_mamba2_gru_imu_stats(analyze_cfg); %#ok<NASGU>

        pipeline.steps.analyze.ok = true;
        pipeline.steps.analyze.output = fullfile(fileparts(fileparts(analyze_cfg.input_mat)), 'analysis', 'analysis_summary.mat');
    catch ME
        pipeline.steps.analyze.ok = false;
        pipeline.steps.analyze.message = ME.message;
        if cfg.stop_on_error
            error('[pipeline] analyze failed: %s', ME.message);
        end
    end
    pipeline.steps.analyze.elapsed_sec = toc(t0);
else
    pipeline.steps.analyze.ok = true;
    pipeline.steps.analyze.message = 'skipped (no compare output or auto_analyze=false)';
end

%% Step 6: Disturbance effectiveness check
% 步骤6：扰动生效体检
pipeline.steps.disturbance_check = local_step_template('disturbance_check');
if cfg.auto_disturbance_check && pipeline.steps.run_compare.ok && ~isempty(pipeline.steps.run_compare.output)
    t0 = tic;
    try
        dcfg = cfg.disturbance_check_cfg;
        dcfg.input_mat = pipeline.steps.run_compare.output;
        dcheck = check_compare_disturbance_effectiveness(dcfg);

        pipeline.steps.disturbance_check.ok = true;
        pipeline.steps.disturbance_check.output = dcheck.summary_csv;
    catch ME
        pipeline.steps.disturbance_check.ok = false;
        pipeline.steps.disturbance_check.message = ME.message;
        if cfg.stop_on_error
            error('[pipeline] disturbance_check failed: %s', ME.message);
        end
    end
    pipeline.steps.disturbance_check.elapsed_sec = toc(t0);
else
    pipeline.steps.disturbance_check.ok = true;
    pipeline.steps.disturbance_check.message = 'skipped (no compare output or auto_disturbance_check=false)';
end

%% Finalize status
if strcmp(pipeline.status, 'running')
    if pipeline.steps.prepare_gru.ok && pipeline.steps.train_gru.ok && ...
       pipeline.steps.run_compare.ok && pipeline.steps.analyze.ok && ...
       pipeline.steps.disturbance_check.ok
        pipeline.status = 'ok';
    else
        pipeline.status = 'partial';
    end
end
pipeline.end_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');

report_dir = results_dir(fullfile('compare', 'mamba2_gru_imu', 'pipeline_reports'));
report_file = fullfile(report_dir, ['pipeline_' datestr(now, 'yyyymmdd_HHMMSS') '.mat']);
save(report_file, 'pipeline', '-v7.3');

fprintf('\n[pipeline] status = %s\n', pipeline.status);
fprintf('[pipeline] report = %s\n', report_file);

if ~isempty(pipeline.manual_actions)
    fprintf('\n[pipeline] manual actions required:\n');
    for i = 1:numel(pipeline.manual_actions)
        fprintf('  %d) %s\n', i, pipeline.manual_actions{i});
    end
end

end

function cfg = local_apply_defaults(cfg)
% 统一默认配置：当前按“tcp_service + 冒烟”执行
if ~isfield(cfg, 'auto_prepare_gru')
    cfg.auto_prepare_gru = true;
end
if ~isfield(cfg, 'force_prepare_gru')
    cfg.force_prepare_gru = false;
end
if ~isfield(cfg, 'auto_train_gru')
    cfg.auto_train_gru = true;
end
if ~isfield(cfg, 'force_train_gru')
    cfg.force_train_gru = false;
end
if ~isfield(cfg, 'auto_compare')
    cfg.auto_compare = true;
end
if ~isfield(cfg, 'auto_analyze')
    cfg.auto_analyze = true;
end
if ~isfield(cfg, 'auto_disturbance_check')
    cfg.auto_disturbance_check = true;
end
if ~isfield(cfg, 'stop_on_error')
    cfg.stop_on_error = false;
end

if ~isfield(cfg, 'mamba_ai_backend') || isempty(cfg.mamba_ai_backend)
    cfg.mamba_ai_backend = 'tcp_service';
end
if ~isfield(cfg, 'mamba_host') || isempty(cfg.mamba_host)
    % 与当前 Mamba_state_classifier 默认配置一致（WSL 网卡 IP）
    cfg.mamba_host = '172.31.248.4';
end
if ~isfield(cfg, 'mamba_port') || isempty(cfg.mamba_port)
    cfg.mamba_port = 5009;
end
if ~isfield(cfg, 'mamba_timeout_sec') || isempty(cfg.mamba_timeout_sec)
    cfg.mamba_timeout_sec = 2.0;
end
if ~isfield(cfg, 'require_mamba_tcp')
    cfg.require_mamba_tcp = true;
end
if ~isfield(cfg, 'auto_fallback_to_stub')
    cfg.auto_fallback_to_stub = false;
end

if ~isfield(cfg, 'compare_cfg') || ~isstruct(cfg.compare_cfg)
    cfg.compare_cfg = struct();
end
if ~isfield(cfg, 'analyze_cfg') || ~isstruct(cfg.analyze_cfg)
    cfg.analyze_cfg = struct();
end
if ~isfield(cfg, 'disturbance_check_cfg') || ~isstruct(cfg.disturbance_check_cfg)
    cfg.disturbance_check_cfg = struct();
end

% ===== 冒烟配置默认值（与你的当前选择一致） =====
if ~isfield(cfg.compare_cfg, 'controllers') || isempty(cfg.compare_cfg.controllers)
    cfg.compare_cfg.controllers = {'Mamba2', 'GRU', 'IMU'};
end
if ~isfield(cfg.compare_cfg, 'disturbance_levels') || isempty(cfg.compare_cfg.disturbance_levels)
    cfg.compare_cfg.disturbance_levels = [0 1 2];
end
if ~isfield(cfg.compare_cfg, 'seeds') || isempty(cfg.compare_cfg.seeds)
    cfg.compare_cfg.seeds = 1:3;
end
if ~isfield(cfg.compare_cfg, 'path_mode') || isempty(cfg.compare_cfg.path_mode)
    % 默认冒烟采用分段路径；正式对照建议切到 full150。
    cfg.compare_cfg.path_mode = 'segmented';
end
if ~isfield(cfg.compare_cfg, 'mamba_ai_backend') || isempty(cfg.compare_cfg.mamba_ai_backend)
    cfg.compare_cfg.mamba_ai_backend = cfg.mamba_ai_backend;
end

if ~isfield(cfg.analyze_cfg, 'controllers') || isempty(cfg.analyze_cfg.controllers)
    cfg.analyze_cfg.controllers = cfg.compare_cfg.controllers;
end
end

function s = local_step_template(name)
s = struct();
s.name = name;
s.ok = false;
s.message = '';
s.output = '';
s.elapsed_sec = NaN;
end

function [ok, msg] = local_check_mamba_runtime(host, port, timeout_sec)
% 使用 tcpclient 做轻量连通性探测。
% 说明：仅检测端口可达，不等同于业务推理健康检查。
try
    c = tcpclient(host, port, 'ConnectTimeout', timeout_sec, 'Timeout', timeout_sec);
    ok = ~isempty(c);
    clear c;
    if ok
        msg = sprintf('Mamba tcp service reachable: %s:%d', host, port);
    else
        msg = sprintf('Mamba tcp service check returned empty client: %s:%d', host, port);
    end
catch ME
    ok = false;
    msg = sprintf('Mamba tcp service unreachable: %s:%d (%s)', host, port, ME.message);
end
end
