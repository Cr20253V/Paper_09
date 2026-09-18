% =============================
% 文件名：gen_tcn_training_paths_v3_transition_rich.m
% 功能描述：
%   生成 V3 transition-rich TCN/GRU 共享训练路径，不覆盖 V1/V2 使用的
%   path_train_tcn_*.mat。V3 在原有 18 条短路径基础上补充坡度-转弯重叠、
%   负坡组合、连续坡度变化和不同坡度过渡时间样本。
%
% 使用方法：
%   init_project;
%   run('src/paths/gen_tcn_training_paths_v3_transition_rich.m');
%
% 产物：
%   data/paths/path_train_tcn_v3_*.mat
%   data/paths/path_train_tcn_v3_manifest.csv
%   figures/paths/path_train_tcn_v3_*_preview.png
% =============================

if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
gen_tcn_training_paths_cfg = struct();
gen_tcn_training_paths_cfg.seed = 20260428;
gen_tcn_training_paths_cfg.rho_filter_tau = 0.4;
gen_tcn_training_paths_cfg.make_figures = true;
gen_tcn_training_paths_cfg.profile_set = 'v3_transition_rich';
gen_tcn_training_paths_cfg.path_prefix = 'path_train_tcn_v3_';
gen_tcn_training_paths_cfg.manifest_name = 'path_train_tcn_v3_manifest.csv';
gen_tcn_training_paths_cfg.figure_prefix = 'path_train_tcn_v3_';

run(fullfile(root, 'src', 'paths', 'gen_tcn_training_paths.m'));
