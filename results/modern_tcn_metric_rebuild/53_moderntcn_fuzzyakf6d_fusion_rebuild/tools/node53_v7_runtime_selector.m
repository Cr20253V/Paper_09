function [state,out]=node53_v7_runtime_selector(action,varargin)
%NODE53_V7_RUNTIME_SELECTOR ModernTCN-delta plus V7 supervised gate.
switch lower(char(action))
    case 'init'
        params=varargin{1}; cfg=varargin{2}; state=struct();
        state.tcn=ModernTCN_state_classifier('init',params,cfg.tcn);
        [state.fuzzy,f]=node53_fuzzyakf6_estimator('init',cfg.estimator,[]);
        [state.fusion,~]=node53_v7_uncertainty_fusion('init',cfg.fusion,[]);
        state.step=0; state.theta_tcn_prev=0; state.cfg=cfg; node53_v7_debug_buffer('reset');
        out=local_default(); out.theta_fuzzyakf=f.theta_imu;
    case 'update'
        state=varargin{1}; legacy=double(varargin{2}(:)); packet=double(varargin{3}(:));
        if numel(legacy)~=34||numel(packet)~=6||any(~isfinite([legacy;packet])); error('node53:V7RuntimeInput','Expected finite 34D frame and 6D IMU.'); end
        [state.tcn,tcn]=ModernTCN_state_classifier('update',state.tcn,legacy,zeros(2,1));
        [state.fuzzy,f]=node53_fuzzyakf6_estimator('update',state.fuzzy,packet);
        theta_tcn=double(tcn.theta_hat_for_mpc); rate=(theta_tcn-state.theta_tcn_prev)/state.cfg.fusion.Ts;
        ready=false; if isfield(tcn,'debug')&&isfield(tcn.debug,'ready'); ready=logical(tcn.debug.ready); end
        [features,aux]=node53_v7_runtime_features(state.cfg.quality_model,f,state.cfg.sensor.g,theta_tcn,rate,double(tcn.conf_main));
        p_help=node53_v7_predict_help(state.cfg.v7_model,features); gate=p_help>=state.cfg.v7_p_help_threshold;
        fin=struct('theta_tcn',theta_tcn,'theta_tcn_rate',rate,'conf_main',double(tcn.conf_main),'tcn_ready',ready, ...
            'theta_imu',double(f.theta_imu),'observer_valid',logical(f.observer_valid),'quality_score',aux.quality_score, ...
            'p_help',p_help,'v7_gate',gate);
        [state.fusion,fused]=node53_v7_uncertainty_fusion('update',state.fusion,fin);
        state.step=state.step+1; state.theta_tcn_prev=theta_tcn; out=fused; out.theta_hat_for_mpc=fused.theta_fused;
        out.theta_tcn=theta_tcn; out.theta_fuzzyakf=f.theta_imu; out.label_main=double(tcn.label_main); out.label_turn=double(tcn.label_turn); out.conf_main=double(tcn.conf_main);
        row=[state.step;packet;theta_tcn;f.theta_imu;f.accel_weight;f.accel_norm;f.innovation;f.nis;f.min_covariance_eigenvalue;f.gyro_energy;f.gyro_vibration_feature;fused.P_tcn_base;fused.P_tcn;fused.P_fuzzyakf_total;fused.cross_error_total;fused.S;fused.NIS;fused.innovation;fused.K_raw;fused.K_eff;fused.Kmax;fused.NIS_weight;fused.quality_weight;fused.correction_prev;fused.correction;fused.target_correction;fused.theta_fused;fused.theta_tcn_abs;double(fused.fallback);fused.fallback_reason_code;double(fused.innovation_gate_flag);double(fused.innovation_min_gate);double(fused.slope_gate);double(fused.nis_downweight_flag);double(fused.nis_reject_flag);double(fused.Kmax_cap_flag);double(fused.rate_limit_flag);double(f.observer_valid);double(ready);fused.regime_index;aux.quality_score;fused.quality_bin;p_help;double(gate);out.label_main;out.label_turn;out.conf_main];
        node53_v7_debug_buffer('append',row);
    otherwise; error('node53:V7RuntimeAction','Unknown action.');
end
end

function out=local_default()
out=struct('theta_hat_for_mpc',0,'theta_fused',0,'theta_tcn',0,'theta_fuzzyakf',0,'label_main',1,'label_turn',0,'conf_main',1);
end
