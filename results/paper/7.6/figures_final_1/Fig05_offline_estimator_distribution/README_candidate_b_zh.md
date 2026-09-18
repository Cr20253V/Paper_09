# Fig. 5 候选 B：配对估计图

## 图形结论

在 ModernTCN 架构保持不变时，多尺度差分输入相对于 22 维原始输入同时降低了
`|theta| <= 10 deg` 范围内的坡度 MAE 和边缘区域 P95 绝对误差。两个指标的正式
配对种子 bootstrap 95% 置信区间均位于零以上。

## 面板设计

- `(a)` 展示 `|theta| <= 10 deg` 范围内的 Grade MAE。
- `(b)` 展示 edge-region P95 absolute error。
- 两个面板均采用横向排列的 Gardner--Altman 风格配对估计图，不再将绝对值和效应量
  拆成上下四个子图。左侧浅灰线连接相同种子，深蓝圆形表示 ModernTCN-delta，橙红
  方形表示 ModernTCN-22D；两种方法使用色盲安全的高对比配色和冗余形状编码。
- 右侧配对效应定义为 `ModernTCN-22D - ModernTCN-delta`；绿色小菱形为十个种子差值，
  大菱形和垂直误差线为正式配对种子 bootstrap 均值效应及 95% CI。正值表示
  ModernTCN-delta 更好。
- 横坐标仅保留方法和比较名称。两个绝对均值以及配对效应 `[95% CI]` 统一放在标题
  下方的独立统计摘要带中；数据区内不放置数值文字，从结构上避免文字遮挡数据。
  图中不显示种子编号或改善种子计数。

## 建议图注

**Matched-seed offline comparison of ModernTCN input representations.**
(a) Grade MAE over test windows with absolute true grade no greater than 10 degrees.
(b) Edge-region P95 absolute grade error. Blue circles and vermillion squares show the
two input representations, and gray lines connect matched model seeds. Larger method
markers identify arithmetic means, which are reported in the text-only summary band.
Green diamonds show seed-paired
effects defined as ModernTCN-22D minus ModernTCN-delta; the larger diamond and vertical
whiskers show the mean effect and 95% paired-seed bootstrap confidence interval. Positive
effects favor ModernTCN-delta.

## 生成与输出

运行入口：

```powershell
python results/paper/7.6/figures_final_1/Fig05_offline_estimator_distribution/scripts/generate_fig05_candidate_b.py
```

`output/` 包含带 `candidate_b` 标识的 PDF、SVG、PNG 和 600 dpi TIFF；`source_data/`
保存绝对种子指标、配对种子效应和统计汇总；`qa/` 保存灰度与色觉缺陷模拟预览。
