# A1 TCN seed21 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed21_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed21\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed21_out.mat`
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
| ModernTCN | 0.0363 | 0.1129 | 0.0479 | 0.0221 | 0.0132 | 2.0698 | 219.2911 | 1.4876 | 0.4196 | 0.0000 | 0.4097 | 0.4145 | 94.9823 | 69.9344 |
| TCN | 5.9521 | 23.1796 | 0.8642 | 5.8740 | 0.7767 | 30.2587 | 874.5384 | 1.6379 | 283.1468 | 0.0000 | 2.8137 | 3.7256 | 43.7574 | 82.3503 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0197 | 0.0280 | 0.0462 | 0.4847 | 0.0000 |
| TCN | 0.0100 | 0.0116 | 0.0151 | 0.0842 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0122 | 0.0041 | 0.0000 |
| TCN | 56.3486 | 56.2263 | 58.6394 | 58.1462 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0363 | 0.1129 | 0.0479 | 0.0221 | 0.0132 | 1.4876 | 0.4196 | 0.4097 | 0.4145 | 94.9823 | 69.9344 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0211 | 0.0000 | 7.671e-05 | 0.1234 | 0.3087 | 0.3317 | 97.9744 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0230 | 0.0000 | 1.823e-05 | 1.2030 | 0.5006 | 0.4455 | 97.2000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0716 | 0.1129 | 0.1073 | 0.0202 | 0.0135 | 1.4876 | 0.2651 | 0.5991 | 0.5991 | 100.0000 | 4.0157 |
| ModernTCN | return_recovery_aisle | 0.0457 | 0.0739 | 0.0449 | 0.0342 | 0.0487 | 0.4070 | 0.0946 | 0.8970 | 0.8970 | 63.7931 | 0.0000 |
| ModernTCN | return_slope_aisle | 0.0293 | 0.0907 | 0.0126 | 0.0239 | 0.0087 | 0.3588 | 0.3538 | 0.3971 | 0.4026 | 92.5541 | 76.2162 |
| ModernTCN | shipping_return_aisle | 0.0022 | 0.0035 | 0.0009093 | 0.0120 | 0.0030 | 0.0051 | 2.7766 | 0.2184 | 0.1847 | 96.1650 | 100.0000 |
| TCN | all | 5.9521 | 23.1796 | 0.8642 | 5.8740 | 0.7767 | 1.6379 | 283.1468 | 2.8137 | 3.7256 | 43.7574 | 82.3503 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.6355 | 0.0537 | 20.5833 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 0.2307 | 3.4581 | 93.5769 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 0.4312 | 1.7622 | 45.6000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.7088 | 23.1796 | 1.6062 | 13.3794 | 1.6823 | 1.4400 | 604.0238 | 8.4666 | 7.0976 | 5.9144 | 18.5072 |
| TCN | return_recovery_aisle | 5.3349 | 7.5086 | 1.4729 | 4.0124 | 1.2242 | 1.6379 | 3434 | 3.6544 | 3.6534 | 37.2742 | 51.0673 |
| TCN | return_slope_aisle | 7.4517 | 7.5061 | 0.7209 | 0.8600 | 0.0243 | 1.3346 | 1.956e-10 | 2.9106 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 7.4162 | 7.4165 | 0.0920 | 0.8600 | 0.0243 | 1.3346 | 0.0000 | 0.9048 | 0.8319 | 78.5818 | 100.0000 |
