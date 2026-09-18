function result = ModernTCN_online_smoke_test(seed, test_rows)
%MODERNTCN_ONLINE_SMOKE_TEST 验证 y_raw 在线封装能复现固定测试窗口。
%
% 功能说明：
%   该脚本不依赖 Simulink 模型修改。它从当前推荐训练数据
%   读取原始 y_raw，按数据集保存的 split 规则重建 test
%   窗口起点，然后逐帧调用 ModernTCN_online_step。到达指定测试窗口末端时，
%   检查在线滑窗归一化结果是否与 dataset.X_test 完全对齐，并检查 ONNX 输出
%   是否与第二步 MATLAB full-test 保存的输出一致。
%
% 用法：
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'ModernTCN'));
%   result = ModernTCN_online_smoke_test();

if nargin < 2 || isempty(test_rows)
    test_rows = [1 2 3 16 128 512 1024 2048 2849];
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
default_cfg = ModernTCN_default_config(root);
if nargin < 1 || isempty(seed)
    seed = default_cfg.seed;
end
dataset_file = default_cfg.dataset_file;
raw_file = default_cfg.raw_train_file;
reference_file = fullfile(default_cfg.reference_dir, ...
    sprintf('modern_tcn_seed%d_matlab_full_testset_outputs.mat', seed));

S = load(dataset_file, 'dataset');
R = load(raw_file, 'data');
P = load(reference_file, 'pred');
dataset = S.dataset;
raw_data = R.data;

