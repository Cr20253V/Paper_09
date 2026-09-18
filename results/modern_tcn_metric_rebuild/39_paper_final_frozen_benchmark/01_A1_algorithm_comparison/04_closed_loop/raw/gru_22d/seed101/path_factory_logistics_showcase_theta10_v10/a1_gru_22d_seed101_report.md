# A1 GRU seed101 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed101_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed101\path_factory_logistics_showcase_theta10_v10\gru_22d_seed101_out.mat`
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
| ModernTCN | 0.0597 | 0.2761 | 0.0683 | 0.0230 | 0.0167 | 2.5473 | 218.1761 | 1.4740 | 1.6339 | 0.0000 | 0.4319 | 0.4399 | 99.2011 | 77.0758 |
| GRU | 2.1735 | 5.4851 | 0.4063 | 0.3355 | 0.0730 | 15.1302 | 900.0000 | 1.6446 | 1529 | 0.0000 | 0.6200 | 0.6272 | 91.4279 | 80.6791 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0205 | 0.0475 | 0.0520 | 0.5538 | 0.0000 |
| GRU | 0.0106 | 0.0122 | 0.0155 | 0.0883 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0571 | 0.0122 | 0.0000 |
| GRU | 11.7230 | 11.5885 | 40.8633 | 32.2912 | 0.0000 |

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
| GRU | all | 2.1735 | 5.4851 | 0.4063 | 0.3355 | 0.0730 | 1.6446 | 1529 | 0.6200 | 0.6272 | 91.4279 | 80.6791 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1357 | 0.0000 | 0.0002577 | 24.3155 | 2.1983 | 2.1057 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0155 | 0.0000 | 4.107e-05 | 0.0045 | 0.2004 | 0.2222 | 98.3974 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0444 | 0.0000 | 4.179e-05 | 0.0206 | 0.9651 | 1.0048 | 96.8000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.3729 | 0.7006 | 0.1453 | 0.0302 | 0.0194 | 1.5821 | 1.9069 | 0.6399 | 0.6480 | 98.2759 | 74.0943 |
| GRU | return_recovery_aisle | 0.6660 | 1.1353 | 0.3497 | 0.1787 | 0.1550 | 1.6446 | 3553 | 1.0063 | 0.9908 | 100.0000 | 13.8752 |
| GRU | return_slope_aisle | 3.5292 | 5.4851 | 0.7161 | 0.4769 | 0.1158 | 1.5356 | 4482 | 0.4188 | 0.4267 | 78.7703 | 66.1622 |
| GRU | shipping_return_aisle | 4.0378 | 4.0387 | 0.0770 | 0.8600 | 0.0239 | 1.3343 | 8.187e-18 | 2.0153 | 2.0153 | 78.5818 | 100.0000 |
