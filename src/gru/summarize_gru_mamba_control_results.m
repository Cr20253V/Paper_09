% =============================
% 文件名：summarize_gru_mamba_control_results.m
% 版本号：V1.0（GRU 对照组结果汇总脚本）
% 最后修改时间：2026-04-15
% 作者：LPV-MPC Project
% 功能描述：
%   对比两组 GRU 对照实验结果：
%   1) strict 同分布对照
%   2) stall 优化版（重采样/权重优化）
%   并输出关键指标与差值，便于快速判断取舍。
%
% 使用方法：
%   直接运行脚本：run('src/gru/summarize_gru_mamba_control_results.m')
%   或预先在工作区覆写 cfg 字段后运行。
%
% 可覆写配置（cfg）：
%   cfg.meta_strict_file
%   cfg.meta_opt_file
%   cfg.label_strict
%   cfg.label_opt
% =============================

root = project_root();

if ~exist('cfg', 'var') || ~isstruct(cfg)
    cfg = struct();
end

if ~isfield(cfg, 'meta_strict_file')
    cfg.meta_strict_file = fullfile(root, 'data', 'models', 'GRU_meta_mamba_control_strict.mat');
end
if ~isfield(cfg, 'meta_opt_file')
    cfg.meta_opt_file = fullfile(root, 'data', 'models', 'GRU_meta_mamba_control_opt.mat');
end
if ~isfield(cfg, 'label_strict')
    cfg.label_strict = 'strict_same_distribution';
end
if ~isfield(cfg, 'label_opt')
    cfg.label_opt = 'stall_optimized';
end

if ~exist(cfg.meta_strict_file, 'file')
    error('未找到 strict 元数据文件: %s', cfg.meta_strict_file);
end
if ~exist(cfg.meta_opt_file, 'file')
    % 向后兼容：若未找到 _opt 文件，回退到历史文件名
    legacy_opt_file = fullfile(root, 'data', 'models', 'GRU_meta_mamba_control.mat');
    if exist(legacy_opt_file, 'file')
        cfg.meta_opt_file = legacy_opt_file;
    else
        error('未找到优化版元数据文件: %s', cfg.meta_opt_file);
    end
end

S1 = load(cfg.meta_strict_file, 'meta');
S2 = load(cfg.meta_opt_file, 'meta');

m1 = extract_metrics(S1.meta);
m2 = extract_metrics(S2.meta);

fprintf('\n========================================\n');
fprintf('GRU 对照实验结果汇总\n');
fprintf('========================================\n');
fprintf('A: %s\n', cfg.label_strict);
fprintf('B: %s\n', cfg.label_opt);
fprintf('\n');

print_row('acc_main(%)', 100*m1.acc_main, 100*m2.acc_main, true);
print_row('acc_turn(%)', 100*m1.acc_turn, 100*m2.acc_turn, true);
print_row('mae_theta(deg)', m1.mae_theta_deg, m2.mae_theta_deg, false);
print_row('macro_f1', m1.macro_f1, m2.macro_f1, true);
print_row('stall_precision', m1.stall_precision, m2.stall_precision, true);
print_row('stall_recall', m1.stall_recall, m2.stall_recall, true);
print_row('stall_f1', m1.stall_f1, m2.stall_f1, true);

fprintf('\n说明：Δ = B - A（B 为优化版）。\n');
fprintf('  正向指标（越大越好）：acc_main, acc_turn, macro_f1, stall_precision/recall/f1\n');
fprintf('  反向指标（越小越好）：mae_theta(deg)\n');

function m = extract_metrics(meta)
    m = struct();
    m.acc_main = NaN;
    m.acc_turn = NaN;
    m.mae_theta_deg = NaN;
    m.macro_f1 = NaN;
    m.stall_precision = NaN;
    m.stall_recall = NaN;
    m.stall_f1 = NaN;

    if isfield(meta, 'test_metrics')
        tm = meta.test_metrics;
        if isfield(tm, 'test_acc_main'); m.acc_main = tm.test_acc_main; end
        if isfield(tm, 'test_acc_turn'); m.acc_turn = tm.test_acc_turn; end
        if isfield(tm, 'test_mae_theta'); m.mae_theta_deg = rad2deg(tm.test_mae_theta); end
    end

    if isfield(meta, 'test_detailed')
        td = meta.test_detailed;
        if isfield(td, 'macro_f1'); m.macro_f1 = td.macro_f1; end
        if isfield(td, 'class_names') && isfield(td, 'precision') && isfield(td, 'recall') && isfield(td, 'f1')
            idx_stall = find(strcmp(td.class_names, 'stall'), 1);
            if ~isempty(idx_stall)
                m.stall_precision = td.precision(idx_stall);
                m.stall_recall = td.recall(idx_stall);
                m.stall_f1 = td.f1(idx_stall);
            end
        end
    end
end

function print_row(name, a, b, higher_is_better)
    d = b - a;
    if higher_is_better
        trend = 'improved';
        if d < 0
            trend = 'degraded';
        end
    else
        trend = 'improved';
        if d > 0
            trend = 'degraded';
        end
    end

    fprintf('%-16s | A=%9.4f | B=%9.4f | Δ=%+9.4f | %s\n', name, a, b, d, trend);
end
