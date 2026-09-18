# A1 GRU seed73 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed73_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed73\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed73_out.mat`
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
| ModernTCN | 0.0228 | 0.0403 | 0.0201 | 0.0380 | 0.0041 | 0.5982 | 232.0212 | 0.1248 | 0.7985 | 0.0000 | 0.9029 | 0.9954 | 95.1480 | 56.5716 |
| GRU | 0.0205 | 0.0446 | 0.0303 | 0.0408 | 0.0045 | 0.6215 | 229.0787 | 0.1444 | 0.2395 | 0.0000 | 0.9943 | 1.0216 | 95.4945 | 74.9400 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0229 | 0.0252 | 0.0272 | 0.2694 | 0.0000 |
| GRU | 0.0104 | 0.0113 | 0.0140 | 0.0195 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0228 | 0.0403 | 0.0201 | 0.0380 | 0.0041 | 0.1248 | 0.7985 | 0.9029 | 0.9954 | 95.1480 | 56.5716 |
| ModernTCN | all | 0.0226 | 0.0403 | 0.0200 | 0.0743 | 0.0040 | 0.1248 | 9.6092 | 0.8915 | 0.9829 | 95.2105 | 57.1316 |
| GRU | all | 0.0205 | 0.0446 | 0.0303 | 0.0408 | 0.0045 | 0.1444 | 0.2395 | 0.9943 | 1.0216 | 95.4945 | 74.9400 |
| GRU | all | 0.0204 | 0.0446 | 0.0301 | 0.0757 | 0.0045 | 0.1444 | 9.0573 | 0.9814 | 1.0085 | 95.5526 | 75.2632 |
