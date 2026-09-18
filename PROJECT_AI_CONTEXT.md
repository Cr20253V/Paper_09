# Project AI Context

生成日期：2026-05-15

本文档用于让后续 AI 模型快速理解当前项目。它描述当前项目模块、已完成工作、核心实验结果、论文中各部分的作用，以及继续写论文或补图时应遵循的事实边界。本文档不是删除清单；文件保留和清理细节见 `PROJECT_FLOW_MANIFEST.md`。

## 1. 项目一句话概述

本项目研究面向对角双转向驱动 AGV 的 LPV-MPC 闭环控制增强方法。核心思路是在传统车辆模型、LPV 线性化和 MPC 控制器之上，引入时序神经网络对车辆当前工况进行在线感知和调度辅助，包括：

- 主工况分类：`flat`、`stall`、`slope`；
- 转向方向分类：`right`、`straight`、`left`；
- 坡度角或调度坡度量回归：`theta_hat`。

当前论文主线算法为 `ModernTCN`，主要对照算法为 `GRU` 和 `TCN`。三者使用同一份统一数据集，均已完成训练和闭环仿真验证。用户已在清理后重新运行三个闭环仿真，均无问题。后续又完成了 `causal ModernTCN` 消融实验；该实验用于讨论因果卷积约束与闭环鲁棒性的关系，不替代当前默认部署的 ModernTCN seed 21。最新补充实验加入了无 AI LPV-MPC 基线和 true-theta oracle 上界，并完成多路径/扰动鲁棒性闭环补充实验，用于回答“相对传统/无感知 LPV-MPC 到底提升多少”以及“ModernTCN 是否只在单一路径和名义工况有效”。

## 2. 当前主线结论

当前结论应按下面层次理解：

- 离线感知/预测测试中，`ModernTCN` 的主工况准确率和转向准确率显著高于 `GRU` 和 `TCN`，是当前最强感知模型。
- `GRU` 是稳定的循环网络基线，主工况准确率接近 `ModernTCN`，但转向方向尤其过渡窗口明显弱于 `ModernTCN`。
- `TCN` 是卷积基线，转向准确率尚可，但主工况分类明显弱于另外两者；闭环中也表现出更大的控制抖动和约束触碰。
- 三算法闭环综合排序为 `ModernTCN > TCN > GRU`。`ModernTCN` 在综合跟踪、控制平滑性和总体排序上最好；`TCN` 在闭环原始 `theta_mae_deg` 和 `turn_acc_pct` 上有局部优势，但控制代价较高；`GRU` 在部分调度坡度误差上较好，但整体闭环跟踪弱于 `ModernTCN` 和 `TCN`。
- LPV-MPC theta 基线实验显示，`LPV-MPC_theta0` 和当前简化 `LPV-MPC_IMU_theta` 在坡道后明显失效；`LPV-MPC_oracle_theta` 是真实坡度调度上界，ModernTCN 的横向跟踪已经接近该上界。
- `causal ModernTCN` 离线测试表现接近甚至局部优于原 ModernTCN，但闭环仿真明显失稳。因此它应作为消融和讨论材料：离线因果化不等价于闭环鲁棒性。

论文中推荐表述为：ModernTCN 在统一数据和统一 LPV-MPC 闭环条件下给出最稳健的综合性能，既提升了感知准确率，也改善了闭环跟踪和控制平滑性。相对 `theta=0` 和简化 IMU 坡度估计的无 AI 基线，ModernTCN 带来数量级闭环提升；相对 true-theta oracle，ModernTCN 在横向跟踪上已接近上界，但控制平滑性仍有提升空间。TCN 的局部指标优势不应被表述为整体优于 ModernTCN，因为其主工况识别和控制平滑性存在明显短板。

## 3. 当前权威文件

后续 AI 模型应优先相信以下文件，而不是历史 README 或旧实验报告。

| 类别 | 文件 | 说明 |
|---|---|---|
| 项目流程清单 | `PROJECT_FLOW_MANIFEST.md` | 当前文件整理和保留边界 |
| AI 上下文 | `PROJECT_AI_CONTEXT.md` | 本文档，面向后续 AI 的项目解释 |
| 统一数据集契约 | `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2_contract.json` | 当前数据特征、标签、split 和窗口定义 |
| ModernTCN 默认配置 | `src/ModernTCN/ModernTCN_default_config.m` | 当前 ModernTCN 闭环部署模型 |
| GRU 默认配置 | `src/gru/GRU_default_config.m` | 当前 GRU 闭环部署模型 |
| TCN 默认配置 | `src/TCN/TCN_default_config.m` | 当前 TCN 闭环部署模型 |
| ModernTCN 训练结果 | `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/ModernTCN_train_report.md` | 当前 ModernTCN 训练报告 |
| Causal ModernTCN 消融结果 | `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_multiseed_summary.csv` | causal ModernTCN 多 seed 离线结果 |
| Causal ModernTCN 闭环消融 | `results/compare/causal_modern_tcn_closed_loop/path_factory_logistics_showcase_theta10_v3/` | causal seed 11 闭环消融结果，显示闭环失稳 |
| LPV-MPC theta 基线与 oracle | `results/compare/lpvmpc_theta_baseline/path_factory_logistics_showcase_theta10_v3/` | `theta=0`、IMU theta、true-theta oracle 与三算法合并闭环对比 |
| GRU 训练结果 | `results/gru/train_logs_theta10_uniform_h0_v2/inputstats_hidden96_l2_seed101/GRU_train_report.md` | 当前 GRU 训练报告 |
| TCN 训练结果 | `results/tcn/train_logs_theta10_uniform_h0_v2/tcn96_rawtheta_sym_seed21/TCN_train_report.md` | 当前 TCN 训练报告 |
| 三算法闭环结果 | `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/` | 当前三算法闭环对比 |
| 两算法闭环历史结果 | `results/compare/modern_tcn_gru_closed_loop/` | ModernTCN 和 GRU 的早期闭环对比 |

注意：`data/tcn/README_ModernTCN_dataset.md` 仍包含早期 V3 数据链说明，与当前 `theta10_uniform_conf_h0_v2` 主线不完全一致。后续 AI 不应把该 README 当作当前权威数据定义。

## 4. 统一数据集

当前三种算法使用同一个数据集：

- `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`

对应 raw train data：

- `data/tcn/ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`

数据集关键信息来自 contract：

| 字段 | 当前值 |
|---|---|
| vehicle_type | `diagonal_dual_steer_drive_agv` |
| active_drive_steer_wheels | `LF`, `RR` |
| passive_support_wheels | `RF`, `LR` |
| Ts | `0.01 s` |
| seq_len | `128` |
| input_dim | `19` |
| label_time_policy | `current_window_end` |
| horizon_steps | `0` |
| split_policy | `run_level_no_window_leakage` |
| scaler_policy | `fit_train_only_apply_val_test_online` |
| train_windows | `18302` |
| val_windows | `2607` |
| test_windows | `3733` |

