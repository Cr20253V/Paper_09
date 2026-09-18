# A1 TCN seed340 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed340_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed340\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0670 | 0.1572 | 0.0561 | 0.0414 | 0.0271 | 0.7479 | 227.1112 | 1.4899 | 5.2068 | 0.0000 | 0.7628 | 0.8984 | 95.3019 | 54.9408 |
| TCN | 0.0228 | 0.0623 | 0.0309 | 0.0329 | 0.0196 | 0.3878 | 225.5393 | 0.1797 | 0.9117 | 0.0000 | 0.5609 | 0.6629 | 89.1089 | 63.3469 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0218 | 0.0230 | 0.2409 | 0.0000 |
| TCN | 0.0087 | 0.0093 | 0.0096 | 0.0546 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0582 | 0.0194 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0670 | 0.1572 | 0.0561 | 0.0414 | 0.0271 | 1.4899 | 5.2068 | 0.7628 | 0.8984 | 95.3019 | 54.9408 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0810 | 0.1572 | 0.0646 | 0.0520 | 0.0242 | 0.1553 | 0.8831 | 1.1230 | 1.2929 | 95.2222 | 87.5556 |
| ModernTCN | downhill_right_transition | 0.0479 | 0.0746 | 0.0529 | 0.0306 | 0.0259 | 0.4246 | 3.2789 | 0.5517 | 0.7094 | 96.8000 | 35.7500 |
| ModernTCN | flat_left_exit | 0.0819 | 0.1544 | 0.0555 | 0.0432 | 0.0373 | 1.4899 | 18.3751 | 0.8043 | 0.8817 | 90.8000 | 18.9000 |
| TCN | all | 0.0228 | 0.0623 | 0.0309 | 0.0329 | 0.0196 | 0.1797 | 0.9117 | 0.5609 | 0.6629 | 89.1089 | 63.3469 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.4093 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.0333 | 0.0623 | 0.0485 | 0.0309 | 0.0241 | 0.1413 | 1.2540 | 0.4292 | 0.6410 | 95.1667 | 87.2222 |
| TCN | downhill_right_transition | 0.0098 | 0.0310 | 0.0171 | 0.0415 | 0.0198 | 0.1446 | 0.8017 | 0.7856 | 0.9868 | 94.7000 | 37.8000 |
| TCN | flat_left_exit | 0.0222 | 0.0337 | 0.0104 | 0.0143 | 0.0122 | 0.1797 | 0.5230 | 0.3814 | 0.2876 | 63.3000 | 58.7000 |
