<#
.SYNOPSIS
Esegue la suite pubblica o riservata sulla copia di lavoro di una run preparata.

.PARAMETER Suite
`public` oppure `reserved`.

.PARAMETER RunDirectory
Directory `runs/<runId>` prodotta da Initialize-EvaluationRun.ps1.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con Vitest.

.PARAMETER BaselinePath
Solo per `public`: `BenchmarkTarget` approvato.

.PARAMETER TimeoutSeconds
Limite per la fase (default 120).

.OUTPUTS
Oggetto JSON su stdout con `status`, `exitCode`, `durationMs`, `steps`, `reports`,
`diagnostics` e, per `reserved`, `suiteIntact`.

.NOTES
Exit code: 0 `passed`; 10 `test-failures`; 12 `timeout`; 30 `integrity-error` (file canonici
o riservati non coincidenti con il manifest); 40 `evaluator-error`. Questo script produce i
report grezzi ma non li valida rispetto ai manifest.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('public', 'reserved')][string]$Suite,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [string]$BaselinePath,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestPhases.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failureOutput = { param($Status, $Message) [ordered]@{ status = $Status; exitCode = $null; durationMs = 0; steps = @(); reports = @(); diagnostics = @($Message) } | ConvertTo-Json -Depth 5 }

try {
    if ($Suite -eq 'public') {
        if (-not $BaselinePath) { throw [System.ArgumentException]::new('BaselinePath e'' obbligatorio per la suite pubblica.') }
        $result = Invoke-PublicPhase -RunDirectory $RunDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath `
            -PublicManifestPath (Join-Path $repositoryRoot 'manifests\public-suite.manifest.json') -TimeoutSeconds $TimeoutSeconds
    }
    else {
        $result = Invoke-ReservedPhase -RunDirectory $RunDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot `
            -ReservedManifestPath (Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json') -TimeoutSeconds $TimeoutSeconds
    }
}
catch [System.IO.InvalidDataException] {
    & $failureOutput 'integrity-error' $_.Exception.Message
    exit (Get-EvaluationExitCode -Outcome 'integrity-error')
}
catch {
    & $failureOutput 'error' "Errore del valutatore nella fase $($Suite): $($_.Exception.GetType().Name)"
    exit (Get-EvaluationExitCode -Outcome 'evaluator-error')
}

$result | ConvertTo-Json -Depth 6
# L'alterazione dei file riservati prevale su qualunque altro esito (stessa precedenza del contratto).
if ($Suite -eq 'reserved' -and -not $result.suiteIntact) { exit (Get-EvaluationExitCode -Outcome 'integrity-error') }
$outcomeByStatus = @{ passed = 'passed'; failed = 'test-failures'; timeout = 'timeout'; error = 'evaluator-error' }
exit (Get-EvaluationExitCode -Outcome $outcomeByStatus[$result.status])
