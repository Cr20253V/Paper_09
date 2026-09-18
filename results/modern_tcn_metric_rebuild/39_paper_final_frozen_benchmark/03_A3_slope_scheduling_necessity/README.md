# A3 当前对象坡度调度必要性实验

当前状态：`COMPLETE`。正式网格 `18/18 COMPLETE`，A5 A3 schema `PASS`；Oracle vs ZS 主裁决为
`SUPPORTED_ALL_PRIMARY`，IMU vs ZS 次要裁决为 `INCONCLUSIVE`。正式报告见
`A3_experiment_report.md`，机器可读裁决见 `decision.json`。

本目录是 A0 冻结协议下 A3 的唯一写入目录。实验在六条冻结路径上比较 `ZS_LPV_MPC`、`IMU_LPV_MPC` 与 `Oracle_LPV_MPC`，三者只改变进入公共 `RhoFilter` 的坡度来源；对象、LPV 数据库、MPC 参数、初始状态、路径和时长均相同。

## 冻结规则

- A0、共享源码、现有模型、其他 Node 目录和 `paper_v3.tex` 只读。
- 默认 `enable_noise=false`，因此每个控制器/路径只运行一次，传感器与过程噪声种子为 `null`。
- IMU 使用 Node36 审计通过的因果估计器原始输出，不附加 G1 外层死区、二次限速或学习标签门；三种坡度来源随后共同通过原 Node26 `RhoFilter`。
- 不按结果更改路径、门限、估计器参数、MPC 配置或运行次数。失败 attempt 原样保留。

## 目录说明

- `00_protocol_lock/`：A0 快照、有效配置与门限适用性。
- `01_inventory/`：长运行前的复用清单、缺失 case、18-case 矩阵、输入路径与 SHA256、预计产物。
- `02_tools/`：隔离模型生成、运行、评价、汇总与校验工具；Simulink cache/codegen 使用目录内短路径 `c/` 以满足 Windows 路径长度限制。
- `03_cases/`：逐 controller/path 的 manifest、原始 MAT、逐采样 trace、指标、日志和 receipt。
- `04_summary/`：A5 兼容 case 表、汇总、配对 bootstrap、安全门和最差 case。
- `05_logs/`：批运行日志。

当前阶段状态以顶层 `task_status.json` 和 `receipt.json` 为准；正式裁决以 `decision.json` 为准。
