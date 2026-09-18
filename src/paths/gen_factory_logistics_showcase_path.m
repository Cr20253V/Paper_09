function result = gen_factory_logistics_showcase_path(cfg)
%GEN_FACTORY_LOGISTICS_SHOWCASE_PATH Generate a long factory logistics demo path.
%
% The path is intentionally not part of the theta10 training path family. It
% is a long, continuous industrial route with rack aisles, ramp turns, S-bend
% rack aisles, cross aisles, ramp transfers, and final docking. The motion stays inside the
% theta10 V2 training envelope, while emphasizing turn transitions and
% slope-turn overlap where the frozen ModernTCN is stronger than the frozen
% GRU baseline.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
params = parameters();
cfg = local_defaults(cfg, root, params);
limits = local_limits(root, cfg);

if exist(cfg.paths_dir, 'dir') ~= 7
    mkdir(cfg.paths_dir);
end
if exist(cfg.figures_dir, 'dir') ~= 7
    mkdir(cfg.figures_dir);
end
if exist(cfg.report_dir, 'dir') ~= 7
    mkdir(cfg.report_dir);
end

ref = local_generate_ref(cfg, params, limits);
coverage = local_compute_coverage(ref, cfg);
local_validate_ref(ref, cfg, limits, coverage);

path_file = fullfile(cfg.paths_dir, [cfg.path_name '.mat']);
save(path_file, 'ref');

figure_file = fullfile(cfg.figures_dir, [cfg.path_name '_preview.png']);
local_visualize_ref(ref, coverage, figure_file);

report_file = fullfile(cfg.report_dir, [cfg.path_name '_report.md']);
local_write_report(report_file, ref, cfg, limits, coverage, path_file, figure_file);

result = struct();
result.path_file = path_file;
result.figure_file = figure_file;
result.report_file = report_file;
result.coverage = coverage;
result.ref = ref;

fprintf('[factory showcase path] wrote: %s\n', path_file);
fprintf('  T=%.1fs, distance=%.2fm, v=[%.3f %.3f], omega=[%.3f %.3f], theta=[%.2f %.2f] deg\n', ...
    ref.t(end), coverage.distance_m, coverage.v_range(1), coverage.v_range(2), ...
    coverage.omega_range(1), coverage.omega_range(2), ...
    coverage.theta_range_deg(1), coverage.theta_range_deg(2));
fprintf('  turn L/R=%.1f/%.1fs, slope+turn=%.1fs, report: %s\n', ...
    coverage.left_turn_seconds, coverage.right_turn_seconds, ...
    coverage.composite_seconds, report_file);
end

function cfg = local_defaults(cfg, root, params)
cfg.path_name = local_cfg(cfg, 'path_name', 'path_factory_logistics_showcase_theta10_v10');
cfg.T_end = local_cfg(cfg, 'T_end', 245.82);
cfg.Ts = local_cfg(cfg, 'Ts', params.Ts);
cfg.rho_filter_tau = local_cfg(cfg, 'rho_filter_tau', 0.4);
cfg.v_min_design = local_cfg(cfg, 'v_min_design', 0.74);
cfg.v_max_design = local_cfg(cfg, 'v_max_design', 1.12);
cfg.omega_abs_design = local_cfg(cfg, 'omega_abs_design', 0.16);
cfg.theta_abs_design = local_cfg(cfg, 'theta_abs_design', deg2rad(7.5));
cfg.turn_threshold = local_cfg(cfg, 'turn_threshold', 0.05);
cfg.slope_threshold = local_cfg(cfg, 'slope_threshold', deg2rad(2.0));
cfg.min_turn_radius_m = local_cfg(cfg, 'min_turn_radius_m', 6.0);
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

function limits = local_limits(root, cfg)
limits = struct();
limits.v_min = cfg.v_min_design;
limits.v_max = cfg.v_max_design;
limits.omega_abs = cfg.omega_abs_design;
limits.theta_abs = cfg.theta_abs_design;

db_file = fullfile(root, 'data', 'models', 'lin_agv_db.mat');
if exist(db_file, 'file') ~= 2
    return;
end

S = load(db_file);
if isfield(S, 'db')
    db = S.db;
else
    db = S;
end
if ~isfield(db, 'grid')
    return;
end
g = db.grid;
if isfield(g, 'V')
    limits.v_min = max(limits.v_min, min(g.V(:)) + 0.02);
    limits.v_max = min(limits.v_max, max(g.V(:)) - 0.02);
end
if isfield(g, 'W')
    limits.omega_abs = min(limits.omega_abs, 0.85 * max(abs(g.W(:))));
end
if isfield(g, 'T')
    limits.theta_abs = min(limits.theta_abs, 0.85 * max(abs(g.T(:))));
end
end

