# A1 GRU seed21 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed21_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed21\path_closed_loop_long_updown_theta10_v1\gru_22d_seed21_out.mat`
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
| ModernTCN | 0.0238 | 0.0646 | 0.0286 | 0.0566 | 0.0214 | 0.5108 | 284.4868 | 0.2077 | 26.1357 | 0.0000 | 0.8366 | 1.1637 | 90.0942 | 53.6428 |
| GRU | 0.0397 | 0.1185 | 0.0191 | 0.0448 | 0.0136 | 0.2151 | 264.2011 | 0.2613 | 0.7105 | 0.0000 | 0.6847 | 0.9196 | 89.0830 | 60.3080 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0220 | 0.0232 | 0.2405 | 0.0000 |
| GRU | 0.0112 | 0.0233 | 0.0503 | 0.1111 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0238 | 0.0646 | 0.0286 | 0.0566 | 0.0214 | 0.2077 | 26.1357 | 0.8366 | 1.1637 | 90.0942 | 53.6428 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0321 | 0.0646 | 0.0394 | 0.0599 | 0.0239 | 0.0918 | 28.3700 | 0.8470 | 1.1251 | 91.0000 | 71.9231 |
| ModernTCN | downhill_transition | 0.0116 | 0.0253 | 0.0159 | 0.0492 | 0.0187 | 0.1955 | 4.7305 | 0.7696 | 1.1320 | 91.4615 | 41.5385 |
| ModernTCN | uphill_return | 0.0207 | 0.0571 | 0.0248 | 0.0688 | 0.0179 | 0.0677 | 53.4643 | 1.0518 | 1.5235 | 84.8000 | 56.7000 |
| ModernTCN | flat_recovery | 0.0323 | 0.0597 | 0.0345 | 0.0485 | 0.0308 | 0.2077 | 33.8772 | 0.9739 | 1.2111 | 89.8000 | 8.4000 |
| GRU | all | 0.0397 | 0.1185 | 0.0191 | 0.0448 | 0.0136 | 0.2613 | 0.7105 | 0.6847 | 0.9196 | 89.0830 | 60.3080 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2193 | 0.0000 | 0.0002637 | 102.0335 | 0.7237 | 0.4630 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0116 | 0.0290 | 0.0128 | 0.0249 | 0.0083 | 0.1188 | 0.1546 | 0.3311 | 0.3878 | 89.9231 | 71.2308 |
| GRU | downhill_transition | 0.0585 | 0.1185 | 0.0232 | 0.0590 | 0.0119 | 0.2613 | 1.0241 | 0.9346 | 1.2922 | 90.3846 | 73.3846 |
| GRU | uphill_return | 0.0454 | 0.0716 | 0.0249 | 0.0359 | 0.0215 | 0.1746 | 0.9428 | 0.4908 | 0.8963 | 84.7000 | 32.8000 |
| GRU | flat_recovery | 0.0175 | 0.0293 | 0.0104 | 0.0562 | 0.0118 | 0.1511 | 0.3577 | 1.2474 | 1.5592 | 86.8000 | 33.2000 |
