$ErrorActionPreference = 'Stop'

$project = 'E:\Matlab\Simulink\S-Function_16'
$target = Join-Path $project 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison'
$tools = Join-Path $target '01_tools'
$matlab = 'D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe'
$stateFile = Join-Path $target 'logs\managed_chain_status.json'
$consoleLog = Join-Path $target 'logs\managed_chain_console.log'
$errorLog = Join-Path $target 'logs\managed_chain_error.log'

function Write-State([string]$stage, [string]$status, [string]$message = '') {
    $payload = [ordered]@{
        task_id = 'A1_algorithm_comparison'
        updated_at = (Get-Date).ToString('o')
        process_id = $PID
        stage = $stage
        status = $status
        message = $message
        starts_formal_closed_loop = $false
    }
    [System.IO.File]::WriteAllText($stateFile, ($payload | ConvertTo-Json -Depth 4) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Logged([string]$label, [scriptblock]$command, [int[]]$acceptable = @(0)) {
    Add-Content -LiteralPath $consoleLog -Value "[$((Get-Date).ToString('o'))] START $label"
    & $command *>> $consoleLog
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $consoleLog -Value "[$((Get-Date).ToString('o'))] END $label exit=$code"
    if ($code -notin $acceptable) {
        throw "$label failed with exit $code"
    }
}

Set-Location -LiteralPath $project
New-Item -ItemType Directory -Path (Join-Path $target 'logs') -Force | Out-Null
Write-State 'TCN_TRAINING' 'RUNNING' 'Frozen seven-seed TCN training; successful seeds are schema-checked and reused.'

try {
    Invoke-Logged 'train_missing_tcn' {
        & $matlab -batch "addpath(fullfile(pwd,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','01_A1_algorithm_comparison','01_tools')); run_A1_train_missing_tcn;"
    }

    Write-State 'REFRESH_INVENTORY' 'RUNNING'
    Invoke-Logged 'refresh_inventory' { python (Join-Path $tools 'build_a1_inventory.py') }

    Write-State 'OFFLINE_TCN' 'RUNNING' 'Only missing MATLAB-native offline cases are evaluated.'
    Invoke-Logged 'offline_matlab' {
        & $matlab -batch "addpath(fullfile(pwd,'results','modern_tcn_metric_rebuild','39_paper_final_frozen_benchmark','01_A1_algorithm_comparison','01_tools')); run_A1_offline_matlab;"
    }

    Write-State 'OFFLINE_FINALIZE' 'RUNNING'
    Invoke-Logged 'finalize_offline' { python (Join-Path $tools 'finalize_A1_offline.py') }

    Write-State 'PROVISIONAL_FINALIZE' 'RUNNING'
    Invoke-Logged 'finalize_provisional' { python (Join-Path $tools 'finalize_A1.py') } @(0, 4)
    Write-State 'READY_FOR_MANUAL_CLOSED_LOOP' 'COMPLETE' 'No formal closed-loop case was started by this chain.'
}
catch {
    $detail = $_ | Out-String
    Add-Content -LiteralPath $errorLog -Value "[$((Get-Date).ToString('o'))] $detail"
    Write-State 'FAILED' 'FAILED' $detail.Trim()
    exit 1
}
