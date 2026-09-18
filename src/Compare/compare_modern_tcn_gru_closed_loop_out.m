function result = compare_modern_tcn_gru_closed_loop_out(modern_file, gru_file, path_file)
%COMPARE_MODERN_TCN_GRU_CLOSED_LOOP_OUT Compare two closed-loop simulation logs.
%
% The metric names are aligned with the existing closed-loop test scripts:
% tracking RMSE/peak, control saturation, j_du, constraint violation rate,
% solver runtime, and per-zone diagnostics.

if nargin < 1 || isempty(modern_file)
    modern_file = fullfile(local_project_root(), 'ModernTCN_out.mat');
end
if nargin < 2 || isempty(gru_file)
    gru_file = fullfile(local_project_root(), 'GRU_out.mat');
end
if nargin < 3 || isempty(path_file)
    path_file = fullfile(local_project_root(), 'data', 'paths', ...
        'path_modern_tcn_demo_loop_v1.mat');
end

if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
out_dir = fullfile(root, 'results', 'compare', 'modern_tcn_gru_closed_loop');
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end

P = load(path_file, 'ref');
ref = P.ref;
zones = local_get_zones(ref);

runs = [ ...
    local_analyze_one("ModernTCN", modern_file, zones), ...
    local_analyze_one("GRU", gru_file, zones)];

summary_table = struct2table([runs.summary]);
zone_table = struct2table([runs.zones]);

summary_file = fullfile(out_dir, 'modern_tcn_gru_closed_loop_summary.csv');
zone_file = fullfile(out_dir, 'modern_tcn_gru_closed_loop_zones.csv');
mat_file = fullfile(out_dir, 'modern_tcn_gru_closed_loop_compare.mat');
report_file = fullfile(out_dir, 'modern_tcn_gru_closed_loop_report.md');

writetable(summary_table, summary_file);
writetable(zone_table, zone_file);

result = struct();
result.modern_file = modern_file;
result.gru_file = gru_file;
result.path_file = path_file;
result.summary_table = summary_table;
result.zone_table = zone_table;
result.summary_file = summary_file;
result.zone_file = zone_file;
result.report_file = report_file;
result.mat_file = mat_file;
result.runs = runs;

save(mat_file, 'result');
local_write_report(report_file, result);

fprintf('[compare] summary: %s\n', summary_file);
fprintf('[compare] zones:   %s\n', zone_file);
fprintf('[compare] report:  %s\n', report_file);
disp(summary_table(:, {'controller','ey_rmse','ey_peak','epsi_rmse', ...
    'ev_rmse','eomega_rmse','j_du','viol_rate','theta_mae_deg', ...
    'main_acc_pct','turn_acc_pct'}));
end

function run = local_analyze_one(controller, mat_file, zones)
S = load(mat_file, 'logsout');
logs = S.logsout;

[e_y, t] = local_get_signal(logs, 'diag.e_y');
if isempty(t)
    error('Missing diag.e_y in %s', mat_file);
end
t = t(:);

sig = struct();
sig.e_y = e_y;
sig.e_psi = local_resample_signal(logs, 'diag.e_psi', t);
sig.e_v = local_resample_signal(logs, 'diag.e_v', t);
sig.e_omega = local_resample_signal(logs, 'diag.e_omega', t);
sig.F_cmd = local_resample_signal(logs, 'diag.F_cmd', t);
sig.omega_cmd = local_resample_signal(logs, 'diag.omega_cmd', t);
sig.X = local_resample_signal(logs, 'diag.X', t);
sig.Y = local_resample_signal(logs, 'diag.Y', t);
sig.X_ref = local_resample_signal(logs, 'diag.X_ref', t);
sig.Y_ref = local_resample_signal(logs, 'diag.Y_ref', t);
sig.v = local_resample_signal(logs, 'diag.v', t);
sig.omega = local_resample_signal(logs, 'diag.omega', t);
sig.v_ref = local_resample_signal(logs, 'diag.v_ref', t);
sig.omega_ref = local_resample_signal(logs, 'diag.omega_ref', t);
sig.theta_ref = local_resample_signal(logs, 'diag.theta_ref', t);
sig.theta_ground = local_resample_signal(logs, 'diag.theta_ground', t);
sig.theta_hat = local_resample_signal(logs, 'diag.theta_hat', t);
sig.label_main = local_resample_signal(logs, 'diag.label_main', t, 'previous');
sig.label_turn = local_resample_signal(logs, 'diag.label_turn', t, 'previous');
sig.conf_main = local_resample_signal(logs, 'diag.conf_main', t);
sig.rho_f = local_resample_signal(logs, 'diag.rho_f', t);
sig.rho_n = local_resample_signal(logs, 'diag.rho_n', t);
sig.F_limit_hi = local_resample_signal(logs, 'diag.F_limit_hi', t);
sig.F_limit_lo = local_resample_signal(logs, 'diag.F_limit_lo', t);
sig.solve_time_ms = local_resample_signal(logs, 'diag_solve_time_ms', t);

