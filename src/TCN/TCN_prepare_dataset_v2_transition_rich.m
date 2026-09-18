function dataset = TCN_prepare_dataset_v2_transition_rich(cfg)
%TCN_PREPARE_DATASET_V2_TRANSITION_RICH 生成 TCN/GRU 共享过渡富集数据集。
%
% v2 不改变原始 raw runs，不重跑 Simulink。它在已有
% TCN_train_data_full.mat 上使用过渡段密集滑窗、稳态段稀疏滑窗，并
% 增加 main/theta 纯度、过渡和样本权重字段，供 TCN/GRU 公平重训。

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
data_tcn_dir = fullfile(root, 'data', 'tcn');
if ~isfield(cfg, 'output_file')
    cfg.output_file = fullfile(data_tcn_dir, 'TCN_dataset_v2_transition_rich.mat');
end
if ~isfield(cfg, 'scaler_file')
    cfg.scaler_file = fullfile(data_tcn_dir, 'TCN_scaler_v2_transition_rich.mat');
end
if ~isfield(cfg, 'split_file')
    cfg.split_file = fullfile(data_tcn_dir, 'TCN_GRU_shared_run_split_v2_transition_rich.mat');
end
if ~isfield(cfg, 'report_file')
    cfg.report_file = fullfile(data_tcn_dir, 'TCN_prepare_dataset_v2_transition_rich_report.md');
end

cfg.transition_rich = true;
cfg.reuse_split_file = true;
cfg.seq_len = local_cfg(cfg, 'seq_len', 128);
cfg.stride = local_cfg(cfg, 'stride', 64);
cfg.steady_stride = local_cfg(cfg, 'steady_stride', 128);
cfg.transition_stride = local_cfg(cfg, 'transition_stride', 16);
cfg.transition_context_sec = local_cfg(cfg, 'transition_context_sec', 1.00);
cfg.main_min_purity = local_cfg(cfg, 'main_min_purity', 0.80);
cfg.main_ambiguous_weight = local_cfg(cfg, 'main_ambiguous_weight', 0.65);
cfg.theta_transition_range_deg = local_cfg(cfg, 'theta_transition_range_deg', 1.50);
cfg.theta_transition_weight = local_cfg(cfg, 'theta_transition_weight', 0.75);
cfg.turn_label_strategy = local_cfg(cfg, 'turn_label_strategy', 'tail_majority');
cfg.turn_tail_sec = local_cfg(cfg, 'turn_tail_sec', 0.50);
cfg.turn_min_purity = local_cfg(cfg, 'turn_min_purity', 0.70);
cfg.turn_ambiguous_weight = local_cfg(cfg, 'turn_ambiguous_weight', 0.50);

dataset = TCN_prepare_dataset(cfg);
end

function v = local_cfg(cfg, field_name, default_value)
if isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end
