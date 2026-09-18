# A1 Manual Closed-Loop Runbook

## Resume interrupted TCN training and finish offline evaluation

The training implementation has no epoch-level optimizer checkpoint. If a seed
is interrupted before its model and meta files are saved, that seed restarts at
epoch 1. Fully saved seeds are hash/schema checked and skipped on rerun.

Run the visible foreground chain from PowerShell:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\01_tools\run_A1_manual_training_and_offline.ps1'
```

This command trains only the frozen seven TCN seeds, refreshes the registry,
evaluates only missing offline cases, and runs the provisional aggregation. It
does not start any formal closed-loop case. If interrupted, execute the same
command again.

Prerequisites: `task_status.json` reports `READY_FOR_MANUAL_CLOSED_LOOP`, `model_registry.csv` contains 40 `READY` models, and `03_offline/offline_case_metrics.csv` contains 40 rows.

## Recommended: two-worker parallel pool

The parallel runner uses two process workers: one for the GRU grid and one for
the TCN grid. Each worker has an independent base workspace and independent
short Simulink cache/codegen directory under `w/`. Canonical case outputs and
schema-based resume behavior are unchanged. This GRU+TCN split passed a
two-worker smoke test on 2026-07-16.

```powershell
& 'D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe' -batch "cd('E:/Matlab/Simulink/S-Function_16'); addpath('E:/Matlab/Simulink/S-Function_16/results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/01_tools'); run_A1_closed_loop_parallel()"
```

Do not start either serial command while the parallel command is active.
Rerunning the parallel command is safe: successful cases are schema-checked and
skipped.

Do not attempt two workers for only GRU or only TCN. A controlled test showed
that two process workers simulating the same Simulink model can return without
`logsout`; the runner therefore rejects `cfg.method='gru'` and
`cfg.method='tcn'`. If one family finishes first, the remaining family continues
on its existing worker. Never run a serial and parallel job for the same method
at the same time.

## Serial fallback

Run from PowerShell. Each command is serial, resumable, and writes only under
this A1 directory. Completed cases are schema-checked and skipped; failed cases
are retained.

## GRU-22D: 10 seeds × 6 paths

```powershell
& 'D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe' -batch "cd('E:/Matlab/Simulink/S-Function_16'); addpath('E:/Matlab/Simulink/S-Function_16/results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/01_tools'); run_A1_closed_loop_manual('gru')"
```

## TCN-22D: 10 seeds × 6 paths

```powershell
& 'D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe' -batch "cd('E:/Matlab/Simulink/S-Function_16'); addpath('E:/Matlab/Simulink/S-Function_16/results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/01_tools'); run_A1_closed_loop_manual('tcn')"
```

Both families may be executed in one serial MATLAB session with
`run_A1_closed_loop_manual('all')`. Do not run two independent serial MATLAB
sessions in parallel; use the isolated parallel-pool runner above.

After both commands finish, run:

```powershell
python 'E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\01_tools\finalize_A1.py'
```

This final command does not simulate or train. It validates the 240-case grid, recomputes ModernTCN-22D-relative control indices, runs the frozen 10,000-iteration bootstrap, and writes the final report, decision and receipt.
