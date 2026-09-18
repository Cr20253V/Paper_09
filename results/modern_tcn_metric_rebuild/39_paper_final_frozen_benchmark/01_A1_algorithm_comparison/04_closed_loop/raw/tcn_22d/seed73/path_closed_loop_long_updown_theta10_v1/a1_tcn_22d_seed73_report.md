# A1 TCN seed73 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed73_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed73\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed73_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0806 | 0.2620 | 0.0390 | 0.0549 | 0.0213 | 0.7401 | 301.3002 | 0.8579 | 13.2571 | 0.0000 | 0.8406 | 1.1354 | 91.4273 | 51.0917 |
| TCN | 0.1512 | 0.4633 | 0.0713 | 0.1018 | 0.0360 | 1.5325 | 406.9669 | 0.3640 | 77.5789 | 0.0000 | 0.6667 | 1.9025 | 83.3601 | 36.9340 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0230 | 0.2462 | 0.0000 |
| TCN | 0.0095 | 0.0102 | 0.0128 | 0.0614 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0230 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0806 | 0.2620 | 0.0390 | 0.0549 | 0.0213 | 0.8579 | 13.2571 | 0.8406 | 1.1354 | 91.4273 | 51.0917 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0337 | 0.0677 | 0.0400 | 0.0627 | 0.0180 | 0.0943 | 26.1924 | 0.7748 | 1.0887 | 94.4615 | 64.5385 |
| ModernTCN | downhill_transition | 0.0264 | 0.0539 | 0.0272 | 0.0438 | 0.0117 | 0.1187 | 4.6943 | 0.7944 | 0.9849 | 92.6923 | 51.5385 |
| ModernTCN | uphill_return | 0.1134 | 0.2560 | 0.0320 | 0.0680 | 0.0241 | 0.3372 | 11.2041 | 1.2662 | 1.7518 | 84.8000 | 39.7000 |
| ModernTCN | flat_recovery | 0.1615 | 0.2620 | 0.0717 | 0.0371 | 0.0400 | 0.8579 | 11.9741 | 0.7028 | 0.9855 | 89.2000 | 13.4000 |
| TCN | all | 0.1512 | 0.4633 | 0.0713 | 0.1018 | 0.0360 | 0.3640 | 77.5789 | 0.6667 | 1.9025 | 83.3601 | 36.9340 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.1565 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1142 | 0.2367 | 0.0757 | 0.1315 | 0.0263 | 0.1704 | 134.0407 | 0.5011 | 2.6785 | 78.3846 | 65.7692 |
| TCN | downhill_transition | 0.1011 | 0.2138 | 0.0653 | 0.0527 | 0.0382 | 0.1696 | 5.8775 | 0.9810 | 1.1190 | 91.1538 | 22.3077 |
| TCN | uphill_return | 0.1427 | 0.4130 | 0.0544 | 0.1367 | 0.0456 | 0.3640 | 154.3436 | 0.8224 | 3.0748 | 91.7000 | 17.5000 |
| TCN | flat_recovery | 0.3124 | 0.4633 | 0.1111 | 0.0130 | 0.0391 | 0.3369 | 2.2996 | 0.2077 | 0.5323 | 51.2000 | 7.4000 |
