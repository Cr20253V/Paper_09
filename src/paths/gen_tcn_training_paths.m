% =============================
% 文件名：gen_tcn_training_paths.m
% 版本号：V1.1
% 最后修改时间：2026-04-28
% 作者：LPV-MPC Project
%
% 功能描述：
%   为 Physics-Guided Multi-task TCN 生成训练用参考轨迹。
%   本脚本只生成 ref 路径文件，不运行 Simulink，不生成 y_raw 训练数据。
%
% 设计原则：
%   1. 默认路径长度以 15-40 s 短片段为主，提高坡度、转弯、扰动建议窗口、
%      堵转建议窗口等局部过渡样本密度。
%      Future ModernTCN profile sets should be added from a clean design.
%   2. 路径参数遵守当前 AGV 车体与 MPC 约束，避免生成不可跟踪或明显
%      超出 LPV 调度网格的参考轨迹。
%   3. 路径文件保存到 data/paths，文件名前缀为 path_train_tcn_，
%      便于和成果展示长路径、历史路径区分。
%   4. 每条 ref 保持现有工程契约：
%      ref.t, ref.X_ref, ref.Y_ref, ref.psi_ref, ref.v_ref,
%      ref.omega_ref, ref.theta_ref, ref.e_y_ref, ref.e_psi_ref,
%      ref.e_v_ref, ref.rho, ref.time, ref.signals。
%
% 约束依据：
%   - AGV 输入：u = [F_cmd; omega_cmd; theta_ground]
%   - MPC 输入约束默认值：
%       F_cmd in [-600, 600] N
%       omega_cmd in [-1.2, 1.2] rad/s
%   - LPV 调度变量：
%       rho = [v, omega, theta]
%     若 data/models/lin_agv_db.mat 存在，则自动读取调度网格范围。
%   - 当前第一阶段固定 Ts = parameters().Ts，通常为 0.01 s。
%
% 使用方法：
%   init_project;
%   run('src/paths/gen_tcn_training_paths.m');
%
% 产物：
%   data/paths/path_train_tcn_*.mat
%   data/paths/path_train_tcn_manifest.csv
%   figures/paths/path_train_tcn_*_preview.png
% 可选高级用法：
%   调用前在工作区放置 gen_tcn_training_paths_cfg 结构体，可覆盖：
%   seed, rho_filter_tau, make_figures, profile_set, path_prefix,
%   manifest_name, figure_prefix。默认行为与 V1.0 完全一致。
% =============================

if exist('gen_tcn_training_paths_cfg', 'var') && isstruct(gen_tcn_training_paths_cfg)
    user_cfg = gen_tcn_training_paths_cfg;
else
    user_cfg = struct();
end
clearvars -except user_cfg;
clc;

%% 0. 项目路径与输出目录
if exist('init_project', 'file') == 2
    init_project();
end

root = project_root();
paths_dir = fullfile(root, 'data', 'paths');
fig_paths_dir = fullfile(root, 'figures', 'paths');
if ~exist(paths_dir, 'dir'), mkdir(paths_dir); end
if ~exist(fig_paths_dir, 'dir'), mkdir(fig_paths_dir); end

%% 1. 读取车辆与控制约束
params = parameters();
Ts = params.Ts;

limits = local_read_constraints(root, params);
local_print_constraint_summary(limits, Ts);

% 第一阶段明确使用 0.01 s。若后续切换 0.02 s，应同步重建 LPV 数据库和对照基线。
if abs(Ts - 0.01) > 1e-12
    warning('gen_tcn_training_paths:TsNotDefault', ...
        ['当前 parameters().Ts = %.4f s，不是第一阶段推荐的 0.01 s。' ...
         '若这是有意修改，请确认 LPV/MPC/GRU/TCN 对照链路均已同步。'], Ts);
end

%% 2. 路径生成配置
cfg = struct();
cfg.seed = local_cfg(user_cfg, 'seed', 20260424);
cfg.rho_filter_tau = local_cfg(user_cfg, 'rho_filter_tau', 0.4);
cfg.make_figures = local_cfg(user_cfg, 'make_figures', true);
cfg.profile_set = local_cfg(user_cfg, 'profile_set', 'v1');
cfg.path_prefix = local_cfg(user_cfg, 'path_prefix', 'path_train_tcn_');
cfg.manifest_name = local_cfg(user_cfg, 'manifest_name', 'path_train_tcn_manifest.csv');
cfg.figure_prefix = local_cfg(user_cfg, 'figure_prefix', 'path_train_tcn_');

% 生成策略：
%   conservative: 工业合理主样本
%   boundary:     贴近边界但不超限
%   challenge:    少量极端挑战样本，用于增强鲁棒性或单独测试
cfg.profiles = local_build_profile_table(cfg.profile_set);

rng(cfg.seed, 'twister');

%% 3. 生成路径
manifest = repmat(local_manifest_row_template(), numel(cfg.profiles), 1);

fprintf('\n[TCN paths] Start generating %d training paths...\n', numel(cfg.profiles));
for i = 1:numel(cfg.profiles)
    spec = cfg.profiles(i);
    spec = local_clip_spec_to_limits(spec, limits);
    ref = local_generate_ref_from_spec(spec, params, cfg, limits);
    local_validate_ref(ref, limits);

    file_name = sprintf('%s%02d_%s.mat', cfg.path_prefix, i, spec.name);
    out_file = fullfile(paths_dir, file_name);
    save(out_file, 'ref');

    manifest(i) = local_manifest_from_ref(i, file_name, out_file, spec, ref, limits);
    fprintf('[%02d/%02d] %-34s T=%5.1fs | v=[%.2f, %.2f] | omega=[%.3f, %.3f] | theta=[%.1f, %.1f] deg\n', ...
        i, numel(cfg.profiles), file_name, ref.t(end), ...
        min(ref.v_ref), max(ref.v_ref), min(ref.omega_ref), max(ref.omega_ref), ...
        min(rad2deg(ref.theta_ref)), max(rad2deg(ref.theta_ref)));

    if cfg.make_figures
        local_visualize_path(ref, spec.name, fig_paths_dir, cfg.figure_prefix);
    end
