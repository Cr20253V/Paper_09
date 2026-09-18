# A1 GRU seed101 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed101_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed101\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| GRU | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0034 | 0.0113 | 0.0083 | 0.0105 | 0.0072 | 0.2764 | 243.3561 | 0.2909 | 0.3035 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 66.0782 |
| GRU | 0.2922 | 1.2381 | 0.1425 | 0.0772 | 0.0578 | 1.8566 | 720.0000 | 1.6511 | 655.2971 | 0.0000 | 1.7033 | 1.7000 | 97.4059 | 47.3068 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0217 | 0.0240 | 0.0258 | 0.2606 | 0.0000 |
| GRU | 0.0105 | 0.0122 | 0.0153 | 0.0646 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.1801 | 0.1261 | 14.0695 | 2.8643 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0034 | 0.0113 | 0.0083 | 0.0105 | 0.0072 | 0.2909 | 0.3035 | 0.0167 | 0.0167 | 99.5496 | 66.0782 |
| ModernTCN | all | 0.0034 | 0.0113 | 0.0083 | 0.0528 | 0.0072 | 0.2909 | 5.2288 | 0.0376 | 0.0376 | 99.0179 | 66.3929 |
| GRU | all | 0.2922 | 1.2381 | 0.1425 | 0.0772 | 0.0578 | 1.6511 | 655.2971 | 1.7033 | 1.7000 | 97.4059 | 47.3068 |
| GRU | all | 0.2905 | 1.2370 | 0.1418 | 0.0927 | 0.0574 | 1.6511 | 625.9137 | 1.7095 | 1.7061 | 96.9107 | 47.7857 |
