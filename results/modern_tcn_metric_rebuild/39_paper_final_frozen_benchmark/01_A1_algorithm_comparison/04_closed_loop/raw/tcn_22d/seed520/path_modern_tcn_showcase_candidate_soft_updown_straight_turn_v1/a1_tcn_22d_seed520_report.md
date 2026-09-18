# A1 TCN seed520 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 11.0000 | 3.0000 | 5.0000 | 19.0000 | 1.0000 |
| TCN | 7.0000 | 6.0000 | 7.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0040 | 0.0112 | 0.0081 | 0.0105 | 0.0066 | 0.2765 | 243.3561 | 0.2905 | 0.3034 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 63.8624 |
| TCN | 0.0031 | 0.0112 | 0.0076 | 0.0105 | 0.0072 | 0.2762 | 243.3561 | 0.3306 | 0.3071 | 0.0000 | 0.9936 | 0.0167 | 73.7525 | 48.1535 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0204 | 0.0220 | 0.0235 | 0.2392 | 0.0000 |
| TCN | 0.0086 | 0.0092 | 0.0098 | 0.0547 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0040 | 0.0112 | 0.0081 | 0.0105 | 0.0066 | 0.2905 | 0.3034 | 0.0167 | 0.0167 | 99.5496 | 63.8624 |
| ModernTCN | all | 0.0040 | 0.0112 | 0.0081 | 0.0528 | 0.0066 | 0.2905 | 5.2288 | 0.0376 | 0.0376 | 99.0179 | 64.1964 |
| TCN | all | 0.0031 | 0.0112 | 0.0076 | 0.0105 | 0.0072 | 0.3306 | 0.3071 | 0.9936 | 0.0167 | 73.7525 | 48.1535 |
| TCN | all | 0.0030 | 0.0112 | 0.0076 | 0.0528 | 0.0072 | 0.3306 | 5.2325 | 1.0057 | 0.0376 | 73.4464 | 48.6250 |
