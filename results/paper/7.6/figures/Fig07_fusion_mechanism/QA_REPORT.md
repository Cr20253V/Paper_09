# Fig. 7 QA Report

## Scope

- Figure generation only; no manuscript text, context, or table files were modified.
- Backend: Python 3 with pandas, NumPy, and matplotlib only for data processing, rendering, export, and visual QA.
- Figure archetype: schematic-led quantitative mechanism trace.
- Core conclusion: the Qualified observer supplies a selective and bounded correction; fallback preserves the ModernTCN-delta estimate exactly.

## Data and alignment

- Runtime samples: 24582
- Trace samples: 24583
- Mapping: `runtime row i maps to trace row i; t_s=(step-1)*0.01`
- Detail window: 129.95-144.94 s (1500 samples)
- Units: grade, innovation, and correction converted from rad to deg; gain, NIS, and state retained dimensionless.

## Numeric checks

- Active fraction: 0.059759
- Exact fallback fraction: 0.940241
- Active samples with reduced grade error: 0.940776
- Scheduled-grade MAE after 0.5 s warm-up: 0.407417 deg
- NIS P95 (MATLAB/Hazen convention): 0.291554
- Active-state K_eff P05/P95: 0.472831 / 0.700492
- Fallback identity maximum absolute deviation: 0.000e+00 rad

## Layout and export checks

- Artist QA: PASS
- Minimum visible font: 5.70 pt
- Text overflow count: 0
- Export QA: PASS
- Final size: 183 x 116 mm
- PNG: 4322 x 2740 px at 600 dpi
- SVG editable text elements: 42
- Grayscale QA copy generated in `qa/`.

## Overall status

**PASS**
