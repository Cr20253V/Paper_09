# A1 GRU seed340 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed340_out.mat`
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
| ModernTCN | 0.0026 | 0.0087 | 0.0075 | 0.0105 | 0.0056 | 0.2764 | 243.3561 | 0.2681 | 0.3006 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 69.2128 |
| GRU | 0.2991 | 0.9340 | 0.1455 | 0.1335 | 0.0635 | 2.0485 | 720.0000 | 1.6560 | 818.6192 | 0.0000 | 1.8628 | 1.8610 | 98.9912 | 46.2259 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0221 | 0.0236 | 0.2372 | 0.0000 |
| GRU | 0.0105 | 0.0124 | 0.0156 | 0.0587 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 2.4680 | 2.4500 | 16.0872 | 5.1342 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0026 | 0.0087 | 0.0075 | 0.0105 | 0.0056 | 0.2681 | 0.3006 | 0.0167 | 0.0167 | 99.5496 | 69.2128 |
| ModernTCN | all | 0.0025 | 0.0087 | 0.0075 | 0.0528 | 0.0055 | 0.2681 | 5.2260 | 0.0376 | 0.0376 | 99.0179 | 69.4821 |
| GRU | all | 0.2991 | 0.9340 | 0.1455 | 0.1335 | 0.0635 | 1.6560 | 818.6192 | 1.8628 | 1.8610 | 98.9912 | 46.2259 |
| GRU | all | 0.2976 | 0.9340 | 0.1449 | 0.1422 | 0.0632 | 1.6560 | 816.3828 | 1.8675 | 1.8658 | 98.4643 | 46.6964 |
