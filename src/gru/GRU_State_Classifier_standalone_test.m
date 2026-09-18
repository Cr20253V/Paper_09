function result = GRU_State_Classifier_standalone_test(run_id, max_steps)
%GRU_STATE_CLASSIFIER_STANDALONE_TEST Check the Simulink GRU wrapper entry.

if nargin < 1 || isempty(run_id)
    run_id = 1;
end
if nargin < 2 || isempty(max_steps)
    max_steps = 420;
end
if exist('init_project', 'file') == 2
    init_project();
end

cfg = GRU_load_default_to_base();
params = evalin('base', 'params');

if exist(cfg.raw_train_file, 'file') ~= 2
    error('GRU_standalone:MissingRawData', 'Missing raw data: %s', cfg.raw_train_file);
end
D = load(cfg.raw_train_file, 'data');
if run_id < 1 || run_id > numel(D.data.runs)
    error('GRU_standalone:BadRunID', 'run_id=%d out of range 1..%d.', ...
        run_id, numel(D.data.runs));
end

run = D.data.runs(run_id);
y_raw = double(run.y_raw);
n = min(max_steps, size(y_raw, 1));

clear GRU_State_Classifier_gru_sim
evalin('base', 'clear gru_out_temp');
GRU_State_Classifier_gru_sim(y_raw(1,:).', 1);

rows = repmat(local_empty_row(), n, 1);
fprintf('[GRU standalone] seed=%d run=%d steps=%d\n', cfg.seed, run_id, n);
for k = 1:n
    [theta_hat, label_main, label_turn, conf_main] = ...
        GRU_State_Classifier_gru_sim(y_raw(k,:).', 0);
    debug = local_read_debug();
    rows(k) = local_make_row(k, params.Ts, theta_hat, label_main, ...
        label_turn, conf_main, run, debug);
end

T = struct2table(rows);
valid_labels = all(ismember(T.label_main, [1; 2; 3])) ...
    && all(ismember(T.label_turn, [-1; 0; 1]));
finite_outputs = all(isfinite(T.theta_hat_rad)) && all(isfinite(T.conf_main));
seq_len = evalin('base', 'gru_model.seq_len');
has_full_buffer = any(T.buffer_count >= seq_len);
eval_mask = T.buffer_count >= seq_len;
acc_main_online = local_masked_acc(T.label_main, T.truth_main, eval_mask);
acc_turn_online = local_masked_acc(T.label_turn, T.truth_turn, eval_mask);

out_dir = fullfile(project_root(), 'results', 'gru', 'simulink_wrapper_v4');
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
csv_file = fullfile(out_dir, sprintf('gru_seed%d_run%d_state_classifier_standalone.csv', cfg.seed, run_id));
mat_file = fullfile(out_dir, sprintf('gru_seed%d_run%d_state_classifier_standalone.mat', cfg.seed, run_id));
report_file = fullfile(out_dir, sprintf('gru_seed%d_run%d_state_classifier_standalone_report.md', cfg.seed, run_id));
writetable(T, csv_file);

result = struct();
result.seed = cfg.seed;
result.run_id = run_id;
result.steps = n;
result.seq_len = seq_len;
result.pass = valid_labels && finite_outputs && has_full_buffer;
result.valid_labels = valid_labels;
result.finite_outputs = finite_outputs;
result.has_full_buffer = has_full_buffer;
result.acc_main_online = acc_main_online;
result.acc_turn_online = acc_turn_online;
result.csv_file = csv_file;
result.mat_file = mat_file;
result.report_file = report_file;
result.table = T;
save(mat_file, 'result');
local_write_report(report_file, result, cfg, run);

fprintf('[GRU standalone] pass=%d | valid=%d finite=%d full_buffer=%d\n', ...
    result.pass, valid_labels, finite_outputs, has_full_buffer);
fprintf('  online acc after warmup: main=%.4f turn=%.4f\n', ...
    acc_main_online, acc_turn_online);
fprintf('  report: %s\n', report_file);
end

function row = local_empty_row()
row = struct('step', NaN, 'time_s', NaN, 'theta_hat_rad', NaN, ...
    'theta_hat_deg', NaN, 'label_main', NaN, 'label_turn', NaN, ...
    'conf_main', NaN, 'buffer_count', NaN, 'truth_main', NaN, ...
    'truth_turn', NaN, 'theta_truth_rad', NaN);
end

function row = local_make_row(k, Ts, theta_hat, label_main, label_turn, conf_main, run, debug)
row = local_empty_row();
row.step = k;
row.time_s = (k - 1) * Ts;
row.theta_hat_rad = theta_hat;
row.theta_hat_deg = rad2deg(theta_hat);
row.label_main = label_main;
row.label_turn = label_turn;
row.conf_main = conf_main;
row.buffer_count = debug.buffer_count;
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
debug = struct('buffer_count', 0);
try
    if evalin('base', 'exist(''gru_out_temp'', ''var'') == 1')
        d = evalin('base', 'gru_out_temp.debug');
        if isstruct(d) && isfield(d, 'buffer_count')
            debug.buffer_count = double(d.buffer_count);
        end
    end
catch
end
end

function acc = local_masked_acc(pred, truth, mask)
mask = logical(mask) & isfinite(pred) & isfinite(truth);
if ~any(mask)
    acc = NaN;
else
    acc = mean(double(pred(mask)) == double(truth(mask)));
end
end

function local_write_report(report_file, result, cfg, run)
fid = fopen(report_file, 'w');
if fid < 0
    warning('GRU_standalone:ReportFailed', 'Cannot write report: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# GRU State Classifier Standalone Test\n\n');
fprintf(fid, '- seed: `%d`\n', result.seed);
fprintf(fid, '- run_id: `%d`\n', result.run_id);
fprintf(fid, '- scene: `%s`\n', local_run_field(run, 'scene', 'unknown'));
fprintf(fid, '- model: `%s`\n', cfg.model_file);
fprintf(fid, '- raw data: `%s`\n', cfg.raw_train_file);
fprintf(fid, '- steps: `%d`\n', result.steps);
fprintf(fid, '- seq_len: `%d`\n', result.seq_len);
fprintf(fid, '- pass: `%d`\n\n', result.pass);

fprintf(fid, '| check | pass |\n');
fprintf(fid, '|---|---:|\n');
fprintf(fid, '| labels in valid ranges | %d |\n', result.valid_labels);
fprintf(fid, '| finite outputs | %d |\n', result.finite_outputs);
fprintf(fid, '| buffer reached seq_len | %d |\n\n', result.has_full_buffer);

fprintf(fid, '- online main acc after warmup: `%.4f`\n', result.acc_main_online);
fprintf(fid, '- online turn acc after warmup: `%.4f`\n\n', result.acc_turn_online);

last = result.table(max(1, height(result.table)-9):height(result.table), :);
fprintf(fid, '## Last Samples\n\n');
fprintf(fid, '| step | t | main | turn | conf | theta deg | buffer | truth main | truth turn |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(last)
    fprintf(fid, '| %d | %.2f | %d | %d | %.4f | %.4f | %d | %d | %d |\n', ...
        last.step(i), last.time_s(i), last.label_main(i), last.label_turn(i), ...
        last.conf_main(i), last.theta_hat_deg(i), last.buffer_count(i), ...
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

