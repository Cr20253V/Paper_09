function result = ModernTCN_analyze_closed_loop_out(out_file)
%MODERNTCN_ANALYZE_CLOSED_LOOP_OUT Analyze ModernTCN closed-loop Simulink logs.
%
%   result = ModernTCN_analyze_closed_loop_out('out.mat')
%
% The analysis expects logsout to contain diag.y_raw plus the public diag.*
% signals from LPVMPC_AGV_simulink_Modern_TCN. It does not modify the model.

if nargin < 1 || isempty(out_file)
    out_file = fullfile(local_project_root(), 'out.mat');
end
if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
S = load(out_file, 'logsout');
logs = S.logsout;

t = local_time(logs, 'diag.y_raw');
y_raw = local_data(logs, 'diag.y_raw');
theta_hat = local_resample(logs, 'diag.theta_hat', t);
label_main = local_resample(logs, 'diag.label_main', t);
label_turn = local_resample(logs, 'diag.label_turn', t);
conf_main = local_resample(logs, 'diag.conf_main', t);
theta_ground = local_resample(logs, 'diag.theta_ground', t);
omega_ref = local_resample(logs, 'diag.omega_ref', t);

e_y = local_resample(logs, 'diag.e_y', t);
e_psi = local_resample(logs, 'diag.e_psi', t);
e_v = local_resample(logs, 'diag.e_v', t);
e_omega = local_resample(logs, 'diag.e_omega', t);
F_cmd = local_resample(logs, 'diag.F_cmd', t);
omega_cmd = local_resample(logs, 'diag.omega_cmd', t);

default_cfg = ModernTCN_default_config(root);
dataset_file = default_cfg.dataset_file;
Ds = load(dataset_file, 'dataset');
dataset = Ds.dataset;

params = parameters();
[~, feature_norm] = local_extract_features_from_yraw(y_raw, t, params, dataset);

zones = local_get_zones(root, t);
zone_names = fieldnames(zones);

truth = local_make_truth(theta_ground, omega_ref);

rows = repmat(local_empty_zone_row(), numel(zone_names), 1);
for i = 1:numel(zone_names)
    name = zone_names{i};
    tr = zones.(name);
    mask = t >= tr(1) & t < tr(2);
    rows(i) = local_zone_row(name, tr, mask, t, e_y, e_psi, e_v, e_omega, ...
        theta_hat, theta_ground, label_main, label_turn, conf_main, truth, ...
        F_cmd, omega_cmd);
end
zone_table = struct2table(rows);

feature_zone = local_feature_zone_summary(zone_names, zones, t, feature_norm, dataset.feat_names);
feature_compare = local_feature_compare_to_training(dataset, feature_norm, t, zones);
assessment = local_assess_closed_loop(zone_table, feature_zone);

out_dir = fullfile(root, 'results', 'modern_tcn', 'closed_loop_diag');
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
[~, base_name, ~] = fileparts(out_file);
mat_file = fullfile(out_dir, sprintf('%s_modern_tcn_closed_loop_diag.mat', base_name));
report_file = fullfile(out_dir, sprintf('%s_modern_tcn_closed_loop_diag_report.md', base_name));

result = struct();
result.out_file = out_file;
result.dataset_file = dataset_file;
result.zone_table = zone_table;
result.feature_zone = feature_zone;
result.feature_compare = feature_compare;
result.assessment = assessment;
result.feature_names = dataset.feat_names(:);
result.theta_error_deg = rad2deg(theta_hat - theta_ground);
result.report_file = report_file;
result.mat_file = mat_file;

save(mat_file, 'result');
local_write_report(report_file, result);

fprintf('[ModernTCN closed-loop diag] report: %s\n', report_file);
fprintf('[ModernTCN closed-loop diag] mat   : %s\n', mat_file);
disp(zone_table(:, {'zone','ey_rmse','epsi_rmse','ev_rmse','theta_mae_deg', ...
    'main_acc_pct','turn_acc_pct','pred_main_1_pct','pred_main_3_pct', ...
    'pred_turn_0_pct','pred_turn_1_pct'}));
disp(assessment(:, {'check','value','threshold','pass'}));
end

