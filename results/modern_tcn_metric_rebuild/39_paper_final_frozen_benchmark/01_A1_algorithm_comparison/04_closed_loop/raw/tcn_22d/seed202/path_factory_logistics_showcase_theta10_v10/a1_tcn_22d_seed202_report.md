# A1 TCN seed202 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed202_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed202\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 7.0000 | 4.0000 | 4.0000 | 15.0000 | 1.0000 |
| TCN | 11.0000 | 5.0000 | 8.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0429 | 0.1902 | 0.0601 | 0.0244 | 0.0212 | 2.3989 | 218.4088 | 1.4773 | 2.9011 | 0.0000 | 0.5129 | 0.5319 | 98.7119 | 75.5431 |
| TCN | 4.5211 | 6.9866 | 0.2829 | 0.5478 | 0.0121 | 33.1262 | 663.8632 | 1.5267 | 190.6496 | 0.0000 | 1.4739 | 2.5831 | 38.8579 | 80.8095 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0195 | 0.0211 | 0.0220 | 0.2541 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0108 | 0.0602 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.1834 | 0.0326 | 0.0000 |
| TCN | 32.5969 | 32.1648 | 56.7358 | 55.1013 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0429 | 0.1902 | 0.0601 | 0.0244 | 0.0212 | 1.4773 | 2.9011 | 0.5129 | 0.5319 | 98.7119 | 75.5431 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0243 | 0.0000 | 8.037e-05 | 0.2560 | 0.4696 | 0.5355 | 98.4103 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0200 | 0.0000 | 3.41e-05 | 7.7016 | 0.4909 | 0.4322 | 93.1000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0704 | 0.1792 | 0.1255 | 0.0195 | 0.0135 | 1.4773 | 1.7740 | 0.5991 | 0.5991 | 100.0000 | 26.5823 |
| ModernTCN | return_recovery_aisle | 0.1209 | 0.1902 | 0.1127 | 0.0334 | 0.0873 | 0.5100 | 34.2123 | 0.8970 | 0.8970 | 100.0000 | 3.3662 |
| ModernTCN | return_slope_aisle | 0.0251 | 0.0820 | 0.0107 | 0.0286 | 0.0113 | 0.4292 | 0.1368 | 0.5695 | 0.5827 | 99.1757 | 80.2838 |
| ModernTCN | shipping_return_aisle | 0.0019 | 0.0031 | 0.000927 | 0.0109 | 0.0027 | 0.0041 | 7.5000 | 0.2267 | 0.1630 | 95.5137 | 100.0000 |
| TCN | all | 4.5211 | 6.9866 | 0.2829 | 0.5478 | 0.0121 | 1.5267 | 190.6496 | 1.4739 | 2.5831 | 38.8579 | 80.8095 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.4007 | 0.0537 | 38.1667 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 0.2505 | 3.4581 | 93.5769 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 0.2996 | 1.7622 | 45.6000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 4.4867 | 6.9866 | 0.3874 | 0.2779 | 0.0217 | 1.3560 | 696.7857 | 1.7006 | 1.7172 | 2.1388 | 6.1109 |
| TCN | return_recovery_aisle | 5.5747 | 6.2164 | 0.6316 | 0.6207 | 0.0059 | 1.3250 | 27.8074 | 0.5197 | 0.8810 | 0.0000 | 91.3793 |
| TCN | return_slope_aisle | 6.5039 | 6.5412 | 0.3235 | 0.8513 | 0.0124 | 1.5267 | 195.9557 | 3.2212 | 3.3082 | 2.5000 | 95.9324 |
| TCN | shipping_return_aisle | 6.4955 | 6.4965 | 0.1049 | 0.8600 | 0.0129 | 1.3277 | 6.044e-25 | 0.8407 | 0.8319 | 78.5818 | 100.0000 |
