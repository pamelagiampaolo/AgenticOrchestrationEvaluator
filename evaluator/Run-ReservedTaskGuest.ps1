[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('T1', 'T2', 'T3', 'T4', 'T5', 'T6')]
    [string]$TaskId
)

$ErrorActionPreference = 'Stop'
$inputRoot = 'C:\EvaluatorInput'
$outputRoot = 'C:\EvaluatorOutput'
$workRoot = 'C:\EvaluatorWork'
$runtimeRoot = Join-Path $workRoot 'runtime'
$nodePath = Join-Path $runtimeRoot 'node.exe'
$vitestPath = Join-Path $runtimeRoot 'node_modules\vitest\vitest.mjs'
$publicRawReportPath = Join-Path $outputRoot 'public-raw-report.json'
$reservedRawReportPath = Join-Path $outputRoot 'reserved-raw-report.json'
$guestResultPath = Join-Path $outputRoot 'guest-result.json'
$startedAt = [DateTimeOffset]::UtcNow

Copy-Item -LiteralPath $inputRoot -Destination $workRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $workRoot 'public-suite\tests') -Destination (Join-Path $workRoot 'submission\tests') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $workRoot 'public-suite\vitest.public-task.config.ts') -Destination (Join-Path $runtimeRoot 'vitest.public-task.config.ts') -Force
$env:PATH = "$runtimeRoot;$env:WINDIR\System32;$env:WINDIR"
$env:NODE_OPTIONS = '--no-network-family-autoselection'
$env:RESERVED_TASK_ID = $TaskId

$publicProcess = Start-Process -FilePath $nodePath `
    -ArgumentList @(
        $vitestPath,
        'run',
        '--config', (Join-Path $runtimeRoot 'vitest.public-task.config.ts'),
        '--root', (Join-Path $workRoot 'submission'),
        '--reporter=json',
        "--outputFile=$publicRawReportPath"
    ) `
    -WorkingDirectory (Join-Path $workRoot 'submission') `
    -RedirectStandardOutput (Join-Path $outputRoot 'public-vitest.stdout.txt') `
    -RedirectStandardError (Join-Path $outputRoot 'public-vitest.stderr.txt') `
    -Wait -PassThru -NoNewWindow

$reservedProcess = Start-Process -FilePath $nodePath `
    -ArgumentList @(
        $vitestPath,
        'run',
        '--config', (Join-Path $workRoot 'reserved\vitest.reserved-task.config.ts'),
        '--root', $workRoot,
        '--reporter=json',
        "--outputFile=$reservedRawReportPath"
    ) `
    -WorkingDirectory $workRoot `
    -RedirectStandardOutput (Join-Path $outputRoot 'reserved-vitest.stdout.txt') `
    -RedirectStandardError (Join-Path $outputRoot 'reserved-vitest.stderr.txt') `
    -Wait -PassThru -NoNewWindow

$upNonLoopbackAdapters = @(
    [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.OperationalStatus -eq [Net.NetworkInformation.OperationalStatus]::Up -and
            $_.NetworkInterfaceType -ne [Net.NetworkInformation.NetworkInterfaceType]::Loopback
        }
)

[ordered]@{
    schemaVersion = 1
    publicExitCode = $publicProcess.ExitCode
    reservedExitCode = $reservedProcess.ExitCode
    publicRawReportPresent = (Test-Path -LiteralPath $publicRawReportPath)
    reservedRawReportPresent = (Test-Path -LiteralPath $reservedRawReportPath)
    noUpNonLoopbackAdapters = ($upNonLoopbackAdapters.Count -eq 0)
    durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
} | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $guestResultPath

if ($publicProcess.ExitCode -ne 0 -or $reservedProcess.ExitCode -ne 0) { exit 1 }
exit 0
