function output = ModernTCN_predict_window(predictor, X_window)
%MODERNTCN_PREDICT_WINDOW 使用已加载的 ModernTCN 对单个时间窗口做在线推理。
%
% 功能说明：
%   输入一个已经归一化、特征顺序与训练数据一致的窗口，输出主工况、
%   转弯状态、坡度角预测值和对应概率。该函数只做推理和后处理，不做 scaler
%   归一化，也不改变特征顺序。若 predictor 来自增强输入模型，它会先把
%   raw [T,22] 窗口扩成训练时的增强维度再送入 ONNX。

if nargin < 2
    error('ModernTCN:MissingInput', '需要 predictor 和 X_window 两个输入。');
end
if ~isstruct(predictor) || ~isfield(predictor, 'net')
    error('ModernTCN:InvalidPredictor', 'predictor 必须来自 ModernTCN_load_predictor。');
end

input_size = local_predictor_size(predictor, 'input_size', [128 22]);
input_augment = strtrim(char(local_predictor_text(predictor, 'input_augment', 'none')));
if ~strcmpi(input_augment, 'none')
    X = local_prepare_augmented_window(X_window, predictor, input_size);
else
    X = local_prepare_exact_window(X_window, input_size);
end
[logits_main, logits_turn, theta_hat_rad] = local_predict_one(predictor.net, X);

main_prob = local_softmax(logits_main);
turn_prob = local_softmax(logits_turn);

[main_confidence, main_idx] = max(main_prob, [], 2);
[turn_confidence, turn_idx] = max(turn_prob, [], 2);

output = struct();
output.seed = predictor.seed;
output.main_state = predictor.main_labels(main_idx);
output.turn_state = predictor.turn_labels(turn_idx);
output.theta_hat_rad = double(theta_hat_rad(1));
output.theta_hat_deg = rad2deg(double(theta_hat_rad(1)));
output.main_prob = main_prob(1,:);
output.turn_prob = turn_prob(1,:);
output.main_confidence = main_confidence(1);
output.turn_confidence = turn_confidence(1);
output.logits_main = logits_main(1,:);
output.logits_turn = logits_turn(1,:);
end

function X = local_prepare_exact_window(X_window, expected_size)
X = single(X_window);
sz = size(X);

if ismatrix(X)
    if isequal(sz, expected_size)
        X = reshape(X, [1 expected_size]);
    elseif isequal(sz, fliplr(expected_size))
        error('ModernTCN:WrongWindowShape', ...
            ['输入尺寸是 [%d,%d]，看起来像 [feature,time]。', ...
             '请转置成 [time,feature] = %s 后再调用。'], sz(1), sz(2), mat2str(expected_size));
    else
        error('ModernTCN:WrongWindowShape', ...
            '输入窗口必须是 %s 或 %s，当前尺寸是 %s。', ...
            mat2str(expected_size), mat2str([1 expected_size]), mat2str(sz));
    end
elseif ndims(X) == 3
    if ~isequal(sz, [1 expected_size])
        error('ModernTCN:WrongWindowShape', ...
            '三维输入必须是 %s，当前尺寸是 %s。', mat2str([1 expected_size]), mat2str(sz));
    end
else
    error('ModernTCN:WrongWindowShape', ...
        '输入窗口维度不支持，必须是二维或三维数组。');
end
end

function X = local_prepare_augmented_window(X_window, predictor, expected_size)
X = single(X_window);
sz = size(X);
seq_len = expected_size(1);
raw_dim = local_predictor_double(predictor, 'raw_input_dim', expected_size(2));
aug_dim = local_predictor_double(predictor, 'augmented_input_dim', expected_size(2));
predictor.seq_len = seq_len;

if ismatrix(X)
    if isequal(sz, [seq_len, raw_dim])
        X = reshape(local_checked_augment(X, predictor, aug_dim), [1 seq_len aug_dim]);
    elseif isequal(sz, [seq_len, aug_dim])
        X = reshape(X, [1 seq_len aug_dim]);
    elseif isequal(sz, fliplr([seq_len, raw_dim])) || isequal(sz, fliplr([seq_len, aug_dim]))
        error('ModernTCN:WrongWindowShape', ...
            ['输入尺寸是 [%d,%d]，看起来像 [feature,time]。', ...
             '请转置成 [time,feature] 后再调用。'], sz(1), sz(2));
    else
        error('ModernTCN:WrongWindowShape', ...
            '增强输入窗口必须是 %s 或 %s，当前尺寸是 %s。', ...
            mat2str([seq_len raw_dim]), mat2str([seq_len aug_dim]), mat2str(sz));
    end
elseif ndims(X) == 3
    if isequal(sz, [1 seq_len raw_dim])
        X = reshape(local_checked_augment(reshape(X, [seq_len raw_dim]), predictor, aug_dim), [1 seq_len aug_dim]);
    elseif isequal(sz, [1 seq_len aug_dim])
        % Already augmented; accept as-is.
    else
        error('ModernTCN:WrongWindowShape', ...
            '增强输入三维窗口必须是 %s 或 %s，当前尺寸是 %s。', ...
            mat2str([1 seq_len raw_dim]), mat2str([1 seq_len aug_dim]), mat2str(sz));
    end
else
    error('ModernTCN:WrongWindowShape', ...
        '输入窗口维度不支持，必须是二维或三维数组。');
end
end

function X_aug = local_checked_augment(X, predictor, aug_dim)
X_aug = ModernTCN_augment_window(X, predictor);
if size(X_aug, 2) ~= aug_dim
    error('ModernTCN:AugmentDimMismatch', ...
        'input augmentation produced feature dim %d, expected %d.', size(X_aug, 2), aug_dim);
end
end

function [logits_main, logits_turn, theta_hat] = local_predict_one(net, X)
% 兼容不同 MATLAB ONNX importer 对 [batch,time,feature] 的解释。
try
    [logits_main, logits_turn, theta_hat] = predict(net, X);
catch
    try
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(X, "BTC"));
    catch
        % 如果 importer 按 [feature,time,batch] 读取，则转为 CTB。
        Xctb = permute(X, [3 2 1]);
        [logits_main, logits_turn, theta_hat] = predict(net, dlarray(Xctb, "CTB"));
    end
end

logits_main = local_to_batch_first(local_extract(logits_main), 3);
logits_turn = local_to_batch_first(local_extract(logits_turn), 3);
theta_hat = local_to_batch_first(local_extract(theta_hat), 1);
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

function P = local_softmax(Z)
% 数值稳定 softmax，避免依赖不同 MATLAB 版本中的同名函数行为。
Z = single(Z);
Z = Z - max(Z, [], 2);
E = exp(Z);
P = E ./ sum(E, 2);
P = single(P);
end

function size_out = local_predictor_size(predictor, field_name, default_value)
size_out = default_value;
if isstruct(predictor) && isfield(predictor, field_name) && ~isempty(predictor.(field_name))
    value = double(predictor.(field_name));
    if numel(value) >= 2
        size_out = value(1:2);
    end
end
end

function v = local_predictor_text(predictor, field_name, default_value)
v = string(default_value);
if isstruct(predictor) && isfield(predictor, field_name) && ~isempty(predictor.(field_name))
    v = string(predictor.(field_name));
end
end

function v = local_predictor_double(predictor, field_name, default_value)
v = double(default_value);
if isstruct(predictor) && isfield(predictor, field_name) && ~isempty(predictor.(field_name))
    raw = double(predictor.(field_name));
    if isfinite(raw)
        v = raw;
    end
end
end
