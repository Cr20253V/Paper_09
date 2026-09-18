# 创新点2方法正文与实验章节呼应约定

日期：2026-07-12

适用项目：

```text
E:\Matlab\Simulink\S-Function_16
```

本文档用于在不同对话中继续撰写创新点2时保持术语、公式、图表和结论一致。后续开始撰写创新点2正文或实验章节前，应先阅读本文档。

## 0. 当前实施状态

截至2026-07-12，创新点2方法正文已经写入：

```text
results/paper/Latex/paper_v2.tex
```

已完成：

1. `Dynamics-Informed 22-D Proprioceptive Feature Construction`；
2. `Multi-Scale Lag and Delta-Lag Representation`；
3. `Historical Window Assembly and Online Input Contract`；
4. 22维特征表；
5. 双面板矢量流程图；
6. 将LPV-MPC重新划分为后续独立章节；
7. 停用旧版19维 `Multi-Task Temporal Scheduling Perception` 章节。

流程图文件：

```text
results/paper/Latex/fig_dynamics_delta_bank_pipeline.tex
results/paper/Latex/fig_dynamics_delta_bank_pipeline.pdf
```

尚待实验章节完成：

1. 128步窗口的参数化数值计算；
2. lag/delta-lag候选表征实验协议；
3. baseline与`delta_bank_124`的10-seed成对图；
4. 严格闭环门槛、失败路径和结论边界说明。

## 1. 已确认的创新点2定位

创新点2不是新的网络主干，而是面向坡度估计的输入构造方法：

```text
基于AGV动力学构造22维本体感知特征，
并通过多尺度lag/delta-lag表征和固定历史窗口，
向轻量化ModernTCN提供同时包含当前状态、局部变化率和历史上下文的输入。
```

建议英文标题：

```text
Dynamics-Informed Feature Construction and Multi-Scale Delta-Lag Representation
```

创新点1已经介绍坡度估计目标和轻量化ModernTCN，因此创新点2不重复介绍完整网络结构，也不再次强调多任务输出。

## 2. 方法正文的三小节结构

### A. Dynamics-Informed 22-D Proprioceptive Feature Construction

写作任务：

1. 从AGV模型中的纵向阻力、轮荷变化、驱动响应和转向耦合出发，说明为什么单一瞬时变量不足以表征坡度。
2. 给出特征选择原则：车载可测、动态时间尺度相关、物理机制互补、无真实坡度泄漏。
3. 定义基础向量 `x_k in R^22`。
4. 按四组介绍22维变量及其物理作用。
5. 明确不输入真实坡度、IMU直接坡度/俯仰估计、全局位姿、质心侧偏角和轮荷。

四组特征固定为：

| 分组 | 维数 | 特征 |
|---|---:|---|
| 原始车载测量 | 7 | `gyro_z`, `I_lf`, `I_rr`, `omega_wheel_lf`, `omega_wheel_rr`, `delta_lf`, `delta_rr` |
| 运动学与多频带响应 | 5 | `v_hat`, `dv_hat_dt`, `dv_hat_dt_lp`, `a_hp`, `accel_x_wheel` |
| 双轮对称性与驱动力分配 | 5 | `ws_imbalance`, `I_sum`, `I_diff_signed`, `I_diff_abs`, `I_drive_signed` |
| 负载与运动学一致性代理量 | 5 | `accel_per_current`, `current_per_accel`, `drive_load_proxy`, `kappa_proxy`, `yaw_consistency_error` |

总维数：

```text
7 + 5 + 5 + 5 = 22
```

注意：`gyro_z`是横摆角速度测量，不是IMU直接坡度或俯仰角通道，因此不违反“无直接坡度测量”的设定。

### B. Multi-Scale Lag and Delta-Lag Representation

写作任务：

1. 说明瞬时状态同时受驱动、制动、转向和路面瞬态影响，不能只凭 `x_k` 区分持续坡度响应。
2. 区分状态记忆和变化量表征：lag保留历史状态，delta-lag突出相邻时间尺度上的变化。
3. 定义实验中使用过的候选表征。
4. 将 `delta_bank_124` 定义为本文最终采用的多尺度差分输入。

