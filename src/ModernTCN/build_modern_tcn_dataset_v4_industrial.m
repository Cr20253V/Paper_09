function outputs = build_modern_tcn_dataset_v4_industrial(cfg)
%BUILD_MODERN_TCN_DATASET_V4_INDUSTRIAL Build the ModernTCN V4 data chain.
%
% Default behavior only generates reference paths. Full continuous
% simulation is intentionally opt-in because it runs Simulink many times.
%
% Example full build:
%   init_project;
%   cfg = struct('generate_train_data', true, 'prepare_dataset', true);
%   outputs = build_modern_tcn_dataset_v4_industrial(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
paths_dir = fullfile(root, 'data', 'paths');
data_tcn_dir = fullfile(root, 'data', 'tcn');

cfg.generate_paths = local_cfg(cfg, 'generate_paths', true);
cfg.generate_train_data = local_cfg(cfg, 'generate_train_data', false);
cfg.prepare_dataset = local_cfg(cfg, 'prepare_dataset', false);
cfg.make_figures = local_cfg(cfg, 'make_figures', false);
cfg.seed = local_cfg(cfg, 'seed', 20260504);
cfg.num_runs_per_path = local_cfg(cfg, 'num_runs_per_path', 4);
cfg.max_paths = local_cfg(cfg, 'max_paths', []);

outputs = struct();
outputs.path_pattern = fullfile(paths_dir, 'path_modern_tcn_v4_*.mat');
outputs.path_manifest = fullfile(paths_dir, 'path_modern_tcn_v4_manifest.csv');
outputs.train_data_file = fullfile(data_tcn_dir, 'ModernTCN_train_data_v4_industrial.mat');
outputs.dataset_file = fullfile(data_tcn_dir, 'ModernTCN_dataset_v4_industrial.mat');
outputs.scaler_file = fullfile(data_tcn_dir, 'ModernTCN_scaler_v4_industrial.mat');
outputs.split_file = fullfile(data_tcn_dir, 'ModernTCN_shared_run_split_v4_industrial.mat');
outputs.report_file = fullfile(data_tcn_dir, 'ModernTCN_prepare_dataset_v4_industrial_report.md');

if cfg.generate_paths
    local_generate_paths(root, cfg.seed, cfg.make_figures);
end

if cfg.generate_train_data
    train_cfg = struct();
    train_cfg.output_dir = data_tcn_dir;
    train_cfg.output_file = outputs.train_data_file;
    train_cfg.path_pattern = outputs.path_pattern;
    train_cfg.seed = cfg.seed;
    train_cfg.num_runs_per_path = cfg.num_runs_per_path;
    train_cfg.noise_on = local_cfg(cfg, 'noise_on', true);
    train_cfg.verbose = local_cfg(cfg, 'verbose', true);
    train_cfg.noise_profile = local_cfg(cfg, 'noise_profile', local_noise_profile());
    train_cfg.event_cfg = local_cfg(cfg, 'event_cfg', local_event_cfg());
    train_cfg.self_check = local_cfg(cfg, 'self_check', local_self_check());
    if ~isempty(cfg.max_paths)
        train_cfg.max_paths = cfg.max_paths;
    end
    outputs.train_data = TCN_gen_train_data(train_cfg);
end

if cfg.prepare_dataset
    prep_cfg = struct();
    prep_cfg.input_file = outputs.train_data_file;
    prep_cfg.output_file = outputs.dataset_file;
    prep_cfg.scaler_file = outputs.scaler_file;
    prep_cfg.split_file = outputs.split_file;
    prep_cfg.report_file = outputs.report_file;
    prep_cfg.transition_rich = true;
    prep_cfg.reuse_split_file = false;
    prep_cfg.seq_len = 128;
    prep_cfg.stride = 64;
    prep_cfg.steady_stride = 128;
    prep_cfg.transition_stride = 12;
    prep_cfg.transition_context_sec = 1.50;
    prep_cfg.main_min_purity = 0.80;
    prep_cfg.main_ambiguous_weight = 0.75;
    prep_cfg.theta_transition_range_deg = 1.00;
    prep_cfg.theta_transition_weight = 1.00;
    prep_cfg.turn_label_strategy = 'tail_majority';
    prep_cfg.turn_tail_sec = 0.50;
    prep_cfg.turn_min_purity = 0.70;
    prep_cfg.turn_ambiguous_weight = 0.60;
    outputs.dataset = TCN_prepare_dataset(prep_cfg);
end
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function s = local_noise_profile()
s = struct();
s.clean_ratio = 0.25;
s.noisy_scales = [1.0, 1.5];
s.noisy_probs = [0.70, 0.30];
end

function local_generate_paths(root, seed, make_figures)
gen_tcn_training_paths_cfg = struct(); %#ok<NASGU>
gen_tcn_training_paths_cfg.seed = seed;
gen_tcn_training_paths_cfg.rho_filter_tau = 0.4;
gen_tcn_training_paths_cfg.make_figures = make_figures;
gen_tcn_training_paths_cfg.profile_set = 'v4_industrial';
gen_tcn_training_paths_cfg.path_prefix = 'path_modern_tcn_v4_';
gen_tcn_training_paths_cfg.manifest_name = 'path_modern_tcn_v4_manifest.csv';
gen_tcn_training_paths_cfg.figure_prefix = 'path_modern_tcn_v4_';
run(fullfile(root, 'src', 'paths', 'gen_tcn_training_paths.m'));
end

function s = local_event_cfg()
s = struct();
s.primary_types = {'slip', 'load_change', 'stall'};
s.primary_probs = [0.25, 0.35, 0.40];
s.extra_event_prob = 0.45;
s.window_padding = 0.15;
s.slip = struct('duration_range', [1.2, 2.4], 'gamma_range', [0.45, 0.78]);
s.load_change = struct('duration_range', [1.5, 3.2], 'load_range', [70, 165]);
s.stall = struct('duration_range', [1.5, 3.0], 'load_range', [210, 315]);
end

function s = local_self_check()
s = struct();
s.min_slope_ratio = 0.12;
s.min_turn_ratio = 0.08;
s.min_transition_window_hits = 20;
end
