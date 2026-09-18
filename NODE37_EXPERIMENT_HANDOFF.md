# Node37 选择性因果融合实验交接

更新时间：2026-07-14  
项目根目录：`E:\Matlab\Simulink\S-Function_16`

## 1. 新对话首先应知道的结论

Node37 的实现、开发集训练、运行器可靠性修复以及协议 v2 Clean 盲测均已完成。
Clean v2 的结果文件和 60 个 G0/G5 运行缓存完整，哈希审计通过；最终返回
`NO_GO_NODE37_ACCEPTANCE` 是实验结论未达到预注册的闭环门槛，不是仿真中断或文件缺失。

当前模型在已激活区间内确实满足“多数时间步坡度误差改善、其余持平”的局部目标：

- 激活区间坡度误差改善比例：`65.6061%`。
- 激活区间坡度误差退化比例：`0%`。
- 层级 bootstrap 95% CI：`[61.0450%, 70.2463%]`。
- 未激活时间步严格回退 ModernTCN：全部通过。

但它没有通过完整闭环验收，而且激活覆盖率过低：

- 30 个 G5 case 中只有 11 个发生过激活，19 个完全未激活。
- 总激活步数 `392/144030`，仅占 `0.2722%`。
- 仅 `25/30` 个 case 满足 `J<=1.02`，要求为至少 `27/30`。
- 平均 `J=1.0035078683`，要求 `<1`。
- 最差 `J=1.0639827917`，要求每个 case `<=1.05`。
- 没有灾难 case、超时、约束违反、非有限坡度或异常跳变。

因此，当前结果不能支持强表述“融合在复杂工况下始终或全面优于 ModernTCN”，也不足以把
“大部分时间优于、小部分时间持平”泛化到完整轨迹的所有时间步。它只支持带明确分母的事实：

> 在本次盲测中，选择性融合被激活的极少量时间步内，65.61% 的时间步坡度误差改善，
> 其余时间步等效且未观察到坡度误差退化；但闭环综合性能未通过预注册验收。

## 2. 已完成的工作

### 2.1 Node37 实现

已建立独立结果目录：

`results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion`

并建立独立 Simulink 副本：

`simulink/LPVMPC_AGV_ModernTCN_IMUFusion_Node37.slx`

主要实现内容包括：

- 因果 IMU 坡度估计与质量状态。
- 离线 shadow replay 数据集和 oracle `k` 标签。
- L2 逻辑回归融合门控和岭回归权重预测。
- 在线滞回、最短激活、冷却、风险保护及 `k` 变化率限制。
- G0、G5P、G5F、G5 四组接口；主实验关闭标签修正。
- 每个 case 的配置指纹、输出完整性 sidecar、缓存哈希与行数校验。
- 未知特征、ModernTCN/IMU 异常时强制报错，不静默伪造输出。
- 动态 IMU 测试，以及 MATLAB/Python 特征和预测一致性测试。

### 2.2 运行器可靠性修复

曾发现 MATLAB 运行器仍硬编码协议 v1 路径，而 JSON 已切换到协议 v2。该问题在真正的
v2 盲测前修复。现在以下组件统一以
`00_protocol_lock/experiment_manifest.json` 为路径和协议的唯一来源：

- `tools/node37_experiment_spec.m`
- `tools/node37_case_fingerprint.m`
- `tools/run_node37_selective_closed_loop.m`
- `tools/node37_audit_cache.m`
- `tools/run_node37_selective_closed_loop.ps1`
- `tools/summarize_node37_results.py`

修复后完成了 60/60 DryRun 预检、完整网格校验、冻结哈希校验和缓存失效测试。

### 2.3 开发集和模型冻结

开发路径为：

1. `path_closed_loop_long_updown_theta10_v1`
2. `path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1`
3. `path_factory_target_downhill_straight_after_turn_v1`

seed 固定为：`1,7,11,21,42,73,101,202,340,520`。

最终模型版本为 v10，冻结状态为 `FROZEN_AFTER_DEVELOPMENT_PASS`：

- 开发集：30/30 G5 case。
- 开发集激活区间改善：`76.9524%`，退化：`0%`。
- bootstrap 95% CI 下界：`72.00%`。
- 开发集平均 `J=0.9895806255`，最差 `J=1.0138814199`。
- 模型规范化文本 SHA-256：
  `75aba59876a740aa6f7f3eda70db077d642eff740d12c4cdda76d7f43798233f`。
- 模型原始文件 SHA-256：
  `e110116a67e88c326d94456049c3f9288c4e4369810b07b2a864edb233238d27`。
- 模型协议 SHA-256：
  `54fc7cb3a1e093a72636fbc1fdbaea0c7905cde9ec6c802f44e7b3ee2d529c68`。

### 2.4 盲测边界

协议 v1 的三条盲测路径已在早期失败诊断中被查看，已经消耗，不能再称为新盲测：

1. `path_closed_loop_sharp_turn_transition_theta10_v1`
2. `path_factory_logistics_showcase_theta10_v10`
3. `path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1`

协议 v2 冻结并完成 Clean 盲测的路径为：

