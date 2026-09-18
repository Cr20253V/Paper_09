# A1 GRU seed73 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed73_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed73\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\gru_22d_seed73_out.mat`
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
| ModernTCN | 0.0178 | 0.0805 | 0.0109 | 0.0035 | 0.0090 | 0.2458 | 155.6001 | 0.2793 | 0.0219 | 0.0000 | 0.0403 | 0.0000 | 99.2085 | 40.9213 |
| GRU | 3.8911 | 11.3027 | 0.4656 | 0.4058 | 0.0691 | 8.8387 | 720.0000 | 1.6560 | 457.1278 | 0.0000 | 0.6542 | 0.6546 | 91.8579 | 45.7390 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0226 | 0.0245 | 0.0264 | 0.2791 | 0.0000 |
| GRU | 0.0107 | 0.0124 | 0.0155 | 0.0918 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 21.3762 | 21.0226 | 27.7136 | 19.2866 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0178 | 0.0805 | 0.0109 | 0.0035 | 0.0090 | 0.2793 | 0.0219 | 0.0403 | 0.0000 | 99.2085 | 40.9213 |
| ModernTCN | all | 0.0177 | 0.0805 | 0.0108 | 0.0267 | 0.0090 | 0.2793 | 1.5336 | 0.0402 | 0.0000 | 99.2105 | 41.0789 |
| GRU | all | 3.8911 | 11.3027 | 0.4656 | 0.4058 | 0.0691 | 1.6560 | 457.1278 | 0.6542 | 0.6546 | 91.8579 | 45.7390 |
| GRU | all | 3.8853 | 11.3027 | 0.4649 | 0.4061 | 0.0690 | 1.6560 | 457.4606 | 0.6525 | 0.6529 | 91.8789 | 45.8842 |
