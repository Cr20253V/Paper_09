$ErrorActionPreference = 'Stop'

$project = 'E:\Matlab\Simulink\S-Function_16'
$target = Join-Path $project 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison'
$tools = Join-Path $target '01_tools'
$matlab = 'D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe'

Set-Location -LiteralPath $project

$active = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^MATLAB' -and $_.CommandLine -like '*run_A1_train_missing_tcn*'
}
if ($active) {
    $ids = ($active.ProcessId -join ', ')
    throw "An A1 TCN training process is already active (PID: $ids). Refusing to start a duplicate."
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'A1 STEP 1/5: frozen TCN training (7 missing seeds)' -ForegroundColor Cyan
Write-Host 'Completed model+meta pairs are verified and skipped on rerun.'
Write-Host '============================================================' -ForegroundColor Cyan
& $matlab -batch "cd('$($project.Replace('\','/'))'); addpath('$($tools.Replace('\','/'))'); run_A1_train_missing_tcn;"
if ($LASTEXITCODE -ne 0) { throw "TCN training MATLAB exited with $LASTEXITCODE" }

Write-Host 'A1 STEP 2/5: refresh model and artifact registry' -ForegroundColor Cyan
python (Join-Path $tools 'build_a1_inventory.py')
if ($LASTEXITCODE -ne 0) { throw "Inventory refresh exited with $LASTEXITCODE" }

Write-Host 'A1 STEP 3/5: MATLAB-native offline inference (missing cases only)' -ForegroundColor Cyan
& $matlab -batch "cd('$($project.Replace('\','/'))'); addpath('$($tools.Replace('\','/'))'); run_A1_offline_matlab;"
if ($LASTEXITCODE -ne 0) { throw "MATLAB offline evaluation exited with $LASTEXITCODE" }

Write-Host 'A1 STEP 4/5: common offline metrics and frozen bootstrap' -ForegroundColor Cyan
python (Join-Path $tools 'finalize_A1_offline.py')
if ($LASTEXITCODE -ne 0) { throw "Offline finalizer exited with $LASTEXITCODE; inspect offline_missing_after_eval.csv" }

Write-Host 'A1 STEP 5/5: provisional grid audit and manual-loop handoff' -ForegroundColor Cyan
python (Join-Path $tools 'finalize_A1.py')
$finalCode = $LASTEXITCODE
if ($finalCode -notin @(0, 4)) { throw "A1 finalizer exited with unexpected code $finalCode" }

Write-Host '============================================================' -ForegroundColor Green
Write-Host 'Training and all 40 offline cases are complete.' -ForegroundColor Green
Write-Host 'Expected next state: READY_FOR_MANUAL_CLOSED_LOOP' -ForegroundColor Green
Write-Host "Runbook: $target\MANUAL_RUNBOOK.md"
Write-Host '============================================================' -ForegroundColor Green
