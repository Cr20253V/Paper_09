# 新对话交接文本：第三创新点选择滤波实验

请在新对话中直接复制以下内容作为任务说明。

---

## 任务背景

当前项目路径：

```text
E:\Matlab\Simulink\S-Function_16
```

后续论文相关工作统一放在：

```text
E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild
可以按照序号依次向下新建文件夹。
```

本论文计划写 SCI 3 区或 4 区，当前定位是：

```text
面向坡度感知 AGV 轨迹跟踪的控制导向时序预测与 MPC 响应框架
```

已有两个创新点：

1. **ModernTCN 结构优化与算法对比**  
   在原始 ModernTCN、GRU、优化 ModernTCN 之间做闭环比较；优化 ModernTCN 包括 lag / delta-lag / lag-stack 等滞后表征增强。

2. **MPC 对预测坡度的响应机制**  
   重点包括 `rho_f(:,3)` 与 Adaptive MPC measured disturbance 同步，以及坡度触发的 MPC 响应 / `dR` 调度思路。

现在要做第三个创新点：

```text
置信度-残差驱动的坡度选择滤波机制
Confidence-Residual Selective Filtering, CRSF
```

目标是在 AGV 在线运行中，当优化 ModernTCN 的坡度输出不可信时，不再无条件使用它，而是在多个坡度源之间进行选择、融合和限速，使进入 MPC 的坡度信号更可靠、更平滑、更控制友好。

## 必须先阅读的现有文档

请先只读阅读这些文件：

```text
results\paper\7.6\literature_search_report_20260706.md
results\paper\7.6\filter_innovation_review_20260706.md
results\modern_tcn_metric_rebuild\24_delta_lag1_closed_loop_44d\README.md
results\modern_tcn_metric_rebuild\README_MPC_CONTROLLER_REPAIR_STATUS.md
results\modern_tcn_sci_innovation\05_confidence_scheduling\confidence_scheduling_summary.md
results\modern_tcn_sci_innovation\05_confidence_scheduling\confidence_scheduling_decision.json
```

如果要查已有诊断信号，可优先看：

```text
results\modern_tcn_metric_rebuild\30_rhofmd_lag_rescreen\
results\modern_tcn_metric_rebuild\31_showcase_factory_eyepsi_repair\
src\Compare\compare_tcn_gru_modern_closed_loop_out.m
```

## 关于 IMU 原始坡度输出的新增要求

用户希望在原来的三类坡度输出基础上，增加一个 **IMU 原始坡度输出**：

```text
theta_opt   = 优化 ModernTCN 输出
theta_base  = 原始 ModernTCN 输出
theta_gru   = GRU 输出
theta_imu   = IMU 原始坡度输出
```

这个想法原则上可行，但必须先做合法性审计。

### 可以使用的情况

`theta_imu` 可以作为第四个滤波输入源，前提是它满足：

```text
1. 在线可用；
2. 只使用当前时刻或过去时刻 IMU 测量；
3. 不包含未来参考路径；
4. 不包含仿真 oracle 坡度；
5. 不等同于标签 / 真值 / theta_ref；
6. 在 Simulink 闭环中能以与其他坡度源相同时间基准对齐。
```

如果满足这些条件，论文中可以把它定义为：

```text
raw IMU-based slope measurement
```

并作为 CRSF 的一个候选测量源。

### 禁止使用的情况

如果所谓 IMU 原始坡度实际来自以下来源，则不能作为在线滤波输入：

```text
theta_ref
run.theta
run.y_theta_ground
oracle theta
未来路径信息
未来控制输入
未来误差
任何真实坡度标签
```

项目历史中还曾明确禁止把 `y_raw(:,9)`、`y_raw(:,10)`、`y_raw(:,16)` 作为学习模型输入。新实验如果想使用这些信号，必须先确认它们是否只是在线 IMU 测量，而不是标签或泄漏源；即使合法，也建议只作为滤波器的在线测量源，不要直接加入 ModernTCN 训练输入。

## 当前旧 E5 不能直接复用为成功证据

项目里已经有过：

```text
results\modern_tcn_sci_innovation\05_confidence_scheduling
```

但它不能直接作为第三创新点成功证据，原因：

```text
1. 旧 E5 是 offline safety screen；
2. 没有进入 sandbox closed-loop；
3. test split 不是可靠连续 replay；
4. run_id 交错，step / smoothness 指标只能 advisory；
5. 五个配置全部 offline_safe=false；
6. rate_limit_only_d01 也没有通过安全筛选。
```

旧 E5 可以作为反例和设计教训，不能写成成功结果。

## 建议的第三创新点方法

推荐方法：

```text
CRSF：Confidence-Residual Selective Filtering
置信度-残差驱动的坡度选择滤波
```

基本输出形式：

```text
theta_mix(k) =
    w_opt(k)  * theta_opt(k)
  + w_base(k) * theta_base(k)
  + w_gru(k)  * theta_gru(k)
  + w_imu(k)  * theta_imu(k)

theta_out(k) =
    theta_out(k-1)
  + clip(alpha(k) * [theta_mix(k) - theta_out(k-1)],
         -r_max * dt,
         +r_max * dt)
```

`theta_out(k)` 是最终送入 MPC / `rho_f(:,3)` 调度链路的坡度信号。

## 在线风险分数建议

不要使用真实坡度误差判断“偏差过大”，因为在线运行时没有真实坡度。建议使用在线可用代理量：

