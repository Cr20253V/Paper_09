$ErrorActionPreference = 'Stop'

$outputDir = 'E:\Matlab\Simulink\S-Function_16\results\paper\7.6\figures\Fig02_framework_redesign\output'
$backup = Join-Path $outputDir 'fig02_framework_redesign_times_before_crop.pdf'
$target = Join-Path $outputDir 'fig02_framework_redesign_times.pdf'

if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
    throw "Backup PDF not found: $backup"
}

Copy-Item -LiteralPath $backup -Destination $target -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
Write-Output "Restored: $target"
Write-Output "SHA256: $hash"
