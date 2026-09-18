# Project Flow Manifest

生成日期：2026-05-14

本文件用于整理当前项目工作区。它不是删除脚本，也不是自动白名单；它是人工核对用的流程清单。后续删除文件前，应先把候选文件移动到隔离目录并重新运行关键流程。

## 扫描范围

当前根目录：`E:\Matlab\Simulink\S-Function_16`

全量扫描显示，项目目录中包含大量环境、缓存和历史实验文件。按清理判断，先区分两类范围：

| 范围 | 文件数 | 说明 |
|---|---:|---|
| 全工作区 | 约 42071 | 包含 `.venv`、`.kilo`、`.git`、`slprj`、Simulink 缓存、历史结果 |
| 项目实质文件 | 2920 | 排除 `.git`、`.venv`、`.kilo`、`slprj`、`__pycache__`、`tools/tmp_slx_*` 后统计 |

项目实质文件约 8.15 GB，主要来自 `data` 和 `results` 下的 `.mat` 训练数据、模型结果和论文图表。

| 顶层目录 | 文件数 | 判断 |
|---|---:|---|
| `results` | 1272 | 训练结果、闭环仿真、论文图表，需分类保留 |
| `data` | 1148 | 训练数据、路径、模型，体积最大，需谨慎 |
| `src` | 350 | 主代码，默认保留 |
| `figures` | 64 | 路径预览和历史图，按论文需要保留 |
| `tools` | 46 | 大量 `tmp_*` 临时审计脚本，可作为清理候选 |
| `docs` | 16 | 历史说明文档，建议归档而非立即删除 |
| `simulink` | 8 | Simulink 主模型，默认保留 |
| 根目录 | 13 | 项目入口、闭环输出、缓存文件 |

主要文件类型：

| 类型 | 文件数 | 说明 |
|---|---:|---|
| `.mat` | 1117 | 训练数据、模型、仿真输出、缓存 |
| `.md` | 619 | 报告、计划、历史记录 |
| `.csv` | 381 | 指标表、汇总表 |
| `.png` | 177 | 图、路径预览 |
| `.m` | 167 | MATLAB 主代码 |
| `.pt` | 84 | PyTorch checkpoint |
| `.py` | 84 | Python 训练/评估脚本 |
| `.json` | 74 | 数据契约、冻结清单 |
| `.onnx` | 23 | ModernTCN 部署模型 |
| `.slx` | 7 | Simulink 模型 |

## 保留级别

| 标记 | 含义 | 删除建议 |
|---|---|---|
| `KEEP_ACTIVE` | 当前主流程、部署或复现必需 | 不删除 |
| `KEEP_RESULT` | 论文可能使用的结果、图、表、冻结模型 | 不删除，论文定稿后再二次筛选 |
| `ARCHIVE_LEGACY` | 旧版本、旧候选、非当前主线，但有追溯价值 | 先移动到 `_archive_unused/`，验证后再决定 |
| `DELETE_CANDIDATE` | 临时脚本、缓存、自动生成中间物 | 先移动到 `_delete_candidates/`，验证后删除 |
| `REVIEW` | 静态扫描不能判断，需人工确认 | 不直接删除 |

## 当前主线判断

当前论文主线建议按下面三组算法组织：

| 算法 | 当前状态 | 当前用途 |
|---|---|---|
| `ModernTCN` | 训练和闭环结果已完成 | 论文主方法、闭环主结果 |
| `GRU` | 训练和闭环结果已完成 | 主要对照基线 |
| `TCN` | 训练已完成，部署配置已冻结 | 补充对照基线，三算法闭环初版已生成 |

三种算法当前冻结/部署使用同一个数据集：

- `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`

| 算法 | 当前最优 seed | 配置名 | 模型结构/关键参数 | 部署模型 |
|---|---:|---|---|---|
| `ModernTCN` | 21 | `modern_tcn_theta10_uniform_h0_v2_seed21` | `seq_len=128`, `input_dim=19`, `channels=64`, `blocks=5`, `kernel_size=31`, `dropout=0.15`, `expansion=2` | `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.onnx` |
| `GRU` | 101 | `inputstats_hidden96_l2` | `hidden_size=96`, `num_layers=2`, `head_pooling=last_mean_inputstats`, `turn_head=mlp/inputstats` | `data/models/GRU_model_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat` |
| `TCN` | 21 | `tcn96_rawtheta_sym` | `num_blocks=6`, `num_filters=96`, `kernel_size=3`, `head_pooling=last_mean_max_inputstats`, `turn_head=mlp/inputstats` | `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat` |

当前 ModernTCN/GRU 冻结闭环清单位于：

- `data/models/CURRENT_FROZEN_CLOSED_LOOP_MODELS.json`

该文件记录了当前 ModernTCN 与 GRU 闭环仿真使用的冻结数据、模型、报告和 Simulink 模型。TCN 的冻结部署配置已写入 `src/TCN/TCN_default_config.m`；三算法闭环对比结果已生成到 `results/compare/tcn_gru_modern_closed_loop/`，若后续要做三算法统一闭环冻结清单，应把 TCN 也补进该 JSON。

## 0. 项目初始化与路径管理

