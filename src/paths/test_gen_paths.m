% =============================
% 文件名：test_gen_paths.m
% 版本号：V1.1
% 最后修改时间：2025-12-29
% 作者：LPV-MPC Project
% 功能描述：
%   测试脚本 - 生成所有路径类型的参考轨迹并保存
%   直接运行此脚本即可生成所有路径文件
%
% 依赖：
%   - parameters.m
%   - gen_agv_ref_path.m
%
% 产物（保存到 data/paths/）：
%   - path_straight.mat
%   - path_straight_left_turn.mat
%   - path_straight_right_turn.mat
%   - path_slope.mat
%   - path_bumpy.mat
%   - path_s_curve.mat
%   - path_multi_turn_left.mat
%   - path_multi_turn_right.mat
% =============================

clear; clc; close all;

root = project_root();
paths_dir = fullfile(root, 'data', 'paths');
fig_paths_dir = fullfile(root, 'figures', 'paths');
if ~exist(paths_dir, 'dir'), mkdir(paths_dir); end
if ~exist(fig_paths_dir, 'dir'), mkdir(fig_paths_dir); end

%% 载入参数
params = parameters();

%% 生成所有路径类型（V1.4：删除 turn，新增 multi_turn_left/right）
path_types = {'straight', 'straight_left_turn', 'straight_right_turn', ...
              'slope', 'bumpy', 's_curve', 'multi_turn_left', 'multi_turn_right'};

for i = 1:length(path_types)
    path_type = path_types{i};
    fprintf('正在生成路径类型: %s ...\n', path_type);
    
    % 生成参考轨迹
    ref = gen_agv_ref_path(path_type, params);
    
    % 保存到文件
    filename = fullfile(paths_dir, sprintf('path_%s.mat', path_type));
    save(filename, 'ref');
    fprintf('  -> 已保存到: %s\n', filename);
    
    % 可视化（可选）
    if true  % 设为 false 可跳过可视化
        visualizePath(ref, path_type, fig_paths_dir);
    end
end

fprintf('\n所有路径生成完成！共 %d 种路径。\n', length(path_types));

%% 可视化函数
function visualizePath(ref, path_type, fig_paths_dir)
    figure('Name', sprintf('Path: %s', path_type), 'Position', [100, 100, 1200, 600]);
    
    % 子图1: XY轨迹
    subplot(2, 3, 1);
    plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.5);
    grid on; axis equal;
    xlabel('X [m]'); ylabel('Y [m]');
    title(sprintf('%s - XY轨迹', strrep(path_type, '_', '\_')));
    
    % 子图2: 速度
    subplot(2, 3, 2);
    plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('速度 [m/s]');
    title('参考速度');
    
    % 子图3: 角速度
    subplot(2, 3, 3);
    plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('角速度 [rad/s]');
    title('参考角速度');
    
    % 子图4: 航向角
    subplot(2, 3, 4);
    plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('航向角 [deg]');
    title('参考航向角');
    
    % 子图5: 坡度角
    subplot(2, 3, 5);
    plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('坡度角 [deg]');
    title('坡度角参考');
    
    % 子图6: 调度变量 rho
    subplot(2, 3, 6);
    plot(ref.t, ref.rho(:, 1), 'r-', 'LineWidth', 1.5); hold on;
    plot(ref.t, ref.rho(:, 2), 'g-', 'LineWidth', 1.5);
    plot(ref.t, rad2deg(ref.rho(:, 3)), 'b-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('调度变量');
    legend('v [m/s]', 'ω [rad/s]', 'θ [deg]');
    title('调度变量 ρ (滤波后)');
    
    % 保存图像
    saveas(gcf, fullfile(fig_paths_dir, sprintf('path_%s_preview.png', path_type)));
end
