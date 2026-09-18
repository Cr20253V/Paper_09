function out = ModernTCN_online_step(y_raw, reset, seed, request_predict, u_cmd)
%MODERNTCN_ONLINE_STEP 从单帧 y_raw 在线更新 ModernTCN 状态并按需推理。
%
% 功能说明：
%   该函数是 ModernTCN 接入 Simulink 前的核心在线封装。它的输入不是
%   已经归一化的 [128,22] 窗口，而是仿真模型每个采样周期输出的一帧
%   y_raw。函数内部会：
%     1. 从 y_raw 提取与 passive17_plus_all5 一致的 22 维特征；
%     2. 使用数据集内保存的 TCN scaler 做归一化；
%     3. 维护 128 步滑动窗口；
%     4. 调用当前推荐 ModernTCN ONNX predictor，输出分类、置信度和 theta_hat。
%
% 输入：
%   y_raw           : 当前时刻 AGV 输出，至少 18 维；闭环模型中实际为 [34,1]。
%   reset           : 非 0 时重置在线状态。
%   seed            : 可选，默认 21。
%   request_predict : 可选。
%                     []  = 按 cfg.infer_period_steps 自动决定是否推理；
%                     true  = 本步强制推理；
%                     false = 本步只更新滑窗，不调用 ONNX。
%
% 输出：
%   out : 结构体，字段包括 label_main、label_turn、theta_hat_rad、conf_main、
%         buffer_count、ready、did_predict 等。函数也会把最近一次输出写入
%         base workspace 的 modern_tcn_online_last_out，便于 Simulink 薄封装读取。

if nargin < 1
    y_raw = [];
end
if nargin < 2 || isempty(reset)
    reset = 0;
end
if nargin < 3 || isempty(seed)
    default_cfg = ModernTCN_default_config(local_project_root());
    seed = default_cfg.seed;
end
if nargin < 4
    request_predict = [];
end
if nargin < 5
    u_cmd = [];
end

persistent state

if reset ~= 0 || isempty(state) || ~isfield(state, 'seed') || state.seed ~= seed
    state = local_init_state(seed);
end

out = local_default_output(state);

if isempty(y_raw)
    local_publish_output(out);
    return;
end
if numel(y_raw) < 18
    out.debug.warning = "y_raw 维度不足，至少需要前 18 维。";
    local_publish_output(out);
    return;
end

[feature_raw, state] = local_extract_feature(double(y_raw(:)), u_cmd, state);
feature_norm = (feature_raw - state.scaler_mean) ./ (state.scaler_std + state.eps);

% 滚动维护 [128,22] 归一化窗口。模型训练时使用的就是这个归一化窗口。
state.buffer(1:end-1, :) = state.buffer(2:end, :);
state.buffer(end, :) = single(feature_norm);
state.buffer_count = min(state.buffer_count + 1, state.seq_len);
state.step = state.step + 1;

out = local_default_output(state);
out.feature_raw = feature_raw;
out.feature_norm = feature_norm;

if state.buffer_count < state.seq_len
    out.debug.warning = "窗口未满，保持默认输出。";
    state.last_out = out;
    local_publish_output(out);
    return;
end

do_predict = local_should_predict(state, request_predict);
if do_predict
    predict_input = local_prepare_predict_input(state.buffer, state);
    pred = ModernTCN_predict_window(state.predictor, predict_input);
    out = local_output_from_prediction(state, pred);
    out.feature_raw = feature_raw;
    out.feature_norm = feature_norm;
    out.did_predict = true;
    state.last_out = out;
else
    out = state.last_out;
    out.step = state.step;
    out.buffer_count = state.buffer_count;
    out.ready = true;
    out.did_predict = false;
end

local_publish_output(out);
end

