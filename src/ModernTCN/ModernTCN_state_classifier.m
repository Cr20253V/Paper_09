function [state, out] = ModernTCN_state_classifier(action, varargin)
%MODERNTCN_STATE_CLASSIFIER ModernTCN 在线工况识别状态机。
%
% 功能说明：
%   本函数从每个仿真步的 y_raw 中提取与 passive17_plus_all5
%   完全一致的 22 维 IMU-free 特征，使用该数据集内保存的 scaler 做归一化，
%   维护 128 步滑动窗口，然后调用当前推荐 ModernTCN ONNX predictor 推理。
%
% 设计边界：
%   1. 本函数只用于 MATLAB/Simulink 仿真，不用于代码生成部署。
%   2. 输入是原始 y_raw 单帧，不是已经归一化的 [128,22] 窗口。
%      Plan B-lite command-response datasets additionally accept u_cmd.
%   3. theta_hat 先作为诊断输出；第一阶段不建议直接接入 RhoFilter。
%
% 用法：
%   params = parameters();
%   state = ModernTCN_state_classifier('init', params);
%   [state, out] = ModernTCN_state_classifier('update', state, y_raw_t);

switch lower(action)
    case 'init'
        if nargin < 2
            error('ModernTCN:init', '初始化需要提供 params。');
        end
        cfg = struct();
        if nargin >= 3 && isstruct(varargin{2})
            cfg = varargin{2};
        end
        state = local_init(varargin{1}, cfg);
        out = [];

    case 'update'
        if nargin < 3
            error('ModernTCN:update', '更新需要提供 state 和 y_raw_t。');
        end
        if nargin >= 4
            u_cmd = varargin{3};
        else
            u_cmd = [];
        end
        [state, out] = local_update(varargin{1}, varargin{2}, u_cmd);

    otherwise
        error('ModernTCN:BadAction', '未知操作: %s，应为 init 或 update。', action);
end
end

function state = local_init(params, cfg)
root = local_project_root();
default_cfg = ModernTCN_default_config(root);
cfg = local_apply_deployment_override(cfg);

if ~isfield(cfg, 'seed') || isempty(cfg.seed)
    cfg.seed = default_cfg.seed;
end
if ~isfield(cfg, 'dataset_file') || isempty(cfg.dataset_file)
    cfg.dataset_file = default_cfg.dataset_file;
end
if (~isfield(cfg, 'run_tag') || isempty(cfg.run_tag)) && (~isfield(cfg, 'onnx_file') || isempty(cfg.onnx_file))
    cfg.run_tag = default_cfg.run_tag;
end
if ~isfield(cfg, 'theta_output_gain') || isempty(cfg.theta_output_gain)
    cfg.theta_output_gain = local_field_or_default(default_cfg, 'theta_output_gain', 1.0);
end
if ~isfield(cfg, 'theta_abs_limit') || isempty(cfg.theta_abs_limit)
    cfg.theta_abs_limit = local_field_or_default(default_cfg, 'theta_abs_limit', inf);
end
if ~isfield(cfg, 'theta_rate_limit') || isempty(cfg.theta_rate_limit)
    cfg.theta_rate_limit = local_field_or_default(default_cfg, 'theta_rate_limit', inf);
end
if ~isfield(cfg, 'theta_mpc_deadzone') || isempty(cfg.theta_mpc_deadzone)
    cfg.theta_mpc_deadzone = local_field_or_default(default_cfg, 'theta_mpc_deadzone', deg2rad(2.0));
end
if ~isfield(cfg, 'theta_mpc_deadzone_soft') || isempty(cfg.theta_mpc_deadzone_soft)
    cfg.theta_mpc_deadzone_soft = local_field_or_default( ...
        default_cfg, 'theta_mpc_deadzone_soft', cfg.theta_mpc_deadzone);
end
if ~isfield(cfg, 'theta_mpc_rate_limit') || isempty(cfg.theta_mpc_rate_limit)
    cfg.theta_mpc_rate_limit = local_field_or_default(default_cfg, 'theta_mpc_rate_limit', inf);
end
if ~isfield(cfg, 'tau_theta') || isempty(cfg.tau_theta)
    cfg.tau_theta = local_field_or_default(default_cfg, 'tau_theta', 0.15);
end
if ~isfield(cfg, 'dwell_main') || isempty(cfg.dwell_main)
    cfg.dwell_main = local_field_or_default(default_cfg, 'dwell_main', 0.20);
end
if ~isfield(cfg, 'dwell_turn') || isempty(cfg.dwell_turn)
    cfg.dwell_turn = local_field_or_default(default_cfg, 'dwell_turn', 0.40);
end
if ~isfield(cfg, 'disable_predictor') || isempty(cfg.disable_predictor)
    cfg.disable_predictor = false;
end
if ~isfield(cfg, 'input_augment') || isempty(cfg.input_augment)
    cfg.input_augment = 'none';
end
if ~isfield(cfg, 'delta_lag') || isempty(cfg.delta_lag)
    cfg.delta_lag = 1;
end
if ~isfield(cfg, 'delta_pad') || isempty(cfg.delta_pad)
    cfg.delta_pad = 'zero';
end
if ~isfield(cfg, 'lag_steps') || isempty(cfg.lag_steps)
    cfg.lag_steps = [1 2 4];
end
if ~isfield(cfg, 'lag_pad') || isempty(cfg.lag_pad)
    cfg.lag_pad = 'edge';
end
if ~isfield(cfg, 'delta_clip_abs') || isempty(cfg.delta_clip_abs)
    cfg.delta_clip_abs = 5.0;
end
if ~isfield(cfg, 'raw_input_dim') || isempty(cfg.raw_input_dim)
    cfg.raw_input_dim = 22;
end
if ~isfield(cfg, 'augmented_input_dim') || isempty(cfg.augmented_input_dim)
    cfg.augmented_input_dim = 44;
end
if ~isfield(cfg, 'turn_command_guard_enable') || isempty(cfg.turn_command_guard_enable)
    cfg.turn_command_guard_enable = local_field_or_default(default_cfg, 'turn_command_guard_enable', false);
end
if ~isfield(cfg, 'turn_command_guard_omega_abs') || isempty(cfg.turn_command_guard_omega_abs)
    cfg.turn_command_guard_omega_abs = local_field_or_default(default_cfg, 'turn_command_guard_omega_abs', 0.0);
end
if ~isfield(cfg, 'turn_command_guard_mean_abs') || isempty(cfg.turn_command_guard_mean_abs)
    cfg.turn_command_guard_mean_abs = local_field_or_default( ...
        default_cfg, 'turn_command_guard_mean_abs', cfg.turn_command_guard_omega_abs);
