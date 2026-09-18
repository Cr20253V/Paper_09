# A1 GRU seed11 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed11_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed11\path_factory_logistics_showcase_theta10_v10\gru_22d_seed11_out.mat`
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
| ModernTCN | 0.1115 | 0.4286 | 0.0898 | 0.0236 | 0.0273 | 3.1071 | 218.3175 | 1.4843 | 8.4697 | 0.0000 | 0.5129 | 0.5220 | 97.4972 | 78.3557 |
| GRU | 2.5927 | 6.7981 | 0.3375 | 0.2610 | 0.0728 | 11.0717 | 720.0000 | 1.6297 | 1425 | 0.0000 | 0.5641 | 0.5659 | 95.3532 | 71.1898 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0456 | 0.0503 | 0.2902 | 0.0000 |
| GRU | 0.0091 | 0.0170 | 0.0212 | 0.0654 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.5299 | 0.1345 | 0.0000 |
| GRU | 4.7935 | 4.8791 | 38.9761 | 28.0968 | 0.0000 |

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
| GRU | all | 2.5927 | 6.7981 | 0.3375 | 0.2610 | 0.0728 | 1.6297 | 1425 | 0.5641 | 0.5659 | 95.3532 | 71.1898 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1246 | 0.0000 | 0.0002577 | 24.2722 | 1.6721 | 1.5950 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0150 | 0.0000 | 3.024e-05 | 0.0045 | 0.2806 | 0.2872 | 98.0769 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0409 | 0.0000 | 2.897e-05 | 0.0213 | 0.9377 | 1.0022 | 98.6000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.4195 | 0.7931 | 0.1326 | 0.0343 | 0.0188 | 1.4841 | 2.4120 | 0.6594 | 0.6613 | 100.0000 | 70.7333 |
| GRU | return_recovery_aisle | 0.3130 | 0.6978 | 0.2300 | 0.0455 | 0.1078 | 1.5831 | 133.9333 | 0.8237 | 0.8246 | 80.0493 | 11.0016 |
| GRU | return_slope_aisle | 4.0426 | 6.7981 | 0.5750 | 0.3441 | 0.1241 | 1.6297 | 3683 | 0.5164 | 0.5168 | 91.9324 | 39.7568 |
| GRU | shipping_return_aisle | 5.5795 | 6.1504 | 0.3835 | 0.7502 | 0.0189 | 1.5295 | 5456 | 0.6214 | 0.6277 | 90.1592 | 86.6136 |
