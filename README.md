# Paper_09 IEEE Access Backup

This repository is the revision backup for the IEEE Access manuscript:

`Slope-Aware LPV-MPC Path Tracking of a Dual-Steering-Wheel AGV with Time-Lag-Enhanced ModernTCN Perception`

The authoritative manuscript is under `results/paper/paper_8.8/`. The matching
portable submission source is under `results/paper/paper_submission_portable/`.

## Contents

- Final 21-page IEEE Access LaTeX source, PDF, figures, bibliography, and ZIP.
- Figure source data, generation scripts, manifests, and QA records from `results/paper/7.6/`.
- Node39 frozen A1-A5 evidence: protocols, scripts, model exports, case CSV/JSON,
  statistical summaries, and reports.
- Node53 V7 evidence for all 60 formal route-seed fusion cases, without duplicate
  retry folders or redundant MAT runtime dumps.
- Frozen model registry artifacts, six route inputs, LPV database, MPC maps/cache,
  Simulink models, and relevant source code.
- The exact 446,285,336-byte training dataset, split into five Git-safe parts.
- `SHA256SUMS.csv`, generated over every backed-up file.

## Restore The Dataset

From PowerShell at the repository root:

```powershell
.\scripts\restore_dataset.ps1
```

The script reconstructs the MAT file and verifies SHA-256
`ab5dde32ef3627aa7032a3b4f7632c87cb471287a638f2b14a25a179a660196f`.

## Revision Context

Read `docs/PAPER_09_BACKUP_CONTEXT.md` before editing the manuscript or drafting
the reviewer response. It records the authoritative version, evidence nodes,
headline results, statistical units, and claims that must remain bounded.

## Reviewer Decision And Revision Workspace

The IEEE Access decision email dated 2026-09-15, the reviewer attachment,
official resubmission templates, and the verified Chinese revision guide are
stored under:

`results/paper/Access-2026-39730_返稿修改_20260915/`

The original materials are preserved without modification. Future response
letters, revised manuscripts, and supplementary experiments should be added to
the numbered subdirectories in that workspace. See its `README.md` and
`REVISION_MATERIALS_SHA256.csv` before editing.

## Deliberate Omissions

The backup excludes regenerable TIFF exports, Python bytecode, LaTeX temporary
files, Simulink cache products, redundant `attempts` copies, and bulky MAT runtime
dumps duplicated by retained CSV traces. These are not unique sources for any
reported paper value. The retained manifests preserve their original checksums.
