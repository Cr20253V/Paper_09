#requires -Version 5.1
param([string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16')

$ErrorActionPreference = 'Stop'
$target = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime'
$tools = Join-Path $target '02_tools'
$python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw "Project Python not found: $python" }
$matlab = (Get-Command matlab -ErrorAction Stop).Source

& $python (Join-Path $tools 'prepare_inventory.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$protectedSnapshot = Join-Path $target '00_protocol_lock\protected_artifact_snapshot.json'
if (Test-Path -LiteralPath $protectedSnapshot) {
    & $python (Join-Path $tools 'protected_snapshot.py') --verify
} else {
    & $python (Join-Path $tools 'protected_snapshot.py') --create
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$derived = @(
    (Join-Path $target '03_derived_models\tcn_22d_seed42_feature.onnx'),
    (Join-Path $target '03_derived_models\tcn_22d_seed42_heads.mat'),
    (Join-Path $target '03_derived_models\tcn_22d_seed42_full.onnx'),
    (Join-Path $target '03_derived_models\gru_22d_seed42_feature.onnx'),
    (Join-Path $target '03_derived_models\gru_22d_seed42_heads.mat'),
    (Join-Path $target '03_derived_models\gru_22d_seed42_full.onnx')
)
$existingCount = @($derived | Where-Object { Test-Path -LiteralPath $_ }).Count
$baseDerived = @($derived[0],$derived[1],$derived[3],$derived[4])
$baseCount = @($baseDerived | Where-Object { Test-Path -LiteralPath $_ }).Count
$featureCount = @(@($derived[0],$derived[3]) | Where-Object { Test-Path -LiteralPath $_ }).Count
$headsCount = @(@($derived[1],$derived[4]) | Where-Object { Test-Path -LiteralPath $_ }).Count
$fullCount = @(@($derived[2],$derived[5]) | Where-Object { Test-Path -LiteralPath $_ }).Count
if ($existingCount -eq 0 -or ($featureCount -eq 2 -and $headsCount -eq 0 -and $fullCount -eq 0)) {
    $expr = "addpath('$($tools.Replace("'","''"))','-begin');export_matlab_models();"
    & $matlab -singleCompThread -batch $expr
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $python (Join-Path $tools 'compose_full_onnx.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} elseif ($baseCount -eq 4 -and $existingCount -lt $derived.Count) {
    Write-Host 'Reusing complete feature/head exports and resuming full-graph composition.'
    & $python (Join-Path $tools 'compose_full_onnx.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} elseif ($existingCount -ne $derived.Count) {
    throw "Partial feature/head export detected ($existingCount/$($derived.Count)). Refusing to overwrite or guess."
} else {
    Write-Host 'Complete derived-model set already exists; keeping it unchanged.'
}

$reference = Join-Path $target '04_validation\matlab_native_reference_seed42.mat'
if (-not (Test-Path -LiteralPath $reference)) {
    $expr = "addpath('$($tools.Replace("'","''"))','-begin');export_native_reference();"
    & $matlab -singleCompThread -batch $expr
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host 'Native MATLAB reference already exists; keeping it unchanged.'
}

& $python (Join-Path $tools 'verify_equivalence.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$status = [ordered]@{
    status = 'READY_FOR_FORMAL_RUN'
    updated_at = (Get-Date).ToString('o')
    formal_timing_started = $false
    preparation_complete = $true
    equivalence_gate = 'PASS'
    existing_matlab_a2_results_modified = $false
}
$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
$receipt = [ordered]@{
    status = 'READY_FOR_FORMAL_RUN'
    prepared_at = (Get-Date).ToString('o')
    note = 'Derived export and equivalence validation complete; formal 10000-repeat timing has not started.'
    formal_run_command = "& '.\results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime\02_tools\invoke_ort_benchmark.ps1'"
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'receipt.json') -Encoding utf8
& $python (Join-Path $tools 'finalize_preparation.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'A2 unified ONNX Runtime preparation complete. Status: READY_FOR_FORMAL_RUN'
