function result = eval_modern_tcn_theta_sweep_plot(cfg)
%EVAL_MODERN_TCN_THETA_SWEEP_PLOT Evaluate ModernTCN on a controlled theta sweep.
%
% This is a paper-figure diagnostic. It generates or reuses a held-out
% straight-line theta sweep path, simulates y_raw with GRU_DataGen, evaluates
% raw ModernTCN ONNX output on steady tail windows, and writes scatter plots.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
default_cfg = ModernTCN_default_config(root);
cfg = local_default(cfg, 'paper_scatter_preset', 'legacy');
cfg = local_apply_preset(cfg, root);

cfg = local_default(cfg, 'output_dir', fullfile(root, 'results', 'paper', ...
    'modern_tcn_theta_sweep_plot'));
cfg = local_default(cfg, 'path_file', fullfile(root, 'data', 'paths', ...
    'path_modern_tcn_theta_sweep_plot_v1.mat'));
cfg = local_default(cfg, 'path_files', {});
cfg = local_default(cfg, 'data_file', fullfile(cfg.output_dir, ...
    'ModernTCN_theta_sweep_plot_data.mat'));
cfg = local_default(cfg, 'dataset_file', default_cfg.dataset_file);
cfg = local_default(cfg, 'seed', default_cfg.seed);
cfg = local_default(cfg, 'onnx_file', '');
cfg = local_default(cfg, 'regenerate_path', true);
cfg = local_default(cfg, 'regenerate_data', false);
cfg = local_default(cfg, 'theta_deg', -10:0.1:10);
cfg = local_default(cfg, 'plot_theta_limit_deg', []);
cfg = local_default(cfg, 'segment_duration', 5.0);
cfg = local_default(cfg, 'v_ref', 0.9);
cfg = local_default(cfg, 'path_num_repeats', 1);
cfg = local_default(cfg, 'path_v_ref_values', cfg.v_ref);
cfg = local_default(cfg, 'path_omega_ref_values', 0);
cfg = local_default(cfg, 'path_segment_duration_values', cfg.segment_duration);
cfg = local_default(cfg, 'path_variant_table', []);
cfg = local_default(cfg, 'path_shuffle_theta', false);
cfg = local_default(cfg, 'path_order_mode', 'repeat_major');
cfg = local_default(cfg, 'path_seed', 20260510);
cfg = local_default(cfg, 'data_seed', 20260507);
cfg = local_default(cfg, 'num_runs_per_path', 1);
cfg = local_default(cfg, 'data_noise_on', false);
cfg = local_default(cfg, 'noise_profile', struct());
cfg = local_default(cfg, 'eval_tail_sec', 1.0);
cfg = local_default(cfg, 'eval_tail_margin_sec', 0.10);
cfg = local_default(cfg, 'eval_stride_sec', 0.10);
cfg = local_default(cfg, 'scatter_metric_source', 'segment');
cfg = local_default(cfg, 'show_segment_median', true);
cfg = local_default(cfg, 'font_name', 'Times New Roman');
cfg = local_default(cfg, 'figure_dpi', 600);
cfg = local_default(cfg, 'marker_size_window', 9);
cfg = local_default(cfg, 'marker_size_segment', 24);
cfg = local_default(cfg, 'marker_alpha_window', 0.18);

if exist(cfg.output_dir, 'dir') ~= 7
    mkdir(cfg.output_dir);
end

path_info = local_ensure_path(cfg);
data = local_ensure_data(cfg, path_info);
eval_result = local_evaluate(data, path_info, cfg);

files = local_output_files(cfg.output_dir);
local_write_outputs(eval_result, cfg, path_info, files);

result = eval_result;
result.path_file = cfg.path_file;
result.path_files = path_info.path_files;
result.data_file = cfg.data_file;
result.output_dir = cfg.output_dir;
result.files = files;

fprintf('[theta sweep eval] segment n=%d | window n=%d\n', ...
    height(eval_result.segment_table), height(eval_result.window_table));
plot_metrics = local_select_plot_metrics(eval_result, cfg);
fprintf('  plot-source(%s) MAE=%.4f deg RMSE=%.4f deg R2=%.4f\n', ...
    char(string(cfg.scatter_metric_source)), ...
    plot_metrics.mae_deg, plot_metrics.rmse_deg, plot_metrics.r2_identity);
fprintf('  all-segment MAE=%.4f deg RMSE=%.4f deg R2=%.4f\n', ...
    eval_result.metrics_segment_all.mae_deg, ...
    eval_result.metrics_segment_all.rmse_deg, ...
    eval_result.metrics_segment_all.r2_identity);
fprintf('  active(|theta|>=2deg) MAE=%.4f deg RMSE=%.4f deg R2=%.4f\n', ...
    eval_result.metrics_segment_active.mae_deg, ...
    eval_result.metrics_segment_active.rmse_deg, ...
    eval_result.metrics_segment_active.r2_identity);
fprintf('  |theta|<=8deg MAE=%.4f deg RMSE=%.4f deg R2=%.4f\n', ...
    eval_result.metrics_segment_abs_le8.mae_deg, ...
    eval_result.metrics_segment_abs_le8.rmse_deg, ...
    eval_result.metrics_segment_abs_le8.r2_identity);
fprintf('  scatter: %s\n', files.scatter_png);
fprintf('  report : %s\n', files.report);
end

function path_info = local_ensure_path(cfg)
if ~isempty(cfg.path_files)
    path_files = local_normalize_path_files(cfg.path_files);
    path_info = local_load_path_info(path_files);
    return;
