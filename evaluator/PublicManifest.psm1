Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ManifestCommon.psm1') -Force

<#
.SYNOPSIS
Funzioni per generare e verificare il manifest canonico di baseline e suite pubbliche.

.DESCRIPTION
Il manifest congela i file della baseline (`BenchmarkTarget`) rilevanti per la
valutazione e, per ciascun ambito (`common`, `T1`..`T6`), gli identificatori dei
test pubblici attesi. Gli identificatori sono ricavati eseguendo davvero Vitest
sulla baseline con il reporter JSON: `vitest list` mostrerebbe i test
parametrici come modelli (`%s`) e non i casi espansi.

Sulla baseline i test specifici del task falliscono, perche' la funzionalita' non
e' implementata: l'esito non fa parte del manifest, che registra solo i nomi.
I test non eseguiti (`pending`, per esempio per `testNamePattern` in T6) sono
registrati come esclusioni dichiarate; fuori da T6 non sono ammessi.
#>

# Ambito -> configurazione Vitest pubblica nella baseline.
$script:Scopes = [ordered]@{
    common = 'vitest.public.config.ts'
    T1     = 'vitest.public.t1.config.ts'
    T2     = 'vitest.public.t2.config.ts'
    T3     = 'vitest.public.t3.config.ts'
    T4     = 'vitest.public.t4.config.ts'
    T5     = 'vitest.public.t5.config.ts'
    T6     = 'vitest.public.t6.config.ts'
}

# Soli ambiti in cui sono ammesse esclusioni dichiarate (contratto: T6).
$script:ScopesAllowingExclusions = @('T6')

<#
.SYNOPSIS
Elenca i file della baseline rilevanti per la valutazione, con hash.

.DESCRIPTION
Include `package.json`, `package-lock.json`, `tsconfig.json`, le configurazioni
`vitest.public*.ts`, `src/` e `tests/public/`. Esclude `node_modules/` e `dist/`.

.OUTPUTS
Oggetti con `path` e `sha256`, ordinati per percorso.
#>
function Get-BaselineFileEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BaselinePath)

    if (-not (Test-Path -LiteralPath $BaselinePath -PathType Container)) {
        throw 'Directory della baseline non trovata.'
    }
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($name in 'package.json', 'package-lock.json', 'tsconfig.json') {
        $path = Join-Path $BaselinePath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "File obbligatorio della baseline mancante: $name" }
        $files.Add((Get-Item -LiteralPath $path))
    }
    foreach ($file in Get-ChildItem -LiteralPath $BaselinePath -File -Filter 'vitest.public*.ts') { $files.Add($file) }
    foreach ($directory in 'src', 'tests\public') {
        $path = Join-Path $BaselinePath $directory
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Directory obbligatoria della baseline mancante: $directory" }
        foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse) { $files.Add($file) }
    }
    return Get-FileEntries -Root $BaselinePath -Files $files.ToArray()
}

<#
.SYNOPSIS
Legge commit e pulizia del working tree della baseline, se Git e' disponibile.