end
if ~isfield(cfg, 'turn_command_guard_min_active_sec') || isempty(cfg.turn_command_guard_min_active_sec)
    cfg.turn_command_guard_min_active_sec = local_field_or_default( ...
        default_cfg, 'turn_command_guard_min_active_sec', 0.0);
end
if ~isfield(cfg, 'main_slope_release_enable') || isempty(cfg.main_slope_release_enable)
    cfg.main_slope_release_enable = local_field_or_default(default_cfg, 'main_slope_release_enable', false);
end
if ~isfield(cfg, 'main_slope_release_theta_abs_deg') || isempty(cfg.main_slope_release_theta_abs_deg)
    cfg.main_slope_release_theta_abs_deg = local_field_or_default(default_cfg, 'main_slope_release_theta_abs_deg', 0.0);
end
if ~isfield(cfg, 'main_slope_release_omega_abs') || isempty(cfg.main_slope_release_omega_abs)
    cfg.main_slope_release_omega_abs = local_field_or_default(default_cfg, 'main_slope_release_omega_abs', 0.0);
end
if ~isfield(cfg, 'main_slope_release_omega_mean_abs') || isempty(cfg.main_slope_release_omega_mean_abs)
    cfg.main_slope_release_omega_mean_abs = local_field_or_default( ...
        default_cfg, 'main_slope_release_omega_mean_abs', cfg.main_slope_release_omega_abs);
end
if ~isfield(cfg, 'main_slope_release_min_active_sec') || isempty(cfg.main_slope_release_min_active_sec)
    cfg.main_slope_release_min_active_sec = local_field_or_default( ...
        default_cfg, 'main_slope_release_min_active_sec', 0.0);
end
if ~isfield(cfg, 'main_slope_release_force_turn_straight') || isempty(cfg.main_slope_release_force_turn_straight)
    cfg.main_slope_release_force_turn_straight = local_field_or_default( ...
        default_cfg, 'main_slope_release_force_turn_straight', false);
end
if ~isfield(cfg, 'hybrid_mode') || isempty(cfg.hybrid_mode)
    cfg.hybrid_mode = 'none';
end
if ~isfield(cfg, 'hybrid_main_conf_threshold') || isempty(cfg.hybrid_main_conf_threshold)
    cfg.hybrid_main_conf_threshold = 0.55;
end
if ~isfield(cfg, 'hybrid_turn_conf_threshold') || isempty(cfg.hybrid_turn_conf_threshold)
    cfg.hybrid_turn_conf_threshold = 0.55;
end
if ~isfield(cfg, 'e5_conf_sched_enable') || isempty(cfg.e5_conf_sched_enable)
    cfg.e5_conf_sched_enable = false;
end
if ~isfield(cfg, 'e5_confidence_mode') || isempty(cfg.e5_confidence_mode)
    cfg.e5_confidence_mode = 'main_conf';
end
if ~isfield(cfg, 'e5_conf_threshold') || isempty(cfg.e5_conf_threshold)
    cfg.e5_conf_threshold = 0.6;
end
if ~isfield(cfg, 'e5_delta_theta_max_deg_per_step') || isempty(cfg.e5_delta_theta_max_deg_per_step)
    cfg.e5_delta_theta_max_deg_per_step = 0.1;
end
state_force_label_main = local_label_override_from_cfg(cfg, 'force_label_main', [1 2 3]);
state_force_label_turn = local_label_override_from_cfg(cfg, 'force_label_turn', [-1 0 1]);
onnx_file = '';
if isfield(cfg, 'onnx_file') && ~isempty(cfg.onnx_file)
    onnx_file = char(cfg.onnx_file);
elseif isfield(cfg, 'run_tag') && ~isempty(cfg.run_tag)
    onnx_file = fullfile(root, 'results', 'modern_tcn', char(cfg.run_tag), ...
        sprintf('modern_tcn_seed%d.onnx', cfg.seed));
end

if exist(cfg.dataset_file, 'file') ~= 2
    error('ModernTCN:MissingDataset', '找不到 ModernTCN 数据集: %s', cfg.dataset_file);
end

S = load(cfg.dataset_file, 'dataset');
dataset = S.dataset;
scaler = dataset.scaler;

state = struct();
state.params = params;
state.Ts = local_field_or_default(params, 'Ts', 0.01);
state.seed = cfg.seed;
state.dataset_file = cfg.dataset_file;
state.onnx_file = onnx_file;
state.scaler = scaler;
state.feat_names = dataset.feat_names;
state.seq_len = local_field_or_default(dataset.meta, 'seq_len', 128);
state.feat_dim = numel(scaler.mean);
state.feature_contract_name = local_field_or_default(scaler, 'feature_contract', ...
    local_field_or_default(dataset.meta, 'feature_contract', 'passive17_plus_all5'));
feature_contract = local_feature_contract(state.feature_contract_name);
if state.feat_dim ~= feature_contract.input_dim
    error('ModernTCN:FeatureContractMismatch', ...
        'Dataset feature dim is %d, but %s requires %d.', ...
        state.feat_dim, feature_contract.feature_contract, feature_contract.input_dim);
end
state.buffer = zeros(state.seq_len, state.feat_dim, 'single');
state.buffer_count = 0;

% 与 TCN_prepare_dataset.m 保持一致：训练数据跳过起始 1s 后再建窗。
state.skip_initial_sec = local_field_or_default(dataset.meta, 'skip_initial_sec', 1.0);
state.skip_initial_steps = round(state.skip_initial_sec / state.Ts);
state.step = 0;

% 特征提取参数。字段来自 TCN scaler，缺省值与 TCN_prepare_dataset.m 一致。
state.tau_accel_lp = local_field_or_default(scaler, 'tau_accel_lp', 0.4);
state.tau_diff = local_field_or_default(scaler, 'tau_diff', 0.3);
state.alpha_accel = state.Ts / (state.tau_accel_lp + state.Ts);
state.alpha_diff = state.Ts / (state.tau_diff + state.Ts);
state.input_augment = lower(strtrim(char(cfg.input_augment)));
state.delta_lag = max(1, round(double(cfg.delta_lag)));
state.delta_pad = lower(strtrim(char(cfg.delta_pad)));
state.lag_steps = round(double(cfg.lag_steps));
state.lag_pad = lower(strtrim(char(cfg.lag_pad)));
state.delta_clip_abs = double(cfg.delta_clip_abs);
state.raw_input_dim = max(1, round(double(cfg.raw_input_dim)));
state.augmented_input_dim = max(state.raw_input_dim, round(double(cfg.augmented_input_dim)));
state.raw_feature_mean = local_field_or_default(cfg, 'raw_feature_mean', []);
state.raw_feature_std = local_field_or_default(cfg, 'raw_feature_std', []);
state.physics_feature_mean = local_field_or_default(cfg, 'physics_feature_mean', []);
state.physics_feature_std = local_field_or_default(cfg, 'physics_feature_std', []);
state.physics_clip_abs = double(local_field_or_default(cfg, 'physics_clip_abs', 8.0));
state.physics_params = local_field_or_default(cfg, 'physics_params', struct());

