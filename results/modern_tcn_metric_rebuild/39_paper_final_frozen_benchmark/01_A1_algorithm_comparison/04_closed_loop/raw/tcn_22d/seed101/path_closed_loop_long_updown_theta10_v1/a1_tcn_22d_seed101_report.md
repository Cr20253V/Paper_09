# A1 TCN seed101 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed101_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed101\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0836 | 0.2550 | 0.0429 | 0.0703 | 0.0262 | 0.7449 | 330.6959 | 0.9263 | 15.9342 | 0.0000 | 1.0385 | 1.4869 | 87.2213 | 43.0246 |
| TCN | 0.1522 | 0.4584 | 0.0723 | 0.1261 | 0.0359 | 1.5259 | 414.0088 | 0.9026 | 286.4814 | 0.0000 | 1.1159 | 2.6477 | 74.4427 | 35.9458 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0233 | 0.2455 | 0.0000 |
| TCN | 0.0096 | 0.0103 | 0.0136 | 0.0639 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0230 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.1379 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0836 | 0.2550 | 0.0429 | 0.0703 | 0.0262 | 0.9263 | 15.9342 | 1.0385 | 1.4869 | 87.2213 | 43.0246 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0479 | 0.0970 | 0.0583 | 0.0907 | 0.0323 | 0.1526 | 35.3665 | 1.1007 | 1.7691 | 82.0000 | 70.8462 |
| ModernTCN | downhill_transition | 0.0203 | 0.0391 | 0.0346 | 0.0542 | 0.0273 | 0.2629 | 8.3003 | 0.9771 | 1.3207 | 92.9231 | 26.4615 |
| ModernTCN | uphill_return | 0.1116 | 0.2500 | 0.0245 | 0.0726 | 0.0219 | 0.1187 | 5.0588 | 1.2724 | 1.6664 | 82.6000 | 32.9000 |
| ModernTCN | flat_recovery | 0.1698 | 0.2550 | 0.0533 | 0.0546 | 0.0194 | 0.9263 | 14.3420 | 1.0901 | 1.5724 | 88.8000 | 5.6000 |
| TCN | all | 0.1522 | 0.4584 | 0.0723 | 0.1261 | 0.0359 | 0.9026 | 286.4814 | 1.1159 | 2.6477 | 74.4427 | 35.9458 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.3538 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1398 | 0.2983 | 0.0785 | 0.1459 | 0.0260 | 0.3759 | 793.2860 | 1.0058 | 3.3778 | 72.0000 | 71.1538 |
| TCN | downhill_transition | 0.0868 | 0.1704 | 0.0606 | 0.0706 | 0.0364 | 0.5741 | 10.0681 | 1.4706 | 1.5700 | 94.0000 | 11.0769 |
| TCN | uphill_return | 0.1274 | 0.3850 | 0.0503 | 0.1708 | 0.0466 | 0.4117 | 108.3354 | 0.6955 | 4.1167 | 64.1000 | 24.5000 |
| TCN | flat_recovery | 0.3140 | 0.4584 | 0.1218 | 0.1063 | 0.0405 | 0.9026 | 188.4366 | 1.6665 | 1.9427 | 38.0000 | 0.0000 |
