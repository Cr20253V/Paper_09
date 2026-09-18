#requires -Version 5.1
param([string]$ProjectRoot = 'E:\Matlab\Simulink\S-Function_16')

$ErrorActionPreference = 'Stop'
$target = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\02_A2_realtime_benchmark'
$paper76 = Join-Path $ProjectRoot 'results\paper\7.6'
function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [System.IO.File]::WriteAllText($Path,$Text,[System.Text.UTF8Encoding]::new($false))
}
function Find-FrozenFileByHash([string]$Directory,[string]$ExpectedHash) {
    $match = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() -eq $ExpectedHash.ToLower()
    })
    if ($match.Count -ne 1) { throw "Expected exactly one frozen file with SHA256 $ExpectedHash under $Directory; found $($match.Count)." }
    return $match[0].FullName
}
$a0File = Find-FrozenFileByHash $paper76 '1fdb75a7effbc2da5d2217df415004a5819eb577c6fdc275ad0f94520860c911'
$a0DescriptionFile = Find-FrozenFileByHash $paper76 '44155532ef770dbb5c4817006caa80213cb2ede7390ee8dbcc75085425058173'
$auditOutlineFile = Find-FrozenFileByHash $paper76 'a8a0c7a736afcb54812cd419a3a31f716eac2820a1c5fed68c85b9636191b8bc'
$a1Root = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison'
$a3Receipt = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\03_A3_slope_scheduling_necessity\receipt.json'
$a5Schema = Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\05_A5_statistical_audit\00_protocol_lock\input_schemas\a2_runtime_case.schema.json'

@('00_protocol_lock','01_inventory','02_tools','03_environment','04_phase1\cases','04_phase1\raw_timing','04_phase1\raw_memory','04_phase1\logs','05_phase2\cases','05_phase2\raw_timing','05_phase2\raw_memory','05_phase2\logs','06_summary') |
    ForEach-Object { New-Item -ItemType Directory -Force -Path (Join-Path $target $_) | Out-Null }

