# A3 当前对象坡度调度必要性实验报告

## 执行结论

- 正式网格：`18/18 COMPLETE`；完整性审计：`18/18 PASS`。
- A5 schema：`PASS`。
- 主裁决 Oracle vs ZS：`SUPPORTED_ALL_PRIMARY`。
- 次要裁决 IMU vs ZS：`INCONCLUSIVE`。
- Oracle 上界相对 IMU：`SUPPORTED_ALL_PRIMARY`。
- 所有结果均按冻结路径、门限、IMU 参数和 MPC 配置保留；未依据观察结果调参或筛选 case。

## 六路径均值

| 控制器 | ey RMSE | epsi RMSE | xy RMSE | ev RMSE | j_du | theta_sched MAE (deg) |
|---|---:|---:|---:|---:|---:|---:|
| ZS_LPV_MPC | 1.48046 | 0.342042 | 9.88861 | 2.68713 | 696.014 | 2.78062 |
| IMU_LPV_MPC | 1.4114 | 0.39816 | 6.74856 | 0.715764 | 703.239 | 2.7282 |
| Oracle_LPV_MPC | 0.0124801 | 0.0113926 | 0.255465 | 0.0104015 | 0.426836 | 0.122846 |

## 配对 bootstrap（比较器 − 目标，正值有利于目标）

| 对比 | 指标 | 均值效应 | 95% CI |
|---|---|---:|---:|
| A3_ORACLE_VS_ZS | ey_rmse | 1.46798 | [0.117151, 3.74682] |
| A3_ORACLE_VS_ZS | epsi_rmse | 0.330649 | [0.0506529, 0.800045] |
| A3_ORACLE_VS_ZS | j_du | 695.587 | [116.408, 1339.45] |
| A3_IMU_VS_ZS | ey_rmse | 0.0690628 | [0.00663159, 0.1781] |
| A3_IMU_VS_ZS | epsi_rmse | -0.0561184 | [-0.198313, 0.0250241] |
| A3_IMU_VS_ZS | j_du | -7.2247 | [-475.104, 439.468] |
| A3_ORACLE_VS_IMU | ey_rmse | 1.39892 | [0.11052, 3.66272] |
| A3_ORACLE_VS_IMU | epsi_rmse | 0.386768 | [0.0478133, 0.99136] |
| A3_ORACLE_VS_IMU | j_du | 702.812 | [109.43, 1668.02] |

## 安全与可复用性

- 18 个 case 的 `solver_fail_count=0`、`constraint_violation_rate=0`、`timeout_count=0`。
- ZS 的零违规基线导致 constraint-penalty 比值按预注册规则标记 `UNEVALUABLE_ZERO_BASELINE`，未强行写成 PASS。
- 分类准确率、召回率与离线边界门对 A3 不适用；固定分类量只用于排除非坡度权重差异。
- `04_summary/a3_case_table.jsonl` 满足 A5 A3 schema；`04_summary/a4_artifact_receipt.json` 提供 A4 可直接引用的逐 case MAT、trace 与 SHA256。

## 结果解释

Oracle 表示真实坡度经公共 RhoFilter 后的调度上界。IMU 使用 Node36 合法因果估计器原始输出；其在部分复杂路径上出现明显闭环退化，这是真实结果而非协议异常。A3 的主问题是“当前对象是否存在坡度调度必要性”，因此主裁决仅按预注册的 Oracle vs ZS 三项指标和安全门作出。

详细逐路径数据见 `04_summary/a3_case_table.csv`，配对效应和置信区间见 `paired_effects.csv` 与 `bootstrap_ci_results.csv`。
