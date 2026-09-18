#requires -Version 5.1
param([string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16')

$ErrorActionPreference='Stop'
$target=Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark'
$tools=Join-Path $target '02_tools'
$matlab='D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe'

function Stop-A2ProcessTree([int]$RootPid){
    try{
        $all=Get-CimInstance Win32_Process
        $ids=[System.Collections.Generic.HashSet[int]]::new(); [void]$ids.Add($RootPid)
        do{
            $changed=$false
            foreach($candidate in $all){
                if($ids.Contains([int]$candidate.ParentProcessId) -and -not $ids.Contains([int]$candidate.ProcessId)){
                    [void]$ids.Add([int]$candidate.ProcessId); $changed=$true
                }
            }
        }while($changed)
        foreach($id in @($ids)){Stop-Process -Id $id -Force -ErrorAction SilentlyContinue}
    }catch{
        Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
    }
}

& (Join-Path $tools 'prepare_a2.ps1') -ProjectRoot $ProjectRoot
if($LASTEXITCODE -ne 0){
    $prepareExitCode=$LASTEXITCODE
    Write-Host 'Formal timing not started because exclusivity preflight failed.'
    $statusFile=Join-Path $target 'task_status.json'
    if(Test-Path -LiteralPath $statusFile){
        $blockedStatus=Get-Content -Raw -Encoding UTF8 -LiteralPath $statusFile | ConvertFrom-Json
        foreach($blocker in @($blockedStatus.blockers)){
            Write-Host ("  PID={0} NAME={1} REASON={2}" -f $blocker.pid,$blocker.name,$blocker.reason)
            Write-Host ("  CMD={0}" -f $blocker.command_line)
        }
    }
    exit $prepareExitCode
}

$env:OMP_NUM_THREADS='1'; $env:MKL_NUM_THREADS='1'; $env:OPENBLAS_NUM_THREADS='1'; $env:NUMEXPR_NUM_THREADS='1'
$env:A2_EXCLUSIVE_TOKEN=[guid]::NewGuid().ToString('N')
$cases=(Import-Csv -LiteralPath (Join-Path $target '01_inventory\planned_run_matrix.csv') | Where-Object {$_.phase -eq '1'}).case_id
$environmentHash=(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target '03_environment\environment_manifest.json') | ConvertFrom-Json).environment_sha256

foreach($caseId in $cases){
    $caseFile=Join-Path $target ("04_phase1\cases\{0}.json" -f $caseId)
    $rawTimingFile=Join-Path $target ("04_phase1\raw_timing\{0}.csv" -f $caseId)
    if((Test-Path -LiteralPath $caseFile) -and (Test-Path -LiteralPath $rawTimingFile)){
        $existing=Get-Content -Raw -Encoding UTF8 -LiteralPath $caseFile | ConvertFrom-Json
        $rawRows=(Get-Content -LiteralPath $rawTimingFile | Measure-Object -Line).Lines-1
        if($existing.case_status -eq 'COMPLETE' -and $existing.formal_count -eq 10000 -and $existing.environment_sha256 -eq $environmentHash -and $rawRows -eq 10000){
            Write-Host "Skipping already completed case: $caseId"
            continue
        }
    }

    $priorFiles=@(
        (Join-Path $target ("04_phase1\logs\{0}.stdout.log" -f $caseId)),
        (Join-Path $target ("04_phase1\logs\{0}.stderr.log" -f $caseId)),
        (Join-Path $target ("04_phase1\raw_memory\{0}.csv" -f $caseId)),
        (Join-Path $target ("03_environment\preflight_{0}.json" -f $caseId)),
        (Join-Path $target ("03_environment\watch_{0}.json" -f $caseId)),
        (Join-Path $target ("03_environment\exclusivity_watch_{0}.csv" -f $caseId)),
        $rawTimingFile,
        $caseFile
    ) | Where-Object {Test-Path -LiteralPath $_}
    if($priorFiles.Count -gt 0){
        # Keep the directory name short. The A2 root is already long and appending the
        # full case ID plus the original filename exceeds legacy Windows MAX_PATH.
        $attemptToken="{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,6))
        $attemptDir=Join-Path $target ("04_phase1\attempt_history\{0}" -f $attemptToken)
        New-Item -ItemType Directory -Force -Path $attemptDir | Out-Null
        [ordered]@{
            archived_at=(Get-Date).ToString('o')
            case_id=$caseId
            reason='INCOMPLETE_PRIOR_ATTEMPT'
            source_files=@($priorFiles)
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $attemptDir 'attempt_metadata.json') -Encoding utf8
        foreach($prior in $priorFiles){
            $destination=Join-Path $attemptDir (Split-Path -Leaf $prior)
            if($destination.Length -ge 248){throw "Archive destination remains too long ($($destination.Length)): $destination"}
            Move-Item -LiteralPath $prior -Destination $destination
        }
    }

    $preflight=Join-Path $target ("03_environment\preflight_{0}.json" -f $caseId)
    & (Join-Path $tools 'check_exclusivity.ps1') -ProjectRoot $ProjectRoot -OutputJson $preflight
    if($LASTEXITCODE -ne 0){
        $status=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target 'task_status.json') | ConvertFrom-Json
        $status.status='BLOCKED_EXCLUSIVITY'; $status.updated_at=(Get-Date).ToString('o'); $status.formal_timing_started=$false
        $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
        exit 3
    }

    $stdout=Join-Path $target ("04_phase1\logs\{0}.stdout.log" -f $caseId)
    $stderr=Join-Path $target ("04_phase1\logs\{0}.stderr.log" -f $caseId)
    # Start-Process joins ArgumentList with spaces; keep the -batch expression as one token.
    $batch="addpath('$($tools.Replace("'","''"))','-begin');run_a2_benchmark('$caseId','formal');"
    $proc=Start-Process -FilePath $matlab -ArgumentList @('-singleCompThread','-batch',$batch) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $status=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target 'task_status.json') | ConvertFrom-Json
    $status.status='FORMAL_RUN_IN_PROGRESS'; $status.updated_at=(Get-Date).ToString('o'); $status.formal_timing_started=$true
    $status | Add-Member -NotePropertyName active_case -NotePropertyValue $caseId -Force
    $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
    $memory=[System.Collections.Generic.List[object]]::new(); $watchRows=[System.Collections.Generic.List[object]]::new(); $interference=$false; $tick=0
    $monitoredPids=@($proc.Id)
    while(-not $proc.HasExited){
        try{
            $treeProcesses=@($monitoredPids | ForEach-Object {Get-Process -Id $_ -ErrorAction SilentlyContinue})
            if($treeProcesses.Count -gt 0){
                $workingSet=($treeProcesses | Measure-Object WorkingSet64 -Sum).Sum
                $privateBytes=($treeProcesses | Measure-Object PrivateMemorySize64 -Sum).Sum
                $pagedBytes=($treeProcesses | Measure-Object PagedMemorySize64 -Sum).Sum
                $memory.Add([pscustomobject]@{
                    timestamp=(Get-Date).ToString('o')
                    root_pid=$proc.Id
                    process_tree_pids=($treeProcesses.Id -join ';')
                    process_count=$treeProcesses.Count
                    working_set_bytes=$workingSet
                    private_bytes=$privateBytes
                    peak_working_set_bytes=$workingSet
                    peak_paged_bytes=$pagedBytes
                })
            }
        }catch{}
        if(($tick % 10) -eq 0){
            $watch=Join-Path $target ("03_environment\watch_{0}.json" -f $caseId)
            & (Join-Path $tools 'check_exclusivity.ps1') -ProjectRoot $ProjectRoot -OutputJson $watch -AllowedMatlabPid $proc.Id | Out-Null
            $watchResult=Get-Content -Raw -Encoding UTF8 -LiteralPath $watch | ConvertFrom-Json
            $monitoredPids=@($watchResult.allowed_process_tree_pids | ForEach-Object {[int]$_})
            if($monitoredPids.Count -eq 0){$monitoredPids=@($proc.Id)}
            $watchRows.Add([pscustomobject]@{timestamp=(Get-Date).ToString('o');exclusive=$watchResult.exclusive;blocker_count=$watchResult.blocker_count})
            if($LASTEXITCODE -ne 0){$interference=$true;break}
        }
        Start-Sleep -Milliseconds 100; $tick++
    }
    if($interference -and -not $proc.HasExited){ Stop-A2ProcessTree -RootPid $proc.Id; $proc.WaitForExit() }
    $proc.WaitForExit(); $memoryFile=Join-Path $target ("04_phase1\raw_memory\{0}.csv" -f $caseId); $memory | Export-Csv -LiteralPath $memoryFile -NoTypeInformation -Encoding utf8
    $watchFile=Join-Path $target ("03_environment\exclusivity_watch_{0}.csv" -f $caseId); $watchRows | Export-Csv -LiteralPath $watchFile -NoTypeInformation -Encoding utf8
    $matlabExitCode=$proc.ExitCode
    if($null -eq $matlabExitCode){$matlabExitCode='UNKNOWN'}
    # On this MATLAB installation Start-Process tracks the launcher, whose ExitCode
    # can be unavailable even after the worker completed. Accept UNKNOWN only when
    # the formal artifacts themselves pass the full resumability contract.
    if($matlabExitCode -eq 'UNKNOWN' -and (Test-Path -LiteralPath $caseFile) -and (Test-Path -LiteralPath $rawTimingFile)){
        try{
            $completedCandidate=Get-Content -Raw -Encoding UTF8 -LiteralPath $caseFile | ConvertFrom-Json
            $candidateRows=(Get-Content -LiteralPath $rawTimingFile | Measure-Object -Line).Lines-1
            if($completedCandidate.case_status -eq 'COMPLETE' -and
               $completedCandidate.formal_count -eq 10000 -and
               $completedCandidate.environment_sha256 -eq $environmentHash -and
               $candidateRows -eq 10000){
                $matlabExitCode=0
            }
        }catch{}
    }
    if($interference -or $matlabExitCode -ne 0){
        $status=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target 'task_status.json') | ConvertFrom-Json
        $status.status=if($interference){'INVALID_INTERFERENCE_DURING_FORMAL_RUN'}else{'PARTIAL_CORE_INCOMPLETE'}; $status.updated_at=(Get-Date).ToString('o')
        $status | Add-Member -NotePropertyName failed_case -NotePropertyValue $caseId -Force
        $failureReason=if($interference){'EXTERNAL_PROCESS_APPEARED'}else{"MATLAB_EXIT_CODE_$matlabExitCode"}
        $status | Add-Member -NotePropertyName failure_reason -NotePropertyValue $failureReason -Force
        $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
        exit 4
    }
    if(-not (Test-Path -LiteralPath $caseFile)){throw "MATLAB completed without case JSON: $caseId"}
    $case=Get-Content -Raw -Encoding UTF8 -LiteralPath $caseFile | ConvertFrom-Json
    if($memory.Count -gt 0){
        $baselineWorking=($memory | Measure-Object working_set_bytes -Minimum).Minimum
        $baselinePrivate=($memory | Measure-Object private_bytes -Minimum).Minimum
        $peakWorking=($memory | Measure-Object peak_working_set_bytes -Maximum).Maximum
        $peakPrivate=($memory | Measure-Object private_bytes -Maximum).Maximum
        $case | Add-Member -NotePropertyName baseline_working_set_bytes -NotePropertyValue $baselineWorking -Force
        $case | Add-Member -NotePropertyName baseline_private_bytes -NotePropertyValue $baselinePrivate -Force
        $case | Add-Member -NotePropertyName peak_working_set_bytes -NotePropertyValue $peakWorking -Force
        $case | Add-Member -NotePropertyName peak_private_bytes -NotePropertyValue $peakPrivate -Force
        $case | Add-Member -NotePropertyName working_set_peak_delta_bytes -NotePropertyValue ($peakWorking-$baselineWorking) -Force
        $case | Add-Member -NotePropertyName private_peak_delta_bytes -NotePropertyValue ($peakPrivate-$baselinePrivate) -Force
        $case | Add-Member -NotePropertyName memory_trace_file -NotePropertyValue $memoryFile -Force
    }
    $case | Add-Member -NotePropertyName exclusivity_watch_file -NotePropertyValue $watchFile -Force
    $case | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $caseFile -Encoding utf8
    $completedCount=(Get-ChildItem -LiteralPath (Join-Path $target '04_phase1\cases') -Filter '*.json' -File | Measure-Object).Count
    $status=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target 'task_status.json') | ConvertFrom-Json
    $status.phase1_completed=$completedCount; $status.updated_at=(Get-Date).ToString('o')
    $status | Add-Member -NotePropertyName active_case -NotePropertyValue $null -Force
    $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
}

& (Join-Path $tools 'finalize_a2.ps1') -ProjectRoot $ProjectRoot
