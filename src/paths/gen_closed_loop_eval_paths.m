function out = gen_closed_loop_eval_paths(cfg)
%GEN_CLOSED_LOOP_EVAL_PATHS Generate supplemental closed-loop evaluation paths.
%
% The generated paths are not training paths.  They are designed for
% supplemental closed-loop benchmarking of ModernTCN / GRU / TCN and LPV-MPC
% theta baselines.

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

local_ensure_dir(cfg.paths_dir);
local_ensure_dir(cfg.figures_dir);
local_ensure_dir(cfg.report_dir);

rows = repmat(local_manifest_row(), 0, 1);
path_files = {};

if cfg.include_factory
    factory_file = fullfile(cfg.paths_dir, 'path_factory_logistics_showcase_theta10_v3.mat');
    if exist(factory_file, 'file') ~= 2 && cfg.generate_missing_factory
        gen_factory_logistics_showcase_path(struct( ...
            'path_name', 'path_factory_logistics_showcase_theta10_v3'));
    end
    if exist(factory_file, 'file') == 2
        path_files{end+1, 1} = factory_file; %#ok<AGROW>
        row = local_manifest_row();
        row.path_tag = "path_factory_logistics_showcase_theta10_v3";
        row.role = "factory_logistics_showcase";
        row.path_file = string(factory_file);
        row.status = "existing";
        rows(end+1) = row; %#ok<AGROW>
    else
        warning('gen_closed_loop_eval_paths:MissingFactory', ...
            'Factory showcase path is missing: %s', factory_file);
    end
end

specs = local_build_specs(cfg);
for i = 1:numel(specs)
    spec = specs(i);
    path_file = fullfile(cfg.paths_dir, [spec.tag '.mat']);
    figure_file = fullfile(cfg.figures_dir, [spec.tag '_preview.png']);
    report_file = fullfile(cfg.report_dir, [spec.tag '_report.md']);

    if exist(path_file, 'file') == 2 && ~cfg.force
        S = load(path_file, 'ref');
        ref = S.ref;
        coverage = local_compute_coverage(ref, spec, cfg);
        status = "existing";
    else
        ref = local_generate_ref(spec, cfg, params, limits);
        coverage = local_compute_coverage(ref, spec, cfg);
        local_validate_ref(ref, spec, cfg, limits, coverage);
        save(path_file, 'ref');
        local_visualize_ref(ref, coverage, spec, figure_file);
        local_write_report(report_file, ref, spec, limits, coverage, path_file, figure_file);
        status = "generated";
    end

    path_files{end+1, 1} = path_file; %#ok<AGROW>
    row = local_manifest_row();
    row.path_tag = string(spec.tag);
    row.role = string(spec.role);
    row.path_file = string(path_file);
    row.figure_file = string(figure_file);
    row.report_file = string(report_file);
    row.status = status;
    row.duration_s = coverage.duration_s;
    row.distance_m = coverage.distance_m;
    row.turn_seconds = coverage.turn_seconds;
    row.slope_seconds = coverage.slope_seconds;
    row.slope_turn_seconds = coverage.slope_turn_seconds;
    row.stall_candidate_seconds = coverage.stall_candidate_seconds;
    row.theta_min_deg = coverage.theta_range_deg(1);
    row.theta_max_deg = coverage.theta_range_deg(2);
    row.omega_min = coverage.omega_range(1);
    row.omega_max = coverage.omega_range(2);
    rows(end+1) = row; %#ok<AGROW>

    fprintf('[closed-loop eval path] %s: %s\n', status, path_file);
end

manifest_table = struct2table(rows);
manifest_file = fullfile(cfg.report_dir, 'closed_loop_eval_paths_manifest.csv');
writetable(manifest_table, manifest_file);

out = struct();
out.path_files = path_files;
out.manifest_table = manifest_table;
out.manifest_file = manifest_file;
out.cfg = cfg;

fprintf('[closed-loop eval path] manifest: %s\n', manifest_file);
end

