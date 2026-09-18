function predictor = TCN_load_predictor(model_file)
%TCN_LOAD_PREDICTOR Load a trained MATLAB TCN model for online inference.
%
% The returned predictor is used by TCN_predict_window. It expects a
% normalized [128,22] window with the passive17_plus_all5 feature order.

root = local_project_root();
default_cfg = TCN_default_config(root);
if nargin < 1 || isempty(model_file)
    model_file = default_cfg.model_file;
end

if exist(model_file, 'file') ~= 2
    error('TCN:MissingModel', '找不到 TCN 模型文件: %s', model_file);
end

S = load(model_file, 'model');
if ~isfield(S, 'model')
    error('TCN:BadModelFile', '模型文件缺少变量 `model`: %s', model_file);
end
model = S.model;

required = {'feature_net','heads','scaler','cfg'};
for i = 1:numel(required)
    if ~isfield(model, required{i})
        error('TCN:BadModel', 'TCN model missing field `%s`.', required{i});
    end
end

seq_len = 128;
if isfield(model.cfg, 'seq_len') && ~isempty(model.cfg.seq_len)
    seq_len = model.cfg.seq_len;
end
feat_dim = numel(model.scaler.mean);
if isfield(model.cfg, 'input_size') && ~isempty(model.cfg.input_size)
    feat_dim = model.cfg.input_size;
end

predictor = struct();
predictor.model_file = string(model_file);
predictor.net = model.feature_net;
predictor.heads = local_heads_to_single(model.heads);
predictor.cfg = model.cfg;
predictor.scaler = model.scaler;
predictor.feat_names = local_field_or_default(model, 'feat_names', {});
predictor.input_size = [seq_len feat_dim];       % [time, feature]
predictor.main_labels = [1 2 3];                 % 1=flat, 2=stall, 3=slope
predictor.turn_labels = [-1 0 1];                % -1=right, 0=straight, 1=left
predictor.theta_unit = "rad";
predictor.theta_output_unit = "deg";
end

function heads = local_heads_to_single(heads)
names = fieldnames(heads);
for i = 1:numel(names)
    heads.(names{i}) = single(gather(heads.(names{i})));
end
end

function v = local_field_or_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
