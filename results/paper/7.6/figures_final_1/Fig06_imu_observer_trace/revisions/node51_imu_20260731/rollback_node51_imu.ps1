param(
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.Parent.Parent.Parent.FullName
$baseline = Join-Path $PSScriptRoot "baseline"
$figureRoot = Join-Path $projectRoot "results/paper/7.6/figures_final_1/Fig06_imu_observer_trace"
$latexRoot = Join-Path $projectRoot "results/paper/Latex"

$required = @(
    (Join-Path $baseline "generate_fig06_imu_observer_trace.py"),
    (Join-Path $baseline "fig06_imu_observer_trace.pdf"),
    (Join-Path $baseline "paper_v4_final_candidate.tex"),
    (Join-Path $baseline "paper_v4_final_candidate.pdf")
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    throw "Missing rollback input(s): $($missing -join ', ')"
}

if ($VerifyOnly) {
    Write-Output "ROLLBACK_READY"
    Get-FileHash -LiteralPath $required -Algorithm SHA256 | Select-Object Path, Hash
    exit 0
}

Copy-Item -LiteralPath (Join-Path $baseline "generate_fig06_imu_observer_trace.py") `
    -Destination (Join-Path $figureRoot "scripts/generate_fig06_imu_observer_trace.py") -Force
Copy-Item -LiteralPath (Join-Path $baseline "paper_v4_final_candidate.tex") `
    -Destination (Join-Path $latexRoot "paper_v4_final_candidate.tex") -Force

Push-Location $figureRoot
try {
    & python "scripts/generate_fig06_imu_observer_trace.py" --approve-visual-qa
    if ($LASTEXITCODE -ne 0) { throw "Figure regeneration failed with exit $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Push-Location $latexRoot
try {
    & latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error `
        "paper_v4_final_candidate.tex"
    if ($LASTEXITCODE -ne 0) { throw "LaTeX rebuild failed with exit $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Copy-Item -LiteralPath (Join-Path $baseline "fig06_imu_observer_trace.pdf") `
    -Destination (Join-Path $figureRoot "output/fig06_imu_observer_trace.pdf") -Force
Copy-Item -LiteralPath (Join-Path $baseline "paper_v4_final_candidate.pdf") `
    -Destination (Join-Path $latexRoot "paper_v4_final_candidate.pdf") -Force

Write-Output "ROLLBACK_COMPLETE"
