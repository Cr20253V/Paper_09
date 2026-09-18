% =============================
% 文件名：GRU_prepare_dataset.m
% 版本号：V2.0（迁移至 industrial_lite 复合路径）
% 最后修改时间：2026-04-14
% 作者：LPV-MPC Project
% 功能描述：
%   GRU训练数据预处理脚本
%   1. 加载原始数据（GRU_train_data_full.mat）
%   2. 提取 passive17_plus_all5 特征并计算派生特征
%   3. 按回合分组，防止数据泄漏（A2优化）
%   4. 滑窗切片（seq_len=48, stride=12）
%   5. 数据归一化（z-score，仅用训练集统计）
%   6. 保存处理后的数据集
%
% V1.7 更新（2025-12-30）：
%   - 主分类简化为 3 类：flat/stall/slope（移除 slip）
%   - 更新标签编号：stall=2, slope=3

root = project_root();
data_gru_dir = fullfile(root, 'data', 'gru');
data_models_dir = fullfile(root, 'data', 'models');
data_mamba_dir = fullfile(root, 'data', 'mamba');

% 若调用前未在工作区定义 cfg，则使用默认配置（便于直接 run 脚本）
if ~exist('cfg', 'var') || ~isstruct(cfg)
    cfg = struct();
end
if ~isfield(cfg, 'dataset_source'); cfg.dataset_source = 'auto'; end  % 'auto'|'gru'|'mamba'
if ~isfield(cfg, 'input_file') || isempty(cfg.input_file)
    cfg.input_file = resolve_source_input_file(cfg.dataset_source, data_gru_dir, data_mamba_dir);
end
if ~isfield(cfg, 'output_file');  cfg.output_file = fullfile(data_gru_dir, 'GRU_dataset_processed.mat');    end
if ~isfield(cfg, 'scaler_file');  cfg.scaler_file = fullfile(data_gru_dir, 'GRU_scaler.mat');               end
if ~isfield(cfg, 'save_split_file'); cfg.save_split_file = true; end
if ~isfield(cfg, 'split_file'); cfg.split_file = fullfile(data_gru_dir, 'GRU_run_split.mat'); end
if ~isfield(cfg, 'split_policy'); cfg.split_policy = 'windowed_runs_only'; end  % 'windowed_runs_only'|'mamba_like'
if ~isfield(cfg, 'enable_train_resampling'); cfg.enable_train_resampling = true; end
if ~isfield(cfg, 'resample_stall_multiplier'); cfg.resample_stall_multiplier = 2.5; end
if ~isfield(cfg, 'resample_stall_target_min'); cfg.resample_stall_target_min = 0; end
if ~isfield(cfg, 'resample_flat_max_ratio'); cfg.resample_flat_max_ratio = 3.0; end
if ~isfield(cfg, 'verbose');      cfg.verbose     = true;                                                    end

%
% 使用方法：
%   直接运行此脚本：run('GRU_prepare_dataset.m') 或 GRU_prepare_dataset
%   修改下方"配置区域"来调整参数
%
% 输出：
%   - dataset: 处理后的数据集，保存至 cfg.output_file
%       .X_train/val/test: [N, seq_len, 22]
%       .y_main_train/val/test: [N,1]∈{1,2,3}
%       .y_turn_train/val/test: [N,1]∈{-1,0,+1}
%       .y_theta_train/val/test: [N,1] [rad]
%       .mask_theta_train/val/test: [N,1] (slope样本=1)
%       .scaler: 归一化统计量（mean, std）
%       .feat_names: 特征名称列表
%       .meta: 元数据
%
% 依赖：
%   - GRU_train_data_full.mat（由 GRU_gen_train_data.m 生成）
%   - parameters.m
%
% 备注：
%   - 特征仅使用允许的轮速/电流/转角/yaw-rate 通道和简单派生
%   - 禁止使用诊断/估计量（如slip_flag, stall_flag等）
%   - theta_ground仅作为监督标签，不作为输入特征
% =============================

%% ==================== 配置区域（用户可修改） ====================
if ~isfield(cfg, 'seq_len'); cfg.seq_len = 128; end                % 序列长度（≈1.28s @ Ts=0.01s，与 Mamba 对齐）
if ~isfield(cfg, 'stride'); cfg.stride = 64; end                   % 滑窗步长（50%重叠，与 Mamba 对齐）
if ~isfield(cfg, 'skip_initial_sec'); cfg.skip_initial_sec = 10.0; end      % 前10s启动区不用于切片（与 industrial_lite 黄金测试区起点对齐）
% V2.0: seq_len/stride 与 Mamba 的 window_size/stride 保持一致
if ~isfield(cfg, 'output_file'); cfg.output_file = fullfile(data_gru_dir, 'GRU_dataset_processed.mat'); end      % 输出数据文件
if ~isfield(cfg, 'scaler_file'); cfg.scaler_file = fullfile(data_gru_dir, 'GRU_scaler.mat'); end                % 归一化参数文件

% 数据分割比例
if ~isfield(cfg, 'train_ratio'); cfg.train_ratio = 0.7; end            % 训练集比例
if ~isfield(cfg, 'val_ratio'); cfg.val_ratio = 0.15; end             % 验证集比例
if ~isfield(cfg, 'test_ratio'); cfg.test_ratio = 0.15; end            % 测试集比例

% 派生特征参数
if ~isfield(cfg, 'tau_accel_lp'); cfg.tau_accel_lp = 0.4; end           % 加速度低通滤波时间常数 [s]
if ~isfield(cfg, 'tau_diff'); cfg.tau_diff = 0.3; end               % 速度差分滤波时间常数 [s]（用于 dv_hat_dt）

% 随机种子（用于可复现的数据分割）
if ~isfield(cfg, 'seed'); cfg.seed = 42; end

% 调试选项
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end               % 是否打印详细信息
if ~isfield(cfg, 'save_intermediate'); cfg.save_intermediate = false; end    % 是否保存中间结果

