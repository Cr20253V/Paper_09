# Unified ONNX Runtime preparation report

Preparation baseline: `READY_FOR_FORMAL_RUN`. At the original preparation handoff, formal timing had not started and `05_formal/runs` was empty. Two later timestamped attempts are retained but excluded because the pre-v2 controller stopped after the first completed child. Formal run `20260717_164306` subsequently completed all four cases and 40,000 raw timings.

## Frozen inputs and derivatives

The four authority models are the A1 `model_registry.csv` seed-42 rows. The two existing ModernTCN ONNX files are referenced in place. TCN and GRU were exported as A2-local derivatives, with authority model path/SHA, feature-export SHA, frozen-head SHA, and complete-graph SHA recorded in `01_inventory/derived_model_registry.csv`. No model was retrained and no checkpoint was reselected.

Derived complete-predictor SHA256:

- TCN-22D: `89537bea08273cb6638c25e06e92beeb9c7ebbb48db7ae76dd7e6fe09ec14512`
- GRU-22D: `449346956e5a0aeaa906dabe1df5d3472b3a690a0de2a1526e3125e347c3b8a4`

Both graphs output `logits_main`, `logits_turn`, and `theta_hat`; their readout and heads are inside the ONNX graph and therefore inside formal `InferenceSession.run` timing.

## Numerical gate

All 3,602 frozen test windows were checked against MATLAB-native seed-42 outputs:

| Model | Main label agreement | Turn label agreement | Max probability error | Max theta error (rad) |
|---|---:|---:|---:|---:|
| TCN-22D | 1.0 | 1.0 | `7.153e-7` | `1.416e-7` |
| GRU-22D | 1.0 | 1.0 | `5.066e-7` | `1.639e-7` |

Both existing ModernTCN ONNX consistency sidecars pass, and an additional 64-window finite-output smoke passed for each. The complete machine-readable result is `04_validation/equivalence_summary.json`.

## Authority-semantics finding

The frozen TCN/GRU MATLAB predictors label `[22,128,1]` as `CBT`; consequently the authority execution is `C=22, B=128, T=1` and pools dimension 2. The derivatives preserve this exactly using MATLAB ONNX export `BatchSize=128`. This is necessary for 100% output equivalence and is documented in `00_protocol_lock/tcn_gru_authority_semantics_audit.md`.

This means the future same-backend table can support measured implementation-latency claims, but it must not be described as a conventional length-128 GRU/TCN FLOP comparison without disclosing the frozen execution semantics.

## Non-formal smoke

The four-model 5-warmup/20-repeat smoke confirmed model loading, ORT execution, high-resolution timing, raw CSV writing, SHA registration, and Windows memory collection. These smoke latencies are diagnostic only and must not be cited as formal results.

## Protection and exclusivity

A SHA256 snapshot covers 5,313 protected files across A0/A1/A3, Node38, original A2 outputs, and `paper_v3.tex`. The formal runner verifies this snapshot before and after timing. All preparation writes are confined to this `07_same_backend_onnxruntime` directory.

At handoff, exclusivity is blocked only by the VS Code Jedi language server using the project `.venv` (PID 23848 at the recorded check). Close that process before invoking the formal runner; PIDs are transient, so always rely on a fresh `check_exclusivity.ps1` result.

## Post-preparation runner audit

The `20260717_161250` and `20260717_162640` timestamped attempts each completed the first child but were excluded after the controller could not retrieve a stable `System.Diagnostics.Process.ExitCode`. No ONNX Runtime error occurred and stderr was empty. Runner v2 replaces that success gate with an atomic child receipt plus independent count, SHA256, stderr, protocol, and provenance checks. Positive and negative non-formal smoke tests passed. See `HOTFIX_20260717_PROCESS_EXIT.md`.

## Post-run memory correction

The completed run's PowerShell external sampler measured the `.venv` launcher instead of the actual Python descendant. Those external fields are invalid, but the actual Python process's internal Windows API counters remain valid and are the corrected historical source. Latency results are unchanged and require no rerun. Future runner validation requires the sampled PID to equal `child_receipt.child_pid`; the real-child monitor smoke passed. See `MEMORY_MONITOR_CORRECTION_20260717.md`.
