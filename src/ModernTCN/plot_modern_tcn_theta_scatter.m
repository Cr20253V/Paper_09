function result = plot_modern_tcn_theta_scatter(cfg)
%PLOT_MODERN_TCN_THETA_SCATTER Plot test-set theta truth vs prediction.
%
% The plot uses the shared ModernTCN test split and a MATLAB full-test output
% file produced by ModernTCN_matlab_full_testset_eval. It does not create or
% modify training samples.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
default_cfg = ModernTCN_default_config(root);
cfg = local_default(cfg, 'seed', default_cfg.seed);
cfg = local_default(cfg, 'run_tag', default_cfg.run_tag);
cfg = local_default(cfg, 'dataset_file', default_cfg.dataset_file);
cfg = local_default(cfg, 'onnx_file', default_cfg.onnx_file);
cfg = local_default(cfg, 'prediction_file', fullfile(root, 'results', 'modern_tcn', ...
    sprintf('matlab_full_testset_%s', char(cfg.run_tag)), ...
    sprintf('modern_tcn_seed%d_matlab_full_testset_outputs.mat', cfg.seed)));
cfg = local_default(cfg, 'output_dir', fullfile(root, 'results', 'paper', 'modern_tcn_theta_scatter'));
cfg = local_default(cfg, 'theta_bins_deg', -10:2:10);
cfg = local_default(cfg, 'plot_theta_limit_deg', []);
cfg = local_default(cfg, 'font_name', 'Times New Roman');
cfg = local_default(cfg, 'figure_dpi', 600);
cfg = local_default(cfg, 'marker_size', 10);
cfg = local_default(cfg, 'marker_alpha', 0.18);

if exist(cfg.output_dir, 'dir') ~= 7
    mkdir(cfg.output_dir);
end
if exist(cfg.dataset_file, 'file') ~= 2
    error('ModernTCNScatter:MissingDataset', 'Missing dataset: %s', cfg.dataset_file);
end
if exist(cfg.prediction_file, 'file') ~= 2
    error('ModernTCNScatter:MissingPrediction', ...
        'Missing prediction file: %s. Run ModernTCN_matlab_full_testset_eval first.', cfg.prediction_file);
end

D = load(cfg.dataset_file, 'dataset');
P = load(cfg.prediction_file, 'pred');
dataset = D.dataset;
pred = P.pred;

mask = logical(dataset.mask_theta_test(:));
theta_true_deg = rad2deg(double(dataset.y_theta_test(:)));
theta_pred_deg = rad2deg(double(pred.theta_hat(:)));
theta_true_deg = theta_true_deg(mask);
theta_pred_deg = theta_pred_deg(mask);

plot_limit = local_plot_limit(cfg, theta_true_deg);
plot_mask = abs(theta_true_deg) <= plot_limit;
metrics = local_metrics(theta_true_deg, theta_pred_deg);
metrics_plot = local_metrics(theta_true_deg(plot_mask), theta_pred_deg(plot_mask));
Tbins = local_binned_metrics(theta_true_deg, theta_pred_deg, cfg.theta_bins_deg);

files = local_files(cfg.output_dir);
local_plot_scatter(theta_true_deg(plot_mask), theta_pred_deg(plot_mask), metrics_plot, cfg, plot_limit, ...
    files.scatter_png, files.scatter_pdf);
local_plot_residual(theta_true_deg(plot_mask), theta_pred_deg(plot_mask), metrics_plot, cfg, plot_limit, ...
    files.residual_png, files.residual_pdf);
local_write_metrics_csv(files.metrics_csv, metrics);
writetable(Tbins, files.binned_csv);
local_write_report(files.report, cfg, files, metrics, metrics_plot, Tbins, plot_limit);

result = struct();
result.metrics = metrics;
result.metrics_plot = metrics_plot;
result.binned_metrics = Tbins;
result.files = files;
result.output_dir = cfg.output_dir;
result.prediction_file = cfg.prediction_file;
result.dataset_file = cfg.dataset_file;

