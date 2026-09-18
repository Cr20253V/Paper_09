function [manifest, refs] = gen_agv_theta10_uniform_paths(cfg)
%GEN_AGV_THETA10_UNIFORM_PATHS Build reference paths for the theta10 dataset.
%
% This generator only creates reference path MAT files. It does not run
% Simulink and does not create training windows.
%
% Design goals:
%   - theta labels cover one-degree bins over [-10, 10) deg with near-uniform
%     dwell time per bin;
%   - path duration is split into long/compound/short groups close to
%     50/30/20 before transition-rich windowing;
%   - each theta bin sees straight, left-turn, and right-turn motion;
%   - turn radius, speed, and steering angle proxies are varied in the same
%     path family;
%   - true-zero flat samples are present but intentionally small.
%
% Example:
%   init_project;
%   cfg = struct('write_files', true, 'make_figures', false);
%   manifest = gen_agv_theta10_uniform_paths(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = local_defaults(cfg, root);
params = parameters();
limits = local_read_constraints(root, params);
local_validate_limits(limits, cfg);

rng(cfg.seed, 'twister');
specs = local_build_specs(cfg, limits);

if cfg.write_files
    if ~exist(cfg.output_dir, 'dir'), mkdir(cfg.output_dir); end
    if cfg.make_figures && ~exist(cfg.figure_dir, 'dir'), mkdir(cfg.figure_dir); end
end

manifest = repmat(local_manifest_row_template(), numel(specs), 1);
refs = cell(numel(specs), 1);

if cfg.verbose
    fprintf('\n[theta10 paths] planned paths: %d\n', numel(specs));
    fprintf('  output_dir : %s\n', cfg.output_dir);
    fprintf('  write_files: %d\n', double(cfg.write_files));
end

for i = 1:numel(specs)
    spec = local_clip_spec_to_limits(specs(i), limits);
    ref = local_generate_ref_from_spec(spec, params, cfg, limits);
    local_validate_ref(ref, limits);
    if nargout >= 2
        refs{i} = ref;
    end

    file_name = sprintf('%s%03d_%s.mat', cfg.path_prefix, i, spec.name);
    out_file = fullfile(cfg.output_dir, file_name);
    if cfg.write_files
        save(out_file, 'ref');
        if cfg.make_figures
            local_visualize_ref(ref, spec.name, cfg.figure_dir, cfg.figure_prefix);
        end
    else
        out_file = '';
    end

    manifest(i) = local_manifest_from_ref(i, file_name, out_file, spec, ref);
    if cfg.verbose
        fprintf('[%03d/%03d] %-42s theta=[%6.2f,%6.2f] deg, R=[%4.1f,%4.1f]\n', ...
            i, numel(specs), spec.name, ...
            min(rad2deg(ref.theta_ref)), max(rad2deg(ref.theta_ref)), ...
            spec.radius_a_m, spec.radius_b_m);
    end
end

if cfg.write_files
    manifest_tbl = struct2table(manifest);
    writetable(manifest_tbl, cfg.manifest_file);
    if cfg.verbose
        fprintf('[theta10 paths] wrote manifest: %s\n', cfg.manifest_file);
    end
end
end

function cfg = local_defaults(cfg, root)
cfg.tag = local_cfg(cfg, 'tag', 'agv_theta10_uniform_v2');
cfg.output_dir = local_cfg(cfg, 'output_dir', fullfile(root, 'data', 'paths', cfg.tag));
cfg.figure_dir = local_cfg(cfg, 'figure_dir', fullfile(root, 'figures', 'paths', cfg.tag));
cfg.path_prefix = local_cfg(cfg, 'path_prefix', [cfg.tag '_']);
cfg.figure_prefix = local_cfg(cfg, 'figure_prefix', [cfg.tag '_']);
cfg.manifest_file = local_cfg(cfg, 'manifest_file', fullfile(cfg.output_dir, [cfg.tag '_manifest.csv']));
cfg.seed = local_cfg(cfg, 'seed', 20260511);
cfg.write_files = local_cfg(cfg, 'write_files', true);
cfg.make_figures = local_cfg(cfg, 'make_figures', false);
cfg.verbose = local_cfg(cfg, 'verbose', true);
cfg.rho_filter_tau = local_cfg(cfg, 'rho_filter_tau', 0.4);
cfg.theta_edges_deg = local_cfg(cfg, 'theta_edges_deg', -10:1:10);
cfg.include_true_zero_profile = local_cfg(cfg, 'include_true_zero_profile', true);
cfg.long_path_count = local_cfg(cfg, 'long_path_count', 10);
cfg.long_path_duration_sec = local_cfg(cfg, 'long_path_duration_sec', 150.0);
cfg.compound_profile_duration_sec = local_cfg(cfg, 'compound_profile_duration_sec', 44.0);
cfg.short_profile_duration_sec = local_cfg(cfg, 'short_profile_duration_sec', 26.5);
cfg.true_zero_profile_duration_sec = local_cfg(cfg, 'true_zero_profile_duration_sec', 30.0);
cfg.turn_ramp_sec = local_cfg(cfg, 'turn_ramp_sec', 1.0);
cfg.min_turn_radius_m = local_cfg(cfg, 'min_turn_radius_m', 6.0);
cfg.max_turn_radius_m = local_cfg(cfg, 'max_turn_radius_m', 20.0);
cfg.max_theta_abs_deg = local_cfg(cfg, 'max_theta_abs_deg', 10.0);

edges = cfg.theta_edges_deg(:)';
if numel(edges) < 2 || any(abs(diff(edges) - 1) > 1e-12)
    error('theta_edges_deg must be a one-degree edge vector, e.g. -10:1:10.');
end
if abs(edges(1) + 10) > 1e-12 || abs(edges(end) - 10) > 1e-12
    error('This generator is intended for theta_edges_deg = -10:1:10.');
end
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function limits = local_read_constraints(root, params)
limits = struct();
limits.Ts = params.Ts;
limits.v_min_design = 0.70;
limits.v_max_design = 1.18;
limits.omega_abs_design = 0.28;
limits.theta_abs_design = deg2rad(10.0);
limits.F_cmd_min = -600;
limits.F_cmd_max = 600;
limits.omega_cmd_min = -1.2;
limits.omega_cmd_max = 1.2;
limits.has_db = false;

db_file = fullfile(root, 'data', 'models', 'lin_agv_db.mat');
if exist(db_file, 'file')
    S = load(db_file);
    if isfield(S, 'db')
        db = S.db;
    else
        db = S;
    end
    if isfield(db, 'grid') && all(isfield(db.grid, {'V', 'W', 'T'}))
        limits.has_db = true;
        limits.v_grid_min = min(db.grid.V(:));
        limits.v_grid_max = max(db.grid.V(:));
        limits.omega_grid_min = min(db.grid.W(:));
        limits.omega_grid_max = max(db.grid.W(:));
        limits.theta_grid_min = min(db.grid.T(:));
        limits.theta_grid_max = max(db.grid.T(:));

        limits.v_min_design = max(limits.v_min_design, limits.v_grid_min + 0.02);
        limits.v_max_design = min(limits.v_max_design, limits.v_grid_max - 0.02);
        limits.omega_abs_design = min(limits.omega_abs_design, ...
            0.90 * max(abs([limits.omega_grid_min, limits.omega_grid_max])));
        limits.theta_abs_design = min(limits.theta_abs_design, ...
            0.98 * max(abs([limits.theta_grid_min, limits.theta_grid_max])));
    end
end
end

function local_validate_limits(limits, cfg)
if abs(limits.Ts - 0.01) > 1e-12
    warning('gen_agv_theta10_uniform_paths:TsNotDefault', ...
        'parameters().Ts is %.4f s; expected 0.01 s for the current dataset contract.', limits.Ts);
end
if rad2deg(limits.theta_abs_design) + 1e-9 < cfg.max_theta_abs_deg
    error('LPV theta design limit is %.2f deg, below requested %.2f deg.', ...
        rad2deg(limits.theta_abs_design), cfg.max_theta_abs_deg);
end
if limits.v_max_design <= limits.v_min_design
    error('Invalid velocity design range.');
end
end

function specs = local_build_specs(cfg, limits)
theta_centers = cfg.theta_edges_deg(1:end-1) + 0.5;
compound_variants = local_compound_variants();
short_variants = local_short_variants();
n_specs = cfg.long_path_count + numel(theta_centers) + numel(theta_centers);
n_specs = n_specs + double(cfg.include_true_zero_profile);
specs = repmat(local_spec_template(), n_specs, 1);
idx = 0;

for li = 1:cfg.long_path_count
    idx = idx + 1;
    specs(idx) = local_long_complete_spec(theta_centers, li, cfg, limits);
end

for bi = 1:numel(theta_centers)
    theta_deg = theta_centers(bi);
    variant = compound_variants(mod(bi - 1, numel(compound_variants)) + 1);
    idx = idx + 1;
    specs(idx) = local_compound_spec(theta_deg, bi, variant, cfg, limits);
end

for bi = 1:numel(theta_centers)
    theta_deg = theta_centers(bi);
    variant = short_variants(mod(bi - 1, numel(short_variants)) + 1);
    idx = idx + 1;
    specs(idx) = local_short_spec(theta_deg, bi, variant, cfg, limits);
end

if cfg.include_true_zero_profile
    idx = idx + 1;
    specs(idx) = local_true_zero_spec(cfg, limits);
end
specs = specs(1:idx);
end

function variants = local_compound_variants()
variants = repmat(struct('id', '', 'v0', NaN, 'radii', [], 'signs', [], ...
    'speed_events', []), 5, 1);
variants(1) = struct('id', 'v084_R06_08_LR', 'v0', 0.84, 'radii', [6, 8], ...
    'signs', [+1, -1], 'speed_events', []);
variants(2) = struct('id', 'v096_R08_10_RL', 'v0', 0.96, 'radii', [8, 10], ...
    'signs', [-1, +1], 'speed_events', []);
variants(3) = struct('id', 'v108_R10_12_LR', 'v0', 1.08, 'radii', [10, 12], ...
    'signs', [+1, -1], 'speed_events', []);
variants(4) = struct('id', 'v090_115_R12_16_RL', 'v0', 0.90, 'radii', [12, 16], ...
    'signs', [-1, +1], 'speed_events', [10.0, 13.0, 1.15; 25.0, 28.0, 0.85]);
variants(5) = struct('id', 'v116_R16_20_LR', 'v0', 1.16, 'radii', [16, 20], ...
    'signs', [+1, -1], 'speed_events', [12.0, 15.0, 0.92; 31.0, 34.0, 1.12]);
end

function variants = local_short_variants()
variants = repmat(struct('id', '', 'v0', NaN, 'radius', NaN, 'sign', NaN, ...
    'kind', ''), 6, 1);
variants(1) = struct('id', 'straight_accdec', 'v0', 0.92, 'radius', NaN, ...
    'sign', 0, 'kind', 'straight_accdec');
variants(2) = struct('id', 'left_R06', 'v0', 0.86, 'radius', 6.0, ...
    'sign', +1, 'kind', 'turn');
variants(3) = struct('id', 'right_R06', 'v0', 0.86, 'radius', 6.0, ...
    'sign', -1, 'kind', 'turn');
variants(4) = struct('id', 'left_R12', 'v0', 0.98, 'radius', 12.0, ...
    'sign', +1, 'kind', 'turn');
variants(5) = struct('id', 'right_R12', 'v0', 0.98, 'radius', 12.0, ...
    'sign', -1, 'kind', 'turn');
variants(6) = struct('id', 'theta_edge_speed_R16', 'v0', 1.04, 'radius', 16.0, ...
    'sign', 0, 'kind', 'theta_edge_speed');
end

function spec = local_long_complete_spec(theta_centers, long_id, cfg, limits)
spec = local_spec_template();
spec.name = sprintf('long_complete_%02d', long_id);
spec.tier = 'long_complete';
spec.T_end = cfg.long_path_duration_sec;

v_grid = [0.84, 0.96, 1.08, 1.16, 0.90, 1.02, 1.12, 1.00];
spec.v0 = min(max(v_grid(mod(long_id - 1, numel(v_grid)) + 1), ...
    limits.v_min_design), limits.v_max_design);

if mod(long_id, 2) == 1
    order = circshift(1:numel(theta_centers), [0, long_id - 1]);
else
    order = circshift(numel(theta_centers):-1:1, [0, long_id - 1]);
end
spec.theta0 = deg2rad(theta_centers(order(1)));
spec.theta_center_deg = NaN;
spec.theta_bin_id = NaN;
spec.theta_bin_low_deg = NaN;
spec.theta_bin_high_deg = NaN;
spec.variant_id = sprintf('permutation_%02d', long_id);
spec.radius_a_m = 6.0;
spec.radius_b_m = 20.0;
spec.turn_order = 'LRLR';
spec.events = {};

theta_ramp_sec = 0.80;
theta_step_sec = 7.00;
t_cur = 3.00;
for k = 2:numel(order)
    target = deg2rad(theta_centers(order(k)));
    spec.events{end+1} = local_event('theta', t_cur, t_cur + theta_ramp_sec, target);
    t_cur = t_cur + theta_step_sec;
end

speed_targets = [1.14, 0.82, 1.06, 0.92, 1.16];
speed_times = [18, 42; 48, 54; 78, 84; 108, 114; 132, 138];
for i = 1:size(speed_times, 1)
    target = speed_targets(mod(i + long_id - 2, numel(speed_targets)) + 1);
    spec.events{end+1} = local_event('speed', speed_times(i, 1), speed_times(i, 2), target);
end

radii = [6, 8, 10, 12, 14, 16, 18, 10];
signs = [+1, -1, +1, -1, -1, +1, -1, +1];
turn_starts = 10:17:129;
for j = 1:numel(turn_starts)
    radius_m = radii(mod(j + long_id - 2, numel(radii)) + 1);
    sgn = signs(mod(j + long_id - 2, numel(signs)) + 1);
    omega_abs = min(spec.v0 / radius_m, limits.omega_abs_design);
    omega = sgn * omega_abs;
    t0 = turn_starts(j);
    t1 = min(t0 + 9.0, spec.T_end - 2.0);
    spec.events{end+1} = local_event('omega', t0, t0 + cfg.turn_ramp_sec, omega);
    spec.events{end+1} = local_event('omega', t1, t1 + cfg.turn_ramp_sec, 0.0);
end

spec.recommended_injection_windows = {[12, 18], [36, 42], [62, 70], [88, 96], [118, 126]};
end

function spec = local_compound_spec(theta_deg, bin_id, variant, cfg, limits)
spec = local_spec_template();
spec.theta_center_deg = theta_deg;
spec.theta_bin_id = bin_id;
spec.theta_bin_low_deg = cfg.theta_edges_deg(bin_id);
spec.theta_bin_high_deg = cfg.theta_edges_deg(bin_id + 1);
spec.variant_id = variant.id;
spec.name = sprintf('compound_bin%02d_%s_%s', bin_id, local_theta_tag(theta_deg), variant.id);
spec.tier = 'compound_midlong';
spec.T_end = cfg.compound_profile_duration_sec;
spec.v0 = min(max(variant.v0, limits.v_min_design), limits.v_max_design);
spec.theta0 = deg2rad(theta_deg - 0.25);
spec.radius_a_m = variant.radii(1);
spec.radius_b_m = variant.radii(2);
spec.turn_order = local_turn_order_name(variant.signs);
spec.events = {};

for i = 1:size(variant.speed_events, 1)
    spec.events{end+1} = local_event('speed', variant.speed_events(i, 1), ...
        variant.speed_events(i, 2), variant.speed_events(i, 3));
end

spec.events{end+1} = local_event('theta', 7.0, 8.2, deg2rad(theta_deg + 0.25));
spec.events{end+1} = local_event('theta', 26.0, 27.2, deg2rad(theta_deg - 0.05));
spec.events{end+1} = local_event('theta', 33.0, 34.2, deg2rad(theta_deg + 0.10));
spec.events{end+1} = local_event('speed', 36.0, 39.0, min(max(spec.v0 + 0.10, limits.v_min_design), limits.v_max_design));
turn_blocks = [6.0, 12.0; 18.0, 24.0];
for j = 1:2
    radius_m = variant.radii(j);
    omega_abs = spec.v0 / radius_m;
    omega_abs = min(omega_abs, limits.omega_abs_design);
    omega = variant.signs(j) * omega_abs;
    spec.events{end+1} = local_event('omega', turn_blocks(j, 1), ...
        turn_blocks(j, 1) + cfg.turn_ramp_sec, omega);
    spec.events{end+1} = local_event('omega', turn_blocks(j, 2), ...
        turn_blocks(j, 2) + cfg.turn_ramp_sec, 0.0);
end
radius_m = mean(variant.radii);
omega_abs = min(spec.v0 / radius_m, limits.omega_abs_design);
omega = variant.signs(1) * omega_abs;
spec.events{end+1} = local_event('omega', 34.0, 34.0 + cfg.turn_ramp_sec, omega);
spec.events{end+1} = local_event('omega', 42.0, 42.0 + cfg.turn_ramp_sec, 0.0);

spec.recommended_injection_windows = {[3.0, 5.0], [13.2, 16.5], [25.2, 31.0], [35.0, 43.0]};
end

function spec = local_short_spec(theta_deg, bin_id, variant, cfg, limits)
spec = local_spec_template();
spec.name = sprintf('short_bin%02d_%s_%s', bin_id, local_theta_tag(theta_deg), variant.id);
spec.tier = 'short_specialty';
spec.T_end = cfg.short_profile_duration_sec;
spec.v0 = min(max(variant.v0, limits.v_min_design), limits.v_max_design);
spec.theta0 = deg2rad(theta_deg);
spec.theta_center_deg = theta_deg;
spec.theta_bin_id = bin_id;
spec.theta_bin_low_deg = cfg.theta_edges_deg(bin_id);
spec.theta_bin_high_deg = cfg.theta_edges_deg(bin_id + 1);
spec.variant_id = variant.id;
spec.radius_a_m = variant.radius;
spec.radius_b_m = variant.radius;
spec.turn_order = local_turn_order_name(variant.sign);
spec.events = {};

theta_lo = cfg.theta_edges_deg(bin_id) + 0.10;
theta_hi = cfg.theta_edges_deg(bin_id + 1) - 0.10;
theta_mid = theta_deg;
theta_q3 = min(theta_hi, theta_mid + 0.20);
spec.theta0 = deg2rad(theta_lo);
spec.events{end+1} = local_event('theta', 3.0, 4.0, deg2rad(theta_hi));
spec.events{end+1} = local_event('theta', 9.0, 10.0, deg2rad(theta_mid));
spec.events{end+1} = local_event('theta', 15.0, 16.0, deg2rad(theta_lo));
spec.events{end+1} = local_event('theta', 19.0, 20.0, deg2rad(theta_q3));

switch lower(variant.kind)
    case 'straight_accdec'
        spec.events{end+1} = local_event('speed', 4.0, 6.0, 1.16);
        spec.events{end+1} = local_event('speed', 13.0, 15.0, 0.80);
    case 'turn'
        omega_abs = min(spec.v0 / variant.radius, limits.omega_abs_design);
        omega = variant.sign * omega_abs;
        spec.events{end+1} = local_event('omega', 5.0, 5.0 + cfg.turn_ramp_sec, omega);
        spec.events{end+1} = local_event('omega', 16.0, 16.0 + cfg.turn_ramp_sec, 0.0);
    case 'theta_edge_speed'
        spec.events{end+1} = local_event('speed', 9.0, 11.0, 1.16);
        spec.events{end+1} = local_event('speed', 15.0, 17.0, 0.82);
    otherwise
        error('Unknown short variant kind: %s', variant.kind);
end
spec.recommended_injection_windows = {[3.0, 5.0], [9.0, 12.0], [16.0, 20.0]};
end

function spec = local_true_zero_spec(cfg, limits)
spec = local_spec_template();
spec.name = 'true_zero_hold_balanced_turn';
spec.tier = 'short_specialty';
spec.T_end = cfg.true_zero_profile_duration_sec;
spec.v0 = min(max(0.96, limits.v_min_design), limits.v_max_design);
spec.theta0 = 0.0;
spec.theta_center_deg = 0.0;
spec.theta_bin_id = 11;
spec.theta_bin_low_deg = 0.0;
spec.theta_bin_high_deg = 1.0;
spec.variant_id = 'zero_control';
spec.radius_a_m = 8.0;
spec.radius_b_m = 12.0;
spec.turn_order = 'LR';
spec.events = {};
spec.events{end+1} = local_event('omega', 5.0, 5.0 + cfg.turn_ramp_sec, spec.v0 / 8.0);
spec.events{end+1} = local_event('omega', 10.0, 10.0 + cfg.turn_ramp_sec, 0.0);
spec.events{end+1} = local_event('omega', 14.0, 14.0 + cfg.turn_ramp_sec, -spec.v0 / 12.0);
spec.events{end+1} = local_event('omega', 19.0, 19.0 + cfg.turn_ramp_sec, 0.0);
spec.events{end+1} = local_event('speed', 22.0, 24.0, 1.12);
spec.events{end+1} = local_event('speed', 27.0, 29.0, 0.88);
spec.recommended_injection_windows = {[3.0, 4.5], [11.2, 13.2], [20.0, 23.0], [25.0, 29.0]};
end

function spec = local_spec_template()
spec = struct();
spec.name = '';
spec.tier = '';
spec.T_end = NaN;
spec.v0 = NaN;
spec.theta0 = NaN;
spec.events = {};
spec.recommended_injection_windows = {};
spec.theta_bin_id = NaN;
spec.theta_bin_low_deg = NaN;
spec.theta_bin_high_deg = NaN;
spec.theta_center_deg = NaN;
spec.variant_id = '';
spec.radius_a_m = NaN;
spec.radius_b_m = NaN;
spec.turn_order = '';
end

function e = local_event(kind, t0, t1, value)
e = struct('kind', kind, 't0', t0, 't1', t1, 'value', value, 'aux', []);
end

function spec = local_clip_spec_to_limits(spec, limits)
spec.v0 = min(max(spec.v0, limits.v_min_design), limits.v_max_design);
spec.theta0 = min(max(spec.theta0, -limits.theta_abs_design), limits.theta_abs_design);
for i = 1:numel(spec.events)
    e = spec.events{i};
    switch lower(e.kind)
        case 'speed'
            e.value = min(max(e.value, limits.v_min_design), limits.v_max_design);
        case 'omega'
            e.value = min(max(e.value, -limits.omega_abs_design), limits.omega_abs_design);
        case 'theta'
            e.value = min(max(e.value, -limits.theta_abs_design), limits.theta_abs_design);
    end
    spec.events{i} = e;
end
end

function ref = local_generate_ref_from_spec(spec, params, cfg, limits)
Ts = params.Ts;
t = (0:Ts:spec.T_end)';
N = numel(t);

v = spec.v0 * ones(N, 1);
omega = zeros(N, 1);
theta = spec.theta0 * ones(N, 1);

for i = 1:numel(spec.events)
    e = spec.events{i};
    switch lower(e.kind)
        case 'speed'
            v = local_apply_level_event(t, v, e.t0, e.t1, e.value);
        case 'omega'
            omega = local_apply_level_event(t, omega, e.t0, e.t1, e.value);
        case 'theta'
            theta = local_apply_level_event(t, theta, e.t0, e.t1, e.value);
        otherwise
            error('Unknown event kind: %s', e.kind);
    end
end

v = min(max(v, limits.v_min_design), limits.v_max_design);
omega = min(max(omega, -limits.omega_abs_design), limits.omega_abs_design);
theta = min(max(theta, -limits.theta_abs_design), limits.theta_abs_design);

psi = zeros(N, 1);
X = zeros(N, 1);
Y = zeros(N, 1);
for k = 2:N
    psi(k) = local_normalize_angle(psi(k-1) + omega(k-1) * Ts);
    X(k) = X(k-1) + v(k-1) * Ts * cos(psi(k-1));
    Y(k) = Y(k-1) + v(k-1) * Ts * sin(psi(k-1));
end

e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);
rho_raw = [v, omega, theta];
rho = local_apply_first_order_filter(rho_raw, Ts, cfg.rho_filter_tau);

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

