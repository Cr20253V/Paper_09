# A1 TCN seed520 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 11.0000 | 3.0000 | 5.0000 | 19.0000 | 1.0000 |
| TCN | 7.0000 | 6.0000 | 7.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0113 | 0.0299 | 0.0084 | 0.0035 | 0.0050 | 0.2515 | 155.6001 | 0.3179 | 0.0224 | 0.0000 | 0.0000 | 0.0000 | 100.0000 | 50.4987 |
| TCN | 0.0073 | 0.0262 | 0.0079 | 0.0035 | 0.0054 | 0.2341 | 155.6001 | 0.4207 | 0.0386 | 0.0000 | 1.0586 | 0.0000 | 78.1595 | 47.8128 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0226 | 0.0244 | 0.0263 | 0.2691 | 0.0000 |
| TCN | 0.0086 | 0.0092 | 0.0098 | 0.0529 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0113 | 0.0299 | 0.0084 | 0.0035 | 0.0050 | 0.3179 | 0.0224 | 0.0000 | 0.0000 | 100.0000 | 50.4987 |
| ModernTCN | all | 0.0113 | 0.0299 | 0.0083 | 0.0267 | 0.0050 | 0.3179 | 1.5341 | 0.0000 | 0.0000 | 100.0000 | 50.6263 |
| TCN | all | 0.0073 | 0.0262 | 0.0079 | 0.0035 | 0.0054 | 0.4207 | 0.0386 | 1.0586 | 0.0000 | 78.1595 | 47.8128 |
| TCN | all | 0.0072 | 0.0262 | 0.0079 | 0.0267 | 0.0054 | 0.4207 | 1.5503 | 1.0558 | 0.0000 | 78.2158 | 47.9526 |