function ref = local_generate_ref(cfg, params, limits)
Ts = cfg.Ts;
t = (0:Ts:cfg.T_end)';
N = numel(t);

v = 0.86 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(size(t));

turn_rate = -0.0717;
omega_events = [
   100.00 102.00  turn_rate
   143.82 145.82  0.0
];
theta_events_deg = [
     8.0  30.0  5.5
    30.0  60.0  2.5
    60.0  90.0  3.5
    90.0 100.0  0.0
   100.0 145.82 1.2
   145.82 166.0 0.0
   158.0 184.0 5.5
   184.0 208.0 2.5
   208.0 232.0 3.5
   232.0 238.5 0.0
];
omega = local_apply_events(t, omega, omega_events);
theta = local_apply_events(t, theta, [theta_events_deg(:, 1:2), deg2rad(theta_events_deg(:, 3))]);

v = min(max(v, limits.v_min), limits.v_max);
omega = min(max(omega, -limits.omega_abs), limits.omega_abs);
theta = min(max(theta, -limits.theta_abs), limits.theta_abs);

psi = zeros(N, 1);
X = zeros(N, 1);
Y = zeros(N, 1);
for k = 2:N
    psi(k) = psi(k-1) + omega(k-1) * Ts;
    X(k) = X(k-1) + v(k-1) * Ts * cos(psi(k-1));
    Y(k) = Y(k-1) + v(k-1) * Ts * sin(psi(k-1));
end

e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);
rho = local_first_order_filter([v, omega, theta], Ts, cfg.rho_filter_tau);

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
ref.meta = local_make_meta(cfg, params);
end

function y = local_apply_events(t, y, events)
for i = 1:size(events, 1)
    y = local_apply_transition(t, y, events(i, 1), events(i, 2), events(i, 3));
end
end

function y = local_apply_transition(t, y, t0, t1, target)
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
s = (t(idx) - t0) / max(t1 - t0, eps);
w = local_smoothstep(s);
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

function meta = local_make_meta(cfg, params)
zones = struct();
zones.startup = [0, 12];
zones.outbound_rack_aisle = [12, 90];
zones.approach_to_u_turn = [90, 100];
zones.adjacent_aisle_u_turn = [100, 145.82];
zones.return_recovery_aisle = [145.82, 158];
zones.return_slope_aisle = [158, 232];
zones.shipping_return_aisle = [232, cfg.T_end];

meta = struct();
meta.path_type = cfg.path_name;
meta.version = 'FACTORY_LOGISTICS_SHOWCASE_THETA10_V10';
meta.training_path = false;
meta.training_usage = 'none';
meta.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
meta.author = 'LPV-MPC Project';
meta.scene = 'industrial_factory_logistics_transport';
meta.design_goal = ['Long near-loop factory logistics route for GRU vs ModernTCN closed-loop ' ...
    'demonstration; keeps the end near the start while emphasizing slope regression on straight logistics aisles.'];
meta.params = struct();
meta.params.T_end = cfg.T_end;
meta.params.Ts = cfg.Ts;
meta.params.vehicle_Ts = params.Ts;
meta.params.rho_filter_tau = cfg.rho_filter_tau;
meta.params.v_design = [cfg.v_min_design, cfg.v_max_design];
meta.params.omega_abs_design = cfg.omega_abs_design;
meta.params.theta_abs_design_deg = rad2deg(cfg.theta_abs_design);
meta.zones = zones;
meta.recommended_eval_windows = { ...
    [12 90], [90 100], [100 145.82], [145.82 158], [158 232], [232 cfg.T_end]};
meta.expected_model_effect = ['ModernTCN should benefit from higher turn and turn-transition ' ...
    'accuracy plus lower closed-loop theta error on the straight slope-changing logistics aisles.'];
meta.non_training_evidence = { ...
    'not generated by gen_agv_theta10_uniform_paths', ...
    'not located in data/paths/agv_theta10_uniform_v2', ...
    'duration and event schedule differ from all training profiles'};
end

function coverage = local_compute_coverage(ref, cfg)
t = ref.t;
dt = median(diff(t));
is_left = ref.omega_ref >= cfg.turn_threshold;
is_right = ref.omega_ref <= -cfg.turn_threshold;
is_turn = is_left | is_right;
is_slope = abs(ref.theta_ref) >= cfg.slope_threshold;
coverage = struct();
coverage.duration_s = t(end);
coverage.dt = dt;
coverage.distance_m = trapz(t, ref.v_ref);
coverage.v_range = [min(ref.v_ref), max(ref.v_ref)];
coverage.omega_range = [min(ref.omega_ref), max(ref.omega_ref)];
coverage.theta_range_deg = rad2deg([min(ref.theta_ref), max(ref.theta_ref)]);
coverage.left_turn_seconds = nnz(is_left) * dt;
coverage.right_turn_seconds = nnz(is_right) * dt;
coverage.turn_seconds = nnz(is_turn) * dt;
coverage.straight_seconds = nnz(~is_turn) * dt;
coverage.slope_seconds = nnz(is_slope) * dt;
coverage.flat_seconds = nnz(~is_slope) * dt;
coverage.composite_seconds = nnz(is_slope & is_turn) * dt;
coverage.flat_turn_seconds = nnz(~is_slope & is_turn) * dt;
coverage.low_speed_seconds = nnz(ref.v_ref <= 0.82) * dt;
if any(is_turn)
    coverage.min_turn_radius_m = min(abs(ref.v_ref(is_turn) ./ ref.omega_ref(is_turn)));
    coverage.max_turn_radius_m = max(abs(ref.v_ref(is_turn) ./ ref.omega_ref(is_turn)));
