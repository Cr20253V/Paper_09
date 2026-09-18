function [x, aux] = node53_v6_runtime_features(quality_model, fuzzy, sensor_g, theta_tcn, theta_tcn_rate, conf_main)
%NODE53_V6_RUNTIME_FEATURES Runtime-observable V6 gate features.
deg = 180/pi;
raw = [1 - double(fuzzy.accel_weight), ...
    abs(double(fuzzy.accel_norm) - double(sensor_g)), ...
    abs(double(fuzzy.innovation)), ...
    double(fuzzy.nis), ...
    double(fuzzy.gyro_vibration_feature)];
% The frozen V6 JSON uses the estimator's canonical field names. Keep the
% runtime feature contract aligned with that artifact rather than introducing
% aliases that do not exist in the loaded struct.
names = {'one_minus_accel_weight','accel_norm_deviation','abs_innovation','nis','gyro_vibration_feature'};
parts = zeros(1,5);
for i = 1:5
    parts(i) = local_ecdf(raw(i), quality_model.(names{i}));
end
quality = max(parts);
[~, dominant] = max(parts);
dominant_onehot = zeros(1,5); dominant_onehot(dominant) = 1;
regime = 1 + double(abs(theta_tcn) >= deg2rad(1.3)) + 2 * double(abs(theta_tcn_rate) >= deg2rad(1.0));
regime_onehot = zeros(1,4); regime_onehot(regime) = 1;
innovation = double(fuzzy.theta_imu) - double(theta_tcn);
x = [parts, quality, dominant_onehot, innovation * deg, abs(innovation) * deg, ...
    log1p(max(double(fuzzy.nis),0)), double(fuzzy.accel_weight), raw(2), ...
    log1p(max(double(fuzzy.gyro_vibration_feature),0)), double(theta_tcn) * deg, ...
    double(theta_tcn_rate) * deg, max(0,min(1,double(conf_main))), regime_onehot];
aux = struct('quality_score', quality, 'regime_index', regime, 'innovation', innovation);
end

function y = local_ecdf(v, s)
values = double(s.values(:)); probs = double(s.probabilities(:));
if isempty(values)
    y = 0; return;
end
[values, ~, group] = unique(values);
probs = accumarray(group, probs, [], @max);
y = interp1(values, probs, double(v), 'linear', 'extrap');
y = max(0, min(1, y));
end
