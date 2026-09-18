function X_aug = ModernTCN_augment_window(X_window, cfg)
%MODERNTCN_AUGMENT_WINDOW Build ModernTCN augmented input windows from raw 22D windows.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end

X = single(X_window);
if ndims(X) == 3 && size(X,1) == 1
    X = squeeze(X);
end
if ~ismatrix(X)
    error('ModernTCN:BadAugmentInput', 'input augmentation expects a [T,F] or [1,T,F] window.');
end

mode = lower(strtrim(char(local_field_or_default(cfg, 'input_augment', 'none'))));
switch mode
    case 'none'
        X_aug = X;
    case 'delta_lag'
        lag = max(1, round(double(local_field_or_default(cfg, 'delta_lag', 1))));
        pad = strtrim(char(local_field_or_default(cfg, 'delta_pad', 'zero')));
        if ~strcmpi(pad, 'zero')
            error('ModernTCN:BadDeltaPad', 'delta_lag only supports delta_pad=zero.');
        end
        local_validate_lag(lag, size(X, 1));
        delta = zeros(size(X), 'like', X);
        delta((lag + 1):end, :) = X((lag + 1):end, :) - X(1:end-lag, :);
        X_aug = [X, delta];
    case 'lag_stack'
        steps = local_lag_steps(cfg, [1 2 4]);
        blocks = cell(1, 1 + numel(steps));
        blocks{1} = X;
        for i = 1:numel(steps)
            blocks{i + 1} = local_lagged_edge(X, steps(i));
        end
        X_aug = cat(2, blocks{:});
    case 'delta_bank'
        steps = local_lag_steps(cfg, [1 2 4]);
        clip_abs = local_delta_clip_abs(cfg);
        blocks = cell(1, 1 + numel(steps));
        blocks{1} = X;
        for i = 1:numel(steps)
            blocks{i + 1} = local_clip_delta(X - local_lagged_edge(X, steps(i)), clip_abs);
        end
        X_aug = cat(2, blocks{:});
    case 'mixed_lag_delta'
        steps = local_lag_steps(cfg, [1 4]);
        clip_abs = local_delta_clip_abs(cfg);
        lag_blocks = cell(1, numel(steps));
        delta_blocks = cell(1, numel(steps));
        for i = 1:numel(steps)
            lag_blocks{i} = local_lagged_edge(X, steps(i));
            delta_blocks{i} = local_clip_delta(X - lag_blocks{i}, clip_abs);
        end
        X_aug = cat(2, X, lag_blocks{:}, delta_blocks{:});
    case 'physics_residual_8'
        X_aug = cat(2, X, local_physics_residual_8(X, cfg));
    otherwise
        error('ModernTCN:BadInputAugment', 'unknown input_augment: %s', mode);
end
X_aug = single(X_aug);
end

function lagged = local_lagged_edge(X, lag)
local_validate_lag(lag, size(X, 1));
lagged = zeros(size(X), 'like', X);
lagged(1:lag, :) = repmat(X(1, :), lag, 1);
lagged((lag + 1):end, :) = X(1:end-lag, :);
end

function delta = local_clip_delta(delta, clip_abs)
delta = min(max(single(delta), -single(clip_abs)), single(clip_abs));
end

function Z = local_physics_residual_8(X, cfg)
if size(X, 2) ~= 22
    error('ModernTCN:BadPhysicsInputDim', ...
        'physics_residual_8 expects raw normalized 22D input, got %d.', size(X, 2));
end
raw_mean = local_vector_field(cfg, 'raw_feature_mean', 22);
raw_std = local_vector_field(cfg, 'raw_feature_std', 22);
phys_mean = local_vector_field(cfg, 'physics_feature_mean', 8);
phys_std = local_vector_field(cfg, 'physics_feature_std', 8);
phys_std(abs(phys_std) < 1e-8) = 1.0;

X_raw = double(X) .* reshape(raw_std, 1, []) + reshape(raw_mean, 1, []);
params = local_physics_params(cfg);

Ts = params.Ts;
m = params.mass;
W = params.W;
Iz = params.Iz;
r = params.wheel_radius;
wheel_inertia = params.wheel_inertia;
kt = params.motor_torque_constant;
motor_inertia = params.motor_inertia;
n = params.gear_ratio;
eta = params.gear_efficiency;
c_roll = params.rolling_resistance;
rho = params.air_density;
CdA = params.drag_coefficient_area;
g = params.gravity;
yaw_tau = params.yaw_accel_tau;

force_gain = n * eta * kt / max(r, 1e-6);
force_scale = max(m * g, 1e-6);
m_eff = m + 2.0 * (wheel_inertia + motor_inertia * n^2) / max(r^2, 1e-6);

gyro_z = X_raw(:, 1);
I_lf = X_raw(:, 2);
I_rr = X_raw(:, 3);
v_hat = X_raw(:, 8);
dv_hat_dt_lp = X_raw(:, 16);

