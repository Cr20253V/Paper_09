% =============================
% 文件名：test_gen_paths_v1.m
% 版本号：V2.4
% 最后修改时间：2026-03-11
% 作者：LPV-MPC Project
% 功能描述：
%   测试脚本 - 生成150s工业轻量路径并保存
%   直接运行此脚本即可生成路径文件和可视化图像
%
% 依赖：
%   - parameters.m
%   - gen_agv_ref_path_v1.m (V3.5)
%
% 产物（保存到 data/paths/）：
%   - path_industrial.mat（兼容闭环测试默认加载）
%   - path_industrial_lite.mat（轻量参数版本）
% =============================

clear; clc; close all;

root = project_root();
paths_dir = fullfile(root, 'data', 'paths');
fig_paths_dir = fullfile(root, 'figures', 'paths');
if ~exist(paths_dir, 'dir'), mkdir(paths_dir); end
if ~exist(fig_paths_dir, 'dir'), mkdir(fig_paths_dir); end

%% 载入参数
params = parameters();

%% 生成工业轻量路径
path_type = 'industrial_lite';
fprintf('正在生成路径类型: %s (150s工业轻量路径)...\n', path_type);

opts = struct();
opts.T_end = 150;
opts.v_cruise = 1.0;                    % 保持巡航段 1m/s
opts.slope_angle = deg2rad(10.0);       % 纯坡度区与复合区使用 ±10deg
opts.omega_limit = 0.18;                % 纯转弯区目标平台峰值 0.18 rad/s
opts.transition_time = 1.8;             % 段间过渡更平缓
opts.theta_filter_tau = 0.6;
opts.omega_filter_tau = 0.6;
opts.rho_filter_tau = 0.4;
opts.closure_turn_angle_deg = 80.0;   % V2.4: 增大转角80°使路径更偏向-Y，终点Y靠近起点（omega≈0.064 rad/s）
opts.closure_turn_end = 140.0;       % 拉长时间窗口，omega≈0.040~0.064 rad/s，远低于0.18上限
opts.closure_curve_mid_end = 136.5;
opts.closure_curve_predecel_end = 145.0;
opts.closure_curve1_angle_deg = 18.0;
opts.closure_curve2_angle_deg = 56.0;
opts.closure_curve3_angle_deg = 10.0;
opts.path_type = path_type;

% 生成参考轨迹
ref = gen_agv_ref_path_v1(params, opts);

% 保存到文件
filename_lite = fullfile(paths_dir, sprintf('path_%s.mat', path_type));
save(filename_lite, 'ref');
fprintf('  -> 已保存到: %s\n', filename_lite);

% 兼容现有闭环脚本（默认读取 path_industrial.mat）
filename_compat = fullfile(paths_dir, 'path_industrial.mat');
save(filename_compat, 'ref');
fprintf('  -> 兼容副本已保存到: %s\n', filename_compat);

%% 可视化
visualizePath(ref, path_type, fig_paths_dir);

fprintf('\n路径生成完成！\n');
fprintf('包含 %d 个行驶段落，总时长 %.1f s\n', ref.meta.num_segments, ref.meta.params.T_end);

%% 终点回归自检
dx_end = ref.X_ref(end) - ref.X_ref(1);
dy_end = ref.Y_ref(end) - ref.Y_ref(1);
d_end = hypot(dx_end, dy_end);
dpsi_end = mod((ref.psi_ref(end) - ref.psi_ref(1)) + pi, 2*pi) - pi;
psi_end_deg = rad2deg(dpsi_end);
tol_end = 5.0;  % [m] 终点接近起点阈值
fprintf('终点偏差: dX=%.3f m, dY=%.3f m, dist=%.3f m, dPsi=%.2f deg\n', dx_end, dy_end, d_end, psi_end_deg);
if d_end <= tol_end
    fprintf('  ✓ 终点回归检查通过 (dist <= %.1f m)\n', tol_end);
else
    fprintf('  ⚠ 终点回归检查未通过 (dist > %.1f m)，建议继续微调闭环区参数\n', tol_end);
end

%% 可视化函数
function visualizePath(ref, path_type, fig_paths_dir)
    figure('Name', sprintf('Path: %s', path_type), 'Position', [50, 50, 1400, 800]);
    
    % 子图1: XY轨迹
    subplot(2, 3, 1);
    plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(ref.X_ref(1), ref.Y_ref(1), 'go', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
    plot(ref.X_ref(end), ref.Y_ref(end), 'rs', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    grid on; axis equal;
    xlabel('X [m]'); ylabel('Y [m]');
    title(sprintf('%s - XY轨迹', strrep(path_type, '_', '\_')));
    legend('路径', '起点', '终点', 'Location', 'best');
    
    % 子图2: 速度
    subplot(2, 3, 2);
    plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('速度 [m/s]');
    title('参考速度 v_{ref}');
    ylim([0 1.2]);
    
    % 子图3: 角速度
    subplot(2, 3, 3);
    plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('角速度 [rad/s]');
    title('参考角速度 \omega_{ref}');
    yline(0, 'k--');
    
    % 子图4: 航向角
    subplot(2, 3, 4);
    plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('航向角 [deg]');
    title('参考航向角 \psi_{ref}');
    
    % 子图5: 坡度角
    subplot(2, 3, 5);
    plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.5);
    grid on;
    xlabel('时间 [s]'); ylabel('坡度角 [deg]');
    title('坡度角参考 \theta_{ref}');
    yline(0, 'k--');
    
    % 子图6: 调度变量 rho
    subplot(2, 3, 6);
    yyaxis left;
    plot(ref.t, ref.rho(:, 1), 'r-', 'LineWidth', 1.2); hold on;
    plot(ref.t, ref.rho(:, 2), 'g-', 'LineWidth', 1.2);
    ylabel('v [m/s], \omega [rad/s]');
    yyaxis right;
    plot(ref.t, rad2deg(ref.rho(:, 3)), 'b-', 'LineWidth', 1.2);
    ylabel('\theta [deg]');
    grid on;
    xlabel('时间 [s]');
    legend('v', '\omega', '\theta', 'Location', 'best');
    title('调度变量 \rho (滤波后)');
    
    % 保存图像
    saveas(gcf, fullfile(fig_paths_dir, sprintf('path_%s_preview.png', path_type)));
    fprintf('  -> 图像已保存到: %s\n', fullfile(fig_paths_dir, sprintf('path_%s_preview.png', path_type)));
end
