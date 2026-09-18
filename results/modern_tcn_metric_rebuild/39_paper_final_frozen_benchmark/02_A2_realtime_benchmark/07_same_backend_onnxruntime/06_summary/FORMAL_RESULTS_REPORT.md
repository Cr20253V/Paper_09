# Unified ONNX Runtime formal result

Status: `FORMAL_RUN_COMPLETE_WITH_HISTORICAL_MEMORY_MONITOR_CORRECTION`.

Run `20260717_164306` completed four frozen seed-42 predictors using ONNX Runtime CPUExecutionProvider, FP32, batch 1, one intra-op thread, one inter-op thread, 500 warmups and 10,000 formal calls per method. All 40,000 raw timings, child receipts, model/data/environment hashes and exclusivity records passed independent validation. The protected 5,313-file snapshot is unchanged.

| Method | Parameters | ONNX bytes | p50 ms | p95 ms | p99 ms | max ms | >10 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| GRU-22D | 99,276 | 400,682 | 0.3071 | 0.3377 | 0.4124 | 0.9854 | 0/10,000 |
| ModernTCN-22D | 118,538 | 472,135 | 0.3582 | 0.3881 | 0.4942 | 1.1671 | 0/10,000 |
| ModernTCN-delta_bank_124 | 145,202 | 578,793 | 0.3744 | 0.4038 | 0.4818 | 1.0823 | 0/10,000 |
| TCN-22D | 156,396 | 627,487 | 1.0452 | 1.1341 | 1.3597 | 13.1071 | 1/10,000 |

ModernTCN-22D has 24.21% fewer parameters and 24.76% smaller ONNX storage than TCN-22D; its p95 latency is 65.78% lower (2.92x speedup). GRU-22D is the fastest core inference implementation in this frozen comparison. Delta-bank core inference has p95 0.4038 ms and zero 10 ms overruns, but online delta construction is outside this timing scope.

TCN-22D has one retained 13.1071 ms observation at iteration 9,094. Its p95 and p99 still meet 10 ms, while `zero_overrun=false`.

Historical external PowerShell memory fields sampled the launcher PID and are invalid. Corrected historical memory uses the actual Python process's internal Windows API counters; see `memory_audit.csv`. Process-lifetime peak working sets are 130.65 MiB (GRU), 130.68 MiB (ModernTCN-22D), 401.02 MiB (delta-bank), and 129.48 MiB (TCN). These include full preloaded test inputs and are not per-frame deployment memory.

Interpretation guard: use the three 22D rows for architecture-only measured latency. Treat delta-bank as representation plus architecture. TCN/GRU preserve the frozen MATLAB `CBT` execution semantics, so this supports claims about the frozen implementations rather than a generic FLOP comparison.

Manuscript-ready Chinese wording, percentile definitions, compact figure annotations and scope restrictions are preserved in `06_summary/PAPER_WRITING_NOTES_CN.md`.
