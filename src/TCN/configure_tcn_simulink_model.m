function configure_tcn_simulink_model(model_name, do_save)
%CONFIGURE_TCN_SIMULINK_MODEL Patch the TCN closed-loop Simulink wrapper.
%
% Usage:
%   init_project;
%   configure_tcn_simulink_model('LPVMPC_AGV_simulink_TCN', true);
%
% The model is expected to be copied from LPVMPC_AGV_simulink_Modern_TCN.
% This function keeps the same ports and signal wiring, then changes:
%   1) model PreLoadFcn -> preloadfcn_tcn
%   2) classifier MATLAB Function -> TCN_State_Classifier_sim

if nargin < 1 || isempty(model_name)
    model_name = 'LPVMPC_AGV_simulink_TCN';
end
if nargin < 2 || isempty(do_save)
    do_save = false;
end

if exist('init_project', 'file') == 2
    init_project();
end

load_system(model_name);
cleanup = onCleanup(@() close_system(model_name, 0));

set_param(model_name, 'PreLoadFcn', 'preloadfcn_tcn');

block_path = [model_name '/ModernTCN_State_Classifier'];
if getSimulinkBlockHandle(block_path) < 0
    block_path = [model_name '/TCN_State_Classifier'];
end
if getSimulinkBlockHandle(block_path) < 0
    error('TCN:MissingClassifierBlock', ...
        'Cannot find classifier block ModernTCN_State_Classifier or TCN_State_Classifier.');
end

rt = sfroot;
chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', block_path);
if isempty(chart)
    error('TCN:MissingClassifierChart', 'Block is not a MATLAB Function chart: %s', block_path);
end

chart.Script = sprintf([ ...
    'function [theta_hat, label_main, label_turn, conf_main] = ModernTCN_State_Classifier(y_raw, reset)\n' ...
    '%%#codegen\n' ...
    '[theta_hat, label_main, label_turn, conf_main] = TCN_State_Classifier_sim(y_raw, reset);\n' ...
    'end\n']);

fprintf('[TCN Simulink config] model: %s\n', model_name);
fprintf('  PreLoadFcn: preloadfcn_tcn\n');
fprintf('  classifier: %s -> TCN_State_Classifier_sim\n', block_path);

if do_save
    save_system(model_name);
    fprintf('  saved: yes\n');
else
    fprintf('  saved: no (pass do_save=true to persist changes)\n');
end
end