end

manifest_tbl = struct2table(manifest);
manifest_file = fullfile(paths_dir, cfg.manifest_name);
writetable(manifest_tbl, manifest_file);

fprintf('\n[TCN paths] Done.\n');
fprintf('  Paths:    %s\n', paths_dir);
fprintf('  Manifest: %s\n', manifest_file);
fprintf('  Figures:  %s\n', fig_paths_dir);

%% ==================== 本地函数 ====================

function v = local_cfg(cfg, field_name, default_value)
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    v = cfg.(field_name);
else
    v = default_value;
end
end

function limits = local_read_constraints(root, params)
% 读取 AGV/MPC/LPV 约束范围。缺失文件时使用保守默认值。
limits = struct();

% 车辆和执行器基本约束
limits.Ts = params.Ts;
limits.v_min_design = 0.55;
limits.v_max_design = 1.50;
limits.omega_abs_design = 0.28;
limits.theta_abs_design = deg2rad(8.0);
limits.theta_abs_main = deg2rad(6.0);
limits.turn_transition_min = 1.0;
limits.slope_transition_min = 1.0;

% MPC 默认约束，来自 mpc_setup_single_interp.m
limits.F_cmd_min = -600;
limits.F_cmd_max = 600;
limits.omega_cmd_min = -1.2;
limits.omega_cmd_max = 1.2;
limits.dF_step_min = -400;
limits.dF_step_max = 400;
limits.domega_step_min = -0.9;
limits.domega_step_max = 0.9;

% 从 LPV 数据库读取调度网格。若不存在则保持保守默认。
limits.has_db = false;
db_file = fullfile(root, 'data', 'models', 'lin_agv_db.mat');
if exist(db_file, 'file')
    S = load(db_file);
    if isfield(S, 'db')
        db = S.db;
    else
        db = S;
    end
    if isfield(db, 'grid') && all(isfield(db.grid, {'V', 'W', 'T'}))
        limits.has_db = true;
        limits.v_grid_min = min(db.grid.V(:));
        limits.v_grid_max = max(db.grid.V(:));
        limits.omega_grid_min = min(db.grid.W(:));
        limits.omega_grid_max = max(db.grid.W(:));
        limits.theta_grid_min = min(db.grid.T(:));
        limits.theta_grid_max = max(db.grid.T(:));

        % 路径设计留出安全边界，避免参考长期贴住 LPV 网格端点。
        limits.v_min_design = max(limits.v_min_design, limits.v_grid_min + 0.05);
        limits.v_max_design = min(limits.v_max_design, limits.v_grid_max - 0.05);
        limits.omega_abs_design = min(limits.omega_abs_design, 0.90 * max(abs([limits.omega_grid_min, limits.omega_grid_max])));
        limits.theta_abs_design = min(limits.theta_abs_design, 0.90 * max(abs([limits.theta_grid_min, limits.theta_grid_max])));
    end
end

% 依据坡度阻力检查 F_cmd 可行性：m*g*sin(theta)+滚阻+风阻应远低于 600 N。
% 8 deg 对 200 kg AGV 约为 273 N 坡度阻力，加滚阻/风阻仍留有余量。
limits.F_equilibrium_margin = 0.80 * limits.F_cmd_max;
end

function local_print_constraint_summary(limits, Ts)
fprintf('\n========== TCN Training Path Constraint Summary ==========\n');
fprintf('Ts = %.4f s\n', Ts);
fprintf('Design v range      : [%.2f, %.2f] m/s\n', limits.v_min_design, limits.v_max_design);
fprintf('Design |omega| max  : %.3f rad/s\n', limits.omega_abs_design);
fprintf('Design |theta| max  : %.2f deg\n', rad2deg(limits.theta_abs_design));
fprintf('MPC F_cmd range     : [%.0f, %.0f] N\n', limits.F_cmd_min, limits.F_cmd_max);
fprintf('MPC omega_cmd range : [%.2f, %.2f] rad/s\n', limits.omega_cmd_min, limits.omega_cmd_max);
if limits.has_db
    fprintf('LPV grid v          : [%.2f, %.2f] m/s\n', limits.v_grid_min, limits.v_grid_max);
    fprintf('LPV grid omega      : [%.3f, %.3f] rad/s\n', limits.omega_grid_min, limits.omega_grid_max);
    fprintf('LPV grid theta      : [%.2f, %.2f] deg\n', rad2deg(limits.theta_grid_min), rad2deg(limits.theta_grid_max));
else
    fprintf('LPV grid            : not found, using conservative defaults.\n');
end
fprintf('==========================================================\n');
end

function profiles = local_build_profile_table(profile_set)
% 构造训练短路径集合。
% 每条路径通过分段事件描述，事件使用 smoothstep 过渡，避免角速度/坡度突变。
if nargin < 1 || isempty(profile_set)
    profile_set = 'v1';
end
profiles = struct('name', {}, 'tier', {}, 'T_end', {}, 'v0', {}, 'events', {}, 'recommended_injection_windows', {});

profiles(end+1) = local_profile('flat_speed_variation', 'conservative', 18, 1.00, { ...
    local_event('speed', 3.0, 5.0, 1.20), ...
    local_event('speed', 11.0, 13.0, 0.80)}, {[6, 9], [13, 16]});

