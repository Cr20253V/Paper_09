# Innovation 4 Figure Contract

Core conclusion:

The causal fused slope is converted into one synchronized scheduling value that
instantiates the discrete LPV model and updates the constrained MPC at each
sampling instant.

Figure archetype: schematic-led composite

Target output: IEEE-style double-column figure, approximately 183 mm wide, with
editable vector text and a 300/600 dpi raster preview.

Backend: Python / matplotlib only

Panel map:

- (a) Offline model construction: continuous nonlinear AGV model, steering
  one-step update, RK4 propagation, path-error mapping, finite-difference
  matrices, and the 11 x 15 x 25 LPV database.
- (b) Online scheduling: ModernTCN and causal IMU outputs are abstracted as the
  innovation-3 fusion interface, followed by conditioning, the scheduling
  vector, and eight-vertex trilinear interpolation.
- (c) Coordinated controller update: the same synchronized slope feeds the
  interpolated model, measured-disturbance channel, nominal feedforward, and
  scheduled weights/constraints before the constrained MPC solve.

Evidence hierarchy:

- Hero evidence: the shared slope signal and the two offline/online paths.
- Supporting evidence: matrix dimensions, grid cardinality, and receding-horizon
  feedback loop.

Statistics: none; this is a method schematic, not a quantitative result figure.

Source-data traceability: every node and dimension is tied to
`state_eq_ref.m`, `lin_agv_at_point.m`, `lin_agv_grid.m`,
`mpc_update_from_rho.m`, and the Adaptive MPC update interface.

Reviewer risks:

1. A reviewer may confuse scheduling slope with measured disturbance. The figure
   therefore labels one shared, filtered slope signal at both destinations.
2. A reviewer may assume the fusion rule is already finalized. The fusion block
   is explicitly an interface block, not a claimed network architecture.
3. A reviewer may mistake the database for a continuous-time model. The figure
   labels the one-step discrete propagation and the matrix dimensions.

Export bundle:

- `fig_fused_slope_lpv_mpc.svg` (primary editable vector)
- `fig_fused_slope_lpv_mpc.pdf` (LaTeX inclusion)
- `fig_fused_slope_lpv_mpc.tiff` (600 dpi)
- `fig_fused_slope_lpv_mpc.png` (300 dpi preview)
