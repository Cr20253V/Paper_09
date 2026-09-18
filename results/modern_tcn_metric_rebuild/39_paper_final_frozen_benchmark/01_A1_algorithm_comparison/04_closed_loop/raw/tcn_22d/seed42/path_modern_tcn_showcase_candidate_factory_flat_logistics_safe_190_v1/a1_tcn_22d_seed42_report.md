# A1 TCN seed42 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed42_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed42\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\tcn_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 7.0000 | 6.0000 | 5.0000 | 18.0000 | 1.0000 |
| ModernTCN | 11.0000 | 3.0000 | 7.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0128 | 0.0801 | 0.0102 | 0.0035 | 0.0082 | 0.2454 | 155.6001 | 0.4913 | 0.0254 | 0.0000 | 0.0000 | 0.0000 | 97.7363 | 35.9559 |
| TCN | 0.0055 | 0.0218 | 0.0080 | 0.0035 | 0.0052 | 0.2373 | 155.6001 | 0.2326 | 0.0199 | 0.0000 | 0.8559 | 0.0000 | 88.0059 | 30.9535 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0225 | 0.0244 | 0.0262 | 0.2663 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0134 | 0.0646 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0128 | 0.0801 | 0.0102 | 0.0035 | 0.0082 | 0.4913 | 0.0254 | 0.0000 | 0.0000 | 97.7363 | 35.9559 |
| ModernTCN | all | 0.0128 | 0.0801 | 0.0101 | 0.0267 | 0.0082 | 0.4913 | 1.5371 | 0.0000 | 0.0000 | 97.7421 | 36.1211 |
| TCN | all | 0.0055 | 0.0218 | 0.0080 | 0.0035 | 0.0052 | 0.2326 | 0.0199 | 0.8559 | 0.0000 | 88.0059 | 30.9535 |
| TCN | all | 0.0055 | 0.0218 | 0.0080 | 0.0267 | 0.0052 | 0.2326 | 1.5316 | 0.8537 | 0.0000 | 88.0368 | 31.1368 |
