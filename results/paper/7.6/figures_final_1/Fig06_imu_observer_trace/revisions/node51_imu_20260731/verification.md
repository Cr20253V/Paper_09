# Fig. 6 Node51 IMU Replacement Verification

## Inputs

- ModernTCN: Node44R1, `ADAPTIVE/s42/P2`, field `theta_tcn`.
- Baseline IMU: covariance-sensitivity P2 RKF, field `theta_rkf`.
- Modified IMU: Node51, `ADAPTIVE/s42/P2`, field `theta_rkf`.
- Metric window: `t >= 0.5 s`; decisive tolerance: `0.1 deg`.

## Baseline And Modified Behavior

Command:

```powershell
python results/paper/7.6/figures_final_1/Fig06_imu_observer_trace/revisions/node51_imu_20260731/verify_node51_imu.py
```

Literal output, exit status 0:

```text
{"baseline":{"rkf_mae_deg":1.00460985616877,"mtcn_mae_deg":0.6207456336387451,"rkf_win_pct":34.07105416423995,"mtcn_win_pct":55.950300912444185,"near_tie_pct":9.978644923315862,"time_truth_exact":true,"evaluated_samples":5151},"modified":{"rkf_mae_deg":0.225628357505021,"mtcn_mae_deg":0.6207456336387451,"rkf_win_pct":53.54300135895943,"mtcn_win_pct":25.276645311589984,"near_tie_pct":21.18035332945059,"time_truth_exact":true,"evaluated_samples":5151}}
```

## Figure Generation

Command, from `results/paper/7.6/figures_final_1/Fig06_imu_observer_trace`:

```powershell
python scripts/generate_fig06_imu_observer_trace.py --approve-visual-qa
```

Literal result, exit status 0:

```text
manifest.json written; PDF, SVG, PNG, and TIFF outputs written.
automatic_qa.status=PASS
visual_qa.status=PASS
```

The standalone PNG and the rendered manuscript page 18 were inspected at original resolution. No clipping, overlap, missing legend entry, or unreadable axis label was found.

## Manuscript Build

Command, from `results/paper/Latex`:

```powershell
latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error paper_v4_final_candidate.tex
```

Literal result, exit status 0:

```text
Output written on paper_v4_final_candidate.pdf (22 pages, 1153762 bytes).
Latexmk: All targets (paper_v4_final_candidate.pdf) are up-to-date
```

Log scan result:

```text
latex_fatal_or_undefined_matches=0
```

## Artifact Hashes

```text
fig06_imu_observer_trace.pdf  29A858BD6A932F1B88D765ED6B4F6B15A4B6DB383EA0721F1076422113992E05
paper_v4_final_candidate.pdf CEBCFD51A16CFF12F3DBD3DC33D6391C56E97E0B9D45AC6046F7AD69D524E905
node51_imu_changes.patch      BA91995F2FF944380B230BDFBDA342A1E28261C998A282CC4211F9E55768DA1C
rollback_node51_imu.ps1       2EF0C0095AD3EF827206D581199D5E0B9DB88963DBB4B910E2A1B57115C6275E
```

## Rollback Readiness

Command:

```powershell
& results/paper/7.6/figures_final_1/Fig06_imu_observer_trace/revisions/node51_imu_20260731/rollback_node51_imu.ps1 -VerifyOnly
```

Literal output, exit status 0:

```text
ROLLBACK_READY
```