F_lf = I_lf * force_gain;
F_rr = I_rr * force_gain;
F_long = F_lf + F_rr;
F_diff = F_lf - F_rr;
F_roll = c_roll * m * g;
F_aero = 0.5 * rho * CdA .* v_hat .* v_hat .* sign(v_hat);
F_res = (F_long - m_eff .* dv_hat_dt_lp - F_roll - F_aero) ./ force_scale;

yaw_drive_accel = (0.5 * W .* F_diff) ./ max(Iz, 1e-6);
gyro_dot = zeros(size(gyro_z));
if numel(gyro_z) > 1
    gyro_dot(2:end) = diff(gyro_z) ./ max(Ts, 1e-6);
end
yaw_accel_est = local_ema(gyro_dot, Ts, yaw_tau, true);
yaw_residual = yaw_accel_est - yaw_drive_accel;

raw_phys = [ ...
    F_long ./ force_scale, ...
    F_diff ./ force_scale, ...
    F_res, ...
    local_ema(F_res, Ts, 0.3, false), ...
    local_ema(F_res, Ts, 0.8, false), ...
    yaw_drive_accel, ...
    yaw_residual, ...
    local_ema(yaw_residual, Ts, 0.3, false)];

Z = (raw_phys - reshape(phys_mean, 1, [])) ./ reshape(phys_std, 1, []);
clip_abs = double(local_field_or_default(cfg, 'physics_clip_abs', 8.0));
if isfinite(clip_abs) && clip_abs > 0
    Z = min(max(Z, -clip_abs), clip_abs);
end
Z = single(Z);
end

function y = local_ema(x, Ts, tau, init_zero)
x = double(x(:));
y = zeros(size(x));
if isempty(x)
    return;
end
alpha = Ts / (max(tau, 1e-6) + Ts);
if init_zero
    y(1) = 0.0;
else
    y(1) = x(1);
end
for k = 2:numel(x)
    y(k) = alpha * x(k) + (1 - alpha) * y(k - 1);
end
end

function params = local_physics_params(cfg)
defaults = struct( ...
    'Ts', 0.01, ...
    'mass', 200.0, ...
    'W', 0.8, ...
    'Iz', 16.67, ...
    'wheel_radius', 0.15, ...
    'wheel_inertia', 0.0135, ...
    'motor_torque_constant', 1.21, ...
    'motor_inertia', 17.7e-4, ...
    'gear_ratio', 10.0, ...
    'gear_efficiency', 0.9, ...
    'rolling_resistance', 0.015, ...
    'air_density', 1.225, ...
    'drag_coefficient_area', 0.5, ...
    'gravity', 9.81, ...
    'yaw_accel_tau', 0.10);
params = defaults;
if isstruct(cfg) && isfield(cfg, 'physics_params') && isstruct(cfg.physics_params)
    names = fieldnames(defaults);
    for i = 1:numel(names)
        name = names{i};
        if isfield(cfg.physics_params, name) && ~isempty(cfg.physics_params.(name))
            params.(name) = double(cfg.physics_params.(name));
        end
    end
end
end

function v = local_vector_field(cfg, field_name, expected_len)
if ~isstruct(cfg) || ~isfield(cfg, field_name) || isempty(cfg.(field_name))
    error('ModernTCN:MissingPhysicsMeta', ...
        'physics_residual_8 requires cfg.%s from ONNX sidecar metadata.', field_name);
end
v = double(cfg.(field_name));
v = v(:).';
if numel(v) ~= expected_len || any(~isfinite(v))
    error('ModernTCN:BadPhysicsMeta', ...
        'cfg.%s must be a finite vector of length %d.', field_name, expected_len);
end
end

function steps = local_lag_steps(cfg, default_steps)
raw = local_field_or_default(cfg, 'lag_steps', default_steps);
steps = unique(round(double(raw(:).')), 'stable');
steps = steps(isfinite(steps) & steps > 0);
if isempty(steps)
    error('ModernTCN:BadLagSteps', 'lag_steps must contain at least one positive integer.');
end
pad = strtrim(char(local_field_or_default(cfg, 'lag_pad', 'edge')));
if ~strcmpi(pad, 'edge')
    error('ModernTCN:BadLagPad', 'Node25 lag augmentation only supports lag_pad=edge.');
end
for i = 1:numel(steps)
    local_validate_lag(steps(i), local_field_or_default(cfg, 'seq_len', inf));
end
end

function clip_abs = local_delta_clip_abs(cfg)
clip_abs = double(local_field_or_default(cfg, 'delta_clip_abs', 5.0));
if ~isscalar(clip_abs) || ~isfinite(clip_abs) || clip_abs <= 0
    error('ModernTCN:BadDeltaClip', 'delta_clip_abs must be positive and finite.');
end
end

function local_validate_lag(lag, seq_len)
if lag <= 0 || lag >= seq_len
    error('ModernTCN:BadLag', 'lag must satisfy 1 <= lag < seq_len; got lag=%g, seq_len=%g.', lag, seq_len);
end
end

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
