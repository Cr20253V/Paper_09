function [theta_hat, label_main, label_turn, conf_main] = TCN_State_Classifier_sim(y_raw, reset)
%TCN_STATE_CLASSIFIER_SIM Simulink MATLAB Function block entrypoint.
%#codegen

coder.extrinsic('evalin');
coder.extrinsic('assignin');
coder.extrinsic('TCN_state_classifier');

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
    has_cfg = evalin('base', 'exist(''tcn_sim_cfg'', ''var'')==1');
    if has_cfg
        cfg = evalin('base', 'tcn_sim_cfg');
        state = TCN_state_classifier('init', params, cfg);
    else
        state = TCN_state_classifier('init', params);
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

[state, out] = TCN_state_classifier('update', state, double(y_raw(:)));
if isempty(out)
    return;
end

assignin('base', 'tcn_out_temp', out);
theta_hat = evalin('base', 'double(tcn_out_temp.theta_hat)');
label_main = evalin('base', 'double(tcn_out_temp.label_main)');
label_turn = evalin('base', 'double(tcn_out_temp.label_turn)');
conf_main = evalin('base', 'double(tcn_out_temp.conf_main)');
end
