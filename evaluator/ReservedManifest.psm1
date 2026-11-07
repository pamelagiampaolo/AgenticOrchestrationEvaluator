Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ManifestCommon.psm1') -Force

<#
.SYNOPSIS
Funzioni per generare e verificare il manifest canonico della suite riservata.

.DESCRIPTION
Il manifest congela, per la suite riservata, l'insieme dei file sotto
`reserved/` (con SHA-256) e gli identificatori dei test attesi per ciascun task.
Gli identificatori sono ricavati da `vitest list --json`, non da analisi testuale
del sorgente, cosi' da riflettere cio' che Vitest eseguirebbe davvero. I test
riservati non sono parametrici, quindi l'elenco statico e' sufficiente.
#>

$script:TaskIds = @('T1', 'T2', 'T3', 'T4', 'T5', 'T6')

<#
.SYNOPSIS
Elenca i file di `reserved/` con percorso relativo e hash.
#>
function Get-ReservedFileEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $reservedDirectory = Join-Path $RepositoryRoot 'reserved'
    if (-not (Test-Path -LiteralPath $reservedDirectory -PathType Container)) {
        throw 'Directory riservata non trovata: reserved/'
    }
    return Get-FileEntries -Root $RepositoryRoot -Files @(Get-ChildItem -LiteralPath $reservedDirectory -File -Recurse)
}

<#
.SYNOPSIS
Esegue `vitest list --json` su una copia temporanea di `reserved/`.

.PARAMETER ConfigFile
Nome della configurazione sotto `reserved/` da usare.

.PARAMETER TaskId
Valore di `RESERVED_TASK_ID`; necessario soltanto per la configurazione per task.

.OUTPUTS
Oggetti con `name` e `file` (percorso relativo con `/`) in ordine ordinale.

.NOTES
Genera un errore se Vitest termina con codice diverso da zero o produce JSON
non valido.
#>
function Get-ListedReservedTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [Parameter(Mandatory)][string]$ConfigFile,
        [string]$TaskId
    )

    $workspace = New-ToolsWorkspace -ToolsNodeModulesPath $ToolsNodeModulesPath
    try {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'reserved') -Destination (Join-Path $workspace 'reserved') -Recurse

        $environment = @{ RESERVED_TASK_ID = $TaskId }
        $result = Invoke-Vitest -Workspace $workspace -EnvironmentVariables $environment `
            -Arguments @('list', '--json', '--config', "reserved/$ConfigFile")
        if ($result.exitCode -ne 0) { throw "vitest list ha restituito il codice $($result.exitCode) per $ConfigFile." }

        try {
            $listed = ($result.stdout -join "`n") | ConvertFrom-Json
        }
        catch {
            throw "Output di vitest list non e' JSON valido per $ConfigFile."
        }

        $workspacePrefix = (Resolve-Path -LiteralPath $workspace).Path.Replace('\', '/').TrimEnd('/') + '/'
        $tests = foreach ($test in @($listed)) {
            [pscustomobject][ordered]@{
                name = [string]$test.name
                file = ([string]$test.file).Replace('\', '/').Substring($workspacePrefix.Length)
            }
        }
        return @($tests | Sort-Object -Property @{ Expression = { $_.file }; Ascending = $true }, @{ Expression = { $_.name }; Ascending = $true } -Culture 'iv' -CaseSensitive)
    }
    finally {
        Remove-ToolsWorkspace -Workspace $workspace
    }
}

<#
.SYNOPSIS
Costruisce l'oggetto manifest a partire dallo stato corrente di `reserved/`.

.OUTPUTS
Oggetto ordinato serializzabile in JSON.
#>
function New-ReservedManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath
    )

    $tasks = [ordered]@{}
    foreach ($taskId in $script:TaskIds) {
        $listed = Get-ListedReservedTests -RepositoryRoot $RepositoryRoot -ToolsNodeModulesPath $ToolsNodeModulesPath `
            -ConfigFile 'vitest.reserved-task.config.ts' -TaskId $taskId
        $tests = foreach ($test in $listed) {
            if ($test.file -notmatch '^reserved/(t[1-6]-r\d{2})\.test\.ts$') {
                throw "File di test inatteso per $taskId nel manifest: $($test.file)"
            }
            [pscustomobject][ordered]@{
                id   = $Matches[1].ToUpperInvariant()
                name = $test.name
                file = $test.file
            }
        }
        $tasks[$taskId] = [ordered]@{ expectedTestCount = @($tests).Count; tests = @($tests) }
    }

    $smoke = Get-ListedReservedTests -RepositoryRoot $RepositoryRoot -ToolsNodeModulesPath $ToolsNodeModulesPath `
        -ConfigFile 'vitest.reserved.config.ts'

    return [ordered]@{
        schemaVersion = 1
        suite         = 'reserved'
        suiteVersion  = 'reserved-1'
        hashing       = [ordered]@{ algorithm = 'SHA-256'; lineEndings = 'CRLF normalizzato in LF prima dell''hash' }
        files         = @(Get-ReservedFileEntries -RepositoryRoot $RepositoryRoot)
        tasks         = $tasks
        smoke         = [ordered]@{ expectedTestCount = @($smoke).Count; tests = @($smoke) }
    }
}

<#
.SYNOPSIS
Confronta lo stato corrente con un manifest e restituisce le differenze.

.PARAMETER ToolsNodeModulesPath
Se omesso, la verifica degli identificatori dei test viene saltata e il fatto e'
riportato esplicitamente tra i risultati.

.OUTPUTS
Oggetto con `mismatches` (elenco di differenze; vuoto se coerente) e
`testListingVerified` (booleano).
#>
function Compare-ReservedManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$ToolsNodeModulesPath
    )

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw "schemaVersion del manifest non supportata: $($manifest.schemaVersion)" }

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($difference in Compare-FileEntries -Scope 'reserved' -Expected @($manifest.files) -Actual @(Get-ReservedFileEntries -RepositoryRoot $RepositoryRoot)) {
        $mismatches.Add($difference)
    }

    $listingVerified = [bool]$ToolsNodeModulesPath
    if ($listingVerified) {
        foreach ($taskId in $script:TaskIds) {
            $listed = Get-ListedReservedTests -RepositoryRoot $RepositoryRoot -ToolsNodeModulesPath $ToolsNodeModulesPath `
                -ConfigFile 'vitest.reserved-task.config.ts' -TaskId $taskId
            $expectedKeys = @($manifest.tasks.$taskId.tests | ForEach-Object { "$($_.file)::$($_.name)" })
            $actualKeys = @($listed | ForEach-Object { "$($_.file)::$($_.name)" })
            foreach ($key in $expectedKeys) { if ($actualKeys -cnotcontains $key) { $mismatches.Add("$taskId test atteso non elencato: $key") } }
            foreach ($key in $actualKeys) { if ($expectedKeys -cnotcontains $key) { $mismatches.Add("$taskId test inatteso: $key") } }
            if (@($listed).Count -ne $manifest.tasks.$taskId.expectedTestCount) {
                $mismatches.Add("$taskId conteggio $(@($listed).Count) diverso dall'atteso $($manifest.tasks.$taskId.expectedTestCount)")
            }
        }
    }

    return [pscustomobject]@{ mismatches = @($mismatches); testListingVerified = $listingVerified }
}

Export-ModuleMember -Function Get-ReservedFileEntries, Get-ListedReservedTests, New-ReservedManifestObject, Compare-ReservedManifest
