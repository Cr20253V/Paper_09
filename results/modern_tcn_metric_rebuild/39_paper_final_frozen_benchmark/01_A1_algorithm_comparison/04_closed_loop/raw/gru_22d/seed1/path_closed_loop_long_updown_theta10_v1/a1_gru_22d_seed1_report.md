# A1 GRU seed1 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed1_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed1\path_closed_loop_long_updown_theta10_v1\gru_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 4.0000 | 6.0000 | 16.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 6.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0304 | 0.0804 | 0.0325 | 0.0579 | 0.0239 | 0.6124 | 322.5731 | 0.2740 | 14.0134 | 0.0000 | 0.9982 | 1.2392 | 93.9784 | 37.4167 |
| GRU | 0.0222 | 0.0494 | 0.0211 | 0.0424 | 0.0158 | 0.3295 | 260.6772 | 0.3051 | 0.8105 | 0.0000 | 0.9006 | 1.1047 | 85.7734 | 61.4112 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0219 | 0.0229 | 0.2329 | 0.0000 |
| GRU | 0.0087 | 0.0096 | 0.0102 | 0.0911 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0304 | 0.0804 | 0.0325 | 0.0579 | 0.0239 | 0.2740 | 14.0134 | 0.9982 | 1.2392 | 93.9784 | 37.4167 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0385 | 0.0804 | 0.0436 | 0.0631 | 0.0262 | 0.1018 | 17.4597 | 1.0146 | 1.3063 | 92.0000 | 67.0769 |
| ModernTCN | downhill_transition | 0.0137 | 0.0329 | 0.0213 | 0.0582 | 0.0217 | 0.2740 | 6.9336 | 0.9538 | 1.2534 | 95.0769 | 27.1538 |
| ModernTCN | uphill_return | 0.0390 | 0.0781 | 0.0265 | 0.0626 | 0.0166 | 0.0694 | 8.5051 | 1.1774 | 1.5549 | 93.2000 | 8.5000 |
| ModernTCN | flat_recovery | 0.0250 | 0.0467 | 0.0410 | 0.0421 | 0.0375 | 0.1060 | 40.8740 | 1.2135 | 1.0184 | 94.8000 | 13.6000 |
| GRU | all | 0.0222 | 0.0494 | 0.0211 | 0.0424 | 0.0158 | 0.3051 | 0.8105 | 0.9006 | 1.1047 | 85.7734 | 61.4112 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2177 | 0.0000 | 0.0002637 | 101.8909 | 0.3861 | 0.2098 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0106 | 0.0319 | 0.0260 | 0.0360 | 0.0123 | 0.1051 | 0.1450 | 0.9133 | 0.9577 | 85.6923 | 81.3846 |
| GRU | downhill_transition | 0.0244 | 0.0494 | 0.0145 | 0.0502 | 0.0147 | 0.3051 | 1.1464 | 1.0383 | 1.3167 | 91.9231 | 51.0000 |
| GRU | uphill_return | 0.0269 | 0.0461 | 0.0229 | 0.0446 | 0.0156 | 0.1297 | 1.1586 | 0.9584 | 1.3491 | 73.7000 | 64.5000 |
| GRU | flat_recovery | 0.0315 | 0.0475 | 0.0230 | 0.0338 | 0.0271 | 0.1235 | 0.5810 | 0.6129 | 0.8756 | 87.0000 | 11.2000 |
