$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$archive = Join-Path $root 'archive_v1'
Copy-Item -LiteralPath (Join-Path $archive 'build_fig02_framework_redesign_v1.py') -Destination (Join-Path $root 'scripts\build_fig02_framework_redesign.py') -Force
Copy-Item -LiteralPath (Join-Path $archive 'fig02_framework_redesign_v1.svg') -Destination (Join-Path $root 'output\fig02_framework_redesign.svg') -Force
Copy-Item -LiteralPath (Join-Path $archive 'fig02_framework_redesign_v1.pdf') -Destination (Join-Path $root 'output\fig02_framework_redesign.pdf') -Force
Copy-Item -LiteralPath (Join-Path $archive 'fig02_framework_redesign_v1.png') -Destination (Join-Path $root 'output\fig02_framework_redesign.png') -Force
Write-Output 'Rollback complete: Figure 2 v1 restored.'