end

if cfg.regenerate_path || exist(cfg.path_file, 'file') ~= 2
    path_cfg = struct();
    path_cfg.output_file = cfg.path_file;
    path_cfg.theta_deg = cfg.theta_deg;
    path_cfg.segment_duration = cfg.segment_duration;
    path_cfg.v_ref = cfg.v_ref;
    path_cfg.num_repeats = cfg.path_num_repeats;
    path_cfg.v_ref_values = cfg.path_v_ref_values;
    path_cfg.omega_ref_values = cfg.path_omega_ref_values;
    path_cfg.segment_duration_values = cfg.path_segment_duration_values;
    path_cfg.variant_table = cfg.path_variant_table;
    path_cfg.shuffle_theta = cfg.path_shuffle_theta;
    path_cfg.order_mode = cfg.path_order_mode;
    path_cfg.seed = cfg.path_seed;
    out = gen_modern_tcn_theta_sweep_plot_path(path_cfg);
    path_info = local_load_path_info({out.output_file});
else
    path_info = local_load_path_info({cfg.path_file});
end
end

function data = local_ensure_data(cfg, path_info)
if ~cfg.regenerate_data && exist(cfg.data_file, 'file') == 2
    S = load(cfg.data_file, 'data');
    data = S.data;
    return;
end

gen_cfg = struct();
gen_cfg.path_files = path_info.path_files;
gen_cfg.path_pattern = path_info.path_files{1};
gen_cfg.num_runs_per_path = cfg.num_runs_per_path;
gen_cfg.output_dir = cfg.output_dir;
gen_cfg.output_file = cfg.data_file;
gen_cfg.model_name = 'GRU_DataGen';
gen_cfg.seed = cfg.data_seed;
gen_cfg.noise_on = logical(cfg.data_noise_on);
if isstruct(cfg.noise_profile) && ~isempty(fieldnames(cfg.noise_profile))
    gen_cfg.noise_profile = cfg.noise_profile;
end
gen_cfg.verbose = true;
gen_cfg.fail_fast = true;
gen_cfg.event_cfg = struct('enabled', false);
gen_cfg.self_check = struct();
gen_cfg.self_check.min_stall_ratio = 0;
gen_cfg.self_check.min_slope_ratio = 0;
gen_cfg.self_check.min_turn_ratio = 0;
gen_cfg.self_check.min_slip_aux_ratio = 0;
gen_cfg.self_check.min_load_change_aux_ratio = 0;
gen_cfg.self_check.min_stall_aux_ratio = 0;
gen_cfg.self_check.min_transition_window_hits = 0;

data = TCN_gen_train_data(gen_cfg);
end

function path_info = local_load_path_info(path_files)
path_files = local_normalize_path_files(path_files);
refs = cell(numel(path_files), 1);
total_samples = 0;
total_stop_time = 0;
for i = 1:numel(path_files)
    if exist(path_files{i}, 'file') ~= 2
        error('ThetaSweepEval:MissingPathFile', ...
            'Configured path file does not exist: %s', path_files{i});
    end
    S = load(path_files{i}, 'ref');
    if ~isfield(S, 'ref')
        error('ThetaSweepEval:BadPathFile', 'Path file has no ref variable: %s', path_files{i});
    end
    refs{i} = S.ref;
    if isfield(S.ref, 't') && ~isempty(S.ref.t)
        total_samples = total_samples + numel(S.ref.t);
        total_stop_time = total_stop_time + double(S.ref.t(end));
    end
end

path_info = struct();
path_info.path_files = path_files;
path_info.refs = refs;
path_info.ref = refs{1};
path_info.output_file = path_files{1};
path_info.num_paths = numel(path_files);
path_info.total_samples = total_samples;
path_info.total_stop_time = total_stop_time;
end

function path_files = local_normalize_path_files(path_files)
if ischar(path_files) || isstring(path_files)
    path_files = cellstr(path_files);
elseif iscell(path_files)
    path_files = cellfun(@char, path_files(:), 'UniformOutput', false);
else
    error('ThetaSweepEval:BadPathFiles', 'path_files must be a char, string, or cell array.');
end
path_files = path_files(:).';
end

function result = local_evaluate(data, path_info, cfg)
if ~isfield(data, 'runs') || isempty(data.runs)
    error('ThetaSweepEval:NoRuns', 'Data file contains no runs.');
end

D = load(cfg.dataset_file, 'dataset');
dataset = D.dataset;
scaler = dataset.scaler;
seq_len = dataset.meta.seq_len;
Ts = dataset.meta.Ts;
if local_has_text(cfg.onnx_file)
    predictor = ModernTCN_load_predictor(cfg.seed, cfg.onnx_file);
else
    predictor = ModernTCN_load_predictor(cfg.seed);
end

stride_steps = max(1, round(cfg.eval_stride_sec / Ts));
tail_steps = max(1, round(cfg.eval_tail_sec / Ts));
margin_steps = max(0, round(cfg.eval_tail_margin_sec / Ts));

window_rows = repmat(local_window_row_template(), 0, 1);
segment_rows = repmat(local_segment_row_template(), 0, 1);
segment_row_idx = 0;

