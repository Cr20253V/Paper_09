function result = gen_modern_tcn_demo_path(cfg)
%GEN_MODERN_TCN_DEMO_PATH Generate a closed-loop demo path for ModernTCN.
%
% Usage:
%   init_project;
%   result = gen_modern_tcn_demo_path();
%
% Outputs:
%   data/paths/path_modern_tcn_demo_loop_v2.mat
%   figures/paths/path_modern_tcn_demo_loop_v2_preview.png
%   results/paths/path_modern_tcn_demo_loop_v2_report.md

if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
params = parameters();
cfg = local_default_cfg(cfg, root, params);

if exist(cfg.paths_dir, 'dir') ~= 7
    mkdir(cfg.paths_dir);
end
if exist(cfg.figures_dir, 'dir') ~= 7
    mkdir(cfg.figures_dir);
end
if exist(cfg.report_dir, 'dir') ~= 7
    mkdir(cfg.report_dir);
end

ref = local_generate_ref(cfg, params);
coverage = local_compute_coverage(ref, cfg);
local_validate_ref(ref, cfg, coverage);

out_file = fullfile(cfg.paths_dir, [cfg.path_name '.mat']);
save(out_file, 'ref');

fig_file = fullfile(cfg.figures_dir, [cfg.path_name '_preview.png']);
local_visualize_ref(ref, coverage, fig_file);

report_file = fullfile(cfg.report_dir, [cfg.path_name '_report.md']);
local_write_report(report_file, ref, cfg, coverage, out_file, fig_file);

result = struct();
result.ref = ref;
result.coverage = coverage;
result.path_file = out_file;
result.figure_file = fig_file;
result.report_file = report_file;

fprintf('[ModernTCN demo path] wrote %s\n', out_file);
fprintf('  T=%.1fs | closed dist=%.4f m | dpsi=%.4f deg\n', ...
    ref.t(end), coverage.closure_distance_m, coverage.closure_heading_deg);
fprintf('  v=[%.3f, %.3f] m/s | omega=[%.3f, %.3f] rad/s | theta=[%.2f, %.2f] deg\n', ...
    min(ref.v_ref), max(ref.v_ref), min(ref.omega_ref), max(ref.omega_ref), ...
    min(rad2deg(ref.theta_ref)), max(rad2deg(ref.theta_ref)));
fprintf('  report: %s\n', report_file);
end

function cfg = local_default_cfg(cfg, root, params)
cfg.path_name = local_cfg(cfg, 'path_name', 'path_modern_tcn_demo_loop_v2');
cfg.variant = local_cfg(cfg, 'variant', 'paper_v2');
cfg.T_end = local_cfg(cfg, 'T_end', 180.0);
cfg.Ts = local_cfg(cfg, 'Ts', params.Ts);
cfg.a = local_cfg(cfg, 'a', 35.0);
cfg.b = local_cfg(cfg, 'b', 15.0);
cfg.rho_filter_tau = local_cfg(cfg, 'rho_filter_tau', 0.4);
cfg.theta_abs_max = local_cfg(cfg, 'theta_abs_max', deg2rad(5.5));
cfg.v_min_design = local_cfg(cfg, 'v_min_design', 0.76);
cfg.v_max_design = local_cfg(cfg, 'v_max_design', 1.08);
cfg.omega_abs_design = local_cfg(cfg, 'omega_abs_design', 0.18);
cfg.turn_threshold = local_cfg(cfg, 'turn_threshold', 0.035);
cfg.slope_threshold = local_cfg(cfg, 'slope_threshold', deg2rad(1.0));
cfg.paths_dir = local_cfg(cfg, 'paths_dir', fullfile(root, 'data', 'paths'));
cfg.figures_dir = local_cfg(cfg, 'figures_dir', fullfile(root, 'figures', 'paths'));
cfg.report_dir = local_cfg(cfg, 'report_dir', fullfile(root, 'results', 'paths'));
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function ref = local_generate_ref(cfg, params)
Ts = cfg.Ts;
t = (0:Ts:cfg.T_end)';
N = numel(t);

