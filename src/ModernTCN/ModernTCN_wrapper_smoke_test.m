function result = ModernTCN_wrapper_smoke_test(seed, test_indices, cfg)
%MODERNTCN_WRAPPER_SMOKE_TEST 检查单窗口 wrapper 是否复现 full-test 输出。
%
% 功能说明：
%   本脚本用于进入 Simulink 前的第三步验证。它会加载指定 seed 的 ONNX，
%   从当前推荐数据集取若干个 X_test 窗口，逐个调用 ModernTCN_predict_window，
%   再和第二步 full-test 保存的 MATLAB 输出做数值对照。
%
% 为什么要做这一步：
%   full-test 脚本证明 MATLAB 可以批量复现 Python 指标；本脚本进一步证明
%   后续 Simulink 将要调用的“单窗口在线接口”没有改变输出顺序、标签映射
%   或输入维度。
%
% 用法：
%   init_project;
%   addpath(fullfile(project_root(), 'src', 'ModernTCN'));
%   result = ModernTCN_wrapper_smoke_test();

if nargin < 2 || isempty(test_indices)
    test_indices = [1 2 3 16 128 512 1024 2048 2849];
end
if nargin < 3 || isempty(cfg)
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
dataset_file = local_cfg_value(cfg, 'dataset_file', ...
    default_cfg.dataset_file);
run_tag = local_cfg_value(cfg, 'run_tag', default_cfg.run_tag);
if ~isempty(run_tag)
    tag = regexprep(char(run_tag), '[^A-Za-z0-9_\-]+', '_');
    reference_dir = fullfile(root, 'results', 'modern_tcn', sprintf('matlab_full_testset_%s', tag));
else
    reference_dir = fullfile(root, 'results', 'modern_tcn', 'matlab_full_testset');
end
reference_dir = local_cfg_value(cfg, 'reference_dir', reference_dir);
reference_file = fullfile(reference_dir, sprintf('modern_tcn_seed%d_matlab_full_testset_outputs.mat', seed));

if exist(dataset_file, 'file') ~= 2
    error('ModernTCN:MissingDataset', '找不到数据集: %s', dataset_file);
end
if exist(reference_file, 'file') ~= 2
    error(['ModernTCN:MissingReference'], ...
        ['找不到 full-test 输出: %s\n', ...
         '请先运行 ModernTCN_matlab_full_testset_eval()。'], reference_file);
end

