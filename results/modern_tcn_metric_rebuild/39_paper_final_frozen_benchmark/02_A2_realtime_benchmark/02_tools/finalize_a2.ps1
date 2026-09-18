#requires -Version 5.1
param([string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16')

$ErrorActionPreference='Stop'
$target=Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark'
function Get-Sha256([string]$Path){
    $stream=[System.IO.File]::OpenRead($Path)
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try{return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLower()}
    finally{$sha.Dispose(); $stream.Dispose()}
}
$matrix=Import-Csv -LiteralPath (Join-Path $target '01_inventory\planned_run_matrix.csv')
$phase1=$matrix | Where-Object {$_.phase -eq '1'}
$official=$phase1 | Where-Object {$_.interface -eq 'A5'}
$supp=$phase1 | Where-Object {$_.interface -eq 'SUPPLEMENTAL'}

function Read-Cases($rows){
    foreach($r in $rows){
        $file=Join-Path $target ("04_phase1\cases\{0}.json" -f $r.case_id)
        if(-not (Test-Path -LiteralPath $file)){throw "Missing completed case: $($r.case_id)"}
        Get-Content -Raw -Encoding UTF8 -LiteralPath $file | ConvertFrom-Json
    }
}
$officialCases=@(Read-Cases $official); $suppCases=@(Read-Cases $supp)
$all=@($officialCases)+@($suppCases)
$expectedEnvironmentHash=(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target '03_environment\environment_manifest.json') | ConvertFrom-Json).environment_sha256

function Get-MatlabPercentile([double[]]$Sorted,[double]$Percent){
    $n=$Sorted.Count
    $rank=($Percent/100.0)*$n+0.5
    if($rank -le 1){return $Sorted[0]}
    if($rank -ge $n){return $Sorted[$n-1]}
    $lower=[math]::Floor($rank); $fraction=$rank-$lower
    return $Sorted[$lower-1]+($Sorted[$lower]-$Sorted[$lower-1])*$fraction
}
function Near([double]$A,[double]$B){return [math]::Abs($A-$B) -le 1e-9}
$validation=[System.Collections.Generic.List[object]]::new()
foreach($case in $all){
    $rawFile=[string]$case.raw_timing_file
    if(-not (Test-Path -LiteralPath $rawFile)){throw "Missing raw timing file: $rawFile"}
    $raw=@(Import-Csv -LiteralPath $rawFile)
    $values=@($raw | ForEach-Object {[double]::Parse($_.latency_ms,[Globalization.CultureInfo]::InvariantCulture)})
    $finite=@($values | Where-Object {-not [double]::IsNaN($_) -and -not [double]::IsInfinity($_)}).Count
    [array]::Sort($values)
    $p50=Get-MatlabPercentile $values 50; $p95=Get-MatlabPercentile $values 95; $p99=Get-MatlabPercentile $values 99
    $max=$values[-1]; $over=@($values | Where-Object {$_ -gt 10.0}).Count/$values.Count
    $valid=($case.case_status -eq 'COMPLETE' -and $case.environment_sha256 -eq $expectedEnvironmentHash -and
            $case.batch_size -eq 1 -and $case.warmup_count -ge 500 -and
            $case.formal_count -eq 10000 -and $raw.Count -eq 10000 -and $finite -eq 10000 -and
            (Near $p50 $case.p50_ms) -and (Near $p95 $case.p95_ms) -and (Near $p99 $case.p99_ms) -and
            (Near $max $case.max_ms) -and (Near $over $case.over_10ms_rate))
    $validation.Add([pscustomobject]@{case_id=$case.case_id;raw_rows=$raw.Count;finite_rows=$finite;recomputed_p50_ms=$p50;recomputed_p95_ms=$p95;recomputed_p99_ms=$p99;recomputed_max_ms=$max;recomputed_over_10ms_rate=$over;valid=$valid})
}
$validation | Export-Csv -LiteralPath (Join-Path $target '06_summary\raw_timing_validation.csv') -NoTypeInformation -Encoding utf8
if(@($validation | Where-Object {-not $_.valid}).Count -gt 0){throw 'Raw timing validation failed.'}
$deltaCase=$all | Where-Object {$_.case_id -eq 'core_inference__modern_tcn_delta_bank_124'}
$modern22Case=$all | Where-Object {$_.case_id -eq 'core_inference__modern_tcn_22d'}
if($deltaCase.parameter_count -ne 145202){throw 'Protocol error: delta_bank_124 parameter_count is not 145202.'}
if($modern22Case.parameter_count -ne 118538){throw 'Protocol error: ModernTCN-22D parameter_count is not 118538.'}

$officialCases | Select-Object component_id,method_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,@{n='status';e={$_.case_status}} |
    Export-Csv -LiteralPath (Join-Path $target '06_summary\runtime_summary.csv') -NoTypeInformation -Encoding utf8
$suppCases | Select-Object case_id,component_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,@{n='status';e={$_.case_status}} |
    Export-Csv -LiteralPath (Join-Path $target '06_summary\supplemental_runtime_summary.csv') -NoTypeInformation -Encoding utf8
$all | Select-Object case_id,method_id,parameter_count,runtime_import_learnable_count,model_file,model_sha256,model_file_bytes,source_file,source_file_sha256,source_file_bytes,peak_working_set_bytes,peak_private_bytes |
    Export-Csv -LiteralPath (Join-Path $target '06_summary\parameter_model_memory_summary.csv') -NoTypeInformation -Encoding utf8
$caseDecisions=@($all | Select-Object case_id,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,meets_p95_10ms,meets_p99_10ms,zero_overrun)
$decision=[ordered]@{task_id='A2';status='PARTIAL_CORE_COMPLETE_WAITING_FOR_FINAL_FUSION';ten_ms_threshold_ms=10.0;phase1_cases_complete=11;phase2_cases_complete=0;fusion_status='NOT_ELIGIBLE_FINAL_FUSION_NOT_FROZEN';cases=$caseDecisions}
$decision | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target '06_summary\decision.json') -Encoding utf8

