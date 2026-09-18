[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Prepare','Qualify','Freeze','G0Full','FormalSixPath','Finalize')]
    [string]$Stage,
    [switch]$ShortTest,
    [switch]$ReuseExisting,
    [string]$LogFile
)
$ErrorActionPreference='Stop'
$nodeRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
function Invoke-Python([string[]]$args){ & python @args; if($LASTEXITCODE -ne 0){throw "Python failed: $($args -join ' ')"} }
function Invoke-Matlab([string]$expr){ & matlab -batch $expr; if($LASTEXITCODE -ne 0){throw "MATLAB failed: $expr"} }
function Assert-DevelopmentQualified {
  $stop=Join-Path $nodeRoot 'STOP_NODE53_NO_QUALIFIED_FUSION.json'
  $selected=Join-Path $nodeRoot 'selected_fusion_config.json'
  if((Test-Path -LiteralPath $stop) -or -not (Test-Path -LiteralPath $selected)){
    throw 'Node53 development qualification is not passed; test, freeze, G0, and formal stages are locked.'
  }
}
if($LogFile){$log=if([IO.Path]::IsPathRooted($LogFile)){$LogFile}else{Join-Path $nodeRoot $LogFile}; New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null; Start-Transcript -LiteralPath $log -Append | Out-Null}
try {
  Push-Location $projectRoot
  $tool=(Join-Path $nodeRoot 'tools'); $quoted=$tool.Replace("'", "''"); $rootq=$projectRoot.Replace("'", "''")
  switch($Stage){
    'Prepare' { if($ShortTest){Invoke-Python @((Join-Path $tool 'node53_pipeline.py'),'prepare','--short'); Invoke-Matlab "init_project;addpath('$quoted');r=node53_run_parity('$rootq');disp(jsonencode(r,PrettyPrint=true));"; Invoke-Python @((Join-Path $tool 'node53_parity.py'),'--compare')} else {Invoke-Python @((Join-Path $tool 'node53_pipeline.py'),'prepare')} }
    'Qualify' {Assert-DevelopmentQualified; Invoke-Python @((Join-Path $tool 'node53_pipeline.py'),'qualify')}
    'Freeze' {Assert-DevelopmentQualified; Invoke-Matlab "init_project;addpath('$quoted');b=create_node53_model('$rootq');disp(jsonencode(b,PrettyPrint=true));v=verify_node53_model_structure('$rootq');disp(jsonencode(v,PrettyPrint=true));"}
    'G0Full' {Assert-DevelopmentQualified; throw 'G0Full runner is intentionally manual after model_freeze.json is present.'}
    'FormalSixPath' {Assert-DevelopmentQualified; throw 'FormalSixPath runner is intentionally manual after model_freeze.json and offline_qualification.json are present.'}
    'Finalize' {Invoke-Python @((Join-Path $tool 'node53_pipeline.py'),'finalize')}
  }
} finally {Pop-Location; if($LogFile){Stop-Transcript | Out-Null}}
