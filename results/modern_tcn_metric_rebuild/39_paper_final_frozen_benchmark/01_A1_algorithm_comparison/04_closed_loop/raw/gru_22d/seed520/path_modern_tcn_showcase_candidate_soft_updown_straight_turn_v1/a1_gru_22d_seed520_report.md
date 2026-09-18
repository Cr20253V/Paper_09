# A1 GRU seed520 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed520_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed520\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| GRU | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0040 | 0.0112 | 0.0081 | 0.0105 | 0.0066 | 0.2765 | 243.3561 | 0.2905 | 0.3034 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 63.8624 |
| GRU | 0.3250 | 1.1130 | 0.1567 | 0.1010 | 0.0697 | 2.1912 | 720.0000 | 1.6560 | 1355 | 0.0000 | 1.9713 | 1.9715 | 99.5496 | 45.4152 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0204 | 0.0220 | 0.0235 | 0.2392 | 0.0000 |
| GRU | 0.0102 | 0.0111 | 0.0136 | 0.0839 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 1.9816 | 1.8916 | 16.9339 | 4.9541 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0040 | 0.0112 | 0.0081 | 0.0105 | 0.0066 | 0.2905 | 0.3034 | 0.0167 | 0.0167 | 99.5496 | 63.8624 |
| ModernTCN | all | 0.0040 | 0.0112 | 0.0081 | 0.0528 | 0.0066 | 0.2905 | 5.2288 | 0.0376 | 0.0376 | 99.0179 | 64.1964 |
| GRU | all | 0.3250 | 1.1130 | 0.1567 | 0.1010 | 0.0697 | 1.6560 | 1355 | 1.9713 | 1.9715 | 99.5496 | 45.4152 |
| GRU | all | 0.3232 | 1.1129 | 0.1560 | 0.1126 | 0.0694 | 1.6560 | 1348 | 1.9751 | 1.9753 | 99.0179 | 45.9107 |