作用：建立 MATLAB 路径、项目根目录定位和结果目录规范。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 初始化入口 | `init_project.m` | `KEEP_ACTIVE` |
| 根目录定位 | `project_root.m` | `KEEP_ACTIVE` |
| 结果目录函数 | `results_dir.m` | `KEEP_ACTIVE` |
| 版本/历史记录 | `change.md` | `ARCHIVE_LEGACY` |
| 功能索引 | `func.md` | `KEEP_RESULT` |
| Git 忽略规则 | `.gitignore` | `KEEP_ACTIVE` |

输出/结果：

- MATLAB 搜索路径；
- 统一的 `data`、`results`、`src`、`simulink` 路径解析。

删除风险：

- 不要删除 `init_project.m`、`project_root.m`、`results_dir.m`。大量脚本通过这些文件定位路径。

## 1. 车辆模型、LPV-MPC 与 Simulink 基础层

作用：提供 AGV 动力学、线性化模型、MPC 控制器和 Simulink 闭环仿真基础。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 主 S-Function | `src/core/agv_model_sfunc.m` | `KEEP_ACTIVE` |
| 训练数据 S-Function | `src/core/agv_model_sfunc_train_data.m` | `KEEP_ACTIVE` |
| 状态方程 | `src/core/state_eq.m` | `KEEP_ACTIVE` |
| 输出方程 | `src/core/output_eq.m` | `KEEP_ACTIVE` |
| 参考状态/输出 | `src/core/state_eq_ref.m`, `src/core/output_eq_ref.m` | `KEEP_ACTIVE` |
| 训练数据参考方程 | `src/core/state_eq_ref_train_data.m`, `src/core/output_eq_ref_train_data.m` | `KEEP_ACTIVE` |
| 参数定义 | `src/core/parameters.m` | `KEEP_ACTIVE` |
| LPV 线性化 | `src/lpv/lin_agv_at_point.m`, `src/lpv/lin_agv_grid.m` | `KEEP_ACTIVE` |
| MPC 创建/更新 | `src/mpc/mpc_setup_single_interp.m`, `src/mpc/mpc_update_from_rho.m`, `src/mpc/Cost_Function.m` | `KEEP_ACTIVE` |
| 植物模型更新 | `src/core/UpdatePlantModel.m`, `src/core/UpdatePlantModel_gru.m` | `KEEP_ACTIVE` |
| 通用预加载 | `src/core/preloadfcn_gru.m` | `KEEP_ACTIVE` |
| ModernTCN 预加载入口 | `src/core/preloadfcn_modern_tcn.m` | `KEEP_ACTIVE` |
| TCN 预加载入口 | `src/core/preloadfcn_tcn.m` | `KEEP_ACTIVE` |
| 旧版预加载 | `src/core/preloadfcn_v1.m`, `src/core/preloadfcn_v2.m` | `ARCHIVE_LEGACY` |

关键输入：

- `data/models/lin_agv_db.mat`
- `data/models/plant_grid_test.mat`
- `data/models/ctrl.mat`
- `data/models/maps_best.mat`

关键 Simulink 模型：

| 文件 | 用途 | 保留级别 |
|---|---|---|
| `simulink/LPVMPC_AGV_simulink_Modern_TCN.slx` | ModernTCN 闭环主模型 | `KEEP_ACTIVE` |
| `simulink/LPVMPC_AGV_simulink_GRU.slx` | GRU 闭环对照模型 | `KEEP_ACTIVE` |
| `simulink/LPVMPC_AGV_simulink_TCN.slx` | TCN 闭环模型，部署配置已冻结但文件当前未跟踪 | `KEEP_ACTIVE` |
| `simulink/LPVMPC_AGV_simulink_ref.slx` | 参考/基线模型 | `KEEP_ACTIVE` |
| `simulink/LPVMPC_AGV_simulink_IMU.slx` | IMU 对照，可选 | `ARCHIVE_LEGACY` |
| `simulink/LPVMPC_AGV_simulink_Mamba.slx` | Mamba 历史对照 | `ARCHIVE_LEGACY` |
| `simulink/GRU_DataGen.slx` | 数据生成模型 | `KEEP_ACTIVE` |
| `simulink/GRU_DataGen.slx.autosave` | Simulink 自动保存 | `DELETE_CANDIDATE` |

删除风险：

- `preloadfcn_gru.m` 同时服务 `GRU`、`ModernTCN`、`TCN` 三种模式，不能按文件名误判为 GRU 专用旧文件。
- `data/models/ctrl.mat`、`lin_agv_db.mat`、`plant_grid_test.mat`、`maps_best.mat` 被 PreLoadFcn 加载，删除前必须完成闭环加载验证。

## 2. 路径生成

作用：生成训练、闭环展示和论文图表所需的参考路径。

