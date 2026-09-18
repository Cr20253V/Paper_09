function export_matlab_models()
% Export the frozen TCN/GRU feature networks and immutable head weights.
% This is a preparation operation, not a formal timing operation.

tools_dir = fileparts(mfilename('fullpath'));
ort_root = fileparts(tools_dir);
project_root = local_project_root(ort_root);
derived = fullfile(ort_root, '03_derived_models');
if exist(derived, 'dir') ~= 7, mkdir(derived); end

tcn_file = fullfile(project_root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '01_A1_algorithm_comparison', ...
    '02_models', 'models', 'TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed42.mat');
gru_file = fullfile(project_root, 'results', 'modern_tcn_metric_rebuild', ...
    '34_gru_10seed_comparator', '01_train_gru_10seed', 'models', ...
    'GRU_model_gru10_full_gru_v5_plantfix_passive17_plus_all5_seed42.mat');

local_export_one(tcn_file, 'tcn_22d_seed42', derived);
local_export_one(gru_file, 'gru_22d_seed42', derived);
fprintf('MATLAB feature-network export complete.\n');
end

function local_export_one(model_file, stem, output_dir)
S = load(model_file, 'model');
if ~isfield(S, 'model') || ~isfield(S.model, 'feature_net') || ...
        ~isfield(S.model, 'heads') || ~isfield(S.model, 'cfg')
    error('A2ORT:BadModel', 'Frozen model is missing feature_net/heads/cfg: %s', model_file);
end
feature_file = fullfile(output_dir, [stem '_feature.onnx']);
heads_file = fullfile(output_dir, [stem '_heads.mat']);
if exist(heads_file, 'file') == 2
    error('A2ORT:RefuseOverwrite', 'Derived head export already exists: %s', heads_file);
end
if exist(feature_file, 'file') ~= 2
    % The frozen authority inference labels [22,128,1] as CBT. Therefore
    % its 128 samples occupy the B axis and the T axis is length one. Use
    % BatchSize=128 to reproduce that exact semantics in the derivative.
    exportONNXNetwork(S.model.feature_net, feature_file, ...
        NetworkName=[stem '_feature'], OpsetVersion=17, BatchSize=128);
else
    fprintf('Reusing existing feature export: %s\n', feature_file);
end
heads = local_heads_to_single(S.model.heads); %#ok<NASGU>
cfg = struct( ...
    'input_size', double(S.model.cfg.input_size), ...
    'seq_len', double(local_field(S.model.cfg, 'seq_len', 128)), ...
    'head_pooling', char(S.model.cfg.head_pooling), ...
    'turn_head_source', char(S.model.cfg.turn_head_source), ...
    'turn_head_type', char(S.model.cfg.turn_head_type)); %#ok<NASGU>
save(heads_file, 'heads', 'cfg', '-v7');
end

function heads = local_heads_to_single(heads)
names = fieldnames(heads);
for i = 1:numel(names)
    value = heads.(names{i});
    if isa(value, 'dlarray'), value = extractdata(value); end
    heads.(names{i}) = single(gather(value));
end
end

function value = local_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
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
