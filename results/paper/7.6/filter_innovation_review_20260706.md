# 第三创新点：选择滤波 / 多模型切换文献与方案分析

日期：2026-07-06

## 1. 问题定义

导师提出的思路可以概括为：

```text
当 AGV 在线运行过程中，优化 ModernTCN 的坡度输出不可信或偏差可能过大时，
不要继续无条件使用该输出，而是切换到其他算法，或对多个算法输出进行融合。
```

这个思路不是传统意义上只做低通滤波，而更接近：

```text
置信度驱动的选择预测
多模型动态选择
异常输出拒绝机制
鲁棒滤波
多模型概率融合
```

因此，建议论文中把第三创新点命名为：

```text
置信度-残差驱动的坡度选择滤波机制
```

或英文：

```text
confidence- and residual-aware selective slope filtering
```

## 2. 与导师想法相近的文献

| 编号 | 文献 | 方法关键词 | 与本文的关系 |
|---:|---|---|---|
| F01 | Geifman Y, El-Yaniv R. **Selective Classification for Deep Neural Networks**. NeurIPS, 2017. arXiv:1705.08500. | selective classification, reject option | 深度网络在不确定时可以拒绝预测。可支撑“ModernTCN 不可信时不直接使用”的理论基础。 |
| F02 | Geifman Y, El-Yaniv R. **SelectiveNet: A Deep Neural Network with an Integrated Reject Option**. ICML, 2019. arXiv:1901.09192. | selective prediction, integrated reject option | 比单纯阈值更进一步，把“是否接受预测”作为模型的一部分学习。可作为后续扩展方向。 |
| F03 | Reisinger M, et al. **A two-layer switching based trajectory prediction method for autonomous vehicles**. *European Journal of Control*, 2021. DOI: 10.1016/j.ejcon.2021.06.011. | switching prediction, physics-based model, maneuver model | 自动驾驶预测中，根据场景切换物理模型和行为模型。与“ModernTCN 异常时切换其他算法”思想相近。 |
| F04 | Jo K, Kim J, Sunwoo M. **Real-Time Road-Slope Estimation Based on Integration of Onboard Sensors With GPS Using an IMMPDA Filter**. *IEEE Transactions on Intelligent Transportation Systems*, 2013. DOI: 10.1109/TITS.2013.2266438. | IMMPDA, PDAF, interacting multiple model, road slope | 直接是路坡估计；使用概率数据关联和交互多模型滤波融合多种坡度测量，并能剔除故障测量。非常适合作为第三创新点背景。 |
| F05 | Feng G, Zhen Y, Chen D. **A Real-Time Road Slope Estimation Based on Multiple Models and Multi-Data Fusion**. *Measurement*, 2021. DOI: 10.1016/j.measurement.2021.109609. | multiple models, multi-data fusion, road slope | 直接支持“多模型坡度估计 / 融合”的思路。可与本文的 ModernTCN/GRU/原始 ModernTCN 输出融合对应。 |
| F06 | Guo J, He C, Li J, Wei H. **Slope Estimation Method of Electric Vehicles Based on Improved Sage-Husa Adaptive Kalman Filter**. *Energies*, 2022. DOI: 10.3390/en15114126. | Sage-Husa adaptive Kalman filter, road slope | 说明坡度估计中可以动态调整滤波噪声统计特性，适合支撑“自适应滤波”而不是固定低通滤波。 |
| F07 | Zha Y, Liu X, Ma F, Liu CC. **Vehicle state estimation based on extended Kalman filter and radial basis function neural networks**. *International Journal of Distributed Sensor Networks*, 2022. DOI: 10.1177/15501329221102730. | EKF, RBF neural network, multi-source fusion | 提供“模型滤波器 + 神经网络估计器”的融合范式，可类比 ModernTCN 与传统/备用算法融合。 |
| F08 | Qi D, Feng J, Li Y, Wang L, Song B. **A Robust Hierarchical Estimation Scheme for Vehicle State Based on Maximum Correntropy Square-Root Cubature Kalman Filter**. *Entropy*, 2023. DOI: 10.3390/e25030453. | maximum correntropy, square-root cubature Kalman filter, non-Gaussian noise | 较新的鲁棒滤波方向，适合处理异常值和非高斯噪声。可作为“新型鲁棒滤波模型”的参考。 |
| F09 | Tan C, Cai Y, Wang H, et al. **Vehicle State Estimation Combining Physics-Informed Neural Network and Unscented Kalman Filtering on Manifolds**. *Sensors*, 2023. DOI: 10.3390/s23156665. | PINN, UKF-M, vehicle state estimation | 代表“神经网络 + UKF”的混合估计方向。若论文想写得更前沿，可作为参考。 |
| F10 | Liu G. **Estimation of Vehicle Mass and Road Slope for Commercial Vehicles Utilizing an Interacting Multiple-Model Filter Method Under Complex Road Conditions**. *World Electric Vehicle Journal*, 2025. DOI: 10.3390/wevj16030172. | IMM, CKF, complex road slope | 很贴近本文坡度场景；通过 IMM 在不同坡度/行驶工况下为不同模型分配权重。 |
| F11 | Carvalho H D P, Oliveira J F L, Fagundes R A A. **Dynamic selection of ensemble-based regression models: Systematic literature review**. *Expert Systems with Applications*, 2025. DOI: 10.1016/j.eswa.2025.128429. | dynamic ensemble selection, regression | 支持“每个时刻动态选择更合适的回归模型”的方法论背景。 |

