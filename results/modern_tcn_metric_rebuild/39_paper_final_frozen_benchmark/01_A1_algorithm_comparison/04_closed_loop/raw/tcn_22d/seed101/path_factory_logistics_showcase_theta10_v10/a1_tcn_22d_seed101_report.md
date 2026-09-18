# A1 TCN seed101 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed101_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed101\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed101_out.mat`
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
| ModernTCN | 0.0597 | 0.2761 | 0.0683 | 0.0230 | 0.0167 | 2.5473 | 218.1761 | 1.4740 | 1.6339 | 0.0000 | 0.4319 | 0.4399 | 99.2011 | 77.0758 |
| TCN | 5.2747 | 23.7377 | 0.9279 | 5.9219 | 0.7587 | 32.6494 | 861.0571 | 1.5366 | 185.8986 | 0.0000 | 2.9026 | 3.6497 | 52.8961 | 86.9482 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0205 | 0.0475 | 0.0520 | 0.5538 | 0.0000 |
| TCN | 0.0101 | 0.0116 | 0.0150 | 0.0820 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0571 | 0.0122 | 0.0000 |
| TCN | 54.1475 | 53.2303 | 58.6679 | 58.2970 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0597 | 0.2761 | 0.0683 | 0.0230 | 0.0167 | 1.4740 | 1.6339 | 0.4319 | 0.4399 | 99.2011 | 77.0758 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0236 | 0.0000 | 7.95e-05 | 0.6546 | 0.3901 | 0.4083 | 98.8333 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0259 | 0.0000 | 1.999e-05 | 1.1925 | 0.5197 | 0.4505 | 99.5000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.1256 | 0.2761 | 0.1503 | 0.0198 | 0.0128 | 1.4740 | 0.8649 | 0.5991 | 0.5991 | 99.5417 | 21.4753 |
| ModernTCN | return_recovery_aisle | 0.1091 | 0.2001 | 0.0944 | 0.0338 | 0.0694 | 0.9994 | 20.6949 | 0.8852 | 0.8970 | 100.0000 | 10.0985 |
| ModernTCN | return_slope_aisle | 0.0101 | 0.0356 | 0.0037 | 0.0241 | 0.0053 | 0.0971 | 0.4127 | 0.3849 | 0.4076 | 99.3108 | 87.4189 |
| ModernTCN | shipping_return_aisle | 0.0028 | 0.0044 | 0.0008703 | 0.0135 | 0.0032 | 0.0052 | 0.8975 | 0.2145 | 0.1723 | 97.9740 | 100.0000 |
| TCN | all | 5.2747 | 23.7377 | 0.9279 | 5.9219 | 0.7587 | 1.5366 | 185.8986 | 2.9026 | 3.6497 | 52.8961 | 86.9482 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 1.6359 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 1.3669 | 3.4581 | 99.6154 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 1.7983 | 1.7622 | 75.9000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.9455 | 23.7377 | 1.6046 | 13.5394 | 1.6819 | 1.4400 | 381.1360 | 8.3176 | 6.9358 | 14.9498 | 41.5539 |
| TCN | return_recovery_aisle | 4.9979 | 6.4721 | 1.6192 | 3.3596 | 0.9730 | 1.5366 | 2312 | 2.7206 | 2.7315 | 45.5665 | 56.9787 |
| TCN | return_slope_aisle | 5.7094 | 5.7736 | 0.9079 | 0.8600 | 0.0243 | 1.3346 | 0.0080 | 1.8127 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 5.6582 | 5.6599 | 0.1544 | 0.8600 | 0.0243 | 1.3346 | 1.245e-25 | 1.4067 | 0.8319 | 78.5818 | 100.0000 |