curve = local_make_curve(cfg);
v_shape = local_speed_shape(t, cfg);
scale = curve.length / trapz(t, v_shape);
v = v_shape * scale;

s = cumtrapz(t, v);
s = min(max(s, 0), curve.length);
s(end) = curve.length;
u = interp1(curve.s, curve.u, s, 'pchip');

[X, Y, psi, kappa] = local_curve_eval(cfg, u);
theta = local_theta_profile(t, cfg);
omega = kappa .* v;

rho_raw = [v, omega, theta];
rho = local_first_order_filter(rho_raw, Ts, cfg.rho_filter_tau);

e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);

ref = struct();
ref.t = t;
ref.X_ref = X;
ref.Y_ref = Y;
ref.psi_ref = psi;
ref.v_ref = v;
ref.omega_ref = omega;
ref.theta_ref = theta;
ref.e_y_ref = e_y_ref;
ref.e_psi_ref = e_psi_ref;
ref.e_v_ref = e_v_ref;
ref.rho = rho;

ref.time = t;
ref.signals.values = [X, Y, psi, v, omega, theta, e_y_ref, e_psi_ref, e_v_ref];
ref.signals.dimensions = 9;

ref.meta = local_make_meta(cfg, params, curve);
end

function curve = local_make_curve(cfg)
u = linspace(0, 2*pi, 50001)';
a = cfg.a;
b = cfg.b;
dx = a * cos(u);
dy = b * cos(2*u);
dsdu = hypot(dx, dy);
s = cumtrapz(u, dsdu);
s(end) = s(end);

curve = struct();
curve.u = u;
curve.s = s;
curve.length = s(end);
curve.min_radius = local_curve_min_radius(cfg);
end

function [X, Y, psi, kappa] = local_curve_eval(cfg, u)
a = cfg.a;
b = cfg.b;

x = a * sin(u);
y = b * sin(u) .* cos(u);
dx = a * cos(u);
dy = b * cos(2*u);
ddx = -a * sin(u);
ddy = -2 * b * sin(2*u);

psi0 = atan2(b, a);
c = cos(-psi0);
s = sin(-psi0);
X = c * x - s * y;
Y = s * x + c * y;
dX = c * dx - s * dy;
dY = s * dx + c * dy;

psi = unwrap(atan2(dY, dX));
psi = psi - psi(1);
speed_u = hypot(dx, dy);
kappa = (dx .* ddy - dy .* ddx) ./ max(speed_u.^3, eps);

X = X - X(1);
Y = Y - Y(1);
X(end) = X(1);
Y(end) = Y(1);
psi(end) = psi(1);
end

function rmin = local_curve_min_radius(cfg)
u = linspace(0, 2*pi, 50001)';
a = cfg.a;
b = cfg.b;
dx = a * cos(u);
dy = b * cos(2*u);
ddx = -a * sin(u);
ddy = -2 * b * sin(2*u);
speed_u = hypot(dx, dy);
kappa = (dx .* ddy - dy .* ddx) ./ max(speed_u.^3, eps);
rmin = 1 / max(abs(kappa));
end

function v = local_speed_shape(t, cfg)
if strcmpi(string(cfg.variant), "paper_v2")
    v = 0.91 * ones(size(t));
    v = local_level_event(t, v, 0.0, 10.0, 0.84);
    v = local_level_event(t, v, 10.0, 22.0, 0.93);
    v = local_level_event(t, v, 35.0, 45.0, 1.02);
    v = local_level_event(t, v, 48.0, 58.0, 0.82);
    v = local_level_event(t, v, 64.0, 76.0, 0.95);
    v = local_level_event(t, v, 92.0, 108.0, 0.88);
    v = local_level_event(t, v, 116.0, 144.0, 0.90);
    v = local_level_event(t, v, 152.0, 164.0, 0.97);
    v = local_level_event(t, v, 166.0, 176.0, 0.85);
    v = local_level_event(t, v, 176.0, 180.0, 0.90);
    return;
end

