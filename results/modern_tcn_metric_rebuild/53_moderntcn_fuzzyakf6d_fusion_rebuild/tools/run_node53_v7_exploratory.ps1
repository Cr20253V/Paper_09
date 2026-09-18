[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Tune','Preflight','Build','Smoke','SixPath','Summarize')][string]$Stage,
  [switch]$ReuseExisting,
  [ValidateSet(1,7,11,21,42,73,101,202,340,520)][int]$ModelSeed=42,
  [switch]$AllSeeds,
  [string]$PathId,
  [string]$WorkerId='serial',
  [string]$LogFile
)
$ErrorActionPreference='Stop'
$nodeRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$workerSafe=($WorkerId -replace '[^A-Za-z0-9_-]','_')
if([string]::IsNullOrWhiteSpace($workerSafe)){ $workerSafe='serial' }
$matlabPref=Join-Path $nodeRoot "cache\prefs\$workerSafe"
$workerTmp=Join-Path $nodeRoot "cache\tmp\$workerSafe"
New-Item -ItemType Directory -Force -Path $matlabPref,$workerTmp | Out-Null
$env:MATLAB_PREFDIR=$matlabPref
$env:TEMP=$workerTmp
$env:TMP=$workerTmp
function Invoke-Python([string[]]$Arguments){ & python @Arguments; if($LASTEXITCODE -ne 0){throw "Python failed: $($Arguments -join ' ')"} }
function Invoke-Matlab([string]$expr){ & matlab -batch $expr; if($LASTEXITCODE -ne 0){throw "MATLAB failed: $expr"} }
if($LogFile){$log=if([IO.Path]::IsPathRooted($LogFile)){$LogFile}else{Join-Path $nodeRoot $LogFile}; New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null; Start-Transcript -LiteralPath $log -Append | Out-Null}
try {
  Push-Location $projectRoot; $tool=$PSScriptRoot; $q=$tool.Replace("'","''"); $rq=$projectRoot.Replace("'","''"); $reuse=if($ReuseExisting){'true'}else{'false'}; $pathExpr=if($PathId){"'"+$PathId.Replace("'","''")+"'"}else{"''"}
  switch($Stage){
    'Tune' { Invoke-Python @((Join-Path $tool 'node53_stage4_slope_aware_v7_fast.py')) }
    'Preflight' { Invoke-Python @((Join-Path $tool 'export_v7_hist_gradient_boosting.py')); Invoke-Python @((Join-Path $tool 'node53_v7_exploratory_preflight.py'),'preflight') }
    'Build' { Invoke-Python @((Join-Path $tool 'export_v7_hist_gradient_boosting.py')); Invoke-Python @((Join-Path $tool 'node53_v7_exploratory_preflight.py'),'preflight'); Invoke-Matlab "init_project;addpath('$q');r=create_node53_v7_exploratory_model('$rq');disp(jsonencode(r,PrettyPrint=true));v=verify_node53_v7_exploratory_model('$rq');disp(jsonencode(v,PrettyPrint=true));u=test_node53_v7_runtime('$rq');disp(jsonencode(u,PrettyPrint=true));"; Invoke-Matlab "init_project;addpath('$q');r=run_node53_v7_exploratory_six_path('$rq',struct('dry_run',true));disp(jsonencode(r,PrettyPrint=true));" }
  'Smoke' { $w=$WorkerId.Replace("'","''"); Invoke-Matlab "init_project;addpath('$q');node53_configure_filegen_worker('$rq','$w');r=run_node53_v7_exploratory_six_path('$rq',struct('short_test',true,'reuse_existing',$reuse,'model_seed',$ModelSeed));disp(jsonencode(r,PrettyPrint=true));" }
  'SixPath' { if($AllSeeds){$extra="'reuse_existing',$reuse,'path_id',$pathExpr,'model_seeds',[1 7 11 21 42 73 101 202 340 520]"}else{$extra="'reuse_existing',$reuse,'path_id',$pathExpr,'model_seed',$ModelSeed"}; $w=$WorkerId.Replace("'","''"); Invoke-Matlab "init_project;addpath('$q');node53_configure_filegen_worker('$rq','$w');r=run_node53_v7_exploratory_six_path('$rq',struct($extra));disp(jsonencode(r,PrettyPrint=true));if isfield(r,'failed_count') && r.failed_count>0;error('node53:v7CasesFailed','V7 worker returned failed_count=%d.',r.failed_count);end;" }
    'Summarize' { Invoke-Python @((Join-Path $tool 'node53_v7_exploratory_preflight.py'),'summarize') }
  }
} finally {Pop-Location; if($LogFile){Stop-Transcript | Out-Null}}
