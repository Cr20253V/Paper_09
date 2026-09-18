function summary = summarize_agv_theta10_uniform_coverage(dataset_file, report_file, gate_cfg)
%SUMMARIZE_AGV_THETA10_UNIFORM_COVERAGE Report theta/turn balance.
%
% The report is designed for the AGV theta10 uniform dataset. It operates on
% the prepared dataset produced by TCN_prepare_dataset and therefore checks
% the actual training/validation/test windows rather than only the reference
% path plan.

if nargin < 1 || isempty(dataset_file)
    error('dataset_file is required.');
end
if exist('init_project', 'file') == 2
    init_project();
end
if nargin < 2 || isempty(report_file)
    report_file = fullfile(project_root(), 'results', 'modern_tcn', ...
        'agv_theta10_uniform_coverage.md');
end
if nargin < 3
    gate_cfg = struct();
end
gate_cfg = local_gate_defaults(gate_cfg);

if ~exist(dataset_file, 'file')
    error('Dataset file not found: %s', dataset_file);
end
S = load(dataset_file, 'dataset');
if ~isfield(S, 'dataset')
    error('Input file must contain variable dataset.');
end
dataset = S.dataset;

summary = struct();
summary.dataset_file = dataset_file;
summary.report_file = report_file;
summary.edges_deg = -10:1:10;
summary.splits = struct();

split_names = {'train', 'val', 'test'};
for i = 1:numel(split_names)
    split_name = split_names{i};
    summary.splits.(split_name) = local_split_stats(dataset, split_name, summary.edges_deg);
end

summary.gate = local_coverage_gate(summary, gate_cfg);

out_dir = fileparts(report_file);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
local_write_report(report_file, dataset, summary);
fprintf('[theta10 coverage] wrote %s\n', report_file);

if summary.gate.enabled && gate_cfg.fail_on_violation && ~summary.gate.passed
    error('AGVTheta10:CoverageGateFailed', ...
        'Coverage gate failed for %s. See %s.', dataset_file, report_file);
end
end

function s = local_split_stats(dataset, split_name, edges_deg)
theta = dataset.(sprintf('y_theta_%s', split_name));
mask = dataset.(sprintf('mask_theta_%s', split_name));
y_main = dataset.(sprintf('y_main_%s', split_name));
y_turn = dataset.(sprintf('y_turn_%s', split_name));
run_id = dataset.(sprintf('run_id_%s', split_name));

theta_deg = rad2deg(double(theta(:)));
mask = mask(:) == 1;
y_main = y_main(:);
y_turn = y_turn(:);
run_id = run_id(:);
[omega_abs, radius_m, steer_abs_deg] = local_kinematic_proxy(dataset, split_name);

s = struct();
s.n = numel(theta_deg);
s.mask_n = sum(mask);
s.run_n = numel(unique(run_id));
s.main_counts = [sum(y_main == 1), sum(y_main == 2), sum(y_main == 3)];
s.turn_counts = [sum(y_turn == -1), sum(y_turn == 0), sum(y_turn == 1)];
s.turn_ratios = s.turn_counts / max(s.n, 1);
s.turn_nonzero_ratio = (s.turn_counts(1) + s.turn_counts(3)) / max(s.n, 1);
s.turn_straight_ratio = s.turn_counts(2) / max(s.n, 1);
s.turn_lr_balance = min(s.turn_counts([1, 3])) / max(max(s.turn_counts([1, 3])), 1);
s.slope_turn_overlap_n = sum(mask & abs(theta_deg) >= 2 & y_turn ~= 0);
s.slope_turn_overlap_ratio = s.slope_turn_overlap_n / max(s.mask_n, 1);

s.theta_bin_counts = local_theta_bins(theta_deg, mask, edges_deg);
s.theta_out_of_range_n = sum(mask & (theta_deg < edges_deg(1) | theta_deg >= edges_deg(end)));
s.theta_zero_abs_n = sum(mask & abs(theta_deg) <= 0.10);
s.theta_zero_abs_ratio = s.theta_zero_abs_n / max(s.mask_n, 1);
s.theta_neg_n = sum(mask & theta_deg < 0);
s.theta_pos_n = sum(mask & theta_deg > 0);
s.theta_sign_balance = min(s.theta_neg_n, s.theta_pos_n) / max(max(s.theta_neg_n, s.theta_pos_n), 1);

