# A1 GRU seed340 path_closed_loop_long_updown_theta10_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_closed_loop_long_updown_theta10_v1\modern_fixed_seed340_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed340\path_closed_loop_long_updown_theta10_v1\gru_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_closed_loop_long_updown_theta10_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| GRU | 8.0000 | 5.0000 | 6.0000 | 19.0000 | 1.0000 |
| ModernTCN | 10.0000 | 4.0000 | 6.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0350 | 0.0974 | 0.0359 | 0.0515 | 0.0278 | 0.6885 | 272.5480 | 0.2580 | 8.7178 | 0.0000 | 0.8177 | 1.1308 | 91.7950 | 50.1494 |
| GRU | 0.0710 | 0.2313 | 0.0266 | 0.0505 | 0.0272 | 0.3918 | 266.7332 | 0.8179 | 0.8432 | 0.0000 | 0.9454 | 1.1653 | 89.9333 | 56.7915 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0203 | 0.0220 | 0.0232 | 0.2348 | 0.0000 |
| GRU | 0.0104 | 0.0113 | 0.0143 | 0.0192 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0460 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0350 | 0.0974 | 0.0359 | 0.0515 | 0.0278 | 0.2580 | 8.7178 | 0.8177 | 1.1308 | 91.7950 | 50.1494 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.2170 | 0.0000 | 0.0002637 | 101.8309 | 0.0000 | 0.0000 | 100.0000 | 100.0000 |
| ModernTCN | uphill_long_entry | 0.0336 | 0.0700 | 0.0372 | 0.0524 | 0.0262 | 0.0931 | 15.8606 | 0.9413 | 1.2083 | 94.0769 | 87.0000 |
| ModernTCN | downhill_transition | 0.0224 | 0.0373 | 0.0283 | 0.0439 | 0.0217 | 0.2580 | 5.9243 | 0.6746 | 0.9889 | 92.0769 | 26.9231 |
| ModernTCN | uphill_return | 0.0533 | 0.0974 | 0.0369 | 0.0682 | 0.0271 | 0.0808 | 3.4954 | 1.1288 | 1.5957 | 89.0000 | 38.4000 |
| ModernTCN | flat_recovery | 0.0271 | 0.0507 | 0.0529 | 0.0338 | 0.0477 | 0.1165 | 11.5262 | 0.6564 | 0.9361 | 86.6000 | 13.4000 |
| GRU | all | 0.0710 | 0.2313 | 0.0266 | 0.0505 | 0.0272 | 0.8179 | 0.8432 | 0.9454 | 1.1653 | 89.9333 | 56.7915 |
| GRU | startup | 0.0000 | 0.0000 | 0.0000 | 0.2213 | 0.0000 | 0.0002637 | 102.1353 | 1.0383 | 0.6899 | 100.0000 | 100.0000 |
| GRU | uphill_long_entry | 0.0206 | 0.0420 | 0.0113 | 0.0383 | 0.0078 | 0.1376 | 0.1570 | 0.8213 | 0.7793 | 92.3077 | 82.8462 |
| GRU | downhill_transition | 0.1084 | 0.2313 | 0.0235 | 0.0608 | 0.0165 | 0.3907 | 1.3064 | 1.0584 | 1.4186 | 91.7692 | 55.2308 |
| GRU | uphill_return | 0.0754 | 0.1943 | 0.0358 | 0.0326 | 0.0314 | 0.8179 | 1.0639 | 0.5650 | 1.0285 | 82.1000 | 35.9000 |
| GRU | flat_recovery | 0.0287 | 0.0419 | 0.0424 | 0.0711 | 0.0598 | 0.2423 | 0.4679 | 1.5826 | 1.9518 | 89.6000 | 13.4000 |
