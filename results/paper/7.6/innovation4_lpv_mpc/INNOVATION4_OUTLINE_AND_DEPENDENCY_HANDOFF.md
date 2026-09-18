# 创新点4正文大纲与创新点3依赖边界

日期：2026-07-12

适用论文：

```text
results/paper/Latex/paper_v2.tex
```

## 0. 结论

可以先跳过创新点3的完整理论与实验，直接撰写创新点4的方法正文。

原因是当前项目已经形成清晰的模块接口：创新点3无论采用何种自适应权重或保护规则，最终都向控制器输出一个当前时刻可用的融合坡度标量；创新点4只使用该标量构造调度向量、更新离散LPV模型，并求解MPC。融合权重的生成方式不会改变LPV网格、离散线性化、三线性插值或MPC优化问题。

创新点3会影响创新点4的最终实验结果和论文结论强度，但不影响创新点4主体方法的推导。当前可先完成控制方法，暂缓所有“融合优于单源”的定量结论。

## 1. 创新点3与创新点4的依赖边界

| 内容 | 是否依赖创新点3最终结果 | 当前处理方式 |
|---|---|---|
| 离散误差状态模型 | 否 | 可直接撰写 |
| LPV网格及三线性插值 | 否 | 可直接撰写 |
| MPC代价函数与约束 | 否 | 可直接撰写 |
| 调度坡度的符号和输入端口 | 弱依赖 | 统一记为 `hat(theta)^fus_k` |
| 融合权重公式、门控和保护逻辑 | 是 | 在创新点3占位，暂不固定 |
| 融合坡度的延迟、限速和死区参数 | 是 | 创新点3定稿后回填 |
| 融合LPV-MPC相对单ModernTCN或单IMU的闭环增益 | 是 | 暂不写结果性结论 |
| 零坡度、真值坡度和模型更新机理分析 | 否 | 可先组织实验和理论说明 |

必须保持以下解耦原则：MPC只接收最终坡度标量，不直接使用融合权重、种子编号、路径名称或未来信息。若后续决定让融合置信度进一步改变MPC权重或约束，则创新点3和4将重新耦合，届时需要修改本大纲。

## 2. 建议冻结的控制接口

创新点3占位节与创新点4之间采用以下接口合同：

```math
\hat\theta^{fus}_k
= \text{the latest causal fused slope available at time }k,
```

```math
\theta^{sch}_k = \mathcal S(\hat\theta^{fus}_k),
\qquad
\rho_k = [v_{f,k},\omega_{f,k},\theta^{sch}_k]^\mathsf T.
```

其中 `S(.)` 表示部署侧的幅值限制、死区、变化率限制或其他已确认保护。创新点3定稿后可以补充 `S(.)` 的具体组成，但创新点4只需要以下性质：

1. 当前时刻因果可用，不使用未来坡度或参考路径真值；
2. 单位为rad，并与LPV数据库坡度轴一致；
3. 超出数据库范围时在控制侧饱和；
4. LPV模型更新、MPC measured-disturbance端口和坡度前馈使用同一个同步后的坡度值；
5. 若融合估计存在推理延迟，使用“当前时刻最新可用值”，并在实验设置中报告延迟。

项目中的Node26同步修复已经验证：`UpdatePlantModel`和Adaptive MPC的MD端口均由同一`RhoFilter`输出驱动，MD具体使用`rho_f(:,3)`。创新点4正文必须保留这一同步关系，不能再画成一条未滤波坡度直接进入MD、另一条滤波坡度进入模型更新。

## 3. 创新点4建议标题与总逻辑

建议标题：

```text
Fused-Slope-Scheduled LPV-MPC Formulation
```

创新点4开头首先完成从前文连续非线性AGV模型到离散控制模型的过渡。此前创新点1和2的有效正文只给出了连续车辆动力学、坡度估计目标、ModernTCN和历史特征构造；创新点3占位只定义融合坡度接口。旧稿中出现的“discrete vehicle state”和`x_{k+1}=f(x_k,u_k,theta_k,p)`位于`\iffalse`块内，不进入当前PDF。因此，离散化过程、离散状态方程、输出方程和系数矩阵应在创新点4中首次完整给出。

