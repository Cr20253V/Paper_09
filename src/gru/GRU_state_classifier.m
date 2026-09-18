% =============================
% 文件名：GRU_state_classifier.m
% 版本号：V1.7（简化主分类：3类，移除 slip）
% 最后修改时间：2025-12-30
% 作者：LPV-MPC Project
% 功能描述：
%   GRU工况识别在线推理封装
%   提供序列缓冲、最小驻留时间、低通滤波等功能
%
% V1.7 更新（2025-12-30）：
%   - 主分类简化为 3 类：flat/stall/slope（移除 slip）
%   - 更新标签编号：stall=2, slope=3
%
% 使用方法：
%   1. 初始化：
%      state = GRU_state_classifier('init', params, model);
%   2. 单步更新：
%      [state, out] = GRU_state_classifier('update', state, y_raw_t);
%
% 输入参数：
%   - action: 'init' 或 'update'
%   - state: 分类器状态结构体（update模式）
%   - params: 系统参数结构体（init模式，来自parameters.m）
%   - model: GRU模型结构体（init模式，来自GRU_model.mat）
%   - y_raw_t: 当前时刻的原始输出 [31×1]（update模式）
%
% 输出参数：
%   - state: 更新后的状态结构体
%   - out: 推理输出结构体
%     .label_main: 主分类 ∈ {1,2,3} (flat/stall/slope)
%     .label_turn: 转弯状态 ∈ {-1,0,+1} (right/straight/left)
%     .theta_hat: 坡度角估计 [rad]
%     .conf_main: 主分类置信度 [3×1]
%     .conf_turn: 转弯分类置信度 [3×1]
%     .label_main_name: 主分类标签名称
%     .label_turn_name: 转弯状态标签名称
%
% 依赖：
%   - GRU_infer.m（推理接口）
%   - GRU_model.mat（训练好的模型）
%   - parameters.m（系统参数）
%
% 备注：
%   - 主分类最小驻留时间: 0.20s
%   - 转弯状态最小驻留时间: 0.40s
%   - θ̂ 低通滤波时间常数: 0.15s
%   - θ̂ 死区阈值: 0.023 rad（≈1.3°）硬区 / 0.031 rad（≈1.8°）软区
%   - 序列未满时输出默认值（flat, straight, θ=0）
% =============================

function [state, out] = GRU_state_classifier(action, varargin)
%GRU_STATE_CLASSIFIER GRU工况识别在线推理封装
%
% 示例:
%   % 初始化
%   params = parameters();
%   load('GRU_model.mat', 'model');
%   state = GRU_state_classifier('init', params, model);
%
%   % 在线循环
%   for t = 1:N
%       y_raw_t = output_eq(x, u, theta, params);  % [31×1]
%       [state, out] = GRU_state_classifier('update', state, y_raw_t);
%       fprintf('t=%.2f: %s, %s, θ=%.2f°\n', ...
%           t*params.Ts, out.label_main_name, out.label_turn_name, rad2deg(out.theta_hat));
%   end

    %% 路由到对应的子函数
    switch lower(action)
        case 'init'
            % 初始化模式
            if nargin < 3
                error('初始化需要提供: GRU_state_classifier(''init'', params, model)');
            end
            state = initClassifier(varargin{1}, varargin{2});
            out = [];
            
        case 'update'
            % 更新模式
            if nargin < 3
                error('更新需要提供: GRU_state_classifier(''update'', state, y_raw_t)');
            end
            [state, out] = updateClassifier(varargin{1}, varargin{2});
            
        otherwise
            error('未知的操作: %s (应为 ''init'' 或 ''update'')', action);
    end
end

