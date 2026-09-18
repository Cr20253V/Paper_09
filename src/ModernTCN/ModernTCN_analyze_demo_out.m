function result = ModernTCN_analyze_demo_out(out_file, path_file)
%MODERNTCN_ANALYZE_DEMO_OUT Analyze ModernTCN outputs on the demo loop path.

if nargin < 1 || isempty(out_file)
    out_file = fullfile(local_project_root(), 'out.mat');
end
if nargin < 2 || isempty(path_file)
    path_file = fullfile(local_project_root(), 'data', 'paths', ...
        'path_modern_tcn_demo_loop_v1.mat');
end
if exist('init_project', 'file') == 2
    init_project();
end

root = local_project_root();
S = load(out_file, 'logsout');
P = load(path_file, 'ref');
logs = S.logsout;
ref = P.ref;

t = local_time(logs, 'diag.theta_hat');
theta_hat = local_resample(logs, 'diag.theta_hat', t);
label_main = round(local_resample(logs, 'diag.label_main', t));
label_turn = round(local_resample(logs, 'diag.label_turn', t));
conf_main = local_resample(logs, 'diag.conf_main', t);
theta_ground = local_resample(logs, 'diag.theta_ground', t);
theta_ref = local_resample(logs, 'diag.theta_ref', t);
omega_ref = local_resample(logs, 'diag.omega_ref', t);
v_ref = local_resample(logs, 'diag.v_ref', t);
e_y = local_resample(logs, 'diag.e_y', t);
e_psi = local_resample(logs, 'diag.e_psi', t);
e_v = local_resample(logs, 'diag.e_v', t);

truth = local_make_truth(theta_ground, omega_ref, median(diff(t)));
zones = ref.meta.zones;
zone_names = fieldnames(zones);
rows = repmat(local_empty_row(), numel(zone_names) + 1, 1);
rows(1) = local_zone_row("all", [min(t), max(t)], true(size(t)), ...
    theta_hat, theta_ground, theta_ref, label_main, label_turn, conf_main, ...
    truth, omega_ref, v_ref, e_y, e_psi, e_v);
for i = 1:numel(zone_names)
    z = zones.(zone_names{i});
    mask = t >= z(1) & t < z(2);
    rows(i + 1) = local_zone_row(string(zone_names{i}), z, mask, ...
        theta_hat, theta_ground, theta_ref, label_main, label_turn, conf_main, ...
        truth, omega_ref, v_ref, e_y, e_psi, e_v);
end
zone_table = struct2table(rows);

cm_main = confusionmat(truth.main, label_main, 'Order', [1 2 3]);
cm_turn = confusionmat(truth.turn, label_turn, 'Order', [-1 0 1]);
simulink_replay = local_compare_with_latest_replay(root, out_file, theta_hat, ...
    label_main, label_turn, conf_main, t);

out_dir = fullfile(root, 'results', 'modern_tcn', 'demo_loop_diag');
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
[~, base_name, ~] = fileparts(out_file);
mat_file = fullfile(out_dir, [base_name '_modern_tcn_demo_loop_diag.mat']);
report_file = fullfile(out_dir, [base_name '_modern_tcn_demo_loop_diag_report.md']);

result = struct();
result.out_file = out_file;
result.path_file = path_file;
result.zone_table = zone_table;
result.cm_main_order = [1 2 3];
result.cm_main = cm_main;
result.cm_turn_order = [-1 0 1];
result.cm_turn = cm_turn;
result.simulink_replay = simulink_replay;
result.t = t;
result.truth = truth;
result.theta_hat = theta_hat;
result.theta_ground = theta_ground;
result.theta_ref = theta_ref;
result.label_main = label_main;
result.label_turn = label_turn;
result.conf_main = conf_main;
result.report_file = report_file;
result.mat_file = mat_file;

save(mat_file, 'result');
local_write_report(report_file, result);

fprintf('[ModernTCN demo-loop diag] report: %s\n', report_file);
disp(zone_table(:, {'zone','main_acc_pct','turn_acc_pct','theta_mae_all_deg', ...
    'theta_mae_slope_deg','flat_false_slope_pct','slope_recall_pct', ...
    'right_recall_pct','left_recall_pct','conf_p10'}));
end

