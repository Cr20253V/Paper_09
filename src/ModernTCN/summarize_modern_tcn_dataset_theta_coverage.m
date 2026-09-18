function summary = summarize_modern_tcn_dataset_theta_coverage(dataset_file, report_file, gate_cfg)
%SUMMARIZE_MODERN_TCN_DATASET_THETA_COVERAGE Write theta/turn coverage diagnostics.
%
% The report focuses on the prepared training dataset, not the paper scatter
% dataset. Optional gate_cfg can fail the build when coverage is insufficient.

if nargin < 1 || isempty(dataset_file)
    error('ModernTCN:DatasetRequired', ...
        'dataset_file is required; legacy dataset defaults were removed.');
end
if nargin < 2 || isempty(report_file)
    report_file = fullfile(project_root(), 'results', 'modern_tcn', ...
        'ModernTCN_dataset_theta_coverage.md');
end
if nargin < 3
    gate_cfg = struct();
end
gate_cfg = local_gate_defaults(gate_cfg);

S = load(dataset_file, 'dataset');
dataset = S.dataset;

summary = struct();
summary.dataset_file = dataset_file;
summary.report_file = report_file;
summary.splits = struct();

splits = {'train','val','test'};
for i = 1:numel(splits)
    split_name = splits{i};
    summary.splits.(split_name) = local_split_stats(dataset, split_name);
end

summary.feature_stats_train = local_feature_side_stats(dataset, 'train');
summary.gate = local_coverage_gate(summary, gate_cfg);

out_dir = fileparts(report_file);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
local_write_report(report_file, dataset, summary);
fprintf('[dataset theta coverage] wrote %s\n', report_file);

if summary.gate.enabled && gate_cfg.fail_on_violation && ~summary.gate.passed
    error('ModernTCN:CoverageGateFailed', ...
        'Coverage gate failed for %s. See %s.', dataset_file, report_file);
end
end

function s = local_split_stats(dataset, split_name)
theta = dataset.(sprintf('y_theta_%s', split_name));
mask = dataset.(sprintf('mask_theta_%s', split_name));
y_main = dataset.(sprintf('y_main_%s', split_name));
y_turn = dataset.(sprintf('y_turn_%s', split_name));
run_id = dataset.(sprintf('run_id_%s', split_name));
theta_deg = rad2deg(theta(:));
mask = mask(:) == 1;
y_main = y_main(:);
y_turn = y_turn(:);
run_id = run_id(:);
[omega_abs, radius_m] = local_kinematic_proxy(dataset, split_name);

s = struct();
s.n = numel(theta_deg);
s.mask_n = sum(mask);
s.main_counts = [sum(y_main == 1), sum(y_main == 2), sum(y_main == 3)];
s.turn_counts = [sum(y_turn == -1), sum(y_turn == 0), sum(y_turn == 1)];
s.turn_ratios = s.turn_counts / max(s.n, 1);
s.turn_straight_ratio = s.turn_counts(2) / max(s.n, 1);
s.turn_lr_balance = min(s.turn_counts([1 3])) / max(max(s.turn_counts([1 3])), 1);
s.sign_counts = [sum(mask & theta_deg < 0), sum(mask & abs(theta_deg) <= 1e-9), sum(mask & theta_deg > 0)];
s.zero_ratio = s.sign_counts(2) / max(s.mask_n, 1);
s.strict_abs_lt2_n = sum(mask & abs(theta_deg) < 2);
s.strict_abs_lt2_runs = numel(unique(run_id(mask & abs(theta_deg) < 2)));
s.pos_2_8_n = sum(mask & theta_deg >= 2 & theta_deg <= 8);
s.neg_8_2_n = sum(mask & theta_deg <= -2 & theta_deg >= -8);
s.pos_6_8_n = sum(mask & theta_deg >= 6 & theta_deg <= 8);
s.neg_8_6_n = sum(mask & theta_deg <= -6 & theta_deg >= -8);
s.bins = local_theta_bins(theta_deg, mask);
s.core_bins = local_theta_core_bins(theta_deg, mask);
s.slope_turn_overlap_n = sum(mask & abs(theta_deg) >= 2 & y_turn ~= 0);
s.slope_turn_overlap_ratio = s.slope_turn_overlap_n / max(s.mask_n, 1);
s.omega_bins = local_numeric_bins(omega_abs, [0, 0.02, 0.05, 0.08, 0.12, 0.16, 0.22, Inf]);
s.radius_bins = local_numeric_bins(radius_m, [0, 6, 12, 20, 40, Inf]);
s.radius_6_12_n = sum(isfinite(radius_m) & radius_m >= 6 & radius_m < 12);
end

