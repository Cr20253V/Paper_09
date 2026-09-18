function result = run_modern_tcn_theta_sweep_multicond_paper_v1(regenerate)
%RUN_MODERN_TCN_THETA_SWEEP_MULTICOND_PAPER_V1 Generate the paper theta scatter set.
%
% This held-out plotting set repeats each true slope under several mild
% speed/curvature conditions. It is not used for training.

if nargin < 1 || isempty(regenerate)
    regenerate = false;
end

if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
tag = 'modern_tcn_theta10_uniform_h0_v2_seed21_multicond_paper_v1';

variants = struct( ...
    'name', {'straight_v080', 'straight_v095', 'straight_v115', ...
        'left_R40_v095', 'right_R40_v095', ...
        'left_R30_v105', 'right_R30_v105'}, ...
    'v_ref', {0.80, 0.95, 1.15, 0.95, 0.95, 1.05, 1.05}, ...
    'omega_ref', {0, 0, 0, 0.95/40, -0.95/40, 1.05/30, -1.05/30}, ...
    'segment_duration', {3.2, 3.2, 3.2, 3.2, 3.2, 3.2, 3.2});

cfg = struct();
cfg.paper_scatter_preset = 'none';
cfg.seed = 21;
cfg.output_dir = fullfile(root, 'results', 'paper', ...
    'modern_tcn_theta_sweep_plot', tag);
cfg.path_file = fullfile(root, 'data', 'paths', ...
    'path_modern_tcn_theta_sweep_multicond_paper_v1.mat');
cfg.data_file = fullfile(cfg.output_dir, ...
    'ModernTCN_theta_sweep_multicond_paper_v1_data.mat');

cfg.regenerate_path = logical(regenerate);
cfg.regenerate_data = logical(regenerate);
cfg.theta_deg = -10:1:10;
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

cfg.eval_tail_sec = 1.2;
cfg.eval_tail_margin_sec = 0.10;
cfg.eval_stride_sec = 0.10;
cfg.scatter_metric_source = 'window';
cfg.show_segment_median = false;
cfg.marker_size_window = 9;
cfg.marker_alpha_window = 0.18;

result = eval_modern_tcn_theta_sweep_plot(cfg);
end
