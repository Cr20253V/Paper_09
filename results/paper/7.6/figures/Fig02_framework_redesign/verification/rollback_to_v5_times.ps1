$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$archive = Join-Path $root 'archive_v5_times'
Copy-Item -LiteralPath (Join-Path $archive 'build_fig02_framework_redesign_v5_times.py') -Destination (Join-Path $root 'scripts\build_fig02_framework_redesign.py') -Force
foreach ($ext in @('svg','pdf','png')) {
  Copy-Item -LiteralPath (Join-Path $archive "fig02_framework_redesign_v5_times.$ext") -Destination (Join-Path $root "output\fig02_framework_redesign_times.$ext") -Force
  Copy-Item -LiteralPath (Join-Path $archive "fig02_framework_redesign_v5_times.$ext") -Destination (Join-Path $root "output\fig02_framework_redesign.$ext") -Force
}
Write-Output 'Rollback complete: Figure 2 v5 Times restored.'
