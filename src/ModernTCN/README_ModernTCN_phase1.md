# ModernTCN 第一阶段说明

## 目标

本目录实现 `ModernTCN-small` 第一阶段实验，固定使用：

- `data/tcn/TCN_dataset_v3_transition_rich.mat`
- MAT 文件内已有 train/val/test run-level split
- MAT 文件内已有归一化后 `X_train/X_val/X_test`
- 19 维输入特征，窗口长度 128
- 三输出：`logits_main`、`logits_turn`、`theta_hat`

第一阶段先跑 `seed42`。只有 seed42 满足以下门槛，才进入 `[42, 73, 101]`：

```text
acc_main >= 0.90
flat_recall >= 0.90
slope_recall >= 0.88
acc_turn_transition >= 0.75
theta_mae_deg <= 0.70
```

## 文件说明

- `modern_tcn_data.py`：读取 MATLAB v7.3 MAT 数据集，不重划分 split，不重拟合 scaler。
- `modern_tcn_model.py`：ONNX 友好的 ModernTCN-small。
- `modern_tcn_metrics.py`：损失、指标、seed42 门槛判定。
- `train_modern_tcn.py`：单 seed 训练与报告。
- `export_modern_tcn_onnx.py`：PyTorch checkpoint 导出 ONNX，并保存 PyTorch 参考输出。
- `check_onnxruntime_consistency.py`：PyTorch vs ONNXRuntime 一致性检查。
- `run_modern_tcn_phase1.py`：第一阶段流水线入口。
- `ModernTCN_check_matlab_onnx.m`：MATLAB 导入 ONNX 后的离线一致性检查。第一版 ONNX 固定 batch=1，脚本会逐窗口推理并拼接结果。
- `ModernTCN_matlab_full_testset_eval.m`：MATLAB 导入 ONNX 后重跑完整 `X_test`，并和 Python summary 做指标级对照。
- `ModernTCN_load_predictor.m`：加载指定 seed 的 ONNX，返回可复用的 MATLAB predictor 结构体。
- `ModernTCN_predict_window.m`：对单个 `[128,19]` 归一化窗口做在线推理，输出标签、概率和 `theta_hat`。
- `ModernTCN_wrapper_smoke_test.m`：验证单窗口 wrapper 是否能复现 full-test 保存的 MATLAB 输出。
- `summarize_modern_tcn_v1.py`：冻结并汇总 ModernTCN-small v1 的 5 seed 结果、baseline 对照和三方一致性状态。
- `generated_layers/`：MATLAB ONNX importer 自动生成的 custom layer package，供 MATLAB 端导入后的 `dlnetwork` 调用。

## 推荐执行顺序

先做数据与模型前向 smoke test：

```powershell
python src/ModernTCN/train_modern_tcn.py --seed 42 --dry-run
```

正式训练 seed42：

```powershell
python src/ModernTCN/run_modern_tcn_phase1.py --seed 42
```

如果缺少 ONNX 依赖：

```powershell
python -m pip install -r src/ModernTCN/requirements.txt
```

如 seed42 过线，可以自动补跑三 seed：

```powershell
python src/ModernTCN/run_modern_tcn_phase1.py --seed 42 --auto-three-seed
```

## MATLAB 离线导入检查

Python 导出 ONNX 后，在 MATLAB 中运行：

```matlab
init_project;
addpath(fullfile(project_root(), 'src', 'ModernTCN'));
result = ModernTCN_check_matlab_onnx( ...
    fullfile(project_root(), 'results', 'modern_tcn', 'transition_rich_v3_seed42', 'modern_tcn_seed42.onnx'), ...
    fullfile(project_root(), 'results', 'modern_tcn', 'transition_rich_v3_seed42', 'modern_tcn_seed42_pytorch_reference.mat'));
```

通过标准：

```text
max_abs_error <= 1e-4
mean_abs_error <= 1e-5
```

MATLAB 检查通过前，不建议接入 Simulink。

## 输出位置

每个 seed 的结果在：

```text
results/modern_tcn/transition_rich_v3_seed<seed>/
```

主要文件：

- `modern_tcn_seed<seed>.pt`
- `modern_tcn_seed<seed>.onnx`
- `modern_tcn_seed<seed>_summary.csv`
- `modern_tcn_seed<seed>_history.csv`
- `modern_tcn_seed<seed>_pytorch_reference.mat`
- `ModernTCN_train_report.md`

## 注意事项