19 个输入特征为：

`accel_x`, `gyro_z`, `I_lf`, `I_rr`, `omega_wheel_lf`, `omega_wheel_rr`, `delta_lf`, `delta_rr`, `gyro_y`, `v_hat`, `dv_hat_dt`, `ws_imbalance`, `I_sum`, `I_diff_signed`, `I_diff_abs`, `accel_x_lp`, `kappa_proxy`, `accel_per_current`, `pitch_angle_est`。

标签定义：

| 任务 | 类别/输出 | 说明 |
|---|---|---|
| 主工况分类 | `flat=1`, `stall=2`, `slope=3` | 用于识别平地、堵转/异常和坡道工况 |
| 转向方向分类 | `right=-1`, `straight=0`, `left=1` | 用于识别转向方向 |
| 坡度回归 | `theta_hat` | 用于闭环中的坡度感知或调度参考 |

论文作用：

- 在“实验数据与标签构建”章节说明所有算法使用同一数据集、同一特征、同一 split，保证对照公平；
- 在“实验设置”章节说明输入窗口长度为 128 steps，即 1.28 s；
- 在“模型输出”章节说明三任务学习结构：主工况分类、转向分类、坡度回归。

## 5. 车辆模型、LPV-MPC 与 Simulink 基础层

该模块不是论文中的深度学习贡献，但它是全部闭环结果的实验平台。

主要代码：

| 模块 | 文件 | 作用 |
|---|---|---|
| AGV S-Function | `src/core/agv_model_sfunc.m` | 闭环仿真车辆模型 |
| 数据生成 S-Function | `src/core/agv_model_sfunc_train_data.m` | 训练数据仿真模型 |
| 状态/输出方程 | `src/core/state_eq.m`, `src/core/output_eq.m` | 非线性车辆状态和输出 |
| 参考方程 | `src/core/state_eq_ref.m`, `src/core/output_eq_ref.m` | 参考轨迹和参考输出 |
| 参数 | `src/core/parameters.m` | 车辆和控制参数 |
| LPV 线性化 | `src/lpv/lin_agv_at_point.m`, `src/lpv/lin_agv_grid.m` | 构造 LPV 网格模型 |
| MPC | `src/mpc/mpc_setup_single_interp.m`, `src/mpc/mpc_update_from_rho.m`, `src/mpc/Cost_Function.m` | 控制器创建、更新和代价函数 |
| 植物模型更新 | `src/core/UpdatePlantModel.m`, `src/core/UpdatePlantModel_gru.m` | Simulink 中更新控制模型 |

关键模型和缓存：

| 文件 | 作用 |
|---|---|
| `data/models/lin_agv_db.mat` | LPV 线性化数据库 |
| `data/models/plant_grid_test.mat` | 植物模型网格 |
| `data/models/ctrl.mat` | MPC 控制器 |
| `data/models/maps_best.mat` | 调度映射或控制相关映射 |

论文作用：

- 系统建模章节：描述 AGV 模型、对角双转向驱动结构和状态/输入定义；
- 控制方法章节：说明 LPV-MPC 是闭环控制基线，神经网络输出用于辅助工况识别和调度；
- 实验平台章节：说明所有算法接入同一 Simulink/LPV-MPC 平台，避免控制器差异影响对比。

## 6. 路径生成与展示路径

路径模块负责生成训练、验证、展示和论文图表所需的参考路径。

当前与论文最相关的路径文件：

| 文件 | 作用 |
|---|---|
| `data/paths/path_factory_logistics_showcase_theta10_v3.mat` | 当前三算法闭环对比使用的展示路径 |
| `data/paths/path_factory_logistics_showcase_theta10_v10.mat` | 早期 ModernTCN/GRU 两算法展示路径 |
| `data/paths/path_modern_tcn_demo_loop_v1.mat` | ModernTCN demo 路径 |
| `data/paths/path_modern_tcn_demo_loop_v2.mat` | ModernTCN demo 路径 |
| `data/paths/path_modern_tcn_theta_sweep_multicond_paper_v1.mat` | 坡度 sweep 论文图相关路径 |

主要脚本：

| 文件 | 作用 |
|---|---|
| `src/paths/gen_agv_ref_path.m` | 基础参考路径接口 |
| `src/paths/gen_agv_theta10_uniform_paths.m` | theta10 uniform 数据路径 |
| `src/paths/gen_factory_logistics_showcase_path.m` | 工厂物流展示路径 |
| `src/paths/gen_modern_tcn_demo_path.m` | ModernTCN demo 路径 |
| `src/paths/gen_modern_tcn_theta_sweep_plot_path.m` | 坡度 sweep 图路径 |
| `src/paths/gen_modern_tcn_theta_sweep_short_paths.m` | 多工况短路径 sweep |

论文作用：

- 展示路径用于闭环轨迹图、分区指标表和控制输入图；
- theta sweep 路径用于坡度感知泛化图；
- 路径图可用于“实验场景设计”或“工业物流场景”小节。

## 7. ModernTCN 模块

ModernTCN 是当前论文主方法。它使用 Python 训练，导出 ONNX 后由 MATLAB/Simulink 加载闭环部署。

当前冻结配置：

| 项 | 当前值 |
|---|---|
| seed | `21` |
| run_tag | `modern_tcn_theta10_uniform_h0_v2_seed21` |
| seq_len | `128` |
| input_dim | `19` |
| channels | `64` |
| blocks | `5` |
| kernel_size | `31` |
| temporal_padding | `same` |
| dropout | `0.15` |
| expansion | `2` |
| 部署模型 | `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.onnx` |

注意：`temporal_padding="same"` 是当前默认和论文主模型。代码已支持 `temporal_padding="causal"` 用于消融实验，但 `ModernTCN_default_config.m` 没有切换到 causal 模型。

主要文件：

| 文件 | 作用 |
|---|---|
| `src/ModernTCN/modern_tcn_model.py` | ModernTCN 模型定义 |
| `src/ModernTCN/modern_tcn_data.py` | 数据读取与 batch 组织 |
| `src/ModernTCN/modern_tcn_metrics.py` | 指标计算 |
| `src/ModernTCN/train_modern_tcn.py` | 单次训练 |
| `src/ModernTCN/run_modern_tcn_theta10_v2_multiseed.py` | 多 seed 训练入口 |
| `src/ModernTCN/test_causal_modern_tcn.py` | causal padding 前缀不变性和 checkpoint 兼容测试 |
| `src/ModernTCN/export_modern_tcn_onnx.py` | ONNX 导出 |
| `src/ModernTCN/check_onnxruntime_consistency.py` | ONNXRuntime 一致性检查 |
| `src/ModernTCN/ModernTCN_check_matlab_onnx.m` | MATLAB ONNX 检查 |
| `src/ModernTCN/ModernTCN_load_predictor.m` | MATLAB 加载器 |
| `src/ModernTCN/ModernTCN_predict_window.m` | MATLAB 在线预测 |
| `src/ModernTCN/ModernTCN_state_classifier.m` | MATLAB 状态分类器 |
| `src/ModernTCN/ModernTCN_State_Classifier_sim.m` | Simulink 包装 |
| `src/ModernTCN/ModernTCN_default_config.m` | 当前部署默认配置 |