state.cmd_stats_window_sec = local_field_or_default(feature_contract, 'command_stats_window_sec', 0.2);
state.u_cmd_already_lagged = logical(local_field_or_default(cfg, ...
    'u_cmd_already_lagged', false));
feature_cfg = struct('tau_diff', state.tau_diff, ...
    'tau_accel_lp', state.tau_accel_lp, ...
    'cmd_stats_window_sec', state.cmd_stats_window_sec, ...
    'u_cmd_already_lagged', state.u_cmd_already_lagged);
if strcmpi(feature_contract.feature_contract, 'passive17_plus_all5_cmdresp_lite_v1')
    state.feature_state = extract_command_response_features('init', params, state.Ts, feature_cfg);
elseif strcmpi(feature_contract.feature_contract, 'passive17_plus_all5_cmdresp_lag1_only_v1')
    state.feature_state = extract_command_response_lag1_features('init', params, state.Ts, feature_cfg);
else
    state.feature_state = extract_passive_features('init', params, state.Ts, feature_cfg);
end

% 标签驻留时间。ModernTCN 的 offline 指标较稳，但 Simulink 中单步更新仍需
% 抑制边界跳变，先沿用 GRU 侧成熟参数。
state.dwell_main = max(0, double(cfg.dwell_main));
state.dwell_turn = max(0, double(cfg.dwell_turn));
state.dwell_main_steps = max(1, round(state.dwell_main / state.Ts));
state.dwell_turn_steps = max(1, round(state.dwell_turn / state.Ts));
state.label_main_current = 1;
state.label_turn_current = 0;
state.label_main_candidate = 1;
state.label_turn_candidate = 0;
state.label_main_stable_count = 0;
state.label_turn_stable_count = 0;
state.conf_main_current = 1.0;
state.conf_turn_current = 1.0;
state.force_label_main = state_force_label_main;
state.force_label_turn = state_force_label_turn;
state.turn_command_guard_enable = logical(cfg.turn_command_guard_enable);
state.turn_command_guard_omega_abs = max(0, double(cfg.turn_command_guard_omega_abs));
state.turn_command_guard_mean_abs = max(0, double(cfg.turn_command_guard_mean_abs));
state.turn_command_guard_min_active_steps = max(0, ...
    round(max(0, double(cfg.turn_command_guard_min_active_sec)) / state.Ts));
state.main_slope_release_enable = logical(cfg.main_slope_release_enable);
state.main_slope_release_theta_abs = deg2rad(max(0, double(cfg.main_slope_release_theta_abs_deg)));
state.main_slope_release_omega_abs = max(0, double(cfg.main_slope_release_omega_abs));
state.main_slope_release_omega_mean_abs = max(0, double(cfg.main_slope_release_omega_mean_abs));
state.main_slope_release_min_active_steps = max(0, ...
    round(max(0, double(cfg.main_slope_release_min_active_sec)) / state.Ts));
state.main_slope_release_force_turn_straight = logical(cfg.main_slope_release_force_turn_straight);
state.hybrid_mode = lower(strtrim(char(cfg.hybrid_mode)));
state.hybrid_gru_enabled = ~strcmp(state.hybrid_mode, 'none');
state.hybrid_main_conf_threshold = max(0, min(1, double(cfg.hybrid_main_conf_threshold)));
state.hybrid_turn_conf_threshold = max(0, min(1, double(cfg.hybrid_turn_conf_threshold)));
state.hybrid_gru_available = false;
state.hybrid_gru_model_file = '';
state.hybrid_gru_state = [];
state.hybrid_last_gru_out = [];
state.hybrid_last_error = '';
if state.hybrid_gru_enabled
    [gru_model, state.hybrid_gru_model_file] = local_load_hybrid_gru_model(root, cfg);
    state.hybrid_gru_state = GRU_state_classifier('init', params, gru_model);
    state.hybrid_gru_available = true;
end

% theta raw/conditioned output remains a model estimate. MPC scheduling can
% use theta_hat_for_mpc, which applies the deployment deadzone outside the
% learned regressor.
state.tau_theta = max(0, double(cfg.tau_theta));
state.alpha_theta = state.Ts / (state.tau_theta + state.Ts);
state.theta_hat_current = 0.0;
state.theta_mpc_deadzone = double(cfg.theta_mpc_deadzone);
state.theta_mpc_deadzone_soft = max(double(cfg.theta_mpc_deadzone_soft), state.theta_mpc_deadzone);
state.theta_mpc_rate_limit = double(cfg.theta_mpc_rate_limit);
state.theta_output_gain = double(cfg.theta_output_gain);
state.theta_abs_limit = double(cfg.theta_abs_limit);
state.theta_rate_limit = double(cfg.theta_rate_limit);
state.theta_hat_output_prev = 0.0;
state.theta_hat_for_mpc_prev = 0.0;
state.e5_conf_sched_enable = logical(cfg.e5_conf_sched_enable);
state.e5_confidence_mode = lower(strtrim(char(cfg.e5_confidence_mode)));
state.e5_conf_threshold = max(0.0, min(1.0, double(cfg.e5_conf_threshold)));
state.e5_delta_theta_max = deg2rad(max(0.0, double(cfg.e5_delta_theta_max_deg_per_step)));
state.e5_theta_sched_prev = 0.0;
state.e5_theta_sched_initialized = false;

state.eps = 1e-8;

% ONNX predictor 只在初始化时加载一次，避免每个仿真步重复导入网络。
if cfg.disable_predictor
    state.predictor = [];
elseif isempty(state.onnx_file)
    state.predictor = ModernTCN_load_predictor(state.seed);
else
    state.predictor = ModernTCN_load_predictor(state.seed, state.onnx_file);
end
state = local_align_augment_config_with_predictor(state);
state.is_ready = true;
end

function [state, out] = local_update(state, y_raw_t, u_cmd)
state.step = state.step + 1;

if isempty(y_raw_t) || numel(y_raw_t) < 18
    out = local_default_output(state, 'y_raw 维度不足');
    return;
end

