% =============================
% 文件名：GRU_infer.m
% 版本号：V1.1（简化主分类：3类，移除 slip）
% 最后修改时间：2025-12-30
% 作者：LPV-MPC Project
% 功能描述：
%   GRU单步推理接口
%   输入一个序列，输出三个任务的预测结果
%
% 输入参数：
%   - x_seq: 输入序列 [seq_len, feat_dim] 或 [feat_dim, seq_len, 1]
%   - model: 模型结构体（从 GRU_model.mat 加载）
%
% 输出参数：
%   - label_main: 主分类标签 ∈ {1,2,3} (flat/stall/slope)
%   - label_turn: 转弯状态标签 ∈ {-1,0,+1} (right/straight/left)
%   - theta_hat: 坡度角估计 [rad]
%   - conf: 置信度结构体
%     .conf_main: 主分类置信度 [3×1]
%     .conf_turn: 转弯分类置信度 [3×1]
%     .label_main_name: 主分类标签名称
%     .label_turn_name: 转弯状态标签名称
%
% 依赖：
%   - GRU_model.mat（由 GRU_train.m 生成）
%
% 备注：
%   - 输入序列需已归一化（使用model.scaler）
%   - 如需从原始传感量推理，请使用 GRU_state_classifier.m
% =============================

function [label_main, label_turn, theta_hat, conf] = GRU_infer(x_seq, model)
%GRU_INFER GRU单步推理接口
%
% 示例:
%   load('GRU_model.mat', 'model');
%   x_seq = randn(96, 16);  % [seq_len, feat_dim]
%   [label_main, label_turn, theta_hat, conf] = GRU_infer(x_seq, model);

    %% 输入验证
    if nargin < 2
        error('需要提供输入序列和模型: GRU_infer(x_seq, model)');
    end

    if isfield(model, 'feature_net') && isfield(model, 'heads')
        [label_main, label_turn, theta_hat, conf] = local_infer_v4_model(x_seq, model);
        return;
    end
    
    % 检查输入维度
    if size(x_seq, 1) == model.net_feature.Layers(1).InputSize && ...
       size(x_seq, 2) > 1
        % [feat_dim, seq_len] → [feat_dim, seq_len, 1]
        x_seq = reshape(x_seq, size(x_seq, 1), size(x_seq, 2), 1);
    elseif size(x_seq, 2) == model.net_feature.Layers(1).InputSize && ...
           size(x_seq, 1) > 1
        % [seq_len, feat_dim] → [feat_dim, seq_len, 1]
        x_seq = permute(x_seq, [2, 1]);
        x_seq = reshape(x_seq, size(x_seq, 1), size(x_seq, 2), 1);
    end
    
    % 最终检查：应该是 [feat_dim, seq_len, 1]
    expected_feat_dim = model.net_feature.Layers(1).InputSize;
    if size(x_seq, 1) ~= expected_feat_dim
        error('输入序列特征维度错误: 期望 %d, 实际 %d', ...
            expected_feat_dim, size(x_seq, 1));
    end
    
    %% 转为dlarray
    X = dlarray(x_seq, 'CBT');  % [feat_dim, seq_len, 1]
    
    % 如果模型在GPU上，也将输入转到GPU
    if canUseGPU() && isa(model.fc_main_weights, 'gpuArray')
        X = gpuArray(X);
    end
    
    %% 前向传播
    % 1) GRU特征提取
    features_seq = forward(model.net_feature, X);  % [hidden_size, seq_len, 1]
    
    % 提取最后一个时间步的特征
    features = features_seq(:, end, :);  % [hidden_size, 1, 1]
    features = squeeze(features);  % [hidden_size, 1]
    
    % 移除维度标签（避免矩阵乘法时的维度标签冲突）
    features = stripdims(features);
    
    % 2) 主分类头
    logits_main = model.fc_main_weights * features + model.fc_main_bias;  % [3, 1]
    probs_main = softmax(logits_main, 'DataFormat', 'CB');
    probs_main = extractdata(gather(probs_main));  % [3, 1]
    [conf_main_max, label_main] = max(probs_main);
    
    % 3) 转弯分类头
    logits_turn = model.fc_turn_weights * features + model.fc_turn_bias;  % [3, 1]
    probs_turn = softmax(logits_turn, 'DataFormat', 'CB');
    probs_turn = extractdata(gather(probs_turn));  % [3, 1]
    [conf_turn_max, label_turn_idx] = max(probs_turn);
    
    % 映射转弯标签：{1,2,3} → {-1,0,+1}
    label_turn = label_turn_idx - 2;  % 1→-1, 2→0, 3→+1
    
    % 4) 坡度回归头
    pred_theta = model.fc_theta_weights * features + model.fc_theta_bias;  % [1, 1]
    theta_hat = extractdata(gather(pred_theta));
    
    %% 构建输出
    % 置信度结构体
    conf = struct();
    conf.conf_main = probs_main;  % [3×1]
    conf.conf_turn = probs_turn;  % [3×1]
    conf.conf_main_max = conf_main_max;
    conf.conf_turn_max = conf_turn_max;
    
    % 标签名称
    conf.label_main_name = model.class_labels_main{label_main};
    conf.label_turn_name = model.class_labels_turn{label_turn_idx};
    
    % 返回标量
    label_main = double(label_main);
    label_turn = double(label_turn);
    theta_hat = double(theta_hat);
