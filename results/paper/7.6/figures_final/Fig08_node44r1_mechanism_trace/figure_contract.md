# Figure contract: Fig08 Node44R1 mechanism trace

Core conclusion: The complete fixed P2 Sharp-turn transition trace at model
seed 42 shows condition-dependent correction, causal rate limiting, and exact
fallback to ModernTCN-delta.

Figure archetype: Quantitative grid of four vertically aligned full-record
time-series panels.

Target journal/output: Nature-style, double-column figure; Python/matplotlib
only; editable SVG and PDF; 600-dpi TIFF; 300-dpi PNG preview.

Final size: 183 mm x 112 mm. Minimum visible text is 6.5 pt; panel labels are
8 pt bold lowercase.

Panel map:

- a: Reference grade, ModernTCN-delta estimate, qualified observer estimate,
  and fused grade over the complete 52-s record.
- b: Effective gain with the frozen `K_max = 0.5` cap and fallback intervals.
- c: Target and applied correction, with rate-limit activity marked and the
  frozen +/-0.5 degree correction bounds visible.
- d: NIS with fallback intervals; the panel reports the observed NIS record
  without implying that every fallback is NIS-triggered.

Evidence hierarchy:

- Hero evidence: Panel a shows when the fused grade follows or departs from the
  learned estimate across the complete route.
- Validation evidence: Panels b and c connect those departures to effective
  gain and the stateful correction update.
- Controls/robustness: Panel d and shared fallback shading show exact-reset
  intervals and distinguish fallback from ordinary gain variation.

Statistics needed: None beyond frozen case-level diagnostics and counts. This
is qualitative mechanism evidence and does not replace the 60-pair summaries.

Source data needed: Frozen P2, model-seed-42 files only from
`11_formal_six_path/cases/ADAPTIVE/s42/p02_sharp_turn_transition`:
`trace.csv`, `node44r1_runtime_debug.csv`, `case_manifest.json`, and
`case_metrics.json`.

Image-integrity notes: No raster scientific images are used. All 5200 runtime
updates are retained in source data and plotted as full traces; rendering may
use line simplification only if it does not alter the numeric source export.

Reviewer risk: The case is fixed for qualitative visualization and is not a
best-seed selection. The observer line is the logged qualified force-balance
output, not a reconstruction from any historical observer formula. Fallback
identity and the normal 5 degree/s rate-limit contract must be verified against
the frozen debug log.

Caption authority: The figure must match the manuscript wording for P2,
model seed 42, the four named evidence panels, continuous zero crossing under
the normal rate limit, and exact recovery of ModernTCN-delta on invalid or gated
samples.

