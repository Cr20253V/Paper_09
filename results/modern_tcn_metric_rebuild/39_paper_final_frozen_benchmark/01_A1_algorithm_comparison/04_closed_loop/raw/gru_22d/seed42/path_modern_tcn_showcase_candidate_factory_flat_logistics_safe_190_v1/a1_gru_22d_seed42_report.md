# A1 GRU seed42 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed42_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed42\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\gru_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 5.0000 | 4.0000 | 15.0000 | 1.0000 |
| GRU | 12.0000 | 4.0000 | 8.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0128 | 0.0801 | 0.0102 | 0.0035 | 0.0082 | 0.2454 | 155.6001 | 0.4913 | 0.0254 | 0.0000 | 0.0000 | 0.0000 | 97.7363 | 35.9559 |
| GRU | 8.0458 | 20.8976 | 0.6741 | 0.5588 | 0.0730 | 21.8714 | 720.0000 | 1.6560 | 772.3974 | 0.0000 | 0.4041 | 0.4040 | 99.3615 | 48.4671 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0225 | 0.0244 | 0.0262 | 0.2663 | 0.0000 |
| GRU | 0.0109 | 0.0120 | 0.0130 | 0.0840 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 40.1351 | 39.8079 | 59.0312 | 45.7021 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0128 | 0.0801 | 0.0102 | 0.0035 | 0.0082 | 0.4913 | 0.0254 | 0.0000 | 0.0000 | 97.7363 | 35.9559 |
| ModernTCN | all | 0.0128 | 0.0801 | 0.0101 | 0.0267 | 0.0082 | 0.4913 | 1.5371 | 0.0000 | 0.0000 | 97.7421 | 36.1211 |
| GRU | all | 8.0458 | 20.8976 | 0.6741 | 0.5588 | 0.0730 | 1.6560 | 772.3974 | 0.4041 | 0.4040 | 99.3615 | 48.4671 |
| GRU | all | 8.0340 | 20.8976 | 0.6732 | 0.5587 | 0.0729 | 1.6560 | 771.9171 | 0.4030 | 0.4030 | 99.3632 | 48.6000 |
