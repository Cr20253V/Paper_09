function predictor = ModernTCN_load_predictor(seed, onnx_file)
% A2-local loader. It prevents ONNX import from generating files outside A2.
if nargin < 1 || isempty(seed), seed = 42; end
if nargin < 2 || isempty(onnx_file), error('A2:MissingONNX', 'A2 requires an explicit frozen ONNX path.'); end
if exist(onnx_file, 'file') ~= 2, error('A2:MissingONNX', 'Missing ONNX: %s', onnx_file); end

[folder,name] = fileparts(onnx_file);
meta_file = fullfile(folder, [name '_onnx_export.json']);
if exist(meta_file, 'file') ~= 2, error('A2:MissingONNXMeta', 'Missing export sidecar: %s', meta_file); end
meta = jsondecode(fileread(meta_file));

tools_dir = fileparts(mfilename('fullpath'));
generated_dir = fullfile(tools_dir, 'generated_layers_runtime');
if exist(generated_dir, 'dir') ~= 7, mkdir(generated_dir); end
addpath(generated_dir);
old = pwd;
cleanup = onCleanup(@() cd(old)); %#ok<NASGU>
cd(generated_dir);
namespace = sprintf('a2_%s_layers', regexprep(lower(name), '[^a-z0-9_]', '_'));
net = importNetworkFromONNX(onnx_file, Namespace=namespace);

shape = double(meta.input_shape(:).');
if numel(shape) ~= 3, error('A2:BadONNXShape', 'Expected [batch,time,feature] in sidecar.'); end
predictor = struct();
predictor.seed = seed;
predictor.onnx_file = string(onnx_file);
predictor.layer_root = string(generated_dir);
predictor.net = net;
predictor.input_size = shape(2:3);
predictor.onnx_input_size = shape;
predictor.input_augment = local_field(meta, 'input_augment', 'none');
predictor.delta_lag = local_field(meta, 'delta_lag', 1);
predictor.delta_pad = local_field(meta, 'delta_pad', 'zero');
predictor.lag_steps = double(local_field(meta, 'lag_steps', []));
predictor.lag_pad = local_field(meta, 'lag_pad', 'edge');
predictor.delta_clip_abs = double(local_field(meta, 'delta_clip_abs', 5));
predictor.raw_input_dim = double(local_field(meta, 'raw_input_dim', shape(3)));
predictor.augmented_input_dim = double(local_field(meta, 'augmented_input_dim', shape(3)));
predictor.raw_feature_contract = local_field(meta, 'raw_feature_contract', 'passive17_plus_all5');
predictor.main_labels = [1 2 3];
predictor.turn_labels = [-1 0 1];
predictor.theta_unit = "rad";
predictor.theta_output_unit = "deg";
end

function value = local_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
end

