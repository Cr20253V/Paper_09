function outputs = run_TCN_GRU_main_confirm_seeds(seeds, run_tag, do_train)
%RUN_TCN_GRU_MAIN_CONFIRM_SEEDS 准备或执行 TCN/GRU 主线多 seed 确认。
%
% 默认只生成配置清单，不训练。确认机器空闲后再传入 do_train=true。
%
% 示例:
%   init_project;
%   run_TCN_GRU_main_confirm_seeds([11 21 42 73 101], 'main_confirm_v1', false);
%   run_TCN_GRU_main_confirm_seeds([11 21 42 73 101], 'main_confirm_v1', true);

if nargin < 1 || isempty(seeds)
    seeds = [11 21 42 73 101];
end
if nargin < 2 || isempty(run_tag)
    run_tag = 'main_confirm_v1';
end
if nargin < 3
    do_train = false;
end

root = project_root();
out_dir = results_dir(fullfile('tcn', 'experiments', run_tag));
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

rows = repmat(local_empty_row(), numel(seeds) * 2, 1);
idx = 0;

for i = 1:numel(seeds)
    seed = seeds(i);

    tcn_cfg = TCN_recommended_cfg('production_current');
    tcn_cfg.seed = seed;
    tcn_cfg.model_file = fullfile(root, 'data', 'models', ...
        sprintf('TCN_model_%s_staged_seed%d.mat', run_tag, seed));
    tcn_cfg.meta_file = fullfile(root, 'data', 'models', ...
        sprintf('TCN_meta_%s_staged_seed%d.mat', run_tag, seed));
    tcn_cfg.log_dir = fullfile(out_dir, sprintf('tcn_staged_seed%d', seed));
    tcn_cfg.report_file = fullfile(tcn_cfg.log_dir, 'TCN_train_report.md');

    idx = idx + 1;
    rows(idx) = local_cfg_row("TCN", seed, tcn_cfg.model_file, ...
        tcn_cfg.meta_file, tcn_cfg.report_file);
    if do_train
        TCN_train(tcn_cfg);
    end

    gru_cfg = GRU_recommended_cfg('inputstats_hidden96');
    gru_cfg.num_layers = 2;
    gru_cfg.lambda_turn = 0.05;
    gru_cfg.seed = seed;
    gru_cfg.model_file = fullfile(root, 'data', 'models', ...
        sprintf('GRU_model_%s_h96_l2_inputstats_seed%d.mat', run_tag, seed));
    gru_cfg.meta_file = fullfile(root, 'data', 'models', ...
        sprintf('GRU_meta_%s_h96_l2_inputstats_seed%d.mat', run_tag, seed));
    gru_cfg.log_dir = fullfile(out_dir, sprintf('gru_h96_l2_inputstats_seed%d', seed));
    gru_cfg.report_file = fullfile(gru_cfg.log_dir, 'GRU_train_report.md');

    idx = idx + 1;
    rows(idx) = local_cfg_row("GRU", seed, gru_cfg.model_file, ...
        gru_cfg.meta_file, gru_cfg.report_file);
    if do_train
        GRU_train(gru_cfg);
    end
end

T = struct2table(rows);
manifest = fullfile(out_dir, 'TCN_GRU_main_confirm_manifest.csv');
writetable(T, manifest);

outputs = struct();
outputs.run_tag = run_tag;
outputs.do_train = do_train;
outputs.manifest = manifest;
outputs.table = T;

fprintf('[main confirm] manifest: %s\n', manifest);
if ~do_train
    fprintf('[main confirm] do_train=false, no training was started.\n');
end
end

function row = local_empty_row()
row = struct('model', "", 'seed', NaN, 'model_file', "", ...
    'meta_file', "", 'report_file', "");
end

function row = local_cfg_row(model_name, seed, model_file, meta_file, report_file)
row = local_empty_row();
row.model = model_name;
row.seed = seed;
row.model_file = string(model_file);
row.meta_file = string(meta_file);
row.report_file = string(report_file);
end
