<#
.SYNOPSIS
Verifica che baseline e suite pubbliche coincidano con il manifest canonico.

.PARAMETER BaselinePath
Directory `BenchmarkTarget` da verificare (solo lettura).

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` contenente Vitest. Se omesso, vengono verificati solo
file e hash; la mancata verifica dei test e' dichiarata nell'output.

.PARAMETER ManifestPath
Default: manifests/public-suite.manifest.json.

.NOTES
Exit code: 0 coerente; 1 differenze rispetto al manifest (integrity-error);
2 errore dello strumento o manifest illeggibile.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselinePath,
    [string]$ToolsNodeModulesPath,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PublicManifest.psm1') -Force

if (-not $ManifestPath) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests\public-suite.manifest.json' }

try {
    $result = Compare-PublicManifest -BaselinePath $BaselinePath -ManifestPath $ManifestPath -ToolsNodeModulesPath $ToolsNodeModulesPath
}
catch {
    [Console]::Error.WriteLine("evaluator-error: $($_.Exception.Message)")
    exit 2
}

if ($result.mismatches.Count -gt 0) {
    $result.mismatches | ForEach-Object { Write-Output "MISMATCH: $_" }
    if (-not $result.testExecutionVerified) { Write-Output 'Test non eseguiti: i file differiscono dal manifest.' }
    exit 1
}
if (-not $result.testExecutionVerified) {
    Write-Warning 'Test pubblici NON verificati: ToolsNodeModulesPath non indicato.'
}
Write-Output "Manifest coerente (test verificati: $($result.testExecutionVerified))."
exit 0
