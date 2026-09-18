# A1 GRU seed340 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\gru_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0060 | 0.0150 | 0.0079 | 0.0035 | 0.0050 | 0.2382 | 155.6001 | 0.2473 | 0.0202 | 0.0000 | 0.0000 | 0.0000 | 100.0000 | 42.8526 |
| GRU | 15.5021 | 32.0615 | 0.5906 | 0.6761 | 0.0392 | 43.8181 | 702.6552 | 1.6253 | 401.2652 | 0.0000 | 2.0823 | 2.0761 | 98.2639 | 53.7861 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0226 | 0.0244 | 0.0262 | 0.2649 | 0.0000 |
| GRU | 0.0108 | 0.0119 | 0.0151 | 0.0282 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 51.3113 | 47.7442 | 70.6453 | 63.2104 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0060 | 0.0150 | 0.0079 | 0.0035 | 0.0050 | 0.2473 | 0.0202 | 0.0000 | 0.0000 | 100.0000 | 42.8526 |
| ModernTCN | all | 0.0060 | 0.0150 | 0.0079 | 0.0267 | 0.0050 | 0.2473 | 1.5320 | 0.0000 | 0.0000 | 100.0000 | 43.0000 |
| GRU | all | 15.5021 | 32.0615 | 0.5906 | 0.6761 | 0.0392 | 1.6253 | 401.2652 | 2.0823 | 2.0761 | 98.2639 | 53.7861 |
| GRU | all | 15.4803 | 32.0615 | 0.5898 | 0.6757 | 0.0392 | 1.6253 | 401.7420 | 2.0768 | 2.0706 | 98.2684 | 53.9053 |
