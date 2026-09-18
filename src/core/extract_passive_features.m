function varargout = extract_passive_features(action, varargin)
%EXTRACT_PASSIVE_FEATURES Shared passive17_plus_all5 feature contract.
%
% This helper is the single source of truth for the IMU-free Node 2 feature
% set. It intentionally never reads y_raw columns 9, 10, or 16.

if nargin < 1
    action = 'contract';
end

switch lower(char(action))
    case 'contract'
        varargout{1} = local_contract();

    case 'names'
        varargout{1} = local_feature_names();

    case 'init'
        params = varargin{1};
        if nargin >= 3 && ~isempty(varargin{2})
            Ts = varargin{2};
        else
            Ts = local_field_or_default(params, 'Ts', 0.01);
        end
        if nargin >= 4 && isstruct(varargin{3})
            cfg = varargin{3};
        else
            cfg = struct();
        end
        varargout{1} = local_init_state(params, Ts, cfg);

    case 'step'
        y_raw = varargin{1};
        state = varargin{2};
        [features, state] = local_step(y_raw, state);
        varargout{1} = features;
        varargout{2} = state;

    case 'batch'
        y_raw = varargin{1};
        params = varargin{2};
        if nargin >= 4 && ~isempty(varargin{3})
            Ts = varargin{3};
        else
            Ts = local_field_or_default(params, 'Ts', 0.01);
        end
        if nargin >= 5 && isstruct(varargin{4})
            cfg = varargin{4};
        else
            cfg = struct();
        end
        [features, state] = local_batch(y_raw, params, Ts, cfg);
        varargout{1} = features;
        varargout{2} = state;

    otherwise
        error('extract_passive_features:BadAction', ...
            'Unknown action: %s', char(action));
end
end

function names = local_feature_names()
names = {
    'gyro_z', ...
    'I_lf', ...
    'I_rr', ...
    'omega_wheel_lf', ...
    'omega_wheel_rr', ...
    'delta_lf', ...
    'delta_rr', ...
    'v_hat', ...
    'dv_hat_dt', ...
    'ws_imbalance', ...
    'I_sum', ...
    'I_diff_signed', ...
    'I_diff_abs', ...
    'kappa_proxy', ...
    'accel_per_current', ...
    'dv_hat_dt_lp', ...
    'accel_x_wheel', ...
    'I_drive_signed', ...
    'current_per_accel', ...
    'drive_load_proxy', ...
    'a_hp', ...
    'yaw_consistency_error'};
end

function contract = local_contract()
contract = struct();
contract.feature_contract = 'passive17_plus_all5';
contract.feature_names = local_feature_names();
contract.input_dim = numel(contract.feature_names);
contract.allowed_y_raw_cols = [6, 7, 11, 12, 13, 17, 18];
contract.forbidden_y_raw_cols = [9, 10, 16];
contract.forbidden_fields = {'theta', 'y_theta_ground'};
contract.current_floor = 0.1;
contract.accel_floor = 0.05;
contract.note = ['IMU-free passive proprioceptive features; no y_raw(:,9), ', ...
    'y_raw(:,10), y_raw(:,16), run.theta, or run.y_theta_ground in inputs.'];
end

function state = local_init_state(params, Ts, cfg)
state = struct();
state.params = params;
state.Ts = Ts;
state.r = local_field_or_default(params, 'wheel_radius', 0.1);
state.W = local_field_or_default(params, 'W', 1.0);
state.tau_diff = local_field_or_default(cfg, 'tau_diff', 0.3);
state.tau_accel_lp = local_field_or_default(cfg, 'tau_accel_lp', 0.4);
state.alpha_diff = Ts / (state.tau_diff + Ts);
state.alpha_dv_lp = Ts / (state.tau_accel_lp + Ts);
state.current_floor = local_field_or_default(cfg, 'current_floor', 0.1);
state.accel_floor = local_field_or_default(cfg, 'accel_floor', 0.05);
state.started = false;
state.v_hat_prev = 0.0;
state.dv_hat_dt_prev = 0.0;
state.dv_hat_dt_lp_prev = 0.0;
state.feature_contract = 'passive17_plus_all5';
state.feat_names = local_feature_names();
end

function [features, state] = local_batch(y_raw, params, Ts, cfg)
if isempty(y_raw)
    features = zeros(0, numel(local_feature_names()));
    state = local_init_state(params, Ts, cfg);
    return;
end

local_assert_y_raw(y_raw);
state = local_init_state(params, Ts, cfg);
features = zeros(size(y_raw, 1), numel(local_feature_names()));
for i = 1:size(y_raw, 1)
    [features(i, :), state] = local_step(y_raw(i, :), state);
end
end

function [features, state] = local_step(y_raw, state)
y = double(y_raw(:).');
local_assert_y_raw(y);

gyro_z = y(11);
I_lf = y(12);
I_rr = y(13);
omega_wheel_lf = y(17);
omega_wheel_rr = y(18);
delta_lf = y(6);
delta_rr = y(7);

v_hat = state.r * (omega_wheel_lf + omega_wheel_rr) / 2;
if ~state.started
    accel_x_wheel = 0.0;
    dv_hat_dt = 0.0;
    dv_hat_dt_lp = 0.0;
    state.started = true;
else
    accel_x_wheel = (v_hat - state.v_hat_prev) / state.Ts;
    dv_hat_dt = state.alpha_diff * accel_x_wheel + ...
        (1 - state.alpha_diff) * state.dv_hat_dt_prev;
    dv_hat_dt_lp = state.alpha_dv_lp * dv_hat_dt + ...
        (1 - state.alpha_dv_lp) * state.dv_hat_dt_lp_prev;
end

ws_imbalance = abs(omega_wheel_lf - omega_wheel_rr);
I_sum = abs(I_lf) + abs(I_rr);
I_diff_signed = I_lf - I_rr;
I_diff_abs = abs(I_lf) - abs(I_rr);
kappa_proxy = (tan(delta_lf) - tan(delta_rr)) / state.W;
accel_per_current = dv_hat_dt / max(I_sum, state.current_floor);
I_drive_signed = I_lf + I_rr;
current_per_accel = I_sum / max(abs(dv_hat_dt_lp), state.accel_floor);
drive_load_proxy = I_drive_signed - dv_hat_dt_lp;
a_hp = accel_x_wheel - dv_hat_dt_lp;
yaw_consistency_error = gyro_z - v_hat * kappa_proxy;

features = [gyro_z, I_lf, I_rr, omega_wheel_lf, omega_wheel_rr, ...
    delta_lf, delta_rr, v_hat, dv_hat_dt, ws_imbalance, I_sum, ...
    I_diff_signed, I_diff_abs, kappa_proxy, accel_per_current, ...
    dv_hat_dt_lp, accel_x_wheel, I_drive_signed, current_per_accel, ...
    drive_load_proxy, a_hp, yaw_consistency_error];

state.v_hat_prev = v_hat;
state.dv_hat_dt_prev = dv_hat_dt;
state.dv_hat_dt_lp_prev = dv_hat_dt_lp;
end

function local_assert_y_raw(y_raw)
if size(y_raw, 2) < 18
    error('extract_passive_features:BadYRaw', ...
        'y_raw needs at least 18 columns; got %d.', size(y_raw, 2));
end
end

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
