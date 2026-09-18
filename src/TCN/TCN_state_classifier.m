function [state, out] = TCN_state_classifier(action, varargin)
%TCN_STATE_CLASSIFIER TCN online state estimator for Simulink.
%
% The feature extraction, normalization, 128-step buffer, dwell logic, and
% theta conditioning mirror the ModernTCN online wrapper so closed-loop tests
% compare models rather than deployment glue.

switch lower(action)
    case 'init'
        if nargin < 2
            error('TCN:init', '初始化需要提供 params。');
        end
        cfg = struct();
        if nargin >= 3 && isstruct(varargin{2})
            cfg = varargin{2};
        end
        state = local_init(varargin{1}, cfg);
        out = [];

    case 'update'
        if nargin < 3
            error('TCN:update', '更新需要提供 state 和 y_raw_t。');
        end
        [state, out] = local_update(varargin{1}, varargin{2});

    otherwise
        error('TCN:BadAction', '未知操作: %s，应为 init 或 update。', action);
end
end

function state = local_init(params, cfg)
root = local_project_root();
default_cfg = TCN_default_config(root);

if ~isfield(cfg, 'seed') || isempty(cfg.seed)
    cfg.seed = default_cfg.seed;
end
if ~isfield(cfg, 'dataset_file') || isempty(cfg.dataset_file)
    cfg.dataset_file = default_cfg.dataset_file;
end
if ~isfield(cfg, 'model_file') || isempty(cfg.model_file)
    cfg.model_file = default_cfg.model_file;
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
if ~isfield(cfg, 'disable_predictor') || isempty(cfg.disable_predictor)
    cfg.disable_predictor = false;
end

if exist(cfg.dataset_file, 'file') ~= 2
    error('TCN:MissingDataset', '找不到 TCN 数据集: %s', cfg.dataset_file);
end

S = load(cfg.dataset_file, 'dataset');
dataset = S.dataset;
scaler = dataset.scaler;

state = struct();
state.params = params;
state.Ts = local_field_or_default(params, 'Ts', 0.01);
state.seed = cfg.seed;
state.dataset_file = cfg.dataset_file;
state.model_file = cfg.model_file;
state.scaler = scaler;
state.feat_names = dataset.feat_names;
state.seq_len = local_field_or_default(dataset.meta, 'seq_len', 128);
state.feat_dim = numel(scaler.mean);
feature_contract = extract_passive_features('contract');
if state.feat_dim ~= feature_contract.input_dim
    error('TCN:FeatureContractMismatch', ...
        'Dataset feature dim is %d, but %s requires %d.', ...
        state.feat_dim, feature_contract.feature_contract, feature_contract.input_dim);
end
state.buffer = zeros(state.seq_len, state.feat_dim, 'single');
state.buffer_count = 0;

state.skip_initial_sec = local_field_or_default(dataset.meta, 'skip_initial_sec', 1.0);
state.skip_initial_steps = round(state.skip_initial_sec / state.Ts);
state.step = 0;

state.tau_accel_lp = local_field_or_default(scaler, 'tau_accel_lp', 0.4);
state.tau_diff = local_field_or_default(scaler, 'tau_diff', 0.3);
state.alpha_accel = state.Ts / (state.tau_accel_lp + state.Ts);
state.alpha_diff = state.Ts / (state.tau_diff + state.Ts);

feature_cfg = struct('tau_diff', state.tau_diff, 'tau_accel_lp', state.tau_accel_lp);
state.feature_state = extract_passive_features('init', params, state.Ts, feature_cfg);

state.dwell_main = 0.20;
state.dwell_turn = 0.40;
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

state.tau_theta = 0.15;
state.alpha_theta = state.Ts / (state.tau_theta + state.Ts);
state.theta_hat_current = 0.0;
state.theta_mpc_deadzone = double(cfg.theta_mpc_deadzone);
state.theta_output_gain = double(cfg.theta_output_gain);
state.theta_abs_limit = double(cfg.theta_abs_limit);
state.theta_rate_limit = double(cfg.theta_rate_limit);
state.theta_hat_output_prev = 0.0;

state.eps = 1e-8;

if cfg.disable_predictor
    state.predictor = [];
else
    state.predictor = TCN_load_predictor(state.model_file);
end
state.is_ready = true;
end

function [state, out] = local_update(state, y_raw_t)
state.step = state.step + 1;

if isempty(y_raw_t) || numel(y_raw_t) < 18
    out = local_default_output(state, 'y_raw 维度不足');
    return;
end

if state.step <= state.skip_initial_steps
    out = local_default_output(state, 'skip_initial_sec 内输出默认值');
    return;
end

[features, state] = local_extract_features(double(y_raw_t(:)), state);
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

try
    pred = TCN_predict_window(state.predictor, single(X_norm));
catch ME
    warning('TCN:InferenceFailed', 'TCN 推理失败: %s', ME.message);
    out = local_default_output(state, 'TCN 推理失败');
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

theta_hat_out = local_apply_theta_conditioning(state.theta_hat_current, state);
theta_hat_for_mpc = local_apply_theta_mpc_deadzone(theta_hat_out, state);
state.theta_hat_output_prev = theta_hat_out;

out = struct();
out.label_main = state.label_main_current;
out.label_turn = state.label_turn_current;
out.theta_hat = theta_hat_out;
out.theta_hat_for_mpc = theta_hat_for_mpc;
out.conf_main = state.conf_main_current;
out.conf_turn = state.conf_turn_current;
out.label_main_raw = label_main_raw;
out.label_turn_raw = label_turn_raw;
out.theta_hat_raw = theta_hat_raw;
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
out.debug.theta_output_gain = state.theta_output_gain;
out.debug.theta_abs_limit = state.theta_abs_limit;
out.debug.theta_rate_limit = state.theta_rate_limit;
out.debug.theta_mpc_deadzone = state.theta_mpc_deadzone;
out.debug.note = 'TCN online output';
end

function [features, state] = local_extract_features(y_raw, state)
[features, state.feature_state] = extract_passive_features('step', y_raw, state.feature_state);
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

function theta_hat = local_apply_theta_mpc_deadzone(theta_hat, state)
if abs(theta_hat) <= state.theta_mpc_deadzone
    theta_hat = 0.0;
end
end

function out = local_default_output(state, note)
out = struct();
out.label_main = state.label_main_current;
out.label_turn = state.label_turn_current;
out.theta_hat = state.theta_hat_current;
out.theta_hat_for_mpc = local_apply_theta_mpc_deadzone(state.theta_hat_current, state);
out.conf_main = state.conf_main_current;
out.conf_turn = state.conf_turn_current;
out.label_main_raw = state.label_main_current;
out.label_turn_raw = state.label_turn_current;
out.theta_hat_raw = state.theta_hat_current;
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
out.debug.note = note;
end

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
