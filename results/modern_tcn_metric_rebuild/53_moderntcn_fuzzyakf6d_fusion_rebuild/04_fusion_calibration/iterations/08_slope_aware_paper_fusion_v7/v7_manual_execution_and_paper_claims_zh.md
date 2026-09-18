# Node53 V7 融合实验执行与论文使用说明

## 当前冻结状态

- 分类：`RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK`
- 候选：`V7C25`
- `Kmax = 1.0`
- `p_help_threshold = 0.60`
- 坡度迟滞：进入 `0.5 deg`，退出 `0.3 deg`
- 最小创新：`0.25 deg`
- 最大创新：`2.0 deg`
- correction limit：`0.5 deg`
- correction rate limit：`5 deg/s`
- R2_06 参数保持冻结；运行时不读取道路坡度真值。

开发集包含 71 train + 15 validation runs、10 个 ModernTCN 模型种子和三折 run-grouped CV。共 4,787,860 个样本：ModernTCN MAE 为 `0.853908 deg`，Fusion MAE 为 `0.802845 deg`，比值为 `0.940200`。三个 fold 比值分别为 `0.937617 / 0.949497 / 0.934006`。

V7 不采用 44R1 的 qualification 判定。它保留 covariance PSD、有限值、fallback identity、correction/rate limit、truth boundary 和 manifest/hash 等运行安全合同。

## 手动执行

在 PowerShell 中进入项目根目录：

```powershell
Set-Location 'E:\Matlab\Simulink\S-Function_16'
$runner = '.\results\modern_tcn_metric_rebuild\53_moderntcn_fuzzyakf6d_fusion_rebuild\tools\run_node53_v7_exploratory.ps1'
```

先运行真实 3 秒短测：

```powershell
& $runner -Stage Smoke -ModelSeed 42 -ReuseExisting -LogFile '10_logs\v7_smoke_seed42.log'
```

只做六条路径、单个模型种子，用于论文中的描述性案例表和曲线：

```powershell
& $runner -Stage SixPath -ModelSeed 42 -ReuseExisting -LogFile '10_logs\v7_six_path_seed42.log'
& $runner -Stage Summarize -LogFile '10_logs\v7_summarize_seed42.log'
```

单独恢复某条路径：

```powershell
& $runner -Stage SixPath -ModelSeed 42 -PathId 'p03_long_updown' -ReuseExisting -LogFile '10_logs\v7_p03_seed42.log'
```

六条路径的 `PathId` 为：

```text
p01_factory_logistics_showcase
p02_sharp_turn_transition
p03_long_updown
p04_soft_updown_straight_turn
p05_factory_flat_logistics
p06_downhill_after_turn
```

若论文需要总体改善、置信区间或显著性结论，运行 6 paths x 10 fixed model seeds：

```powershell
& $runner -Stage SixPath -AllSeeds -ReuseExisting -LogFile '10_logs\v7_six_path_60cases.log'
& $runner -Stage Summarize -LogFile '10_logs\v7_summarize_60cases.log'
```

中断后重复同一命令即可。完整且 fingerprint/hash 一致的案例会复用；已有但不匹配的目录会保留，并在该案例的 `attempts` 子目录生成新结果。

## 输出位置

模型副本：

```text
06_model_freeze\v7_exploratory\LPVMPC_AGV_MTCN_FAKF6D_V7_Exp.slx
```

闭环结果根目录：

```text
08_formal_six_path_exploratory_v7\
```

单案例目录：

```text
08_formal_six_path_exploratory_v7\cases\V7\seed<MODEL_SEED>\<PATH_ID>\
```

汇总文件：

```text
v7_all_available_metrics.csv
v7_all_available_metrics.json
v7_all_available_safety_summary.json
```

## 论文表述边界

仅运行 seed42 的 6 个案例时，可以报告为“六个预先指定路径上的描述性闭环比较”，并逐路径列出指标。不能把 6 条路径当作 6 个独立随机重复，也不报告总体 bootstrap CI。

运行 60 个与 ModernTCN-only 一一配对的案例后，可以进行 seed-first hierarchical paired bootstrap，再报告总体效应和 95% CI。六路径在 V7 之前已经暴露，因此仍应表述为 retrospective exploratory benchmark，而不是 blind/prospective qualification。

R2_06 本身仍不称为 qualified observer。论文中可将贡献表述为：冻结的六轴 FuzzyAKF 通过运行时可观测的 helpfulness、坡度迟滞和创新门控，为 ModernTCN-delta 提供受限修正；最终闭环结论以实际 V7 六路径结果为准。

实验结果完成前不修改 `paper_v4_final_candidate.tex`。