完成离散模型后，再说明坡度不仅表现为外部纵向扰动，还改变局部误差动力学和合适的控制配置。因此，融合坡度不应只作为补偿项加入，而应作为可解释调度变量，同步驱动局部模型、测量扰动、名义前馈以及权重/约束更新。

全文逻辑建议为：

```text
前文连续非线性AGV模型
  -> 一步离散状态转移与路径误差映射
  -> 离散系数矩阵 A_d/B_d/C_d/D_d/E_d
  -> 离线LPV模型库
  -> 融合坡度调度接口
  -> 在线三线性插值
  -> 模型/MD/前馈/权重与约束同步更新
  -> 有限时域MPC求解
  -> 施加首个控制量并滚动更新
```

## 4. 正文小节结构

### A. Discrete-Time Path-Error Model and Coefficient-Matrix Construction

本小节必须放在创新点4最前面，负责把前文连续AGV动力学转换为MPC实际使用的离散路径误差模型。不能只写一句“the model is discretized”，而应交代状态选择、一步状态转移、工作点、扰动变量、状态方程、输出方程和每个系数矩阵的生成方式。

控制状态、控制输入和坡度扰动定义为：

```math
\mathbf x^e_k=[e_{y,k},e_{\psi,k},e_{v,k},e_{\omega,k}]^\mathsf T,
```

```math
\mathbf u_k=[F_{cmd,k},\omega_{cmd,k}]^\mathsf T,
\qquad d_k=\theta_k.
```

先把连续动力学记为`dot(x)=f_c(x,u,theta)`，再定义项目实际采用的一步状态转移：

```math
\mathbf x_{k+1}=\Phi_{T_s}(\mathbf x_k,\mathbf u_k,\theta_k),
\qquad T_s=0.01\ \mathrm{s},
```

其中`Phi_Ts(.)`是`state_eq_ref`在一个采样周期内的非线性状态推进。随后通过全局状态到路径误差状态的映射`q(.)`得到一步误差转移`g(.)`。在工作点`(bar(x),bar(u),bar(theta))`附近，正文应采用偏差形式：

项目实际采用混合的一步离散推进。转向执行器首先按前向一步更新并施加角度/角速度限制：

```math
\delta_{i,k+1}=\operatorname{sat}\!\left(
\delta_{i,k}+T_s\dot\delta_{i,k},-\delta_{max},\delta_{max}\right),
\qquad i\in\{lf,rr\}.
```

其余核心状态记为`\mathbf s=[X,Y,psi,v,omega,beta]^T`，使用四阶Runge--Kutta推进，并在中间级使用转向角中点值：

```math
\begin{aligned}
\mathbf k_1&=f_c(\mathbf s_k,\delta_k),\\
\mathbf k_2&=f_c(\mathbf s_k+\tfrac{T_s}{2}\mathbf k_1,\delta_{k+1/2}),\\
\mathbf k_3&=f_c(\mathbf s_k+\tfrac{T_s}{2}\mathbf k_2,\delta_{k+1/2}),\\
\mathbf k_4&=f_c(\mathbf s_k+T_s\mathbf k_3,\delta_{k+1}),\\
\mathbf s_{k+1}&=\mathbf s_k+\frac{T_s}{6}
(\mathbf k_1+2\mathbf k_2+2\mathbf k_3+\mathbf k_4).
\end{aligned}
```

因此，创新点4不能写成“采用ZOH和`c2d`获得离散模型”。准确表述应是：先用上述RK4/执行器一步更新构成非线性离散映射`Phi_Ts`，再对该离散映射进行工作点有限差分线性化。

