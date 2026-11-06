[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('T1', 'T2', 'T3', 'T4', 'T5', 'T6')]
    [string]$TaskId,

    [Parameter(Mandatory)]
    [ValidateSet('compliant', 'violating')]
    [string]$FixtureId,

    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$trustedRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = 'C:\Users\Utente\TesiAgenticAI'
$submissionSource = Join-Path $trustedRoot "fixtures\t5-r02-r03\$FixtureId"
$reservedSource = Join-Path $trustedRoot 'reserved'
$guestScriptSource = Join-Path $PSScriptRoot 'Run-T5R02R03Guest.ps1'
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$dependencySource = Join-Path $repositoryRoot 'BenchmarkTarget\node_modules'
$wsbPath = (Get-Command wsb.exe -ErrorAction Stop).Source
$probeId = 'T5-R02-R03-v1'
$submissionId = "t5-r02-r03-$FixtureId-v1"
$runId = [guid]::NewGuid().ToString('N')
$runRoot = Join-Path $trustedRoot "runs\$runId"
$inputRoot = Join-Path $runRoot 'worker-input'
$submissionRoot = Join-Path $inputRoot 'submission'
$runtimeRoot = Join-Path $inputRoot 'runtime'
$outputRoot = Join-Path $runRoot 'worker-output'
$evidenceRoot = Join-Path $runRoot 'evidence'
$rawReportPath = Join-Path $outputRoot 'reserved-raw-report.json'
$guestResultPath = Join-Path $outputRoot 'guest-result.json'
$manifestPath = Join-Path $evidenceRoot 'submission-manifest.json'
$summaryPath = Join-Path $evidenceRoot 'evaluation-summary.json'
$sandboxId = $null
$stopSucceeded = $false
$startedAt = [DateTimeOffset]::UtcNow

function Get-TreeManifest {
    param([string]$Root)
    return @(
        Get-ChildItem -LiteralPath $Root -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    relativePath = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
                    length = $_.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
                }
            }
    )
}

function Get-ManifestDigest {
    param($Manifest)
    $text = $Manifest | ConvertTo-Json -Depth 5 -Compress
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '')
    }
    finally { $algorithm.Dispose() }
}

function ConvertTo-QuotedProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-WsbExec {
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
    if (-not $process.Start()) { throw 'Impossibile avviare wsb exec.' }
    try {
        if (-not $process.WaitForExit($Timeout * 1000)) {
            try { $process.Kill($true) } catch [InvalidOperationException] { }
            return [ordered]@{ timedOut = $true; exitCode = $null }
        }
        return [ordered]@{ timedOut = $false; exitCode = $process.ExitCode }
    }
    finally { $process.Dispose() }
}

function Get-ActiveSandboxCount {
    $result = & $wsbPath list --raw | ConvertFrom-Json
    return @($result.WindowsSandboxEnvironments).Count
}

$repositoryPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($trustedRoot.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $trustedRoot.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'L area fidata deve essere esterna al repository.'
}
if ((Get-ActiveSandboxCount) -ne 0) {
    throw 'La prova richiede zero Sandbox attive all avvio.'
}

New-Item -ItemType Directory -Path $inputRoot, $runtimeRoot, $outputRoot, $evidenceRoot -Force | Out-Null
Copy-Item -LiteralPath $submissionSource -Destination $submissionRoot -Recurse -Force
Copy-Item -LiteralPath $reservedSource -Destination $inputRoot -Recurse -Force
Copy-Item -LiteralPath $guestScriptSource -Destination (Join-Path $inputRoot 'Run-ReservedSmokeGuest.ps1')
Copy-Item -LiteralPath $nodePath -Destination (Join-Path $runtimeRoot 'node.exe')
Copy-Item -LiteralPath $dependencySource -Destination (Join-Path $runtimeRoot 'node_modules') -Recurse -Force