S = load(dataset_file, 'dataset');
R = load(reference_file, 'pred', 'onnx_file');
n_total = size(S.dataset.X_test, 1);
test_indices = unique(test_indices(:).');
test_indices = test_indices(test_indices >= 1 & test_indices <= n_total);
if isempty(test_indices)
    error('ModernTCN:EmptyIndices', '没有可用的测试窗口索引。');
end

onnx_file = local_cfg_value(cfg, 'onnx_file', '');
if isempty(onnx_file) && ~isempty(run_tag)
    onnx_file = fullfile(root, 'results', 'modern_tcn', char(run_tag), sprintf('modern_tcn_seed%d.onnx', seed));
end
if isempty(onnx_file)
    predictor = ModernTCN_load_predictor(seed);
else
    predictor = ModernTCN_load_predictor(seed, onnx_file);
end
cfg = local_fill_augment_cfg(cfg, predictor);
rows = repmat(local_empty_row(), numel(test_indices), 1);

fprintf('[ModernTCN wrapper smoke] seed=%d | windows=%d\n', seed, numel(test_indices));
for k = 1:numel(test_indices)
    idx = test_indices(k);
    % 推荐的在线输入形状是 [time,feature]，这里刻意 squeeze 成 128xF
    % 来验证后续 MATLAB/Simulink 调用路径。
    X_window = squeeze(single(S.dataset.X_test(idx,:,:)));
    X_window = local_prepare_wrapper_window(X_window, cfg, predictor);
    out = ModernTCN_predict_window(predictor, X_window);

    ref_main = single(R.pred.logits_main(idx,:));
    ref_turn = single(R.pred.logits_turn(idx,:));
    ref_theta = single(R.pred.theta_hat(idx,:));

    rows(k) = local_make_row(idx, out, ref_main, ref_turn, ref_theta);
    fprintf('  idx=%4d main=%d turn=%d theta=%.4f deg | max_err=%.3g\n', ...
        idx, rows(k).main_state, rows(k).turn_state, rows(k).theta_hat_deg, ...
        max([rows(k).main_max_abs_error, rows(k).turn_max_abs_error, rows(k).theta_abs_error]));
end

T = struct2table(rows);
max_main = max(T.main_max_abs_error);
max_turn = max(T.turn_max_abs_error);
max_theta = max(T.theta_abs_error);
tol = 1e-6;
pass = max([max_main, max_turn, max_theta]) <= tol;

out_dir = fullfile(root, 'results', 'modern_tcn', 'wrapper_smoke');
if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
    out_dir = char(cfg.output_dir);
end
if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end
csv_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_wrapper_smoke.csv', seed));
mat_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_wrapper_smoke.mat', seed));
report_file = fullfile(out_dir, sprintf('modern_tcn_seed%d_wrapper_smoke_report.md', seed));
writetable(T, csv_file);

result = struct();
result.seed = seed;
result.pass = pass;
result.tolerance = tol;
result.indices = test_indices;
result.max_main_abs_error = max_main;
result.max_turn_abs_error = max_turn;
result.max_theta_abs_error = max_theta;
result.table = T;
result.dataset_file = dataset_file;
result.reference_file = reference_file;
result.csv_file = csv_file;
result.mat_file = mat_file;
result.report_file = report_file;
result.onnx_file = predictor.onnx_file;

save(mat_file, 'result');
local_write_report(report_file, result);

fprintf('[ModernTCN wrapper smoke] pass=%d | main=%.3g turn=%.3g theta=%.3g\n', ...
    result.pass, result.max_main_abs_error, result.max_turn_abs_error, result.max_theta_abs_error);
fprintf('  csv   : %s\n', csv_file);
fprintf('  report: %s\n', report_file);
end

function cfg = local_fill_augment_cfg(cfg, predictor)
if ~isfield(cfg, 'input_augment') || isempty(cfg.input_augment)
    cfg.input_augment = local_cfg_value(predictor, 'input_augment', 'none');
end
if ~isfield(cfg, 'delta_lag') || isempty(cfg.delta_lag)
    cfg.delta_lag = local_cfg_value(predictor, 'delta_lag', 1);
end
if ~isfield(cfg, 'delta_pad') || isempty(cfg.delta_pad)
    cfg.delta_pad = local_cfg_value(predictor, 'delta_pad', 'zero');
end
if ~isfield(cfg, 'lag_steps') || isempty(cfg.lag_steps)
    cfg.lag_steps = local_cfg_value(predictor, 'lag_steps', [1 2 4]);
end
if ~isfield(cfg, 'lag_pad') || isempty(cfg.lag_pad)
    cfg.lag_pad = local_cfg_value(predictor, 'lag_pad', 'edge');
end
if ~isfield(cfg, 'delta_clip_abs') || isempty(cfg.delta_clip_abs)
    cfg.delta_clip_abs = local_cfg_value(predictor, 'delta_clip_abs', 5.0);
end
if ~isfield(cfg, 'raw_input_dim') || isempty(cfg.raw_input_dim)
    cfg.raw_input_dim = local_cfg_value(predictor, 'raw_input_dim', 22);
end
if ~isfield(cfg, 'augmented_input_dim') || isempty(cfg.augmented_input_dim)
    cfg.augmented_input_dim = local_cfg_value(predictor, 'augmented_input_dim', 44);
end
if ~isfield(cfg, 'raw_feature_mean') || isempty(cfg.raw_feature_mean)
    cfg.raw_feature_mean = local_cfg_value(predictor, 'raw_feature_mean', []);
end
if ~isfield(cfg, 'raw_feature_std') || isempty(cfg.raw_feature_std)
    cfg.raw_feature_std = local_cfg_value(predictor, 'raw_feature_std', []);
end
if ~isfield(cfg, 'physics_feature_mean') || isempty(cfg.physics_feature_mean)
    cfg.physics_feature_mean = local_cfg_value(predictor, 'physics_feature_mean', []);
end
if ~isfield(cfg, 'physics_feature_std') || isempty(cfg.physics_feature_std)
    cfg.physics_feature_std = local_cfg_value(predictor, 'physics_feature_std', []);
end
if ~isfield(cfg, 'physics_clip_abs') || isempty(cfg.physics_clip_abs)
    cfg.physics_clip_abs = local_cfg_value(predictor, 'physics_clip_abs', 8.0);
end
if ~isfield(cfg, 'physics_params') || isempty(cfg.physics_params)
    cfg.physics_params = local_cfg_value(predictor, 'physics_params', struct());
end
end

function X_window = local_prepare_wrapper_window(X_window, cfg, predictor)
input_augment = lower(strtrim(char(local_cfg_value(cfg, 'input_augment', 'none'))));
if ~strcmp(input_augment, 'none')
    cfg.input_augment = input_augment;
    cfg.delta_lag = local_cfg_value(cfg, 'delta_lag', local_cfg_value(predictor, 'delta_lag', 1));
    cfg.delta_pad = local_cfg_value(cfg, 'delta_pad', local_cfg_value(predictor, 'delta_pad', 'zero'));
    cfg.lag_steps = local_cfg_value(cfg, 'lag_steps', local_cfg_value(predictor, 'lag_steps', [1 2 4]));
    cfg.lag_pad = local_cfg_value(cfg, 'lag_pad', local_cfg_value(predictor, 'lag_pad', 'edge'));
    cfg.delta_clip_abs = local_cfg_value(cfg, 'delta_clip_abs', local_cfg_value(predictor, 'delta_clip_abs', 5.0));
    cfg.raw_feature_mean = local_cfg_value(cfg, 'raw_feature_mean', local_cfg_value(predictor, 'raw_feature_mean', []));
    cfg.raw_feature_std = local_cfg_value(cfg, 'raw_feature_std', local_cfg_value(predictor, 'raw_feature_std', []));
    cfg.physics_feature_mean = local_cfg_value(cfg, 'physics_feature_mean', local_cfg_value(predictor, 'physics_feature_mean', []));
    cfg.physics_feature_std = local_cfg_value(cfg, 'physics_feature_std', local_cfg_value(predictor, 'physics_feature_std', []));
    cfg.physics_clip_abs = local_cfg_value(cfg, 'physics_clip_abs', local_cfg_value(predictor, 'physics_clip_abs', 8.0));
    cfg.physics_params = local_cfg_value(cfg, 'physics_params', local_cfg_value(predictor, 'physics_params', struct()));
    X_window = ModernTCN_augment_window(X_window, cfg);
end
end

function v = local_cfg_value(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function row = local_empty_row()
row = struct('index', NaN, 'main_state', NaN, 'turn_state', NaN, ...
    'theta_hat_deg', NaN, 'main_max_abs_error', NaN, ...
    'turn_max_abs_error', NaN, 'theta_abs_error', NaN, ...
    'main_confidence', NaN, 'turn_confidence', NaN);
end

function row = local_make_row(idx, out, ref_main, ref_turn, ref_theta)
row = local_empty_row();
row.index = idx;
row.main_state = out.main_state;
row.turn_state = out.turn_state;
row.theta_hat_deg = out.theta_hat_deg;
row.main_max_abs_error = max(abs(single(out.logits_main) - ref_main), [], 'all');
row.turn_max_abs_error = max(abs(single(out.logits_turn) - ref_turn), [], 'all');
row.theta_abs_error = abs(single(out.theta_hat_rad) - ref_theta(1));
row.main_confidence = out.main_confidence;
row.turn_confidence = out.turn_confidence;
end

function local_write_report(report_file, result)
fid = fopen(report_file, 'w');
if fid < 0
    warning('ModernTCN:ReportFailed', '无法写入报告: %s', report_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# ModernTCN Wrapper Smoke Test\n\n');
fprintf(fid, '- seed: `%d`\n', result.seed);
fprintf(fid, '- pass: `%d`\n', result.pass);
fprintf(fid, '- tolerance: `%.1e`\n', result.tolerance);
fprintf(fid, '- onnx: `%s`\n', result.onnx_file);
fprintf(fid, '- reference: `%s`\n\n', result.reference_file);
fprintf(fid, '| max main abs error | max turn abs error | max theta abs error |\n');
fprintf(fid, '|---:|---:|---:|\n');
fprintf(fid, '| %.6g | %.6g | %.6g |\n\n', ...
    result.max_main_abs_error, result.max_turn_abs_error, result.max_theta_abs_error);
fprintf(fid, '## Checked Windows\n\n');
fprintf(fid, '| index | main | turn | theta deg | main confidence | turn confidence |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(result.table)
    fprintf(fid, '| %d | %d | %d | %.4f | %.4f | %.4f |\n', ...
        result.table.index(i), result.table.main_state(i), ...
        result.table.turn_state(i), result.table.theta_hat_deg(i), ...
        result.table.main_confidence(i), result.table.turn_confidence(i));
end
end
