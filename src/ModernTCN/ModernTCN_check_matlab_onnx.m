function result = ModernTCN_check_matlab_onnx(onnx_file, sample_file)
%MODERNTCN_CHECK_MATLAB_ONNX 导入 ModernTCN ONNX 并和 PyTorch 输出做离线一致性检查。
%
% 用法：
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'ModernTCN'));
%   result = ModernTCN_check_matlab_onnx();
%
% 说明：
%   该脚本只做离线 test window 推理检查，不接入 Simulink。输入固定为
%   [batch, time=128, feature=input_dim]，输出固定为 logits_main、logits_turn、
%   theta_hat。通过该检查后，才建议继续写 MATLAB 在线封装。

if nargin < 1 || isempty(onnx_file)
    default_cfg = ModernTCN_default_config(project_root());
    onnx_file = default_cfg.onnx_file;
end
if nargin < 2 || isempty(sample_file)
    default_cfg = ModernTCN_default_config(project_root());
    sample_file = default_cfg.pytorch_reference_file;
end

if exist(onnx_file, 'file') ~= 2
    error('ModernTCN:MissingONNX', '找不到 ONNX 文件: %s', onnx_file);
end
if exist(sample_file, 'file') ~= 2
    error('ModernTCN:MissingSample', '找不到 PyTorch 参考样本: %s', sample_file);
end

S = load(sample_file);
X = single(S.X_sample);

% R2024b 的 importNetworkFromONNX 已直接返回 dlnetwork，不支持旧
% importONNXNetwork 中的 TargetNetwork 参数。ONNX importer 对部分算子会
% 自动生成 MATLAB custom layer package；这里把生成目录固定到
% src/ModernTCN/generated_layers，避免在项目根目录生成 +modern_tcn_seed*
% 这类临时 package 文件夹。
net = local_import_modern_tcn_onnx(onnx_file);
[logits_main, logits_turn, theta_hat] = local_predict_all_windows(net, X);

result = struct();
result.onnx_file = onnx_file;
result.sample_file = sample_file;
result.logits_main = local_diff(logits_main, single(S.logits_main_pytorch));
result.logits_turn = local_diff(logits_turn, single(S.logits_turn_pytorch));
result.theta_hat = local_diff(theta_hat, single(S.theta_hat_pytorch));
result.max_abs_tol = 1e-4;
result.mean_abs_tol = 1e-5;
result.pass = result.logits_main.max_abs_error <= result.max_abs_tol ...
    && result.logits_main.mean_abs_error <= result.mean_abs_tol ...
    && result.logits_turn.max_abs_error <= result.max_abs_tol ...
    && result.logits_turn.mean_abs_error <= result.mean_abs_tol ...
    && result.theta_hat.max_abs_error <= result.max_abs_tol ...
    && result.theta_hat.mean_abs_error <= result.mean_abs_tol;

[out_dir, onnx_name] = fileparts(onnx_file);
mat_file = fullfile(out_dir, sprintf('%s_matlab_consistency.mat', onnx_name));
md_file = fullfile(out_dir, sprintf('%s_matlab_consistency.md', onnx_name));
save(mat_file, 'result');
local_write_report(md_file, result);

fprintf('[ModernTCN MATLAB ONNX] pass=%d\n', result.pass);
fprintf('  mat: %s\n', mat_file);
fprintf('  report: %s\n', md_file);
end

function net = local_import_modern_tcn_onnx(onnx_file)
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
meta = local_onnx_meta(onnx_file);
layer_root = fullfile(root, 'src', 'ModernTCN', 'generated_layers');
if exist(layer_root, 'dir') ~= 7
    mkdir(layer_root);
end
addpath(layer_root);
old_dir = pwd;
cleanup = onCleanup(@() cd(old_dir));
cd(layer_root);
net = importNetworkFromONNX(onnx_file, Namespace=local_onnx_namespace(onnx_file, meta));
end

function namespace = local_onnx_namespace(onnx_file, meta)
input_augment = local_meta_text(meta, 'input_augment', 'none');
if strcmpi(input_augment, 'delta_lag')
    delta_lag = round(local_meta_double(meta, 'delta_lag', 0));
    if delta_lag > 0
        namespace = sprintf("modern_tcn_delta_lag%d_onnx_layers", delta_lag);
    else
        namespace = "modern_tcn_delta_lag_onnx_layers";
    end
    return;
end
if any(strcmpi(input_augment, {'lag_stack','delta_bank','mixed_lag_delta'}))
    namespace = sprintf("modern_tcn_%s_%s_onnx_layers", ...
        char(input_augment), local_lag_suffix(local_meta_vector(meta, 'lag_steps', [])));
    return;
end
if strcmpi(input_augment, 'physics_residual_8')
    namespace = "modern_tcn_physics_residual8_onnx_layers";
    return;
end
if local_meta_double(meta, 'augmented_input_dim', 0) > local_meta_double(meta, 'raw_input_dim', 0)
    namespace = "modern_tcn_augmented_onnx_layers";
    return;
end

model_family = local_onnx_model_family(onnx_file, meta);
if strcmpi(model_family, 'small_gffn') || contains(lower(char(onnx_file)), 'gffn')
    namespace = "modern_tcn_gffn_onnx_layers";
