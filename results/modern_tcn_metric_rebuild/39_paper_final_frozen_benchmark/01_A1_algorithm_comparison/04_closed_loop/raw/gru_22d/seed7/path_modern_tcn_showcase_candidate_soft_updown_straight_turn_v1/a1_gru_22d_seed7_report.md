# A1 GRU seed7 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed7_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed7\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed7_out.mat`
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
| ModernTCN | 0.0051 | 0.0160 | 0.0080 | 0.0105 | 0.0058 | 0.2764 | 243.3561 | 0.2607 | 0.3010 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 63.0697 |
| GRU | 0.2745 | 0.8210 | 0.1325 | 0.1371 | 0.0613 | 1.9091 | 720.0000 | 1.6560 | 631.8921 | 0.0000 | 1.7627 | 1.7628 | 99.5496 | 43.9560 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0219 | 0.0230 | 0.2444 | 0.0000 |
| GRU | 0.0087 | 0.0097 | 0.0112 | 0.0488 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 2.7743 | 2.5581 | 15.1504 | 4.6658 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0051 | 0.0160 | 0.0080 | 0.0105 | 0.0058 | 0.2607 | 0.3010 | 0.0167 | 0.0167 | 99.5496 | 63.0697 |
| ModernTCN | all | 0.0051 | 0.0160 | 0.0080 | 0.0528 | 0.0058 | 0.2607 | 5.2264 | 0.0376 | 0.0376 | 99.0179 | 63.4107 |
| GRU | all | 0.2745 | 0.8210 | 0.1325 | 0.1371 | 0.0613 | 1.6560 | 631.8921 | 1.7627 | 1.7628 | 99.5496 | 43.9560 |
| GRU | all | 0.2730 | 0.8210 | 0.1319 | 0.1455 | 0.0610 | 1.6560 | 631.2900 | 1.7684 | 1.7684 | 99.0179 | 44.4643 |
