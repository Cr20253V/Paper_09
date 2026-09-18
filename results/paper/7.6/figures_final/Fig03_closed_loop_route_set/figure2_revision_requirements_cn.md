# 六条闭环测试路径图修改要求

## 1. 修改目标与边界

本图用于说明独立于模型训练数据和离线测试数据的六条正式闭环测试路径。图中统一称为“闭环基准路径（closed-loop benchmark routes）”，不要称为训练集、验证集或测试数据集。保留六路径、六面板和 `2 x 3` 排列，不修改现有图目录、脚本入口、图编号或输出文件名。

图的核心信息仍由三部分组成：左侧为完整平面参考轨迹，右上为与轨迹时间对齐的坡度曲线，右下为参考速度曲线。六个面板的结构、尺寸、坐标轴样式和信息层级必须一致。

## 2. 六个面板名称

按下列名称显示，不在名称后添加星号或其他上标：

1. `P1  Factory logistics`
2. `P2  Sharp-turn transition`
3. `P3  Long up/down slope`
4. `P4  Mild slope-turn coupling`
5. `P5  Flat factory logistics`
6. `P6  Downhill recovery`

P4 的名称应明确包含 slope-turn coupling，避免含义过于笼统；P5 明确标为平坦工厂物流路径。不要修改 P1--P6 的编号、顺序或路径身份。

## 3. P4 坡度曲线的特殊处理

P4 的平面轨迹、时间轴和参考速度继续读取现有路径文件，但坡度曲线不读取当前文件中的 `theta_ref`，而是以路径元数据中的七个分段为权威绘图规范：

| 时间区间 | 元数据分段 | 绘制要求 |
|---|---|---|
| 0--4 s | `startup_flat` | 保持 `0 deg` |
| 4--15 s | `uphill_entry` | 由 `0 deg` 平滑、单调上升至 `+4.0 deg` |
| 15--21 s | `uphill_left_turn` | 保持 `+4.0 deg` |
| 21--34 s | `slope_release_only` | 由 `+4.0 deg` 平滑、单调回落至 `0 deg` |
| 34--43 s | `downhill_entry` | 由 `0 deg` 平滑、单调下降至 `-3.5 deg` |
| 43--49 s | `downhill_right_turn` | 保持 `-3.5 deg` |
| 49--56 s | `flat_recovery` | 由 `-3.5 deg` 平滑、单调恢复至 `0 deg` |

过渡段优先采用与其他路径生成逻辑一致的平滑阶跃或 smoothstep 插值，端点必须精确满足上述值，且不得出现过冲、振荡或启动阶段的正负坡度脉冲。P4 的坡度绘图数据必须写入图的 source-data 文件，并增加类似 `grade_source=metadata_reconstructed` 的来源标识；QA 记录中也要说明该曲线来自分段元数据。

从论文可复核性考虑，在正式投稿前必须保证实际闭环仿真使用的 P4 坡度与本图一致；若尚未重新运行 P4，则图注中必须明确该曲线表示 P4 的元数据规定剖面，而不能让读者误认为它是当前仿真文件中实际执行的 `theta_ref`。

## 4. 星号和图内注释

- 删除 P1、P3 和 P4 标题后的全部星号。
- 删除图底部的 `* Pre-specified qualitative route...` 整句说明。
- 不再通过星号区分所谓 qualitative routes；六条路径在本图中具有相同的闭环基准身份。
- 删除不承载数据的解释性文字和脚注，释放出来的底部空间用于改善上下边距。
- 保留轨迹起点圆形、终点方形及行驶方向箭头，因为它们属于轨迹编码，而不是解释性注释；起止点含义统一放在论文图注中说明。

## 5. 排版与视觉调整

- 保持双栏宽度 `183 mm`，采用 `2 x 3` 等尺寸面板，不更改现有输出文件名。
- 每个面板仍采用左侧平面轨迹、右上坡度、右下速度的结构；六个面板的内部宽度比例、行间距和列间距保持一致。
- 对齐 `(a)`--`(f)` 面板字母和标题基线，避免标题长度变化导致位置漂移。
- 删除底部注释后重新平衡 `top`、`bottom`、`hspace` 和 `wspace`，保证第二行横轴标题及刻度不拥挤，面板之间不发生文字或坐标轴重叠。
- 平面路径保持等比例坐标轴；六条路径均显示完整，不得裁切起点、终点或方向箭头。
- 六幅坡度图使用相同的纵轴范围，六幅速度图使用相同的纵轴范围，以便横向比较。
- 坡度零线可以保留为细灰色虚线；所有数据曲线、刻度、轴标题和面板标题使用统一线宽与字号。
- 最小可见字号不得低于当前图的 `6.2 pt`，建议正文式轴标和刻度采用 `6.5--7 pt`；不通过压缩字体解决排版问题。
- 保持白色背景和当前克制配色，确保灰度打印时路径、坡度、速度、起点和终点仍可辨认。

## 6. 论文图注同步

删除原图注中关于星号的句子。若实际仿真已按元数据修正 P4，可使用：

> Frozen six-route closed-loop benchmark. Each panel shows the complete planar reference path together with the aligned grade and reference-speed profiles. Circles and squares mark route starts and ends, respectively.

若 P4 尚未按该元数据坡度重新运行，则必须使用带来源说明的版本：

> Frozen six-route closed-loop benchmark. Each panel shows the complete planar reference path together with the aligned grade and reference-speed profiles. Circles and squares mark route starts and ends, respectively. The P4 grade profile follows its frozen segment metadata.

## 7. 输出与验收

修改生成脚本后重新生成 PDF、SVG、PNG、TIFF、source-data、manifest 和 QA 文件，但保持现有 stem `fig03_closed_loop_route_set` 不变。至少检查：

1. 六条路径顺序仍为 P1--P6，且没有任何星号或底部解释性注释。
2. P4 在 0--4 s 为零坡度，并完整包含 `+4.0 deg` 上坡段和 `-3.5 deg` 下坡段。
3. P5 的最大绝对坡度仍为 `0 deg`。
4. 六幅坡度图和速度图分别共享一致的纵轴范围。
5. 所有标题、刻度和轴标签在最终 `183 mm` 尺寸下清晰，无重叠、裁切或越界。
6. source-data 与图中曲线逐点一致，并保留 P4 坡度的数据来源说明。
7. 论文图注与最终图中的标记完全一致。
