$ErrorActionPreference = 'Stop'

$baseline = 'E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate_before_fig02_redesign_20260803.tex'
$target = 'E:\Matlab\Simulink\S-Function_16\results\paper\Latex\paper_v4_final_candidate.tex'

if (-not (Test-Path -LiteralPath $baseline -PathType Leaf)) {
    throw "Baseline TeX not found: $baseline"
}

Copy-Item -LiteralPath $baseline -Destination $target -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
Write-Output "Restored: $target"
Write-Output "SHA256: $hash"
