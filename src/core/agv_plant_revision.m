function revision = agv_plant_revision(params)
%AGV_PLANT_REVISION Return the active plant-parameter revision metadata.
%
% This helper is intentionally read-only. It gives data, LPV, MPC, and
% closed-loop runners one common label for the current plant baseline.

if nargin < 1 || isempty(params)
    params = parameters();
end

revision = struct();
revision.id = 'agv_physics_v2_plantfix';
revision.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
revision.description = ['current repaired plant: higher AGV cornering ' ...
    'stiffness, configurable yaw damping, and no normal-speed artificial ' ...
    'beta damping'];
revision.params_version = local_get(params, 'version', '');
revision.Ts = local_get(params, 'Ts', NaN);
revision.mass = local_get(params, 'mass', NaN);
revision.front_cornering_stiffness = local_get(params, 'front_cornering_stiffness', NaN);
revision.rear_cornering_stiffness = local_get(params, 'rear_cornering_stiffness', NaN);
revision.yaw_damping = local_get(params, 'yaw_damping', NaN);
revision.sideslip_damping = local_get(params, 'sideslip_damping', NaN);
revision.sideslip_low_speed_damping = local_get(params, 'sideslip_low_speed_damping', NaN);
revision.rules = { ...
    'do not restore the old hard-coded high yaw damping constant', ...
    'do not restore the old normal-speed artificial beta feedback term', ...
    'MPC retuning must be done through controller weights/horizon/constraints'};
revision.source_files = { ...
    'src/core/parameters.m', ...
    'src/core/state_eq.m', ...
    'src/core/state_eq_ref.m', ...
    'src/core/state_eq_ref_train_data.m'};
end

function value = local_get(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name)
    value = s.(field_name);
else
    value = default_value;
end
end
