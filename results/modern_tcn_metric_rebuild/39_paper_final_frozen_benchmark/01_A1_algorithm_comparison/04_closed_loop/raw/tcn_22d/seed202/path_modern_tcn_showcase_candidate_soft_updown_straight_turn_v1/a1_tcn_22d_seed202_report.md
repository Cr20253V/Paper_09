# A1 TCN seed202 path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\modern_fixed_seed202_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed202\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1\tcn_22d_seed202_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\modern_tcn_showcase\candidates\path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 6.0000 | 6.0000 | 6.0000 | 18.0000 | 1.0000 |
| ModernTCN | 12.0000 | 3.0000 | 6.0000 | 21.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0055 | 0.0175 | 0.0082 | 0.0105 | 0.0061 | 0.2764 | 243.3561 | 0.2906 | 0.3036 | 0.0000 | 0.0167 | 0.0167 | 99.5496 | 53.3778 |
| TCN | 0.0032 | 0.0087 | 0.0073 | 0.0105 | 0.0056 | 0.2756 | 243.3561 | 0.2963 | 0.3015 | 0.0000 | 0.5229 | 0.0167 | 9.0254 | 43.5417 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0204 | 0.0221 | 0.0234 | 0.2375 | 0.0000 |
| TCN | 0.0088 | 0.0093 | 0.0095 | 0.0566 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0055 | 0.0175 | 0.0082 | 0.0105 | 0.0061 | 0.2906 | 0.3036 | 0.0167 | 0.0167 | 99.5496 | 53.3778 |
| ModernTCN | all | 0.0054 | 0.0175 | 0.0081 | 0.0528 | 0.0061 | 0.2906 | 5.2290 | 0.0376 | 0.0376 | 99.0179 | 53.8036 |
| TCN | all | 0.0032 | 0.0087 | 0.0073 | 0.0105 | 0.0056 | 0.2963 | 0.3015 | 0.5229 | 0.0167 | 9.0254 | 43.5417 |
| TCN | all | 0.0032 | 0.0087 | 0.0073 | 0.0528 | 0.0055 | 0.2963 | 5.2269 | 0.5393 | 0.0376 | 9.3036 | 44.0536 |