for run_i = 1:numel(data.runs)
    run = data.runs(run_i);
    segments = local_segments_for_run(run, path_info);
    run_path_file = local_run_path_file(run, path_info);
    run_path_idx = local_path_index(run_path_file, path_info);
    t = double(run.t(:));
    y_raw = double(run.y_raw);
    theta_ground = double(run.y_theta_ground(:));
    features = local_extract_features(y_raw, Ts);
    features_norm = (features - double(scaler.mean)) ./ (double(scaler.std) + 1e-8);
    noise_variant = local_run_noise_variant(run);

    for s = 1:numel(segments)
        seg = segments(s);
        global_segment_idx = segment_row_idx + 1;
        i0 = max(1, round(seg.sample_start));
        i1 = min(numel(t), round(seg.sample_end) - margin_steps);
        tail0 = max(i0 + seq_len - 1, i1 - tail_steps + 1);
        eval_idx = tail0:stride_steps:i1;
        if isempty(eval_idx) || eval_idx(end) ~= i1
            eval_idx = unique([eval_idx, i1]);
        end
        eval_idx = eval_idx(eval_idx >= seq_len & eval_idx <= size(features_norm, 1));

        pred_theta = nan(numel(eval_idx), 1);
        pred_main = nan(numel(eval_idx), 1);
        pred_turn = nan(numel(eval_idx), 1);
        pred_conf_main = nan(numel(eval_idx), 1);

        for j = 1:numel(eval_idx)
            k = eval_idx(j);
            Xw = single(features_norm((k - seq_len + 1):k, :));
            pred = ModernTCN_predict_window(predictor, Xw);
            pred_theta(j) = double(pred.theta_hat_deg);
            pred_main(j) = double(pred.main_state);
            pred_turn(j) = double(pred.turn_state);
            pred_conf_main(j) = double(pred.main_confidence);

            row = local_window_row_template();
            row.run_idx = run_i;
            row.path_idx = run_path_idx;
            row.path_file = string(run_path_file);
            row.segment_idx = global_segment_idx;
            row.ref_segment_idx = s;
            row.theta_true_deg = seg.theta_deg;
            row.repeat_idx = local_seg_value(seg, 'repeat_idx', 1);
            row.variant_idx = local_seg_value(seg, 'variant_idx', 1);
            row.variant_name = local_seg_text(seg, 'variant_name', "");
            row.v_ref = local_seg_value(seg, 'v_ref', cfg.v_ref);
            row.omega_ref = local_seg_value(seg, 'omega_ref', 0);
            row.radius_m = local_seg_value(seg, 'radius_m', local_radius(row.v_ref, row.omega_ref));
            row.segment_duration = local_seg_value(seg, 'segment_duration', cfg.segment_duration);
            row.noise_variant = noise_variant;
            row.window_rank = j;
            row.t_end = t(k);
            row.sample_end = k;
            row.theta_ground_deg = rad2deg(theta_ground(k));
            row.theta_pred_deg = pred_theta(j);
            row.error_deg = row.theta_pred_deg - row.theta_true_deg;
            row.label_main = pred_main(j);
            row.label_turn = pred_turn(j);
            row.conf_main = pred_conf_main(j);
            window_rows(end + 1) = row; %#ok<AGROW>
        end

        segment_row_idx = segment_row_idx + 1;
        seg_row = local_segment_row_template();
        seg_row.run_idx = run_i;
        seg_row.path_idx = run_path_idx;
        seg_row.path_file = string(run_path_file);
        seg_row.segment_idx = global_segment_idx;
        seg_row.ref_segment_idx = s;
        seg_row.theta_true_deg = seg.theta_deg;
        seg_row.repeat_idx = local_seg_value(seg, 'repeat_idx', 1);
        seg_row.variant_idx = local_seg_value(seg, 'variant_idx', 1);
        seg_row.variant_name = local_seg_text(seg, 'variant_name', "");
        seg_row.v_ref = local_seg_value(seg, 'v_ref', cfg.v_ref);
        seg_row.omega_ref = local_seg_value(seg, 'omega_ref', 0);
        seg_row.radius_m = local_seg_value(seg, 'radius_m', local_radius(seg_row.v_ref, seg_row.omega_ref));
        seg_row.segment_duration = local_seg_value(seg, 'segment_duration', cfg.segment_duration);
        seg_row.noise_variant = noise_variant;
        seg_row.t0 = seg.t0;
        seg_row.t1 = seg.t1;
        seg_row.n_windows = numel(eval_idx);
        seg_row.theta_pred_median_deg = median(pred_theta, 'omitnan');
        seg_row.theta_pred_mean_deg = mean(pred_theta, 'omitnan');
        seg_row.theta_pred_std_deg = std(pred_theta, 0, 'omitnan');
        seg_row.error_median_deg = seg_row.theta_pred_median_deg - seg.theta_deg;
        seg_row.error_mean_deg = seg_row.theta_pred_mean_deg - seg.theta_deg;
        seg_row.label_main_mode = local_mode_or_nan(pred_main);
        seg_row.conf_main_median = median(pred_conf_main, 'omitnan');
        segment_rows(end + 1) = seg_row; %#ok<AGROW>
    end
end

window_table = struct2table(window_rows);
segment_table = struct2table(segment_rows);

metrics_segment_all = local_metrics(segment_table.theta_true_deg, ...
    segment_table.theta_pred_median_deg);
active_mask = abs(segment_table.theta_true_deg) >= 2.0;
metrics_segment_active = local_metrics(segment_table.theta_true_deg(active_mask), ...
    segment_table.theta_pred_median_deg(active_mask));