%% ==================== 主程序（自动执行） ====================

if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('GRU数据预处理开始\n');
    fprintf('========================================\n');
end

%% 1. 加载原始数据
if cfg.verbose
    fprintf('\n[步骤1/5] 加载原始数据...\n');
    fprintf('  数据来源策略: %s\n', cfg.dataset_source);
    fprintf('  输入文件: %s\n', cfg.input_file);
end

if ~exist(cfg.input_file, 'file')
    error('输入文件不存在: %s', cfg.input_file);
end

load(cfg.input_file, 'data');  % 加载 data 结构体
dataset_source_used = detect_dataset_source(data, cfg.input_file);

if cfg.verbose
    fprintf('  ✓ 加载成功！共 %d 个回合\n', length(data.runs));
    fprintf('  ✓ 识别数据来源: %s\n', dataset_source_used);
end

% 加载参数（用于获取常量）
params = parameters();

% V2.0: Ts 从数据元信息读取（确保与数据生成时的采样周期一致）
if isfield(data.meta, 'Ts')
    Ts = data.meta.Ts;
else
    Ts = params.Ts;
    warning('数据元信息中未找到 Ts，使用 parameters() 中的值: %.4f', Ts);
end
fprintf('  采样周期 Ts = %.4f s（来源: 数据元信息）\n', Ts);

% 提取滤波时间常数
tau_accel_lp = cfg.tau_accel_lp;
tau_diff = cfg.tau_diff;
feature_cfg = struct('tau_diff', tau_diff, 'tau_accel_lp', tau_accel_lp);

%% 2. 提取特征并计算派生特征
if cfg.verbose
    fprintf('\n[步骤2/5] 提取特征并计算派生特征...\n');
end

% 遍历所有回合，提取特征（V1.2: 记录run_id用于按回合分组）
all_features = [];
all_label_main = [];
all_label_turn = [];
all_theta = [];
all_run_id = [];  % V1.2: 记录每个样本来自哪个回合
run_segments = zeros(0, 3);  % [seg_start, seg_end, run_id]
theta_source_counter = struct('y_theta_ground', 0, 'theta', 0, 'y_raw16', 0);

for k = 1:length(data.runs)
    run_data = data.runs(k);
    
    % 提取原始传感量（y_raw）
    y_raw = run_data.y_raw;
    if size(y_raw, 2) < 18
        error('第%d回合 y_raw 列数不足: 至少需要18列，实际为%d列', k, size(y_raw, 2));
    end
    N = size(y_raw, 1);
    % 跳过前 skip_initial_sec 秒的平地段，再做滑窗切片
    skip_steps = min(N, max(0, ceil(cfg.skip_initial_sec / Ts)));
    idx_keep = (skip_steps + 1):N;
    if isempty(idx_keep)
        continue;
    end
    y_raw = y_raw(idx_keep, :);
    label_main_run = run_data.label_main(idx_keep);
    label_turn_run = run_data.label_turn(idx_keep);
    [theta_run, theta_source_name] = select_theta_target(run_data, idx_keep, k);
    theta_source_counter.(theta_source_name) = theta_source_counter.(theta_source_name) + numel(theta_run);
    N = size(y_raw, 1);
    
    features = extract_passive_features('batch', y_raw, params, Ts, feature_cfg);
    
    % 累积到全局（V1.2: 同时记录run_id）
    seg_start = size(all_features, 1) + 1;
    all_features = [all_features; features]; %#ok<AGROW>
    all_label_main = [all_label_main; label_main_run]; %#ok<AGROW>
    all_label_turn = [all_label_turn; label_turn_run]; %#ok<AGROW>
    all_theta = [all_theta; theta_run]; %#ok<AGROW>
    all_run_id = [all_run_id; k * ones(N, 1)]; %#ok<AGROW>  % V1.2: 记录回合编号
    seg_end = size(all_features, 1);
    run_segments = [run_segments; seg_start, seg_end, k]; %#ok<AGROW>
end

if isempty(all_features)
    error('未提取到有效特征样本，请检查输入数据/skip_initial_sec/标签字段。');
end

feat_names = extract_passive_features('names');

if cfg.verbose
    fprintf('  ✓ 特征提取完成！\n');
    fprintf('    总样本数: %d\n', size(all_features, 1));
    fprintf('    特征维度: %d\n', size(all_features, 2));
    fprintf('    特征列表: %s\n', strjoin(feat_names, ', '));
end

%% 3. 滑窗切片
if cfg.verbose
    fprintf('\n[步骤3/5] 滑窗切片...\n');
    fprintf('  序列长度: %d (≈%.2f s)\n', cfg.seq_len, cfg.seq_len * Ts);
    fprintf('  滑窗步长: %d\n', cfg.stride);
end

% 计算切片数量（仅在同一回合内切片，避免跨回合窗口）
N_slices = 0;
for rr = 1:size(run_segments, 1)
    run_len = run_segments(rr, 2) - run_segments(rr, 1) + 1;
    n_win = floor((run_len - cfg.seq_len) / cfg.stride) + 1;
    if n_win > 0
        N_slices = N_slices + n_win;
    end
end

if N_slices <= 0
    error('有效切片数为 0，请检查 seq_len/stride/skip_initial_sec 与数据长度。');
end

% 预分配（V1.2: 增加run_id记录）
feat_dim = size(all_features, 2);
X_all = zeros(N_slices, cfg.seq_len, feat_dim);
y_main_all = zeros(N_slices, 1);
y_turn_all = zeros(N_slices, 1);
y_theta_all = zeros(N_slices, 1);
run_id_all = zeros(N_slices, 1);  % V1.2: 记录每个切片来自哪个回合

