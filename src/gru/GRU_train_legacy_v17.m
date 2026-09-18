% =============================
% 文件名：GRU_train.m
% 版本号：V1.7（简化主分类：3类，移除 slip）
% 最后修改时间：2025-12-30
% 作者：LPV-MPC Project
% 功能描述：
%   GRU多任务学习训练脚本（主分类+转弯分类+坡度回归）
%   1. 加载预处理数据集（GRU_dataset_processed.mat）
%   2. 构建三头GRU网络（主分类头+转弯分类头+坡度回归头）
%   3. 训练模型（自定义训练循环，混合损失函数，类别权重平衡）
%   4. 保存训练好的模型
%
% 使用方法：
%   直接运行此脚本：run('GRU_train.m') 或 GRU_train
%   修改下方"配置区域"来调整参数
%
% 输出：
%   - GRU_model.mat: 训练好的模型（包含 dlnetwork 对象）
%   - GRU_meta.mat: 训练元数据（超参数、训练历史）
%   - GRU_logs/: 训练日志目录（损失曲线图等）
%
% 依赖：
%   - GRU_dataset_processed.mat（由 GRU_prepare_dataset.m 生成）
%   - Deep Learning Toolbox（MATLAB R2024b+）
%
% 备注：
%   - 多任务学习：L = CE_main(加权) + λ_turn·CE_turn + λ_theta·MSE_theta·mask_theta + λ_theta_flat·MSE_theta(flat)
%   - 类别权重：按类频次的反比计算（平衡训练）
%   - 早停：验证损失无改善patience轮后停止
%   - 使用 dlnetwork + dlfeval + dlgradient 实现自定义训练循环
% =============================

%% ==================== 配置区域（用户可修改） ====================

root = project_root();
data_gru_dir = fullfile(root, 'data', 'gru');
data_models_dir = fullfile(root, 'data', 'models');
default_log_dir = results_dir('gru/train_logs');

if ~exist('cfg', 'var') || ~isstruct(cfg)
    cfg = struct();
end

if ~isfield(cfg, 'experiment_mode'); cfg.experiment_mode = 'default'; end
mode_str = lower(string(cfg.experiment_mode));
if mode_str == "mamba_control"
    default_log_dir_selected = results_dir('gru/train_logs_mamba_control');
    default_model_file = fullfile(data_models_dir, 'GRU_model_mamba_control.mat');
    default_meta_file = fullfile(data_models_dir, 'GRU_meta_mamba_control.mat');
else
    default_log_dir_selected = default_log_dir;
    default_model_file = fullfile(data_models_dir, 'GRU_model.mat');
    default_meta_file = fullfile(data_models_dir, 'GRU_meta.mat');
end

% 文件路径
if ~isfield(cfg, 'input_file'); cfg.input_file = fullfile(data_gru_dir, 'GRU_dataset_processed.mat'); end
if ~isfield(cfg, 'model_file'); cfg.model_file = default_model_file; end
if ~isfield(cfg, 'meta_file');  cfg.meta_file  = default_meta_file;  end
if ~isfield(cfg, 'log_dir');    cfg.log_dir    = default_log_dir_selected; end

% 模型超参数
if ~isfield(cfg, 'hidden_size'); cfg.hidden_size = 96; end                % GRU隐藏层大小
if ~isfield(cfg, 'num_layers'); cfg.num_layers = 2; end                  % GRU层数（当前实现固定2层）
if ~isfield(cfg, 'dropout'); cfg.dropout = 0.2; end                   % Dropout概率

% 训练超参数
if ~isfield(cfg, 'batch_size'); cfg.batch_size = 64; end                 % 批量大小
if mode_str == "mamba_control"
    if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 30; end             % 与当前 Mamba 训练轮数对齐
else
    if ~isfield(cfg, 'max_epochs'); cfg.max_epochs = 150; end
end
if ~isfield(cfg, 'initial_lr'); cfg.initial_lr = 1e-3; end               % 初始学习率
if ~isfield(cfg, 'lr_schedule'); cfg.lr_schedule = 'cosine'; end          % 学习率调度策略（'cosine' / 'step' / 'none'）
if ~isfield(cfg, 'lr_drop_factor'); cfg.lr_drop_factor = 0.5; end            % 学习率下降因子（step策略）
if ~isfield(cfg, 'lr_drop_period'); cfg.lr_drop_period = 20; end             % 学习率下降周期（step策略）

% 损失函数权重
if ~isfield(cfg, 'lambda_turn'); cfg.lambda_turn = 0.3; end               % 转弯分类损失权重
if ~isfield(cfg, 'lambda_theta'); cfg.lambda_theta = 0.5; end              % 坡度回归损失权重
if ~isfield(cfg, 'lambda_theta_flat'); cfg.lambda_theta_flat = 0.2; end         % 平地theta=0约束权重（抑制平地漂移）

% 梯度裁剪
if ~isfield(cfg, 'grad_clip'); cfg.grad_clip = 5.0; end                 % 梯度裁剪阈值

% 早停
if mode_str == "mamba_control"
    if ~isfield(cfg, 'patience'); cfg.patience = 10; end
else
    if ~isfield(cfg, 'patience'); cfg.patience = 20; end
end
if ~isfield(cfg, 'min_delta'); cfg.min_delta = 1e-4; end                % 验证损失改善的最小阈值

% 类别权重（主分类）
if ~isfield(cfg, 'use_class_weights'); cfg.use_class_weights = true; end        % 是否使用类别权重平衡
if ~isfield(cfg, 'class_weight_method'); cfg.class_weight_method = 'balanced'; end % 类别权重计算方法（'inverse' / 'sqrt_inverse' / 'balanced' / 'inverse_capped' / 'custom'）【默认使用balanced，根据样本量自动生成温和权重】

% 调试与可视化
if ~isfield(cfg, 'verbose'); cfg.verbose = true; end                  % 是否打印详细信息
if ~isfield(cfg, 'plot_loss'); cfg.plot_loss = true; end                % 是否绘制损失曲线
if ~isfield(cfg, 'validation_frequency'); cfg.validation_frequency = 1; end        % 验证频率（每N个epoch验证一次）

% 随机种子（用于可复现）
if ~isfield(cfg, 'seed'); cfg.seed = 42; end

% GPU选项
if ~isfield(cfg, 'use_gpu'); cfg.use_gpu = true; end                  % 是否使用GPU（如果可用）

%% ==================== 主程序（自动执行） ====================

if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('GRU多任务学习训练开始\n');
    fprintf('========================================\n');
    fprintf('实验模式: %s\n', cfg.experiment_mode);
end

%% 0. 初始化
% 固定随机种子
rng(cfg.seed);

% 创建日志目录
if ~exist(cfg.log_dir, 'dir')
    mkdir(cfg.log_dir);
end

if cfg.num_layers ~= 2 && cfg.verbose
    fprintf('[提示] 当前实现固定为2层GRU，cfg.num_layers=%d 将仅用于记录。\n', cfg.num_layers);
end

% 检查GPU可用性
if cfg.use_gpu && canUseGPU()
    exec_env = 'gpu';
    if cfg.verbose
        fprintf('\n[环境] 使用GPU加速\n');
        gpuinfo = gpuDevice();
        fprintf('  GPU设备: %s\n', gpuinfo.Name);
        fprintf('  显存: %.2f GB\n', gpuinfo.TotalMemory / 1e9);
    end
else
    exec_env = 'cpu';
    if cfg.verbose
        fprintf('\n[环境] 使用CPU训练\n');
    end
end

%% 1. 加载数据集
if cfg.verbose
    fprintf('\n[步骤1/6] 加载数据集...\n');
    fprintf('  输入文件: %s\n', cfg.input_file);
end

if ~exist(cfg.input_file, 'file')
    error('数据集文件不存在: %s', cfg.input_file);
end

load(cfg.input_file, 'dataset');  % 加载 dataset 结构体

% 补齐 scaler 的滤波参数（兼容旧版数据集）
if ~isfield(dataset, 'meta'); dataset.meta = struct(); end
if ~isfield(dataset.scaler, 'tau_accel_lp')
    if isfield(dataset.meta, 'tau_accel_lp')
        dataset.scaler.tau_accel_lp = dataset.meta.tau_accel_lp;
    else
        dataset.scaler.tau_accel_lp = 0.4;  % 与预处理默认一致
    end
end
if ~isfield(dataset.scaler, 'tau_diff')
    if isfield(dataset.meta, 'tau_diff')
        dataset.scaler.tau_diff = dataset.meta.tau_diff;
    else
        dataset.scaler.tau_diff = 0.3;
    end
