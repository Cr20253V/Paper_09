function cfg = GRU_load_default_to_base(cfg_user)
%GRU_LOAD_DEFAULT_TO_BASE Load the frozen GRU model for Simulink tests.

if nargin < 1 || isempty(cfg_user)
    cfg_user = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
cfg = GRU_default_config(root);
cfg = local_overlay_cfg(cfg, cfg_user);

if exist(cfg.model_file, 'file') ~= 2
    error('GRU_load_default_to_base:MissingModel', 'Missing model file: %s', cfg.model_file);
end
if exist(cfg.meta_file, 'file') ~= 2
    error('GRU_load_default_to_base:MissingMeta', 'Missing meta file: %s', cfg.meta_file);
end

S = load(cfg.model_file, 'model');
M = load(cfg.meta_file, 'meta');
model = local_standardize_model(S.model);
meta = M.meta;

if exist('parameters', 'file') == 2
    params = parameters();
else
    params = struct('Ts', 0.01);
end

assignin('base', 'gru_model', model);
assignin('base', 'gru_meta', meta);
assignin('base', 'params', params);
assignin('base', 'gru_default_cfg', cfg);

fprintf('[GRU default] loaded seed=%d case=%s\n', cfg.seed, cfg.case_name);
fprintf('  model: %s\n', cfg.model_file);
fprintf('  meta : %s\n', cfg.meta_file);
end

function cfg = local_overlay_cfg(cfg, cfg_user)
names = fieldnames(cfg_user);
for i = 1:numel(names)
    cfg.(names{i}) = cfg_user.(names{i});
end
end

function model = local_standardize_model(model)
if ~isfield(model, 'seq_len') && isfield(model, 'cfg') && isfield(model.cfg, 'seq_len')
    model.seq_len = model.cfg.seq_len;
end
if ~isfield(model, 'class_labels_main')
    model.class_labels_main = {'flat', 'stall', 'slope'};
end
if ~isfield(model, 'class_labels_turn')
    model.class_labels_turn = {'right', 'straight', 'left'};
end
end
