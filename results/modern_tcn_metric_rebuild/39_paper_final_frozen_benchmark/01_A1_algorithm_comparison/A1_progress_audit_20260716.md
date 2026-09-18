# A1 Progress Audit — 2026-07-16

## Current state

- protocol: `A0_paper_final_unified_protocol_v1`
- task status: `READY_FOR_MANUAL_CLOSED_LOOP`
- models: `40/40 READY`
- unified offline cases: `40/40`
- reusable closed-loop cases: `120/120`
- new GRU/TCN formal closed-loop cases: `0/120`
- complete closed-loop grid: `120/240`
- provisional decision: `INCOMPLETE_GRID`
- offline decision: `SUPPORTED_ALL_PRIMARY`

## Completed checks

- The seven missing TCN seeds `1, 7, 11, 42, 202, 340, 520` have complete
  model/meta pairs and a successful training receipt.
- The seven frozen training configurations are identical after excluding only
  the seed and output paths.
- The model registry contains 40 unique method/seed pairs.
- Every registered model and meta/config SHA256 matches the current file.
- Every model references the frozen dataset SHA256
  `ab5dde32ef3627aa7032a3b4f7632c87cb471287a638f2b14a25a179a660196f`.
- The offline table contains 40 unique method/seed cases.
- Every offline raw prediction file contains exactly 3,602 test-window rows.
- There are 40 prediction audit JSON files and 40 unified metric JSON files.
- Offline bootstrap contains 14 effects using 10,000 iterations, random seed
  `20260715`, 95% percentile CI, and paired model-seed resampling.
- The 120 referenced Node30/Node32 closed-loop cases are unique, cover six paths
  for every seed, and pass source MAT/summary SHA256 verification.
- The full formal GRU/TCN preflight contains 120 rows: 60 GRU and 60 TCN, all
  with status `ready`.
- A0, the A0 explanation, the experiment outline, and `paper_v3.tex` retain
  their protected baseline SHA256 values.

## Offline result checkpoint

The confirmatory offline bootstrap supports `ModernTCN + delta_bank_124`
against all three comparators for both preregistered primary metrics:
`theta_mae_deg` and `theta_abs_le_10_p95_abs_err_deg`. All six confirmatory
95% confidence intervals have positive lower bounds under the frozen
`comparator - target` effect convention.

This is an offline-only result. The overall A1 claim remains provisional until
the 120 formal GRU/TCN closed-loop cases are complete and the full 240-case
hierarchical bootstrap and Node10 gate audit have run.

## Provisional gate observation

On the 120 currently available referenced closed-loop cases, 24
`ModernTCN + delta_bank_124` case rows carry an observed Node10 gate failure:

- seeds `21` and `101`: `stall_recall_drop` on all six paths, 12 rows total;
- seeds `73` and `340`: `theta_flat_abs_max_deg_ratio` on all six paths,
  12 rows total.

These are seed-level offline gate inputs repeated across the six matched paths,
not 24 independent offline failures. They are retained without changing any
seed, path, model, threshold, or recipe. The formal decision field remains
unset (`null`) until the complete 240-case grid is present.

## Remaining work

1. Run the 60 formal GRU-22D closed-loop cases.
2. Run the 60 formal TCN-22D closed-loop cases.
3. Execute `01_tools/finalize_A1.py`.
4. Audit the complete 240-case grid, worst paths/cases, closed-loop bootstrap,
   Node10 gates, final decision, receipt, and artifact manifest.

No result has been used to change a frozen path, seed, threshold, plant
revision, MPC configuration, dataset, split, scaler, window, input definition,
or training recipe. Missing cases are not imputed.