profiles(end+1) = local_profile('left_turn_entry_exit', 'conservative', 20, 1.00, { ...
    local_event('omega', 3.0, 4.2, 0.16), ...
    local_event('omega', 12.0, 13.2, 0.00)}, {[5, 8], [14, 17]});

profiles(end+1) = local_profile('right_turn_entry_exit', 'conservative', 20, 1.00, { ...
    local_event('omega', 3.0, 4.2, -0.16), ...
    local_event('omega', 12.0, 13.2, 0.00)}, {[5, 8], [14, 17]});

profiles(end+1) = local_profile('slope_up_down', 'conservative', 24, 1.00, { ...
    local_event('theta', 3.0, 5.0, deg2rad(5.0)), ...
    local_event('theta', 15.0, 17.0, 0.00)}, {[6, 10], [18, 21]});

profiles(end+1) = local_profile('down_slope_recovery', 'conservative', 24, 1.00, { ...
    local_event('theta', 3.0, 5.0, deg2rad(-4.0)), ...
    local_event('theta', 15.0, 17.0, 0.00)}, {[6, 10], [18, 21]});

profiles(end+1) = local_profile('s_curve_balanced', 'conservative', 28, 1.00, { ...
    local_event('omega', 3.0, 4.2, -0.15), ...
    local_event('omega', 10.0, 11.2, 0.15), ...
    local_event('omega', 18.0, 19.2, 0.00)}, {[5, 8], [12, 15], [20, 24]});

profiles(end+1) = local_profile('slope_left_turn_combo', 'conservative', 30, 1.00, { ...
    local_event('theta', 3.0, 5.0, deg2rad(4.5)), ...
    local_event('omega', 8.0, 9.2, 0.14), ...
    local_event('omega', 18.0, 19.2, 0.00), ...
    local_event('theta', 22.0, 24.0, 0.00)}, {[10, 14], [24, 28]});

profiles(end+1) = local_profile('slope_right_turn_combo', 'conservative', 30, 1.00, { ...
    local_event('theta', 3.0, 5.0, deg2rad(4.5)), ...
    local_event('omega', 8.0, 9.2, -0.14), ...
    local_event('omega', 18.0, 19.2, 0.00), ...
    local_event('theta', 22.0, 24.0, 0.00)}, {[10, 14], [24, 28]});

profiles(end+1) = local_profile('load_change_candidate', 'conservative', 22, 0.95, { ...
    local_event('speed', 4.0, 6.0, 0.75), ...
    local_event('theta', 8.0, 10.0, deg2rad(3.0)), ...
    local_event('theta', 16.0, 18.0, 0.00)}, {[6, 9], [12, 16]});

profiles(end+1) = local_profile('stall_candidate_low_speed', 'conservative', 20, 0.85, { ...
    local_event('speed', 3.0, 5.0, 0.60), ...
    local_event('speed', 12.0, 14.0, 1.00)}, {[6, 10]});

profiles(end+1) = local_profile('multi_turn_left_variable_radius', 'boundary', 32, 1.10, { ...
    local_event('omega', 3.0, 4.0, 0.20), ...
    local_event('omega', 10.0, 11.0, 0.12), ...
    local_event('omega', 17.0, 18.0, 0.22), ...
    local_event('omega', 25.0, 26.0, 0.00)}, {[5, 8], [19, 23], [27, 30]});

profiles(end+1) = local_profile('multi_turn_right_variable_radius', 'boundary', 32, 1.10, { ...
    local_event('omega', 3.0, 4.0, -0.20), ...
    local_event('omega', 10.0, 11.0, -0.12), ...
    local_event('omega', 17.0, 18.0, -0.22), ...
    local_event('omega', 25.0, 26.0, 0.00)}, {[5, 8], [19, 23], [27, 30]});

profiles(end+1) = local_profile('steep_slope_transition', 'boundary', 28, 1.00, { ...
    local_event('theta', 3.0, 4.5, deg2rad(6.0)), ...
    local_event('speed', 8.0, 10.0, 0.80), ...
    local_event('theta', 18.0, 20.0, 0.00), ...
    local_event('speed', 21.0, 23.0, 1.10)}, {[5, 9], [10, 15]});

profiles(end+1) = local_profile('downhill_turn_transition', 'boundary', 30, 1.00, { ...
    local_event('theta', 3.0, 4.5, deg2rad(-5.5)), ...
    local_event('omega', 8.0, 9.0, 0.18), ...
    local_event('omega', 17.0, 18.0, 0.00), ...
    local_event('theta', 21.0, 23.0, 0.00)}, {[10, 14], [23, 27]});

profiles(end+1) = local_profile('bumpy_theta_local', 'boundary', 30, 1.00, { ...
    local_event('theta_sine', 4.0, 20.0, deg2rad(3.0), 0.45)}, {[6, 9], [15, 19], [22, 26]});

profiles(end+1) = local_profile('disturbance_transition_meta', 'boundary', 26, 1.00, { ...
    local_event('omega', 4.0, 5.2, -0.16), ...
    local_event('theta', 9.0, 10.5, deg2rad(4.0)), ...
    local_event('omega', 15.0, 16.0, 0.00), ...
    local_event('theta', 19.0, 21.0, 0.00)}, {[6, 8], [11, 14], [21, 24]});

profiles(end+1) = local_profile('challenge_fast_s_curve', 'challenge', 26, 1.25, { ...
    local_event('omega', 3.0, 3.8, -0.24), ...
    local_event('omega', 9.0, 9.8, 0.24), ...
    local_event('omega', 16.0, 17.0, 0.00)}, {[5, 8], [11, 14], [18, 23]});

