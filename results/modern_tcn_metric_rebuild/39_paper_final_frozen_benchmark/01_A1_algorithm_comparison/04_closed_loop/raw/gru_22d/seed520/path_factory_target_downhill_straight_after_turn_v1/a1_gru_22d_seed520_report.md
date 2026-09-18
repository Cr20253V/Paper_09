# A1 GRU seed520 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed520_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed520\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 6.0000 | 16.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 6.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0115 | 0.0267 | 0.0060 | 0.0259 | 0.0030 | 0.1669 | 230.0465 | 0.1267 | 0.7953 | 0.0000 | 0.4567 | 0.5653 | 96.6142 | 61.8768 |
| GRU | 0.0164 | 0.0390 | 0.0180 | 0.0318 | 0.0037 | 0.2767 | 229.0453 | 0.1364 | 0.3039 | 0.0000 | 0.6706 | 0.7480 | 95.2546 | 69.9014 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0241 | 0.0265 | 0.0292 | 0.2657 | 0.0000 |
| GRU | 0.0103 | 0.0109 | 0.0117 | 0.0189 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0115 | 0.0267 | 0.0060 | 0.0259 | 0.0030 | 0.1267 | 0.7953 | 0.4567 | 0.5653 | 96.6142 | 61.8768 |
| ModernTCN | all | 0.0115 | 0.0267 | 0.0059 | 0.0689 | 0.0030 | 0.1267 | 9.6060 | 0.4511 | 0.5583 | 96.6579 | 62.3684 |
| GRU | all | 0.0164 | 0.0390 | 0.0180 | 0.0318 | 0.0037 | 0.1364 | 0.3039 | 0.6706 | 0.7480 | 95.2546 | 69.9014 |
| GRU | all | 0.0163 | 0.0390 | 0.0179 | 0.0713 | 0.0036 | 0.1364 | 9.1210 | 0.6615 | 0.7380 | 95.3158 | 70.3158 |
