# 7.6 论文文献检索报告

日期：2026-07-06

后续论文相关工作统一放在：

```text
E:\Matlab\Simulink\S-Function_16\results\paper\7.6
```

## 1. 检索范围

本轮文献检索围绕当前论文的三条预设创新线展开：

1. **ModernTCN 结构优化与算法对比**：包括原始 ModernTCN、GRU、优化后的 ModernTCN，以及 lag / delta-lag / lag-stack 等时序输入增强方式。
2. **MPC 对预测坡度的响应机制**：包括坡度信号进入 MPC 后，对模型扰动、权重调度、控制增益或代价函数的影响。
3. **选择滤波或置信度滤波**：在坡度预测结果进入控制器之前，判断其是否可信、是否需要衰减、是否应切换为保守滤波值。

需要注意：本文档先作为**选题和参考文献池**使用。SCI 3 区 / 4 区结论不能仅依赖公开网页检索，后续还需要按目标投稿年份核验 JCR 或中科院分区。

## 2. 检索策略

主要检索关键词包括：

- `ModernTCN time series`
- `TCN GRU comparison time series`
- `AGV trajectory tracking MPC neural network`
- `LSTM-MPC AGV trajectory tracking`
- `dilated convolution model predictive control vehicle tracking`
- `adaptive MPC intelligent vehicle PSO-BP`
- `road slope estimation GRU deep learning`
- `road grade prediction CNN-LSTM vehicle`
- `Kalman filter neural network road slope vehicle`

检索时优先采用出版社页面、DOI 页面、arXiv / OpenReview 页面和开放获取期刊页面。

## 3. 推荐文献池

| 编号 | 文献 | 来源 / DOI | 在本文中的用途 | 备注 |
|---:|---|---|---|---|
| R01 | Luo D, Wang X. **ModernTCN: A Modern Pure Convolution Structure for General Time Series Analysis**. ICLR, 2024. | https://openreview.net/forum?id=vpJMJerXHU | ModernTCN 算法来源文献。 | 不是 SCI 期刊论文，但必须作为 ModernTCN 方法源头引用。 |
| R02 | Bai S, Kolter JZ, Koltun V. **An Empirical Evaluation of Generic Convolutional and Recurrent Networks for Sequence Modeling**. arXiv, 2018. | https://arxiv.org/abs/1803.01271 | 支撑 TCN 类卷积时序模型与 RNN/GRU/LSTM 对比的理论背景。 | 可用于方法背景，不适合作为目标期刊层级参考。 |
| R03 | Cho K, van Merrienboer B, Gulcehre C, et al. **Learning Phrase Representations using RNN Encoder-Decoder for Statistical Machine Translation**. arXiv, 2014. | https://arxiv.org/abs/1406.1078 | GRU 基础引用。 | 用于介绍 GRU baseline。 |
| R04 | Li Z, Pei R, Zhang Y. **Research on Intelligent Vehicle Tracking Control and Energy Consumption Optimization Based on Dilated Convolutional Model Predictive Control**. *Energies*, 2025. | DOI: 10.3390/en18102588 | 与“膨胀卷积 + MPC + 车辆轨迹跟踪”高度相关。 | 可支撑创新点 1 和创新点 2 的衔接。 |
| R05 | Wan X, Tang Y, Li X, et al. **Trajectory Tracking Method of Four-Wheeled Independent Drive and Steering AGV Based on LSTM-MPC and Fuzzy PID Cooperative Control**. *Electronics*, 2025. | DOI: 10.3390/electronics14102000 | AGV 轨迹跟踪中使用神经网络预测器与 MPC 的直接参考。 | 与本文 AGV + MPC 场景接近。 |
| R06 | Tang L, Yan F, Zou B, Wang K, Lv C. **An Improved Kinematic Model Predictive Control for High-Speed Path Tracking of Autonomous Vehicles Based on Road Friction Coefficient**. *Machines*, 2022. | DOI: 10.3390/machines10040249 | 说明道路条件信息可以进入 MPC 路径跟踪控制。 | 可类比本文的坡度感知 MPC 调度。 |
| R07 | Tang L, Yan F, Zou B, Wang K, Lv C. **Research on Adaptive Path Tracking Control Strategy of Intelligent Vehicle Based on MPC**. *Sensors*, 2023. | DOI: 10.3390/s23010412 | 采用 PSO-BP 调整 MPC 权重系数。 | 对创新点 2 的“自适应 MPC 响应 / 权重调度”很有价值。 |
| R08 | Zhang Q, Zhang T, Wen J. **Enhanced accuracy and adaptability: An ISSA-optimized MPC approach for AGV trajectory tracking**. *PLOS ONE*, 2026. | DOI: 10.1371/journal.pone.0345476 | 较新的 AGV 轨迹跟踪 MPC 优化文献。 | 可作为 SCI 3/4 区风格参考，但分区需要后续核验。 |
| R09 | Li W, Liu S. **Physics-Informed Neural Network-Based Nonlinear Model Predictive Control for Automated Guided Vehicle Trajectory Tracking**. *World Electric Vehicle Journal*, 2024. | DOI: 10.3390/wevj15120569 | 连接 AGV 轨迹跟踪、神经网络建模和 NMPC。 | 若后续讨论物理约束或模型感知控制，可作为参考。 |
| R10 | Zhai J, Wang S, Zhang Q, et al. **Neural Network-Based Model Predictive Trajectory Tracking Control for Dual-Motor-Driven a Tracked Unmanned Vehicle**. *Sensors*, 2025. | DOI: 10.3390/s25226877 | 使用 LSTM 预测与 NMPC 轨迹跟踪。 | 可作为“神经网络预测器 + 控制器”的对照文献。 |
| R11 | Qin Y, He Z, Wang X, et al. **Vehicle Road Grade Prediction Based on CNN-LSTM**. *IFAC-PapersOnLine*, 2023. | DOI: 10.1016/j.ifacol.2023.10.1810 | 与车辆路坡 / 坡度预测直接相关。 | 不是 SCI 期刊论文，但适合作为坡度预测背景。 |
| R12 | Zhu Q, Li L, Xin L, Wang H, Zhang Y. **The Prediction Model for Road Slope of Electric Vehicles Based on Stacking Framework of Deep Learning**. *IEEE Access*, 2023. | IEEE Xplore 文档号疑似为 `10061393`，本轮未完全核验 DOI。 | 涉及 CNN、GRU、CNN-GRU 与堆叠模型的路坡预测比较。 | 与 ModernTCN / GRU / 优化 ModernTCN 对比高度相关，但正式引用前必须核验元数据。 |
| R13 | Feng G, Zhen Y, Chen D. **A Real-Time Road Slope Estimation Based on Multiple Models and Multi-Data Fusion**. *Measurement*, 2021. | DOI: 10.1016/j.measurement.2021.109609 | 支撑实时路坡估计中的多模型融合和滤波思想。 | 可作为创新点 3 的重要背景文献。 |
| R14 | Li J, Zhang H, Ren X, et al. **Short-Term Road Traffic Flow Prediction Based on a Graph Convolutional Network-Gated Recurrent Unit Neural Network Model**. *Scientific Reports*, 2024. | DOI: 10.1038/s41598-024-80563-3 | 展示 GRU 在交通时序预测中的应用。 | 与控制关系较弱，可作为 GRU 时序预测补充文献。 |
| R15 | **Driving Style Recognition Based on TCN and Self-Attention**. *Journal of Advanced Transportation*, 2023. | DOI: 10.1155/2023/1286977 | 展示 TCN 类模型在车辆行为时序特征提取中的应用。 | 可作为 TCN 在车辆领域应用的补充文献。 |

