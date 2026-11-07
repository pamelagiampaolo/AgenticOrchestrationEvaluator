<#
.SYNOPSIS
Esegue typecheck e build nella copia di lavoro di una run preparata.

.PARAMETER RunDirectory
Directory `runs/<runId>` prodotta da Initialize-EvaluationRun.ps1.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con TypeScript.

.PARAMETER TimeoutSeconds
Limite complessivo per typecheck e build (default 60).

.OUTPUTS
Oggetto JSON su stdout con `status`, `exitCode`, `durationMs`, `steps`, `diagnostics`.

.NOTES
Exit code (stessa tabella degli esiti del contratto): 0 `passed`; 11 `build-failure`;
12 `timeout`; 40 `evaluator-error` (strumento o run non utilizzabili).
Questo script non esegue test e non rimuove la copia di lavoro.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BuildPhase.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

try {
    $result = Invoke-BuildPhase -RunDirectory $RunDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -TimeoutSeconds $TimeoutSeconds
}
catch {
    [ordered]@{ status = 'error'; exitCode = $null; durationMs = 0; steps = @(); diagnostics = @("Errore del valutatore nella fase di build: $($_.Exception.GetType().Name)") } | ConvertTo-Json -Depth 5
    exit (Get-EvaluationExitCode -Outcome 'evaluator-error')
}

$result | ConvertTo-Json -Depth 5
$outcomeByStatus = @{ passed = 'passed'; failed = 'build-failure'; timeout = 'timeout'; error = 'evaluator-error' }
exit (Get-EvaluationExitCode -Outcome $outcomeByStatus[$result.status])
