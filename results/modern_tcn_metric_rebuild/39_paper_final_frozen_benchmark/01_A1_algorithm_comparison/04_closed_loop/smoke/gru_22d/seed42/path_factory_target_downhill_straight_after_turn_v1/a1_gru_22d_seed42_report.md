# A1 GRU seed42 path_factory_target_downhill_straight_after_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_target_downhill_straight_after_turn_v1\modern_fixed_seed42_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\smoke\gru_22d\seed42\path_factory_target_downhill_straight_after_turn_v1\gru_22d_seed42_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\factory_targeted_eval\path_factory_target_downhill_straight_after_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 9.0000 | 4.0000 | 6.0000 | 19.0000 | 1.0000 |
| GRU | 9.0000 | 5.0000 | 6.0000 | 20.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0218 | 0.0529 | 0.0161 | 0.0316 | 0.0035 | 0.1813 | 232.6634 | 0.1454 | 0.8754 | 0.0000 | 0.4929 | 0.5893 | 97.1474 | 70.4079 |
| GRU | 0.0010 | 0.0026 | 0.0034 | 0.0487 | 0.0036 | 0.2530 | 164.7529 | 0.0213 | 1.8220 | 0.0000 | 0.9961 | 0.9961 | 90.0398 | 89.2430 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0228 | 0.0250 | 0.0272 | 0.2605 | 0.0000 |
| GRU | 0.0110 | 0.0124 | 0.0767 | 2.3772 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0218 | 0.0529 | 0.0161 | 0.0316 | 0.0035 | 0.1454 | 0.8754 | 0.4929 | 0.5893 | 97.1474 | 70.4079 |
| ModernTCN | all | 0.0217 | 0.0529 | 0.0160 | 0.0713 | 0.0035 | 0.1454 | 9.6851 | 0.4868 | 0.5820 | 97.1842 | 70.7895 |
| GRU | all | 0.0010 | 0.0026 | 0.0034 | 0.0487 | 0.0036 | 0.0213 | 1.8220 | 0.9961 | 0.9961 | 90.0398 | 89.2430 |
| GRU | all | 0.00094 | 0.0026 | 0.0031 | 0.2316 | 0.0033 | 0.0213 | 113.2216 | 0.8345 | 0.8345 | 91.6944 | 91.0299 |
