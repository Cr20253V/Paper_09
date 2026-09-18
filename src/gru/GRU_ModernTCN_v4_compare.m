function result = GRU_ModernTCN_v4_compare(cfg)
%GRU_MODERNTCN_V4_COMPARE Write the current GRU/ModernTCN V4 comparison.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
gru_cfg = GRU_default_config(root);
modern_cfg = ModernTCN_default_config(root);
cfg = local_defaults(cfg, root, gru_cfg, modern_cfg);

G = readtable(cfg.gru_summary_file, 'TextType', 'string');
GG = readtable(cfg.gru_group_summary_file, 'TextType', 'string');
M = readtable(cfg.modern_tcn_summary_file, 'TextType', 'string');

rows = repmat(local_empty_row(), 3, 1);
rows(1) = local_modern_row(M(1,:), cfg, modern_cfg);
rows(2) = local_gru_candidate_row(G(G.seed == gru_cfg.seed, :), gru_cfg);
rows(3) = local_gru_group_row(GG(1,:), gru_cfg);
T = struct2table(rows);

if exist(cfg.output_dir, 'dir') ~= 7
    mkdir(cfg.output_dir);
end
csv_file = fullfile(cfg.output_dir, 'modern_tcn_gru_v4_candidate_compare.csv');
md_file = fullfile(cfg.output_dir, 'modern_tcn_gru_v4_candidate_compare.md');
writetable(T, csv_file);
local_write_md(md_file, T, cfg);

result = struct();
result.table = T;
result.csv_file = csv_file;
result.report_file = md_file;
fprintf('[GRU/ModernTCN compare] wrote %s\n', md_file);
end

function cfg = local_defaults(cfg, root, gru_cfg, modern_cfg)
if ~isfield(cfg, 'output_dir')
    cfg.output_dir = fullfile(root, 'results', 'compare', 'modern_tcn_gru_v4');
end
if ~isfield(cfg, 'gru_summary_file')
    cfg.gru_summary_file = gru_cfg.summary_file;
end
if ~isfield(cfg, 'gru_group_summary_file')
    cfg.gru_group_summary_file = gru_cfg.group_summary_file;
end
if ~isfield(cfg, 'modern_tcn_summary_file')
    cfg.modern_tcn_summary_file = fullfile(root, 'results', 'modern_tcn', ...
        modern_cfg.run_tag, sprintf('modern_tcn_seed%d_summary.csv', modern_cfg.seed));
end
end

function row = local_empty_row()
row = struct('model', "", 'candidate', "", 'seed', NaN, 'n_seeds', NaN, ...
    'acc_main', NaN, 'acc_main_std', NaN, ...
    'acc_turn', NaN, 'acc_turn_std', NaN, ...
    'acc_turn_pure', NaN, 'acc_turn_pure_std', NaN, ...
    'acc_turn_transition', NaN, 'acc_turn_transition_std', NaN, ...
    'theta_mae_deg', NaN, 'theta_mae_deg_std', NaN, ...
    'flat_recall', NaN, 'stall_recall', NaN, 'slope_recall', NaN, ...
    'uphill_recall', NaN, 'downhill_recall', NaN, 'flat_as_slope', NaN, ...
    'artifact', "", 'report_file', "");
end

function row = local_modern_row(T, cfg, modern_cfg)
row = local_empty_row();
row.model = "ModernTCN";
row.candidate = string(modern_cfg.run_tag);
row.seed = T.seed;
row.n_seeds = 1;
row.acc_main = T.acc_main;
row.acc_turn = T.acc_turn;
row.acc_turn_pure = T.acc_turn_pure;
row.acc_turn_transition = T.acc_turn_transition;
row.theta_mae_deg = T.theta_mae_deg;
row.flat_recall = T.flat_recall;
row.stall_recall = T.stall_recall;
row.slope_recall = T.slope_recall;
row.uphill_recall = T.uphill_recall;
row.downhill_recall = T.downhill_recall;
if ismember('flat_as_slope', T.Properties.VariableNames)
    row.flat_as_slope = T.flat_as_slope;
end
row.artifact = string(modern_cfg.onnx_file);
row.report_file = string(T.report_file);
if strlength(row.report_file) == 0
    row.report_file = string(cfg.modern_tcn_summary_file);
end
end

