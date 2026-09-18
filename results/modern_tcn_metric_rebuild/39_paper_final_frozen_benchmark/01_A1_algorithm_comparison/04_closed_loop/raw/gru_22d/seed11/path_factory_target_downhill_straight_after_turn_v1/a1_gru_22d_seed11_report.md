# A1 GRU seed11 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed11_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed11\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| GRU | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0125 | 0.0283 | 0.0119 | 0.0261 | 0.0032 | 0.1589 | 228.7386 | 0.1298 | 0.7848 | 0.0000 | 0.5133 | 0.6212 | 97.4140 | 81.0184 |
| GRU | 0.0180 | 0.0399 | 0.0262 | 0.0360 | 0.0042 | 0.4942 | 229.1532 | 0.1385 | 0.2736 | 0.0000 | 0.8530 | 0.9148 | 95.2279 | 48.6270 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0250 | 0.0273 | 0.2641 | 0.0000 |
| GRU | 0.0104 | 0.0169 | 0.0195 | 0.0269 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0125 | 0.0283 | 0.0119 | 0.0261 | 0.0032 | 0.1298 | 0.7848 | 0.5133 | 0.6212 | 97.4140 | 81.0184 |
| ModernTCN | all | 0.0125 | 0.0283 | 0.0119 | 0.0690 | 0.0032 | 0.1298 | 9.5957 | 0.5070 | 0.6135 | 97.4474 | 81.2632 |
| GRU | all | 0.0180 | 0.0399 | 0.0262 | 0.0360 | 0.0042 | 0.1385 | 0.2736 | 0.8530 | 0.9148 | 95.2279 | 48.6270 |
| GRU | all | 0.0179 | 0.0399 | 0.0260 | 0.0733 | 0.0041 | 0.1385 | 9.0911 | 0.8418 | 0.9029 | 95.2895 | 49.2895 |