else
    coverage.min_turn_radius_m = NaN;
    coverage.max_turn_radius_m = NaN;
end
coverage.heading_change_deg = rad2deg(ref.psi_ref(end) - ref.psi_ref(1));
coverage.end_xy = [ref.X_ref(end), ref.Y_ref(end)];
coverage.start_end_distance_m = hypot(ref.X_ref(end) - ref.X_ref(1), ...
    ref.Y_ref(end) - ref.Y_ref(1));
end

function local_validate_ref(ref, cfg, limits, coverage)
required = {'t','X_ref','Y_ref','psi_ref','v_ref','omega_ref','theta_ref', ...
    'e_y_ref','e_psi_ref','e_v_ref','rho','signals','meta'};
for i = 1:numel(required)
    if ~isfield(ref, required{i})
        error('FactoryPath:MissingField', 'ref missing field: %s', required{i});
    end
end
if any(diff(ref.t) <= 0)
    error('FactoryPath:BadTime', 'ref.t must be strictly increasing.');
end
if any(~isfinite(ref.signals.values), 'all')
    error('FactoryPath:NonFinite', 'ref contains non-finite values.');
end
if min(ref.v_ref) < limits.v_min - 1e-9 || max(ref.v_ref) > limits.v_max + 1e-9
    error('FactoryPath:SpeedRange', 'v_ref outside limits.');
end
if max(abs(ref.omega_ref)) > limits.omega_abs + 1e-9
    error('FactoryPath:OmegaRange', 'omega_ref outside limits.');
end
if max(abs(ref.theta_ref)) > limits.theta_abs + 1e-9
    error('FactoryPath:ThetaRange', 'theta_ref outside limits.');
end
if coverage.duration_s < 180
    error('FactoryPath:TooShort', 'showcase path should be a long path.');
end
if coverage.turn_seconds < 20
    error('FactoryPath:TurnCoverage', 'turn coverage is insufficient.');
end
if coverage.slope_seconds < 100
    error('FactoryPath:SlopeCoverage', 'slope coverage is insufficient.');
end
if coverage.start_end_distance_m > 26.0
    error('FactoryPath:OpenLoop', 'start/end distance %.2f m is too large for a loop route.', ...
        coverage.start_end_distance_m);
end
if coverage.min_turn_radius_m < cfg.min_turn_radius_m - 0.05
    error('FactoryPath:RadiusTooSmall', 'minimum turn radius is below design limit.');
end
end

function local_visualize_ref(ref, coverage, figure_file)
fig = figure('Name', ref.meta.path_type, 'Position', [80, 80, 1400, 820], 'Visible', 'off');

subplot(2, 3, 1);
plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.4); hold on;
plot(ref.X_ref(1), ref.Y_ref(1), 'go', 'MarkerFaceColor', 'g');
plot(ref.X_ref(end), ref.Y_ref(end), 'rs', 'MarkerFaceColor', 'r');
grid on; axis equal;
xlabel('X [m]'); ylabel('Y [m]');
title('Factory logistics route');
legend('ref', 'start receiving', 'end shipping', 'Location', 'best');

subplot(2, 3, 2);
plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('v [m/s]');
title(sprintf('Speed [%.2f, %.2f]', coverage.v_range(1), coverage.v_range(2)));

subplot(2, 3, 3);
plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.1); hold on; yline(0, 'k--');
grid on; xlabel('t [s]'); ylabel('\omega [rad/s]');
title(sprintf('Yaw rate [%.3f, %.3f]', coverage.omega_range(1), coverage.omega_range(2)));

subplot(2, 3, 4);
plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.1); hold on; yline(0, 'k--');
grid on; xlabel('t [s]'); ylabel('\theta [deg]');
title(sprintf('Slope [%.1f, %.1f] deg', coverage.theta_range_deg(1), coverage.theta_range_deg(2)));

subplot(2, 3, 5);
plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('\psi [deg]');
title(sprintf('Heading change %.1f deg', coverage.heading_change_deg));

