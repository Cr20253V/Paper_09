#requires -Version 5.1
param(
    [string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16',
    [string]$OutputJson = '',
    [int]$AllowedRootPid = 0
)

$ErrorActionPreference = 'Stop'
$target = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime'
if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = Join-Path $target '03_environment\exclusivity_check.json'
}
$parent = Split-Path -Parent $OutputJson
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

$all = @(Get-CimInstance Win32_Process)
$allowedPids = [System.Collections.Generic.HashSet[int]]::new()
if ($AllowedRootPid -gt 0) {
    [void]$allowedPids.Add($AllowedRootPid)
    do {
        $changed = $false
        foreach ($candidate in $all) {
            if ($allowedPids.Contains([int]$candidate.ParentProcessId) -and -not $allowedPids.Contains([int]$candidate.ProcessId)) {
                [void]$allowedPids.Add([int]$candidate.ProcessId)
                $changed = $true
            }
        }
    } while ($changed)
}

$blocked = foreach ($process in $all) {
    if ($allowedPids.Contains([int]$process.ProcessId)) { continue }
    $name = [string]$process.Name
    $command = [string]$process.CommandLine
    $reason = $null
    if ($name -match '^(matlab|simulink)\.exe$') {
        $reason = 'OTHER_MATLAB_OR_SIMULINK'
    } elseif ($name -match '^python(w)?\.exe$' -and ($command -like "*$ProjectRoot*" -or $command -match 'train|fusion|modern_tcn_metric_rebuild|benchmark_ort')) {
        $reason = 'PROJECT_PYTHON_OR_EXPERIMENT'
    } elseif ($command -match '38_final_fusion|Node38') {
        $reason = 'NODE38_OR_FUSION'
    }
    if ($reason) {
        [pscustomobject]@{
            pid = [int]$process.ProcessId
            parent_pid = [int]$process.ParentProcessId
            name = $name
            reason = $reason
            command_line = $command
        }
    }
}

$result = [ordered]@{
    checked_at = (Get-Date).ToString('o')
    project_root = $ProjectRoot
    allowed_root_pid = $AllowedRootPid
    allowed_process_tree_pids = @($allowedPids)
    exclusive = (@($blocked).Count -eq 0)
    blocker_count = @($blocked).Count
    blockers = @($blocked)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding utf8
$result | ConvertTo-Json -Depth 8
if (-not $result.exclusive) { exit 3 }

