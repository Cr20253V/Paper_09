# A1 GRU seed520 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed520_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed520\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 7.0000 | 3.0000 | 5.0000 | 15.0000 | 1.0000 |
| GRU | 11.0000 | 6.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0459 | 0.1019 | 0.0271 | 0.0319 | 0.0120 | 0.3400 | 226.0018 | 0.6274 | 2.5202 | 0.0000 | 0.5356 | 0.6465 | 93.7488 | 71.8501 |
| GRU | 0.0682 | 0.1898 | 0.0328 | 0.0440 | 0.0177 | 0.2709 | 223.5642 | 0.9615 | 2.9027 | 0.0000 | 0.7394 | 0.8087 | 91.9045 | 68.0839 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0217 | 0.0225 | 0.2415 | 0.0000 |
| GRU | 0.0105 | 0.0113 | 0.0147 | 0.0197 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0459 | 0.1019 | 0.0271 | 0.0319 | 0.0120 | 0.6274 | 2.5202 | 0.5356 | 0.6465 | 93.7488 | 71.8501 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0502 | 0.0891 | 0.0397 | 0.0393 | 0.0131 | 0.1774 | 1.5428 | 0.7227 | 0.8755 | 92.6667 | 87.1667 |
| ModernTCN | downhill_right_transition | 0.0162 | 0.0311 | 0.0113 | 0.0300 | 0.0103 | 0.1551 | 4.3002 | 0.5031 | 0.6529 | 95.9000 | 66.8000 |
| ModernTCN | flat_left_exit | 0.0761 | 0.1019 | 0.0261 | 0.0216 | 0.0148 | 0.6274 | 1.2940 | 0.4519 | 0.4482 | 89.2000 | 44.6000 |
| GRU | all | 0.0682 | 0.1898 | 0.0328 | 0.0440 | 0.0177 | 0.9615 | 2.9027 | 0.7394 | 0.8087 | 91.9045 | 68.0839 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1893 | 0.0000 | 0.0002457 | 66.6802 | 1.7638 | 1.4458 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0295 | 0.0603 | 0.0171 | 0.0433 | 0.0099 | 0.2143 | 0.8091 | 0.6813 | 0.6987 | 93.0556 | 87.8889 |
| GRU | downhill_right_transition | 0.1010 | 0.1898 | 0.0462 | 0.0400 | 0.0144 | 0.3599 | 6.2704 | 0.5887 | 0.7913 | 95.0000 | 54.2000 |
| GRU | flat_left_exit | 0.0445 | 0.0746 | 0.0270 | 0.0341 | 0.0319 | 0.9615 | 0.5166 | 0.6970 | 0.7449 | 80.8000 | 49.1000 |
