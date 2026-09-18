function outputs = build_agv_theta10_uniform_dataset(cfg)
%BUILD_AGV_THETA10_UNIFORM_DATASET Configure the theta10 h0 data chain.
%
% Default behavior is intentionally non-destructive: it only returns the
% planned file names and does not generate paths, run Simulink, or prepare a
% dataset unless the corresponding cfg flags are set true.
%
% Full build command after review:
%   init_project;
%   cfg = struct('generate_paths', true, 'generate_train_data', true, ...
%       'prepare_dataset', true, 'coverage_report', true, ...
%       'fail_on_coverage_violation', true);
%   outputs = build_agv_theta10_uniform_dataset(cfg);

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
paths_root = fullfile(root, 'data', 'paths');
data_tcn_dir = fullfile(root, 'data', 'tcn');
results_root = fullfile(root, 'results', 'modern_tcn');

cfg.tag = local_cfg(cfg, 'tag', 'agv_dualsteer_theta10_uniform_conf_h0_v3_passive17_plus_all5');
cfg.path_tag = local_cfg(cfg, 'path_tag', 'agv_theta10_uniform_v2');
cfg.generate_paths = local_cfg(cfg, 'generate_paths', false);
cfg.generate_train_data = local_cfg(cfg, 'generate_train_data', false);
cfg.prepare_dataset = local_cfg(cfg, 'prepare_dataset', false);
cfg.coverage_report = local_cfg(cfg, 'coverage_report', false);
cfg.make_figures = local_cfg(cfg, 'make_figures', false);
cfg.seed = local_cfg(cfg, 'seed', 20260511);
cfg.num_runs_per_path = local_cfg(cfg, 'num_runs_per_path', 2);
cfg.max_paths = local_cfg(cfg, 'max_paths', []);
cfg.noise_on = local_cfg(cfg, 'noise_on', true);
cfg.verbose = local_cfg(cfg, 'verbose', true);
cfg.path_duration_warn_range = local_cfg(cfg, 'path_duration_warn_range', [16, 180]);
cfg.use_manifest_paths = local_cfg(cfg, 'use_manifest_paths', true);
cfg.fail_on_coverage_violation = local_cfg(cfg, 'fail_on_coverage_violation', false);

paths_dir = fullfile(paths_root, cfg.path_tag);
path_prefix = [cfg.path_tag '_'];

outputs = struct();
outputs.tag = cfg.tag;
outputs.path_tag = cfg.path_tag;
outputs.feature_contract = extract_passive_features('contract');
outputs.paths_dir = paths_dir;
outputs.path_pattern = fullfile(paths_dir, [path_prefix '*.mat']);
outputs.path_manifest = fullfile(paths_dir, [cfg.path_tag '_manifest.csv']);
outputs.train_data_file = fullfile(data_tcn_dir, ['ModernTCN_train_data_' cfg.tag '.mat']);
outputs.dataset_file = fullfile(data_tcn_dir, ['ModernTCN_dataset_' cfg.tag '.mat']);
outputs.scaler_file = fullfile(data_tcn_dir, ['ModernTCN_scaler_' cfg.tag '.mat']);
outputs.split_file = fullfile(data_tcn_dir, ['ModernTCN_shared_run_split_' cfg.tag '.mat']);
outputs.prepare_report_file = fullfile(data_tcn_dir, ['ModernTCN_prepare_dataset_' cfg.tag '_report.md']);
outputs.contract_file = fullfile(data_tcn_dir, ['ModernTCN_dataset_' cfg.tag '_contract.json']);
outputs.coverage_report_file = fullfile(results_root, ['ModernTCN_dataset_' cfg.tag '_coverage.md']);

if cfg.generate_paths
    path_cfg = struct();
    path_cfg.tag = cfg.path_tag;
    path_cfg.output_dir = paths_dir;
    path_cfg.manifest_file = outputs.path_manifest;
    path_cfg.path_prefix = path_prefix;
    path_cfg.figure_dir = fullfile(root, 'figures', 'paths', cfg.path_tag);
    path_cfg.figure_prefix = [cfg.path_tag '_'];
    path_cfg.seed = cfg.seed;
    path_cfg.write_files = true;
    path_cfg.make_figures = cfg.make_figures;
    path_cfg.verbose = cfg.verbose;
    outputs.path_manifest_table = gen_agv_theta10_uniform_paths(path_cfg);
