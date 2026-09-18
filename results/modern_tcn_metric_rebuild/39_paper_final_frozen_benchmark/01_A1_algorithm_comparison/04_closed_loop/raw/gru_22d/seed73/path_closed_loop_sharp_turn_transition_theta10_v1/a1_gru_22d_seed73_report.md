# A1 GRU seed73 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed73_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed73\path_closed_loop_sharp_turn_transition_theta10_v1\gru_22d_seed73_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| GRU | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0541 | 0.1638 | 0.0458 | 0.0388 | 0.0248 | 0.5744 | 226.5429 | 1.4640 | 2.2045 | 0.0000 | 0.6936 | 0.8154 | 93.7100 | 55.6979 |
| GRU | 0.1583 | 0.4590 | 0.0568 | 0.0412 | 0.0311 | 0.6819 | 226.7752 | 0.8623 | 11.7135 | 0.0000 | 0.8070 | 0.8718 | 92.4287 | 68.0645 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0201 | 0.0218 | 0.0228 | 0.2415 | 0.0000 |
| GRU | 0.0104 | 0.0112 | 0.0144 | 0.0195 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0582 | 0.0194 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 3.3197 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0541 | 0.1638 | 0.0458 | 0.0388 | 0.0248 | 1.4640 | 2.2045 | 0.6936 | 0.8154 | 93.7100 | 55.6979 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0474 | 0.0870 | 0.0550 | 0.0394 | 0.0262 | 0.1384 | 0.6550 | 0.6389 | 0.7472 | 95.2222 | 65.3889 |
| ModernTCN | downhill_right_transition | 0.0290 | 0.0623 | 0.0302 | 0.0458 | 0.0178 | 0.1830 | 3.0292 | 0.9818 | 1.1785 | 93.4500 | 48.7000 |
| ModernTCN | flat_left_exit | 0.0968 | 0.1638 | 0.0596 | 0.0232 | 0.0363 | 1.4640 | 3.8083 | 0.4592 | 0.4983 | 89.3000 | 36.8000 |
| GRU | all | 0.1583 | 0.4590 | 0.0568 | 0.0412 | 0.0311 | 0.8623 | 11.7135 | 0.8070 | 0.8718 | 92.4287 | 68.0645 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.1802 | 0.0000 | 0.0002457 | 66.4955 | 0.9897 | 0.7987 | 100.0000 | 100.0000 |
| GRU | uphill_left_transition | 0.0291 | 0.0554 | 0.0244 | 0.0342 | 0.0170 | 0.2091 | 1.0610 | 1.0041 | 0.9016 | 94.2778 | 87.3333 |
| GRU | downhill_right_transition | 0.2431 | 0.4590 | 0.0735 | 0.0519 | 0.0251 | 0.8525 | 28.3510 | 0.8289 | 1.0538 | 95.7500 | 54.4000 |
| GRU | flat_left_exit | 0.0965 | 0.1797 | 0.0688 | 0.0188 | 0.0564 | 0.8623 | 1.3399 | 0.2958 | 0.4408 | 79.8000 | 49.6000 |
