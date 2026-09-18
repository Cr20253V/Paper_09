# A1 GRU seed202 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0059 | 0.0198 | 0.0083 | 0.0035 | 0.0054 | 0.2418 | 155.6001 | 0.2843 | 0.0241 | 0.0000 | 0.0000 | 0.0000 | 100.0000 | 31.1962 |
| GRU | 0.0803 | 0.3585 | 0.0595 | 0.0230 | 0.0334 | 1.0293 | 155.6001 | 1.6069 | 8.4150 | 0.0000 | 0.4217 | 0.4202 | 99.8945 | 47.0002 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0225 | 0.0243 | 0.0262 | 0.2608 | 0.0000 |
| GRU | 0.0104 | 0.0114 | 0.0147 | 0.0189 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.3694 | 0.0475 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0059 | 0.0198 | 0.0083 | 0.0035 | 0.0054 | 0.2843 | 0.0241 | 0.0000 | 0.0000 | 100.0000 | 31.1962 |
| ModernTCN | all | 0.0059 | 0.0198 | 0.0083 | 0.0267 | 0.0054 | 0.2843 | 1.5359 | 0.0000 | 0.0000 | 100.0000 | 31.3789 |
| GRU | all | 0.0803 | 0.3585 | 0.0595 | 0.0230 | 0.0334 | 1.6069 | 8.4150 | 0.4217 | 0.4202 | 99.8945 | 47.0002 |
| GRU | all | 0.0802 | 0.3585 | 0.0594 | 0.0350 | 0.0334 | 1.6069 | 9.9051 | 0.4205 | 0.4190 | 99.8947 | 47.1421 |