function row = local_empty_row()
row = struct('zone', "", 't0', NaN, 't1', NaN, 'duration_s', NaN, ...
    'main_acc_pct', NaN, 'flat_recall_pct', NaN, 'slope_recall_pct', NaN, ...
    'flat_false_slope_pct', NaN, 'stall_pred_pct', NaN, ...
    'turn_acc_pct', NaN, 'right_recall_pct', NaN, 'straight_recall_pct', NaN, ...
    'left_recall_pct', NaN, 'theta_mae_all_deg', NaN, ...
    'theta_mae_slope_deg', NaN, 'theta_mae_flat_deg', NaN, ...
    'theta_flat_abs_p95_deg', NaN, 'theta_bias_all_deg', NaN, ...
    'pred_main_1_pct', NaN, 'pred_main_2_pct', NaN, 'pred_main_3_pct', NaN, ...
    'true_main_1_pct', NaN, 'true_main_3_pct', NaN, ...
    'pred_turn_m1_pct', NaN, 'pred_turn_0_pct', NaN, 'pred_turn_1_pct', NaN, ...
    'true_turn_m1_pct', NaN, 'true_turn_0_pct', NaN, 'true_turn_1_pct', NaN, ...
    'conf_median', NaN, 'conf_p10', NaN, 'v_ref_min', NaN, 'v_ref_max', NaN, ...
    'omega_ref_min', NaN, 'omega_ref_max', NaN, 'theta_ref_min_deg', NaN, ...
    'theta_ref_max_deg', NaN, 'ey_rmse', NaN, 'epsi_rmse', NaN, 'ev_rmse', NaN);
end

function row = local_zone_row(name, z, mask, theta_hat, theta_ground, theta_ref, ...
    label_main, label_turn, conf_main, truth, omega_ref, v_ref, e_y, e_psi, e_v)
row = local_empty_row();
row.zone = string(name);
row.t0 = z(1);
row.t1 = z(2);
row.duration_s = z(2) - z(1);
if nnz(mask) < 2
    return;
end

lm = label_main(mask);
lt = label_turn(mask);
tm = truth.main(mask);
tt = truth.turn(mask);
th = theta_hat(mask);
tg = theta_ground(mask);
tr = theta_ref(mask);
flat = tm == 1;
slope = tm == 3;
right = tt == -1;
straight = tt == 0;
left = tt == 1;

row.main_acc_pct = 100 * mean(lm == tm, 'omitnan');
row.flat_recall_pct = local_recall(lm, tm, 1);
row.slope_recall_pct = local_recall(lm, tm, 3);
row.flat_false_slope_pct = 100 * mean(lm(flat) == 3, 'omitnan');
row.stall_pred_pct = 100 * mean(lm == 2, 'omitnan');
row.turn_acc_pct = 100 * mean(lt == tt, 'omitnan');
row.right_recall_pct = local_recall(lt, tt, -1);
row.straight_recall_pct = local_recall(lt, tt, 0);
row.left_recall_pct = local_recall(lt, tt, 1);
row.theta_mae_all_deg = rad2deg(mean(abs(th - tg), 'omitnan'));
row.theta_mae_slope_deg = local_mae_deg(th(slope), tg(slope));
row.theta_mae_flat_deg = local_mae_deg(th(flat), tg(flat));
row.theta_flat_abs_p95_deg = local_p95_deg(abs(th(flat) - tg(flat)));
row.theta_bias_all_deg = rad2deg(mean(th - tg, 'omitnan'));
row.pred_main_1_pct = 100 * mean(lm == 1, 'omitnan');
row.pred_main_2_pct = 100 * mean(lm == 2, 'omitnan');
row.pred_main_3_pct = 100 * mean(lm == 3, 'omitnan');
row.true_main_1_pct = 100 * mean(tm == 1, 'omitnan');
row.true_main_3_pct = 100 * mean(tm == 3, 'omitnan');
row.pred_turn_m1_pct = 100 * mean(lt == -1, 'omitnan');
row.pred_turn_0_pct = 100 * mean(lt == 0, 'omitnan');
row.pred_turn_1_pct = 100 * mean(lt == 1, 'omitnan');
row.true_turn_m1_pct = 100 * mean(tt == -1, 'omitnan');
row.true_turn_0_pct = 100 * mean(tt == 0, 'omitnan');
row.true_turn_1_pct = 100 * mean(tt == 1, 'omitnan');
row.conf_median = median(conf_main(mask), 'omitnan');
row.conf_p10 = prctile(conf_main(mask), 10);
row.v_ref_min = min(v_ref(mask));
row.v_ref_max = max(v_ref(mask));
row.omega_ref_min = min(omega_ref(mask));
row.omega_ref_max = max(omega_ref(mask));
row.theta_ref_min_deg = min(rad2deg(tr));
row.theta_ref_max_deg = max(rad2deg(tr));
row.ey_rmse = local_rms(e_y(mask));
row.epsi_rmse = local_rms(e_psi(mask));
row.ev_rmse = local_rms(e_v(mask));