```text
low_confidence:
  conf_main(k) 或 conf_turn(k) 过低

model_disagreement:
  theta_opt 与 theta_base / theta_gru / theta_imu 差异过大

theta_rate_abnormal:
  theta_opt(k) 相对 theta_out(k-1) 变化过快

mode_theta_inconsistency:
  flat 工况却输出大坡度，或 slope 工况坡度长期接近 0

imu_outlier:
  theta_imu 与其他模型输出或上一时刻滤波输出差异过大

control_residual:
  若在线可用，短窗口 e_y / e_psi / omega_cmd 明显恶化
```

可以先实现一个简单风险分数：

```text
risk(k) =
    a1 * low_confidence
  + a2 * model_disagreement
  + a3 * theta_rate_abnormal
  + a4 * mode_theta_inconsistency
  + a5 * imu_outlier
```

然后由 `risk(k)` 决定权重：

```text
risk 低：主要相信 theta_opt
risk 中：theta_opt、theta_base、theta_gru、theta_imu 软融合
risk 高：降低 theta_opt 权重，更多使用稳定源或保守滤波值
```

## 对照实验设计

至少设置以下组别：

| 组别 | 含义 |
|---|---|
| G0 | 无滤波，直接使用优化 ModernTCN 输出 |
| G1 | 固定一阶低通 / rate limit |
| G2 | 硬切换：异常时切到原始 ModernTCN、GRU 或 IMU |
| G3 | 软融合：按置信度和分歧加权融合多个坡度源 |
| G4 | 软融合 + 限速 + hysteresis + dwell time，作为最终 CRSF |

如果 IMU 原始坡度审计通过，再增加：

| 组别 | 含义 |
|---|---|
| G5 | CRSF-IMU：G4 基础上加入 `theta_imu` 第四输入源 |

论文主推不应是 G2 硬切换，而应是 G4 或 G5。

## 首轮实验范围

先不要跑全量。建议首轮只跑保护路径和少量 seed：

```text
paths:
  path_closed_loop_long_updown_theta10_v1
  path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1
  path_factory_target_downhill_straight_after_turn_v1

seeds:
  42
  520
  必要时加 1
```

这些路径覆盖此前 lag-enhanced ModernTCN 的主要失败模式。

首轮目标不是发论文最终结果，而是判断：

```text
1. CRSF 是否减少最坏路径退化；
2. 是否降低 j_du / omega_cmd_rms；
3. 是否不引入 path_catastrophic；
4. IMU 源是否有帮助，还是会因为噪声导致更差；
5. G5 是否明显优于 G4。
```

## 完整验证范围

如果首轮通过，再扩展到：

```text
6 条路径
10 个 seed
G0-G5 对照
```

核心指标：

```text
J_control
ey_rmse
xy_rmse
epsi_rmse
j_du
omega_cmd_rms
theta_mae_deg
theta_edge_p95_abs_err
flat_peak_theta_error
theta_step_p95_abs_deg
switch_count
switch_rate
dwell_violation_count
imu_reject_rate
path_catastrophic
```

其中 `J_control` 应继续使用当前项目的五项控制指标：

```text
mean([
  ey_rmse_ratio,
  xy_rmse_ratio,
  epsi_rmse_ratio,
  j_du_ratio,
  omega_cmd_rms_ratio
])
```

## 工作边界

新对话开始后，建议先做以下事：

```text
1. 只读检查现有文档和结果；
2. 写 results\paper\7.6\filter_experiment_protocol.md；
3. 在 protocol 中固定 IMU 合法性审计规则、输入信号、禁止信号、候选组别、路径、seed、指标、晋级规则；
4. 不要立刻改 shared source；
5. 不要覆盖已有 results；
6. 新实验输出应放到 results\paper\7.6 或用户明确指定的新实验目录下。
```

如果需要实际实现，建议新建独立实验根目录，例如：

```text
results\paper\7.6\crsf_filter_experiment\
```

## 预期交付物

第一阶段交付物：

```text
results\paper\7.6\filter_experiment_protocol.md
results\paper\7.6\crsf_filter_experiment\00_signal_legality_audit\
results\paper\7.6\crsf_filter_experiment\01_offline_replay_probe\
results\paper\7.6\crsf_filter_experiment\02_protected_closed_loop_screen\
```

其中第一步必须先完成：

```text
IMU 原始坡度输出是否在线可用、是否非 oracle、是否可与模型输出时间对齐。
```

只有 IMU 审计通过，才把 `theta_imu` 纳入 G5；否则只做 G0-G4。

## 给新对话的执行要求

请新对话遵守：

```text
1. 用中文汇报；
2. 先做只读审计和 protocol；
3. 不覆盖旧实验；
4. 不把旧 E5 写成成功证据；
5. 不使用 theta_ref / oracle / future path 作为在线滤波输入；
6. IMU 原始坡度必须先证明是在线测量源；
7. 若发现 IMU 实际是标签或真值，必须将其降级为 oracle/reference，只能用于评价，不能用于滤波输入。
```

---

## 一句话任务目标

请基于当前项目，设计并逐步实现第三创新点：

```text
加入 IMU 原始坡度候选源的置信度-残差驱动坡度选择滤波 CRSF，
在优化 ModernTCN、原始 ModernTCN、GRU、IMU 原始坡度之间进行在线选择 / 融合，
并验证其是否能改善 AGV 闭环轨迹跟踪中的 J_control、控制平滑性和最坏路径鲁棒性。
```
