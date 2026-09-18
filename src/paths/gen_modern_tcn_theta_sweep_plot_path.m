function out = gen_modern_tcn_theta_sweep_plot_path(cfg)
%GEN_MODERN_TCN_THETA_SWEEP_PLOT_PATH Generate a controlled theta sweep path.
%
% The path is only for paper plotting and diagnostics. It is not a training
% path. Each theta value can appear in multiple held-out variants so the
% scatter plot contains multiple input windows per true slope angle.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
params = parameters();
Ts = local_default(cfg, 'Ts', params.Ts);
theta_deg = local_default(cfg, 'theta_deg', -10:0.1:10);
segment_duration = local_default(cfg, 'segment_duration', 5.0);
v_ref = local_default(cfg, 'v_ref', 0.9);
num_repeats = local_default(cfg, 'num_repeats', 1);
v_ref_values = local_default(cfg, 'v_ref_values', v_ref);
omega_ref_values = local_default(cfg, 'omega_ref_values', 0);
segment_duration_values = local_default(cfg, 'segment_duration_values', segment_duration);
variant_table = local_default(cfg, 'variant_table', []);
shuffle_theta = local_default(cfg, 'shuffle_theta', false);
order_mode = lower(char(string(local_default(cfg, 'order_mode', 'repeat_major'))));
seed = local_default(cfg, 'seed', 20260510);
output_file = local_default(cfg, 'output_file', fullfile(root, 'data', 'paths', ...
    'path_modern_tcn_theta_sweep_plot_v1.mat'));

