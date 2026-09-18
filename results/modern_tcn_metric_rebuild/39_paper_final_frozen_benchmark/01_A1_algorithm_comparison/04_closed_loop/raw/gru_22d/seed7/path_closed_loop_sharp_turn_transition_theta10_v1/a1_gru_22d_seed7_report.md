# A1 GRU seed7 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed7_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed7\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed7_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 7.0000 | 4.0000 | 5.0000 | 16.0000 | 1.0000 |
| GRU | 11.0000 | 5.0000 | 7.0000 | 23.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0343 | 0.1019 | 0.0368 | 0.0377 | 0.0204 | 0.4681 | 225.8353 | 0.1558 | 2.0706 | 0.0000 | 0.6705 | 0.7733 | 94.3700 | 47.6995 |
| GRU | 0.1037 | 0.2694 | 0.0412 | 0.0454 | 0.0268 | 0.3577 | 225.0142 | 0.5104 | 9.0557 | 0.0000 | 0.9036 | 0.9712 | 93.0499 | 55.8726 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0216 | 0.0225 | 0.2432 | 0.0000 |
| GRU | 0.0086 | 0.0095 | 0.0104 | 0.0181 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0343 | 0.1019 | 0.0368 | 0.0377 | 0.0204 | 0.1558 | 2.0706 | 0.6705 | 0.7733 | 94.3700 | 47.6995 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0543 | 0.1019 | 0.0577 | 0.0387 | 0.0259 | 0.1558 | 0.6714 | 0.7389 | 0.8521 | 95.0556 | 57.8889 |
| ModernTCN | downhill_right_transition | 0.0157 | 0.0270 | 0.0202 | 0.0456 | 0.0195 | 0.1397 | 3.9049 | 0.9065 | 1.0694 | 95.7500 | 35.9500 |
| ModernTCN | flat_left_exit | 0.0162 | 0.0445 | 0.0135 | 0.0163 | 0.0131 | 0.1258 | 1.3360 | 0.3106 | 0.3105 | 88.4000 | 34.6000 |
| GRU | all | 0.1037 | 0.2694 | 0.0412 | 0.0454 | 0.0268 | 0.5104 | 9.0557 | 0.9036 | 0.9712 | 93.0499 | 55.8726 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1869 | 0.0000 | 0.0002457 | 66.6226 | 1.5956 | 1.3076 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0615 | 0.1182 | 0.0251 | 0.0413 | 0.0046 | 0.2033 | 0.1006 | 0.8201 | 0.7378 | 93.3333 | 77.8333 |
| GRU | downhill_right_transition | 0.1422 | 0.2694 | 0.0526 | 0.0475 | 0.0179 | 0.5104 | 22.3863 | 1.0067 | 1.2164 | 95.1000 | 31.5000 |
| GRU | flat_left_exit | 0.0900 | 0.1515 | 0.0456 | 0.0339 | 0.0549 | 0.3907 | 1.2455 | 0.5268 | 0.7186 | 86.0000 | 49.7000 |
