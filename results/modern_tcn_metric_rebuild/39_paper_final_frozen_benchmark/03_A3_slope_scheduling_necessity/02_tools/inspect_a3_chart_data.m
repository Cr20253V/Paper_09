root = 'E:\Matlab\Simulink\S-Function_16';
addpath(root, genpath(fullfile(root, 'src')));
a3 = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '03_A3_slope_scheduling_necessity');
addpath(fullfile(a3, '02_tools'));
assignin('base', 'a3_theta_mode', 1.0);
model_file = fullfile(a3, '00_protocol_lock', 'a3.slx');
load_system(model_file);
[~, model] = fileparts(model_file);
rt = sfroot;
charts = rt.find('-isa', 'Stateflow.EMChart');
for i = 1:numel(charts)
    if ~strcmp(bdroot(charts(i).Path), model), continue; end
    if ~ismember(charts(i).Name, {'ModernTCN_State_Classifier','ThetaScheduleGuard'}), continue; end
    fprintf('CHART %s\n%s\n', charts(i).Path, charts(i).Script);
    d = charts(i).find('-isa', 'Stateflow.Data');
    for k = 1:numel(d)
        sz = '';
        try, sz = d(k).Props.Array.Size; catch, end
        fprintf('DATA name=%s scope=%s port=%g type=%s size=%s\n', ...
            d(k).Name, d(k).Scope, d(k).Port, d(k).DataType, sz);
    end
end
close_system(model, 0);
