# AGV 路径跟踪公平对比方案（IEEE 风格，Mamba2/GRU/IMU）

更新时间：2026-04-17

## 1. 目标与范围

本方案用于在同一工程框架下，公平比较以下三种配置：

- LPV-MPC + Mamba2
- LPV-MPC + GRU
- LPV-MPC + IMU（弱基线）

对比目标：

- 评估路径跟踪精度、控制平滑性、约束满足、实时性、鲁棒性
- 形成可复现实验流程，支持重复试验与统计显著性检验
- 输出可直接用于论文/报告的图表与结论结构

适配当前工程的关键基础（基于仓库现状）：

- Simulink 模型：
  - Mamba2 配置：simulink/LPVMPC_AGV_simulink_Mamba.slx
  - IMU 配置：simulink/LPVMPC_AGV_simulink_IMU.slx
  - GRU 配置：simulink/LPVMPC_AGV_simulink.slx（在批处理脚本中固定到 GRU 分支）
- Mamba2 在线推理接口：
  - src/Mamba/Mamba_state_classifier.m
  - src/Mamba/mamba2_online_infer.py
- GRU 训练与对照流程入口：
  - src/gru/run_GRU_prepare_dataset_mamba_compare.m
  - src/gru/run_GRU_train_mamba_control.m
- 对比专用目录：
  - src/Compare/（仓库已有目录名；本文统一采用该大小写）
- 路径库：
  - data/paths/path_*.mat

## 2. 文献锚点（近年 IEEE，已核验 DOI）

说明：严格“AGV+路径跟踪”标题命中文献很少，工程上通常结合“AGV专用+车辆/移动机器人路径跟踪”两层证据。

### 2.1 AGV 直接相关

1) IEEE Transactions on Vehicular Technology, 2025  
Interval Trajectory Tracking Control for Automated Guided Vehicles based on a Novel Set-Membership Global Estimation Strategy  
DOI: 10.1109/TVT.2025.3624797

2) IEEE/CAA Journal of Automatica Sinica, 2022  
Dynamic Scheduling and Path Planning of Automated Guided Vehicles in Automatic Container Terminal  
DOI: 10.1109/JAS.2022.105950

3) IEEE Transactions on Industrial Informatics, 2025  
A Platoon-Based Approach for AGV Scheduling and Trajectory Planning in Fully Automated Production Systems  
DOI: 10.1109/TII.2024.3455413

### 2.2 路径跟踪方法学（车辆/移动机器人）

4) IEEE Transactions on Intelligent Transportation Systems, 2022  
Trajectory Tracking of Autonomous Vehicle Based on Model Predictive Control With PID Feedback  
DOI: 10.1109/TITS.2022.3150365

5) IEEE Transactions on Intelligent Vehicles, 2023  
Event-Triggered Model Predictive Control for Autonomous Vehicle Path Tracking: Validation Using CARLA Simulator  
DOI: 10.1109/TIV.2023.3266941

6) IEEE Transactions on Industrial Electronics, 2024  
Parallel Nonlinear Model Predictive Controller for Real-Time Path Tracking of Autonomous Vehicle  
DOI: 10.1109/TIE.2024.3390738

7) IEEE Transactions on Control Systems Technology, 2024  
Observer-Based Trajectory Tracking Control of Nonholonomic Wheeled Mobile Robots  
DOI: 10.1109/TCST.2024.3351073

8) IEEE Transactions on Vehicular Technology, 2025  
Autonomous Vehicle Path Tracking: Stochastic Tube Model Predictive Control With Covariance Steering and Discounted Chance Constraints  
DOI: 10.1109/TVT.2024.3522673

## 3. 公平性原则（必须满足）

1) 同路径、同初值、同仿真步长、同扰动注入。
2) 同等控制输入边界与输入变化率边界。
3) 同一误差定义（同一坐标系、同一符号约定）。
4) 每条路径都做多随机种子重复（禁止单次跑分）。
5) 指标主表必须给出均值与离散度（标准差或分位数）。
6) 统计检验先于结论（先显著性，再“优于/劣于”）。

## 4. 场景矩阵设计

建议至少覆盖以下维度：

- 路径几何：直线、S弯、多弯、坡道
- 速度段：低速、中速、高速
- 扰动级别：无扰动、轻扰动、强扰动
- 模型失配：名义参数、质量偏差、摩擦偏差

可直接使用现有路径集合（示例）：

