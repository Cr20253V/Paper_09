# A1 TCN seed21 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed21_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed21\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed21_out.mat`
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
| ModernTCN | 0.0238 | 0.0646 | 0.0286 | 0.0566 | 0.0214 | 0.5108 | 284.4868 | 0.2077 | 26.1357 | 0.0000 | 0.8366 | 1.1637 | 90.0942 | 53.6428 |
| TCN | 0.3579 | 1.0015 | 0.0961 | 0.1304 | 0.0338 | 2.2907 | 404.2510 | 1.5584 | 191.8476 | 0.0000 | 0.8027 | 2.8750 | 75.7987 | 40.3356 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0232 | 0.2405 | 0.0000 |
| TCN | 0.0095 | 0.0105 | 0.0134 | 0.0598 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 4.8495 | 0.3218 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0238 | 0.0646 | 0.0286 | 0.0566 | 0.0214 | 0.2077 | 26.1357 | 0.8366 | 1.1637 | 90.0942 | 53.6428 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0321 | 0.0646 | 0.0394 | 0.0599 | 0.0239 | 0.0918 | 28.3700 | 0.8470 | 1.1251 | 91.0000 | 71.9231 |
| ModernTCN | downhill_transition | 0.0116 | 0.0253 | 0.0159 | 0.0492 | 0.0187 | 0.1955 | 4.7305 | 0.7696 | 1.1320 | 91.4615 | 41.5385 |
| ModernTCN | uphill_return | 0.0207 | 0.0571 | 0.0248 | 0.0688 | 0.0179 | 0.0677 | 53.4643 | 1.0518 | 1.5235 | 84.8000 | 56.7000 |
| ModernTCN | flat_recovery | 0.0323 | 0.0597 | 0.0345 | 0.0485 | 0.0308 | 0.2077 | 33.8772 | 0.9739 | 1.2111 | 89.8000 | 8.4000 |
| TCN | all | 0.3579 | 1.0015 | 0.0961 | 0.1304 | 0.0338 | 1.5584 | 191.8476 | 0.8027 | 2.8750 | 75.7987 | 40.3356 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.1580 | 0.0000 | 82.3333 | 100.0000 |
| TCN | uphill_long_entry | 0.1510 | 0.3271 | 0.0874 | 0.1636 | 0.0222 | 0.4487 | 165.2701 | 0.6731 | 4.0239 | 71.8462 | 68.9231 |
| TCN | downhill_transition | 0.2540 | 0.5542 | 0.0862 | 0.0956 | 0.0455 | 0.2445 | 15.4199 | 1.0196 | 1.9354 | 91.1538 | 15.2308 |
| TCN | uphill_return | 0.3303 | 0.8385 | 0.0856 | 0.1562 | 0.0209 | 0.6467 | 50.3967 | 0.8722 | 4.0091 | 63.5000 | 29.3000 |
| TCN | flat_recovery | 0.8180 | 1.0015 | 0.1624 | 0.0735 | 0.0489 | 1.5584 | 1100 | 0.7430 | 1.5054 | 69.4000 | 23.6000 |
