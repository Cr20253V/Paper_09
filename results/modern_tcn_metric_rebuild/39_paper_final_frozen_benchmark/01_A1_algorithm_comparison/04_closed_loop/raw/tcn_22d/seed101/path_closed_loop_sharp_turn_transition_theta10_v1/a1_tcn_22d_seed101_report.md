# A1 TCN seed101 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed101_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed101\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0393 | 0.0825 | 0.0343 | 0.0373 | 0.0189 | 0.4633 | 224.2241 | 0.2873 | 2.2166 | 0.0000 | 0.6662 | 0.8059 | 90.2737 | 49.9515 |
| TCN | 0.1517 | 0.3297 | 0.1497 | 0.0930 | 0.0638 | 1.7326 | 354.4891 | 1.4702 | 65.2279 | 0.0000 | 0.8591 | 1.6655 | 82.2559 | 60.2213 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0217 | 0.0225 | 0.2365 | 0.0000 |
| TCN | 0.0096 | 0.0105 | 0.0132 | 0.0664 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.4853 | 0.0388 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0393 | 0.0825 | 0.0343 | 0.0373 | 0.0189 | 0.2873 | 2.2166 | 0.6662 | 0.8059 | 90.2737 | 49.9515 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0462 | 0.0825 | 0.0527 | 0.0406 | 0.0238 | 0.1334 | 0.7098 | 0.7168 | 0.8292 | 93.5556 | 60.1667 |
| ModernTCN | downhill_right_transition | 0.0164 | 0.0261 | 0.0197 | 0.0342 | 0.0182 | 0.1415 | 4.2909 | 0.6639 | 0.8690 | 96.3500 | 37.7000 |
| ModernTCN | flat_left_exit | 0.0598 | 0.0761 | 0.0170 | 0.0409 | 0.0123 | 0.2873 | 1.2476 | 0.8138 | 0.9204 | 68.8000 | 38.6000 |
| TCN | all | 0.1517 | 0.3297 | 0.1497 | 0.0930 | 0.0638 | 1.4702 | 65.2279 | 0.8591 | 1.6655 | 82.2559 | 60.2213 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.7888 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.1707 | 0.3287 | 0.1427 | 0.1222 | 0.0289 | 0.5635 | 59.9216 | 0.9908 | 2.6083 | 81.0556 | 81.2778 |
| TCN | downhill_right_transition | 0.1746 | 0.3297 | 0.1633 | 0.0919 | 0.0710 | 1.1442 | 37.0173 | 0.9086 | 1.7818 | 82.7000 | 44.9500 |
| TCN | flat_left_exit | 0.0716 | 0.1458 | 0.1594 | 0.0248 | 0.0968 | 1.4702 | 152.7138 | 0.5086 | 0.3203 | 77.3000 | 39.0000 |