% 滑窗切片（逐回合）
slice_idx = 0;
for rr = 1:size(run_segments, 1)
    seg_start = run_segments(rr, 1);
    seg_end = run_segments(rr, 2);
    rid = run_segments(rr, 3);
    run_len = seg_end - seg_start + 1;
    if run_len < cfg.seq_len
        continue;
    end

    for local_start = 1:cfg.stride:(run_len - cfg.seq_len + 1)
        slice_idx = slice_idx + 1;
        start_idx = seg_start + local_start - 1;
        end_idx = start_idx + cfg.seq_len - 1;

        % 提取序列
        X_all(slice_idx, :, :) = all_features(start_idx:end_idx, :);

        % 标签取序列末尾时刻（预测当前状态）
        y_main_all(slice_idx) = all_label_main(end_idx);
        y_turn_all(slice_idx) = all_label_turn(end_idx);
        y_theta_all(slice_idx) = all_theta(end_idx);
        run_id_all(slice_idx) = rid;
    end
end

if slice_idx < N_slices
    X_all = X_all(1:slice_idx, :, :);
    y_main_all = y_main_all(1:slice_idx);
    y_turn_all = y_turn_all(1:slice_idx);
    y_theta_all = y_theta_all(1:slice_idx);
    run_id_all = run_id_all(1:slice_idx);
    N_slices = slice_idx;
end

% 生成 mask_theta（仅 slope 样本为1）
mask_theta_all = double(y_main_all == 3);  % V1.7: slope 的类别编号为 3

if cfg.verbose
    fprintf('  ✓ 切片完成！\n');
    fprintf('    切片总数: %d\n', N_slices);
    fprintf('    数据形状: [%d, %d, %d]\n', size(X_all));
    fprintf('  [V2.1] 切片策略: 仅在同一回合内滑窗（无跨回合窗口）\n');
end

%% 4. 数据分割（按回合分组，防止数据泄漏，V1.2优化）
if cfg.verbose
    fprintf('\n[步骤4/5] 数据分割（按回合分组）...\n');
    fprintf('  训练集: %.0f%%, 验证集: %.0f%%, 测试集: %.0f%%\n', ...
        cfg.train_ratio*100, cfg.val_ratio*100, cfg.test_ratio*100);
    fprintf('  Run 划分策略: %s\n', cfg.split_policy);
end

% 固定随机种子
rng(cfg.seed);

% V1.2: 按回合分组分割（防止同一回合的相邻切片被分到不同集合）
% 说明：
%   - windowed_runs_only: 仅对“产生了有效切片的回合”做划分（历史默认行为）
%   - mamba_like: 对 1..N_runs 全体回合做划分，以复现 Mamba 导出脚本的 run-level split
num_runs_total = length(data.runs);
if ischar(cfg.split_policy) || isstring(cfg.split_policy)
    split_policy = char(cfg.split_policy);
else
    split_policy = 'windowed_runs_only';
end

if strcmpi(split_policy, 'mamba_like')
    unique_runs = (1:num_runs_total)';
else
    unique_runs = unique(run_id_all);  % 获取所有回合编号（仅含有窗口的回合）
end
num_runs = length(unique_runs);

% 随机打乱回合顺序
run_perm = unique_runs(randperm(num_runs));

% 计算每组的回合数
n_runs_train = floor(num_runs * cfg.train_ratio);
n_runs_val = floor(num_runs * cfg.val_ratio);
n_runs_test = num_runs - n_runs_train - n_runs_val;

% 分配回合到各集合
runs_train = run_perm(1:n_runs_train);
runs_val = run_perm(n_runs_train+1:n_runs_train+n_runs_val);
runs_test = run_perm(n_runs_train+n_runs_val+1:end);

% 可选：保存 run 级切分索引，便于与 Mamba 训练共享同一划分
if cfg.save_split_file
    split_dir = fileparts(cfg.split_file);
    if ~isempty(split_dir) && ~exist(split_dir, 'dir')
        mkdir(split_dir);
    end
    split_info = struct();
    split_info.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    split_info.source_file = cfg.input_file;
    split_info.dataset_source = dataset_source_used;
    split_info.seed = cfg.seed;
    split_info.train_ratio = cfg.train_ratio;
    split_info.val_ratio = cfg.val_ratio;
    split_info.test_ratio = cfg.test_ratio;
    split_info.runs_train = runs_train;
    split_info.runs_val = runs_val;
    split_info.runs_test = runs_test;
    split_info.seq_len = cfg.seq_len;
    split_info.stride = cfg.stride;
    split_info.skip_initial_sec = cfg.skip_initial_sec;
    save(cfg.split_file, 'split_info');
end

% 根据回合归属，分配切片索引
idx_train = find(ismember(run_id_all, runs_train));
idx_val = find(ismember(run_id_all, runs_val));
idx_test = find(ismember(run_id_all, runs_test));

% 在各组内随机打乱（可选，保持多样性）
idx_train = idx_train(randperm(length(idx_train)));
idx_val = idx_val(randperm(length(idx_val)));
idx_test = idx_test(randperm(length(idx_test)));

% 统计实际分割比例
n_train = length(idx_train);
n_val = length(idx_val);
n_test = length(idx_test);

% 分割数据
X_train = X_all(idx_train, :, :);
X_val = X_all(idx_val, :, :);
X_test = X_all(idx_test, :, :);

y_main_train = y_main_all(idx_train);
y_main_val = y_main_all(idx_val);
y_main_test = y_main_all(idx_test);

y_turn_train = y_turn_all(idx_train);
y_turn_val = y_turn_all(idx_val);
y_turn_test = y_turn_all(idx_test);

y_theta_train = y_theta_all(idx_train);
y_theta_val = y_theta_all(idx_val);
y_theta_test = y_theta_all(idx_test);

mask_theta_train = mask_theta_all(idx_train);
mask_theta_val = mask_theta_all(idx_val);
mask_theta_test = mask_theta_all(idx_test);

