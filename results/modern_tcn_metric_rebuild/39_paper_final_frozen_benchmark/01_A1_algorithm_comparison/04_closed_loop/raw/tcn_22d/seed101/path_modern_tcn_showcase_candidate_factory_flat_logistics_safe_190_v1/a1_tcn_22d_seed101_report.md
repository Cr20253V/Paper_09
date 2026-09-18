# A1 TCN seed101 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed101_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed101\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\tcn_22d_seed101_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 10.0000 | 4.0000 | 5.0000 | 19.0000 | 1.0000 |
| TCN | 8.0000 | 5.0000 | 7.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0069 | 0.0317 | 0.0088 | 0.0035 | 0.0067 | 0.2426 | 155.6001 | 0.2767 | 0.0224 | 0.0000 | 0.0000 | 0.0000 | 99.8364 | 39.2380 |
| TCN | 0.0094 | 0.0306 | 0.0077 | 0.0035 | 0.0061 | 0.2361 | 155.6001 | 0.3518 | 0.0342 | 0.0000 | 1.6419 | 0.0000 | 63.6378 | 42.9793 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0225 | 0.0244 | 0.0264 | 0.2720 | 0.0000 |
| TCN | 0.0096 | 0.0105 | 0.0133 | 0.0709 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0069 | 0.0317 | 0.0088 | 0.0035 | 0.0067 | 0.2767 | 0.0224 | 0.0000 | 0.0000 | 99.8364 | 39.2380 |
| ModernTCN | all | 0.0069 | 0.0317 | 0.0088 | 0.0267 | 0.0067 | 0.2767 | 1.5341 | 0.0000 | 0.0000 | 99.8368 | 39.3947 |
| TCN | all | 0.0094 | 0.0306 | 0.0077 | 0.0035 | 0.0061 | 0.3518 | 0.0342 | 1.6419 | 0.0000 | 63.6378 | 42.9793 |
| TCN | all | 0.0094 | 0.0306 | 0.0077 | 0.0267 | 0.0061 | 0.3518 | 1.5459 | 1.6375 | 0.0000 | 63.7316 | 43.1316 |
