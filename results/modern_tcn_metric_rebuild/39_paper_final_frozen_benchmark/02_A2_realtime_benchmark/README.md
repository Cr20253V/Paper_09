# A2 当前最终方法轻量化与 10 ms 实时基准

本目录是 Node39 A2 的唯一写入目录。A0、A1、A3、Node38、已有模型/结果和 `paper_v3.tex` 均只读引用。

## 正式协议

- 后端：MATLAB R2024b、CPU、单线程、batch=1，GPU 不参与推理。
- 每个 case：500 次预热，10,000 次正式重复；模型加载和磁盘 I/O 不计入延迟。
- 原始逐次延迟全部保存，汇总报告 p50/p95/p99/max 和严格 `latency_ms > 10` 的比例。
- 第一阶段包含 A5 需要的 9 个 runtime cells，以及两个补充单元：归一化+delta-bank、无 Fusion 的估计+MPC 全周期。
- 第二阶段只有在 Node38 最终 Fusion 模型和 wrapper 有冻结路径、SHA256、receipt 后才能执行。

## 运行方法

在项目根目录的 PowerShell 中执行：

```powershell
& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\02_tools\prepare_a2.ps1'
& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\02_tools\invoke_a2.ps1'
```

`invoke_a2.ps1` 不会结束任何用户进程。若检测到其他 MATLAB/Simulink、项目 Python、训练或 Node38/Fusion 进程，它会写入 `BLOCKED_EXCLUSIVITY` 并在正式计时前退出。

## 结果口径

- `core_inference`：预加载并预处理好的固定窗口到网络推理和输出解码。
- `end_to_end_update`：单帧 `y_raw` 到特征提取、滑窗、归一化、可选 delta-bank、网络推理和在线输出处理。
- `mpc_solve`：冻结控制器的 `mpcmoveAdaptive` 调用；LPV 更新和对象构造在计时外准备。
- 补充 `full_cycle__slope_estimation_mpc`：ModernTCN-delta_bank_124 更新、LPV 更新、对象构造和 MPC 求解位于同一个计时区间，不以分位数相加代替。

机器或软件环境发生变化时不得把结果混入同一 `environment_sha256`。性能不符合 10 ms 时保留真实结果，不改变路径、seed、checkpoint 或阈值。

