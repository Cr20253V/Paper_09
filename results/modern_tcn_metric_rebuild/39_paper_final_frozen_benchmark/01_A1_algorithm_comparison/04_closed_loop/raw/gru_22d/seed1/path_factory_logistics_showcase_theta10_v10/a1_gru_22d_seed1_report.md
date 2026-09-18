# A1 GRU seed1 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed1_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed1\path_factory_logistics_showcase_theta10_v10\gru_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| ModernTCN | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 2.2646 | 4.9434 | 0.3343 | 0.3787 | 0.0669 | 17.0136 | 720.0000 | 1.6388 | 761.2871 | 0.0000 | 0.9147 | 0.9342 | 86.8178 | 52.3621 |
| GRU | 0.0231 | 0.1623 | 0.0477 | 0.0330 | 0.0139 | 1.6528 | 217.8040 | 0.9777 | 0.4547 | 0.0000 | 0.6513 | 0.6410 | 98.4307 | 95.8260 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0205 | 0.0220 | 0.0237 | 4.9392 | 0.0000 |
| GRU | 0.0087 | 0.0099 | 0.0113 | 3.4674 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 17.0016 | 16.9771 | 37.8103 | 29.3808 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0041 | 0.0000 | 0.0000 |

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
| GRU | all | 0.0231 | 0.1623 | 0.0477 | 0.0330 | 0.0139 | 0.9777 | 0.4547 | 0.6513 | 0.6410 | 98.4307 | 95.8260 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1198 | 0.0000 | 0.0002577 | 24.2648 | 1.4073 | 1.3396 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0148 | 0.0000 | 2.401e-05 | 0.0039 | 0.2768 | 0.2778 | 97.9487 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0362 | 0.0000 | 2.313e-05 | 0.0198 | 0.7666 | 0.8280 | 99.1000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.0423 | 0.1289 | 0.1073 | 0.0491 | 0.0125 | 0.9777 | 0.2418 | 1.2026 | 1.1662 | 100.0000 | 92.8852 |
| GRU | return_recovery_aisle | 0.0629 | 0.1623 | 0.0497 | 0.0369 | 0.0568 | 0.2937 | 7.8583 | 1.0808 | 0.9651 | 100.0000 | 42.6929 |
| GRU | return_slope_aisle | 0.0024 | 0.0047 | 0.0007194 | 0.0196 | 0.0029 | 0.0045 | 0.0039 | 0.3567 | 0.3570 | 97.5676 | 100.0000 |
| GRU | shipping_return_aisle | 0.0033 | 0.0037 | 0.0004093 | 0.0557 | 0.0028 | 0.0044 | 0.0220 | 1.3726 | 1.4181 | 97.3951 | 100.0000 |