当前结果文件：

| 文件 | 作用 |
|---|---|
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.pt` | PyTorch checkpoint |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.onnx` | Simulink 部署模型 |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21_pytorch_reference.mat` | PyTorch 参考输出 |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21_summary.csv` | 训练测试指标 |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/ModernTCN_train_report.md` | 训练报告 |

Causal ModernTCN 消融结果文件：

| 文件 | 作用 |
|---|---|
| `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_multiseed_summary.csv` | causal ModernTCN 五 seed 离线汇总 |
| `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11.pt` | causal 离线综合最优 seed 11 checkpoint |
| `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11.onnx` | causal seed 11 ONNX |
| `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11_onnxruntime_consistency.md` | PyTorch 与 ONNXRuntime 一致性检查 |
| `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11_matlab_consistency.md` | PyTorch 与 MATLAB ONNX 一致性检查 |
| `src/ModernTCN/generated_layers/+modern_tcn_causal_onnx_layers/` | causal ONNX 导入 MATLAB 后生成的隔离 custom layer namespace |

论文作用：

- 方法章节的主网络结构；
- 与 GRU/TCN 的离线对比主结果；
- 闭环实验的主方法；
- 可用于强调多任务时序感知对 LPV-MPC 调度和闭环稳定性的帮助。

## 8. GRU 模块

GRU 是主要循环网络基线。当前 GRU 使用与 ModernTCN 相同的数据集，不再依赖旧 `data/gru` 数据链。

当前冻结配置：

| 项 | 当前值 |
|---|---|
| seed | `101` |
| case_name | `inputstats_hidden96_l2` |
| hidden_size | `96` |
| num_layers | `2` |
| head_pooling | `last_mean_inputstats` |
| turn_head | `mlp/inputstats` |
| 部署模型 | `data/models/GRU_model_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat` |
| 元数据 | `data/models/GRU_meta_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat` |

主要文件：

| 文件 | 作用 |
|---|---|
| `src/gru/GRU_train.m` | 主训练函数 |
| `src/gru/run_GRU_train_theta10_v2_multi_seed.m` | 当前多 seed 训练入口 |
| `src/gru/GRU_default_config.m` | 当前部署默认配置 |
| `src/gru/GRU_infer.m` | 推理函数 |
| `src/gru/GRU_state_classifier.m` | 在线状态分类 |
| `src/gru/GRU_State_Classifier_gru_sim.m` | Simulink 包装 |
| `src/gru/GRU_load_default_to_base.m` | 加载到 base workspace |

论文作用：

- 作为循环神经网络基线，证明 ModernTCN 相比传统 RNN/GRU 在转向识别和闭环综合表现上更好；
- 离线表中重点比较 `acc_turn`、`acc_turn_transition`、`theta_mae_deg`；
- 闭环表中重点比较跟踪误差、调度误差和控制平滑性。

## 9. TCN 模块

TCN 是普通卷积时序网络基线。当前训练已完成，部署 seed 冻结为 21。

当前冻结配置：

| 项 | 当前值 |
|---|---|
| seed | `21` |
| case_name | `tcn96_rawtheta_sym` |
| num_blocks | `6` |
| num_filters | `96` |
| kernel_size | `3` |
| head_pooling | `last_mean_max_inputstats` |
| turn_head | `mlp/inputstats` |
| 部署模型 | `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat` |
| 元数据 | `data/models/TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat` |

主要文件：

| 文件 | 作用 |
|---|---|
| `src/TCN/TCN_train.m` | 主训练函数 |
| `src/TCN/run_TCN_train_theta10_v2_multi_seed.m` | 当前多 seed 训练入口 |
| `src/TCN/TCN_default_config.m` | 当前部署默认配置 |
| `src/TCN/TCN_load_predictor.m` | MATLAB 加载器 |
| `src/TCN/TCN_predict_window.m` | 在线预测 |
| `src/TCN/TCN_state_classifier.m` | 在线状态分类 |
| `src/TCN/TCN_State_Classifier_sim.m` | Simulink 包装 |
| `src/TCN/configure_tcn_simulink_model.m` | Simulink 配置脚本 |

seed 21 的选择依据：

- 在 TCN 多 seed 结果中，seed 21 的 `theta_mae_deg=0.2902` 最低；
- `theta_abs_le_10_p95_abs_err_deg=0.8473` 最低；
- `acc_main=0.7479` 最高；
- `slope_recall=0.8108` 最高；
- seed 101 的 `acc_turn=0.7849` 略高，但其主工况准确率、坡度误差和 slope recall 更弱。

论文作用：

- 作为普通 TCN baseline，说明不是所有卷积时序模型都能带来同等闭环收益；
- 可用于突出 ModernTCN 结构设计和训练策略带来的分类可靠性；
- 闭环中可作为“局部感知指标好但控制综合表现不稳定”的讨论案例。

## 10. Simulink 闭环部署

当前闭环模型与基线：

| 算法 | Simulink 模型 | 预加载入口 |
|---|---|---|
| ModernTCN | `simulink/LPVMPC_AGV_simulink_Modern_TCN.slx` | `src/core/preloadfcn_modern_tcn.m` |
| GRU | `simulink/LPVMPC_AGV_simulink_GRU.slx` | `src/core/preloadfcn_gru.m` |
| TCN | `simulink/LPVMPC_AGV_simulink_TCN.slx` | `src/core/preloadfcn_tcn.m` |
| LPV-MPC theta baselines | `simulink/LPVMPC_AGV_simulink_IMU.slx` | `src/core/preloadfcn_v2.m` + `src/Compare/run_lpvmpc_theta_baseline_experiment.m` |

根目录闭环输出快照：

| 文件 | 说明 |
|---|---|
| `ModernTCN_out.mat` | ModernTCN 闭环仿真输出 |
| `GRU_out.mat` | GRU 闭环仿真输出 |
| `TCN_out.mat` | TCN 闭环仿真输出 |

三算法对比脚本：

- `src/Compare/compare_tcn_gru_modern_closed_loop_out.m`
- `src/Compare/run_lpvmpc_theta_baseline_experiment.m` 用于自动运行 `theta_mode=1/2/3` 的 LPV-MPC 基线，并把结果追加进三算法闭环对比表。

当前三算法对比结果目录：

- `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/`

论文作用：

- 实验平台和闭环验证章节；
- 提供最关键的工程结果：神经网络不是只在离线测试上好，而是在 LPV-MPC 闭环中影响轨迹跟踪、控制约束和控制平滑性。

## 11. 离线训练结果对比

所有离线结果来自同一测试集。主要指标如下。

| 算法 | seed | 配置 | acc_main | acc_turn | acc_turn_transition | theta_mae_deg | theta_abs_le_10_p95_abs_err_deg | flat_recall | stall_recall | slope_recall |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ModernTCN | 21 | `modern_tcn_theta10_uniform_h0_v2_seed21` | 0.9807 | 0.9022 | 0.7757 | 0.2519 | 0.8194 | 0.9657 | 0.6923 | 0.9965 |
| Causal ModernTCN | 11 | `modern_tcn_causal_theta10_uniform_h0_v2_seed11` | 0.9783 | 0.9006 | 0.7907 | 0.2507 | 0.7995 | 0.9590 | 0.7009 | 0.9948 |
| GRU | 101 | `inputstats_hidden96_l2` | 0.9767 | 0.7680 | 0.5271 | 0.2601 | 0.7790 | 0.9604 | 0.6752 | 0.9934 |
| TCN | 21 | `tcn96_rawtheta_sym` | 0.7479 | 0.7771 | 0.5645 | 0.2902 | 0.8473 | 0.5403 | 0.5556 | 0.8108 |

离线结果解读：

- `ModernTCN` 的主工况分类和转向分类最强，尤其 `acc_turn_transition=0.7757` 明显高于 GRU 和 TCN；
- `Causal ModernTCN` 的离线结果接近原 ModernTCN，且 `acc_turn_transition`、`theta_mae_deg` 和 theta P95 略优；但该优势没有转化为闭环收益；
- `GRU` 的 `theta_abs_le_10_p95_abs_err_deg=0.7790` 略好于 ModernTCN 的 0.8194，但分类尤其转向过渡能力明显较弱；
- `TCN` 的转向分类略高于 GRU，但主工况分类显著偏弱，flat/stall recall 不足；
- 对论文主线而言，ModernTCN 的核心优势应放在“多任务时序工况识别可靠性”和“闭环综合收益”，不要单独用某一个 theta P95 指标概括全部结果。

## 12. 三算法闭环结果对比

当前三算法闭环结果来自：

- `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/tcn_gru_modern_closed_loop_summary.csv`
- `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/tcn_gru_modern_closed_loop_rank.csv`
- `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/tcn_gru_modern_closed_loop_report.md`

闭环展示路径：

- `data/paths/path_factory_logistics_showcase_theta10_v3.mat`

综合排序：

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---:|---:|---:|---:|---:|
| ModernTCN | 6 | 6 | 4 | 16 | 1 |
| TCN | 13 | 5 | 11 | 29 | 2 |
| GRU | 17 | 7 | 9 | 33 | 3 |

总体闭环指标：

| controller | ey_rmse | ey_peak | epsi_rmse | ev_rmse | eomega_rmse | xy_rmse | F_peak | omega_cmd_peak | j_du | viol_rate | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ModernTCN | 0.0246 | 0.0940 | 0.0438 | 0.0535 | 0.0307 | 0.8036 | 285.6759 | 0.8860 | 0.5991 | 0.0000 | 0.8974 | 0.9239 | 94.1375 | 81.3941 |
| GRU | 0.0623 | 0.3696 | 0.1714 | 0.0753 | 0.0653 | 1.6641 | 325.0353 | 1.5545 | 7.0298 | 0.0000 | 0.3664 | 0.3415 | 92.2168 | 80.0697 |
| TCN | 0.0364 | 0.1862 | 0.1061 | 0.1154 | 0.0474 | 1.3538 | 720.0000 | 1.4364 | 235.6737 | 5.277e-05 | 0.2590 | 1.7077 | 74.7137 | 86.0904 |

闭环结果解读：

- `ModernTCN` 是综合最优，横向误差、航向误差、角速度误差、XY 误差、控制平滑性和约束安全性都最稳；
- `TCN` 在闭环 `theta_mae_deg` 和 `turn_acc_pct` 上最好，但 `main_acc_pct` 仅 74.71%，`F_peak=720`，`j_du=235.67`，存在明显控制平滑性问题；
- `GRU` 的 `theta_sched_mae_deg` 最低，但轨迹跟踪误差和角速度命令峰值明显弱于 ModernTCN；
- 闭环综合排序比单一离线指标更适合作为论文最终结论，因为论文目标是提升 AGV 闭环控制性能，而不是只优化离线预测误差。

### 12.1 LPV-MPC theta 基线与 oracle 上界实验

该补充实验用于回答审稿人可能提出的问题：如果没有 AI 感知，仅使用传统 LPV-MPC 或真实坡度调度，闭环性能会怎样。实验复用同一展示路径：

- `data/paths/path_factory_logistics_showcase_theta10_v3.mat`

自动化入口：

- `src/Compare/run_lpvmpc_theta_baseline_experiment.m`

输出目录：

- `results/compare/lpvmpc_theta_baseline/path_factory_logistics_showcase_theta10_v3/`

核心结果文件：

- `tcn_gru_modern_lpvmpc_theta_baseline_summary.csv`
- `tcn_gru_modern_lpvmpc_theta_baseline_rank.csv`
- `tcn_gru_modern_lpvmpc_theta_baseline_report.md`
- `lpvmpc_theta0_out.mat`
- `lpvmpc_imu_theta_out.mat`
- `lpvmpc_oracle_theta_out.mat`

三条 LPV-MPC 基线由 `LPVMPC_AGV_simulink_IMU.slx` 中的 `ThetaModeSelect` 切换：

| theta_mode | 曲线含义 | 论文角色 |
|---:|---|---|
| 1 | `LPV-MPC_theta0`，nominal `theta=0` | 无坡度感知/无 AI 的弱基线 |
| 2 | `LPV-MPC_IMU_theta`，简化 IMU 积分坡度估计 | 传统传感器估计基线 |
| 3 | `LPV-MPC_oracle_theta`，true theta/oracle | 真实坡度调度上界 |

合并综合排序如下。注意：LPV-MPC 三条基线的 `main_acc_pct/turn_acc_pct` 是固定占位标签，不代表真实感知分类能力，因此综合排名中的“感知项”不应用来评价 oracle；oracle 更适合作为跟踪和控制性能上界。

| controller | tracking_rank_sum | perception_rank_sum | control_rank_sum | overall_rank_sum | overall_rank |
|---|---:|---:|---:|---:|---:|
| ModernTCN | 11 | 7 | 7 | 25 | 1 |
| LPV-MPC_oracle_theta | 7 | 13 | 6 | 26 | 2 |
| TCN | 19 | 6 | 19 | 44 | 3 |
| GRU | 23 | 8 | 14 | 45 | 4 |
| LPV-MPC_IMU_theta | 33 | 15 | 18 | 66 | 5 |
| LPV-MPC_theta0 | 33 | 14 | 20 | 67 | 6 |

总体核心指标：

| controller | ey_rmse | epsi_rmse | xy_rmse | omega_cmd_peak | j_du | viol_rate | theta_sched_mae_deg |
|---|---:|---:|---:|---:|---:|---:|---:|
| ModernTCN | 0.0246 | 0.0438 | 0.8036 | 0.8860 | 0.5991 | 0.0000 | 0.9239 |
| GRU | 0.0623 | 0.1714 | 1.6641 | 1.5545 | 7.0298 | 0.0000 | 0.3415 |
| TCN | 0.0364 | 0.1061 | 1.3538 | 1.4364 | 235.6737 | 5.277e-05 | 1.7077 |
| LPV-MPC_theta0 | 26.2527 | 1.6517 | 32.0981 | 1.3675 | 285.9290 | 0.1040 | 3.1339 |
| LPV-MPC_IMU_theta | 26.4718 | 1.6155 | 32.1210 | 1.3633 | 285.8180 | 0.1040 | 2.9522 |
| LPV-MPC_oracle_theta | 0.0236 | 0.0315 | 0.5602 | 0.2103 | 0.0609 | 0.0000 | 0.0722 |

实验解读：

- `LPV-MPC_oracle_theta` 证明真实坡度调度下的 LPV-MPC 上界很强：相对 ModernTCN，`xy_rmse` 低约 30%，`j_du` 低约 90%，`omega_cmd_peak` 低约 76%。
- `ModernTCN` 已接近 oracle 的横向跟踪上界：`ey_rmse=0.0246`，oracle 为 `0.0236`，差距约 4.1%。
- `LPV-MPC_theta0` 和 `LPV-MPC_IMU_theta` 在坡道后明显失效，`ey_rmse≈26m`、`xy_rmse≈32m`、约束违规率约 10.4%，说明没有可靠坡度/工况感知时，展示路径上的 LPV-MPC 无法维持闭环轨迹质量。
- 当前简化 `IMU_theta` 仅把调度坡度误差从 `3.13 deg` 降到 `2.95 deg`，但没有改善闭环跟踪，说明该传统估计链路不能替代时序神经网络感知。

推荐论文表述：`LPV-MPC_oracle_theta` 作为 true-theta 上界，`LPV-MPC_theta0` 和 `LPV-MPC_IMU_theta` 作为无 AI 感知基线；ModernTCN 相比无 AI 基线带来数量级闭环提升，并在横向跟踪上接近真实坡度调度上界。

### 12.2 多路径闭环补充实验

本轮新增了多路径闭环补充实验，用于回答“ModernTCN 是否只在单一路径上有效”。正式主结果采用 3 条路径：

- `data/paths/path_factory_logistics_showcase_theta10_v3.mat`：当前主路径，复用已有完整六链路结果；
- `data/paths/path_closed_loop_long_updown_theta10_v1.mat`：紧凑长坡度上/下坡路径，强调坡度调度；
- `data/paths/path_closed_loop_sharp_turn_transition_theta10_v1.mat`：坡度耦合转向过渡路径，强调转向过渡与坡度切换。

新增自动化入口：

- `src/paths/gen_closed_loop_eval_paths.m`：生成补充闭环路径、路径预览图和 manifest；
- `src/Compare/run_multi_path_closed_loop_benchmark.m`：执行或复用多路径闭环结果，并汇总 6 条链路；
- `src/Compare/run_closed_loop_model_once.m`：新增 `stop_time_override` 支持，并清理默认 ModernTCN 运行时的外部配置残留；
- `src/Compare/compare_tcn_gru_modern_closed_loop_out.m`：支持从 `ref.meta.stall_windows` 读取 stall 真值窗口，供后续 mixed disturbance 路径使用。

输出目录：

- `results/compare/multipath_closed_loop/`

核心结果文件：

- `multipath_closed_loop_summary.csv`
- `multipath_closed_loop_rank.csv`
- `multipath_closed_loop_aggregate.csv`
- `multipath_closed_loop_report.md`

三路径综合排序如下。该排序允许 `LPV-MPC_oracle_theta` 在部分跟踪/控制指标上优于 ModernTCN，因为它使用真实坡度；但综合闭环排名中 ModernTCN 在 3/3 条路径均优于 GRU 和 TCN。

| controller | path_count | overall_rank_mean | overall_rank_worst | ey_rmse_mean | xy_rmse_mean | j_du_mean |
|---|---:|---:|---:|---:|---:|---:|
| ModernTCN | 3 | 1.0000 | 1 | 0.0319 | 0.4889 | 13.313 |
| LPV-MPC_oracle_theta | 3 | 2.0000 | 2 | 0.0347 | 0.3951 | 0.4386 |
| GRU | 3 | 3.3333 | 4 | 0.0483 | 0.9358 | 3.3528 |
| TCN | 3 | 3.6667 | 4 | 0.0489 | 1.0695 | 313.92 |
| LPV-MPC_IMU_theta | 3 | 5.0000 | 5 | 8.8930 | 12.178 | 579.76 |
| LPV-MPC_theta0 | 3 | 6.0000 | 6 | 8.8276 | 12.253 | 644.06 |

逐路径综合排名：

| path | rank 1 | rank 2 | rank 3 | rank 4 |
|---|---|---|---|---|
| `path_factory_logistics_showcase_theta10_v3` | ModernTCN | LPV-MPC_oracle_theta | TCN | GRU |
| `path_closed_loop_long_updown_theta10_v1` | ModernTCN | LPV-MPC_oracle_theta | GRU | TCN |
| `path_closed_loop_sharp_turn_transition_theta10_v1` | ModernTCN | LPV-MPC_oracle_theta | GRU | TCN |

实验边界：

- `mixed disturbance` 路径生成能力已保留为可选项，但未纳入正式三路径主结果；当前闭环 plant 尚未接入时变 `stall_load` 输入，因此 mixed 路径更适合作为后续扩展而非本轮主结论；
- 新增两条补充路径是紧凑高覆盖路径，目的是降低 Simulink 批跑耗时，同时在 38-52 s 内覆盖坡度和转向过渡；
- 后续写论文时可将本节作为“多路径闭环鲁棒性补充实验”：ModernTCN 不只在 factory showcase 主路径上综合最优，在新增坡度主导和坡度耦合转向过渡路径上也保持综合排名第一。

### 12.3 扰动鲁棒性自动化闭环实验

本轮新增了扰动鲁棒性自动化闭环实验，用于在路径扰动、测量噪声和 plant 参数偏差下验证 ModernTCN 相比 GRU/TCN 的闭环稳定优势。

自动化入口：

- `src/Compare/run_closed_loop_robustness_experiment.m`：默认批跑 `path_closed_loop_long_updown_theta10_v1` 和 `path_closed_loop_sharp_turn_transition_theta10_v1` 两条紧凑补充路径，控制器为 `ModernTCN/GRU/TCN`，扰动等级为 `[0 1 2]`，随机种子为 `21`；
- `src/Compare/run_closed_loop_model_once.m`：新增 `params_override`、`ff_rt_override` 和 `robustness_case` 支持，可将扰动参数同时写入 base workspace 和 model workspace，供 Simulink 批处理复现实验。

扰动定义：

- `d=0`：名义工况，复用多路径实验输出并重新按三算法排序；
- `d=1`：中等测量噪声与 plant 参数扰动，`noise_scale=1.0`，`process_scale=0.35`；
- `d=2`：强测量噪声与 plant 参数扰动，`noise_scale=1.5`，`process_scale=0.70`；
- plant 参数扰动包括质量、摩擦、滚阻、空气阻力、前后侧偏刚度和最大加速度的联合偏移。

输出目录：

- `results/compare/robustness_closed_loop/`

核心结果文件：

- `robustness_closed_loop_cases.csv`
- `robustness_closed_loop_summary.csv`
- `robustness_closed_loop_rank.csv`
- `robustness_closed_loop_aggregate.csv`
- `robustness_closed_loop_report.md`

三档扰动聚合结果如下。`case_count=2` 表示每档扰动包含长坡路径和急转过渡路径各一条。

| d | controller | case_count | overall_rank_mean | overall_rank_worst | ey_rmse_mean | xy_rmse_mean | j_du_mean | viol_rate_mean |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | ModernTCN | 2 | 1.000 | 1 | 0.03555 | 0.33155 | 19.67 | 0 |
| 0 | GRU | 2 | 2.000 | 2 | 0.04126 | 0.57156 | 1.514 | 0 |
| 0 | TCN | 2 | 3.000 | 3 | 0.05520 | 0.92733 | 353.04 | 0 |
| 1 | ModernTCN | 2 | 1.000 | 1 | 0.06182 | 1.2880 | 205.78 | 0 |
| 1 | GRU | 2 | 2.500 | 3 | 0.07648 | 1.3874 | 307.31 | 0 |
| 1 | TCN | 2 | 2.500 | 3 | 0.06863 | 1.4244 | 669.08 | 0 |
| 2 | ModernTCN | 2 | 1.000 | 1 | 0.08192 | 1.6587 | 709.76 | 0 |
| 2 | GRU | 2 | 2.000 | 2 | 0.11699 | 1.8842 | 292.18 | 0 |
| 2 | TCN | 2 | 3.000 | 3 | 0.09565 | 1.8597 | 1101.81 | 0 |

关键结论：

- ModernTCN 在 `6/6` 个 path x disturbance case 中按 per-case overall rank 均优于 GRU 和 TCN；
- 随扰动增强，三算法误差都上升，但 ModernTCN 的 `overall_rank_mean` 与 `overall_rank_worst` 始终为 1；
- d=2 强扰动下，ModernTCN 的 `ey_rmse_mean=0.0819`、`xy_rmse_mean=1.6587`，仍优于 GRU 和 TCN 的对应聚合误差；TCN 在部分单项控制指标或局部跟踪指标上可能接近，但综合控制/感知/跟踪排序仍落后。

论文中可将该实验作为“扰动鲁棒性补充实验”：ModernTCN 的优势不依赖单一主路径，也不只存在于名义 plant 参数下；在中等/强扰动闭环下仍保持三算法综合第一。

### 12.4 实时性补充实验

本轮新增了实时性补充实验，用于回答 ModernTCN 是否具备闭环在线部署的计算余量。该实验刻意区分“部署核心计算链路”和“桌面 MATLAB/Simulink 仿真开销”，避免把 extrinsic MATLAB 调用误写成嵌入式实时能力。

自动化入口：

- `src/Compare/benchmark_modern_tcn_onnx_runtime.py`：使用 ONNXRuntime `CPUExecutionProvider`、batch size 1、输入 `[1,128,19]` 测量 ModernTCN 单窗口推理时间；
- `src/Compare/run_realtime_benchmark.m`：回放闭环 `diag.y_raw` 统计 MATLAB 在线 wrapper 调用时间，并从闭环输出的 `diag_solve_time_ms` 汇总 MPC 求解时间。

输出目录：

- `results/compare/realtime_benchmark/`

核心结果文件：

- `realtime_onnx_runtime_summary.csv`
- `realtime_matlab_replay_summary.csv`
- `realtime_mpc_solve_summary.csv`
- `realtime_simulink_wall_summary.csv`
- `realtime_summary.csv`
- `realtime_report.md`

实验配置：

- 控制采样周期：`Ts=10 ms`；
- ONNXRuntime：`sample_count=512`、`warmup=200`、`repeat=5000`、`batch_size=1`；
- MATLAB replay：使用 `ModernTCN_state_classifier('update', ...)` 回放一条闭环 `diag.y_raw`，滑窗 ready 后剔除前 20 次 predict 的首次执行开销；
- MPC solve time：读取两条补充闭环路径 ModernTCN 输出中的 `diag_solve_time_ms`，剔除前 `1 s` warmup。

核心结果：

| metric | mean ms | p50 ms | p95 ms | max ms | p95 margin vs Ts | pass p95 |
|---|---:|---:|---:|---:|---:|---:|
| ONNXRuntime single window | 0.3804 | 0.3659 | 0.4507 | 1.8839 | 9.5493 | yes |
| MPC solve time | 0.0268 | 0.0243 | 0.0416 | 2.1766 | 9.9584 | yes |
| ONNXRuntime + MPC | 0.4072 | 0.3902 | 0.4923 | 4.0605 | 9.5077 | yes |
| MATLAB replay wrapper steady | 17.1346 | 15.2057 | 28.3888 | 42.4473 | -18.3888 | no |
| MATLAB replay + MPC | 17.1613 | 15.2300 | 28.4304 | 44.6239 | -18.4304 | no |
| Simulink desktop wall per step | 29.3024 | 29.3024 | 30.0940 | 30.0940 | -20.0940 | no |

结论和论文边界：

- 可用于论文主张的是部署核心链路：`ONNXRuntime single window + MPC solve time` 的 p95 总周期约 `0.492 ms`，远小于 `Ts=10 ms`，说明 ModernTCN 的推理计算量相对控制周期有充足余量；
- MATLAB/Simulink 当前通过 extrinsic 和 MATLAB dlnetwork wrapper 调用 ONNX，桌面 replay p95 约 `28.4 ms`，不满足 `10 ms` 硬实时；它应作为“桌面仿真/调试开销”报告，不能表述为嵌入式部署实时性；
- 推荐论文表述：ModernTCN 的 ONNX 部署核心推理耗时低，和 MPC 求解时间相加后满足 10 ms 控制周期；当前 MATLAB/Simulink extrinsic 封装主要用于闭环仿真验证，不代表最终部署实现。

## 13. Causal ModernTCN 消融实验

该消融实验的目标是检查 ModernTCN 中 temporal depthwise convolution 从 symmetric/same padding 改为 causal padding 后，对离线测试和闭环部署的影响。实现方式是给 `ModernTCNConfig` 增加 `temporal_padding="same"|"causal"`，默认仍为 `"same"`，因此当前最优 ModernTCN seed 21 不受影响。causal 实现使用 ONNX 友好的 `Conv1d(padding=kernel_size-1) + Slice`，并在 MATLAB 侧使用独立 namespace `modern_tcn_causal_onnx_layers`，避免覆盖默认 ModernTCN 的 generated layers。

causal 多 seed 训练命令使用：

```text
python src/ModernTCN/run_modern_tcn_theta10_v2_multiseed.py ^
  --dataset-file data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat ^
  --run-tag-prefix modern_tcn_causal_theta10_uniform_h0_v2 ^
  --seeds 11 21 42 73 101 ^
  --temporal-padding causal ^
  --epochs 180 --batch-size 256 --lr 1e-3 --weight-decay 1e-4 --patience 35 --min-epochs 50
