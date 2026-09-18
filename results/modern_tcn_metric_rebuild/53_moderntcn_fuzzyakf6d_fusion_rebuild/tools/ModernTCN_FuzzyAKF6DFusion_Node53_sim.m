function [theta_hat,label_main,label_turn,conf_main]=ModernTCN_FuzzyAKF6DFusion_Node53_sim(legacy_frame,imu_packet,reset)
%#codegen
coder.extrinsic('evalin','assignin','node53_runtime_selector');persistent state initialized
theta_hat=0;label_main=1;label_turn=0;conf_main=1;if isempty(initialized);initialized=false;end
if ~initialized||reset~=0;ready=evalin('base','exist(''params'',''var'')==1 && exist(''node53_runtime_cfg'',''var'')==1');if ~ready;return;end;p=evalin('base','params');c=evalin('base','node53_runtime_cfg');[state,~]=node53_runtime_selector('init',p,c);initialized=true;return;end
if isempty(state)||numel(legacy_frame)~=34||numel(imu_packet)~=6;return;end
[state,out]=node53_runtime_selector('update',state,double(legacy_frame(:)),double(imu_packet(:)));assignin('base','node53_runtime_out_temp',out);theta_hat=evalin('base','double(node53_runtime_out_temp.theta_hat_for_mpc)');label_main=evalin('base','double(node53_runtime_out_temp.label_main)');label_turn=evalin('base','double(node53_runtime_out_temp.label_turn)');conf_main=evalin('base','double(node53_runtime_out_temp.conf_main)');
end
