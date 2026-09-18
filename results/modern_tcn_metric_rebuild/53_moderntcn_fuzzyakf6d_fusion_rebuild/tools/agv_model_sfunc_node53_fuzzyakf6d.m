function agv_model_sfunc_node53_fuzzyakf6d(block)
%AGV_MODEL_SFUNC_NODE53_FUZZYAKF6D Plant plus causal body-pitch 6D IMU boundary.
setup(block);

function setup(block)
block.NumDialogPrms = 1; block.NumInputPorts = 1; block.NumOutputPorts = 2;
block.SetPreCompInpPortInfoToDynamic; block.InputPort(1).Dimensions = 3;
block.InputPort(1).DatatypeID = 0; block.InputPort(1).Complexity = 'Real';
block.InputPort(1).DirectFeedthrough = false; block.SetPreCompOutPortInfoToDynamic;
block.OutputPort(1).Dimensions = 34; block.OutputPort(2).Dimensions = 6;
for i = 1:2
    block.OutputPort(i).DatatypeID = 0; block.OutputPort(i).Complexity = 'Real';
end
p = block.DialogPrm(1).Data; block.SampleTimes = [p.Ts, 0];
block.SimStateCompliance = 'DefaultSimState';
block.RegBlockMethod('PostPropagationSetup', @DoPostPropagationSetup);
block.RegBlockMethod('InitializeConditions', @DoInitialize);
block.RegBlockMethod('Outputs', @DoOutputs); block.RegBlockMethod('Update', @DoUpdate);
end

function DoPostPropagationSetup(block)
p = block.DialogPrm(1).Data; nx = 8;
if isfield(p, 'nx') && ~isempty(p.nx); nx = p.nx; end
block.NumDworks = 7;
local_dwork(block, 1, 'xdisc', nx, true);
local_dwork(block, 2, 'imu_packet', 6, false);
local_dwork(block, 3, 'imu_filter_state', 6, false);
local_dwork(block, 4, 'sensor_sample_index', 1, false);
local_dwork(block, 5, 'road_pitch_previous', 1, false);
local_dwork(block, 6, 'body_pitch', 1, true);
local_dwork(block, 7, 'body_pitch_rate', 1, true);
end

function local_dwork(block, k, name, n, is_state)
block.Dwork(k).Name = name; block.Dwork(k).Dimensions = n;
block.Dwork(k).DatatypeID = 0; block.Dwork(k).Complexity = 'Real';
block.Dwork(k).UsedAsDiscState = is_state;
end

function DoInitialize(block)
p = block.DialogPrm(1).Data; nx = block.Dwork(1).Dimensions;
if isfield(p, 'x0') && ~isempty(p.x0)
    x0 = p.x0(:);
else
    x0 = [p.initial_x; p.initial_y; p.initial_heading; p.initial_velocity; ...
        p.initial_angular_velocity; p.initial_front_steering; ...
        p.initial_rear_steering; p.initial_sideslip];
end
if numel(x0) ~= nx; error('node53:PlantState', 'Unexpected initial state size.'); end
c = local_sensor_cfg(p);
R_y = [cos(c.mount_pitch_error_rad), 0, sin(c.mount_pitch_error_rad); ...
    0, 1, 0; -sin(c.mount_pitch_error_rad), 0, cos(c.mount_pitch_error_rad)];
initial = [R_y * [0; 0; c.g] + c.accel_bias_mps2(:); c.gyro_bias_radps(:)];
block.Dwork(1).Data = x0; block.Dwork(2).Data = initial;
block.Dwork(3).Data = initial; block.Dwork(4).Data = 0;
block.Dwork(5).Data = 0; block.Dwork(6).Data = 0; block.Dwork(7).Data = 0;
end

