# A1 Fair Algorithm Comparison — Final Experiment Report

- Protocol: `A0_paper_final_unified_protocol_v1`
- Final status: `COMPLETE`
- Final decision: `NOT_SUPPORTED`
- Decision reason: one or more applicable Node10 gate checks failed for the primary method
- Models: `40/40`; offline cases: `40/40`; closed-loop cases: `240/240`
- Closed-loop sources: `120` referenced upstream cases + `120` Node39 manual cases
- Protected A0, outline and `paper_v3.tex` unchanged: `True`

## Protocol compliance

All four methods use the frozen dataset/run split, training-set normalization, 128-step window and 22D raw input. The primary method uses the frozen 88D `delta_bank_124` construction. The six paths, ten seeds, Node10 v2 gates, plant revision, MPC configuration and training recipes were not changed in response to results. Missing values were not imputed.

## Unified offline evaluation

| Method | theta MAE (deg) | \|theta\|<=10 P95 error (deg) | main accuracy | stall recall | slope recall |
|---|---:|---:|---:|---:|---:|
| `modern_tcn_delta_bank_124` | 0.59888 | 1.6778 | 0.96452 | 0.66875 | 0.97669 |
| `modern_tcn_22d` | 0.653 | 1.8063 | 0.96438 | 0.66354 | 0.97542 |
| `gru_22d` | 0.88583 | 2.2595 | 0.93257 | 0.57083 | 0.95455 |
| `tcn_22d` | 0.91537 | 2.6358 | 0.74953 | 0.51354 | 0.86018 |

The paired 10,000-iteration seed bootstrap supports delta-bank over all three comparators for both preregistered offline primary metrics.

