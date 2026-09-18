function metrics = evaluate_a3_case(out_file, path_file, controller_id, path_id, attempt_dir)
%EVALUATE_A3_CASE Extract the A3 trace and frozen metrics from one MAT output.

S = load(out_file, 'logsout');
logs = S.logsout;
[ey, t] = local_get(logs, 'diag.e_y');
if isempty(t), error('A3:MissingSignal', 'Missing diag.e_y in %s', out_file); end
t = t(:);
sig = struct();
names = {'e_psi','e_v','e_omega','F_cmd','omega_cmd','X','Y','X_ref','Y_ref', ...
    'v','omega','v_ref','omega_ref','theta_ref','theta_ground','theta_hat', ...
    'label_main','label_turn','conf_main','rho_f','F_limit_hi','F_limit_lo'};
sig.e_y = ey;
for i = 1:numel(names)
    sig.(names{i}) = local_resample(logs, ['diag.' names{i}], t);
end
sig.solve_time_ms = local_resample(logs, 'diag_solve_time_ms', t);
if isempty(sig.e_v), sig.e_v = sig.v - sig.v_ref; end
if isempty(sig.e_omega), sig.e_omega = sig.omega - sig.omega_ref; end

theta_sched = local_col(sig.rho_f, 3);
theta_true = sig.theta_ground;
if isempty(theta_true) || all(~isfinite(theta_true)), theta_true = sig.theta_ref; end
xy = hypot(sig.X - sig.X_ref, sig.Y - sig.Y_ref);
mask = t >= 0.5;
idx = find(mask);
Ts = median(diff(t), 'omitnan');

metrics = struct();
metrics.task_id = 'A3';
metrics.protocol_id = 'A0_paper_final_unified_protocol_v1';
metrics.case_id = sprintf('%s__%s', controller_id, path_id);
metrics.case_status = 'COMPLETE';
metrics.controller_id = controller_id;
metrics.path_id = path_id;
metrics.plant_revision = 'agv_physics_v2_plantfix';
metrics.sensor_noise_seed = [];
metrics.process_disturbance_seed = [];
metrics.initialization_exclusion_s = 0.5;
metrics.n_samples_total = numel(t);
metrics.n_samples_evaluated = nnz(mask);
metrics.simulation_stop_s = t(end);
metrics.ey_rmse = local_rms(sig.e_y(mask));
metrics.ey_peak = local_peak(sig.e_y(mask));
metrics.epsi_rmse = local_rms(sig.e_psi(mask));
metrics.epsi_peak = local_peak(sig.e_psi(mask));
metrics.xy_rmse = local_rms(xy(mask));
metrics.xy_peak = local_peak(xy(mask));
metrics.ev_rmse = local_rms(sig.e_v(mask));
metrics.ev_peak = local_peak(sig.e_v(mask));
metrics.eomega_rmse = local_rms(sig.e_omega(mask));
metrics.eomega_peak = local_peak(sig.e_omega(mask));
metrics.F_rms = local_rms(sig.F_cmd(mask));
metrics.F_peak = local_peak(sig.F_cmd(mask));
metrics.omega_cmd_rms = local_rms(sig.omega_cmd(mask));
metrics.omega_cmd_peak = local_peak(sig.omega_cmd(mask));
metrics.force_saturation_rate = mean(abs(sig.F_cmd(mask)) >= 595, 'omitnan');
metrics.omega_saturation_rate = mean(abs(sig.omega_cmd(mask)) >= 0.60, 'omitnan');
metrics.force_saturation_pct = 100 * metrics.force_saturation_rate;
metrics.omega_saturation_pct = 100 * metrics.omega_saturation_rate;
[metrics.dynamic_force_limit_hit_rate, metrics.dynamic_omega_limit_hit_rate, ...
    metrics.constraint_violation_rate] = local_limits(sig.F_cmd(mask), ...
    sig.omega_cmd(mask), sig.F_limit_hi(mask,:), sig.F_limit_lo(mask,:));
metrics.constraint_penalty = metrics.constraint_violation_rate;
if numel(idx) >= 3
    metrics.j_du = mean(diff(sig.F_cmd(idx)).^2 + diff(sig.omega_cmd(idx)).^2, 'omitnan');
else
    metrics.j_du = NaN;
end
metrics.solve_time_p50_ms = prctile(sig.solve_time_ms(mask), 50);
metrics.solve_time_p95_ms = prctile(sig.solve_time_ms(mask), 95);
metrics.solve_time_p99_ms = prctile(sig.solve_time_ms(mask), 99);
metrics.solve_time_max_ms = max(sig.solve_time_ms(mask), [], 'omitnan');
metrics.timeout_count = nnz(sig.solve_time_ms(mask) > 10.0);
metrics.timeout_rate = metrics.timeout_count / nnz(mask);

essential = [sig.e_y(mask), sig.e_psi(mask), sig.e_v(mask), xy(mask), ...
    sig.F_cmd(mask), sig.omega_cmd(mask), sig.solve_time_ms(mask), theta_sched(mask)];
metrics.solver_fail_count = nnz(any(~isfinite(essential), 2));
if metrics.solver_fail_count > 0, metrics.case_status = 'FAILED'; end