function cfg = local_defaults(cfg, root, params)
cfg.Ts = local_cfg(cfg, 'Ts', params.Ts);
cfg.force = local_cfg(cfg, 'force', false);
cfg.include_factory = local_cfg(cfg, 'include_factory', true);
cfg.include_mixed = local_cfg(cfg, 'include_mixed', false);
cfg.generate_missing_factory = local_cfg(cfg, 'generate_missing_factory', false);
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

function v = local_cfg(cfg, name, default_value)
if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
    v = cfg.(name);
else
    v = default_value;
end
end

function local_ensure_dir(d)
if exist(d, 'dir') ~= 7
    mkdir(d);
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

function specs = local_build_specs(cfg)
specs = repmat(local_empty_spec(), 0, 1);
specs(end+1) = local_spec_long_updown(); %#ok<AGROW>
specs(end+1) = local_spec_sharp_turn(); %#ok<AGROW>
if cfg.include_mixed
    specs(end+1) = local_spec_mixed_disturbance(); %#ok<AGROW>
end
end

function spec = local_empty_spec()
spec = struct();
spec.tag = '';
spec.role = '';
spec.title = '';
spec.design_goal = '';
spec.T_end = NaN;
spec.v_base = NaN;
spec.v_events = zeros(0, 3);
spec.omega_events = zeros(0, 3);
spec.theta_events_deg = zeros(0, 3);
spec.zones = struct();
spec.stall_windows = zeros(0, 2);
spec.min_slope_seconds = 0;
spec.min_turn_seconds = 0;
spec.min_stall_candidate_seconds = 0;
end

function spec = local_spec_long_updown()
spec = local_empty_spec();
spec.tag = 'path_closed_loop_long_updown_theta10_v1';
spec.role = 'long_updown';
spec.title = 'Long Uphill/Downhill Path';
spec.design_goal = ['Long slope transitions with a few gentle transfer turns; ' ...
    'intended to stress theta scheduling without leaving the LPV grid.'];
spec.T_end = 44.0;
spec.v_base = 0.88;
spec.v_events = [
     0.0   3.0  0.84
    15.0  18.0  0.92
    28.0  31.0  0.86
    39.0  42.0  0.90
    ];
spec.theta_events_deg = [
     3.0   7.0   6.2
    16.0  21.0  -5.8
    29.0  34.0   6.6
    39.0  43.0   0.0
    ];
spec.omega_events = [
     9.0  10.5   0.090
    13.5  15.0   0.000
    23.0  24.5  -0.100
    27.5  29.0   0.000
    35.0  36.5   0.085
    39.0  40.5   0.000
    ];
spec.zones = struct( ...
    'startup', [0 3], ...
    'uphill_long_entry', [3 16], ...
    'downhill_transition', [16 29], ...
    'uphill_return', [29 39], ...
    'flat_recovery', [39 spec.T_end]);
spec.min_slope_seconds = 32;
spec.min_turn_seconds = 9;
end

function spec = local_spec_sharp_turn()
spec = local_empty_spec();
spec.tag = 'path_closed_loop_sharp_turn_transition_theta10_v1';
spec.role = 'sharp_turn_transition';
spec.title = 'Sharp Turning Transition Path';
spec.design_goal = ['Alternating left/right turn transitions overlapped with slope entry/exit; ' ...
    'intended to stress coupled turn-transition recognition and theta scheduling.'];
spec.T_end = 52.0;
spec.v_base = 0.82;
spec.v_events = [
     0.0   3.0  0.82
    16.0  20.0  0.88
    34.0  38.0  0.84
    46.0  50.0  0.86
    ];
spec.theta_events_deg = [
     4.0  10.0   5.5
    24.0  30.0  -5.2
    44.0  50.0   0.0
    ];
spec.omega_events = [
    11.0  13.0   0.108
    19.0  21.0   0.000
    31.0  33.0  -0.108
    39.0  41.0   0.000
    43.0  45.0   0.098
    48.0  50.0   0.000
    ];
