# A1 GRU seed21 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed21_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed21\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed21_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 8.0000 | 5.0000 | 5.0000 | 18.0000 | 1.0000 |
| GRU | 10.0000 | 4.0000 | 7.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0370 | 0.1035 | 0.0306 | 0.0369 | 0.0146 | 0.3998 | 224.8742 | 0.4246 | 2.1333 | 0.0000 | 0.5973 | 0.6742 | 94.3506 | 72.7432 |
| GRU | 0.0632 | 0.1784 | 0.0380 | 0.0362 | 0.0241 | 0.2949 | 223.3806 | 0.6011 | 5.2112 | 0.0000 | 0.5150 | 0.6097 | 93.2440 | 78.1984 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0199 | 0.0215 | 0.0224 | 0.2405 | 0.0000 |
| GRU | 0.0102 | 0.0112 | 0.0123 | 0.1681 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0370 | 0.1035 | 0.0306 | 0.0369 | 0.0146 | 0.4246 | 2.1333 | 0.5973 | 0.6742 | 94.3506 | 72.7432 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0565 | 0.1035 | 0.0470 | 0.0398 | 0.0180 | 0.1628 | 1.1938 | 0.5818 | 0.7188 | 91.8889 | 86.8889 |
| ModernTCN | downhill_right_transition | 0.0145 | 0.0286 | 0.0141 | 0.0404 | 0.0127 | 0.1513 | 3.4824 | 0.7283 | 0.9076 | 95.4000 | 70.2000 |
| ModernTCN | flat_left_exit | 0.0295 | 0.0465 | 0.0211 | 0.0262 | 0.0137 | 0.4246 | 1.5645 | 0.5729 | 0.3640 | 94.7000 | 42.9000 |
| GRU | all | 0.0632 | 0.1784 | 0.0380 | 0.0362 | 0.0241 | 0.6011 | 5.2112 | 0.5150 | 0.6097 | 93.2440 | 78.1984 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1813 | 0.0000 | 0.0002457 | 66.5234 | 1.0960 | 0.8807 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0297 | 0.0567 | 0.0086 | 0.0268 | 0.0071 | 0.1639 | 0.0714 | 0.3890 | 0.4075 | 95.0556 | 83.5556 |
| GRU | downhill_right_transition | 0.0882 | 0.1784 | 0.0510 | 0.0461 | 0.0281 | 0.3957 | 13.0712 | 0.6672 | 0.8724 | 94.1500 | 83.8500 |
| GRU | flat_left_exit | 0.0588 | 0.0899 | 0.0458 | 0.0124 | 0.0363 | 0.6011 | 0.1993 | 0.1798 | 0.3100 | 85.8000 | 49.7000 |