profiles(end+1) = local_profile('challenge_steep_combo', 'challenge', 34, 1.10, { ...
    local_event('theta', 3.0, 4.0, deg2rad(7.5)), ...
    local_event('omega', 8.0, 9.0, 0.22), ...
    local_event('omega', 18.0, 19.0, -0.18), ...
    local_event('omega', 25.0, 26.0, 0.00), ...
    local_event('theta', 28.0, 30.0, 0.00)}, {[10, 14], [20, 24], [30, 33]});

profile_set = lower(char(profile_set));
switch profile_set
    case 'v1'
        % 默认 V1 路径集合保持不变。
    case 'v3_transition_rich'
        profiles = local_append_v3_transition_rich_profiles(profiles);
    case 'v4_industrial'
        profiles = local_build_v4_industrial_profiles();
    otherwise
        error('Unknown TCN path profile_set: %s', profile_set);
end
end

function profiles = local_append_v3_transition_rich_profiles(profiles)
% V3 针对 transition-rich v2 暴露出的短板补充路径：
%   1. 负坡样本偏少；
%   2. 坡度变化和转弯变化真正重叠的样本不足；
%   3. 多数坡度路径是“过渡 + 平台 + 回落”，连续变化坡度覆盖不足。

profiles(end+1) = local_profile('v3_uphill_left_overlap_entry', 'transition_v3', 32, 1.00, { ...
    local_event('theta', 3.0, 7.0, deg2rad(5.5)), ...
    local_event('omega', 4.5, 6.5, 0.16), ...
    local_event('omega', 15.0, 17.0, 0.00), ...
    local_event('theta', 20.0, 24.0, 0.00)}, {[4, 8], [14, 18], [20, 25]});

profiles(end+1) = local_profile('v3_uphill_right_overlap_entry', 'transition_v3', 32, 1.00, { ...
    local_event('theta', 3.0, 7.0, deg2rad(5.5)), ...
    local_event('omega', 4.5, 6.5, -0.16), ...
    local_event('omega', 15.0, 17.0, 0.00), ...
    local_event('theta', 20.0, 24.0, 0.00)}, {[4, 8], [14, 18], [20, 25]});

profiles(end+1) = local_profile('v3_downhill_left_overlap_entry', 'transition_v3', 32, 1.00, { ...
    local_event('theta', 3.0, 7.0, deg2rad(-5.5)), ...
    local_event('omega', 4.5, 6.5, 0.16), ...
    local_event('omega', 15.0, 17.0, 0.00), ...
    local_event('theta', 20.0, 24.0, 0.00)}, {[4, 8], [14, 18], [20, 25]});

profiles(end+1) = local_profile('v3_downhill_right_overlap_entry', 'transition_v3', 32, 1.00, { ...
    local_event('theta', 3.0, 7.0, deg2rad(-5.5)), ...
    local_event('omega', 4.5, 6.5, -0.16), ...
    local_event('omega', 15.0, 17.0, 0.00), ...
    local_event('theta', 20.0, 24.0, 0.00)}, {[4, 8], [14, 18], [20, 25]});

profiles(end+1) = local_profile('v3_uphill_left_overlap_exit', 'transition_v3', 34, 1.05, { ...
    local_event('theta', 3.0, 5.5, deg2rad(5.0)), ...
    local_event('omega', 9.0, 11.0, 0.18), ...
    local_event('theta', 14.0, 18.0, 0.00), ...
    local_event('omega', 15.0, 18.0, 0.00)}, {[8, 12], [14, 19], [21, 25]});

profiles(end+1) = local_profile('v3_downhill_right_overlap_exit', 'transition_v3', 34, 1.05, { ...
    local_event('theta', 3.0, 5.5, deg2rad(-5.0)), ...
    local_event('omega', 9.0, 11.0, -0.18), ...
    local_event('theta', 14.0, 18.0, 0.00), ...
    local_event('omega', 15.0, 18.0, 0.00)}, {[8, 12], [14, 19], [21, 25]});

profiles(end+1) = local_profile('v3_long_ramp_up_left_turn', 'transition_v3', 36, 1.00, { ...
    local_event('theta', 3.0, 15.0, deg2rad(6.0)), ...
    local_event('omega', 7.0, 9.0, 0.14), ...
    local_event('omega', 19.0, 21.0, 0.00), ...
    local_event('theta', 24.0, 32.0, 0.00)}, {[6, 10], [12, 16], [23, 32]});

profiles(end+1) = local_profile('v3_long_ramp_down_right_turn', 'transition_v3', 36, 1.00, { ...
    local_event('theta', 3.0, 15.0, deg2rad(-6.0)), ...
    local_event('omega', 7.0, 9.0, -0.14), ...
    local_event('omega', 19.0, 21.0, 0.00), ...
    local_event('theta', 24.0, 32.0, 0.00)}, {[6, 10], [12, 16], [23, 32]});

profiles(end+1) = local_profile('v3_theta_reversal_s_curve', 'transition_v3', 40, 1.05, { ...
    local_event('theta', 3.0, 11.0, deg2rad(5.0)), ...
    local_event('omega', 6.0, 8.0, -0.14), ...
    local_event('theta', 12.0, 22.0, deg2rad(-5.0)), ...
    local_event('omega', 16.0, 18.0, 0.14), ...
    local_event('omega', 26.0, 28.0, 0.00), ...
    local_event('theta', 29.0, 36.0, 0.00)}, {[5, 9], [12, 22], [25, 30], [31, 37]});

profiles(end+1) = local_profile('v3_theta_sine_left_turn', 'transition_v3', 34, 1.00, { ...
    local_event('theta_sine', 3.0, 25.0, deg2rad(4.0), 0.18181818), ...
    local_event('omega', 7.0, 9.0, 0.15), ...
    local_event('omega', 20.0, 22.0, 0.00)}, {[6, 10], [13, 18], [21, 27]});