## 4. 与本文创新点的对应关系

### 4.1 创新点 1：ModernTCN 结构优化与算法对比

建议以 R01 作为 ModernTCN 的算法源头文献，以 R02 说明 TCN 类卷积时序模型相对循环网络的比较价值，以 R03 作为 GRU baseline 的基础引用。

用于论文对比叙述时，R04、R05、R10、R11 和 R12 更有价值，因为它们把时序神经网络预测与车辆 / AGV 轨迹跟踪、路坡预测或控制系统联系起来。

建议表述方向：

```text
本文在统一 AGV 闭环评价协议下，对原始 ModernTCN、GRU baseline 和引入滞后表征的优化 ModernTCN 进行比较，而不是仅报告离线预测精度。
```

需要谨慎之处：

```text
当前项目内部证据显示，lag / delta-lag 表征具有平均 J_control 改善潜力，但严格闭环保护路径并非全部通过。
因此论文中不能直接写成“优化 ModernTCN 已无条件替代原始 baseline”，更稳妥的写法是“面向控制闭环的时序表征增强与受保护路径验证”。
```

### 4.2 创新点 2：MPC 对预测坡度的响应方式

最相关的参考文献是 R04、R06、R07、R08、R09 和 R10。

可利用的论证点：

- R04 支持“卷积时序预测 + MPC 车辆跟踪”的组合思路。
- R07 支持“基于学习模型调整 MPC 权重”的思路。
- R06 支持“道路条件信息进入 MPC”的思路。
- R08 支持“AGV 轨迹跟踪中的 MPC 优化”。
- R09 / R10 支持“神经网络模型与 NMPC 结合”的控制框架。

建议表述方向：

```text
本文不将坡度预测仅作为感知输出，而是进一步研究预测坡度进入 MPC 后，控制器应如何调整模型扰动输入、权重或控制惩罚参数，从而改善闭环轨迹跟踪和控制平滑性。
```

### 4.3 创新点 3：选择滤波 / 置信度滤波

当前最有价值的参考文献是 R11、R12 和 R13。

可利用的论证点：

- R11 和 R12 可以说明路坡预测本身是车辆控制中的重要问题。
- R13 可以支撑多模型融合、实时坡度估计和滤波逻辑。
- 如果选择滤波最终会改变 MPC 权重或调度增益，R07 也可以作为控制侧参考。

建议表述方向：

```text
选择滤波模块可被定义为学习坡度输出与 MPC 控制器之间的安全接口：
当预测坡度可信时允许其进入控制调度；
当预测波动过大或置信度不足时，对坡度信号进行衰减、限幅或切换为保守滤波值。
```

## 5. 初步判断

当前更适合的论文主线不是单独声称“提出一个新的 ModernTCN 模型”，而是构建一个面向 AGV 闭环控制的完整框架：

```text
一种面向坡度感知 AGV 轨迹跟踪的控制导向时序预测与 MPC 响应框架，
包括 lag-enhanced ModernTCN 坡度预测、
ModernTCN / GRU / 优化 ModernTCN 的统一对比、
以及面向闭环鲁棒性的 MPC 响应与选择滤波机制。
```

后续最值得做的工作是：

1. 核验候选期刊和候选文献的 JCR / 中科院分区。
2. 从本报告中筛出 8-12 篇作为正式引言和相关工作核心引用。
3. 将项目已有的 ModernTCN、GRU、优化 ModernTCN 闭环结果整理成论文结果表。
4. 明确第二创新点中 MPC 响应策略的最终形式，例如 `rho_f(:,3)` 同步、`dR` 调度、权重调度或组合策略。
5. 为第三创新点设计一个可验证、不过度复杂的选择滤波实验。