if isempty(sig.e_v) && ~isempty(sig.v) && ~isempty(sig.v_ref)
    sig.e_v = sig.v - sig.v_ref;
end
if isempty(sig.e_omega) && ~isempty(sig.omega) && ~isempty(sig.omega_ref)
    sig.e_omega = sig.omega - sig.omega_ref;
end

truth = local_make_truth(sig.theta_ground, sig.theta_ref, sig.omega_ref, t);

zone_names = fieldnames(zones);
rows = repmat(local_empty_row(), numel(zone_names) + 1, 1);
rows(1) = local_metrics_row(controller, "all", [min(t), max(t)], ...
    t >= 0.5 & t <= max(t), t, sig, truth);
for i = 1:numel(zone_names)
    z = zones.(zone_names{i});
    mask = t >= z(1) & t < z(2);
    rows(i + 1) = local_metrics_row(controller, string(zone_names{i}), z, ...
        mask, t, sig, truth);
end

run = struct();
run.controller = controller;
run.file = mat_file;
run.summary = rows(1);
run.zones = rows(:).';
run.signals = sig;
run.truth = truth;
end

function row = local_empty_row()
row = struct( ...
    'controller', "", 'zone', "", 't0', NaN, 't1', NaN, 'duration_s', NaN, ...
    'n_samples', NaN, ...
    'ey_rmse', NaN, 'ey_peak', NaN, 'ey_iae', NaN, ...
    'epsi_rmse', NaN, 'epsi_peak', NaN, ...
    'ev_rmse', NaN, 'ev_peak', NaN, ...
    'eomega_rmse', NaN, 'eomega_peak', NaN, ...
    'xy_rmse', NaN, 'xy_peak', NaN, ...
    'F_rms', NaN, 'F_peak', NaN, 'F_sat595_pct', NaN, 'F_limit_hit_pct', NaN, ...
    'omega_cmd_rms', NaN, 'omega_cmd_peak', NaN, ...
    'omega_sat060_pct', NaN, 'omega_limit_hit_pct', NaN, ...
    'viol_rate', NaN, 'j_du', NaN, 'dF_rms', NaN, 'domega_cmd_rms', NaN, ...
    'solve_time_p50_ms', NaN, 'solve_time_p95_ms', NaN, ...
    'solve_time_p99_ms', NaN, 'solve_time_max_ms', NaN, 'timeout_rate', NaN, ...
    'theta_mae_deg', NaN, 'theta_peak_deg', NaN, ...
    'theta_sched_mae_deg', NaN, 'theta_hat_step_p95_deg', NaN, ...
    'theta_sched_step_p95_deg', NaN, ...
    'main_acc_pct', NaN, 'turn_acc_pct', NaN, ...
    'flat_false_slope_pct', NaN, 'slope_recall_pct', NaN, ...
    'right_recall_pct', NaN, 'left_recall_pct', NaN, ...
    'pred_main_1_pct', NaN, 'pred_main_2_pct', NaN, 'pred_main_3_pct', NaN, ...
    'pred_turn_m1_pct', NaN, 'pred_turn_0_pct', NaN, 'pred_turn_1_pct', NaN);
end

function row = local_metrics_row(controller, zone, range, mask, t, sig, truth)
row = local_empty_row();
row.controller = string(controller);
row.zone = string(zone);
row.t0 = range(1);
row.t1 = range(2);
row.duration_s = range(2) - range(1);
row.n_samples = nnz(mask);
if nnz(mask) < 2
    return;
end

