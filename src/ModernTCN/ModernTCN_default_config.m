function cfg = ModernTCN_default_config(root)
%MODERNTCN_DEFAULT_CONFIG 当前冻结的 ModernTCN 部署配置。
%
% 这里只保存当前闭环仿真使用的默认模型。需要临时测试其他 checkpoint 时，仍可在调用脚本中传入 cfg
% 覆盖 seed、dataset_file、run_tag 或 onnx_file。

if nargin < 1 || isempty(root)
    root = local_project_root();
end

cfg = struct();
cfg.seed = 21;
cfg.run_tag = 'node6_v3_passive17_plus_all5_seed21';
cfg.dataset_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v3_passive17_plus_all5.mat');
cfg.raw_train_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat');
cfg.reference_dir = fullfile(root, 'results', 'paper', ...
    'plan_a_imu_removal_workflow', '03_offline_train', 'modern_tcn', ...
    'modern_tcn_passive17_plus_all5_seed21');
cfg.onnx_file = fullfile(cfg.reference_dir, 'modern_tcn_seed21.onnx');
cfg.pytorch_reference_file = fullfile(cfg.reference_dir, ...
    'modern_tcn_seed21_pytorch_reference.mat');

% Deployment-side theta conditioning for closed-loop scheduling. These are
% the original Node 4 ModernTCN plus Node 7 theta_smooth_conservative values.
cfg.theta_output_gain = 1.0;
cfg.theta_abs_limit = deg2rad(12.0);
cfg.theta_rate_limit = deg2rad(3.5);
cfg.theta_mpc_deadzone = deg2rad(2.0);
cfg.theta_mpc_deadzone_soft = deg2rad(2.0);
cfg.theta_mpc_rate_limit = inf;
cfg.tau_theta = 0.30;
cfg.dwell_main = 0.20;
cfg.dwell_turn = 0.40;

% Optional online command-consistency guard. Disabled by default; experiments
% may enable it for command-response contracts to suppress left/right turn
% labels when recent omega commands indicate straight driving.
cfg.turn_command_guard_enable = false;
cfg.turn_command_guard_omega_abs = 0.0;
cfg.turn_command_guard_mean_abs = 0.0;
cfg.turn_command_guard_min_active_sec = 0.0;

% Optional online slope-release guard. Disabled by default; experiments may
% enable it to recover from persistent false slope lock when both recent
% commands and scheduled theta indicate straight/flat driving.
cfg.main_slope_release_enable = false;
cfg.main_slope_release_theta_abs_deg = 0.0;
cfg.main_slope_release_omega_abs = 0.0;
cfg.main_slope_release_omega_mean_abs = 0.0;
cfg.main_slope_release_min_active_sec = 0.0;
cfg.main_slope_release_force_turn_straight = false;
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
