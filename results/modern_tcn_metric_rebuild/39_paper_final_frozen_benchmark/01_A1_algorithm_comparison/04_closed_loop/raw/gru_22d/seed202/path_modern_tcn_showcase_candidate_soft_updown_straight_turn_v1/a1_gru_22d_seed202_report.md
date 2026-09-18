# A1 GRU seed202 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed202_out.mat`
  - GRU: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\gru_22d\seed202\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\gru_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| ModernTCN | 6.0000 | 3.0000 | 5.0000 | 14.0000 | 1.0000 |
| GRU | 12.0000 | 6.0000 | 7.0000 | 25.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0055 | 0.0175 | 0.0082 | 0.0105 | 0.0061 | 0.2764 | 243.3561 | 0.2906 | 0.3036 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 53.3778 |
| GRU | 0.0251 | 0.0885 | 0.0171 | 0.0225 | 0.0107 | 0.3258 | 243.3561 | 0.8827 | 0.3367 | 0.0000 | 0.4505 | 0.4453 | 99.5496 | 46.1358 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0204 | 0.0221 | 0.0234 | 0.2375 | 0.0000 |
| GRU | 0.0104 | 0.0115 | 0.0148 | 0.0195 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| GRU | 0.0000 | 0.0000 | 0.0360 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0055 | 0.0175 | 0.0082 | 0.0105 | 0.0061 | 0.2906 | 0.3036 | 0.0167 | 0.0167 | 99.5496 | 53.3778 |
| ModernTCN | all | 0.0054 | 0.0175 | 0.0081 | 0.0528 | 0.0061 | 0.2906 | 5.2290 | 0.0376 | 0.0376 | 99.0179 | 53.8036 |
| GRU | all | 0.0251 | 0.0885 | 0.0171 | 0.0225 | 0.0107 | 0.8827 | 0.3367 | 0.4505 | 0.4453 | 99.5496 | 46.1358 |
| GRU | all | 0.0250 | 0.0885 | 0.0170 | 0.0564 | 0.0106 | 0.8827 | 5.2618 | 0.4675 | 0.4623 | 99.0179 | 46.6250 |
