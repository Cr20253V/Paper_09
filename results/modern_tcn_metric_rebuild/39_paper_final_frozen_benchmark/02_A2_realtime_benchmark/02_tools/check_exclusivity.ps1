#requires -Version 5.1
param(
    [string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16',
    [string]$OutputJson = '',
    [int]$AllowedMatlabPid = 0
)

$ErrorActionPreference = 'Stop'
$target = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark'
if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = Join-Path $target '03_environment\exclusivity_check.json'
}

$all = Get-CimInstance Win32_Process
$allowedPids = [System.Collections.Generic.HashSet[int]]::new()
if ($AllowedMatlabPid -gt 0) {
    [void]$allowedPids.Add($AllowedMatlabPid)
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
$blocked = foreach ($p in $all) {
    $name = [string]$p.Name
    $cmd = [string]$p.CommandLine
    $reason = $null
    if ($name -match '^(matlab|simulink)\.exe$' -and -not $allowedPids.Contains([int]$p.ProcessId)) {
        $reason = 'OTHER_MATLAB_OR_SIMULINK'
    } elseif ($name -match '^python(w)?\.exe$' -and ($cmd -like "*$ProjectRoot*" -or $cmd -match 'train|fusion|modern_tcn_metric_rebuild')) {
        $reason = 'PROJECT_PYTHON_OR_EXPERIMENT'
    } elseif ($cmd -match '38_final_fusion|Node38' -and [int]$p.ProcessId -ne $PID) {
        $reason = 'NODE38_OR_FUSION'
    }
    if ($reason) {
        [pscustomobject]@{
            pid = [int]$p.ProcessId
            parent_pid = [int]$p.ParentProcessId
            name = $name
            reason = $reason
            command_line = $cmd
        }
    }
}

$result = [ordered]@{
    checked_at = (Get-Date).ToString('o')
    project_root = $ProjectRoot
    allowed_matlab_pid = $AllowedMatlabPid
    allowed_process_tree_pids = @($allowedPids)
    exclusive = (@($blocked).Count -eq 0)
    blocker_count = @($blocked).Count
    blockers = @($blocked)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding utf8
$result | ConvertTo-Json -Depth 8
if (-not $result.exclusive) { exit 3 }
