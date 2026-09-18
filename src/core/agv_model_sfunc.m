
function agv_model_sfunc(block)
% ==========================================
% Level-2 MATLAB S-Function (Simulink)
% 外壳：AGV 离散植物，内部调用 state_eq / output_eq
% 接口：
%   - 参数 p：parameters() 结构体（必须包含 Ts；可选 nx、x0）
%   - 输入端口(1)：u_all = [F_cmd; omega_cmd; theta_ground] (3x1)
%   - 输出端口(1)：y (34x1) - V4.3 Mamba适配
%   - 离散状态：x (nx×1，默认 8)，使用 DWork 管理
% ==========================================
setup(block);

% -------- S-Function 框架 --------
function setup(block)
  % 1) 模块参数
  block.NumDialogPrms  = 1;    % p = parameters()

  % 2) 端口
  block.NumInputPorts  = 1;
  block.NumOutputPorts = 1;

  % 输入端口：3×1
  block.SetPreCompInpPortInfoToDynamic;
  block.InputPort(1).Dimensions        = 3;
  block.InputPort(1).DatatypeID        = 0; % double
  block.InputPort(1).Complexity        = 'Real';
  block.InputPort(1).DirectFeedthrough = false;

  % 输出端口：34×1 (V4.3 Mamba适配)
  block.SetPreCompOutPortInfoToDynamic;
  block.OutputPort(1).Dimensions = 34;
  block.OutputPort(1).DatatypeID = 0; % double
  block.OutputPort(1).Complexity = 'Real';

  % 3) 采样时间（来自参数 Ts）
  p = block.DialogPrm(1).Data;
  if ~isfield(p,'Ts')
      error('parameters() 必须包含字段 Ts');
  end
  block.SampleTimes = [p.Ts 0];

  % 4) 不在 setup 里设置 NumDworks / Dwork 属性

  % 5) 注册方法
  block.SimStateCompliance = 'DefaultSimState';
  block.RegBlockMethod('PostPropagationSetup', @DoPostPropSetup);
  block.RegBlockMethod('InitializeConditions', @DoInitialize);
  block.RegBlockMethod('Outputs',              @DoOutputs);
  block.RegBlockMethod('Update',               @DoUpdate);
end

% -------- 在 PostPropagationSetup 里设置 DWork 的数量和属性 --------
function DoPostPropSetup(block)
  block.NumDworks = 1;  % 关键：必须在这里设置

  % 状态维度（可用 p.nx 指定，默认 8）
  nx = 8;
  if block.NumDialogPrms>=1 && isstruct(block.DialogPrm(1).Data)
      p = block.DialogPrm(1).Data;
      if isfield(p,'nx') && ~isempty(p.nx)
          nx = p.nx;
      end
  end

  block.Dwork(1).Name            = 'xdisc';
  block.Dwork(1).Dimensions      = nx;
  block.Dwork(1).DatatypeID      = 0;     % double
  block.Dwork(1).Complexity      = 'Real';
  block.Dwork(1).UsedAsDiscState = true;  % 离散状态
end

% -------- 初始化离散状态 --------
function DoInitialize(block)
  p = block.DialogPrm(1).Data;
  nx = block.Dwork(1).Dimensions;

  % 优先使用 p.x0；否则由 parameters.m 的 initial_* 字段组装
  if isfield(p,'x0') && ~isempty(p.x0)
      x0 = p.x0(:);
  elseif all(isfield(p, {'initial_x','initial_y','initial_heading', ...
                         'initial_velocity','initial_angular_velocity', ...
                         'initial_front_steering','initial_rear_steering', ...
                         'initial_sideslip'}))
      x0 = [p.initial_x; p.initial_y; p.initial_heading; ...
            p.initial_velocity; p.initial_angular_velocity; ...
            p.initial_front_steering; p.initial_rear_steering; ...
            p.initial_sideslip];
  else
      x0 = zeros(nx,1);
  end

  if numel(x0)~=nx
      error('x0 维度(%d)与 nx(%d)不一致', numel(x0), nx);
  end
  block.Dwork(1).Data = x0;
end

% -------- 输出方程 --------
function DoOutputs(block)
  p     = block.DialogPrm(1).Data;
  u_all = block.InputPort(1).Data;       % [F_cmd; omega_cmd; theta_ground]
  x     = block.Dwork(1).Data;

  u            = u_all(1:2);             % 控制量
  theta_ground = u_all(3);               % 坡度角

  % y = output_eq(x, u, theta_ground, p);  % 修正：按签名传入4个参数
  y = output_eq_ref(x, u, theta_ground, p);  % 利用v_ref和omega_ref生成参考半径

  if ~isvector(y) || numel(y)~=block.OutputPort(1).Dimensions
      % error('output_eq 返回长度与输出端口不一致，期望 %d，实际 %d', ...     % 利用v_ref和omega_ref生成参考半径
            % block.OutputPort(1).Dimensions, numel(y));
      error('output_eq_ref 返回长度与输出端口不一致，期望 %d，实际 %d', ...
            block.OutputPort(1).Dimensions, numel(y));
  end
  block.OutputPort(1).Data = y(:);
end

% -------- 状态更新（离散化步进）--------
function DoUpdate(block)
  p     = block.DialogPrm(1).Data;
  u_all = block.InputPort(1).Data;       % [F_cmd; omega_cmd; theta_ground]
  x     = block.Dwork(1).Data;

  u            = u_all(1:2);
  theta_ground = u_all(3);

  % 修正：state_eq 的签名为 (x, u, theta_ground, params)
  % x_next = state_eq(x, u, theta_ground, p);         % 利用v_ref和omega_ref生成参考半径
  x_next = state_eq_ref(x, u, theta_ground, p);

  if numel(x_next)~=numel(x)
      % error('state_eq 返回维度与 DWork 不一致');      % 利用v_ref和omega_ref生成参考半径
      error('state_eq_ref 返回维度与 DWork 不一致');
  end
  block.Dwork(1).Data = x_next(:);
end
end

