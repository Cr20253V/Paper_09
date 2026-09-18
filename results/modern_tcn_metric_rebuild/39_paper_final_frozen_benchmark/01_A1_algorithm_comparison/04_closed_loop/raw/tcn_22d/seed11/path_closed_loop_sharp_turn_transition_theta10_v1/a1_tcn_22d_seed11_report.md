# A1 TCN seed11 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed11_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed11\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0407 | 0.1057 | 0.0442 | 0.0321 | 0.0243 | 0.5709 | 225.6178 | 0.7955 | 3.2048 | 0.0000 | 0.5293 | 0.6247 | 94.9913 | 50.0874 |
| TCN | 0.0778 | 0.2523 | 0.0779 | 0.0772 | 0.0425 | 0.8023 | 368.6388 | 0.4060 | 265.5385 | 0.0000 | 1.5003 | 1.6146 | 81.0328 | 64.6282 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0216 | 0.0225 | 0.2404 | 0.0000 |
| TCN | 0.0097 | 0.0110 | 0.0138 | 0.0626 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0407 | 0.1057 | 0.0442 | 0.0321 | 0.0243 | 0.7955 | 3.2048 | 0.5293 | 0.6247 | 94.9913 | 50.0874 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0580 | 0.1057 | 0.0628 | 0.0434 | 0.0299 | 0.1780 | 4.2072 | 0.8287 | 0.9482 | 95.1667 | 59.5000 |
| ModernTCN | downhill_right_transition | 0.0324 | 0.0563 | 0.0329 | 0.0271 | 0.0228 | 0.1674 | 3.4973 | 0.4527 | 0.6248 | 96.7000 | 41.9000 |
| ModernTCN | flat_left_exit | 0.0195 | 0.0321 | 0.0279 | 0.0156 | 0.0196 | 0.7955 | 1.6323 | 0.3295 | 0.2614 | 89.5000 | 32.1000 |
| TCN | all | 0.0778 | 0.2523 | 0.0779 | 0.0772 | 0.0425 | 0.4060 | 265.5385 | 1.5003 | 1.6146 | 81.0328 | 64.6282 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.8080 | 0.0000 | 61.7500 | 100.0000 |
| TCN | uphill_left_transition | 0.1222 | 0.2523 | 0.1219 | 0.1046 | 0.0422 | 0.3803 | 530.6956 | 1.2172 | 2.1846 | 86.3333 | 83.0556 |
| TCN | downhill_right_transition | 0.0391 | 0.1532 | 0.0455 | 0.0683 | 0.0543 | 0.4060 | 205.4716 | 1.9282 | 1.7929 | 93.6000 | 45.5500 |
| TCN | flat_left_exit | 0.0355 | 0.0615 | 0.0183 | 0.0381 | 0.0148 | 0.1668 | 0.5495 | 1.3557 | 0.7989 | 55.1000 | 57.3000 |