归一化基础特征记为：

```math
z_k = N(x_k) in R^22.
```

多尺度差分定义为：

```math
\Delta_\ell \mathbf z_k = \operatorname{clip}
(\mathbf z_k - \mathbf z_{k-\ell}, -5, 5),
\qquad \ell \in \{1,2,4\}.
```

最终单时刻输入为：

```math
\widetilde{\mathbf z}_k =
[\mathbf z_k,\Delta_1\mathbf z_k,\Delta_2\mathbf z_k,\Delta_4\mathbf z_k]
\in \mathbb R^{88}.
```

所有差分均在训练集归一化后的空间中计算。序列起点使用edge padding，不允许引入未来样本。

候选表征及维数：

| 名称 | 定义 | 维数 |
|---|---|---:|
| raw baseline | `[z_k]` | 22 |
| `delta_lag1_44d` | `[z_k, Delta_1 z_k]` | 44 |
| `lag_stack_124` | `[z_k, z_{k-1}, z_{k-2}, z_{k-4}]` | 88 |
| `delta_bank_124` | `[z_k, Delta_1 z_k, Delta_2 z_k, Delta_4 z_k]` | 88 |
| `mixed_lag_delta_14` | `[z_k, z_{k-1}, z_{k-4}, Delta_1 z_k, Delta_4 z_k]` | 110 |

### C. Historical Window Assembly and Online Input Contract

最终窗口固定为：

```text
sampling time Ts = 0.01 s
window length L = 128 samples
window duration = 1.28 s
single-step augmented dimension = 88
ModernTCN input tensor = 128 x 88
```

建议方法正文使用以下逻辑，但不要在此处展开完整计算：

```text
The historical length is fixed at 128 samples, corresponding to 1.28 s at the
0.01-s sampling interval. This duration is selected from the characteristic
time over which grade-induced longitudinal resistance produces an observable
change in the onboard dynamic responses at representative AGV speed and road
grade. The parameter-based calculation is provided in the experimental setup.
```

允许使用的动词：

```text
selected, configured, determined from, derived from, fixed at
```

暂不使用：

```text
optimal, globally optimal, experimentally optimal, best window length
```

这里不主动强调“没有窗口消融”。只需要将窗口定位为基于动力学时间尺度的设计选择，并把具体计算指向实验设置章节。

## 3. 实验章节必须补写的窗口长度说明

实验设置中增加一个小节，例如：

```text
Physics-Based Determination of the Historical Window
```

该小节必须包含：

1. 代表性运行速度 `v_c` 的来源，例如训练和测试路径中的典型速度区间 `0.8-1.1 m/s`。
2. 代表性非零坡度 `theta_c` 的来源，例如训练坡度范围或典型坡段。
3. AGV参数：`m`, `m_eff`, `g`, `r`, `I_w`, `I_m`, `n_g`, `T_s`。
4. 坡度力和特征响应时间公式。
5. 连续时间长度如何转换为离散窗口长度128。
6. 最终说明1.28 s同时覆盖局部差分尺度和持续坡度响应，但不声称它是所有路线的全局最优值。

建议的公式骨架为：

```math
m_{\mathrm{eff}} = m + \frac{2(I_w + I_m n_g^2)}{r^2},
```

```math
F_\theta(\theta_c) = m g |\sin(\theta_c)|,
```

```math
T_\theta = \frac{m_{\mathrm{eff}}\Delta v_{\mathrm{char}}}
{F_\theta(\theta_c)},
```

```math
L_{\mathrm{raw}} = \left\lceil\frac{T_\theta}{T_s}\right\rceil,
\qquad
L = \mathcal Q(L_{\mathrm{raw}}),
```

其中 `Delta v_char` 是用于表征坡度影响的特征速度变化尺度，`Q(.)` 表示将连续估算值映射到实现兼容的窗口长度。最终实验撰写前必须用实际代表性速度、坡度和AGV参数完成数值核算，不能为了得到128而反向选择参数。

可选增强：在实验设置中给出一个小表，列出 `v_c`, `theta_c`, `m_eff`, `T_theta`, `T_s`, `L_raw`, `L=128`。这属于参数化设计说明，不是窗口消融实验。

