function result = node53_v7_reconstruct_audit(T,c)
%NODE53_V7_RECONSTRUCT_AUDIT Reconstruct V7 covariance, NIS and gain logs.
required = {'P_tcn','P_fuzzyakf_total','cross_error_total','S','NIS','innovation','K_raw','K_eff', ...
    'NIS_weight','quality_weight','quality_score','Kmax','fallback'};
if ~all(ismember(required,T.Properties.VariableNames))
    result = struct('status','FAIL_NODE53_V7_LOG_SCHEMA'); return;
end
expectedS = max(T.P_tcn + T.P_fuzzyakf_total - 2*T.cross_error_total, deg2rad(0.02)^2);
expectedNIS = T.innovation.^2 ./ expectedS;
expectedK = (T.P_tcn - T.cross_error_total) ./ expectedS;
expectedNisWeight = ones(height(T),1); down = expectedNIS > c.nis_downweight;
expectedNisWeight(down) = sqrt(c.nis_downweight ./ expectedNIS(down));
expectedQuality = max(c.quality_floor,min(1,c.quality_intercept-c.quality_slope*T.quality_score));
fallback = logical(T.fallback); expectedNisWeight(fallback)=1; expectedQuality(fallback)=0;
expectedKeff = min(T.Kmax,max(0,expectedK)) .* expectedQuality .* expectedNisWeight; expectedKeff(fallback)=0;
tol = @(x)1e-12+1e-10*abs(x);
errors = struct('S',local_max(abs(T.S-expectedS)),'NIS',local_max(abs(T.NIS-expectedNIS)), ...
    'K_raw',local_max(abs(T.K_raw-expectedK)),'NIS_weight',local_max(abs(T.NIS_weight-expectedNisWeight)), ...
    'quality_weight',local_max(abs(T.quality_weight-expectedQuality)),'K_eff',local_max(abs(T.K_eff-expectedKeff)));
passed = all(abs(T.S-expectedS)<=tol(expectedS)) && all(abs(T.NIS-expectedNIS)<=tol(expectedNIS)) && ...
    all(abs(T.K_raw-expectedK)<=tol(expectedK)) && all(abs(T.NIS_weight-expectedNisWeight)<=tol(expectedNisWeight)) && ...
    all(abs(T.quality_weight-expectedQuality)<=tol(expectedQuality)) && all(abs(T.K_eff-expectedKeff)<=tol(expectedKeff));
if passed; status='PASS_NODE53_V7_LOG_RECONSTRUCTION'; else; status='FAIL_NODE53_V7_LOG_RECONSTRUCTION'; end
result=struct('status',status,'row_count',height(T),'max_abs_error',errors, ...
    'quality_weight_formula','clip(quality_intercept-quality_slope*quality_score,quality_floor,1)', ...
    'nis_weight_formula','1 when NIS<=9 else sqrt(9/NIS)','fallback_identity','theta_fused==theta_tcn and correction==0');
end
function y=local_max(x), x=x(isfinite(x)); if isempty(x); y=NaN; else; y=max(x); end, end
