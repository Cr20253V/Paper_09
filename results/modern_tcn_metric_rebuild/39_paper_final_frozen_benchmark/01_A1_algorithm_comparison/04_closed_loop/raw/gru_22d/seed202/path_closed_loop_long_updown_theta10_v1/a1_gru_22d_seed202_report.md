# A1 GRU seed202 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_closed_loop_long_updown_theta10_v1\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| ModernTCN | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0270 | 0.0803 | 0.0337 | 0.0587 | 0.0239 | 0.6070 | 312.9248 | 0.2489 | 14.4533 | 0.0000 | 0.8356 | 1.2099 | 89.4047 | 43.3693 |
| GRU | 0.0184 | 0.0520 | 0.0150 | 0.0339 | 0.0118 | 0.2228 | 265.8208 | 0.1754 | 0.8611 | 0.0000 | 0.4763 | 0.7601 | 90.0712 | 62.4684 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0231 | 0.2482 | 0.0000 |
| GRU | 0.0104 | 0.0113 | 0.0146 | 0.0278 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0270 | 0.0803 | 0.0337 | 0.0587 | 0.0239 | 0.2489 | 14.4533 | 0.8356 | 1.2099 | 89.4047 | 43.3693 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0397 | 0.0803 | 0.0454 | 0.0709 | 0.0266 | 0.1240 | 14.9911 | 0.7744 | 1.2789 | 91.3077 | 76.8462 |
| ModernTCN | downhill_transition | 0.0156 | 0.0274 | 0.0234 | 0.0559 | 0.0202 | 0.2489 | 9.8073 | 1.1275 | 1.3230 | 92.2308 | 27.2308 |
| ModernTCN | uphill_return | 0.0210 | 0.0518 | 0.0276 | 0.0591 | 0.0196 | 0.1100 | 23.2140 | 0.8249 | 1.3490 | 80.8000 | 19.5000 |
| ModernTCN | flat_recovery | 0.0266 | 0.0530 | 0.0394 | 0.0372 | 0.0362 | 0.1696 | 14.2021 | 0.6763 | 1.0649 | 89.0000 | 17.8000 |
| GRU | all | 0.0184 | 0.0520 | 0.0150 | 0.0339 | 0.0118 | 0.1754 | 0.8611 | 0.4763 | 0.7601 | 90.0712 | 62.4684 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2171 | 0.0000 | 0.0002637 | 101.8347 | 0.1036 | 0.0525 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0083 | 0.0215 | 0.0191 | 0.0206 | 0.0092 | 0.1053 | 0.1816 | 0.3865 | 0.4699 | 92.7692 | 85.6154 |
| GRU | downhill_transition | 0.0276 | 0.0520 | 0.0098 | 0.0406 | 0.0089 | 0.1754 | 1.1334 | 0.5219 | 0.8684 | 92.0769 | 62.0000 |
| GRU | uphill_return | 0.0171 | 0.0316 | 0.0175 | 0.0419 | 0.0177 | 0.1082 | 1.3787 | 0.6545 | 1.1194 | 81.2000 | 48.2000 |
| GRU | flat_recovery | 0.0143 | 0.0229 | 0.0122 | 0.0257 | 0.0127 | 0.1447 | 0.5608 | 0.4103 | 0.8636 | 90.6000 | 13.4000 |
