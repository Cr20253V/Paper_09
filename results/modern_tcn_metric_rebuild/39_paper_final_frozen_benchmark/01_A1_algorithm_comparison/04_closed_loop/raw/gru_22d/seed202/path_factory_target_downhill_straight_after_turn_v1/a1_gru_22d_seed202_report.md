# A1 GRU seed202 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0215 | 0.0442 | 0.0237 | 0.0359 | 0.0041 | 0.3187 | 231.6208 | 0.1454 | 2.1780 | 0.0000 | 0.7723 | 0.8782 | 97.0674 | 66.6222 |
| GRU | 0.0137 | 0.0339 | 0.0087 | 0.0249 | 0.0031 | 0.0861 | 230.1135 | 0.1303 | 0.2605 | 0.0000 | 0.3335 | 0.4567 | 95.3346 | 81.0984 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0250 | 0.0274 | 0.2601 | 0.0000 |
| GRU | 0.0103 | 0.0112 | 0.0145 | 0.0198 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0215 | 0.0442 | 0.0237 | 0.0359 | 0.0041 | 0.1454 | 2.1780 | 0.7723 | 0.8782 | 97.0674 | 66.6222 |
| ModernTCN | all | 0.0213 | 0.0442 | 0.0235 | 0.0733 | 0.0041 | 0.1454 | 10.9709 | 0.7627 | 0.8672 | 97.1053 | 67.0526 |
| GRU | all | 0.0137 | 0.0339 | 0.0087 | 0.0249 | 0.0031 | 0.1303 | 0.2605 | 0.3335 | 0.4567 | 95.3346 | 81.0984 |
| GRU | all | 0.0136 | 0.0339 | 0.0087 | 0.0686 | 0.0031 | 0.1303 | 9.0781 | 0.3294 | 0.4510 | 95.3947 | 81.3684 |
