# A1 GRU seed11 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed11_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed11\path_closed_loop_long_updown_theta10_v1\gru_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 8.0000 | 4.0000 | 6.0000 | 18.0000 | 1.0000 |
| ModernTCN | 10.0000 | 5.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0407 | 0.1048 | 0.0366 | 0.0588 | 0.0240 | 0.7311 | 325.3801 | 0.1154 | 26.4074 | 0.0000 | 0.8068 | 1.2085 | 90.8067 | 60.9285 |
| GRU | 0.0408 | 0.1050 | 0.0178 | 0.0371 | 0.0127 | 0.1698 | 263.0970 | 0.3559 | 0.6657 | 0.0000 | 0.6013 | 0.8445 | 87.5891 | 67.3179 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0218 | 0.0228 | 0.2348 | 0.0000 |
| GRU | 0.0400 | 0.0454 | 0.0486 | 0.0797 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0407 | 0.1048 | 0.0366 | 0.0588 | 0.0240 | 0.1154 | 26.4074 | 0.8068 | 1.2085 | 90.8067 | 60.9285 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0510 | 0.1048 | 0.0415 | 0.0701 | 0.0177 | 0.0956 | 72.1393 | 0.8807 | 1.4591 | 86.8462 | 77.6923 |
| ModernTCN | downhill_transition | 0.0225 | 0.0364 | 0.0249 | 0.0456 | 0.0143 | 0.1152 | 7.4967 | 0.7167 | 1.0252 | 93.9231 | 57.5385 |
| ModernTCN | uphill_return | 0.0530 | 0.0995 | 0.0371 | 0.0725 | 0.0262 | 0.0808 | 3.6170 | 1.1379 | 1.6105 | 89.0000 | 57.6000 |
| ModernTCN | flat_recovery | 0.0263 | 0.0467 | 0.0527 | 0.0299 | 0.0480 | 0.1154 | 14.8931 | 0.5922 | 0.8365 | 92.0000 | 13.4000 |
| GRU | all | 0.0408 | 0.1050 | 0.0178 | 0.0371 | 0.0127 | 0.3559 | 0.6657 | 0.6013 | 0.8445 | 87.5891 | 67.3179 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2181 | 0.0000 | 0.0002637 | 101.9208 | 0.4972 | 0.2855 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0030 | 0.0069 | 0.0127 | 0.0238 | 0.0064 | 0.1091 | 0.1530 | 0.3761 | 0.4382 | 88.0769 | 82.5385 |
| GRU | downhill_transition | 0.0400 | 0.0821 | 0.0173 | 0.0495 | 0.0111 | 0.2157 | 0.8965 | 0.8160 | 1.1690 | 91.8462 | 83.7692 |
| GRU | uphill_return | 0.0513 | 0.1050 | 0.0245 | 0.0311 | 0.0205 | 0.1806 | 0.8349 | 0.5259 | 0.9430 | 78.3000 | 39.3000 |
| GRU | flat_recovery | 0.0711 | 0.1048 | 0.0187 | 0.0381 | 0.0113 | 0.3559 | 0.5843 | 0.7792 | 1.1101 | 87.6000 | 24.8000 |