end

if cfg.verbose
    fprintf('  ✓ 加载成功！\n');
    fprintf('    训练集: %d 样本\n', size(dataset.X_train, 1));
    fprintf('    验证集: %d 样本\n', size(dataset.X_val, 1));
    fprintf('    测试集: %d 样本\n', size(dataset.X_test, 1));
    fprintf('    特征维度: %d\n', size(dataset.X_train, 3));
    fprintf('    序列长度: %d\n', size(dataset.X_train, 2));
end

% mamba_control 模式下的对照组一致性检查
if strcmpi(cfg.experiment_mode, 'mamba_control')
    if ~isfield(dataset, 'meta')
        warning('GRU_train:NoDatasetMeta', '数据集中缺少 meta，无法执行对照组一致性检查。');
    else
        if isfield(dataset.meta, 'dataset_source') && ~strcmpi(dataset.meta.dataset_source, 'mamba')
            warning('GRU_train:SourceMismatch', '当前 experiment_mode=mamba_control，但 dataset_source=%s。', dataset.meta.dataset_source);
        end
        if isfield(dataset.meta, 'seq_len') && dataset.meta.seq_len ~= 128
            warning('GRU_train:SeqLenMismatch', 'mamba_control 推荐 seq_len=128，当前=%d。', dataset.meta.seq_len);
        end
        if isfield(dataset.meta, 'stride') && dataset.meta.stride ~= 64
            warning('GRU_train:StrideMismatch', 'mamba_control 推荐 stride=64，当前=%d。', dataset.meta.stride);
        end
        if isfield(dataset.meta, 'split_policy') && ~strcmpi(dataset.meta.split_policy, 'mamba_like')
            warning('GRU_train:SplitPolicyMismatch', 'mamba_control 推荐 split_policy=mamba_like，当前=%s。', dataset.meta.split_policy);
        end
        if isfield(dataset.meta, 'enable_train_resampling') && dataset.meta.enable_train_resampling
            warning('GRU_train:ResamplingEnabled', '检测到预处理启用了重采样，建议关闭以保持对照组公平性。');
        end
    end
end

%% 2. 计算类别权重（主分类）
if cfg.verbose
    fprintf('\n[步骤2/6] 计算类别权重（主分类）...\n');
end

% 统计主分类标签分布（V1.7: 3类，移除 slip）
y_main_train = dataset.y_main_train;
class_labels = (1:3)';  % V1.7: [flat, stall, slope]
n_classes_main = length(class_labels);
class_counts = zeros(n_classes_main, 1);

for i = 1:n_classes_main
    class_counts(i) = sum(y_main_train == class_labels(i));
end

% 计算类别权重
if cfg.use_class_weights
    switch cfg.class_weight_method
        case 'inverse'
            % 按频次的反比
            class_weights = 1 ./ class_counts;
        case 'sqrt_inverse'
            % 按频次平方根的反比（缓和权重差异）
            class_weights = 1 ./ sqrt(class_counts);
        case 'balanced'
            % sklearn风格：n_samples / (n_classes * n_samples_per_class)
            n_total = sum(class_counts);
            class_weights = n_total ./ (n_classes_main * class_counts);
        case 'inverse_capped'
            % inverse权重但添加上界限制，防止过度补偿（V1.2新增）
            class_weights = 1 ./ class_counts;
            % 先归一化再限制上界
            class_weights = class_weights / mean(class_weights);
            max_weight = 2.0;  % 最大权重为平均值的2倍
            class_weights = min(class_weights, max_weight);
            % 再次归一化（因为限制后均值可能不为1）
            class_weights = class_weights / mean(class_weights);
            fprintf('    权重策略: inverse with cap (max=%.1f)\n', max_weight);
        case 'custom'
            % 手动设置权重（V1.7: 3类，移除 slip）
            class_weights = [0.60;   % flat
                             1.80;   % stall
                             0.80];  % slope
            class_weights = class_weights / mean(class_weights);
            fprintf('    权重策略: custom (3-class v1.7)\n');
        otherwise
            error('未知的类别权重计算方法: %s', cfg.class_weight_method);
    end
    
    % 零样本保护：将没有样本的类别权重强制置为 0，避免 NaN/Inf 污染归一化结果
    empty_mask = (class_counts == 0);
    class_weights(empty_mask) = 0;
    class_weights(~isfinite(class_weights)) = 0;  % 兜底：将 Inf/NaN 一并置零
    
    % 仅用有样本的类别进行归一化（使有样本类的平均权重=1）
    present_weights_mean = mean(class_weights(~empty_mask));
    if present_weights_mean > 0
        class_weights = class_weights / present_weights_mean;
    else
        class_weights = ones(n_classes_main, 1);
        warning('GRU_train:WeightFallback', '所有类别样本均为零，回退为均匀权重');
    end
else
    % 均匀权重
    class_weights = ones(n_classes_main, 1);
end

if cfg.verbose
    fprintf('  ✓ 类别权重计算完成！\n');
    fprintf('    类别标签: ');
    fprintf('%d ', class_labels);
    fprintf('\n');
    
    fprintf('    类别计数: ');
    fprintf('%d ', class_counts);
    fprintf('\n');
    
    fprintf('    类别权重: ');
    fprintf('%.4f ', class_weights);
    fprintf('\n');
    
    fprintf('    类别名称: flat, stall, slope\n');
end

%% 3. 准备数据
if cfg.verbose
    fprintf('\n[步骤3/6] 准备训练数据...\n');
end

% 提取训练集（permute使得维度为 [feat_dim, seq_len, n_samples]）
X_train = permute(dataset.X_train, [3, 2, 1]);  % [feat_dim, seq_len, n_train]
y_main_train = dataset.y_main_train;            % [n_train, 1]
y_turn_train = dataset.y_turn_train;            % [n_train, 1]
y_theta_train = dataset.y_theta_train;          % [n_train, 1]
mask_theta_train = dataset.mask_theta_train;    % [n_train, 1]

% 提取验证集
X_val = permute(dataset.X_val, [3, 2, 1]);      % [feat_dim, seq_len, n_val]
y_main_val = dataset.y_main_val;
y_turn_val = dataset.y_turn_val;
y_theta_val = dataset.y_theta_val;
mask_theta_val = dataset.mask_theta_val;

% 提取测试集
X_test = permute(dataset.X_test, [3, 2, 1]);
y_main_test = dataset.y_main_test;
y_turn_test = dataset.y_turn_test;
y_theta_test = dataset.y_theta_test;
mask_theta_test = dataset.mask_theta_test;

% 转弯标签映射：{-1, 0, +1} → {1, 2, 3}（用于分类）
y_turn_train_cls = y_turn_train + 2;  % -1→1, 0→2, +1→3
y_turn_val_cls = y_turn_val + 2;

% 训练样本数
n_train = size(X_train, 3);
n_val = size(X_val, 3);

if cfg.verbose
    fprintf('  ✓ 数据准备完成！\n');
    fprintf('    训练批次数: %d (batch_size=%d)\n', ...
        ceil(n_train / cfg.batch_size), cfg.batch_size);
end

%% 4. 构建GRU网络（使用functionLayer实现三输出头）
if cfg.verbose
    fprintf('\n[步骤4/6] 构建GRU网络...\n');
end

% 输入维度
input_size = size(X_train, 1);  % feat_dim = 16
seq_len = size(X_train, 2);     % seq_len = 48

% 构建网络层（共享GRU特征提取器）
layers = [
    sequenceInputLayer(input_size, 'Name', 'input', 'Normalization', 'none')
    
    % GRU层1
    gruLayer(cfg.hidden_size, 'OutputMode', 'sequence', 'Name', 'gru1')
    dropoutLayer(cfg.dropout, 'Name', 'dropout1')
    
    % GRU层2（输出所有时刻的特征）
    gruLayer(cfg.hidden_size, 'OutputMode', 'sequence', 'Name', 'gru2')
    dropoutLayer(cfg.dropout, 'Name', 'dropout2')
];

% 创建 dlnetwork（只包含特征提取部分）
net_feature = dlnetwork(layers);

% 创建三个输出头的参数
% 主分类头: hidden_size → 3
fc_main_weights = dlarray(randn(3, cfg.hidden_size) * 0.01);  % V1.7: 4→3
fc_main_bias = dlarray(zeros(3, 1));