theta_deg = round(double(theta_deg(:).') * 10) / 10;
num_repeats = max(1, round(double(num_repeats)));
v_ref_values = double(v_ref_values(:).');
omega_ref_values = double(omega_ref_values(:).');
segment_duration_values = double(segment_duration_values(:).');
variants = local_variants(v_ref_values, omega_ref_values, segment_duration_values, variant_table, segment_duration);
n_seg = numel(theta_deg) * num_repeats;
rng(seed, 'twister');

theta = zeros(0, 1);
v = zeros(0, 1);
omega = zeros(0, 1);
segment = repmat(local_segment_template(), n_seg, 1);

seg_idx = 0;
switch order_mode
    case {'repeat_major', 'variant_major'}
        for r_idx = 1:num_repeats
            variant_idx = mod(r_idx - 1, numel(variants)) + 1;
            var = variants(variant_idx);
            if shuffle_theta
                theta_order = theta_deg(randperm(numel(theta_deg)));
            else
                theta_order = theta_deg;
            end
            for j = 1:numel(theta_order)
                [theta, v, omega, segment, seg_idx] = local_append_segment( ...
                    theta, v, omega, segment, seg_idx, theta_order(j), ...
                    r_idx, variant_idx, var, Ts);
            end
        end
    case {'theta_major', 'interleave_variants', 'interleaved'}
        if shuffle_theta
            theta_order = theta_deg(randperm(numel(theta_deg)));
        else
            theta_order = theta_deg;
        end
        for j = 1:numel(theta_order)
            for r_idx = 1:num_repeats
                variant_idx = mod(r_idx - 1, numel(variants)) + 1;
                var = variants(variant_idx);
                [theta, v, omega, segment, seg_idx] = local_append_segment( ...
                    theta, v, omega, segment, seg_idx, theta_order(j), ...
                    r_idx, variant_idx, var, Ts);
            end
        end
    otherwise
        error('ThetaSweepPath:BadOrderMode', ...
            'order_mode must be repeat_major or theta_major, got %s', order_mode);
end

segment = segment(1:seg_idx);

N = numel(theta);
t = (0:(N - 1)).' * Ts;
psi = cumtrapz(t, omega);
X = cumtrapz(t, v .* cos(psi));
Y = cumtrapz(t, v .* sin(psi));
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
ref.rho = [v, omega, theta];
ref.time = t;
ref.signals = struct();
ref.signals.values = [X, Y, psi, v, omega, theta, e_y_ref, e_psi_ref, e_v_ref];
ref.signals.dimensions = 9;
ref.meta = struct();
ref.meta.path_type = 'path_modern_tcn_theta_sweep_plot_v1';
ref.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ref.meta.version = 'ModernTCN_THETA_SWEEP_PLOT_V1';
ref.meta.author = 'LPV-MPC Project';
ref.meta.training_path = 0;
ref.meta.paper_plot_dataset = 1;
ref.meta.design_goal = 'Controlled straight-line slope sweep for ModernTCN theta regression plotting.';
ref.meta.params = struct();
ref.meta.params.Ts = Ts;
ref.meta.params.v_ref = v_ref;
ref.meta.params.v_ref_values = v_ref_values;
ref.meta.params.omega_ref_values = omega_ref_values;
ref.meta.params.segment_duration = segment_duration;
ref.meta.params.segment_duration_values = segment_duration_values;
ref.meta.params.variant_table_enabled = ~isempty(variant_table);
ref.meta.params.variant_names = {variants.name};
ref.meta.params.num_repeats = num_repeats;
ref.meta.params.shuffle_theta = logical(shuffle_theta);
ref.meta.params.order_mode = order_mode;
ref.meta.params.seed = seed;
ref.meta.params.theta_min_deg = min(theta_deg);
ref.meta.params.theta_max_deg = max(theta_deg);
ref.meta.params.theta_step_deg = median(diff(theta_deg));
ref.meta.params.num_segments = n_seg;
ref.meta.segments = segment;
ref.meta.notes = { ...
    'This path is a held-out plotting/evaluation path, not a training path.', ...
    'Use steady-state tail windows from each segment for theta true-vs-predicted scatter.', ...
    'Multiple repeats can vary speed, curvature, segment duration, and theta order for richer scatter coverage.'};

out_dir = fileparts(output_file);
if ~isempty(out_dir) && exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
save(output_file, 'ref');

out = struct();
out.ref = ref;
out.output_file = output_file;
out.theta_deg = theta_deg(:);
out.segment_duration = segment_duration;
out.v_ref = v_ref;
out.num_repeats = num_repeats;
out.v_ref_values = v_ref_values;
out.omega_ref_values = omega_ref_values;
out.segment_duration_values = segment_duration_values;

fprintf('[theta sweep path] wrote %s\n', output_file);
fprintf('  theta: %.1f:%.1f:%.1f deg | repeats=%d | segments=%d | T=%.2f s\n', ...
    min(theta_deg), median(diff(theta_deg)), max(theta_deg), num_repeats, n_seg, t(end));
end

function [theta, v, omega, segment, seg_idx] = local_append_segment( ...
    theta, v, omega, segment, seg_idx, theta_deg, repeat_idx, variant_idx, var, Ts)
N_seg = max(2, round(var.segment_duration / Ts));
seg_idx = seg_idx + 1;
i0 = numel(theta) + 1;
i1 = i0 + N_seg - 1;
theta(i0:i1, 1) = deg2rad(theta_deg);
v(i0:i1, 1) = var.v_ref;
omega(i0:i1, 1) = var.omega_ref;

segment(seg_idx).idx = seg_idx;
segment(seg_idx).theta_deg = theta_deg;
segment(seg_idx).t0 = (i0 - 1) * Ts;
segment(seg_idx).t1 = (i1 - 1) * Ts;
segment(seg_idx).sample_start = i0;
segment(seg_idx).sample_end = i1;
segment(seg_idx).repeat_idx = repeat_idx;
segment(seg_idx).variant_idx = variant_idx;
segment(seg_idx).variant_name = var.name;
segment(seg_idx).v_ref = var.v_ref;
segment(seg_idx).omega_ref = var.omega_ref;
segment(seg_idx).radius_m = var.radius_m;
segment(seg_idx).segment_duration = N_seg * Ts;
end

function segment = local_segment_template()
segment = struct('idx', NaN, 'theta_deg', NaN, 't0', NaN, 't1', NaN, ...
    'sample_start', NaN, 'sample_end', NaN, 'repeat_idx', NaN, ...
    'variant_idx', NaN, 'variant_name', "", 'v_ref', NaN, ...
    'omega_ref', NaN, 'radius_m', NaN, ...
    'segment_duration', NaN);
end

function variants = local_variants(v_values, omega_values, duration_values, variant_table, default_duration)
if ~isempty(variant_table)
    variants = local_variant_table(variant_table, default_duration);
    return;
end

n = max(1, numel(v_values) * numel(omega_values) * numel(duration_values));
variants = repmat(local_variant_template(), n, 1);
k = 0;
for i = 1:numel(v_values)
    for j = 1:numel(omega_values)
        for d = 1:numel(duration_values)
            k = k + 1;
            variants(k).name = sprintf('v%.2f_w%+.3f_T%.1f', ...
                v_values(i), omega_values(j), duration_values(d));
            variants(k).v_ref = v_values(i);
            variants(k).omega_ref = omega_values(j);
            variants(k).segment_duration = duration_values(d);
            if abs(omega_values(j)) > 1e-9
                variants(k).radius_m = abs(v_values(i) / omega_values(j));
            else
                variants(k).radius_m = Inf;
            end
        end
    end
end
end

function variants = local_variant_table(variant_table, default_duration)
if istable(variant_table)
    variant_table = table2struct(variant_table);
end
if ~isstruct(variant_table)
    error('ThetaSweepPath:BadVariantTable', ...
        'variant_table must be a struct array or table.');
end

variant_table = variant_table(:);
variants = repmat(local_variant_template(), numel(variant_table), 1);
for i = 1:numel(variant_table)
    row = variant_table(i);
    if ~isfield(row, 'v_ref') || isempty(row.v_ref) || ~isfield(row, 'omega_ref') || isempty(row.omega_ref)
        error('ThetaSweepPath:BadVariantTable', ...
            'Each variant_table row must define v_ref and omega_ref.');
    end
    variants(i).v_ref = double(row.v_ref);
    variants(i).omega_ref = double(row.omega_ref);
    if isfield(row, 'segment_duration') && ~isempty(row.segment_duration)
        variants(i).segment_duration = double(row.segment_duration);
    else
        variants(i).segment_duration = double(default_duration);
    end
    if isfield(row, 'name') && ~isempty(row.name)
        variants(i).name = string(row.name);
    else
        variants(i).name = sprintf('variant_%02d', i);
    end
    if isfield(row, 'radius_m') && ~isempty(row.radius_m)
        variants(i).radius_m = double(row.radius_m);
    elseif abs(variants(i).omega_ref) > 1e-9
        variants(i).radius_m = abs(variants(i).v_ref / variants(i).omega_ref);
    else
        variants(i).radius_m = Inf;
    end
end
end

function variant = local_variant_template()
variant = struct('name', "", 'v_ref', NaN, 'omega_ref', NaN, ...
    'radius_m', NaN, 'segment_duration', NaN);
end

function v = local_default(cfg, name, default_value)
if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
    v = cfg.(name);
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
