function result = ModernTCN_State_Classifier_standalone_test(seed, run_id, max_steps, cfg)
%MODERNTCN_STATE_CLASSIFIER_STANDALONE_TEST 离线检查 Simulink wrapper 入口。
%
% 功能说明：
%   本测试不打开、不修改 Simulink 模型。它直接读取当前推荐训练数据中的某个
%   raw run，把每一帧 34 维 y_raw 按仿真步送入
%   ModernTCN_State_Classifier_sim，检查在线滑窗、归一化、ONNX 推理和标签
%   输出是否能正常工作。
%
% 用法：
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'ModernTCN'));
%   result = ModernTCN_State_Classifier_standalone_test();

if nargin < 2 || isempty(run_id)
    run_id = 1;
end
if nargin < 3 || isempty(max_steps)
    max_steps = 360;
end
if nargin < 4 || isempty(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
default_cfg = ModernTCN_default_config(root);
if nargin < 1 || isempty(seed)
    seed = default_cfg.seed;
end
params = parameters();
assignin('base', 'params', params);

sim_cfg = default_cfg;
sim_cfg = local_merge_struct_fields(sim_cfg, cfg);
sim_cfg.seed = seed;
if seed ~= default_cfg.seed && (~isfield(sim_cfg, 'onnx_file') || isempty(sim_cfg.onnx_file))
    sim_cfg.onnx_file = fullfile(root, 'results', 'modern_tcn', default_cfg.run_tag, ...
        sprintf('modern_tcn_seed%d.onnx', seed));
end
had_cfg = evalin('base', 'exist(''modern_tcn_sim_cfg'', ''var'')==1');
if had_cfg
    old_cfg = evalin('base', 'modern_tcn_sim_cfg');
else
    old_cfg = [];
end
assignin('base', 'modern_tcn_sim_cfg', sim_cfg);
cleanup_cfg = onCleanup(@() local_restore_sim_cfg(had_cfg, old_cfg)); %#ok<NASGU>

data_file = default_cfg.raw_train_file;
if exist(data_file, 'file') ~= 2
    error('ModernTCN:MissingTrainData', '找不到训练原始数据: %s', data_file);
end
D = load(data_file, 'data');
if run_id < 1 || run_id > numel(D.data.runs)
    error('ModernTCN:BadRunID', 'run_id=%d 超出范围 1..%d。', run_id, numel(D.data.runs));
end

run = D.data.runs(run_id);
y_raw = double(run.y_raw);
n = min(max_steps, size(y_raw, 1));

% reset=1 的第一次调用只初始化 persistent state，和 Simulink 接法一致。
ModernTCN_State_Classifier_sim(y_raw(1,:).', 1);

rows = repmat(local_empty_row(), n, 1);
fprintf('[ModernTCN standalone] seed=%d run=%d steps=%d\n', seed, run_id, n);
for k = 1:n
    [theta_hat, label_main, label_turn, conf_main] = ...
        ModernTCN_State_Classifier_sim(y_raw(k,:).', 0);
    debug = local_read_debug();
    rows(k) = local_make_row(k, params.Ts, theta_hat, label_main, label_turn, conf_main, run, debug);
end

T = struct2table(rows);
valid_labels = all(ismember(T.label_main, [1; 2; 3])) && all(ismember(T.label_turn, [-1; 0; 1]));
finite_outputs = all(isfinite(T.theta_hat_rad)) && all(isfinite(T.conf_main));
finite_theta_for_mpc = all(isfinite(T.theta_hat_for_mpc_rad));
mpc_matches_wrapper = all(abs(T.theta_hat_for_mpc_rad - T.theta_hat_rad) < 1e-12 | ...
    (~isfinite(T.theta_hat_for_mpc_rad) & ~isfinite(T.theta_hat_rad)));
deadzone_mask = isfinite(T.theta_diag_rad) & ...
    abs(T.theta_diag_rad) <= (T.theta_mpc_deadzone_rad + 1e-12);
deadzone_checked = any(deadzone_mask);
theta_mpc_target = local_theta_mpc_target(T.theta_diag_rad, ...
    T.theta_mpc_deadzone_rad, T.theta_mpc_deadzone_soft_rad);
mpc_rate_limit_applied = local_check_rate_limit(T.theta_hat_for_mpc_rad, ...
    T.theta_mpc_rate_limit_rad_s, params.Ts);
deadzone_applied = local_check_moves_toward_target(T.theta_hat_for_mpc_rad, ...
    theta_mpc_target, deadzone_mask);
soft_mask = isfinite(T.theta_diag_rad) & isfinite(T.theta_mpc_deadzone_soft_rad) & ...
    abs(T.theta_diag_rad) > T.theta_mpc_deadzone_rad & ...
    abs(T.theta_diag_rad) < T.theta_mpc_deadzone_soft_rad;
soft_deadzone_checked = any(soft_mask);
soft_deadzone_applied = local_check_moves_toward_target(T.theta_hat_for_mpc_rad, ...
    theta_mpc_target, soft_mask);
warmup_steps = 128 + round(1.0 / params.Ts);
has_post_warmup = n > warmup_steps;
has_inference = any(T.did_predict ~= 0);
post_warmup_changed = false;
if has_post_warmup
    tail = T((warmup_steps + 1):end, :);
    post_warmup_changed = any(tail.label_main ~= 1) || any(tail.label_turn ~= 0) || any(abs(tail.theta_hat_rad) > 0);
end

out_dir = fullfile(root, 'results', 'modern_tcn', 'simulink_wrapper');
if isfield(sim_cfg, 'output_dir') && ~isempty(sim_cfg.output_dir)
    out_dir = char(sim_cfg.output_dir);
end
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
csv_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_run%d_state_classifier_standalone.csv', seed, run_id));
report_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_run%d_state_classifier_standalone_report.md', seed, run_id));
mat_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_run%d_state_classifier_standalone.mat', seed, run_id));
writetable(T, csv_file);

result = struct();
result.seed = seed;
result.run_id = run_id;
result.steps = n;
result.pass = valid_labels && finite_outputs && has_post_warmup;
result.pass = result.pass && has_inference;
result.pass = result.pass && finite_theta_for_mpc && mpc_matches_wrapper && ...
    deadzone_applied && soft_deadzone_applied && mpc_rate_limit_applied;
result.valid_labels = valid_labels;
result.finite_outputs = finite_outputs;
result.finite_theta_for_mpc = finite_theta_for_mpc;
result.mpc_matches_wrapper = mpc_matches_wrapper;
result.deadzone_checked = deadzone_checked;
result.deadzone_applied = deadzone_applied;
result.soft_deadzone_checked = soft_deadzone_checked;
result.soft_deadzone_applied = soft_deadzone_applied;
result.mpc_rate_limit_applied = mpc_rate_limit_applied;
result.has_post_warmup = has_post_warmup;
result.has_inference = has_inference;
result.post_warmup_changed = post_warmup_changed;
result.warmup_steps = warmup_steps;
result.csv_file = csv_file;
result.report_file = report_file;
result.mat_file = mat_file;
result.table = T;

save(mat_file, 'result');
local_write_report(report_file, result, data_file, run);

fprintf('[ModernTCN standalone] pass=%d | valid_labels=%d finite=%d mpc_finite=%d deadzone=%d soft=%d rate=%d post_warmup=%d\n', ...
    result.pass, result.valid_labels, result.finite_outputs, result.finite_theta_for_mpc, ...
    result.deadzone_applied, result.soft_deadzone_applied, result.mpc_rate_limit_applied, ...
    result.has_post_warmup);
fprintf('  inference observed: %d\n', result.has_inference);
fprintf('  csv   : %s\n', csv_file);
fprintf('  report: %s\n', report_file);
end

function row = local_empty_row()
row = struct('step', NaN, 'time_s', NaN, 'theta_hat_rad', NaN, ...
    'theta_hat_deg', NaN, 'theta_hat_for_mpc_rad', NaN, ...
    'theta_hat_for_mpc_deg', NaN, 'theta_diag_rad', NaN, ...
    'theta_diag_deg', NaN, 'theta_hat_raw_rad', NaN, ...
    'theta_hat_raw_deg', NaN, 'theta_mpc_deadzone_rad', NaN, ...
    'theta_mpc_deadzone_deg', NaN, 'theta_mpc_deadzone_soft_rad', NaN, ...
    'theta_mpc_deadzone_soft_deg', NaN, 'theta_mpc_rate_limit_rad_s', NaN, ...
    'theta_mpc_rate_limit_deg_s', NaN, 'label_main', NaN, 'label_turn', NaN, ...
    'conf_main', NaN, 'did_predict', NaN, 'ready', NaN, 'buffer_count', NaN, ...
    'truth_main', NaN, 'truth_turn', NaN, 'theta_truth_rad', NaN);
end

function row = local_make_row(k, Ts, theta_hat, label_main, label_turn, conf_main, run, debug)
row = local_empty_row();
row.step = k;
row.time_s = (k - 1) * Ts;
row.theta_hat_rad = theta_hat;
row.theta_hat_deg = rad2deg(theta_hat);
row.theta_hat_for_mpc_rad = debug.theta_hat_for_mpc;
row.theta_hat_for_mpc_deg = rad2deg(debug.theta_hat_for_mpc);
row.theta_diag_rad = debug.theta_hat;
row.theta_diag_deg = rad2deg(debug.theta_hat);
row.theta_hat_raw_rad = debug.theta_hat_raw;
row.theta_hat_raw_deg = rad2deg(debug.theta_hat_raw);
row.theta_mpc_deadzone_rad = debug.theta_mpc_deadzone;
row.theta_mpc_deadzone_deg = rad2deg(debug.theta_mpc_deadzone);
row.theta_mpc_deadzone_soft_rad = debug.theta_mpc_deadzone_soft;
row.theta_mpc_deadzone_soft_deg = rad2deg(debug.theta_mpc_deadzone_soft);
row.theta_mpc_rate_limit_rad_s = debug.theta_mpc_rate_limit;
row.theta_mpc_rate_limit_deg_s = rad2deg(debug.theta_mpc_rate_limit);
row.label_main = label_main;
row.label_turn = label_turn;
row.conf_main = conf_main;
row.did_predict = double(debug.did_predict);
row.ready = double(debug.ready);
row.buffer_count = double(debug.buffer_count);
if isfield(run, 'label_main') && numel(run.label_main) >= k
    row.truth_main = double(run.label_main(k));
end
if isfield(run, 'label_turn') && numel(run.label_turn) >= k
    row.truth_turn = double(run.label_turn(k));
end
if isfield(run, 'y_theta_ground') && numel(run.y_theta_ground) >= k
    row.theta_truth_rad = double(run.y_theta_ground(k));
elseif isfield(run, 'theta') && numel(run.theta) >= k
    row.theta_truth_rad = double(run.theta(k));
elseif isfield(run, 'y_raw') && size(run.y_raw, 2) >= 16
    row.theta_truth_rad = double(run.y_raw(k, 16));
end
end

function debug = local_read_debug()
debug = struct('did_predict', false, 'ready', false, 'buffer_count', 0, ...
    'theta_hat', NaN, 'theta_hat_for_mpc', NaN, 'theta_hat_raw', NaN, ...
    'theta_mpc_deadzone', NaN, 'theta_mpc_deadzone_soft', NaN, ...
    'theta_mpc_rate_limit', NaN);
try
    if evalin('base', 'exist(''modern_tcn_out_temp'', ''var'') == 1')
        out = evalin('base', 'modern_tcn_out_temp');
        if isstruct(out)
            if isfield(out, 'theta_hat')
                debug.theta_hat = double(out.theta_hat);
            end
            if isfield(out, 'theta_hat_for_mpc')
                debug.theta_hat_for_mpc = double(out.theta_hat_for_mpc);
            end
            if isfield(out, 'theta_hat_raw')
                debug.theta_hat_raw = double(out.theta_hat_raw);
            end
        end
        if isstruct(out) && isfield(out, 'debug') && isstruct(out.debug)
            d = out.debug;
            if isfield(d, 'did_predict')
                debug.did_predict = logical(d.did_predict);
            end
            if isfield(d, 'ready')
                debug.ready = logical(d.ready);
            end
            if isfield(d, 'buffer_count')
                debug.buffer_count = double(d.buffer_count);
            end
            if isfield(d, 'theta_mpc_deadzone')
                debug.theta_mpc_deadzone = double(d.theta_mpc_deadzone);
            end
            if isfield(d, 'theta_mpc_deadzone_soft')
                debug.theta_mpc_deadzone_soft = double(d.theta_mpc_deadzone_soft);
            end
            if isfield(d, 'theta_mpc_rate_limit')
                debug.theta_mpc_rate_limit = double(d.theta_mpc_rate_limit);
            end
        end
    end
catch
end
end

function local_restore_sim_cfg(had_cfg, old_cfg)
if had_cfg
    assignin('base', 'modern_tcn_sim_cfg', old_cfg);
else
    evalin('base', 'clear modern_tcn_sim_cfg');
end
end

function out = local_merge_struct_fields(out, extra)
if ~isstruct(extra)
    return;
end
names = fieldnames(extra);
for i = 1:numel(names)
    out.(names{i}) = extra.(names{i});
end
end

function local_write_report(report_file, result, data_file, run)
fid = fopen(report_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', '无法写入报告: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN State Classifier Standalone Test\n\n');
fprintf(fid, '- seed: `%d`\n', result.seed);
fprintf(fid, '- run_id: `%d`\n', result.run_id);
fprintf(fid, '- scene: `%s`\n', local_run_field(run, 'scene', 'unknown'));
fprintf(fid, '- data: `%s`\n', data_file);
fprintf(fid, '- steps: `%d`\n', result.steps);
fprintf(fid, '- warmup_steps: `%d`\n', result.warmup_steps);
fprintf(fid, '- pass: `%d`\n\n', result.pass);

fprintf(fid, '| check | pass |\n');
fprintf(fid, '|---|---:|\n');
fprintf(fid, '| labels in valid ranges | %d |\n', result.valid_labels);
fprintf(fid, '| finite outputs | %d |\n', result.finite_outputs);
fprintf(fid, '| finite theta for MPC | %d |\n', result.finite_theta_for_mpc);
fprintf(fid, '| wrapper returns theta_hat_for_mpc | %d |\n', result.mpc_matches_wrapper);
fprintf(fid, '| deadzone samples observed | %d |\n', result.deadzone_checked);
fprintf(fid, '| deadzone applied to MPC theta | %d |\n', result.deadzone_applied);
fprintf(fid, '| soft deadzone samples observed | %d |\n', result.soft_deadzone_checked);
fprintf(fid, '| soft deadzone attenuates MPC theta | %d |\n', result.soft_deadzone_applied);
fprintf(fid, '| MPC theta rate limit respected | %d |\n', result.mpc_rate_limit_applied);
fprintf(fid, '| has post-warmup samples | %d |\n', result.has_post_warmup);
fprintf(fid, '| ONNX inference observed | %d |\n', result.has_inference);
fprintf(fid, '| post-warmup output changed from default | %d |\n\n', result.post_warmup_changed);

last = result.table(max(1, height(result.table)-9):height(result.table), :);
fprintf(fid, '## Last Samples\n\n');
fprintf(fid, '| step | t | main | turn | conf | theta MPC deg | theta diag deg | theta raw deg | predict | buffer | truth main | truth turn |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(last)
    fprintf(fid, '| %d | %.2f | %d | %d | %.4f | %.4f | %.4f | %.4f | %d | %d | %d | %d |\n', ...
        last.step(i), last.time_s(i), last.label_main(i), last.label_turn(i), ...
        last.conf_main(i), last.theta_hat_for_mpc_deg(i), last.theta_diag_deg(i), ...
        last.theta_hat_raw_deg(i), last.did_predict(i), last.buffer_count(i), ...
        last.truth_main(i), last.truth_turn(i));
end
end

function v = local_run_field(s, field_name, default_value)
if isfield(s, field_name)
    v = s.(field_name);
else
    v = default_value;
end
end

function theta_target = local_theta_mpc_target(theta_diag, deadzone, soft_deadzone)
theta_target = theta_diag;
for i = 1:numel(theta_diag)
    th = theta_diag(i);
    dz = deadzone(i);
    sdz = soft_deadzone(i);
    if ~isfinite(th) || ~isfinite(dz)
        theta_target(i) = NaN;
        continue;
    end
    if ~isfinite(sdz) || sdz < dz
        sdz = dz;
    end
    a = abs(th);
    if a <= dz
        theta_target(i) = 0;
    elseif sdz > dz && a < sdz
        scale = (a - dz) / max(sdz - dz, eps);
        theta_target(i) = sign(th) * scale * (a - dz);
    else
        theta_target(i) = th;
    end
end
end

function ok = local_check_moves_toward_target(y, target, mask)
idx = find(mask(:) & isfinite(y(:)) & isfinite(target(:)));
if isempty(idx)
    ok = true;
    return;
end
ok = all(abs(y(idx)) <= abs(target(idx)) + max(deg2rad(2.0), 1e-12) | ...
    sign(y(idx)) == sign(target(idx)) | abs(y(idx)) < 1e-12);
end

function ok = local_check_rate_limit(y, limit, Ts)
dy = abs(diff(y(:)));
lim = limit(2:end);
mask = isfinite(dy) & isfinite(lim) & lim > 0;
if ~any(mask)
    ok = true;
    return;
end
ok = all(dy(mask) <= lim(mask) * Ts + 1e-10);
end