row.ey_rmse = local_rms(sig.e_y(mask));
row.ey_peak = local_peak(sig.e_y(mask));
row.ey_iae = local_iae(t(mask), sig.e_y(mask));
row.epsi_rmse = local_rms(sig.e_psi(mask));
row.epsi_peak = local_peak(sig.e_psi(mask));
row.ev_rmse = local_rms(sig.e_v(mask));
row.ev_peak = local_peak(sig.e_v(mask));
row.eomega_rmse = local_rms(sig.e_omega(mask));
row.eomega_peak = local_peak(sig.e_omega(mask));

if ~isempty(sig.X) && ~isempty(sig.X_ref) && ~isempty(sig.Y) && ~isempty(sig.Y_ref)
    xy = hypot(sig.X(mask) - sig.X_ref(mask), sig.Y(mask) - sig.Y_ref(mask));
    row.xy_rmse = local_rms(xy);
    row.xy_peak = local_peak(xy);
end

row.F_rms = local_rms(sig.F_cmd(mask));
row.F_peak = local_peak(sig.F_cmd(mask));
row.F_sat595_pct = local_pct(abs(sig.F_cmd(mask)) >= 595);
row.omega_cmd_rms = local_rms(sig.omega_cmd(mask));
row.omega_cmd_peak = local_peak(sig.omega_cmd(mask));
row.omega_sat060_pct = local_pct(abs(sig.omega_cmd(mask)) >= 0.60);

[row.F_limit_hit_pct, row.omega_limit_hit_pct, row.viol_rate] = ...
    local_limit_metrics(sig.F_cmd(mask), sig.omega_cmd(mask), ...
    sig.F_limit_hi(mask, :), sig.F_limit_lo(mask, :));

if nnz(mask) >= 3
    idx = find(mask);
    dF = diff(sig.F_cmd(idx));
    dO = diff(sig.omega_cmd(idx));
    row.j_du = local_nanmean(dF.^2 + dO.^2);
    row.dF_rms = local_rms(dF);
    row.domega_cmd_rms = local_rms(dO);
end

if ~isempty(sig.solve_time_ms)
    row.solve_time_p50_ms = local_prctile(sig.solve_time_ms(mask), 50);
    row.solve_time_p95_ms = local_prctile(sig.solve_time_ms(mask), 95);
    row.solve_time_p99_ms = local_prctile(sig.solve_time_ms(mask), 99);
    row.solve_time_max_ms = max(sig.solve_time_ms(mask), [], 'omitnan');
    row.timeout_rate = local_pct(sig.solve_time_ms(mask) > 10.0);
end

if ~isempty(sig.theta_hat) && ~isempty(truth.theta)
    theta_err = sig.theta_hat(mask) - truth.theta(mask);
    row.theta_mae_deg = rad2deg(local_nanmean(abs(theta_err)));
    row.theta_peak_deg = rad2deg(local_peak(theta_err));
    row.theta_hat_step_p95_deg = local_step_p95_deg(sig.theta_hat(mask));
end

theta_sched = local_third_channel(sig.rho_f);
if ~isempty(theta_sched) && ~isempty(truth.theta)
    theta_sched_err = theta_sched(mask) - truth.theta(mask);
    row.theta_sched_mae_deg = rad2deg(local_nanmean(abs(theta_sched_err)));
    row.theta_sched_step_p95_deg = local_step_p95_deg(theta_sched(mask));
end

if ~isempty(sig.label_main)
    pred_main = round(sig.label_main(mask));
    true_main = truth.main(mask);
    row.main_acc_pct = local_pct(pred_main == true_main);
    flat = true_main == 1;
    slope = true_main == 3;
    row.flat_false_slope_pct = local_pct(pred_main(flat) == 3);
    row.slope_recall_pct = local_pct(pred_main(slope) == 3);
    row.pred_main_1_pct = local_pct(pred_main == 1);
    row.pred_main_2_pct = local_pct(pred_main == 2);
    row.pred_main_3_pct = local_pct(pred_main == 3);
end

if ~isempty(sig.label_turn)
    pred_turn = round(sig.label_turn(mask));
    true_turn = truth.turn(mask);
    row.turn_acc_pct = local_pct(pred_turn == true_turn);
    row.right_recall_pct = local_pct(pred_turn(true_turn == -1) == -1);
    row.left_recall_pct = local_pct(pred_turn(true_turn == 1) == 1);
    row.pred_turn_m1_pct = local_pct(pred_turn == -1);
    row.pred_turn_0_pct = local_pct(pred_turn == 0);
    row.pred_turn_1_pct = local_pct(pred_turn == 1);