profiles(end+1) = local_profile('v3_theta_sine_right_turn', 'transition_v3', 34, 1.00, { ...
    local_event('theta_sine', 3.0, 25.0, deg2rad(4.0), 0.18181818), ...
    local_event('omega', 7.0, 9.0, -0.15), ...
    local_event('omega', 20.0, 22.0, 0.00)}, {[6, 10], [13, 18], [21, 27]});

profiles(end+1) = local_profile('v3_fast_slope_step_left', 'transition_v3', 30, 1.00, { ...
    local_event('theta', 3.0, 4.0, deg2rad(4.5)), ...
    local_event('omega', 3.8, 5.0, 0.17), ...
    local_event('omega', 12.0, 13.2, 0.00), ...
    local_event('theta', 18.0, 19.0, 0.00)}, {[3, 6], [11, 14], [17, 20]});

profiles(end+1) = local_profile('v3_slow_slope_step_right', 'transition_v3', 38, 1.00, { ...
    local_event('theta', 3.0, 8.5, deg2rad(-4.5)), ...
    local_event('omega', 5.0, 8.0, -0.17), ...
    local_event('omega', 18.0, 21.0, 0.00), ...
    local_event('theta', 24.0, 30.0, 0.00)}, {[4, 9], [17, 22], [23, 31]});

profiles(end+1) = local_profile('v3_speed_slope_turn_coupled', 'transition_v3', 36, 1.10, { ...
    local_event('speed', 3.0, 6.0, 0.80), ...
    local_event('theta', 4.0, 8.0, deg2rad(5.0)), ...
    local_event('omega', 6.0, 8.5, -0.16), ...
    local_event('omega', 17.0, 19.0, 0.00), ...
    local_event('theta', 22.0, 27.0, deg2rad(-3.5)), ...
    local_event('theta', 30.0, 34.0, 0.00)}, {[4, 9], [16, 20], [22, 28], [30, 35]});

% V3.1: industrial_lite closed-loop diagnostic showed a targeted gap:
% low-load flat turns are confused with slope, and turn recall drops on
% mild slope-turn composites. Add short hard-negative samples instead of
% copying the whole diagnostic path into training.
profiles(end+1) = local_profile('v3_flat_low_load_left_turn', 'transition_v3', 28, 0.72, { ...
    local_event('omega', 4.0, 6.0, 0.10), ...
    local_event('omega', 18.0, 20.0, 0.00)}, {[5, 9], [16, 21]});

profiles(end+1) = local_profile('v3_flat_low_load_right_turn', 'transition_v3', 28, 0.72, { ...
    local_event('omega', 4.0, 6.0, -0.10), ...
    local_event('omega', 18.0, 20.0, 0.00)}, {[5, 9], [16, 21]});

profiles(end+1) = local_profile('v3_flat_low_load_s_curve', 'transition_v3', 34, 0.78, { ...
    local_event('omega', 4.0, 6.0, 0.09), ...
    local_event('omega', 13.0, 15.0, -0.09), ...
    local_event('omega', 23.0, 25.0, 0.00)}, {[5, 9], [12, 17], [22, 27]});

profiles(end+1) = local_profile('v3_flat_left_turn_speed_sweep', 'transition_v3', 34, 0.68, { ...
    local_event('speed', 4.0, 8.0, 0.95), ...
    local_event('omega', 6.0, 8.0, 0.08), ...
    local_event('omega', 20.0, 22.0, 0.00), ...
    local_event('speed', 24.0, 28.0, 0.70)}, {[6, 10], [18, 23], [24, 29]});

profiles(end+1) = local_profile('v3_flat_right_turn_speed_sweep', 'transition_v3', 34, 0.68, { ...
    local_event('speed', 4.0, 8.0, 0.95), ...
    local_event('omega', 6.0, 8.0, -0.08), ...
    local_event('omega', 20.0, 22.0, 0.00), ...
    local_event('speed', 24.0, 28.0, 0.70)}, {[6, 10], [18, 23], [24, 29]});

profiles(end+1) = local_profile('v3_mild_slope_low_load_left_turn', 'transition_v3', 34, 0.78, { ...
    local_event('theta', 3.5, 7.0, deg2rad(3.5)), ...
    local_event('omega', 7.0, 9.0, 0.08), ...
    local_event('omega', 18.0, 20.0, 0.00), ...
    local_event('theta', 23.0, 27.0, 0.00)}, {[6, 10], [17, 21], [22, 28]});

profiles(end+1) = local_profile('v3_mild_slope_low_load_right_turn', 'transition_v3', 34, 0.78, { ...
    local_event('theta', 3.5, 7.0, deg2rad(-3.5)), ...
    local_event('omega', 7.0, 9.0, -0.08), ...
    local_event('omega', 18.0, 20.0, 0.00), ...
    local_event('theta', 23.0, 27.0, 0.00)}, {[6, 10], [17, 21], [22, 28]});

profiles(end+1) = local_profile('v3_flat_low_speed_closure_turn', 'transition_v3', 38, 0.95, { ...
    local_event('speed', 5.0, 10.0, 0.62), ...
    local_event('omega', 12.0, 15.0, 0.07), ...
    local_event('omega', 25.0, 28.0, 0.00), ...
    local_event('speed', 30.0, 34.0, 0.90)}, {[9, 16], [24, 29], [30, 35]});
end

function profiles = local_build_v4_industrial_profiles()
% V4 industrial main training paths.
% Design intent:
%   - make clean/flat turns part of the base path set, not a later merge;
%   - cover speed and radius grids densely enough for industrial turning;
%   - keep theta dense enough for training, but not the paper-only 0.1 deg grid;
%   - avoid full Cartesian explosion across speed, radius, theta, direction.

