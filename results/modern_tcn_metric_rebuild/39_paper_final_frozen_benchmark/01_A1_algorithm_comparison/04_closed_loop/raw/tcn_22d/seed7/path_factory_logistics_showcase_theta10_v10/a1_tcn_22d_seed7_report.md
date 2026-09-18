# A1 TCN seed7 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed7_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed7\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed7_out.mat`
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
| ModernTCN | 0.0403 | 0.1839 | 0.0563 | 0.0210 | 0.0131 | 2.2371 | 217.8351 | 1.4835 | 0.7195 | 0.0000 | 0.3907 | 0.4044 | 97.4116 | 74.0187 |
| TCN | 5.1877 | 23.6418 | 0.9803 | 5.7797 | 0.7430 | 33.0808 | 870.9847 | 1.6459 | 271.9167 | 0.0000 | 2.8240 | 3.5958 | 54.5836 | 81.3313 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0198 | 0.0210 | 0.0221 | 0.4139 | 0.0000 |
| TCN | 0.0107 | 0.0234 | 0.0465 | 0.0744 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.1957 | 0.0408 | 0.0000 |
| TCN | 53.3771 | 52.7331 | 58.6475 | 58.2603 | 0.0000 |

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
| TCN | all | 5.1877 | 23.6418 | 0.9803 | 5.7797 | 0.7430 | 1.6459 | 271.9167 | 2.8240 | 3.5958 | 54.5836 | 81.3313 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 1.6232 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1373 | 0.0000 | 2.542e-05 | 0.0030 | 1.2493 | 3.4581 | 99.4744 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 1.7460 | 1.7622 | 82.2000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.8376 | 23.6418 | 1.6104 | 13.2586 | 1.6689 | 1.4400 | 340.0727 | 8.4104 | 6.9532 | 18.9873 | 6.6128 |
| TCN | return_recovery_aisle | 4.9021 | 5.6616 | 1.6420 | 2.4652 | 0.7981 | 1.6459 | 4201 | 1.6864 | 1.5810 | 60.0985 | 75.2874 |
| TCN | return_slope_aisle | 5.5862 | 5.6563 | 1.0557 | 0.8600 | 0.0235 | 1.3341 | 0.0127 | 1.7962 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 5.5232 | 5.5264 | 0.3440 | 0.8600 | 0.0235 | 1.3341 | 2.002e-25 | 1.4178 | 0.8319 | 78.5818 | 100.0000 |