ref.meta = struct();
ref.meta.path_type = ['theta10_uniform_' spec.name];
ref.meta.training_path = true;
ref.meta.training_usage = 'AGV dual-steer theta10 uniform ModernTCN/GRU training';
ref.meta.tier = spec.tier;
ref.meta.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
ref.meta.version = 'AGV_THETA10_UNIFORM_PATH_V2';
ref.meta.author = 'LPV-MPC Project';
ref.meta.params.T_end = spec.T_end;
ref.meta.params.Ts = Ts;
ref.meta.params.v0 = spec.v0;
ref.meta.params.theta0_deg = rad2deg(spec.theta0);
ref.meta.params.rho_filter_tau = cfg.rho_filter_tau;
ref.meta.theta_bin_id = spec.theta_bin_id;
ref.meta.theta_bin_edges_deg = [spec.theta_bin_low_deg, spec.theta_bin_high_deg];
ref.meta.theta_center_deg = spec.theta_center_deg;
ref.meta.variant_id = spec.variant_id;
ref.meta.radius_pair_m = [spec.radius_a_m, spec.radius_b_m];
ref.meta.turn_order = spec.turn_order;
ref.meta.events = spec.events;
ref.meta.recommended_injection_windows = spec.recommended_injection_windows;
ref.meta.constraint_basis = struct( ...
    'v_design', [limits.v_min_design, limits.v_max_design], ...
    'omega_abs_design', limits.omega_abs_design, ...
    'theta_abs_design', limits.theta_abs_design, ...
    'F_cmd_range', [limits.F_cmd_min, limits.F_cmd_max], ...
    'omega_cmd_range', [limits.omega_cmd_min, limits.omega_cmd_max]);
