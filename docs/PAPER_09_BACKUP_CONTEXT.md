# Paper 09 IEEE Access 返修与备份上下文

更新时间：2026-09-18

## 1. 论文权威版本

- 标题：`Slope-Aware LPV-MPC Path Tracking of a Dual-Steering-Wheel AGV with Time-Lag-Enhanced ModernTCN Perception`
- 最终源文件与可编译包：`results/paper/paper_8.8/`
- 最终 PDF：`results/paper/paper_8.8/paper.pdf`
- 同步投稿包：`results/paper/paper_8.8.zip`
- 等价便携源：`results/paper/paper_submission_portable/`
- 图表设计、源数据与 QA 记录：`results/paper/7.6/`

`paper_8.8/paper.tex` 与 `paper_submission_portable/paper.tex` 的 SHA-256 均为
`b6b59425d730d3decc94c4c954064f5874be0ccfe183aacaa5a9f4a808fc789f`。
最终 PDF 为 21 页，生成时间为 2026-08-08 01:36:26，SHA-256 为
`653816cb79996c2652dfb2708770832873c01d114c1451fa2c9de52f06cd60b5`。

## 2. 论文主线

本文研究双转向轮 AGV 的坡度感知 LPV-MPC 路径跟踪。ModernTCN-Delta 使用
128 步（1.28 s）历史，将 22 维基础输入与滞后 1、2、4 的差分拼接成 88 维输入，
预测坡度并作为主要调度源。合格观测器仅通过带不确定性、创新量、NIS、幅值和
变化率约束的有界接口提供互补修正；最终控制仍由约束 LPV-MPC 产生。

数据集由 51 个路线模板的两次实现构成，共 102 条连续运行和 588102 个原始样本。
按运行划分为 71/15/16 个训练、验证和测试运行，随后才提取 16529/3695/3602 个窗口，
避免同一路线运行跨集合泄漏。控制周期为 0.01 s，预测时域 150 步，控制时域 30 步。

## 3. 冻结证据链

主要冻结基准位于：

`results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/`

其中 A1--A5 覆盖四种估计器的离线与闭环比较、统一 ONNX Runtime CPU 推理时间、
坡度调度必要性、控制器比较和配对统计。A1 清单确认 40 个模型、40/40 个离线案例和
240/240 个闭环案例完整。

最终融合研究位于：

`results/modern_tcn_metric_rebuild/53_moderntcn_fuzzyakf6d_fusion_rebuild/08_formal_six_path_exploratory_v7/`

该节点包含六条路线、十个模型种子的 60 个匹配基线/融合案例、完整逐案例轨迹、
运行时诊断、汇总表、分层 bootstrap 统计、协议锁和源文件校验。最终图 8 的三个统计输入
直接来自该节点的 `reports/v7_formal_paired_comparison.csv`、
`v7_paired_path_summary.csv` 和 `v7_paired_bootstrap_statistics.csv`。

## 4. 论文关键结果

- 坡度调度必要性：零坡度调度的平均横向 RMS、航向 RMS 和 `J_delta_u` 分别为
  1.48046 m、0.34204 rad 和 696.014；合格观测器调度为 0.02051 m、0.02347 rad
  和 0.51646；仅用于分析的真实坡度参考为 0.01248 m、0.01139 rad 和 0.42684。
- 多尺度滞后差分：ModernTCN-Delta 的离线 MAE 为 0.59888 deg，ModernTCN-22D 为
  0.65300 deg；配对改善为 0.05412 deg，95% CI `[0.00608, 0.10180]`。边缘区 P95
  从 2.88256 deg 降至 2.45649 deg。
- 完整闭环估计：ModernTCN-Delta 的六路径平均 MAE 为 0.423 deg，P95 为 1.237 deg，
  两项均在六条路线中的四条排名第一。
- MTCN-LPV-MPC 基线：60 个路线-种子案例的平均横向 RMS、航向 RMS 和 `J_delta_u`
  为 0.02635 m、0.02216 rad 和 0.93053。
- Fusion-LPV-MPC：相应均值为 0.01891 m、0.01643 rad 和 0.67361；横向 RMS 降低
  28.23%，配对效应为 0.00744 m，95% CI `[0.00245, 0.01527]`。输入增量指标的
  点估计改善，但论文明确保留其区间跨零的限定。
- 推理时间：统一 CPU/ONNX Runtime 条件下，ModernTCN-Delta 的 p95 核心推理时间为
  0.4038 ms，10000 次计时调用中没有一次超过 10 ms。

## 5. 六条闭环路线与固定种子

路线为 P1 Factory logistics、P2 Sharp-turn transition、P3 Long up/down slope、
P4 Mild slope-turn coupling、P5 Flat factory logistics 和 P6 Downhill recovery。
模型种子固定为 1、7、11、21、42、73、101、202、340、520。种子 42 用于控制器和
融合机理图，四估计器 P2 代表轨迹使用种子 73；定量结论始终使用全部六条路线和十个种子。

## 6. 返修时必须保留的边界

- 实验来自非线性 MATLAB/Simulink 仿真，不等同于实车验证。
- 真实坡度源仅是分析参考，不能描述为可部署传感器。
- 融合接口中 ModernTCN-Delta 始终是主要坡度源，观测器只提供有界互补修正。
- 推理时间只覆盖同一 ONNX Runtime CPU 后端的估计器核心，不包含控制器、I/O 或完整包装层。
- `J_delta_u` 是控制输入增量的复合平滑性指标，不是物理能耗。
- 代表轨迹只解释机制，统计结论必须引用完整匹配案例及其 bootstrap 单元。
- 不得把五页 GRU/MEMS 会议论文的七路径结果混入本 IEEE Access 论文。

## 7. GitHub 备份范围

`Paper_09` 当前备份以 IEEE Access 定稿为根，包含最终 LaTeX/PDF/ZIP、图表源数据与 QA、
Node39 冻结基准的协议/脚本/模型/CSV/JSON 证据、Node53 V7 的 60 个正式案例 CSV/JSON、
融合配置与模型、六条精确路径、核心 MATLAB/Python/Simulink 源码、项目上下文和 SHA-256
清单。为控制 Git 仓库体积，省略可由保留的 CSV、配置和脚本重建的冗余 `*_out.mat`、
运行缓存、TIFF、Python 字节码、LaTeX 临时文件以及重复 `attempts` 副本；这些省略项不参与
论文表格或统计值的唯一来源。
