# A1 TCN seed1 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed1_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed1\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 2.2646 | 4.9434 | 0.3343 | 0.3787 | 0.0669 | 17.0136 | 720.0000 | 1.6388 | 761.2871 | 0.0000 | 0.9147 | 0.9342 | 86.8178 | 52.3621 |
| TCN | 5.1625 | 23.6192 | 0.8957 | 5.7772 | 0.7414 | 32.2096 | 873.2695 | 1.6560 | 270.8973 | 0.0000 | 2.8666 | 3.5786 | 51.6936 | 82.2239 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0205 | 0.0220 | 0.0237 | 4.9392 | 0.0000 |
| TCN | 0.0098 | 0.0111 | 0.0139 | 1.6181 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 17.0016 | 16.9771 | 37.8103 | 29.3808 | 0.0000 |
| TCN | 51.1841 | 50.7154 | 58.6679 | 58.2277 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 2.2646 | 4.9434 | 0.3343 | 0.3787 | 0.0669 | 1.6388 | 761.2871 | 0.9147 | 0.9342 | 86.8178 | 52.3621 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0347 | 0.0000 | 8.537e-05 | 1.3571 | 0.7640 | 0.7836 | 97.1026 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0251 | 0.0000 | 1.711e-05 | 3.7396 | 0.5543 | 0.4748 | 99.6000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.4151 | 0.7258 | 0.2722 | 0.0195 | 0.0240 | 1.4987 | 29.1728 | 0.6763 | 0.5991 | 100.0000 | 42.4051 |
| ModernTCN | return_recovery_aisle | 0.6221 | 0.9720 | 0.2629 | 0.0722 | 0.1205 | 1.6175 | 152.7597 | 0.8935 | 0.8970 | 100.0000 | 6.2397 |
| ModernTCN | return_slope_aisle | 3.5046 | 4.9434 | 0.5579 | 0.5787 | 0.1094 | 1.6388 | 2479 | 1.4225 | 1.5244 | 63.4054 | 11.8514 |
| ModernTCN | shipping_return_aisle | 4.9336 | 4.9340 | 0.1045 | 0.8600 | 0.0230 | 1.5339 | 3.267e-23 | 0.8319 | 0.8319 | 78.5818 | 0.0000 |
| TCN | all | 5.1625 | 23.6192 | 0.8957 | 5.7772 | 0.7414 | 1.6560 | 270.8973 | 2.8666 | 3.5786 | 51.6936 | 82.2239 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 1.8610 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 1.6038 | 3.4581 | 96.0000 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 2.0497 | 1.7622 | 56.2000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.8291 | 23.6192 | 1.6108 | 13.2569 | 1.6678 | 1.4400 | 343.0773 | 8.2314 | 6.8911 | 14.7097 | 12.8110 |
| TCN | return_recovery_aisle | 4.8574 | 5.5966 | 1.4550 | 2.3797 | 0.7767 | 1.6560 | 4169 | 1.7092 | 1.4678 | 61.5764 | 69.9507 |
| TCN | return_slope_aisle | 5.5303 | 5.5913 | 0.8381 | 0.8600 | 0.0239 | 1.3343 | 0.0273 | 1.5588 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 5.4839 | 5.4851 | 0.1063 | 0.8600 | 0.0239 | 1.3343 | 1.177e-25 | 1.5898 | 0.8319 | 78.5818 | 100.0000 |