nonzero_bins = s.theta_bin_counts(s.theta_bin_counts > 0);
if isempty(nonzero_bins)
    s.theta_bin_min = 0;
    s.theta_bin_max = 0;
    s.theta_bin_imbalance = Inf;
    s.theta_bin_cv = Inf;
else
    s.theta_bin_min = min(nonzero_bins);
    s.theta_bin_max = max(nonzero_bins);
    s.theta_bin_imbalance = s.theta_bin_max / max(s.theta_bin_min, 1);
    s.theta_bin_cv = std(double(s.theta_bin_counts), 0) / max(mean(double(s.theta_bin_counts)), eps);
end

s.omega_bins = local_numeric_bins(omega_abs, [0, 0.02, 0.05, 0.08, 0.12, 0.16, 0.22, Inf]);
s.radius_bins = local_numeric_bins(radius_m, [0, 6, 8, 10, 12, 16, 20, Inf]);
s.steer_bins_deg = local_numeric_bins(steer_abs_deg, [0, 2, 5, 10, 15, 20, 30, Inf]);
end

function bins = local_theta_bins(theta_deg, mask, edges_deg)
bins = zeros(1, numel(edges_deg) - 1);
for i = 1:(numel(edges_deg) - 1)
    if i == numel(edges_deg) - 1
        bins(i) = sum(mask & theta_deg >= edges_deg(i) & theta_deg <= edges_deg(i + 1));
    else
        bins(i) = sum(mask & theta_deg >= edges_deg(i) & theta_deg < edges_deg(i + 1));
    end
end
end

function bins = local_numeric_bins(x, edges)
x = x(:);
finite = isfinite(x);
bins = zeros(1, numel(edges) - 1);
for i = 1:(numel(edges) - 1)
    if isinf(edges(i + 1))
        bins(i) = sum(finite & x >= edges(i));
    else
        bins(i) = sum(finite & x >= edges(i) & x < edges(i + 1));
    end
end
end

function [omega_abs, radius_m, steer_abs_deg] = local_kinematic_proxy(dataset, split_name)
X = dataset.(sprintf('X_%s', split_name));
n = size(X, 1);
omega_abs = NaN(n, 1);
radius_m = NaN(n, 1);
steer_abs_deg = NaN(n, 1);

feat_names = cellstr(dataset.feat_names);
idx_omega = find(strcmp(feat_names, 'gyro_z'), 1);
idx_v = find(strcmp(feat_names, 'v_hat'), 1);
idx_delta_lf = find(strcmp(feat_names, 'delta_lf'), 1);
idx_delta_rr = find(strcmp(feat_names, 'delta_rr'), 1);
if ~isfield(dataset, 'scaler')
    return;
end
if ~isempty(idx_omega)
    omega = local_unscale_last_feature(X, dataset.scaler, idx_omega);
    omega_abs = abs(omega);
end
if ~isempty(idx_v) && ~isempty(idx_omega)
    v = abs(local_unscale_last_feature(X, dataset.scaler, idx_v));
    turn = omega_abs >= 0.05;
    radius_m(turn) = v(turn) ./ max(omega_abs(turn), eps);
end
if ~isempty(idx_delta_lf) && ~isempty(idx_delta_rr)
    delta_lf = local_unscale_last_feature(X, dataset.scaler, idx_delta_lf);
    delta_rr = local_unscale_last_feature(X, dataset.scaler, idx_delta_rr);
    steer_abs_deg = rad2deg(max(abs(delta_lf), abs(delta_rr)));
end
end

function x = local_unscale_last_feature(X, scaler, idx)
x = double(reshape(X(:, end, idx), [], 1));
mu = double(scaler.mean(idx));
sig = double(scaler.std(idx));
x = x .* sig + mu;
end

function gate_cfg = local_gate_defaults(gate_cfg)
if islogical(gate_cfg) || isnumeric(gate_cfg)
    gate_cfg = struct('enabled', logical(gate_cfg));
end
if ~isstruct(gate_cfg)
    gate_cfg = struct();
