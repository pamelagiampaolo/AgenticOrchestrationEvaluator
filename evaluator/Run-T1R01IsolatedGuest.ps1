[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$inputRoot = 'C:\EvaluatorInput'
$outputRoot = 'C:\EvaluatorOutput'
$workRoot = 'C:\EvaluatorWork'
$diagnosticPath = Join-Path $outputRoot 't1-r01-guest-diagnostics.log'
$currentPhase = 'entry'
"$([DateTimeOffset]::UtcNow.ToString('o')) phase=entry" | Set-Content -Encoding utf8 -LiteralPath $diagnosticPath

$runtimeRoot = Join-Path $workRoot 'runtime'
$reservedRoot = Join-Path $workRoot 'reserved'
$candidateRoot = Join-Path $workRoot 'candidate'
$trustedOutputRoot = Join-Path $workRoot 'trusted-output'
$reportPath = Join-Path $trustedOutputRoot 't1-r01-isolation-report.json'
$guestResultPath = Join-Path $outputRoot 'guest-result.json'
$candidateUser = 'TesiCandidate'
$candidatePassword = 'T3si-Ipc-Proof!2026'
$pipeName = 'tesi-t1-r01-' + [guid]::NewGuid().ToString('N')
$startedAt = [DateTimeOffset]::UtcNow

function Protect-DiagnosticText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $protected = $Text.Replace($candidatePassword, '[credential-redacted]')
    $protected = $protected.Replace($reservedRoot, '[reserved]')
    $protected = $protected.Replace($trustedOutputRoot, '[trusted-output]')
    return ($protected -replace '[\r\n]+', ' ').Trim()
}

function Write-Diagnostic {
    param([string]$Message)
    "$([DateTimeOffset]::UtcNow.ToString('o')) $(Protect-DiagnosticText $Message)" |
        Add-Content -Encoding utf8 -LiteralPath $diagnosticPath
}

function Set-DiagnosticPhase {
    param([string]$Phase)
    $script:currentPhase = $Phase
    Write-Diagnostic "phase=$Phase"
}

