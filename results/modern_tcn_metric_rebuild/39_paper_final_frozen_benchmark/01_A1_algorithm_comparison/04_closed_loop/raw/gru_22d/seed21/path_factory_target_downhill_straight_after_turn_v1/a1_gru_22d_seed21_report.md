# A1 GRU seed21 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed21_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed21\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed21_out.mat`
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
| ModernTCN | 0.0137 | 0.0339 | 0.0060 | 0.0261 | 0.0031 | 0.0864 | 231.6682 | 0.1288 | 0.7908 | 0.0000 | 0.4751 | 0.5762 | 97.4407 | 71.4476 |
| GRU | 0.0209 | 0.0488 | 0.0281 | 0.0386 | 0.0044 | 0.5234 | 229.9769 | 0.1496 | 0.2774 | 0.0000 | 0.8911 | 0.9300 | 95.6545 | 83.2311 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0228 | 0.0251 | 0.0274 | 0.2658 | 0.0000 |
| GRU | 0.0107 | 0.0215 | 0.0248 | 0.0341 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0137 | 0.0339 | 0.0060 | 0.0261 | 0.0031 | 0.1288 | 0.7908 | 0.4751 | 0.5762 | 97.4407 | 71.4476 |
| ModernTCN | all | 0.0136 | 0.0339 | 0.0059 | 0.0690 | 0.0030 | 0.1288 | 9.6016 | 0.4693 | 0.5691 | 97.4737 | 71.8158 |
| GRU | all | 0.0209 | 0.0488 | 0.0281 | 0.0386 | 0.0044 | 0.1496 | 0.2774 | 0.8911 | 0.9300 | 95.6545 | 83.2311 |
| GRU | all | 0.0208 | 0.0488 | 0.0279 | 0.0746 | 0.0043 | 0.1496 | 9.0948 | 0.8794 | 0.9178 | 95.7105 | 83.4474 |
