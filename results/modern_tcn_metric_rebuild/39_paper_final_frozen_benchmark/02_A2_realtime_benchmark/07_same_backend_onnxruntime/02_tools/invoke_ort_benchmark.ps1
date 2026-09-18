#requires -Version 5.1
param([string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16')

$ErrorActionPreference = 'Stop'
$target = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark\07_same_backend_onnxruntime'
$tools = Join-Path $target '02_tools'
$python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$statusFile = Join-Path $target 'task_status.json'
. (Join-Path $tools 'process_tree_memory.ps1')
function Get-TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}
function Wait-ForChildTermination([System.Diagnostics.Process]$Process) {
    [void]$Process.WaitForExit()
    # Do not query System.Diagnostics.Process.ExitCode on this host. It is not
    # reliable here; the atomic child receipt is the success authority.
}
if (-not (Test-Path -LiteralPath $statusFile)) { throw 'Preparation status is missing. Run prepare_ort_assets.ps1 first.' }
$prepared = Get-Content -Raw -Encoding UTF8 -LiteralPath $statusFile | ConvertFrom-Json
$allowedStartStatuses = @('READY_FOR_FORMAL_RUN','FORMAL_RUN_FAILED_ATTEMPT_RETAINED')
if ($allowedStartStatuses -notcontains $prepared.status -or $prepared.equivalence_gate -ne 'PASS') {
    throw "Preparation/equivalence gate is not ready: $($prepared.status)"
}
& $python (Join-Path $tools 'protected_snapshot.py') --verify
if ($LASTEXITCODE -ne 0) { throw 'Protected-artifact verification failed before formal timing.' }

& (Join-Path $tools 'check_exclusivity.ps1') -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Formal timing not started because exclusivity preflight failed.'
    exit $LASTEXITCODE
}

$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $target ("05_formal\runs\$runId")
if (Test-Path -LiteralPath $runDir) { throw "Run directory already exists: $runDir" }
New-Item -ItemType Directory -Path $runDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runDir 'logs') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runDir 'exclusivity') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runDir 'raw_memory') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $runDir 'child_receipts') | Out-Null

$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$power = & powercfg /GETACTIVESCHEME
$gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    [ordered]@{ name = $_.Name; adapter_ram_bytes = $_.AdapterRAM; driver_version = $_.DriverVersion }
})
$stableEnvironment = [ordered]@{
    computer_model = $computer.Model
    cpu = $cpu.Name
    physical_cores = $cpu.NumberOfCores
    logical_processors = $cpu.NumberOfLogicalProcessors
    memory_bytes = [int64]$computer.TotalPhysicalMemory
    gpu = $gpu
    os = $os.Caption
    os_version = $os.Version
    power_scheme = ($power -join ' ')
    backend = 'onnxruntime CPUExecutionProvider'
    precision = 'FP32'
    intra_op_num_threads = 1
    inter_op_num_threads = 1
    execution_mode = 'ORT_SEQUENTIAL'
    graph_optimization = 'ORT_ENABLE_ALL'
    input_protocol = 'preloaded C-contiguous FP32; session.run; output allocation included'
}
$stableJson = $stableEnvironment | ConvertTo-Json -Depth 8 -Compress
$environment = [ordered]@{
    captured_at = (Get-Date).ToString('o')
    run_id = $runId
    computer_model = $computer.Model
    cpu = $cpu.Name
    physical_cores = $cpu.NumberOfCores
    logical_processors = $cpu.NumberOfLogicalProcessors
    memory_bytes = [int64]$computer.TotalPhysicalMemory
    os = $os.Caption
    os_version = $os.Version
    power_scheme = ($power -join ' ')
    gpu = $gpu
    backend = 'onnxruntime CPUExecutionProvider'
    precision = 'FP32'
    intra_op_num_threads = 1
    inter_op_num_threads = 1
    execution_mode = 'ORT_SEQUENTIAL'
    graph_optimization = 'ORT_ENABLE_ALL'
    environment_sha256 = Get-TextSha256 $stableJson
    stable_environment = $stableEnvironment
}
$environment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'environment.json') -Encoding utf8
[ordered]@{ status='FORMAL_RUN_IN_PROGRESS'; updated_at=(Get-Date).ToString('o'); formal_timing_started=$true; preparation_complete=$true; equivalence_gate='PASS'; active_run=$runId; existing_matlab_a2_results_modified=$false } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusFile -Encoding utf8