spec.zones = struct( ...
    'startup', [0 4], ...
    'uphill_left_transition', [4 22], ...
    'downhill_right_transition', [22 42], ...
    'flat_left_exit', [42 spec.T_end]);
spec.min_slope_seconds = 34;
spec.min_turn_seconds = 16;
end

function spec = local_spec_mixed_disturbance()
spec = local_empty_spec();
spec.tag = 'path_closed_loop_mixed_disturbance_theta10_v1';
spec.role = 'mixed_disturbance_candidate';
spec.title = 'Mixed Disturbance Candidate Path';
spec.design_goal = ['Slope, sharp turn, and low-speed high-load candidate windows. ' ...
    'The stall windows are encoded in ref.meta for truth labeling; physical ' ...
    'time-varying load injection can be added by a future plant input path.'];
spec.T_end = 220.0;
spec.v_base = 0.86;
spec.v_events = [
     0.0  10.0  0.84
    46.0  54.0  0.75
    66.0  74.0  0.90
   114.0 122.0  0.74
   136.0 144.0  0.88
   184.0 194.0  0.82
    ];
spec.theta_events_deg = [
    12.0  28.0   5.8
    72.0  86.0   0.0
    94.0 110.0  -5.8
   148.0 166.0   6.5
   198.0 212.0   0.0
    ];
spec.omega_events = [
    32.0  36.0   0.118
    48.0  52.0   0.000
    84.0  88.0  -0.118
   100.0 104.0   0.000
   128.0 132.0   0.112
   144.0 148.0   0.000
   170.0 174.0  -0.118
   186.0 190.0   0.000
    ];
spec.stall_windows = [
    46.0  62.0
   114.0 130.0
    ];
spec.zones = struct( ...
    'startup', [0 12], ...
    'uphill_turn_mix', [12 46], ...
    'stall_candidate_1', [46 72], ...
    'downhill_turn_mix', [72 114], ...
    'stall_candidate_2', [114 148], ...
    'uphill_reversal_mix', [148 198], ...
    'flat_recovery', [198 spec.T_end]);
spec.min_slope_seconds = 115;
spec.min_turn_seconds = 45;
spec.min_stall_candidate_seconds = 25;
end

function ref = local_generate_ref(spec, cfg, params, limits)
t = (0:cfg.Ts:spec.T_end)';
N = numel(t);

v = spec.v_base * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);

v = local_apply_events(t, v, spec.v_events);
omega = local_apply_events(t, omega, spec.omega_events);
theta = local_apply_events(t, theta, [spec.theta_events_deg(:, 1:2), deg2rad(spec.theta_events_deg(:, 3))]);

v = min(max(v, limits.v_min), limits.v_max);
omega = min(max(omega, -limits.omega_abs), limits.omega_abs);
theta = min(max(theta, -limits.theta_abs), limits.theta_abs);

psi = zeros(N, 1);
X = zeros(N, 1);
Y = zeros(N, 1);
for k = 2:N
    psi(k) = psi(k-1) + omega(k-1) * cfg.Ts;
    X(k) = X(k-1) + v(k-1) * cfg.Ts * cos(psi(k-1));
    Y(k) = Y(k-1) + v(k-1) * cfg.Ts * sin(psi(k-1));
end

e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);
rho = local_first_order_filter([v, omega, theta], cfg.Ts, cfg.rho_filter_tau);

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
ref.meta = local_make_meta(spec, cfg, params);
end

function y = local_apply_events(t, y, events)
if isempty(events)
    return;
end
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