function state = local_init_state(seed)
% 初始化在线状态。注意：这里读取的是 TCN/ModernTCN 数据集 scaler，不是 GRU scaler。
root = local_project_root();
default_cfg = ModernTCN_default_config(root);
cfg = local_read_sim_cfg(seed);
dataset_file = default_cfg.dataset_file;
if isfield(cfg, 'dataset_file') && ~isempty(cfg.dataset_file)
    dataset_file = cfg.dataset_file;
end
if exist(dataset_file, 'file') ~= 2
    error('ModernTCN:MissingDataset', '找不到数据集: %s', dataset_file);
end

S = load(dataset_file, 'dataset');
dataset = S.dataset;

params = parameters();
state = struct();
state.seed = seed;
state.params = params;
state.Ts = dataset.meta.Ts;
state.seq_len = dataset.meta.seq_len;
state.feat_dim = numel(dataset.scaler.mean);
state.feature_contract_name = local_field_or_default(dataset.scaler, 'feature_contract', ...
    local_field_or_default(dataset.meta, 'feature_contract', 'passive17_plus_all5'));
feature_contract = local_feature_contract(state.feature_contract_name);
if state.feat_dim ~= feature_contract.input_dim
    error('ModernTCN:FeatureContractMismatch', ...
        'Dataset feature dim is %d, but %s requires %d.', ...
        state.feat_dim, feature_contract.feature_contract, feature_contract.input_dim);
end
state.buffer = zeros(state.seq_len, state.feat_dim, 'single');
state.buffer_count = 0;
state.step = 0;
state.eps = 1e-8;

