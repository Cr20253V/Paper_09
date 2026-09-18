# A1 GRU seed520 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed520_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed520\path_factory_logistics_showcase_theta10_v10\gru_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| GRU | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0279 | 0.1083 | 0.0387 | 0.0197 | 0.0113 | 1.7368 | 217.9462 | 1.4746 | 0.9763 | 0.0000 | 0.3840 | 0.3948 | 96.2989 | 77.9358 |
| GRU | 3.0176 | 7.7527 | 0.3711 | 0.2838 | 0.0655 | 13.1232 | 720.0000 | 1.6503 | 800.4757 | 0.0000 | 0.7360 | 0.7272 | 93.3233 | 66.3637 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0215 | 0.0233 | 0.2467 | 0.0000 |
| GRU | 0.0107 | 0.0119 | 0.0153 | 0.0807 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.2568 | 0.0204 | 0.0000 |
| GRU | 4.5734 | 4.5327 | 43.7126 | 32.3564 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0279 | 0.1083 | 0.0387 | 0.0197 | 0.0113 | 1.4746 | 0.9763 | 0.3840 | 0.3948 | 96.2989 | 77.9358 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0189 | 0.0000 | 6.996e-05 | 0.1540 | 0.3151 | 0.3416 | 98.3974 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0213 | 0.0000 | 2.208e-05 | 6.1538 | 0.4354 | 0.4252 | 97.9000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0466 | 0.0770 | 0.0859 | 0.0215 | 0.0120 | 1.4746 | 2.0712 | 0.5991 | 0.5991 | 96.6608 | 37.2763 |
| ModernTCN | return_recovery_aisle | 0.0551 | 0.1083 | 0.0403 | 0.0347 | 0.0395 | 0.5447 | 0.0835 | 0.8970 | 0.8970 | 59.3596 | 8.1281 |
| ModernTCN | return_slope_aisle | 0.0272 | 0.0910 | 0.0115 | 0.0175 | 0.0088 | 0.5284 | 0.1266 | 0.3159 | 0.3304 | 98.9730 | 80.8108 |
| ModernTCN | shipping_return_aisle | 0.0014 | 0.0024 | 0.0009886 | 0.0122 | 0.0032 | 0.0060 | 4.1450 | 0.2079 | 0.1801 | 97.2504 | 100.0000 |
| GRU | all | 3.0176 | 7.7527 | 0.3711 | 0.2838 | 0.0655 | 1.6503 | 800.4757 | 0.7360 | 0.7272 | 93.3233 | 66.3637 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1487 | 0.0000 | 0.0002577 | 24.3569 | 2.7423 | 2.6251 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0254 | 0.0000 | 6.526e-05 | 0.0039 | 0.3986 | 0.4022 | 97.5897 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0634 | 0.0000 | 6.075e-05 | 0.0194 | 1.3546 | 1.3555 | 98.9000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.6643 | 1.2008 | 0.1543 | 0.0398 | 0.0175 | 1.4853 | 19.4283 | 0.7081 | 0.7146 | 100.0000 | 61.3269 |
| GRU | return_recovery_aisle | 0.5390 | 0.7976 | 0.2807 | 0.0915 | 0.1017 | 1.6019 | 225.7753 | 0.7619 | 0.7243 | 70.1149 | 13.7931 |
| GRU | return_slope_aisle | 4.4372 | 7.7527 | 0.6432 | 0.3904 | 0.1107 | 1.6503 | 2295 | 0.5269 | 0.5222 | 98.4459 | 27.7568 |
| GRU | shipping_return_aisle | 7.3801 | 7.6424 | 0.2856 | 0.7647 | 0.0190 | 1.3357 | 1658 | 1.6115 | 1.5729 | 30.6078 | 93.9219 |
