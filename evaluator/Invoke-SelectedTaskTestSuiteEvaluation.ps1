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
$publicTestsSource = Join-Path $repositoryRoot 'BenchmarkTarget\tests\public'
$publicConfigSource = Join-Path $repositoryRoot ("BenchmarkTarget\vitest.public.{0}.config.ts" -f $TaskId.ToLowerInvariant())
$guestScriptSource = Join-Path $PSScriptRoot 'Run-SelectedTaskTestSuiteGuest.ps1'
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
$publicRawReportPath = Join-Path $outputRoot 'public-raw-report.json'
$reservedRawReportPath = Join-Path $outputRoot 'reserved-raw-report.json'
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

function Read-VitestReport {
    param([string]$Path)
    $report = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $reportCounts = [ordered]@{
        total = [int]$report.numTotalTests
        passed = [int]$report.numPassedTests
        failed = [int]$report.numFailedTests
        skipped = [int]$report.numPendingTests
        todo = [int]$report.numTodoTests
    }
    if ($reportCounts.total -le 0 -or
        @($reportCounts.Values | Where-Object { $_ -lt 0 }).Count -ne 0 -or
        $reportCounts.total -ne ($reportCounts.passed + $reportCounts.failed + $reportCounts.skipped + $reportCounts.todo)) {
        throw 'I conteggi del report non sono validi.'
    }
    $reportAssertions = @($report.testResults | ForEach-Object { $_.assertionResults })
    if ($reportAssertions.Count -ne $reportCounts.total) {
        throw 'Il numero degli esiti non coincide con il totale dichiarato.'
    }
    return [ordered]@{ counts = $reportCounts; assertions = $reportAssertions }
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
$publicSuiteRoot = Join-Path $inputRoot 'public-suite'
New-Item -ItemType Directory -Path (Join-Path $publicSuiteRoot 'tests') -Force | Out-Null
Copy-Item -LiteralPath $publicTestsSource -Destination (Join-Path $publicSuiteRoot 'tests\public') -Recurse -Force
Copy-Item -LiteralPath $publicConfigSource -Destination (Join-Path $publicSuiteRoot 'vitest.public-task.config.ts') -Force
Copy-Item -LiteralPath $guestScriptSource -Destination (Join-Path $inputRoot 'Run-SelectedTaskTestSuiteGuest.ps1')
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
$publicCounts = [ordered]@{ total = $null; passed = $null; failed = $null; skipped = $null; todo = $null }
$reservedCounts = [ordered]@{ total = $null; passed = $null; failed = $null; skipped = $null; todo = $null }
$counts = [ordered]@{ total = $null; passed = $null; failed = $null; skipped = $null; todo = $null }
$controlResults = @()
$sharedCoverageResults = @()
$controlResultsValid = $false
$guestDurationMs = $null
$networkDisabledObserved = $false

try {
    $startText = (& $wsbPath start --config $configuration --raw 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "wsb start non riuscito: $startText" }
    $sandboxId = [string](($startText | ConvertFrom-Json).Id)
    if ([string]::IsNullOrWhiteSpace($sandboxId)) { throw 'wsb start non ha restituito un ID.' }
    $guestCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EvaluatorInput\Run-SelectedTaskTestSuiteGuest.ps1 -TaskId $TaskId"
    $exec = Invoke-WsbExec -Id $sandboxId -Command $guestCommand -Timeout $TimeoutSeconds
    if ($exec.timedOut) {
        $errorCode = 'timeout'
    }
    elseif (-not (Test-Path -LiteralPath $guestResultPath) -or
            -not (Test-Path -LiteralPath $publicRawReportPath) -or
            -not (Test-Path -LiteralPath $reservedRawReportPath)) {
        $errorCode = 'missing-report'
    }
    else {
        try {
            $guestResult = Get-Content -Raw -LiteralPath $guestResultPath | ConvertFrom-Json
            $publicReport = Read-VitestReport -Path $publicRawReportPath
            $reservedReport = Read-VitestReport -Path $reservedRawReportPath
            $publicCounts = $publicReport.counts
            $reservedCounts = $reservedReport.counts
            $publicAssertions = @($publicReport.assertions)
            $assertions = @($reservedReport.assertions)

            $controlIdPattern = '^' + [regex]::Escape($TaskId) + '-R\d{2}'
            $controlTitlePattern = $controlIdPattern + '(?:-shared)?(?:\s+.+)?$'
            $invalidAssertions = @($assertions | Where-Object {
                [string]$_.title -notmatch $controlTitlePattern -or
                [string]$_.status -notin @('passed', 'failed', 'pending', 'todo')
            })
            if ($invalidAssertions.Count -ne 0) {
                throw 'Il report contiene esiti non appartenenti alla suite selezionata.'
            }

            $normalizedIds = @($assertions | ForEach-Object {
                [regex]::Match([string]$_.title, $controlIdPattern).Value
            })
            if (@($normalizedIds | Group-Object | Where-Object { $_.Count -ne 1 }).Count -ne 0) {
                throw 'Il report contiene controlli duplicati.'
            }

            $controlResults = @($assertions | Sort-Object title | ForEach-Object {
                $controlId = [regex]::Match([string]$_.title, $controlIdPattern).Value
                $result = [ordered]@{
                    id = $controlId
                    passed = ([string]$_.status -eq 'passed')
                }
                if ($controlId -eq 'T5-R02') {
                    $result.sharedCoverage = 'T5-P04'
                }
                $result
            })
            $controlResultsValid = ($controlResults.Count -eq $reservedCounts.total)

            $sharedCoverageMap = [ordered]@{
                'T2-R03' = 'T2-P02'
                'T5-R02' = 'T5-P04'
                'T6-R04' = 'T6-P03'
            }
            $deduplicatedTotal = 0
            $deduplicatedPassed = 0
            $deduplicatedFailed = 0
            foreach ($control in $controlResults) {
                if (-not $sharedCoverageMap.Contains($control.id)) { continue }
                $publicId = [string]$sharedCoverageMap[$control.id]
                $publicMatches = @($publicAssertions | Where-Object { [string]$_.title -match ('^' + [regex]::Escape($publicId) + '(?:\s+.+)?$') })
                if ($publicMatches.Count -eq 0) { continue }
                if ($publicMatches.Count -ne 1) { throw 'La copertura pubblica condivisa non e univoca.' }
                $publicPassed = ([string]$publicMatches[0].status -eq 'passed')
                $deduplicatedTotal++
                if ($control.passed -and $publicPassed) { $deduplicatedPassed++ }
                elseif (-not $control.passed -and -not $publicPassed) { $deduplicatedFailed++ }
                else { $deduplicatedPassed++ }
                $sharedCoverageResults += [ordered]@{ reservedId = $control.id; publicId = $publicId; countedOnce = $true }
            }

            $counts.total = $publicCounts.total + $reservedCounts.total - $deduplicatedTotal
            $counts.passed = $publicCounts.passed + $reservedCounts.passed - $deduplicatedPassed
            $counts.failed = $publicCounts.failed + $reservedCounts.failed - $deduplicatedFailed
            $counts.skipped = $publicCounts.skipped + $reservedCounts.skipped
            $counts.todo = $publicCounts.todo + $reservedCounts.todo
            $guestDurationMs = [int64]$guestResult.durationMs
            $networkDisabledObserved = [bool]$guestResult.noUpNonLoopbackAdapters
            $evaluationStatus = if ([int]$guestResult.publicExitCode -eq 0 -and [int]$guestResult.reservedExitCode -eq 0 -and $counts.failed -eq 0) { 'completed' } else { 'test-failures' }
        }
        catch {
            $evaluationStatus = 'evaluator-error'
            $errorCode = 'invalid-report'
            $controlResults = @()
            $controlResultsValid = $false
        }
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
$allSelectedTestsExecuted = ($publicCounts.total -gt 0 -and $reservedCounts.total -gt 0 -and
    ($publicCounts.passed + $publicCounts.failed) -eq $publicCounts.total -and
    ($reservedCounts.passed + $reservedCounts.failed) -eq $reservedCounts.total -and
    $publicCounts.skipped -eq 0 -and $publicCounts.todo -eq 0 -and
    $reservedCounts.skipped -eq 0 -and $reservedCounts.todo -eq 0)
$allControlsPassed = ($counts.total -gt 0 -and $counts.failed -eq 0 -and $counts.skipped -eq 0 -and $counts.todo -eq 0)
$evaluationReliable = ($evaluationStatus -in @('completed', 'test-failures') -and $null -eq $errorCode -and $allSelectedTestsExecuted -and $controlResultsValid -and $manifestUnchanged -and $networkDisabledObserved -and $stopSucceeded -and $activeSandboxCount -eq 0)

[ordered]@{
    schemaVersion = 1
    probeId = $probeId
    runId = $runId
    submission = [ordered]@{ id = $submissionId; treeSha256 = $digestBefore }
    evaluator = [ordered]@{ status = $evaluationStatus; errorCode = $errorCode; successful = $evaluationReliable }
    suites = [ordered]@{
        public = [ordered]@{ counts = $publicCounts }
        reserved = [ordered]@{ counts = $reservedCounts }
    }
    controls = $controlResults
    sharedCoverage = $sharedCoverageResults
    counts = $counts
    durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
    guestDurationMs = $guestDurationMs
    checks = [ordered]@{
        allSelectedTestsExecuted = $allSelectedTestsExecuted
        controlResultsValid = $controlResultsValid
        manifestUnchanged = $manifestUnchanged
        networkDisabledObserved = $networkDisabledObserved
        sandboxStopped = ($stopSucceeded -and $activeSandboxCount -eq 0)
    }
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath $summaryPath

Write-Output "RUN_ID=$runId"
Write-Output "SUMMARY=$summaryPath"
Write-Output "PUBLIC_RAW_REPORT=$publicRawReportPath"
Write-Output "RESERVED_RAW_REPORT=$reservedRawReportPath"
if (-not $evaluationReliable) { exit 20 }
if (-not $allControlsPassed) { exit 10 }
exit 0
