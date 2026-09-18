# A1 GRU seed7 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed7_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed7\path_closed_loop_long_updown_theta10_v1\gru_22d_seed7_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 8.0000 | 4.0000 | 6.0000 | 18.0000 | 1.0000 |
| ModernTCN | 10.0000 | 5.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0197 | 0.0699 | 0.0257 | 0.0490 | 0.0192 | 0.4564 | 275.3162 | 0.2094 | 4.8827 | 0.0000 | 0.8474 | 1.1167 | 91.4043 | 38.0142 |
| GRU | 0.0600 | 0.1674 | 0.0204 | 0.0458 | 0.0146 | 0.2351 | 262.8859 | 0.4967 | 0.7502 | 0.0000 | 0.8134 | 0.9886 | 88.6003 | 53.8497 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0231 | 0.2421 | 0.0000 |
| GRU | 0.0087 | 0.0095 | 0.0104 | 0.0190 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0197 | 0.0699 | 0.0257 | 0.0490 | 0.0192 | 0.2094 | 4.8827 | 0.8474 | 1.1167 | 91.4043 | 38.0142 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0332 | 0.0699 | 0.0373 | 0.0463 | 0.0210 | 0.0854 | 1.2031 | 0.8686 | 1.0450 | 94.6923 | 69.8462 |
| ModernTCN | downhill_transition | 0.0088 | 0.0229 | 0.0166 | 0.0510 | 0.0186 | 0.2094 | 6.0145 | 0.9324 | 1.2304 | 92.0769 | 27.6923 |
| ModernTCN | uphill_return | 0.0084 | 0.0222 | 0.0203 | 0.0547 | 0.0171 | 0.1005 | 3.0517 | 0.9120 | 1.2872 | 85.3000 | 11.8000 |
| ModernTCN | flat_recovery | 0.0130 | 0.0235 | 0.0241 | 0.0462 | 0.0240 | 0.0919 | 16.9080 | 0.8679 | 1.2269 | 89.0000 | 3.6000 |
| GRU | all | 0.0600 | 0.1674 | 0.0204 | 0.0458 | 0.0146 | 0.4967 | 0.7502 | 0.8134 | 0.9886 | 88.6003 | 53.8497 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2220 | 0.0000 | 0.0002637 | 102.1406 | 1.1290 | 0.7748 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0206 | 0.0400 | 0.0079 | 0.0350 | 0.0071 | 0.1348 | 0.1530 | 0.5901 | 0.5238 | 87.5385 | 82.7692 |
| GRU | downhill_transition | 0.0803 | 0.1674 | 0.0207 | 0.0563 | 0.0153 | 0.3060 | 1.2101 | 0.9759 | 1.3155 | 91.6154 | 50.5385 |
| GRU | uphill_return | 0.0630 | 0.1306 | 0.0306 | 0.0308 | 0.0201 | 0.4967 | 0.8451 | 0.5362 | 0.9478 | 83.0000 | 22.1000 |
| GRU | flat_recovery | 0.0742 | 0.1074 | 0.0220 | 0.0564 | 0.0178 | 0.3882 | 0.3532 | 1.2510 | 1.4554 | 89.0000 | 27.8000 |