% 转弯分类头: hidden_size → 3
fc_turn_weights = dlarray(randn(3, cfg.hidden_size) * 0.01);
fc_turn_bias = dlarray(zeros(3, 1));

% 坡度回归头: hidden_size → 1
fc_theta_weights = dlarray(randn(1, cfg.hidden_size) * 0.01);
fc_theta_bias = dlarray(0);

% 转移到GPU
if strcmp(exec_env, 'gpu')
    % dlnetwork对象会自动处理GPU转换，只需转换权重参数
    fc_main_weights = gpuArray(fc_main_weights);
    fc_main_bias = gpuArray(fc_main_bias);
    fc_turn_weights = gpuArray(fc_turn_weights);
    fc_turn_bias = gpuArray(fc_turn_bias);
    fc_theta_weights = gpuArray(fc_theta_weights);
    fc_theta_bias = gpuArray(fc_theta_bias);
end

if cfg.verbose
    fprintf('  ✓ 网络构建完成！\n');
    fprintf('    输入维度: [%d, %d] (feat_dim, seq_len)\n', input_size, seq_len);
    fprintf('    GRU隐藏层: %d 单元 × %d 层\n', cfg.hidden_size, cfg.num_layers);
    fprintf('    输出头:\n');
    fprintf('      - 主分类: 3类 (flat/stall/slope)\n');  % V1.7
    fprintf('      - 转弯分类: 3类 (right/straight/left)\n');
    fprintf('      - 坡度回归: 1维 (theta [rad])\n');
end

%% 5. 初始化优化器（Adam）
if cfg.verbose
    fprintf('\n[步骤5/6] 初始化优化器...\n');
end

% 收集所有可训练参数
params = struct();
params.net_feature = net_feature.Learnables;
params.fc_main_weights = fc_main_weights;
params.fc_main_bias = fc_main_bias;
params.fc_turn_weights = fc_turn_weights;
params.fc_turn_bias = fc_turn_bias;
params.fc_theta_weights = fc_theta_weights;
params.fc_theta_bias = fc_theta_bias;

% Adam优化器状态
adamState = struct();
adamState.avgGrad = [];
adamState.avgSqGrad = [];
adamState.iter = 0;

% 学习率调度函数
if strcmp(cfg.lr_schedule, 'cosine')
    lr_fn = @(epoch) cfg.initial_lr * 0.5 * (1 + cos(pi * epoch / cfg.max_epochs));
elseif strcmp(cfg.lr_schedule, 'step')
    lr_fn = @(epoch) cfg.initial_lr * (cfg.lr_drop_factor ^ floor(epoch / cfg.lr_drop_period));
else
    lr_fn = @(epoch) cfg.initial_lr;
end

% 训练历史记录
history = struct();
history.train_loss = [];
history.train_loss_main = [];
history.train_loss_turn = [];
history.train_loss_theta = [];
history.train_loss_theta_flat = [];
history.val_loss = [];
history.val_loss_main = [];
history.val_loss_turn = [];
history.val_loss_theta = [];
history.val_loss_theta_flat = [];
history.val_acc_main = [];
history.val_acc_turn = [];
history.val_mae_theta = [];
history.lr = [];

% 早停变量
best_val_loss = inf;
patience_counter = 0;
best_params = [];

if cfg.verbose
    fprintf('  ✓ 优化器初始化完成！\n');
    fprintf('    优化器: Adam\n');
    fprintf('    初始学习率: %.4f\n', cfg.initial_lr);
    fprintf('    学习率调度: %s\n', cfg.lr_schedule);
    fprintf('    梯度裁剪: %.1f\n', cfg.grad_clip);
end

%% 6. 训练循环
if cfg.verbose
    fprintf('\n[步骤6/6] 开始训练...\n');
    fprintf('========================================\n\n');
end

% 训练进度
start_time = tic;
num_iterations_per_epoch = ceil(n_train / cfg.batch_size);

for epoch = 1:cfg.max_epochs
    % 更新学习率
    current_lr = lr_fn(epoch);
    history.lr(epoch) = current_lr;
    
    % 随机打乱训练数据
    idx_shuffle = randperm(n_train);
    
    % Epoch统计
    epoch_loss = 0;
    epoch_loss_main = 0;
    epoch_loss_turn = 0;
    epoch_loss_theta = 0;
    epoch_loss_theta_flat = 0;
    num_batches = 0;
    
    % Mini-batch训练
    for iter = 1:num_iterations_per_epoch
        % 提取当前batch的索引
        batch_start = (iter - 1) * cfg.batch_size + 1;
        batch_end = min(iter * cfg.batch_size, n_train);
        batch_idx = idx_shuffle(batch_start:batch_end);
        
        % 提取batch数据
        X_batch = X_train(:, :, batch_idx);
        y_main_batch = y_main_train(batch_idx);
        y_turn_batch = y_turn_train_cls(batch_idx);  % 使用映射后的标签
        y_theta_batch = y_theta_train(batch_idx);
        mask_theta_batch = mask_theta_train(batch_idx);
        
        % 转为dlarray
        X_batch = dlarray(X_batch, 'CBT');  % [feat_dim, seq_len, batch]
        
        % 转移到GPU
        if strcmp(exec_env, 'gpu')
            X_batch = gpuArray(X_batch);
            y_main_batch = gpuArray(y_main_batch);
            y_turn_batch = gpuArray(y_turn_batch);
            y_theta_batch = gpuArray(y_theta_batch);
            mask_theta_batch = gpuArray(mask_theta_batch);
        end
        
        % 前向传播 + 计算损失 + 反向传播
        [loss, loss_main, loss_turn, loss_theta, loss_theta_flat, gradients] = dlfeval(...
            @modelGradients, net_feature, ...
            fc_main_weights, fc_main_bias, ...
            fc_turn_weights, fc_turn_bias, ...
            fc_theta_weights, fc_theta_bias, ...
            X_batch, y_main_batch, y_turn_batch, y_theta_batch, mask_theta_batch, ...
            class_weights, cfg.lambda_turn, cfg.lambda_theta, cfg.lambda_theta_flat, exec_env);
        
        % 梯度裁剪
        [gradients, grad_norm] = clipGradients(gradients, cfg.grad_clip);
        
        % 更新参数（Adam）
        adamState.iter = adamState.iter + 1;
        [params, adamState] = adamUpdate(params, gradients, adamState, current_lr);
        
        % 更新网络和权重
        net_feature.Learnables = params.net_feature;
        fc_main_weights = params.fc_main_weights;
        fc_main_bias = params.fc_main_bias;
        fc_turn_weights = params.fc_turn_weights;
        fc_turn_bias = params.fc_turn_bias;
        fc_theta_weights = params.fc_theta_weights;
        fc_theta_bias = params.fc_theta_bias;
        
        % 累积损失
        epoch_loss = epoch_loss + extractdata(gather(loss));
        epoch_loss_main = epoch_loss_main + extractdata(gather(loss_main));
        epoch_loss_turn = epoch_loss_turn + extractdata(gather(loss_turn));
        epoch_loss_theta = epoch_loss_theta + extractdata(gather(loss_theta));
        epoch_loss_theta_flat = epoch_loss_theta_flat + extractdata(gather(loss_theta_flat));
        num_batches = num_batches + 1;
    end
    
    % Epoch平均损失
    epoch_loss = epoch_loss / num_batches;
    epoch_loss_main = epoch_loss_main / num_batches;
    epoch_loss_turn = epoch_loss_turn / num_batches;
    epoch_loss_theta = epoch_loss_theta / num_batches;
    epoch_loss_theta_flat = epoch_loss_theta_flat / num_batches;
    
    history.train_loss(epoch) = epoch_loss;
    history.train_loss_main(epoch) = epoch_loss_main;
    history.train_loss_turn(epoch) = epoch_loss_turn;
    history.train_loss_theta(epoch) = epoch_loss_theta;
    history.train_loss_theta_flat(epoch) = epoch_loss_theta_flat;
    
    % 验证
    if mod(epoch, cfg.validation_frequency) == 0
        [val_loss, val_loss_main, val_loss_turn, val_loss_theta, val_loss_theta_flat, ...
         val_acc_main, val_acc_turn, val_mae_theta, ~, ~, ~] = ...
            evaluateModel(net_feature, ...
                fc_main_weights, fc_main_bias, ...
                fc_turn_weights, fc_turn_bias, ...
                fc_theta_weights, fc_theta_bias, ...
                X_val, y_main_val, y_turn_val_cls, y_theta_val, mask_theta_val, ...
                class_weights, cfg.lambda_turn, cfg.lambda_theta, cfg.lambda_theta_flat, ...
                cfg.batch_size, exec_env);
        
        history.val_loss(epoch) = val_loss;
        history.val_loss_main(epoch) = val_loss_main;
        history.val_loss_turn(epoch) = val_loss_turn;
        history.val_loss_theta(epoch) = val_loss_theta;
        history.val_loss_theta_flat(epoch) = val_loss_theta_flat;
        history.val_acc_main(epoch) = val_acc_main;
        history.val_acc_turn(epoch) = val_acc_turn;
        history.val_mae_theta(epoch) = val_mae_theta;
        
        % 打印进度
        if cfg.verbose
            elapsed = toc(start_time);
            eta = elapsed / epoch * (cfg.max_epochs - epoch);
            fprintf('[Epoch %3d/%3d] train_loss=%.4f (main=%.4f, turn=%.4f, theta=%.4f, flatθ=%.4f) | ', ...
                epoch, cfg.max_epochs, epoch_loss, epoch_loss_main, epoch_loss_turn, epoch_loss_theta, epoch_loss_theta_flat);
            fprintf('val_loss=%.4f (acc_main=%.3f, acc_turn=%.3f, mae_theta=%.4f°, flatθ=%.4f) | ', ...
                val_loss, val_acc_main, val_acc_turn, rad2deg(val_mae_theta), val_loss_theta_flat);
            fprintf('lr=%.4e | %.1fs/%.1fs\n', current_lr, elapsed, eta);
        end
        
        % 早停检查
        if val_loss < (best_val_loss - cfg.min_delta)
            % 验证损失改善
            best_val_loss = val_loss;
            patience_counter = 0;
            
            % 保存最佳模型
            best_params = struct();
            best_params.net_feature = net_feature.Learnables;
            best_params.fc_main_weights = fc_main_weights;
            best_params.fc_main_bias = fc_main_bias;
            best_params.fc_turn_weights = fc_turn_weights;
            best_params.fc_turn_bias = fc_turn_bias;
            best_params.fc_theta_weights = fc_theta_weights;
            best_params.fc_theta_bias = fc_theta_bias;
            
            if cfg.verbose
                fprintf('  ✓ 验证损失改善 (%.4f → %.4f)，保存最佳模型\n', ...
                    best_val_loss + cfg.min_delta, best_val_loss);
            end
        else
            % 验证损失未改善
            patience_counter = patience_counter + 1;
            
            if patience_counter >= cfg.patience
                if cfg.verbose
                    fprintf('\n早停触发：验证损失连续 %d 轮未改善\n', cfg.patience);
                end
                break;
            end
        end
    else
        % 不进行验证，只打印训练损失
        if cfg.verbose
            elapsed = toc(start_time);
            eta = elapsed / epoch * (cfg.max_epochs - epoch);
            fprintf('[Epoch %3d/%3d] train_loss=%.4f (main=%.4f, turn=%.4f, theta=%.4f) | lr=%.4e | %.1fs/%.1fs\n', ...
                epoch, cfg.max_epochs, epoch_loss, epoch_loss_main, epoch_loss_turn, epoch_loss_theta, ...
                current_lr, elapsed, eta);
        end
    end