end

if cfg.generate_train_data
    train_cfg = struct();
    train_cfg.output_dir = data_tcn_dir;
    train_cfg.output_file = outputs.train_data_file;
    train_cfg.path_pattern = outputs.path_pattern;
    if cfg.use_manifest_paths
        train_cfg.path_files = local_manifest_path_files(outputs.path_manifest);
        if ~isempty(cfg.max_paths)
            train_cfg.path_files = train_cfg.path_files(1:min(numel(train_cfg.path_files), cfg.max_paths));
        end
        outputs.train_path_files = train_cfg.path_files;
    end
    train_cfg.seed = cfg.seed;
    train_cfg.num_runs_per_path = cfg.num_runs_per_path;
    train_cfg.noise_on = cfg.noise_on;
    train_cfg.verbose = cfg.verbose;
    train_cfg.noise_profile = local_noise_profile();
    train_cfg.event_cfg = local_event_cfg();
    train_cfg.self_check = local_train_self_check();
    train_cfg.label_cfg = local_label_cfg();
    train_cfg.path_duration_warn_range = cfg.path_duration_warn_range;
    if isfield(cfg, 'plant_revision') && ~isempty(cfg.plant_revision)
        train_cfg.plant_revision = cfg.plant_revision;
    end
    if ~isempty(cfg.max_paths) && ~cfg.use_manifest_paths
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
    prep_cfg.report_file = outputs.prepare_report_file;
    prep_cfg.contract_file = outputs.contract_file;
    prep_cfg.reuse_split_file = false;
    prep_cfg.split_strategy = 'stratified';
    prep_cfg.split_search_trials = local_cfg(cfg, 'split_search_trials', 40000);
    prep_cfg.seq_len = 128;
    prep_cfg.stride = 64;
    prep_cfg.skip_initial_sec = 1.0;
    prep_cfg.transition_rich = true;
    prep_cfg.steady_stride = 96;
    prep_cfg.transition_stride = 16;
    prep_cfg.transition_context_sec = 1.25;
    prep_cfg.main_min_purity = 0.80;
    prep_cfg.main_ambiguous_weight = 0.70;
    prep_cfg.turn_label_strategy = 'tail_majority';
    prep_cfg.turn_tail_sec = 0.50;
    prep_cfg.turn_min_purity = 0.70;
    prep_cfg.turn_ambiguous_weight = 0.60;
    prep_cfg.theta_transition_range_deg = 0.50;
    prep_cfg.theta_transition_weight = 1.00;
    prep_cfg.theta_event_range_deg = 0.30;
    prep_cfg.theta_event_window_sec = 0.50;
    prep_cfg.theta_split_edges_deg = -10:1:10;
    prep_cfg.theta_split_bin_weight = 14.0;
    prep_cfg.theta_split_low_bin_penalty = 55.0;
    prep_cfg.theta_split_imbalance_penalty = 30.0;
    prep_cfg.theta_split_min_ratio_of_target = 0.70;
    prep_cfg.theta_split_target_imbalance = 1.30;
    prep_cfg.theta_balance_after_split = true;
    prep_cfg.theta_balance_max_imbalance = 1.45;
    prep_cfg.turn_balance_after_split = true;
    prep_cfg.turn_balance_min_lr_balance = 0.90;
    prep_cfg.theta_mask_strategy = 'nonstall_full_range';
    prep_cfg.horizon_steps = 0;
    prep_cfg.seed = cfg.seed;
    prep_cfg.train_ratio = local_cfg(cfg, 'train_ratio', 0.70);
    prep_cfg.val_ratio = local_cfg(cfg, 'val_ratio', 0.15);
    prep_cfg.test_ratio = local_cfg(cfg, 'test_ratio', 0.15);
    prep_cfg.verbose = cfg.verbose;
    outputs.dataset = TCN_prepare_dataset(prep_cfg);
end

if cfg.coverage_report
    gate_cfg = local_coverage_gate_cfg(cfg);
    outputs.coverage = summarize_agv_theta10_uniform_coverage( ...
        outputs.dataset_file, outputs.coverage_report_file, gate_cfg);
end

