# A2 实验报告

## 当前状态

正式基准尚未产生有效样本。初次准备阶段检测到 VS Code 为项目 `.venv` 启动的 Jedi Python 进程，独占性门禁按协议阻止了正式计时。清除该进程后的首次正式启动通过预检，但监控器把 MATLAB 启动器的计算子进程误判为另一个 MATLAB，因而在写入正式样本前中止；该次尝试不构成正式结果。

监控器现已改为递归放行启动器的完整子进程树，异常状态字段使用显式属性写入，并按整个 MATLAB 进程树采样内存。重新运行时会归档未完成尝试；只有 case JSON 为 `COMPLETE`、环境哈希一致且原始 CSV 恰有 10,000 行的 case 才会跳过。

第二次正式入口调用已通过独占预检，但在 MATLAB 启动前因未完成尝试的归档目标超过 Windows 传统路径长度限制而停止。该问题同样没有产生正式样本；归档目录现使用短 token，完整 case ID 和源文件列表保存于目录内的 `attempt_metadata.json`。

第三次正式入口调用通过独占预检并启动 MATLAB，但 Windows PowerShell 5.1 为新生成的 `protocol_snapshot.json` 写入 UTF-8 BOM，MATLAB `jsondecode(fileread(...))` 在初始化阶段拒绝该首字符。该次运行在正式循环前失败，仍为 0 个正式样本。写端现对 MATLAB 消费的配置使用无 BOM UTF-8，读端也以二进制方式识别并移除 BOM；随后主方法 case 的 2 次预热、5 次调用 smoke 以退出码 0 通过。smoke 延迟不构成正式结果。

第四次入口调用完成了 `core_inference__modern_tcn_delta_bank_124` 的 500 次预热和 10,000 次正式计时。MATLAB 启动器未向 Windows PowerShell 暴露退出码，旧判断因此在有效输出写完后停止；运行器现仅在 `COMPLETE` case JSON、10,000 行原始 CSV、环境哈希全部一致时接受未知启动器退出码。该 case 已独立复核为 10,000 个有限样本，独占监控 110 次均为真：p50 10.1598 ms、p95 12.1382 ms、p99 13.0987 ms、max 18.2865 ms，超过 10 ms 比例 0.603。该真实结果未通过 p95/p99 10 ms 判据，协议未作调整。当前第一阶段进度为 1/11，尚不能签发核心阶段完成收据。

## 可复用输入

四个 seed42 权威模型直接来自 A1 `model_registry.csv`；ModernTCN 运行时使用已有 ONNX 部署派生物并登记其父 checkpoint SHA256。数据集、六路径、LPV 数据库、maps 和控制器均来自 A0 冻结配置。完整路径和重新计算的 SHA256 见 `01_inventory/input_artifact_registry.csv`。

## 缺失结果

第一阶段 9 个 A5 runtime cells 和 2 个补充单元均缺失。Fusion 尚未冻结，第二阶段 3 个 A5 cells 为 `NOT_ELIGIBLE`。

正式运行完成后，本报告由汇总脚本补充环境、参数量、文件大小、峰值内存、逐 case 延迟统计和 10 ms 判定；不符合预期的结果不会被替换或删除。

## 非正式 smoke 验证

第一阶段 11 个接口均已使用单线程 MATLAB 通过小规模 smoke：每个 case 仅 2 次预热、5 次调用，用于验证数据读取、四模型推理、在线 wrapper、delta-bank、冻结 MPC 和真实全周期调用链。结果位于 `04_phase1/logs/smoke_summary.csv`，明确标记为 `SMOKE_ONLY_NOT_FORMAL`，不得用于论文性能表或 10 ms 结论。

smoke 中已观察到部分组件明显超过 10 ms，尤其是冻结 MPC 和包含 MPC 的全周期。该现象不会触发更换控制器、门限、路径、seed 或后端；必须由独占环境下的正式 10,000 次结果确认。

# Phase 1 formal results

Status: PARTIAL_CORE_COMPLETE_WAITING_FOR_FINAL_FUSION.

Completed 9 A5 runtime cells and 2 supplemental cells; each cell used 500 warmups and 10,000 formal repetitions. Final Fusion is not frozen, so phase 2 was not run.

See `06_summary/runtime_summary.csv`, `06_summary/supplemental_runtime_summary.csv`, `06_summary/raw_timing_validation.csv`, and `06_summary/decision.json` for the measured values.