## 4. 方法正文与实验章节的呼应矩阵

| 方法正文中的陈述 | 实验章节对应内容 | 项目证据来源 | 允许结论 |
|---|---|---|---|
| 22维变量由AGV动力学构造 | 22维特征表和可测性说明 | `输入选取.tex`, dataset config | 特征具有物理来源和在线可用性 |
| 多尺度差分突出短期动态 | lag 1/2/4及候选表征定义 | Node23/25配置 | 表征覆盖10/20/40 ms局部变化 |
| `delta_bank_124`作为最终输入 | 离线10-seed成对比较 | Node19与Node25训练结果 | 平均坡度误差和边缘误差总体改善 |
| 新表征提高跨种子整体稳定性 | Node30 10-seed完整闭环汇总 | Node30 decision CSV | 在测试表征中具有更低平均J和更小波动 |
| 窗口固定为128步 | 参数化窗口计算 | `parameters.m`, 路径速度/坡度 | 1.28 s是物理时间尺度驱动的工程选择 |
| 表征改善不等于所有闭环种子都胜出 | 严格门槛和失败路径表 | Node30 report | 结论限定为aggregate/stability advantage |

## 5. 图表安排

### 5.1 方法正文主图：必须创建

建议图名：

```text
Dynamics-informed feature construction and multi-scale delta-lag representation.
```

建议采用一个双栏宽、两面板的矢量流程图。

Panel (a)：物理机制到22维特征

```text
AGV slope-sensitive dynamics
  -> longitudinal resistance / drive load / wheel asymmetry / yaw-steering coupling
  -> four feature groups (7 + 5 + 5 + 5)
  -> 22-D proprioceptive vector x_k
```

Panel (b)：22维到128 x 88输入张量

```text
22-D x_k
  -> train-set normalization z_k
  -> Delta_1 / Delta_2 / Delta_4 branches
  -> concatenate to 88-D z_tilde_k
  -> stack 128 historical steps
  -> 128 x 88 ModernTCN input
```

图中必须明确：

1. 22维是基础物理变量维数。
2. 88维是单时刻增强后的维数。
3. 128是历史步数，不是特征维数。
4. 不包含真实坡度和IMU直接坡度/俯仰通道。
5. 流程图终点是ModernTCN输入，不重复绘制创新点1中的网络内部结构。

实现定义注意事项：

```text
ws_imbalance = abs(omega_wheel_lf - omega_wheel_rr)
I_sum = abs(I_lf) + abs(I_rr)
I_diff_abs = abs(I_lf) - abs(I_rr)
kappa_proxy = (tan(delta_lf) - tan(delta_rr)) / W
drive_load_proxy = I_drive_signed - dv_hat_dt_lp
yaw_consistency_error = gyro_z - v_hat * kappa_proxy
```

因此，`kappa_proxy`必须称为转向几何曲率代理，不能称为纵向滑移率；
`I_diff_abs`是两轮电流绝对值之差，不是电流差的绝对值；
`yaw_consistency_error`是测量横摆率减去几何预测横摆率。

视觉规范：

```text
全图左到右阅读；
四组特征使用四种低饱和度颜色；
归一化和拼接使用中性绿色；
delta分支使用同一色系的深浅变化；
禁用渐变、阴影和装饰性图标；
节点圆角不超过2-3 pt；
同层节点等宽、等高、等间距；
在线主路径用实线，排除通道或说明用灰色虚线；
所有关键张量在箭头上直接标注维数。
```

### 5.2 原计划的10-seed结果分布图：移到实验章节

不建议在创新点2的理论方法正文中放完整10-seed结果分布图。原因不是结果“难看”，而是方法章节的任务是定义表征，详细跨种子结果本来就应由实验章节承担。

理论部分如果版面需要第二张图，可改为：

```text
Illustration of multi-scale delta responses around a slope transition
```

该图只展示一个代表性归一化信号在 `Delta_1`, `Delta_2`, `Delta_4` 下的响应差异，用于解释不同尺度分别强调快速变化和较慢趋势。它不能包含完整算法排名，也不能用单个seed宣称总体性能。

