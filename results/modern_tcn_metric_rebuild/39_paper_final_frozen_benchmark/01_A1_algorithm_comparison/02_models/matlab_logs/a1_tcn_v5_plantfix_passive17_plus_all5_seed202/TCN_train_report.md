# TCN 训练报告

- 生成时间: 2026-07-16 16:37:05
- 训练模式: `physics_guided`
- 数据集: `E:\Matlab\Simulink\S-Function_16\data\tcn\ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat`
- 模型文件: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\02_models\models\TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed202.mat`
- 最佳轮次: 68
- 主任务基座最佳轮次: 11
- 最佳验证损失: 1.016490
- 最佳选择分数: 4.132926
- 主任务基座选择分数: 0.895939
- 选模指标: `turn_priority`
- Base best metric: `composite`, combine_base_and_turn_best=1
- Base selection start epoch: 10
- Composite guard floors [flat stall slope]: [0.900 0.900 0.900], weights: [3.000 1.500 3.000]
- Head pooling: `last_mean_max_inputstats`
- Turn head: `mlp`, source=`inputstats`, hidden=64
- Turn finetune: start_epoch=64, lambda_turn=0.500, disable_other_losses=1
- Gradient clip: `global`, threshold=5.000
- 损失权重: 转弯=0.080, 坡度=0.550, 平地坡度约束=0.120, 辅助=0.000, pitch一致性=0.000
- 平地坡度约束模式: `near_zero`, near-zero tol=0.300 deg
- Physics-guided loss: lambda_phy=0.000, lambda_smooth=0.000, turn_transition_weight=1.250
- Physics thresholds: pitch=1.000 deg, turn_signal=0.0100, turn_gyro_weight=0.250, theta_mag_weight=0.250
- 坡度符号权重: 负坡=2.000, 正坡=1.000
- 主分类 slope 样本权重: 负坡=4.000, 正坡=1.000
- 下坡选模惩罚权重: 0.250
- 类别权重策略: main=`sqrt_inverse`, turn=`sqrt_inverse`
- 主工况类别乘子 [flat stall slope]: [1.000 1.000 1.000]
- 转弯类别乘子 [right straight left]: [1.080 1.000 1.080]
- Focal loss: enable=0, gamma_main=1.000, gamma_turn=0.500
- 感受野: 127 steps / 1.270 s

## 测试指标

| 指标 | 数值 |
|---|---:|
| 总损失 | 0.584857 |
| 主工况准确率 | 0.7324 |
| 转弯准确率 | 0.5330 |
| 转弯纯窗口准确率 | 0.5609 |
| 转弯过渡窗口准确率 | 0.4113 |
| 坡度 MAE deg | 0.9537 |
| |theta|<=10 P95 deg | 2.7359 |
| [-10,-8] P95 deg | 1.6306 |
| [8,10] P95 deg | 3.9304 |
| [-2,-0.5] P95 deg | 2.6431 |
| [0.5,2] P95 deg | 2.9355 |
| near-flat abs P95 deg | 2.4764 |
| flat theta bias deg | 0.4146 |

## 测试集混淆矩阵

### 主工况

| true \ pred | flat | stall | slope | recall |
|---|---:|---:|---:|---:|
| flat | 250 | 0 | 506 | 0.3307 |
| stall | 22 | 45 | 29 | 0.4688 |
| slope | 327 | 80 | 2343 | 0.8520 |

| pred class | precision |
|---|---:|
| flat | 0.4174 |
| stall | 0.3600 |
| slope | 0.8141 |

### 转弯方向

| true \ pred | right | straight | left | recall |
|---|---:|---:|---:|---:|
| right | 317 | 340 | 142 | 0.3967 |
| straight | 313 | 1187 | 433 | 0.6141 |
| left | 162 | 292 | 416 | 0.4782 |

| pred class | precision |
|---|---:|
| right | 0.4003 |
| straight | 0.6526 |
| left | 0.4198 |

## 坡度回归范围

- Slope 真值范围: [-9.750, 9.750] deg
- Slope 预测范围: [-11.068, 17.149] deg
- Slope 符号准确率: 0.9484

## 上坡/下坡子项指标

| 子项 | n | slope recall | theta MAE deg | theta sign acc | true theta range deg | pred theta range deg |
|---|---:|---:|---:|---:|---:|---:|
| uphill | 1744 | 0.6760 | 1.0860 | 0.9696 | [0.056, 9.750] | [-2.996, 17.149] |
| downhill | 1762 | 0.9478 | 0.8227 | 0.9274 | [-9.750, -0.235] | [-11.068, 3.871] |
