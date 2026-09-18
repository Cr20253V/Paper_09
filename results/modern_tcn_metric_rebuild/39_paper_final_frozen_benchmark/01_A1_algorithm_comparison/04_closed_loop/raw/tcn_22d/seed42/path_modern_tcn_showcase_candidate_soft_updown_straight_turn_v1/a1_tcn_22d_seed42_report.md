# A1 TCN seed42 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed42_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed42\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\tcn_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 8.0000 | 3.0000 | 5.0000 | 16.0000 | 1.0000 |
| TCN | 10.0000 | 6.0000 | 7.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0029 | 0.0101 | 0.0074 | 0.0105 | 0.0051 | 0.2763 | 243.3561 | 0.2680 | 0.3012 | 0.0000 | 0.0167 | 0.0167 | 97.0636 | 69.1227 |
| TCN | 0.0053 | 0.0148 | 0.0073 | 0.0105 | 0.0068 | 0.2755 | 243.3561 | 0.3346 | 0.3066 | 0.0000 | 0.7641 | 0.0167 | 67.4293 | 45.5053 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0223 | 0.0242 | 0.0257 | 0.2654 | 0.0000 |
| TCN | 0.0096 | 0.0103 | 0.0129 | 0.0627 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0029 | 0.0101 | 0.0074 | 0.0105 | 0.0051 | 0.2680 | 0.3012 | 0.0167 | 0.0167 | 97.0636 | 69.1227 |
| ModernTCN | all | 0.0029 | 0.0101 | 0.0074 | 0.0528 | 0.0051 | 0.2680 | 5.2266 | 0.0376 | 0.0376 | 96.5536 | 69.3929 |
| TCN | all | 0.0053 | 0.0148 | 0.0073 | 0.0105 | 0.0068 | 0.3346 | 0.3066 | 0.7641 | 0.0167 | 67.4293 | 45.5053 |
| TCN | all | 0.0053 | 0.0148 | 0.0073 | 0.0528 | 0.0068 | 0.3346 | 5.2319 | 0.7783 | 0.0376 | 67.1786 | 46.0000 |
