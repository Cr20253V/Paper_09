[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$relativeBase = 'data\tcn\ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat'
$partsDirectory = Join-Path $RepositoryRoot ($relativeBase + '.parts')
$outputPath = Join-Path $RepositoryRoot $relativeBase
$expectedBytes = 446285336
$expectedSha256 = 'ab5dde32ef3627aa7032a3b4f7632c87cb471287a638f2b14a25a179a660196f'

$parts = @(Get-ChildItem -LiteralPath $partsDirectory -File -Filter 'part-*.bin' | Sort-Object Name)
if ($parts.Count -ne 5) {
    throw "Expected 5 dataset parts in $partsDirectory, found $($parts.Count)."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
$output = [System.IO.File]::Create($outputPath)
try {
    foreach ($part in $parts) {
        $input = [System.IO.File]::OpenRead($part.FullName)
        try {
            $input.CopyTo($output)
        }
        finally {
            $input.Dispose()
        }
    }
}
finally {
    $output.Dispose()
}

$item = Get-Item -LiteralPath $outputPath
if ($item.Length -ne $expectedBytes) {
    throw "Dataset size mismatch: expected $expectedBytes bytes, found $($item.Length)."
}

$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "Dataset SHA-256 mismatch: expected $expectedSha256, found $actualSha256."
}

Write-Output "Restored and verified: $outputPath"