function bins = local_theta_bins(theta_deg, mask)
edges = [-Inf, -8, -6, -4, -2, 0, 2, 4, 6, 8, Inf];
bins = zeros(1, numel(edges) - 1);
for i = 1:(numel(edges) - 1)
    if i == 1
        bins(i) = sum(mask & theta_deg < edges(i + 1));
    elseif i == numel(edges) - 1
        bins(i) = sum(mask & theta_deg >= edges(i));
    else
        bins(i) = sum(mask & theta_deg >= edges(i) & theta_deg < edges(i + 1));
    end
end
end

function bins = local_theta_core_bins(theta_deg, mask)
ranges = [-8 -6; -6 -4; -4 -2; -2 -0.5; 0.5 2; 2 4; 4 6; 6 8];
bins = zeros(1, size(ranges, 1));
for i = 1:size(ranges, 1)
    bins(i) = sum(mask & theta_deg >= ranges(i, 1) & theta_deg < ranges(i, 2));
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

function [omega_abs, radius_m] = local_kinematic_proxy(dataset, split_name)
X = dataset.(sprintf('X_%s', split_name));
n = size(X, 1);
omega_abs = NaN(n, 1);
radius_m = NaN(n, 1);
feat_names = cellstr(dataset.feat_names);
idx_omega = find(strcmp(feat_names, 'gyro_z'), 1);
idx_v = find(strcmp(feat_names, 'v_hat'), 1);
if isempty(idx_omega) || isempty(idx_v) || ~isfield(dataset, 'scaler')
    return;
end
omega = local_unscale_last_feature(X, dataset.scaler, idx_omega);
v = abs(local_unscale_last_feature(X, dataset.scaler, idx_v));
omega_abs = abs(omega);
turn = omega_abs >= 0.05;
radius_m(turn) = v(turn) ./ max(omega_abs(turn), eps);
end

function x = local_unscale_last_feature(X, scaler, idx)
x = double(reshape(X(:, end, idx), [], 1));
mu = double(scaler.mean(idx));
sig = double(scaler.std(idx));
x = x .* sig + mu;
end

function T = local_feature_side_stats(dataset, split_name)
X = dataset.(sprintf('X_%s', split_name));
theta_deg = rad2deg(dataset.(sprintf('y_theta_%s', split_name)));
mask = dataset.(sprintf('mask_theta_%s', split_name)) == 1;
feat_names = cellstr(dataset.feat_names);
want = {'gyro_z','I_lf','I_rr','omega_wheel_lf','omega_wheel_rr', ...
    'delta_lf','delta_rr','v_hat','dv_hat_dt','I_sum', ...
    'accel_per_current','dv_hat_dt_lp','accel_x_wheel', ...
    'I_drive_signed','current_per_accel','drive_load_proxy', ...
    'a_hp','yaw_consistency_error'};
rows = struct('feature', {}, 'neg_mean', {}, 'neg_std', {}, 'pos_mean', {}, 'pos_std', {}, ...
    'neg_r', {}, 'pos_r', {});

neg = mask & theta_deg >= -8 & theta_deg <= -2;
pos = mask & theta_deg >= 2 & theta_deg <= 8;
for i = 1:numel(want)
    idx = find(strcmp(feat_names, want{i}), 1);
    if isempty(idx)
        continue;
    end
    z = squeeze(mean(X(:, :, idx), 2));
    rows(end+1).feature = want{i}; %#ok<AGROW>
    rows(end).neg_mean = mean(z(neg), 'omitnan');
    rows(end).neg_std = std(z(neg), 0, 'omitnan');
    rows(end).pos_mean = mean(z(pos), 'omitnan');
    rows(end).pos_std = std(z(pos), 0, 'omitnan');
    rows(end).neg_r = local_corr(theta_deg(neg), z(neg));
    rows(end).pos_r = local_corr(theta_deg(pos), z(pos));