end
end

function zones = local_get_zones(ref)
if isfield(ref, 'meta') && isfield(ref.meta, 'zones')
    zones = ref.meta.zones;
else
    zones = struct('all', [ref.t(1), ref.t(end)]);
end
end

function truth = local_make_truth(theta_ground, theta_ref, omega_ref, t)
if ~isempty(theta_ground)
    theta = theta_ground(:);
elseif ~isempty(theta_ref)
    theta = theta_ref(:);
else
    theta = NaN(size(t));
end
truth = struct();
truth.theta = theta;
truth.main = ones(size(t));
truth.main(abs(theta) >= deg2rad(2.0)) = 3;

if isempty(omega_ref)
    truth.turn = NaN(size(t));
    return;
end
dt = median(diff(t), 'omitnan');
raw_turn = zeros(size(t));
raw_turn(omega_ref(:) > 0.05) = 1;
raw_turn(omega_ref(:) < -0.05) = -1;
truth.turn = zeros(size(t));
dwell_steps = max(1, round(0.40 / dt));
for sgn = [-1, 1]
    truth.turn(local_apply_dwell(raw_turn == sgn, dwell_steps)) = sgn;
end
end

function mask2 = local_apply_dwell(mask, dwell_steps)
mask = mask(:);
mask2 = false(size(mask));
i = 1;
while i <= numel(mask)
    if mask(i)
        j = i;
        while j <= numel(mask) && mask(j)
            j = j + 1;
        end
        if j - i >= dwell_steps
            mask2(i:j-1) = true;
        end
        i = j;
    else
        i = i + 1;
    end
end
end

function [data, time] = local_get_signal(logs, name)
data = [];
time = [];
sig = [];
for i = 1:logs.numElements
    el = logs.get(i);
    if strcmp(el.Name, name)
        sig = el;
    end
end
if isempty(sig)
    return;
end
time = sig.Values.Time(:);
data = local_time_rows(squeeze(sig.Values.Data), numel(time));
end

function data = local_resample_signal(logs, name, tout, method)
if nargin < 4 || isempty(method)
    method = 'linear';
end
[d, tin] = local_get_signal(logs, name);
if isempty(d)
    data = [];
    return;
end
if numel(tin) == numel(tout) && max(abs(tin(:) - tout(:))) < 1e-12
    data = d;
    return;
end
data = NaN(numel(tout), size(d, 2));
for c = 1:size(d, 2)
    data(:, c) = interp1(tin, d(:, c), tout, method, 'extrap');
end
end

function data = local_time_rows(data, n_time)
if isempty(data)
    return;
end
if isvector(data)
    data = data(:);
    return;
end
sz = size(data);
if sz(1) == n_time
    return;
end
if sz(2) == n_time
    data = data.';
    return;
end
data = reshape(data, n_time, []);
end

function theta = local_third_channel(x)
theta = [];
if isempty(x) || size(x, 2) < 3
    return;
end
theta = x(:, 3);
end

function [F_hit, O_hit, viol_rate] = local_limit_metrics(F, O, hi, lo)
F_hit = NaN;
O_hit = NaN;
viol_rate = NaN;
if isempty(hi) || isempty(lo) || size(hi, 2) < 2 || size(lo, 2) < 2
    return;
end
F_hi = hi(:, 1);
F_lo = lo(:, 1);
O_hi = hi(:, 2);
O_lo = lo(:, 2);
tol = 1e-8;
F_hit = local_pct(F >= 0.99 * F_hi | F <= 0.99 * F_lo);
O_hit = local_pct(O >= 0.99 * O_hi | O <= 0.99 * O_lo);
viol_rate = local_nanmean(double(F > F_hi + tol | F < F_lo - tol | ...
    O > O_hi + tol | O < O_lo - tol));
end

