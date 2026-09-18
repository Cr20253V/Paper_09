# TCN 训练报告

- 生成时间: 2026-07-16 12:01:55
- 训练模式: `physics_guided`
- 数据集: `E:\Matlab\Simulink\S-Function_16\data\tcn\ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat`
- 模型文件: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\02_models\models\TCN_model_a1_tcn_v5_plantfix_passive17_plus_all5_seed11.mat`
- 最佳轮次: 87
- 主任务基座最佳轮次: 19
- 最佳验证损失: 1.099189
- 最佳选择分数: 4.425550
- 主任务基座选择分数: 0.902239
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
| 总损失 | 0.587123 |
| 主工况准确率 | 0.7338 |
| 转弯准确率 | 0.5305 |
| 转弯纯窗口准确率 | 0.5571 |
| 转弯过渡窗口准确率 | 0.4143 |
| 坡度 MAE deg | 0.8914 |
| |theta|<=10 P95 deg | 2.3005 |
| [-10,-8] P95 deg | 1.3848 |
| [8,10] P95 deg | 3.7792 |
| [-2,-0.5] P95 deg | 2.1938 |
| [0.5,2] P95 deg | 2.2941 |
| near-flat abs P95 deg | 2.5140 |
| flat theta bias deg | 0.0235 |

## 测试集混淆矩阵

### 主工况

| true \ pred | flat | stall | slope | recall |
|---|---:|---:|---:|---:|
| flat | 246 | 1 | 509 | 0.3254 |
| stall | 19 | 50 | 27 | 0.5208 |
| slope | 290 | 113 | 2347 | 0.8535 |

| pred class | precision |
|---|---:|
| flat | 0.4432 |
| stall | 0.3049 |
| slope | 0.8141 |

### 转弯方向

| true \ pred | right | straight | left | recall |
|---|---:|---:|---:|---:|
| right | 336 | 321 | 142 | 0.4205 |
| straight | 318 | 1147 | 468 | 0.5934 |
| left | 153 | 289 | 428 | 0.4920 |

| pred class | precision |
|---|---:|
| right | 0.4164 |
| straight | 0.6528 |
| left | 0.4123 |

## 坡度回归范围

- Slope 真值范围: [-9.750, 9.750] deg
- Slope 预测范围: [-11.370, 14.204] deg
- Slope 符号准确率: 0.9589

## 上坡/下坡子项指标

| 子项 | n | slope recall | theta MAE deg | theta sign acc | true theta range deg | pred theta range deg |
|---|---:|---:|---:|---:|---:|---:|
| uphill | 1744 | 0.6841 | 1.0188 | 0.9622 | [0.056, 9.750] | [-2.499, 14.204] |
| downhill | 1762 | 0.9438 | 0.7653 | 0.9557 | [-9.750, -0.235] | [-11.370, 3.217] |
