# QA Report: Figure 5 Representative Four-Estimator Trace

- Overall automatic QA: **PASS**
- Backend: Python/matplotlib; MAT v7.3 extraction used Python/h5py.
- Final size: 183 mm x 100 mm.
- Raster export: 600 dpi PNG.
- Scope: figure, source data, scripts, and QA only; no TeX or table files were modified.
- Trace policy: complete 0-52 s route, no smoothing, no local-window cropping.
- Alignment: all estimators share the same 5201-sample, 0.01-s time axis; reference traces agree exactly.
- Metric policy: MAE uses t >= 0.5 s to match the frozen benchmark; P95 uses the complete trace with MATLAB-compatible prctile.

| Method | MAE (deg) | P95 abs. error (deg) | Peak abs. error (deg) |
|---|---:|---:|---:|
| ModernTCN-delta | 0.50378 | 1.1382 | 3.21749 |
| ModernTCN-22D | 0.69363 | 1.7682 | 3.52813 |
| GRU-22D | 0.80700 | 1.9409 | 2.94116 |
| TCN-22D | 0.55303 | 1.3891 | 2.12935 |

- Minimum visible font: 6.0 pt.
- Text overflow count: 0.
- Editable SVG text elements: 47.
- PNG dimensions: 4322 x 2362 px.
- Grayscale separability is supported by distinct line patterns for all four estimators.

Visual QA should confirm the metrics box does not obscure a principal transition and that all five legend entries remain readable at final size.