function DoOutputs(block)
p = local_clean_params(block.DialogPrm(1).Data);
u = double(block.InputPort(1).Data(:));
if numel(u) ~= 3 || any(~isfinite(u)); error('node53:PlantInput', 'Expected finite [F, omega, road pitch].'); end
y = output_eq_ref(block.Dwork(1).Data, u(1:2), u(3), p);
if numel(y) ~= 34 || any(~isfinite(y)); error('node53:PlantOutput', 'Legacy plant output contract failed.'); end
block.OutputPort(1).Data = y(:); block.OutputPort(2).Data = block.Dwork(2).Data;
end

function DoUpdate(block)
p0 = block.DialogPrm(1).Data; p = local_clean_params(p0);
u = double(block.InputPort(1).Data(:)); x = double(block.Dwork(1).Data(:));
road_pitch = u(3); y = output_eq_ref(x, u(1:2), road_pitch, p);
c = local_sensor_cfg(p0); k = double(block.Dwork(4).Data);
body_pitch = double(block.Dwork(6).Data);
body_pitch_rate = double(block.Dwork(7).Data);
specific_body = [double(y(9)) + c.g * sin(body_pitch); ...
    double(y(34)); c.g * cos(body_pitch)];
delta = c.mount_pitch_error_rad;
R_y = [cos(delta), 0, sin(delta); 0, 1, 0; -sin(delta), 0, cos(delta)];
accel = R_y * specific_body + c.accel_bias_mps2(:);
gyro = [0; body_pitch_rate; double(y(11))] + c.gyro_bias_radps(:);
raw = [accel; gyro];
for ch = 1:6
    if ch <= 3
        sigma = c.accel_noise_std_mps2(ch); alpha = exp(-2*pi*c.accel_bandwidth_hz*c.Ts);
    else
        sigma = c.gyro_noise_std_radps(ch-3); alpha = exp(-2*pi*c.gyro_bandwidth_hz*c.Ts);
    end
    raw(ch) = raw(ch) + sigma * local_randn(c.sensor_seed, k, ch);
    if k > 0; raw(ch) = alpha * block.Dwork(3).Data(ch) + (1-alpha) * raw(ch); end
end
if any(~isfinite(raw)); error('node53:Sensor', 'Non-finite IMU measurement.'); end
block.Dwork(2).Data = raw; block.Dwork(3).Data = raw; block.Dwork(4).Data = k + 1;

wn = 2*pi*c.body_pitch_natural_frequency_hz;
pitch_accel = wn^2 * (road_pitch - body_pitch) - ...
    2*c.body_pitch_damping_ratio*wn*body_pitch_rate;
body_pitch_rate = body_pitch_rate + c.Ts*pitch_accel;
body_pitch_rate = max(-c.body_pitch_rate_limit_radps, ...
    min(c.body_pitch_rate_limit_radps, body_pitch_rate));
body_pitch = body_pitch + c.Ts*body_pitch_rate;
block.Dwork(5).Data = road_pitch; block.Dwork(6).Data = body_pitch;
block.Dwork(7).Data = body_pitch_rate;
block.Dwork(1).Data = state_eq_ref(x, u(1:2), road_pitch, p);
end

function p = local_clean_params(p); p.enable_noise = false; end
function c = local_sensor_cfg(p)
if isfield(p, 'node53_sensor') && isstruct(p.node53_sensor)
    c = p.node53_sensor;
else
    c = node53_runtime_config(project_root()).sensor;
end
end
function z = local_randn(seed, k, ch)
u1 = local_uniform(seed, k, ch, 1); u2 = local_uniform(seed, k, ch, 2);
z = sqrt(-2*log(max(u1, realmin))) * cos(2*pi*u2);
end
function u = local_uniform(seed, k, ch, lane)
v = uint32(mod(double(seed) + 1664525*(double(k)+1) + ...
    1013904223*double(ch) + 69069*double(lane), 2^32));
v = bitxor(v, bitshift(v, 13)); v = bitxor(v, bitshift(v, -17));
v = bitxor(v, bitshift(v, 5)); u = (double(v) + 0.5) / 2^32;
end
end