end
gate_cfg.enabled = local_cfg(gate_cfg, 'enabled', false);
gate_cfg.fail_on_violation = local_cfg(gate_cfg, 'fail_on_violation', false);
gate_cfg.min_train_bin = local_cfg(gate_cfg, 'min_train_bin', 80);
gate_cfg.min_val_bin = local_cfg(gate_cfg, 'min_val_bin', 15);
gate_cfg.min_test_bin = local_cfg(gate_cfg, 'min_test_bin', 15);
gate_cfg.max_bin_imbalance = local_cfg(gate_cfg, 'max_bin_imbalance', 1.50);
gate_cfg.max_zero_abs_ratio = local_cfg(gate_cfg, 'max_zero_abs_ratio', 0.08);
gate_cfg.max_straight_ratio = local_cfg(gate_cfg, 'max_straight_ratio', 0.70);
gate_cfg.min_turn_nonzero_ratio = local_cfg(gate_cfg, 'min_turn_nonzero_ratio', 0.20);
gate_cfg.min_left_right_balance = local_cfg(gate_cfg, 'min_left_right_balance', 0.85);
gate_cfg.min_slope_turn_overlap_train = local_cfg(gate_cfg, 'min_slope_turn_overlap_train', 0.08);
gate_cfg.min_radius_6_8_train = local_cfg(gate_cfg, 'min_radius_6_8_train', 20);
gate_cfg.min_radius_8_10_train = local_cfg(gate_cfg, 'min_radius_8_10_train', 20);
gate_cfg.min_radius_10_12_train = local_cfg(gate_cfg, 'min_radius_10_12_train', 20);
gate_cfg.min_radius_12_16_train = local_cfg(gate_cfg, 'min_radius_12_16_train', 20);
end

