# A1 GRU seed202 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_factory_logistics_showcase_theta10_v10\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0429 | 0.1902 | 0.0601 | 0.0244 | 0.0212 | 2.3989 | 218.4088 | 1.4773 | 2.9011 | 0.0000 | 0.5129 | 0.5319 | 98.7119 | 75.5431 |
| GRU | 0.0060 | 0.0300 | 0.0149 | 0.0154 | 0.0050 | 0.3218 | 217.9628 | 0.6265 | 0.0884 | 0.0000 | 0.3451 | 0.3345 | 98.0068 | 92.1045 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0195 | 0.0211 | 0.0220 | 0.2541 | 0.0000 |
| GRU | 0.0104 | 0.0115 | 0.0145 | 0.0201 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.1834 | 0.0326 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0122 | 0.0000 | 0.0000 |

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
| GRU | all | 0.0060 | 0.0300 | 0.0149 | 0.0154 | 0.0050 | 0.6265 | 0.0884 | 0.3451 | 0.3345 | 98.0068 | 92.1045 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1079 | 0.0000 | 0.0002577 | 24.2468 | 0.4811 | 0.4435 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0106 | 0.0000 | 1.131e-05 | 0.0055 | 0.2334 | 0.2542 | 97.3077 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0115 | 0.0000 | 4.296e-06 | 0.0364 | 0.3147 | 0.2135 | 96.6000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.0135 | 0.0300 | 0.0345 | 0.0218 | 0.0100 | 0.6265 | 0.3532 | 0.5952 | 0.5081 | 100.0000 | 85.3121 |
| GRU | return_recovery_aisle | 0.0049 | 0.0120 | 0.0038 | 0.0165 | 0.0076 | 0.0382 | 0.0259 | 0.4354 | 0.3917 | 100.0000 | 27.7504 |
| GRU | return_slope_aisle | 0.0016 | 0.0037 | 0.0008345 | 0.0120 | 0.0030 | 0.0068 | 0.0053 | 0.2456 | 0.2704 | 96.7838 | 100.0000 |
| GRU | shipping_return_aisle | 0.0011 | 0.0022 | 0.000835 | 0.0205 | 0.0030 | 0.0061 | 0.0362 | 0.4902 | 0.4860 | 99.4935 | 72.2865 |
