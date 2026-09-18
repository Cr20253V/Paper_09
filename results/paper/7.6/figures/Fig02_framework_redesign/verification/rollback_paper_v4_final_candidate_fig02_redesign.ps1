$ErrorActionPreference = 'Stop'
$candidate = 'E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate_fig02_redesign.tex'
$snapshot = 'E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\source_snapshot\paper_v4_final_candidate.current_20260803_1653.tex'

if (-not (Test-Path -LiteralPath $snapshot)) { throw "Snapshot not found: $snapshot" }
Copy-Item -LiteralPath $snapshot -Destination $candidate -Force
Write-Output "RESTORED=$candidate"
Write-Output "SHA256="
Get-FileHash -Algorithm SHA256 -LiteralPath $candidate