end

function y = local_apply_level_event(t, y, t0, t1, target)
if t1 <= t0
    return;
end
y0_idx = find(t <= t0, 1, 'last');
if isempty(y0_idx)
    y_start = y(1);
else
    y_start = y(y0_idx);
end
idx_tr = t >= t0 & t <= t1;
s = (t(idx_tr) - t0) / max(t1 - t0, eps);
w = local_smoothstep(s);
y(idx_tr) = y_start + (target - y_start) .* w;
y(t > t1) = target;
end

function w = local_smoothstep(s)
s = min(max(s, 0), 1);
w = s.^2 .* (3 - 2*s);
end

function rho_filtered = local_apply_first_order_filter(rho_raw, Ts, tau)
[N, dim] = size(rho_raw);
alpha = Ts / (Ts + tau);
rho_filtered = zeros(N, dim);
rho_filtered(1, :) = rho_raw(1, :);
for k = 2:N
    rho_filtered(k, :) = alpha * rho_raw(k, :) + (1 - alpha) * rho_filtered(k-1, :);
end
end

function local_validate_ref(ref, limits)
if any(diff(ref.t) <= 0)
    error('ref.t must be strictly increasing.');
end
if any(ref.v_ref < limits.v_min_design - 1e-9) || any(ref.v_ref > limits.v_max_design + 1e-9)
    error('v_ref exceeds design range.');
