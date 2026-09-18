# A1 GRU seed1 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed1_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed1\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 6.0000 | 16.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 6.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0104 | 0.0243 | 0.0044 | 0.0280 | 0.0030 | 0.1878 | 230.7962 | 0.1276 | 2.2720 | 0.0000 | 0.4413 | 0.5559 | 95.1213 | 70.7811 |
| GRU | 0.0217 | 0.0442 | 0.0337 | 0.0423 | 0.0047 | 0.6606 | 228.5067 | 0.1458 | 0.2441 | 0.0000 | 1.0152 | 1.0712 | 95.5212 | 49.3735 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0250 | 0.0274 | 0.2651 | 0.0000 |
| GRU | 0.0088 | 0.0093 | 0.0098 | 0.0203 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0104 | 0.0243 | 0.0044 | 0.0280 | 0.0030 | 0.1276 | 2.2720 | 0.4413 | 0.5559 | 95.1213 | 70.7811 |
| ModernTCN | all | 0.0103 | 0.0243 | 0.0044 | 0.0697 | 0.0030 | 0.1276 | 11.0637 | 0.4360 | 0.5491 | 95.1842 | 71.1579 |
| GRU | all | 0.0217 | 0.0442 | 0.0337 | 0.0423 | 0.0047 | 0.1458 | 0.2441 | 1.0152 | 1.0712 | 95.5212 | 49.3735 |
| GRU | all | 0.0216 | 0.0442 | 0.0335 | 0.0765 | 0.0047 | 0.1458 | 9.0619 | 1.0020 | 1.0574 | 95.5789 | 50.0263 |