$before=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target '00_protocol_lock\protected_artifacts_before.json') | ConvertFrom-Json
$after=foreach($r in $before){$sha=Get-Sha256 $r.path;[pscustomobject]@{path=$r.path;before_sha256=$r.sha256;after_sha256=$sha;unchanged=($sha -eq $r.sha256)}}
$after | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $target '00_protocol_lock\protected_artifacts_after.json') -Encoding utf8
if(@($after | Where-Object {-not $_.unchanged}).Count -gt 0){throw 'Protected artifact changed during A2.'}

$status=[ordered]@{task_id='A2';status='PARTIAL_CORE_COMPLETE_WAITING_FOR_FINAL_FUSION';updated_at=(Get-Date).ToString('o');phase1_completed=11;phase1_expected=11;official_a5_phase1_completed=9;phase2_eligibility='NOT_ELIGIBLE_FINAL_FUSION_NOT_FROZEN';formal_timing_started=$true;formal_timing_complete=$true}
$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
$env=(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target '03_environment\environment_manifest.json') | ConvertFrom-Json).environment_sha256
$receipt=[ordered]@{task_id='A2';protocol_id='A0_paper_final_unified_protocol_v1';status='PARTIAL_CORE_COMPLETE_WAITING_FOR_FINAL_FUSION';environment_sha256=$env;phase1_cases_complete=11;phase1_a5_cases_complete=9;phase2_cases_complete=0;protected_artifacts_unchanged=$true;raw_timing_samples=110000;raw_timing_validation='PASS';fusion_status='NOT_ELIGIBLE_FINAL_FUSION_NOT_FROZEN';summary_files=@('06_summary/runtime_summary.csv','06_summary/supplemental_runtime_summary.csv','06_summary/parameter_model_memory_summary.csv','06_summary/raw_timing_validation.csv','06_summary/decision.json')}
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'receipt.json') -Encoding utf8

$report=Join-Path $target 'A2_experiment_report.md'
$lines=@('','# Phase 1 formal results','',"Status: `PARTIAL_CORE_COMPLETE_WAITING_FOR_FINAL_FUSION`.",'','Completed 9 A5 runtime cells and 2 supplemental cells; each cell used 500 warmups and 10,000 formal repetitions. Final Fusion is not frozen, so phase 2 was not run.','','See `06_summary/runtime_summary.csv`, `06_summary/supplemental_runtime_summary.csv`, `06_summary/raw_timing_validation.csv`, and `06_summary/decision.json` for the measured values.')
if(-not ((Get-Content -Raw -Encoding UTF8 -LiteralPath $report).Contains('# Phase 1 formal results'))){
    Add-Content -LiteralPath $report -Value $lines -Encoding utf8
}
$files=Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object {$_.Name -ne 'artifact_manifest.csv'}
$files | ForEach-Object {[pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-Sha256 $_.FullName)}} |
    Export-Csv -LiteralPath (Join-Path $target 'artifact_manifest.csv') -NoTypeInformation -Encoding utf8
Write-Host 'A2 phase 1 complete; waiting for final Fusion.'
