# A1 TCN seed202 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed202_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed202\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed202_out.mat`
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
| ModernTCN | 0.0270 | 0.0803 | 0.0337 | 0.0587 | 0.0239 | 0.6070 | 312.9248 | 0.2489 | 14.4533 | 0.0000 | 0.8356 | 1.2099 | 89.4047 | 43.3693 |
| TCN | 0.4029 | 1.0842 | 0.1042 | 0.1324 | 0.0395 | 2.3803 | 391.3738 | 1.5363 | 207.4652 | 0.0000 | 0.8023 | 2.9690 | 87.9108 | 30.8205 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0231 | 0.2482 | 0.0000 |
| TCN | 0.0087 | 0.0093 | 0.0104 | 0.0578 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 7.4925 | 0.4826 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0270 | 0.0803 | 0.0337 | 0.0587 | 0.0239 | 0.2489 | 14.4533 | 0.8356 | 1.2099 | 89.4047 | 43.3693 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0397 | 0.0803 | 0.0454 | 0.0709 | 0.0266 | 0.1240 | 14.9911 | 0.7744 | 1.2789 | 91.3077 | 76.8462 |
| ModernTCN | downhill_transition | 0.0156 | 0.0274 | 0.0234 | 0.0559 | 0.0202 | 0.2489 | 9.8073 | 1.1275 | 1.3230 | 92.2308 | 27.2308 |
| ModernTCN | uphill_return | 0.0210 | 0.0518 | 0.0276 | 0.0591 | 0.0196 | 0.1100 | 23.2140 | 0.8249 | 1.3490 | 80.8000 | 19.5000 |
| ModernTCN | flat_recovery | 0.0266 | 0.0530 | 0.0394 | 0.0372 | 0.0362 | 0.1696 | 14.2021 | 0.6763 | 1.0649 | 89.0000 | 17.8000 |
| TCN | all | 0.4029 | 1.0842 | 0.1042 | 0.1324 | 0.0395 | 1.5363 | 207.4652 | 0.8023 | 2.9690 | 87.9108 | 30.8205 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.1028 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1520 | 0.3267 | 0.0834 | 0.1671 | 0.0278 | 0.4472 | 156.0974 | 0.5049 | 4.1553 | 88.5385 | 69.5385 |
| TCN | downhill_transition | 0.3157 | 0.6994 | 0.0660 | 0.1007 | 0.0319 | 0.3696 | 3.4425 | 1.1364 | 2.0867 | 91.1538 | 6.3077 |
| TCN | uphill_return | 0.3977 | 0.9018 | 0.1093 | 0.1535 | 0.0224 | 0.7303 | 58.3696 | 0.8840 | 4.0019 | 81.3000 | 7.8000 |
| TCN | flat_recovery | 0.8814 | 1.0842 | 0.2027 | 0.0778 | 0.0891 | 1.5363 | 1276 | 0.8831 | 1.6032 | 85.0000 | 5.4000 |