| 类型 | 文件 | 主要输出 | 保留级别 |
|---|---|---|---|
| 基础路径接口 | `src/paths/gen_agv_ref_path.m` | `ref` 结构 | `KEEP_ACTIVE` |
| 旧版基础路径接口 | `src/paths/gen_agv_ref_path_v1.m` | 旧路径结构 | `ARCHIVE_LEGACY` |
| TCN 训练路径 | `src/paths/gen_tcn_training_paths.m` | `data/paths/path_train_tcn_*.mat` | `ARCHIVE_LEGACY` |
| TCN v3 过渡增强路径 | `src/paths/gen_tcn_training_paths_v3_transition_rich.m` | `data/paths/path_train_tcn_v3_*.mat` | `KEEP_RESULT` |
| theta10 uniform 路径 | `src/paths/gen_agv_theta10_uniform_paths.m` | `data/paths/agv_theta10_uniform_v*` | `KEEP_ACTIVE` |
| ModernTCN v4 工业路径 | `src/paths/gen_modern_tcn_paths_v4_industrial.m` | `data/paths/path_modern_tcn_v4_*.mat` | `ARCHIVE_LEGACY` |
| 闭环展示路径 | `src/paths/gen_factory_logistics_showcase_path.m` | `path_factory_logistics_showcase_theta10_v*.mat` | `KEEP_RESULT` |
| 多路径闭环补充路径 | `src/paths/gen_closed_loop_eval_paths.m` | `path_closed_loop_long_updown_theta10_v1.mat`, `path_closed_loop_sharp_turn_transition_theta10_v1.mat` | `KEEP_RESULT` |
| ModernTCN 演示路径 | `src/paths/gen_modern_tcn_demo_path.m` | `path_modern_tcn_demo_loop_v*.mat` | `KEEP_RESULT` |
| theta sweep 路径 | `src/paths/gen_modern_tcn_theta_sweep_plot_path.m`, `src/paths/gen_modern_tcn_theta_sweep_short_paths.m` | 论文坡度评估路径 | `KEEP_RESULT` |

关键保留路径：

- `data/paths/path_factory_logistics_showcase_theta10_v10.mat`
- `data/paths/path_modern_tcn_demo_loop_v1.mat`
- `data/paths/path_modern_tcn_demo_loop_v2.mat`
- `data/paths/path_modern_tcn_theta_sweep_multicond_paper_v1.mat`
- `data/paths/path_train_tcn_v3_manifest.csv`
- `data/paths/path_modern_tcn_v4_manifest.csv`

清理建议：

- `data/paths/path_modern_tcn_v4_*.mat` 数量很多，若论文不用 v4 工业全集，可归档。
- `data/paths/tmp_ref_analysis.mat` 属于临时分析，列为 `DELETE_CANDIDATE`。

## 3. 训练数据生成与窗口化数据集

作用：从 Simulink 仿真输出生成连续训练数据，再窗口化成深度模型输入。

### 3.1 TCN/GRU 共享数据链

| 类型 | 文件 | 主要输入 | 主要输出 | 保留级别 |
|---|---|---|---|---|
| 原始数据生成 | `src/TCN/TCN_gen_train_data.m` | `GRU_DataGen.slx`, `path_train_tcn_*.mat` | `data/tcn/TCN_train_data_full.mat` | `ARCHIVE_LEGACY` |
| v3 原始数据生成 | `src/TCN/TCN_gen_train_data_v3_transition_rich.m` | `path_train_tcn_v3_*.mat` | `TCN_train_data_v3_transition_rich_full.mat` | `KEEP_RESULT` |
| 窗口化 | `src/TCN/TCN_prepare_dataset.m` | raw train data | `TCN_dataset_processed.mat` | `KEEP_ACTIVE` |
| v2 窗口化 | `src/TCN/TCN_prepare_dataset_v2_transition_rich.m` | v2 raw data | `TCN_dataset_v2_transition_rich.mat` | `ARCHIVE_LEGACY` |
| v3 窗口化 | `src/TCN/TCN_prepare_dataset_v3_transition_rich.m` | v3 raw data | `TCN_dataset_v3_transition_rich*.mat` | `KEEP_RESULT` |
| 数据诊断 | `src/TCN/TCN_diagnose_dataset.m` | raw/window dataset | `results/tcn/diagnostics` | `KEEP_RESULT` |

关键数据文件：

| 文件 | 用途 | 保留级别 |
|---|---|---|
| `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat` | 当前 ModernTCN/GRU/TCN 统一数据集 | `KEEP_ACTIVE` |
| `data/tcn/ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat` | 当前统一 raw train data | `KEEP_ACTIVE` |
| `data/tcn/ModernTCN_shared_run_split_agv_dualsteer_theta10_uniform_conf_h0_v2.mat` | 当前统一 run-level split | `KEEP_ACTIVE` |
| `data/tcn/ModernTCN_scaler_agv_dualsteer_theta10_uniform_conf_h0_v2.mat` | 当前统一 scaler | `KEEP_ACTIVE` |
| `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2_contract.json` | 当前数据契约 | `KEEP_ACTIVE` |
| `data/tcn/TCN_dataset_v3_transition_rich_clean_turn_aug.mat` | 过渡增强旧主线数据 | `KEEP_RESULT` |
| `data/tcn/TCN_train_data_v3_transition_rich_clean_turn_aug_full.mat` | 过渡增强 raw 数据 | `KEEP_RESULT` |
| `data/tcn/CURRENT_ModernTCN_DATASET.json` | 历史数据链清单 | `KEEP_RESULT` |

可归档数据：

- `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v1*.mat`
- `data/tcn/ModernTCN_dataset_v4_industrial.mat`
- `data/tcn/ModernTCN_train_data_v4_industrial.mat`
- `data/tcn/TCN_dataset_v2_transition_rich.mat`
- `data/tcn/TCN_dataset_processed*.mat`
- `data/tcn/TCN_train_data_smoke*.mat`