profiles = struct('name', {}, 'tier', {}, 'T_end', {}, 'v0', {}, 'events', {}, 'recommended_injection_windows', {});

speed_grid = [0.80, 0.90, 1.00, 1.10];
radius_grid = 6:12;
theta_levels = [-8:-1, 1:8];
theta_combo_levels = [-6, -5, -4, -3, 3, 4, 5, 6];
dirs = [-1, 1];

% Flat straight speed anchors.
for iv = 1:numel(speed_grid)
    v0 = speed_grid(iv);
    profiles(end+1) = local_profile( ...
        sprintf('v4_flat_straight_v%02d', round(10*v0)), ...
        'v4_flat', 24, v0, { ...
        local_event('speed', 6.0, 9.0, min(1.10, v0 + 0.10)), ...
        local_event('speed', 15.0, 18.0, v0)}, {[5, 10], [14, 19]}); %#ok<AGROW>
end

% Integrated clean-turn radius/speed grid. These replace the old
% post-generated clean-turn augmentation in the main path set.
for iv = 1:numel(speed_grid)
    v0 = speed_grid(iv);
    for ir = 1:numel(radius_grid)
        R = radius_grid(ir);
        omega_abs = v0 / R;
        for id = 1:numel(dirs)
            sgn = dirs(id);
            name = local_v4_name('flat_turn', v0, R, 0, sgn);
            profiles(end+1) = local_profile(name, 'v4_clean_turn', 30, v0, { ...
                local_event('omega', 4.0, 6.0, sgn * omega_abs), ...
                local_event('omega', 20.0, 22.0, 0.00)}, {[5, 9], [18, 23]}); %#ok<AGROW>
        end
    end
end

% Straight slope grid. This is the main theta coverage for training. The
% dense 0.1 deg set should be kept for a separate paper/evaluation dataset.
for iv = 1:numel(speed_grid)
    v0 = speed_grid(iv);
    for it = 1:numel(theta_levels)
        th_deg = theta_levels(it);
        profiles(end+1) = local_profile( ...
            sprintf('v4_slope_straight_v%02d_th%s', round(10*v0), local_v4_deg_token(th_deg)), ...
            'v4_slope', 30, v0, { ...
            local_event('theta', 4.0, 8.0, deg2rad(th_deg)), ...
            local_event('theta', 21.0, 25.0, 0.00)}, {[5, 10], [19, 26]}); %#ok<AGROW>
    end
end

% Slope-turn overlap samples. Cycle speed/radius to obtain pairwise
% coverage without exploding into the full Cartesian product.
overlap_modes = {'entry', 'middle', 'exit'};
for im = 1:numel(overlap_modes)
    mode = overlap_modes{im};
    for it = 1:numel(theta_combo_levels)
        th_deg = theta_combo_levels(it);
        for id = 1:numel(dirs)
            sgn = dirs(id);
            v0 = speed_grid(mod(it + im + id - 3, numel(speed_grid)) + 1);
            R = radius_grid(mod(2*it + im + id - 4, numel(radius_grid)) + 1);
            omega_abs = v0 / R;
            name = sprintf('v4_slope_turn_%s_%s', mode, local_v4_name('', v0, R, th_deg, sgn));
            switch mode
                case 'entry'
                    events = { ...
                        local_event('theta', 4.0, 8.0, deg2rad(th_deg)), ...
                        local_event('omega', 5.0, 7.0, sgn * omega_abs), ...
                        local_event('omega', 18.0, 20.0, 0.00), ...
                        local_event('theta', 24.0, 28.0, 0.00)};
                    rec = {[4, 9], [17, 21], [23, 29]};
                case 'middle'
                    events = { ...
                        local_event('theta', 4.0, 8.0, deg2rad(th_deg)), ...
                        local_event('omega', 10.0, 12.0, sgn * omega_abs), ...
                        local_event('omega', 20.0, 22.0, 0.00), ...
                        local_event('theta', 24.0, 28.0, 0.00)};
                    rec = {[5, 9], [10, 13], [20, 23], [24, 29]};
                otherwise
                    events = { ...
                        local_event('theta', 4.0, 8.0, deg2rad(th_deg)), ...
                        local_event('omega', 15.0, 17.0, sgn * omega_abs), ...
                        local_event('theta', 16.0, 20.0, 0.00), ...
                        local_event('omega', 22.0, 24.0, 0.00)};
                    rec = {[5, 9], [15, 21], [22, 25]};
            end
            profiles(end+1) = local_profile(name, 'v4_slope_turn', 34, v0, events, rec); %#ok<AGROW>
        end
    end
end

% Industrial S-curve and reversal paths. These are not full-grid; they are
% structural cases that help turn-tail labeling and closure behavior.
for iv = 1:numel(speed_grid)
    v0 = speed_grid(iv);
    for R = [7, 9, 11]
        omega_abs = v0 / R;
        profiles(end+1) = local_profile( ...
            sprintf('v4_flat_s_curve_v%02d_R%02d', round(10*v0), R), ...
            'v4_s_curve', 36, v0, { ...
            local_event('omega', 4.0, 6.0, omega_abs), ...
            local_event('omega', 13.0, 15.0, -omega_abs), ...
            local_event('omega', 25.0, 27.0, 0.00)}, {[5, 9], [13, 17], [24, 28]}); %#ok<AGROW>
    end
end

