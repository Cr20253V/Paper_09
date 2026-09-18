# Figure contract: Fig09 Node44R1 formal summary

Core conclusion: Across 60 matched route-seed pairs, Fusion has supported
aggregate improvements in heading-error RMS and input regularity, while the
favorable lateral-error effect remains statistically unresolved and route P6
contains the only adverse route-metric mean.

Figure archetype: Quantitative grid with a dominant aggregate forest panel and
a route-stratified supporting matrix.

Target journal/output: Nature-style, double-column figure; Python/matplotlib
only; editable SVG and PDF; 600-dpi TIFF; 300-dpi PNG preview.

Final size: 183 mm x 104 mm. Minimum visible text is 6.5 pt; panel labels are
8 pt bold lowercase.

Panel map:

- a: Three metric-specific MTCN-minus-Fusion effects and frozen hierarchical
  paired-bootstrap 95% confidence intervals, each on its native unit scale.
- b: Six-route by three-metric route-level mean effects, with favorable,
  unchanged, and adverse directions encoded by both color and marker shape.

Evidence hierarchy:

- Hero evidence: Panel a carries the formal aggregate inference over all 60
  matched route-seed pairs.
- Validation evidence: Panel b shows all 18 route-metric mean comparisons and
  localizes the sole adverse mean to `J_delta_u` on P6.
- Controls/robustness: Exact-zero P4 effects remain visible and distinct from
  favorable effects; no route is omitted.

Statistics needed: Read the frozen estimates, 95% confidence intervals,
claim status, and route means. Do not rerun bootstrap sampling or alter the
pre-specified joint rule.

Source data needed: Frozen files only from `12_statistics`:
`bootstrap_ci_results.csv`, `per_path_summary.csv`, `paired_case_details.csv`,
`decision.json`, and `safety_summary.csv`.

Image-integrity notes: No raster scientific images are used. All plotted values
are copied or deterministically aggregated from frozen summary tables; vector
text remains editable in SVG/PDF.

Reviewer risk: Positive effects must be labeled as MTCN-minus-Fusion. Native
units prevent cross-metric magnitude ranking. The lateral-error interval crosses
zero and must remain visually and verbally inconclusive. P4 exact zeros and the
P6 adverse `J_delta_u` mean must not be hidden. Aggregate inference uses all 60
pairs despite route-level display.

Caption authority: The figure must reproduce the manuscript counts: 14 of 18
route-metric means favor Fusion, three are unchanged, only P6 `J_delta_u` is
adverse, and aggregate inference uses all 60 matched pairs.