```math
\Delta\mathbf x^e_{k+1}=A_d(\rho_k)\Delta\mathbf x^e_k
+B_d(\rho_k)\Delta\mathbf u_k+E_d(\rho_k)\Delta\theta_k,
```

```math
\Delta\mathbf y_k=C_d(\rho_k)\Delta\mathbf x^e_k
+D_d(\rho_k)\Delta\mathbf u_k.
```

这里使用偏差形式很重要，因为代码通过`plant.U=[F_eq,omega,theta]`保存当前名义输入。坡度既用于选择工作点，也作为measured disturbance的偏差输入进入预测，不能在公式中把实际量和偏差量混写。

系数矩阵应完整展开为：

```math
A_d(\rho)=
\begin{bmatrix}
a_{11}&a_{12}&a_{13}&a_{14}\\
a_{21}&a_{22}&a_{23}&a_{24}\\
a_{31}&a_{32}&a_{33}&a_{34}\\
a_{41}&a_{42}&a_{43}&a_{44}
\end{bmatrix},
\quad
B_d(\rho)=
\begin{bmatrix}
b_{11}&b_{12}\\
b_{21}&b_{22}\\
b_{31}&b_{32}\\
b_{41}&b_{42}
\end{bmatrix},
```

```math
E_d(\rho)=
\begin{bmatrix}e_1&e_2&e_3&e_4\end{bmatrix}^\mathsf T,
\qquad
C_d=I_4,
\qquad
D_d=0_{4\times2}.
```

项目中没有单独保存一套解析闭式`a_ij,b_ij,e_i`公式，而是从非线性一步转移直接计算数值雅可比。因此，正文中每个元素应按实际算法定义：

```math
a_{ij}(\rho)=
\frac{g_i(\bar x^e+\varepsilon_{x,j}\mathbf e_j,\bar u,\bar\theta)
-g_i(\bar x^e,\bar u,\bar\theta)}{\varepsilon_{x,j}},
```

```math
b_{ij}(\rho)=
\frac{g_i(\bar x^e,\bar u+\varepsilon_{u,j}\mathbf e_j,\bar\theta)
-g_i(\bar x^e,\bar u-\varepsilon_{u,j}\mathbf e_j,\bar\theta)}
{2\varepsilon_{u,j}},
```

```math
e_i(\rho)=
\frac{g_i(\bar x^e,\bar u,\bar\theta+\varepsilon_\theta)
-g_i(\bar x^e,\bar u,\bar\theta-\varepsilon_\theta)}
{2\varepsilon_\theta}.
```

这样既给出了详细矩阵表达，也准确反映`lin_agv_at_point.m`的一步有限差分实现。若强行推导一套简化解析矩阵，反而会与包含执行器、轮胎限幅、载荷转移和数值稳定化的实际模型不一致。

### B. Offline LPV Model Database

本小节说明上述离散系数矩阵如何在三维工作点上离线生成并形成canonical数据库。

需要说明的项目实际：

1. `A_d,B_d,E_d`由非线性一步状态转移的数值有限差分直接获得；
2. 这里不是先求连续线性模型再调用`c2d`；
3. 线性化工作点使用坡度平衡驱动力和对应横摆指令；
4. 数据库坡度轴同时参与工作点生成和扰动雅可比计算；
5. 为满足MPC数值要求，数据库生成阶段对单位圆外的离散模态进行了有限的谱半径稳定化，此项应在正文末句、参数表注释或附录中透明说明。

当前canonical数据库：

| 轴 | 网格 |
|---|---|
| 速度`V` | 11点，`0.02-1.20 m/s`，非均匀 |
| 横摆角速度`W` | 15点，`-1.20-1.20 rad/s` |
| 坡度`Theta` | 25点，`-12 deg`到`12 deg`，步长`1 deg` |
| 总工作点 | `11 x 15 x 25 = 4125` |

### C. Fused-Slope Scheduling Interface and Coordinated Update

本小节承接创新点3，并明确融合坡度在控制器中的接口，不再承担离散模型的首次定义。