metrics_window_all = local_metrics(window_table.theta_true_deg, window_table.theta_pred_deg);
metrics_window_active = local_metrics(window_table.theta_true_deg(abs(window_table.theta_true_deg) >= 2.0), ...
    window_table.theta_pred_deg(abs(window_table.theta_true_deg) >= 2.0));
metrics_segment_abs_le8 = local_metrics(segment_table.theta_true_deg(abs(segment_table.theta_true_deg) <= 8.0), ...
    segment_table.theta_pred_median_deg(abs(segment_table.theta_true_deg) <= 8.0));
metrics_segment_abs_le10 = local_metrics(segment_table.theta_true_deg(abs(segment_table.theta_true_deg) <= 10.0), ...
    segment_table.theta_pred_median_deg(abs(segment_table.theta_true_deg) <= 10.0));
metrics_window_abs_le8 = local_metrics(window_table.theta_true_deg(abs(window_table.theta_true_deg) <= 8.0), ...
    window_table.theta_pred_deg(abs(window_table.theta_true_deg) <= 8.0));
metrics_window_abs_le10 = local_metrics(window_table.theta_true_deg(abs(window_table.theta_true_deg) <= 10.0), ...
    window_table.theta_pred_deg(abs(window_table.theta_true_deg) <= 10.0));

result = struct();
result.segment_table = segment_table;
result.window_table = window_table;
result.metrics_segment_all = metrics_segment_all;
result.metrics_segment_active = metrics_segment_active;
result.metrics_segment_abs_le8 = metrics_segment_abs_le8;
result.metrics_segment_abs_le10 = metrics_segment_abs_le10;
result.metrics_window_all = metrics_window_all;
result.metrics_window_active = metrics_window_active;
result.metrics_window_abs_le8 = metrics_window_abs_le8;
result.metrics_window_abs_le10 = metrics_window_abs_le10;
result.eval_config = cfg;
result.data_meta = data.meta;
end

function segments = local_segments_for_run(run, path_info)
if isstruct(run) && isfield(run, 'meta') && isstruct(run.meta) ...
        && isfield(run.meta, 'path_meta') && isstruct(run.meta.path_meta) ...
        && isfield(run.meta.path_meta, 'segments')
    segments = run.meta.path_meta.segments(:);
    return;
end

path_file = local_run_path_file(run, path_info);
idx = local_path_index(path_file, path_info);
if idx >= 1 && idx <= numel(path_info.refs) ...
        && isfield(path_info.refs{idx}, 'meta') ...
        && isfield(path_info.refs{idx}.meta, 'segments')
    segments = path_info.refs{idx}.meta.segments(:);
    return;
end

if isfield(path_info.ref, 'meta') && isfield(path_info.ref.meta, 'segments')
    segments = path_info.ref.meta.segments(:);
else
    error('ThetaSweepEval:NoSegments', 'Cannot find path segments for run.');
end
end

function path_file = local_run_path_file(run, path_info)
if isstruct(run) && isfield(run, 'path_file') && ~isempty(run.path_file)
    path_file = char(string(run.path_file));
elseif isfield(path_info, 'path_files') && ~isempty(path_info.path_files)
    path_file = path_info.path_files{1};
else
    path_file = '';
end
end

function idx = local_path_index(path_file, path_info)
idx = NaN;
if ~isfield(path_info, 'path_files') || isempty(path_info.path_files) || isempty(path_file)
    return;
end
match = find(strcmpi(string(path_info.path_files), string(path_file)), 1, 'first');
if ~isempty(match)
    idx = match;
else
    idx = 1;
end
end

function features = local_extract_features(y_raw, Ts)
params = parameters();
feature_cfg = struct('tau_diff', 0.3, 'tau_accel_lp', 0.4);
features = extract_passive_features('batch', y_raw, params, Ts, feature_cfg);
end

function local_write_outputs(result, cfg, path_info, files)
writetable(result.segment_table, files.segment_csv);
writetable(result.window_table, files.window_csv);

metrics_segment_all = result.metrics_segment_all;
metrics_segment_active = result.metrics_segment_active;
metrics_segment_abs_le8 = result.metrics_segment_abs_le8;
metrics_segment_abs_le10 = result.metrics_segment_abs_le10;
metrics_window_all = result.metrics_window_all;
metrics_window_active = result.metrics_window_active;
metrics_window_abs_le8 = result.metrics_window_abs_le8;
metrics_window_abs_le10 = result.metrics_window_abs_le10;
segment_table = result.segment_table;
window_table = result.window_table;
save(files.result_mat, 'metrics_segment_all', 'metrics_segment_active', ...
    'metrics_segment_abs_le8', 'metrics_segment_abs_le10', ...
    'metrics_window_all', 'metrics_window_active', ...
    'metrics_window_abs_le8', 'metrics_window_abs_le10', ...
    'segment_table', 'window_table', 'cfg', 'path_info');

local_plot_scatter(result, cfg, files.scatter_png, files.scatter_pdf);
local_plot_residual(result, cfg, files.residual_png, files.residual_pdf);
local_write_report(result, cfg, path_info, files);
end

function local_plot_scatter(result, cfg, png_file, pdf_file)
Tseg = result.segment_table;
Twin = result.window_table;
plot_limit = local_plot_limit(cfg, Tseg.theta_true_deg);
Tseg = Tseg(abs(Tseg.theta_true_deg) <= plot_limit, :);
Twin = Twin(abs(Twin.theta_true_deg) <= plot_limit, :);
m = local_plot_metrics_from_tables(Tseg, Twin, cfg);