%% ========== 子函数：初始化 ==========
function state = initClassifier(params, model)
%INITCLASSIFIER 初始化分类器状态

    % 基本参数
    state.params = params;
    state.model = model;
    state.Ts = params.Ts;
    
    % 坡度死区阈值配置（平地抑噪专用）
    state.theta_deadzone_hard = deg2rad(1.3);   % <1.3° 强制置零
    state.theta_deadzone_soft = deg2rad(1.8);   % 1.3°~1.8° 线性压缩
    
    % 序列缓冲配置
    % 序列长度和特征维度从model获取
    if isfield(model, 'seq_len')
        state.seq_len = model.seq_len;
    elseif isfield(model, 'cfg') && isfield(model.cfg, 'seq_len')
        state.seq_len = model.cfg.seq_len;
    else
        % 回退方案：假设seq_len=48（与GRU_prepare_dataset.m默认值一致）
        state.seq_len = 48;
        warning('model中未找到seq_len字段，使用默认值48');
    end
    state.feat_dim = numel(model.scaler.mean);  % 特征维度
    feature_contract = extract_passive_features('contract');
    if state.feat_dim ~= feature_contract.input_dim
        error('GRU_state_classifier:FeatureContractMismatch', ...
            'Model feature dim is %d, but %s requires %d.', ...
            state.feat_dim, feature_contract.feature_contract, feature_contract.input_dim);
    end
    state.buffer = zeros(state.seq_len, state.feat_dim);  % [seq_len, feat_dim]
    state.buffer_count = 0;  % 当前缓冲区样本数

    if ~isfield(state.model, 'class_labels_main')
        state.model.class_labels_main = {'flat', 'stall', 'slope'};
    end
    if ~isfield(state.model, 'class_labels_turn')
        state.model.class_labels_turn = {'right', 'straight', 'left'};
    end
    
    % 最小驻留时间配置（与 test_gru_latency 评估结果对齐）
    state.dwell_main = 0.20;     % 主分类驻留时间 [s]
    state.dwell_turn = 0.40;     % 转弯状态驻留时间 [s]
    state.dwell_main_steps = round(state.dwell_main / state.Ts);
    state.dwell_turn_steps = round(state.dwell_turn / state.Ts);
    
    % 当前状态
    state.label_main_current = 1;       % flat
    state.label_turn_current = 0;       % straight
    state.theta_hat_current = 0;        % 0 rad
    state.label_main_stable_count = 0;  % 稳定计数器
    state.label_turn_stable_count = 0;
    state.label_main_candidate = 1;     % 候选标签
    state.label_turn_candidate = 0;
    
    % θ̂ 低通滤波配置
    state.tau_theta = 0.15;  % 时间常数 [s]
    state.alpha_theta = state.Ts / (state.tau_theta + state.Ts);
    
    % 特征计算滤波参数（从scaler读取，与离线一致）
    if isfield(model, 'scaler')
        if isfield(model.scaler, 'tau_diff')
            state.tau_diff = model.scaler.tau_diff;
        else
            state.tau_diff = 0.3;  % 默认值
            warning('scaler中未找到tau_diff，使用默认值0.3s');
        end
        
        if isfield(model.scaler, 'tau_accel_lp')
            state.tau_accel_lp = model.scaler.tau_accel_lp;
        else
            state.tau_accel_lp = 0.4;  % 默认值
            warning('scaler中未找到tau_accel_lp，使用默认值0.4s');
        end
    else
        state.tau_diff = 0.3;
        state.tau_accel_lp = 0.4;
        warning('model中未找到scaler，使用默认滤波参数');
    end
    
    feature_cfg = struct('tau_diff', state.tau_diff, 'tau_accel_lp', state.tau_accel_lp);
    state.feature_state = extract_passive_features('init', params, state.Ts, feature_cfg);
    
    % 数值稳健性
    state.eps = 1e-8;
    
    % 统计信息
    state.step = 0;
end

