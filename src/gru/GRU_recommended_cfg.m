function cfg = GRU_recommended_cfg(mode)
%GRU_RECOMMENDED_CFG 返回 TCN 公平对照用的 GRU 推荐配置。
%
% 使用示例:
%   init_project;
%   cfg = GRU_recommended_cfg('baseline');
%   [model, meta] = GRU_train(cfg);

if nargin < 1 || isempty(mode)
    mode = 'baseline';
end

cfg = struct();
cfg.max_epochs = 60;
cfg.batch_size = 64;
cfg.use_gpu = true;
cfg.mode = 'physics_guided';
cfg.hidden_size = 64;
cfg.num_layers = 1;
cfg.dropout = 0.15;
cfg.head_pooling = 'last_mean';
cfg.best_metric = 'composite';
cfg.class_weight_method = 'balanced';
cfg.turn_class_weight_method = 'none';
cfg.turn_class_multipliers = [1.0 1.10 1.0];
cfg.grad_clip_mode = 'global';
cfg.grad_clip = 5.0;
cfg.lambda_turn = 0.05;
cfg.lambda_theta = 0.35;
cfg.lambda_theta_flat = 0.20;
cfg.theta_flat_loss_mode = 'near_zero';
cfg.theta_flat_zero_tol_deg = 0.3;
cfg.lambda_aux = 0.00;
cfg.main_neg_slope_weight = 1.0;
cfg.main_pos_slope_weight = 1.0;
cfg.theta_neg_weight = 1.0;
cfg.theta_pos_weight = 1.0;
cfg.select_downhill_error_weight = 0.25;
cfg.select_turn_transition_weight = 0.0;
cfg.select_turn_transition_target = 0.75;
cfg.select_turn_lr_weight = 0.0;
cfg.select_turn_lr_target = 0.80;
cfg.turn_head_type = 'linear';
cfg.turn_head_source = 'readout';
cfg.turn_head_hidden = 64;
cfg.early_stop_min_epochs = 20;
cfg.selection_start_epoch = 1;
cfg.patience = 12;

switch lower(char(mode))
    case {'baseline','gru_base_last_mean'}
        % Defaults above.
    case {'inputstats','gru_inputstats_head'}
        cfg.head_pooling = 'last_mean_inputstats';
        cfg.turn_head_type = 'mlp';
        cfg.turn_head_source = 'inputstats';
        cfg.turn_head_hidden = 64;
    case {'hidden96','gru_hidden96'}
        cfg.hidden_size = 96;
        cfg.head_pooling = 'last_mean';
    case {'inputstats_hidden96','gru_inputstats_hidden96'}
        cfg.hidden_size = 96;
        cfg.head_pooling = 'last_mean_inputstats';
        cfg.turn_head_type = 'mlp';
        cfg.turn_head_source = 'inputstats';
        cfg.turn_head_hidden = 64;
    case {'two_layer','gru_two_layer'}
        cfg.hidden_size = 64;
        cfg.num_layers = 2;
        cfg.dropout = 0.20;
    otherwise
        error('GRU_recommended_cfg:BadMode', 'Unknown recommended mode: %s', mode);
end
end
