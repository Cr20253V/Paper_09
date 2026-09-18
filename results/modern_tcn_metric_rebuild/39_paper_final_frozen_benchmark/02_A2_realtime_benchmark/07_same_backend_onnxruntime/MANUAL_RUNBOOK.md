# Manual runbook

The preparation step exports only derived TCN/GRU ONNX files, creates native-reference outputs, and checks numerical equivalence. It does not execute the 10,000-repeat formal benchmark.

All commands below are run from the project root in PowerShell.

## 1. Prepare and validate assets

```powershell
& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime\02_tools\prepare_ort_assets.ps1'
```

Expected terminal state: `READY_FOR_FORMAL_RUN`. If this has already completed and the hashes still match, the script validates and reuses the derived files instead of touching prior A2 results.

## 2. Before formal timing

Close MATLAB/Simulink, model training, Fusion/Node38 jobs, and project Python processes. In VS Code, the Python/Jedi language server started from this project's `.venv` is also a blocker. Close the relevant VS Code window or stop that language-server process manually; do not terminate unrelated system Python processes.

Check exclusivity:

```powershell
& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime\02_tools\check_exclusivity.ps1'
```

Proceed only when `exclusive` is `true` and `blocker_count` is `0`.

## 3. Run the formal benchmark

```powershell
& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime\02_tools\invoke_ort_benchmark.ps1'
```

The runner creates a new timestamped directory under `05_formal/runs`. It never overwrites an earlier formal run. Each model uses a fresh Python process, CPUExecutionProvider, FP32, batch 1, warmup 500, formal repeats 10,000, one intra-op thread, one inter-op thread, sequential execution, and full graph optimization.

On this host, PowerShell's child-process `ExitCode` can be unavailable even after a successful exit. Runner v2 therefore does not use that volatile property as its success gate. Each Python child publishes an atomic completion receipt only after its case JSON and raw CSV are complete; the controller verifies the receipt, exact counts, stderr, environment/model provenance, and file SHA256 values before moving to the next case.

If an earlier timestamped attempt contains `failure_receipt.json`, leave it in place and rerun the same command after correcting the reported blocker. The runner creates a new directory; never copy completed cases from a failed attempt into a new run.

Do not open MATLAB, start training/Fusion, or start a project Python process until the runner prints `FORMAL_RUN_COMPLETE`.

## 4. Read the result

The new run contains:

- `raw_timing/*.csv`: every formal latency sample;
- `cases/*.json`: per-model summary and artifact hashes;
- `child_receipts/*.json`: atomic per-child completion and raw-data SHA256 evidence;
- `environment.json`: runtime/hardware/thread/backend record;
- `runtime_summary.csv`: p50/p95/p99/max and `>10 ms` rate;
- `validation_receipt.json`: independent recomputation of every summary;
- `receipt.json` and `task_status.json`.

Use the 22D rows for architecture-only claims. Treat the delta-bank row as a final-method composite, not as an input-equivalent architecture comparison.

Run `20260717_164306` is the completed formal result. Its historical external memory CSV sampled the launcher PID; use `06_summary/memory_audit.csv` for corrected historical memory. Future runs use the fixed actual-descendant PID monitor.
