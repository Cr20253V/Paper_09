function p = node53_v7_predict_help(model, x)
%NODE53_V7_PREDICT_HELP Evaluate the exported V7 HistGradientBoosting gate.
x = double(x(:)).';
if numel(x) ~= double(model.feature_count)
    error('node53:V7FeatureCount','Expected %d features, got %d.', model.feature_count, numel(x));
end
raw = double(model.baseline_prediction);
for t = 1:numel(model.trees)
    tr = model.trees(t);
    node = 1;
    while tr.is_leaf(node) == 0
        f = tr.feature_idx(node) + 1;
        b = local_bin(x(f), model.bin_thresholds{f});
        if ~isfinite(x(f))
            go_left = tr.missing_go_to_left(node) ~= 0;
        else
            go_left = b <= tr.bin_threshold(node);
        end
        if go_left
            node = tr.left(node) + 1;
        else
            node = tr.right(node) + 1;
        end
    end
    raw = raw + tr.value(node);
end
p = 1 ./ (1 + exp(-raw));
p = max(0, min(1, p));
end

function b = local_bin(v, thresholds)
thresholds = double(thresholds(:));
b = sum(v > thresholds);
end
