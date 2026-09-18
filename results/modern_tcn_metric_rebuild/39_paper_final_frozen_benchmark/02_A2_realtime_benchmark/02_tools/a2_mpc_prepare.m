function [ctx, prepared] = a2_mpc_prepare(ctx, sample, theta_override)
% Prepare the frozen adaptive MPC call. No solver execution occurs here.
if nargin < 3 || isempty(theta_override), theta = double(sample.theta_ref); else, theta = double(theta_override); end
Ts = double(ctx.db.Ts);
rho = [double(sample.v_ref); double(sample.omega_ref); theta];
alpha = Ts / (Ts + 0.4);
ctx.rho_prev = alpha * rho + (1-alpha) * ctx.rho_prev;
upd = mpc_update_from_rho(ctx.rho_prev, ctx.db, ctx.ctrl.maps);

B = [upd.B, upd.E];
D = [upd.D, zeros(size(upd.D,1),1)];
plant_model = ss(upd.A, B, upd.C, D, Ts);
nominal = struct('X',zeros(4,1),'Y',zeros(4,1),'DX',zeros(4,1),'U',zeros(3,1));
p = ctx.params;
nominal.U(1) = p.mass * p.gravity * (sin(theta) + p.rolling_resistance * cos(theta));
nominal.U(2) = ctx.rho_prev(2);
nominal.U(3) = theta;

ctx.ctrl.mpcobj.Weights.OutputVariables = upd.Q;
ctx.ctrl.mpcobj.Weights.ManipulatedVariables = upd.R;
ctx.ctrl.mpcobj.Weights.ManipulatedVariablesRate = upd.dR;
ctx.ctrl.mpcobj.MV(1).Min = upd.umin(1); ctx.ctrl.mpcobj.MV(1).Max = upd.umax(1);
ctx.ctrl.mpcobj.MV(2).Min = upd.umin(2); ctx.ctrl.mpcobj.MV(2).Max = upd.umax(2);

prepared = struct('plant_model',plant_model,'nominal',nominal, ...
    'y_meas',double(sample.y_meas(:)),'r_ref',zeros(4,1),'md',theta);
end