这些文件体积较大，但不能直接删除。建议等论文确定不会使用 v1/v4/v2 结果后统一移动到 `_archive_unused/data_tcn_legacy/`。

### 3.2 GRU 历史数据链

| 类型 | 文件 | 主要输出 | 保留级别 |
|---|---|---|---|
| GRU 原始数据生成 | `src/gru/GRU_gen_train_data.m` | `data/gru/GRU_train_data_full.mat` | `ARCHIVE_LEGACY` |
| GRU 数据预处理 | `src/gru/GRU_prepare_dataset.m` | `data/gru/GRU_dataset_processed*.mat` | `KEEP_ACTIVE` |
| Mamba 对照数据准备 | `src/gru/run_GRU_prepare_dataset_mamba_compare.m` | `data/gru/GRU_dataset_processed.mat` | `ARCHIVE_LEGACY` |
| strict/stall 旧版本 | `src/gru/run_GRU_prepare_dataset_mamba_*` | 旧 GRU 数据 | `ARCHIVE_LEGACY` |

当前 GRU 主线实际使用 `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`，不是旧 `data/gru` 数据。因此 `data/gru` 下大体可归档，但若要复现早期 Mamba/GRU 对照，则先保留。

## 4. ModernTCN 训练、导出与部署

作用：训练 ModernTCN-small，导出 ONNX，并用于 Simulink 闭环。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 模型定义 | `src/ModernTCN/modern_tcn_model.py` | `KEEP_ACTIVE` |
| 数据加载 | `src/ModernTCN/modern_tcn_data.py` | `KEEP_ACTIVE` |
| 指标/损失 | `src/ModernTCN/modern_tcn_metrics.py` | `KEEP_ACTIVE` |
| 单 seed 训练 | `src/ModernTCN/train_modern_tcn.py` | `KEEP_ACTIVE` |
| 多 seed 训练 | `src/ModernTCN/run_modern_tcn_theta10_v2_multiseed.py` | `KEEP_ACTIVE` |
| ONNX 导出 | `src/ModernTCN/export_modern_tcn_onnx.py` | `KEEP_ACTIVE` |
| ONNXRuntime 检查 | `src/ModernTCN/check_onnxruntime_consistency.py` | `KEEP_ACTIVE` |
| MATLAB ONNX 检查 | `src/ModernTCN/ModernTCN_check_matlab_onnx.m` | `KEEP_ACTIVE` |
| MATLAB 加载器 | `src/ModernTCN/ModernTCN_load_predictor.m` | `KEEP_ACTIVE` |
| 在线推理 | `src/ModernTCN/ModernTCN_predict_window.m`, `ModernTCN_online_step.m`, `ModernTCN_state_classifier.m` | `KEEP_ACTIVE` |
| Simulink 包装 | `src/ModernTCN/ModernTCN_State_Classifier_sim.m` | `KEEP_ACTIVE` |
| 默认冻结配置 | `src/ModernTCN/ModernTCN_default_config.m` | `KEEP_ACTIVE` |
| 闭环/输出分析 | `src/ModernTCN/ModernTCN_analyze_closed_loop_out.m`, `ModernTCN_replay_closed_loop_yraw.m` | `KEEP_RESULT` |
| 论文坡度图 | `src/ModernTCN/plot_modern_tcn_theta_scatter.m`, `eval_modern_tcn_theta_sweep_plot.m` | `KEEP_RESULT` |

当前冻结 ModernTCN 结果：

