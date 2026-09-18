# 非 Nature 实验图重设计说明

## 方法

本目录使用 `scientific-visualization` 与 `matplotlib` skill 的原则完成，没有调用
Nature 系列 skill。所有图均从冻结 CSV/MAT/trace 数据重新读取，不从旧 PDF、PNG
反向取数。脚本固定导出 PDF、SVG、PNG 和 600 dpi TIFF，并将整理后的 source data
保存在 `source_data/`。

运行入口：

```powershell
python results/paper/7.6/figures_redesigned_non_nature/generate_redesigned_figures.py
```

## 建议取舍

| 候选图 | 主要目的 | 相对现图的改进 | 建议 |
|---|---|---|---|
| R1 六路线档案 | 在比较结果前说明 P1--P6 工况覆盖 | 实际包含全部六路线；2×3 档案式布局比 3×6 小面板更易读 | 替换当前只含三路线的 Fig03 |
| R2 调度必要性 forest plot | 证明准确坡度调度的闭环价值 | 将机制时序与统计效应分离，保留所有 route 点和冻结 CI | 正文主图；P3 时序可移补充材料 |
| R3 离线估计器分布 | 比较四估计器与 delta-bank 增益 | 保留十种子、配对线和 CI，减少说明性文字占图面积 | 可替换 Fig05，也可保留现图 |
| R4 IMU 互补性 | 展示 IMU 有利、无效和不利区间 | 把 validity/gain 压缩成状态带，将主要高度留给误差互补证据 | 替换 Fig06 |
| R5 融合案例矩阵 | 展示 90 个案例平均改善但非逐例保证 | route×seed 热图能直接定位退化模式；右侧显示路线均值 | 强烈建议作为正文主图 |
| R6 P1 全路线融合时序 | 连接估计、融合、调度接口和局部误差 | 四层因果链共享时间轴，保留完整路线和局部退化 | 正文或补充材料 |
| R7 五控制器小倍数 | 比较三路线上的调度、误差和控制输入 | 统一方法编码；`e_y` 用 symlog 避免失稳基线压扁部署方法 | 双栏大图；版面紧张时拆为正文/补充图 |

## 关键审计结论

1. 当前 `figures_final/Fig03_closed_loop_route_set` 的脚本和成图只包含 P1、P3、P2
   三条路线，与论文 caption 的“six held-out closed-loop routes”不一致。
2. 当前 Fig04 把一条路线的四层时序和三指标配对效应放在同一画布，缩印后 route
   标签与 CI 过密。R2 保留统计结论，把机制时序作为独立证据处理。
3. 当前 Fig05 已具备较好的统计透明度，R3 是版面与标注上的渐进改进，不是必须替换。
4. 当前 Fig06 的 `imu_valid` 和 `K_imu_eff` 几乎全程为 1，单独占用较大面板的
   信息收益低；R4 将其改成薄状态带。
5. 原计划中的融合案例分布、P1 融合时序和五控制器时序此前没有成图，本目录已补齐。
6. `paper_v3 _1.tex` 在新版 Results 之后仍保留一套旧版实验与结果章节。正式接图前
   应先确定唯一正文版本，否则图号和 label 会继续冲突。

## 验收

`manifest.json` 记录输出文件和自动检查结果。当前检查覆盖：

- R1：6 条路线；
- R2：36 个配对效应点，即 2 contrasts × 3 metrics × 6 routes；
- R3：40 个离线模型结果，即 4 methods × 10 seeds；
- R4：4401 个对齐样本；
- R5：90 个融合案例，即 9 routes × 10 seeds；
- R6：24583 个完整 P1 trace 样本；
- R7：15 个 route–controller 案例，绘图源数据 27000 行；
- 每张图均包含 PDF/SVG/PNG/TIFF，SVG 文本保持可编辑，PNG 非空。
