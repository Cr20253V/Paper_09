function data = TCN_gen_train_data_v3_transition_rich(cfg)
%TCN_GEN_TRAIN_DATA_V3_TRANSITION_RICH 生成 V3 transition-rich 训练母集。
%
% V3 不覆盖 V2 的 TCN_train_data_full.mat。它默认读取
% data/paths/path_train_tcn_v3_*.mat，并输出到
% data/tcn/TCN_train_data_v3_transition_rich_full.mat。
%
% 使用方法：
%   init_project;
%   data = TCN_gen_train_data_v3_transition_rich();

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
data_tcn_dir = fullfile(root, 'data', 'tcn');
paths_dir = fullfile(root, 'data', 'paths');

cfg.output_dir = local_cfg(cfg, 'output_dir', data_tcn_dir);
cfg.output_file = local_cfg(cfg, 'output_file', ...
    fullfile(data_tcn_dir, 'TCN_train_data_v3_transition_rich_full.mat'));
cfg.path_pattern = local_cfg(cfg, 'path_pattern', ...
    fullfile(paths_dir, 'path_train_tcn_v3_*.mat'));
cfg.seed = local_cfg(cfg, 'seed', 20260428);
cfg.num_runs_per_path = local_cfg(cfg, 'num_runs_per_path', 4);
cfg.noise_on = local_cfg(cfg, 'noise_on', true);
cfg.verbose = local_cfg(cfg, 'verbose', true);

if ~isfield(cfg, 'noise_profile') || ~isstruct(cfg.noise_profile)
    cfg.noise_profile = struct();
end
cfg.noise_profile.clean_ratio = local_cfg(cfg.noise_profile, 'clean_ratio', 0.25);
cfg.noise_profile.noisy_scales = local_cfg(cfg.noise_profile, 'noisy_scales', [1.0, 1.5]);
cfg.noise_profile.noisy_probs = local_cfg(cfg.noise_profile, 'noisy_probs', [0.70, 0.30]);

if ~isfield(cfg, 'event_cfg') || ~isstruct(cfg.event_cfg)
    cfg.event_cfg = struct();
end
cfg.event_cfg.primary_types = local_cfg(cfg.event_cfg, 'primary_types', {'slip', 'load_change', 'stall'});
cfg.event_cfg.primary_probs = local_cfg(cfg.event_cfg, 'primary_probs', [0.25, 0.35, 0.40]);
cfg.event_cfg.extra_event_prob = local_cfg(cfg.event_cfg, 'extra_event_prob', 0.45);
cfg.event_cfg.window_padding = local_cfg(cfg.event_cfg, 'window_padding', 0.15);
if ~isfield(cfg.event_cfg, 'slip')
    cfg.event_cfg.slip = struct('duration_range', [1.2, 2.4], 'gamma_range', [0.45, 0.78]);
end
if ~isfield(cfg.event_cfg, 'load_change')
    cfg.event_cfg.load_change = struct('duration_range', [1.5, 3.2], 'load_range', [70, 165]);
end
if ~isfield(cfg.event_cfg, 'stall')
    cfg.event_cfg.stall = struct('duration_range', [1.5, 3.0], 'load_range', [210, 315]);
end

if ~isfield(cfg, 'self_check') || ~isstruct(cfg.self_check)
    cfg.self_check = struct();
end
cfg.self_check.min_slope_ratio = local_cfg(cfg.self_check, 'min_slope_ratio', 0.12);
cfg.self_check.min_turn_ratio = local_cfg(cfg.self_check, 'min_turn_ratio', 0.08);
cfg.self_check.min_transition_window_hits = local_cfg(cfg.self_check, 'min_transition_window_hits', 20);

data = TCN_gen_train_data(cfg);
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end
