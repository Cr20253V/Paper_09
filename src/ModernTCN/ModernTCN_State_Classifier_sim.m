function [theta_hat, label_main, label_turn, conf_main] = ModernTCN_State_Classifier_sim(y_raw, reset, u_cmd)
%MODERNTCN_STATE_CLASSIFIER_SIM Simulink MATLAB Function 块调用入口。
%#codegen
%
% 功能说明：
%   这是替换 GRU_State_Classifier_gru_sim 的薄封装。Simulink 每个仿真步给
%   一帧 34 维 y_raw，本函数通过 extrinsic 调用 MATLAB 侧的
%   ModernTCN_state_classifier，内部维护特征滤波、128 步滑窗、归一化和
%   ONNX 推理状态。
%
% 手动接入时，MATLAB Function block 内建议改为：
%   [theta_hat, label_main, label_turn, conf_main] = ...
%       ModernTCN_State_Classifier_sim(y_raw, reset);
%
% Plan B-lite command-response candidates may pass u_cmd=[F_cmd; omega_cmd].
% The two-argument call remains compatible with passive-only datasets.

coder.extrinsic('evalin');
coder.extrinsic('assignin');
coder.extrinsic('ModernTCN_state_classifier');

persistent state is_initialized

theta_hat = 0.0;
label_main = 1.0;
label_turn = 0.0;
conf_main = 1.0;

if isempty(is_initialized)
    is_initialized = false;
end

need_reset = (~is_initialized) || (reset ~= 0);
if need_reset
    has_required = evalin('base', 'exist(''params'', ''var'')==1');
    if ~has_required
        return;
    end

    params = evalin('base', 'params');
    has_cfg = evalin('base', 'exist(''modern_tcn_sim_cfg'', ''var'')==1');
    if has_cfg
        cfg = evalin('base', 'modern_tcn_sim_cfg');
        state = ModernTCN_state_classifier('init', params, cfg);
    else
        state = ModernTCN_state_classifier('init', params);
    end
    is_initialized = true;
    return;
end

if isempty(state)
    return;
end

if isempty(y_raw) || numel(y_raw) < 18
    return;
end

if nargin < 3 || isempty(u_cmd)
    u_cmd = zeros(2, 1);
end

[state, out] = ModernTCN_state_classifier('update', state, double(y_raw(:)), double(u_cmd(:)));
if isempty(out)
    return;
end

assignin('base', 'modern_tcn_out_temp', out);
theta_hat = evalin('base', 'double(modern_tcn_out_temp.theta_hat_for_mpc)');
label_main = evalin('base', 'double(modern_tcn_out_temp.label_main)');
label_turn = evalin('base', 'double(modern_tcn_out_temp.label_turn)');
conf_main = evalin('base', 'double(modern_tcn_out_temp.conf_main)');
end