if cfg.verbose
    fprintf('  ✓ 分割完成！\n');
    fprintf('    训练集: %d 样本（来自 %d 个回合，%.1f%%）\n', n_train, n_runs_train, 100*n_train/max(N_slices,1));
    fprintf('    验证集: %d 样本（来自 %d 个回合，%.1f%%）\n', n_val, n_runs_val, 100*n_val/max(N_slices,1));
    fprintf('    测试集: %d 样本（来自 %d 个回合，%.1f%%）\n', n_test, n_runs_test, 100*n_test/max(N_slices,1));
    fprintf('  [V1.2] 采用按回合分组策略，防止数据泄漏\n');
    if cfg.save_split_file
        fprintf('  ✓ 已保存 run 划分文件: %s\n', cfg.split_file);
    end
end

%% 5. 数据归一化（z-score，仅用训练集统计）
if cfg.verbose
    fprintf('\n[步骤5/5] 数据归一化（z-score）...\n');
end

% 将训练集reshape为 [n_train*seq_len, feat_dim]
X_train_flat = reshape(X_train, [], feat_dim);

% 计算训练集的均值和标准差
scaler.mean = mean(X_train_flat, 1);  % [1 × feat_dim]
scaler.std = std(X_train_flat, 0, 1); % [1 × feat_dim]

% 避免除零（对于常数特征）
scaler.std(scaler.std < 1e-8) = 1.0;
scaler.tau_accel_lp = tau_accel_lp;  % 记录滤波参数，确保在线/离线一致
scaler.tau_diff = tau_diff;
feature_contract = extract_passive_features('contract');
scaler.feature_contract = feature_contract.feature_contract;
scaler.feature_names = feature_contract.feature_names;

% 归一化函数
normalize_fn = @(X) (X - reshape(scaler.mean, 1, 1, [])) ./ reshape(scaler.std, 1, 1, []);

% 应用归一化（对所有集合）
X_train_norm = normalize_fn(X_train);
X_val_norm = normalize_fn(X_val);
X_test_norm = normalize_fn(X_test);

if cfg.verbose
    fprintf('  ✓ 归一化完成！\n');
    fprintf('    均值范围: [%.4f, %.4f]\n', min(scaler.mean), max(scaler.mean));
    fprintf('    标准差范围: [%.4f, %.4f]\n', min(scaler.std), max(scaler.std));
end

%% 6. 统计与验证（V1.4: 增强统计输出）
if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('数据集统计信息\n');
    fprintf('========================================\n');
    
    % 主分类标签分布
    fprintf('\n[主分类标签分布]\n');
    fprintf('  训练集:\n');
    print_label_dist(y_main_train, {'flat', 'stall', 'slope'});
    fprintf('  验证集:\n');
    print_label_dist(y_main_val, {'flat', 'stall', 'slope'});
    fprintf('  测试集:\n');
    print_label_dist(y_main_test, {'flat', 'stall', 'slope'});
    
    % 转弯标签分布
    fprintf('\n[转弯状态标签分布]\n');
    fprintf('  训练集:\n');
    print_turn_label_dist(y_turn_train);
    fprintf('  验证集:\n');
    print_turn_label_dist(y_turn_val);
    fprintf('  测试集:\n');
    print_turn_label_dist(y_turn_test);
    
    % 坡度角统计（仅slope样本）
    fprintf('\n[坡度角统计（仅slope样本）]\n');
    theta_train_slope = y_theta_train(mask_theta_train == 1);
    theta_val_slope = y_theta_val(mask_theta_val == 1);
    theta_test_slope = y_theta_test(mask_theta_test == 1);
    
    fprintf('  训练集: N=%d, 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        sum(mask_theta_train), rad2deg(min(theta_train_slope)), rad2deg(max(theta_train_slope)), ...
        rad2deg(mean(theta_train_slope)), 100*sum(theta_train_slope>0)/max(sum(mask_theta_train),1));
    fprintf('  验证集: N=%d, 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        sum(mask_theta_val), rad2deg(min(theta_val_slope)), rad2deg(max(theta_val_slope)), ...
        rad2deg(mean(theta_val_slope)), 100*sum(theta_val_slope>0)/max(sum(mask_theta_val),1));
    fprintf('  测试集: N=%d, 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        sum(mask_theta_test), rad2deg(min(theta_test_slope)), rad2deg(max(theta_test_slope)), ...
        rad2deg(mean(theta_test_slope)), 100*sum(theta_test_slope>0)/max(sum(mask_theta_test),1));
    
    % 全局theta统计（包括所有样本）
    fprintf('\n[全局坡度角统计（所有样本）]\n');
    fprintf('  训练集: 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        rad2deg(min(y_theta_train)), rad2deg(max(y_theta_train)), ...
        rad2deg(mean(y_theta_train)), 100*sum(y_theta_train>0)/length(y_theta_train));
    fprintf('  验证集: 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        rad2deg(min(y_theta_val)), rad2deg(max(y_theta_val)), ...
        rad2deg(mean(y_theta_val)), 100*sum(y_theta_val>0)/length(y_theta_val));
    fprintf('  测试集: 范围=[%.2f, %.2f]°, 均值=%.2f°, 正值比例=%.1f%%\n', ...
        rad2deg(min(y_theta_test)), rad2deg(max(y_theta_test)), ...
        rad2deg(mean(y_theta_test)), 100*sum(y_theta_test>0)/length(y_theta_test));
    
    % V1.4: 场景分布统计（已禁用 - 原始数据未保存场景信息）
    % fprintf('\n[场景分布统计（基于原始数据回合元信息）]\n');
    % print_scene_distribution(data, runs_train, runs_val, runs_test);
    % 注：原始训练数据未保存 meta.scene 字段，跳过此统计
    
    % V1.4: 新增统计 - slip/stall 时间窗口分布
    fprintf('\n[打滑/堵转时间窗口统计]\n');
    print_injection_time_stats(data, runs_train, runs_val, runs_test);
    
    % V1.4: 新增统计 - slip/stall 强度范围
    fprintf('\n[打滑/堵转强度范围统计]\n');
    print_injection_intensity_stats(data, runs_train, runs_val, runs_test);
    
    % V1.4: 新增统计 - 速度与角速度范围
    fprintf('\n[速度与角速度范围统计]\n');
    print_velocity_stats(data, runs_train, runs_val, runs_test);
    
    % V1.4: 新增统计 - 类别不平衡指标
    fprintf('\n[类别不平衡指标（训练集）]\n');
    print_imbalance_metrics(y_main_train, {'flat', 'stall', 'slope'});
    
    % V1.4: 新增统计 - 样本持续时间
    fprintf('\n[样本持续时间统计（训练集）]\n');
    print_duration_stats(y_main_train, Ts, cfg.stride);
