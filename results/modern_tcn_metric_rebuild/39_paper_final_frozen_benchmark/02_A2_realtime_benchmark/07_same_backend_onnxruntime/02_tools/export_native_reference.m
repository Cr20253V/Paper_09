function export_native_reference()
% Generate untimed MATLAB-native outputs for all 3602 frozen test windows.

tools_dir = fileparts(mfilename('fullpath'));
ort_root = fileparts(tools_dir);
project_root = local_project_root(ort_root);
addpath(fullfile(project_root, 'src', 'TCN'));
addpath(fullfile(project_root, 'src', 'gru'));
validation_dir = fullfile(ort_root, '04_validation');
if exist(validation_dir, 'dir') ~= 7, mkdir(validation_dir); end
output_file = fullfile(validation_dir, 'matlab_native_reference_seed42.mat');
if exist(output_file, 'file') == 2
    error('A2ORT:RefuseOverwrite', 'Native reference already exists: %s', output_file);
end

dataset_file = fullfile(project_root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat');
tcn_file = fullfile(project_root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '01_A1_algorithm_comparison', ...
    '02_models', 'models', 'TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed42.mat');
gru_file = fullfile(project_root, 'results', 'modern_tcn_metric_rebuild', ...
    '34_gru_10seed_comparator', '01_train_gru_10seed', 'models', ...
    'GRU_model_gru10_full_gru_v5_plantfix_passive17_plus_all5_seed42.mat');

D = load(dataset_file, 'dataset');
X = single(D.dataset.X_test);
n = size(X, 1);
tcn = TCN_load_predictor(tcn_file);
G = load(gru_file, 'model');

tcn_main_prob = zeros(n, 3, 'single');
tcn_turn_prob = zeros(n, 3, 'single');
tcn_theta = zeros(n, 1, 'single');
gru_main_prob = zeros(n, 3, 'single');
gru_turn_prob = zeros(n, 3, 'single');
gru_theta = zeros(n, 1, 'single');
for i = 1:n
    window = squeeze(X(i,:,:));
    out = TCN_predict_window(tcn, window);
    tcn_main_prob(i,:) = single(out.main_prob);
    tcn_turn_prob(i,:) = single(out.turn_prob);
    tcn_theta(i) = single(out.theta_hat_rad);
    [~,~,theta,conf] = GRU_infer(window, G.model);
    gru_main_prob(i,:) = single(conf.conf_main(:).');
    gru_turn_prob(i,:) = single(conf.conf_turn(:).');
    gru_theta(i) = single(theta);
    if mod(i, 500) == 0, fprintf('Native reference: %d/%d\n', i, n); end
end
test_index = uint32((1:n).'); %#ok<NASGU>
save(output_file, 'test_index', 'tcn_main_prob', 'tcn_turn_prob', 'tcn_theta', ...
    'gru_main_prob', 'gru_turn_prob', 'gru_theta', '-v7');
fprintf('MATLAB native reference complete: %d windows.\n', n);
end

function root = local_project_root(start_dir)
root = start_dir;
marker = fullfile('results', 'paper', '7.6', 'A0_论文最终统一实验配置_20260715.json');
while true
    if exist(fullfile(root, marker), 'file') == 2, return; end
    parent = fileparts(root);
    if strcmp(parent, root), error('A2ORT:RootNotFound', 'Cannot locate project root.'); end
    root = parent;
end
end