function Write-NativeDiagnostic {
    param([string]$Tool, [int]$ExitCode, [object[]]$Output)
    $messages = @($Output | ForEach-Object { Protect-DiagnosticText ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 4)
    Write-Diagnostic "native=$Tool exitCode=$ExitCode messages=$($messages -join ' | ')"
}

function Set-OnlySystemAccess {
    param([string]$Path)
    $nativeOutput = @(& icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' /T /C 2>&1)
    $nativeExitCode = $LASTEXITCODE
    $diagnosticOutput = if ($Path -eq $reservedRoot) { @() } else { $nativeOutput }
    Write-NativeDiagnostic -Tool 'icacls.exe' -ExitCode $nativeExitCode -Output $diagnosticOutput
    if ($nativeExitCode -ne 0) { throw "acl-system-only-failed:$Path" }
}

function Grant-CandidateReadExecute {
    param([string]$Path, [string]$CandidateSid)
    $nativeOutput = @(& icacls.exe $Path /grant:r "*$CandidateSid`:(OI)(CI)RX" /T /C 2>&1)
    $nativeExitCode = $LASTEXITCODE
    Write-NativeDiagnostic -Tool 'icacls.exe' -ExitCode $nativeExitCode -Output $nativeOutput
    if ($nativeExitCode -ne 0) { throw "acl-candidate-read-failed:$Path" }
}

try {
    Set-DiagnosticPhase 'copy-files'
    Copy-Item -LiteralPath $inputRoot -Destination $workRoot -Recurse -Force

    Set-DiagnosticPhase 'create-trusted-output'
    New-Item -ItemType Directory -Path $trustedOutputRoot -Force | Out-Null

    Set-DiagnosticPhase 'create-user'
    $netOutput = @(& net.exe user $candidateUser $candidatePassword /add /expires:never /passwordchg:no 2>&1)
    $netExitCode = $LASTEXITCODE
    Write-NativeDiagnostic -Tool 'net.exe' -ExitCode $netExitCode -Output $netOutput
    if ($netExitCode -ne 0) { throw 'candidate-identity-creation-failed' }

    Set-DiagnosticPhase 'resolve-sid'
    $account = [Security.Principal.NTAccount]::new("$env:COMPUTERNAME\$candidateUser")
    $candidateSid = $account.Translate([Security.Principal.SecurityIdentifier]).Value
    $candidateIdentity = "$env:COMPUTERNAME\$candidateUser"

    Set-DiagnosticPhase 'apply-acl-reserved'
    Set-OnlySystemAccess -Path $reservedRoot
    Set-DiagnosticPhase 'apply-acl-trusted-output'
    Set-OnlySystemAccess -Path $trustedOutputRoot
    Set-DiagnosticPhase 'apply-acl-runtime'
    Grant-CandidateReadExecute -Path $runtimeRoot -CandidateSid $candidateSid
    Set-DiagnosticPhase 'apply-acl-candidate'
    Grant-CandidateReadExecute -Path $candidateRoot -CandidateSid $candidateSid

    Set-DiagnosticPhase 'start-runner'
    $runnerPath = Join-Path $reservedRoot 't1-r01-ipc-runner.ps1'
    $reservedProbePath = $runnerPath
    $runner = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath,
        '-PipeName', $pipeName, '-CandidateSid', $candidateSid,
        '-CandidateIdentity', $candidateIdentity,
        '-ReservedProbePath', $reservedProbePath, '-ReportPath', $reportPath
    ) -RedirectStandardOutput (Join-Path $trustedOutputRoot 'runner.stdout.txt') `
      -RedirectStandardError (Join-Path $trustedOutputRoot 'runner.stderr.txt') `
      -PassThru -WindowStyle Hidden

    Set-DiagnosticPhase 'check-seclogon'
    $secondaryLogon = Get-Service -Name 'seclogon'
    if ($secondaryLogon.Status -ne 'Running') {
        Set-DiagnosticPhase 'start-seclogon'
        Start-Service -Name 'seclogon'
    }

    Set-DiagnosticPhase 'start-candidate'
    $credential = [Management.Automation.PSCredential]::new(
        $candidateIdentity,
        (ConvertTo-SecureString $candidatePassword -AsPlainText -Force))
    $candidate = Start-Process -FilePath (Join-Path $runtimeRoot 'node.exe') `
        -Credential $credential `
        -ArgumentList @(
            (Join-Path $candidateRoot 't1-candidate-host.mjs'),
            $pipeName,
            (Join-Path $candidateRoot 'submission\src\index.mjs')) `
        -WorkingDirectory $candidateRoot -Wait -PassThru -WindowStyle Hidden

    Set-DiagnosticPhase 'wait-runner'
    if (-not $runner.WaitForExit(30000)) {
        try { $runner.Kill() } catch [InvalidOperationException] { }
        throw 'trusted-runner-timeout'
    }

    Set-DiagnosticPhase 'read-report'
    if (-not (Test-Path -LiteralPath $reportPath)) { throw 'trusted-report-missing' }
    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

    Set-DiagnosticPhase 'publish-report'
    Copy-Item -LiteralPath $reportPath `
        -Destination (Join-Path $outputRoot 't1-r01-isolation-report.json') -Force

    Set-DiagnosticPhase 'publish-guest-result'
    [ordered]@{
        schemaVersion = 1
        candidateExitCode = $candidate.ExitCode
        runnerExitCode = $runner.ExitCode
        successful = ($candidate.ExitCode -eq 0 -and $runner.ExitCode -eq 0 -and $report.passed -eq $true)
        durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $guestResultPath

    if ($candidate.ExitCode -ne 0 -or $runner.ExitCode -ne 0 -or $report.passed -ne $true) { exit 10 }
    exit 0
}
catch {
    $exceptionType = $_.Exception.GetType().FullName
    $exceptionMessage = Protect-DiagnosticText $_.Exception.Message
    $lineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-Diagnostic "error phase=$currentPhase type=$exceptionType line=$lineNumber message=$exceptionMessage"
    exit 1
}