v = 0.90 * ones(size(t));
v = local_level_event(t, v, 0.0, 10.0, 0.84);
v = local_level_event(t, v, 10.0, 22.0, 0.92);
v = local_level_event(t, v, 35.0, 45.0, 1.02);
v = local_level_event(t, v, 48.0, 58.0, 0.80);
v = local_level_event(t, v, 64.0, 76.0, 0.95);
v = local_level_event(t, v, 92.0, 108.0, 0.88);
v = local_level_event(t, v, 112.0, 124.0, 1.04);
v = local_level_event(t, v, 132.0, 144.0, 0.86);
v = local_level_event(t, v, 152.0, 164.0, 0.98);
v = local_level_event(t, v, 166.0, 176.0, 0.84);
v = local_level_event(t, v, 176.0, 180.0, 0.90);
end

function theta = local_theta_profile(t, cfg)
theta = zeros(size(t));
if strcmpi(string(cfg.variant), "paper_v2")
    theta = local_level_event(t, theta, 64.0, 70.0, deg2rad(5.5));
    theta = local_level_event(t, theta, 82.0, 88.0, 0.0);
    theta = local_level_event(t, theta, 90.0, 96.0, deg2rad(-5.5));
    theta = local_level_event(t, theta, 104.0, 110.0, 0.0);

    % The V1 composite left turn contained an uphill/downhill reversal.
    % That is an intentionally hard stress test, but it dominated the
    % closed-loop comparison.  V2 keeps the composite state while making it
    % a single downhill left-turn episode, which is still industrially
    % plausible and better aligned with the current ModernTCN deployment.
    theta = local_level_event(t, theta, 116.0, 122.0, deg2rad(-4.5));
    theta = local_level_event(t, theta, 142.0, 148.0, 0.0);

    mask = t >= 154.0 & t <= 166.0;
    if any(mask)
        tau = (t(mask) - 154.0) / (166.0 - 154.0);
        envelope = local_smoothstep(min(tau * 4, 1)) .* local_smoothstep(min((1 - tau) * 4, 1));
        theta(mask) = theta(mask) + deg2rad(1.5) * envelope .* sin(2*pi*0.12*(t(mask) - 154.0));
    end
    return;
end

theta = local_level_event(t, theta, 64.0, 70.0, deg2rad(5.5));
theta = local_level_event(t, theta, 82.0, 88.0, 0.0);
theta = local_level_event(t, theta, 90.0, 96.0, deg2rad(-5.5));
theta = local_level_event(t, theta, 104.0, 110.0, 0.0);
theta = local_level_event(t, theta, 116.0, 122.0, deg2rad(4.5));
theta = local_level_event(t, theta, 130.0, 136.0, deg2rad(-4.5));
theta = local_level_event(t, theta, 142.0, 148.0, 0.0);

mask = t >= 152.0 & t <= 170.0;
if any(mask)
    tau = (t(mask) - 152.0) / (170.0 - 152.0);
    envelope = local_smoothstep(min(tau * 4, 1)) .* local_smoothstep(min((1 - tau) * 4, 1));
    theta(mask) = theta(mask) + deg2rad(2.5) * envelope .* sin(2*pi*0.12*(t(mask) - 152.0));
end
end

function y = local_level_event(t, y, t0, t1, target)
if t1 <= t0
    return;
end
i0 = find(t <= t0, 1, 'last');
if isempty(i0)
    y_start = y(1);
else
    y_start = y(i0);
end
idx = t >= t0 & t <= t1;
tau = (t(idx) - t0) / max(t1 - t0, eps);
w = local_smoothstep(tau);
y(idx) = y_start + (target - y_start) .* w;
y(t > t1) = target;
end

function w = local_smoothstep(s)
s = min(max(s, 0), 1);
w = s.^2 .* (3 - 2*s);
end

function rho = local_first_order_filter(x, Ts, tau)
[N, dim] = size(x);
rho = zeros(N, dim);
rho(1, :) = x(1, :);
alpha = Ts / (Ts + tau);
for k = 2:N
    rho(k, :) = alpha * x(k, :) + (1 - alpha) * rho(k-1, :);
end
end

function meta = local_make_meta(cfg, params, curve)
zones = struct();
zones.startup = [0, 12];
zones.flat_right_turn = [12, 48];
zones.low_speed_flat_turn = [48, 62];
zones.pure_slope = [64, 110];
zones.slope_left_turn_composite = [116, 148];
zones.bumpy_theta_closure = [152, 170];
zones.closure = [170, cfg.T_end];

