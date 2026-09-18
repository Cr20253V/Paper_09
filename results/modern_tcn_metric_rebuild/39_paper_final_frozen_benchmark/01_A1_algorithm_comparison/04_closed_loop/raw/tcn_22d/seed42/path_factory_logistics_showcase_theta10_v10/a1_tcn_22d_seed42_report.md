# A1 TCN seed42 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed42_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed42\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed42_out.mat`
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
| ModernTCN | 0.0533 | 0.2607 | 0.0650 | 0.0247 | 0.0186 | 2.3892 | 217.9292 | 1.4805 | 8.3745 | 0.0000 | 0.5018 | 0.4672 | 97.0611 | 78.2579 |
| TCN | 4.2379 | 23.2979 | 1.2921 | 5.7894 | 0.7529 | 35.5246 | 720.0000 | 1.5387 | 295.4191 | 0.0000 | 2.8310 | 3.6856 | 52.4600 | 88.4890 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0479 | 0.0532 | 0.2965 | 0.0000 |
| TCN | 0.0101 | 0.0117 | 0.0150 | 0.0610 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.4443 | 0.1019 | 0.0000 |
| TCN | 47.3852 | 46.1745 | 58.6679 | 58.2603 | 0.0000 |

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
| TCN | all | 4.2379 | 23.2979 | 1.2921 | 5.7894 | 0.7529 | 1.5387 | 295.4191 | 2.8310 | 3.6856 | 52.4600 | 88.4890 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.7448 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.1349 | 0.0000 | 0.0003636 | 47.5622 | 0.3148 | 3.4124 | 97.9744 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0829 | 0.0000 | 1.615e-05 | 0.0172 | 0.6651 | 1.7622 | 67.9000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 8.6945 | 23.2979 | 1.6058 | 13.2473 | 1.6718 | 1.4400 | 519.9267 | 8.7116 | 7.1223 | 11.3924 | 41.7503 |
| TCN | return_recovery_aisle | 2.9174 | 5.3444 | 2.2346 | 3.0771 | 0.9485 | 1.5387 | 3692 | 2.9495 | 3.0479 | 67.2414 | 87.2742 |
| TCN | return_slope_aisle | 3.1035 | 3.1772 | 1.7135 | 0.8600 | 0.0243 | 1.3346 | 0.1350 | 2.7881 | 3.3082 | 13.1216 | 100.0000 |
| TCN | shipping_return_aisle | 3.0163 | 3.0235 | 0.9814 | 0.8600 | 0.0243 | 1.3346 | 3.594e-25 | 0.9388 | 0.8319 | 78.5818 | 100.0000 |
