% Generate ModernTCN V4 industrial main training paths.
%
% Outputs:
%   data/paths/path_modern_tcn_v4_*.mat
%   data/paths/path_modern_tcn_v4_manifest.csv
%   figures/paths/path_modern_tcn_v4_*_preview.png

if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
gen_tcn_training_paths_cfg = struct();
gen_tcn_training_paths_cfg.seed = 20260504;
gen_tcn_training_paths_cfg.rho_filter_tau = 0.4;
gen_tcn_training_paths_cfg.make_figures = true;
gen_tcn_training_paths_cfg.profile_set = 'v4_industrial';
gen_tcn_training_paths_cfg.path_prefix = 'path_modern_tcn_v4_';
gen_tcn_training_paths_cfg.manifest_name = 'path_modern_tcn_v4_manifest.csv';
gen_tcn_training_paths_cfg.figure_prefix = 'path_modern_tcn_v4_';

run(fullfile(root, 'src', 'paths', 'gen_tcn_training_paths.m'));