$a0 = Get-Content -Raw -Encoding UTF8 -LiteralPath $a0File | ConvertFrom-Json
$a0Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $a0File).Hash.ToLower()
$protectedPaths = @(
    $a0File,
    $a0DescriptionFile,
    $auditOutlineFile,
    (Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\receipt.json'),
    (Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\01_A1_algorithm_comparison\model_registry.csv'),
    (Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\39_paper_final_frozen_benchmark\03_A3_slope_scheduling_necessity\receipt.json')
)
$protected = foreach ($path in $protectedPaths) {
    [pscustomobject]@{ path=$path; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower(); bytes=(Get-Item -LiteralPath $path).Length }
}
$protected | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $target '00_protocol_lock\protected_artifacts_before.json') -Encoding utf8

$snapshot = [ordered]@{
    task_id = 'A2'
    protocol_id = $a0.protocol_id
    source_config = $a0File
    source_config_sha256 = $a0Hash
    plant_revision = $a0.dataset.plant_revision
    dataset = $a0.dataset
    input_representations = $a0.input_representations
    representative_model_seed = 42
    closed_loop_paths = $a0.closed_loop_paths
    lpv_mpc = $a0.lpv_mpc
    protected_write_boundary = $target
}
Write-Utf8NoBom -Path (Join-Path $target '00_protocol_lock\protocol_snapshot.json') -Text ($snapshot | ConvertTo-Json -Depth 30)

$effective = [ordered]@{
    task_id='A2'; protocol_id=$a0.protocol_id; phase=1; batch_size=1; warmup_count=500; formal_count=10000
    backend='MATLAB_R2024b_CPU'; thread_policy='single'; gpu_used=$false
    core_inputs=[ordered]@{ modern_tcn_delta_bank_124='single[1,128,88]'; others='single[1,128,22]' }
    input_order='A0 test windows in stored order; A1 seed42 six-path y_raw in A0 path order'
    over_10ms_definition='latency_ms > 10.0'
    percentile_method='MATLAB prctile on all 10000 untrimmed samples'
    a0_effective_config_sha256=$a0Hash
}
$effective | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target '00_protocol_lock\effective_config.json') -Encoding utf8
@{
    p50_ms='50th percentile of all untrimmed per-call samples'; p95_ms='95th percentile'; p99_ms='99th percentile'; max_ms='maximum';
    over_10ms_rate='count(latency_ms > 10.0) / formal_count'; timer_overhead='reported separately and never subtracted';
    peak_working_set_bytes='maximum summed OS working set observed across the isolated MATLAB launcher and descendant process tree'; peak_private_bytes='maximum summed OS private bytes observed across that process tree'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $target '00_protocol_lock\metric_dictionary.json') -Encoding utf8
Copy-Item -LiteralPath $a5Schema -Destination (Join-Path $target '00_protocol_lock\a2_runtime_case.schema.json') -Force

$modelRegistry = Import-Csv -LiteralPath (Join-Path $a1Root 'model_registry.csv') | Where-Object { $_.model_seed -eq '42' }
$inventory = [System.Collections.Generic.List[object]]::new()
function Add-Artifact([string]$kind,[string]$id,[string]$path,[string]$expected,[string]$parent='') {
    $exists = Test-Path -LiteralPath $path
    $actual = if ($exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() } else { '' }
    $bytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { 0 }
    $inventory.Add([pscustomobject]@{artifact_kind=$kind;artifact_id=$id;path=$path;expected_sha256=$expected;actual_sha256=$actual;sha256_match=($actual -eq $expected);bytes=$bytes;parent_sha256=$parent})
}
Add-Artifact 'dataset' 'a0_dataset' (Join-Path $ProjectRoot $a0.dataset.file) $a0.dataset.sha256
foreach ($row in $modelRegistry) { Add-Artifact 'authority_model' $row.method_id $row.model_file $row.model_sha256 }
$onnx = @(
    @('deployment_model','modern_tcn_delta_bank_124_onnx',(Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\25_lag_representation_repair\03_onnx_and_smoke\delta_bank_124\seed42\modern_tcn_delta_bank_124_seed42.onnx'),'45e1fc805ca93c2572d85bf4d90744b7f486b0bddbd7503cd44e9c2b1ee4835e','d49238d2a90803a4abbc8ca65f822b3f65f4f77b62be3b9f10227b9e038895f7'),
    @('deployment_model','modern_tcn_22d_onnx',(Join-Path $ProjectRoot 'results\modern_tcn_metric_rebuild\32_four_algorithm_10seed_closed_loop\01_modern_fixed_onnx\seed42\modern_fixed_seed42.onnx'),'bad282e477990865a2f9598926d1015b39b79312991415a459db1cba362fe4fd','4cd19cdbaf399c6abb03e0de5c1a020d4b540d27914488f521e58eb22d6f2704')
)
foreach ($o in $onnx) { Add-Artifact $o[0] $o[1] $o[2] $o[3] $o[4] }
Add-Artifact 'lpv_database' 'frozen_lpv_database' (Join-Path $ProjectRoot $a0.lpv_mpc.lpv_database_file) $a0.lpv_mpc.lpv_database_sha256
Add-Artifact 'mpc_maps' 'frozen_mpc_maps' (Join-Path $ProjectRoot $a0.lpv_mpc.maps_file) $a0.lpv_mpc.maps_sha256
Add-Artifact 'mpc_controller' 'frozen_controller_cache' (Join-Path $ProjectRoot $a0.lpv_mpc.controller_cache_file) $a0.lpv_mpc.controller_cache_sha256
foreach ($p in $a0.closed_loop_paths) { Add-Artifact 'path' $p.path_id (Join-Path $ProjectRoot $p.file) $p.sha256 }

$traceRegistry = Import-Csv -LiteralPath (Join-Path $a1Root '04_closed_loop\reused_case_registry.csv') |
    Where-Object { $_.method_id -eq 'modern_tcn_delta_bank_124' -and $_.seed -eq '42' } | Sort-Object path_id
foreach ($row in $traceRegistry) { Add-Artifact 'runtime_trace' ("seed42_"+$row.path_id) $row.raw_result_file $row.raw_result_sha256 }
$inventory | Export-Csv -LiteralPath (Join-Path $target '01_inventory\input_artifact_registry.csv') -NoTypeInformation -Encoding utf8
if (@($inventory | Where-Object { -not $_.sha256_match }).Count -gt 0) { throw 'At least one frozen input SHA256 does not match.' }

$reusable = @(
    [pscustomobject]@{category='MODEL';item='A1 seed42 four models';use='direct authority paths from model_registry.csv'},
    [pscustomobject]@{category='DEPLOYMENT';item='two existing ModernTCN ONNX files';use='runtime derivative with authority checkpoint parent SHA'},
    [pscustomobject]@{category='DATA';item='A0 dataset and scaler';use='core windows and normalization'},
    [pscustomobject]@{category='TRACE';item='A1 seed42 six-path closed-loop outputs';use='common y_raw/controller input stream'},
    [pscustomobject]@{category='CONTROL';item='A0 LPV database, maps and ctrl.mat';use='frozen MPC solve harness'},
    [pscustomobject]@{category='LOGIC_ONLY';item='src/Compare legacy benchmark';use='timing pattern only; all old results excluded'}
)
$reusable | Export-Csv -LiteralPath (Join-Path $target '01_inventory\reusable_results.csv') -NoTypeInformation -Encoding utf8

$officialP1=@('core_inference__modern_tcn_delta_bank_124','core_inference__modern_tcn_22d','core_inference__gru_22d','core_inference__tcn_22d','end_to_end_update__modern_tcn_delta_bank_124','end_to_end_update__modern_tcn_22d','end_to_end_update__gru_22d','end_to_end_update__tcn_22d','mpc_solve__effective_controller')
$supp=@('preprocess__normalization_delta_bank_124','full_cycle__slope_estimation_mpc')
$phase2=@('core_inference__fusion_wrapper','end_to_end_update__fusion_wrapper','full_cycle__perception_fusion_mpc')
$matrix=@()
foreach($id in $officialP1){$matrix += [pscustomobject]@{phase=1;interface='A5';case_id=$id;warmup=500;formal=10000;eligibility='READY_AFTER_EXCLUSIVITY'}}
foreach($id in $supp){$matrix += [pscustomobject]@{phase=1;interface='SUPPLEMENTAL';case_id=$id;warmup=500;formal=10000;eligibility='READY_AFTER_EXCLUSIVITY'}}
foreach($id in $phase2){$matrix += [pscustomobject]@{phase=2;interface='A5';case_id=$id;warmup=500;formal=10000;eligibility='WAITING_FOR_FINAL_FUSION'}}
$matrix | Export-Csv -LiteralPath (Join-Path $target '01_inventory\planned_run_matrix.csv') -NoTypeInformation -Encoding utf8
$matrix | ForEach-Object { [pscustomobject]@{phase=$_.phase;case_id=$_.case_id;reason=if($_.phase -eq 1){'NO_A2_FORMAL_RESULT'}else{'FINAL_FUSION_NOT_FROZEN'};missing=$true} } |
    Export-Csv -LiteralPath (Join-Path $target '01_inventory\missing_cases.csv') -NoTypeInformation -Encoding utf8

$cpu = Get-CimInstance Win32_Processor | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
$cs = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM
$power = (& powercfg /getactivescheme 2>&1 | Out-String).Trim()
$matlabExe='D:\LenovoSoftstore\install\Matlab R2024b\bin\matlab.exe'
$stableEnv=[ordered]@{cpu=@($cpu);computer=$cs;os=$os;gpu=@($gpu);matlab='R2024b';matlab_executable=$matlabExe;backend='CPU';threads=1;batch_size=1;gpu_used=$false;power_policy=$power;input_shapes=@('[1,128,88]','[1,128,22]');data_movement='preloaded host single arrays; disk IO excluded'}
$stableJson=$stableEnv | ConvertTo-Json -Depth 10 -Compress
$sha=[System.Security.Cryptography.SHA256]::Create(); $envHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stableJson)))).Replace('-','').ToLower()
$envManifest=[ordered]@{environment_sha256=$envHash;captured_at=(Get-Date).ToString('o');stable=$stableEnv;volatile=[ordered]@{logical_processor_load=(Get-CimInstance Win32_Processor | Select-Object LoadPercentage);free_physical_memory_kb=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory}}
Write-Utf8NoBom -Path (Join-Path $target '03_environment\environment_manifest.json') -Text ($envManifest | ConvertTo-Json -Depth 12)