### 5.3 实验章节的10-seed主图：推荐成对seed图

推荐使用paired-seed slope plot或individual points + mean/CI，而不是只画通过数量。

主面板建议：

```text
(a) Baseline 22-D vs delta_bank_124 theta MAE for the same 10 seeds
(b) Baseline 22-D vs delta_bank_124 edge P95 error for the same 10 seeds
```

当前项目数据支持：

```text
theta MAE improved in 8/10 paired seeds;
edge P95 error improved in 9/10 paired seeds;
mean theta MAE: approximately 0.65 deg -> 0.60 deg;
best theta MAE: approximately 0.57 deg -> 0.52 deg.
```

这种图比单纯柱状图更有说服力，因为它保留了种子对应关系，也不会用均值掩盖个别退化seed。

闭环结果建议放在同一实验小节的表格或次级面板中：

```text
delta_bank_124: mean J_control about 0.728, std about 0.070
delta_lag1_44d: mean J_control about 0.786, std about 0.12
lag_stack_124: mean J_control about 0.877, std about 0.13
```

严格晋级结果仍需在表格或正文中披露：`delta_bank_124`仅3/10个seed通过全部路径门槛。因此图中可以突出总体改善和成对seed变化，但不能隐藏严格门槛结论，也不能写成所有seed均优于原算法。

## 6. 推荐的结果叙述边界

允许：

```text
The multi-scale delta-bank representation reduced the mean slope-regression
error and improved most paired-seed results relative to the unaugmented input.

Among the evaluated temporal representations, delta_bank_124 achieved the
lowest mean closed-loop score and the smallest cross-seed dispersion.
```

不允许：

```text
delta_bank_124 passed all closed-loop tests;
delta_bank_124 was superior for every seed and every route;
the 128-step window was experimentally proven optimal;
the lag representation guarantees closed-loop improvement.
```

建议的边界句：

```text
The aggregate improvement did not translate into universal per-seed dominance
under the strict worst-path promotion rule, indicating that temporal input
representation and closed-loop scheduling robustness should be evaluated
separately.
```

## 7. 参考图示逻辑

已检查项目中保存的以下原始论文：

```text
results/paper/Latex/reference/引言中使用的参考文献/
ModernTCN_ A Modern Pure Convolution Structure for General Time Series Analysis.pdf

results/paper/7.6/
Lag-Enhanced LSTM for Power Grid Frequency Prediction.pdf

results/paper/Latex/reference/使用离散系统相关论文/
Road Slope Prediction and Vehicle Dynamics Control for Autonomous Vehicles.pdf
```

可借鉴的逻辑：

1. ModernTCN使用并列小面板区分时间卷积、特征混合和完整模块，并在图中标注张量维度；本文应借鉴这种“不同维度分开表达”的方式。
2. Lag-Enhanced LSTM先用时间滞后关系图解释为什么选lag，再把性能结果放到后面的实验图；本文也应把表征机理与10-seed结果分开。
3. 车辆坡度与控制类论文通常使用“传感器/动力学来源 -> 估计器 -> 控制接口”的分层流程，不在方法总图中塞入完整指标表。

## 8. 后续新对话的执行顺序

```text
1. 阅读本文档；
2. 检查paper_v2.tex中创新点1结尾和LPV段落位置；
3. 绘制创新点2双面板矢量流程图；
4. 撰写A：22维特征构造；
5. 撰写B：multi-scale lag/delta-lag；
6. 撰写C：128步窗口和在线输入契约；
7. 将当前LPV/MPC段落继续后移到创新点4；
8. 实验章节按本文档第3-6节补写对应验证。
```

## 9. 关键项目文件

```text
results/paper/Latex/paper_v2.tex
results/paper/Latex/输入选取.tex
src/core/parameters.m
results/modern_tcn_metric_rebuild/23_delta_lag_ablation_modern_small/
results/modern_tcn_metric_rebuild/25_lag_representation_repair/
results/modern_tcn_metric_rebuild/30_rhofmd_lag_rescreen/
results/modern_tcn_metric_rebuild/19_fair_10seed_selection_and_final_test_path_extension/
```
