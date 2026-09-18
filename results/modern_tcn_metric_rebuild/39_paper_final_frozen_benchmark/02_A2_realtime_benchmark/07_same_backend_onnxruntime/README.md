# A2 supplemental: unified ONNX Runtime benchmark

This directory is an independent supplement to the completed MATLAB A2 benchmark. It never rewrites `04_phase1`, `06_summary`, the A2 root receipt/status, or any A0/A1/A3/Node38/paper artifact.

Purpose: remove the dominant execution-backend confound by running the four frozen seed-42 predictors through the same ONNX Runtime CPU backend. The primary architecture comparison is ModernTCN-22D vs GRU-22D vs TCN-22D with identical `[1,128,22]` FP32 input. ModernTCN-delta_bank_124 is reported separately as the final representation-plus-architecture method with `[1,128,88]` input.

The formal scope is **complete predictor inference** (`input_window -> logits_main, logits_turn, theta_hat`). Session construction, model loading, dataset loading, delta-bank construction, and MPC are outside this supplemental core timing. The existing MATLAB A2 end-to-end and full-cycle results remain the deployment evidence.

Formal run `20260717_164306` is complete: four cases and 40,000 raw timings passed validation. Two earlier pre-v2 attempts remain retained and excluded. The final result is in `06_summary/FORMAL_RESULTS_REPORT.md`.

The historical formal run's external PowerShell memory sampler followed the `.venv` launcher PID, so those external fields are invalid; latency is unaffected. Corrected historical memory uses Windows API counters recorded inside the actual Python process and is documented in `MEMORY_MONITOR_CORRECTION_20260717.md`. The runner now discovers and samples the real descendant PID and requires equality with the atomic child receipt.