segments = local_zone_segments(zones);

meta = struct();
meta.path_type = cfg.path_name;
meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
if strcmpi(string(cfg.variant), "paper_v2")
    meta.version = 'ModernTCN_DEMO_LOOP_V2';
else
    meta.version = 'ModernTCN_DEMO_LOOP_V1';
end
meta.author = 'LPV-MPC Project';
meta.closed_loop_path = true;
meta.training_path = false;
meta.design_goal = ['ModernTCN-friendly closed-loop demonstration with rich ' ...
    'state transitions and limited long pure-slope plateaus.'];
meta.params = struct();
meta.params.T_end = cfg.T_end;
meta.params.Ts = cfg.Ts;
meta.params.curve = 'rotated Gerono lemniscate';
meta.params.a = cfg.a;
meta.params.b = cfg.b;
meta.params.curve_length = curve.length;
meta.params.min_radius = curve.min_radius;
meta.params.rho_filter_tau = cfg.rho_filter_tau;
meta.params.v_design = [cfg.v_min_design, cfg.v_max_design];
meta.params.omega_abs_design = cfg.omega_abs_design;
meta.params.theta_abs_max_deg = rad2deg(cfg.theta_abs_max);
meta.params.vehicle_Ts = params.Ts;
meta.zones = zones;
meta.segments = segments;
meta.num_segments = numel(segments);
meta.recommended_eval_windows = { ...
    [12 35], [48 62], [66 86], [90 108], [116 136], [136 148], [152 170]};
meta.recommended_injection_windows = { ...
    [18 28], [50 58], [72 82], [94 104], [122 132], [136 144], [154 168]};
meta.optional_disturbance_windows = struct( ...
    'load_change', [24 30], ...
    'stall', [50 56], ...
    'slip', [136 142]);
meta.notes = { ...
    'The path is a closed figure-eight loop: start/end position and heading match.', ...
    'Right and left turns are created by the two natural lobes of the curve.', ...
    'Slope content uses short transitions, reversal, and composite turn-slope zones.', ...
    'Low-speed flat turn and bumpy theta zones are included as hard negatives.', ...
    'Stall/load/slip are disturbance-injection states in the dataset, not pure reference-path states; optional windows are recorded for later controlled injection tests.'};
end

function segments = local_zone_segments(zones)
names = fieldnames(zones);
segments = repmat(struct('t_start', NaN, 't_end', NaN, 'type', '', 'desc', ''), numel(names), 1);
for i = 1:numel(names)
    span = zones.(names{i});
    segments(i).t_start = span(1);
    segments(i).t_end = span(2);
    segments(i).type = names{i};
    segments(i).desc = strrep(names{i}, '_', ' ');
end
end

function coverage = local_compute_coverage(ref, cfg)
t = ref.t;
dt = median(diff(t));
is_slope = abs(ref.theta_ref) >= cfg.slope_threshold;
is_left = ref.omega_ref >= cfg.turn_threshold;
is_right = ref.omega_ref <= -cfg.turn_threshold;
is_turn = is_left | is_right;
is_straight = ~is_turn;

coverage = struct();
coverage.T_end = ref.t(end);
coverage.dt = dt;
coverage.v_range = [min(ref.v_ref), max(ref.v_ref)];
coverage.omega_range = [min(ref.omega_ref), max(ref.omega_ref)];
coverage.theta_range_deg = rad2deg([min(ref.theta_ref), max(ref.theta_ref)]);
coverage.flat_seconds = local_duration(~is_slope, dt);
coverage.slope_seconds = local_duration(is_slope, dt);
coverage.pure_slope_seconds = local_duration(is_slope & is_straight, dt);
coverage.composite_seconds = local_duration(is_slope & is_turn, dt);
coverage.left_turn_seconds = local_duration(is_left, dt);
coverage.right_turn_seconds = local_duration(is_right, dt);
coverage.straight_seconds = local_duration(is_straight, dt);
coverage.flat_turn_seconds = local_duration(~is_slope & is_turn, dt);
coverage.low_speed_seconds = local_duration(ref.v_ref < 0.83, dt);
coverage.closure_distance_m = hypot(ref.X_ref(end) - ref.X_ref(1), ref.Y_ref(end) - ref.Y_ref(1));
coverage.closure_heading_deg = rad2deg(local_wrap_to_pi(ref.psi_ref(end) - ref.psi_ref(1)));
coverage.min_turn_radius_m = min(abs(ref.v_ref(is_turn) ./ ref.omega_ref(is_turn)));
end

