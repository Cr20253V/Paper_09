# Figure contract: Fig07 Node44R1 gain calibration

Core conclusion: Validation-only calibration shows that the selected
`K_max = 0.5` is a condition-dependent cap rather than a fixed Fusion weight.

Figure archetype: Quantitative grid with one calibration-table panel and two
validation-summary panels.

Target journal/output: Nature-style, double-column figure; Python/matplotlib
only; editable SVG and PDF; 600-dpi TIFF; 300-dpi PNG preview.

Color contract: Panel a uses one shared low-saturation light-blue-gray to
deep-blue sequential scale for error magnitude. This follows the manuscript's
established blue family for ModernTCN/Fusion evidence and avoids a competing
yellow highlight. Identical values retain identical colors in both heatmaps;
green/red remain reserved for qualification outcomes in panel c.

Final size: 183 mm x 100 mm. Minimum visible text is 6.5 pt; panel labels are
8 pt bold lowercase.

Panel map:

- a: Frozen four-regime by three-excitation empirical total-error moments for
  ModernTCN-delta and the qualified observer, displayed as error scale in
  degrees (`sqrt(P) * 180 / pi`).
- b: Selected-candidate `K_raw` and `K_eff` P05-P50-P95 intervals by observer
  excitation bin; the `K_max = 0.5` cap is shown explicitly.
- c: Frozen qualification of the three candidate caps, combining MAE ratio,
  effective-gain spread, and pass/fail status without reranking candidates.

Evidence hierarchy:

- Hero evidence: Panel b shows that the effective gain occupies a non-zero
  range below the selected cap.
- Validation evidence: Panel c shows why `K_max = 0.5` is selected under the
  registered qualification and ranking.
- Controls/robustness: Panel a exposes the calibrated regime/excitation table
  that supplies the condition dependence.

Statistics needed: Validation-only descriptive quantiles and candidate gate
outcomes. No new interval, hypothesis test, parameter choice, or seed choice is
computed.

Source data needed: Frozen files only from
`06_uncertainty_calibration_v3`: `selected_fusion_config.json`,
`candidate_table.csv`, `quality_gain_audit.csv`, and
`empirical_quality_uncertainty_tables.json`.

Image-integrity notes: No raster scientific images are used. Heatmap cells and
intervals are rebuilt numerically from frozen tables. All labels remain vector
text in SVG/PDF.

Reviewer risk: A quantile interval must not be read as a confidence interval;
the panel labels it P05-P50-P95. The source-error heatmaps show error scale
derived from frozen total second moments, not newly estimated standard errors.
Candidate qualification must retain the registered failure of `K_max = 0.3`
and the registered selection of `K_max = 0.5`.

Caption authority: The figure must remain consistent with the manuscript
caption stating that the selected candidate has P05-P95 gain spreads of
0.42698 and 0.21872, and that `K_eff` is at least 0.01 below its cap for 35.37%
of valid non-fallback samples.
