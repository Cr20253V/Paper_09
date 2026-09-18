# A4 五种坡度来源下的 LPV-MPC 闭环正向验证

## 执行结论

- A4 decision：`MIXED_FIVE_CONTROLLER_RESULT`。
- 正式主表：138 case；A3 确定性控制器 18 case，Node42 G0/ADAPTIVE 六路径十种子 120 case。
- Node42 历史开发裁决继续保留为 `FAIL_NODE42_INNOVATION_DEVELOPMENT`；A4 未改写该裁决。
- 核心对比通过数：3/4；安全失败数：0。
- 未进行训练或闭环补跑；全部正式数据来自哈希审计通过的现有 case。

## 表 A4-1 五控制器总体结果

| Controller | ey RMSE | epsi RMSE | xy RMSE | j_du | omega RMS | Viol./timeouts | J_control vs ZS (%) |
|---|---|---|---|---|---|---|---|
| ZS_LPV_MPC | 1.4805 | 0.34204 | 9.8886 | 696.01 | 0.38514 | 0/0 | 0 |
| IMU_LPV_MPC | 1.4114 | 0.39816 | 6.7486 | 703.24 | 0.36175 | 0/0 | 2.6482 |
| MTCN_LPV_MPC | 0.026349 | 0.022161 | 0.50588 | 0.93053 | 0.058675 | 0/0 | -39.363 |
| Fusion_LPV_MPC | 0.023633 | 0.020038 | 0.47684 | 0.77885 | 0.056173 | 0/0 | 30.664 |
| Oracle_LPV_MPC | 0.01248 | 0.011393 | 0.25546 | 0.42684 | 0.051559 | 0/0 | 50.645 |

均值按冻结统计单位计算；学习控制器使用十个模型种子与六条路径，确定性控制器仅有每路径一个正式观测。表中的 ZS 相对改善率按同路径配对后求平均，不能解释为确定性控制器拥有十次独立重复。

## 表 A4-2 Fusion 相对 MTCN 的配对结果

| Metric | Comparator-target | 95% CI | Improved | Degraded | Worst path/seed |
|---|---|---|---|---|---|
| ey_rmse | 0.002716 | [-0.0011033, 0.0071579] | 27 | 17 | p02_sharp_turn_transition/seed340 |
| epsi_rmse | 0.0021229 | [0.00026081, 0.004334] | 32 | 12 | p01_factory_logistics_showcase/seed42 |
| j_du | 0.15168 | [-6.6879e-05, 0.41936] | 24 | 20 | p02_sharp_turn_transition/seed340 |

正效应表示 Fusion 更优；CI 使用 A5 冻结的 10,000 次“先种子、后路径”分层配对 bootstrap，随机种子为 20260715。

## 表 A4-3 六条 A0 路径结果

