# A1 GRU seed73 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed73_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed73\path_factory_logistics_showcase_theta10_v10\gru_22d_seed73_out.mat`
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
| ModernTCN | 0.0570 | 0.2438 | 0.0679 | 0.0198 | 0.0224 | 2.3218 | 218.1131 | 1.4781 | 5.4232 | 0.0000 | 0.4264 | 0.4225 | 98.8057 | 80.9481 |
| GRU | 1.1262 | 3.2342 | 1.2399 | 0.5594 | 0.0256 | 35.1691 | 720.0000 | 1.6560 | 621.4346 | 0.0000 | 1.6359 | 1.6251 | 71.4792 | 54.9138 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0445 | 0.0520 | 0.0569 | 0.5209 | 0.0000 |
| GRU | 0.0106 | 0.0121 | 0.0154 | 0.1206 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.2364 | 0.0611 | 0.0000 |
| GRU | 38.2261 | 16.4717 | 18.0940 | 12.6972 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0570 | 0.2438 | 0.0679 | 0.0198 | 0.0224 | 1.4781 | 5.4232 | 0.4264 | 0.4225 | 98.8057 | 80.9481 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0216 | 0.0000 | 7.135e-05 | 0.1194 | 0.4041 | 0.4191 | 98.8590 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0193 | 0.0000 | 1.779e-05 | 3.8434 | 0.4412 | 0.3743 | 94.8000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.1027 | 0.2438 | 0.1419 | 0.0188 | 0.0117 | 1.4781 | 2.8785 | 0.5959 | 0.5991 | 100.0000 | 49.8036 |
| ModernTCN | return_recovery_aisle | 0.1512 | 0.2394 | 0.1258 | 0.0332 | 0.0922 | 1.0151 | 55.8013 | 0.8941 | 0.8970 | 100.0000 | 11.6585 |
| ModernTCN | return_slope_aisle | 0.0220 | 0.0809 | 0.0152 | 0.0174 | 0.0136 | 0.1828 | 5.8059 | 0.3704 | 0.3544 | 98.7027 | 82.4595 |
| ModernTCN | shipping_return_aisle | 0.0027 | 0.0047 | 0.00083 | 0.0097 | 0.0031 | 0.0051 | 2.8017 | 0.1758 | 0.1438 | 95.9479 | 100.0000 |
| GRU | all | 1.1262 | 3.2342 | 1.2399 | 0.5594 | 0.0256 | 1.6560 | 621.4346 | 1.6359 | 1.6251 | 71.4792 | 54.9138 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1225 | 0.0000 | 0.0002577 | 24.2870 | 1.5901 | 1.5159 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0372 | 0.0000 | 2.987e-05 | 0.0047 | 1.0203 | 1.0087 | 98.0513 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0581 | 0.0000 | 3.001e-05 | 0.0233 | 1.5264 | 1.6236 | 98.7000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 1.9432 | 3.2342 | 0.4012 | 0.3159 | 0.0194 | 1.5837 | 2518 | 0.4552 | 0.4473 | 99.5853 | 74.2252 |
| GRU | return_recovery_aisle | 1.2978 | 2.5840 | 1.1520 | 0.7612 | 0.0883 | 1.6560 | 3049 | 0.8412 | 0.7212 | 92.7750 | 9.9343 |
| GRU | return_slope_aisle | 1.1449 | 1.2156 | 1.8913 | 0.8600 | 0.0236 | 0.2975 | 8.558e-05 | 3.3082 | 3.3082 | 13.1216 | 0.0000 |
| GRU | shipping_return_aisle | 1.2208 | 1.2230 | 2.5350 | 0.8600 | 0.0236 | 0.2017 | 0.0003356 | 0.8319 | 0.8319 | 78.5818 | 0.0000 |