end

%% [附加步骤] 训练集类别重采样（简化版）
% V1.7: 移除 slip，仅过采样 stall

if cfg.enable_train_resampling
    resample_cfg.target_multiplier = struct('stall', cfg.resample_stall_multiplier);  % 仅过采样 stall
    resample_cfg.stall_target_min = cfg.resample_stall_target_min;
    resample_cfg.flat_max_ratio = cfg.resample_flat_max_ratio;

    if cfg.verbose
        fprintf('\n[附加步骤] 训练集类别重采样（stall 过采样 + flat 欠采样）...\n');
        fprintf('  配置: stall_multiplier=%.2f, stall_target_min=%d, flat_max_ratio=%.2f\n', ...
            resample_cfg.target_multiplier.stall, resample_cfg.stall_target_min, resample_cfg.flat_max_ratio);
    end

    % 打印重采样前分布
    if cfg.verbose
        print_label_dist(y_main_train, {'flat', 'stall', 'slope'});
    end

    % ===== 过采样 stall =====
    oversample_plan = [2, resample_cfg.target_multiplier.stall];  % stall 的标签为 2

    for iPlan = 1:size(oversample_plan,1)
        class_label = oversample_plan(iPlan,1);
        multiplier = oversample_plan(iPlan,2);
        idx_class = find(y_main_train == class_label);
        n_class = numel(idx_class);
        target = max(round(multiplier * n_class), resample_cfg.stall_target_min);
        if n_class == 0 || target <= n_class
            continue;
        end
        rep_needed = target - n_class;
        rep_idx = randi(n_class, rep_needed, 1);
        sel = idx_class(rep_idx);

        % 记录放回采样情况
        [unique_sel, ~, ic] = unique(sel);
        dup_counts = accumarray(ic, 1);
        reused_samples = sum(dup_counts > 1);
        max_reuse = max(dup_counts);

        % 执行过采样
        X_train_norm     = cat(1, X_train_norm,     X_train_norm(sel,:,:));
        y_main_train     = cat(1, y_main_train,     y_main_train(sel,:));
        y_turn_train     = cat(1, y_turn_train,     y_turn_train(sel,:));
        y_theta_train    = cat(1, y_theta_train,    y_theta_train(sel,:));
        mask_theta_train = cat(1, mask_theta_train, mask_theta_train(sel,:));

        if cfg.verbose
            class_name = {'flat','stall','slope'};
            fprintf('  %s 过采样: 原始=%d, 目标≈%d, 实际=%d\n', ...
                class_name{class_label}, n_class, target, sum(y_main_train==class_label));
            fprintf('    放回采样情况: 去重后样本=%d, 被重复采样=%d, 最大重复次数=%d\n', ...
                numel(unique_sel), reused_samples, max_reuse);
        end
    end

    % ===== flat 欠采样（限制为 3× 少数类） =====
    counts_after = arrayfun(@(lbl) sum(y_main_train == lbl), 1:3);  % V1.7: 3 类
    minor_counts = counts_after([2,3]);  % stall, slope
    minor_counts = minor_counts(minor_counts > 0);
    if ~isempty(minor_counts)
        min_minor = min(minor_counts);
        flat_limit = round(resample_cfg.flat_max_ratio * min_minor);
        flat_idx = find(y_main_train == 1);
        if numel(flat_idx) > flat_limit
            perm = flat_idx(randperm(numel(flat_idx)));
            keep_flat = perm(1:flat_limit);
            drop_flat = perm(flat_limit+1:end);
            keep_mask = true(size(y_main_train));
            keep_mask(drop_flat) = false;

            X_train_norm     = X_train_norm(keep_mask,:,:);
            y_main_train     = y_main_train(keep_mask,:);
            y_turn_train     = y_turn_train(keep_mask,:);
            y_theta_train    = y_theta_train(keep_mask,:);
            mask_theta_train = mask_theta_train(keep_mask,:);

            if cfg.verbose
                fprintf('  flat 欠采样: 原始=%d, 目标上限=%d, 实际=%d\n', ...
                    numel(flat_idx), flat_limit, sum(y_main_train==1));
            end
        else
            if cfg.verbose
                fprintf('  flat 样本无需欠采样: 当前=%d, 阈值=%d\n', numel(flat_idx), flat_limit);
            end
        end
    else
        if cfg.verbose
            fprintf('  警告：少数类计数为空，跳过 flat 欠采样\n');
        end
    end

    n_train = size(X_train_norm, 1);

    if cfg.verbose
        fprintf('  重采样后训练集分布:\n');
        print_label_dist(y_main_train, {'flat', 'stall', 'slope'});
    end
else
    if cfg.verbose
        fprintf('\n[附加步骤] 已关闭训练集类别重采样（enable_train_resampling=false）\n');
    end
end

%% 7. 保存处理后的数据集
if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('保存处理后的数据集\n');
    fprintf('========================================\n');
end

% 构建数据集结构体
dataset = struct();

