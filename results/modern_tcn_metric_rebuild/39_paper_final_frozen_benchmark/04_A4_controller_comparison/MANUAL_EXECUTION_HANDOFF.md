# A4 长耗时手动执行交接

状态：`NOT_REQUIRED`

当前兼容性审计确认 138/138 个正式主分析 case 完整，因此本轮禁止重新训练、重新导出 checkpoint 或补跑仿真，直接复用现有结果。

若未来重新审计发现缺失 case，必须先停止统计并满足以下规则：

1. 只允许在 A4 `02_case_runs` 下写入，A3 和 Node42 runner 不得直接调用，因为它们会写回受保护目录。
2. checkpoint 缺失或哈希不一致属于阻塞，不允许重训或修复。
3. 仅可为 `case_availability_matrix.csv` 明确标记缺失的 A0 路径×种子生成 A4 本地 runner。
4. 运行前必须执行兼容性审计、dry-run 和短 smoke；所有 MATLAB case 单进程串行。
5. 命令必须固定项目根目录、路径、种子、控制器、输出目录和 `-ReuseExisting` 语义，并将完整日志写入 `02_case_runs/logs`。
6. 中断后用相同命令恢复；不得删 case、改参数、改门限或更换种子。
7. 回传清单必须包含运行日志、case manifest、case metrics、trace、输出 MAT、运行前后哈希及更新后的可用性矩阵。

当前无需用户执行任何命令。