应包含：

1. 定义融合坡度、调度坡度和调度向量；
2. 说明速度、横摆角速度和坡度分别描述纵向、转向和路面工况；
3. 明确同一个`theta^sch_k`同步进入四条控制路径；
4. 解释同步的必要性：若模型插值和MD端口使用不同时间基准，会造成模型与扰动不一致；
5. 给出不同基线的坡度源定义：零坡度、IMU、ModernTCN、融合坡度和真值oracle。

四条实际控制路径为：

| 路径 | 项目实现 | 作用 |
|---|---|---|
| LPV模型矩阵 | `mpc_update_from_rho`插值`A,B,C,D,E` | 更新预测动力学 |
| measured disturbance | Adaptive MPC的MD端口接收`rho_f(:,3)` | 显式预测坡度扰动作用 |
| 名义工作点/前馈 | `F_eq = mg(sin(theta)+c_r cos(theta))` | 对齐坡度平衡驱动力 |
| 权重与约束 | 输出`Q,R,dR,umin,umax`到Adaptive MPC端口 | 随转弯和坡度工况调整控制侧配置 |

注意：论文摘要目前只写“融合坡度进入代价函数和约束”，这一表述不完整。最终应改为“融合坡度同步更新局部预测模型、坡度扰动通道、名义前馈以及调度权重/约束”。

### D. Online Trilinear Interpolation and Slope-Dependent Controller Scheduling

本小节解释在线更新怎样落地，不重复离散模型的构造过程。

应包含：

1. 将`rho_k`限制到数据库边界；
2. 定位包围当前工况的三维网格单元；
3. 定义局部坐标`xi, eta, zeta in [0,1]`；
4. 给出8个顶点的三线性权重；
5. 对`A,B,C,D,E`执行同一组权重插值；
6. 用坡度和横摆工况平滑调度`Q,R,dR`及输入上下界；
7. 将插值结果组装为Adaptive MPC在线plant和外部权重/约束端口。

矩阵插值可统一写为：

```math
M(\rho_k)=\sum_{j=1}^{8}\lambda_j(\xi_k,\eta_k,\zeta_k)M_j,
\quad M\in\{A_d,B_d,C_d,D_d,E_d\},
```

```math
\lambda_j\ge 0,\qquad\sum_{j=1}^{8}\lambda_j=1.
```

调度权重部分不宜把所有工程参数逐项展开成大量分段式。正文说明“阈值附近采用smooth-step连续过渡”，参数数值放入表格；完整映射可放附录或补充材料。

### E. MPC Prediction Equations, Constraints, and Receding-Horizon Execution

本小节不能只给代价函数，还应先把离散模型递推为预测方程。重点体现更新后的模型、权重和约束均在时刻`k`固定后进入预测。

应包含：

1. 给出`x_{k+i|k}`和`y_{k+i|k}`的逐步离散预测方程；
2. 说明当前实现采用时刻`k`冻结的插值模型，还是在预测域内继续调度；按当前Adaptive MPC实现应写为当前更新模型在本次QP内固定；
3. 预测时域`Np=150`与控制时域`Nc=30`；
4. 对`e_y,e_psi,e_v,e_omega`的跟踪代价；
5. 对`F_cmd,omega_cmd`及其增量的惩罚；
6. 输入幅值、输入变化率和输出软约束；
7. measured disturbance在预测域中的使用方式；
8. 每个采样时刻只施加最优序列的首个控制量。

在逐步方程之后，可给出标准提升形式：

```math
\mathbf Y_k=\mathcal F_k\Delta\mathbf x^e_k
+\mathcal G_k\Delta\mathbf U_k
+\mathcal H_k\Delta\boldsymbol\Theta_k,
```

其中`F_k,G_k,H_k`由当前插值后的`A_d,B_d,C_d,E_d`构造。正文不必逐元素展开150步预测矩阵，但必须说明其块矩阵组成和维数，避免从单步状态方程直接跳到代价函数。