| 文件 | 用途 | 保留级别 |
|---|---|---|
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.pt` | PyTorch checkpoint | `KEEP_ACTIVE` |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.onnx` | Simulink 部署模型 | `KEEP_ACTIVE` |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21_pytorch_reference.mat` | 导出一致性参考 | `KEEP_ACTIVE` |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21_summary.csv` | 训练指标 | `KEEP_RESULT` |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21_history.csv` | 训练曲线数据 | `KEEP_RESULT` |
| `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/ModernTCN_train_report.md` | 训练报告 | `KEEP_RESULT` |

论文图表结果：

- `results/paper/modern_tcn_theta_scatter/`
- `results/paper/modern_tcn_theta_sweep_plot/`

清理建议：

- `src/ModernTCN/__pycache__/` 可删除。
- `src/ModernTCN/generated_layers/` 可能与 MATLAB ONNX 导入相关，先标为 `REVIEW`，不要直接删。
- 旧 run 目录如 `transition_rich_v3_*`、`modern_tcn_v6_*`、`theta_calib_*` 应归档，不建议在论文初稿前删除。

## 5. GRU 训练、对照与部署

作用：作为当前主要对照基线，训练多任务 GRU 并用于闭环对比。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 主训练函数 | `src/gru/GRU_train.m` | `KEEP_ACTIVE` |
| 当前多 seed 入口 | `src/gru/run_GRU_train_theta10_v2_multi_seed.m` | `KEEP_ACTIVE` |
| 数据契约检查 | `src/gru/GRU_check_v4_dataset_contract.m` | `KEEP_ACTIVE` |
| 默认部署配置 | `src/gru/GRU_default_config.m` | `KEEP_ACTIVE` |
| 推理函数 | `src/gru/GRU_infer.m` | `KEEP_ACTIVE` |
| 在线状态分类器 | `src/gru/GRU_state_classifier.m` | `KEEP_ACTIVE` |
| Simulink 包装 | `src/gru/GRU_State_Classifier_gru_sim.m` | `KEEP_ACTIVE` |
| MATLAB 加载 | `src/gru/GRU_load_default_to_base.m` | `KEEP_ACTIVE` |
| ModernTCN 对照表 | `src/gru/GRU_ModernTCN_v4_compare.m` | `KEEP_RESULT` |
| 旧训练函数 | `src/gru/GRU_train_legacy_v17.m` | `ARCHIVE_LEGACY` |

当前冻结 GRU 结果：

| 文件 | 用途 | 保留级别 |
|---|---|---|
| `data/models/GRU_model_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat` | 当前 GRU 闭环模型 | `KEEP_ACTIVE` |
| `data/models/GRU_meta_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat` | 当前 GRU 元数据 | `KEEP_ACTIVE` |
| `results/gru/train_logs_theta10_uniform_h0_v2/inputstats_hidden96_l2_seed101/GRU_train_report.md` | 当前 GRU 训练报告 | `KEEP_RESULT` |
| `results/gru/train_logs_theta10_uniform_h0_v2/GRU_theta10_v2_multi_seed_summary.csv` | 多 seed 汇总 | `KEEP_RESULT` |
| `results/gru/train_logs_theta10_uniform_h0_v2/GRU_theta10_v2_group_summary.csv` | 多 seed 分组汇总 | `KEEP_RESULT` |

可归档对象：

- `data/models/GRU_model_gru_fair_v1_*`
- `data/models/GRU_model_transition_rich_v2_*`
- `data/models/GRU_model_transition_rich_v3_*`
- `results/gru/train_logs_v4_industrial*`
- `results/gru/train_logs_mamba_control*`

这些旧结果可以支撑历史对照或审稿补充，但不是当前主线。建议归档，不建议直接删除。

## 6. TCN 训练、对照与部署

作用：训练已结束的 TCN 对照算法，当前最优部署 seed 为 21，后续用于补充论文中的三算法对比。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 主训练函数 | `src/TCN/TCN_train.m` | `KEEP_ACTIVE` |
| 当前多 seed 入口 | `src/TCN/run_TCN_train_theta10_v2_multi_seed.m` | `KEEP_ACTIVE` |
| 推荐配置 | `src/TCN/TCN_recommended_cfg.m` | `KEEP_ACTIVE` |
| 默认部署配置 | `src/TCN/TCN_default_config.m` | `KEEP_ACTIVE` |
| MATLAB 加载器 | `src/TCN/TCN_load_predictor.m` | `KEEP_ACTIVE` |
| 在线推理 | `src/TCN/TCN_predict_window.m`, `TCN_state_classifier.m` | `KEEP_ACTIVE` |
| Simulink 包装 | `src/TCN/TCN_State_Classifier_sim.m` | `KEEP_ACTIVE` |
| Simulink 配置脚本 | `src/TCN/configure_tcn_simulink_model.m` | `KEEP_ACTIVE` |
| TCN/GRU 公平对照 | `src/TCN/run_TCN_GRU_transition_rich_v*.m`, `run_TCN_GRU_main_confirm_seeds.m` | `ARCHIVE_LEGACY` |
| 自动扫描/消融 | `src/TCN/TCN_auto_experiment_pipeline.m`, `TCN_auto_train_sweep.m`, `TCN_pg_auto_experiment_pipeline.m` | `ARCHIVE_LEGACY` |
| 消融汇总 | `src/TCN/TCN_write_ablation_summary.m` | `KEEP_RESULT` |

当前 TCN 结果：

| 文件 | 用途 | 保留级别 |
|---|---|---|
| `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat` | 当前冻结 TCN 部署模型 | `KEEP_ACTIVE` |
| `data/models/TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat` | 当前冻结 TCN 元数据 | `KEEP_ACTIVE` |
| `results/tcn/train_logs_theta10_uniform_h0_v2/tcn96_rawtheta_sym_seed21/TCN_train_report.md` | 当前冻结 TCN 训练报告 | `KEEP_RESULT` |
| `results/tcn/train_logs_theta10_uniform_h0_v2/TCN_theta10_v2_multi_seed_summary.csv` | 多 seed 汇总 | `KEEP_RESULT` |
| `results/tcn/train_logs_theta10_uniform_h0_v2/TCN_theta10_v2_group_summary.csv` | 多 seed 分组汇总 | `KEEP_RESULT` |
| `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed*.mat` | 其它 seed 候选模型，用于复核/论文补充 | `KEEP_RESULT` |
| `data/models/TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed*.mat` | 其它 seed 候选元数据 | `KEEP_RESULT` |
| `results/tcn/train_logs_theta10_uniform_h0_v2/tcn96_rawtheta_sym_seed*/TCN_train_report.md` | 其它 seed 单次训练报告 | `KEEP_RESULT` |

TCN seed 21 的选择依据：

- `TCN_default_config.m` 已冻结到 `seed=21`、`case_name=tcn96_rawtheta_sym`。
- 多 seed 汇总表中，seed 21 具有最低 `theta_mae_deg=0.2902`、最低 `theta_abs_le_10_p95_abs_err_deg=0.8473`、最高 `acc_main=0.7479` 和最高 `slope_recall=0.8108`。
- seed 101 的 `acc_turn=0.7849` 略高于 seed 21 的 `0.7771`，但 theta 误差、主工况准确率和 slope recall 均弱于 seed 21，因此当前冻结为 seed 21 是合理的整体最优选择。

可归档对象：

- `data/models/TCN_model_neg*`
- `data/models/TCN_model_pg_*`
- `data/models/TCN_model_transition_rich_v2_*`
- `data/models/TCN_model_transition_rich_v3_*`
- `results/tcn/sweeps/`
- `results/tcn/experiments/transition_rich_v2_*`
- `results/tcn/experiments/transition_rich_v3_*`
- `results/tcn/smoke_*`

注意：

- TCN 训练冻结已完成，三算法闭环初版结果也已生成；后续需要决定论文采用的闭环路径和指标表格式。

## 7. 闭环仿真与对比分析

作用：运行 Simulink 模型，保存 `logsout`，并计算闭环指标。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 单模型闭环运行 | `src/Compare/run_closed_loop_model_once.m` | `KEEP_ACTIVE` |
| ModernTCN/GRU 闭环对比 | `src/Compare/compare_modern_tcn_gru_closed_loop_out.m` | `KEEP_ACTIVE` |
| ModernTCN/GRU/TCN 三算法闭环对比 | `src/Compare/compare_tcn_gru_modern_closed_loop_out.m` | `KEEP_ACTIVE` |
| 多路径闭环补充实验 | `src/Compare/run_multi_path_closed_loop_benchmark.m` | `KEEP_ACTIVE` |
| 扰动鲁棒性闭环补充实验 | `src/Compare/run_closed_loop_robustness_experiment.m` | `KEEP_ACTIVE` |
| ModernTCN ONNXRuntime 实时性测试 | `src/Compare/benchmark_modern_tcn_onnx_runtime.py` | `KEEP_ACTIVE` |
| 实时性汇总实验 | `src/Compare/run_realtime_benchmark.m` | `KEEP_ACTIVE` |
| 批量闭环对比旧链路 | `src/Compare/run_compare_mamba2_gru_imu_batch.m` | `ARCHIVE_LEGACY` |
| 统计分析旧链路 | `src/Compare/analyze_compare_mamba2_gru_imu_stats.m` | `ARCHIVE_LEGACY` |
| 扰动有效性检查 | `src/Compare/check_compare_disturbance_effectiveness.m` | `ARCHIVE_LEGACY` |
| 一致性审计报告 | `src/Compare/公平性与链路一致性审计报告_V1.md` | `KEEP_RESULT` |
| 公平对比协议 | `src/Compare/IEEE_AGV_Fair_Comparison_Protocol.md` | `KEEP_RESULT` |

当前闭环结果：

| 文件/目录 | 用途 | 保留级别 |
|---|---|---|
| `results/compare/modern_tcn_gru_closed_loop/` | ModernTCN vs GRU 闭环指标、分区表和报告 | `KEEP_RESULT` |
| `results/compare/tcn_gru_modern_closed_loop/path_factory_logistics_showcase_theta10_v3/` | ModernTCN/GRU/TCN 三算法闭环指标、排序表和报告 | `KEEP_RESULT` |
| `results/compare/multipath_closed_loop/` | 多路径六链路闭环补充实验，ModernTCN 在 3/3 路径综合排名第一 | `KEEP_RESULT` |
| `results/compare/robustness_closed_loop/` | 两条补充路径三档扰动鲁棒性闭环实验，ModernTCN 在 6/6 个 path x disturbance case 综合排名第一 | `KEEP_RESULT` |
| `results/compare/realtime_benchmark/` | 实时性补充实验，ONNXRuntime+MPC p95 总周期约 0.492 ms，小于 Ts=10 ms | `KEEP_RESULT` |
| `ModernTCN_out.mat` | 根目录闭环输出，人工运行结果 | `REVIEW` |
| `GRU_out.mat` | 根目录闭环输出，人工运行结果 | `REVIEW` |
| `TCN_out.mat` | 根目录 TCN 闭环输出，人工运行结果 | `REVIEW` |
| `results/closed_loop/` | 其他闭环结果 | `REVIEW` |
| `results/simulink/` | Simulink 结果缓存 | `REVIEW` |

清理建议：

- 优先保留 `results/compare/modern_tcn_gru_closed_loop/` 和 `results/compare/tcn_gru_modern_closed_loop/`。
- 根目录 `ModernTCN_out.mat`、`GRU_out.mat`、`TCN_out.mat` 若已被复制到 `results/compare/...` 且能复现实验，可归档。

## 8. 论文图表与数据表

作用：论文初稿中会直接引用的图、表、报告和中间数据。

| 类型 | 文件/目录 | 保留级别 |
|---|---|---|
| 论文结果目录 | `results/paper/` | `KEEP_RESULT` |
| ModernTCN theta scatter | `results/paper/modern_tcn_theta_scatter/` | `KEEP_RESULT` |
| ModernTCN theta sweep | `results/paper/modern_tcn_theta_sweep_plot/` | `KEEP_RESULT` |
| 路径预览图 | `figures/paths/` | `KEEP_RESULT` |
| 旧总图 | `figures/bo_history_curve.png`, `figures/scene_performance.png` | `REVIEW` |

建议论文核心图表清单：

- 训练/测试指标表：ModernTCN、GRU、TCN；
- 闭环总体指标表；
- 闭环分区指标表；
- 预测误差/坡度回归散点图；
- theta sweep 或多工况泛化图；
- 代表性闭环轨迹图；
- 控制输入与约束触碰图；
- 模型结构示意图。

清理建议：

- `results/papers/` 与 `results/paper/` 名称相近，需人工确认是否重复。
- 论文图表定稿前，不建议删除 `results/paper/` 下的旧变体目录；可先移动旧变体到 `results/paper/_archive_candidates/`。

## 9. 测试与验证

作用：清理前后用于验证关键流程没有被破坏。

| 类型 | 文件 | 保留级别 |
|---|---|---|
| 闭环测试 | `src/tests/test_simulink_closed_loop.m` | `KEEP_ACTIVE` |
| GRU 工作流测试 | `src/tests/test_GRU_workflow.m` | `KEEP_ACTIVE` |
| GRU 性能/延迟测试 | `src/tests/test_gru_performance.m`, `test_gru_latency.m`, `test_gru_filter_constants.m` | `KEEP_RESULT` |
| AGV 开环测试 | `src/tests/test_agv_open_loop.m` | `KEEP_ACTIVE` |
| 工业开环条目测试 | `src/tests/test_industrial_open_loop_items.m` | `KEEP_RESULT` |
| 角速度跟踪分析 | `src/tests/omega_tracking_analysis.md` | `KEEP_RESULT` |

清理验证建议：

1. `init_project`
2. `load_system('simulink/LPVMPC_AGV_simulink_Modern_TCN.slx')`
3. `load_system('simulink/LPVMPC_AGV_simulink_GRU.slx')`
4. `load_system('simulink/LPVMPC_AGV_simulink_TCN.slx')`
5. ModernTCN 在线分类器 smoke test
6. GRU 在线分类器 smoke test
7. TCN 在线分类器 smoke test
8. ModernTCN/GRU 闭环短仿真
9. `compare_modern_tcn_gru_closed_loop_out(...)`

## 10. 明确清理候选

这些文件/目录更接近临时物或缓存。仍建议先移动到 `_delete_candidates/`，不要直接删除。

### 高优先级 DELETE_CANDIDATE

| 文件/目录 | 原因 |
|---|---|
| `tools/tmp_*` | 临时审计脚本、日志、CSV、ZIP |
| `tools/tmp_slx_*` | 解包 SLX 的中间 XML/资源 |
| `**/__pycache__/` | Python 字节码缓存 |
| `slprj/` | Simulink 自动生成缓存 |
| `src/**/slprj/` | Simulink 自动生成缓存 |
| `*.slxc` | Simulink cache，可重建 |
| `simulink/GRU_DataGen.slx.autosave` | 自动保存副本 |
| `data/paths/tmp_ref_analysis.mat` | 临时路径分析 |

### REVIEW 后再删

| 文件/目录 | 原因 |
|---|---|
| `.venv/` | 体积大，但包含 Python 环境；若有 `requirements.txt` 且环境可重建，可移出项目根目录 |
| `.kilo/` | IDE/工具状态目录，可能与当前工作记录有关 |
| `.cursor/` | IDE 规则目录，可能有项目规则 |
| `src/Mamba/` | 历史算法链路；若论文不再使用 Mamba，可整体归档 |
| `data/mamba/` | Mamba 训练数据，体积大，归档优先 |
| `data/gru/` | 当前主线不依赖，但早期 GRU/Mamba 对照依赖 |
| `results/compare/mamba2_gru_imu/` | 旧闭环对照结果 |
| `src/ModernTCN/generated_layers/` | MATLAB ONNX 兼容层，先验证后判断 |

### 可归档的旧实验族

| 文件/目录模式 | 建议 |
|---|---|
| `results/modern_tcn/transition_rich_v3_*` | 旧 ModernTCN 训练族，归档 |
| `results/modern_tcn/modern_tcn_v4_*` | 旧 v4 训练族，归档 |
| `results/modern_tcn/modern_tcn_v6_*` | 旧 v6/校准族，论文不用则归档 |
| `results/tcn/sweeps/` | TCN 参数扫描，归档 |
| `results/tcn/experiments/main_recovery_grid_v2/` | 旧 TCN 修复网格，归档 |
| `results/tcn/experiments/pg_*` | PG-TCN 消融/旧实验，若论文不用则归档 |
| `results/gru/train_logs_v4_industrial*` | 旧 GRU 训练族，归档 |
| `data/models/TCN_model_neg*` | 旧 TCN 参数扫描模型，归档 |
| `data/models/GRU_model_gru_fair_v1_*` | 旧 GRU 公平对照模型，归档 |

## 11. 当前 Git 工作区风险

扫描时 Git 工作区显示以下未提交/未跟踪项：

- `M src/core/preloadfcn_gru.m`
- `m src/Mamba/model/mamba`
- `?? results/tcn/train_logs_theta10_uniform_h0_v2/tcn96_rawtheta_sym_seed21/`
- `?? simulink/LPVMPC_AGV_simulink_TCN.slx`
- `?? src/TCN/TCN_State_Classifier_sim.m`
- `?? src/TCN/TCN_default_config.m`
- `?? src/TCN/TCN_load_predictor.m`
- `?? src/TCN/TCN_predict_window.m`
- `?? src/TCN/TCN_state_classifier.m`
- `?? src/TCN/configure_tcn_simulink_model.m`
- `?? src/core/preloadfcn_tcn.m`

这些文件很可能属于当前 TCN 闭环接入工作。清理时不能把未跟踪文件当成无用文件。

## 12. 推荐清理流程

第一轮只做隔离，不做永久删除：

1. 创建 `_delete_candidates/` 和 `_archive_unused/`。
2. 将 `tools/tmp_*`、`tools/tmp_slx_*`、`__pycache__`、`slprj`、`*.slxc` 移到 `_delete_candidates/`。
3. 重新运行初始化和模型加载验证。
4. 将旧实验族移动到 `_archive_unused/`，保留目录结构。
5. 重新运行 ModernTCN/GRU/TCN 短闭环和对比脚本。
6. 若三算法闭环结果更新，补充新的统一闭环结果目录和指标表。
7. 论文图表确定后，再精简 `results/paper/` 的旧变体。

建议先不要动：

- `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`
- `data/tcn/ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`
- `data/models/CURRENT_FROZEN_CLOSED_LOOP_MODELS.json`
- `data/models/GRU_model_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat`
- `data/models/GRU_meta_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat`
- `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat`
- `data/models/TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat`
- `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/`
- `results/gru/train_logs_theta10_uniform_h0_v2/`
- `results/tcn/train_logs_theta10_uniform_h0_v2/`
- `results/compare/modern_tcn_gru_closed_loop/`
- `results/compare/tcn_gru_modern_closed_loop/`
- `results/paper/`
- `simulink/*.slx`
- `src/core/`
- `src/ModernTCN/`
- `src/gru/`
- `src/TCN/`

## 13. 下一次需要补充的内容

论文整理阶段还需要更新：

- ModernTCN/GRU/TCN 三算法统一离线指标表；
- ModernTCN/GRU/TCN 三算法统一闭环指标表和论文采用路径；
- 三算法论文图表生成脚本和输出目录；
- 是否保留 PG-TCN、Mamba、IMU 作为消融或扩展对照。

## 14. 清理执行记录

执行时间：2026-05-14。

本次已删除训练和闭环过程中产生的高置信度冗余文件，范围包括旧数据集、旧模型检查点、旧训练结果、旧闭环结果、临时脚本输出、MATLAB/Simulink 缓存和 Python 缓存。删除前按绝对路径确认均位于当前项目根目录内，未处理 `.git/`、`.venv/`、`.kilo/`、`.cursor/` 等环境或 IDE 目录。

本次删除规模：

- 计划并执行删除：1156 个已存在项目；
- 释放空间约：6831.26 MB；
- 清理后当前项目实用文件规模约：888 个文件，1093.64 MB（不计 `.git/`、`.venv/`、`.kilo/`、`slprj/`、`__pycache__/` 和 `tools/tmp_slx_*` 等环境/缓存目录）。

已确认仍然存在的主线保留项：

- `data/tcn/ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`
- `data/tcn/ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v2.mat`
- `data/models/CURRENT_FROZEN_CLOSED_LOOP_MODELS.json`
- `data/models/GRU_model_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat`
- `data/models/GRU_meta_gru_theta10_uniform_h0_v2_inputstats_hidden96_l2_seed101.mat`
- `data/models/TCN_model_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat`
- `data/models/TCN_meta_tcn_theta10_uniform_h0_v2_tcn96_rawtheta_sym_seed21.mat`
- `results/modern_tcn/modern_tcn_theta10_uniform_h0_v2_seed21/modern_tcn_seed21.onnx`
- `results/gru/train_logs_theta10_uniform_h0_v2/inputstats_hidden96_l2_seed101/GRU_train_report.md`
- `results/tcn/train_logs_theta10_uniform_h0_v2/tcn96_rawtheta_sym_seed21/TCN_train_report.md`
- `results/compare/modern_tcn_gru_closed_loop/`
- `results/compare/tcn_gru_modern_closed_loop/`
- `simulink/LPVMPC_AGV_simulink_Modern_TCN.slx`
- `simulink/LPVMPC_AGV_simulink_GRU.slx`
- `simulink/LPVMPC_AGV_simulink_TCN.slx`
- `src/ModernTCN/ModernTCN_default_config.m`
- `src/gru/GRU_default_config.m`
- `src/TCN/TCN_default_config.m`

本次刻意未删除但后续可继续复核的内容：

- `src/Mamba/`：历史算法源码仍保留，但 `data/mamba/` 已删除；
- 根目录 `ModernTCN_out.mat`、`GRU_out.mat`、`TCN_out.mat`：当前可作为闭环仿真输出快照保留；
- `results/paper/`：论文图表输出目录在论文图表最终确定前建议保留；
- `docs/`、`figures/`：文档和图表素材目录建议等论文结构明确后再筛选；
- `.venv/`、`.kilo/`、`.cursor/`：环境、插件或 IDE 目录，不属于算法结果清理范围。

Git 工作区中会出现大量 `D` 状态文件，这是本次删除产生的预期结果。若后续确认某个历史实验还需要用于论文图表或对照，可从 Git 历史恢复对应文件。