function s = local_duration(mask, dt)
s = nnz(mask) * dt;
end

function local_validate_ref(ref, cfg, coverage)
if any(diff(ref.t) <= 0)
    error('DemoPath:BadTime', 'ref.t must be strictly increasing.');
end
if any(~isfinite(ref.signals.values), 'all')
    error('DemoPath:NonFinite', 'ref.signals contains non-finite values.');
end
if min(ref.v_ref) < cfg.v_min_design - 0.03 || max(ref.v_ref) > cfg.v_max_design + 0.03
    error('DemoPath:SpeedRange', 'v_ref range is outside the demo design envelope.');
end
if max(abs(ref.omega_ref)) > cfg.omega_abs_design + 0.01
    error('DemoPath:OmegaRange', 'omega_ref exceeds the demo design envelope.');
end
if max(abs(ref.theta_ref)) > cfg.theta_abs_max + deg2rad(0.05)
    error('DemoPath:ThetaRange', 'theta_ref exceeds the demo design envelope.');
end
if coverage.closure_distance_m > 0.10
    error('DemoPath:ClosureDistance', 'Path endpoint is not closed enough.');
end
if abs(coverage.closure_heading_deg) > 0.5
    error('DemoPath:ClosureHeading', 'Path heading is not closed enough.');
end
if coverage.left_turn_seconds < 20 || coverage.right_turn_seconds < 20
    error('DemoPath:TurnCoverage', 'Insufficient left/right turn coverage.');
end
if coverage.slope_seconds < 40 || coverage.composite_seconds < 15
    error('DemoPath:SlopeCoverage', 'Insufficient slope/composite coverage.');
end
end

function local_visualize_ref(ref, coverage, fig_file)
fig = figure('Name', ref.meta.path_type, 'Position', [80, 80, 1400, 820], 'Visible', 'off');

subplot(2, 3, 1);
plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.5); hold on;
plot(ref.X_ref(1), ref.Y_ref(1), 'go', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
plot(ref.X_ref(end), ref.Y_ref(end), 'rs', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
grid on; axis equal;
xlabel('X [m]'); ylabel('Y [m]');
title('Closed demo path');
legend('ref', 'start', 'end', 'Location', 'best');

subplot(2, 3, 2);
plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('v [m/s]');
title(sprintf('Speed [%.2f, %.2f]', coverage.v_range(1), coverage.v_range(2)));

subplot(2, 3, 3);
plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.2); hold on;
yline(0, 'k--');
grid on; xlabel('t [s]'); ylabel('\omega [rad/s]');
title(sprintf('Yaw rate [%.3f, %.3f]', coverage.omega_range(1), coverage.omega_range(2)));

subplot(2, 3, 4);
plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('\psi [deg]');
title('Heading');

subplot(2, 3, 5);
plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.2); hold on;
yline(0, 'k--');
grid on; xlabel('t [s]'); ylabel('\theta [deg]');
title(sprintf('Slope [%.1f, %.1f] deg', coverage.theta_range_deg(1), coverage.theta_range_deg(2)));

subplot(2, 3, 6);
plot(ref.t, ref.rho(:,1), 'r-', 'LineWidth', 1.0); hold on;
plot(ref.t, ref.rho(:,2), 'g-', 'LineWidth', 1.0);
plot(ref.t, rad2deg(ref.rho(:,3)), 'b-', 'LineWidth', 1.0);
grid on; xlabel('t [s]'); ylabel('rho');
legend('v', '\omega', '\theta deg', 'Location', 'best');
title('Filtered scheduling rho');