if cfg.verbose && ~cfg.generate_paths && ~cfg.generate_train_data && ...
        ~cfg.prepare_dataset && ~cfg.coverage_report
    fprintf('\n[theta10 build] No generation flags were enabled. Planned outputs only.\n');
    fprintf('  paths     : %s\n', outputs.path_pattern);
    fprintf('  train data: %s\n', outputs.train_data_file);
    fprintf('  dataset   : %s\n', outputs.dataset_file);
    fprintf('  coverage  : %s\n', outputs.coverage_report_file);
end
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function path_files = local_manifest_path_files(manifest_file)
if exist(manifest_file, 'file') ~= 2
    error('build_agv_theta10_uniform_dataset:MissingManifest', ...
        'Path manifest not found: %s', manifest_file);
end
manifest = readtable(manifest_file, 'TextType', 'string');
if ~ismember('path_file', manifest.Properties.VariableNames)
    error('build_agv_theta10_uniform_dataset:BadManifest', ...
        'Path manifest has no path_file column: %s', manifest_file);
end
path_files = cellstr(manifest.path_file(:));
missing = path_files(cellfun(@(p) exist(p, 'file') ~= 2, path_files));
if ~isempty(missing)
    error('build_agv_theta10_uniform_dataset:MissingPathFile', ...
        'Manifest contains missing path file: %s', missing{1});
end
end

function s = local_noise_profile()
s = struct();
s.clean_ratio = 0.35;
s.noisy_scales = [0.75, 1.00, 1.35];
s.noisy_probs = [0.20, 0.60, 0.20];
end

function s = local_event_cfg()
s = struct();
s.enabled = true;
s.primary_types = {'slip', 'load_change', 'stall'};
s.primary_probs = [0.25, 0.35, 0.40];
s.extra_event_prob = 0.30;
s.window_padding = 0.15;
s.slip = struct('duration_range', [1.0, 2.0], 'gamma_range', [0.50, 0.78]);
s.load_change = struct('duration_range', [1.3, 2.8], 'load_range', [65, 150]);
s.stall = struct('duration_range', [1.3, 2.6], 'load_range', [210, 300]);
end

function s = local_train_self_check()
s = struct();
s.min_stall_ratio = 0.004;
s.min_slope_ratio = 0.25;
s.min_turn_ratio = 0.15;
s.min_slip_aux_ratio = 0.006;
s.min_load_change_aux_ratio = 0.006;
s.min_stall_aux_ratio = 0.006;
s.min_transition_window_hits = 20;
end

function s = local_label_cfg()
s = struct();
s.theta_slope_thresh = deg2rad(2.0);
s.omega_turn_thresh = 0.05;
s.turn_dwell_sec = 0.40;
s.stall_dwell_sec = 0.60;
end

function gate_cfg = local_coverage_gate_cfg(cfg)
gate_cfg = struct();
gate_cfg.enabled = true;
gate_cfg.fail_on_violation = cfg.fail_on_coverage_violation;
gate_cfg.min_train_bin = local_cfg(cfg, 'min_train_theta_bin_windows', 80);
gate_cfg.min_val_bin = local_cfg(cfg, 'min_val_theta_bin_windows', 15);
gate_cfg.min_test_bin = local_cfg(cfg, 'min_test_theta_bin_windows', 15);
gate_cfg.max_bin_imbalance = local_cfg(cfg, 'max_theta_bin_imbalance', 1.50);
gate_cfg.max_zero_abs_ratio = local_cfg(cfg, 'max_zero_abs_ratio', 0.08);
gate_cfg.max_straight_ratio = local_cfg(cfg, 'max_straight_ratio', 0.70);
gate_cfg.min_turn_nonzero_ratio = local_cfg(cfg, 'min_turn_nonzero_ratio', 0.20);
gate_cfg.min_left_right_balance = local_cfg(cfg, 'min_left_right_balance', 0.85);
gate_cfg.min_slope_turn_overlap_train = local_cfg(cfg, 'min_slope_turn_overlap_train', 0.08);
gate_cfg.min_radius_6_8_train = local_cfg(cfg, 'min_radius_6_8_train', 20);
gate_cfg.min_radius_8_10_train = local_cfg(cfg, 'min_radius_8_10_train', 20);
gate_cfg.min_radius_10_12_train = local_cfg(cfg, 'min_radius_10_12_train', 20);
gate_cfg.min_radius_12_16_train = local_cfg(cfg, 'min_radius_12_16_train', 20);
end
