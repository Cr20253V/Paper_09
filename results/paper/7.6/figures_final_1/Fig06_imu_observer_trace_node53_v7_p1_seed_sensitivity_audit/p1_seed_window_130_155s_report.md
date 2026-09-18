# V7/P1 ModernTCN-delta seed-sensitivity audit

## Scope

The audit evaluates the same P1 factory-logistics trajectory from V7 for model seeds
1, 7, 11, 21, 42, 73, 101, 202, 340, and 520. All records are complete and use the
same sensor seed (4631). The inspection window is 130–155 s,
which contains the visible seed42 fluctuation around 150 s.

## Detection rule

A step-like event is a ModernTCN-delta change of at least 20 deg/s.
A dropout is a zero ModernTCN-delta estimate while the true grade magnitude is at least
0.5 deg. The `tcn_ready` flag is retained to distinguish an unavailable
network output from a zero-valued output emitted while the network is ready.

## Result

All ten seeds exhibit an anomalous ModernTCN-delta behavior in this window. Step-like
oscillation/dropout is present in seeds [1, 7, 21, 42, 73, 101, 202, 340]. Seeds [11, 520] do not show
step transitions because they remain at zero through the entire 25.01-s window; this is a
more persistent dropout rather than an improvement. The zero-output behavior occurs while
`tcn_ready=1` for the affected samples.

Seed42 is therefore not an isolated bad draw and is not the worst case by local maximum
error or number of transitions. The Qualified observer is substantially smoother in this
window for every seed; its local MAE remains approximately 0.29–0.30 deg, while the raw
ModernTCN-delta local MAE is approximately 1.04–1.58 deg.

## Files

- `p1_seed_window_130_155s_summary.csv`: one row per seed.
- `p1_seed_window_130_155s_events.csv`: start/end times of every detected step transition
  and zero-output run.