$manifestBefore = Get-TreeManifest -Root $submissionRoot
$digestBefore = Get-ManifestDigest -Manifest $manifestBefore
[ordered]@{
    schemaVersion = 1
    submissionId = $submissionId
    treeSha256 = $digestBefore
    fileCount = $manifestBefore.Count
    files = $manifestBefore
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath $manifestPath

$escapedInput = [Security.SecurityElement]::Escape($inputRoot)
$escapedOutput = [Security.SecurityElement]::Escape($outputRoot)
$configuration = @"
<Configuration>
  <VGpu>Disable</VGpu><Networking>Disable</Networking>
  <AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput>
  <ProtectedClient>Enable</ProtectedClient><PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>$escapedInput</HostFolder><SandboxFolder>C:\EvaluatorInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$escapedOutput</HostFolder><SandboxFolder>C:\EvaluatorOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
</Configuration>
"@

$evaluationStatus = 'evaluator-error'
$errorCode = $null
$counts = [ordered]@{ total = $null; passed = $null; failed = $null; skipped = $null; todo = $null }
$r02Passed = $null
$r03Passed = $null
$controlResultsValid = $false
$guestDurationMs = $null
$networkDisabledObserved = $false

try {
    $startText = (& $wsbPath start --config $configuration --raw 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "wsb start non riuscito: $startText" }
    $sandboxId = [string](($startText | ConvertFrom-Json).Id)
    if ([string]::IsNullOrWhiteSpace($sandboxId)) { throw 'wsb start non ha restituito un ID.' }
    $guestCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EvaluatorInput\Run-ReservedSmokeGuest.ps1 -TaskId $TaskId"
    $exec = Invoke-WsbExec -Id $sandboxId -Command $guestCommand -Timeout $TimeoutSeconds
    if ($exec.timedOut) {
        $errorCode = 'timeout'
    }
    elseif (-not (Test-Path -LiteralPath $guestResultPath) -or -not (Test-Path -LiteralPath $rawReportPath)) {
        $errorCode = 'missing-report'
    }
    else {
        try {
            $guestResult = Get-Content -Raw -LiteralPath $guestResultPath | ConvertFrom-Json
            $rawReport = Get-Content -Raw -LiteralPath $rawReportPath | ConvertFrom-Json
            $counts.total = [int]$rawReport.numTotalTests
            $counts.passed = [int]$rawReport.numPassedTests
            $counts.failed = [int]$rawReport.numFailedTests
            $counts.skipped = [int]$rawReport.numPendingTests
            $counts.todo = [int]$rawReport.numTodoTests
            $assertions = @($rawReport.testResults | ForEach-Object { $_.assertionResults })
            $r02Assertions = @($assertions | Where-Object { $_.title -eq 'T5-R02-shared' })
            $r03Assertions = @($assertions | Where-Object { $_.title -eq 'T5-R03' })
            $controlResultsValid = ($r02Assertions.Count -eq 1 -and $r03Assertions.Count -eq 1)
            if ($controlResultsValid) {
                $r02Passed = ($r02Assertions[0].status -eq 'passed')
                $r03Passed = ($r03Assertions[0].status -eq 'passed')
            }
            $guestDurationMs = [int64]$guestResult.durationMs
            $networkDisabledObserved = [bool]$guestResult.noUpNonLoopbackAdapters
            $evaluationStatus = if ([int]$guestResult.exitCode -eq 0 -and $counts.failed -eq 0) { 'completed' } else { 'test-failures' }
        }
        catch { $errorCode = 'invalid-report' }
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($sandboxId)) {
        & $wsbPath stop --id $sandboxId --raw | Out-Null
        $stopSucceeded = ($LASTEXITCODE -eq 0)
        $sandboxId = $null
    }
}

$manifestAfter = Get-TreeManifest -Root $submissionRoot
$digestAfter = Get-ManifestDigest -Manifest $manifestAfter
$activeSandboxCount = Get-ActiveSandboxCount
$manifestUnchanged = ($digestBefore -eq $digestAfter)
$exactlyTwoExecuted = ($counts.total -eq 2 -and ($counts.passed + $counts.failed) -eq 2 -and $counts.skipped -eq 0 -and $counts.todo -eq 0)
$allControlsPassed = ($r02Passed -eq $true -and $r03Passed -eq $true)
$evaluationReliable = ($evaluationStatus -in @('completed', 'test-failures') -and $null -eq $errorCode -and $exactlyTwoExecuted -and $controlResultsValid -and $manifestUnchanged -and $networkDisabledObserved -and $stopSucceeded -and $activeSandboxCount -eq 0)

[ordered]@{
    schemaVersion = 1
    probeId = $probeId
    runId = $runId
    submission = [ordered]@{ id = $submissionId; treeSha256 = $digestBefore }
    evaluator = [ordered]@{ status = $evaluationStatus; errorCode = $errorCode; successful = $evaluationReliable }
    controls = @(
        [ordered]@{ id = 'T5-R02'; passed = $r02Passed; sharedCoverage = 'T5-P04' }
        [ordered]@{ id = 'T5-R03'; passed = $r03Passed }
    )
    counts = $counts
    durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
    guestDurationMs = $guestDurationMs
    checks = [ordered]@{
        exactlyTwoExecuted = $exactlyTwoExecuted
        controlResultsValid = $controlResultsValid
        manifestUnchanged = $manifestUnchanged
        networkDisabledObserved = $networkDisabledObserved
        sandboxStopped = ($stopSucceeded -and $activeSandboxCount -eq 0)
    }
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath $summaryPath

Write-Output "RUN_ID=$runId"
Write-Output "SUMMARY=$summaryPath"
Write-Output "RAW_REPORT=$rawReportPath"
if (-not $evaluationReliable) { exit 20 }
if (-not $allControlsPassed) { exit 10 }
exit 0
