[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$inputRoot = 'C:\EvaluatorInput'; $outputRoot = 'C:\EvaluatorOutput'; $workRoot = 'C:\EvaluatorWork'
$runtimeRoot = Join-Path $workRoot 'runtime'; $reservedRoot = Join-Path $workRoot 'reserved'; $candidateRoot = Join-Path $workRoot 'candidate'; $trustedOutputRoot = Join-Path $workRoot 'trusted-output'
$reportPath = Join-Path $trustedOutputRoot 't1-r01-isolation-report.json'; $guestResultPath = Join-Path $outputRoot 'guest-result.json'
$candidateUser = 'TesiCandidate'; $candidatePassword = 'T3si-Ipc-Proof!2026'; $pipeName = 'tesi-t1-r01-' + [guid]::NewGuid().ToString('N'); $startedAt = [DateTimeOffset]::UtcNow
Copy-Item -LiteralPath $inputRoot -Destination $workRoot -Recurse -Force
New-Item -ItemType Directory -Path $trustedOutputRoot -Force | Out-Null
& net.exe user $candidateUser $candidatePassword /add /expires:never /passwordchg:no | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'candidate-identity-creation-failed' }
$account = [Security.Principal.NTAccount]::new("$env:COMPUTERNAME\$candidateUser")
$candidateSid = $account.Translate([Security.Principal.SecurityIdentifier]).Value
$candidateIdentity = "$env:COMPUTERNAME\$candidateUser"
function Set-OnlySystemAccess { param([string]$Path) & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' /T /C | Out-Null; if ($LASTEXITCODE -ne 0) { throw "acl-system-only-failed:$Path" } }
function Grant-CandidateReadExecute { param([string]$Path) & icacls.exe $Path /grant:r "*$candidateSid`:(OI)(CI)RX" /T /C | Out-Null; if ($LASTEXITCODE -ne 0) { throw "acl-candidate-read-failed:$Path" } }
Set-OnlySystemAccess $reservedRoot; Set-OnlySystemAccess $trustedOutputRoot; Grant-CandidateReadExecute $runtimeRoot; Grant-CandidateReadExecute $candidateRoot
$runnerPath = Join-Path $reservedRoot 't1-r01-ipc-runner.ps1'; $reservedProbePath = $runnerPath
$runner = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerPath,'-PipeName',$pipeName,'-CandidateSid',$candidateSid,'-CandidateIdentity',$candidateIdentity,'-ReservedProbePath',$reservedProbePath,'-ReportPath',$reportPath) -RedirectStandardOutput (Join-Path $trustedOutputRoot 'runner.stdout.txt') -RedirectStandardError (Join-Path $trustedOutputRoot 'runner.stderr.txt') -PassThru -WindowStyle Hidden
$secondaryLogon = Get-Service -Name 'seclogon'; if ($secondaryLogon.Status -ne 'Running') { Start-Service -Name 'seclogon' }
$credential = [Management.Automation.PSCredential]::new($candidateIdentity, (ConvertTo-SecureString $candidatePassword -AsPlainText -Force))
$candidate = Start-Process -FilePath (Join-Path $runtimeRoot 'node.exe') -Credential $credential -ArgumentList @((Join-Path $candidateRoot 't1-candidate-host.mjs'),$pipeName,(Join-Path $candidateRoot 'submission\src\index.mjs')) -WorkingDirectory $candidateRoot -Wait -PassThru -WindowStyle Hidden
if (-not $runner.WaitForExit(30000)) { try { $runner.Kill() } catch [InvalidOperationException] { }; throw 'trusted-runner-timeout' }
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'trusted-report-missing' }
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $outputRoot 't1-r01-isolation-report.json') -Force
[ordered]@{ schemaVersion = 1; candidateExitCode = $candidate.ExitCode; runnerExitCode = $runner.ExitCode; successful = ($candidate.ExitCode -eq 0 -and $runner.ExitCode -eq 0 -and $report.passed -eq $true); durationMs = [int64]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $guestResultPath
if ($candidate.ExitCode -ne 0 -or $runner.ExitCode -ne 0 -or $report.passed -ne $true) { exit 10 }
exit 0
