#requires -Version 5.1

function Find-A2BenchmarkPythonProcess {
    param(
        [Parameter(Mandatory = $true)][int]$RootPid,
        [string]$ScriptLeaf = 'benchmark_ort.py'
    )

    $all = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
    $tree = [System.Collections.Generic.HashSet[int]]::new()
    [void]$tree.Add($RootPid)
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($item in $all) {
            $pidValue = [int]$item.ProcessId
            if (-not $tree.Contains($pidValue) -and $tree.Contains([int]$item.ParentProcessId)) {
                [void]$tree.Add($pidValue)
                $changed = $true
            }
        }
    }

    $matches = @($all | Where-Object {
        [int]$_.ProcessId -ne $RootPid -and
        $tree.Contains([int]$_.ProcessId) -and
        $_.Name -ieq 'python.exe' -and
        $_.CommandLine -like "*$ScriptLeaf*"
    })
    if ($matches.Count -gt 1) {
        throw "Multiple benchmark Python descendants found below launcher PID $RootPid."
    }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function Add-A2ProcessMemorySample {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Samples,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [string]$ProcessRole = 'benchmark_python'
    )

    $sample = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $sample) { return $false }
    $Samples.Add([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        pid = $ProcessId
        process_role = $ProcessRole
        working_set_bytes = [int64]$sample.WorkingSet64
        private_bytes = [int64]$sample.PrivateMemorySize64
        paged_bytes = [int64]$sample.PagedMemorySize64
    })
    return $true
}
