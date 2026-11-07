Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ManifestCommon.psm1') -Force

<#
.SYNOPSIS
Fase di ingresso del runner: validazione dell'input e preparazione della run.

.DESCRIPTION
Valida `SubmissionPath` e `TaskId`, calcola il manifest della submission,
archivia una copia in sola lettura sotto `runs/<runId>/input/` e prepara una
copia di lavoro separata sotto `runs/<runId>/work/`.

Classificazione degli errori (le eccezioni si distinguono per tipo):
- `System.ArgumentException`: input non valido -> `invalid-input`;
- `System.IO.InvalidDataException`: copia o sorgente non coincidono con il
  manifest -> `integrity-error`;
- qualunque altra eccezione: errore del valutatore -> `evaluator-error`.
#>

$script:TaskIdPattern = '^T[1-6]$'
$script:RunIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
# Artefatti generati o installati, non parte dell'input valutato: le dipendenze
# canoniche sono fornite dal valutatore. L'assenza/presenza e' registrata nel manifest.
$script:ExcludedTopLevelEntries = @('node_modules', 'dist')
$script:RequiredFiles = @('package.json', 'package-lock.json', 'tsconfig.json')
$script:RequiredDirectories = @('src')

function New-InvalidInputError {
    param([string]$Message)
    return [System.ArgumentException]::new($Message)
}

function Test-IsReparsePoint {
    param([System.IO.FileSystemInfo]$Item)
    return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Test-PathInside {
    param([string]$Child, [string]$Parent)
    $childPath = [System.IO.Path]::GetFullPath($Child).TrimEnd('\') + '\'
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    return $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $json = ($Value | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

<#
.SYNOPSIS
Verifica che il TaskId sia uno tra T1..T6 (maiuscolo).
#>
function Test-TaskId {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$TaskId)
    return [bool]($TaskId -cmatch $script:TaskIdPattern)
}

<#
.SYNOPSIS
Genera un runId nel formato `<UTC>-<TaskId>-<8 esadecimali>`.
#>
function New-RunId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId)
    $stamp = [datetime]::UtcNow.ToString('yyyyMMddTHHmmss', [cultureinfo]::InvariantCulture) + 'Z'
    return "$stamp-$TaskId-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
}

<#
.SYNOPSIS
Percorre la submission senza seguire collegamenti e ne restituisce i file.

.DESCRIPTION
Esclude le voci di primo livello elencate in `$script:ExcludedTopLevelEntries`
(senza entrarvi, anche se sono collegamenti). Qualunque altro symlink o junction
e' rifiutato, perche' la copia potrebbe leggere o scrivere fuori dalla submission.

.OUTPUTS
Oggetto con `files` (FileInfo[]) e `excluded` (nome -> presente).

.NOTES
Genera `System.ArgumentException` per radice o contenuto non ammessi.
#>
function Get-SubmissionTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $rootInfo = New-Object System.IO.DirectoryInfo $Root
    if (Test-IsReparsePoint -Item $rootInfo) { throw (New-InvalidInputError 'La directory della submission e'' un collegamento (symlink o junction).') }
    $rootPath = $rootInfo.FullName.TrimEnd('\')
    $prefix = $rootPath + '\'

    $excluded = [ordered]@{}
    foreach ($name in $script:ExcludedTopLevelEntries) { $excluded[$name] = $false }
    $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push($rootInfo)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $isTopLevel = $current.FullName.TrimEnd('\') -eq $rootPath
        foreach ($item in $current.GetFileSystemInfos()) {
            if ($isTopLevel -and $item.Name -in $script:ExcludedTopLevelEntries) {
                $excluded[($script:ExcludedTopLevelEntries | Where-Object { $_ -eq $item.Name })] = $true
                continue
            }
            if (Test-IsReparsePoint -Item $item) {
                throw (New-InvalidInputError "Collegamento (symlink o junction) non ammesso nella submission: $($item.FullName.Substring($prefix.Length).Replace('\', '/'))")
            }
            if ($item -is [System.IO.DirectoryInfo]) { $pending.Push($item) } else { $files.Add($item) }
        }
    }
    return [pscustomobject]@{ files = $files.ToArray(); excluded = $excluded }
}

<#
.SYNOPSIS
Verifica i file e le directory obbligatori della submission.

.NOTES
Genera `System.ArgumentException` indicando il primo elemento mancante.
#>
function Assert-SubmissionStructure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    foreach ($name in $script:RequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $name) -PathType Leaf)) { throw (New-InvalidInputError "File obbligatorio mancante nella submission: $name") }
    }
    foreach ($name in $script:RequiredDirectories) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $name) -PathType Container)) { throw (New-InvalidInputError "Directory obbligatoria mancante nella submission: $name") }
    }
}