$env:OMP_NUM_THREADS = '1'
$env:MKL_NUM_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
$env:NUMEXPR_NUM_THREADS = '1'
$env:ORT_NUM_THREADS = '1'
$env:A2_ORT_EXCLUSIVE_TOKEN = [guid]::NewGuid().ToString('N')
$methods = @('modern_tcn_22d','gru_22d','tcn_22d','modern_tcn_delta_bank_124')

try {
foreach ($method in $methods) {
    $preflight = Join-Path $runDir ("exclusivity\pre_$method.json")
    & (Join-Path $tools 'check_exclusivity.ps1') -ProjectRoot $ProjectRoot -OutputJson $preflight | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Exclusivity failed before $method" }
    $stdout = Join-Path $runDir ("logs\$method.stdout.log")
    $stderr = Join-Path $runDir ("logs\$method.stderr.log")
    $arguments = @((Join-Path $tools 'benchmark_ort.py'),'--method',$method,'--run-dir',$runDir,'--formal')
    $process = Start-Process -FilePath $python -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $benchmarkProcess = $null
    $discoveryDeadline = (Get-Date).AddSeconds(10)
    while ($null -eq $benchmarkProcess -and -not $process.HasExited -and (Get-Date) -lt $discoveryDeadline) {
        $benchmarkProcess = Find-A2BenchmarkPythonProcess -RootPid $process.Id
        if ($null -eq $benchmarkProcess) { Start-Sleep -Milliseconds 25 }
    }
    if ($null -eq $benchmarkProcess) {
        throw "Could not resolve the real benchmark Python descendant below launcher PID $($process.Id)."
    }
    $benchmarkProcessId = [int]$benchmarkProcess.ProcessId
    $interference = $false
    $tick = 0
    $memory = [System.Collections.Generic.List[object]]::new()
    while (-not $process.HasExited) {
        [void](Add-A2ProcessMemorySample -Samples $memory -ProcessId $benchmarkProcessId)
        if (($tick % 4) -eq 0) {
            $watch = Join-Path $runDir ("exclusivity\watch_${method}_$tick.json")
            & (Join-Path $tools 'check_exclusivity.ps1') -ProjectRoot $ProjectRoot -OutputJson $watch -AllowedRootPid $process.Id | Out-Null
            if ($LASTEXITCODE -ne 0) { $interference = $true; break }
        }
        Start-Sleep -Milliseconds 250
        $tick++
    }
    if ($interference -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit()
        $interruptedMemoryFile = Join-Path $runDir ("raw_memory\$method.interrupted.csv")
        $memory | Export-Csv -LiteralPath $interruptedMemoryFile -NoTypeInformation -Encoding utf8
        throw "Interference detected during $method; its incomplete run is retained in $runDir"
    }
    Wait-ForChildTermination -Process $process
    $observedExitCode = 'NOT_QUERIED_UNRELIABLE_ON_HOST'
    $memoryFile = Join-Path $runDir ("raw_memory\$method.csv")
    $memory | Export-Csv -LiteralPath $memoryFile -NoTypeInformation -Encoding utf8
    $caseFile = Join-Path $runDir ("cases\core_inference__$method.json")
    $rawFile = Join-Path $runDir ("raw_timing\core_inference__$method.csv")
    $childReceiptFile = Join-Path $runDir ("child_receipts\core_inference__$method.json")
    if (-not (Test-Path -LiteralPath $childReceiptFile)) {
        $stderrText = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -Encoding UTF8 -LiteralPath $stderr } else { '' }
        throw "Child did not publish its atomic success receipt for $method. Observed exit code=$observedExitCode. stderr=$stderrText"
    }
    $childReceipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $childReceiptFile | ConvertFrom-Json
    if ($childReceipt.status -ne 'CHILD_COMPLETE' -or $childReceipt.method_id -ne $method -or
        -not $childReceipt.formal -or $childReceipt.warmup_count -ne 500 -or
        $childReceipt.formal_count -ne 10000 -or $childReceipt.raw_rows -ne 10000 -or
        $childReceipt.completion_protocol -ne 'atomic_child_receipt_v1') {
        throw "Invalid atomic child receipt for $method"
    }
    if ([int]$childReceipt.child_pid -ne $benchmarkProcessId) {
        throw "External memory PID does not match child receipt for $method`: sampled=$benchmarkProcessId receipt=$($childReceipt.child_pid)"
    }
    if (-not (Test-Path -LiteralPath $caseFile)) { throw "Child receipt exists but case JSON is missing: $caseFile" }
    if (-not (Test-Path -LiteralPath $rawFile)) { throw "Child receipt exists but raw timing CSV is missing: $rawFile" }
    if ([IO.Path]::GetFullPath([string]$childReceipt.case_file) -ne [IO.Path]::GetFullPath($caseFile) -or
        [IO.Path]::GetFullPath([string]$childReceipt.raw_timing_file) -ne [IO.Path]::GetFullPath($rawFile)) {
        throw "Child receipt output path mismatch for $method"
    }
    $actualRawSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $rawFile).Hash.ToLowerInvariant()
    if ($actualRawSha -ne $childReceipt.raw_timing_sha256) { throw "Raw timing SHA256 mismatch for $method" }
    $actualCaseShaBeforeAugmentation = (Get-FileHash -Algorithm SHA256 -LiteralPath $caseFile).Hash.ToLowerInvariant()
    if ($actualCaseShaBeforeAugmentation -ne $childReceipt.case_sha256_before_monitor_augmentation) {
        throw "Pre-monitor case SHA256 mismatch for $method"
    }
    $rawRows = (Get-Content -LiteralPath $rawFile | Measure-Object -Line).Lines - 1
    if ($rawRows -ne 10000) { throw "Raw timing row count mismatch for $method`: $rawRows" }
    $stderrText = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -Encoding UTF8 -LiteralPath $stderr } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) { throw "Child stderr is non-empty for $method`: $stderrText" }
    $case = Get-Content -Raw -Encoding UTF8 -LiteralPath $caseFile | ConvertFrom-Json
    if ($case.case_status -ne 'COMPLETE' -or -not $case.formal -or $case.warmup_count -ne 500 -or $case.formal_count -ne 10000) {
        throw "Case protocol metadata is incomplete for $method"
    }
    if ($case.environment_sha256 -ne $environment.environment_sha256) {
        throw "Environment hash mismatch for $method"
    }
    if ($childReceipt.environment_sha256 -ne $environment.environment_sha256 -or
        $childReceipt.model_sha256 -ne $case.model_sha256 -or
        $childReceipt.authority_model_sha256 -ne $case.authority_model_sha256) {
        throw "Child receipt provenance mismatch for $method"
    }
    if ($memory.Count -gt 0) {
        $case | Add-Member -NotePropertyName external_peak_working_set_bytes -NotePropertyValue (($memory | Measure-Object working_set_bytes -Maximum).Maximum) -Force
        $case | Add-Member -NotePropertyName external_peak_private_bytes -NotePropertyValue (($memory | Measure-Object private_bytes -Maximum).Maximum) -Force
    }
    $case | Add-Member -NotePropertyName external_memory_pid -NotePropertyValue $benchmarkProcessId -Force
    $case | Add-Member -NotePropertyName external_memory_pid_matches_child_receipt -NotePropertyValue $true -Force
    $case | Add-Member -NotePropertyName raw_memory_file -NotePropertyValue $memoryFile -Force
    $case | Add-Member -NotePropertyName child_receipt_file -NotePropertyValue $childReceiptFile -Force
    $case | Add-Member -NotePropertyName child_case_sha256_before_monitor_augmentation -NotePropertyValue $actualCaseShaBeforeAugmentation -Force
    $case | Add-Member -NotePropertyName observed_process_exit_code -NotePropertyValue $observedExitCode -Force
    $case | Add-Member -NotePropertyName success_authority -NotePropertyValue 'atomic_child_receipt_plus_artifact_validation' -Force
    $case | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $caseFile -Encoding utf8
}