```

离线综合最优 seed 选择为 `11`。依据：seed 11 在 causal 组中同时具有最好的 `acc_turn_transition=0.7907`、`theta_mae_deg=0.2507`、`theta_abs_le_10_p95_abs_err_deg=0.7995` 和 `stall_recall=0.7009`，比 seed 73 的总转向准确率优势更均衡。

一致性检查：

| 检查 | 文件 | 结论 |
|---|---|---|
| ONNXRuntime | `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11_onnxruntime_consistency.md` | pass=1 |
| MATLAB ONNX | `results/modern_tcn/modern_tcn_causal_theta10_uniform_h0_v2_seed11/modern_tcn_seed11_matlab_consistency.md` | pass=1 |

闭环消融结果来自：

- `results/compare/causal_modern_tcn_closed_loop/path_factory_logistics_showcase_theta10_v3/causal_tcn_gru_modern_closed_loop_summary.csv`
- `results/compare/causal_modern_tcn_closed_loop/path_factory_logistics_showcase_theta10_v3/causal_tcn_gru_modern_closed_loop_rank.csv`
- `results/compare/causal_modern_tcn_closed_loop/path_factory_logistics_showcase_theta10_v3/causal_tcn_gru_modern_closed_loop_report.md`

四算法闭环核心指标：

| controller | ey_rmse | xy_rmse | theta_mae_deg | main_acc_pct | turn_acc_pct | overall_rank |
|---|---:|---:|---:|---:|---:|---:|
| ModernTCN | 0.0246 | 0.8036 | 0.8974 | 94.14 | 81.39 | 1 |
| TCN | 0.0364 | 1.3538 | 0.2590 | 74.71 | 86.09 | 2 |
| GRU | 0.0623 | 1.6641 | 0.3664 | 92.22 | 80.07 | 3 |
| ModernTCN_causal | 23.13 | 27.48 | 1.5950 | 77.10 | 62.22 | 4 |

结论：causal ModernTCN 离线指标很好，但闭环明显失稳，不应替代当前默认 ModernTCN。该实验适合作为论文讨论材料，说明“离线因果化”和“闭环鲁棒性”不是等价问题；闭环控制中的模型输出会改变后续状态和输入窗口，一旦局部误差把系统带入训练分布之外，误差会被控制闭环放大。

使用边界：

- `LPVMPC_AGV_simulink_Modern_TCN.slx` 默认仍加载 `ModernTCN_default_config.m` 中的 same-padding seed 21；
- 只有显式在 base workspace 中传入 `modern_tcn_sim_cfg`，并指定 causal seed 11 的 `run_tag/onnx_file`，才会加载 causal 模型；
- 后续写论文时，causal 结果应放在“消融/讨论”，不应进入主方法闭环性能结论。

## 14. ModernTCN 与 GRU 两算法闭环历史结果

两算法历史结果位于：

- `results/compare/modern_tcn_gru_closed_loop/`

其中 `factory_showcase_theta10_v10` 是一个重要历史展示路径。该结果显示：

| controller | ey_rmse | epsi_rmse | xy_rmse | theta_mae_deg | theta_sched_mae_deg | main_acc_pct | turn_acc_pct |
|---|---:|---:|---:|---:|---:|---:|---:|
| ModernTCN | 0.0275 | 0.1044 | 2.4412 | 0.3789 | 0.4208 | 98.0516 | 95.3002 |
| GRU | 0.0193 | 0.0799 | 1.8724 | 0.5079 | 0.5075 | 95.3247 | 97.5380 |

这组结果可作为历史补充，但不是当前三算法主闭环结论。论文若篇幅有限，应优先采用三算法 `theta10_v3` 结果；如果要解释路径差异或早期验证过程，再引用该目录。

## 15. 论文中的模块角色

建议论文结构和项目模块对应如下。

| 论文章节 | 项目模块 | 应使用的结果/文件 |
|---|---|---|
| 引言 | 项目整体目标 | 说明 AGV 在坡度、转向、堵转等工况下需要更可靠的在线感知辅助 MPC |
| 系统建模 | `src/core`, `src/lpv`, `src/mpc` | AGV 状态方程、LPV 线性化、MPC 框架 |
| 数据集构建 | `data/tcn/*contract.json`, `src/paths`, `src/ModernTCN/build_agv_theta10_uniform_dataset.m` | 统一数据集、19 维特征、三任务标签、run-level split |
| 方法 | `src/ModernTCN` | ModernTCN 结构、多任务输出、ONNX/MATLAB 部署 |
| 基线 | `src/gru`, `src/TCN` | GRU 和 TCN 配置、训练公平性 |
| 离线实验 | 三算法训练报告和 summary CSV | acc_main、acc_turn、acc_turn_transition、theta 误差、recall |
| 闭环实验 | `simulink/*.slx`, `src/Compare` | 三算法闭环 summary/rank/zones，以及 LPV-MPC theta 基线与 oracle 上界 |
| 消融或补充 | causal ModernTCN | 可写入“消融/讨论”：离线接近主模型，但闭环失稳，说明闭环验证不可替代 |
| 消融或补充 | LPV-MPC theta baselines | 可写入“无 AI 感知基线/真实坡度上界”：说明 ModernTCN 相比 theta=0/IMU 基线的数量级闭环收益，并接近 true-theta oracle |
| 讨论 | 三算法对比结论 | 解释离线指标与闭环指标不完全一致的原因 |

## 16. 推荐论文图表

当前最值得进入论文的图表包括：

| 图/表 | 内容 | 数据来源 |
|---|---|---|
| 表 1 | 统一数据集与输入特征说明 | `ModernTCN_dataset_*_contract.json` |
| 表 2 | 三算法配置表 | 三个 `*_default_config.m` 和训练报告 |
| 表 3 | 三算法离线测试指标 | 三算法 summary CSV |
| 表 4 | 三算法闭环总体指标 | `tcn_gru_modern_closed_loop_summary.csv` |
| 表 5 | 三算法闭环综合排序 | `tcn_gru_modern_closed_loop_rank.csv` |
| 表 6 | AI 感知增强 LPV-MPC、无 AI LPV-MPC 和 true-theta oracle 闭环对比 | `results/compare/lpvmpc_theta_baseline/path_factory_logistics_showcase_theta10_v3/tcn_gru_modern_lpvmpc_theta_baseline_summary.csv` |
| 表 7 | 多路径和扰动鲁棒性闭环综合排序 | `results/compare/multipath_closed_loop/multipath_closed_loop_aggregate.csv`、`results/compare/robustness_closed_loop/robustness_closed_loop_aggregate.csv` |
| 表 8 | 实时性补充实验：ONNXRuntime 推理、MATLAB replay、MPC 求解和总周期余量 | `results/compare/realtime_benchmark/realtime_summary.csv` |
| 图 1 | 系统框图：AGV + LPV-MPC + 时序神经网络调度 | 需要新画 |
| 图 2 | ModernTCN 多任务结构图 | 需要新画或由代码抽象绘制 |
| 图 3 | 展示路径轨迹和分区 | `path_factory_logistics_showcase_theta10_v3.mat`、zones CSV |
| 图 4 | 三算法闭环轨迹跟踪对比 | 三个 `*_out.mat` 或 compare 结果 |
| 图 5 | 控制输入/控制增量对比 | 三个 `*_out.mat` |
| 图 6 | theta 预测或调度误差对比 | summary/zones 或 `results/paper/modern_tcn_theta_*` |

已有论文图表目录：

- `results/paper/modern_tcn_theta_scatter/`
- `results/paper/modern_tcn_theta_sweep_plot/`

注意：上述 `results/paper` 目录包含多个历史变体。论文正式使用前应确认采用哪一组图，不要直接混用不同训练 run 的图。

## 17. 历史和非主线模块

以下模块仍存在或有残余记录，但当前不属于论文主线。

| 模块 | 当前状态 | 建议 |
|---|---|---|
| `src/Mamba/` | 历史算法源码保留，`data/mamba/` 已删除 | 不作为当前论文主线，除非后续明确增加 Mamba 对照 |
| `src/bo/` | Bayesian optimization 历史模块 | 可作为历史调参说明，不建议进入主结果 |
| PG-TCN/旧 TCN experiments | 多数结果已清理 | 当前不写入主线；已新增的消融重点是 causal ModernTCN |
| `data/gru/` | 已删除旧 GRU 数据链 | 当前 GRU 使用统一 `data/tcn` 数据集 |
| 旧 ModernTCN v3/v4/v6 结果 | 多数已清理或只保留论文图变体 | 不要作为当前训练结论 |

后续 AI 不应根据历史脚本名推断这些模块仍然可完整复现，因为清理后很多旧数据和结果已删除。

## 18. 继续工作的注意事项

后续写论文、补图或补数据时请遵守以下边界：

- 不要重新选择默认模型，除非用户明确要求重新训练或重新冻结；
- 默认使用三个配置文件中的冻结模型；
- 默认使用 `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`；
- 默认使用三算法闭环目录 `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/`；
- 不要把 causal ModernTCN 作为默认部署模型；若引用 causal 结果，应明确它是消融实验，且闭环表现明显弱于默认 ModernTCN；
- `LPVMPC_AGV_simulink_Modern_TCN.slx` 默认加载 same-padding seed 21；只有显式传入 `modern_tcn_sim_cfg` 才会使用 causal seed 11；
- 若引用 ModernTCN/GRU 两算法历史闭环结果，要明确它是历史或补充结果，不要和三算法主结果混为同一实验；
- 不要把旧 README 中的 V3/V4 数据链当作当前主线；
- 生成论文图时，应把脚本、输入数据和输出目录写回本文档或 `PROJECT_FLOW_MANIFEST.md`，方便后续追踪；
- 如果需要恢复旧实验文件，应从 Git 历史恢复具体路径，而不是重新构造不明来源的数据。

## 19. 当前最短复现实验链

若后续 AI 需要验证当前主线，不建议直接重训。优先执行轻量复核：

1. `init_project`
2. 检查三个默认配置：
   - `ModernTCN_default_config`
   - `GRU_default_config`
   - `TCN_default_config`
3. 加载三个 Simulink 模型：
   - `simulink/LPVMPC_AGV_simulink_Modern_TCN.slx`
   - `simulink/LPVMPC_AGV_simulink_GRU.slx`
   - `simulink/LPVMPC_AGV_simulink_TCN.slx`
4. 运行或读取根目录闭环输出：
   - `ModernTCN_out.mat`
   - `GRU_out.mat`
   - `TCN_out.mat`
5. 用 `src/Compare/compare_tcn_gru_modern_closed_loop_out.m` 生成或更新三算法闭环 summary/rank/zones/report。

用户已完成第 3-4 步的三算法闭环仿真验证，当前文件清理后主流程可用。

## 20. 当前论文主张的推荐表述

可以作为论文初稿核心论点的表述：

> 在统一数据集、统一输入特征、统一 LPV-MPC 闭环平台下，ModernTCN 相比 GRU 和普通 TCN 在多任务工况感知上具有更高的主工况和转向识别可靠性，并在工厂物流展示路径的闭环仿真中取得最优综合排序。虽然 TCN 在部分闭环感知指标上具有局部优势，但其主工况识别不足导致控制峰值、控制增量和约束触碰风险增大；GRU 则在部分坡度调度误差上表现稳定，但整体跟踪误差和转向过渡识别弱于 ModernTCN。因此，ModernTCN 是当前 AGV LPV-MPC 感知增强框架下更适合部署的主模型。

这段表述可以后续压缩成摘要、结论或实验分析段落。
