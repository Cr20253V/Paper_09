# A1 GRU seed11 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed11_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed11\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed11_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 8.0000 | 4.0000 | 6.0000 | 18.0000 | 1.0000 |
| ModernTCN | 10.0000 | 5.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0407 | 0.1057 | 0.0442 | 0.0321 | 0.0243 | 0.5709 | 225.6178 | 0.7955 | 3.2048 | 0.0000 | 0.5293 | 0.6247 | 94.9913 | 50.0874 |
| GRU | 0.0483 | 0.1263 | 0.0294 | 0.0311 | 0.0191 | 0.1930 | 222.8470 | 0.9772 | 2.2460 | 0.0000 | 0.4703 | 0.5734 | 91.7686 | 65.4048 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0216 | 0.0225 | 0.2404 | 0.0000 |
| GRU | 0.0396 | 0.0461 | 0.0506 | 0.0995 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0407 | 0.1057 | 0.0442 | 0.0321 | 0.0243 | 0.7955 | 3.2048 | 0.5293 | 0.6247 | 94.9913 | 50.0874 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0580 | 0.1057 | 0.0628 | 0.0434 | 0.0299 | 0.1780 | 4.2072 | 0.8287 | 0.9482 | 95.1667 | 59.5000 |
| ModernTCN | downhill_right_transition | 0.0324 | 0.0563 | 0.0329 | 0.0271 | 0.0228 | 0.1674 | 3.4973 | 0.4527 | 0.6248 | 96.7000 | 41.9000 |
| ModernTCN | flat_left_exit | 0.0195 | 0.0321 | 0.0279 | 0.0156 | 0.0196 | 0.7955 | 1.6323 | 0.3295 | 0.2614 | 89.5000 | 32.1000 |
| GRU | all | 0.0483 | 0.1263 | 0.0294 | 0.0311 | 0.0191 | 0.9772 | 2.2460 | 0.4703 | 0.5734 | 91.7686 | 65.4048 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1794 | 0.0000 | 0.0002457 | 66.4452 | 0.8779 | 0.6828 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0234 | 0.0434 | 0.0090 | 0.0246 | 0.0079 | 0.1554 | 0.0706 | 0.3416 | 0.3746 | 91.8333 | 79.1111 |
| GRU | downhill_right_transition | 0.0657 | 0.1263 | 0.0410 | 0.0337 | 0.0256 | 0.5049 | 5.3363 | 0.4973 | 0.7028 | 94.9500 | 54.9000 |
| GRU | flat_left_exit | 0.0492 | 0.0748 | 0.0310 | 0.0289 | 0.0213 | 0.9772 | 0.4242 | 0.4616 | 0.6007 | 82.4000 | 49.7000 |
