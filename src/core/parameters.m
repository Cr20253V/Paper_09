function params = parameters()
% =============================
% 文件名：parameters.m
% 版本：V4.0
% 说明：
%   1) 集中维护模型与控制参数，还原原始数值
%   2) 取消所有别名，使用规范的变量命名
%   3) 为每个变量提供详细的中文注释
%   4) 可直接作为 S-Function 对话框参数（例如：parameters()）
% =============================

%% 时基参数
params.Ts = 0.01;                      % 采样周期 [s] - 系统离散化时间步长

%% 车辆质量与几何参数
params.mass = 200.0;                   % 车辆总质量 [kg] - 包含载荷的总重量
params.L = 2.0;                        % 前后轴距 [m] - 前轮轴心到后轮轴心的距离
params.W = 0.8;                        % 左右轮距 [m] - 左轮中心到右轮中心的距离
params.h_cg = 0.5;                     % 质心高度 [m] - 质心到地面的垂直距离
params.Lf = 1.0;                       % 前轴到质心距离 [m] - 前轮轴心到质心的纵向距离
params.Lr = 1.0;                       % 后轴到质心距离 [m] - 后轮轴心到质心的纵向距离
params.Iz = 16.67;                     % 车辆绕z轴转动惯量 [kg·m^2] - 计算值：(1/12)*m*(L^2+W^2)

%% 车轮参数
params.wheel_radius = 0.15;            % 车轮半径 [m] - 轮胎外径的一半
params.wheel_mass = 1.2;               % 单个车轮质量 [kg] - 包含轮胎和轮毂的质量
params.wheel_inertia = 0.0135;         % 单个车轮转动惯量 [kg·m^2] - 计算值：0.5*m*r^2

%% 电机与传动系统参数
params.motor_torque_constant = 1.21;   % 电机转矩常数 [N·m/A] - 电流到转矩的转换系数
params.motor_inertia = 17.7e-4;        % 电机转子转动惯量 [kg·m^2] - 电机内部转子惯量
params.motor_current_limit = 9.0;      % 单电机电流限制 [A] - 电机最大允许电流
params.gear_ratio = 10.0;              % 减速器传动比 [-] - 电机转速与车轮转速的比值
params.gear_efficiency = 0.9;          % 传动效率 [-] - 机械传动的能量传递效率
params.current_limit = 9.0;            % 系统电流限制 [A] - 新增参数，用于动力学计算

%% 执行器与限制参数
params.steering_time_constant = 0.08;  % 转向执行器时间常数 [s] - 转向系统的响应时间特性
params.max_steering_angle = deg2rad(90.0);      % 最大转向角 [rad] - 车轮可转向的最大角度
params.max_steering_rate = deg2rad(30.0);      % 最大转向角速度 [rad/s] - 转向系统的最大角速度
params.max_acceleration = 1.0;         % 最大纵向加速度限制 [m/s^2] - 系统加速度保护限制

%% 环境与阻力参数
params.rolling_resistance = 0.015;     % 滚动阻力系数 [-] - 轮胎与地面的滚动摩擦系数
params.friction_coefficient = 0.8;     % 地面摩擦系数 [-] - 轮胎与地面的最大静摩擦系数
params.air_density = 1.225;            % 空气密度 [kg/m^3] - 标准大气条件下的空气密度
params.drag_coefficient_area = 0.5;    % 风阻系数乘以迎风面积 [m^2] - 空气阻力计算参数
params.gravity = 9.81;                 % 重力加速度 [m/s^2] - 地球表面重力加速度

%% 轮胎侧偏特性参数
% 修正：从过软的300 N/rad提升到更符合200 kg室内AGV的保守量级
% 说明：该值低于乘用车典型轮胎刚度，但足以避免旧模型转向响应过慢
params.front_cornering_stiffness = 3000;  % 前轮侧偏刚度 [N/rad]
params.rear_cornering_stiffness = 3000;   % 后轮侧偏刚度 [N/rad]

%% 横摆与侧滑数值阻尼参数
params.yaw_damping = 250.0;                  % 横摆阻尼系数 [Nm/(rad/s)]
params.sideslip_damping = 0.0;               % 正常速度侧滑角人工阻尼 [1/s]，0表示移除
params.sideslip_low_speed_damping = 1.0;     % 低速侧滑角数值回零阻尼 [1/s]

%% 噪声与数值阈值参数
params.enable_noise = false;           % 噪声使能开关 [-] - 是否在仿真中添加测量噪声；开启时需设定随机种子与各通道标准差
params.current_noise_std = 0.2;        % 电流测量噪声标准差 [A] - 电流传感器的测量噪声水平
params.wheel_speed_noise_std = 0.5;    % 轮速测量噪声标准差 [rad/s] - 轮速传感器的测量噪声水平
params.disturbance_noise_std = 3.0;    % 扰动力噪声标准差 [N] - 外部扰动力的噪声水平
params.random_seed = 42;                % 随机数种子 [-] - 用于噪声生成的随机数初始化种子
params.v_noise_std = 0.05;             % 车速测量噪声标准差 [m/s] - 速度传感器噪声（可用于 e_v 等指标）
params.psi_noise_std = deg2rad(0.5);   % 航向角测量噪声标准差 [rad] - 约0.5度
params.omega_noise_std = 0.01;         % 角速度测量噪声标准差 [rad/s] - 角速度传感器噪声
params.min_angular_velocity_threshold = 1e-3;  % 最小角速度阈值 [rad/s] - 避免数值奇异的角速度下限
params.low_speed_threshold = 0.05;     % 低速阈值 [m/s] - 低速特殊处理的速度界限

% 线性化友好性参数
params.use_smooth_saturation = false;  % 是否使用光滑限幅 [-] - true用于线性化，false用于仿真
params.smooth_gain = 30.0;             % 光滑限幅增益 [-] - 控制光滑程度，越大越接近硬限幅

%% 初始状态参数
params.initial_x = 0.0;                % 初始纵向位置 [m] - 车辆起始的x坐标
params.initial_y = 0.0;                % 初始横向位置 [m] - 车辆起始的y坐标
params.initial_heading = 0.0;          % 初始航向角 [rad] - 车辆起始的朝向角度
params.initial_velocity = 0.0;         % 初始速度 [m/s] - 车辆起始的前进速度
params.initial_angular_velocity = 0.0; % 初始角速度 [rad/s] - 车辆起始的转向角速度
params.initial_front_steering = 0.0;   % 初始前轮转向角 [rad] - 左前轮的初始转向角度
params.initial_rear_steering = 0.0;    % 初始后轮转向角 [rad] - 右后轮的初始转向角度
params.initial_sideslip = 0.0;         % 初始侧滑角 [rad] - 车辆质心的初始侧滑角度

%% AI 推理配置参数（V4.1 新增）
params.ai_backend        = 'tcp_service';  % 推理后端，可选: 'tcp_service' | 'matlab_stub' | 'matlab_native'
params.ai_model_type     = 'mamba2';       % 模型类型标识，供后端加载时使用
params.ai_model_path     = '';             % 本地模型文件路径（matlab_native 后端使用）
params.ai_model_meta_path = '';            % 模型元数据文件路径（scaler / mu_sigma 等）
params.ai_infer_interval = 5;             % 推理间隔步数（与 mamba_infer_interval 同义，此字段优先）

%% 版本信息
params.version = 'V4.1';               % 参数文件版本号
params.creation_date = datestr(now,'yyyy-mm-dd HH:MM:SS');  % 参数文件创建时间

end