| Controller | Path | ey RMSE mean | epsi RMSE mean | j_du mean | Worst seed by j_du |
|---|---|---|---|---|---|
| ZS_LPV_MPC | p01_factory_logistics_showcase | 6.8602 | 1.4853 | 1931.4 | NA |
| ZS_LPV_MPC | p02_sharp_turn_transition | 1.2697 | 0.21974 | 1543.7 | NA |
| ZS_LPV_MPC | p03_long_updown | 0.70018 | 0.18455 | 700.53 | NA |
| ZS_LPV_MPC | p04_soft_updown_straight_turn | 0.0031655 | 0.0075051 | 0.29928 | NA |
| ZS_LPV_MPC | p05_factory_flat_logistics | 0.005953 | 0.0076133 | 0.01881 | NA |
| ZS_LPV_MPC | p06_downhill_after_turn | 0.043566 | 0.14754 | 0.16447 | NA |
| IMU_LPV_MPC | p01_factory_logistics_showcase | 6.8153 | 1.888 | 2895.6 | NA |
| IMU_LPV_MPC | p02_sharp_turn_transition | 0.94089 | 0.17165 | 664.73 | NA |
| IMU_LPV_MPC | p03_long_updown | 0.65877 | 0.17226 | 658.62 | NA |
| IMU_LPV_MPC | p04_soft_updown_straight_turn | 0.0037682 | 0.0077759 | 0.32443 | NA |
| IMU_LPV_MPC | p05_factory_flat_logistics | 0.0062456 | 0.0081685 | 0.017692 | NA |
| IMU_LPV_MPC | p06_downhill_after_turn | 0.043396 | 0.14115 | 0.16016 | NA |
| MTCN_LPV_MPC | p03_long_updown | 0.03787 | 0.025676 | 1.809 | 520 |
| MTCN_LPV_MPC | p04_soft_updown_straight_turn | 0.003955 | 0.0081131 | 0.3067 | 101 |
| MTCN_LPV_MPC | p06_downhill_after_turn | 0.019716 | 0.019022 | 0.50897 | 340 |
| MTCN_LPV_MPC | p02_sharp_turn_transition | 0.042416 | 0.031392 | 0.98443 | 21 |
| MTCN_LPV_MPC | p01_factory_logistics_showcase | 0.036605 | 0.034655 | 1.5365 | 520 |
| MTCN_LPV_MPC | p05_factory_flat_logistics | 0.017532 | 0.01411 | 0.43758 | 101 |
| Fusion_LPV_MPC | p03_long_updown | 0.038549 | 0.024757 | 1.8595 | 520 |
| Fusion_LPV_MPC | p04_soft_updown_straight_turn | 0.0039341 | 0.0081086 | 0.30443 | 101 |
| Fusion_LPV_MPC | p06_downhill_after_turn | 0.017107 | 0.014912 | 0.5251 | 340 |
| Fusion_LPV_MPC | p02_sharp_turn_transition | 0.038626 | 0.029006 | 0.80436 | 202 |
| Fusion_LPV_MPC | p01_factory_logistics_showcase | 0.029956 | 0.031519 | 1.1141 | 520 |
| Fusion_LPV_MPC | p05_factory_flat_logistics | 0.013625 | 0.011929 | 0.065632 | 101 |
| Oracle_LPV_MPC | p01_factory_logistics_showcase | 0.0044092 | 0.0064855 | 0.029442 | NA |
| Oracle_LPV_MPC | p02_sharp_turn_transition | 0.02038 | 0.018186 | 0.43389 | NA |
| Oracle_LPV_MPC | p03_long_updown | 0.036072 | 0.02266 | 1.1513 | NA |
| Oracle_LPV_MPC | p04_soft_updown_straight_turn | 0.0030268 | 0.0071139 | 0.59057 | NA |
| Oracle_LPV_MPC | p05_factory_flat_logistics | 0.005953 | 0.0076133 | 0.01881 | NA |
| Oracle_LPV_MPC | p06_downhill_after_turn | 0.0050389 | 0.0062967 | 0.337 | NA |

确定性控制器没有模型种子，其最差种子记为 NA；学习控制器的路线均值与最差种子均在同一路线的十个冻结模型种子内计算。

## 坡度精度与闭环收益

Fusion 相对 MTCN 的 `theta_sched_mae_deg` 平均配对效应为 0.067622°，95% CI 为 [0.046303, 0.089143]。坡度调度精度的平均改善并未完整转化为三个闭环主指标同时受支持：只有 `epsi_rmse` CI 全部位于零以上，`ey_rmse` 与 `j_du` 仍跨零，因此不得表述为 Fusion 全面优于 MTCN。

## 判定解释

- `Fusion_vs_MTCN`：False；ey_rmse=False, epsi_rmse=True, j_du=False
- `MTCN_vs_IMU`：True；ey_rmse=True, epsi_rmse=True, j_du=True
- `MTCN_vs_ZS`：True；ey_rmse=True, epsi_rmse=True, j_du=True
- `Oracle_vs_ZS`：True；ey_rmse=True, epsi_rmse=True, j_du=True

`Fusion_vs_IMU` 和 `Oracle_vs_Fusion` 完整报告但不改变四个预注册核心层次判定。J_control 仅作为五个同路径比值的综合解释指标，不替代 ey_rmse、epsi_rmse 和 j_du 三个主指标。局部退化点、最差路径/种子及全部安全统计均保留在统计表和图 A4-2 中。

## 图表与可追溯性

- 图 A4-1 固定使用 A0 的三条定性路径和 seed42，展示真实坡度、五种调度坡度、横向误差及两个控制输入。
- 图 A4-2 展示 Fusion 相对 MTCN 的全部 60 个配对点；未删除退化点。
- SVG 保留可编辑文字，同时提供 PDF、PNG 和 600 dpi TIFF。
- 每一图形点均可追溯至 `04_figures/figure_data`，每个统计值均可追溯至统一 case table 和源文件 SHA256。

## 边界声明

A0、A1、A2、A3、A5、Node40–Node42、`paper_v3.tex`、路径、种子、模型、融合/MPC 参数和评价门限均未修改。Node42 三条扩展路径仅写入 `extended_path_summary.csv`，未进入正式 CI 或 decision。
