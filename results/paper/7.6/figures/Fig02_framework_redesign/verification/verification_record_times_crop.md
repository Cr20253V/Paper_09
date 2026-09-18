# Fig. 2 right-margin crop verification

Date: 2026-08-03

## Scope

Only the PDF page boxes were changed. Figure text, vectors, fonts, labels, layout, and content streams were not modified.

## Artifacts

- Modified PDF: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times.pdf`
- Preserved manual original: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times_before_crop.pdf`
- Reapplication copy: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times_cropped.pdf`
- Crop patch: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\fig02_framework_redesign_times_crop.patch.json`
- Rollback: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\rollback_times_crop.ps1`

## Geometry and hashes

| Check | Before | After |
|---|---:|---:|
| Page box | 520 x 317 pt | 504 x 317 pt |
| Approx. left margin | 7.2 pt | 7.2 pt |
| Approx. right margin | 23.4 pt | 7.2 pt |
| SHA-256 | `510DF68A02D79199B6B8F80144798902FE6AADF2E652D92FEC780C1B490B3370` | `C409C38FBF98B6EE7B6AD6904CF5CFC1100B56542834ABE92F370B89B134E79F` |
| Content-stream SHA-256 | `97A698782C369419D6E22CB4A875528CA27BC2D4F56FDBC6E4025104BBB8366F` | `97A698782C369419D6E22CB4A875528CA27BC2D4F56FDBC6E4025104BBB8366F` |

At `\textwidth`, the effective figure-content scale increases by about 3.2% because only unused page width was removed.

## Rollback and reapplication verification

Command:

```powershell
& 'E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\rollback_times_crop.ps1'
Copy-Item -LiteralPath 'E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times_cropped.pdf' -Destination 'E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times.pdf' -Force
```

Literal result:

```text
Rollback SHA256: 510DF68A02D79199B6B8F80144798902FE6AADF2E652D92FEC780C1B490B3370
Rollback verification: PASS
Reapplied SHA256: C409C38FBF98B6EE7B6AD6904CF5CFC1100B56542834ABE92F370B89B134E79F
Final cropped-state verification: PASS
Exit status: 0
```

## Double-column LaTeX verification

The active manuscript was left untouched. A separate verification source uses:

```latex
\includegraphics[width=\textwidth]{../7.6/figures/Fig02_framework_redesign/output/fig02_framework_redesign_times.pdf}
```

Source:

`E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate_fig02_times_cropped.tex`

Commands (run from `E:\Matlab\Simulink\S-Function_16\results\paper\Latex`):

```powershell
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_times_cropped" "paper_v4_final_candidate_fig02_times_cropped.tex"
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_times_cropped" "paper_v4_final_candidate_fig02_times_cropped.tex"
```

Literal result:

```text
pdflatex pass 1 exit: 0
pdflatex pass 2 exit: 0
Output written ... (20 pages, 1190112 bytes).
Verification PDF SHA256: 2E771431BCD3CF00447DC63943E2ACF1855AAFD6E36CCDB028D08AC9AADF371D
```

Verification PDF:

`E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_times_cropped\paper_v4_final_candidate_fig02_times_cropped.pdf`
