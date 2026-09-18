function X_aug = ModernTCN_delta_lag_augment_window(X_window, lag, pad)
%MODERNTCN_DELTA_LAG_AUGMENT_WINDOW Build [X, X - lag(X,m)] for MATLAB wrappers.

if nargin < 2 || isempty(lag)
    lag = 1;
end
if nargin < 3 || isempty(pad)
    pad = 'zero';
end

X = single(X_window);
if ndims(X) == 3 && size(X,1) == 1
    X = squeeze(X);
end
if ~ismatrix(X)
    error('ModernTCN:BadDeltaInput', 'delta_lag augmentation expects a [T,F] or [1,T,F] window.');
end

lag = round(double(lag));
if lag <= 0
    error('ModernTCN:BadDeltaLag', 'delta_lag 必须为正整数。');
end
if ~strcmpi(strtrim(char(pad)), 'zero')
    error('ModernTCN:BadDeltaPad', '当前只支持 delta_pad=zero。');
end

[seq_len, ~] = size(X);
if lag >= seq_len
    error('ModernTCN:BadDeltaLag', 'delta_lag 必须满足 1 <= lag < seq_len。');
end

delta = zeros(size(X), 'like', X);
delta((lag + 1):end, :) = X((lag + 1):end, :) - X(1:end-lag, :);
X_aug = [X, delta];
end
