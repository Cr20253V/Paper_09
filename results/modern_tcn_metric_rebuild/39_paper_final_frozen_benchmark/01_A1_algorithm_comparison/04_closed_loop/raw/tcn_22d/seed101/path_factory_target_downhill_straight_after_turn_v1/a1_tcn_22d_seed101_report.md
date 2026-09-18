# A1 TCN seed101 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed101_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed101\path_factory_target_downhill_straight_after_turn_v1\tcn_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0126 | 0.0299 | 0.0106 | 0.0250 | 0.0032 | 0.1356 | 231.1770 | 0.1291 | 0.9629 | 0.0000 | 0.4316 | 0.5506 | 96.8542 | 71.7675 |
| TCN | 0.0304 | 0.0660 | 0.0444 | 0.0567 | 0.0057 | 0.8901 | 231.4362 | 0.1682 | 1.0759 | 0.0000 | 1.3588 | 1.3656 | 91.1224 | 75.6332 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0251 | 0.0271 | 0.2632 | 0.0000 |
| TCN | 0.0093 | 0.0098 | 0.0102 | 0.0620 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0126 | 0.0299 | 0.0106 | 0.0250 | 0.0032 | 0.1291 | 0.9629 | 0.4316 | 0.5506 | 96.8542 | 71.7675 |
| ModernTCN | all | 0.0125 | 0.0299 | 0.0105 | 0.0686 | 0.0031 | 0.1291 | 9.7715 | 0.4263 | 0.5438 | 96.8947 | 72.1316 |
| TCN | all | 0.0304 | 0.0660 | 0.0444 | 0.0567 | 0.0057 | 0.1682 | 1.0759 | 1.3588 | 1.3656 | 91.1224 | 75.6332 |
| TCN | all | 0.0302 | 0.0660 | 0.0441 | 0.0852 | 0.0057 | 0.1682 | 9.8830 | 1.3410 | 1.3483 | 91.2368 | 75.9737 |