end

function [label_main, label_turn, theta_hat, conf] = local_infer_v4_model(x_seq, model)
%LOCAL_INFER_V4_MODEL Inference path for GRU_train.m V4 artifacts.

expected_feat_dim = model.feature_net.Layers(1).InputSize;
x_seq = local_prepare_sequence(x_seq, expected_feat_dim);
X = dlarray(x_seq, 'CBT');

Z = predict(model.feature_net, X);
cfg = model.cfg;
heads = model.heads;
[H, H_inputstats] = local_temporal_readout(Z, X, cfg);
H_turn = local_turn_readout(H, H_inputstats, cfg);

logits_main = heads.main_W * H + heads.main_b;
logits_turn = local_turn_logits(heads, H_turn, cfg);
theta = heads.theta_W * H + heads.theta_b;

probs_main = softmax(logits_main, 'DataFormat', 'CB');
probs_turn = softmax(logits_turn, 'DataFormat', 'CB');
probs_main = extractdata(gather(probs_main));
probs_turn = extractdata(gather(probs_turn));

[conf_main_max, label_main] = max(probs_main, [], 1);
[conf_turn_max, label_turn_idx] = max(probs_turn, [], 1);
label_turn = label_turn_idx - 2;
theta_hat = extractdata(gather(theta));

[main_names, turn_names] = local_class_names(model);

conf = struct();
conf.conf_main = probs_main(:);
conf.conf_turn = probs_turn(:);
conf.conf_main_max = conf_main_max;
conf.conf_turn_max = conf_turn_max;
conf.label_main_name = main_names{label_main};
conf.label_turn_name = turn_names{label_turn_idx};

label_main = double(label_main);
label_turn = double(label_turn);
theta_hat = double(theta_hat(1));
end

function x_seq = local_prepare_sequence(x_seq, expected_feat_dim)
if size(x_seq, 1) == expected_feat_dim && size(x_seq, 2) > 1
    x_seq = reshape(x_seq, size(x_seq, 1), size(x_seq, 2), []);
elseif size(x_seq, 2) == expected_feat_dim && size(x_seq, 1) > 1
    x_seq = permute(x_seq, [2, 1]);
    x_seq = reshape(x_seq, size(x_seq, 1), size(x_seq, 2), []);
end

if size(x_seq, 1) ~= expected_feat_dim
    error('GRU_infer:FeatureMismatch', 'Expected %d features, got %d.', ...
        expected_feat_dim, size(x_seq, 1));
end
end

function [H, H_inputstats] = local_temporal_readout(Z, X, cfg)
H_inputstats = local_input_stats_readout(X);
switch lower(char(cfg.head_pooling))
    case 'last'
        H = Z(:, end, :);
    case 'last_mean'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H = cat(1, H_last, H_mean);
    case 'last_mean_inputstats'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H = cat(1, H_last, H_mean, H_inputstats);
    case 'last_mean_max'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max);
    case 'last_mean_max_inputstats'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max, H_inputstats);
    otherwise
        error('GRU_infer:BadHeadPooling', 'Unknown head_pooling: %s', cfg.head_pooling);
end
H = reshape(H, size(H,1), []);
H_inputstats = reshape(H_inputstats, size(H_inputstats,1), []);
end

function H = local_input_stats_readout(X)
X_last = X(:, end, :);
X_mean = mean(X, 2);
X_std = sqrt(mean((X - X_mean).^2, 2) + 1e-8);
X_max = max(X, [], 2);
X_min = min(X, [], 2);
H = cat(1, X_last, X_mean, X_std, X_max, X_min);
end

function H_turn = local_turn_readout(H, H_inputstats, cfg)
switch lower(char(cfg.turn_head_source))
    case 'readout'
        H_turn = H;
    case 'inputstats'
        H_turn = H_inputstats;
    otherwise
        error('GRU_infer:BadTurnHeadSource', 'Unknown turn_head_source: %s', cfg.turn_head_source);
end
end

function logits = local_turn_logits(heads, H_turn, cfg)
switch lower(char(cfg.turn_head_type))
    case 'linear'
        logits = heads.turn_W * H_turn + heads.turn_b;
    case 'mlp'
        A = max(heads.turn_W1 * H_turn + heads.turn_b1, 0);
        logits = heads.turn_W2 * A + heads.turn_b2;
    otherwise
        error('GRU_infer:BadTurnHead', 'Unknown turn_head_type: %s', cfg.turn_head_type);
end
end

function [main_names, turn_names] = local_class_names(model)
if isfield(model, 'class_labels_main')
    main_names = model.class_labels_main;
else
    main_names = {'flat', 'stall', 'slope'};
end
if isfield(model, 'class_labels_turn')
    turn_names = model.class_labels_turn;
else
    turn_names = {'right', 'straight', 'left'};
end
end
