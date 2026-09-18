function predictor = ModernTCN_load_predictor(seed, onnx_file)
%MODERNTCN_LOAD_PREDICTOR Node53 worker-isolated ONNX importer.
root = project_root();
if nargin < 1 || isempty(seed); seed = 42; end
if nargin < 2 || isempty(onnx_file)
    cfg = ModernTCN_default_config(root);
    onnx_file = cfg.onnx_file;
end
onnx_file = char(onnx_file);
if exist(onnx_file, 'file') ~= 2
    error('ModernTCN:MissingONNX', 'ONNX file not found: %s', onnx_file);
end
meta_file = strrep(onnx_file, '.onnx', '_onnx_export.json');
meta = struct();
if exist(meta_file, 'file') == 2; meta = jsondecode(fileread(meta_file)); end
worker = 'serial';
try
    worker = char(evalin('base', 'node53_worker_id'));
catch
end
worker = regexprep(worker, '[^A-Za-z0-9_-]', '_');
layer_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '53_moderntcn_fuzzyakf6d_fusion_rebuild', 'cache', 'workers', worker, 'generated_layers');
if exist(layer_root, 'dir') ~= 7; mkdir(layer_root); end
addpath(layer_root, '-begin');
old_dir = pwd; cleanup = onCleanup(@() cd(old_dir)); %#ok<NASGU>
cd(layer_root);
net = importNetworkFromONNX(onnx_file, Namespace=local_namespace(meta));
shape = local_shape(meta);
predictor = struct('seed',double(seed),'onnx_file',string(onnx_file), ...
    'layer_root',string(layer_root),'net',net,'input_size',shape, ...
    'onnx_input_size',[1 shape],'input_augment',local_text(meta,'input_augment','none'), ...
    'delta_lag',local_num(meta,'delta_lag',1),'delta_pad',local_text(meta,'delta_pad','zero'), ...
    'lag_steps',local_vec(meta,'lag_steps',[]),'lag_pad',local_text(meta,'lag_pad','edge'), ...
    'delta_clip_abs',local_num(meta,'delta_clip_abs',5), ...
    'raw_input_dim',local_num(meta,'raw_input_dim',shape(2)), ...
    'augmented_input_dim',local_num(meta,'augmented_input_dim',shape(2)), ...
    'raw_feature_contract',local_text(meta,'raw_feature_contract',''), ...
    'raw_feature_mean',local_vec(meta,'raw_feature_mean',[]), ...
    'raw_feature_std',local_vec(meta,'raw_feature_std',[]), ...
    'physics_feature_mean',local_vec(meta,'physics_feature_mean',[]), ...
    'physics_feature_std',local_vec(meta,'physics_feature_std',[]), ...
    'physics_clip_abs',local_num(meta,'physics_clip_abs',8), ...
    'physics_params',local_struct(meta,'physics_params',struct()), ...
    'physics_feature_names',local_cellstr(meta,'physics_feature_names'), ...
    'source_feature_names',local_cellstr(meta,'source_feature_names'), ...
    'forbidden_source_features',local_cellstr(meta,'forbidden_source_features'), ...
    'main_labels',[1 2 3],'turn_labels',[-1 0 1], ...
    'theta_unit',"rad",'theta_output_unit',"deg");
end

function shape = local_shape(meta)
shape = [128 88];
if isfield(meta,'input_shape') && numel(meta.input_shape) >= 3
    s = double(meta.input_shape(:).'); shape = s(end-1:end);
end
end
function ns = local_namespace(meta)
kind = local_text(meta,'input_augment','none'); lag = local_vec(meta,'lag_steps',[]);
if any(strcmpi(kind,{'lag_stack','delta_bank','mixed_lag_delta'}))
    ns = sprintf('modern_tcn_%s_%s_onnx_layers',kind,local_lag_suffix(lag));
else
    ns = sprintf('modern_tcn_%s_onnx_layers',kind);
end
end
function x = local_lag_suffix(v)
if isempty(v); x = 'none'; else; x = strjoin(arrayfun(@(q)sprintf('%d',q),double(v(:).'),'UniformOutput',false),'_'); end
end
function x = local_text(s,n,d); x=d; if isfield(s,n)&&~isempty(s.(n)); x=char(string(s.(n))); end; end
function x = local_num(s,n,d); x=d; if isfield(s,n)&&~isempty(s.(n)); x=double(s.(n)); end; end
function x = local_vec(s,n,d); x=d; if isfield(s,n)&&~isempty(s.(n)); x=double(s.(n)); end; end
function x = local_struct(s,n,d); x=d; if isfield(s,n)&&~isempty(s.(n)); x=s.(n); end; end
function x = local_cellstr(s,n); x={}; if isfield(s,n)&&~isempty(s.(n)); x=cellstr(string(s.(n))); end; end