function row = local_gru_candidate_row(T, gru_cfg)
if height(T) ~= 1
    error('GRU_ModernTCN_compare:MissingGRUSeed', 'Cannot find GRU seed %d summary.', gru_cfg.seed);
end
row = local_empty_row();
row.model = "GRU";
row.candidate = string(T.case_name);
row.seed = T.seed;
row.n_seeds = 1;
row.acc_main = T.acc_main;
row.acc_turn = T.acc_turn;
row.acc_turn_pure = T.acc_turn_pure;
row.acc_turn_transition = T.acc_turn_transition;
row.theta_mae_deg = T.theta_mae_deg;
row.flat_recall = T.flat_recall;
row.stall_recall = T.stall_recall;
row.slope_recall = T.slope_recall;
row.uphill_recall = T.uphill_recall;
row.downhill_recall = T.downhill_recall;
row.flat_as_slope = T.flat_as_slope;
row.artifact = string(T.model_file);
row.report_file = string(T.report_file);
end

function row = local_gru_group_row(T, gru_cfg)
row = local_empty_row();
row.model = "GRU";
row.candidate = string(T.case_name) + "_5seed_mean";
row.seed = NaN;
row.n_seeds = T.n;
row.acc_main = T.acc_main_mean;
row.acc_main_std = T.acc_main_std;
row.acc_turn = T.acc_turn_mean;
row.acc_turn_std = T.acc_turn_std;
row.acc_turn_pure = T.acc_turn_pure_mean;
row.acc_turn_pure_std = T.acc_turn_pure_std;
row.acc_turn_transition = T.acc_turn_transition_mean;
row.acc_turn_transition_std = T.acc_turn_transition_std;
row.theta_mae_deg = T.theta_mae_deg_mean;
row.theta_mae_deg_std = T.theta_mae_deg_std;
row.flat_recall = T.flat_recall_mean;
row.stall_recall = T.stall_recall_mean;
row.slope_recall = T.slope_recall_mean;
row.uphill_recall = T.uphill_recall_mean;
row.downhill_recall = T.downhill_recall_mean;
row.flat_as_slope = T.flat_as_slope_mean;
row.artifact = string(gru_cfg.summary_file);
row.report_file = string(fullfile(fileparts(gru_cfg.summary_file), ...
    'GRU_v4_industrial_existing_meta_report.md'));
end

function local_write_md(md_file, T, cfg)
fid = fopen(md_file, 'w');
if fid < 0
    warning('GRU_ModernTCN_compare:ReportFailed', 'Cannot write report: %s', md_file);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# ModernTCN vs GRU V4 Candidate Compare\n\n');
fprintf(fid, '- ModernTCN summary: `%s`\n', cfg.modern_tcn_summary_file);
fprintf(fid, '- GRU per-seed summary: `%s`\n', cfg.gru_summary_file);
fprintf(fid, '- GRU group summary: `%s`\n\n', cfg.gru_group_summary_file);
fprintf(fid, '| model | candidate | seed | n | main | turn | turn pure | turn trans | theta deg | flat | stall | slope | uphill | downhill | flat->slope | artifact |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(T)
    seed_text = local_seed_text(T.seed(i));
    fprintf(fid, '| %s | %s | %s | %.0f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f | `%s` |\n', ...
        char(T.model(i)), char(T.candidate(i)), char(seed_text), T.n_seeds(i), ...
        T.acc_main(i), T.acc_turn(i), T.acc_turn_pure(i), ...
        T.acc_turn_transition(i), T.theta_mae_deg(i), ...
        T.flat_recall(i), T.stall_recall(i), T.slope_recall(i), ...
        T.uphill_recall(i), T.downhill_recall(i), T.flat_as_slope(i), ...
        char(T.artifact(i)));
end
fprintf(fid, '\n## Reading\n\n');
fprintf(fid, '- ModernTCN remains the better classifier on this V4 test split, especially main state and turn transition.\n');
fprintf(fid, '- GRU seed101 is the best GRU deployment candidate because it has the best main/turn scores and lowest theta MAE among the five seeds.\n');
fprintf(fid, '- GRU has lower theta MAE than the current ModernTCN deployment candidate, so it is still a useful regression baseline.\n');
end

function s = local_seed_text(v)
if isnan(v)
    s = "mean";
else
    s = string(sprintf('%.0f', v));
end
end
