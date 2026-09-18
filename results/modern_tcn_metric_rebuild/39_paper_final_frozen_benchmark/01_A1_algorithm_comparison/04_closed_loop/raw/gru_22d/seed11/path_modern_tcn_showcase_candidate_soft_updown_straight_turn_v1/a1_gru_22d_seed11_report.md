# A1 GRU seed11 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed11_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed11\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed11_out.mat`
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
| ModernTCN | 0.0053 | 0.0150 | 0.0078 | 0.0105 | 0.0056 | 0.2763 | 243.3561 | 0.2687 | 0.3011 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 66.1142 |
| GRU | 0.1531 | 0.5263 | 0.0785 | 0.0749 | 0.0523 | 1.3689 | 719.9908 | 1.6559 | 484.0008 | 0.0000 | 1.3023 | 1.3021 | 99.5496 | 46.1358 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0206 | 0.0221 | 0.0232 | 0.2368 | 0.0000 |
| GRU | 0.0102 | 0.0284 | 0.0428 | 0.0890 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 1.0809 | 1.0629 | 5.1342 | 1.9636 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0053 | 0.0150 | 0.0078 | 0.0105 | 0.0056 | 0.2687 | 0.3011 | 0.0167 | 0.0167 | 99.5496 | 66.1142 |
| ModernTCN | all | 0.0053 | 0.0150 | 0.0078 | 0.0528 | 0.0055 | 0.2687 | 5.2265 | 0.0376 | 0.0376 | 99.0179 | 66.4286 |
| GRU | all | 0.1531 | 0.5263 | 0.0785 | 0.0749 | 0.0523 | 1.6559 | 484.0008 | 1.3023 | 1.3021 | 99.5496 | 46.1358 |
| GRU | all | 0.1524 | 0.5263 | 0.0781 | 0.0908 | 0.0521 | 1.6559 | 484.6914 | 1.3120 | 1.3118 | 99.0179 | 46.6250 |
