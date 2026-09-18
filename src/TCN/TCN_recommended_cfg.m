function cfg = TCN_recommended_cfg(mode)
%TCN_RECOMMENDED_CFG 返回当前 TCN 实验推荐配置。
%
% 使用示例：
%   init_project;
%   cfg = TCN_recommended_cfg('main_recovery_best');
%   [model, meta] = TCN_train(cfg);

if nargin < 1 || isempty(mode)
    mode = 'production_current';
end

cfg = struct();
cfg.max_epochs = 90;
cfg.batch_size = 64;
cfg.use_gpu = true;
cfg.mode = 'physics_guided';
cfg.head_pooling = 'last_mean_max_inputstats';
cfg.best_metric = 'composite';
cfg.class_weight_method = 'balanced';
cfg.turn_class_weight_method = 'none';
cfg.grad_clip_mode = 'global';

switch lower(char(mode))
    case {'production_current','staged_best'}
        cfg.main_neg_slope_weight = 4.0;
        cfg.select_downhill_error_weight = 0.25;
        cfg.lambda_turn = 0.05;
        cfg.turn_head_type = 'mlp';
        cfg.turn_head_source = 'inputstats';
        cfg.turn_head_hidden = 64;
        cfg.turn_class_multipliers = [1.0 1.10 1.0];
        cfg.turn_finetune_start_epoch = 64;
        cfg.turn_finetune_lambda_turn = 0.50;
        cfg.turn_finetune_disable_other_losses = true;
        cfg.base_best_metric = 'composite';
        cfg.combine_base_and_turn_best = true;
        cfg.best_metric = 'turn_priority';
        cfg.selection_start_epoch = 64;
        cfg.early_stop_min_epochs = 75;
        cfg.select_main_floor = 0.92;
        cfg.select_theta_floor_deg = 1.20;
        cfg.select_downhill_floor = 0.80;
    case {'main_recovery_best','production_base'}
        cfg.main_neg_slope_weight = 4.0;
        cfg.select_downhill_error_weight = 0.25;
        cfg.lambda_turn = 0.20;
        cfg.turn_head_type = 'linear';
        cfg.turn_head_source = 'readout';
    case {'main_max_acc'}
        cfg.main_neg_slope_weight = 2.0;
        cfg.select_downhill_error_weight = 0.15;
        cfg.lambda_turn = 0.20;
        cfg.turn_head_type = 'linear';
        cfg.turn_head_source = 'readout';
        cfg.grad_clip_mode = 'separate';
    case {'staged_turn_probe'}
        cfg.main_neg_slope_weight = 4.0;
        cfg.select_downhill_error_weight = 0.25;
        cfg.lambda_turn = 0.05;
        cfg.turn_head_type = 'mlp';
        cfg.turn_head_source = 'inputstats';
        cfg.turn_head_hidden = 64;
        cfg.turn_class_multipliers = [1.0 1.10 1.0];
        cfg.turn_finetune_start_epoch = 64;
        cfg.turn_finetune_lambda_turn = 0.50;
        cfg.turn_finetune_disable_other_losses = true;
        cfg.base_best_metric = 'composite';
        cfg.combine_base_and_turn_best = true;
        cfg.best_metric = 'turn_priority';
        cfg.selection_start_epoch = 64;
        cfg.early_stop_min_epochs = 75;
        cfg.select_main_floor = 0.92;
        cfg.select_theta_floor_deg = 1.20;
        cfg.select_downhill_floor = 0.80;
    case {'physics_guided_full','pg_full'}
        cfg.main_neg_slope_weight = 4.0;
        cfg.select_downhill_error_weight = 0.25;
        cfg.lambda_turn = 0.05;
        cfg.lambda_theta = 0.35;
        cfg.lambda_theta_flat = 0.20;
        cfg.lambda_aux = 0.15;
        cfg.lambda_phy = 0.002;
        cfg.lambda_smooth = 0.003;
        cfg.turn_transition_weight = 1.25;
        cfg.phy_pitch_threshold_deg = 1.00;
        cfg.phy_turn_signal_threshold = 0.010;
        cfg.phy_turn_gyro_weight = 0.25;
        cfg.phy_theta_mag_weight = 0.25;
        cfg.smooth_feature_weight = 1.00;
        cfg.turn_head_type = 'mlp';
        cfg.turn_head_source = 'inputstats';
        cfg.turn_head_hidden = 64;
        cfg.turn_class_multipliers = [1.0 1.10 1.0];
        cfg.turn_finetune_start_epoch = 64;
        cfg.turn_finetune_lambda_turn = 0.50;
        cfg.turn_finetune_disable_other_losses = true;
        cfg.base_best_metric = 'composite';
        cfg.combine_base_and_turn_best = true;
        cfg.best_metric = 'turn_priority';
        cfg.selection_start_epoch = 64;
        cfg.early_stop_min_epochs = 75;
        cfg.select_main_floor = 0.92;
        cfg.select_theta_floor_deg = 1.20;
        cfg.select_downhill_floor = 0.80;
    otherwise
        error('TCN_recommended_cfg:BadMode', 'Unknown recommended mode: %s', mode);
end
end