end

% 训练结束
total_time = toc(start_time);

if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('训练完成！\n');
    fprintf('========================================\n');
    fprintf('  总训练时间: %.2f 分钟\n', total_time / 60);
    fprintf('  实际训练轮数: %d / %d\n', epoch, cfg.max_epochs);
    fprintf('  最佳验证损失: %.4f (Epoch %d)\n', best_val_loss, ...
        find(history.val_loss == best_val_loss, 1));
end

%% 7. 恢复最佳模型
if ~isempty(best_params)
    net_feature.Learnables = best_params.net_feature;
    fc_main_weights = best_params.fc_main_weights;
    fc_main_bias = best_params.fc_main_bias;
    fc_turn_weights = best_params.fc_turn_weights;
    fc_turn_bias = best_params.fc_turn_bias;
    fc_theta_weights = best_params.fc_theta_weights;
    fc_theta_bias = best_params.fc_theta_bias;
end

%% 8. 测试集评估
if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('测试集评估\n');
    fprintf('========================================\n');
end

y_turn_test_cls = y_turn_test + 2;
[test_loss, test_loss_main, test_loss_turn, test_loss_theta, test_loss_theta_flat, ...
 test_acc_main, test_acc_turn, test_mae_theta, pred_main_test, pred_turn_test, pred_theta_test] = ...
    evaluateModel(net_feature, ...
        fc_main_weights, fc_main_bias, ...
        fc_turn_weights, fc_turn_bias, ...
        fc_theta_weights, fc_theta_bias, ...
        X_test, y_main_test, y_turn_test_cls, y_theta_test, mask_theta_test, ...
        class_weights, cfg.lambda_turn, cfg.lambda_theta, cfg.lambda_theta_flat, ...
        cfg.batch_size, exec_env);

    test_detailed = [];