for th_deg = [-5, 5]
    for sgn = dirs
        v0 = 0.90;
        R = 8;
        omega_abs = v0 / R;
        profiles(end+1) = local_profile( ...
            sprintf('v4_theta_reversal_s_curve_th%s_%s', local_v4_deg_token(th_deg), local_v4_dir_token(sgn)), ...
            'v4_reversal', 40, v0, { ...
            local_event('theta', 4.0, 11.0, deg2rad(th_deg)), ...
            local_event('omega', 6.0, 8.0, sgn * omega_abs), ...
            local_event('theta', 13.0, 21.0, deg2rad(-th_deg)), ...
            local_event('omega', 17.0, 19.0, -sgn * omega_abs), ...
            local_event('omega', 27.0, 29.0, 0.00), ...
            local_event('theta', 30.0, 35.0, 0.00)}, {[5, 9], [13, 22], [26, 31], [30, 36]}); %#ok<AGROW>
    end
end
end

function name = local_v4_name(prefix, v0, R, th_deg, sgn)
parts = {};
if ~isempty(prefix)
    parts{end+1} = prefix; %#ok<AGROW>
end
parts{end+1} = local_v4_dir_token(sgn); %#ok<AGROW>
parts{end+1} = sprintf('v%02d', round(10*v0)); %#ok<AGROW>
parts{end+1} = sprintf('R%02d', round(R)); %#ok<AGROW>
if th_deg ~= 0
    parts{end+1} = ['th' local_v4_deg_token(th_deg)]; %#ok<AGROW>
end
name = strjoin(parts, '_');
end

function tok = local_v4_dir_token(sgn)
if sgn > 0
    tok = 'L';
elseif sgn < 0
    tok = 'R';
else
    tok = 'S';
end
end

function tok = local_v4_deg_token(deg_val)
if deg_val < 0
    tok = sprintf('m%02d', round(abs(deg_val)));
else
    tok = sprintf('p%02d', round(abs(deg_val)));
end
end

function p = local_profile(name, tier, T_end, v0, events, rec_windows)
p = struct();
p.name = name;
p.tier = tier;
p.T_end = T_end;
p.v0 = v0;
p.events = events;
p.recommended_injection_windows = rec_windows;
end

function e = local_event(kind, t0, t1, value, aux)
if nargin < 5
    aux = [];
end
e = struct('kind', kind, 't0', t0, 't1', t1, 'value', value, 'aux', aux);
end

function spec = local_clip_spec_to_limits(spec, limits)
% 将规格裁剪到设计范围内，防止路径超出 LPV/MPC 可靠区。
spec.v0 = min(max(spec.v0, limits.v_min_design), limits.v_max_design);
for i = 1:numel(spec.events)
    e = spec.events{i};
    switch lower(e.kind)
        case 'speed'
            e.value = min(max(e.value, limits.v_min_design), limits.v_max_design);
        case 'omega'
            e.value = min(max(e.value, -limits.omega_abs_design), limits.omega_abs_design);
        case {'theta', 'theta_sine'}
            e.value = min(max(e.value, -limits.theta_abs_design), limits.theta_abs_design);
    end
    spec.events{i} = e;
end
end

function ref = local_generate_ref_from_spec(spec, params, cfg, limits)
Ts = params.Ts;
t = (0:Ts:spec.T_end)';
N = numel(t);

v = spec.v0 * ones(N, 1);
omega = zeros(N, 1);
theta = zeros(N, 1);

for i = 1:numel(spec.events)
    e = spec.events{i};
    idx = t >= e.t0 & t <= e.t1;
    switch lower(e.kind)
        case 'speed'
            v = local_apply_level_event(t, v, e.t0, e.t1, e.value);
        case 'omega'
            omega = local_apply_level_event(t, omega, e.t0, e.t1, e.value);
        case 'theta'
            theta = local_apply_level_event(t, theta, e.t0, e.t1, e.value);
        case 'theta_sine'
            freq_hz = e.aux;
            if isempty(freq_hz)
                freq_hz = 0.4;
            end
            theta(idx) = theta(idx) + e.value * sin(2*pi*freq_hz*(t(idx) - e.t0));
        otherwise
            error('Unknown event kind: %s', e.kind);
    end
end

% 安全裁剪，防止叠加事件超出范围。
v = min(max(v, limits.v_min_design), limits.v_max_design);
omega = min(max(omega, -limits.omega_abs_design), limits.omega_abs_design);
theta = min(max(theta, -limits.theta_abs_design), limits.theta_abs_design);

% 积分得到轨迹。使用前一拍参考速度和角速度，保持离散一致性。
psi = zeros(N, 1);
X = zeros(N, 1);
Y = zeros(N, 1);
for k = 2:N
    psi(k) = local_normalize_angle(psi(k-1) + omega(k-1) * Ts);
    X(k) = X(k-1) + v(k-1) * Ts * cos(psi(k-1));
    Y(k) = Y(k-1) + v(k-1) * Ts * sin(psi(k-1));
end

e_y_ref = zeros(N, 1);
e_psi_ref = zeros(N, 1);
e_v_ref = zeros(N, 1);
rho_raw = [v, omega, theta];
rho = local_apply_first_order_filter(rho_raw, Ts, cfg.rho_filter_tau);

ref = struct();
ref.t = t;
ref.X_ref = X;
ref.Y_ref = Y;
ref.psi_ref = psi;
ref.v_ref = v;
ref.omega_ref = omega;
ref.theta_ref = theta;
ref.e_y_ref = e_y_ref;
ref.e_psi_ref = e_psi_ref;
ref.e_v_ref = e_v_ref;
ref.rho = rho;

ref.time = t;
ref.signals.values = [X, Y, psi, v, omega, theta, e_y_ref, e_psi_ref, e_v_ref];
ref.signals.dimensions = 9;

