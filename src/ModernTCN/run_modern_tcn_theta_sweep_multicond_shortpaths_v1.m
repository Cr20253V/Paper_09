function result = run_modern_tcn_theta_sweep_multicond_shortpaths_v1(mode, regenerate)
%RUN_MODERN_TCN_THETA_SWEEP_MULTICOND_SHORTPATHS_V1 Dense paper scatter on short paths.
%
% mode:
%   'smoke' - small validation set
%   'full'  - theta = -10:0.1:10 deg

if nargin < 1 || isempty(mode)
    mode = 'full';
end
if nargin < 2 || isempty(regenerate)
    regenerate = false;
end

if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
mode = lower(char(string(mode)));
variants = local_variants();

switch mode
    case {'smoke', 'test'}
        theta_deg = 9.5:0.1:10;
        tag = 'modern_tcn_theta10_uniform_h0_v2_seed21_multicond_shortpaths_v1_smoke';
        path_tag = 'modern_tcn_theta_sweep_multicond_shortpaths_v1_smoke';
        marker_size = 9;
        marker_alpha = 0.18;
    case {'full', 'theta0p1'}
        theta_deg = -10:0.1:10;
        tag = 'modern_tcn_theta10_uniform_h0_v2_seed21_multicond_shortpaths_v1_theta0p1';
        path_tag = 'modern_tcn_theta_sweep_multicond_shortpaths_v1_theta0p1';
        marker_size = 6;
        marker_alpha = 0.08;
    otherwise
        error('ShortPathThetaSweep:BadMode', 'mode must be smoke or full, got %s', mode);
end

path_dir = fullfile(root, 'data', 'paths', path_tag);
path_prefix = ['path_' path_tag];
manifest_file = fullfile(path_dir, [path_prefix '_manifest.csv']);

if logical(regenerate) || exist(manifest_file, 'file') ~= 2
    path_cfg = struct();
    path_cfg.output_dir = path_dir;
    path_cfg.path_prefix = path_prefix;
    path_cfg.theta_deg = theta_deg;
    path_cfg.theta_per_path = 2;
    path_cfg.segment_duration = 3.2;
    path_cfg.v_ref = 0.95;
    path_cfg.num_repeats = numel(variants);
    path_cfg.variant_table = variants;
    path_cfg.order_mode = 'repeat_major';
    path_cfg.shuffle_theta = false;
    path_cfg.seed = 20260513;
    path_out = gen_modern_tcn_theta_sweep_short_paths(path_cfg);
    path_files = path_out.path_files;
else
    path_files = local_manifest_path_files(manifest_file);
end

cfg = struct();
cfg.paper_scatter_preset = 'none';
cfg.seed = 21;
cfg.output_dir = fullfile(root, 'results', 'paper', ...
    'modern_tcn_theta_sweep_plot', tag);
cfg.path_files = path_files;
cfg.path_file = path_files{1};
cfg.data_file = fullfile(cfg.output_dir, ...
    ['ModernTCN_theta_sweep_' mode '_shortpaths_v1_data.mat']);

cfg.regenerate_path = false;
cfg.regenerate_data = logical(regenerate);
cfg.theta_deg = theta_deg;
cfg.segment_duration = 3.2;
cfg.v_ref = 0.95;
cfg.path_num_repeats = numel(variants);
cfg.path_variant_table = variants;
cfg.path_order_mode = 'repeat_major';
cfg.path_shuffle_theta = false;
cfg.path_seed = 20260513;
cfg.data_seed = 20260513;
cfg.num_runs_per_path = 1;
cfg.data_noise_on = false;

cfg.eval_tail_sec = 0.7;
cfg.eval_tail_margin_sec = 0.10;
cfg.eval_stride_sec = 0.10;
cfg.scatter_metric_source = 'window';
cfg.show_segment_median = false;
cfg.marker_size_window = marker_size;
cfg.marker_alpha_window = marker_alpha;

result = eval_modern_tcn_theta_sweep_plot(cfg);
end

function variants = local_variants()
variants = struct( ...
    'name', {'straight_v080', 'straight_v095', 'straight_v115', ...
        'left_R40_v095', 'right_R40_v095', ...
        'left_R30_v105', 'right_R30_v105'}, ...
    'v_ref', {0.80, 0.95, 1.15, 0.95, 0.95, 1.05, 1.05}, ...
    'omega_ref', {0, 0, 0, 0.95/40, -0.95/40, 1.05/30, -1.05/30}, ...
    'segment_duration', {3.2, 3.2, 3.2, 3.2, 3.2, 3.2, 3.2});
end

function path_files = local_manifest_path_files(manifest_file)
T = readtable(manifest_file, 'TextType', 'string', 'Delimiter', ',');
if ~ismember('path_file', T.Properties.VariableNames)
    error('ShortPathThetaSweep:BadManifest', 'Manifest has no path_file column: %s', manifest_file);
end
path_files = cellstr(T.path_file(:));
missing = path_files(cellfun(@(p) exist(p, 'file') ~= 2, path_files));
if ~isempty(missing)
    error('ShortPathThetaSweep:MissingPathFile', ...
        'Manifest references missing path file: %s', missing{1});
end
end
