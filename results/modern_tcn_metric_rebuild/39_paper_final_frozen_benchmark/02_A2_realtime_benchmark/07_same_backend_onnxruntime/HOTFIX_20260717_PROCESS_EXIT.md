# Formal-runner child-completion hotfix v2

The `20260717_161250` and `20260717_162640` attempts did not fail inside ONNX Runtime. In both attempts, the ModernTCN-22D child completed 500 warmups and 10,000 formal calls, wrote a complete case JSON and 10,000-row raw timing CSV, and produced empty stderr. The PowerShell controller then lost `System.Diagnostics.Process.ExitCode` after process exit. `WaitForExit()` plus `Refresh()` did not make that property reliable on this host.

Both timestamped attempts remain excluded because neither contains all four cases or a final validation receipt. Their partial measurements must not be merged with a later run.

The v2 runner no longer uses `ExitCode` as a success gate:

1. Each Python child atomically publishes raw timing and case JSON files.
2. Only after both files are complete, stdout is flushed, and their SHA256 values are computed does the child atomically publish `child_receipts/core_inference__<method>.json`.
3. PowerShell waits for termination and treats `ExitCode` as optional diagnostic metadata only.
4. PowerShell requires a valid child receipt, exact method/protocol/count/environment/model provenance, an empty stderr log, a 10,000-row raw CSV, and matching raw/case SHA256 values before accepting a case.
5. The final validator independently requires all four child receipts and rechecks every raw CSV SHA256, sequence, statistic, backend field, provenance hash, and external-memory record.
6. A genuine child failure cannot create a success receipt; absence of the receipt fails closed and retains the timestamped attempt.
7. Atomic temporary files use short PID-based basenames so the deep project path cannot cross the Windows legacy path-length boundary.

Validation performed after the v2 change:

- Python compilation and PowerShell parser checks passed.
- Positive non-formal smoke: `CHILD_COMPLETE`, 20/20 rows, raw SHA match, case SHA match, empty stderr.
- Negative smoke with an invalid method: nonzero Python termination, no success receipt, nonempty stderr.
- Four-case `Start-Process` controller smoke: all four methods passed receipt, row-count, raw SHA, case SHA, and stderr gates without using `ExitCode` as success authority.
- A deliberately deep smoke path exposed the first long temporary basename; the failed non-formal smoke is retained with a diagnostic receipt, and the short-basename rerun passed all four cases.

The authoritative completion signal is now `atomic_child_receipt_plus_artifact_validation`, not the volatile process property.