- data/paths/path_straight.mat
- data/paths/path_s_curve.mat
- data/paths/path_multi_turn_left.mat
- data/paths/path_slope.mat
- data/paths/path_industrial_lite.mat

推荐实验规模（最低）：

- 控制器 3 个
- 路径 >= 6 条
- 扰动等级 3 个
- 重复次数 N >= 10

总仿真次数约为 3 x 6 x 3 x 10 = 540。

## 5. 指标体系（主指标 + 辅指标）

### 5.1 主指标（论文主表）

1) 横向误差：

$$
\mathrm{RMSE}(e_y)=\sqrt{\frac{1}{T}\int_0^T e_y^2(t)\,dt}
$$

2) 航向误差：

$$
\mathrm{RMSE}(e_\psi)=\sqrt{\frac{1}{T}\int_0^T e_\psi^2(t)\,dt}
$$

3) 峰值误差：

$$
\max |e_y|,\quad \max |e_\psi|
$$

4) 控制平滑性（输入变化率）：

$$
J_{\Delta u}=\frac{1}{T}\int_0^T \|\dot u(t)\|_2^2\,dt
$$

5) 约束违反率：

$$
r_{\mathrm{viol}}=\frac{1}{T}\int_0^T \mathbf{1}[u(t)\notin\mathcal{U}]\,dt
$$

6) 实时性：

- 每步求解时间中位数 P50
- 尾部延迟 P95/P99
- 超时率（超过采样周期比例）

### 5.2 辅指标（分析与解释）

- 速度误差 RMSE
- 饱和占比
- 能耗近似指标（如 $\int |F\cdot v|dt$）
- 稳态误差（末段窗口均值）

## 6. 统计检验与排名规则

### 6.1 检验流程

1) 每条路径内，先做配对差值（同种子、同场景下两控制器相减）。
2) 正态性可疑时，优先用 Wilcoxon 符号秩检验。
3) 多控制器总体比较可用 Friedman 检验。
4) 事后两两比较用 Holm 校正控制多重比较。

### 6.2 报告格式

每个主指标至少报告：

- 均值 ± 标准差
- 中位数 [P25, P75]
- p 值（校正后）
- 效应量（建议 Cliff's delta 或配对 Cohen's d）

### 6.3 总分与名次

不建议只给单一加权分。推荐：

- 主表分指标排名
- 另给“鲁棒性优先”与“精度优先”两种权重结果作敏感性分析

## 7. 与现有工程的落地映射

### 7.1 已有基础与缺口

- 已有三条模型链路（Mamba2/GRU/IMU）和路径库，可直接支撑同场景对比。
- src/Compare/ 目录已存在，但当前为空。
- 当前仓库中尚无“批量三配置对比 + 统计检验”的一体化脚本。
- 你已明确不采用 src/tests/test_simulink_closed_loop.m 作为主流程入口。

### 7.2 建议新增（最小改造）

1) 在 src/Compare/ 新增批量驱动脚本（建议名）：run_compare_mamba2_gru_imu_batch.m
- 输入：模型名、路径列表、随机种子列表、扰动等级
- 输出：统一结果结构体 results

2) 在 src/Compare/ 新增统计分析脚本（建议名）：analyze_compare_mamba2_gru_imu_stats.m
- 执行检验、输出表格、保存图形

3) 新增统一结果目录：results/compare/mamba2_gru_imu/
- 原始明细
- 统计汇总
- 图表

### 7.4 开跑前待修改清单（必须完成）

1) 在批处理脚本中显式绑定三配置入口（Mamba2/GRU/IMU），禁止自动回退到其他分支。
2) 显式声明不使用 src/tests/test_simulink_closed_loop.m 作为实验入口。
3) 固化随机种子列表与扰动注入规则，并写入结果元数据（可追溯）。
4) 统一日志字段命名与单位（角度/弧度、力/归一化控制量），避免后处理混淆。
5) 统计脚本输出必须包含校正后 p 值与效应量，避免仅凭均值下结论。

### 7.3 日志信号契约（建议）

三模型统一记录下列信号名：

- 误差：e_y, e_psi, e_v, e_omega
- 控制：F_cmd, omega_cmd
- 状态：X, Y, psi, v, omega
- 实时性：solve_time_ms（若可获取）

## 8. IMU 弱基线说明写法（可直接用于论文）

- 本文将 LPV-MPC+IMU 设为工程可运行弱基线，用于体现学习估计器在坡度/工况识别方面的增益。
- IMU 分支不引入复杂姿态融合与高阶漂移补偿，避免将研究焦点转移到传感器融合算法本身。
- 该设定保证了基线可运行、可复现、可解释，但不代表 IMU 方案的理论上限。

