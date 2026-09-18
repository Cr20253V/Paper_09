# A1 GRU seed42 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed42_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed42\path_factory_logistics_showcase_theta10_v10\gru_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 7.0000 | 4.0000 | 5.0000 | 16.0000 | 1.0000 |
| ModernTCN | 11.0000 | 5.0000 | 7.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0533 | 0.2607 | 0.0650 | 0.0247 | 0.0186 | 2.3892 | 217.9292 | 1.4805 | 8.3745 | 0.0000 | 0.5018 | 0.4672 | 97.0611 | 78.2579 |
| GRU | 0.0361 | 0.1970 | 0.0438 | 0.0340 | 0.0158 | 1.5533 | 217.8414 | 0.6604 | 0.5968 | 0.0000 | 0.6490 | 0.6416 | 98.5530 | 92.8178 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0479 | 0.0532 | 0.2965 | 0.0000 |
| GRU | 0.0109 | 0.0240 | 0.0481 | 0.0693 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.4443 | 0.1019 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0082 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0533 | 0.2607 | 0.0650 | 0.0247 | 0.0186 | 1.4805 | 8.3745 | 0.5018 | 0.4672 | 97.0611 | 78.2579 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0209 | 0.0000 | 6.965e-05 | 0.1182 | 0.3835 | 0.4009 | 98.3077 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0217 | 0.0000 | 1.467e-05 | 1.1956 | 0.4359 | 0.3613 | 96.6000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.1041 | 0.2607 | 0.1432 | 0.0158 | 0.0131 | 1.4805 | 11.4785 | 0.6786 | 0.5000 | 94.4129 | 61.0650 |
| ModernTCN | return_recovery_aisle | 0.0998 | 0.1901 | 0.0854 | 0.0327 | 0.0762 | 0.6922 | 112.3223 | 0.8970 | 0.8969 | 84.8933 | 10.1806 |
| ModernTCN | return_slope_aisle | 0.0327 | 0.0808 | 0.0106 | 0.0334 | 0.0089 | 0.1125 | 1.2225 | 0.5908 | 0.5817 | 99.0405 | 68.2162 |
| ModernTCN | shipping_return_aisle | 0.0017 | 0.0039 | 0.0012 | 0.0107 | 0.0038 | 0.0127 | 3.3711 | 0.1780 | 0.1607 | 96.8162 | 92.4747 |
| GRU | all | 0.0361 | 0.1970 | 0.0438 | 0.0340 | 0.0158 | 0.6604 | 0.5968 | 0.6490 | 0.6416 | 98.5530 | 92.8178 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1242 | 0.0000 | 0.0002577 | 24.2937 | 1.6717 | 1.5957 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0157 | 0.0000 | 2.967e-05 | 0.0039 | 0.2784 | 0.2811 | 98.2692 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0407 | 0.0000 | 2.766e-05 | 0.0194 | 0.8719 | 0.9256 | 97.4000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 0.0762 | 0.1970 | 0.0972 | 0.0423 | 0.0167 | 0.6604 | 0.1528 | 0.9557 | 0.9231 | 100.0000 | 88.1711 |
| GRU | return_recovery_aisle | 0.0661 | 0.1507 | 0.0565 | 0.0475 | 0.0628 | 0.3306 | 11.0274 | 1.3167 | 1.2647 | 100.0000 | 3.2841 |
| GRU | return_slope_aisle | 0.0025 | 0.0054 | 0.0008023 | 0.0211 | 0.0029 | 0.0244 | 0.0046 | 0.3748 | 0.3737 | 97.9730 | 99.4324 |
| GRU | shipping_return_aisle | 0.0017 | 0.0028 | 0.0005869 | 0.0618 | 0.0028 | 0.0043 | 0.0214 | 1.5306 | 1.5705 | 96.8162 | 100.0000 |
