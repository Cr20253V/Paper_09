# Figure contract: Fig07 gain calibration redesign

Core conclusion: Validation-only calibration demonstrates that the selected
`K_max = 0.5` is a condition-dependent upper bound rather than a fixed Fusion
weight.

Figure archetype: Asymmetric quantitative grid.

Target journal/output: Double-column manuscript figure; Python/matplotlib;
editable SVG and PDF; 600-dpi TIFF; 300-dpi PNG preview.

Backend: Python only.

Final size: 183 mm x 88 mm.

Panel map:

- a: One compact 4 x 4 matrix compares the regime-only ModernTCN-delta error
  scale with observer error scales at low, medium, and high excitation. The
  learned source is shown once per regime so observer excitation is not
  incorrectly attributed to ModernTCN-delta.
- b: Hero panel. Horizontal P05-P50-P95 intervals show `K_raw` and `K_eff` for
  the selected cap in each observer-excitation bin. The cap and the aggregate
  capped/below-cap fractions are stated directly.
- c: A two-dimensional validation decision plot combines MAE ratio and
  effective-gain spread. Thresholds define the displayed qualification region;
  direct labels distinguish failure, qualification, and final selection.

Evidence hierarchy:

- Hero evidence: Panel b establishes a non-degenerate effective-gain
  distribution below the selected cap.
- Validation evidence: Panel c shows that 0.3 fails the spread gate, 0.4 and
  0.5 qualify, and 0.5 is selected because it has the lowest validation MAE
  ratio among qualified candidates.
- Supporting calibration: Panel a exposes the condition-dependent marginal
  error scales used by the gain model.

Statistics needed: Descriptive validation-sample P05, P50, and P95 quantiles;
candidate MAE ratios; gain-spread gate outcomes. Quantile intervals are not
confidence intervals. No new hypothesis test or parameter selection is added.

Source data needed: Frozen selected configuration, empirical uncertainty
tables, candidate table, and quality-gain audit from the existing calibration
workflow.

Image-integrity notes: All marks are reconstructed from frozen numeric tables.
No raster scientific image is used. Text remains editable in SVG/PDF.

Reviewer risks:

- Do not imply that ModernTCN-delta is conditioned on observer excitation.
- Do not imply that P05-P95 intervals are confidence intervals.
- Do not imply that the largest gain spread is the ranking objective.
- The displayed two gates are not the only registered gates; the source table
  retains all qualification outcomes.