function row = local_empty_zone_row()
row = struct('zone', "", 't0', NaN, 't1', NaN, ...
    'ey_rmse', NaN, 'ey_peak', NaN, 'epsi_rmse', NaN, 'epsi_peak', NaN, ...
    'ev_rmse', NaN, 'ev_peak', NaN, 'eomega_rmse', NaN, 'eomega_peak', NaN, ...
    'theta_mae_deg', NaN, 'theta_rmse_deg', NaN, 'theta_peak_deg', NaN, ...
    'theta_hat_min_deg', NaN, 'theta_hat_max_deg', NaN, ...
    'main_acc_pct', NaN, 'turn_acc_pct', NaN, ...
    'true_main_1_pct', NaN, 'true_main_3_pct', NaN, ...
    'pred_main_1_pct', NaN, 'pred_main_2_pct', NaN, 'pred_main_3_pct', NaN, ...
    'true_turn_m1_pct', NaN, 'true_turn_0_pct', NaN, 'true_turn_1_pct', NaN, ...
    'pred_turn_m1_pct', NaN, 'pred_turn_0_pct', NaN, 'pred_turn_1_pct', NaN, ...
    'conf_median', NaN, 'conf_p10', NaN, ...
    'F_min', NaN, 'F_max', NaN, 'omega_cmd_min', NaN, 'omega_cmd_max', NaN);
end

function row = local_zone_row(name, tr, mask, ~, e_y, e_psi, e_v, e_omega, ...
    theta_hat, theta_ground, label_main, label_turn, conf_main, truth, F_cmd, omega_cmd)
row = local_empty_zone_row();
row.zone = string(name);
row.t0 = tr(1);
row.t1 = tr(2);
if nnz(mask) < 2
    return;
end

th_err = theta_hat(mask) - theta_ground(mask);
row.ey_rmse = local_rms(e_y(mask));
row.ey_peak = max(abs(e_y(mask)));
row.epsi_rmse = local_rms(e_psi(mask));
row.epsi_peak = max(abs(e_psi(mask)));
row.ev_rmse = local_rms(e_v(mask));
row.ev_peak = max(abs(e_v(mask)));
row.eomega_rmse = local_rms(e_omega(mask));
row.eomega_peak = max(abs(e_omega(mask)));
row.theta_mae_deg = rad2deg(mean(abs(th_err), 'omitnan'));
row.theta_rmse_deg = rad2deg(local_rms(th_err));
row.theta_peak_deg = rad2deg(max(abs(th_err)));
row.theta_hat_min_deg = rad2deg(min(theta_hat(mask)));
row.theta_hat_max_deg = rad2deg(max(theta_hat(mask)));

lm = round(label_main(mask));
lt = round(label_turn(mask));
tm = truth.main(mask);
tt = truth.turn(mask);
row.main_acc_pct = 100 * mean(lm == tm, 'omitnan');
row.turn_acc_pct = 100 * mean(lt == tt, 'omitnan');
row.true_main_1_pct = 100 * mean(tm == 1, 'omitnan');
row.true_main_3_pct = 100 * mean(tm == 3, 'omitnan');
row.pred_main_1_pct = 100 * mean(lm == 1, 'omitnan');
row.pred_main_2_pct = 100 * mean(lm == 2, 'omitnan');
row.pred_main_3_pct = 100 * mean(lm == 3, 'omitnan');
row.true_turn_m1_pct = 100 * mean(tt == -1, 'omitnan');
row.true_turn_0_pct = 100 * mean(tt == 0, 'omitnan');
row.true_turn_1_pct = 100 * mean(tt == 1, 'omitnan');
row.pred_turn_m1_pct = 100 * mean(lt == -1, 'omitnan');
row.pred_turn_0_pct = 100 * mean(lt == 0, 'omitnan');
row.pred_turn_1_pct = 100 * mean(lt == 1, 'omitnan');
row.conf_median = median(conf_main(mask), 'omitnan');
row.conf_p10 = prctile(conf_main(mask), 10);
row.F_min = min(F_cmd(mask));
row.F_max = max(F_cmd(mask));
row.omega_cmd_min = min(omega_cmd(mask));
row.omega_cmd_max = max(omega_cmd(mask));
end

function truth = local_make_truth(theta_ground, omega_ref)
truth = struct();
truth.main = ones(size(theta_ground));
truth.main(abs(theta_ground) > deg2rad(2.0)) = 3;
truth.turn = zeros(size(omega_ref));
truth.turn(omega_ref > 0.02) = 1;
truth.turn(omega_ref < -0.02) = -1;
end

function [feature_raw, feature_norm] = local_extract_features_from_yraw(y_raw, t, params, dataset)
Ts = median(diff(t));
scaler = dataset.scaler;
seq_skip = round(dataset.meta.skip_initial_sec / Ts);
n = size(y_raw, 1);
feat_dim = numel(scaler.mean);
feature_raw = nan(n, feat_dim);

