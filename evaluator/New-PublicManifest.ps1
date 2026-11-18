<#
.SYNOPSIS
Genera il manifest canonico della baseline e delle suite pubbliche.

.PARAMETER BaselinePath
Directory `BenchmarkTarget` approvata. Viene soltanto letta: Vitest gira su una
copia temporanea.

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` contenente Vitest.

.PARAMETER OutputPath
File di destinazione. Default: manifests/public-suite.manifest.json.

.NOTES
Exit code: 0 manifest scritto; 2 errore dello strumento o dell'ambiente.
Non sovrascrive un manifest esistente senza -Force: un manifest congelato non
deve cambiare silenziosamente.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselinePath,
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [ValidatePattern('^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$')][string]$DeclaredCommit,
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PublicManifest.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repositoryRoot 'manifests\public-suite.manifest.json' }

try {
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Il manifest esiste gia'. Usare -Force solo per creare una nuova versione della suite."
    }
    $manifest = New-PublicManifestObject -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -DeclaredCommit $DeclaredCommit
    $json = ($manifest | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "Manifest scritto: $OutputPath"
}
catch {
    [Console]::Error.WriteLine("evaluator-error: $($_.Exception.Message)")
    exit 2
}
