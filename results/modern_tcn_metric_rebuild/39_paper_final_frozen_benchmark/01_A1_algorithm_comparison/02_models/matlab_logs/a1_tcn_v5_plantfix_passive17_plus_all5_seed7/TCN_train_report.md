# TCN 训练报告

- 生成时间: 2026-07-16 09:37:17
- 训练模式: `physics_guided`
- 数据集: `E:\Matlab\Simulink\S-Function_16\data\tcn\ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat`
- 模型文件: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\02_models\models\TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed7.mat`
- 最佳轮次: 92
- 主任务基座最佳轮次: 11
- 最佳验证损失: 1.090834
- 最佳选择分数: 5.266982
- 主任务基座选择分数: 0.907528
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
| 总损失 | 0.587071 |
| 主工况准确率 | 0.7218 |
| 转弯准确率 | 0.5425 |
| 转弯纯窗口准确率 | 0.5660 |
| 转弯过渡窗口准确率 | 0.4396 |
| 坡度 MAE deg | 0.8324 |
| |theta|<=10 P95 deg | 2.3582 |
| [-10,-8] P95 deg | 2.1157 |
| [8,10] P95 deg | 4.3341 |
| [-2,-0.5] P95 deg | 2.0492 |
| [0.5,2] P95 deg | 3.2742 |
| near-flat abs P95 deg | 2.2879 |
| flat theta bias deg | -0.1200 |

## 测试集混淆矩阵

### 主工况

| true \ pred | flat | stall | slope | recall |
|---|---:|---:|---:|---:|
| flat | 233 | 1 | 522 | 0.3082 |
| stall | 22 | 50 | 24 | 0.5208 |
| slope | 261 | 172 | 2317 | 0.8425 |

| pred class | precision |
|---|---:|
| flat | 0.4516 |
| stall | 0.2242 |
| slope | 0.8093 |

### 转弯方向

| true \ pred | right | straight | left | recall |
|---|---:|---:|---:|---:|
| right | 334 | 325 | 140 | 0.4180 |
| straight | 355 | 1228 | 350 | 0.6353 |
| left | 161 | 317 | 392 | 0.4506 |

| pred class | precision |
|---|---:|
| right | 0.3929 |
| straight | 0.6567 |
| left | 0.4444 |

## 坡度回归范围

- Slope 真值范围: [-9.750, 9.750] deg
- Slope 预测范围: [-10.890, 15.246] deg
- Slope 符号准确率: 0.9595

## 上坡/下坡子项指标

| 子项 | n | slope recall | theta MAE deg | theta sign acc | true theta range deg | pred theta range deg |
|---|---:|---:|---:|---:|---:|---:|
| uphill | 1744 | 0.6594 | 0.9014 | 0.9570 | [0.056, 9.750] | [-3.470, 15.246] |
| downhill | 1762 | 0.9586 | 0.7640 | 0.9620 | [-9.750, -0.235] | [-10.890, 3.339] |
