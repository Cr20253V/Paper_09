# A1 TCN seed7 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed7_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed7\path_factory_target_downhill_straight_after_turn_v1\tcn_22d_seed7_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0267 | 0.0440 | 0.0331 | 0.0411 | 0.0048 | 0.5534 | 229.5260 | 0.1481 | 0.7878 | 0.0000 | 0.9240 | 1.0323 | 96.4809 | 63.1032 |
| TCN | 0.0317 | 0.0672 | 0.0478 | 0.0608 | 0.0062 | 0.9697 | 231.0249 | 0.1730 | 1.9511 | 0.0000 | 1.4526 | 1.4637 | 92.8819 | 62.6233 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0228 | 0.0249 | 0.0280 | 0.2688 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0111 | 0.0659 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0267 | 0.0440 | 0.0331 | 0.0411 | 0.0048 | 0.1481 | 0.7878 | 0.9240 | 1.0323 | 96.4809 | 63.1032 |
| ModernTCN | all | 0.0265 | 0.0440 | 0.0329 | 0.0759 | 0.0047 | 0.1481 | 9.5986 | 0.9124 | 1.0193 | 96.5263 | 63.5789 |
| TCN | all | 0.0317 | 0.0672 | 0.0478 | 0.0608 | 0.0062 | 0.1730 | 1.9511 | 1.4526 | 1.4637 | 92.8819 | 62.6233 |
| TCN | all | 0.0315 | 0.0672 | 0.0475 | 0.0880 | 0.0061 | 0.1730 | 10.7469 | 1.4336 | 1.4451 | 92.9737 | 63.1316 |