function meta = local_make_meta(spec, cfg, params)
meta = struct();
meta.path_type = spec.tag;
meta.version = 'CLOSED_LOOP_EVAL_PATH_V1';
meta.training_path = false;
meta.training_usage = 'none';
meta.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
meta.author = 'LPV-MPC Project';
meta.scene = 'supplemental_closed_loop_benchmark';
meta.role = spec.role;
meta.design_goal = spec.design_goal;
meta.params = struct();
meta.params.T_end = spec.T_end;
meta.params.Ts = cfg.Ts;
meta.params.vehicle_Ts = params.Ts;
meta.params.rho_filter_tau = cfg.rho_filter_tau;
meta.params.v_design = [cfg.v_min_design, cfg.v_max_design];
meta.params.omega_abs_design = cfg.omega_abs_design;
meta.params.theta_abs_design_deg = rad2deg(cfg.theta_abs_design);
meta.zones = spec.zones;
meta.stall_windows = spec.stall_windows;
meta.disturbance_windows = struct('stall', spec.stall_windows);
meta.recommended_eval_windows = local_zone_windows(spec.zones);
meta.non_training_evidence = { ...
    'not generated by gen_agv_theta10_uniform_paths', ...
    'supplemental closed-loop-only evaluation path', ...
    'file name uses path_closed_loop_* rather than training path prefix'};
end

function c = local_zone_windows(zones)
names = fieldnames(zones);
c = cell(numel(names), 1);
for i = 1:numel(names)
    c{i} = zones.(names{i});
end
end

function coverage = local_compute_coverage(ref, spec, cfg)
t = ref.t(:);
dt = median(diff(t));
is_left = ref.omega_ref(:) >= cfg.turn_threshold;
is_right = ref.omega_ref(:) <= -cfg.turn_threshold;
is_turn = is_left | is_right;
is_slope = abs(ref.theta_ref(:)) >= cfg.slope_threshold;

coverage = struct();
coverage.duration_s = t(end);
coverage.dt = dt;
coverage.distance_m = trapz(t, ref.v_ref(:));
coverage.v_range = [min(ref.v_ref(:)), max(ref.v_ref(:))];
coverage.omega_range = [min(ref.omega_ref(:)), max(ref.omega_ref(:))];
coverage.theta_range_deg = rad2deg([min(ref.theta_ref(:)), max(ref.theta_ref(:))]);
coverage.left_turn_seconds = nnz(is_left) * dt;
coverage.right_turn_seconds = nnz(is_right) * dt;
coverage.turn_seconds = nnz(is_turn) * dt;
coverage.slope_seconds = nnz(is_slope) * dt;
coverage.slope_turn_seconds = nnz(is_slope & is_turn) * dt;
coverage.flat_turn_seconds = nnz(~is_slope & is_turn) * dt;
coverage.low_speed_seconds = nnz(ref.v_ref(:) <= 0.78) * dt;
coverage.stall_candidate_seconds = local_window_seconds(spec.stall_windows);
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

function sec = local_window_seconds(windows)
sec = 0;
if isempty(windows)
    return;
end
for i = 1:size(windows, 1)
    sec = sec + max(0, windows(i, 2) - windows(i, 1));
end
end

function local_validate_ref(ref, spec, cfg, limits, coverage)
required = {'t','X_ref','Y_ref','psi_ref','v_ref','omega_ref','theta_ref', ...
    'e_y_ref','e_psi_ref','e_v_ref','rho','signals','meta'};
for i = 1:numel(required)
    if ~isfield(ref, required{i})
        error('ClosedLoopEvalPath:MissingField', 'ref missing field: %s', required{i});
    end
end
if any(diff(ref.t) <= 0)
    error('ClosedLoopEvalPath:BadTime', 'ref.t must be strictly increasing.');
end
if any(~isfinite(ref.signals.values), 'all')
    error('ClosedLoopEvalPath:NonFinite', 'ref contains non-finite values.');
end
if min(ref.v_ref) < limits.v_min - 1e-9 || max(ref.v_ref) > limits.v_max + 1e-9
    error('ClosedLoopEvalPath:SpeedRange', 'v_ref outside limits.');
end
if max(abs(ref.omega_ref)) > limits.omega_abs + 1e-9
    error('ClosedLoopEvalPath:OmegaRange', 'omega_ref outside limits.');
end
if max(abs(ref.theta_ref)) > limits.theta_abs + 1e-9
    error('ClosedLoopEvalPath:ThetaRange', 'theta_ref outside limits.');
end
if coverage.duration_s < 30
    error('ClosedLoopEvalPath:TooShort', 'supplemental path is too short.');
