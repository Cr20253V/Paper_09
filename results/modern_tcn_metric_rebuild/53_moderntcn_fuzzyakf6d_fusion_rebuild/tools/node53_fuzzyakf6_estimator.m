function [state,out]=node53_fuzzyakf6_estimator(action,state_or_cfg,packet)
%NODE53_FUZZYAKF6_ESTIMATOR Independent frozen R2_06 implementation.
switch lower(char(action))
    case 'init'
        c=state_or_cfg;
        state=struct('method_id',char(c.method_id),'cfg',c,'x',[0;0], ...
            'P',diag([deg2rad(c.initial_pitch_std_deg)^2 c.initial_bias_std_rad_s^2]), ...
            'initialized',false,'gyro_energy',0);
        out=local_out(0,0,0,0,0,0,0,min(eig(state.P)),false,0,0);
    case 'update'
        state=state_or_cfg;c=state.cfg;p=double(packet(:));
        if numel(p)~=6||any(~isfinite(p));error('node53:FuzzyPacket','Expected six finite IMU channels.');end
        a=p(1:3);gyro=p(4:6);an=norm(a);theta_acc=atan2(a(1),a(3));
        if ~state.initialized;state.x(1)=theta_acc;state.initialized=true;end
        F=[1 -c.Ts;0 1];xpred=[state.x(1)+c.Ts*(gyro(2)-state.x(2));state.x(2)];
        Q=diag([(c.gyro_noise_std_rad_s*c.Ts)^2 (c.bias_rw_std_rad_s*c.Ts)^2]);
        Ppred=local_psd(F*state.P*F'+Q);innovation=atan2(sin(theta_acc-xpred(1)),cos(theta_acc-xpred(1)));
        state.gyro_energy=c.vibration_alpha*state.gyro_energy+(1-c.vibration_alpha)*(gyro'*gyro);
        fn=min(1,abs(an-c.g)/(c.norm_full_scale_g*c.g));fv=min(1,sqrt(max(state.gyro_energy,0))/c.gyro_full_scale_rad_s);fi=min(1,abs(innovation)/deg2rad(c.innovation_full_scale_deg));
        risk=c.norm_weight*fn+c.vibration_weight*fv+c.innovation_weight*fi;R=deg2rad(c.accel_pitch_std_deg)^2*(1+c.max_r_multiplier*min(1,risk));
        S=Ppred(1,1)+R;K=Ppred(:,1)/S;state.x=xpred+K*innovation;IKH=eye(2)-K*[1 0];state.P=local_psd(IKH*Ppred*IKH'+K*R*K');
        weight=1/(1+c.max_r_multiplier*min(1,risk));nis=innovation^2/S;mineig=min(eig(state.P));valid=all(isfinite(state.x))&&all(isfinite(state.P(:)))&&mineig>=-1e-10;
        out=local_out(state.x(1),theta_acc,xpred(1),weight,an,innovation,nis,mineig,valid,state.gyro_energy,fv);
    otherwise;error('node53:FuzzyAction','Unknown action.');
end
end
function out=local_out(theta,theta_acc,pred,weight,an,innovation,nis,mineig,valid,energy,vibration)
out=struct('theta_imu',double(theta),'theta_acc',double(theta_acc),'theta_pred',double(pred), ...
 'accel_weight',double(weight),'accel_norm',double(an),'innovation',double(innovation),'nis',double(nis), ...
 'NIS',double(nis),'min_covariance_eigenvalue',double(mineig),'observer_valid',logical(valid),'valid',logical(valid), ...
 'gyro_energy',double(energy),'gyro_vibration_feature',double(vibration));
end
function P=local_psd(P),P=(P+P')/2;[V,D]=eig(P);P=V*diag(max(diag(D),1e-12))*V';P=(P+P')/2;end
