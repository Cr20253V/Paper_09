# A1 GRU seed340 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 7.0000 | 5.0000 | 6.0000 | 18.0000 | 1.0000 |
| GRU | 11.0000 | 4.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0145 | 0.0328 | 0.0131 | 0.0297 | 0.0033 | 0.1878 | 232.8208 | 0.1271 | 0.7758 | 0.0000 | 0.6018 | 0.7051 | 97.6540 | 66.6756 |
| GRU | 0.0149 | 0.0367 | 0.0142 | 0.0311 | 0.0032 | 0.1974 | 229.4164 | 0.1347 | 0.3604 | 0.0000 | 0.5863 | 0.6608 | 95.2279 | 86.9901 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0252 | 0.0273 | 0.2684 | 0.0000 |
| GRU | 0.0107 | 0.0118 | 0.0148 | 0.0194 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0145 | 0.0328 | 0.0131 | 0.0297 | 0.0033 | 0.1271 | 0.7758 | 0.6018 | 0.7051 | 97.6540 | 66.6756 |
| ModernTCN | all | 0.0144 | 0.0328 | 0.0130 | 0.0704 | 0.0033 | 0.1271 | 9.5868 | 0.5944 | 0.6963 | 97.6842 | 67.1053 |
| GRU | all | 0.0149 | 0.0367 | 0.0142 | 0.0311 | 0.0032 | 0.1347 | 0.3604 | 0.5863 | 0.6608 | 95.2279 | 86.9901 |
| GRU | all | 0.0148 | 0.0367 | 0.0141 | 0.0710 | 0.0032 | 0.1347 | 9.1768 | 0.5783 | 0.6519 | 95.2895 | 87.1842 |