truth_seg = Tseg.theta_true_deg;
pred_seg = Tseg.theta_pred_median_deg;
truth_win = Twin.theta_true_deg;
pred_win = Twin.theta_pred_deg;

lims = [-plot_limit - 0.8, plot_limit + 0.8];
x_line = linspace(lims(1), lims(2), 400);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100 100 840 560], ...
    'Visible', 'off');
ax = axes(fig, 'Units', 'normalized', 'Position', [0.26 0.15 0.67 0.77]);
hold(ax, 'on');

fill(ax, [x_line fliplr(x_line)], [x_line + 2 fliplr(x_line - 2)], ...
    [0.92 0.92 0.92], 'EdgeColor', 'none', 'FaceAlpha', 0.72);
fill(ax, [x_line fliplr(x_line)], [x_line + 1 fliplr(x_line - 1)], ...
    [0.84 0.89 0.96], 'EdgeColor', 'none', 'FaceAlpha', 0.78);

scatter(ax, truth_win, pred_win, cfg.marker_size_window, ...
    'MarkerFaceColor', [0.35 0.65 0.85], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', cfg.marker_alpha_window);
if logical(cfg.show_segment_median)
    scatter(ax, truth_seg, pred_seg, cfg.marker_size_segment, ...
        'MarkerFaceColor', [0.000 0.447 0.741], ...
        'MarkerEdgeColor', [0.000 0.250 0.450], 'LineWidth', 0.25);
end

plot(ax, x_line, x_line, 'k-', 'LineWidth', 1.15);
plot(ax, x_line, m.fit_slope * x_line + m.fit_intercept_deg, ...
    '--', 'Color', [0.80 0.20 0.10], 'LineWidth', 1.1);

axis(ax, 'square');
xlim(ax, lims);
ylim(ax, lims);
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontName', cfg.font_name, 'FontSize', 9.2, 'LineWidth', 1.0, ...
    'GridAlpha', 0.18, 'Layer', 'top');
xlabel(ax, 'True slope (deg)', 'FontName', cfg.font_name, 'FontSize', 10.0);
ylabel(ax, 'Predicted slope (deg)', 'FontName', cfg.font_name, 'FontSize', 10.0);
if logical(cfg.show_segment_median)
    legend_items = {'\pm2 deg band', '\pm1 deg band', 'Evaluation windows', ...
        'Segment median', 'Ideal: y=x', 'Linear fit'};
else
    legend_items = {'\pm2 deg band', '\pm1 deg band', 'Evaluation windows', ...
        'Ideal: y=x', 'Linear fit'};
end
legend(ax, legend_items, 'Location', 'northwest', ...
    'FontName', cfg.font_name, 'FontSize', 7.2, 'Box', 'off');

txt = sprintf(['N = %d\nMAE = %.3f deg\nRMSE = %.3f deg\n' ...
    'R^2 = %.3f\nFit: y = %.3fx %+.3f'], ...
    m.n, m.mae_deg, m.rmse_deg, m.r2_identity, ...
    m.fit_slope, m.fit_intercept_deg);
text(ax, 0.97, 0.05, txt, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'FontName', cfg.font_name, 'FontSize', 8.0, ...
    'BackgroundColor', 'w', 'EdgeColor', [0.75 0.75 0.75], 'Margin', 6);

exportgraphics(fig, png_file, 'Resolution', cfg.figure_dpi);
exportgraphics(fig, pdf_file, 'ContentType', 'vector');
close(fig);
end

function local_plot_residual(result, cfg, png_file, pdf_file)
Tseg = result.segment_table;
Twin = result.window_table;
plot_limit = local_plot_limit(cfg, Tseg.theta_true_deg);
Tseg = Tseg(abs(Tseg.theta_true_deg) <= plot_limit, :);
Twin = Twin(abs(Twin.theta_true_deg) <= plot_limit, :);
m = local_plot_metrics_from_tables(Tseg, Twin, cfg);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100 100 840 420], ...
    'Visible', 'off');
