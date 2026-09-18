# A1 GRU seed1 path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\modern_fixed_seed1_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed1\path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1\gru_22d_seed1_out.mat`
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
| ModernTCN | 0.0055 | 0.0128 | 0.0078 | 0.0035 | 0.0039 | 0.2354 | 155.6001 | 0.2074 | 0.0192 | 0.0000 | 0.0232 | 0.0000 | 100.0000 | 44.0241 |
| GRU | 0.1628 | 0.4272 | 0.1057 | 0.0376 | 0.0650 | 1.3908 | 720.0000 | 1.6424 | 487.6011 | 0.0000 | 0.5668 | 0.5667 | 98.8075 | 50.2929 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0216 | 0.0226 | 0.2417 | 0.0000 |
| GRU | 0.0088 | 0.0096 | 0.0104 | 0.1129 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.2269 | 0.2111 | 2.4484 | 0.3430 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0055 | 0.0128 | 0.0078 | 0.0035 | 0.0039 | 0.2074 | 0.0192 | 0.0232 | 0.0000 | 100.0000 | 44.0241 |
| ModernTCN | all | 0.0055 | 0.0128 | 0.0078 | 0.0267 | 0.0039 | 0.2074 | 1.5309 | 0.0232 | 0.0000 | 100.0000 | 44.1684 |
| GRU | all | 0.1628 | 0.4272 | 0.1057 | 0.0376 | 0.0650 | 1.6424 | 487.6011 | 0.5668 | 0.5667 | 98.8075 | 50.2929 |
| GRU | all | 0.1626 | 0.4272 | 0.1055 | 0.0460 | 0.0649 | 1.6424 | 487.8554 | 0.5653 | 0.5652 | 98.8105 | 50.4263 |
