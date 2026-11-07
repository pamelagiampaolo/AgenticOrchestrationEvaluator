Set-StrictMode -Version Latest

<#
.SYNOPSIS
Funzioni per generare e verificare il manifest canonico della suite riservata.

.DESCRIPTION
Il manifest congela, per la suite riservata, l'insieme dei file sotto
`reserved/` (con SHA-256) e gli identificatori dei test attesi per ciascun task.
Gli identificatori sono ricavati da `vitest list --json`, non da analisi testuale
del sorgente, cosi' da riflettere cio' che Vitest eseguirebbe davvero.
#>

$script:TaskIds = @('T1', 'T2', 'T3', 'T4', 'T5', 'T6')

<#
.SYNOPSIS
Calcola lo SHA-256 di un file normalizzando CRLF in LF.

.DESCRIPTION
La normalizzazione rende l'hash indipendente da `core.autocrlf`. Il contenuto
resta altrimenti invariato byte per byte.

.OUTPUTS
Stringa esadecimale minuscola di 64 caratteri.
#>
function Get-NormalizedFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = New-Object System.Collections.Generic.List[byte]
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $isCrLf = $bytes[$index] -eq 13 -and ($index + 1) -lt $bytes.Length -and $bytes[$index + 1] -eq 10
        if (-not $isCrLf) { $normalized.Add($bytes[$index]) }
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($normalized.ToArray())
    }
    finally {
        $sha256.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

<#
.SYNOPSIS
Elenca i file di `reserved/` con percorso relativo (separatore `/`) e hash.

.OUTPUTS
Oggetti con `path` e `sha256`, ordinati per percorso (ordinamento ordinale).
#>
function Get-ReservedFileEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $reservedDirectory = Join-Path $RepositoryRoot 'reserved'
    if (-not (Test-Path -LiteralPath $reservedDirectory -PathType Container)) {
        throw "Directory riservata non trovata: reserved/"
    }
    $rootPrefix = (Resolve-Path -LiteralPath $RepositoryRoot).Path.TrimEnd('\') + '\'
    $entries = foreach ($file in Get-ChildItem -LiteralPath $reservedDirectory -File -Recurse) {
        [pscustomobject][ordered]@{
            path   = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            sha256 = Get-NormalizedFileSha256 -Path $file.FullName
        }
    }
    return @($entries | Sort-Object -Property @{ Expression = { $_.path }; Ascending = $true } -Culture 'iv' -CaseSensitive)
}

<#
.SYNOPSIS
Esegue `vitest list --json` su una copia temporanea di `reserved/`.

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` che contiene Vitest. Viene collegata tramite junction
alla copia temporanea, senza modificare ne' il repository ne' la directory
degli strumenti.

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

    $vitestCommand = Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'
    if (-not (Test-Path -LiteralPath $vitestCommand)) {
        throw "Vitest non trovato nel percorso strumenti indicato."
    }

    $workspace = Join-Path ([System.IO.Path]::GetTempPath()) ("reserved-manifest-" + [guid]::NewGuid().ToString('N'))
    $junction = Join-Path $workspace 'node_modules'
    $previousTaskId = $env:RESERVED_TASK_ID
    New-Item -ItemType Directory -Path $workspace | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'reserved') -Destination (Join-Path $workspace 'reserved') -Recurse
        New-Item -ItemType Junction -Path $junction -Target (Resolve-Path -LiteralPath $ToolsNodeModulesPath).Path | Out-Null

        if ($TaskId) { $env:RESERVED_TASK_ID = $TaskId } else { Remove-Item Env:\RESERVED_TASK_ID -ErrorAction SilentlyContinue }
        Push-Location $workspace
        try {
            # In Windows PowerShell 5.1 l'output su stderr di un eseguibile nativo diventa
            # un errore terminante con ErrorActionPreference=Stop. L'avviso di Vite sulle
            # config ESM e' non bloccante: l'esito e' stabilito da codice di uscita e
            # validita' del JSON su stdout.
            $previousPreference = $ErrorActionPreference
            $previousWarningFlag = $env:VITE_CONFIG_NATIVE_IGNORE_WARNING
            $ErrorActionPreference = 'Continue'
            $env:VITE_CONFIG_NATIVE_IGNORE_WARNING = 'true'
            try {
                $output = & $vitestCommand list --json --config "reserved/$ConfigFile" 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
                $env:VITE_CONFIG_NATIVE_IGNORE_WARNING = $previousWarningFlag
                if ($null -eq $previousWarningFlag) { Remove-Item Env:\VITE_CONFIG_NATIVE_IGNORE_WARNING -ErrorAction SilentlyContinue }
            }
        }
        finally {
            Pop-Location
        }
        if ($exitCode -ne 0) { throw "vitest list ha restituito il codice $exitCode per $ConfigFile." }

        try {
            $listed = ($output -join "`n") | ConvertFrom-Json
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
        $env:RESERVED_TASK_ID = $previousTaskId
        if ($null -eq $previousTaskId) { Remove-Item Env:\RESERVED_TASK_ID -ErrorAction SilentlyContinue }
        # La junction va rimossa da sola: una rimozione ricorsiva potrebbe entrare nella
        # directory degli strumenti collegata.
        if (Test-Path -LiteralPath $junction) { [System.IO.Directory]::Delete($junction) }
        Remove-Item -LiteralPath $workspace -Recurse -Force
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

    $expectedFiles = @{}
    foreach ($entry in $manifest.files) { $expectedFiles[$entry.path] = $entry.sha256 }
    $actualFiles = @{}
    foreach ($entry in Get-ReservedFileEntries -RepositoryRoot $RepositoryRoot) { $actualFiles[$entry.path] = $entry.sha256 }

    foreach ($path in ($expectedFiles.Keys | Sort-Object)) {
        if (-not $actualFiles.ContainsKey($path)) { $mismatches.Add("file mancante: $path") }
        elseif ($actualFiles[$path] -ne $expectedFiles[$path]) { $mismatches.Add("hash diverso: $path") }
    }
    foreach ($path in ($actualFiles.Keys | Sort-Object)) {
        if (-not $expectedFiles.ContainsKey($path)) { $mismatches.Add("file non dichiarato: $path") }
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

Export-ModuleMember -Function Get-NormalizedFileSha256, Get-ReservedFileEntries, Get-ListedReservedTests, New-ReservedManifestObject, Compare-ReservedManifest
