# A1 TCN seed520 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0266 | 0.0729 | 0.0358 | 0.0619 | 0.0261 | 0.6311 | 350.2730 | 0.2185 | 48.2297 | 0.0000 | 0.8084 | 1.2154 | 89.2209 | 40.8412 |
| TCN | 0.3384 | 0.9127 | 0.1009 | 0.1383 | 0.0405 | 2.3171 | 388.9666 | 1.5175 | 148.9763 | 0.0000 | 0.6028 | 3.0000 | 74.1209 | 36.6582 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0228 | 0.2402 | 0.0000 |
| TCN | 0.0086 | 0.0093 | 0.0100 | 0.0563 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 3.2636 | 0.2988 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0266 | 0.0729 | 0.0358 | 0.0619 | 0.0261 | 0.2185 | 48.2297 | 0.8084 | 1.2154 | 89.2209 | 40.8412 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0334 | 0.0655 | 0.0417 | 0.0640 | 0.0260 | 0.0989 | 36.2897 | 0.8295 | 1.2000 | 89.9231 | 75.7692 |
| ModernTCN | downhill_transition | 0.0106 | 0.0264 | 0.0198 | 0.0453 | 0.0183 | 0.2146 | 7.4215 | 0.7189 | 1.0212 | 92.6154 | 26.0000 |
| ModernTCN | uphill_return | 0.0287 | 0.0721 | 0.0378 | 0.0891 | 0.0240 | 0.1095 | 139.4720 | 1.1712 | 1.9627 | 78.2000 | 16.0000 |
| ModernTCN | flat_recovery | 0.0359 | 0.0729 | 0.0524 | 0.0327 | 0.0463 | 0.2185 | 26.6650 | 0.6666 | 0.8763 | 95.2000 | 8.8000 |
| TCN | all | 0.3384 | 0.9127 | 0.1009 | 0.1383 | 0.0405 | 1.5175 | 148.9763 | 0.6028 | 3.0000 | 74.1209 | 36.6582 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.2383 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1746 | 0.3703 | 0.0902 | 0.1754 | 0.0198 | 1.5158 | 199.5146 | 0.3742 | 4.5004 | 63.4615 | 70.2308 |
| TCN | downhill_transition | 0.2677 | 0.5716 | 0.0978 | 0.0927 | 0.0650 | 1.3198 | 93.2689 | 0.8127 | 1.7139 | 86.6154 | 7.6923 |
| TCN | uphill_return | 0.3124 | 0.7691 | 0.0909 | 0.1636 | 0.0239 | 1.4970 | 96.6773 | 0.6321 | 4.0761 | 67.3000 | 20.3000 |
| TCN | flat_recovery | 0.7316 | 0.9127 | 0.1612 | 0.1014 | 0.0341 | 1.5175 | 342.2027 | 0.7511 | 1.7966 | 70.0000 | 25.8000 |
