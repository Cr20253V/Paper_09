# A1 GRU seed520 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed520_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed520\path_closed_loop_long_updown_theta10_v1\gru_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 8.0000 | 5.0000 | 6.0000 | 19.0000 | 1.0000 |
| ModernTCN | 10.0000 | 4.0000 | 6.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0266 | 0.0729 | 0.0358 | 0.0619 | 0.0261 | 0.6311 | 350.2730 | 0.2185 | 48.2297 | 0.0000 | 0.8084 | 1.2154 | 89.2209 | 40.8412 |
| GRU | 0.0284 | 0.0820 | 0.0165 | 0.0465 | 0.0141 | 0.1271 | 258.6189 | 0.2225 | 0.6832 | 0.0000 | 0.8092 | 1.0011 | 89.1979 | 62.7902 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0228 | 0.2402 | 0.0000 |
| GRU | 0.0105 | 0.0118 | 0.0147 | 0.0190 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0266 | 0.0729 | 0.0358 | 0.0619 | 0.0261 | 0.2185 | 48.2297 | 0.8084 | 1.2154 | 89.2209 | 40.8412 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0334 | 0.0655 | 0.0417 | 0.0640 | 0.0260 | 0.0989 | 36.2897 | 0.8295 | 1.2000 | 89.9231 | 75.7692 |
| ModernTCN | downhill_transition | 0.0106 | 0.0264 | 0.0198 | 0.0453 | 0.0183 | 0.2146 | 7.4215 | 0.7189 | 1.0212 | 92.6154 | 26.0000 |
| ModernTCN | uphill_return | 0.0287 | 0.0721 | 0.0378 | 0.0891 | 0.0240 | 0.1095 | 139.4720 | 1.1712 | 1.9627 | 78.2000 | 16.0000 |
| ModernTCN | flat_recovery | 0.0359 | 0.0729 | 0.0524 | 0.0327 | 0.0463 | 0.2185 | 26.6650 | 0.6666 | 0.8763 | 95.2000 | 8.8000 |
| GRU | all | 0.0284 | 0.0820 | 0.0165 | 0.0465 | 0.0141 | 0.2225 | 0.6832 | 0.8092 | 1.0011 | 89.1979 | 62.7902 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2232 | 0.0000 | 0.0002637 | 102.2384 | 1.2611 | 0.8694 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0163 | 0.0349 | 0.0108 | 0.0417 | 0.0077 | 0.1244 | 0.1334 | 0.7752 | 0.7875 | 89.5385 | 78.6923 |
| GRU | downhill_transition | 0.0419 | 0.0820 | 0.0167 | 0.0505 | 0.0102 | 0.2225 | 0.9940 | 0.6958 | 1.0271 | 91.5385 | 72.0769 |
| GRU | uphill_return | 0.0273 | 0.0491 | 0.0247 | 0.0299 | 0.0230 | 0.1507 | 0.8357 | 0.5289 | 0.9479 | 82.8000 | 45.5000 |
| GRU | flat_recovery | 0.0168 | 0.0311 | 0.0111 | 0.0615 | 0.0157 | 0.1350 | 0.3449 | 1.3955 | 1.5692 | 89.6000 | 13.4000 |