fprintf('[ModernTCN theta scatter] n=%d MAE=%.4f RMSE=%.4f R2=%.4f\n', ...
    metrics.n, metrics.mae_deg, metrics.rmse_deg, metrics.r2_identity);
fprintf('  output: %s\n', cfg.output_dir);
end

function local_plot_scatter(truth_deg, pred_deg, m, cfg, plot_limit, png_file, pdf_file)
lims = [-plot_limit - 0.8, plot_limit + 0.8];
x_line = linspace(lims(1), lims(2), 400);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100 100 640 560], 'Visible', 'off');
ax = axes(fig, 'Units', 'normalized', 'Position', [0.15 0.14 0.79 0.79]);
hold(ax, 'on');
fill(ax, [x_line fliplr(x_line)], [x_line + 2 fliplr(x_line - 2)], ...
    [0.92 0.92 0.92], 'EdgeColor', 'none', 'FaceAlpha', 0.72);
fill(ax, [x_line fliplr(x_line)], [x_line + 1 fliplr(x_line - 1)], ...
    [0.84 0.89 0.96], 'EdgeColor', 'none', 'FaceAlpha', 0.78);
scatter(ax, truth_deg, pred_deg, cfg.marker_size, ...
    'MarkerFaceColor', [0.20 0.55 0.80], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', cfg.marker_alpha);
plot(ax, x_line, x_line, 'k-', 'LineWidth', 1.15);
plot(ax, x_line, m.fit_slope * x_line + m.fit_intercept_deg, ...
    '--', 'Color', [0.80 0.20 0.10], 'LineWidth', 1.1);
axis(ax, 'square');
xlim(ax, lims);
ylim(ax, lims);
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontName', cfg.font_name, 'FontSize', 9.5, 'LineWidth', 1.0, ...
    'GridAlpha', 0.18, 'Layer', 'top');
xlabel(ax, 'True slope angle (deg)', 'FontName', cfg.font_name, 'FontSize', 10.5);
ylabel(ax, 'Predicted slope angle (deg)', 'FontName', cfg.font_name, 'FontSize', 10.5);
legend(ax, {'\pm2 deg band', '\pm1 deg band', 'Test windows', 'Ideal: y=x', 'Linear fit'}, ...
    'Location', 'northwest', 'FontName', cfg.font_name, 'FontSize', 7.8, 'Box', 'off');
txt = sprintf(['N = %d\nMAE = %.3f deg\nRMSE = %.3f deg\n' ...
    'R^2 = %.3f\nFit: y = %.3fx %+.3f'], ...
    m.n, m.mae_deg, m.rmse_deg, m.r2_identity, m.fit_slope, m.fit_intercept_deg);
text(ax, 0.97, 0.05, txt, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'FontName', cfg.font_name, 'FontSize', 8.5, ...
    'BackgroundColor', 'w', 'EdgeColor', [0.75 0.75 0.75], 'Margin', 6);
exportgraphics(fig, png_file, 'Resolution', cfg.figure_dpi);
exportgraphics(fig, pdf_file, 'ContentType', 'vector');
close(fig);
end

