# A1 TCN seed520 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0279 | 0.1083 | 0.0387 | 0.0197 | 0.0113 | 1.7368 | 217.9462 | 1.4746 | 0.9763 | 0.0000 | 0.3840 | 0.3948 | 96.2989 | 77.9358 |
| TCN | 5.5969 | 23.6435 | 1.0787 | 5.9570 | 0.7798 | 31.7870 | 876.0433 | 1.6445 | 226.0624 | 0.0000 | 2.7879 | 3.7490 | 51.7589 | 79.4155 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0215 | 0.0233 | 0.2467 | 0.0000 |
| TCN | 0.0092 | 0.0105 | 0.0122 | 0.0787 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.2568 | 0.0204 | 0.0000 |
| TCN | 56.2671 | 56.1896 | 58.6679 | 58.2481 | 0.0000 |

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
| TCN | all | 5.5969 | 23.6435 | 1.0787 | 5.9570 | 0.7798 | 1.6445 | 226.0624 | 2.7879 | 3.7490 | 51.7589 | 79.4155 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.9891 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 0.3848 | 3.4581 | 99.0128 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 0.8565 | 1.7622 | 73.3000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.9022 | 23.6435 | 1.6050 | 13.5396 | 1.6848 | 1.4400 | 340.3298 | 8.3851 | 6.9924 | 12.9419 | 7.3985 |
| TCN | return_recovery_aisle | 4.9157 | 6.8499 | 1.7894 | 4.4344 | 1.2515 | 1.6445 | 3276 | 4.4698 | 4.5193 | 36.2069 | 33.7438 |
| TCN | return_slope_aisle | 6.5546 | 6.6305 | 1.2870 | 0.8600 | 0.0221 | 1.3333 | 9.217e-10 | 2.4334 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 6.4771 | 6.4825 | 0.6517 | 0.8600 | 0.0221 | 1.3332 | 9.359e-30 | 1.0689 | 0.8319 | 78.5818 | 100.0000 |
