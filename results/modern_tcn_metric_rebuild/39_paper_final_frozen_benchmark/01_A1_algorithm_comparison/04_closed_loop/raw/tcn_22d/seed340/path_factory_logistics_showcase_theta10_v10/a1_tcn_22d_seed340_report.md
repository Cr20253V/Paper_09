# A1 TCN seed340 path_factory_logistics_showcase_theta10_v10

- 输出文件：
  - ModernTCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\02_modern_fixed_full_closed_loop\path_factory_logistics_showcase_theta10_v10\modern_fixed_seed340_out.mat`
  - TCN: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\04_closed_loop\raw\tcn_22d\seed340\path_factory_logistics_showcase_theta10_v10\tcn_22d_seed340_out.mat`
- 展示路径文件：`E:\Matlab\Simulink\S-Function_16\data\paths\path_factory_logistics_showcase_theta10_v10.mat`

## 排序

排序采用名次和，数值越小越好。跟踪项包含横向/航向/速度/角速度/XY 误差；感知项包含坡度 MAE、主状态准确率和转向准确率；控制项包含控制增量、约束违规率和控制峰值。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---|---|---|---|---|
| TCN | 6.0000 | 4.0000 | 5.0000 | 15.0000 | 1.0000 |
| ModernTCN | 12.0000 | 5.0000 | 7.0000 | 24.0000 | 2.0000 |

## 总体结果

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | 0.0436 | 0.1837 | 0.0574 | 0.0226 | 0.0159 | 2.3866 | 218.2441 | 1.4894 | 1.0965 | 0.0000 | 0.4368 | 0.4451 | 93.4822 | 73.0608 |
| TCN | 0.0216 | 0.0904 | 0.0233 | 0.0201 | 0.0108 | 1.3754 | 217.8330 | 0.9940 | 0.4209 | 0.0000 | 0.4065 | 0.3983 | 85.0732 | 88.1588 |

## 处理用时统计

| controller | solve_time_p50_ms | solve_time_p95_ms | solve_time_p99_ms | solve_time_max_ms | timeout_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0197 | 0.0215 | 0.0246 | 0.2401 | 0.0000 |
| TCN | 0.0087 | 0.0093 | 0.0096 | 0.0578 | 0.0000 |

## 约束与饱和

| controller | F_sat595_pct | F_limit_hit_pct | omega_sat060_pct | omega_limit_hit_pct | viol_rate |
|---|---|---|---|---|---|
| ModernTCN | 0.0000 | 0.0000 | 0.0938 | 0.0163 | 0.0000 |
| TCN | 0.0000 | 0.0000 | 0.0815 | 0.0000 | 0.0000 |

## 分区关键指标

| controller | zone | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | omega_cmd_peak | j_du | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ModernTCN | all | 0.0436 | 0.1837 | 0.0574 | 0.0226 | 0.0159 | 1.4894 | 1.0965 | 0.4368 | 0.4451 | 93.4822 | 73.0608 |
| ModernTCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.0537 | 0.0537 | 100.0000 | 100.0000 |
| ModernTCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0199 | 0.0000 | 6.466e-05 | 0.4231 | 0.3227 | 0.3727 | 98.9359 | 100.0000 |
| ModernTCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0179 | 0.0000 | 1.567e-05 | 4.1404 | 0.3921 | 0.3598 | 93.7000 | 100.0000 |
| ModernTCN | adjacent_aisle_u_turn | 0.0843 | 0.1837 | 0.1252 | 0.0198 | 0.0117 | 1.4894 | 0.8592 | 0.6872 | 0.5991 | 71.3444 | 20.5587 |
| ModernTCN | return_recovery_aisle | 0.0899 | 0.1627 | 0.0816 | 0.0336 | 0.0643 | 0.3891 | 4.9155 | 0.8970 | 0.8970 | 100.0000 | 3.6125 |
| ModernTCN | return_slope_aisle | 0.0239 | 0.0817 | 0.0116 | 0.0275 | 0.0087 | 0.0753 | 0.6264 | 0.4391 | 0.4772 | 99.0405 | 75.7432 |
| ModernTCN | shipping_return_aisle | 0.0011 | 0.0026 | 0.0006523 | 0.0101 | 0.0028 | 0.0056 | 3.3044 | 0.1824 | 0.1596 | 95.0072 | 100.0000 |
| TCN | all | 0.0216 | 0.0904 | 0.0233 | 0.0201 | 0.0108 | 0.9940 | 0.4209 | 0.4065 | 0.3983 | 85.0732 | 88.1588 |
| TCN | startup | 0.0000 | 0.0000 | 0.0000 | 0.1062 | 0.0000 | 0.0002577 | 24.2442 | 0.8095 | 0.0537 | 100.0000 | 100.0000 |
| TCN | outbound_rack_aisle | 0.0000 | 0.0000 | 0.0000 | 0.0154 | 0.0000 | 6.13e-05 | 0.2102 | 0.2442 | 0.2979 | 99.5385 | 100.0000 |
| TCN | approach_to_u_turn | 0.0000 | 0.0000 | 0.0000 | 0.0172 | 0.0000 | 2.026e-05 | 2.0869 | 0.5778 | 0.4009 | 88.8000 | 100.0000 |
| TCN | adjacent_aisle_u_turn | 0.0203 | 0.0390 | 0.0495 | 0.0238 | 0.0107 | 0.9940 | 0.6448 | 0.6198 | 0.5991 | 53.7538 | 91.5321 |
| TCN | return_recovery_aisle | 0.0452 | 0.0638 | 0.0345 | 0.0353 | 0.0384 | 0.3997 | 0.0255 | 0.4564 | 0.8970 | 52.7915 | 21.0181 |
| TCN | return_slope_aisle | 0.0308 | 0.0904 | 0.0090 | 0.0208 | 0.0085 | 0.5722 | 0.1949 | 0.2618 | 0.3895 | 90.3649 | 78.9865 |
| TCN | shipping_return_aisle | 0.0013 | 0.0029 | 0.0009948 | 0.0108 | 0.0031 | 0.0056 | 1.3243 | 0.8575 | 0.1906 | 92.2576 | 100.0000 |
