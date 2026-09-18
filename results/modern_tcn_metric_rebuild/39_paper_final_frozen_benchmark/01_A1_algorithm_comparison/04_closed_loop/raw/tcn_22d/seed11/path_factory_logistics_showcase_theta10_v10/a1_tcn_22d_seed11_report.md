# A1 TCN seed11 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed11_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed11\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed11_out.mat`
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
| ModernTCN | 0.1115 | 0.4286 | 0.0898 | 0.0236 | 0.0273 | 3.1071 | 218.3175 | 1.4843 | 8.4697 | 0.0000 | 0.5129 | 0.5220 | 97.4972 | 78.3557 |
| TCN | 4.5003 | 23.4594 | 0.9638 | 5.5178 | 0.7061 | 31.3243 | 720.0000 | 1.5418 | 339.7493 | 0.0000 | 2.8347 | 3.4772 | 46.1419 | 84.0460 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0456 | 0.0503 | 0.2902 | 0.0000 |
| TCN | 0.0100 | 0.0116 | 0.0150 | 0.0991 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.5299 | 0.1345 | 0.0000 |
| TCN | 45.9340 | 43.6962 | 58.6842 | 58.2725 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.1115 | 0.4286 | 0.0898 | 0.0236 | 0.0273 | 1.4843 | 8.4697 | 0.5129 | 0.5220 | 97.4972 | 78.3557 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0262 | 0.0000 | 7.449e-05 | 0.1198 | 0.5260 | 0.5420 | 98.6538 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0231 | 0.0000 | 1.731e-05 | 3.5329 | 0.5155 | 0.4342 | 97.7000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.2393 | 0.4286 | 0.1925 | 0.0175 | 0.0165 | 1.4843 | 5.9678 | 0.5991 | 0.5991 | 92.3396 | 45.1986 |
| ModernTCN | return_recovery_aisle | 0.1770 | 0.3376 | 0.1445 | 0.0321 | 0.1115 | 0.9863 | 127.6959 | 0.8935 | 0.8970 | 100.0000 | 0.0000 |
| ModernTCN | return_slope_aisle | 0.0241 | 0.1368 | 0.0194 | 0.0250 | 0.0162 | 0.4603 | 2.1906 | 0.5092 | 0.5431 | 98.6351 | 78.6351 |
| ModernTCN | shipping_return_aisle | 0.0026 | 0.0040 | 0.0009193 | 0.0125 | 0.0028 | 0.0054 | 2.9044 | 0.2169 | 0.1623 | 97.5398 | 100.0000 |
| TCN | all | 4.5003 | 23.4594 | 0.9638 | 5.5178 | 0.7061 | 1.5418 | 339.7493 | 2.8347 | 3.4772 | 46.1419 | 84.0460 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 1.6831 | 0.0537 | 20.5833 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1320 | 0.0000 | 0.0004814 | 172.7662 | 1.6449 | 3.3492 | 93.5769 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 2.0188 | 1.7622 | 45.6000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.6572 | 23.4594 | 1.5626 | 12.6944 | 1.6328 | 1.4400 | 379.1112 | 7.9941 | 6.7056 | 8.9044 | 23.1122 |
| TCN | return_recovery_aisle | 3.7676 | 4.0242 | 1.7024 | 1.2489 | 0.0966 | 1.5418 | 4313 | 0.8499 | 0.8208 | 74.0558 | 67.8982 |
| TCN | return_slope_aisle | 3.9467 | 4.0160 | 1.0368 | 0.8600 | 0.0242 | 1.3345 | 0.1410 | 1.7588 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 3.8861 | 3.8889 | 0.2911 | 0.8600 | 0.0242 | 1.3345 | 8.594e-26 | 1.4432 | 0.8319 | 78.5818 | 100.0000 |