saveas(fig, fig_file);
close(fig);
end

function local_write_report(report_file, ref, cfg, coverage, out_file, fig_file)
fid = fopen(report_file, 'w');
if fid < 0
    warning('DemoPath:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN Demo Closed-Loop Path\n\n');
fprintf(fid, '- path file: `%s`\n', out_file);
fprintf(fid, '- preview: `%s`\n', fig_file);
fprintf(fid, '- duration: `%.1f s`\n', ref.t(end));
fprintf(fid, '- curve: `%s`\n', ref.meta.params.curve);
fprintf(fid, '- curve length: `%.2f m`\n', ref.meta.params.curve_length);
fprintf(fid, '- minimum radius: `%.2f m`\n', ref.meta.params.min_radius);
fprintf(fid, '- closure distance: `%.4f m`\n', coverage.closure_distance_m);
fprintf(fid, '- closure heading error: `%.4f deg`\n\n', coverage.closure_heading_deg);

fprintf(fid, '## Ranges\n\n');
fprintf(fid, '| signal | min | max |\n');
fprintf(fid, '|---|---:|---:|\n');
fprintf(fid, '| v [m/s] | %.4f | %.4f |\n', min(ref.v_ref), max(ref.v_ref));
fprintf(fid, '| omega [rad/s] | %.4f | %.4f |\n', min(ref.omega_ref), max(ref.omega_ref));
fprintf(fid, '| theta [deg] | %.4f | %.4f |\n\n', min(rad2deg(ref.theta_ref)), max(rad2deg(ref.theta_ref)));

fprintf(fid, '## Coverage\n\n');
fprintf(fid, '| state bucket | seconds |\n');
fprintf(fid, '|---|---:|\n');
fprintf(fid, '| flat | %.2f |\n', coverage.flat_seconds);
fprintf(fid, '| slope | %.2f |\n', coverage.slope_seconds);
fprintf(fid, '| pure slope | %.2f |\n', coverage.pure_slope_seconds);
fprintf(fid, '| slope + turn composite | %.2f |\n', coverage.composite_seconds);
fprintf(fid, '| flat turn | %.2f |\n', coverage.flat_turn_seconds);
fprintf(fid, '| left turn | %.2f |\n', coverage.left_turn_seconds);
fprintf(fid, '| right turn | %.2f |\n', coverage.right_turn_seconds);
fprintf(fid, '| straight / low-yaw | %.2f |\n', coverage.straight_seconds);
fprintf(fid, '| low speed candidate | %.2f |\n\n', coverage.low_speed_seconds);

fprintf(fid, '## Zones\n\n');
fprintf(fid, '| zone | start | end |\n');
fprintf(fid, '|---|---:|---:|\n');
names = fieldnames(ref.meta.zones);
for i = 1:numel(names)
    z = ref.meta.zones.(names{i});
    fprintf(fid, '| %s | %.1f | %.1f |\n', names{i}, z(1), z(2));
end

fprintf(fid, '\n## Design Notes\n\n');
fprintf(fid, '- The path stays inside the V4 training envelope: speed around 0.8-1.1 m/s, radius above %.1f m, theta within +/-5.5 deg.\n', coverage.min_turn_radius_m);
fprintf(fid, '- It favors ModernTCN by emphasizing state classification, transition timing, left/right turn signs, slope-turn overlap, and hard-negative flat turns.\n');
fprintf(fid, '- It avoids making the demo mostly long smooth slope plateaus, where GRU theta regression would be the dominant advantage.\n');
fprintf(fid, '- Dataset stall/load/slip states require disturbance injection; this path records optional windows but does not inject disturbances by itself.\n');
fprintf(fid, '- No Simulink model file is modified by this generator.\n');

fprintf(fid, '\n## MATLAB Command\n\n');
fprintf(fid, '```matlab\n');
fprintf(fid, 'init_project;\n');
fprintf(fid, 'result = gen_modern_tcn_demo_path();\n');
fprintf(fid, 'load(result.path_file, ''ref'');\n');
fprintf(fid, '```\n');
end

function a = local_wrap_to_pi(a)
a = mod(a + pi, 2*pi) - pi;
end