state.scaler_mean = double(dataset.scaler.mean(:).');
state.scaler_std = double(dataset.scaler.std(:).');
state.tau_accel_lp = dataset.scaler.tau_accel_lp;
state.tau_diff = dataset.scaler.tau_diff;
state.alpha_diff = state.Ts / (state.tau_diff + state.Ts);
state.alpha_accel = state.Ts / (state.tau_accel_lp + state.Ts);

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

state.infer_period_steps = cfg.infer_period_steps;
state.input_augment = lower(strtrim(char(local_field_or_default(cfg, 'input_augment', 'none'))));
state.delta_lag = max(1, round(double(local_field_or_default(cfg, 'delta_lag', 1))));
state.delta_pad = lower(strtrim(char(local_field_or_default(cfg, 'delta_pad', 'zero'))));
state.lag_steps = round(double(local_field_or_default(cfg, 'lag_steps', [1 2 4])));
state.lag_pad = lower(strtrim(char(local_field_or_default(cfg, 'lag_pad', 'edge'))));
state.delta_clip_abs = double(local_field_or_default(cfg, 'delta_clip_abs', 5.0));
state.raw_input_dim = max(1, round(double(local_field_or_default(cfg, 'raw_input_dim', state.feat_dim))));
state.augmented_input_dim = max(state.raw_input_dim, round(double(local_field_or_default(cfg, 'augmented_input_dim', state.feat_dim * 2))));
state.raw_feature_mean = local_field_or_default(cfg, 'raw_feature_mean', []);
state.raw_feature_std = local_field_or_default(cfg, 'raw_feature_std', []);
state.physics_feature_mean = local_field_or_default(cfg, 'physics_feature_mean', []);
state.physics_feature_std = local_field_or_default(cfg, 'physics_feature_std', []);
state.physics_clip_abs = double(local_field_or_default(cfg, 'physics_clip_abs', 8.0));
state.physics_params = local_field_or_default(cfg, 'physics_params', struct());
state.onnx_file = char(local_field_or_default(cfg, 'onnx_file', ''));
if isfield(cfg, 'disable_predictor') && logical(cfg.disable_predictor)
    state.predictor = [];
elseif ~isempty(state.onnx_file)
    state.predictor = ModernTCN_load_predictor(seed, state.onnx_file);
else
    state.predictor = ModernTCN_load_predictor(seed);
end
state = local_align_augment_config_with_predictor(state);
state.last_out = local_default_output(state);
end

function cfg = local_read_sim_cfg(seed)
% 允许用户在 base workspace 里用 modern_tcn_sim_cfg 覆写仿真配置。
cfg = struct();
cfg.seed = seed;
cfg.infer_period_steps = 5;  % 默认每 0.05s 推理一次，降低闭环仿真开销。
try
    if evalin('base', 'exist(''modern_tcn_sim_cfg'', ''var'') == 1')
        user_cfg = evalin('base', 'modern_tcn_sim_cfg');
        if isstruct(user_cfg)
            if isfield(user_cfg, 'infer_period_steps') && ~isempty(user_cfg.infer_period_steps)
                cfg.infer_period_steps = max(1, round(double(user_cfg.infer_period_steps)));
            end
            if isfield(user_cfg, 'dataset_file') && ~isempty(user_cfg.dataset_file)
                cfg.dataset_file = char(user_cfg.dataset_file);
            end
            if isfield(user_cfg, 'onnx_file') && ~isempty(user_cfg.onnx_file)
                cfg.onnx_file = char(user_cfg.onnx_file);
            end
            if isfield(user_cfg, 'disable_predictor') && ~isempty(user_cfg.disable_predictor)
                cfg.disable_predictor = logical(user_cfg.disable_predictor);
            end
            if isfield(user_cfg, 'u_cmd_already_lagged') && ~isempty(user_cfg.u_cmd_already_lagged)
                cfg.u_cmd_already_lagged = logical(user_cfg.u_cmd_already_lagged);
            end
            if isfield(user_cfg, 'input_augment') && ~isempty(user_cfg.input_augment)
                cfg.input_augment = char(user_cfg.input_augment);
            end
            if isfield(user_cfg, 'delta_lag') && ~isempty(user_cfg.delta_lag)
                cfg.delta_lag = round(double(user_cfg.delta_lag));
            end
            if isfield(user_cfg, 'delta_pad') && ~isempty(user_cfg.delta_pad)
                cfg.delta_pad = char(user_cfg.delta_pad);
            end
            if isfield(user_cfg, 'lag_steps') && ~isempty(user_cfg.lag_steps)
                cfg.lag_steps = round(double(user_cfg.lag_steps));
            end
            if isfield(user_cfg, 'lag_pad') && ~isempty(user_cfg.lag_pad)
                cfg.lag_pad = char(user_cfg.lag_pad);
            end
            if isfield(user_cfg, 'delta_clip_abs') && ~isempty(user_cfg.delta_clip_abs)
                cfg.delta_clip_abs = double(user_cfg.delta_clip_abs);
            end
            if isfield(user_cfg, 'raw_input_dim') && ~isempty(user_cfg.raw_input_dim)
                cfg.raw_input_dim = round(double(user_cfg.raw_input_dim));
            end
            if isfield(user_cfg, 'augmented_input_dim') && ~isempty(user_cfg.augmented_input_dim)
                cfg.augmented_input_dim = round(double(user_cfg.augmented_input_dim));
            end
            if isfield(user_cfg, 'raw_feature_mean') && ~isempty(user_cfg.raw_feature_mean)
                cfg.raw_feature_mean = user_cfg.raw_feature_mean;
            end
            if isfield(user_cfg, 'raw_feature_std') && ~isempty(user_cfg.raw_feature_std)
                cfg.raw_feature_std = user_cfg.raw_feature_std;
            end
            if isfield(user_cfg, 'physics_feature_mean') && ~isempty(user_cfg.physics_feature_mean)
                cfg.physics_feature_mean = user_cfg.physics_feature_mean;
            end
            if isfield(user_cfg, 'physics_feature_std') && ~isempty(user_cfg.physics_feature_std)
                cfg.physics_feature_std = user_cfg.physics_feature_std;
            end
            if isfield(user_cfg, 'physics_clip_abs') && ~isempty(user_cfg.physics_clip_abs)
                cfg.physics_clip_abs = double(user_cfg.physics_clip_abs);
            end
            if isfield(user_cfg, 'physics_params') && ~isempty(user_cfg.physics_params)
                cfg.physics_params = user_cfg.physics_params;
            end
        end
    end
catch
    % base workspace 不可用时保留默认配置。
end
end

function [feature_raw, state] = local_extract_feature(y_raw, u_cmd, state)
if strcmpi(state.feature_contract_name, 'passive17_plus_all5_cmdresp_lite_v1')
    if isempty(u_cmd)
        u_cmd = [0; 0];
    end
    [feature_raw, state.feature_state] = extract_command_response_features( ...
        'step', y_raw, double(u_cmd(:)).', state.feature_state);
elseif strcmpi(state.feature_contract_name, 'passive17_plus_all5_cmdresp_lag1_only_v1')
    if isempty(u_cmd)
        u_cmd = [0; 0];
    end
    [feature_raw, state.feature_state] = extract_command_response_lag1_features( ...
        'step', y_raw, double(u_cmd(:)).', state.feature_state);
else
    [feature_raw, state.feature_state] = extract_passive_features('step', y_raw, state.feature_state);
end
end

function tf = local_should_predict(state, request_predict)
if isempty(request_predict)
    tf = mod(state.step - state.seq_len, state.infer_period_steps) == 0;
else
    tf = logical(request_predict);
end
end

function out = local_output_from_prediction(state, pred)
out = struct();
out.seed = state.seed;
out.step = state.step;
out.buffer_count = state.buffer_count;
out.ready = state.buffer_count >= state.seq_len;
out.did_predict = false;
out.label_main = double(pred.main_state);
out.label_turn = double(pred.turn_state);
out.theta_hat_rad = double(pred.theta_hat_rad);
out.theta_hat_deg = double(pred.theta_hat_deg);
out.conf_main = double(pred.main_confidence);
out.conf_turn = double(pred.turn_confidence);
out.main_prob = double(pred.main_prob(:));
out.turn_prob = double(pred.turn_prob(:));
out.logits_main = single(pred.logits_main(:).');
out.logits_turn = single(pred.logits_turn(:).');
out.X_window_norm = state.buffer;
out.debug = struct();
out.debug.infer_period_steps = state.infer_period_steps;
out.debug.u_cmd_already_lagged = state.u_cmd_already_lagged;
out.debug.note = "ModernTCN raw output; theta_hat 建议先只记录，不直接接入 RhoFilter。";
end

function out = local_default_output(state)
out = struct();
out.seed = state.seed;
out.step = state.step;
out.buffer_count = state.buffer_count;
out.ready = false;
out.did_predict = false;
out.label_main = 1.0;
out.label_turn = 0.0;
out.theta_hat_rad = 0.0;
out.theta_hat_deg = 0.0;
out.conf_main = 1.0;
out.conf_turn = 1.0;
out.main_prob = [1; 0; 0];
out.turn_prob = [0; 1; 0];
out.logits_main = single([0 0 0]);
out.logits_turn = single([0 0 0]);
out.X_window_norm = state.buffer;
out.feature_raw = zeros(1, state.feat_dim);
out.feature_norm = zeros(1, state.feat_dim);
out.debug = struct();
out.debug.infer_period_steps = state.infer_period_steps;
end

function local_publish_output(out)
% Simulink 薄封装通过 base workspace 读取标量，普通 MATLAB 调试也可查看。
try
    assignin('base', 'modern_tcn_online_last_out', out);
catch
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

function X = local_prepare_predict_input(X_norm, state)
if ~strcmp(state.input_augment, 'none')
    X = ModernTCN_augment_window(X_norm, state);
else
    X = single(X_norm);
end
end

function state = local_align_augment_config_with_predictor(state)
if isempty(state.predictor) || ~isstruct(state.predictor) || ~isfield(state.predictor, 'input_augment')
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

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
