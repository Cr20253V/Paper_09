# A1 TCN seed11 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed11_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed11\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\tcn_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 6.0000 | 6.0000 | 5.0000 | 17.0000 | 1.0000 |
| ModernTCN | 12.0000 | 3.0000 | 7.0000 | 22.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0160 | 0.0695 | 0.0088 | 0.0035 | 0.0070 | 0.2369 | 155.6001 | 0.3091 | 0.0220 | 0.0000 | 0.0000 | 0.0000 | 100.0000 | 44.7100 |
| TCN | 0.0076 | 0.0243 | 0.0077 | 0.0035 | 0.0047 | 0.2343 | 155.6001 | 0.1360 | 0.0188 | 0.0000 | 2.1357 | 0.0000 | 1.3561 | 28.7689 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0215 | 0.0224 | 0.2467 | 0.0000 |
| TCN | 0.0096 | 0.0109 | 0.0138 | 0.0601 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0160 | 0.0695 | 0.0088 | 0.0035 | 0.0070 | 0.3091 | 0.0220 | 0.0000 | 0.0000 | 100.0000 | 44.7100 |
| ModernTCN | all | 0.0160 | 0.0695 | 0.0088 | 0.0267 | 0.0070 | 0.3091 | 1.5337 | 0.0000 | 0.0000 | 100.0000 | 44.8526 |
| TCN | all | 0.0076 | 0.0243 | 0.0077 | 0.0035 | 0.0047 | 0.1360 | 0.0188 | 2.1357 | 0.0000 | 1.3561 | 28.7689 |
| TCN | all | 0.0076 | 0.0243 | 0.0077 | 0.0267 | 0.0047 | 0.1360 | 1.5306 | 2.1301 | 0.0000 | 1.6158 | 28.9579 |
