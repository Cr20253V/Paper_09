# A1 TCN seed11 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed11_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed11\path_factory_target_downhill_straight_after_turn_v1\tcn_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0125 | 0.0283 | 0.0119 | 0.0261 | 0.0032 | 0.1589 | 228.7386 | 0.1298 | 0.7848 | 0.0000 | 0.5133 | 0.6212 | 97.4140 | 81.0184 |
| TCN | 0.0287 | 0.0622 | 0.0426 | 0.0530 | 0.0057 | 0.8352 | 231.0530 | 0.1649 | 0.4889 | 0.0000 | 1.3472 | 1.2730 | 93.4151 | 76.8062 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0250 | 0.0273 | 0.2641 | 0.0000 |
| TCN | 0.0095 | 0.0114 | 0.0137 | 0.0648 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0125 | 0.0283 | 0.0119 | 0.0261 | 0.0032 | 0.1298 | 0.7848 | 0.5133 | 0.6212 | 97.4140 | 81.0184 |
| ModernTCN | all | 0.0125 | 0.0283 | 0.0119 | 0.0690 | 0.0032 | 0.1298 | 9.5957 | 0.5070 | 0.6135 | 97.4474 | 81.2632 |
| TCN | all | 0.0287 | 0.0622 | 0.0426 | 0.0530 | 0.0057 | 0.1649 | 0.4889 | 1.3472 | 1.2730 | 93.4151 | 76.8062 |
| TCN | all | 0.0285 | 0.0622 | 0.0423 | 0.0829 | 0.0057 | 0.1649 | 9.3036 | 1.3296 | 1.2569 | 93.5000 | 77.1316 |
