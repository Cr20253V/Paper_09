# Fig. 5 候选 A：离线估计器证据重绘

## 图形结论

多尺度差分特征在保持 ModernTCN 架构不变时，降低了平均坡度误差和边缘区域尾部误差；
ModernTCN-delta 同时保持四种离线估计器中最低的 MAE 和整体 P95 绝对误差。

## 面板设计

- `(a)` 是主证据面板。小点为十个模型种子的配对效应，效应定义为
  `ModernTCN-22D - ModernTCN-delta`，正值表示 ModernTCN-delta 更好；菱形和水平须为
  正式配对种子 bootstrap 均值效应及 95% CI。图中仅标注效应值和区间，不标种子计数。
  第二行使用论文正式比较中的 edge-region P95。
- `(b)` 是绝对性能辅助面板。点和水平须为四种方法在真实坡度
  `|theta| <= 10 deg` 测试窗口上的十种子均值及描述性 95% Student-t 区间。

这种结构将 delta-bank 的表示贡献置于视觉中心，同时保留四种方法的绝对性能量级，
不再使用旧图中交叉的种子连线和四组同等醒目的彩色散点。

## 建议图注

**Ten-seed offline evidence for the multi-scale delta-bank representation.**
(a) Seed-paired effects of ModernTCN-22D minus ModernTCN-delta for grade MAE and
edge-region P95 absolute error. Small points denote individual model-seed effects;
diamonds and horizontal whiskers denote mean effects and 95% paired-seed bootstrap
confidence intervals. Positive values favor ModernTCN-delta. Labels report the mean
effect and confidence interval. (b) Absolute test-set grade
MAE and P95 absolute error over the pre-specified `|theta| <= 10 deg` range. Symbols and
whiskers denote ten-seed means and descriptive 95% Student-t intervals. Lower values are
better in panel (b).

## 生成与输出

运行入口：

```powershell
python results/paper/7.6/figures_final_1/Fig05_offline_estimator_distribution/scripts/generate_fig05_candidate_a.py
```

`output/` 包含带 `candidate_a` 标识的 PDF、SVG、PNG 和 600 dpi TIFF；`source_data/` 保存绝对种子指标、
配对种子效应和统计汇总；`qa/` 保存灰度与色觉缺陷模拟预览。
