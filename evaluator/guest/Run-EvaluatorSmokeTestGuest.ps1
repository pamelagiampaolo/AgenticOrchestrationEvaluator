[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$inputRoot = 'C:\EvaluatorInput'
$outputRoot = 'C:\EvaluatorOutput'
$workRoot = 'C:\EvaluatorWork'
$runtimeRoot = Join-Path $workRoot 'runtime'
$nodePath = Join-Path $runtimeRoot 'node.exe'
$vitestPath = Join-Path $runtimeRoot 'node_modules\vitest\vitest.mjs'
$rawReportPath = Join-Path $outputRoot 'reserved-raw-report.json'
$guestResultPath = Join-Path $outputRoot 'guest-result.json'
$startedAt = [DateTimeOffset]::UtcNow

Copy-Item -LiteralPath $inputRoot -Destination $workRoot -Recurse -Force
$env:PATH = "$runtimeRoot;$env:WINDIR\System32;$env:WINDIR"
$env:NODE_OPTIONS = '--no-network-family-autoselection'

$process = Start-Process -FilePath $nodePath `
    -ArgumentList @(
        $vitestPath,
        'run',
        '--config', (Join-Path $workRoot 'reserved\vitest.reserved.config.ts'),
        '--root', $workRoot,
        '--reporter=json',
        "--outputFile=$rawReportPath"
    ) `
    -WorkingDirectory $workRoot `
    -RedirectStandardOutput (Join-Path $outputRoot 'vitest.stdout.txt') `
    -RedirectStandardError (Join-Path $outputRoot 'vitest.stderr.txt') `
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
    exitCode = $process.ExitCode
    rawReportPresent = (Test-Path -LiteralPath $rawReportPath)
    noUpNonLoopbackAdapters = ($upNonLoopbackAdapters.Count -eq 0)
    durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
} | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $guestResultPath

exit $process.ExitCode