1. `path_modern_tcn_showcase_candidate_balanced_mild_updown_lr_v1`
2. `path_factory_target_uphill_left_overlap_v1`
3. `path_factory_target_downhill_right_reversal_v1`

这三条 v2 路径现在也已被用于最终评估。后续若根据其结果修改训练、特征或门限，它们只能作为
开发/诊断数据，不能再次作为新的盲测集。新模型必须另选完全未参与开发的协议 v3 路径。

## 3. Clean v2 最终结果

完整运行：`10 seed x 3 path x 2 group = 60` 个 G0/G5 case。最终评价 G5 为 30 个 case。

验收项：

| 验收项 | 结果 | 判定 |
|---|---:|---|
| 激活区间坡度改善 >=60% | 65.6061% | 通过 |
| 激活区间坡度退化 <=5% | 0% | 通过 |
| bootstrap 95% CI 下界 >50% | 61.0450% | 通过 |
| 未激活严格回退，误差 <=1e-12 | 全部满足 | 通过 |
| 至少 27/30 case 的 J<=1.02 | 25/30 | 失败 |
| 所有 case 的 J<=1.05 | 最差 1.06398 | 失败 |
| 平均 J<1 | 1.00351 | 失败 |
| 无超时、违反、非有限值、异常跳变 | 全部满足 | 通过 |

失败的 5 个 case：

| seed | 路径 | J | 坡度改善 | e_y 比 | e_psi 比 | j_du 比 |
|---:|---|---:|---:|---:|---:|---:|
| 520 | downhill_right_reversal | 1.063983 | 69.44% | 1.057501 | 1.024488 | 1.233940 |
| 11 | uphill_left_overlap | 1.031124 | 58.33% | 0.991204 | 0.995382 | 1.159165 |
| 101 | downhill_right_reversal | 1.030696 | 74.29% | 1.023279 | 1.049481 | 1.083548 |
| 202 | uphill_left_overlap | 1.029567 | 50.00% | 1.013008 | 1.015687 | 1.108046 |
| 7 | downhill_right_reversal | 1.026329 | 69.44% | 1.147181 | 1.032135 | 0.958472 |

这些 case 说明坡度估计改善并不自动转化为闭环控制改善。主要退化集中在横向误差、航向误差和
控制增量，尤其 seed 520 的 `j_du` 增加到基线的 1.23394 倍。

## 4. 失败原因审计

### 4.1 训练目标与验收目标不一致

`tools/train_node37_selective_model.py` 的标签只优化逐时间步坡度绝对误差，未把闭环控制代价纳入
正样本或权重目标。`tools/evaluate_node37_case.m` 中的 J 却由以下五项比值的平均值构成：

- `e_y RMSE`
- `xy RMSE`
- `e_psi RMSE`
- `j_du`
- `omega_cmd RMS`

因此模型学到的是“何时 IMU 能改善坡度”，而不是“何时融合能安全改善闭环”。失败 case 中，
门控概率、TCN/IMU 差值和坡度改善程度与成功 case 很接近，现有特征无法识别控制风险。

### 4.2 激活覆盖率被全局规则压得过低

当前运行时包含全轨迹一次性的 `admission_decided`，并有
`LIFETIME_ACTIVE_BUDGET_STEPS=25` 一类全局激活预算。虽然实际短暂爬升过程产生了约 35--36
个激活样本，但总体仅激活 `0.2722%`。这使“激活区间多数改善”虽然统计通过，论文意义仍很弱。

### 4.3 权重回归实际退化为固定下限

训练数据中有益样本的 oracle `k` 中位数和 90 分位数均为约 `0.70`；岭回归原始预测也几乎全部
集中在 `0.70`。运行时却把 `k` 下限限制为 `0.80`，所以 100% 的有效预测都被裁剪到 `0.80`。
当前 G5 实质上接近“门控后固定 k=0.8 并带斜率限制”，并非真正有区分度的自适应权重模型。

### 4.4 离线状态特征没有真正参与学习

shadow 数据构造时 `k_prev` 和 `gate_active_prev` 固定为 1/0，对应系数为 0，不能代表在线状态
转移。需要用事件级或序列级 replay 重新生成这些状态特征。

### 4.5 消融统计已过期

`06_statistics/node37_clean_development_ablation.csv` 中 G5F case 使用的模型哈希为
`95dc2931...`，与冻结 v10 的模型协议哈希 `54fc7cb3...` 不一致。旧消融激活率约 22.65%，
而当前 v10 开发集激活率约 0.86%，不能把这份 G5P/G5F 消融表作为当前 v10 的论文证据。
核心 G0/G5 Clean v2 盲测不受此问题影响。

### 4.6 真值使用边界需在下一版写得更清楚

`tools/export_node37_shadow_dataset.m` 曾通过
`debug_ax - 9.81*sin(theta_ground)` 重构经重力项校正的传感器量；运行时的传感器生成链也采用相同
物理构造。这不等于把 `theta_ground` 直接送入门控特征，但容易造成协议歧义。下一版应直接记录
Node37 G0 的校正前原始传感器流，避免用真值重构训练输入。

