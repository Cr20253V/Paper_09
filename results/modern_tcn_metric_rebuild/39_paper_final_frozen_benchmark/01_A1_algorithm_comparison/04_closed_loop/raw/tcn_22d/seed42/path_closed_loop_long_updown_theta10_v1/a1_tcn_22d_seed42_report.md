# A1 TCN seed42 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed42_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed42\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed42_out.mat`
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
| ModernTCN | 0.0358 | 0.0948 | 0.0356 | 0.0649 | 0.0242 | 0.6997 | 298.9569 | 0.2520 | 8.0379 | 0.0000 | 0.9684 | 1.2507 | 91.7490 | 50.2183 |
| TCN | 0.2984 | 0.8491 | 0.0865 | 0.1276 | 0.0293 | 2.1331 | 392.3867 | 1.5104 | 235.0192 | 0.0000 | 0.7179 | 2.7466 | 74.9483 | 39.0025 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0231 | 0.2381 | 0.0000 |
| TCN | 0.0096 | 0.0105 | 0.0135 | 0.0618 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 1.8616 | 0.2298 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0358 | 0.0948 | 0.0356 | 0.0649 | 0.0242 | 0.2520 | 8.0379 | 0.9684 | 1.2507 | 91.7490 | 50.2183 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0439 | 0.0895 | 0.0444 | 0.0854 | 0.0210 | 0.1068 | 4.6225 | 1.3117 | 1.5027 | 92.3077 | 78.0000 |
| ModernTCN | downhill_transition | 0.0164 | 0.0298 | 0.0232 | 0.0554 | 0.0187 | 0.2520 | 11.2463 | 0.8872 | 1.1565 | 92.3077 | 28.1538 |
| ModernTCN | uphill_return | 0.0493 | 0.0948 | 0.0336 | 0.0643 | 0.0235 | 0.0788 | 3.2071 | 1.0615 | 1.5504 | 89.0000 | 48.8000 |
| ModernTCN | flat_recovery | 0.0242 | 0.0444 | 0.0475 | 0.0327 | 0.0439 | 0.1017 | 21.5776 | 0.5870 | 0.8685 | 90.2000 | 13.4000 |
| TCN | all | 0.2984 | 0.8491 | 0.0865 | 0.1276 | 0.0293 | 1.5104 | 235.0192 | 0.7179 | 2.7466 | 74.9483 | 39.0025 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.1827 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1378 | 0.2982 | 0.0851 | 0.1525 | 0.0238 | 0.4196 | 630.9798 | 0.4062 | 3.7165 | 77.0000 | 71.9231 |
| TCN | downhill_transition | 0.2077 | 0.4541 | 0.0779 | 0.0946 | 0.0342 | 0.2074 | 8.6842 | 1.0117 | 1.8760 | 89.2308 | 16.4615 |
| TCN | uphill_return | 0.2639 | 0.7049 | 0.0672 | 0.1532 | 0.0280 | 0.8444 | 54.6323 | 0.8768 | 3.7961 | 60.1000 | 23.1000 |
| TCN | flat_recovery | 0.6884 | 0.8491 | 0.1462 | 0.1025 | 0.0370 | 1.5104 | 273.2731 | 0.6955 | 1.7683 | 49.8000 | 13.4000 |