## 3. 这些文献对本文的启发

### 3.1 导师建议是合理的，但不应只做硬切换

导师的建议“ModernTCN 偏差过大时选择其他算法”是合理的，并且可以找到对应的学术支撑：

- selective prediction / reject option：模型不确定时拒绝使用该预测；
- dynamic ensemble selection：不同输入区域由不同模型负责；
- IMM / PDAF：根据概率权重选择或融合不同模型 / 测量源；
- robust Kalman filtering：检测异常创新项，并降低异常测量对状态估计的影响。

但如果直接硬切换：

```text
ModernTCN 不好 -> 立刻切换到 GRU
```

会有三个问题：

1. 在线运行时没有真实坡度，因此不能直接知道 ModernTCN 的真实误差。
2. 硬切换容易造成坡度输入跳变，反而刺激 MPC。
3. 切换规则如果只靠经验阈值，审稿人会质疑泛化性。

因此，更推荐使用：

```text
置信度 + 模型分歧 + 物理变化率 + 控制残差
```

构成一个选择滤波器，而不是只做简单 if-else。

## 4. 可选实现路线

### 4.1 路线 A：硬选择滤波

基本逻辑：

```text
默认使用优化 ModernTCN；
如果优化 ModernTCN 输出被判定为不可信，则切换到原始 ModernTCN 或 GRU；
切换后保持一段 dwell time，避免频繁抖动。
```

优点：

- 逻辑清楚；
- 容易解释；
- 实现成本低；
- 与导师原始建议最接近。

缺点：

- 切换边界可能产生跳变；
- 阈值敏感；
- 审稿人可能认为是工程规则，不够“创新”。

适合定位：

```text
baseline filter / ablation control
```

不建议作为最终主方案。

### 4.2 路线 B：软融合选择滤波

基本逻辑：

```text
同时计算优化 ModernTCN、原始 ModernTCN、GRU 的坡度输出；
根据每个模型当前可信度分配权重；
输出加权融合后的坡度。
```

可写成：

```text
theta_sel(k) = w_opt(k) * theta_opt(k)
             + w_base(k) * theta_base(k)
             + w_gru(k) * theta_gru(k)
```

其中权重由以下因素决定：

```text
模型置信度
模型之间的输出分歧
相邻时刻坡度变化率
当前工况类别
历史验证集中该工况下的模型可靠性
```

优点：

- 比硬切换平滑；
- 更符合 IMM / 多模型融合思想；
- 更容易写成论文创新点。

缺点：

- 需要设计权重计算；
- 需要避免过多经验参数。

推荐作为主方案。

### 4.3 路线 C：创新项自适应 Kalman 滤波

基本逻辑：

把优化 ModernTCN、原始 ModernTCN、GRU 的输出看成多个“测量值”，用滤波器估计最终进入 MPC 的坡度：

```text
theta_f(k) = filter(theta_opt(k), theta_base(k), theta_gru(k), theta_f(k-1))
```

当某个模型输出与预测值差异过大时，不是立刻切换，而是增大该模型的测量噪声：

```text
innovation_i(k) = theta_i(k) - theta_f(k|k-1)
R_i(k) ↑ if |innovation_i(k)| is abnormal
```

优点：

- 学术上更像“滤波创新点”；
- 可自然处理异常输出；
- 可和 Sage-Husa、IMM、MCC-SRCKF 等文献连接。

缺点：

- 实现和解释比路线 B 稍复杂；
- 如果只靠离线乱序窗口验证，会再次遇到 E5 的证据问题。

适合最终版本：

```text
路线 B + 简化 Kalman / 自适应一阶滤波
```

## 5. 推荐给本文的最终方案

推荐第三创新点采用：

```text
CRSF：Confidence-Residual Selective Filtering
置信度-残差驱动的坡度选择滤波
```

### 5.1 输入

每个仿真步 `k` 计算：

```text
theta_opt(k)   优化 ModernTCN 坡度输出
theta_base(k)  原始 ModernTCN 坡度输出
theta_gru(k)   GRU 坡度输出
conf_main(k)   主工况分类置信度
conf_turn(k)   转向分类置信度
theta_f(k-1)   上一时刻进入 MPC 的滤波坡度
```

