# A1 TCN seed520 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed520_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed520\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed520_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 4.0000 | 13.0000 | 1.0000 |
| TCN | 12.0000 | 6.0000 | 8.0000 | 26.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0459 | 0.1019 | 0.0271 | 0.0319 | 0.0120 | 0.3400 | 226.0018 | 0.6274 | 2.5202 | 0.0000 | 0.5356 | 0.6465 | 93.7488 | 71.8501 |
| TCN | 0.5434 | 1.4337 | 0.1389 | 0.0997 | 0.0418 | 2.0096 | 704.9550 | 1.4041 | 386.2577 | 0.0000 | 0.6940 | 1.7431 | 83.6342 | 37.6238 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0217 | 0.0225 | 0.2415 | 0.0000 |
| TCN | 0.0087 | 0.0095 | 0.0105 | 0.0584 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |
| TCN | 0.1359 | 0.1359 | 10.1534 | 0.7183 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0459 | 0.1019 | 0.0271 | 0.0319 | 0.0120 | 0.6274 | 2.5202 | 0.5356 | 0.6465 | 93.7488 | 71.8501 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0502 | 0.0891 | 0.0397 | 0.0393 | 0.0131 | 0.1774 | 1.5428 | 0.7227 | 0.8755 | 92.6667 | 87.1667 |
| ModernTCN | downhill_right_transition | 0.0162 | 0.0311 | 0.0113 | 0.0300 | 0.0103 | 0.1551 | 4.3002 | 0.5031 | 0.6529 | 95.9000 | 66.8000 |
| ModernTCN | flat_left_exit | 0.0761 | 0.1019 | 0.0261 | 0.0216 | 0.0148 | 0.6274 | 1.2940 | 0.4519 | 0.4482 | 89.2000 | 44.6000 |
| TCN | all | 0.5434 | 1.4337 | 0.1389 | 0.0997 | 0.0418 | 1.4041 | 386.2577 | 0.6940 | 1.7431 | 83.6342 | 37.6238 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.4956 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.2048 | 0.3857 | 0.1523 | 0.1259 | 0.0299 | 0.5999 | 65.0781 | 0.5433 | 2.8416 | 87.2778 | 62.0556 |
| TCN | downhill_right_transition | 0.5081 | 0.9615 | 0.1352 | 0.0852 | 0.0434 | 1.0039 | 25.4176 | 0.8968 | 1.6131 | 91.8000 | 3.2500 |
| TCN | flat_left_exit | 0.9630 | 1.4337 | 0.1450 | 0.0888 | 0.0604 | 1.4041 | 1822 | 0.6047 | 0.6375 | 55.1000 | 40.6000 |
