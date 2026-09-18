# A1 GRU seed340 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 8.0000 | 4.0000 | 5.0000 | 17.0000 | 1.0000 |
| GRU | 10.0000 | 5.0000 | 7.0000 | 22.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0670 | 0.1572 | 0.0561 | 0.0414 | 0.0271 | 0.7479 | 227.1112 | 1.4899 | 5.2068 | 0.0000 | 0.7628 | 0.8984 | 95.3019 | 54.9408 |
| GRU | 0.1459 | 0.4132 | 0.0478 | 0.0506 | 0.0293 | 0.5293 | 271.3608 | 0.7625 | 17.4423 | 0.0000 | 1.0596 | 1.1343 | 92.6034 | 61.8715 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0218 | 0.0230 | 0.2409 | 0.0000 |
| GRU | 0.0104 | 0.0112 | 0.0148 | 0.0201 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0582 | 0.0194 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.5048 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0670 | 0.1572 | 0.0561 | 0.0414 | 0.0271 | 1.4899 | 5.2068 | 0.7628 | 0.8984 | 95.3019 | 54.9408 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0810 | 0.1572 | 0.0646 | 0.0520 | 0.0242 | 0.1553 | 0.8831 | 1.1230 | 1.2929 | 95.2222 | 87.5556 |
| ModernTCN | downhill_right_transition | 0.0479 | 0.0746 | 0.0529 | 0.0306 | 0.0259 | 0.4246 | 3.2789 | 0.5517 | 0.7094 | 96.8000 | 35.7500 |
| ModernTCN | flat_left_exit | 0.0819 | 0.1544 | 0.0555 | 0.0432 | 0.0373 | 1.4899 | 18.3751 | 0.8043 | 0.8817 | 90.8000 | 18.9000 |
| GRU | all | 0.1459 | 0.4132 | 0.0478 | 0.0506 | 0.0293 | 0.7625 | 17.4423 | 1.0596 | 1.1343 | 92.6034 | 61.8715 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1864 | 0.0000 | 0.0002457 | 66.6203 | 1.5494 | 1.2539 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0512 | 0.1018 | 0.0314 | 0.0423 | 0.0186 | 0.2725 | 11.9938 | 0.8862 | 0.7987 | 94.2222 | 87.3333 |
| GRU | downhill_right_transition | 0.2214 | 0.4132 | 0.0628 | 0.0498 | 0.0249 | 0.7625 | 33.5596 | 1.0517 | 1.2652 | 96.0500 | 50.5000 |
| GRU | flat_left_exit | 0.0833 | 0.1712 | 0.0455 | 0.0567 | 0.0504 | 0.2885 | 0.7142 | 1.1396 | 1.3730 | 80.2000 | 25.5000 |
