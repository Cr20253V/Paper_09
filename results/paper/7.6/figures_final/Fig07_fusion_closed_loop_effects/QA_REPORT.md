# Figure 7 QA Report

- Overall status: **PASS**
- Backend: Python/matplotlib only.
- Final size: 183 mm x 90 mm.
- Raster export: 600 dpi PNG.
- Scope: figure generation only; manuscript and tables were not modified.

## Evidence and numeric checks

- Included 6 routes x 10 seeds = 60 matched pairs for each metric.
- Effect direction is ModernTCN minus Fusion; positive values favor fusion.
- Exact ties remain at x=0; only vertical within-route separation is used.
- `ey_rmse` wins/ties/losses: 36/16/8; all numeric mappings PASS.
- `epsi_rmse` wins/ties/losses: 29/16/15; all numeric mappings PASS.
- `j_du` wins/ties/losses: 24/16/20; all numeric mappings PASS.
- The `j_du` overall 95% interval crosses zero and is drawn without warning color.
- Panel (c) uses a labelled off-scale marker for the single distant positive effect while preserving central detail.

## Layout and export checks

- Minimum visible font: 6.0 pt.
- Material text overflow count: 0.
- PNG dimensions: 4322 x 2125 px.
- PDF size: 183.000 x 90.000 mm.
- SVG editable text elements: 35.
- PDF extractable text characters: 432.
- Grayscale preview: `qa/fig07_fusion_closed_loop_effects_grayscale.png`.

## Visual language

- Arial-compatible sans-serif typography, 8-pt bold panel labels, and 6.2-7.2-pt supporting text match the surrounding manuscript figures.
- The established manuscript blue (`#0072B2`) marks route means; lighter gray-blue marks cases and deep blue marks overall intervals.
- Neutral gray zero lines, subtle row bands, and restrained grid lines preserve grayscale legibility.