if ~any(flat)
    row.flat_false_slope_pct = NaN;
    row.theta_mae_flat_deg = NaN;
    row.theta_flat_abs_p95_deg = NaN;
end
end

function truth = local_make_truth(theta_ground, omega_ref, dt)
truth = struct();
truth.main = ones(size(theta_ground));
truth.main(abs(theta_ground) >= deg2rad(2.0)) = 3;

raw_turn = zeros(size(omega_ref));
raw_turn(omega_ref > 0.05) = 1;
raw_turn(omega_ref < -0.05) = -1;
truth.turn = zeros(size(omega_ref));
dwell_steps = max(1, round(0.40 / dt));
for sgn = [-1, 1]
    truth.turn(local_apply_dwell(raw_turn == sgn, dwell_steps)) = sgn;
end
truth.raw_turn = raw_turn;
truth.main_threshold_deg = 2.0;
truth.turn_threshold = 0.05;
truth.turn_dwell_sec = 0.40;
end

function m2 = local_apply_dwell(m, dwell_steps)
N = numel(m);
m2 = false(N, 1);
i = 1;
while i <= N
    if m(i)
        j = i;
        while j <= N && m(j)
            j = j + 1;
        end
        if (j - i) >= dwell_steps
            m2(i:j-1) = true;
        end
        i = j;
    else
        i = i + 1;
    end
end
end

function r = local_recall(pred, truth, cls)
m = truth == cls;
if ~any(m)
    r = NaN;
else
    r = 100 * mean(pred(m) == cls, 'omitnan');
end
end

function e = local_mae_deg(a, b)
if isempty(a)
    e = NaN;
else
    e = rad2deg(mean(abs(a - b), 'omitnan'));
end
end

function p = local_p95_deg(x)
if isempty(x)
    p = NaN;
else
    p = rad2deg(prctile(x, 95));
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

function cmp = local_compare_with_latest_replay(root, out_file, theta_hat, label_main, label_turn, conf_main, t)
cmp = struct('available', false, 'theta_hat_max_abs_diff', NaN, ...
    'label_main_diff_count', NaN, 'label_turn_diff_count', NaN, ...
    'conf_main_max_abs_diff', NaN, 'replay_file', "");
[~, base_name, ~] = fileparts(out_file);
files = dir(fullfile(root, 'results', 'modern_tcn', 'closed_loop_replay', ...
    [base_name '_modern_tcn_replay_*.mat']));
if isempty(files)
    return;
end
[~, idx] = max([files.datenum]);
replay_file = fullfile(files(idx).folder, files(idx).name);
try
    R = load(replay_file, 'result');
    rr = R.result;
    if numel(rr.t) ~= numel(t) || max(abs(rr.t(:) - t(:))) > 1e-9
        return;
    end
    cmp.available = true;
    cmp.replay_file = string(replay_file);
    cmp.theta_hat_max_abs_diff = max(abs(theta_hat(:) - rr.theta_hat(:)), [], 'omitnan');
    cmp.label_main_diff_count = nnz(label_main(:) ~= rr.label_main(:));
    cmp.label_turn_diff_count = nnz(label_turn(:) ~= rr.label_turn(:));
    cmp.conf_main_max_abs_diff = max(abs(conf_main(:) - rr.conf_main(:)), [], 'omitnan');
catch
end
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
T = result.zone_table;

