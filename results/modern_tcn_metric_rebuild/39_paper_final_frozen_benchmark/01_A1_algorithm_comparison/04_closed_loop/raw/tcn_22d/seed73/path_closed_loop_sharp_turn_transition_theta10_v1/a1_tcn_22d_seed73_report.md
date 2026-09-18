# A1 TCN seed73 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed73_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed73\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed73_out.mat`
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
| ModernTCN | 0.0541 | 0.1638 | 0.0458 | 0.0388 | 0.0248 | 0.5744 | 226.5429 | 1.4640 | 2.2045 | 0.0000 | 0.6936 | 0.8154 | 93.7100 | 55.6979 |
| TCN | 0.1141 | 0.2995 | 0.0970 | 0.0628 | 0.0417 | 1.1068 | 311.2292 | 1.4881 | 63.2638 | 0.0000 | 0.5530 | 1.0287 | 83.1489 | 58.0664 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0218 | 0.0228 | 0.2415 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0136 | 0.0640 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0582 | 0.0194 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.1165 | 0.0194 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0541 | 0.1638 | 0.0458 | 0.0388 | 0.0248 | 1.4640 | 2.2045 | 0.6936 | 0.8154 | 93.7100 | 55.6979 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0474 | 0.0870 | 0.0550 | 0.0394 | 0.0262 | 0.1384 | 0.6550 | 0.6389 | 0.7472 | 95.2222 | 65.3889 |
| ModernTCN | downhill_right_transition | 0.0290 | 0.0623 | 0.0302 | 0.0458 | 0.0178 | 0.1830 | 3.0292 | 0.9818 | 1.1785 | 93.4500 | 48.7000 |
| ModernTCN | flat_left_exit | 0.0968 | 0.1638 | 0.0596 | 0.0232 | 0.0363 | 1.4640 | 3.8083 | 0.4592 | 0.4983 | 89.3000 | 36.8000 |
| TCN | all | 0.1141 | 0.2995 | 0.0970 | 0.0628 | 0.0417 | 1.4881 | 63.2638 | 0.5530 | 1.0287 | 83.1489 | 58.0664 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.3218 | 0.0000 | 61.7500 | 100.0000 |
| TCN | uphill_left_transition | 0.1577 | 0.2995 | 0.1160 | 0.0961 | 0.0370 | 0.3603 | 152.4455 | 0.4751 | 1.8693 | 89.9444 | 67.2778 |
| TCN | downhill_right_transition | 0.0452 | 0.1020 | 0.0855 | 0.0402 | 0.0463 | 0.3610 | 22.0252 | 0.6926 | 0.8248 | 92.2500 | 56.4500 |
| TCN | flat_left_exit | 0.1350 | 0.2049 | 0.0980 | 0.0158 | 0.0468 | 1.4881 | 6.0693 | 0.4783 | 0.2843 | 62.2000 | 30.1000 |
