param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$PythonExe,
    [Parameter(Mandatory = $true)][string]$LogDirectory
)

$ErrorActionPreference = 'Stop'
$taskSource = 'NFG Visits Debt Refresh'
$startedAt = Get-Date
$stamp = $startedAt.ToString('yyyyMMdd_HHmmss')

try {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "ProjectRoot does not exist"
    }
    if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
        throw "PythonExe does not exist"
    }
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $logPath = Join-Path $LogDirectory "visits_debt_$stamp.log"
    $runner = Join-Path $ProjectRoot 'scripts\load_unconfirmed_service_debt_movement_incremental.py'

    Push-Location $ProjectRoot
    try {
        & $PythonExe $runner --run *>&1 | Tee-Object -FilePath $logPath
        $runnerExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($runnerExit -ne 0) {
        & eventcreate.exe /T ERROR /ID 101 /L APPLICATION /SO $taskSource /D "Bounded visits-debt refresh failed; exit=$runnerExit; log=$logPath" | Out-Null
        exit $runnerExit
    }

    & eventcreate.exe /T INFORMATION /ID 100 /L APPLICATION /SO $taskSource /D "Bounded visits-debt refresh succeeded; log=$logPath" | Out-Null
    exit 0
}
catch {
    $message = $_.Exception.Message
    try {
        & eventcreate.exe /T ERROR /ID 102 /L APPLICATION /SO $taskSource /D "Bounded visits-debt scheduler wrapper failed; $message" | Out-Null
    }
    catch {
        # Task Scheduler still records the non-zero LastTaskResult.
    }
    Write-Error $message
    exit 1
}