fprintf(fid, '# ModernTCN Demo Loop Output Diagnostic\n\n');
fprintf(fid, '- out file: `%s`\n', result.out_file);
fprintf(fid, '- path file: `%s`\n', result.path_file);
fprintf(fid, '- main truth: flat if `|theta_ground| < 2 deg`, slope otherwise; no disturbance injection means no true stall.\n');
fprintf(fid, '- turn truth: `|omega_ref| > 0.05 rad/s` with `0.40 s` dwell, matching training label generation.\n\n');

fprintf(fid, '## Summary\n\n');
all_row = T(T.zone == "all", :);
fprintf(fid, '- overall main accuracy: `%.2f%%`\n', all_row.main_acc_pct);
fprintf(fid, '- overall turn accuracy: `%.2f%%`\n', all_row.turn_acc_pct);
fprintf(fid, '- theta MAE all/slope/flat: `%.3f / %.3f / %.3f deg`\n', ...
    all_row.theta_mae_all_deg, all_row.theta_mae_slope_deg, all_row.theta_mae_flat_deg);
fprintf(fid, '- flat false-slope rate: `%.2f%%`\n', all_row.flat_false_slope_pct);
fprintf(fid, '- slope recall: `%.2f%%`\n', all_row.slope_recall_pct);
fprintf(fid, '- right/left recall: `%.2f%% / %.2f%%`\n\n', ...
    all_row.right_recall_pct, all_row.left_recall_pct);

if result.simulink_replay.available
    fprintf(fid, '## Simulink vs Replay\n\n');
    fprintf(fid, '- replay file: `%s`\n', result.simulink_replay.replay_file);
    fprintf(fid, '- max abs theta diff: `%.3g rad`\n', result.simulink_replay.theta_hat_max_abs_diff);
    fprintf(fid, '- label main diff count: `%d`\n', result.simulink_replay.label_main_diff_count);
    fprintf(fid, '- label turn diff count: `%d`\n', result.simulink_replay.label_turn_diff_count);
    fprintf(fid, '- max abs conf diff: `%.3g`\n\n', result.simulink_replay.conf_main_max_abs_diff);
end

fprintf(fid, '## Zone Metrics\n\n');
fprintf(fid, '| zone | main acc | turn acc | theta all | theta slope | flat false slope | slope recall | right recall | left recall | pred main 1/2/3 | pred turn -1/0/1 | conf p10 |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(T)
    fprintf(fid, '| %s | %.1f | %.1f | %.3f | %.3f | %.1f | %.1f | %.1f | %.1f | %.1f/%.1f/%.1f | %.1f/%.1f/%.1f | %.3f |\n', ...
        T.zone(i), T.main_acc_pct(i), T.turn_acc_pct(i), ...
        T.theta_mae_all_deg(i), T.theta_mae_slope_deg(i), ...
        T.flat_false_slope_pct(i), T.slope_recall_pct(i), ...
        T.right_recall_pct(i), T.left_recall_pct(i), ...
        T.pred_main_1_pct(i), T.pred_main_2_pct(i), T.pred_main_3_pct(i), ...
        T.pred_turn_m1_pct(i), T.pred_turn_0_pct(i), T.pred_turn_1_pct(i), ...
        T.conf_p10(i));
end

fprintf(fid, '\n## Confusion Matrices\n\n');
fprintf(fid, 'Main order `[1 flat, 2 stall, 3 slope]`:\n\n');
fprintf(fid, '```text\n');
fprintf(fid, '%8d %8d %8d\n', result.cm_main.');
fprintf(fid, '```\n\n');
fprintf(fid, 'Turn order `[-1 right, 0 straight, 1 left]`:\n\n');
fprintf(fid, '```text\n');
fprintf(fid, '%8d %8d %8d\n', result.cm_turn.');
fprintf(fid, '```\n');
end

function data = local_resample(logs, name, t)
ts = local_timeseries(logs, name);
data = squeeze(double(ts.Data));
tt = double(ts.Time(:));
if isvector(data)
    data = data(:);
else
    data = reshape(data, [], numel(tt)).';
end
if numel(tt) == numel(t) && max(abs(tt - t)) < 1e-12
    return;
end
data = interp1(tt, data, t, 'linear', 'extrap');
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
ts = logs.getElement(hit(end)).Values;
end

function root = local_project_root()
if exist('project_root', 'file') == 2
    root = project_root();
else
    root = pwd;
end
end

