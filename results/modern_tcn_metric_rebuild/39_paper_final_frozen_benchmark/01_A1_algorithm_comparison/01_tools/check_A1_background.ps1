$target = 'E:\Matlab\Simulink\S-Function_16\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison'
$stateFile = Join-Path $target 'logs\managed_chain_status.json'
$receiptFile = Join-Path $target '02_models\tcn_training_receipt.json'
$taskStatusFile = Join-Path $target 'task_status.json'

$state = if (Test-Path $stateFile) { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } else { $null }
$pidAlive = $false
if ($null -ne $state -and $null -ne $state.process_id) {
    $pidAlive = $null -ne (Get-Process -Id ([int]$state.process_id) -ErrorAction SilentlyContinue)
}
$trainingComplete = $false
if (Test-Path $receiptFile) {
    try { $trainingComplete = [bool]((Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json).complete) } catch {}
}
$modelCount = @(Get-ChildItem -LiteralPath (Join-Path $target '02_models\models') -Filter 'TCN_model_a1_tcn*.mat' -ErrorAction SilentlyContinue).Count
$offlineCount = @(Get-ChildItem -LiteralPath (Join-Path $target '03_offline\raw') -Filter '*_predictions.csv' -ErrorAction SilentlyContinue).Count
$taskStatus = if (Test-Path $taskStatusFile) { (Get-Content -LiteralPath $taskStatusFile -Raw | ConvertFrom-Json).status } else { 'MISSING' }

if ($trainingComplete -and $offlineCount -eq 40 -and $taskStatus -in @('READY_FOR_MANUAL_CLOSED_LOOP','COMPLETE')) {
    $verdict = 'COMPLETE_OR_READY_FOR_MANUAL_CLOSED_LOOP'; $exitCode = 0
} elseif ($pidAlive) {
    $verdict = 'RUNNING'; $exitCode = 10
} elseif ($null -ne $state -and $state.status -eq 'FAILED') {
    $verdict = 'FAILED'; $exitCode = 20
} else {
    $verdict = 'INTERRUPTED_OR_INCOMPLETE'; $exitCode = 20
}

[pscustomobject]@{
    verdict = $verdict
    manager_pid = if ($null -ne $state) { $state.process_id } else { $null }
    process_alive = $pidAlive
    managed_stage = if ($null -ne $state) { $state.stage } else { 'MISSING' }
    managed_status = if ($null -ne $state) { $state.status } else { 'MISSING' }
    training_receipt_complete = $trainingComplete
    new_tcn_models = $modelCount
    offline_cases = $offlineCount
    task_status = $taskStatus
    state_file = $stateFile
    training_log = (Join-Path $target 'logs\tcn_missing_7seed_train.log')
} | Format-List

exit $exitCode
