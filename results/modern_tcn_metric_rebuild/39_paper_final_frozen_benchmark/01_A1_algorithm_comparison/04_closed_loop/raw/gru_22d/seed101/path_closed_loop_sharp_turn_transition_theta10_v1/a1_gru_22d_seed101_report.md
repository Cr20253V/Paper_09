# A1 GRU seed101 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed101_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed101\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 7.0000 | 6.0000 | 5.0000 | 18.0000 | 1.0000 |
| GRU | 11.0000 | 3.0000 | 7.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0393 | 0.0825 | 0.0343 | 0.0373 | 0.0189 | 0.4633 | 224.2241 | 0.2873 | 2.2166 | 0.0000 | 0.6662 | 0.8059 | 90.2737 | 49.9515 |
| GRU | 0.0706 | 0.2074 | 0.0403 | 0.0396 | 0.0244 | 0.3246 | 223.5635 | 0.5382 | 5.7596 | 0.0000 | 0.6151 | 0.7133 | 92.9917 | 73.0926 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0217 | 0.0225 | 0.2365 | 0.0000 |
| GRU | 0.0104 | 0.0113 | 0.0147 | 0.0205 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0393 | 0.0825 | 0.0343 | 0.0373 | 0.0189 | 0.2873 | 2.2166 | 0.6662 | 0.8059 | 90.2737 | 49.9515 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0462 | 0.0825 | 0.0527 | 0.0406 | 0.0238 | 0.1334 | 0.7098 | 0.7168 | 0.8292 | 93.5556 | 60.1667 |
| ModernTCN | downhill_right_transition | 0.0164 | 0.0261 | 0.0197 | 0.0342 | 0.0182 | 0.1415 | 4.2909 | 0.6639 | 0.8690 | 96.3500 | 37.7000 |
| ModernTCN | flat_left_exit | 0.0598 | 0.0761 | 0.0170 | 0.0409 | 0.0123 | 0.2873 | 1.2476 | 0.8138 | 0.9204 | 68.8000 | 38.6000 |
| GRU | all | 0.0706 | 0.2074 | 0.0403 | 0.0396 | 0.0244 | 0.5382 | 5.7596 | 0.6151 | 0.7133 | 92.9917 | 73.0926 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1833 | 0.0000 | 0.0002457 | 66.5816 | 1.2893 | 1.0357 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0311 | 0.0595 | 0.0118 | 0.0323 | 0.0079 | 0.1668 | 0.0751 | 0.5173 | 0.5660 | 94.7778 | 82.0000 |
| GRU | downhill_right_transition | 0.1043 | 0.2074 | 0.0561 | 0.0455 | 0.0277 | 0.4280 | 14.4134 | 0.6424 | 0.8394 | 95.1500 | 72.1000 |
| GRU | flat_left_exit | 0.0465 | 0.0926 | 0.0428 | 0.0265 | 0.0376 | 0.5382 | 0.3092 | 0.4366 | 0.5623 | 83.0000 | 49.7000 |
