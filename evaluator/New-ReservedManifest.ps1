<#
.SYNOPSIS
Genera il manifest canonico della suite riservata.

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` contenente Vitest, usata per elencare i test.

.PARAMETER OutputPath
File di destinazione. Default: manifests/reserved-suite.manifest.json.

.NOTES
Exit code: 0 manifest scritto; 2 errore dello strumento o dell'ambiente.
Non sovrascrive un manifest esistente senza -Force: un manifest congelato non
deve cambiare silenziosamente.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReservedManifest.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json' }

try {
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Il manifest esiste gia'. Usare -Force solo per creare una nuova versione della suite."
    }
    $manifest = New-ReservedManifestObject -RepositoryRoot $repositoryRoot -ToolsNodeModulesPath $ToolsNodeModulesPath
    $json = ($manifest | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "Manifest scritto: $OutputPath"
}
catch {
    [Console]::Error.WriteLine("evaluator-error: $($_.Exception.Message)")
    exit 2
}
