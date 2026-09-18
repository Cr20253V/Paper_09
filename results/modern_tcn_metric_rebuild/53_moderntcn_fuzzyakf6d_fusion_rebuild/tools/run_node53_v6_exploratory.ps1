[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Preflight','Build','Smoke','SixPath','Summarize')][string]$Stage,
  [switch]$ReuseExisting,
  [string]$PathId,
  [string]$LogFile
)
$ErrorActionPreference='Stop'
$nodeRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
function Invoke-Python([string[]]$Arguments){ & python @Arguments; if($LASTEXITCODE -ne 0){throw "Python failed: $($Arguments -join ' ')"} }
function Invoke-Matlab([string]$expr){ & matlab -batch $expr; if($LASTEXITCODE -ne 0){throw "MATLAB failed: $expr"} }
if($LogFile){$log=if([IO.Path]::IsPathRooted($LogFile)){$LogFile}else{Join-Path $nodeRoot $LogFile}; New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null; Start-Transcript -LiteralPath $log -Append | Out-Null}
try {
  Push-Location $projectRoot; $tool=$PSScriptRoot; $q=$tool.Replace("'","''"); $rq=$projectRoot.Replace("'","''"); $reuse=if($ReuseExisting){'true'}else{'false'}; $pathExpr=if($PathId){"'"+$PathId.Replace("'","''")+"'"}else{"''"}
  switch($Stage){
    'Preflight' { Invoke-Python @((Join-Path $tool 'node53_v6_exploratory_preflight.py'),'preflight') }
    'Build' { Invoke-Python @((Join-Path $tool 'node53_v6_exploratory_preflight.py'),'preflight'); Invoke-Matlab "init_project;addpath('$q');r=create_node53_v6_exploratory_model('$rq');disp(jsonencode(r,PrettyPrint=true));v=verify_node53_v6_exploratory_model('$rq');disp(jsonencode(v,PrettyPrint=true));u=test_node53_v6_runtime('$rq');disp(jsonencode(u,PrettyPrint=true));"; Invoke-Matlab "init_project;addpath('$q');r=run_node53_v6_exploratory_six_path('$rq',struct('dry_run',true));disp(jsonencode(r,PrettyPrint=true));" }
    'Smoke' { Invoke-Matlab "init_project;addpath('$q');r=run_node53_v6_exploratory_six_path('$rq',struct('short_test',true,'reuse_existing',$reuse));disp(jsonencode(r,PrettyPrint=true));" }
    'SixPath' { $extra="'reuse_existing',$reuse,'path_id',$pathExpr"; Invoke-Matlab "init_project;addpath('$q');r=run_node53_v6_exploratory_six_path('$rq',struct($extra));disp(jsonencode(r,PrettyPrint=true));" }
    'Summarize' { Invoke-Python @((Join-Path $tool 'node53_v6_exploratory_preflight.py'),'summarize') }
  }
} finally {Pop-Location; if($LogFile){Stop-Transcript | Out-Null}}
