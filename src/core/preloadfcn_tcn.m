function preloadfcn_tcn()
%PRELOADFCN_TCN PreLoadFcn entry for LPVMPC_AGV_simulink_TCN.slx.
%
% This reuses the shared standalone LPV/MPC initialization and selects the
% TCN deployment config in Step 4.

preloadfcn_gru('tcn');
end