$completedIds=[System.Collections.Generic.List[string]]::new()
$completedCases=[System.Collections.Generic.List[object]]::new()
foreach($id in @($officialP1)+@($supp)){
    $caseFile=Join-Path $target ("04_phase1\cases\{0}.json" -f $id)
    $rawFile=Join-Path $target ("04_phase1\raw_timing\{0}.csv" -f $id)
    if((Test-Path -LiteralPath $caseFile) -and (Test-Path -LiteralPath $rawFile)){
        try{
            $candidate=Get-Content -Raw -Encoding UTF8 -LiteralPath $caseFile | ConvertFrom-Json
            $rawRows=(Get-Content -LiteralPath $rawFile | Measure-Object -Line).Lines-1
            if($candidate.case_status -eq 'COMPLETE' -and $candidate.formal_count -eq 10000 -and
               $candidate.environment_sha256 -eq $envHash -and $rawRows -eq 10000){
                $completedIds.Add($id); $completedCases.Add($candidate)
            }
        }catch{}
    }
}
$phase1Completed=$completedIds.Count
$matrix | ForEach-Object {
    $done=($_.phase -eq 1 -and $completedIds.Contains($_.case_id))
    [pscustomobject]@{phase=$_.phase;case_id=$_.case_id;reason=if($done){'COMPLETE'}elseif($_.phase -eq 1){'NO_VALID_A2_FORMAL_RESULT'}else{'FINAL_FUSION_NOT_FROZEN'};missing=(-not $done)}
} | Export-Csv -LiteralPath (Join-Path $target '01_inventory\missing_cases.csv') -NoTypeInformation -Encoding utf8

