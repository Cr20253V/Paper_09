# A1 Parallel Closed-Loop Validation (2026-07-16)

## Environment

- MATLAB: R2024b
- Parallel Computing Toolbox license test: available
- Pool type: `Processes`
- Validated pool size: 2 workers
- CPU: Intel Core i7-14650HX, 16 cores / 24 logical processors
- RAM: 31.7 GB

## Implementation

- Entry point: `01_tools/run_A1_closed_loop_parallel.m`
- Safe partition: one GRU worker plus one TCN worker
- Worker cache folders: `w/c/g` and `w/c/t`
- Worker code-generation folders: `w/g/g` and `w/g/t`
- Resume behavior: a case is skipped only after output and summary schema checks
- Progress behavior: changed counts are printed immediately and an unchanged
  heartbeat is printed every 60 seconds

## Validation evidence

1. A two-worker dry run produced 120 schedulable rows with no worker errors.
2. A GRU+TCN smoke run used seed 42 and frozen path
   `p06_downhill_after_turn`; both cases completed with output, comparison
   summary and case manifest.
3. The successful smoke receipt is
   `04_closed_loop/closed_loop_parallel_smoke_status.json` with
   `row_count=2`, `failed_future_count=0`, and `failed_case_count=0`.

## Rejected configuration

Two workers running the same TCN Simulink model were tested and both returned
without `logsout`, although the equivalent single-worker control run completed.
The original failed smoke logs are retained under
`04_closed_loop/smoke/tcn_22d`. Therefore the production runner rejects
`cfg.method='gru'` and `cfg.method='tcn'`; it permits only the validated
GRU+TCN partition. No model, path, seed, threshold, plant revision or MPC
configuration was changed in response.

## Current formal state at validation

- Reused closed-loop cases: 120
- New GRU cases complete and schema-audited: 18/60
- New TCN cases complete: 0/60
- Full grid: 138/240 complete, 102 missing
- Provisional decision: `INCOMPLETE_GRID`