% 训练集
dataset.X_train = X_train_norm;
dataset.y_main_train = y_main_train;
dataset.y_turn_train = y_turn_train;
dataset.y_theta_train = y_theta_train;
dataset.mask_theta_train = mask_theta_train;

% 验证集
dataset.X_val = X_val_norm;
dataset.y_main_val = y_main_val;
dataset.y_turn_val = y_turn_val;
dataset.y_theta_val = y_theta_val;
dataset.mask_theta_val = mask_theta_val;

% 测试集
dataset.X_test = X_test_norm;
dataset.y_main_test = y_main_test;
dataset.y_turn_test = y_turn_test;
dataset.y_theta_test = y_theta_test;
dataset.mask_theta_test = mask_theta_test;

% 归一化参数
dataset.scaler = scaler;

% 特征名称
dataset.feat_names = feat_names;

% 元数据
dataset.meta.generation_time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
dataset.meta.version = 'V1.4';
dataset.meta.author = 'LPV-MPC Project';
dataset.meta.input_file = cfg.input_file;
dataset.meta.dataset_source = dataset_source_used;
dataset.meta.theta_source_counter = theta_source_counter;
dataset.meta.seq_len = cfg.seq_len;
dataset.meta.stride = cfg.stride;
dataset.meta.skip_initial_sec = cfg.skip_initial_sec;
dataset.meta.window_policy = 'within_run_only';
dataset.meta.Ts = Ts;
dataset.meta.split_strategy = 'run_grouped';  % V1.2: 按回合分组，防止数据泄漏
dataset.meta.split_policy = split_policy;
dataset.meta.num_runs_total = num_runs;      % V1.2: 总回合数
dataset.meta.num_runs_train = n_runs_train;  % V1.2: 训练集回合数
dataset.meta.num_runs_val = n_runs_val;      % V1.2: 验证集回合数
dataset.meta.num_runs_test = n_runs_test;    % V1.2: 测试集回合数
dataset.meta.feat_dim = feat_dim;
dataset.meta.y_raw_dim = size(data.runs(1).y_raw, 2);
dataset.meta.train_ratio = cfg.train_ratio;
dataset.meta.val_ratio = cfg.val_ratio;
dataset.meta.test_ratio = cfg.test_ratio;
dataset.meta.seed = cfg.seed;
dataset.meta.n_train = n_train;
dataset.meta.n_val = n_val;
dataset.meta.n_test = n_test;
dataset.meta.tau_accel_lp = tau_accel_lp;  % V1.1: 记录滤波时间常数
dataset.meta.tau_diff = tau_diff;          % V1.1: 记录差分滤波时间常数
dataset.meta.feature_contract = scaler.feature_contract;
dataset.meta.feature_policy = 'imu_free_passive17_plus_all5';
dataset.meta.input_dim = feat_dim;
dataset.meta.no_new_inputs = true;
dataset.meta.enable_train_resampling = cfg.enable_train_resampling;
dataset.meta.resample_stall_multiplier = cfg.resample_stall_multiplier;
dataset.meta.resample_stall_target_min = cfg.resample_stall_target_min;
dataset.meta.resample_flat_max_ratio = cfg.resample_flat_max_ratio;
if cfg.save_split_file
    dataset.meta.split_file = cfg.split_file;
end

% 保存到文件
if cfg.verbose
    fprintf('  正在保存到: %s\n', cfg.output_file);
end
save(cfg.output_file, 'dataset', '-v7.3');

% 单独保存 scaler（便于部署）
if cfg.verbose
    fprintf('  正在保存到: %s\n', cfg.scaler_file);
end
scaler_data = struct('scaler', scaler, 'feat_names', {feat_names}, ...
                     'seq_len', cfg.seq_len, 'Ts', Ts, ...
                     'tau_accel_lp', tau_accel_lp, 'tau_diff', tau_diff, ...
                     'feature_contract', scaler.feature_contract);  % V1.1: 增加滤波参数
save(cfg.scaler_file, '-struct', 'scaler_data');

if cfg.verbose
    fprintf('  ✓ 保存成功！\n');
    fprintf('\n========================================\n');
    fprintf('数据预处理完成！\n');
    fprintf('========================================\n');
    fprintf('输出文件:\n');
    fprintf('  - %s (完整数据集)\n', cfg.output_file);
    fprintf('  - %s (归一化参数)\n', cfg.scaler_file);
    fprintf('\n可用于训练的数据:\n');
    fprintf('  - X_train: [%d, %d, %d]\n', size(X_train_norm));
    fprintf('  - y_main_train: [%d, 1] ∈ {1,2,3}\n', length(y_main_train));
    fprintf('  - y_turn_train: [%d, 1] ∈ {-1,0,+1}\n', length(y_turn_train));
    fprintf('  - y_theta_train: [%d, 1] [rad]\n', length(y_theta_train));
end

%% ========== 辅助函数 ==========

function print_label_dist(labels, label_names)
% 打印主分类标签分布（1,2,3,4）
    unique_labels = unique(labels);
    for i = 1:length(unique_labels)
        lbl = unique_labels(i);
        count = sum(labels == lbl);
        ratio = count / length(labels) * 100;
        
        % 主分类标签：1,2,3,4 → 直接索引
        if lbl >= 1 && lbl <= length(label_names)
            name = label_names{lbl};
        else
            name = sprintf('未知(%d)', lbl);
        end
        
        fprintf('    %s: %d (%.1f%%)\n', name, count, ratio);
    end
end

function print_turn_label_dist(labels)
% 打印转弯状态标签分布（-1,0,+1）
    unique_labels = unique(labels);
    for i = 1:length(unique_labels)
        lbl = unique_labels(i);
        count = sum(labels == lbl);
        ratio = count / length(labels) * 100;
        
        % 转弯标签映射
        if lbl == -1
            name = 'right(-1)';
        elseif lbl == 0
            name = 'straight(0)';
        elseif lbl == 1
            name = 'left(+1)';
        else
            name = sprintf('未知(%d)', lbl);
        end
        
        fprintf('    %s: %d (%.1f%%)\n', name, count, ratio);
    end
