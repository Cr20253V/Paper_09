function result = GRU_check_v4_dataset_contract(dataset_file)
%GRU_CHECK_V4_DATASET_CONTRACT Check whether the V4 dataset can train GRU.
%
% This check is intentionally read-only. It verifies the fields and shapes
% required by GRU_train.m without starting a training run.

if nargin < 1 || isempty(dataset_file)
    if exist('init_project', 'file') == 2
        init_project();
    end
    dataset_file = fullfile(project_root(), 'data', 'tcn', 'ModernTCN_dataset_v4_industrial.mat');
end

if exist(dataset_file, 'file') ~= 2
    error('GRU:MissingDataset', 'Dataset not found: %s', dataset_file);
end

S = load(dataset_file, 'dataset');
dataset = S.dataset;

required = {'X_train','X_val','X_test', ...
    'y_main_train','y_main_val','y_main_test', ...
    'y_turn_train','y_turn_val','y_turn_test', ...
    'y_theta_train','y_theta_val','y_theta_test', ...
    'mask_theta_train','mask_theta_val','mask_theta_test', ...
    'scaler','feat_names','meta'};

missing = {};
for i = 1:numel(required)
    if ~isfield(dataset, required{i})
        missing{end+1} = required{i}; %#ok<AGROW>
    end
end

result = struct();
result.dataset_file = dataset_file;
result.missing_fields = missing;
result.pass = isempty(missing);

if ~isempty(missing)
    error('GRU:BadDataset', 'Dataset missing fields: %s', strjoin(missing, ', '));
end

result.n_train = size(dataset.X_train, 1);
result.n_val = size(dataset.X_val, 1);
result.n_test = size(dataset.X_test, 1);
result.seq_len = size(dataset.X_train, 2);
result.feat_dim = size(dataset.X_train, 3);
result.n_feat_names = numel(dataset.feat_names);
result.main_counts_train = local_counts(dataset.y_main_train, [1 2 3]);
result.turn_counts_train = local_counts(dataset.y_turn_train, [-1 0 1]);
result.theta_mask_train = nnz(dataset.mask_theta_train ~= 0);
result.has_turn_weights = isfield(dataset, 'turn_sample_weight_train');
result.has_transition_flags = isfield(dataset, 'turn_transition_train');

if result.feat_dim ~= result.n_feat_names
    error('GRU:FeatureMismatch', 'feat_dim=%d but feat_names=%d.', ...
        result.feat_dim, result.n_feat_names);
end
if result.seq_len ~= 128
    warning('GRU:SeqLen', 'Expected seq_len=128 for V4 comparison, got %d.', result.seq_len);
end

fprintf('[GRU V4 dataset check] pass=%d\n', result.pass);
fprintf('  dataset: %s\n', dataset_file);
fprintf('  windows train/val/test: %d / %d / %d\n', ...
    result.n_train, result.n_val, result.n_test);
fprintf('  seq_len=%d feat_dim=%d\n', result.seq_len, result.feat_dim);
fprintf('  train main counts [flat stall slope]=[%d %d %d]\n', result.main_counts_train);
fprintf('  train turn counts [right straight left]=[%d %d %d]\n', result.turn_counts_train);
fprintf('  theta train mask count=%d\n', result.theta_mask_train);
end

function c = local_counts(labels, order)
c = zeros(1, numel(order));
for i = 1:numel(order)
    c(i) = nnz(labels(:) == order(i));
end
end
