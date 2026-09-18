# 图 7：融合增益标定（重设计版）

本目录是图 7 的独立重设计版本，不覆盖 `figures_final` 中的旧图，也不修改论文
LaTeX 排版。

## 主要调整

1. 面板 a 将 ModernTCN-delta 每个工况只显示一次，避免把观测器激励等级错误地
   归因于 ModernTCN。
2. 面板 b 改为横向 P05-P50-P95 区间，并直接标明有效增益触及上限及明显低于上限
   的总体比例。图中的区间是验证样本分位区间，不是置信区间。
3. 面板 c 将两个候选折线图合并为 MAE 比与有效增益跨度的二维资格图。0.5 的
   “selected”标记与最低验证 MAE 比绑定，而不是与最大跨度绑定。
4. 所有增益符号采用正式数学排版；失败状态改用灰色叉号，资格与最终选择使用
   青色和深青色，并保留形状冗余编码。

## 推荐英文图注

Validation-only calibration of the uncertainty-adaptive fusion gain. **a,**
Empirical marginal prediction-error scale, shown as
`sqrt(E[e^2])` in degrees, for ModernTCN-delta in four operating regimes and
for the qualified observer across low, medium, and high excitation. The learned
source is regime-conditioned only. **b,** Validation-sample P05-P50-P95
intervals of the unconstrained gain and innovation-weighted effective gain for
the selected `K_max = 0.5` candidate; intervals are distribution quantiles, not
confidence intervals. Of 458,327 valid non-fallback samples, 64.49% reached the
cap and 35.37% were at least 0.01 below it. **c,** Candidate validation in the
plane of Fusion-to-ModernTCN MAE ratio and effective-gain P95-P05 spread. The
0.3 candidate failed the registered spread gate; 0.4 and 0.5 qualified, and 0.5
was selected by the registered ranking because it achieved the lowest
validation MAE ratio among qualified candidates.

## 生成

```powershell
python results/paper/7.6/figures_final_1/Fig07_node44r1_gain_calibration/scripts/generate_fig07_node44r1_redesign.py
```

主输出文件名保持为 `fig07_node44r1_gain_calibration.*`，便于后续替换论文引用。

