function [ctx, u, info] = a2_mpc_solve(ctx, prepared)
% Invoke the same adaptive MPC API used by the frozen controller chain.
mpcobj = ctx.ctrl.mpcobj;
xmpc = ctx.xmpc;
plant_model = prepared.plant_model;
Nominal = prepared.nominal;
y_meas = prepared.y_meas;
r_ref = prepared.r_ref;
md = prepared.md;
evalc('[u, info] = mpcmoveAdaptive(mpcobj, xmpc, plant_model, Nominal, y_meas, r_ref, md);');
ctx.xmpc = xmpc;
end