if cfg.verbose
    fprintf('  测试损失: %.4f\n', test_loss);
    fprintf('  主分类准确率: %.2f%%\n', test_acc_main * 100);
    fprintf('  转弯分类准确率: %.2f%%\n', test_acc_turn * 100);
    fprintf('  坡度角MAE: %.4f° (%.4f rad)\n', rad2deg(test_mae_theta), test_mae_theta);
    fprintf('  平地θ约束损失: %.4f\n', test_loss_theta_flat);
    
    % ========== V1.1: 详细评估指标 ==========
    fprintf('\n----------------------------------------\n');
    fprintf('详细评估指标（主分类）\n');
    fprintf('----------------------------------------\n');
    
    % 计算混淆矩阵（显式指定类别顺序，防止少数类缺失导致矩阵降阶）
    % V1.7: 更新为 3 类（flat, stall, slope），移除 slip
    class_names = {'flat', 'stall', 'slope'};
    class_order = 1:length(class_names);
    CM_main = confusionmat(y_main_test, pred_main_test, 'Order', class_order);
    
    % 计算per-class指标
    n_classes_main = length(class_names);
    precision = zeros(n_classes_main, 1);
    recall = zeros(n_classes_main, 1);
    f1 = zeros(n_classes_main, 1);
    support = zeros(n_classes_main, 1);
    
    for c = 1:n_classes_main
        TP = CM_main(c, c);
        FP = sum(CM_main(:, c)) - TP;
        FN = sum(CM_main(c, :)) - TP;
        
        precision(c) = TP / (TP + FP + eps);
        recall(c) = TP / (TP + FN + eps);
        f1(c) = 2 * precision(c) * recall(c) / (precision(c) + recall(c) + eps);
        support(c) = sum(y_main_test == c);
    end
    
    % macro-F1
    macro_f1 = mean(f1);
    
    % 打印per-class指标
    fprintf('\n%-10s | Precision | Recall | F1-Score | Support\n', 'Class');
    fprintf('-----------|-----------|--------|----------|--------\n');
    for c = 1:n_classes_main
        fprintf('%-10s |   %.4f  | %.4f |  %.4f  |  %d\n', ...
            class_names{c}, precision(c), recall(c), f1(c), support(c));
    end
    fprintf('-----------|-----------|--------|----------|--------\n');
    fprintf('macro-F1   |           |        |  %.4f  |  %d\n', macro_f1, length(y_main_test));
    fprintf('weighted-F1|           |        |  %.4f  |  %d\n', ...
        sum(f1 .* support) / sum(support), length(y_main_test));
    
    % 打印混淆矩阵
    fprintf('\n[混淆矩阵 - 主分类]\n');
    fprintf('%-10s', '真实\\预测');
    for c = 1:n_classes_main
        fprintf(' | %-6s', class_names{c});
    end
    fprintf('\n');
    fprintf(repmat('-', 1, 10 + 9*n_classes_main));
    fprintf('\n');
    for r = 1:n_classes_main
        fprintf('%-10s', class_names{r});
        for c = 1:n_classes_main
            fprintf(' |  %4d ', CM_main(r, c));
        end
        fprintf('\n');
    end
    
    % 可视化混淆矩阵
    figure('Name', '主分类混淆矩阵', 'NumberTitle', 'off');
    confusionchart(CM_main, class_names);
    title(sprintf('主分类混淆矩阵（测试集）- 准确率: %.2f%%, macro-F1: %.4f', ...
        test_acc_main * 100, macro_f1));
    saveas(gcf, fullfile(cfg.log_dir, 'confusion_matrix_main.png'));
    if cfg.verbose
        fprintf('\n  ✓ 混淆矩阵已保存至: %s\n', fullfile(cfg.log_dir, 'confusion_matrix_main.png'));
    end

    % ========== 转弯三分类混淆矩阵 ==========
    turn_class_names = {'right', 'straight', 'left'};  % 对应标签 {1,2,3}
    CM_turn = confusionmat(y_turn_test_cls, pred_turn_test, 'Order', 1:3);
    figure('Name', '转弯分类混淆矩阵', 'NumberTitle', 'off');
    confusionchart(CM_turn, turn_class_names);
    title(sprintf('转弯分类混淆矩阵（测试集）- 准确率: %.2f%%', test_acc_turn * 100));
    saveas(gcf, fullfile(cfg.log_dir, 'confusion_matrix_turn.png'));
    if cfg.verbose
        fprintf('  ✓ 转弯混淆矩阵已保存至: %s\n', fullfile(cfg.log_dir, 'confusion_matrix_turn.png'));
    end

    % ========== 坡度回归可视化（theta vs theta / 误差直方 / CDF） ==========
    theta_true = gather(y_theta_test(:));
    theta_pred = gather(pred_theta_test(:));
    mask_slope = gather(mask_theta_test(:)) == 1;
    theta_true_deg = rad2deg(theta_true(mask_slope));
    theta_pred_deg = rad2deg(theta_pred(mask_slope));
    theta_err_deg = theta_pred_deg - theta_true_deg;
    theta_abs_err_deg = abs(theta_err_deg);

    if isempty(theta_true_deg)
        warning('坡度样本为空，跳过坡度回归可视化。');
    else

        % 散点图：theta_true vs theta_pred
        figure('Name', '坡度回归散点', 'NumberTitle', 'off');
        scatter(theta_true_deg, theta_pred_deg, 12, 'filled', 'MarkerFaceAlpha', 0.6);
        hold on; grid on;
        lim_min = min([theta_true_deg; theta_pred_deg]);
        lim_max = max([theta_true_deg; theta_pred_deg]);
        plot([lim_min, lim_max], [lim_min, lim_max], 'k--', 'LineWidth', 1);
        xlabel('\\theta True (deg)'); ylabel('\\theta Pred (deg)');
        title(sprintf('坡度回归: \\theta_{true} vs \\theta_{pred} (MAE=%.3f°)', rad2deg(test_mae_theta)));
        xlim([lim_min, lim_max]); ylim([lim_min, lim_max]);
        saveas(gcf, fullfile(cfg.log_dir, 'theta_scatter.png'));

        % 误差直方图
        figure('Name', '坡度回归误差直方图', 'NumberTitle', 'off');
        histogram(theta_err_deg, 40, 'Normalization', 'pdf'); grid on;
        xlabel('误差 (deg)'); ylabel('概率密度');
        title('坡度回归误差直方图 (pred - true)');
        saveas(gcf, fullfile(cfg.log_dir, 'theta_error_hist.png'));

        % 绝对误差CDF
        figure('Name', '坡度回归误差CDF', 'NumberTitle', 'off');
        [f_ecdf, x_ecdf] = ecdf(theta_abs_err_deg);
        plot(x_ecdf, f_ecdf, 'LineWidth', 1.5); grid on;
        xlabel('|误差| (deg)'); ylabel('CDF');
        title('坡度回归绝对误差CDF');
        saveas(gcf, fullfile(cfg.log_dir, 'theta_error_cdf.png'));
        if cfg.verbose
            fprintf('  ✓ 坡度回归图已保存至: %s, %s, %s\n', ...
                fullfile(cfg.log_dir, 'theta_scatter.png'), ...
                fullfile(cfg.log_dir, 'theta_error_hist.png'), ...
                fullfile(cfg.log_dir, 'theta_error_cdf.png'));
        end
    end
    
    % ========== 自动分析与建议 ==========
    fprintf('\n========================================\n');
    fprintf('自动分析与建议\n');
    fprintf('========================================\n');
    
    % 调用分析函数
    analysis = analyzeModelPerformance(CM_main, precision, recall, f1, macro_f1, ...
        class_counts, class_names, cfg.class_weight_method);
    
    % 打印建议
    fprintf('\n[整体评估]: %s\n', analysis.overall_status);
    if ~isempty(analysis.recommendations)
        fprintf('\n[改进建议]:\n');
        for i = 1:length(analysis.recommendations)
            fprintf('  %d. %s\n', i, analysis.recommendations{i});
        end
    end
    if ~isempty(analysis.warnings)
        fprintf('\n[⚠️ 警告]:\n');
        for i = 1:length(analysis.warnings)
            fprintf('  - %s\n', analysis.warnings{i});
        end
    end
    
    % 保存详细指标（稍后写入meta）
    test_detailed = struct();
    test_detailed.confusion_matrix = CM_main;
    test_detailed.precision = precision;
    test_detailed.recall = recall;
    test_detailed.f1 = f1;
    test_detailed.macro_f1 = macro_f1;
    test_detailed.support = support;
    test_detailed.class_names = class_names;
    test_detailed.analysis = analysis;
end

%% 9. 保存模型
if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('保存模型\n');
    fprintf('========================================\n');
end

% 构建模型结构体
model = struct();
model.net_feature = net_feature;
model.fc_main_weights = gather(fc_main_weights);
model.fc_main_bias = gather(fc_main_bias);
model.fc_turn_weights = gather(fc_turn_weights);
model.fc_turn_bias = gather(fc_turn_bias);
model.fc_theta_weights = gather(fc_theta_weights);
model.fc_theta_bias = gather(fc_theta_bias);
model.scaler = dataset.scaler;
model.feat_names = dataset.feat_names;
model.seq_len = seq_len;  % 序列长度（便于推理时使用）
model.feat_dim = input_size;  % 特征维度
model.class_labels_main = {'flat', 'stall', 'slope'};  % V1.7: 3类
model.class_labels_turn = {'right', 'straight', 'left'};  % [-1, 0, +1]
model.class_weights = class_weights;
model.cfg = cfg;

% 保存模型
if cfg.verbose
    fprintf('  正在保存到: %s\n', cfg.model_file);
end
save(cfg.model_file, 'model', '-v7.3');

% 保存元数据
meta = struct();
meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
meta.version = 'V1.0';
meta.author = 'LPV-MPC Project';
meta.cfg = cfg;
meta.history = history;
meta.best_val_loss = best_val_loss;
meta.test_metrics = struct(...
    'test_loss', test_loss, ...
    'test_acc_main', test_acc_main, ...
    'test_acc_turn', test_acc_turn, ...
    'test_mae_theta', test_mae_theta, ...
    'test_loss_theta_flat', test_loss_theta_flat);
meta.total_time = total_time;
meta.actual_epochs = epoch;
if ~isempty(test_detailed)
    meta.test_detailed = test_detailed;
end

if cfg.verbose
    fprintf('  正在保存到: %s\n', cfg.meta_file);
end
save(cfg.meta_file, 'meta');

if cfg.verbose
    fprintf('  ✓ 保存成功！\n');
end