| Comparator | Metric | comparator − delta | 95% percentile CI | Seeds improved |
|---|---|---:|---:|---:|
| `modern_tcn_22d` | `theta_mae_deg` | 0.054119 | [0.0060846, 0.1018] | 8/10 |
| `modern_tcn_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.12849 | [0.029622, 0.22947] | 7/10 |
| `gru_22d` | `theta_mae_deg` | 0.28694 | [0.18468, 0.37271] | 9/10 |
| `gru_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.58172 | [0.38462, 0.80045] | 10/10 |
| `tcn_22d` | `theta_mae_deg` | 0.31648 | [0.24668, 0.38012] | 10/10 |
| `tcn_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.95802 | [0.6917, 1.2546] | 10/10 |

## Closed-loop comparison

| Method | ey RMSE | epsi RMSE | j_du | mean J_control_path | Node10 failed rows |
|---|---:|---:|---:|---:|---:|
| `modern_tcn_delta_bank_124` | 0.025956 | 0.023607 | 1.125 | 0.98371 | 24 |
| `modern_tcn_22d` | 0.064824 | 0.032183 | 17.037 | 1 | 0 |
| `gru_22d` | 1.9006 | 0.20514 | 291.65 | 822.03 | 60 |
| `tcn_22d` | 0.83263 | 0.17542 | 127.2 | 15.501 | 60 |

`J_control_path` is recomputed against the matched ModernTCN-22D seed/path case; historical J values are not reused.

| Comparator | Metric | comparator − delta | 95% percentile CI | Cases improved | CI supports delta |
|---|---|---:|---:|---:|---:|
| `modern_tcn_22d` | `ey_rmse` | 0.038868 | [-0.006538, 0.15744] | 30/60 | False |
| `modern_tcn_22d` | `epsi_rmse` | 0.0085759 | [-0.0025636, 0.026551] | 35/60 | False |
| `modern_tcn_22d` | `j_du` | 15.912 | [1.6384, 55.899] | 52/60 | True |
| `gru_22d` | `ey_rmse` | 1.8747 | [0.65763, 3.5073] | 45/60 | True |
| `gru_22d` | `epsi_rmse` | 0.18153 | [0.083273, 0.30549] | 41/60 | True |
| `gru_22d` | `j_du` | 290.52 | [158.59, 445.75] | 36/60 | True |
| `tcn_22d` | `ey_rmse` | 0.80667 | [0.37225, 1.2958] | 51/60 | True |
| `tcn_22d` | `epsi_rmse` | 0.15181 | [0.071676, 0.24456] | 43/60 | True |
| `tcn_22d` | `j_du` | 126.07 | [69.86, 191.97] | 54/60 | True |

Delta-bank is clearly favored over GRU-22D and TCN-22D for all three closed-loop primary metrics. Against ModernTCN-22D, `j_du` is supported, while the `ey_rmse` and `epsi_rmse` confidence intervals cross zero.

## 22D architecture control

| Domain | Target | Comparator | Metric | comparator − target | 95% CI | Supported |
|---|---|---|---|---:|---:|---:|
| offline | `modern_tcn_22d` | `gru_22d` | `theta_mae_deg` | 0.23283 | [0.13218, 0.32451] | True |
| offline | `modern_tcn_22d` | `gru_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.45324 | [0.21468, 0.69883] | True |
| offline | `modern_tcn_22d` | `tcn_22d` | `theta_mae_deg` | 0.26237 | [0.21847, 0.30595] | True |
| offline | `modern_tcn_22d` | `tcn_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.82953 | [0.55081, 1.1305] | True |
| offline | `gru_22d` | `tcn_22d` | `theta_mae_deg` | 0.02954 | [-0.079305, 0.1273] | False |
| offline | `gru_22d` | `tcn_22d` | `theta_abs_le_10_p95_abs_err_deg` | 0.3763 | [0.050481, 0.71863] | True |
| closed_loop | `modern_tcn_22d` | `gru_22d` | `ey_rmse` | 1.8358 | [0.59436, 3.4843] | True |
| closed_loop | `modern_tcn_22d` | `gru_22d` | `epsi_rmse` | 0.17296 | [0.070819, 0.29861] | True |
| closed_loop | `modern_tcn_22d` | `gru_22d` | `j_du` | 274.61 | [136.27, 432.14] | True |
| closed_loop | `modern_tcn_22d` | `tcn_22d` | `ey_rmse` | 0.7678 | [0.35035, 1.2522] | True |
| closed_loop | `modern_tcn_22d` | `tcn_22d` | `epsi_rmse` | 0.14324 | [0.065308, 0.23365] | True |
| closed_loop | `modern_tcn_22d` | `tcn_22d` | `j_du` | 110.16 | [51.012, 174.18] | True |
| closed_loop | `gru_22d` | `tcn_22d` | `ey_rmse` | -1.068 | [-2.6842, 0.22496] | False |
| closed_loop | `gru_22d` | `tcn_22d` | `epsi_rmse` | -0.029719 | [-0.16294, 0.092806] | False |
| closed_loop | `gru_22d` | `tcn_22d` | `j_du` | -164.45 | [-328.85, -8.3959] | False |

ModernTCN-22D is supported over both GRU-22D and traditional TCN-22D on the offline architecture controls and all three closed-loop primary metrics. The exploratory GRU-versus-TCN comparison is mixed.

## Paired representation ablation

| Domain | Metric | ModernTCN-22D − delta-bank | 95% CI | Supported |
|---|---|---:|---:|---:|
| offline | `theta_mae_deg` | 0.054119 | [0.0060846, 0.1018] | True |
| offline | `theta_edge_p95_abs_err` | 0.42608 | [0.18517, 0.70987] | True |
| closed_loop | `ey_rmse` | 0.038868 | [-0.006538, 0.15744] | False |
| closed_loop | `epsi_rmse` | 0.0085759 | [-0.0025636, 0.026551] | False |
| closed_loop | `j_du` | 15.912 | [1.6384, 55.899] | True |

The 88D delta-bank representation improves both offline ablation metrics. In closed loop it substantially reduces `j_du`, but the two tracking-error CIs do not exclude zero.

## Frozen Node10 gate audit

- `stall_recall_min_drop`: 0.05
- `flat_peak_theta_error_max_ratio`: 1.05
- The 24 failed path rows arise from four seed-level offline gate failures repeated across the six frozen paths; they are not 24 independent offline failures.

| Seed | Gate | Delta value | ModernTCN-22D value | Difference/ratio |
|---:|---|---:|---:|---:|
| 21 | `stall_recall_drop` | 0.64583 | 0.69792 | 0.052083 |
| 101 | `stall_recall_drop` | 0.64583 | 0.69792 | 0.052083 |
| 73 | `theta_flat_abs_max_deg_ratio` | 6.6794 | 5.5036 | 1.2136 |
| 340 | `theta_flat_abs_max_deg_ratio` | 8.9767 | 6.629 | 1.3542 |

Because the primary method fails an applicable frozen gate, the preregistered decision rule requires `NOT_SUPPORTED`, even though its aggregate offline results and most closed-loop comparisons are favorable.

## Worst-path and worst-case audit

| Method | Worst path | Path mean J | Worst seed | Seed mean J | Worst case | Case J |
|---|---|---:|---:|---:|---|---:|
| `modern_tcn_delta_bank_124` | `p06_downhill_after_turn` | 1.2096 | 520 | 1.9797 | seed 520 / `p01_factory_logistics_showcase` | 5.1797 |
| `modern_tcn_22d` | `p01_factory_logistics_showcase` | 1 | 1 | 1 | seed 1 / `p01_factory_logistics_showcase` | 1 |
| `gru_22d` | `p05_factory_flat_logistics` | 4331.6 | 21 | 3210.9 | seed 21 / `p05_factory_flat_logistics` | 18587 |
| `tcn_22d` | `p01_factory_logistics_showcase` | 57.285 | 21 | 40.21 | seed 21 / `p01_factory_logistics_showcase` | 178.75 |

## Final decision

**`NOT_SUPPORTED`** — one or more applicable Node10 gate checks failed for the primary method.

This result is retained without changing paths, seeds, thresholds, plant/MPC settings or model recipes. No manuscript source file was modified.