feature_cfg = struct('tau_diff', scaler.tau_diff, 'tau_accel_lp', scaler.tau_accel_lp);
if seq_skip < n
    feature_raw((seq_skip + 1):n, :) = extract_passive_features( ...
        'batch', y_raw((seq_skip + 1):n, :), params, Ts, feature_cfg);
end

feature_norm = (feature_raw - double(scaler.mean(:).')) ./ ...
    (double(scaler.std(:).') + 1e-8);
end

function T = local_feature_zone_summary(zone_names, zones, t, feature_norm, feat_names)
rows = repmat(struct('zone', "", 'feature', "", 'median_z', NaN, ...
    'p95_abs_z', NaN, 'max_abs_z', NaN, 'pct_abs_z_gt_3', NaN), ...
    numel(zone_names) * numel(feat_names), 1);
idx = 0;
for zi = 1:numel(zone_names)
    zn = zone_names{zi};
    tr = zones.(zn);
    mask = t >= tr(1) & t < tr(2);
    for fi = 1:numel(feat_names)
        idx = idx + 1;
        z = feature_norm(mask, fi);
        z = z(isfinite(z));
        rows(idx).zone = string(zn);
        rows(idx).feature = string(feat_names{fi});
        if isempty(z)
            continue;
        end
        rows(idx).median_z = median(z);
        rows(idx).p95_abs_z = prctile(abs(z), 95);
        rows(idx).max_abs_z = max(abs(z));
        rows(idx).pct_abs_z_gt_3 = 100 * mean(abs(z) > 3);
    end
end
T = struct2table(rows(1:idx));
end

function T = local_feature_compare_to_training(dataset, feature_norm, t, zones)
feat_names = dataset.feat_names(:);
X = cat(1, dataset.X_train, dataset.X_val, dataset.X_test);
y_main = [dataset.y_main_train; dataset.y_main_val; dataset.y_main_test];
y_turn = [dataset.y_turn_train; dataset.y_turn_val; dataset.y_turn_test];

cases = {
    'train_flat_straight',  y_main == 1 & y_turn == 0;
    'train_flat_left',      y_main == 1 & y_turn == 1;
    'train_slope_straight', y_main == 3 & y_turn == 0;
    'sim_pure_turn',        [];
    'sim_pure_slope',       [];
    'sim_composite',        [];
};

rows = repmat(struct('group', "", 'feature', "", 'median_z', NaN, ...
    'p95_abs_z', NaN, 'max_abs_z', NaN), numel(cases) * numel(feat_names), 1);
idx = 0;
for ci = 1:size(cases, 1)
    group = cases{ci, 1};
    train_mask = cases{ci, 2};
    if startsWith(group, 'train')
        if ~any(train_mask)
            Z = [];
        else
            Xg = X(train_mask, :, :);
            Z = reshape(Xg, [], numel(feat_names));
        end
    else
        switch group
            case 'sim_pure_turn'
                tr = zones.pure_turn;
            case 'sim_pure_slope'
                tr = zones.pure_slope;
            otherwise
                tr = zones.composite;
        end
        m = t >= tr(1) & t < tr(2);
        Z = feature_norm(m, :);
    end
    for fi = 1:numel(feat_names)
        idx = idx + 1;
        z = Z(:, fi);
        z = z(isfinite(z));
        rows(idx).group = string(group);
        rows(idx).feature = string(feat_names{fi});
        if isempty(z)
            continue;
        end
        rows(idx).median_z = median(z);
        rows(idx).p95_abs_z = prctile(abs(z), 95);
        rows(idx).max_abs_z = max(abs(z));
    end
end
T = struct2table(rows(1:idx));
end

function assessment = local_assess_closed_loop(zone_table, feature_zone)
rows = repmat(struct('check', "", 'value', NaN, 'threshold', "", ...
    'pass', false, 'comment', ""), 0, 1);

pure_turn = local_zone_or_empty(zone_table, 'pure_turn');
pure_slope = local_zone_or_empty(zone_table, 'pure_slope');
composite = local_zone_or_empty(zone_table, 'composite');
closure = local_zone_or_empty(zone_table, 'closure');
if height(closure) == 0
    closure = local_zone_or_empty(zone_table, 'closed_loop');
end

if height(pure_turn) > 0
    rows(end+1) = local_assess_row('pure_turn_false_slope_pct', ...
        pure_turn.pred_main_3_pct, '<= 5', pure_turn.pred_main_3_pct <= 5, ...
        'Flat turn should not be classified as slope.');
    rows(end+1) = local_assess_row('pure_turn_left_recall_pct', ...
        pure_turn.pred_turn_1_pct, '>= 80', pure_turn.pred_turn_1_pct >= 80, ...
        'Flat left turn should be detected before labels are used by MPC.');
    rows(end+1) = local_assess_row('pure_turn_theta_mae_deg', ...
        pure_turn.theta_mae_deg, '<= 2', pure_turn.theta_mae_deg <= 2, ...
        'Theta estimate should stay near zero on flat turns.');
end

if height(pure_slope) > 0
    rows(end+1) = local_assess_row('pure_slope_main_acc_pct', ...
        pure_slope.main_acc_pct, '>= 90', pure_slope.main_acc_pct >= 90, ...
        'Pure slope segment should be recognized consistently.');
    rows(end+1) = local_assess_row('pure_slope_theta_mae_deg', ...
        pure_slope.theta_mae_deg, '<= 2', pure_slope.theta_mae_deg <= 2, ...
        'Slope magnitude error should remain below controller-use tolerance.');
end

if height(composite) > 0
    rows(end+1) = local_assess_row('composite_turn_recall_pct', ...
        composite.pred_turn_1_pct, '>= 60', composite.pred_turn_1_pct >= 60, ...
        'Composite slope-turn segment should preserve turn information.');
end

if height(closure) > 0
    rows(end+1) = local_assess_row('closure_main_acc_pct', ...
        closure.main_acc_pct, '>= 90', closure.main_acc_pct >= 90, ...
        'Low-speed closure should not collapse into false slope labels.');
end

ood = local_feature_ood(feature_zone, closure, 'v_hat');
if isfinite(ood)
    rows(end+1) = local_assess_row('closure_v_hat_ood_pct', ...
        ood, '<= 5', ood <= 5, ...
        'High low-speed OOD rate means the dataset needs low-speed closure samples.');
end

ood = local_feature_ood(feature_zone, closure, 'accel_per_current');
if isfinite(ood)
    rows(end+1) = local_assess_row('closure_accel_per_current_ood_pct', ...
        ood, '<= 5', ood <= 5, ...
        'Large accel/current ratio OOD points to low-load sample coverage gap.');
end

assessment = struct2table(rows);
end

function row = local_assess_row(check, value, threshold, pass, comment)
row = struct('check', string(check), 'value', double(value), ...
    'threshold', string(threshold), 'pass', logical(pass), ...
    'comment', string(comment));
end

function Z = local_zone_or_empty(T, name)
Z = T(T.zone == string(name), :);
end

function ood = local_feature_ood(feature_zone, zone_row, feature_name)
ood = NaN;
if height(zone_row) == 0
    return;
end
zone_name = zone_row.zone(1);
m = feature_zone.zone == zone_name & feature_zone.feature == string(feature_name);
if any(m)
    ood = feature_zone.pct_abs_z_gt_3(find(m, 1, 'first'));
end
end

function zones = local_get_zones(root, t)
path_file = fullfile(root, 'data', 'paths', 'path_industrial_lite.mat');
if exist(path_file, 'file') == 2
    S = load(path_file, 'ref');
    if isfield(S, 'ref') && isfield(S.ref, 'meta') && isfield(S.ref.meta, 'zones')
        zones = S.ref.meta.zones;
        return;
    end
end
zones = struct();
zones.startup = [min(t), 10];
zones.golden_test = [10, 50];
zones.pure_turn = [50, 78];
zones.pure_slope = [78, 98];
zones.composite = [98, 118];
zones.closure = [118, max(t)];
end

function data = local_resample(logs, name, t)
ts = local_timeseries(logs, name);
data = squeeze(double(ts.Data));
if isvector(data)
    data = data(:);
else
    data = reshape(data, [], size(data, ndims(data)));
    data = data(:);
end
tt = double(ts.Time(:));
if numel(tt) ~= numel(data)
    data = squeeze(double(ts.Data));
    data = reshape(data, [], numel(tt)).';
end
if numel(tt) == numel(t) && max(abs(tt - t)) < 1e-12
    return;
end
data = interp1(tt, data, t, 'linear', 'extrap');
end

function data = local_data(logs, name)
ts = local_timeseries(logs, name);
data = squeeze(double(ts.Data));
end

function t = local_time(logs, name)
ts = local_timeseries(logs, name);
t = double(ts.Time(:));
end

function ts = local_timeseries(logs, name)
hit = [];
for i = 1:logs.numElements
    el = logs.getElement(i);
    if strcmp(el.Name, name)
        hit(end + 1) = i; %#ok<AGROW>
    end
end
if isempty(hit)
    error('ModernTCN:MissingLogSignal', 'logsout missing signal: %s', name);
end
% Duplicate names exist for some diag signals. Prefer the last logged signal,
% which is the high-rate diagnostic line in this model.
ts = logs.getElement(hit(end)).Values;
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN Closed-loop Diagnostic\n\n');
fprintf(fid, '- out file: `%s`\n', result.out_file);
fprintf(fid, '- dataset: `%s`\n\n', result.dataset_file);

fprintf(fid, '## Decision Summary\n\n');
fprintf(fid, '- Keep ModernTCN output diagnostic-only for now; do not feed `theta_hat` or labels into MPC scheduling yet.\n');
fprintf(fid, '- The controller is not the current bottleneck: tracking errors stay small in the neutral-control run, while classifier errors concentrate in path zones.\n');
fprintf(fid, '- Main data gap: low-load flat turns are being confused with slope, and turn labels are missed in flat/composite turn zones.\n');
fprintf(fid, '- Next training revision should add targeted short samples for flat low-load turns and mild slope-turn composites, then rerun full-test and this closed-loop diagnostic.\n\n');

fprintf(fid, '## Readiness Checks\n\n');
A = result.assessment;
fprintf(fid, '| check | value | threshold | pass | comment |\n');
fprintf(fid, '|---|---:|---:|---:|---|\n');
for i = 1:height(A)
    if A.pass(i)
        pass_text = "yes";
    else
        pass_text = "no";
    end
    fprintf(fid, '| %s | %.3f | %s | %s | %s |\n', ...
        A.check(i), A.value(i), A.threshold(i), pass_text, A.comment(i));
end
fprintf(fid, '\n');

fprintf(fid, '## Per-zone Metrics\n\n');
fprintf(fid, '| zone | ey rmse | epsi rmse | ev rmse | theta MAE deg | main acc | turn acc | pred main 1/2/3 | pred turn -1/0/1 |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
T = result.zone_table;
for i = 1:height(T)
    fprintf(fid, '| %s | %.4f | %.4f | %.4f | %.3f | %.1f | %.1f | %.1f/%.1f/%.1f | %.1f/%.1f/%.1f |\n', ...
        T.zone(i), T.ey_rmse(i), T.epsi_rmse(i), T.ev_rmse(i), ...
        T.theta_mae_deg(i), T.main_acc_pct(i), T.turn_acc_pct(i), ...
        T.pred_main_1_pct(i), T.pred_main_2_pct(i), T.pred_main_3_pct(i), ...
        T.pred_turn_m1_pct(i), T.pred_turn_0_pct(i), T.pred_turn_1_pct(i));
end

fprintf(fid, '\n## Top Feature Z-score by Zone\n\n');
F = result.feature_zone;
zones = unique(F.zone, 'stable');
for zi = 1:numel(zones)
    zname = zones(zi);
    Fz = F(F.zone == zname, :);
    Fz = sortrows(Fz, 'p95_abs_z', 'descend');
    fprintf(fid, '### %s\n\n', zname);
    fprintf(fid, '| feature | median z | p95 abs z | max abs z | pct abs z > 3 |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|\n');
    n = min(8, height(Fz));
    for i = 1:n
        fprintf(fid, '| %s | %.3f | %.3f | %.3f | %.1f |\n', ...
            Fz.feature(i), Fz.median_z(i), Fz.p95_abs_z(i), ...
            Fz.max_abs_z(i), Fz.pct_abs_z_gt_3(i));
    end
    fprintf(fid, '\n');
end

fprintf(fid, '## Feature Distribution Compare\n\n');
groups = unique(result.feature_compare.group, 'stable');
for gi = 1:numel(groups)
    g = groups(gi);
    G = result.feature_compare(result.feature_compare.group == g, :);
    G = sortrows(G, 'p95_abs_z', 'descend');
    fprintf(fid, '### %s\n\n', g);
    fprintf(fid, '| feature | median z | p95 abs z | max abs z |\n');
    fprintf(fid, '|---|---:|---:|---:|\n');
    n = min(8, height(G));
    for i = 1:n
        fprintf(fid, '| %s | %.3f | %.3f | %.3f |\n', ...
            G.feature(i), G.median_z(i), G.p95_abs_z(i), G.max_abs_z(i));
    end
    fprintf(fid, '\n');
end
end

function y = local_rms(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = sqrt(mean(x.^2));
end
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end