%% 10. 绘制训练曲线
if cfg.plot_loss
    if cfg.verbose
        fprintf('\n========================================\n');
        fprintf('绘制训练曲线\n');
        fprintf('========================================\n');
    end
    
    % 创建2行3列的子图
    fig = figure('Position', [100, 100, 1400, 800]);
    
    % 子图1：总损失
    subplot(2, 3, 1);
    plot(1:epoch, history.train_loss, 'b-', 'LineWidth', 1.5);
    hold on;
    val_epochs = find(history.val_loss > 0);
    plot(val_epochs, history.val_loss(val_epochs), 'r-', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('Loss');
    title('总损失');
    legend({'训练', '验证'}, 'Location', 'best');
    grid on;
    
    % 子图2：主分类损失
    subplot(2, 3, 2);
    plot(1:epoch, history.train_loss_main, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(val_epochs, history.val_loss_main(val_epochs), 'r-', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('Loss');
    title('主分类损失');
    legend({'训练', '验证'}, 'Location', 'best');
    grid on;
    
    % 子图3：转弯分类损失
    subplot(2, 3, 3);
    plot(1:epoch, history.train_loss_turn, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(val_epochs, history.val_loss_turn(val_epochs), 'r-', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('Loss');
    title('转弯分类损失');
    legend({'训练', '验证'}, 'Location', 'best');
    grid on;
    
    % 子图4：坡度/平地θ损失
    subplot(2, 3, 4);
    plot(1:epoch, history.train_loss_theta, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(val_epochs, history.val_loss_theta(val_epochs), 'r-', 'LineWidth', 1.5);
    plot(1:epoch, history.train_loss_theta_flat, 'c--', 'LineWidth', 1.5);
    plot(val_epochs, history.val_loss_theta_flat(val_epochs), 'm--', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('Loss');
    title('坡度/平地θ损失');
    legend({'训练-坡度', '验证-坡度', '训练-平地θ', '验证-平地θ'}, 'Location', 'best');
    grid on;
    
    % 子图5：准确率
    subplot(2, 3, 5);
    plot(val_epochs, history.val_acc_main(val_epochs), 'g-', 'LineWidth', 1.5);
    hold on;
    plot(val_epochs, history.val_acc_turn(val_epochs), 'm-', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('准确率');
    title('分类准确率');
    legend({'主分类', '转弯分类'}, 'Location', 'best');
    grid on;
    ylim([0, 1]);
    
    % 子图6：学习率
    subplot(2, 3, 6);
    plot(1:epoch, history.lr(1:epoch), 'k-', 'LineWidth', 1.5);
    xlabel('Epoch');
    ylabel('学习率');
    title('学习率调度');
    grid on;
    
    % 保存图像
    saveas(fig, fullfile(cfg.log_dir, 'training_curves.png'));
    
    if cfg.verbose
        fprintf('  ✓ 训练曲线已保存至: %s\n', fullfile(cfg.log_dir, 'training_curves.png'));
    end
end

if cfg.verbose
    fprintf('\n========================================\n');
    fprintf('GRU训练完成！\n');
    fprintf('========================================\n');
    fprintf('输出文件:\n');
    fprintf('  - %s (训练好的模型)\n', cfg.model_file);
    fprintf('  - %s (训练元数据)\n', cfg.meta_file);
    fprintf('  - %s/ (训练日志)\n', cfg.log_dir);
    fprintf('\n最终性能:\n');
    fprintf('  - 测试集主分类准确率: %.2f%%\n', test_acc_main * 100);
    fprintf('  - 测试集转弯分类准确率: %.2f%%\n', test_acc_turn * 100);
    fprintf('  - 测试集坡度角MAE: %.4f°\n', rad2deg(test_mae_theta));
end

%% ========== 辅助函数 ==========

function [loss, loss_main, loss_turn, loss_theta, loss_theta_flat, gradients] = modelGradients(...
    net_feature, fc_main_w, fc_main_b, fc_turn_w, fc_turn_b, fc_theta_w, fc_theta_b, ...
    X, y_main, y_turn, y_theta, mask_theta, class_weights, lambda_turn, lambda_theta, lambda_theta_flat, exec_env)
% 计算模型损失和梯度（多任务学习）
% 输入:
%   net_feature: dlnetwork对象（GRU特征提取器）
%   fc_main_w/b: 主分类头权重和偏置
%   fc_turn_w/b: 转弯分类头权重和偏置
%   fc_theta_w/b: 坡度回归头权重和偏置
%   X: 输入特征 [feat_dim, seq_len, batch]
%   y_main: 主分类标签 [batch] ∈ {1,2,3,4}
%   y_turn: 转弯分类标签 [batch] ∈ {1,2,3}（已映射）
%   y_theta: 坡度角真值 [batch] [rad]
%   mask_theta: 坡度角mask [batch] (slope样本=1)
%   class_weights: 主分类类别权重 [4]
%   lambda_turn: 转弯分类损失权重
%   lambda_theta: 坡度回归损失权重
%   lambda_theta_flat: 平地theta约束损失权重
%   exec_env: 'cpu' 或 'gpu'
% 输出:
%   loss: 总损失（标量）
%   loss_main: 主分类损失
%   loss_turn: 转弯分类损失
%   loss_theta: 坡度回归损失
%   loss_theta_flat: 平地theta约束损失
%   gradients: 梯度结构体

    % 前向传播：GRU特征提取
    features_seq = forward(net_feature, X);  % [hidden_size, seq_len, batch]
    
    % 提取最后一个时间步的特征
    features = features_seq(:, end, :);  % [hidden_size, 1, batch]
    features = squeeze(features);  % [hidden_size, batch]
    
    % 移除维度标签（避免矩阵乘法时的维度标签冲突）
    features = stripdims(features);
    
    % 主分类头
    logits_main = fc_main_w * features + fc_main_b;  % [4, batch]
    probs_main = softmax(logits_main, 'DataFormat', 'CB');
    
    % 转弯分类头
    logits_turn = fc_turn_w * features + fc_turn_b;  % [3, batch]
    probs_turn = softmax(logits_turn, 'DataFormat', 'CB');
    
    % 坡度回归头
    pred_theta = fc_theta_w * features + fc_theta_b;  % [1, batch]
    % 注意：不使用squeeze，保持[1, batch]形状
    
    % 计算损失
    % 获取实际批量大小
    batch_size = size(X, 3);
    
    % 1) 主分类损失（交叉熵，带类别权重）
    loss_main = 0;
    for i = 1:batch_size
        class_idx = y_main(i);
        weight = class_weights(class_idx);
        if strcmp(exec_env, 'gpu')
            weight = gpuArray(weight);
        end
        loss_main = loss_main - weight * log(probs_main(class_idx, i) + 1e-8);
    end
    loss_main = loss_main / batch_size;
    
    % 2) 转弯分类损失（交叉熵，无权重）
    loss_turn = 0;
    for i = 1:batch_size
        class_idx = y_turn(i);
        loss_turn = loss_turn - log(probs_turn(class_idx, i) + 1e-8);
    end
    loss_turn = loss_turn / batch_size;
    
    % 3) 坡度回归损失（MSE，仅slope样本）
    % 将y_theta和mask_theta转换为行向量以匹配pred_theta的形状[1, batch]
    if strcmp(exec_env, 'gpu')
        y_theta = gpuArray(y_theta);
        mask_theta = gpuArray(mask_theta);
    end
    
    % 转为行向量并转为dlarray
    y_theta_row = dlarray(reshape(y_theta, 1, []));  % [1, batch]
    mask_theta_row = dlarray(reshape(mask_theta, 1, []));  % [1, batch]
    
    % 计算误差
    errors = (pred_theta - y_theta_row) .* mask_theta_row;  % [1, batch]
    n_slope = sum(mask_theta) + 1e-8;  % 避免除零
    loss_theta = sum(errors.^2) / n_slope;
    
    % 4) 平地theta约束（平地样本MSE）
    flat_mask = double(y_main == 1);
    flat_mask_row = dlarray(reshape(flat_mask, 1, []));
    flat_errors = pred_theta .* flat_mask_row;
    n_flat = sum(flat_mask_row) + 1e-8;
    loss_theta_flat = sum(flat_errors.^2) / n_flat;
    
    % 总损失
    loss = loss_main + lambda_turn * loss_turn + lambda_theta * loss_theta + lambda_theta_flat * loss_theta_flat;
    
    % 计算梯度
    gradients = struct();
    gradients.net_feature = dlgradient(loss, net_feature.Learnables);
    gradients.fc_main_weights = dlgradient(loss, fc_main_w);
    gradients.fc_main_bias = dlgradient(loss, fc_main_b);
    gradients.fc_turn_weights = dlgradient(loss, fc_turn_w);
    gradients.fc_turn_bias = dlgradient(loss, fc_turn_b);
    gradients.fc_theta_weights = dlgradient(loss, fc_theta_w);
    gradients.fc_theta_bias = dlgradient(loss, fc_theta_b);
end

function [val_loss, val_loss_main, val_loss_turn, val_loss_theta, val_loss_theta_flat, ...
          val_acc_main, val_acc_turn, val_mae_theta, all_pred_main, all_pred_turn, all_pred_theta] = ...
    evaluateModel(net_feature, fc_main_w, fc_main_b, fc_turn_w, fc_turn_b, ...
                  fc_theta_w, fc_theta_b, ...
                  X_val, y_main_val, y_turn_val, y_theta_val, mask_theta_val, ...
                  class_weights, lambda_turn, lambda_theta, lambda_theta_flat, batch_size, exec_env)
% 评估模型在验证集上的性能（V1.1: 返回预测结果用于详细分析）

    n_val = size(X_val, 3);
    num_batches = ceil(n_val / batch_size);
    
    total_loss = 0;
    total_loss_main = 0;
    total_loss_turn = 0;
    total_loss_theta = 0;
    total_loss_theta_flat = 0;
    
    all_pred_main = [];
    all_pred_turn = [];
    all_pred_theta = [];
    
    for iter = 1:num_batches
        % 提取当前batch
        batch_start = (iter - 1) * batch_size + 1;
        batch_end = min(iter * batch_size, n_val);
        batch_idx = batch_start:batch_end;
        
        X_batch = X_val(:, :, batch_idx);
        y_main_batch = y_main_val(batch_idx);
        y_turn_batch = y_turn_val(batch_idx);
        y_theta_batch = y_theta_val(batch_idx);
        mask_theta_batch = mask_theta_val(batch_idx);
        
        % 转为dlarray
        X_batch = dlarray(X_batch, 'CBT');
        
        % 转移到GPU
        if strcmp(exec_env, 'gpu')
            X_batch = gpuArray(X_batch);
            y_main_batch = gpuArray(y_main_batch);
            y_turn_batch = gpuArray(y_turn_batch);
            y_theta_batch = gpuArray(y_theta_batch);
            mask_theta_batch = gpuArray(mask_theta_batch);
        end
        
        % 前向传播
        features_seq = forward(net_feature, X_batch);  % [hidden_size, seq_len, batch]
        
        % 提取最后一个时间步的特征
        features = features_seq(:, end, :);  % [hidden_size, 1, batch]
        features = squeeze(features);  % [hidden_size, batch]
        
        % 移除维度标签（避免矩阵乘法时的维度标签冲突）
        features = stripdims(features);
        
        % 主分类头
        logits_main = fc_main_w * features + fc_main_b;
        probs_main = softmax(logits_main, 'DataFormat', 'CB');
        [~, pred_main] = max(extractdata(gather(probs_main)), [], 1);
        all_pred_main = [all_pred_main; pred_main(:)];
        
        % 转弯分类头
        logits_turn = fc_turn_w * features + fc_turn_b;
        probs_turn = softmax(logits_turn, 'DataFormat', 'CB');
        [~, pred_turn] = max(extractdata(gather(probs_turn)), [], 1);
        all_pred_turn = [all_pred_turn; pred_turn(:)];
        
        % 坡度回归头
        pred_theta = fc_theta_w * features + fc_theta_b;
        pred_theta = squeeze(pred_theta);
        all_pred_theta = [all_pred_theta; extractdata(gather(pred_theta(:)))];
        
        % 计算损失
        batch_loss_main = 0;
        curr_batch_size = length(batch_idx);
        for i = 1:curr_batch_size
            class_idx = y_main_batch(i);
            weight = class_weights(class_idx);
            if strcmp(exec_env, 'gpu')
                weight = gpuArray(weight);
            end
            batch_loss_main = batch_loss_main - weight * log(probs_main(class_idx, i) + 1e-8);
        end
        batch_loss_main = batch_loss_main / curr_batch_size;
        
        batch_loss_turn = 0;
        for i = 1:curr_batch_size
            class_idx = y_turn_batch(i);
            batch_loss_turn = batch_loss_turn - log(probs_turn(class_idx, i) + 1e-8);
        end
        batch_loss_turn = batch_loss_turn / curr_batch_size;
        
        errors = (pred_theta(:) - y_theta_batch(:)) .* mask_theta_batch(:);
        n_slope = sum(mask_theta_batch) + 1e-8;
        batch_loss_theta = sum(errors.^2) / n_slope;
        
        flat_mask_batch = double(y_main_batch == 1);
        batch_loss_theta_flat = sum((pred_theta(:) .* flat_mask_batch(:)).^2) / (sum(flat_mask_batch) + 1e-8);
        
        batch_loss = batch_loss_main + lambda_turn * batch_loss_turn + lambda_theta * batch_loss_theta + lambda_theta_flat * batch_loss_theta_flat;
        
        total_loss = total_loss + extractdata(gather(batch_loss));
        total_loss_main = total_loss_main + extractdata(gather(batch_loss_main));
        total_loss_turn = total_loss_turn + extractdata(gather(batch_loss_turn));
        total_loss_theta = total_loss_theta + extractdata(gather(batch_loss_theta));
        total_loss_theta_flat = total_loss_theta_flat + extractdata(gather(batch_loss_theta_flat));
    end
    
    % 平均损失
    val_loss = total_loss / num_batches;
    val_loss_main = total_loss_main / num_batches;
    val_loss_turn = total_loss_turn / num_batches;
    val_loss_theta = total_loss_theta / num_batches;
    val_loss_theta_flat = total_loss_theta_flat / num_batches;
    
    % 准确率
    val_acc_main = mean(all_pred_main == y_main_val);
    val_acc_turn = mean(all_pred_turn == y_turn_val);
    
    % MAE（仅slope样本）
    mask_theta_val = gather(mask_theta_val);
    y_theta_val = gather(y_theta_val);
    slope_idx = find(mask_theta_val == 1);
    if ~isempty(slope_idx)
        val_mae_theta = mean(abs(all_pred_theta(slope_idx) - y_theta_val(slope_idx)));
    else
        val_mae_theta = 0;
    end
end

function [gradients, grad_norm] = clipGradients(gradients, threshold)
% 梯度裁剪（全局范数）
    grad_norm = 0;
    
    % 计算全局梯度范数
    fields = fieldnames(gradients);
    for i = 1:length(fields)
        field = fields{i};
        if istable(gradients.(field))
            % dlnetwork Learnables（table格式）
            for j = 1:height(gradients.(field))
                grad = gradients.(field).Value{j};
                grad_norm = grad_norm + sum(grad(:).^2);
            end
        else
            % 普通数组
            grad = gradients.(field);
            grad_norm = grad_norm + sum(grad(:).^2);
        end
    end
    grad_norm = sqrt(grad_norm);
    
    % 裁剪
    if grad_norm > threshold
        scale = threshold / grad_norm;
        for i = 1:length(fields)
            field = fields{i};
            if istable(gradients.(field))
                for j = 1:height(gradients.(field))
                    gradients.(field).Value{j} = gradients.(field).Value{j} * scale;
                end
            else
                gradients.(field) = gradients.(field) * scale;
            end
        end
    end
end

function [params, adamState] = adamUpdate(params, gradients, adamState, learningRate)
% Adam优化器更新
    beta1 = 0.9;
    beta2 = 0.999;
    epsilon = 1e-8;
    
    adamState.iter = adamState.iter + 1;
    
    % 初始化状态
    if isempty(adamState.avgGrad)
        adamState.avgGrad = struct();
        adamState.avgSqGrad = struct();
    end
    
    % 更新 net_feature
    if ~isfield(adamState.avgGrad, 'net_feature')
        adamState.avgGrad.net_feature = gradients.net_feature;
        adamState.avgGrad.net_feature.Value(:) = {0};
        adamState.avgSqGrad.net_feature = gradients.net_feature;
        adamState.avgSqGrad.net_feature.Value(:) = {0};
    end
    
    for i = 1:height(params.net_feature)
        grad = gradients.net_feature.Value{i};
        
        % 更新一阶矩估计
        adamState.avgGrad.net_feature.Value{i} = ...
            beta1 * adamState.avgGrad.net_feature.Value{i} + (1 - beta1) * grad;
        
        % 更新二阶矩估计
        adamState.avgSqGrad.net_feature.Value{i} = ...
            beta2 * adamState.avgSqGrad.net_feature.Value{i} + (1 - beta2) * (grad .^ 2);
        
        % 偏差修正
        m_hat = adamState.avgGrad.net_feature.Value{i} / (1 - beta1^adamState.iter);
        v_hat = adamState.avgSqGrad.net_feature.Value{i} / (1 - beta2^adamState.iter);
        
        % 更新参数
        params.net_feature.Value{i} = params.net_feature.Value{i} - ...
            learningRate * m_hat ./ (sqrt(v_hat) + epsilon);
    end
    
    % 更新其他参数（fc权重和偏置）
    param_names = {'fc_main_weights', 'fc_main_bias', 'fc_turn_weights', ...
                   'fc_turn_bias', 'fc_theta_weights', 'fc_theta_bias'};
    
    for i = 1:length(param_names)
        name = param_names{i};
        grad = gradients.(name);
        
        if ~isfield(adamState.avgGrad, name)
            adamState.avgGrad.(name) = 0;
            adamState.avgSqGrad.(name) = 0;
        end
        
        % 更新矩估计
        adamState.avgGrad.(name) = beta1 * adamState.avgGrad.(name) + (1 - beta1) * grad;
        adamState.avgSqGrad.(name) = beta2 * adamState.avgSqGrad.(name) + (1 - beta2) * (grad .^ 2);
        
        % 偏差修正
        m_hat = adamState.avgGrad.(name) / (1 - beta1^adamState.iter);
        v_hat = adamState.avgSqGrad.(name) / (1 - beta2^adamState.iter);
        
        % 更新参数
        params.(name) = params.(name) - learningRate * m_hat ./ (sqrt(v_hat) + epsilon);
    end
end
function analysis = analyzeModelPerformance(CM, precision, recall, f1, macro_f1, ...
    class_counts, class_names, weight_method)
% 自动分析模型性能并给出改进建议（V1.1新增）
% 输入:
%   CM: 混淆矩阵 [n_classes × n_classes]
%   precision, recall, f1: per-class指标 [n_classes × 1]
%   macro_f1: macro-F1分数
%   class_counts: 训练集类别样本数 [n_classes × 1]
%   class_names: 类别名称 cell array
%   weight_method: 当前使用的类别权重方法
% 输出:
%   analysis: 分析结果结构体
%     .overall_status: 整体评估（字符串）
%     .recommendations: 改进建议（cell array）
%     .warnings: 警告信息（cell array）
%     .metrics: 关键指标汇总

    n_classes = length(class_names);
    analysis = struct();
    analysis.recommendations = {};
    analysis.warnings = {};
    
    % ========== 1. 整体评估 ==========
    if macro_f1 >= 0.85
        analysis.overall_status = '🎯 完美！所有类别表现优秀';
    elseif macro_f1 >= 0.75
        analysis.overall_status = '✅ 良好，但仍有提升空间';
    elseif macro_f1 >= 0.65
        analysis.overall_status = '⚠️ 需要关注，部分类别表现不佳';
    else
        analysis.overall_status = '❌ 需要改进，模型泛化能力不足';
    end
    
    % ========== 2. 类别不平衡分析 ==========
    max_count = max(class_counts);
    min_count = min(class_counts);
    imbalance_ratio = max_count / min_count;
    
    analysis.metrics.imbalance_ratio = imbalance_ratio;
    analysis.metrics.min_class_samples = min_count;
    analysis.metrics.max_class_samples = max_count;
    
    if imbalance_ratio > 10
        analysis.warnings{end+1} = sprintf('严重类别不平衡（比例 %.1f:1），最少类仅%d样本', ...
            imbalance_ratio, min_count);
        analysis.recommendations{end+1} = '🔴 强烈建议：对少数类进行过采样或SMOTE数据增强';
    elseif imbalance_ratio > 5
        analysis.warnings{end+1} = sprintf('中度类别不平衡（比例 %.1f:1）', imbalance_ratio);
        analysis.recommendations{end+1} = '🟡 建议：考虑调整类别权重或适度过采样';
    elseif imbalance_ratio > 3
        analysis.recommendations{end+1} = sprintf('📊 轻度类别不平衡（比例 %.1f:1），当前权重策略（%s）应已充分补偿', ...
            imbalance_ratio, weight_method);
    end
    
    % ========== 3. Per-Class 性能分析 ==========
    low_recall_classes = {};
    low_precision_classes = {};
    low_f1_classes = {};
    low_sample_classes = {};
    
    for c = 1:n_classes
        % 召回率检查
        if recall(c) < 0.60
            low_recall_classes{end+1} = class_names{c};
            analysis.warnings{end+1} = sprintf('%s 召回率极低（%.2f%%），大量漏检！', ...
                class_names{c}, recall(c)*100);
        elseif recall(c) < 0.70
            low_recall_classes{end+1} = class_names{c};
        end
        
        % 精确率检查
        if precision(c) < 0.60
            low_precision_classes{end+1} = class_names{c};
            analysis.warnings{end+1} = sprintf('%s 精确率极低（%.2f%%），可能存在标注错误！', ...
                class_names{c}, precision(c)*100);
        end
        
        % F1检查
        if f1(c) < 0.65
            low_f1_classes{end+1} = class_names{c};
        end
        
        % 样本量检查
        if class_counts(c) < 500
            low_sample_classes{end+1} = sprintf('%s(%d)', class_names{c}, class_counts(c));
        end
    end
    
    % ========== 4. 生成建议 ==========
    
    % 低召回率建议
    if ~isempty(low_recall_classes)
        % 分析原因
        for c = 1:n_classes
            if ismember(class_names{c}, low_recall_classes)
                if precision(c) > 0.75 && recall(c) < 0.70
                    analysis.recommendations{end+1} = sprintf(...
                        '⚖️ %s：高精确率（%.2f）但低召回率（%.2f） → 增加类别权重（当前方法：%s）', ...
                        class_names{c}, precision(c), recall(c), weight_method);
                elseif class_counts(c) < 500
                    analysis.recommendations{end+1} = sprintf(...
                        '📈 %s：样本量不足（%d） → 增加数据或过采样', ...
                        class_names{c}, class_counts(c));
                else
                    analysis.recommendations{end+1} = sprintf(...
                        '🔍 %s：召回率低（%.2f） → 检查特征区分度或增强该类数据多样性', ...
                        class_names{c}, recall(c));
                end
            end
        end
    end
    
    % 低精确率建议
    if ~isempty(low_precision_classes)
        for c = 1:n_classes
            if ismember(class_names{c}, low_precision_classes)
                analysis.recommendations{end+1} = sprintf(...
                    '🔄 %s：精确率低（%.2f） → 检查标注质量或该类与其他类的混淆情况', ...
                    class_names{c}, precision(c));
            end
        end
    end
    
    % 样本量不足建议
    if ~isempty(low_sample_classes)
        analysis.recommendations{end+1} = sprintf(...
            '📊 样本量不足的类别：%s → 建议每类至少收集500+样本', ...
            strjoin(low_sample_classes, ', '));
    end
    
    % ========== 5. 混淆对分析 ==========
    confusion_pairs = {};
    for r = 1:n_classes
        for c = 1:n_classes
            if r ~= c
                confusion_rate = CM(r, c) / sum(CM(r, :));
                if confusion_rate > 0.20  % 超过20%的错分
                    pair_str = sprintf('%s → %s (%.1f%%)', ...
                        class_names{r}, class_names{c}, confusion_rate*100);
                    confusion_pairs{end+1} = pair_str;
                end
            end
        end
    end
    
    if ~isempty(confusion_pairs)
        analysis.warnings{end+1} = '严重混淆对检测：';
        for i = 1:length(confusion_pairs)
            analysis.warnings{end+1} = sprintf('  - %s', confusion_pairs{i});
        end
        analysis.recommendations{end+1} = ...
            '🔍 建议：分析上述混淆对的特征差异，考虑添加区分性特征或数据增强';
    end
    
    % ========== 6. 权重策略建议 ==========
    if strcmp(weight_method, 'inverse') && imbalance_ratio > 5
        analysis.recommendations{end+1} = ...
            '⚖️ 当前使用 inverse 权重，不平衡比例较高 → 可尝试 ''sqrt_inverse'' 平滑权重差异';
    elseif strcmp(weight_method, 'sqrt_inverse') && min(recall) < 0.60
        analysis.recommendations{end+1} = ...
            '⚖️ 当前使用 sqrt_inverse 权重，少数类召回率仍低 → 可尝试 ''inverse'' 增强权重';
    end
    
    % ========== 7. 训练策略建议 ==========
    if macro_f1 < 0.75 && macro_f1 > 0.65
        analysis.recommendations{end+1} = ...
            '📈 macro-F1处于边界值 → 建议增加训练轮数或调整学习率';
    end
    
    % ========== 8. 汇总指标 ==========
    analysis.metrics.macro_f1 = macro_f1;
    analysis.metrics.min_recall = min(recall);
    analysis.metrics.max_recall = max(recall);
    analysis.metrics.min_precision = min(precision);
    analysis.metrics.num_low_recall_classes = length(low_recall_classes);
    analysis.metrics.num_confusion_pairs = length(confusion_pairs);
    
    % 如果没有建议，给予肯定
    if isempty(analysis.recommendations)
        analysis.recommendations{1} = '✨ 模型表现优秀，无需额外调整！';
    end
    
    % 如果没有警告，表示正常
    if isempty(analysis.warnings)
        analysis.warnings{1} = '✅ 无异常警告';
    end
end

