<#
.SYNOPSIS
Valida i report grezzi di una suite rispetto al manifest canonico.

.PARAMETER Suite
`public` oppure `reserved`.

.PARAMETER RunDirectory
Directory `runs/<runId>` dopo l'esecuzione della fase corrispondente.

.OUTPUTS
Oggetto JSON su stdout con `outcome`, `counts` (expected, executed, passed, failed, skipped,
missing, unexpected), `scopes` e `issues`.

.NOTES
Exit code: 0 `passed`; 10 `test-failures`; 40 `evaluator-error` (anomalie strutturali,
report assente o incoerente, run non utilizzabile). Gli issue possono contenere identificatori
di test riservati: sono evidenze per il ricercatore, non per l'agente.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('public', 'reserved')][string]$Suite,
    [Parameter(Mandatory)][string]$RunDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReportValidation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
try {
    if ($Suite -eq 'public') { $result = Test-PublicReports -RunDirectory $RunDirectory -PublicManifestPath (Join-Path $repositoryRoot 'manifests\public-suite.manifest.json') }
    else { $result = Test-ReservedReport -RunDirectory $RunDirectory -ReservedManifestPath (Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json') }
}
catch {
    [ordered]@{ outcome = 'evaluator-error'; counts = $null; scopes = @(); issues = @("Errore del valutatore nella validazione dei report: $($_.Exception.GetType().Name)") } | ConvertTo-Json -Depth 8
    exit (Get-EvaluationExitCode -Outcome 'evaluator-error')
}

$result | ConvertTo-Json -Depth 8
exit (Get-EvaluationExitCode -Outcome $result.outcome)