# Impronta unica dell'albero: SHA-256 delle righe "percorso<TAB>hash<LF>" in ordine.
function Get-TreeSha256 {
    param([object[]]$Entries)
    $text = ($Entries | ForEach-Object { "$($_.path)`t$($_.sha256)`n" }) -join ''
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha256.Dispose() }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

<#
.SYNOPSIS
Costruisce il manifest di una submission (hash a byte esatti).

.OUTPUTS
Oggetto ordinato serializzabile in `submission-manifest.json`.
#>
function New-SubmissionManifestObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $tree = Get-SubmissionTree -Root $Root
    $entries = @(Get-FileEntries -Root $Root -Files $tree.files -RawBytes)
    $excludedEntries = foreach ($name in $tree.excluded.Keys) { [pscustomobject][ordered]@{ name = $name; presentInSource = $tree.excluded[$name] } }
    return [ordered]@{
        schemaVersion           = 1
        hashing                 = [ordered]@{ algorithm = 'SHA-256'; mode = 'byte esatti, nessuna normalizzazione dei fine riga' }
        excludedTopLevelEntries = @($excludedEntries)
        fileCount               = $entries.Count
        treeSha256              = Get-TreeSha256 -Entries $entries
        files                   = $entries
    }
}

<#
.SYNOPSIS
Confronta una directory con un manifest di submission.

.OUTPUTS
Elenco di differenze; vuoto se la directory coincide con il manifest.
#>
function Compare-SubmissionToManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Scope
    )

    $tree = Get-SubmissionTree -Root $Root
    $actual = @(Get-FileEntries -Root $Root -Files $tree.files -RawBytes)
    return @(Compare-FileEntries -Scope $Scope -Expected @($Manifest.files) -Actual $actual)
}

<#
.SYNOPSIS
Verifica che sorgente, copia archiviata e copia di lavoro coincidano con il manifest.

.DESCRIPTION
Le tre verifiche distinguono una copia difettosa da un sorgente cambiato durante
la copia: in entrambi i casi la valutazione non e' affidabile.

.NOTES
Genera `System.IO.InvalidDataException` elencando le differenze.
#>
function Assert-RunInputIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$ArchivedPath,
        [Parameter(Mandatory)][string]$WorkPath,
        [Parameter(Mandatory)]$Manifest
    )

    $differences = @()
    $differences += @(Compare-SubmissionToManifest -Root $ArchivedPath -Manifest $Manifest -Scope 'copia archiviata')
    $differences += @(Compare-SubmissionToManifest -Root $WorkPath -Manifest $Manifest -Scope 'copia di lavoro')
    $differences += @(Compare-SubmissionToManifest -Root $SourcePath -Manifest $Manifest -Scope 'sorgente')
    if ($differences.Count -gt 0) { throw [System.IO.InvalidDataException]::new("Copia non coincidente con il manifest: $($differences -join '; ')") }
}

