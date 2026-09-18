function [state,out] = node53_v6_uncertainty_fusion(action,state_or_cfg,in)
%NODE53_V6_UNCERTAINTY_FUSION V6 gated bounded correction.
switch lower(char(action))
    case 'init'; state=struct('cfg',state_or_cfg,'correction',0); out=local_default();
    case 'update'; [state,out]=local_update(state_or_cfg,in);
    otherwise; error('node53:V6FusionAction','Unknown action.');
end
end

function [s,o]=local_update(s,in)
c=s.cfg; tcn=double(in.theta_tcn); innovation=double(in.theta_imu)-tcn;
regime=1+double(abs(tcn)>=c.flat_threshold)+2*double(abs(double(in.theta_tcn_rate))>=c.transition_rate_threshold);
quality=max(0,min(1,double(in.quality_score))); qb=1+double(quality>=c.quality_edges(1))+double(quality>=c.quality_edges(2));
pbase=max(c.P_tcn_total(regime,qb),c.variance_floor); pobs=max(c.P_fuzzyakf_total(regime,qb),c.variance_floor);
cross=c.cross_error_total(regime,qb); inflation=1+c.conf_inflation_gain*(1-max(0,min(1,double(in.conf_main))));
ptcn=inflation*pbase; cross=sqrt(inflation)*cross; bound=c.correlation_clip*sqrt(ptcn*pobs); cross=max(-bound,min(bound,cross));
S=max(ptcn+pobs-2*cross,c.S_floor); nis=innovation^2/S; kraw=(ptcn-cross)/S;
reason=0; if strcmpi(c.group,'G0'); reason=bitor(reason,1); end
if ~logical(in.tcn_ready); reason=bitor(reason,2); end
if ~logical(in.observer_valid); reason=bitor(reason,4); end
if abs(innovation)>c.innovation_gate; reason=bitor(reason,8); end
if nis>c.nis_reject; reason=bitor(reason,16); end
if ~logical(in.v6_gate); reason=bitor(reason,32); end
previous=s.correction;
if reason~=0
    s.correction=0; o=local_pack(tcn,pbase,ptcn,pobs,cross,S,nis,innovation,kraw,0,previous,0,0,true,reason,regime,quality,qb,c,in); return;
end
nw=1; if nis>c.nis_downweight; nw=sqrt(c.nis_downweight/nis); end
qw=max(c.quality_floor,min(1,c.quality_intercept-c.quality_slope*quality));
keff=min(c.Kmax,max(0,kraw))*qw*nw; target=max(-c.correction_limit,min(c.correction_limit,keff*innovation));
step=c.correction_rate_limit*c.Ts; s.correction=previous+max(-step,min(step,target-previous));
o=local_pack(tcn+s.correction,pbase,ptcn,pobs,cross,S,nis,innovation,kraw,keff,previous,s.correction,target,false,0,regime,quality,qb,c,in);
o.NIS_weight=nw; o.quality_weight=qw;
end

function o=local_pack(theta,pbase,ptcn,pobs,cross,S,nis,innovation,kraw,keff,previous,correction,target,fallback,reason,regime,quality,qb,c,in)
o=struct('theta_fused',theta,'P_tcn_base',pbase,'P_tcn',ptcn,'P_fuzzyakf_total',pobs,'cross_error_total',cross,'S',S,'NIS',nis,'innovation',innovation,'K_raw',kraw,'K_eff',keff,'Kmax',c.Kmax,'NIS_weight',1,'quality_weight',0,'correction_prev',previous,'correction',correction,'target_correction',target,'fallback',logical(fallback),'fallback_reason_code',double(reason),'innovation_gate_flag',logical(bitand(uint32(reason),uint32(8))),'nis_downweight_flag',nis>c.nis_downweight,'nis_reject_flag',logical(bitand(uint32(reason),uint32(16))),'Kmax_cap_flag',kraw>c.Kmax,'rate_limit_flag',abs(correction-previous)>c.correction_rate_limit*c.Ts+eps,'observer_valid',logical(in.observer_valid),'tcn_ready',logical(in.tcn_ready),'regime_index',regime,'quality_score',quality,'quality_bin',qb,'p_help',double(in.p_help),'v6_gate',logical(in.v6_gate));
end

function o=local_default()
o=struct('theta_fused',0,'P_tcn_base',1,'P_tcn',1,'P_fuzzyakf_total',1,'cross_error_total',0,'S',2,'NIS',0,'innovation',0,'K_raw',0,'K_eff',0,'Kmax',0,'NIS_weight',1,'quality_weight',0,'correction_prev',0,'correction',0,'target_correction',0,'fallback',true,'fallback_reason_code',1,'innovation_gate_flag',false,'nis_downweight_flag',false,'nis_reject_flag',false,'Kmax_cap_flag',false,'rate_limit_flag',false,'observer_valid',false,'tcn_ready',false,'regime_index',1,'quality_score',1,'quality_bin',3,'p_help',0,'v6_gate',false);
end
