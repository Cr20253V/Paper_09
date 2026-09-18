# A1 GRU seed202 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| ModernTCN | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0412 | 0.1019 | 0.0304 | 0.0355 | 0.0139 | 0.4082 | 223.7643 | 0.5102 | 2.8675 | 0.0000 | 0.5915 | 0.7300 | 89.5943 | 51.0775 |
| GRU | 0.0351 | 0.0907 | 0.0176 | 0.0290 | 0.0094 | 0.2070 | 222.2253 | 0.2182 | 0.4124 | 0.0000 | 0.4618 | 0.5891 | 92.7004 | 74.5098 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0217 | 0.0227 | 0.2432 | 0.0000 |
| GRU | 0.0104 | 0.0113 | 0.0143 | 0.0197 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0412 | 0.1019 | 0.0304 | 0.0355 | 0.0139 | 0.5102 | 2.8675 | 0.5915 | 0.7300 | 89.5943 | 51.0775 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0569 | 0.1019 | 0.0476 | 0.0388 | 0.0169 | 0.1929 | 1.6128 | 0.5903 | 0.7831 | 93.1667 | 58.6667 |
| ModernTCN | downhill_right_transition | 0.0299 | 0.0700 | 0.0167 | 0.0402 | 0.0139 | 0.5102 | 5.0899 | 0.8596 | 0.9931 | 94.7000 | 40.0500 |
| ModernTCN | flat_left_exit | 0.0335 | 0.0490 | 0.0118 | 0.0186 | 0.0098 | 0.2939 | 1.3782 | 0.2650 | 0.3645 | 69.3000 | 42.4000 |
| GRU | all | 0.0351 | 0.0907 | 0.0176 | 0.0290 | 0.0094 | 0.2182 | 0.4124 | 0.4618 | 0.5891 | 92.7004 | 74.5098 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1756 | 0.0000 | 0.0002457 | 66.3656 | 0.2046 | 0.1532 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0105 | 0.0271 | 0.0219 | 0.0165 | 0.0111 | 0.1422 | 0.0838 | 0.3358 | 0.3812 | 93.6667 | 87.1667 |
| GRU | downhill_right_transition | 0.0291 | 0.0629 | 0.0165 | 0.0323 | 0.0100 | 0.2182 | 0.5998 | 0.4911 | 0.6893 | 95.5000 | 66.4000 |
| GRU | flat_left_exit | 0.0667 | 0.0907 | 0.0140 | 0.0389 | 0.0059 | 0.1588 | 0.4575 | 0.7102 | 0.9085 | 82.8000 | 59.1000 |