- `--limit-train/--limit-val/--limit-test` 只能用于 smoke test，正式实验必须保持为 0。
- 第一版模型使用 ReLU、BatchNorm1d、Conv1d 和 Linear，避免自定义 CUDA op、复杂 dynamic control flow 和 dynamic axes。
- 第一版 ONNX 固定 batch=1，更接近后续在线单窗口部署；Python/MATLAB 一致性检查脚本会自动逐窗口推理。
- 当前默认使用 PyTorch legacy TorchScript ONNX exporter 和 opset 17。新 exporter 在 `logits_turn` 上可能出现约 `1e-3` 数值差异，不满足本项目一致性门槛。
- MATLAB consistency 脚本会把 importer 生成的 custom layer 固定写入 `src/ModernTCN/generated_layers`。若项目根目录出现 `+modern_tcn_seed*`，它们是早期检查脚本生成的同类 package，可在确认不再使用旧导入对象后删除。
- 导出前脚本会调用 `model.eval()`，dropout 不参与 ONNX 推理。
- 如果 MATLAB 对某个 ONNX 算子报错，优先把错误信息返回，再决定是降 opset 还是替换模型中的具体算子。
- `ModernTCN_predict_window` 的输入必须已经完成与训练数据一致的归一化，且特征顺序必须和 `TCN_dataset_v3_transition_rich.mat` 中的 `X_test` 一致。
- 当前 wrapper 推荐输入形状是 `[128,19] = [time,feature]`；如果输入是 `[19,128]`，需要先转置。

## 冻结 v1 结果

5 seed 训练和三方一致性检查完成后，运行：

```powershell
python src/ModernTCN/summarize_modern_tcn_v1.py
```

输出：

```text
results/modern_tcn/ModernTCN_v1_5seed_per_seed.csv
results/modern_tcn/ModernTCN_v1_5seed_summary.csv
results/modern_tcn/ModernTCN_v1_baseline_comparison.csv
results/modern_tcn/ModernTCN_v1_freeze_manifest.json
results/modern_tcn/ModernTCN_v1_5seed_report.md
```

## MATLAB 完整测试集离线推理

三方一致性检查只覆盖少量参考窗口。进入 Simulink 前，建议在 MATLAB 中重跑完整
`X_test`：

```matlab
init_project;
addpath(fullfile(project_root(), 'src', 'ModernTCN'));

% 快速检查脚本可运行，只跑 seed73 的前 16 个窗口：
ModernTCN_matlab_full_testset_eval(73, 16);

% 正式运行 5 seed 完整测试集：
result = ModernTCN_matlab_full_testset_eval();
```

输出：

```text
results/modern_tcn/matlab_full_testset/ModernTCN_v1_matlab_full_testset_per_seed.csv
results/modern_tcn/matlab_full_testset/ModernTCN_v1_matlab_full_testset_summary.csv
results/modern_tcn/matlab_full_testset/ModernTCN_v1_matlab_full_testset_python_diff.csv
results/modern_tcn/matlab_full_testset/ModernTCN_v1_matlab_full_testset_report.md
```

## MATLAB 单窗口在线 wrapper

完整测试集对齐通过后，先用 seed73 验证在线单窗口接口：

```powershell
matlab -batch "init_project; addpath(fullfile(project_root(),'src','ModernTCN')); result = ModernTCN_wrapper_smoke_test(73); disp(result.pass);"
```

通过标准：

```text
result.pass = 1
max main/turn/theta abs error <= 1e-6
```

输出：

```text
results/modern_tcn/wrapper_smoke/modern_tcn_seed73_wrapper_smoke.csv
results/modern_tcn/wrapper_smoke/modern_tcn_seed73_wrapper_smoke.mat
results/modern_tcn/wrapper_smoke/modern_tcn_seed73_wrapper_smoke_report.md
```

手动调用一个窗口的示例：

```matlab
init_project;
addpath(fullfile(project_root(), 'src', 'ModernTCN'));

S = load(fullfile(project_root(), 'data', 'tcn', 'TCN_dataset_v3_transition_rich.mat'), 'dataset');
predictor = ModernTCN_load_predictor(73);

% 在线接口推荐输入 [time,feature] = [128,19]
X_window = squeeze(single(S.dataset.X_test(1,:,:)));
out = ModernTCN_predict_window(predictor, X_window);

disp(out.main_state);
disp(out.turn_state);
disp(out.theta_hat_deg);
```

标签含义：

```text
main_state: 1=flat, 2=stall, 3=slope
turn_state: -1=right, 0=straight, 1=left
theta_hat_deg: 坡度角预测，单位为度
```
