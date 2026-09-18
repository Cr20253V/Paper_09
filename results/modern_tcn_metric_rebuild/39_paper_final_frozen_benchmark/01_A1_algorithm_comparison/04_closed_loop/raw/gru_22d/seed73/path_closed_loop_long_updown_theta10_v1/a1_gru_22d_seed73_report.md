# A1 GRU seed73 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed73_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed73\path_closed_loop_long_updown_theta10_v1\gru_22d_seed73_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 7.0000 | 6.0000 | 5.0000 | 18.0000 | 1.0000 |
| ModernTCN | 11.0000 | 3.0000 | 7.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0806 | 0.2620 | 0.0390 | 0.0549 | 0.0213 | 0.7401 | 301.3002 | 0.8579 | 13.2571 | 0.0000 | 0.8406 | 1.1354 | 91.4273 | 51.0917 |
| GRU | 0.0749 | 0.2469 | 0.0336 | 0.0496 | 0.0335 | 0.5251 | 266.1885 | 0.7860 | 0.9071 | 0.0000 | 0.9338 | 1.1987 | 90.3930 | 50.5631 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0230 | 0.2462 | 0.0000 |
| GRU | 0.0104 | 0.0114 | 0.0147 | 0.0204 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0230 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0460 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0806 | 0.2620 | 0.0390 | 0.0549 | 0.0213 | 0.8579 | 13.2571 | 0.8406 | 1.1354 | 91.4273 | 51.0917 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0337 | 0.0677 | 0.0400 | 0.0627 | 0.0180 | 0.0943 | 26.1924 | 0.7748 | 1.0887 | 94.4615 | 64.5385 |
| ModernTCN | downhill_transition | 0.0264 | 0.0539 | 0.0272 | 0.0438 | 0.0117 | 0.1187 | 4.6943 | 0.7944 | 0.9849 | 92.6923 | 51.5385 |
| ModernTCN | uphill_return | 0.1134 | 0.2560 | 0.0320 | 0.0680 | 0.0241 | 0.3372 | 11.2041 | 1.2662 | 1.7518 | 84.8000 | 39.7000 |
| ModernTCN | flat_recovery | 0.1615 | 0.2620 | 0.0717 | 0.0371 | 0.0400 | 0.8579 | 11.9741 | 0.7028 | 0.9855 | 89.2000 | 13.4000 |
| GRU | all | 0.0749 | 0.2469 | 0.0336 | 0.0496 | 0.0335 | 0.7860 | 0.9071 | 0.9338 | 1.1987 | 90.3930 | 50.5631 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2189 | 0.0000 | 0.0002637 | 101.9739 | 0.6532 | 0.4251 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0111 | 0.0237 | 0.0093 | 0.0342 | 0.0075 | 0.1264 | 0.1786 | 0.8642 | 0.8637 | 92.9231 | 74.5385 |
| GRU | downhill_transition | 0.1153 | 0.2469 | 0.0305 | 0.0655 | 0.0161 | 0.4115 | 1.1739 | 1.1626 | 1.5521 | 92.1538 | 51.0769 |
| GRU | uphill_return | 0.0768 | 0.1986 | 0.0415 | 0.0326 | 0.0360 | 0.7860 | 1.4995 | 0.5976 | 1.0538 | 81.7000 | 31.1000 |
| GRU | flat_recovery | 0.0462 | 0.0770 | 0.0610 | 0.0644 | 0.0795 | 0.2981 | 0.5375 | 1.2696 | 1.7864 | 91.8000 | 1.2000 |
