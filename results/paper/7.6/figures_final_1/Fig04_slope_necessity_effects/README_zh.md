# Fig. 4 候选表达

## 论文采用版本

论文正式采用候选 B（路线级绝对值配对图）。`output/fig04_slope_necessity_effects.*`
为提交和论文引用使用的正式文件组；名称中带 `candidate_b` 的文件保留用于候选方案追溯。

`output/fig04_slope_necessity_effects_ra_x2_qg_x05.*` 是保持候选 B 版式不变的
RKF 协方差敏感性数据版本。该版本保留冻结的零坡度与真值参考对照，图中的
`Qualified observer` 路线点使用 `R_a x2, Q_g x0.5` 的六路线 RKF-IMU 结果；在确认
用于论文前不会覆盖正式图 4。

两张候选图均直接读取当前 Fig. 4 的冻结 source data，不从现有 PDF 或 PNG 反向取数。

- `candidate_a_effect_heatmap_ci`：路线效应热图加总体均值和 95% route-bootstrap CI。
  热图格内为绝对效应，定义为 Zero-grade comparator minus target；正值有利于目标方法。
  三个指标使用各自独立的绝对效应色阶，避免混合 m、rad 和 J_Delta_u 三种量纲。
- `candidate_b_paired_dumbbell`：Zero-grade、Truth-driven reference 和 Causal-IMU 的
  路线级绝对指标配对图。横轴明确使用对数尺度，以同时显示 P1 与 P4--P6 的数量级差异。
- `candidate_c_normalized_ratio`：以 `Target / Zero-grade` 为共同尺度的基准归一化比值图。
  `1x` 为无变化，左侧为改善，右侧为退化；该图删除了候选 B 中重复的基准点和连接结构。
- `candidate_d_mechanism_summary`：左侧使用 P3 完整 trace 展示坡度调度、横向误差、航向误差
  和累计输入增量，右侧用箭头矩阵汇总六路线相对变化及 route-bootstrap CI 是否跨零。
- `candidate_e_paired_values_ci`：候选 B 的路线级绝对值配对图加三组正式统计汇总。
  上排保留 Zero-grade、Causal-IMU 和 Truth-driven 的绝对指标与平均调度坡度 MAE；下排分别给出
  Truth vs Zero、IMU vs Zero、Truth vs IMU 的配对均值效应和 95% route-bootstrap CI。
  该图用于同时表达准确坡度调度的闭环收益、简单 IMU 的路线依赖性，以及真实坡度相对 IMU
  的可实现上界。正效应定义为 comparator minus target，即目标方法数值更低、更好。

输出目录为 `output/`，每张图包含 PDF、SVG、PNG 和 600 dpi TIFF；`qa/` 中包含灰度预览
和自动检查结果。运行入口：

```powershell
python results/paper/7.6/figures_final_1/Fig04_slope_necessity_effects/scripts/generate_fig04_alternatives.py
python results/paper/7.6/figures_final_1/Fig04_slope_necessity_effects/scripts/generate_fig04_candidates_cd.py
python results/paper/7.6/figures_final_1/Fig04_slope_necessity_effects/scripts/generate_fig04_ra_x2_qg_x05.py
```
