function cfg = TCN_default_config(root)
%TCN_DEFAULT_CONFIG Current TCN deployment artifact.
%
% Frozen after the theta10 V2 multi-seed run. Seed 21 gives the best overall
% closed-loop candidate profile: lowest theta MAE/P95, best main accuracy,
% strongest slope recall, and near-best turn accuracy.

if nargin < 1 || isempty(root)
    root = local_project_root();
end

cfg = struct();
cfg.seed = 21;
cfg.case_name = 'tcn96_rawtheta_sym';
cfg.run_tag = 'tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21';
cfg.dataset_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat');
cfg.raw_train_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat');
cfg.model_file = fullfile(root, 'data', 'models', ...
    'TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat');
cfg.meta_file = fullfile(root, 'data', 'models', ...
    'TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat');
cfg.summary_file = fullfile(root, 'results', 'tcn', 'train_logs_theta10_uniform_h0_v2', ...
    'TCN_theta10_v2_multi_seed_summary.csv');
cfg.group_summary_file = fullfile(root, 'results', 'tcn', 'train_logs_theta10_uniform_h0_v2', ...
    'TCN_theta10_v2_group_summary.csv');
cfg.report_file = fullfile(root, 'results', 'tcn', 'train_logs_theta10_uniform_h0_v2', ...
    sprintf('%s_seed%d', cfg.case_name, cfg.seed), 'TCN_train_report.md');
cfg.selection_note = 'frozen_best_overall_seed21_theta10_v2_2026_05_14';

cfg.theta_output_gain = 1.0;
cfg.theta_abs_limit = deg2rad(12.0);
cfg.theta_rate_limit = deg2rad(5.0);
cfg.theta_mpc_deadzone = deg2rad(2.0);
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