end

%% V1.4: 新增辅助统计函数

% function print_scene_distribution(data, runs_train, runs_val, runs_test)
% % V1.4: 已禁用 - 统计各场景（straight/turn/slope/bumpy）的回合数分布
% % 原因：原始训练数据未保存 meta.scene 字段
%     scenes_all = {data.runs.meta};
%     scene_names_train = cellfun(@(x) x.scene, scenes_all(runs_train), 'UniformOutput', false);
%     scene_names_val = cellfun(@(x) x.scene, scenes_all(runs_val), 'UniformOutput', false);
%     scene_names_test = cellfun(@(x) x.scene, scenes_all(runs_test), 'UniformOutput', false);
%     
%     fprintf('  训练集回合: ');
%     print_scene_counts(scene_names_train);
%     fprintf('  验证集回合: ');
%     print_scene_counts(scene_names_val);
%     fprintf('  测试集回合: ');
%     print_scene_counts(scene_names_test);
% end
% 
% function print_scene_counts(scene_names)
% % 统计场景名称出现次数
%     unique_scenes = unique(scene_names);
%     counts = cellfun(@(s) sum(strcmp(scene_names, s)), unique_scenes);
%     [~, idx_sort] = sort(counts, 'descend');
%     
%     parts = {};
%     for i = 1:length(idx_sort)
%         parts{end+1} = sprintf('%s=%d', unique_scenes{idx_sort(i)}, counts(idx_sort(i)));
%     end
%     fprintf('%s\n', strjoin(parts, ', '));
% end

function print_injection_time_stats(data, runs_train, runs_val, runs_test)
% 统计 slip/stall 的注入时间窗口分布（验证是否 >5s）
    slip_times_train = [];
    stall_times_train = [];
    slip_times_val = [];
    stall_times_val = [];
    slip_times_test = [];
    stall_times_test = [];
    
    % 训练集
    for k = runs_train'
        meta = data.runs(k).meta;
        if isfield(meta, 'inject_info')
            inj = meta.inject_info;
            if isfield(inj, 'slip_window') && ~isempty(inj.slip_window)
                slip_times_train = [slip_times_train; inj.slip_window(1)]; %#ok<AGROW>
            end
            if isfield(inj, 'stall_window') && ~isempty(inj.stall_window)
                stall_times_train = [stall_times_train; inj.stall_window(1)]; %#ok<AGROW>
            end
        end
    end
    
    % 验证集
    for k = runs_val'
        meta = data.runs(k).meta;
        if isfield(meta, 'inject_info')
            inj = meta.inject_info;
            if isfield(inj, 'slip_window') && ~isempty(inj.slip_window)
                slip_times_val = [slip_times_val; inj.slip_window(1)]; %#ok<AGROW>
            end
            if isfield(inj, 'stall_window') && ~isempty(inj.stall_window)
                stall_times_val = [stall_times_val; inj.stall_window(1)]; %#ok<AGROW>
            end
        end
    end
    
    % 测试集
    for k = runs_test'
        meta = data.runs(k).meta;
        if isfield(meta, 'inject_info')
            inj = meta.inject_info;
            if isfield(inj, 'slip_window') && ~isempty(inj.slip_window)
                slip_times_test = [slip_times_test; inj.slip_window(1)]; %#ok<AGROW>
            end
            if isfield(inj, 'stall_window') && ~isempty(inj.stall_window)
                stall_times_test = [stall_times_test; inj.stall_window(1)]; %#ok<AGROW>
            end
        end
    end
    
    % 打印统计
    if ~isempty(slip_times_train)
        slip_min = min(slip_times_train);
        slip_max = max(slip_times_train);
        slip_mean = mean(slip_times_train);
    else
        slip_min = inf; slip_max = -inf; slip_mean = 0;
    end
    if ~isempty(stall_times_train)
        stall_min = min(stall_times_train);
        stall_max = max(stall_times_train);
        stall_mean = mean(stall_times_train);
    else
        stall_min = inf; stall_max = -inf; stall_mean = 0;
    end
    
    fprintf('  打滑开始时间（训练集）: N=%d, 范围=[%.1f, %.1f]s, 均值=%.1f s, <5s样本=%d (%.1f%%)\n', ...
        length(slip_times_train), slip_min, slip_max, ...
        slip_mean, sum(slip_times_train < 5), 100*sum(slip_times_train<5)/max(length(slip_times_train),1));
    fprintf('  堵转开始时间（训练集）: N=%d, 范围=[%.1f, %.1f]s, 均值=%.1f s, <5s样本=%d (%.1f%%)\n', ...
        length(stall_times_train), stall_min, stall_max, ...
        stall_mean, sum(stall_times_train < 5), 100*sum(stall_times_train<5)/max(length(stall_times_train),1));
end

function print_injection_intensity_stats(data, runs_train, ~, ~)
% 统计 slip gamma 和 stall load 的范围（从 meta.inject_info 中读取）
    slip_gamma = [];
    stall_load = [];
    
    for k = runs_train'
        meta = data.runs(k).meta;
        if isfield(meta, 'inject_info')
            inj = meta.inject_info;
            if isfield(inj, 'slip_gamma') && ~isempty(inj.slip_gamma)
                slip_gamma = [slip_gamma; inj.slip_gamma]; %#ok<AGROW>
            end
            if isfield(inj, 'stall_load') && ~isempty(inj.stall_load)
                stall_load = [stall_load; inj.stall_load]; %#ok<AGROW>
            end
        end
    end
    
    if ~isempty(slip_gamma)
        fprintf('  打滑牵引系数 gamma（训练集）: N=%d, 范围=[%.2f, %.2f], 均值=%.2f\n', ...
            length(slip_gamma), min(slip_gamma), max(slip_gamma), mean(slip_gamma));
    else
        fprintf('  打滑牵引系数 gamma（训练集）: 无打滑样本\n');
    end
    
    if ~isempty(stall_load)
        fprintf('  堵转负载 load（训练集）: N=%d, 范围=[%.1f, %.1f] N, 均值=%.1f N\n', ...
            length(stall_load), min(stall_load), max(stall_load), mean(stall_load));
    else
        fprintf('  堵转负载 load（训练集）: 无堵转样本\n');
    end
