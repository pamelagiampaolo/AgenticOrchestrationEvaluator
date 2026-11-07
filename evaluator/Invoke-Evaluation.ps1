<#
.SYNOPSIS
Esegue una valutazione completa di una submission.

.PARAMETER SubmissionPath
Directory con una copia completa di `BenchmarkTarget`. Non viene mai modificata.

.PARAMETER TaskId
Uno tra T1..T6.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato, sorgente dei test pubblici.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con TypeScript e Vitest.

.PARAMETER RunsRoot
Default: runs/ nel repository del valutatore.

.PARAMETER RunId
Facoltativo; se omesso viene generato.

.PARAMETER BuildTimeoutSeconds
.PARAMETER PublicTimeoutSeconds
.PARAMETER ReservedTimeoutSeconds
Limiti per fase (default 60, 120, 120, dal contratto).

.PARAMETER KeepWorkspace
Non rimuove la copia di lavoro (solo per diagnostica).

.OUTPUTS
Il riepilogo JSON su stdout (o, con TaskId non valido, un oggetto con `outcome` e `diagnostics`).
Evidenze in `runs/<runId>/evidence/`: `evaluation-summary.json` e `report-validation.json`
(quest'ultimo puo' contenere identificatori di test riservati: solo per il ricercatore).

.NOTES
Exit code: 0 passed; 10 test-failures; 11 build-failure; 12 timeout; 20 invalid-input;
30 integrity-error; 40 evaluator-error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$SubmissionPath,
    [Parameter(Mandatory)][AllowEmptyString()][string]$TaskId,
    [Parameter(Mandatory)][string]$BaselinePath,
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [string]$RunsRoot,
    [string]$RunId,
    [int]$BuildTimeoutSeconds = 60,
    [int]$PublicTimeoutSeconds = 120,
    [int]$ReservedTimeoutSeconds = 120,
    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Evaluation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

try {
    $arguments = @{
        SubmissionPath = $SubmissionPath; TaskId = $TaskId; BaselinePath = $BaselinePath; ToolsNodeModulesPath = $ToolsNodeModulesPath
        BuildTimeoutSeconds = $BuildTimeoutSeconds; PublicTimeoutSeconds = $PublicTimeoutSeconds; ReservedTimeoutSeconds = $ReservedTimeoutSeconds
    }
    if ($RunsRoot) { $arguments.RunsRoot = $RunsRoot }
    if ($RunId) { $arguments.RunId = $RunId }
    if ($KeepWorkspace) { $arguments.KeepWorkspace = $true }
    $result = Invoke-Evaluation @arguments
}
catch {
    [ordered]@{ outcome = 'evaluator-error'; diagnostics = @("Errore del valutatore: $($_.Exception.GetType().Name)") } | ConvertTo-Json -Depth 5
    exit (Get-EvaluationExitCode -Outcome 'evaluator-error')
}

if ($null -ne $result.summary) { $result.summary | ConvertTo-Json -Depth 10 }
else { [ordered]@{ outcome = $result.outcome; diagnostics = @($result.diagnostics) } | ConvertTo-Json -Depth 5 }
exit $result.exitCode
