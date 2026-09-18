# A1 GRU seed340 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_factory_logistics_showcase_theta10_v10\gru_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0436 | 0.1837 | 0.0574 | 0.0226 | 0.0159 | 2.3866 | 218.2441 | 1.4894 | 1.0965 | 0.0000 | 0.4368 | 0.4451 | 93.4822 | 73.0608 |
| GRU | 1.1092 | 4.0485 | 0.5101 | 0.5466 | 0.0251 | 36.6086 | 815.0365 | 1.5795 | 470.0864 | 0.0000 | 1.1518 | 1.1409 | 69.3963 | 94.3138 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0197 | 0.0215 | 0.0246 | 0.2401 | 0.0000 |
| GRU | 0.0107 | 0.0118 | 0.0149 | 0.0968 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0938 | 0.0163 | 0.0000 |
| GRU | 38.4095 | 38.3973 | 56.2630 | 44.1691 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0436 | 0.1837 | 0.0574 | 0.0226 | 0.0159 | 1.4894 | 1.0965 | 0.4368 | 0.4451 | 93.4822 | 73.0608 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0199 | 0.0000 | 6.466e-05 | 0.4231 | 0.3227 | 0.3727 | 98.9359 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0179 | 0.0000 | 1.567e-05 | 4.1404 | 0.3921 | 0.3598 | 93.7000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0843 | 0.1837 | 0.1252 | 0.0198 | 0.0117 | 1.4894 | 0.8592 | 0.6872 | 0.5991 | 71.3444 | 20.5587 |
| ModernTCN | return_recovery_aisle | 0.0899 | 0.1627 | 0.0816 | 0.0336 | 0.0643 | 0.3891 | 4.9155 | 0.8970 | 0.8970 | 100.0000 | 3.6125 |
| ModernTCN | return_slope_aisle | 0.0239 | 0.0817 | 0.0116 | 0.0275 | 0.0087 | 0.0753 | 0.6264 | 0.4391 | 0.4772 | 99.0405 | 75.7432 |
| ModernTCN | shipping_return_aisle | 0.0011 | 0.0026 | 0.0006523 | 0.0101 | 0.0028 | 0.0056 | 3.3044 | 0.1824 | 0.1596 | 95.0072 | 100.0000 |
| GRU | all | 1.1092 | 4.0485 | 0.5101 | 0.5466 | 0.0251 | 1.5795 | 470.0864 | 1.1518 | 1.1409 | 69.3963 | 94.3138 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1440 | 0.0000 | 0.0002577 | 24.3253 | 2.5470 | 2.4375 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0384 | 0.0000 | 5.735e-05 | 0.0044 | 0.9983 | 0.9926 | 97.8077 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0688 | 0.0000 | 5.522e-05 | 0.0201 | 1.7637 | 1.8147 | 99.9000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 2.1089 | 4.0485 | 0.4575 | 0.2971 | 0.0294 | 1.5788 | 1979 | 0.6574 | 0.6558 | 98.6905 | 84.1554 |
| GRU | return_recovery_aisle | 1.6028 | 3.5068 | 1.1682 | 0.5745 | 0.0751 | 1.5795 | 2024 | 1.1919 | 1.0825 | 54.7619 | 45.0739 |
| GRU | return_slope_aisle | 0.8778 | 0.9315 | 0.7126 | 0.8600 | 0.0229 | 1.3337 | 2.086e-09 | 1.1405 | 1.1405 | 13.1216 | 100.0000 |
| GRU | shipping_return_aisle | 0.8395 | 0.8400 | 0.0581 | 0.8600 | 0.0229 | 1.3337 | 1.872e-29 | 1.9846 | 1.9846 | 78.5818 | 100.0000 |