end
T = struct2table(rows);
end

function r = local_corr(a, b)
a = a(:);
b = b(:);
m = isfinite(a) & isfinite(b);
if sum(m) < 3
    r = NaN;
    return;
end
C = corrcoef(a(m), b(m));
r = C(1, 2);
end

function local_write_report(report_file, dataset, summary)
fid = fopen(report_file, 'w');
if fid < 0
    error('Cannot write report: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN Dataset Theta Coverage\n\n');
fprintf(fid, '- Dataset: `%s`\n', summary.dataset_file);
if isfield(dataset, 'meta') && isfield(dataset.meta, 'theta_mask_strategy')
    fprintf(fid, '- theta_mask_strategy: `%s`\n', dataset.meta.theta_mask_strategy);
end
if isfield(dataset, 'meta') && isfield(dataset.meta, 'source_file')
    fprintf(fid, '- Source train data: `%s`\n', dataset.meta.source_file);
end
fprintf(fid, '\n');

splits = {'train','val','test'};

fprintf(fid, '## Split Coverage\n\n');
fprintf(fid, '| split | windows | theta mask | flat | stall | slope | neg | zero | pos | strict `abs(theta)<2` | runs `<2` | `-8..-2` | `+2..+8` | `-8..-6` | `+6..+8` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    s = summary.splits.(name);
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, s.n, s.mask_n, s.main_counts, s.sign_counts, s.strict_abs_lt2_n, ...
        s.strict_abs_lt2_runs, s.neg_8_2_n, s.pos_2_8_n, s.neg_8_6_n, s.pos_6_8_n);
end

