# A1 TCN seed520 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_factory_target_downhill_straight_after_turn_v1\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0115 | 0.0267 | 0.0060 | 0.0259 | 0.0030 | 0.1669 | 230.0465 | 0.1267 | 0.7953 | 0.0000 | 0.4567 | 0.5653 | 96.6142 | 61.8768 |
| TCN | 0.0255 | 0.0604 | 0.0304 | 0.0431 | 0.0045 | 0.4912 | 231.1086 | 0.1508 | 2.8946 | 0.0000 | 0.7038 | 0.8678 | 93.9216 | 73.6337 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0241 | 0.0265 | 0.0292 | 0.2657 | 0.0000 |
| TCN | 0.0089 | 0.0104 | 0.0124 | 0.0644 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0115 | 0.0267 | 0.0060 | 0.0259 | 0.0030 | 0.1267 | 0.7953 | 0.4567 | 0.5653 | 96.6142 | 61.8768 |
| ModernTCN | all | 0.0115 | 0.0267 | 0.0059 | 0.0689 | 0.0030 | 0.1267 | 9.6060 | 0.4511 | 0.5583 | 96.6579 | 62.3684 |
| TCN | all | 0.0255 | 0.0604 | 0.0304 | 0.0431 | 0.0045 | 0.1508 | 2.8946 | 0.7038 | 0.8678 | 93.9216 | 73.6337 |
| TCN | all | 0.0253 | 0.0604 | 0.0302 | 0.0770 | 0.0045 | 0.1508 | 11.6782 | 0.6948 | 0.8569 | 94.0000 | 73.9737 |