ref.meta = struct();
ref.meta.path_type = ['train_tcn_' spec.name];
ref.meta.training_path = true;
ref.meta.training_usage = 'TCN state-estimation training';
ref.meta.tier = spec.tier;
ref.meta.generation_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ref.meta.version = 'TCN_PATH_V1.0';
ref.meta.author = 'LPV-MPC Project';
ref.meta.params.T_end = spec.T_end;
ref.meta.params.Ts = Ts;
ref.meta.params.v0 = spec.v0;
ref.meta.params.rho_filter_tau = cfg.rho_filter_tau;
ref.meta.events = spec.events;
ref.meta.recommended_injection_windows = spec.recommended_injection_windows;
ref.meta.constraint_basis = struct( ...
    'v_design', [limits.v_min_design, limits.v_max_design], ...
    'omega_abs_design', limits.omega_abs_design, ...
    'theta_abs_design', limits.theta_abs_design, ...
    'F_cmd_range', [limits.F_cmd_min, limits.F_cmd_max], ...
    'omega_cmd_range', [limits.omega_cmd_min, limits.omega_cmd_max]);
end

function y = local_apply_level_event(t, y, t0, t1, target)
% 对 [t0,t1] 内的信号做平滑阶跃，并在 t1 后保持 target。
% 若后续事件再次作用于同一变量，会从当前值继续平滑过渡。
if t1 <= t0
    return;
end
y0_idx = find(t <= t0, 1, 'last');
if isempty(y0_idx)
    y_start = y(1);
else
    y_start = y(y0_idx);
end

idx_tr = t >= t0 & t <= t1;
s = (t(idx_tr) - t0) / max(t1 - t0, eps);
w = local_smoothstep(s);
y(idx_tr) = y_start + (target - y_start) .* w;
y(t > t1) = target;
end

function w = local_smoothstep(s)
s = min(max(s, 0), 1);
w = s.^2 .* (3 - 2*s);
end

function rho_filtered = local_apply_first_order_filter(rho_raw, Ts, tau)
[N, dim] = size(rho_raw);
alpha = Ts / (Ts + tau);
rho_filtered = zeros(N, dim);
rho_filtered(1, :) = rho_raw(1, :);
for k = 2:N
    rho_filtered(k, :) = alpha * rho_raw(k, :) + (1 - alpha) * rho_filtered(k-1, :);
end
end

function local_validate_ref(ref, limits)
% 路径级快速校验：调度变量不超出设计范围，等效平衡力留有余量。
if any(diff(ref.t) <= 0)
    error('ref.t must be strictly increasing.');
end
if any(ref.v_ref < limits.v_min_design - 1e-9) || any(ref.v_ref > limits.v_max_design + 1e-9)
    error('v_ref exceeds design range.');
end
if any(abs(ref.omega_ref) > limits.omega_abs_design + 1e-9)
    error('omega_ref exceeds design range.');
end
if any(abs(ref.theta_ref) > limits.theta_abs_design + 1e-9)
    error('theta_ref exceeds design range.');
end
end

function row = local_manifest_row_template()
row = struct();
row.index = NaN;
row.file_name = '';
row.path_file = '';
row.name = '';
row.tier = '';
row.T_end = NaN;
row.Ts = NaN;
row.v_min = NaN;
row.v_max = NaN;
row.omega_min = NaN;
row.omega_max = NaN;
row.theta_min_deg = NaN;
row.theta_max_deg = NaN;
row.n_recommended_windows = NaN;
end

function row = local_manifest_from_ref(index, file_name, out_file, spec, ref, ~)
row = local_manifest_row_template();
row.index = index;
row.file_name = file_name;
row.path_file = out_file;
row.name = spec.name;
row.tier = spec.tier;
row.T_end = ref.t(end);
row.Ts = median(diff(ref.t));
row.v_min = min(ref.v_ref);
row.v_max = max(ref.v_ref);
row.omega_min = min(ref.omega_ref);
row.omega_max = max(ref.omega_ref);
row.theta_min_deg = min(rad2deg(ref.theta_ref));
row.theta_max_deg = max(rad2deg(ref.theta_ref));
row.n_recommended_windows = numel(spec.recommended_injection_windows);
end

function local_visualize_path(ref, name, fig_paths_dir, figure_prefix)
if nargin < 4 || isempty(figure_prefix)
    figure_prefix = 'path_train_tcn_';
end
fig = figure('Name', sprintf('TCN train path: %s', name), ...
    'Position', [100, 100, 1200, 700], 'Visible', 'off');

subplot(2, 3, 1);
plot(ref.X_ref, ref.Y_ref, 'b-', 'LineWidth', 1.4);
grid on; axis equal;
xlabel('X [m]'); ylabel('Y [m]');
title(strrep(name, '_', '\_'));

subplot(2, 3, 2);
plot(ref.t, ref.v_ref, 'r-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('v [m/s]');
title('Speed');

subplot(2, 3, 3);
plot(ref.t, ref.omega_ref, 'g-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('\omega [rad/s]');
title('Yaw Rate');

subplot(2, 3, 4);
plot(ref.t, rad2deg(ref.psi_ref), 'm-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('\psi [deg]');
title('Heading');

subplot(2, 3, 5);
plot(ref.t, rad2deg(ref.theta_ref), 'c-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('\theta [deg]');
title('Ground Slope');

subplot(2, 3, 6);
plot(ref.t, ref.rho(:,1), 'r-', 'LineWidth', 1.2); hold on;
plot(ref.t, ref.rho(:,2), 'g-', 'LineWidth', 1.2);
plot(ref.t, rad2deg(ref.rho(:,3)), 'b-', 'LineWidth', 1.2);
grid on; xlabel('t [s]'); ylabel('rho');
legend('v [m/s]', '\omega [rad/s]', '\theta [deg]', 'Location', 'best');
title('Filtered Scheduling Variables');

out_png = fullfile(fig_paths_dir, sprintf('%s%s_preview.png', figure_prefix, name));
saveas(fig, out_png);
close(fig);
end

function a = local_normalize_angle(a)
a = atan2(sin(a), cos(a));
end
