# A1 GRU seed21 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed21_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed21\path_factory_logistics_showcase_theta10_v10\gru_22d_seed21_out.mat`
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
| ModernTCN | 0.0363 | 0.1129 | 0.0479 | 0.0221 | 0.0132 | 2.0698 | 219.2911 | 1.4876 | 0.4196 | 0.0000 | 0.4097 | 0.4145 | 94.9823 | 69.9344 |
| GRU | 1.7904 | 6.2670 | 0.3619 | 0.2435 | 0.0702 | 10.3267 | 826.2292 | 1.6252 | 1302 | 0.0000 | 0.5787 | 0.5821 | 96.8328 | 58.9125 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0197 | 0.0280 | 0.0462 | 0.4847 | 0.0000 |
| GRU | 0.0104 | 0.0115 | 0.0132 | 0.8865 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0122 | 0.0041 | 0.0000 |
| GRU | 1.1576 | 1.1046 | 42.9951 | 27.7626 | 0.0000 |

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
| GRU | all | 1.7904 | 6.2670 | 0.3619 | 0.2435 | 0.0702 | 1.6252 | 1302 | 0.5787 | 0.5821 | 96.8328 | 58.9125 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1276 | 0.0000 | 0.0002577 | 24.3005 | 1.8383 | 1.7574 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0178 | 0.0000 | 3.307e-05 | 0.0043 | 0.3570 | 0.3611 | 98.5000 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0466 | 0.0000 | 3.252e-05 | 0.0197 | 1.0910 | 1.1492 | 95.8000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.7253 | 1.3181 | 0.1576 | 0.0346 | 0.0184 | 1.4850 | 93.8974 | 0.6611 | 0.6799 | 100.0000 | 59.5810 |
| GRU | return_recovery_aisle | 0.5303 | 0.7706 | 0.2722 | 0.0971 | 0.1022 | 1.6035 | 263.4486 | 0.7737 | 0.7371 | 83.1691 | 10.5090 |
| GRU | return_slope_aisle | 2.0404 | 4.8492 | 0.6146 | 0.3504 | 0.1195 | 1.6252 | 2665 | 0.5164 | 0.5126 | 97.9865 | 15.8919 |
| GRU | shipping_return_aisle | 5.7088 | 6.2659 | 0.3928 | 0.6120 | 0.0232 | 1.5208 | 8299 | 0.2345 | 0.2887 | 80.8973 | 33.9363 |
