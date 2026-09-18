function summary = run_A1_train_missing_tcn()
%RUN_A1_TRAIN_MISSING_TCN Train exactly the seven frozen A1 TCN seeds.
% All outputs are confined to Node39/A1. Scientific settings mirror the
% Stage1 production_current / tcn96_rawtheta_sym recipe byte-for-value.

init_project();
root = project_root();
task_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '01_A1_algorithm_comparison');
dataset_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat');
seeds = [1 7 11 42 202 340 520];
model_dir = fullfile(task_root, '02_models', 'models');
log_root = fullfile(task_root, '02_models', 'matlab_logs');
local_mkdir(model_dir); local_mkdir(log_root); local_mkdir(fullfile(task_root, 'logs'));
local_check_dataset_contract(dataset_file);

diary_file = fullfile(task_root, 'logs', 'tcn_missing_7seed_train.log');
diary(diary_file); diary on;
cleanup = onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('[A1 TCN] frozen training started %s\n', datestr(now, 30));
fprintf('[A1 TCN] dataset=%s\n', dataset_file);
fprintf('[A1 TCN] seeds=%s\n', mat2str(seeds));

rows = repmat(local_empty_row(), numel(seeds), 1);
for i = 1:numel(seeds)
    seed = seeds(i);
    rows(i) = local_train_one(root, task_root, dataset_file, model_dir, log_root, seed);
    writetable(struct2table(rows(1:i)), fullfile(task_root, '02_models', 'tcn_training_summary_partial.csv'));
end

T = struct2table(rows);
summary_file = fullfile(task_root, '02_models', 'tcn_training_summary.csv');
writetable(T, summary_file);
summary = struct('task_id', 'A1_algorithm_comparison', 'dataset_file', dataset_file, ...
    'seeds', seeds, 'rows', T, 'summary_file', summary_file, ...
    'complete', all(ismember(string(T.status), ["trained","reused_verified"])));
save(fullfile(task_root, '02_models', 'tcn_training_summary.mat'), 'summary', '-v7.3');
local_write_json(fullfile(task_root, '02_models', 'tcn_training_receipt.json'), ...
    struct('task_id', 'A1_algorithm_comparison', 'timestamp', datestr(now, 30), ...
    'seeds', seeds, 'complete', summary.complete, 'summary_file', summary_file));
fprintf('[A1 TCN] complete=%d summary=%s\n', summary.complete, summary_file);
end

function row = local_train_one(root, task_root, dataset_file, model_dir, log_root, seed)
row = local_empty_row();
row.seed = seed;
row.started_at = string(datestr(now, 30));
tag = sprintf('a1_tcn_v5_plantfix_passive17_plus_all5_seed%d', seed);
log_dir = fullfile(log_root, tag);
local_mkdir(log_dir);

cfg = TCN_recommended_cfg('production_current');
cfg.case_name = 'tcn96_rawtheta_sym';
cfg.input_file = dataset_file;
cfg.seed = seed;
cfg.max_epochs = 140;
cfg.batch_size = 128;
cfg.use_gpu = true;
cfg.verbose = true;
if ~isfield(cfg, 'num_blocks'); cfg.num_blocks = 6; end
if ~isfield(cfg, 'num_filters'); cfg.num_filters = 96; end
if ~isfield(cfg, 'kernel_size'); cfg.kernel_size = 3; end
if ~isfield(cfg, 'dropout'); cfg.dropout = 0.15; end
cfg.initial_lr = 1e-3;
cfg.grad_clip_mode = 'global';
cfg.grad_clip = 5.0;
cfg.class_weight_method = 'sqrt_inverse';
cfg.turn_class_weight_method = 'sqrt_inverse';
cfg.main_class_multipliers = [1.00 1.00 1.00];
cfg.turn_class_multipliers = [1.08 1.00 1.08];
cfg.lambda_turn = 0.08;
cfg.lambda_theta = 0.55;
cfg.lambda_theta_flat = 0.12;
cfg.theta_flat_loss_mode = 'near_zero';
cfg.theta_flat_zero_tol_deg = 0.3;
cfg.theta_near_flat_deg = 0.5;
cfg.lambda_aux = 0.00;
cfg.lambda_phy = 0.00;
cfg.lambda_smooth = 0.00;
cfg.select_theta_weight = 0.30;
cfg.select_theta_ref_deg = 2.0;
cfg.turn_transition_weight = 1.25;
cfg.base_selection_start_epoch = 10;
cfg.selection_start_epoch = 64;
cfg.early_stop_min_epochs = 75;
cfg.patience = 25;
cfg.print_every = 5;
cfg.log_dir = log_dir;
cfg.model_file = fullfile(model_dir, sprintf('TCN_model_%s.mat', tag));
cfg.meta_file = fullfile(model_dir, sprintf('TCN_meta_%s.mat', tag));
cfg.report_file = fullfile(log_dir, 'TCN_train_report.md');

row.model_file = string(cfg.model_file);
row.meta_file = string(cfg.meta_file);
row.report_file = string(cfg.report_file);
row.config_file = string(fullfile(log_dir, 'frozen_train_config.mat'));
save(char(row.config_file), 'cfg');
local_write_config_json(fullfile(log_dir, 'frozen_train_config.json'), cfg, root, task_root);

