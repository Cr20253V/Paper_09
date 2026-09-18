# A1 TCN seed1 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed1_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed1\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0304 | 0.0804 | 0.0325 | 0.0579 | 0.0239 | 0.6124 | 322.5731 | 0.2740 | 14.0134 | 0.0000 | 0.9982 | 1.2392 | 93.9784 | 37.4167 |
| TCN | 0.1935 | 0.5542 | 0.0722 | 0.1286 | 0.0313 | 1.6355 | 434.9432 | 0.9799 | 119.5987 | 0.0000 | 1.1453 | 2.6748 | 73.1326 | 37.8074 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0219 | 0.0229 | 0.2329 | 0.0000 |
| TCN | 0.0101 | 0.0202 | 0.0235 | 0.1638 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.2758 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0304 | 0.0804 | 0.0325 | 0.0579 | 0.0239 | 0.2740 | 14.0134 | 0.9982 | 1.2392 | 93.9784 | 37.4167 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0385 | 0.0804 | 0.0436 | 0.0631 | 0.0262 | 0.1018 | 17.4597 | 1.0146 | 1.3063 | 92.0000 | 67.0769 |
| ModernTCN | downhill_transition | 0.0137 | 0.0329 | 0.0213 | 0.0582 | 0.0217 | 0.2740 | 6.9336 | 0.9538 | 1.2534 | 95.0769 | 27.1538 |
| ModernTCN | uphill_return | 0.0390 | 0.0781 | 0.0265 | 0.0626 | 0.0166 | 0.0694 | 8.5051 | 1.1774 | 1.5549 | 93.2000 | 8.5000 |
| ModernTCN | flat_recovery | 0.0250 | 0.0467 | 0.0410 | 0.0421 | 0.0375 | 0.1060 | 40.8740 | 1.2135 | 1.0184 | 94.8000 | 13.6000 |
| TCN | all | 0.1935 | 0.5542 | 0.0722 | 0.1286 | 0.0313 | 0.9799 | 119.5987 | 1.1453 | 2.6748 | 73.1326 | 37.8074 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.3836 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.1575 | 0.3406 | 0.0859 | 0.1588 | 0.0326 | 0.4672 | 246.5923 | 0.9855 | 3.6654 | 66.6154 | 72.2308 |
| TCN | downhill_transition | 0.1290 | 0.2513 | 0.0514 | 0.0712 | 0.0345 | 0.9291 | 13.4165 | 1.6350 | 1.6247 | 88.6154 | 7.3846 |
| TCN | uphill_return | 0.1636 | 0.4700 | 0.0450 | 0.1648 | 0.0284 | 0.6452 | 115.7038 | 0.6525 | 3.8365 | 68.7000 | 30.0000 |
| TCN | flat_recovery | 0.4055 | 0.5542 | 0.1234 | 0.1019 | 0.0325 | 0.9799 | 132.0926 | 1.6129 | 1.8491 | 45.4000 | 12.0000 |
