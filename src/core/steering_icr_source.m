function [v_icr, w_icr] = steering_icr_source(v, omega, omega_cmd, Ts, params)
%STEERING_ICR_SOURCE Select the speed/yaw-rate pair used for steering ICR.
%
% The reference trajectory is the preferred geometry source when it is
% available in the base workspace. If the reference yaw rate is too small or
% unavailable, fall back to measured omega, then to omega_cmd as a last resort.

if nargin < 4 || isempty(Ts)
    Ts = 0.01;
end
if nargin < 5 || ~isstruct(params)
    params = struct();
end

w_ref_min = getfield_default(params, 'min_angular_velocity_threshold', 1e-3);
v_icr = v;
w_icr = NaN;

ref = struct();
try
    ref = evalin('base', 'ref');
catch
end

if isstruct(ref) && isfield(ref, 'v_ref') && isfield(ref, 'omega_ref')
    v_ref_use = NaN;
    omega_ref_use = NaN;
    if isfield(ref, 't') && ~isempty(ref.t)
        try
            t_sim = get_param(bdroot, 'SimulationTime');
        catch
            t_sim = 0;
        end
        idx = 1 + round(t_sim / max(Ts, 1e-6));
        idx = max(1, min(idx, numel(ref.t)));
        v_ref_use = local_pick(ref.v_ref, idx);
        omega_ref_use = local_pick(ref.omega_ref, idx);
    else
        if isscalar(ref.v_ref)
            v_ref_use = ref.v_ref;
        end
        if isscalar(ref.omega_ref)
            omega_ref_use = ref.omega_ref;
        end
    end

    if isfinite(v_ref_use) && isfinite(omega_ref_use) && abs(omega_ref_use) >= w_ref_min
        v_icr = v_ref_use;
        w_icr = omega_ref_use;
    end
end

if ~isfinite(w_icr) || abs(w_icr) < w_ref_min
    if isfinite(omega) && abs(omega) >= w_ref_min
        w_icr = omega;
        v_icr = v;
    else
        w_icr = omega_cmd;
        v_icr = v;
    end
end
end

function v = local_pick(x, idx)
x = x(:);
if isempty(x)
    v = NaN;
else
    idx = max(1, min(idx, numel(x)));
    v = x(idx);
end
end

function v = getfield_default(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    v = s.(field_name);
else
    v = default_value;
end
end