.OUTPUTS
Oggetto con `commit` e `workingTreeClean`; `unavailable` quando non acquisibile.
#>
function Get-BaselineGitState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BaselinePath)

    $unavailable = [pscustomobject][ordered]@{ commit = 'unavailable'; workingTreeClean = 'unavailable' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $unavailable }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $commit = (& git -C $BaselinePath rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { return $unavailable }
        $status = (& git -C $BaselinePath status --porcelain -- . 2>$null)
        if ($LASTEXITCODE -ne 0) { return $unavailable }
        return [pscustomobject][ordered]@{ commit = $commit; workingTreeClean = (-not $status) }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

<#
.SYNOPSIS
Esegue una configurazione pubblica sulla baseline e restituisce i test osservati.

.DESCRIPTION
Copia in una directory temporanea soltanto i file elencati da
Get-BaselineFileEntries, esegue `vitest run` con il reporter JSON e legge il
report. L'esito dei test (anche se falliti) non e' un errore: lo e' un report
assente o non valido.

.OUTPUTS
Oggetti con `name` (nome completo), `file` (relativo, con `/`) e `status`.
#>
function Get-ObservedPublicTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [Parameter(Mandatory)][string]$ConfigFile
    )

    $workspace = New-ToolsWorkspace -ToolsNodeModulesPath $ToolsNodeModulesPath
    try {
        foreach ($entry in Get-BaselineFileEntries -BaselinePath $BaselinePath) {
            $destination = Join-Path $workspace ($entry.path.Replace('/', '\'))
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Copy-Item -LiteralPath (Join-Path $BaselinePath ($entry.path.Replace('/', '\'))) -Destination $destination
        }

        $reportPath = Join-Path $workspace 'report.json'
        $result = Invoke-Vitest -Workspace $workspace -Arguments @('run', '--config', $ConfigFile, '--reporter=json', "--outputFile=$reportPath")
        if (-not (Test-Path -LiteralPath $reportPath)) {
            throw "Report JSON assente per $ConfigFile (codice di uscita $($result.exitCode))."
        }
        try {
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Report JSON non valido per $ConfigFile."
        }
        if ($null -eq $report.PSObject.Properties['testResults']) { throw "Report senza testResults per $ConfigFile." }

        $workspacePrefix = (Resolve-Path -LiteralPath $workspace).Path.Replace('\', '/').TrimEnd('/') + '/'
        $tests = foreach ($fileResult in @($report.testResults)) {
            $relativeFile = ([string]$fileResult.name).Replace('\', '/').Substring($workspacePrefix.Length)
            foreach ($assertion in @($fileResult.assertionResults)) {
                [pscustomobject][ordered]@{ name = [string]$assertion.fullName; file = $relativeFile; status = [string]$assertion.status }
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
Divide i test osservati in eseguiti ed esclusi.

.DESCRIPTION
Eseguiti: `passed` e `failed`. Esclusi: `pending`, `skipped`, `todo`. Qualunque
altro stato e' un errore, cosi' un esito sconosciuto non viene classificato per
default.
#>
function Split-ObservedTests {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Observed)

    $executed = New-Object System.Collections.Generic.List[object]
    $excluded = New-Object System.Collections.Generic.List[object]
    foreach ($test in $Observed) {
        $declared = [pscustomobject][ordered]@{ name = $test.name; file = $test.file }
        switch ($test.status) {
            { $_ -in 'passed', 'failed' } { $executed.Add($declared) }
            { $_ -in 'pending', 'skipped', 'todo' } { $excluded.Add($declared) }
            default { throw "Stato di test sconosciuto '$($test.status)' per: $($test.name)" }
        }
    }
    return [pscustomobject]@{ executed = $executed.ToArray(); excluded = $excluded.ToArray() }
}

<#
.SYNOPSIS
Costruisce l'oggetto manifest a partire dalla baseline indicata.

.OUTPUTS
Oggetto ordinato serializzabile in JSON.

.NOTES
Genera un errore se un ambito contiene nomi duplicati o esclusioni non ammesse.
#>
function New-PublicManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath
    )

    $scopes = [ordered]@{}
    foreach ($scope in $script:Scopes.Keys) {
        $observed = Get-ObservedPublicTests -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -ConfigFile $script:Scopes[$scope]
        $duplicates = @($observed | Group-Object -Property file, name | Where-Object { $_.Count -gt 1 })
        if ($duplicates.Count -gt 0) { throw "Ambito ${scope}: nomi di test duplicati: $($duplicates[0].Name)" }
        $split = Split-ObservedTests -Observed $observed
        if ($split.excluded.Count -gt 0 -and $scope -notin $script:ScopesAllowingExclusions) {
            throw "Ambito ${scope}: esclusioni non ammesse ($($split.excluded.Count) test non eseguiti)."
        }
        $scopes[$scope] = [ordered]@{
            config                = $script:Scopes[$scope]
            expectedExecutedCount = $split.executed.Count
            expectedExcludedCount = $split.excluded.Count
            executed              = $split.executed
            excluded              = $split.excluded
        }
    }

    $git = Get-BaselineGitState -BaselinePath $BaselinePath
    return [ordered]@{
        schemaVersion = 1
        suite         = 'public'
        suiteVersion  = 'public-1'
        hashing       = [ordered]@{ algorithm = 'SHA-256'; lineEndings = 'CRLF normalizzato in LF prima dell''hash' }
        baseline      = [ordered]@{
            declaredCommit   = $git.commit
            workingTreeClean = $git.workingTreeClean
            files            = @(Get-BaselineFileEntries -BaselinePath $BaselinePath)
        }
        scopes        = $scopes
    }
}

<#
.SYNOPSIS
Confronta baseline e suite pubbliche correnti con un manifest.

.PARAMETER ToolsNodeModulesPath
Se omesso, si verificano solo file e hash e il fatto e' riportato nel risultato.

.OUTPUTS
Oggetto con `mismatches` (vuoto se coerente) e `testExecutionVerified`.
#>
function Compare-PublicManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$ToolsNodeModulesPath
    )

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw "schemaVersion del manifest non supportata: $($manifest.schemaVersion)" }

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($difference in Compare-FileEntries -Scope 'baseline' -Expected @($manifest.baseline.files) -Actual @(Get-BaselineFileEntries -BaselinePath $BaselinePath)) {
        $mismatches.Add($difference)
    }

    # Con file diversi dal manifest la baseline e' gia' non conforme: non si esegue
    # codice non verificato, e il fallimento resta una differenza di integrita'.
    foreach ($scope in $script:Scopes.Keys) {
        foreach ($kind in 'executed', 'excluded') {
            $declaredCount = $manifest.scopes.$scope."expected$([char]::ToUpper($kind[0]))$($kind.Substring(1))Count"
            if (@($manifest.scopes.$scope.$kind).Count -ne $declaredCount) {
                $mismatches.Add("${scope}: manifest incoerente, conteggio $kind dichiarato $declaredCount diverso dalla lista")
            }
        }
    }

    $executionVerified = [bool]$ToolsNodeModulesPath -and $mismatches.Count -eq 0
    if ($executionVerified) {
        foreach ($scope in $script:Scopes.Keys) {
            $expectedScope = $manifest.scopes.$scope
            $observed = Get-ObservedPublicTests -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -ConfigFile $script:Scopes[$scope]
            $duplicates = @($observed | Group-Object -Property file, name | Where-Object { $_.Count -gt 1 })
            foreach ($duplicate in $duplicates) { $mismatches.Add("${scope}: nome di test duplicato: $($duplicate.Name)") }
            $split = Split-ObservedTests -Observed $observed
            foreach ($kind in 'executed', 'excluded') {
                $expectedKeys = @($expectedScope.$kind | ForEach-Object { "$($_.file)::$($_.name)" })
                $actualKeys = @($split.$kind | ForEach-Object { "$($_.file)::$($_.name)" })
                foreach ($key in $expectedKeys) { if ($actualKeys -cnotcontains $key) { $mismatches.Add("${scope}: test $kind atteso non osservato: $key") } }
                foreach ($key in $actualKeys) { if ($expectedKeys -cnotcontains $key) { $mismatches.Add("${scope}: test $kind inatteso: $key") } }
            }
        }
    }

    return [pscustomobject]@{ mismatches = @($mismatches); testExecutionVerified = $executionVerified }
}

Export-ModuleMember -Function Get-BaselineFileEntries, Get-BaselineGitState, Get-ObservedPublicTests, Split-ObservedTests, New-PublicManifestObject, Compare-PublicManifest