& $python (Join-Path $tools 'validate_formal_run.py') --run-dir $runDir
if ($LASTEXITCODE -ne 0) { throw "Final formal-run validation failed with exit code $LASTEXITCODE" }
& $python (Join-Path $tools 'protected_snapshot.py') --verify
if ($LASTEXITCODE -ne 0) { throw 'Protected-artifact verification failed after formal timing.' }
[ordered]@{ latest_completed_run = $runId; path = $runDir; updated_at = (Get-Date).ToString('o') } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $target '06_summary\latest_completed_run.json') -Encoding utf8
$finishedAt = (Get-Date).ToString('o')
[ordered]@{ status='FORMAL_RUN_COMPLETE'; updated_at=$finishedAt; formal_timing_started=$true; preparation_complete=$true; equivalence_gate='PASS'; latest_completed_run=$runId; existing_matlab_a2_results_modified=$false } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusFile -Encoding utf8
[ordered]@{ status='FORMAL_RUN_COMPLETE'; completed_at=$finishedAt; latest_completed_run=$runId; run_directory=$runDir; note='Unified ONNX Runtime supplemental benchmark; original MATLAB A2 retained.' } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'receipt.json') -Encoding utf8
& $python (Join-Path $tools 'finalize_preparation.py')
if ($LASTEXITCODE -ne 0) { throw "Root artifact-manifest finalization failed with exit code $LASTEXITCODE" }
Write-Host "FORMAL_RUN_COMPLETE: $runDir"
} catch {
    $failedAt = (Get-Date).ToString('o')
    $failure = [ordered]@{
        status = 'FORMAL_RUN_FAILED_ATTEMPT_RETAINED'
        failed_at = $failedAt
        run_id = $runId
        run_directory = $runDir
        active_method = $method
        error = $_.Exception.Message
        completed_case_files = @((Get-ChildItem -LiteralPath (Join-Path $runDir 'cases') -Filter '*.json' -ErrorAction SilentlyContinue).Name)
        completed_child_receipts = @((Get-ChildItem -LiteralPath (Join-Path $runDir 'child_receipts') -Filter '*.json' -ErrorAction SilentlyContinue).Name)
        note = 'This timestamped attempt is retained and is not eligible for formal summary unless all four cases and final validation complete.'
    }
    $failure | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'failure_receipt.json') -Encoding utf8
    $failure | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'task_status.json') -Encoding utf8
    [ordered]@{ status='FORMAL_RUN_FAILED_ATTEMPT_RETAINED'; updated_at=$failedAt; formal_timing_started=$true; preparation_complete=$true; equivalence_gate='PASS'; latest_failed_run=$runId; existing_matlab_a2_results_modified=$false } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusFile -Encoding utf8
    [ordered]@{ status='FORMAL_RUN_FAILED_ATTEMPT_RETAINED'; failed_at=$failedAt; latest_failed_run=$runId; run_directory=$runDir; error=$_.Exception.Message; note='Original MATLAB A2 retained; rerun creates a new timestamped directory.' } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'receipt.json') -Encoding utf8
    throw
}
