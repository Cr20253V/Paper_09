function agv_model_sfunc_train_data(block)
%AGV_MODEL_SFUNC_TRAIN_DATA 训练数据生成专用 Level-2 MATLAB S-Function。
%
% 功能说明：
%   本模块由 GRU_DataGen.slx 调用，用于生成 GRU/TCN 共享训练数据。
%   它与闭环主模型 agv_model_sfunc.m 分离，原因是训练数据生成需要
%   额外注入滑移和负载/堵转扰动，不能污染正式控制模型。
%
% 输入端口：
%   u_all = [F_cmd; omega_cmd; theta_ground; slip_gamma; stall_load]
%
%   F_cmd       : 纵向驱动力命令 [N]
%   omega_cmd   : 横摆角速度命令 [rad/s]
%   theta_ground: 地面坡度角 [rad]
%   slip_gamma  : 滑移注入系数，1.0 表示正常附着
%   stall_load  : 外加纵向负载，用于 load/stall 扰动注入 [N]
%
% 内部动力学/输出方程：
%   state_eq_ref_train_data(...)
%   output_eq_ref_train_data(...)
%
% 输出约定：
%   y 为 34 x 1，保持当前 GRU/Mamba/TCN 数据生成链路使用的训练信号
%   契约。第 32-34 维为滑移率和横向加速度等扩展诊断量。

setup(block);

function setup(block)
    block.NumDialogPrms = 1;  % params 参数结构体

    block.NumInputPorts = 1;
    block.NumOutputPorts = 1;

    block.SetPreCompInpPortInfoToDynamic;
    block.InputPort(1).Dimensions = 5;
    block.InputPort(1).DatatypeID = 0; % double 类型
    block.InputPort(1).Complexity = 'Real';
    block.InputPort(1).DirectFeedthrough = false;

    block.SetPreCompOutPortInfoToDynamic;
    block.OutputPort(1).Dimensions = 34;
    block.OutputPort(1).DatatypeID = 0; % double 类型
    block.OutputPort(1).Complexity = 'Real';

    p = block.DialogPrm(1).Data;
    if ~isstruct(p) || ~isfield(p, 'Ts')
        error('agv_model_sfunc_train_data:InvalidParams', ...
            'Dialog parameter must be a params struct with field Ts.');
    end
    block.SampleTimes = [p.Ts 0];

    block.SimStateCompliance = 'DefaultSimState';
    block.RegBlockMethod('PostPropagationSetup', @DoPostPropSetup);
    block.RegBlockMethod('InitializeConditions', @DoInitialize);
    block.RegBlockMethod('Outputs', @DoOutputs);
    block.RegBlockMethod('Update', @DoUpdate);
end

function DoPostPropSetup(block)
    nx = 8;
    if block.NumDialogPrms >= 1 && isstruct(block.DialogPrm(1).Data)
        p = block.DialogPrm(1).Data;
        if isfield(p, 'nx') && ~isempty(p.nx)
            nx = p.nx;
        end
    end

    block.NumDworks = 1;
    block.Dwork(1).Name = 'xdisc';
    block.Dwork(1).Dimensions = nx;
    block.Dwork(1).DatatypeID = 0;
    block.Dwork(1).Complexity = 'Real';
    block.Dwork(1).UsedAsDiscState = true;
end

function DoInitialize(block)
    p = block.DialogPrm(1).Data;
    nx = block.Dwork(1).Dimensions;

    if isfield(p, 'x0') && ~isempty(p.x0)
        x0 = p.x0(:);
    elseif all(isfield(p, {'initial_x', 'initial_y', 'initial_heading', ...
            'initial_velocity', 'initial_angular_velocity', ...
            'initial_front_steering', 'initial_rear_steering', ...
            'initial_sideslip'}))
        x0 = [p.initial_x; p.initial_y; p.initial_heading; ...
              p.initial_velocity; p.initial_angular_velocity; ...
              p.initial_front_steering; p.initial_rear_steering; ...
              p.initial_sideslip];
    else
        x0 = zeros(nx, 1);
    end

    if numel(x0) ~= nx
        error('agv_model_sfunc_train_data:InvalidX0', ...
            'x0 length (%d) does not match nx (%d).', numel(x0), nx);
    end
    block.Dwork(1).Data = x0;
end

function DoOutputs(block)
    p = block.DialogPrm(1).Data;
    u_all = block.InputPort(1).Data;
    x = block.Dwork(1).Data;

    u = u_all(1:2);
    theta_ground = u_all(3);
    slip_gamma = u_all(4);
    stall_load = u_all(5);

    y = output_eq_ref_train_data(x, u, theta_ground, p, slip_gamma, stall_load);

    if ~isvector(y) || numel(y) ~= block.OutputPort(1).Dimensions
        error('agv_model_sfunc_train_data:InvalidOutputSize', ...
            'output_eq_ref_train_data returned %d elements, expected %d.', ...
            numel(y), block.OutputPort(1).Dimensions);
    end
    block.OutputPort(1).Data = y(:);
end

function DoUpdate(block)
    p = block.DialogPrm(1).Data;
    u_all = block.InputPort(1).Data;
    x = block.Dwork(1).Data;

    u = u_all(1:2);
    theta_ground = u_all(3);
    slip_gamma = u_all(4);
    stall_load = u_all(5);

    x_next = state_eq_ref_train_data(x, u, theta_ground, p, slip_gamma, stall_load);

    if numel(x_next) ~= numel(x)
        error('agv_model_sfunc_train_data:InvalidStateSize', ...
            'state_eq_ref_train_data returned %d elements, expected %d.', ...
            numel(x_next), numel(x));
    end
    block.Dwork(1).Data = x_next(:);
end

end