end
if any(abs(ref.omega_ref) > limits.omega_abs_design + 1e-9)
    error('omega_ref exceeds design range.');
end
if any(abs(ref.theta_ref) > limits.theta_abs_design + 1e-9)
    error('theta_ref exceeds design range.');
end
end

function row = local_manifest_row_template()
row = struct();
row.index = NaN;
row.file_name = '';
row.path_file = '';
row.name = '';
row.tier = '';
row.variant_id = '';
row.T_end = NaN;
row.Ts = NaN;
row.theta_bin_id = NaN;
row.theta_bin_low_deg = NaN;
row.theta_bin_high_deg = NaN;
row.theta_center_deg = NaN;
row.theta_min_deg = NaN;
row.theta_max_deg = NaN;
row.v_min = NaN;
row.v_max = NaN;
row.omega_min = NaN;
row.omega_max = NaN;
row.radius_a_m = NaN;
row.radius_b_m = NaN;
row.turn_order = '';
row.n_recommended_windows = NaN;
end

function row = local_manifest_from_ref(index, file_name, out_file, spec, ref)
row = local_manifest_row_template();
row.index = index;
row.file_name = file_name;
row.path_file = out_file;
row.name = spec.name;
row.tier = spec.tier;
row.variant_id = spec.variant_id;
row.T_end = ref.t(end);
row.Ts = median(diff(ref.t));
row.theta_bin_id = spec.theta_bin_id;
row.theta_bin_low_deg = spec.theta_bin_low_deg;
row.theta_bin_high_deg = spec.theta_bin_high_deg;
row.theta_center_deg = spec.theta_center_deg;
row.theta_min_deg = min(rad2deg(ref.theta_ref));
row.theta_max_deg = max(rad2deg(ref.theta_ref));
row.v_min = min(ref.v_ref);
row.v_max = max(ref.v_ref);
row.omega_min = min(ref.omega_ref);
row.omega_max = max(ref.omega_ref);
row.radius_a_m = spec.radius_a_m;
row.radius_b_m = spec.radius_b_m;
row.turn_order = spec.turn_order;
row.n_recommended_windows = numel(spec.recommended_injection_windows);
end