test_rows = unique(test_rows(:).');
test_rows = test_rows(test_rows >= 1 & test_rows <= size(dataset.X_test, 1));
if isempty(test_rows)
    error('ModernTCN:EmptyRows', '没有可检查的 test row。');
end

% 测试时强制每个被请求的窗口都推理，非目标步只更新滑窗，不调用 ONNX。
modern_tcn_sim_cfg = struct('infer_period_steps', 1); %#ok<NASGU>
assignin('base', 'modern_tcn_sim_cfg', modern_tcn_sim_cfg);

map = local_build_test_window_map(dataset, raw_data);
rows = repmat(local_empty_row(), numel(test_rows), 1);
row_written = false(size(test_rows));

fprintf('[ModernTCN online smoke] seed=%d | rows=%d\n', seed, numel(test_rows));
for r = unique(map.run_id(ismember(map.test_row, test_rows))).'
    idx_this_run = find(map.run_id == r & ismember(map.test_row, test_rows));
    max_end_rel = max(map.end_rel(idx_this_run));
    selected_end_rel = map.end_rel(idx_this_run);
    selected_rows = map.test_row(idx_this_run);

    ModernTCN_online_step([], 1, seed, false);
    run = raw_data.runs(r);
    skip_steps = round(dataset.meta.skip_initial_sec / dataset.meta.Ts);

    for t_rel = 1:max_end_rel
        raw_idx = skip_steps + t_rel;
        do_predict = any(selected_end_rel == t_rel);
        out = ModernTCN_online_step(run.y_raw(raw_idx, :).', 0, seed, do_predict);
        if do_predict
            hit = find(selected_end_rel == t_rel);
            for h = 1:numel(hit)
                test_row = selected_rows(hit(h));
                pos = find(test_rows == test_row, 1);
                rows(pos) = local_compare_one(test_row, r, t_rel, out, dataset, P.pred);
                row_written(pos) = true;
                fprintf('  row=%4d run=%3d end=%4d | x_err=%.3g main_err=%.3g turn_err=%.3g theta_err=%.3g\n', ...
                    test_row, r, t_rel, rows(pos).x_window_max_abs_error, ...
                    rows(pos).main_logits_max_abs_error, rows(pos).turn_logits_max_abs_error, ...
                    rows(pos).theta_abs_error);
            end
        end
    end
end

if ~all(row_written)
    missing = test_rows(~row_written);
    error('ModernTCN:MissingRows', '以下 test row 未被检查到: %s', mat2str(missing));
end

T = struct2table(rows);
tol_x = 1e-5;
tol_y = 1e-4;
pass = all(T.x_window_max_abs_error <= tol_x) ...
    && all(T.main_logits_max_abs_error <= tol_y) ...
    && all(T.turn_logits_max_abs_error <= tol_y) ...
    && all(T.theta_abs_error <= tol_y);

out_dir = fullfile(root, 'results', 'modern_tcn', 'online_smoke');
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
csv_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_online_smoke.csv', seed));
mat_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_online_smoke.mat', seed));
report_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_online_smoke_report.md', seed));
writetable(T, csv_file);

result = struct();
result.seed = seed;
result.pass = pass;
result.table = T;
result.tol_x = tol_x;
result.tol_y = tol_y;
result.csv_file = csv_file;
result.mat_file = mat_file;
result.report_file = report_file;
save(mat_file, 'result');
local_write_report(report_file, result);

fprintf('[ModernTCN online smoke] pass=%d | max_x=%.3g max_main=%.3g max_turn=%.3g max_theta=%.3g\n', ...
    result.pass, max(T.x_window_max_abs_error), max(T.main_logits_max_abs_error), ...
    max(T.turn_logits_max_abs_error), max(T.theta_abs_error));
fprintf('  csv   : %s\n', csv_file);
fprintf('  report: %s\n', report_file);
end

function map = local_build_test_window_map(dataset, raw_data)
cfg = local_cfg_from_dataset(dataset);
runs_test = dataset.split_info.runs_test(:).';
runs_train = dataset.split_info.runs_train(:).';
runs_val = dataset.split_info.runs_val(:).';
all_rows = repmat(struct('all_row', NaN, 'run_id', NaN, 'start_rel', NaN, 'end_rel', NaN), ...
    100000, 1);
all_row = 0;
for r = 1:numel(raw_data.runs)
    run = raw_data.runs(r);
    labels = local_labels_for_run(run, cfg);
    starts = local_window_starts(labels, numel(labels.y_main), cfg);
    for i = 1:numel(starts)
        all_row = all_row + 1;
        if all_row > numel(all_rows)
            all_rows(end + 100000).all_row = NaN; %#ok<AGROW>
        end
        all_rows(all_row).all_row = all_row;
        all_rows(all_row).run_id = r;
        all_rows(all_row).start_rel = starts(i);
        all_rows(all_row).end_rel = starts(i) + cfg.seq_len - 1;
    end
end
all_rows = all_rows(1:all_row);
T_all = struct2table(all_rows);
idx_test = find(ismember(T_all.run_id, runs_test));
idx_train = find(ismember(T_all.run_id, runs_train));
idx_val = find(ismember(T_all.run_id, runs_val));

% TCN_prepare_dataset 在拆分后会对 idx_test 做固定 seed 的 randperm；
% dataset.X_test 和 run_id_test 都采用该随机顺序。这里必须复刻这一步，
% 否则 test row 会指向错误窗口。
rng(double(dataset.split_info.seed), 'twister');
idx_train = idx_train(randperm(numel(idx_train))); %#ok<NASGU>
idx_val = idx_val(randperm(numel(idx_val))); %#ok<NASGU>
idx_test = idx_test(randperm(numel(idx_test)));
T_test = T_all(idx_test, :);

if height(T_test) ~= size(dataset.X_test, 1)
    error('ModernTCN:WindowMapMismatch', ...
        '重建 test 窗口数=%d，但 dataset.X_test=%d。', height(T_test), size(dataset.X_test, 1));
end
map = table();
map.test_row = (1:height(T_test)).';
map.run_id = T_test.run_id;
map.start_rel = T_test.start_rel;
map.end_rel = T_test.end_rel;

if any(double(dataset.run_id_test(:)) ~= map.run_id)
    error('ModernTCN:RunIdOrderMismatch', ...
        '重建后的 run_id_test 顺序与 dataset.run_id_test 不一致。');
end
end

function cfg = local_cfg_from_dataset(dataset)
cfg = struct();
cfg.Ts = dataset.meta.Ts;
cfg.seq_len = dataset.meta.seq_len;
cfg.steady_stride = dataset.meta.steady_stride;
cfg.transition_stride = dataset.meta.transition_stride;
cfg.transition_context_sec = dataset.meta.transition_context_sec;
cfg.transition_rich = dataset.meta.transition_rich;
cfg.skip_initial_sec = dataset.meta.skip_initial_sec;
end

function labels = local_labels_for_run(run, cfg)
skip_steps = round(cfg.skip_initial_sec / cfg.Ts);
idx = (skip_steps + 1):numel(run.label_main);
labels = struct();
labels.y_main = run.label_main(idx);
labels.y_turn = run.label_turn(idx);
if isfield(run, 'y_theta_ground')
    labels.y_theta = run.y_theta_ground(idx);
elseif isfield(run, 'theta')
    labels.y_theta = run.theta(idx);
else
    labels.y_theta = run.y_raw(idx, 16);
end
end

function starts = local_window_starts(L, N, cfg)
last_start = N - cfg.seq_len + 1;
if last_start < 1
    starts = [];
    return;
end
if ~cfg.transition_rich
    starts = 1:cfg.stride:last_start;
    return;
end
steady_starts = 1:cfg.steady_stride:last_start;
transition_candidates = 1:cfg.transition_stride:last_start;
event_mask = local_event_mask(L, cfg);
keep_transition = false(size(transition_candidates));
for i = 1:numel(transition_candidates)
    s = transition_candidates(i);
    keep_transition(i) = any(event_mask(s:(s + cfg.seq_len - 1)));
end
starts = unique([steady_starts, transition_candidates(keep_transition), last_start]);
end

function event_mask = local_event_mask(L, cfg)
N = numel(L.y_main);
event_mask = false(N, 1);
main_change = [false; diff(L.y_main(:)) ~= 0];
turn_change = [false; diff(L.y_turn(:)) ~= 0];
theta_change = [false; abs(diff(L.y_theta(:))) >= deg2rad(0.20)];
event_idx = find(main_change | turn_change | theta_change);
buf = max(0, round(cfg.transition_context_sec / cfg.Ts));
for i = 1:numel(event_idx)
    i0 = max(1, event_idx(i) - buf);
    i1 = min(N, event_idx(i) + buf);
    event_mask(i0:i1) = true;
end
end

function row = local_empty_row()
row = struct('test_row', NaN, 'run_id', NaN, 'end_rel', NaN, ...
    'label_main', NaN, 'label_turn', NaN, 'theta_hat_deg', NaN, ...
    'x_window_max_abs_error', NaN, 'main_logits_max_abs_error', NaN, ...
    'turn_logits_max_abs_error', NaN, 'theta_abs_error', NaN);
end

function row = local_compare_one(test_row, run_id, end_rel, out, dataset, pred_ref)
row = local_empty_row();
row.test_row = test_row;
row.run_id = run_id;
row.end_rel = end_rel;
row.label_main = out.label_main;
row.label_turn = out.label_turn;
row.theta_hat_deg = out.theta_hat_deg;
X_ref = squeeze(single(dataset.X_test(test_row, :, :)));
row.x_window_max_abs_error = max(abs(single(out.X_window_norm) - X_ref), [], 'all');
row.main_logits_max_abs_error = max(abs(single(out.logits_main) - single(pred_ref.logits_main(test_row, :))), [], 'all');
row.turn_logits_max_abs_error = max(abs(single(out.logits_turn) - single(pred_ref.logits_turn(test_row, :))), [], 'all');
row.theta_abs_error = abs(single(out.theta_hat_rad) - single(pred_ref.theta_hat(test_row)));
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', '无法写入报告: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# ModernTCN Online Smoke Test\n\n');
fprintf(fid, '- seed: `%d`\n', result.seed);
fprintf(fid, '- pass: `%d`\n', result.pass);
fprintf(fid, '- window tolerance: `%.1e`\n', result.tol_x);
fprintf(fid, '- output tolerance: `%.1e`\n\n', result.tol_y);
fprintf(fid, '| test row | run | end rel | label main | label turn | theta deg | X err | main err | turn err | theta err |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(result.table)
    fprintf(fid, '| %d | %d | %d | %d | %d | %.4f | %.3g | %.3g | %.3g | %.3g |\n', ...
        result.table.test_row(i), result.table.run_id(i), result.table.end_rel(i), ...
        result.table.label_main(i), result.table.label_turn(i), result.table.theta_hat_deg(i), ...
        result.table.x_window_max_abs_error(i), result.table.main_logits_max_abs_error(i), ...
        result.table.turn_logits_max_abs_error(i), result.table.theta_abs_error(i));
end
end