end

function print_velocity_stats(data, runs_train, ~, ~)
% 统计控制输入 u 的范围（注意：这是控制量，不是直接的物理参考速度）
    u1_all = [];
    u2_all = [];
    
    for k = runs_train'
        if isfield(data.runs(k), 'u') && ~isempty(data.runs(k).u)
            u1_all = [u1_all; data.runs(k).u(:, 1)]; %#ok<AGROW>
            u2_all = [u2_all; data.runs(k).u(:, 2)]; %#ok<AGROW>
        end
    end
    
    if ~isempty(u1_all)
        fprintf('  控制输入 u(:,1)（训练集）: 范围=[%.2f, %.2f], 均值=%.2f\n', ...
            min(u1_all), max(u1_all), mean(u1_all));
        fprintf('  控制输入 u(:,2)（训练集）: 范围=[%.3f, %.3f], 均值=%.3f\n', ...
            min(u2_all), max(u2_all), mean(u2_all));
    else
        fprintf('  无控制输入 u 数据\n');
    end
end

function print_imbalance_metrics(labels, label_names)
% 计算类别不平衡指标（最大类与最小类的比例）
    counts = arrayfun(@(lbl) sum(labels == lbl), 1:length(label_names));
    max_count = max(counts);
    min_count = min(counts(counts > 0));  % 排除0样本
    imbalance_ratio = max_count / min_count;
    
    fprintf('  最大类样本数: %d (%s)\n', max_count, label_names{counts == max_count});
    fprintf('  最小类样本数: %d (%s)\n', min_count, label_names{find(counts == min_count, 1)});
    fprintf('  不平衡比例: %.2f:1\n', imbalance_ratio);
    if imbalance_ratio > 10
        fprintf('  ⚠ 警告：类别不平衡较严重（>10:1），建议训练时使用类别加权\n');
    elseif imbalance_ratio > 5
        fprintf('  提示：存在一定类别不平衡（>5:1），可考虑加权或重采样\n');
    else
        fprintf('  ✓ 类别分布相对均衡\n');
    end
end

function print_duration_stats(labels, Ts, stride)
% 统计各标签类别的平均持续样本数（基于连续相同标签计数）
% V1.7: 更新为 3 类（flat, stall, slope）
    label_names = {'flat', 'stall', 'slope'};
    fprintf('  各类别平均连续持续时长（基于滑窗切片）:\n');
    
    for lbl = 1:3
        % 查找该标签的所有位置
        idx_lbl = find(labels == lbl);
        if isempty(idx_lbl)
            fprintf('    %s: 无样本\n', label_names{lbl});
            continue;
        end
        
        % 计算连续段长度（简化估计：切片间隔 = stride * Ts）
        % 实际持续时间难以精确计算（需要原始时间戳），此处仅给出切片数统计
        n_samples = length(idx_lbl);
        avg_duration_approx = n_samples * stride * Ts;  % 近似总时长
        
        fprintf('    %s: %d 个切片（近似总时长 %.1f s）\n', ...
            label_names{lbl}, n_samples, avg_duration_approx);
    end
    fprintf('  注：以上为粗略估计，实际持续时间需参考原始数据时间戳\n');
end

function input_file = resolve_source_input_file(dataset_source, data_gru_dir, data_mamba_dir)
% 根据来源策略选择输入母集
source = lower(string(dataset_source));
gru_file = fullfile(data_gru_dir, 'GRU_train_data_full.mat');
mamba_file = fullfile(data_mamba_dir, 'Mamba_train_data_full.mat');

switch source
    case "gru"
        input_file = gru_file;
    case "mamba"
        input_file = mamba_file;
    otherwise
        if exist(mamba_file, 'file')
            input_file = mamba_file;
        else
            input_file = gru_file;
        end
end
end

function dataset_source_used = detect_dataset_source(data, input_file)
% 根据字段判定母集来源，仅用于记录与日志
dataset_source_used = 'gru_like';
if isfield(data, 'meta') && isfield(data.meta, 'mamba_channels')
    dataset_source_used = 'mamba';
    return;
end
if contains(lower(input_file), [filesep 'mamba' filesep]) || contains(lower(input_file), 'mamba_train_data_full.mat')
    dataset_source_used = 'mamba';
end
end

function [theta_run, theta_source_name] = select_theta_target(run_data, idx_keep, run_idx)
% 兼容 GRU / Mamba 母集的坡度监督标签字段
if isfield(run_data, 'y_theta_ground') && numel(run_data.y_theta_ground) >= max(idx_keep)
    theta_run = run_data.y_theta_ground(idx_keep);
    theta_source_name = 'y_theta_ground';
    return;
end

if isfield(run_data, 'theta') && numel(run_data.theta) >= max(idx_keep)
    theta_run = run_data.theta(idx_keep);
    theta_source_name = 'theta';
    return;
end

if isfield(run_data, 'y_raw') && size(run_data.y_raw, 2) >= 16 && size(run_data.y_raw, 1) >= max(idx_keep)
    theta_run = run_data.y_raw(idx_keep, 16);
    theta_source_name = 'y_raw16';
    warning('第%d回合缺少 theta/y_theta_ground，回退使用 y_raw(:,16) 作为坡度监督。', run_idx);
    return;
end

error('第%d回合缺少可用坡度标签字段（theta / y_theta_ground / y_raw(:,16)）。', run_idx);
end
