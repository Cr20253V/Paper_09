# A5 主要结论统计与失败门复核：第二阶段报告

生成时间：2026-07-20T02:29:50+08:00

## 审计结论

- A5第二阶段状态：`PARTIAL`。
- A1离线40/40、A1闭环240/240、A3 18/18、A4五控制器138/138；主指标无缺失、重复或非有限值。
- A0、analysis plan、数据集、六路径、plant/MPC链及两套Node10门限哈希均按冻结值复核。
- 获得全部预注册主指标共同CI支持的主对比：A1_OFFLINE_DB124_VS_GRU, A1_OFFLINE_DB124_VS_M22, A1_OFFLINE_DB124_VS_TCN。
- `Fusion vs MTCN` 的三项闭环主指标未共同获支持；创新点3的真实负面/混合结果被保留。

## 失败门复核

A1原生表的`closed_loop_unstable`与`constraint_penalty`未导出，不能按A5冻结规则推定为PASS。A3/A4的约束惩罚比较值为零，比例门按冻结规则为`UNEVALUABLE_ZERO_BASELINE`，没有改写为PASS。因此确认性闭环主张被标为安全门不可完全裁决，状态为`PARTIAL`；这不是缺少实验case，而是失败门输入/零分母口径的显式阻断。

A1现有closed-loop-v2源门结果同时保留真实硬失败：ModernTCN+delta-bank为24/60，GRU为60/60，TCN为60/60，ModernTCN-22D为0/60。A5逐check重算见`failure_gate_cases.csv`。

## 统计口径

离线以模型种子配对；闭环先重采样模型种子、再在种子内重采样六条路线；确定性控制器只按六条路线配对重采样。bootstrap固定10,000次、随机种子20260715、百分位95% CI。相邻时间点和逐次计时调用均未作为科学独立重复。

## A2运行时

MATLAB原生核心/端到端/MPC/完整周期与同后端ONNX Runtime四模型结果分组报告，不跨后端合并排名。两次失败的ONNX Runtime尝试未进入正式表。Fusion在A2运行前未资格化，按运行时冻结状态保留为`NOT_ELIGIBLE_AT_RUNTIME_FREEZE`，不因后来创新点3完成而追溯补写。

## 文件导航

- `normalized_offline_cases.csv`、`normalized_closed_loop_cases.csv`：A5规范化逐case长表。
- `paired_effects.csv`、`bootstrap_ci.csv`、`contrast_decisions.csv`：配对效应、CI与裁决。
- `method_summary.csv`、`per_path_summary.csv`、`per_seed_summary.csv`、`worst_cases.csv`：均值/中位数/标准差、路线/种子及最差case。
- `failure_gate_cases.csv`、`failure_gate_summary.csv`：逐check及失败率/协议非通过率。
- `protocol_blockers.csv`：不得静默删除的阻断清单。
- `source_ci_crosscheck.csv`：A5与A1/A3/A4源统计表的CI逐项复算核对。
