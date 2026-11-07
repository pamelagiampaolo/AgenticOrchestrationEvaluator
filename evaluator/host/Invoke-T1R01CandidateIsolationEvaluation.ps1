[CmdletBinding()]
param([ValidateRange(1, 300)][int]$TimeoutSeconds = 120)
$ErrorActionPreference = 'Stop'
$evaluatorRoot = Split-Path -Parent $PSScriptRoot; $trustedRoot = Split-Path -Parent $evaluatorRoot; $guestRoot = Join-Path $evaluatorRoot 'guest'; $runtimeNode = (Get-Command node.exe -ErrorAction Stop).Source; $wsbPath = (Get-Command wsb.exe -ErrorAction Stop).Source
$runId = [guid]::NewGuid().ToString('N'); $runRoot = Join-Path $trustedRoot "runs\$runId"; $inputRoot = Join-Path $runRoot 'worker-input'; $outputRoot = Join-Path $runRoot 'worker-output'; $evidenceRoot = Join-Path $runRoot 'evidence'; $summaryPath = Join-Path $evidenceRoot 'evaluation-summary.json'; $sandboxId = $null; $stopSucceeded = $false
$wsbExecStdoutPath = Join-Path $evidenceRoot 'wsb-exec.stdout.txt'; $wsbExecStderrPath = Join-Path $evidenceRoot 'wsb-exec.stderr.txt'; $wsbExecResultPath = Join-Path $evidenceRoot 'wsb-exec-result.json'

function ConvertTo-QuotedProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-WsbExecDiagnostic {
    param([string]$Id, [string]$Command, [int]$Timeout)
    $arguments = @('exec', '--id', $Id, '--command', $Command, '--run-as', 'System', '--raw')
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $wsbPath
    $startInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [ordered]@{ timedOut = $false; exitCode = $null; stdout = ''; stderr = 'wsb-exec-process-start-failed' }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Timeout * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch [InvalidOperationException] { }
            $process.WaitForExit()
        }
        return [ordered]@{
            timedOut = $timedOut
            exitCode = $(if ($timedOut) { $null } else { $process.ExitCode })
            stdout = $stdoutTask.GetAwaiter().GetResult()
            stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    catch {
        return [ordered]@{ timedOut = $false; exitCode = $null; stdout = ''; stderr = $_.Exception.ToString() }
    }
    finally { $process.Dispose() }
}

function Save-WsbExecDiagnostic {
    param($Result)
    [string]$Result.stdout | Set-Content -Encoding utf8 -LiteralPath $wsbExecStdoutPath
    [string]$Result.stderr | Set-Content -Encoding utf8 -LiteralPath $wsbExecStderrPath
    [ordered]@{ timedOut = [bool]$Result.timedOut; exitCode = $Result.exitCode } | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 -LiteralPath $wsbExecResultPath
}
New-Item -ItemType Directory -Path (Join-Path $inputRoot 'runtime'),(Join-Path $inputRoot 'reserved'),(Join-Path $inputRoot 'candidate\submission\src'),$outputRoot,$evidenceRoot -Force | Out-Null
Copy-Item $runtimeNode (Join-Path $inputRoot 'runtime\node.exe'); Copy-Item (Join-Path $trustedRoot 'reserved\t1-r01-ipc-runner.ps1') (Join-Path $inputRoot 'reserved\t1-r01-ipc-runner.ps1'); Copy-Item (Join-Path $guestRoot 'T1CandidateProcess.mjs') (Join-Path $inputRoot 'candidate\T1CandidateProcess.mjs'); Copy-Item (Join-Path $trustedRoot 'fixtures\t1-ipc-compliant\src\index.mjs') (Join-Path $inputRoot 'candidate\submission\src\index.mjs'); Copy-Item (Join-Path $guestRoot 'Run-T1R01CandidateIsolationGuest.ps1') (Join-Path $inputRoot 'Run-T1R01CandidateIsolationGuest.ps1')
$escapedInput = [Security.SecurityElement]::Escape($inputRoot); $escapedOutput = [Security.SecurityElement]::Escape($outputRoot)
$configuration = "<Configuration><VGpu>Disable</VGpu><Networking>Disable</Networking><ClipboardRedirection>Disable</ClipboardRedirection><MappedFolders><MappedFolder><HostFolder>$escapedInput</HostFolder><SandboxFolder>C:\EvaluatorInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder><MappedFolder><HostFolder>$escapedOutput</HostFolder><SandboxFolder>C:\EvaluatorOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder></MappedFolders></Configuration>"
try {
    $startText = (& $wsbPath start --config $configuration --raw 2>&1 | Out-String).Trim(); if ($LASTEXITCODE -ne 0) { throw "sandbox-start-failed:$startText" }; $sandboxId = [string](($startText | ConvertFrom-Json).Id)
    $command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EvaluatorInput\Run-T1R01CandidateIsolationGuest.ps1'
    $exec = Invoke-WsbExecDiagnostic -Id $sandboxId -Command $command -Timeout $TimeoutSeconds
    Save-WsbExecDiagnostic -Result $exec
    if ($exec.timedOut) { throw 'sandbox-exec-timeout' }
    if ($null -eq $exec.exitCode) { throw 'sandbox-exec-no-exit-code' }
    if ([int]$exec.exitCode -ne 0) { throw "sandbox-exec-failed:$($exec.exitCode)" }
    if (-not (Test-Path (Join-Path $outputRoot 'guest-result.json'))) { throw 'guest-result-missing' }; if (-not (Test-Path (Join-Path $outputRoot 't1-r01-isolation-report.json'))) { throw 'isolation-report-missing' }
    $guest = Get-Content -Raw (Join-Path $outputRoot 'guest-result.json') | ConvertFrom-Json; $report = Get-Content -Raw (Join-Path $outputRoot 't1-r01-isolation-report.json') | ConvertFrom-Json
}
finally { if ($sandboxId) { & $wsbPath stop --id $sandboxId --raw | Out-Null; $stopSucceeded = ($LASTEXITCODE -eq 0) } }
[ordered]@{ schemaVersion = 1; probeId = 'T1-R01-separated-identity-v1'; runId = $runId; evaluator = [ordered]@{ status = $(if ($guest.successful -and $report.passed -and $stopSucceeded) { 'completed' } else { 'test-failures' }) }; control = [ordered]@{ id = 'T1-R01'; passed = [bool]$report.queryPassed }; isolation = [ordered]@{ reservedReadDenied = [bool]$report.reservedReadDenied; candidateIdentityDistinct = [bool]$report.candidateIdentityDistinct; sandboxStopped = $stopSucceeded } } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $summaryPath
Write-Output "RUN_ID=$runId"; Write-Output "SUMMARY=$summaryPath"
if (-not $guest.successful -or -not $report.passed -or -not $stopSucceeded) { exit 10 }; exit 0
