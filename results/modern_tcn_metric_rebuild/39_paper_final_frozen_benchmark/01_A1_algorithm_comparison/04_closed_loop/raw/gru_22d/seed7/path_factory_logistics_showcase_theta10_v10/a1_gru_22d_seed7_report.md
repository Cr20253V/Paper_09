# A1 GRU seed7 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed7_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed7\path_factory_logistics_showcase_theta10_v10\gru_22d_seed7_out.mat`
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
| ModernTCN | 0.0403 | 0.1839 | 0.0563 | 0.0210 | 0.0131 | 2.2371 | 217.8351 | 1.4835 | 0.7195 | 0.0000 | 0.3907 | 0.4044 | 97.4116 | 74.0187 |
| GRU | 15.3861 | 23.0727 | 1.1143 | 0.6475 | 0.0239 | 40.4107 | 817.0416 | 1.5786 | 156.3095 | 0.0000 | 1.3413 | 1.3367 | 71.3651 | 57.0578 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0198 | 0.0210 | 0.0221 | 0.4139 | 0.0000 |
| GRU | 0.0091 | 0.0101 | 0.0109 | 0.0297 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.1957 | 0.0408 | 0.0000 |
| GRU | 56.1692 | 56.1692 | 57.0864 | 53.9355 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0403 | 0.1839 | 0.0563 | 0.0210 | 0.0131 | 1.4835 | 0.7195 | 0.3907 | 0.4044 | 97.4116 | 74.0187 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0201 | 0.0000 | 7.135e-05 | 0.1268 | 0.3192 | 0.3448 | 98.7564 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0202 | 0.0000 | 3.029e-05 | 2.7262 | 0.3806 | 0.3480 | 94.9000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0829 | 0.1839 | 0.1264 | 0.0202 | 0.0127 | 1.4835 | 1.6981 | 0.5991 | 0.5991 | 93.5618 | 16.4120 |
| ModernTCN | return_recovery_aisle | 0.0624 | 0.1334 | 0.0575 | 0.0341 | 0.0508 | 0.3756 | 0.5954 | 0.8970 | 0.8970 | 94.3350 | 0.0000 |
| ModernTCN | return_slope_aisle | 0.0218 | 0.0892 | 0.0081 | 0.0221 | 0.0063 | 0.2457 | 0.1555 | 0.3505 | 0.3762 | 99.1351 | 82.0811 |
| ModernTCN | shipping_return_aisle | 0.0007906 | 0.0017 | 0.0006053 | 0.0098 | 0.0029 | 0.0040 | 2.8520 | 0.1593 | 0.1425 | 95.7308 | 100.0000 |
| GRU | all | 15.3861 | 23.0727 | 1.1143 | 0.6475 | 0.0239 | 1.5786 | 156.3095 | 1.3413 | 1.3367 | 71.3651 | 57.0578 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1420 | 0.0000 | 0.0002577 | 24.3260 | 2.4828 | 2.3752 | 100.0000 | 100.0000 |
| GRU | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0378 | 0.0000 | 5.616e-05 | 0.0041 | 0.9613 | 0.9555 | 97.5256 | 100.0000 |
| GRU | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0692 | 0.0000 | 5.183e-05 | 0.0198 | 1.7647 | 1.8179 | 98.5000 | 100.0000 |
| GRU | adjacent_aisle_u_turn | 10.6956 | 22.8956 | 1.1592 | 0.7904 | 0.0459 | 1.5786 | 836.9547 | 1.4437 | 1.4454 | 97.9921 | 88.3457 |
| GRU | return_recovery_aisle | 22.9008 | 22.9054 | 2.0729 | 0.8600 | 0.0210 | 1.5035 | 4.248e-29 | 1.4452 | 1.4452 | 100.0000 | 0.0000 |
| GRU | return_slope_aisle | 22.9828 | 23.0624 | 1.5496 | 0.8600 | 0.0210 | 1.5035 | 6.987e-30 | 1.3271 | 1.3271 | 13.1216 | 0.0000 |
| GRU | shipping_return_aisle | 23.0694 | 23.0727 | 0.9700 | 0.8600 | 0.0210 | 1.5035 | 0.0000 | 1.7837 | 1.7837 | 78.5818 | 0.0000 |
