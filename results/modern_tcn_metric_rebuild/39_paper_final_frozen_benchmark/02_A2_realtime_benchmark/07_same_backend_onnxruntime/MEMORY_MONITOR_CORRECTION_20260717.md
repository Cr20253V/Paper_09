# Historical memory-monitor correction

The completed latency run `20260717_164306` is valid and remains immutable. Its 40,000 raw latency samples, four child receipts, validation receipt and run artifact manifest are not changed.

The PowerShell external memory sampler in that historical run followed the `.venv` launcher process. For every case, the sampled PID differs from the actual Python PID recorded atomically by the child. Consequently, historical `external_peak_working_set_bytes`, `external_peak_private_bytes`, and `raw_memory/*.csv` describe the launcher and are invalid for inference-memory claims.

The case JSON also contains `PROCESS_MEMORY_COUNTERS_EX` measurements collected inside the actual Python process before session construction, before timing and after timing. Those fields are the authoritative historical memory source. They include Python, all preloaded test windows, feature materialization and the ORT session; they are not model-only or per-frame deployment memory. The corrected table and source hashes are in `06_summary/memory_audit.csv` and `06_summary/memory_audit.json`.

No latency rerun is needed. Future runs use descendant-process discovery, sample the real `benchmark_ort.py` PID, and require that PID to equal `child_receipt.child_pid`. A non-formal smoke found a launcher/child pair of `3940/10920`, collected 69 actual-child samples, matched receipt PID `10920`, and passed with empty stderr.
