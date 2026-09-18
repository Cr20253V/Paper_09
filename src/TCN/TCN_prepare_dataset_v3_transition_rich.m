function dataset = TCN_prepare_dataset_v3_transition_rich(cfg)
%TCN_PREPARE_DATASET_V3_TRANSITION_RICH 生成 V3 TCN/GRU 共享过渡富集数据集。
%
% V3 默认读取 TCN_train_data_v3_transition_rich_full.mat，不覆盖 V2 的
% TCN_dataset_v2_transition_rich.mat。相比 V2，V3 对坡度连续变化和
% 坡度-转弯重叠样本使用更密集的过渡滑窗，并保留 theta 过渡样本的
% 回归权重。

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
data_tcn_dir = fullfile(root, 'data', 'tcn');
cfg.input_file = local_cfg(cfg, 'input_file', ...
    fullfile(data_tcn_dir, 'TCN_train_data_v3_transition_rich_full.mat'));
cfg.output_file = local_cfg(cfg, 'output_file', ...
    fullfile(data_tcn_dir, 'TCN_dataset_v3_transition_rich.mat'));
cfg.scaler_file = local_cfg(cfg, 'scaler_file', ...
    fullfile(data_tcn_dir, 'TCN_scaler_v3_transition_rich.mat'));
cfg.split_file = local_cfg(cfg, 'split_file', ...
    fullfile(data_tcn_dir, 'TCN_GRU_shared_run_split_v3_transition_rich.mat'));
cfg.report_file = local_cfg(cfg, 'report_file', ...
    fullfile(data_tcn_dir, 'TCN_prepare_dataset_v3_transition_rich_report.md'));

cfg.transition_rich = true;
% V3 path table is still being revised during ModernTCN integration. Rebuild
% the run-level split by default so newly added paths are not silently
% excluded by an older split file.
cfg.reuse_split_file = local_cfg(cfg, 'reuse_split_file', false);
cfg.seq_len = local_cfg(cfg, 'seq_len', 128);
cfg.stride = local_cfg(cfg, 'stride', 64);
cfg.steady_stride = local_cfg(cfg, 'steady_stride', 128);
cfg.transition_stride = local_cfg(cfg, 'transition_stride', 12);
cfg.transition_context_sec = local_cfg(cfg, 'transition_context_sec', 1.50);
cfg.main_min_purity = local_cfg(cfg, 'main_min_purity', 0.80);
cfg.main_ambiguous_weight = local_cfg(cfg, 'main_ambiguous_weight', 0.75);
cfg.theta_transition_range_deg = local_cfg(cfg, 'theta_transition_range_deg', 1.00);
cfg.theta_transition_weight = local_cfg(cfg, 'theta_transition_weight', 1.00);
cfg.turn_label_strategy = local_cfg(cfg, 'turn_label_strategy', 'tail_majority');
cfg.turn_tail_sec = local_cfg(cfg, 'turn_tail_sec', 0.50);
cfg.turn_min_purity = local_cfg(cfg, 'turn_min_purity', 0.70);
cfg.turn_ambiguous_weight = local_cfg(cfg, 'turn_ambiguous_weight', 0.60);

dataset = TCN_prepare_dataset(cfg);
end

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end
