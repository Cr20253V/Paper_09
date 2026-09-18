# A1 TCN seed21 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed21_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed21\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed21_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0370 | 0.1035 | 0.0306 | 0.0369 | 0.0146 | 0.3998 | 224.8742 | 0.4246 | 2.1333 | 0.0000 | 0.5973 | 0.6742 | 94.3506 | 72.7432 |
| TCN | 0.4914 | 1.2821 | 0.1294 | 0.0851 | 0.0538 | 1.7787 | 704.9307 | 1.4069 | 487.1284 | 0.0000 | 0.8039 | 1.5743 | 80.5086 | 39.4681 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0215 | 0.0224 | 0.2405 | 0.0000 |
| TCN | 0.0095 | 0.0106 | 0.0135 | 0.0771 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.1553 | 0.1359 | 9.3380 | 0.2718 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0370 | 0.1035 | 0.0306 | 0.0369 | 0.0146 | 0.4246 | 2.1333 | 0.5973 | 0.6742 | 94.3506 | 72.7432 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0565 | 0.1035 | 0.0470 | 0.0398 | 0.0180 | 0.1628 | 1.1938 | 0.5818 | 0.7188 | 91.8889 | 86.8889 |
| ModernTCN | downhill_right_transition | 0.0145 | 0.0286 | 0.0141 | 0.0404 | 0.0127 | 0.1513 | 3.4824 | 0.7283 | 0.9076 | 95.4000 | 70.2000 |
| ModernTCN | flat_left_exit | 0.0295 | 0.0465 | 0.0211 | 0.0262 | 0.0137 | 0.4246 | 1.5645 | 0.5729 | 0.3640 | 94.7000 | 42.9000 |
| TCN | all | 0.4914 | 1.2821 | 0.1294 | 0.0851 | 0.0538 | 1.4069 | 487.1284 | 0.8039 | 1.5743 | 80.5086 | 39.4681 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.3245 | 0.0000 | 61.7500 | 100.0000 |
| TCN | uphill_left_transition | 0.1541 | 0.3030 | 0.1460 | 0.1182 | 0.0423 | 0.4942 | 413.6910 | 0.6984 | 2.7502 | 86.3333 | 82.5000 |
| TCN | downhill_right_transition | 0.4753 | 0.9043 | 0.1191 | 0.0378 | 0.0625 | 0.4605 | 33.0955 | 0.8918 | 1.0374 | 92.2500 | 3.0500 |
| TCN | flat_left_exit | 0.8647 | 1.2821 | 0.1392 | 0.0954 | 0.0621 | 1.4069 | 1690 | 0.9700 | 1.0841 | 55.1000 | 13.7000 |