function local_plot_residual(truth_deg, pred_deg, m, cfg, plot_limit, png_file, pdf_file)
err = pred_deg - truth_deg;
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100 100 640 420], 'Visible', 'off');
ax = axes(fig, 'Units', 'normalized', 'Position', [0.15 0.17 0.79 0.75]);
hold(ax, 'on');
scatter(ax, truth_deg, err, cfg.marker_size, ...
    'MarkerFaceColor', [0.20 0.55 0.80], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', cfg.marker_alpha);
yline(ax, 0, 'k-', 'LineWidth', 1.1);
yline(ax, 1, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.9);
yline(ax, -1, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.9);
yline(ax, 2, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
yline(ax, -2, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontName', cfg.font_name, 'FontSize', 9.5, 'LineWidth', 1.0, ...
    'GridAlpha', 0.18, 'Layer', 'top');
xlim(ax, [-plot_limit - 0.8, plot_limit + 0.8]);
xlabel(ax, 'True slope angle (deg)', 'FontName', cfg.font_name, 'FontSize', 10.5);
ylabel(ax, 'Prediction error (deg)', 'FontName', cfg.font_name, 'FontSize', 10.5);
txt = sprintf('Bias = %.3f deg\nP95 |error| = %.3f deg', m.bias_deg, m.p95_abs_err_deg);
text(ax, 0.97, 0.94, txt, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontName', cfg.font_name, 'FontSize', 8.5, ...
    'BackgroundColor', 'w', 'EdgeColor', [0.75 0.75 0.75], 'Margin', 6);
exportgraphics(fig, png_file, 'Resolution', cfg.figure_dpi);
exportgraphics(fig, pdf_file, 'ContentType', 'vector');
close(fig);
end

function T = local_binned_metrics(truth_deg, pred_deg, edges)
edges = double(edges(:));
rows = repmat(struct('theta_bin_deg', "", 'n', NaN, 'mae_deg', NaN, ...
    'rmse_deg', NaN, 'bias_deg', NaN), max(numel(edges) - 1, 0), 1);
for i = 1:numel(edges)-1
    lo = edges(i);
    hi = edges(i + 1);
    if i == numel(edges)-1
        mask = truth_deg >= lo & truth_deg <= hi;
    else
        mask = truth_deg >= lo & truth_deg < hi;
    end
    m = local_metrics(truth_deg(mask), pred_deg(mask));
    rows(i).theta_bin_deg = sprintf('[%.1f, %.1f]', lo, hi);
    rows(i).n = m.n;
    rows(i).mae_deg = m.mae_deg;
    rows(i).rmse_deg = m.rmse_deg;
    rows(i).bias_deg = m.bias_deg;
end
T = struct2table(rows);
end

function local_write_metrics_csv(path, m)
names = fieldnames(m);
fid = fopen(path, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'metric,value\n');
for i = 1:numel(names)
    v = m.(names{i});
    if isnumeric(v)
        fprintf(fid, '%s,%.12g\n', names{i}, v);
    end
end
end

function local_write_report(path, cfg, files, metrics, metrics_plot, Tbins, plot_limit)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# ModernTCN Theta Scatter Report\n\n');
fprintf(fid, '- Dataset: `%s`\n', cfg.dataset_file);
fprintf(fid, '- Prediction file: `%s`\n', cfg.prediction_file);
fprintf(fid, '- ONNX file: `%s`\n', cfg.onnx_file);
fprintf(fid, '- Samples: theta-mask test split only, raw network output before closed-loop scheduling protection.\n');
fprintf(fid, '- Plot range: `[-%.1f, %.1f] deg`\n\n', plot_limit, plot_limit);
local_report_metrics(fid, 'Metrics, all test theta', metrics);
local_report_metrics(fid, 'Metrics, plotted range', metrics_plot);
fprintf(fid, '## Outputs\n\n');
fprintf(fid, '- Scatter PNG: `%s`\n', files.scatter_png);
fprintf(fid, '- Scatter PDF: `%s`\n', files.scatter_pdf);
fprintf(fid, '- Residual PNG: `%s`\n', files.residual_png);
fprintf(fid, '- Residual PDF: `%s`\n', files.residual_pdf);
fprintf(fid, '- Metrics CSV: `%s`\n', files.metrics_csv);
fprintf(fid, '- Binned metrics CSV: `%s`\n\n', files.binned_csv);
fprintf(fid, '## Binned Metrics\n\n');
fprintf(fid, '| theta bin (deg) | n | MAE (deg) | RMSE (deg) | Bias (deg) |\n');
fprintf(fid, '|---|---:|---:|---:|---:|\n');
for i = 1:height(Tbins)
    fprintf(fid, '| %s | %d | %.6f | %.6f | %.6f |\n', ...
        char(string(Tbins.theta_bin_deg(i))), Tbins.n(i), Tbins.mae_deg(i), Tbins.rmse_deg(i), Tbins.bias_deg(i));
end
end

function local_report_metrics(fid, title_text, m)
fprintf(fid, '## %s\n\n', title_text);
fprintf(fid, '| metric | value |\n');
fprintf(fid, '|---|---:|\n');
fprintf(fid, '| n | %d |\n', m.n);
fprintf(fid, '| MAE (deg) | %.6f |\n', m.mae_deg);
fprintf(fid, '| RMSE (deg) | %.6f |\n', m.rmse_deg);
fprintf(fid, '| P95 abs error (deg) | %.6f |\n', m.p95_abs_err_deg);
fprintf(fid, '| Peak abs error (deg) | %.6f |\n', m.peak_abs_err_deg);
fprintf(fid, '| Bias (deg) | %.6f |\n', m.bias_deg);
fprintf(fid, '| Fit slope | %.6f |\n', m.fit_slope);
fprintf(fid, '| Fit intercept (deg) | %.6f |\n', m.fit_intercept_deg);
fprintf(fid, '| Pearson r | %.6f |\n', m.pearson_r);
fprintf(fid, '| R2 identity | %.6f |\n\n', m.r2_identity);
end

function files = local_files(output_dir)
files = struct();
files.scatter_png = fullfile(output_dir, 'modern_tcn_theta_scatter.png');
files.scatter_pdf = fullfile(output_dir, 'modern_tcn_theta_scatter.pdf');
files.residual_png = fullfile(output_dir, 'modern_tcn_theta_residual.png');
files.residual_pdf = fullfile(output_dir, 'modern_tcn_theta_residual.pdf');
files.metrics_csv = fullfile(output_dir, 'modern_tcn_theta_metrics.csv');
files.binned_csv = fullfile(output_dir, 'modern_tcn_theta_binned_metrics.csv');
files.report = fullfile(output_dir, 'modern_tcn_theta_scatter_report.md');
end

function m = local_metrics(truth_deg, pred_deg)
truth_deg = double(truth_deg(:));
pred_deg = double(pred_deg(:));
mask = isfinite(truth_deg) & isfinite(pred_deg);
truth_deg = truth_deg(mask);
pred_deg = pred_deg(mask);
err = pred_deg - truth_deg;
if isempty(truth_deg)
    m = struct('n', 0, 'mae_deg', NaN, 'rmse_deg', NaN, ...
        'p95_abs_err_deg', NaN, 'peak_abs_err_deg', NaN, ...
        'bias_deg', NaN, 'fit_slope', NaN, 'fit_intercept_deg', NaN, ...
        'pearson_r', NaN, 'r2_identity', NaN);
    return;
end
if numel(unique(truth_deg)) < 2
    coef = [NaN; NaN];
    pearson_r = NaN;
else
    X = [truth_deg, ones(numel(truth_deg), 1)];
    coef = X \ pred_deg;
    R = corrcoef(truth_deg, pred_deg);
    if numel(R) < 4
        pearson_r = NaN;
    else
        pearson_r = R(1, 2);
    end
end
ss_identity = sum((pred_deg - truth_deg).^2);
ss_truth = sum((truth_deg - mean(truth_deg)).^2);
m = struct();
m.n = numel(truth_deg);
m.mae_deg = mean(abs(err), 'omitnan');
m.rmse_deg = sqrt(mean(err.^2, 'omitnan'));
m.p95_abs_err_deg = prctile(abs(err), 95);
m.peak_abs_err_deg = max(abs(err), [], 'omitnan');
m.bias_deg = mean(err, 'omitnan');
m.fit_slope = coef(1);
m.fit_intercept_deg = coef(2);
m.pearson_r = pearson_r;
if ss_truth <= eps
    m.r2_identity = NaN;
else
    m.r2_identity = 1 - ss_identity / ss_truth;
end
end

function lim = local_plot_limit(cfg, truth_deg)
if isfield(cfg, 'plot_theta_limit_deg') && ~isempty(cfg.plot_theta_limit_deg)
    lim = double(cfg.plot_theta_limit_deg);
else
    lim = ceil(max(abs(double(truth_deg(:))), [], 'omitnan'));
end
if ~isfinite(lim) || lim <= 0
    lim = 8;
end
end

function cfg = local_default(cfg, name, value)
if ~isfield(cfg, name) || isempty(cfg.(name))
    cfg.(name) = value;
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