state = local_update_hybrid_gru(state, y_raw_t);

% 与训练预处理保持一致：跳过起始 transient，跳过期间不更新特征滤波状态。
if state.step <= state.skip_initial_steps
    out = local_default_output(state, 'skip_initial_sec 内输出默认值');
    return;
end

[features, state] = local_extract_features(double(y_raw_t(:)), u_cmd, state);
if any(~isfinite(features))
    out = local_default_output(state, '特征含 NaN/Inf');
    return;
end

state.buffer(1:end-1, :) = state.buffer(2:end, :);
state.buffer(end, :) = single(features);
state.buffer_count = min(state.buffer_count + 1, state.seq_len);

if state.buffer_count < state.seq_len
    out = local_default_output(state, '滑动窗口未填满');
    out.features = double(features(:));
    out.features_norm = double(((features(:).' - double(state.scaler.mean)) ./ ...
        (double(state.scaler.std) + state.eps)).');
    return;
end

X_norm = (double(state.buffer) - double(state.scaler.mean)) ./ ...
    (double(state.scaler.std) + state.eps);
predict_input = local_prepare_predict_input(single(X_norm), state);

try
    pred = ModernTCN_predict_window(state.predictor, predict_input);
catch ME
    warning('ModernTCN:InferenceFailed', 'ModernTCN 推理失败: %s', ME.message);
    out = local_default_output(state, 'ModernTCN 推理失败');
    return;
end

label_main_raw = double(pred.main_state);
label_turn_raw = double(pred.turn_state);
conf_main_raw = double(pred.main_confidence);
conf_turn_raw = double(pred.turn_confidence);
theta_hat_raw = double(pred.theta_hat_rad);

[state.label_main_current, state.label_main_candidate, state.label_main_stable_count] = ...
    local_apply_dwell(label_main_raw, state.label_main_current, ...
    state.label_main_candidate, state.label_main_stable_count, state.dwell_main_steps);

[state.label_turn_current, state.label_turn_candidate, state.label_turn_stable_count] = ...
    local_apply_dwell(label_turn_raw, state.label_turn_current, ...
    state.label_turn_candidate, state.label_turn_stable_count, state.dwell_turn_steps);

state.conf_main_current = conf_main_raw;
state.conf_turn_current = conf_turn_raw;
state.theta_hat_current = state.alpha_theta * theta_hat_raw + ...
    (1 - state.alpha_theta) * state.theta_hat_current;

label_main_model_out = state.label_main_current;
[label_main_guarded, main_slope_release_applied, main_slope_release_theta_abs, ...
    main_slope_release_omega_lag1, main_slope_release_omega_mean] = ...
    local_apply_main_slope_release_guard(label_main_model_out, features, state);
label_turn_model_out = state.label_turn_current;
[label_turn_guarded, turn_guard_applied, turn_guard_omega_lag1, turn_guard_omega_mean] = ...
    local_apply_turn_command_guard(label_turn_model_out, features, state);
if main_slope_release_applied && state.main_slope_release_force_turn_straight
    label_turn_guarded = 0;
end
modern_conf_main_out = state.conf_main_current;
[label_main_hybrid, label_turn_hybrid, conf_main_hybrid, hybrid_debug] = ...
    local_apply_hybrid_labels(label_main_guarded, label_turn_guarded, ...
    modern_conf_main_out, state.conf_turn_current, state);
label_main_out = local_apply_forced_label(label_main_hybrid, state.force_label_main);
label_turn_out = local_apply_forced_label(label_turn_hybrid, state.force_label_turn);

theta_hat_out = local_apply_theta_conditioning(state.theta_hat_current, state);
[theta_sched_for_mpc_input, state, e5_debug] = local_apply_e5_confidence_scheduling( ...
    theta_hat_out, theta_hat_raw, modern_conf_main_out, state.conf_turn_current, state);
theta_hat_for_mpc = local_apply_theta_mpc_deadzone(theta_sched_for_mpc_input, state);
theta_hat_for_mpc = local_apply_theta_mpc_rate_limit(theta_hat_for_mpc, state);
state.theta_hat_output_prev = theta_hat_out;
state.theta_hat_for_mpc_prev = theta_hat_for_mpc;

out = struct();
out.label_main = label_main_out;
out.label_turn = label_turn_out;
out.theta_hat = theta_hat_out;
out.theta_hat_for_mpc = theta_hat_for_mpc;
out.conf_main = conf_main_hybrid;
out.conf_turn = state.conf_turn_current;
out.label_main_raw = label_main_raw;
out.label_turn_raw = label_turn_raw;
out.theta_hat_raw = theta_hat_raw;
out.theta_sched = theta_sched_for_mpc_input;
out.e5_conf_sched = e5_debug;
out.main_prob = double(pred.main_prob(:));
out.turn_prob = double(pred.turn_prob(:));
out.features = double(features(:));
out.features_norm = double(X_norm(end, :).');
out.debug = struct();
out.debug.step = state.step;
out.debug.buffer_count = state.buffer_count;
out.debug.ready = true;
out.debug.did_predict = true;
out.debug.skip_initial_steps = state.skip_initial_steps;
out.debug.feature_contract = state.feature_state.feature_contract;
out.debug.u_cmd_already_lagged = state.u_cmd_already_lagged;
out.debug.theta_output_gain = state.theta_output_gain;
out.debug.theta_abs_limit = state.theta_abs_limit;
out.debug.theta_rate_limit = state.theta_rate_limit;
out.debug.theta_mpc_deadzone = state.theta_mpc_deadzone;
out.debug.theta_mpc_deadzone_soft = state.theta_mpc_deadzone_soft;
out.debug.theta_mpc_rate_limit = state.theta_mpc_rate_limit;
out.debug.e5_conf_sched_enable = state.e5_conf_sched_enable;
out.debug.e5_confidence_mode = state.e5_confidence_mode;
out.debug.e5_conf_threshold = state.e5_conf_threshold;
out.debug.e5_delta_theta_max = state.e5_delta_theta_max;
out.debug.theta_hat_raw = e5_debug.theta_hat_raw;
out.debug.theta_sched = e5_debug.theta_sched;
out.debug.main_conf = e5_debug.main_conf;
out.debug.turn_conf = e5_debug.turn_conf;
out.debug.c_eff = e5_debug.c_eff;
out.debug.low_conf_flag = e5_debug.low_conf_flag;
out.debug.rate_limit_hit_flag = e5_debug.rate_limit_hit_flag;
out.debug.tau_theta = state.tau_theta;
out.debug.dwell_main = state.dwell_main;
out.debug.dwell_turn = state.dwell_turn;
out.debug.force_label_main = state.force_label_main;
out.debug.force_label_turn = state.force_label_turn;
out.debug.hybrid = hybrid_debug;
out.debug.hybrid_mode = state.hybrid_mode;
out.debug.hybrid_applied = hybrid_debug.applied;
out.debug.hybrid_reason = hybrid_debug.reason;
out.debug.hybrid_gru_available = state.hybrid_gru_available;
out.debug.hybrid_gru_model_file = state.hybrid_gru_model_file;
out.debug.hybrid_gru_label_main = hybrid_debug.gru_label_main;
out.debug.hybrid_gru_label_turn = hybrid_debug.gru_label_turn;
out.debug.hybrid_gru_conf_main = hybrid_debug.gru_conf_main;
out.debug.hybrid_modern_conf_main = modern_conf_main_out;
out.debug.hybrid_modern_conf_turn = state.conf_turn_current;
out.debug.main_slope_release_enable = state.main_slope_release_enable;
out.debug.main_slope_release_theta_abs = state.main_slope_release_theta_abs;
out.debug.main_slope_release_omega_abs = state.main_slope_release_omega_abs;
out.debug.main_slope_release_omega_mean_abs = state.main_slope_release_omega_mean_abs;
out.debug.main_slope_release_min_active_steps = state.main_slope_release_min_active_steps;
out.debug.main_slope_release_force_turn_straight = state.main_slope_release_force_turn_straight;
out.debug.main_slope_release_applied = main_slope_release_applied;
out.debug.main_slope_release_theta_abs_now = main_slope_release_theta_abs;
out.debug.main_slope_release_omega_lag1 = main_slope_release_omega_lag1;
out.debug.main_slope_release_omega_mean = main_slope_release_omega_mean;
out.debug.turn_command_guard_enable = state.turn_command_guard_enable;
out.debug.turn_command_guard_omega_abs = state.turn_command_guard_omega_abs;
out.debug.turn_command_guard_mean_abs = state.turn_command_guard_mean_abs;
out.debug.turn_command_guard_min_active_steps = state.turn_command_guard_min_active_steps;
out.debug.turn_command_guard_applied = turn_guard_applied;
out.debug.turn_command_guard_omega_lag1 = turn_guard_omega_lag1;
out.debug.turn_command_guard_omega_mean = turn_guard_omega_mean;
out.debug.note = 'ModernTCN online output';
end

function [features, state] = local_extract_features(y_raw, u_cmd, state)
if strcmpi(state.feature_contract_name, 'passive17_plus_all5_cmdresp_lite_v1')
    if isempty(u_cmd)
        u_cmd = [0; 0];
    end
    [features, state.feature_state] = extract_command_response_features( ...
        'step', y_raw, double(u_cmd(:)).', state.feature_state);
elseif strcmpi(state.feature_contract_name, 'passive17_plus_all5_cmdresp_lag1_only_v1')
    if isempty(u_cmd)
        u_cmd = [0; 0];
    end
    [features, state.feature_state] = extract_command_response_lag1_features( ...
        'step', y_raw, double(u_cmd(:)).', state.feature_state);
else
    [features, state.feature_state] = extract_passive_features('step', y_raw, state.feature_state);
end
end

function state = local_update_hybrid_gru(state, y_raw_t)
if ~isfield(state, 'hybrid_gru_enabled') || ~state.hybrid_gru_enabled || ...
        ~state.hybrid_gru_available
    return;
end
if isempty(y_raw_t) || numel(y_raw_t) < 31
    return;
end
try
    [state.hybrid_gru_state, gru_out] = GRU_state_classifier( ...
        'update', state.hybrid_gru_state, double(y_raw_t(1:31)));
    if ~isempty(gru_out)
        state.hybrid_last_gru_out = gru_out;
    end
catch ME
    state.hybrid_gru_available = false;
    state.hybrid_last_error = ME.message;
    warning('ModernTCN:HybridGRUFailed', ...
        'Hybrid GRU update failed and was disabled: %s', ME.message);
end
end

function [label_main, label_turn, conf_main, dbg] = local_apply_hybrid_labels( ...
        modern_label_main, modern_label_turn, modern_conf_main, modern_conf_turn, state)
label_main = modern_label_main;
label_turn = modern_label_turn;
conf_main = modern_conf_main;
dbg = local_hybrid_debug(state, modern_label_main, modern_label_turn, ...
    modern_conf_main, modern_conf_turn);
if ~state.hybrid_gru_enabled || ~state.hybrid_gru_available || ...
        isempty(state.hybrid_last_gru_out)
    return;
end

gru_out = state.hybrid_last_gru_out;
if ~isfield(gru_out, 'label_main') || ~isfield(gru_out, 'label_turn')
    return;
end
gru_label_main = double(gru_out.label_main);
gru_label_turn = double(gru_out.label_turn);
gru_conf_main = local_gru_conf_main(gru_out);
dbg.gru_label_main = gru_label_main;
dbg.gru_label_turn = gru_label_turn;
dbg.gru_conf_main = gru_conf_main;

mode = state.hybrid_mode;
apply_gru = false;
reason = 'modern';
switch mode
    case {'mt_theta_gru_labels', 'modern_theta_gru_labels', 'gru_labels'}
        apply_gru = true;
        reason = 'gru_labels';
    case {'lowconf_gru_labels', 'gru_fallback_labels'}
        apply_gru = modern_conf_main < state.hybrid_main_conf_threshold || ...
            modern_conf_turn < state.hybrid_turn_conf_threshold;
        if apply_gru
            reason = 'low_confidence';
        end
    case {'disagreement_gru_labels'}
        apply_gru = gru_label_main ~= modern_label_main || ...
            gru_label_turn ~= modern_label_turn;
        if apply_gru
            reason = 'disagreement';
        end
    case {'lowconf_or_disagreement_gru_labels'}
        apply_gru = modern_conf_main < state.hybrid_main_conf_threshold || ...
            modern_conf_turn < state.hybrid_turn_conf_threshold || ...
            gru_label_main ~= modern_label_main || gru_label_turn ~= modern_label_turn;
        if apply_gru
            reason = 'low_confidence_or_disagreement';
        end
end

if apply_gru
    label_main = gru_label_main;
    label_turn = gru_label_turn;
    conf_main = gru_conf_main;
    dbg.applied = true;
    dbg.reason = reason;
else
    dbg.reason = reason;
end
end

function dbg = local_hybrid_debug(state, modern_label_main, modern_label_turn, ...
        modern_conf_main, modern_conf_turn)
dbg = struct();
dbg.mode = state.hybrid_mode;
dbg.enabled = state.hybrid_gru_enabled;
dbg.available = state.hybrid_gru_available;
dbg.applied = false;
dbg.reason = 'modern';
dbg.modern_label_main = modern_label_main;
dbg.modern_label_turn = modern_label_turn;
dbg.modern_conf_main = modern_conf_main;
dbg.modern_conf_turn = modern_conf_turn;
dbg.gru_label_main = NaN;
dbg.gru_label_turn = NaN;
dbg.gru_conf_main = NaN;
dbg.gru_model_file = state.hybrid_gru_model_file;
dbg.last_error = state.hybrid_last_error;
end

function c = local_gru_conf_main(gru_out)
c = 1.0;
if isfield(gru_out, 'conf_main') && ~isempty(gru_out.conf_main)
    c = max(double(gru_out.conf_main(:)));
end
if ~isfinite(c)
    c = 1.0;
end
end

function [current, candidate, count] = local_apply_dwell(raw_label, current, candidate, count, required_count)
if raw_label == candidate
    count = count + 1;
    if count >= required_count
        current = raw_label;
    end
else
    candidate = raw_label;
    count = 1;
end
end

function theta_hat = local_apply_theta_conditioning(theta_hat, state)
theta_hat = state.theta_output_gain * theta_hat;

if isfinite(state.theta_abs_limit) && state.theta_abs_limit > 0
    theta_hat = min(max(theta_hat, -state.theta_abs_limit), state.theta_abs_limit);
end

if isfinite(state.theta_rate_limit) && state.theta_rate_limit > 0
    max_step = state.theta_rate_limit * state.Ts;
    theta_delta = theta_hat - state.theta_hat_output_prev;
    theta_delta = min(max(theta_delta, -max_step), max_step);
    theta_hat = state.theta_hat_output_prev + theta_delta;
end
end

function [theta_sched, state, dbg] = local_apply_e5_confidence_scheduling( ...
        theta_hat_conditioned, theta_hat_raw, main_conf, turn_conf, state)
dbg = struct();
dbg.enabled = state.e5_conf_sched_enable;
dbg.theta_hat_raw = theta_hat_raw;
dbg.theta_hat_conditioned = theta_hat_conditioned;
dbg.theta_sched = theta_hat_conditioned;
dbg.main_conf = main_conf;
dbg.turn_conf = turn_conf;
dbg.confidence_mode = state.e5_confidence_mode;
dbg.conf_threshold = state.e5_conf_threshold;
dbg.c_eff = 1.0;
dbg.low_conf_flag = false;
dbg.rate_limit_hit_flag = false;
dbg.delta_theta_max = state.e5_delta_theta_max;

theta_sched = theta_hat_conditioned;
if ~state.e5_conf_sched_enable
    return;
end

if ~state.e5_theta_sched_initialized
    state.e5_theta_sched_prev = theta_hat_conditioned;
    state.e5_theta_sched_initialized = true;
    theta_sched = theta_hat_conditioned;
    dbg.theta_sched = theta_sched;
    return;
end

switch state.e5_confidence_mode
    case {'main_conf', 'main'}
        conf = main_conf;
    case {'main_turn_conf', 'mainturn', 'main_conf*turn_conf'}
        conf = main_conf * turn_conf;
    otherwise
        conf = main_conf;
end
if ~isfinite(conf)
    conf = 0.0;
end
low_conf = conf < state.e5_conf_threshold;
if low_conf
    c_eff = 0.0;
else
    c_eff = min(max(conf, 0.0), 1.0);
end

theta_safe = state.e5_theta_sched_prev;
theta_blend = c_eff * theta_hat_conditioned + (1.0 - c_eff) * theta_safe;
theta_delta = theta_blend - theta_safe;
if isfinite(state.e5_delta_theta_max) && state.e5_delta_theta_max > 0
    theta_delta_clip = min(max(theta_delta, -state.e5_delta_theta_max), state.e5_delta_theta_max);
else
    theta_delta_clip = theta_delta;
end
theta_sched = theta_safe + theta_delta_clip;
rate_hit = abs(theta_delta - theta_delta_clip) > 1e-12;
state.e5_theta_sched_prev = theta_sched;

dbg.theta_sched = theta_sched;
dbg.c_eff = c_eff;
dbg.low_conf_flag = low_conf;
dbg.rate_limit_hit_flag = rate_hit;
end

function theta_hat = local_apply_theta_mpc_deadzone(theta_hat, state)
theta_abs = abs(theta_hat);
if theta_abs <= state.theta_mpc_deadzone
    theta_hat = 0.0;
elseif state.theta_mpc_deadzone_soft > state.theta_mpc_deadzone && ...
        theta_abs < state.theta_mpc_deadzone_soft
    span = state.theta_mpc_deadzone_soft - state.theta_mpc_deadzone;
    scale = (theta_abs - state.theta_mpc_deadzone) / max(span, state.eps);
    theta_hat = sign(theta_hat) * scale * (theta_abs - state.theta_mpc_deadzone);
end
end

function theta_hat = local_apply_theta_mpc_rate_limit(theta_hat, state)
if isfinite(state.theta_mpc_rate_limit) && state.theta_mpc_rate_limit > 0
    max_step = state.theta_mpc_rate_limit * state.Ts;
    theta_delta = theta_hat - state.theta_hat_for_mpc_prev;
    theta_delta = min(max(theta_delta, -max_step), max_step);
    theta_hat = state.theta_hat_for_mpc_prev + theta_delta;
end
end

function [label_turn, applied, omega_lag1, omega_mean] = local_apply_turn_command_guard(label_turn, features, state)
applied = false;
omega_lag1 = NaN;
omega_mean = NaN;
if ~state.turn_command_guard_enable || label_turn == 0 || numel(features) < 30
    return;
end
if state.label_turn_stable_count < state.turn_command_guard_min_active_steps
    return;
end

% Command-response features are appended as:
% F_lag1, omega_lag1, dF_lag1, domega_lag1, F_mean, F_std, omega_mean, omega_std.
omega_lag1 = double(features(end - 6));
omega_mean = double(features(end - 1));
if abs(omega_lag1) <= state.turn_command_guard_omega_abs && ...
        abs(omega_mean) <= state.turn_command_guard_mean_abs
    label_turn = 0;
    applied = true;
end
end

function [label_main, applied, theta_abs_now, omega_lag1, omega_mean] = ...
        local_apply_main_slope_release_guard(label_main, features, state)
applied = false;
theta_abs_now = NaN;
omega_lag1 = NaN;
omega_mean = NaN;
if ~state.main_slope_release_enable || label_main ~= 3 || numel(features) < 30
    return;
end
if state.label_main_stable_count < state.main_slope_release_min_active_steps
    return;
end

theta_abs_now = abs(state.theta_hat_current);
omega_lag1 = double(features(end - 6));
omega_mean = double(features(end - 1));
if theta_abs_now <= state.main_slope_release_theta_abs && ...
        abs(omega_lag1) <= state.main_slope_release_omega_abs && ...
        abs(omega_mean) <= state.main_slope_release_omega_mean_abs
    label_main = 1;
    applied = true;
end
end

function out = local_default_output(state, note)
out = struct();
modern_conf_main_out = state.conf_main_current;
[label_main_hybrid, label_turn_hybrid, conf_main_hybrid, hybrid_debug] = ...
    local_apply_hybrid_labels(state.label_main_current, state.label_turn_current, ...
    modern_conf_main_out, state.conf_turn_current, state);
out.label_main = local_apply_forced_label(label_main_hybrid, state.force_label_main);
out.label_turn = local_apply_forced_label(label_turn_hybrid, state.force_label_turn);
out.theta_hat = state.theta_hat_current;
theta_hat_for_mpc = local_apply_theta_mpc_deadzone(state.theta_hat_current, state);
out.theta_hat_for_mpc = local_apply_theta_mpc_rate_limit(theta_hat_for_mpc, state);
out.conf_main = conf_main_hybrid;
out.conf_turn = state.conf_turn_current;
out.label_main_raw = state.label_main_current;
out.label_turn_raw = state.label_turn_current;
out.theta_hat_raw = state.theta_hat_current;
out.theta_sched = state.theta_hat_current;
out.e5_conf_sched = local_e5_default_debug(state);
out.main_prob = [1; 0; 0];
out.turn_prob = [0; 1; 0];
out.features = nan(state.feat_dim, 1);
out.features_norm = nan(state.feat_dim, 1);
out.debug = struct();
out.debug.step = state.step;
out.debug.buffer_count = state.buffer_count;
out.debug.ready = state.buffer_count >= state.seq_len;
out.debug.did_predict = false;
out.debug.skip_initial_steps = state.skip_initial_steps;
out.debug.theta_output_gain = state.theta_output_gain;
out.debug.theta_abs_limit = state.theta_abs_limit;
out.debug.theta_rate_limit = state.theta_rate_limit;
out.debug.theta_mpc_deadzone = state.theta_mpc_deadzone;
out.debug.theta_mpc_deadzone_soft = state.theta_mpc_deadzone_soft;
out.debug.theta_mpc_rate_limit = state.theta_mpc_rate_limit;
out.debug.e5_conf_sched_enable = state.e5_conf_sched_enable;
out.debug.e5_confidence_mode = state.e5_confidence_mode;
out.debug.e5_conf_threshold = state.e5_conf_threshold;
out.debug.e5_delta_theta_max = state.e5_delta_theta_max;
out.debug.theta_hat_raw = out.theta_hat_raw;
out.debug.theta_sched = out.theta_sched;
out.debug.main_conf = out.conf_main;
out.debug.turn_conf = out.conf_turn;
out.debug.c_eff = out.e5_conf_sched.c_eff;
out.debug.low_conf_flag = out.e5_conf_sched.low_conf_flag;
out.debug.rate_limit_hit_flag = out.e5_conf_sched.rate_limit_hit_flag;
out.debug.tau_theta = state.tau_theta;
out.debug.dwell_main = state.dwell_main;
out.debug.dwell_turn = state.dwell_turn;
out.debug.force_label_main = state.force_label_main;
out.debug.force_label_turn = state.force_label_turn;
out.debug.hybrid = hybrid_debug;
out.debug.hybrid_mode = state.hybrid_mode;
out.debug.hybrid_applied = hybrid_debug.applied;
out.debug.hybrid_reason = hybrid_debug.reason;
out.debug.hybrid_gru_available = state.hybrid_gru_available;
out.debug.hybrid_gru_model_file = state.hybrid_gru_model_file;
out.debug.hybrid_gru_label_main = hybrid_debug.gru_label_main;
out.debug.hybrid_gru_label_turn = hybrid_debug.gru_label_turn;
out.debug.hybrid_gru_conf_main = hybrid_debug.gru_conf_main;
out.debug.hybrid_modern_conf_main = modern_conf_main_out;
out.debug.hybrid_modern_conf_turn = state.conf_turn_current;
out.debug.main_slope_release_enable = state.main_slope_release_enable;
out.debug.main_slope_release_theta_abs = state.main_slope_release_theta_abs;
out.debug.main_slope_release_omega_abs = state.main_slope_release_omega_abs;
out.debug.main_slope_release_omega_mean_abs = state.main_slope_release_omega_mean_abs;
out.debug.main_slope_release_min_active_steps = state.main_slope_release_min_active_steps;
out.debug.main_slope_release_force_turn_straight = state.main_slope_release_force_turn_straight;
out.debug.main_slope_release_applied = false;
out.debug.main_slope_release_theta_abs_now = NaN;
out.debug.main_slope_release_omega_lag1 = NaN;
out.debug.main_slope_release_omega_mean = NaN;
out.debug.turn_command_guard_enable = state.turn_command_guard_enable;
out.debug.turn_command_guard_omega_abs = state.turn_command_guard_omega_abs;
out.debug.turn_command_guard_mean_abs = state.turn_command_guard_mean_abs;
out.debug.turn_command_guard_min_active_steps = state.turn_command_guard_min_active_steps;
out.debug.turn_command_guard_applied = false;
out.debug.turn_command_guard_omega_lag1 = NaN;
out.debug.turn_command_guard_omega_mean = NaN;
out.debug.note = note;
end

function dbg = local_e5_default_debug(state)
dbg = struct();
dbg.enabled = state.e5_conf_sched_enable;
dbg.theta_hat_raw = state.theta_hat_current;
dbg.theta_hat_conditioned = state.theta_hat_current;
dbg.theta_sched = state.theta_hat_current;
dbg.main_conf = state.conf_main_current;
dbg.turn_conf = state.conf_turn_current;
dbg.confidence_mode = state.e5_confidence_mode;
dbg.conf_threshold = state.e5_conf_threshold;
dbg.c_eff = 1.0;
dbg.low_conf_flag = false;
dbg.rate_limit_hit_flag = false;
dbg.delta_theta_max = state.e5_delta_theta_max;
end

function cfg = local_apply_deployment_override(cfg)
override_names = {'deploy_override', 'deployment_override', ...
    'classifier_override', 'deployment_params'};
for i = 1:numel(override_names)
    name = override_names{i};
    if isfield(cfg, name) && isstruct(cfg.(name))
        cfg = local_merge_allowed_deploy_fields(cfg, cfg.(name));
    end
end
end

function cfg = local_merge_allowed_deploy_fields(cfg, override)
allowed = {'theta_output_gain', 'theta_abs_limit', 'theta_rate_limit', ...
    'theta_mpc_deadzone', 'theta_mpc_deadzone_soft', ...
    'theta_mpc_rate_limit', 'tau_theta', 'dwell_main', 'dwell_turn', ...
    'force_label_main', 'force_label_turn', 'disable_predictor', ...
    'input_augment', 'delta_lag', 'delta_pad', 'lag_steps', 'lag_pad', ...
    'delta_clip_abs', 'raw_input_dim', 'augmented_input_dim', ...
    'raw_feature_mean', 'raw_feature_std', 'physics_feature_mean', ...
    'physics_feature_std', 'physics_clip_abs', 'physics_params', ...
    'turn_command_guard_enable', 'turn_command_guard_omega_abs', ...
    'turn_command_guard_mean_abs', 'turn_command_guard_min_active_sec', ...
    'main_slope_release_enable', 'main_slope_release_theta_abs_deg', ...
    'main_slope_release_omega_abs', 'main_slope_release_omega_mean_abs', ...
    'main_slope_release_min_active_sec', 'main_slope_release_force_turn_straight', ...
    'hybrid_mode', 'hybrid_main_conf_threshold', 'hybrid_turn_conf_threshold', ...
    'hybrid_gru_model_file', 'e5_conf_sched_enable', 'e5_confidence_mode', ...
    'e5_conf_threshold', 'e5_delta_theta_max_deg_per_step'};
for i = 1:numel(allowed)
    name = allowed{i};
    if isfield(override, name) && ~isempty(override.(name))
        cfg.(name) = override.(name);
    end
end
end

function X = local_prepare_predict_input(X_norm, state)
if ~strcmp(state.input_augment, 'none')
    X = ModernTCN_augment_window(X_norm, state);
else
    X = single(X_norm);
end
end

function state = local_align_augment_config_with_predictor(state)
if ~isstruct(state) || ~isfield(state, 'predictor') || isempty(state.predictor) || ...
        ~isstruct(state.predictor) || ~isfield(state.predictor, 'input_augment')
    return;
end
predictor_augment = lower(strtrim(char(state.predictor.input_augment)));
if strcmp(state.input_augment, 'none') && ~strcmp(predictor_augment, 'none')
    state.input_augment = predictor_augment;
end
state.delta_lag = max(1, round(double(local_field_or_default(state.predictor, 'delta_lag', state.delta_lag))));
state.delta_pad = lower(strtrim(char(local_field_or_default(state.predictor, 'delta_pad', state.delta_pad))));
state.lag_steps = round(double(local_field_or_default(state.predictor, 'lag_steps', state.lag_steps)));
state.lag_pad = lower(strtrim(char(local_field_or_default(state.predictor, 'lag_pad', state.lag_pad))));
state.delta_clip_abs = double(local_field_or_default(state.predictor, 'delta_clip_abs', state.delta_clip_abs));
state.raw_input_dim = max(1, round(double(local_field_or_default(state.predictor, 'raw_input_dim', state.raw_input_dim))));
state.augmented_input_dim = max(state.raw_input_dim, round(double(local_field_or_default(state.predictor, 'augmented_input_dim', state.augmented_input_dim))));
state.raw_feature_mean = local_field_or_default(state.predictor, 'raw_feature_mean', state.raw_feature_mean);
state.raw_feature_std = local_field_or_default(state.predictor, 'raw_feature_std', state.raw_feature_std);
state.physics_feature_mean = local_field_or_default(state.predictor, 'physics_feature_mean', state.physics_feature_mean);
state.physics_feature_std = local_field_or_default(state.predictor, 'physics_feature_std', state.physics_feature_std);
state.physics_clip_abs = double(local_field_or_default(state.predictor, 'physics_clip_abs', state.physics_clip_abs));
state.physics_params = local_field_or_default(state.predictor, 'physics_params', state.physics_params);
end

function v = local_label_override_from_cfg(cfg, field_name, allowed_values)
v = NaN;
if ~isstruct(cfg) || ~isfield(cfg, field_name) || isempty(cfg.(field_name))
    return;
end
raw = double(cfg.(field_name));
if ~isscalar(raw) || ~isfinite(raw)
    return;
end
v = round(raw);
if ~any(v == allowed_values)
    error('ModernTCN:BadLabelOverride', ...
        '%s must be one of %s, got %.6g.', field_name, mat2str(allowed_values), raw);
end
end

function y = local_apply_forced_label(y, forced_value)
if isfinite(forced_value)
    y = forced_value;
end
end

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end

function [model, model_file] = local_load_hybrid_gru_model(root, cfg)
if isfield(cfg, 'hybrid_gru_model_file') && ~isempty(cfg.hybrid_gru_model_file)
    model_file = char(cfg.hybrid_gru_model_file);
else
    gru_cfg = GRU_default_config(root);
    model_file = gru_cfg.model_file;
end
if exist(model_file, 'file') ~= 2
    error('ModernTCN:MissingHybridGRUModel', ...
        'Hybrid GRU model not found: %s', model_file);
end
S = load(model_file);
if isfield(S, 'model')
    model = S.model;
elseif isfield(S, 'gru_model')
    model = S.gru_model;
elseif isfield(S, 'net')
    model = S.net;
else
    error('ModernTCN:BadHybridGRUModel', ...
        'Hybrid GRU model file has no model/gru_model/net field: %s', model_file);
end
if ~isfield(model, 'seq_len') && isfield(model, 'cfg') && isfield(model.cfg, 'seq_len')
    model.seq_len = model.cfg.seq_len;
end
if ~isfield(model, 'class_labels_main')
    model.class_labels_main = {'flat', 'stall', 'slope'};
end
if ~isfield(model, 'class_labels_turn')
    model.class_labels_turn = {'right', 'straight', 'left'};
end
end

function contract = local_feature_contract(feature_contract_name)
name = lower(char(feature_contract_name));
switch name
    case {'passive17_plus_all5_cmdresp_lite_v1','command_response','cmdresp_lite_v1'}
        contract = extract_command_response_features('contract');
    case {'passive17_plus_all5_cmdresp_lag1_only_v1','cmdresp_lag1_only_v1','cmdresp_lag1_only'}
        contract = extract_command_response_lag1_features('contract');
    otherwise
        contract = extract_passive_features('contract');
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