如果在线可用，也可以加入：

```text
e_y(k), e_psi(k), omega_cmd(k), F_cmd(k)
```

但必须确认这些量在时间 `k` 是在线可得，不能使用未来轨迹、oracle theta 或真实坡度。

### 5.2 异常判据

不要使用真实误差，因为在线没有真实坡度。建议使用以下代理指标：

```text
1. 低置信度：
   conf_main(k) < tau_main 或 conf_turn(k) < tau_turn

2. 模型分歧过大：
   max(|theta_opt - theta_base|, |theta_opt - theta_gru|) > tau_disagree

3. 物理变化率异常：
   |theta_opt(k) - theta_f(k-1)| / dt > tau_rate

4. 工况一致性异常：
   模型预测为 flat，但 theta_opt 绝对值过大；
   或模型预测为 slope，但 theta_opt 接近 0 且持续多个采样点。

5. 控制残差异常：
   e_y / e_psi / omega_cmd_rms 在短窗口内明显恶化。
```

### 5.3 输出规则

建议避免直接跳变，使用加权融合 + 限速：

```text
theta_mix(k) = sum_i w_i(k) * theta_i(k)

theta_out(k) = theta_out(k-1)
             + clip(alpha(k) * [theta_mix(k) - theta_out(k-1)],
                    -r_max * dt,
                    +r_max * dt)
```

其中：

```text
i ∈ {opt, base, gru}
w_i(k) 由置信度、模型分歧、工况可靠性共同决定
alpha(k) 在低置信度时减小
r_max 是坡度变化率上限
```

### 5.4 防止切换抖动

加入：

```text
1. hysteresis：进入异常和退出异常使用不同阈值；
2. dwell time：切换后至少保持 N 个采样点；
3. no-cross-run inheritance：不同 path/run 开始时重置滤波状态；
4. saturation：限制 theta_out 的物理范围。
```

## 6. 为什么不建议直接复用旧 E5

项目里已经有过 `05_confidence_scheduling`，但它不能直接作为第三创新点的成功证据。

原因：

```text
1. E5 是 offline safety screen，没有进入 sandbox closed-loop。
2. test split 不是可靠连续 replay，run_id 交错。
3. step/smoothness 指标只能 advisory。
4. 所有五个配置 offline_safe=false。
5. rate_limit_only_d01 也没有通过安全筛选。
```

因此，如果第三创新点继续做滤波，必须换一种证据链：

```text
在 Simulink 闭环仿真中实时运行滤波器；
或者先生成具备 sample_id / window_start_idx / global_time_idx 的连续 replay 数据。
```

不要把旧 E5 结果升级成正式成功。

## 7. 论文实验设计建议

第三创新点至少需要以下对照：

| 组别 | 含义 |
|---|---|
| G0 | 无滤波，直接使用优化 ModernTCN 输出 |
| G1 | 固定一阶低通 / rate limit |
| G2 | 硬切换：异常时切到原始 ModernTCN 或 GRU |
| G3 | 软融合：置信度-残差加权融合 |
| G4 | 软融合 + 限速 + hysteresis，作为最终 CRSF |

评价指标：

```text
theta_mae_deg
theta_edge_p95_abs_err
flat_peak_theta_error
theta_step_p95_abs_deg
ey_rmse
xy_rmse
epsi_rmse
j_du
omega_cmd_rms
J_control
path_catastrophic
switch_count
switch_rate
dwell_violation_count
```

建议先在这些路径上验证：

```text
path_closed_loop_long_updown_theta10_v1
path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1
path_factory_target_downhill_straight_after_turn_v1
```

这些路径正好覆盖此前 lag-enhanced ModernTCN 的主要失败模式。

## 8. 初步结论

导师提出的“ModernTCN 输出偏差过大时选择其他算法”方向是有文献基础的，但建议不要直接做成简单硬切换。

更适合本文的第三创新点是：

```text
基于置信度、模型分歧和物理残差的坡度选择滤波，
在优化 ModernTCN、原始 ModernTCN 和 GRU 之间进行动态加权融合，
并通过限速和滞回机制保证进入 MPC 的坡度信号连续、可信和控制友好。
```

这样做的优点是：

1. 与导师建议一致；
2. 能和多模型融合、selective prediction、IMM/Kalman 滤波文献对应；
3. 不会退化成简单低通滤波；
4. 能自然连接前两个创新点：
   - 优化 ModernTCN 提供更强预测；
   - MPC 响应机制使用 `rho_f(:,3)`；
   - 选择滤波负责保证输入 MPC 的坡度信号可靠。

后续实施时，最重要的边界是：

```text
所有触发信号必须在线可用；
不能使用真实坡度、未来参考路径或离线 oracle；
旧 E5 只能作为反例和设计教训，不能作为成功证据。
```