建议代价函数：

```math
J_k=\sum_{i=1}^{N_p}\|y_{k+i|k}-y^{ref}_{k+i}\|^2_{Q_k}
+\sum_{i=0}^{N_c-1}\|u_{k+i|k}\|^2_{R_k}
+\sum_{i=0}^{N_c-1}\|\Delta u_{k+i|k}\|^2_{R_{\Delta,k}}.
```

下标`k`应保留，以体现权重可能随当前调度点更新。不要写成融合坡度直接作为新的优化变量；在当前项目中，它是可测/可估调度量和MD输入，不是由MPC优化的决策变量。

### F. Online Update Sequence

建议用一个简短算法框或段落收束本节：

```text
At each k:
1. acquire the current AGV state and latest fused slope;
2. condition/filter the scheduling variables;
3. synchronize theta^sch_k to rho_k and the MPC MD input;
4. locate the LPV cell and interpolate model matrices;
5. update nominal input, weights, and constraints;
6. solve the finite-horizon MPC problem;
7. apply the first command and advance to k+1.
```

这一部分能把公式重新连接为实际闭环流程，也是创新点4区别于一般MPC介绍的关键。

## 5. 图表规划

### 5.1 主方法图：建议创建一张双栏三面板矢量图

建议图名：

```text
Fused-slope-scheduled LPV-MPC model update and receding-horizon control.
```

Panel (a)：连续模型到离散LPV数据库的离线构造

```text
continuous nonlinear AGV dynamics
  -> path-error mapping [e_y,e_psi,e_v,e_omega]
  -> steering one-step update + RK4 nonlinear state propagation
  -> finite-difference Jacobians at Ts=0.01 s
  -> A_d/B_d/C_d/D_d/E_d
  -> 11 x 15 x 25 offline LPV database
```

Panel (b)：融合坡度接口与三维LPV插值

```text
ModernTCN + causal IMU
  -> innovation-3 fusion placeholder
  -> conditioning/RhoFilter
  -> rho_k=[v_f,omega_f,theta^sch]
axes: v, omega, theta
current rho_k inside one cell
8 neighboring vertices
lambda_1 ... lambda_8
interpolated A/B/C/D/E
```

Panel (c)：Adaptive MPC闭环更新

```text
model + MD + nominal feedforward + weights/constraints
  -> finite-horizon optimizer
  -> F_cmd, omega_cmd
  -> nonlinear AGV
  -> measured state for next update
```

视觉上应同时突出两件事：第一，创新点4使用的不是一个未说明来源的线性模型，而是由前文连续AGV动力学经过一步离散线性化形成的LPV数据库；第二，同一坡度同步进入模型调度和MD两条关键支路，这是Node26修复后最重要的在线实现事实。不要在图中展开创新点3内部的权重网络，以免在融合算法未定稿时反复重画。

现有`fig03_scheduling_mismatch.pdf`只说明调度误差会导致预测失配，不能完整承担创新点4主图。建议将其核心逻辑并入新图的旁注或在最终排版时删除，避免两张概念图重复。

### 5.2 表1：模型和接口定义

建议列出：状态、控制输入、调度变量、测量扰动、输出、单位、维数和在线来源。该表用于消除“坡度既是调度变量又是MD”的歧义。

### 5.3 表2：LPV数据库与MPC设置

建议列出：`Ts`、三维网格、总工作点、线性化方法、插值方法、`Np/Nc`、基础权重、输入/增量/输出约束、求解器和更新周期。

### 5.4 Algorithm 1：推荐但非必须

如果正文公式较多，建议用7步在线更新算法替代第三张独立流程图。这样既能交代实时实现，又不会增加过多版面。

### 5.5 方法部分不放结果图

创新点4方法节不建议放闭环误差曲线或柱状图。结果图应进入实验章节，理论部分只保留控制结构图、LPV插值示意图和参数表。

