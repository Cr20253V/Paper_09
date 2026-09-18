function cfg = GRU_default_config(root)
%GRU_DEFAULT_CONFIG Current frozen GRU deployment artifact.

if nargin < 1 || isempty(root)
    root = local_project_root();
end

cfg = struct();
cfg.seed = 101;
cfg.case_name = 'inputstats_hidden96_l2';
cfg.run_tag = 'full_gru_passive17_plus_all5_seed101';
cfg.dataset_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v3_passive17_plus_all5.mat');
cfg.raw_train_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat');
node4_dir = fullfile(root, 'results', 'paper', ...
    'plan_a_imu_removal_workflow', '03_offline_train');
cfg.model_file = fullfile(node4_dir, 'models', ...
    'GRU_model_full_gru_passive17_plus_all5_seed101.mat');
cfg.meta_file = fullfile(node4_dir, 'models', ...
    'GRU_meta_full_gru_passive17_plus_all5_seed101.mat');
cfg.summary_file = fullfile(node4_dir, 'node4_training_summary.csv');
cfg.group_summary_file = fullfile(node4_dir, 'node4_full_gru_tcn_summary.csv');
cfg.report_file = fullfile(node4_dir, 'matlab_logs', ...
    'full_gru_passive17_plus_all5_seed101', 'GRU_train_report.md');
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
