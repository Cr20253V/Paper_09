# A1 Fair Algorithm Comparison

- protocol: `A0_paper_final_unified_protocol_v1`
- status: `READY_FOR_MANUAL_CLOSED_LOOP`
- output boundary: `E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison`
- paper primary method: `modern_tcn_delta_bank_124`
- models ready: `40/40`
- unified offline cases: `40/40`
- reusable closed-loop cases: `120/120`
- new formal closed-loop cases: `0/120`
- current full grid: `120/240`
- pre-run missing evaluation cases: `127` (TCN offline 7 + GRU closed loop 60 + TCN closed loop 60)

All upstream models and results are referenced by absolute path and SHA256. No upstream artifact is copied or overwritten. Historical Node30/Node32 `J_control_path` values are not used for A1 cross-algorithm normalization; A1 recomputes them against matched ModernTCN-22D seed/path cases.

The seven missing TCN seeds and all 40 unified offline cases are complete.
The full 120-case GRU/TCN formal closed-loop preflight passed on 2026-07-16.
Run the formal cases using `MANUAL_RUNBOOK.md`, then execute
`01_tools/finalize_A1.py`.