$allProcesses=Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine
$allProcesses | Export-Csv -LiteralPath (Join-Path $target '03_environment\processes_prepare.csv') -NoTypeInformation -Encoding utf8
$checkScript=Join-Path $target '02_tools\check_exclusivity.ps1'
& $checkScript -ProjectRoot $ProjectRoot -OutputJson (Join-Path $target '03_environment\exclusivity_check.json') | Out-Null
$exclusive=($LASTEXITCODE -eq 0)
$status=if($exclusive){'READY_FOR_FORMAL_RUN'}else{'BLOCKED_EXCLUSIVITY'}
$blockers=(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $target '03_environment\exclusivity_check.json') | ConvertFrom-Json).blockers

$runManifest=[ordered]@{task_id='A2';protocol_id=$a0.protocol_id;created_at=(Get-Date).ToString('o');write_root=$target;phase1_cases=$officialP1+$supp;phase2_cases=$phase2;environment_sha256=$envHash;model_seed=42;warmup_count=500;formal_count=10000;phase1_completed=$phase1Completed;status=$status}
$runManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'run_manifest.json') -Encoding utf8
$taskStatus=[ordered]@{task_id='A2';status=$status;updated_at=(Get-Date).ToString('o');phase1_completed=$phase1Completed;phase1_expected=11;phase2_eligibility='NOT_ELIGIBLE_FINAL_FUSION_NOT_FROZEN';formal_timing_started=($phase1Completed -gt 0);blockers=@($blockers)}
$taskStatus | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'task_status.json') -Encoding utf8
$receipt=[ordered]@{task_id='A2';status=$status;protocol_id=$a0.protocol_id;environment_sha256=$envHash;protected_artifacts_verified=$true;formal_results_available=($phase1Completed -gt 0);phase1_cases_complete=$phase1Completed;fusion_status='NOT_ELIGIBLE';outputs=@('README.md','A2_experiment_report.md','00_protocol_lock/protocol_snapshot.json','01_inventory/input_artifact_registry.csv','run_manifest.json','task_status.json')}
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target 'receipt.json') -Encoding utf8
$decision=[ordered]@{task_id='A2';status=$status;formal_results_available=($phase1Completed -gt 0);phase1_cases_complete=$phase1Completed;reason=if(-not $exclusive){'EXCLUSIVITY_BLOCKED'}elseif($phase1Completed -gt 0){'PARTIAL_FORMAL_RESULTS_AVAILABLE_READY_TO_RESUME'}else{'FORMAL_RUN_NOT_STARTED'};ten_ms_threshold_ms=10.0;protocol_change_allowed=$false;fusion_status='NOT_ELIGIBLE_FINAL_FUSION_NOT_FROZEN'}
$decision | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target '06_summary\decision.json') -Encoding utf8
'component_id,method_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,status' | Set-Content -LiteralPath (Join-Path $target '06_summary\runtime_summary.csv') -Encoding utf8
'case_id,component_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,status' | Set-Content -LiteralPath (Join-Path $target '06_summary\supplemental_runtime_summary.csv') -Encoding utf8
if($completedCases.Count -gt 0){
    @($completedCases | Where-Object {$officialP1 -contains $_.case_id}) | Select-Object component_id,method_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,@{n='status';e={$_.case_status}} | Export-Csv -LiteralPath (Join-Path $target '06_summary\runtime_summary.csv') -NoTypeInformation -Encoding utf8
    $completedSupplemental=@($completedCases | Where-Object {$supp -contains $_.case_id})
    if($completedSupplemental.Count -gt 0){$completedSupplemental | Select-Object case_id,component_id,environment_sha256,batch_size,warmup_count,formal_count,p50_ms,p95_ms,p99_ms,max_ms,over_10ms_rate,@{n='status';e={$_.case_status}} | Export-Csv -LiteralPath (Join-Path $target '06_summary\supplemental_runtime_summary.csv') -NoTypeInformation -Encoding utf8}
}
"[$((Get-Date).ToString('o'))] prepare_a2 status=$status; formal timing not started" | Set-Content -LiteralPath (Join-Path $target '03_environment\prepare.log') -Encoding utf8
$files=Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object {$_.Name -notin @('artifact_manifest.csv','prepare_console.log')}
$files | ForEach-Object {[pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()}} |
    Export-Csv -LiteralPath (Join-Path $target 'artifact_manifest.csv') -NoTypeInformation -Encoding utf8
Write-Host "A2 preparation complete. Status: $status"
if(-not $exclusive){ exit 3 }