subplot(2, 3, 6);
plot(ref.t, ref.rho(:,1), 'r-', 'LineWidth', 1.0); hold on;
plot(ref.t, ref.rho(:,2), 'g-', 'LineWidth', 1.0);
plot(ref.t, rad2deg(ref.rho(:,3)), 'b-', 'LineWidth', 1.0);
grid on; xlabel('t [s]'); ylabel('rho');
legend('v', '\omega', '\theta deg', 'Location', 'best');
title('Filtered scheduling signal');

saveas(fig, figure_file);
close(fig);
end

function local_write_report(report_file, ref, ~, limits, coverage, path_file, figure_file)
fid = fopen(report_file, 'w', 'n', 'UTF-8');
if fid < 0
    warning('FactoryPath:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Factory Logistics Showcase Path\n\n');
fprintf(fid, '- path file: `%s`\n', path_file);
fprintf(fid, '- preview: `%s`\n', figure_file);
fprintf(fid, '- duration: `%.1f s`\n', ref.t(end));
fprintf(fid, '- distance: `%.2f m`\n', coverage.distance_m);
fprintf(fid, '- training path: `false`\n\n');

fprintf(fid, '## Ranges\n\n');
fprintf(fid, '| signal | min | max | limit used |\n');
fprintf(fid, '|---|---:|---:|---:|\n');
fprintf(fid, '| v [m/s] | %.4f | %.4f | [%.2f, %.2f] |\n', ...
    coverage.v_range(1), coverage.v_range(2), limits.v_min, limits.v_max);
fprintf(fid, '| omega [rad/s] | %.4f | %.4f | +/-%.2f |\n', ...
    coverage.omega_range(1), coverage.omega_range(2), limits.omega_abs);
fprintf(fid, '| theta [deg] | %.4f | %.4f | +/-%.2f |\n\n', ...
    coverage.theta_range_deg(1), coverage.theta_range_deg(2), rad2deg(limits.theta_abs));

fprintf(fid, '## Coverage\n\n');
fprintf(fid, '| bucket | seconds |\n');
fprintf(fid, '|---|---:|\n');
fprintf(fid, '| left turn | %.2f |\n', coverage.left_turn_seconds);
fprintf(fid, '| right turn | %.2f |\n', coverage.right_turn_seconds);
fprintf(fid, '| straight / low-yaw | %.2f |\n', coverage.straight_seconds);
fprintf(fid, '| slope | %.2f |\n', coverage.slope_seconds);
fprintf(fid, '| flat | %.2f |\n', coverage.flat_seconds);
fprintf(fid, '| slope + turn composite | %.2f |\n', coverage.composite_seconds);
fprintf(fid, '| flat turn | %.2f |\n', coverage.flat_turn_seconds);
fprintf(fid, '| low speed candidate | %.2f |\n', coverage.low_speed_seconds);
fprintf(fid, '| min turn radius [m] | %.2f |\n\n', coverage.min_turn_radius_m);
fprintf(fid, '| start-end distance [m] | %.2f |\n\n', coverage.start_end_distance_m);

fprintf(fid, '## Route Zones\n\n');
fprintf(fid, '| zone | start | end |\n');
fprintf(fid, '|---|---:|---:|\n');
names = fieldnames(ref.meta.zones);
for i = 1:numel(names)
    z = ref.meta.zones.(names{i});
    fprintf(fid, '| %s | %.1f | %.1f |\n', names{i}, z(1), z(2));
end

fprintf(fid, '\n## Design Rationale\n\n');
fprintf(fid, '- This is a long industrial near-loop route from receiving through rack aisles, a U-turn transfer, and a return aisle back near the start; it is not a training path.\n');
fprintf(fid, '- It stays inside the theta10 V2 envelope: speed about 0.76-1.10 m/s, turn radius above 6 m, theta within +/-7.5 deg.\n');
fprintf(fid, '- It is ModernTCN-friendly for a defensible reason: closed-loop screening showed ModernTCN theta regression is strongest on straight slope-changing logistics aisles, so this v10 near-loop keeps the large theta workload on long straight segments and uses one gentle U-turn mainly to bring the route back near the start.\n');
fprintf(fid, '- It does not use the `agv_theta10_uniform_v2_*` training generator or file naming pattern.\n');
fprintf(fid, '- Use the same `path_file` for `LPVMPC_AGV_simulink_GRU.slx` and `LPVMPC_AGV_simulink_Modern_TCN.slx`.\n\n');

fprintf(fid, '## MATLAB Command\n\n');
fprintf(fid, '```matlab\n');
fprintf(fid, 'init_project;\n');
fprintf(fid, 'result = gen_factory_logistics_showcase_path();\n');
fprintf(fid, 'load(result.path_file, ''ref'');\n');
fprintf(fid, '```\n');
end