elseif strcmpi(model_family, 'small_dualkernel') || contains(lower(char(onnx_file)), 'dualkernel') || contains(lower(char(onnx_file)), 'dual_kernel')
    namespace = "modern_tcn_dualkernel_onnx_layers";
elseif contains(lower(char(onnx_file)), 'causal')
    namespace = "modern_tcn_causal_onnx_layers";
else
    namespace = "modern_tcn_onnx_layers";
end
end

function model_family = local_onnx_model_family(onnx_file, meta)
model_family = "";
if nargin >= 2 && isstruct(meta) && isfield(meta, 'model_family')
    model_family = string(meta.model_family);
    return;
end
[folder, name, ~] = fileparts(char(onnx_file));
meta_file = fullfile(folder, [name '_onnx_export.json']);
if exist(meta_file, 'file') ~= 2
    return;
end
try
    meta = jsondecode(fileread(meta_file));
    if isfield(meta, 'model_family')
        model_family = string(meta.model_family);
    end
catch
    model_family = "";
end
end

function meta = local_onnx_meta(onnx_file)
meta = struct();
[folder, name, ~] = fileparts(char(onnx_file));
meta_file = fullfile(folder, [name '_onnx_export.json']);
if exist(meta_file, 'file') ~= 2
    return;
end
try
    meta = jsondecode(fileread(meta_file));
catch
    meta = struct();
end
end

function v = local_meta_text(meta, field_name, default_value)
v = string(default_value);
if isstruct(meta) && isfield(meta, field_name) && ~isempty(meta.(field_name))
    v = string(meta.(field_name));
end
end

function v = local_meta_double(meta, field_name, default_value)
v = double(default_value);
if isstruct(meta) && isfield(meta, field_name) && ~isempty(meta.(field_name))
    raw = double(meta.(field_name));
    if isfinite(raw)
        v = raw;
    end
end
end

function v = local_meta_vector(meta, field_name, default_value)
v = double(default_value);
if isstruct(meta) && isfield(meta, field_name) && ~isempty(meta.(field_name))
    raw = double(meta.(field_name));
    raw = raw(:).';
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        v = raw;
    end
end
end

function suffix = local_lag_suffix(steps)
steps = round(double(steps(:).'));
steps = steps(isfinite(steps) & steps > 0);
if isempty(steps)
    suffix = "custom";
else
    suffix = string(strjoin(arrayfun(@(x) sprintf('%d', x), steps, 'UniformOutput', false), ''));
end
end

function [logits_main, logits_turn, theta_hat] = local_predict_all_windows(net, X)
% ONNX 第一版固定 batch=1，更接近在线单窗口部署；离线一致性检查逐窗口拼接。
n = size(X, 1);
logits_main = zeros(n, 3, 'single');
logits_turn = zeros(n, 3, 'single');
theta_hat = zeros(n, 1, 'single');
for i = 1:n
    [lm, lt, th] = local_predict_modern_tcn(net, X(i,:,:));
    logits_main(i,:) = lm(1,:);
    logits_turn(i,:) = lt(1,:);
    theta_hat(i,:) = th(1,:);
end
end

function [logits_main, logits_turn, theta_hat] = local_predict_modern_tcn(net, X)
% 尽量兼容不同 MATLAB ONNX importer 对 NTC/CBT 维度的解释。
try
    [logits_main, logits_turn, theta_hat] = predict(net, X);
catch
    try
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(X, "BTC"));
    catch
        % 若 importer 将输入解释为 CBT，可手动转成 [feature,time,batch]。
        Xcbt = permute(X, [3 2 1]);
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(Xcbt, "CTB"));
    end
end

logits_main = local_extract(logits_main);
logits_turn = local_extract(logits_turn);
theta_hat = local_extract(theta_hat);
logits_main = local_to_batch_first(logits_main, 3);
logits_turn = local_to_batch_first(logits_turn, 3);
theta_hat = local_to_batch_first(theta_hat, 1);
end

function A = local_extract(A)
if isa(A, 'dlarray')
    A = gather(extractdata(A));
else
    A = gather(A);
end
end

function A = local_to_batch_first(A, width)
A = squeeze(A);
if size(A, 2) ~= width && size(A, 1) == width
    A = A.';
end
if width == 1
    A = reshape(A, [], 1);
end
A = single(A);
end

function d = local_diff(A, B)
d = struct();
D = abs(single(A) - single(B));
d.max_abs_error = max(D(:));
d.mean_abs_error = mean(D(:));
end

function local_write_report(md_file, result)
fid = fopen(md_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', '无法写入报告: %s', md_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# ModernTCN MATLAB ONNX 一致性检查\n\n');
fprintf(fid, '- onnx: `%s`\n', result.onnx_file);
fprintf(fid, '- sample: `%s`\n', result.sample_file);
fprintf(fid, '- pass: `%d`\n\n', result.pass);
fprintf(fid, '| output | max abs error | mean abs error |\n');
fprintf(fid, '|---|---:|---:|\n');
fprintf(fid, '| logits_main | %.6g | %.6g |\n', ...
    result.logits_main.max_abs_error, result.logits_main.mean_abs_error);
fprintf(fid, '| logits_turn | %.6g | %.6g |\n', ...
    result.logits_turn.max_abs_error, result.logits_turn.mean_abs_error);
fprintf(fid, '| theta_hat | %.6g | %.6g |\n', ...
    result.theta_hat.max_abs_error, result.theta_hat.mean_abs_error);
end