function tag = local_theta_tag(theta_deg)
if theta_deg < 0
    prefix = 'm';
else
    prefix = 'p';
end
tag = sprintf('%s%04.1f', prefix, abs(theta_deg));
tag = strrep(tag, '.', 'p');
end

function name = local_turn_order_name(signs)
name = repmat('S', 1, numel(signs));
for i = 1:numel(signs)
    if signs(i) > 0
        name(i) = 'L';
    elseif signs(i) < 0
        name(i) = 'R';
    end
end
end

function a = local_normalize_angle(a)
a = atan2(sin(a), cos(a));
end

function local_visualize_ref(ref, name, figure_dir, figure_prefix)
fig = figure('Name', sprintf('theta10 path: %s', name), ...
    'Position', [100, 100, 1200, 700], 'Visible', 'off');

subplot(2, 3, 1);
plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.3);
axis equal; grid on; xlabel('X [m]'); ylabel('Y [m]');
title(strrep(name, '_', '\_'));

subplot(2, 3, 2);
plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('v [m/s]');

subplot(2, 3, 3);
plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('omega [rad/s]');

subplot(2, 3, 4);
plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('psi [deg]');

subplot(2, 3, 5);
plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.1);
grid on; xlabel('t [s]'); ylabel('theta [deg]');

subplot(2, 3, 6);
plot(ref.t, ref.rho(:,1), 'r-', 'LineWidth', 1.0); hold on;
plot(ref.t, ref.rho(:,2), 'g-', 'LineWidth', 1.0);
plot(ref.t, rad2deg(ref.rho(:,3)), 'b-', 'LineWidth', 1.0);
grid on; xlabel('t [s]'); ylabel('rho');
legend('v', 'omega', 'theta deg', 'Location', 'best');

out_png = fullfile(figure_dir, sprintf('%s%s_preview.png', figure_prefix, name));
saveas(fig, out_png);
close(fig);
end
