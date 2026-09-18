# Node53 V7 60-case closed-loop report

Classification: RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK.

## Completeness and integrity

- Complete cases: 60/60.
- Case safety passes: 60/60.
- Artifact hash mismatches: 0.
- Input/config hash mismatches: 0.

## Paired bootstrap

Effect = ModernTCN-only minus Fusion; a positive value favors Fusion.

- ey_rmse: baseline=0.0263489490561, fusion=0.0189109904479, effect=0.00743795860827, 95% CI=[0.00245344430189, 0.0152668755497], CI support=True.
- epsi_rmse: baseline=0.0221613342475, fusion=0.0193276061971, effect=0.00283372805036, 95% CI=[0.000644952765608, 0.00614654128514], CI support=True.
- j_du: baseline=0.930530763681, fusion=0.673614563077, effect=0.256916200604, 95% CI=[-0.0134858586395, 0.933331096146], CI support=False.

## Claim boundary

The confidence intervals support Fusion for ey_rmse and epsi_rmse, but not for j_du.
Therefore the result supports those two primary metrics only; it does not support a claim that all three primary metrics improved.
The V7 protocol records qualification_bypassed=true and formal_claim_allowed=false, so this report remains exploratory retrospective evidence rather than a final paper-qualification result.