function Copy-ManifestFiles {
    param([string]$SourceRoot, [object[]]$Entries, [string]$DestinationRoot)
    foreach ($entry in $Entries) {
        $relative = $entry.path.Replace('/', '\')
        $destination = Join-Path $DestinationRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        [System.IO.File]::Copy((Join-Path $SourceRoot $relative), $destination, $false)
    }
}

<#
.SYNOPSIS
Prepara una run: valida l'input, archivia la submission e crea la copia di lavoro.

.PARAMETER SubmissionPath
Directory con una copia completa di `BenchmarkTarget`. Non viene mai modificata.

.PARAMETER TaskId
Uno tra T1..T6.

.PARAMETER RunsRoot
Directory che conterra' `<runId>/`. Non deve contenere la submission ne' esserne contenuta.

.PARAMETER RunId
Facoltativo; se omesso viene generato. Non deve esistere gia' sotto RunsRoot.

.OUTPUTS
Oggetto con `runId`, `runDirectory`, `archivedSubmissionPath`, `workSubmissionPath`,
`treeSha256`, `fileCount`.

.NOTES
Tutta la validazione avviene prima della creazione di qualunque directory: un
input non valido non lascia tracce. Errori successivi alla creazione lasciano la
directory della run per l'analisi. Le directory vuote non fanno parte del manifest.
#>
function New-EvaluationRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SubmissionPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TaskId,
        [Parameter(Mandatory)][string]$RunsRoot,
        [string]$RunId
    )

    if (-not (Test-TaskId -TaskId $TaskId)) { throw (New-InvalidInputError 'TaskId non valido: atteso uno tra T1, T2, T3, T4, T5, T6.') }
    if (-not $RunId) { $RunId = New-RunId -TaskId $TaskId }
    if ($RunId -cnotmatch $script:RunIdPattern) { throw (New-InvalidInputError 'RunId non valido.') }
    if (-not $SubmissionPath -or -not (Test-Path -LiteralPath $SubmissionPath -PathType Container)) {
        throw (New-InvalidInputError 'SubmissionPath non esiste o non e'' una directory.')
    }

    $submissionRoot = (Resolve-Path -LiteralPath $SubmissionPath).Path.TrimEnd('\')
    $runsRootFull = [System.IO.Path]::GetFullPath($RunsRoot).TrimEnd('\')
    if ((Test-PathInside -Child $runsRootFull -Parent $submissionRoot) -or (Test-PathInside -Child $submissionRoot -Parent $runsRootFull)) {
        throw (New-InvalidInputError 'RunsRoot e SubmissionPath non possono contenersi a vicenda.')
    }
    $runDirectory = Join-Path $runsRootFull $RunId
    if (Test-Path -LiteralPath $runDirectory) { throw (New-InvalidInputError 'Esiste gia'' una run con questo RunId.') }

    Assert-SubmissionStructure -Root $submissionRoot
    $manifest = New-SubmissionManifestObject -Root $submissionRoot
    $manifestObject = $manifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json

    $createdAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [cultureinfo]::InvariantCulture)
    $inputDirectory = Join-Path $runDirectory 'input'
    $archivedPath = Join-Path $inputDirectory 'submission'
    $workPath = Join-Path (Join-Path $runDirectory 'work') 'submission'
    New-Item -ItemType Directory -Path $archivedPath, $workPath | Out-Null

    Copy-ManifestFiles -SourceRoot $submissionRoot -Entries $manifest.files -DestinationRoot $archivedPath
    Copy-ManifestFiles -SourceRoot $submissionRoot -Entries $manifest.files -DestinationRoot $workPath

    Assert-RunInputIntegrity -SourcePath $submissionRoot -ArchivedPath $archivedPath -WorkPath $workPath -Manifest $manifestObject

    foreach ($file in Get-ChildItem -LiteralPath $archivedPath -File -Recurse) { $file.IsReadOnly = $true }

    Write-JsonFile -Path (Join-Path $inputDirectory 'submission-manifest.json') -Value $manifest
    Write-JsonFile -Path (Join-Path $inputDirectory 'metadata.json') -Value ([ordered]@{
            schemaVersion    = 1
            runId            = $RunId
            taskId           = $TaskId
            createdAtUtc     = $createdAtUtc
            executionMode    = 'local-controlled'
            submissionSource = $submissionRoot
            treeSha256       = $manifest.treeSha256
        })

    return [pscustomobject][ordered]@{
        runId                  = $RunId
        runDirectory           = $runDirectory
        archivedSubmissionPath = $archivedPath
        workSubmissionPath     = $workPath
        treeSha256             = $manifest.treeSha256
        fileCount              = $manifest.fileCount
    }
}

Export-ModuleMember -Function Test-TaskId, New-RunId, Get-SubmissionTree, Assert-SubmissionStructure, New-SubmissionManifestObject, Compare-SubmissionToManifest, Assert-RunInputIntegrity, New-EvaluationRun
