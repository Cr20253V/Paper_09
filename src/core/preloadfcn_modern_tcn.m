function preloadfcn_modern_tcn()
%PRELOADFCN_MODERN_TCN PreLoadFcn entry for the ModernTCN closed-loop model.
%
% The common LPV/MPC initialization lives in preloadfcn_gru. The mode flag
% selects the frozen ModernTCN artifact instead of loading a GRU artifact.

preloadfcn_gru('modern_tcn');
end