function y = local_rms(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = sqrt(mean(x.^2));
end
end

function y = local_peak(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = max(abs(x));
end
end

function y = local_iae(t, x)
m = isfinite(t) & isfinite(x);
if nnz(m) < 2
    y = NaN;
else
    y = trapz(t(m), abs(x(m)));
end
end

function y = local_nanmean(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = mean(x);
end
end

function y = local_prctile(x, p)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = prctile(x, p);
end
end

function y = local_pct(mask)
if isempty(mask)
    y = NaN;
else
    y = 100 * local_nanmean(double(mask(:)));
end
end

function y = local_step_p95_deg(x)
x = x(isfinite(x));
if numel(x) < 2
    y = NaN;
else
    y = rad2deg(prctile(abs(diff(x)), 95));
end
end

function local_write_report(report_file, result)
T = result.summary_table;
Z = result.zone_table;

fid = fopen(report_file, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN 与 GRU 闭环仿真对比报告\n\n');
fprintf(fid, '- ModernTCN 输出文件：`%s`\n', result.modern_file);
fprintf(fid, '- GRU 输出文件：`%s`\n', result.gru_file);
fprintf(fid, '- 展示路径文件：`%s`\n\n', result.path_file);

fprintf(fid, '## 指标说明\n\n');
fprintf(fid, '- 跟踪误差：`ey_rmse/peak`、`epsi_rmse/peak`、`ev_rmse/peak`、`eomega_rmse/peak`、`xy_rmse/peak`，数值越小越好。\n');
fprintf(fid, '- 控制性能：`F_rms/peak`、`omega_cmd_rms/peak`、`j_du`、`F_sat595_pct`、`omega_sat060_pct`、主动约束触碰率和 `viol_rate`，用于检查控制幅值、平滑性和约束安全性。\n');
fprintf(fid, '- 处理用时：输出文件中记录了 `diag_solve_time_ms`，本报告统计 p50/p95/p99/max 和 10 ms 阈值下的超时率 `timeout_rate`。\n');
fprintf(fid, '- AI/调度：`theta_mae_deg`、`theta_sched_mae_deg`、主状态准确率 `main_acc_pct`、转向准确率 `turn_acc_pct`。\n');
fprintf(fid, '- 表格列名保留脚本中的指标变量名，便于和 CSV/MAT 结果一一对应。\n\n');

fprintf(fid, '## 总体结果\n\n');
local_write_table(fid, T(:, {'controller','ey_rmse','ey_peak','epsi_rmse', ...
    'ev_rmse','eomega_rmse','xy_rmse','F_peak','omega_cmd_peak','j_du', ...
    'viol_rate','theta_mae_deg','theta_sched_mae_deg','main_acc_pct','turn_acc_pct'}));

fprintf(fid, '\n## 处理用时统计\n\n');
fprintf(fid, '处理用时信号来自 `diag_solve_time_ms`。`timeout_rate` 使用 10 ms 作为阈值。\n\n');
local_write_table(fid, T(:, {'controller','solve_time_p50_ms', ...
    'solve_time_p95_ms','solve_time_p99_ms','solve_time_max_ms', ...
    'timeout_rate'}));

fprintf(fid, '\n## 约束与饱和\n\n');
local_write_table(fid, T(:, {'controller','F_sat595_pct','F_limit_hit_pct', ...
    'omega_sat060_pct','omega_limit_hit_pct','viol_rate'}));

fprintf(fid, '\n## 分区关键指标\n\n');
local_write_table(fid, Z(:, {'controller','zone','ey_rmse','ey_peak','epsi_rmse', ...
    'ev_rmse','eomega_rmse','omega_cmd_peak','j_du','theta_mae_deg', ...
    'theta_sched_mae_deg','main_acc_pct','turn_acc_pct'}));
end

function local_write_table(fid, T)
vars = T.Properties.VariableNames;
fprintf(fid, '| %s |\n', strjoin(vars, ' | '));
fprintf(fid, '|%s|\n', strjoin(repmat({'---'}, 1, numel(vars)), '|'));
for r = 1:height(T)
    vals = cell(1, numel(vars));
    for c = 1:numel(vars)
        v = T.(vars{c})(r);
        vals{c} = local_fmt(v);
    end
    fprintf(fid, '| %s |\n', strjoin(vals, ' | '));
end
end

function s = local_fmt(v)
if isstring(v) || ischar(v)
    s = char(v);
elseif isnumeric(v) || islogical(v)
    if isnan(v)
        s = 'NaN';
    elseif abs(v) >= 1000 || (abs(v) > 0 && abs(v) < 1e-3)
        s = sprintf('%.4g', v);
    else
        s = sprintf('%.4f', v);
    end
else
    s = char(string(v));
end
end

function root = local_project_root()
this_file = mfilename('fullpath');
root = fileparts(fileparts(fileparts(this_file)));
end