## 5. 可实现性分析

对已消耗的 v2 路径做离线 oracle 分析后，三条路径合计：

- oracle 显著有益时间：`43.921%`。
- 加安全条件后的 oracle 显著有益时间：`41.629%`。
- 固定 `k=0.8`：改善 `28.966%`，退化 `0.098%`。

分路径的安全 oracle 改善覆盖率约为：

- balanced mild：`1.474%`。
- uphill left overlap：`58.005%`。
- downhill right reversal：`65.407%`。

结论是：复杂工厂坡道事件中存在足够的可融合收益，但三条路径全部时间步合计的安全 oracle
改善也只有 41.63%。因此不应把目标定义为“整条实验超过一半的所有时间步显著改善”。更可辩护的
论文目标是：

> 在预先定义的融合适用区间内，门控覆盖足够比例的有益时间步；在激活区间内多数时间步优于
> ModernTCN，其余以等效为主；非适用或高风险区间严格回退 ModernTCN，完整闭环总体不退化。

该目标必须增加“最低激活覆盖率/有益覆盖率”门槛，避免通过几乎不激活获得表面上的安全结论。

## 6. 下一步建议

不要执行 Node37 v2 的 medium noise 或 IMU bias 长仿真。Clean 主门槛已经失败，原协议规定应停止；
继续运行不会修复核心问题。

建议新建独立版本，例如：

`results/modern_tcn_metric_rebuild/38_moderntcn_imu_control_aware_selective_fusion`

Node38 应按以下顺序推进：

1. 将 Node37 开发集、已消耗的协议 v1 和 v2 数据全部降级为开发/诊断数据，保留 Node37 只读。
2. 直接记录同轨迹 G0 的原始在线传感器和控制状态，避免用真值重构运行输入。
3. 以 0.5--1.0 s 的因果事件窗口建立标签，不再只按孤立时间步训练。
4. 建立两个透明模型：融合收益分类器和闭环控制风险分类器；仅在收益高且风险低时激活。
5. 加入因果控制特征：`e_y`、`e_psi`、车速、横摆率、转角、控制量、控制增量、饱和裕度及滚动变化率。
6. 把正样本定义为“坡度改善且闭环窗口代价不退化”，把高 `j_du`/跟踪误差风险作为 veto。
7. 用离散动作 `k in {0.80,0.85,0.90,0.95,1.00}` 替代当前失效的岭回归，或采用同时约束坡度与控制代价的多目标 k 标签。
8. 用每个坡度事件独立 admission、dwell 和 cooldown，删除全轨迹一次性判定及 25 步 lifetime budget。
9. 用外层留一路径、内层 seed 压力测试选择门限；先满足闭环安全，再最大化有益覆盖率。
10. 在冻结前用当前哈希重新跑完整 G0/G5P/G5F/G5 消融，旧消融不能复用。
11. 明确预注册 J 的公式、窗口标签、最低激活覆盖率、闭环安全门槛及全部选择规则。
12. 冻结模型和代码后，选择三条完全未参与上述过程的新协议 v3 路径，只运行一次盲测。

长仿真前应先完成单元测试、shadow replay、交叉验证、短 case 烟雾测试和严格 DryRun。调试通过后再
生成新的手动执行文档交给用户运行，以免重复消耗数小时仿真时间。

## 7. 关键文件

- 最终判定：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/07_decision/node37_clean_blind_decision.json`
- 逐 case 结果：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/07_decision/node37_clean_blind_cases.csv`
- 冻结模型：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/03_model/node37_selective_model.json`
- 冻结清单：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/03_model/frozen_model_manifest.json`
- 协议：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/00_protocol_lock/selective_fusion_protocol.md`
- 实验清单：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/00_protocol_lock/experiment_manifest.json`
- 最终运行日志：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/09_run_logs/blind_v2_clean_10seed_corrected.log`
- 历史手动运行说明：
  `results/modern_tcn_metric_rebuild/37_moderntcn_imu_selective_fusion/MANUAL_EXECUTION_HANDOFF.md`

注意：历史手动运行说明记录的是运行时的操作步骤，其中“必须看到 PASS”的文字是验收期望，不是
实际结果。实际结果必须以 `node37_clean_blind_decision.json` 的
`NO_GO_NODE37_ACCEPTANCE` 为准。

## 8. 给下一次 Codex 对话的建议开场

可以在新对话中直接说：

> 请先完整阅读项目根目录的 `NODE37_EXPERIMENT_HANDOFF.md`，再核对其中列出的最终判定、
> 逐 case 表、冻结模型和训练代码。Node37 及协议 v2 结果必须只读，v1/v2 路径不能再次作为
> 新盲测。先汇报你对失败原因和 Node38 方案的理解，不要立即启动长仿真。

## 9. 工作区保护说明

当前 Git 工作区存在大量用户已有修改和未跟踪的实验/论文文件。后续工作不得执行
`git reset --hard`、`git checkout --` 或批量清理，也不得覆盖 Node30、Node36、Node37、协议 v1/v2
及现有论文材料。新实验应使用独立 Node38 目录和独立 Simulink 副本。