function v = local_cfg(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end

function gate = local_coverage_gate(summary, cfg)
gate = struct('enabled', logical(cfg.enabled), 'passed', true, 'failures', {{}});
if ~gate.enabled
    return;
end

split_names = {'train', 'val', 'test'};
mins = [cfg.min_train_bin, cfg.min_val_bin, cfg.min_test_bin];
for si = 1:numel(split_names)
    split_name = split_names{si};
    s = summary.splits.(split_name);
    for bi = 1:numel(s.theta_bin_counts)
        if s.theta_bin_counts(bi) < mins(si)
            edge0 = summary.edges_deg(bi);
            edge1 = summary.edges_deg(bi + 1);
            gate.failures{end+1} = sprintf('%s theta bin [%g,%g) has %d windows, threshold %d.', ...
                split_name, edge0, edge1, s.theta_bin_counts(bi), mins(si));
        end
    end
    if s.theta_bin_imbalance > cfg.max_bin_imbalance
        gate.failures{end+1} = sprintf('%s theta bin imbalance %.3f exceeds %.3f.', ...
            split_name, s.theta_bin_imbalance, cfg.max_bin_imbalance);
    end
    if s.theta_zero_abs_ratio > cfg.max_zero_abs_ratio
        gate.failures{end+1} = sprintf('%s true-zero abs ratio %.4f exceeds %.4f.', ...
            split_name, s.theta_zero_abs_ratio, cfg.max_zero_abs_ratio);
    end
    if s.turn_straight_ratio > cfg.max_straight_ratio
        gate.failures{end+1} = sprintf('%s straight ratio %.4f exceeds %.4f.', ...
            split_name, s.turn_straight_ratio, cfg.max_straight_ratio);
    end
    if s.turn_nonzero_ratio < cfg.min_turn_nonzero_ratio
        gate.failures{end+1} = sprintf('%s nonzero-turn ratio %.4f is below %.4f.', ...
            split_name, s.turn_nonzero_ratio, cfg.min_turn_nonzero_ratio);
    end
    if s.turn_lr_balance < cfg.min_left_right_balance
        gate.failures{end+1} = sprintf('%s left/right balance %.4f is below %.4f.', ...
            split_name, s.turn_lr_balance, cfg.min_left_right_balance);
    end
end

train = summary.splits.train;
if train.slope_turn_overlap_ratio < cfg.min_slope_turn_overlap_train
    gate.failures{end+1} = sprintf('train slope+turn overlap ratio %.4f is below %.4f.', ...
        train.slope_turn_overlap_ratio, cfg.min_slope_turn_overlap_train);
end
radius_thresholds = [cfg.min_radius_6_8_train, cfg.min_radius_8_10_train, ...
    cfg.min_radius_10_12_train, cfg.min_radius_12_16_train];
radius_bin_indices = 2:5;
for i = 1:numel(radius_bin_indices)
    idx = radius_bin_indices(i);
    if train.radius_bins(idx) < radius_thresholds(i)
        gate.failures{end+1} = sprintf('train radius bin %d has %d windows, threshold %d.', ...
            idx, train.radius_bins(idx), radius_thresholds(i));
    end
end

gate.passed = isempty(gate.failures);
end

function local_write_report(report_file, dataset, summary)
fid = fopen(report_file, 'w');
if fid < 0
    error('Cannot write report: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# AGV Theta10 Uniform Dataset Coverage\n\n');
fprintf(fid, '- Dataset: `%s`\n', summary.dataset_file);
if isfield(dataset, 'meta')
    if isfield(dataset.meta, 'horizon_steps')
        fprintf(fid, '- horizon_steps: `%d`\n', dataset.meta.horizon_steps);
    end
    if isfield(dataset.meta, 'theta_mask_strategy')
        fprintf(fid, '- theta_mask_strategy: `%s`\n', dataset.meta.theta_mask_strategy);
    end
    if isfield(dataset.meta, 'source_file')
        fprintf(fid, '- Source train data: `%s`\n', dataset.meta.source_file);
    end
end
fprintf(fid, '\n');

split_names = {'train', 'val', 'test'};
fprintf(fid, '## Split Summary\n\n');
fprintf(fid, '| split | windows | runs | theta mask | flat | stall | slope | nonzero turn ratio | straight ratio | L/R balance | slope+turn overlap | zero abs ratio | bin imbalance | bin CV |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(split_names)
    name = split_names{i};
    s = summary.splits.(name);
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.3f | %.3f |\n', ...
        name, s.n, s.run_n, s.mask_n, s.main_counts, s.turn_nonzero_ratio, ...
        s.turn_straight_ratio, s.turn_lr_balance, s.slope_turn_overlap_ratio, ...
        s.theta_zero_abs_ratio, s.theta_bin_imbalance, s.theta_bin_cv);
end

fprintf(fid, '\n## Theta One-Degree Bins\n\n');
fprintf(fid, '| split ');
for i = 1:(numel(summary.edges_deg) - 1)
    fprintf(fid, '| `[%g,%g)` ', summary.edges_deg(i), summary.edges_deg(i + 1));
end
fprintf(fid, '| out of range |\n');
fprintf(fid, '|---');
for i = 1:(numel(summary.edges_deg) - 1)
    fprintf(fid, '|---:');
end
fprintf(fid, '|---:|\n');
for si = 1:numel(split_names)
    name = split_names{si};
    s = summary.splits.(name);
    fprintf(fid, '| %s ', name);
    for bi = 1:numel(s.theta_bin_counts)
        fprintf(fid, '| %d ', s.theta_bin_counts(bi));
    end
    fprintf(fid, '| %d |\n', s.theta_out_of_range_n);
end

fprintf(fid, '\n## Turn Labels\n\n');
fprintf(fid, '| split | right | straight | left |\n|---|---:|---:|---:|\n');
for i = 1:numel(split_names)
    name = split_names{i};
    fprintf(fid, '| %s | %d | %d | %d |\n', name, summary.splits.(name).turn_counts);
end

fprintf(fid, '\n## Omega Proxy Bins\n\n');
fprintf(fid, 'Proxy: unscaled window-end `gyro_z`.\n\n');
fprintf(fid, '| split | `[0,0.02)` | `[0.02,0.05)` | `[0.05,0.08)` | `[0.08,0.12)` | `[0.12,0.16)` | `[0.16,0.22)` | `>=0.22` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(split_names)
    name = split_names{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).omega_bins);
end

fprintf(fid, '\n## Radius Proxy Bins\n\n');
fprintf(fid, 'Proxy: `R = abs(v_hat) / abs(gyro_z)` for `abs(gyro_z) >= 0.05`.\n\n');
fprintf(fid, '| split | `<6` | `[6,8)` | `[8,10)` | `[10,12)` | `[12,16)` | `[16,20)` | `>=20` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(split_names)
    name = split_names{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).radius_bins);
end

fprintf(fid, '\n## Steering Proxy Bins\n\n');
fprintf(fid, 'Proxy: max absolute unscaled `delta_lf`/`delta_rr` at the window end, in degrees.\n\n');
fprintf(fid, '| split | `[0,2)` | `[2,5)` | `[5,10)` | `[10,15)` | `[15,20)` | `[20,30)` | `>=30` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(split_names)
    name = split_names{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).steer_bins_deg);
end

if isfield(summary, 'gate') && summary.gate.enabled
    fprintf(fid, '\n## Coverage Gate\n\n');
    fprintf(fid, '- passed: `%d`\n', double(summary.gate.passed));
    if isempty(summary.gate.failures)
        fprintf(fid, '- failures: none\n');
    else
        fprintf(fid, '- failures:\n');
        for i = 1:numel(summary.gate.failures)
            fprintf(fid, '  - %s\n', summary.gate.failures{i});
        end
    end
end
end
