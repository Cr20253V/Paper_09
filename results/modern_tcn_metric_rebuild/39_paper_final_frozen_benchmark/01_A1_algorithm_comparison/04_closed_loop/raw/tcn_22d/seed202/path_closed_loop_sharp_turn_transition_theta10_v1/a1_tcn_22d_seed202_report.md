# A1 TCN seed202 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed202_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed202\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0412 | 0.1019 | 0.0304 | 0.0355 | 0.0139 | 0.4082 | 223.7643 | 0.5102 | 2.8675 | 0.0000 | 0.5915 | 0.7300 | 89.5943 | 51.0775 |
| TCN | 0.5327 | 1.4626 | 0.1454 | 0.1195 | 0.0662 | 1.9201 | 718.4837 | 1.6560 | 889.1322 | 0.0000 | 0.7645 | 1.8144 | 79.1497 | 48.9031 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0217 | 0.0227 | 0.2432 | 0.0000 |
| TCN | 0.0091 | 0.0099 | 0.0116 | 0.0577 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 2.3491 | 2.2520 | 12.5607 | 1.7861 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0412 | 0.1019 | 0.0304 | 0.0355 | 0.0139 | 0.5102 | 2.8675 | 0.5915 | 0.7300 | 89.5943 | 51.0775 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0569 | 0.1019 | 0.0476 | 0.0388 | 0.0169 | 0.1929 | 1.6128 | 0.5903 | 0.7831 | 93.1667 | 58.6667 |
| ModernTCN | downhill_right_transition | 0.0299 | 0.0700 | 0.0167 | 0.0402 | 0.0139 | 0.5102 | 5.0899 | 0.8596 | 0.9931 | 94.7000 | 40.0500 |
| ModernTCN | flat_left_exit | 0.0335 | 0.0490 | 0.0118 | 0.0186 | 0.0098 | 0.2939 | 1.3782 | 0.2650 | 0.3645 | 69.3000 | 42.4000 |
| TCN | all | 0.5327 | 1.4626 | 0.1454 | 0.1195 | 0.0662 | 1.6560 | 889.1322 | 0.7645 | 1.8144 | 79.1497 | 48.9031 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.2079 | 0.0000 | 61.7500 | 100.0000 |
| TCN | uphill_left_transition | 0.1788 | 0.3506 | 0.1535 | 0.1175 | 0.0422 | 0.5074 | 472.3809 | 0.4928 | 2.6063 | 93.1667 | 80.0000 |
| TCN | downhill_right_transition | 0.4585 | 0.8643 | 0.1525 | 0.0952 | 0.0852 | 1.6560 | 1205 | 1.1242 | 1.9157 | 82.6000 | 13.4000 |
| TCN | flat_left_exit | 0.9907 | 1.4626 | 0.1410 | 0.1733 | 0.0698 | 1.4051 | 1305 | 0.7188 | 0.8231 | 55.1000 | 46.1000 |
