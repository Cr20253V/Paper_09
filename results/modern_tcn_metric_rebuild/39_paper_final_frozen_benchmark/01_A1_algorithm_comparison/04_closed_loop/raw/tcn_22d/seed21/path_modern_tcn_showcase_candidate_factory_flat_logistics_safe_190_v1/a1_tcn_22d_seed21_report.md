# A1 TCN seed21 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed21_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed21\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\tcn_22d_seed21_out.mat`
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
| ModernTCN | 0.0128 | 0.0701 | 0.0091 | 0.0035 | 0.0055 | 0.2411 | 155.6001 | 0.4353 | 0.0207 | 0.0000 | 0.2895 | 0.0000 | 98.6333 | 43.4014 |
| TCN | 0.0089 | 0.0234 | 0.0078 | 0.0035 | 0.0060 | 0.2335 | 155.6001 | 0.2099 | 0.0190 | 0.0000 | 0.8091 | 0.0000 | 1.5830 | 37.7447 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0202 | 0.0232 | 0.0264 | 0.2492 | 0.0000 |
| TCN | 0.0096 | 0.0104 | 0.0135 | 0.0619 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0128 | 0.0701 | 0.0091 | 0.0035 | 0.0055 | 0.4353 | 0.0207 | 0.2895 | 0.0000 | 98.6333 | 43.4014 |
| ModernTCN | all | 0.0128 | 0.0701 | 0.0091 | 0.0267 | 0.0055 | 0.4353 | 1.5325 | 0.2887 | 0.0000 | 98.6368 | 43.5474 |
| TCN | all | 0.0089 | 0.0234 | 0.0078 | 0.0035 | 0.0060 | 0.2099 | 0.0190 | 0.8091 | 0.0000 | 1.5830 | 37.7447 |
| TCN | all | 0.0089 | 0.0234 | 0.0078 | 0.0267 | 0.0060 | 0.2099 | 1.5308 | 0.8069 | 0.0000 | 1.8421 | 37.9105 |
