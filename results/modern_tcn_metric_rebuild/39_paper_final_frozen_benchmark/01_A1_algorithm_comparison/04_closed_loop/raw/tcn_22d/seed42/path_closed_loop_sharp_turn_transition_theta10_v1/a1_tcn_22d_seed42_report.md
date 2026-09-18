# A1 TCN seed42 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed42_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed42\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 5.0000 | 4.0000 | 15.0000 | 1.0000 |
| TCN | 12.0000 | 4.0000 | 8.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0414 | 0.1007 | 0.0417 | 0.0372 | 0.0240 | 0.5698 | 223.5020 | 0.9883 | 10.2263 | 0.0000 | 0.6761 | 0.7861 | 94.1759 | 46.9423 |
| TCN | 0.1755 | 0.3561 | 0.1455 | 0.0715 | 0.0660 | 1.5406 | 327.8932 | 1.4813 | 136.3353 | 0.0000 | 0.6348 | 1.3449 | 86.2357 | 48.9614 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0217 | 0.0227 | 0.2444 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0131 | 0.0633 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0388 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.3494 | 0.1359 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0414 | 0.1007 | 0.0417 | 0.0372 | 0.0240 | 0.9883 | 10.2263 | 0.6761 | 0.7861 | 94.1759 | 46.9423 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0547 | 0.1007 | 0.0591 | 0.0442 | 0.0270 | 0.1587 | 0.7159 | 0.8934 | 1.0010 | 93.4444 | 63.9444 |
| ModernTCN | downhill_right_transition | 0.0264 | 0.0433 | 0.0304 | 0.0322 | 0.0257 | 0.1583 | 5.1157 | 0.5498 | 0.7400 | 96.3500 | 36.3500 |
| ModernTCN | flat_left_exit | 0.0452 | 0.0886 | 0.0284 | 0.0364 | 0.0182 | 0.9883 | 40.8773 | 0.7748 | 0.7674 | 89.1000 | 19.0000 |
| TCN | all | 0.1755 | 0.3561 | 0.1455 | 0.0715 | 0.0660 | 1.4813 | 136.3353 | 0.6348 | 1.3449 | 86.2357 | 48.9614 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.3768 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.1417 | 0.2816 | 0.1436 | 0.1087 | 0.0312 | 0.4081 | 305.6702 | 0.4418 | 2.2852 | 92.3889 | 78.2222 |
| TCN | downhill_right_transition | 0.2056 | 0.3561 | 0.1481 | 0.0465 | 0.0884 | 0.7077 | 40.5857 | 0.8347 | 1.1210 | 88.2500 | 17.7500 |
| TCN | flat_left_exit | 0.1946 | 0.2951 | 0.1676 | 0.0222 | 0.0710 | 1.4813 | 69.3570 | 0.6534 | 0.5719 | 66.4000 | 40.9000 |