fprintf(fid, '\n## Turn Coverage\n\n');
fprintf(fid, '| split | right | straight | left | straight ratio | L/R balance | slope+turn overlap | overlap ratio |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    s = summary.splits.(name);
    fprintf(fid, '| %s | %d | %d | %d | %.4f | %.4f | %d | %.4f |\n', ...
        name, s.turn_counts, s.turn_straight_ratio, s.turn_lr_balance, ...
        s.slope_turn_overlap_n, s.slope_turn_overlap_ratio);
end

fprintf(fid, '\n## Omega Proxy Bins\n\n');
fprintf(fid, 'Proxy uses the unscaled window-end `gyro_z` feature because `omega_ref` is not stored in the prepared dataset.\n\n');
fprintf(fid, '| split | `[0,0.02)` | `[0.02,0.05)` | `[0.05,0.08)` | `[0.08,0.12)` | `[0.12,0.16)` | `[0.16,0.22)` | `>=0.22` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).omega_bins);
end

fprintf(fid, '\n## Radius Proxy Bins\n\n');
fprintf(fid, 'Proxy uses `R = abs(v_hat) / abs(gyro_z)` for windows with `abs(gyro_z) >= 0.05`.\n\n');
fprintf(fid, '| split | `<6m` | `[6,12)m` | `[12,20)m` | `[20,40)m` | `>=40m` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).radius_bins);
end

fprintf(fid, '\n## Theta Supervision Bins\n\n');
fprintf(fid, '| split | `<-8` | `[-8,-6)` | `[-6,-4)` | `[-4,-2)` | `[-2,0)` | `[0,2)` | `[2,4)` | `[4,6)` | `[6,8)` | `>=8` |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n', ...
        name, summary.splits.(name).bins);
end

fprintf(fid, '\n## Core Theta Gate Bins\n\n');
fprintf(fid, '| split | `[-8,-6)` | `[-6,-4)` | `[-4,-2)` | `[-2,-0.5)` | `[0.5,2)` | `[2,4)` | `[4,6)` | `[6,8)` | zero ratio |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(splits)
    name = splits{i};
    s = summary.splits.(name);
    fprintf(fid, '| %s | %d | %d | %d | %d | %d | %d | %d | %d | %.4f |\n', ...
        name, s.core_bins, s.zero_ratio);
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

fprintf(fid, '\n## Train Feature Side Stats\n\n');
fprintf(fid, '| feature | neg mean | neg std | pos mean | pos std | r neg | r pos |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|\n');
T = summary.feature_stats_train;
for i = 1:height(T)
    fprintf(fid, '| %s | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        T.feature{i}, T.neg_mean(i), T.neg_std(i), T.pos_mean(i), T.pos_std(i), T.neg_r(i), T.pos_r(i));
end
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
gate_cfg.min_train_core_bin = local_cfg(gate_cfg, 'min_train_core_bin', 80);
gate_cfg.min_val_core_bin = local_cfg(gate_cfg, 'min_val_core_bin', 15);
gate_cfg.min_test_core_bin = local_cfg(gate_cfg, 'min_test_core_bin', 15);
gate_cfg.max_zero_ratio_train = local_cfg(gate_cfg, 'max_zero_ratio_train', 0.55);
gate_cfg.max_zero_ratio_val = local_cfg(gate_cfg, 'max_zero_ratio_val', 0.65);
gate_cfg.max_zero_ratio_test = local_cfg(gate_cfg, 'max_zero_ratio_test', 0.65);
gate_cfg.max_straight_ratio = local_cfg(gate_cfg, 'max_straight_ratio', 0.75);
gate_cfg.min_left_right_balance = local_cfg(gate_cfg, 'min_left_right_balance', 0.70);
gate_cfg.min_slope_turn_overlap_train = local_cfg(gate_cfg, 'min_slope_turn_overlap_train', 0.03);
gate_cfg.min_radius_6_12_train = local_cfg(gate_cfg, 'min_radius_6_12_train', 20);
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

names = {'[-8,-6)', '[-6,-4)', '[-4,-2)', '[-2,-0.5)', '[0.5,2)', '[2,4)', '[4,6)', '[6,8)'};
splits = {'train','val','test'};
mins = [cfg.min_train_core_bin, cfg.min_val_core_bin, cfg.min_test_core_bin];
zero_max = [cfg.max_zero_ratio_train, cfg.max_zero_ratio_val, cfg.max_zero_ratio_test];
for si = 1:numel(splits)
    split_name = splits{si};
    s = summary.splits.(split_name);
    for bi = 1:numel(names)
        if s.core_bins(bi) < mins(si)
            gate.failures{end+1} = sprintf('%s core theta bin %s has %d windows, threshold %d.', ...
                split_name, names{bi}, s.core_bins(bi), mins(si)); %#ok<AGROW>
        end
    end
    if s.zero_ratio > zero_max(si)
        gate.failures{end+1} = sprintf('%s true-zero ratio %.4f exceeds %.4f.', ...
            split_name, s.zero_ratio, zero_max(si)); %#ok<AGROW>
    end
    if s.turn_straight_ratio > cfg.max_straight_ratio
        gate.failures{end+1} = sprintf('%s straight turn-label ratio %.4f exceeds %.4f.', ...
            split_name, s.turn_straight_ratio, cfg.max_straight_ratio); %#ok<AGROW>
    end
    if s.turn_lr_balance < cfg.min_left_right_balance
        gate.failures{end+1} = sprintf('%s left/right balance %.4f is below %.4f.', ...
            split_name, s.turn_lr_balance, cfg.min_left_right_balance); %#ok<AGROW>
    end
end

train = summary.splits.train;
if train.slope_turn_overlap_ratio < cfg.min_slope_turn_overlap_train
    gate.failures{end+1} = sprintf('train slope+turn overlap ratio %.4f is below %.4f.', ...
        train.slope_turn_overlap_ratio, cfg.min_slope_turn_overlap_train); %#ok<AGROW>
end
if train.radius_6_12_n < cfg.min_radius_6_12_train
    gate.failures{end+1} = sprintf('train radius proxy [6,12)m has %d windows, threshold %d.', ...
        train.radius_6_12_n, cfg.min_radius_6_12_train); %#ok<AGROW>
end
gate.passed = isempty(gate.failures);
end
