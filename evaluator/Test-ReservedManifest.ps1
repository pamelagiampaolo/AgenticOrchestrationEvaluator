<#
.SYNOPSIS
Verifica che `reserved/` coincida con il manifest canonico.

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` contenente Vitest. Se omesso, vengono verificati solo
file e hash; la mancata verifica degli identificatori dei test e' dichiarata
nell'output.

.PARAMETER ManifestPath
Default: manifests/reserved-suite.manifest.json.

.NOTES
Exit code: 0 coerente; 1 differenze rispetto al manifest (integrity-error);
2 errore dello strumento o manifest illeggibile.
#>
[CmdletBinding()]
param(
    [string]$ToolsNodeModulesPath,
    [string]$ManifestPath,
    [string]$RepositoryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReservedManifest.psm1') -Force

if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
if (-not $ManifestPath) { $ManifestPath = Join-Path $RepositoryRoot 'manifests\reserved-suite.manifest.json' }

try {
    $result = Compare-ReservedManifest -RepositoryRoot $RepositoryRoot -ManifestPath $ManifestPath -ToolsNodeModulesPath $ToolsNodeModulesPath
}
catch {
    [Console]::Error.WriteLine("evaluator-error: $($_.Exception.Message)")
    exit 2
}

if (-not $result.testListingVerified) {
    Write-Warning 'Identificatori dei test NON verificati: ToolsNodeModulesPath non indicato.'
}
if ($result.mismatches.Count -gt 0) {
    $result.mismatches | ForEach-Object { Write-Output "MISMATCH: $_" }
    exit 1
}
Write-Output "Manifest coerente (identificatori dei test verificati: $($result.testListingVerified))."
exit 0
