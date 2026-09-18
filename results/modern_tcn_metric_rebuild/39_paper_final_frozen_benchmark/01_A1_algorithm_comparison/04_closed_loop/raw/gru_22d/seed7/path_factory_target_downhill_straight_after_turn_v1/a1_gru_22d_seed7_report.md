# A1 GRU seed7 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed7_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed7\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed7_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 4.0000 | 6.0000 | 16.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 6.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0267 | 0.0440 | 0.0331 | 0.0411 | 0.0048 | 0.5534 | 229.5260 | 0.1481 | 0.7878 | 0.0000 | 0.9240 | 1.0323 | 96.4809 | 63.1032 |
| GRU | 0.0152 | 0.0376 | 0.0118 | 0.0293 | 0.0031 | 0.1223 | 229.7038 | 0.1310 | 0.2893 | 0.0000 | 0.4792 | 0.5667 | 95.4412 | 77.5260 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0228 | 0.0249 | 0.0280 | 0.2688 | 0.0000 |
| GRU | 0.0087 | 0.0094 | 0.0101 | 0.0192 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0267 | 0.0440 | 0.0331 | 0.0411 | 0.0048 | 0.1481 | 0.7878 | 0.9240 | 1.0323 | 96.4809 | 63.1032 |
| ModernTCN | all | 0.0265 | 0.0440 | 0.0329 | 0.0759 | 0.0047 | 0.1481 | 9.5986 | 0.9124 | 1.0193 | 96.5263 | 63.5789 |
| GRU | all | 0.0152 | 0.0376 | 0.0118 | 0.0293 | 0.0031 | 0.1310 | 0.2893 | 0.4792 | 0.5667 | 95.4412 | 77.5260 |
| GRU | all | 0.0151 | 0.0376 | 0.0118 | 0.0703 | 0.0031 | 0.1310 | 9.1066 | 0.4726 | 0.5591 | 95.5000 | 77.8421 |
