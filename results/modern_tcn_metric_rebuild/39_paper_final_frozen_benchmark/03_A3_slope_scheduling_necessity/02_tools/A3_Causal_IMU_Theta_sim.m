function theta_hat = A3_Causal_IMU_Theta_sim(y_raw, reset)
%A3_CAUSAL_IMU_THETA_SIM Frozen causal IMU slope source for A3.
% Reads only current y_raw and persistent past estimator state.  It does not
% read theta_ref, theta_ground, future route data, or a learned model.

persistent estimator_state initialized
if isempty(initialized) || logical(reset)
    params = parameters();
    cfg = struct();
    cfg.cf_alpha = 0.98;
    cfg.cf_alpha_dynamic = 0.995;
    cfg.a_long_alpha = 0.90;
    cfg.a_long_correction_gain = 0.60;
    cfg.accel_norm_gate = 2.5;
    cfg.dynamic_accel_gate = 1.2;
    cfg.lateral_accel_gate = 1.5;
    cfg.theta_abs_limit_rad = deg2rad(12.0);
    cfg.r_max_rad_s = deg2rad(8.0);
    [estimator_state, ~] = node36_causal_imu_slope_estimator('init', params, cfg);
    initialized = true;
end
[estimator_state, out] = node36_causal_imu_slope_estimator( ...
    'update', estimator_state, double(y_raw(:)));
theta_hat = double(out.theta_hat);
if ~isfinite(theta_hat)
    theta_hat = 0.0;
end
end