## 6. 实验章节需要与创新点4呼应的内容

当前可以先准备、且不依赖创新点3最终晋级结果的内容：

1. 零坡度与true-slope oracle之间的调度失配对照；
2. `rho_f(:,3)`与MD同步性的实现审计；
3. LPV网格覆盖率和越界饱和统计；
4. 单步模型预测误差或代表性矩阵随坡度变化的分析；
5. MPC求解时间和0.01 s采样周期下的实时性统计。

必须等待创新点3定稿后才能写入最终结论的内容：

1. fused-slope LPV-MPC相对ModernTCN-only和IMU-only的闭环优势；
2. 融合策略在多seed、多路径上的均值、方差和最坏路径结果；
3. 摘要、贡献和结论中关于融合增益的定量描述；
4. 最终融合保护参数、延迟和失效回退策略。

推荐最终控制对照组：

| 组别 | 调度坡度源 | 用途 |
|---|---|---|
| ZS-LPV-MPC | `0` | 验证忽略坡度的模型失配 |
| IMU-LPV-MPC | 因果IMU估计 | 单传感器基线 |
| TCN-LPV-MPC | ModernTCN输出 | 单学习模型基线 |
| Fusion-LPV-MPC | 最终融合输出 | 提出方法 |
| Oracle-LPV-MPC | true slope | 性能参考上界，不作为可部署方案 |

所有组必须使用相同AGV plant、LPV数据库、MPC时域、权重映射、约束和同步逻辑，仅改变坡度源。

## 7. 已修正内容与创新点4正文完成状态

1. 已将MPC参数表从旧稿的`Np=160, Nc=60`修正为当前闭环入口使用的`Np=150, Nc=30`。
2. 已将旧固定`Q,R,dR`修正为P0口径的名义值和在线基础调度范围，并补充在线输入约束包络及runtime ECR权重。
3. 已将学习坡度记号统一为`hat(theta)^fus_k`。
4. 已在`paper_v2.tex`中完成离散路径误差模型、执行器前向更新、RK4一步转移、有限差分矩阵、4125点数据库和8顶点三线性插值的正文表述。
5. 已将创新点4旧的通用LPV段落和调度失配概念图替换为`fig_fused_slope_lpv_mpc.pdf`；主图明确展示连续模型到离散数据库、融合坡度同步以及MPC滚动闭环。
6. 正文明确了谱半径稳定化发生在离线数据库生成阶段，而不是插值后临时修改；后续实验应报告代表性矩阵或数据库审计即可。
7. 最终实验runner仍应检查是否显式注入`mpc_runtime_override`；若存在论文主实验专用覆盖，应以保存到结果文件中的`runtime_override_used`为最终参数证据。

## 8. 项目证据位置

```text
src/core/parameters.m
src/core/preloadfcn_v2.m
src/core/UpdatePlantModel.m
src/lpv/lin_agv_at_point.m
src/lpv/lin_agv_grid.m
src/mpc/mpc_update_from_rho.m
src/mpc/mpc_setup_single_interp.m
data/models/lin_agv_db.mat
results/paper/agv_model_parameter_correction_workflow/04_lpv_database/
results/modern_tcn_metric_rebuild/26_rhof_md_sync_repair/
results/modern_tcn_metric_rebuild/36_moderntcn_imu_fusion/
```

## 9. 后续工作顺序

```text
1. 已完成A：连续模型到离散路径误差模型及系数矩阵；
2. 已完成B：4125点离线LPV数据库；
3. 已完成C：融合坡度接口与同步更新；
4. 已完成双栏三面板主图及Python生成脚本；
5. 已完成D：三线性插值和权重/约束调度；
6. 已完成E：离散预测方程、提升矩阵、代价函数与约束；
7. 已完成F：在线滚动更新段落；
8. 已完成LaTeX编译与第10--12页版式检查；
9. 创新点3实验定稿后，仅回填融合节和最终对照结果，不改创新点4主体公式。
```
