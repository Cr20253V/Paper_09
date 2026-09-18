function [theta_hat, label_main, label_turn, conf_main] = GRU_State_Classifier_gru_sim(y_raw, reset)
%#codegen

coder.extrinsic('evalin');
coder.extrinsic('assignin');
coder.extrinsic('GRU_state_classifier');
coder.extrinsic('GRU_load_default_to_base');

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
    has_required = evalin('base', ...
        'exist(''gru_model'', ''var'')==1 && exist(''params'', ''var'')==1');
    if ~has_required
        GRU_load_default_to_base();
        has_required = evalin('base', ...
            'exist(''gru_model'', ''var'')==1 && exist(''params'', ''var'')==1');
        if ~has_required
            return;
        end
    end

    model = evalin('base', 'gru_model');
    params = evalin('base', 'params');
    state = GRU_state_classifier('init', params, model);
    is_initialized = true;
    return;
end

if isempty(state)
    return;
end

if isempty(y_raw) || numel(y_raw) < 31
    return;
end

y_raw_31 = double(y_raw(1:31));
[state, out] = GRU_state_classifier('update', state, y_raw_31);

if isempty(out)
    return;
end

assignin('base', 'gru_out_temp', out);
theta_hat = evalin('base', 'double(gru_out_temp.theta_hat)');
label_main = evalin('base', 'double(gru_out_temp.label_main)');
label_turn = evalin('base', 'double(gru_out_temp.label_turn)');
conf_main  = evalin('base', 'double(max(gru_out_temp.conf_main(:)))');

end
