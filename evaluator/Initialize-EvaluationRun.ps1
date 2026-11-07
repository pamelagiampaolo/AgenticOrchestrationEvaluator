<#
.SYNOPSIS
Fase di ingresso della valutazione: valida l'input e prepara la run.

.PARAMETER SubmissionPath
Directory con una copia completa di `BenchmarkTarget`.

.PARAMETER TaskId
Uno tra T1..T6.

.PARAMETER RunsRoot
Default: runs/ nel repository del valutatore.

.PARAMETER RunId
Facoltativo; se omesso viene generato.

.OUTPUTS
Un oggetto JSON su stdout con `status` (`ready` oppure un esito del contratto),
`diagnostics` e, se pronto, percorsi e impronta della submission.

.NOTES
Exit code: 0 se `ready`; altrimenti l'exit code dell'esito (20 invalid-input,
30 integrity-error, 40 evaluator-error). Questo script non esegue build ne' test.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$SubmissionPath,
    [Parameter(Mandatory)][AllowEmptyString()][string]$TaskId,
    [string]$RunsRoot,
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'EvaluationInput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

if (-not $RunsRoot) { $RunsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'runs' }

$outcome = $null
$diagnostic = $null
$run = $null
try {
    $run = New-EvaluationRun -SubmissionPath $SubmissionPath -TaskId $TaskId -RunsRoot $RunsRoot -RunId $RunId
}
catch [System.ArgumentException] {
    $outcome = 'invalid-input'; $diagnostic = $_.Exception.Message
}
catch [System.IO.InvalidDataException] {
    $outcome = 'integrity-error'; $diagnostic = $_.Exception.Message
}
catch {
    $outcome = 'evaluator-error'; $diagnostic = "Errore del valutatore durante l'ingresso: $($_.Exception.GetType().Name)"
}

if ($null -ne $outcome) {
    [ordered]@{ status = $outcome; diagnostics = @($diagnostic) } | ConvertTo-Json -Depth 5
    exit (Get-EvaluationExitCode -Outcome $outcome)
}

[ordered]@{
    status                 = 'ready'
    runId                  = $run.runId
    runDirectory           = $run.runDirectory
    archivedSubmissionPath = $run.archivedSubmissionPath
    workSubmissionPath     = $run.workSubmissionPath
    treeSha256             = $run.treeSha256
    fileCount              = $run.fileCount
    diagnostics            = @()
} | ConvertTo-Json -Depth 5
exit 0
