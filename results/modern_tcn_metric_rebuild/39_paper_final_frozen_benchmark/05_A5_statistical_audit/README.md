# A5 主要结论的统计与失败门复核

## 当前状态

- `PHASE1_COMPLETE`：统计方案、输入schema、主要/次要指标、统计单位、bootstrap、失败门和输出表格式已在读取A1–A4最终结果之前冻结。
- `ANALYSIS_PLAN_FROZEN`：论文主方法仍为 `ModernTCN + delta_bank_124`，本任务不做方法重选。
- `PHASE2=PARTIAL`：第二阶段已执行。A1离线40/40、A1闭环240/240、A3 18/18、A4 138/138均完整，A0与输入哈希复核通过；`PARTIAL`来自冻结失败门的不可裁决输入，不是缺少实验case。
- 最终报告位于 `04_phase2/A5_experiment_report.md`，逐项裁决见 `04_phase2/contrast_decisions.csv`，显式阻断清单见 `04_phase2/protocol_blockers.csv`。

## 冻结依据

| 文件 | SHA256 |
|---|---|
| `results/paper/7.6/A0_论文最终统一实验配置_20260715.json` | `1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911` |
| `results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md` | `44155532ef770dbb5c4817006caa80213cb2ede7390ee8dbcc75085425058173` |
| `results/paper/7.6/后续三章实验审计与写作大纲_20260715.md` | `a8a0c7a736afcb54812cd419a3a31f716eac2820a1c5fed68c85b9636191b8bc` |

A0登记的22项数据、路径、plant、MPC和门限输入均通过实际SHA复核。完整逐文件结果见 `03_phase1/raw_protocol_audit_cases.csv`。

## 第一阶段执行前的可复用与缺失快照

- 本节是2026-07-15第一阶段冻结时点的历史快照，不代表第二阶段当前缺失状态。
- 当时ModernTCN-delta-bank、ModernTCN-22D和GRU均有10/10固定种子模型；TCN仅有21、73、101。
- Node30 delta-bank和Node32 ModernTCN-22D的六路径×十种子网格各为60/60，但必须先由A1统一登记，A5第二阶段不直接拼接旧Node结果。
- 当时缺少TCN七种子、GRU闭环60例、TCN闭环60例，以及A2/A3/A4冻结结果。历史逐case清单见 `01_inventory/missing_cases.csv`；这些case现已由A1–A4正式交付补齐并在第二阶段重新审计。

## 统计口径

- 离线统计单位为配对模型种子；闭环为路线×模型种子的两层配对统计。相邻时间点和滑动窗口禁止作为独立重复。
- bootstrap固定10,000次、seed=20260715、百分位95% CI；闭环先重采样种子，再在种子内重采样路径。
- 闭环主指标严格为 `ey_rmse`、`epsi_rmse`、`j_du`。只有三项改善CI下界均大于0且安全门无失败，才允许总体改善结论。
- 缺失、重复、非有限、意外case和协议不一致均显式进入阻断表；不插补，不在不完整网格上生成确认性CI。

## 第二阶段结果

- 三个A1离线主对比的全部预注册主指标均获CI支持。
- A1 delta-bank相对ModernTCN-22D的闭环`ey_rmse`与`epsi_rmse` CI跨零，且delta-bank存在24/60个closed-loop-v2硬门失败，不能声称三项主指标整体改善。
- Fusion相对MTCN只有`epsi_rmse`获正向CI支持；`ey_rmse`与`j_du`未获支持，不能声称创新点3整体闭环改善。
- A5复核发现MTCN相对ZS在`seed101 / p05_factory_flat_logistics`的`j_du`比值为215.14，超过冻结门限45。
- A1没有导出显式`closed_loop_unstable`和`constraint_penalty`输入；A3/A4约束惩罚比例遇到零分母。按冻结规则均保留为`UNEVALUABLE`，不改写为PASS，因此总状态为`PARTIAL`。
- A5与A1/A3/A4源表可对应的38行bootstrap CI（覆盖34个唯一contrast-metric项）全部复现，最大绝对差为`2.78e-17`。

复现命令：`python 02_tools/run_phase2.py`。该脚本只读A1–A4和冻结输入，所有写入均限制在本A5目录。

本目录中的现有模型和结果均只通过原路径与SHA引用，没有复制或重新训练；未修改A0、`paper_v3.tex`或其他Node/A类任务目录。