err = theta_sched(mask) - theta_true(mask);
metrics.theta_sched_mae_deg = rad2deg(mean(abs(err), 'omitnan'));
metrics.theta_sched_peak_abs_err_deg = rad2deg(max(abs(err), [], 'omitnan'));
metrics.theta_imu_raw_mae_deg = rad2deg(mean(abs(sig.theta_hat(mask)-theta_true(mask)), 'omitnan'));
dtheta = abs(diff(theta_sched(mask)));
metrics.theta_step_p95_deg = rad2deg(prctile(dtheta, 95));
metrics.theta_rate_p95_deg_s = rad2deg(prctile(dtheta ./ Ts, 95));
metrics.theta_rate_max_deg_s = rad2deg(max(dtheta ./ Ts, [], 'omitnan'));
metrics.theta_total_variation_deg = rad2deg(sum(dtheta, 'omitnan'));
[metrics.theta_delay_s, metrics.theta_delay_correlation, metrics.theta_delay_reason] = ...
    local_delay(theta_true(mask), theta_sched(mask), Ts, 2.0);

trace = table(t, sig.e_y, sig.e_psi, sig.e_v, sig.e_omega, xy, ...
    sig.X, sig.Y, sig.X_ref, sig.Y_ref, sig.F_cmd, sig.omega_cmd, ...
    local_col(sig.F_limit_lo,1), local_col(sig.F_limit_hi,1), ...
    local_col(sig.F_limit_lo,2), local_col(sig.F_limit_hi,2), ...
    theta_true, sig.theta_ref, sig.theta_hat, theta_sched, sig.solve_time_ms, ...
    'VariableNames', {'t_s','e_y','e_psi','e_v','e_omega','xy_error', ...
    'X','Y','X_ref','Y_ref','F_cmd','omega_cmd','F_limit_lo','F_limit_hi', ...
    'omega_limit_lo','omega_limit_hi','theta_true','theta_ref','theta_imu_raw', ...
    'theta_sched','solve_time_ms'});
writetable(trace, fullfile(attempt_dir, 'trace.csv'));
save(fullfile(attempt_dir, 'normalized_trace.mat'), 'trace', '-v7.3');
local_json(fullfile(attempt_dir, 'case_metrics.json'), metrics);
end

function [data, time] = local_get(logs, name)
data=[]; time=[]; sig=[];
for i=1:logs.numElements
    el=logs.get(i); if strcmp(el.Name,name), sig=el; break; end
end
if isempty(sig), return; end
time=sig.Values.Time(:); data=local_rows(squeeze(sig.Values.Data),numel(time));
end

function data = local_resample(logs,name,t)
[d,tin]=local_get(logs,name); if isempty(d), data=nan(numel(t),1); return; end
if numel(tin)==numel(t) && max(abs(tin(:)-t(:)))<1e-12, data=d; return; end
data=nan(numel(t),size(d,2));
for c=1:size(d,2), data(:,c)=interp1(tin,d(:,c),t,'linear','extrap'); end
end

function d=local_rows(d,n)
if isvector(d), d=d(:); elseif size(d,1)~=n && size(d,2)==n, d=d.'; elseif size(d,1)~=n, d=reshape(d,n,[]); end
end
function c=local_col(x,k), if isempty(x)||size(x,2)<k, c=nan(size(x,1),1); else, c=x(:,k); end, end
function y=local_rms(x), x=x(isfinite(x)); y=sqrt(mean(x.^2)); end
function y=local_peak(x), x=x(isfinite(x)); y=max(abs(x)); end

function [fh,oh,vr]=local_limits(F,O,hi,lo)
if size(hi,2)<2||size(lo,2)<2, fh=NaN;oh=NaN;vr=NaN;return; end
tol=1e-8; fh=mean(F>=0.99*hi(:,1)|F<=0.99*lo(:,1),'omitnan');
oh=mean(O>=0.99*hi(:,2)|O<=0.99*lo(:,2),'omitnan');
vr=mean(F>hi(:,1)+tol|F<lo(:,1)-tol|O>hi(:,2)+tol|O<lo(:,2)-tol,'omitnan');
end

function [lag_s,best,reason]=local_delay(x,y,Ts,window_s)
dx=diff(double(x(:))); dy=diff(double(y(:)));
if std(dx,'omitnan')<1e-12, lag_s=NaN;best=NaN;reason='theta_true_first_difference_zero_variance';return; end
if std(dy,'omitnan')<1e-12, lag_s=NaN;best=NaN;reason='theta_sched_first_difference_zero_variance';return; end
maxlag=min(round(window_s/Ts),numel(dx)-3); lags=(-maxlag:maxlag).'; scores=nan(size(lags));
for i=1:numel(lags)
    L=lags(i);
    if L>=0, a=dx(1:end-L); b=dy(1+L:end); else, a=dx(1-L:end); b=dy(1:end+L); end
    m=isfinite(a)&isfinite(b); if nnz(m)>=3, C=corrcoef(a(m),b(m)); scores(i)=C(1,2); end
end
[best,j]=max(scores,[],'omitnan');
if isempty(j)||~isfinite(best),lag_s=NaN;reason='no_finite_cross_correlation';else,lag_s=lags(j)*Ts;reason='positive_means_theta_sched_lags_theta_true';end
end

function local_json(file,s)
fid=fopen(file,'w','n','UTF-8'); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(s,'PrettyPrint',true,'ConvertInfAndNaN',true));
end
