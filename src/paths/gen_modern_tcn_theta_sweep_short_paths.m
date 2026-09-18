function out = gen_modern_tcn_theta_sweep_short_paths(cfg)
%GEN_MODERN_TCN_THETA_SWEEP_SHORT_PATHS Generate short held-out theta sweep paths.
%
% The output is for paper plotting diagnostics, not for training. It splits
% a dense theta sweep into short path files so each Simulink run remains
% within the recommended duration range.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
theta_deg = local_default(cfg, 'theta_deg', -10:0.1:10);
theta_per_path = max(1, round(double(local_default(cfg, 'theta_per_path', 2))));
output_dir = local_default(cfg, 'output_dir', fullfile(root, 'data', 'paths', ...
    'modern_tcn_theta_sweep_short_paths_v1'));
path_prefix = char(string(local_default(cfg, 'path_prefix', ...
    'path_modern_tcn_theta_sweep_short_v1')));
segment_duration = local_default(cfg, 'segment_duration', 3.2);
v_ref = local_default(cfg, 'v_ref', 0.95);
num_repeats = local_default(cfg, 'num_repeats', 1);
variant_table = local_default(cfg, 'variant_table', []);
order_mode = local_default(cfg, 'order_mode', 'repeat_major');
shuffle_theta = local_default(cfg, 'shuffle_theta', false);
seed = local_default(cfg, 'seed', 20260513);

theta_deg = round(double(theta_deg(:).') * 10) / 10;
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

n_path = ceil(numel(theta_deg) / theta_per_path);
path_files = cell(n_path, 1);
manifest = repmat(local_manifest_row(), n_path, 1);

for p = 1:n_path
    i0 = (p - 1) * theta_per_path + 1;
    i1 = min(numel(theta_deg), p * theta_per_path);
    theta_chunk = theta_deg(i0:i1);
    output_file = fullfile(output_dir, sprintf('%s_%03d_%s_%s.mat', ...
        path_prefix, p, local_theta_tag(theta_chunk(1)), local_theta_tag(theta_chunk(end))));

    path_cfg = struct();
    path_cfg.output_file = output_file;
    path_cfg.theta_deg = theta_chunk;
    path_cfg.segment_duration = segment_duration;
    path_cfg.v_ref = v_ref;
    path_cfg.num_repeats = num_repeats;
    path_cfg.variant_table = variant_table;
    path_cfg.order_mode = order_mode;
    path_cfg.shuffle_theta = shuffle_theta;
    path_cfg.seed = seed + p - 1;
    path_out = gen_modern_tcn_theta_sweep_plot_path(path_cfg);

    path_files{p} = output_file;
    manifest(p).path_idx = p;
    manifest(p).path_file = string(output_file);
    manifest(p).theta_start_deg = theta_chunk(1);
    manifest(p).theta_end_deg = theta_chunk(end);
    manifest(p).theta_count = numel(theta_chunk);
    manifest(p).segment_count = numel(path_out.ref.meta.segments);
    manifest(p).stop_time_sec = double(path_out.ref.t(end));
end

manifest_table = struct2table(manifest);
manifest_file = fullfile(output_dir, sprintf('%s_manifest.csv', path_prefix));
writetable(manifest_table, manifest_file);

out = struct();
out.path_files = path_files;
out.manifest_table = manifest_table;
out.manifest_file = manifest_file;
out.output_dir = output_dir;
out.theta_deg = theta_deg(:);
out.theta_per_path = theta_per_path;
out.num_paths = n_path;

fprintf('[theta sweep short paths] wrote %d paths to %s\n', n_path, output_dir);
fprintf('  theta: %.1f:%.1f:%.1f deg | theta/path=%d | manifest=%s\n', ...
    min(theta_deg), median(diff(theta_deg)), max(theta_deg), theta_per_path, manifest_file);
end

function row = local_manifest_row()
row = struct('path_idx', NaN, 'path_file', "", 'theta_start_deg', NaN, ...
    'theta_end_deg', NaN, 'theta_count', NaN, 'segment_count', NaN, ...
    'stop_time_sec', NaN);
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
