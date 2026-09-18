# Paper Figure 2 replacement verification

Date: 2026-08-03

## Decision

The redesigned flowchart is suitable for direct use as Figure 2 in the two-column manuscript. The figure label and numbering remain unchanged (`fig:overall_framework`).

## Changes applied

1. Replaced the former Figure 2 source with:
   `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output\fig02_framework_redesign_times.pdf`
2. Rewrote the caption because the old caption referred to obsolete stage-band headers and did not describe the LPV database, grade-conditioning stage, or the signal-path legend shown in the redesigned figure.
3. Changed the adjacent wording from “a single fused grade” to “a single conditioned fused grade” so that `$\theta_k^{\mathrm{sch}}$` is distinguished from the pre-conditioning fusion output.
4. No other manuscript content was changed.

## Consistency checks

- `102` continuous runs: confirmed in the experimental settings and dataset-construction algorithm.
- `22-D` base feature bank and `88-D` delta-augmented input: confirmed in the method and experimental settings.
- `4125` LPV local models: confirmed as `11 x 15 x 25` in the LPV database description.
- Qualified observer, uncertainty-adaptive fusion, grade conditioning, scheduled model/disturbance/equivalent-force/weights/bounds, reference path, and AGV feedback: consistent with the surrounding method text.
- Figure appears as `FIGURE 2` in the compiled manuscript.

## Compile verification

Commands, run twice from `E:\Matlab\Simulink\S-Function_16\results\paper\Latex`:

```powershell
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_manuscript_fig02_replaced" "paper_v4_final_candidate.tex"
```

Result:

```text
pdflatex pass 1 exit: 0
pdflatex pass 2 exit: 0
pages=20
bytes=1200191
sha256=E1D4DA2A782445A99C3AC24939D2183460D22557C2C92B7FFD524DA015EF8F29
Figure 2 page: 6
```

The page-6 render shows no clipping, overlap, or abnormal right margin.

## Artifacts and rollback

- Modified manuscript: `E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate.tex`
- Baseline backup: `E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate_before_fig02_redesign_20260803.tex`
- Exact patch: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\paper_v4_final_candidate_fig02_replacement.patch`
- Verification PDF: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_manuscript_fig02_replaced\paper_v4_final_candidate.pdf`
- Page-6 preview: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\compile_manuscript_fig02_replaced\fig02_page.png`
- Rollback script: `E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\verification\rollback_paper_fig02_replacement.ps1`

Rollback and reapplication were both executed successfully. The final active-manuscript SHA-256 is:

`8EEEEE471C5AA024E7F82FBC87F8974C79D33A49F7C8660F8DDCFD28A69A99AA`
