# A1 TCN seed340 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed340_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed340\path_closed_loop_long_updown_theta10_v1\tcn_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 8.0000 | 4.0000 | 6.0000 | 18.0000 | 1.0000 |
| ModernTCN | 10.0000 | 5.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0350 | 0.0974 | 0.0359 | 0.0515 | 0.0278 | 0.6885 | 272.5480 | 0.2580 | 8.7178 | 0.0000 | 0.8177 | 1.1308 | 91.7950 | 50.1494 |
| TCN | 0.0371 | 0.1172 | 0.0290 | 0.0448 | 0.0247 | 0.4485 | 267.4950 | 0.3335 | 3.1511 | 0.0000 | 0.6064 | 1.0020 | 86.1411 | 54.3094 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0232 | 0.2348 | 0.0000 |
| TCN | 0.0087 | 0.0093 | 0.0096 | 0.0554 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0350 | 0.0974 | 0.0359 | 0.0515 | 0.0278 | 0.2580 | 8.7178 | 0.8177 | 1.1308 | 91.7950 | 50.1494 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0336 | 0.0700 | 0.0372 | 0.0524 | 0.0262 | 0.0931 | 15.8606 | 0.9413 | 1.2083 | 94.0769 | 87.0000 |
| ModernTCN | downhill_transition | 0.0224 | 0.0373 | 0.0283 | 0.0439 | 0.0217 | 0.2580 | 5.9243 | 0.6746 | 0.9889 | 92.0769 | 26.9231 |
| ModernTCN | uphill_return | 0.0533 | 0.0974 | 0.0369 | 0.0682 | 0.0271 | 0.0808 | 3.4954 | 1.1288 | 1.5957 | 89.0000 | 38.4000 |
| ModernTCN | flat_recovery | 0.0271 | 0.0507 | 0.0529 | 0.0338 | 0.0477 | 0.1165 | 11.5262 | 0.6564 | 0.9361 | 86.6000 | 13.4000 |
| TCN | all | 0.0371 | 0.1172 | 0.0290 | 0.0448 | 0.0247 | 0.3335 | 3.1511 | 0.6064 | 1.0020 | 86.1411 | 54.3094 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.1976 | 0.0000 | 100.0000 | 100.0000 |
| TCN | uphill_long_entry | 0.0285 | 0.0586 | 0.0317 | 0.0437 | 0.0214 | 0.0953 | 2.6443 | 0.4570 | 0.8745 | 92.2308 | 81.6154 |
| TCN | downhill_transition | 0.0262 | 0.0574 | 0.0186 | 0.0465 | 0.0231 | 0.3335 | 1.5181 | 0.8208 | 1.1503 | 88.4615 | 29.3077 |
| TCN | uphill_return | 0.0540 | 0.1172 | 0.0247 | 0.0540 | 0.0218 | 0.0650 | 5.3378 | 0.6320 | 1.3214 | 80.7000 | 60.4000 |
| TCN | flat_recovery | 0.0477 | 0.1065 | 0.0507 | 0.0251 | 0.0421 | 0.2189 | 5.1885 | 0.5710 | 0.8123 | 68.4000 | 13.4000 |