## 8.1 Mamba2 与 GRU 对照说明（建议补充到论文实验设置）

- Mamba2 与 GRU 的训练数据母集应保持一致（建议统一使用 data/mamba/Mamba_train_data_full.mat 派生）。
- 数据切分策略建议固定为 run-level 可复现策略（同 seed、同划分比例）。
- 闭环比较阶段仅更换工况估计/分类模块，保持 MPC 主参数、约束和路径任务一致。
- 对比结论应区分：模型本体差异、数据分布差异、以及在线接口延迟差异。

## 9. 结果判定门槛（建议）

声明“显著优于”需同时满足：

1) 主指标 e_y RMSE 与 e_psi RMSE 至少一项显著更优（校正后 p < 0.05）。
2) 约束违反率与实时性不劣化（或劣化不显著）。
3) 在 >= 70% 路径上保持同方向优势。

## 10. 一页执行清单

1) 固定 Mamba2/GRU/IMU 三配置的输入约束、采样周期、路径与扰动注入。
2) 通过 src/compare/ 下批量脚本跑完整场景矩阵并保存明细。
3) 统一计算主指标与辅指标。
4) 做 Friedman + Wilcoxon(Holm) 统计检验（同路径同种子配对）。
5) 输出主表、箱线图、CDF、代表性轨迹图。
6) 按第 9 节门槛给出结论，避免“看图说话”。

## 11. 专业项目开发流程计划（逐步执行版）

### 11.1 阶段 0：立项冻结与基线定义（Day 0）

1) 明确对比对象仅为 Mamba2、GRU、IMU 三配置，冻结本轮研究边界。
2) 冻结公平性约束：采样周期、输入边界、路径集合、扰动注入规则、随机种子生成策略。
3) 冻结工具链版本：MATLAB/Simulink 版本、Python 环境、关键依赖版本。

产出物：研究边界说明、参数冻结表、环境快照文件。
验收标准：团队成员对同一配置复跑可得到一致配置哈希与环境信息。

### 11.2 阶段 1：需求拆解与任务排期（Day 1）

1) 将工作拆分为四条主线：数据线、训练线、闭环线、统计线。
2) 为每条主线定义负责人、输入、输出、完成时间和依赖关系。
3) 建立统一任务看板，定义任务状态和阻塞升级机制。

产出物：WBS 任务分解表、里程碑时间表、责任矩阵。
验收标准：每个任务都有唯一责任人与可验证交付件。

### 11.3 阶段 2：数据与预处理基线固化（Day 1-2）

1) 统一训练数据母集来源，明确 Mamba2 与 GRU 的同源数据策略。
2) 固化数据清洗、标准化、切分规则，禁止实验过程中临时改动。
3) 将数据版本号和切分种子写入元数据文件，保证追溯。

产出物：数据说明文档、切分索引文件、标准化参数文件。
验收标准：不同机器上可复现完全一致的训练/验证/测试索引。

### 11.4 阶段 3：训练脚本标准化与产物归档（Day 2-3）

1) 统一训练入口参数风格，固定日志格式与模型命名规则。
2) 训练过程强制记录关键指标与早停信息，禁止只留最终模型。
3) 将模型、配置、日志、评估快照按 run_id 归档。

产出物：标准化训练脚本、训练日志、模型权重、训练配置快照。
验收标准：给定 run_id 可完整复原当次训练设置与结果。

### 11.5 阶段 4：闭环接口联调与契约测试（Day 3-4）

1) 统一三配置输入输出信号契约，确保同接口可替换。
2) 编写接口级自检脚本，覆盖维度、单位、时间戳、空值、延迟。
3) 对 Mamba2 在线接口做超时与异常降级策略验证。

产出物：接口契约文档、接口测试脚本、联调报告。
验收标准：三配置通过同一接口测试集且无阻塞级错误。

### 11.6 阶段 5：批量仿真框架实现（Day 4-5）

1) 在 src/Compare/ 实现批量驱动脚本 run_compare_mamba2_gru_imu_batch.m。
2) 支持路径、扰动、种子、配置四维组合自动遍历。
3) 每次仿真自动落盘原始轨迹、控制量、耗时与异常标志。

产出物：批量仿真脚本、结果目录结构、批量运行日志。
验收标准：可一键完成完整矩阵任务且支持失败重试与断点续跑。

### 11.7 阶段 6：统计分析流水线实现（Day 5-6）

