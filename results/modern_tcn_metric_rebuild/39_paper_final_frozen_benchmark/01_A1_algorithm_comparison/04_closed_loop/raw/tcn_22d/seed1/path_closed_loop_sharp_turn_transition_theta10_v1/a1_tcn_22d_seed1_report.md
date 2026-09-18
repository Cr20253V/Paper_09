# A1 TCN seed1 path_closed_loop_sharp_turn_transition_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_sharp_turn_transition_theta10_v1\modern_fixed_seed1_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed1\path_closed_loop_sharp_turn_transition_theta10_v1\tcn_22d_seed1_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_sharp_turn_transition_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 4.0000 | 4.0000 | 14.0000 | 1.0000 |
| TCN | 12.0000 | 5.0000 | 8.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0368 | 0.1045 | 0.0399 | 0.0411 | 0.0232 | 0.4544 | 235.8110 | 0.7104 | 3.9448 | 0.0000 | 0.7262 | 0.7882 | 93.2052 | 46.3017 |
| TCN | 0.4608 | 1.3011 | 0.1727 | 0.1034 | 0.0671 | 2.0299 | 708.5996 | 1.4185 | 866.0244 | 0.0000 | 0.8404 | 1.7948 | 84.3137 | 58.5323 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0200 | 0.0220 | 0.0233 | 0.3657 | 0.0000 |
| TCN | 0.0094 | 0.0104 | 0.0120 | 0.2567 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0194 | 0.0000 | 0.0000 |
| TCN | 0.1553 | 0.0777 | 5.6494 | 0.9124 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0368 | 0.1045 | 0.0399 | 0.0411 | 0.0232 | 0.7104 | 3.9448 | 0.7262 | 0.7882 | 93.2052 | 46.3017 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_left_transition | 0.0562 | 0.1045 | 0.0608 | 0.0491 | 0.0275 | 0.1619 | 1.1567 | 0.9670 | 1.0726 | 93.2222 | 52.8889 |
| ModernTCN | downhill_right_transition | 0.0174 | 0.0454 | 0.0233 | 0.0400 | 0.0249 | 0.3099 | 5.3684 | 0.7179 | 0.7807 | 94.4000 | 36.4000 |
| ModernTCN | flat_left_exit | 0.0262 | 0.0484 | 0.0209 | 0.0308 | 0.0128 | 0.7104 | 7.1961 | 0.5646 | 0.5678 | 88.4000 | 35.5000 |
| TCN | all | 0.4608 | 1.3011 | 0.1727 | 0.1034 | 0.0671 | 1.4185 | 866.0244 | 0.8404 | 1.7948 | 84.3137 | 58.5323 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1753 | 0.0000 | 0.0002457 | 66.3593 | 0.8833 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_left_transition | 0.2021 | 0.3864 | 0.1560 | 0.1352 | 0.0256 | 0.5633 | 603.5825 | 1.0846 | 3.1804 | 90.0556 | 84.4444 |
| TCN | downhill_right_transition | 0.2182 | 0.3613 | 0.2116 | 0.0818 | 0.0872 | 1.3036 | 61.9338 | 0.8781 | 1.6038 | 91.0500 | 34.7000 |
| TCN | flat_left_exit | 0.9613 | 1.3011 | 0.1416 | 0.0927 | 0.0825 | 1.4185 | 3245 | 0.2672 | 0.3129 | 55.1000 | 45.1000 |
