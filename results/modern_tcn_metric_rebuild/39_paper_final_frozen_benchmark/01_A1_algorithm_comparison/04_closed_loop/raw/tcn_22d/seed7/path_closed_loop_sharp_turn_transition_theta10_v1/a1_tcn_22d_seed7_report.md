# A1 TCN seed7 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed7_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed7\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed7_out.mat`
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
| ModernTCN | 0.0343 | 0.1019 | 0.0368 | 0.0377 | 0.0204 | 0.4681 | 225.8353 | 0.1558 | 2.0706 | 0.0000 | 0.6705 | 0.7733 | 94.3700 | 47.6995 |
| TCN | 0.6474 | 1.6285 | 0.1683 | 0.1013 | 0.0623 | 2.2227 | 341.7137 | 1.5837 | 79.6464 | 0.0000 | 0.6190 | 1.9720 | 79.1497 | 47.7577 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0216 | 0.0225 | 0.2432 | 0.0000 |
| TCN | 0.0098 | 0.0118 | 0.0135 | 0.0645 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 16.7346 | 4.8146 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0343 | 0.1019 | 0.0368 | 0.0377 | 0.0204 | 0.1558 | 2.0706 | 0.6705 | 0.7733 | 94.3700 | 47.6995 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0543 | 0.1019 | 0.0577 | 0.0387 | 0.0259 | 0.1558 | 0.6714 | 0.7389 | 0.8521 | 95.0556 | 57.8889 |
| ModernTCN | downhill_right_transition | 0.0157 | 0.0270 | 0.0202 | 0.0456 | 0.0195 | 0.1397 | 3.9049 | 0.9065 | 1.0694 | 95.7500 | 35.9500 |
| ModernTCN | flat_left_exit | 0.0162 | 0.0445 | 0.0135 | 0.0163 | 0.0131 | 0.1258 | 1.3360 | 0.3106 | 0.3105 | 88.4000 | 34.6000 |
| TCN | all | 0.6474 | 1.6285 | 0.1683 | 0.1013 | 0.0623 | 1.5837 | 79.6464 | 0.6190 | 1.9720 | 79.1497 | 47.7577 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.7834 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.2603 | 0.4929 | 0.1783 | 0.1474 | 0.0281 | 0.6391 | 197.0020 | 0.6808 | 3.8147 | 71.5000 | 86.7222 |
| TCN | downhill_right_transition | 0.6892 | 1.2430 | 0.1659 | 0.0803 | 0.0922 | 1.5837 | 14.0707 | 0.6479 | 1.4590 | 94.4500 | 3.5500 |
| TCN | flat_left_exit | 1.0413 | 1.6285 | 0.1837 | 0.0253 | 0.0392 | 1.3284 | 27.3084 | 0.3533 | 0.3734 | 55.1000 | 47.8000 |