end
if coverage.turn_seconds < spec.min_turn_seconds
    error('ClosedLoopEvalPath:TurnCoverage', 'turn coverage is insufficient.');
end
if coverage.slope_seconds < spec.min_slope_seconds
    error('ClosedLoopEvalPath:SlopeCoverage', 'slope coverage is insufficient.');
end
if coverage.stall_candidate_seconds < spec.min_stall_candidate_seconds
    error('ClosedLoopEvalPath:StallCoverage', 'stall candidate coverage is insufficient.');
end
if isfinite(coverage.min_turn_radius_m) && ...
        coverage.min_turn_radius_m < cfg.min_turn_radius_m - 0.05
    error('ClosedLoopEvalPath:RadiusTooSmall', ...
        'minimum turn radius %.2f m is below design limit.', coverage.min_turn_radius_m);
end
end

function local_visualize_ref(ref, coverage, spec, figure_file)
fig = figure('Name', spec.tag, 'Position', [80, 80, 1400, 820], 'Visible', 'off');

subplot(2, 3, 1);
plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.4); hold on;
plot(ref.X_ref(1), ref.Y_ref(1), 'go', 'MarkerFaceColor', 'g');
plot(ref.X_ref(end), ref.Y_ref(end), 'rs', 'MarkerFaceColor', 'r');
grid on; axis equal;
xlabel('X [m]'); ylabel('Y [m]');
title(spec.title);
legend('ref', 'start', 'end', 'Location', 'best');

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

function local_write_report(report_file, ref, spec, limits, coverage, path_file, figure_file)
fid = fopen(report_file, 'w', 'n', 'UTF-8');
if fid < 0
    warning('ClosedLoopEvalPath:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# %s\n\n', spec.title);
fprintf(fid, '- path file: `%s`\n', path_file);
fprintf(fid, '- preview: `%s`\n', figure_file);
fprintf(fid, '- role: `%s`\n', spec.role);
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
fprintf(fid, '| turn | %.2f |\n', coverage.turn_seconds);
fprintf(fid, '| left turn | %.2f |\n', coverage.left_turn_seconds);
fprintf(fid, '| right turn | %.2f |\n', coverage.right_turn_seconds);
fprintf(fid, '| slope | %.2f |\n', coverage.slope_seconds);
fprintf(fid, '| slope + turn | %.2f |\n', coverage.slope_turn_seconds);
fprintf(fid, '| low speed candidate | %.2f |\n', coverage.low_speed_seconds);
fprintf(fid, '| stall candidate window | %.2f |\n', coverage.stall_candidate_seconds);
fprintf(fid, '| min turn radius [m] | %.2f |\n\n', coverage.min_turn_radius_m);

fprintf(fid, '## Route Zones\n\n');
fprintf(fid, '| zone | start | end |\n');
fprintf(fid, '|---|---:|---:|\n');
names = fieldnames(ref.meta.zones);
for i = 1:numel(names)
    z = ref.meta.zones.(names{i});
    fprintf(fid, '| %s | %.1f | %.1f |\n', names{i}, z(1), z(2));
end

fprintf(fid, '\n## Design Goal\n\n');
fprintf(fid, '%s\n\n', spec.design_goal);
fprintf(fid, '## MATLAB Command\n\n');
fprintf(fid, '```matlab\n');
fprintf(fid, 'init_project;\n');
fprintf(fid, 'out = gen_closed_loop_eval_paths(struct(''force'', true));\n');
fprintf(fid, '```\n');
end

function row = local_manifest_row()
row = struct();
row.path_tag = "";
row.role = "";
row.path_file = "";
row.figure_file = "";
row.report_file = "";
row.status = "";
row.duration_s = NaN;
row.distance_m = NaN;
row.turn_seconds = NaN;
row.slope_seconds = NaN;
row.slope_turn_seconds = NaN;
row.stall_candidate_seconds = NaN;
row.theta_min_deg = NaN;
row.theta_max_deg = NaN;
row.omega_min = NaN;
row.omega_max = NaN;
end