1) 在 src/Compare/ 实现分析脚本 analyze_compare_mamba2_gru_imu_stats.m。
2) 按配对设计输出 Friedman、Wilcoxon、Holm 校正结果。
3) 输出效应量、置信区间、主表与图形（箱线图、CDF、轨迹对照）。

产出物：统计表、图形文件、自动生成摘要报告。
验收标准：统计结论与图表结论一致，且可从原始结果追溯。

### 11.8 阶段 7：试运行与质量门禁（Day 6）

1) 先运行 10% 小规模矩阵，验证流程稳定性与结果合理性。
2) 检查异常率、超时率、缺失率，超过阈值立即回滚修复。
3) 通过后再执行全量矩阵，避免资源浪费。

产出物：试运行报告、问题清单、修复记录。
验收标准：小规模试运行无 P0/P1 问题且关键指标分布合理。

### 11.9 阶段 8：全量实验执行与监控（Day 7-8）

1) 执行完整场景矩阵并实时监控进度、失败任务和资源占用。
2) 对失败任务按统一策略重试并记录重试原因。
3) 每日输出进度简报，确保实验可控。

产出物：全量实验日志、重试日志、进度日报。
验收标准：全量覆盖率达到 100%，有效样本满足统计最小规模。

### 11.10 阶段 9：结果复核与结论发布（Day 9）

1) 进行双人复核：代码复核、统计复核、图表复核。
2) 按第 9 节判定门槛发布结论，区分显著优于与工程可用优于。
3) 输出最终结论时附上局限性与外推边界。

产出物：最终报告、图表包、复核记录、结论摘要。
验收标准：结论可被第三方按文档步骤独立复现。

### 11.11 阶段 10：沉淀与复用（Day 10）

1) 将脚本、模板、配置、报告流程沉淀为可复用资产。
2) 形成下一轮实验改进清单，按影响度排序。
3) 对关键经验写入项目文档，降低后续协作成本。

产出物：资产清单、复用手册、下一轮优化路线图。
验收标准：新成员可按手册独立完成一次端到端复现实验。

## 12. 执行顺序总览（里程碑）

1) M1 参数与环境冻结完成。
2) M2 数据与训练基线可复现。
3) M3 闭环接口与批量仿真打通。
4) M4 统计流水线与质量门禁通过。
5) M5 全量实验完成并发布结论。

## 13. 自动化执行入口（已实现）

已在 src/Compare/ 提供三份自动化脚本：

1) run_pipeline_mamba2_gru_imu.m
- 端到端主入口：可自动执行 GRU 数据预处理、GRU 训练、批量闭环对比、统计分析。

2) run_compare_mamba2_gru_imu_batch.m
- 批量仿真入口：按 控制器 x 路径 x 扰动 x 随机种子 生成全矩阵结果。

3) analyze_compare_mamba2_gru_imu_stats.m
- 统计分析入口：输出 Friedman、Wilcoxon + Holm、效应量、主表与图表。

建议执行顺序：

1) 一键端到端：run('src/Compare/run_pipeline_mamba2_gru_imu.m')
2) 仅跑批量仿真：run('src/Compare/run_compare_mamba2_gru_imu_batch.m')
3) 仅做统计分析：run('src/Compare/analyze_compare_mamba2_gru_imu_stats.m')

默认输出目录：

- results/compare/mamba2_gru_imu/
  - compare_时间戳/raw/case_rows.mat
  - compare_时间戳/raw/case_rows.csv
  - compare_时间戳/analysis/analysis_summary.mat
  - compare_时间戳/analysis/analysis_report.md

## 14. 需要人工确认或手动设置的项

以下项无法完全由脚本替你决定，需要你反馈一次配置：

1) Mamba2 在线服务是否启用
- 若使用 tcp_service，需要先在 WSL 侧启动 mamba2_online_infer.py 服务。
- 若暂不启用，可在主入口配置中切换为 matlab_stub（仅联调用，不用于最终结论）。

2) 训练资源策略
- GRU 训练默认 use_gpu=true、max_epochs=30；若本机无 GPU 或预算受限，请确认是否改为 CPU/更少 epoch。

3) 全量矩阵规模
- 默认为 3 控制器 x 6 路径 x 3 扰动 x 10 种子。
- 若你希望先做冒烟验证，可先将 seeds 减到 2-3，再放大全量运行。

4) 结果覆盖门槛
- 是否严格执行第 9 节门槛（建议是）；如有项目特定门槛，请明确阈值。
