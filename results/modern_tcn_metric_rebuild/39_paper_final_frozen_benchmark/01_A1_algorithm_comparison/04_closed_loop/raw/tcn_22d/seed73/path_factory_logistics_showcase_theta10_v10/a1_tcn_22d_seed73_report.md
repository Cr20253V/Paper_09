# A1 TCN seed73 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed73_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed73\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed73_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0570 | 0.2438 | 0.0679 | 0.0198 | 0.0224 | 2.3218 | 218.1131 | 1.4781 | 5.4232 | 0.0000 | 0.4264 | 0.4225 | 98.8057 | 80.9481 |
| TCN | 3.5117 | 22.5365 | 0.7357 | 4.6232 | 0.6186 | 20.6478 | 821.7464 | 1.5493 | 585.5049 | 0.0000 | 2.1283 | 2.9799 | 44.3036 | 70.5417 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0445 | 0.0520 | 0.0569 | 0.5209 | 0.0000 |
| TCN | 0.0100 | 0.0115 | 0.0144 | 0.0575 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.2364 | 0.0611 | 0.0000 |
| TCN | 39.6120 | 39.6038 | 21.6402 | 16.5410 | 0.0000 |

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
| TCN | all | 3.5117 | 22.5365 | 0.7357 | 4.6232 | 0.6186 | 1.5493 | 585.5049 | 2.1283 | 2.9799 | 44.3036 | 70.5417 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.6342 | 0.0537 | 20.5833 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1215 | 0.0000 | 0.0005244 | 151.1838 | 0.2647 | 3.0681 | 92.4231 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0755 | 0.0000 | 0.0002107 | 23.7459 | 0.5149 | 1.6083 | 45.6000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 7.8009 | 22.5365 | 1.4342 | 10.6469 | 1.4297 | 1.5298 | 1987 | 6.2029 | 5.1547 | 9.4500 | 21.1698 |
| TCN | return_recovery_aisle | 1.8454 | 3.4265 | 0.7019 | 0.0812 | 0.0318 | 1.5272 | 895.7090 | 0.5633 | 0.8909 | 3.3662 | 16.0920 |
| TCN | return_slope_aisle | 1.6180 | 3.7549 | 0.5041 | 0.7185 | 0.0531 | 1.5493 | 401.2822 | 2.5034 | 2.9254 | 19.5405 | 64.9595 |
| TCN | shipping_return_aisle | 0.3605 | 0.3638 | 0.9967 | 0.8600 | 0.0234 | 0.3111 | 7.867e-09 | 0.8970 | 0.8319 | 78.5818 | 100.0000 |