%% ========== 子函数：更新 ==========
function [state, out] = updateClassifier(state, y_raw_t)
%UPDATECLASSIFIER 单步更新分类器

    state.step = state.step + 1;
    
    %% 1. 提取特征（更新状态变量）
    [features, state] = extractFeatures(y_raw_t, state);
    state.last_features = features;
    
    % 检查NaN/Inf
    if any(isnan(features)) || any(isinf(features))
        % 数值异常，保持当前状态
        out = constructOutput(state);
        warning('[GRU_state_classifier] 特征含NaN/Inf，保持当前状态');
        return;
    end
    
    %% 2. 更新序列缓冲
    % 滚动缓冲区（FIFO）
    state.buffer(1:end-1, :) = state.buffer(2:end, :);
    state.buffer(end, :) = features;
    state.buffer_count = min(state.buffer_count + 1, state.seq_len);
    
    %% 3. 判断是否可以推理
    if state.buffer_count < state.seq_len
        % 序列未满，输出默认值
        out = constructOutput(state);
        return;
    end
    
    %% 4. 归一化
    x_seq_norm = (state.buffer - state.model.scaler.mean) ./ ...
                 (state.model.scaler.std + state.eps);
    
    %% 5. GRU推理
    try
        [label_main_raw, label_turn_raw, theta_hat_raw, conf] = ...
            GRU_infer(x_seq_norm, state.model);
    catch ME
        % 推理失败，保持当前状态
        warning('GRU_state_classifier:InferenceFailed', '[GRU_state_classifier] GRU推理失败: %s', ME.message);
        out = constructOutput(state);
        return;
    end
    
    %% 6. 最小驻留时间处理（主分类）
    if label_main_raw == state.label_main_candidate
        % 候选标签稳定
        state.label_main_stable_count = state.label_main_stable_count + 1;
        
        if state.label_main_stable_count >= state.dwell_main_steps
            % 达到驻留时间，更新当前标签
            state.label_main_current = label_main_raw;
        end
    else
        % 候选标签改变，重置计数器
        state.label_main_candidate = label_main_raw;
        state.label_main_stable_count = 1;
    end
    
    %% 7. 最小驻留时间处理（转弯状态）
    if label_turn_raw == state.label_turn_candidate
        % 候选标签稳定
        state.label_turn_stable_count = state.label_turn_stable_count + 1;
        
        if state.label_turn_stable_count >= state.dwell_turn_steps
            % 达到驻留时间，更新当前标签
            state.label_turn_current = label_turn_raw;
        end
    else
        % 候选标签改变，重置计数器
        state.label_turn_candidate = label_turn_raw;
        state.label_turn_stable_count = 1;
    end
    
    %% 8. θ̂ 低通滤波
    state.theta_hat_current = state.alpha_theta * theta_hat_raw + ...
                              (1 - state.alpha_theta) * state.theta_hat_current;

    %% 9. 坡度死区处理（仅影响输出，不改内部状态）
    theta_hat_out = state.theta_hat_current;
    if state.label_main_current == 1
        theta_abs = abs(theta_hat_out);
        if theta_abs <= state.theta_deadzone_hard
            theta_hat_out = 0.0;
        elseif theta_abs < state.theta_deadzone_soft
            span = state.theta_deadzone_soft - state.theta_deadzone_hard;
            scale = (theta_abs - state.theta_deadzone_hard) / max(span, state.eps);
            theta_hat_out = sign(theta_hat_out) * (scale * theta_abs);  % 线性过渡至原值
        end
    end
    
    %% 10. 构建输出
    out = struct();
    out.label_main = state.label_main_current;
    out.label_turn = state.label_turn_current;
    out.theta_hat = theta_hat_out;
    out.conf_main = conf.conf_main;
    out.conf_turn = conf.conf_turn;
    
    % 标签名称
    out.label_main_name = state.model.class_labels_main{state.label_main_current};
    turn_idx = state.label_turn_current + 2;  % -1→1, 0→2, +1→3
    out.label_turn_name = state.model.class_labels_turn{turn_idx};
    
    % 调试信息（可选）
    out.debug = struct();
    out.debug.label_main_raw = label_main_raw;
    out.debug.label_turn_raw = label_turn_raw;
    out.debug.theta_hat_raw = theta_hat_raw;
    out.debug.buffer_count = state.buffer_count;
    out.debug.step = state.step;
end

%% ========== 辅助函数 ==========

function [features, state] = extractFeatures(y_raw, state)
%EXTRACTFEATURES 从原始输出提取 passive17_plus_all5 特征。

    [features, state.feature_state] = extract_passive_features('step', y_raw, state.feature_state);
end

function out = constructOutput(state)
%CONSTRUCTOUTPUT 构建默认输出（序列未满或异常时）

    out = struct();
    out.label_main = state.label_main_current;
    out.label_turn = state.label_turn_current;
    out.theta_hat = state.theta_hat_current;
    out.conf_main = [1; 0; 0];  % 默认flat（V1.7: 3维）
    out.conf_turn = [0; 1; 0];     % 默认straight
    
    % 标签名称
    out.label_main_name = state.model.class_labels_main{state.label_main_current};
    turn_idx = state.label_turn_current + 2;
    out.label_turn_name = state.model.class_labels_turn{turn_idx};
    
    % 调试信息
    out.debug = struct();
    out.debug.buffer_count = state.buffer_count;
    out.debug.step = state.step;
    out.debug.warning = 'Using default output (buffer not full or exception)';
    if isfield(state, 'last_features') && ~isempty(state.last_features)
        out.features = double(state.last_features(:));
    else
        out.features = nan(state.feat_dim, 1);
    end
    out.debug.feature_contract = state.feature_state.feature_contract;
end
