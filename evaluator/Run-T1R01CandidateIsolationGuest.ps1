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
$candidatePassword = 'Ax7!mQ2#vR9@pz'
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

function Get-SanitizedNativeMessages {
    param([AllowNull()][string]$Text, [ValidateRange(0, 4)][int]$Limit = 4)
    if ($Limit -eq 0) { return @() }
    return @(([string]$Text -split '[\r\n]+') |
        ForEach-Object { Protect-DiagnosticText $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First $Limit)
}

function Write-NativeDiagnostic {
    param(
        [string]$Tool,
        [int]$ExitCode,
        [AllowNull()][string]$Stdout,
        [AllowNull()][string]$Stderr,
        [switch]$SuppressMessages
    )
    Write-Diagnostic "native=$Tool exitCode=$ExitCode"
    if ($SuppressMessages) { return }
    $stdoutMessages = @(Get-SanitizedNativeMessages -Text $Stdout -Limit 4)
    $stderrMessages = @(Get-SanitizedNativeMessages -Text $Stderr -Limit (4 - $stdoutMessages.Count))
    Write-Diagnostic "native=$Tool stream=stdout messages=$($stdoutMessages -join ' | ')"
    Write-Diagnostic "native=$Tool stream=stderr messages=$($stderrMessages -join ' | ')"
}

function Invoke-NativeWithCapturedStreams {
    param([string]$FilePath, [string[]]$ArgumentList)
    $temporaryRoot = [IO.Path]::GetTempPath()
    $temporaryId = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $temporaryRoot "t1-r01-$temporaryId.stdout.tmp"
    $stderrPath = Join-Path $temporaryRoot "t1-r01-$temporaryId.stderr.tmp"
    $previousPreference = $ErrorActionPreference
    try {
        try {
            $ErrorActionPreference = 'Continue'
            & $FilePath @ArgumentList 1> $stdoutPath 2> $stderrPath
            $nativeExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { '' }
        return [ordered]@{ exitCode = $nativeExitCode; stdout = [string]$stdout; stderr = [string]$stderr }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-OnlySystemAccess {
    param([string]$Path)
    $nativeResult = Invoke-NativeWithCapturedStreams -FilePath 'icacls.exe' -ArgumentList @($Path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '/T', '/C')
    Write-NativeDiagnostic -Tool 'icacls.exe' -ExitCode $nativeResult.exitCode -Stdout $nativeResult.stdout -Stderr $nativeResult.stderr -SuppressMessages:($Path -eq $reservedRoot)
    if ($nativeResult.exitCode -ne 0) { throw "acl-system-only-failed:$Path" }
}

function Grant-CandidateReadExecute {
    param([string]$Path, [string]$CandidateSid)
    $nativeResult = Invoke-NativeWithCapturedStreams -FilePath 'icacls.exe' -ArgumentList @($Path, '/grant:r', "*$CandidateSid`:(OI)(CI)RX", '/T', '/C')
    Write-NativeDiagnostic -Tool 'icacls.exe' -ExitCode $nativeResult.exitCode -Stdout $nativeResult.stdout -Stderr $nativeResult.stderr
    if ($nativeResult.exitCode -ne 0) { throw "acl-candidate-read-failed:$Path" }
}

try {
    Set-DiagnosticPhase 'copy-files'
    Copy-Item -LiteralPath $inputRoot -Destination $workRoot -Recurse -Force

    Set-DiagnosticPhase 'create-trusted-output'
    New-Item -ItemType Directory -Path $trustedOutputRoot -Force | Out-Null

    Set-DiagnosticPhase 'create-user'
    $netResult = Invoke-NativeWithCapturedStreams -FilePath 'net.exe' -ArgumentList @('user', $candidateUser, $candidatePassword, '/add', '/expires:never', '/passwordchg:no')
    Write-NativeDiagnostic -Tool 'net.exe' -ExitCode $netResult.exitCode -Stdout $netResult.stdout -Stderr $netResult.stderr
    if ($netResult.exitCode -ne 0) { throw 'candidate-identity-creation-failed' }

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
