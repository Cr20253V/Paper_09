function output = TCN_predict_window(predictor, X_window)
%TCN_PREDICT_WINDOW Run one normalized TCN window through the MATLAB model.
%
% Input:
%   X_window: [128,22] normalized window in [time, feature] order.
%
% Output labels:
%   main_state = 1/2/3 for flat/stall/slope.
%   turn_state = -1/0/1 for right/straight/left.

if nargin < 2
    error('TCN:MissingInput', '需要 predictor 和 X_window 两个输入。');
end
if ~isstruct(predictor) || ~isfield(predictor, 'net') || ~isfield(predictor, 'heads')
    error('TCN:InvalidPredictor', 'predictor 必须来自 TCN_load_predictor。');
end

X = local_prepare_single_window(X_window, predictor.input_size);
[logits_main, logits_turn, theta_hat_rad] = local_predict_one( ...
    predictor.net, predictor.heads, X, predictor.cfg);

main_prob = local_softmax(logits_main);
turn_prob = local_softmax(logits_turn);

[main_confidence, main_idx] = max(main_prob, [], 2);
[turn_confidence, turn_idx] = max(turn_prob, [], 2);

output = struct();
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

function X = local_prepare_single_window(X_window, expected_size)
X = single(X_window);
sz = size(X);

if ismatrix(X)
    if isequal(sz, expected_size)
        % keep [time, feature]
    elseif isequal(sz, fliplr(expected_size))
        error('TCN:WrongWindowShape', ...
            ['输入尺寸是 [%d,%d]，看起来像 [feature,time]。', ...
             '请转置成 [time,feature] = %s 后再调用。'], sz(1), sz(2), mat2str(expected_size));
    else
        error('TCN:WrongWindowShape', ...
            '输入窗口必须是 %s，当前尺寸是 %s。', mat2str(expected_size), mat2str(sz));
    end
elseif ndims(X) == 3
    if isequal(sz, [1 expected_size])
        X = squeeze(X(1,:,:));
    else
        error('TCN:WrongWindowShape', ...
            '三维输入必须是 %s，当前尺寸是 %s。', mat2str([1 expected_size]), mat2str(sz));
    end
else
    error('TCN:WrongWindowShape', '输入窗口维度不支持。');
end
end

function [logits_main, logits_turn, theta_hat] = local_predict_one(net, heads, X_window, cfg)
X = dlarray(permute(X_window, [2 1 3]), 'CBT'); % [feature,time,batch]
Z = predict(net, X);
[H, H_inputstats] = local_temporal_readout(Z, X, cfg);
H_turn = local_turn_readout(H, H_inputstats, cfg);

main_W = dlarray(heads.main_W);
main_b = dlarray(heads.main_b);
theta_W = dlarray(heads.theta_W);
theta_b = dlarray(heads.theta_b);

logits_main = main_W * H + main_b;
logits_turn = local_turn_logits(heads, H_turn, cfg);
theta_hat = theta_W * H + theta_b;

logits_main = local_to_batch_first(local_extract(logits_main), 3);
logits_turn = local_to_batch_first(local_extract(logits_turn), 3);
theta_hat = local_to_batch_first(local_extract(theta_hat), 1);
end

function H_turn = local_turn_readout(H, H_inputstats, cfg)
switch lower(char(cfg.turn_head_source))
    case 'readout'
        H_turn = H;
    case 'inputstats'
        H_turn = H_inputstats;
    otherwise
        error('TCN:BadTurnHeadSource', '未知 turn_head_source: %s', cfg.turn_head_source);
end
end

function logits = local_turn_logits(heads, H_turn, cfg)
switch lower(char(cfg.turn_head_type))
    case 'linear'
        logits = dlarray(heads.turn_W) * H_turn + dlarray(heads.turn_b);
    case 'mlp'
        A = max(dlarray(heads.turn_W1) * H_turn + dlarray(heads.turn_b1), 0);
        logits = dlarray(heads.turn_W2) * A + dlarray(heads.turn_b2);
    otherwise
        error('TCN:BadTurnHead', '未知 turn_head_type: %s', cfg.turn_head_type);
end
end

function [H, H_inputstats] = local_temporal_readout(Z, X, cfg)
H_inputstats = local_input_stats_readout(X);
switch lower(char(cfg.head_pooling))
    case 'last'
        H = Z(:, end, :);
    case 'last_mean_max'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max);
    case 'last_mean_max_inputstats'
        H_last = Z(:, end, :);
        H_mean = mean(Z, 2);
        H_max = max(Z, [], 2);
        H = cat(1, H_last, H_mean, H_max, H_inputstats);
    otherwise
        error('TCN:BadHeadPooling', '未知 head_pooling: %s', cfg.head_pooling);
end
H = reshape(H, size(H,1), []);
H_inputstats = reshape(H_inputstats, size(H_inputstats,1), []);
end

function H = local_input_stats_readout(X)
X_last = X(:, end, :);
X_mean = mean(X, 2);
X_std = sqrt(mean((X - X_mean).^2, 2) + 1e-8);
X_max = max(X, [], 2);
X_min = min(X, [], 2);
H = cat(1, X_last, X_mean, X_std, X_max, X_min);
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
Z = single(Z);
Z = Z - max(Z, [], 2);
E = exp(Z);
P = E ./ sum(E, 2);
P = single(P);
end
