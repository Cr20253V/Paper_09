root = 'E:\Matlab\Simulink\S-Function_16';
addpath(root, genpath(fullfile(root, 'src')));
init_project();
a3 = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '03_A3_slope_scheduling_necessity');
addpath(fullfile(a3, '02_tools'));
run_a3_experiment('full');