try
    if local_existing_valid(cfg)
        S = load(cfg.meta_file, 'meta');
        meta = S.meta;
        status = "reused_verified";
    else
        fprintf('[A1 TCN] training seed=%d\n', seed);
        [~, meta] = TCN_train(cfg);
        status = "trained";
    end
    row.status = status;
    row.best_epoch = local_get(meta, 'best_epoch');
    row.base_best_epoch = local_get(meta, 'base_best_epoch');
    row.train_seconds = local_get(meta, 'train_seconds');
    row.input_dim = 22;
    if isfield(meta, 'test_metrics')
        row.theta_mae_deg = rad2deg(local_metric(meta.test_metrics, 'mae_theta'));
        row.theta_abs_le_10_p95_abs_err_deg = local_metric(meta.test_metrics, 'theta_abs_le_10_p95_abs_err_deg');
        row.acc_main = local_metric(meta.test_metrics, 'acc_main');
        row.acc_turn = local_metric(meta.test_metrics, 'acc_turn');
    end
catch ME
    row.status = "failed";
    row.error_message = string(getReport(ME, 'extended', 'hyperlinks', 'off'));
    fid = fopen(fullfile(log_dir, 'failure.txt'), 'w', 'n', 'UTF-8');
    if fid >= 0; fprintf(fid, '%s\n', row.error_message); fclose(fid); end
    warning('A1:TCNTrainFailed', 'TCN seed %d failed: %s', seed, ME.message);
end
row.finished_at = string(datestr(now, 30));
end

function tf = local_existing_valid(cfg)
tf = false;
if exist(cfg.model_file, 'file') ~= 2 || exist(cfg.meta_file, 'file') ~= 2; return; end
try
    S = load(cfg.meta_file, 'meta');
    tf = isfield(S, 'meta') && isfield(S.meta, 'cfg') && ...
        strcmp(char(S.meta.cfg.input_file), char(cfg.input_file)) && ...
        isequal(double(S.meta.cfg.seed), double(cfg.seed)) && ...
        exist(cfg.model_file, 'file') == 2;
catch
    tf = false;
end
end

function local_check_dataset_contract(dataset_file)
if exist(dataset_file, 'file') ~= 2; error('A1:MissingDataset', 'Missing %s', dataset_file); end
S = load(dataset_file, 'dataset'); d = S.dataset;
assert(size(d.X_train, 2) == 128 && size(d.X_train, 3) == 22, 'A1:DatasetShape', 'Expected train [N,128,22].');
assert(size(d.X_val, 1) == 3695 && size(d.X_test, 1) == 3602, 'A1:DatasetSplit', 'Frozen val/test count mismatch.');
if isfield(d, 'meta') && isfield(d.meta, 'plant_revision')
    revision = d.meta.plant_revision;
    if isstruct(revision) && isfield(revision, 'id'); revision = revision.id; end
    assert(strcmp(char(revision), 'agv_physics_v2_plantfix'), 'A1:PlantRevision', 'Plant revision mismatch.');
end
end

function local_write_config_json(path, cfg, root, task_root)
x = struct('task_id', 'A1_algorithm_comparison', 'recipe', 'production_current/tcn96_rawtheta_sym', ...
    'seed', cfg.seed, 'input_file', cfg.input_file, 'seq_len', 128, 'input_dim', 22, ...
    'max_epochs', cfg.max_epochs, 'batch_size', cfg.batch_size, 'use_gpu', cfg.use_gpu, ...
    'num_blocks', cfg.num_blocks, 'num_filters', cfg.num_filters, 'kernel_size', cfg.kernel_size, ...
    'dropout', cfg.dropout, 'initial_lr', cfg.initial_lr, 'grad_clip_mode', cfg.grad_clip_mode, ...
    'grad_clip', cfg.grad_clip, 'lambda_turn', cfg.lambda_turn, 'lambda_theta', cfg.lambda_theta, ...
    'lambda_theta_flat', cfg.lambda_theta_flat, 'selection_start_epoch', cfg.selection_start_epoch, ...
    'early_stop_min_epochs', cfg.early_stop_min_epochs, 'patience', cfg.patience, ...
    'model_file', cfg.model_file, 'meta_file', cfg.meta_file, 'project_root', root, 'output_root', task_root);
local_write_json(path, x);
end

function v = local_metric(s, name)
v = NaN; if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = double(s.(name)); end
end
function v = local_get(s, name)
v = NaN; if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = double(s.(name)); end
end
function local_mkdir(path)
if exist(path, 'dir') ~= 7; mkdir(path); end
end
function local_write_json(path, data)
fid = fopen(path, 'w', 'n', 'UTF-8'); if fid < 0; error('A1:JsonWrite', 'Cannot write %s', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(data, 'PrettyPrint', true));
end
function row = local_empty_row()
row = struct('seed', NaN, 'status', "pending", 'started_at', "", 'finished_at', "", ...
    'model_file', "", 'meta_file', "", 'report_file', "", 'config_file', "", ...
    'best_epoch', NaN, 'base_best_epoch', NaN, 'train_seconds', NaN, 'input_dim', NaN, ...
    'theta_mae_deg', NaN, 'theta_abs_le_10_p95_abs_err_deg', NaN, ...
    'acc_main', NaN, 'acc_turn', NaN, 'error_message', "");
end