ax = axes(fig, 'Units', 'normalized', 'Position', [0.22 0.17 0.72 0.75]);
hold(ax, 'on');
scatter(ax, Twin.theta_true_deg, Twin.error_deg, cfg.marker_size_window, ...
    'MarkerFaceColor', [0.35 0.65 0.85], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', cfg.marker_alpha_window);
if logical(cfg.show_segment_median)
    scatter(ax, Tseg.theta_true_deg, Tseg.error_median_deg, cfg.marker_size_segment, ...
        'MarkerFaceColor', [0.000 0.447 0.741], ...
        'MarkerEdgeColor', [0.000 0.250 0.450], 'LineWidth', 0.25);
end
yline(ax, 0, 'k-', 'LineWidth', 1.1);
yline(ax, 1, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.9);
yline(ax, -1, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.9);
yline(ax, 2, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
yline(ax, -2, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontName', cfg.font_name, 'FontSize', 9.2, 'LineWidth', 1.0, ...
    'GridAlpha', 0.18, 'Layer', 'top');
xlim(ax, [-plot_limit - 0.8, plot_limit + 0.8]);
xlabel(ax, 'True slope (deg)', 'FontName', cfg.font_name, 'FontSize', 10.0);
ylabel(ax, 'Prediction error (deg)', 'FontName', cfg.font_name, 'FontSize', 10.0);
txt = sprintf('Bias = %.3f deg\nP95 |error| = %.3f deg', ...
    m.bias_deg, m.p95_abs_err_deg);
text(ax, 0.97, 0.94, txt, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontName', cfg.font_name, 'FontSize', 8.0, ...
    'BackgroundColor', 'w', 'EdgeColor', [0.75 0.75 0.75], 'Margin', 6);

exportgraphics(fig, png_file, 'Resolution', cfg.figure_dpi);
exportgraphics(fig, pdf_file, 'ContentType', 'vector');
close(fig);
end

function local_write_report(result, cfg, path_info, files)
fid = fopen(files.report, 'w', 'n', 'UTF-8');
if fid < 0
    warning('ThetaSweepEval:ReportOpenFailed', 'Cannot write report: %s', files.report);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN Theta Sweep Plot Report\n\n');
if isfield(path_info, 'path_files') && numel(path_info.path_files) > 1
    fprintf(fid, '- Path files: `%d`\n', numel(path_info.path_files));
    fprintf(fid, '- First path file: `%s`\n', path_info.path_files{1});
    fprintf(fid, '- Last path file: `%s`\n', path_info.path_files{end});
else
    fprintf(fid, '- Path file: `%s`\n', path_info.path_files{1});
end
fprintf(fid, '- Data file: `%s`\n', cfg.data_file);
fprintf(fid, '- Model seed: `%d`\n', cfg.seed);
if local_has_text(cfg.onnx_file)
    fprintf(fid, '- ONNX file: `%s`\n', cfg.onnx_file);
end
fprintf(fid, '- Sweep: %.1f to %.1f deg, step %.1f deg, segment %.2f s, v=%.2f m/s\n', ...
    min(cfg.theta_deg), max(cfg.theta_deg), median(diff(cfg.theta_deg)), ...
    cfg.segment_duration, cfg.v_ref);
fprintf(fid, '- Scatter metric source: `%s`; show segment median: `%d`\n', ...
    char(string(cfg.scatter_metric_source)), logical(cfg.show_segment_median));
if ~isempty(cfg.path_variant_table)
    variants = local_report_variant_table(cfg.path_variant_table);
    fprintf(fid, '- Path repeats: `%d`; explicit variants: `%d`\n', ...
        cfg.path_num_repeats, numel(variants));
else
    variants = struct([]);
    fprintf(fid, '- Path repeats: `%d`; v variants: `%s`; omega variants: `%s`; duration variants: `%s`\n', ...
        cfg.path_num_repeats, mat2str(cfg.path_v_ref_values), ...
        mat2str(cfg.path_omega_ref_values), mat2str(cfg.path_segment_duration_values));
end
fprintf(fid, '- Evaluation windows: tail %.2f s, stride %.3f s, margin %.2f s\n', ...
    cfg.eval_tail_sec, cfg.eval_stride_sec, cfg.eval_tail_margin_sec);
fprintf(fid, '- Note: held-out paper plotting set; not added to training data.\n\n');

if ~isempty(variants)
    fprintf(fid, '## Path Variants\n\n');
    fprintf(fid, '| variant | v_ref (m/s) | omega_ref (rad/s) | radius (m) | segment (s) |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|\n');
    for i = 1:numel(variants)
        fprintf(fid, '| %s | %.3f | %.6f | %s | %.2f |\n', ...
            char(string(variants(i).name)), variants(i).v_ref, variants(i).omega_ref, ...
            local_report_radius_text(variants(i).radius_m), variants(i).segment_duration);
    end
    fprintf(fid, '\n');
end

local_report_metrics(fid, 'Segment median, all theta', result.metrics_segment_all);
local_report_metrics(fid, 'Segment median, |theta| >= 2 deg', result.metrics_segment_active);
local_report_metrics(fid, 'Segment median, |theta| <= 8 deg', result.metrics_segment_abs_le8);
local_report_metrics(fid, 'Segment median, |theta| <= 10 deg', result.metrics_segment_abs_le10);
local_report_metrics(fid, 'Window-level, all theta', result.metrics_window_all);
local_report_metrics(fid, 'Window-level, |theta| >= 2 deg', result.metrics_window_active);
local_report_metrics(fid, 'Window-level, |theta| <= 8 deg', result.metrics_window_abs_le8);
local_report_metrics(fid, 'Window-level, |theta| <= 10 deg', result.metrics_window_abs_le10);

fprintf(fid, '## Outputs\n\n');
fprintf(fid, '- Scatter PNG: `%s`\n', files.scatter_png);
fprintf(fid, '- Scatter PDF: `%s`\n', files.scatter_pdf);
fprintf(fid, '- Residual PNG: `%s`\n', files.residual_png);
fprintf(fid, '- Residual PDF: `%s`\n', files.residual_pdf);
fprintf(fid, '- Segment CSV: `%s`\n', files.segment_csv);
fprintf(fid, '- Window CSV: `%s`\n', files.window_csv);
fprintf(fid, '- Result MAT: `%s`\n\n', files.result_mat);

if isfield(path_info, 'ref') && isfield(path_info.ref, 'meta')
    fprintf(fid, '## Path Meta\n\n');
    if isfield(path_info, 'num_paths')
        fprintf(fid, '- Path count: `%d`\n', path_info.num_paths);
    end
    fprintf(fid, '- Path type: `%s`\n', path_info.ref.meta.path_type);
    if isfield(path_info, 'total_samples')
        fprintf(fid, '- Total samples: `%d`\n', path_info.total_samples);
    else
        fprintf(fid, '- Samples: `%d`\n', numel(path_info.ref.t));
    end
    if isfield(path_info, 'total_stop_time')
        fprintf(fid, '- Total stop time: `%.2f s`\n', path_info.total_stop_time);
    else
        fprintf(fid, '- Stop time: `%.2f s`\n', path_info.ref.t(end));
    end
end
end

function variants = local_report_variant_table(variant_table)
if istable(variant_table)
    variant_table = table2struct(variant_table);
end
variant_table = variant_table(:);
variants = repmat(struct('name', "", 'v_ref', NaN, 'omega_ref', NaN, ...
    'radius_m', NaN, 'segment_duration', NaN), numel(variant_table), 1);
for i = 1:numel(variant_table)
    row = variant_table(i);
    if isfield(row, 'name') && ~isempty(row.name)
        variants(i).name = string(row.name);
    else
        variants(i).name = sprintf('variant_%02d', i);
    end
    if isfield(row, 'v_ref') && ~isempty(row.v_ref)
        variants(i).v_ref = double(row.v_ref);
    end
    if isfield(row, 'omega_ref') && ~isempty(row.omega_ref)
        variants(i).omega_ref = double(row.omega_ref);
    end
    if isfield(row, 'segment_duration') && ~isempty(row.segment_duration)
        variants(i).segment_duration = double(row.segment_duration);
    end
    if isfield(row, 'radius_m') && ~isempty(row.radius_m)
        variants(i).radius_m = double(row.radius_m);
    elseif isfinite(variants(i).v_ref) && isfinite(variants(i).omega_ref) && abs(variants(i).omega_ref) > 1e-9
        variants(i).radius_m = abs(variants(i).v_ref / variants(i).omega_ref);
    else
        variants(i).radius_m = Inf;
    end
end
end

function text = local_report_radius_text(radius_m)
if isfinite(radius_m)
    text = sprintf('%.2f', radius_m);
else
    text = 'Inf';
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

function m = local_select_plot_metrics(result, cfg)
source = lower(char(string(cfg.scatter_metric_source)));
switch source
    case 'window'
        m = result.metrics_window_all;
    case 'segment'
        m = result.metrics_segment_all;
    otherwise
        error('ThetaSweepEval:BadMetricSource', ...
            'scatter_metric_source must be segment or window, got %s', source);
end
end

function m = local_plot_metrics_from_tables(Tseg, Twin, cfg)
source = lower(char(string(cfg.scatter_metric_source)));
switch source
    case 'window'
        m = local_metrics(Twin.theta_true_deg, Twin.theta_pred_deg);
    case 'segment'
        m = local_metrics(Tseg.theta_true_deg, Tseg.theta_pred_median_deg);
    otherwise
        error('ThetaSweepEval:BadMetricSource', ...
            'scatter_metric_source must be segment or window, got %s', source);
end
end

function files = local_output_files(output_dir)
files = struct();
files.scatter_png = fullfile(output_dir, 'modern_tcn_theta_sweep_scatter.png');
files.scatter_pdf = fullfile(output_dir, 'modern_tcn_theta_sweep_scatter.pdf');
files.residual_png = fullfile(output_dir, 'modern_tcn_theta_sweep_residual.png');
files.residual_pdf = fullfile(output_dir, 'modern_tcn_theta_sweep_residual.pdf');
files.segment_csv = fullfile(output_dir, 'modern_tcn_theta_sweep_segment_summary.csv');
files.window_csv = fullfile(output_dir, 'modern_tcn_theta_sweep_window_predictions.csv');
files.result_mat = fullfile(output_dir, 'modern_tcn_theta_sweep_eval_result.mat');
files.report = fullfile(output_dir, 'modern_tcn_theta_sweep_report.md');
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

X = [truth_deg, ones(numel(truth_deg), 1)];
coef = X \ pred_deg;
R = corrcoef(truth_deg, pred_deg);
if numel(R) < 4
    pearson_r = NaN;
else
    pearson_r = R(1, 2);
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
m.r2_identity = 1 - ss_identity / max(ss_truth, eps);
end

function lim = local_plot_limit(cfg, truth_deg)
if isfield(cfg, 'plot_theta_limit_deg') && ~isempty(cfg.plot_theta_limit_deg)
    lim = double(cfg.plot_theta_limit_deg);
else
    lim = ceil(max(abs(double(truth_deg(:))), [], 'omitnan'));
end
if ~isfinite(lim) || lim <= 0
    lim = 10;
end
end

function tf = local_has_text(v)
tf = ~isempty(v) && strlength(string(v)) > 0;
end

function v = local_mode_or_nan(x)
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = mode(x);
end
end

function row = local_window_row_template()
row = struct('run_idx', NaN, 'path_idx', NaN, 'path_file', "", ...
    'segment_idx', NaN, 'ref_segment_idx', NaN, 'theta_true_deg', NaN, ...
    'repeat_idx', NaN, 'variant_idx', NaN, ...
    'variant_name', "", 'v_ref', NaN, 'omega_ref', NaN, ...
    'radius_m', NaN, 'segment_duration', NaN, ...
    'noise_variant', "", 'window_rank', NaN, 't_end', NaN, ...
    'sample_end', NaN, 'theta_ground_deg', NaN, 'theta_pred_deg', NaN, ...
    'error_deg', NaN, 'label_main', NaN, 'label_turn', NaN, ...
    'conf_main', NaN);
end

function row = local_segment_row_template()
row = struct('run_idx', NaN, 'path_idx', NaN, 'path_file', "", ...
    'segment_idx', NaN, 'ref_segment_idx', NaN, 'theta_true_deg', NaN, ...
    'repeat_idx', NaN, 'variant_idx', NaN, ...
    'variant_name', "", 'v_ref', NaN, 'omega_ref', NaN, ...
    'radius_m', NaN, 'segment_duration', NaN, ...
    'noise_variant', "", 't0', NaN, 't1', NaN, 'n_windows', NaN, ...
    'theta_pred_median_deg', NaN, 'theta_pred_mean_deg', NaN, ...
    'theta_pred_std_deg', NaN, 'error_median_deg', NaN, ...
    'error_mean_deg', NaN, 'label_main_mode', NaN, ...
    'conf_main_median', NaN);
end

function cfg = local_default(cfg, name, value)
if ~isfield(cfg, name) || isempty(cfg.(name))
    cfg.(name) = value;
end
end

function cfg = local_apply_preset(cfg, root)
preset = lower(char(string(cfg.paper_scatter_preset)));
switch preset
    case {'legacy', 'none'}
        return;
    case {'rich_window', 'richer_window'}
        cfg.output_dir = local_default_value(cfg, 'output_dir', fullfile(root, ...
            'results', 'paper', 'modern_tcn_theta_sweep_plot', 'rich_window_v4'));
        cfg.path_file = local_default_value(cfg, 'path_file', fullfile(root, ...
            'data', 'paths', 'path_modern_tcn_theta_sweep_plot_rich_window_v4.mat'));
        cfg.data_file = local_default_value(cfg, 'data_file', fullfile(cfg.output_dir, ...
            'ModernTCN_theta_sweep_plot_rich_window_v4_data.mat'));

        % Paper-only diagnostic set: repeated true theta labels under distinct
        % speed/curvature/duration contexts. This is deliberately separate
        % from any training dataset.
        cfg.theta_deg = local_default_value(cfg, 'theta_deg', -8:0.5:8);
        cfg.segment_duration = local_default_value(cfg, 'segment_duration', 5.2);
        cfg.v_ref = local_default_value(cfg, 'v_ref', 0.9);
        cfg.path_v_ref_values = local_default_value(cfg, 'path_v_ref_values', [0.95 1.15]);
        cfg.path_omega_ref_values = local_default_value(cfg, 'path_omega_ref_values', 0);
        cfg.path_segment_duration_values = local_default_value(cfg, 'path_segment_duration_values', [5.2 6.0]);
        cfg.path_num_repeats = local_default_value(cfg, 'path_num_repeats', 4);
        cfg.path_shuffle_theta = local_default_value(cfg, 'path_shuffle_theta', false);
        cfg.path_seed = local_default_value(cfg, 'path_seed', 20260510);
        cfg.num_runs_per_path = local_default_value(cfg, 'num_runs_per_path', 1);
        cfg.data_noise_on = local_default_value(cfg, 'data_noise_on', false);
        if ~isfield(cfg, 'noise_profile') || ~isstruct(cfg.noise_profile) || isempty(fieldnames(cfg.noise_profile))
            cfg.noise_profile = struct('clean_ratio', 0.50, ...
                'noisy_scales', [0.75 1.00 1.25], ...
                'noisy_probs', [0.25 0.50 0.25]);
        end
        cfg.eval_tail_sec = local_default_value(cfg, 'eval_tail_sec', 1.8);
        cfg.eval_tail_margin_sec = local_default_value(cfg, 'eval_tail_margin_sec', 0.10);
        cfg.eval_stride_sec = local_default_value(cfg, 'eval_stride_sec', 0.08);
        cfg.scatter_metric_source = local_default_value(cfg, 'scatter_metric_source', 'window');
        cfg.show_segment_median = local_default_value(cfg, 'show_segment_median', false);
        cfg.marker_size_window = local_default_value(cfg, 'marker_size_window', 8);
        cfg.marker_alpha_window = local_default_value(cfg, 'marker_alpha_window', 0.16);
    otherwise
        error('ThetaSweepEval:BadPreset', ...
            'Unknown paper_scatter_preset: %s', preset);
end
end

function v = local_default_value(cfg, name, value)
if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
    v = cfg.(name);
else
    v = value;
end
end

function v = local_seg_value(seg, name, default_value)
if isstruct(seg) && isfield(seg, name) && ~isempty(seg.(name)) && all(isfinite(double(seg.(name))))
    v = double(seg.(name));
else
    v = default_value;
end
end

function v = local_seg_text(seg, name, default_value)
if isstruct(seg) && isfield(seg, name) && ~isempty(seg.(name))
    v = string(seg.(name));
else
    v = string(default_value);
end
end

function r = local_radius(v_ref, omega_ref)
if abs(omega_ref) > 1e-9
    r = abs(v_ref / omega_ref);
else
    r = Inf;
end
end

function noise_variant = local_run_noise_variant(run)
noise_variant = "clean";
if ~isstruct(run) || ~isfield(run, 'meta') || ~isstruct(run.meta)
    return;
end
if ~isfield(run.meta, 'noise') || ~isstruct(run.meta.noise)
    return;
end
noise = run.meta.noise;
if isfield(noise, 'variant') && ~isempty(noise.variant)
    noise_variant = string(noise.variant);
elseif isfield(noise, 'enabled') && logical(noise.enabled)
    if isfield(noise, 'std_scale')
        noise_variant = "noise_x" + string(noise.std_scale);
    else
        noise_variant = "noise";
    end
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
