Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ManifestCommon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProcessRunner.psm1') -Force

<#
.SYNOPSIS
Fasi di test pubblica e riservata di una run preparata da New-EvaluationRun.

.DESCRIPTION
Le suite eseguite non provengono mai dalla submission: i test pubblici sono quelli
canonici della baseline e i test riservati sono quelli di questo repository, entrambi
verificati contro il rispettivo manifest prima dell'esecuzione. Questa fase produce i
report JSON grezzi di Vitest; la validazione rispetto ai manifest (test mancanti,
inattesi, saltati) e' un passo successivo.

Classificazione degli errori di preparazione:
- `System.IO.InvalidDataException`: un file canonico non coincide con il manifest ->
  `integrity-error`;
- qualunque altra eccezione: errore del valutatore.
#>

$script:TaskIdPattern = '^T[1-6]$'
# Task per cui la suite comune (vitest.public.config.ts) e' una configurazione separata.
# Per T5 e T6 la configurazione del task include gia' i file comuni.
$script:TasksWithSeparateCommonSuite = @('T1', 'T2', 'T3', 'T4')

# Scope pubblici eseguiti per un task, nell'ordine di esecuzione.
function Get-PublicScopeNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId)
    if ($TaskId -in $script:TasksWithSeparateCommonSuite) { return @('common', $TaskId) }
    return @($TaskId)
}

function Get-RunTaskId {
    param([string]$RunDirectory)
    $metadataPath = Join-Path $RunDirectory 'input\metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw [System.ArgumentException]::new('La run non ha input/metadata.json.') }
    $taskId = (Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json).taskId
    if ($taskId -cnotmatch $script:TaskIdPattern) { throw [System.ArgumentException]::new('TaskId non valido in metadata.json.') }
    return $taskId
}

function Copy-VerifiedFile {
    param([string]$Source, [string]$Destination, [string]$ExpectedSha256, [string]$Label)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    [System.IO.File]::Copy($Source, $Destination, $true)
    if ((Get-NormalizedFileSha256 -Path $Destination) -ne $ExpectedSha256) {
        throw [System.IO.InvalidDataException]::new("File canonico non coincidente con il manifest: $Label")
    }
}

function Initialize-WorkDependencies {
    param([string]$Directory, [string]$ToolsNodeModulesPath)
    $junction = Join-Path $Directory 'node_modules'
    if (-not (Test-Path -LiteralPath $junction)) {
        New-Item -ItemType Junction -Path $junction -Target (Resolve-Path -LiteralPath $ToolsNodeModulesPath).Path | Out-Null
    }
}

<#
.SYNOPSIS
Sostituisce nella copia di lavoro i test pubblici con quelli canonici della baseline.

.DESCRIPTION
Elimina `tests/public/` e `vitest.public*.ts` della submission e copia i file
canonici elencati dal manifest pubblico, verificandone l'hash. I test aggiunti o
modificati dall'agente non entrano quindi nel risultato.

.NOTES
Genera `System.IO.InvalidDataException` se un file della baseline differisce dal manifest.
#>
function Install-CanonicalPublicSuite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$PublicManifestPath
    )

    $workPath = Join-Path (Join-Path $RunDirectory 'work') 'submission'
    $manifest = Get-Content -LiteralPath $PublicManifestPath -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath (Join-Path $workPath 'tests\public')) { Remove-Item -LiteralPath (Join-Path $workPath 'tests\public') -Recurse -Force }
    Get-ChildItem -LiteralPath $workPath -File -Filter 'vitest.public*.ts' | Remove-Item -Force

    $canonical = @($manifest.baseline.files | Where-Object { $_.path -like 'tests/public/*' -or $_.path -match '^vitest\.public[^/]*\.ts$' })
    foreach ($entry in $canonical) {
        $relative = $entry.path.Replace('/', '\')
        Copy-VerifiedFile -Source (Join-Path $BaselinePath $relative) -Destination (Join-Path $workPath $relative) -ExpectedSha256 $entry.sha256 -Label $entry.path
    }
    return $canonical.Count
}

function Get-ReservedSuiteEntries {
    param([string]$TaskId, $ReservedManifest)
    $taskPrefix = "reserved/$($TaskId.ToLowerInvariant())-r"
    return @($ReservedManifest.files | Where-Object { $_.path.StartsWith($taskPrefix, [System.StringComparison]::Ordinal) -or $_.path -eq 'reserved/vitest.reserved-task.config.ts' })
}

<#
.SYNOPSIS
Copia in `work/reserved/` soltanto i file riservati del task, verificati contro il manifest.

.NOTES
Genera `System.IO.InvalidDataException` se un file riservato differisce dal manifest.
#>
function Install-ReservedSuite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ReservedManifestPath
    )

    $workRoot = Join-Path $RunDirectory 'work'
    $manifest = Get-Content -LiteralPath $ReservedManifestPath -Raw | ConvertFrom-Json
    $entries = Get-ReservedSuiteEntries -TaskId $TaskId -ReservedManifest $manifest
    if ($entries.Count -lt 2) { throw 'Nessun file riservato dichiarato per il task.' }
    if (Test-Path -LiteralPath (Join-Path $workRoot 'reserved')) { Remove-Item -LiteralPath (Join-Path $workRoot 'reserved') -Recurse -Force }
    foreach ($entry in $entries) {
        $relative = $entry.path.Replace('/', '\')
        Copy-VerifiedFile -Source (Join-Path $RepositoryRoot $relative) -Destination (Join-Path $workRoot $relative) -ExpectedSha256 $entry.sha256 -Label $entry.path
    }
    return $entries.Count
}

<#
.SYNOPSIS
Riverifica i file riservati copiati nella copia di lavoro dopo l'esecuzione.

.OUTPUTS
Elenco di differenze rispetto al manifest; vuoto se i file sono intatti.
#>
function Test-ReservedSuiteIntact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ReservedManifestPath
    )

    $workRoot = Join-Path $RunDirectory 'work'
    $manifest = Get-Content -LiteralPath $ReservedManifestPath -Raw | ConvertFrom-Json
    $expected = @(Get-ReservedSuiteEntries -TaskId $TaskId -ReservedManifest $manifest)
    $reservedDirectory = Join-Path $workRoot 'reserved'
    $files = @()
    if (Test-Path -LiteralPath $reservedDirectory) { $files = @(Get-ChildItem -LiteralPath $reservedDirectory -File -Recurse) }
    $actual = @()
    if ($files.Count -gt 0) { $actual = @(Get-FileEntries -Root $workRoot -Files $files) }
    return @(Compare-FileEntries -Scope 'riservati copiati' -Expected $expected -Actual $actual)
}

function Test-VitestReport {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
    if ($null -eq $report.PSObject.Properties['testResults'] -or $null -eq $report.PSObject.Properties['success']) { return $null }
    return $report
}

# Esegue in sequenza i passi di una suite e classifica l'esito complessivo. Un timeout o
# un errore interrompono la sequenza; un fallimento di test no, per avere tutti i report.
function Invoke-VitestSteps {
    param(
        [string]$Suite,
        [string]$RunDirectory,
        [string]$ToolsNodeModulesPath,
        [object[]]$Steps,
        [int]$TimeoutSeconds
    )

    $rawDirectory = Join-Path $RunDirectory 'raw'
    New-Item -ItemType Directory -Force -Path $rawDirectory | Out-Null
    $stdoutLog = Join-Path $rawDirectory "$Suite.stdout.txt"
    $stderrLog = Join-Path $rawDirectory "$Suite.stderr.txt"
    foreach ($log in $stdoutLog, $stderrLog) { [System.IO.File]::WriteAllText($log, '', (New-Object System.Text.UTF8Encoding($false))) }

    $vitest = Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'
    $results = New-Object System.Collections.Generic.List[object]
    $diagnostics = New-Object System.Collections.Generic.List[string]
    $status = 'passed'; $lastExitCode = $null
    if (-not (Test-Path -LiteralPath $vitest -PathType Leaf)) {
        return [pscustomobject][ordered]@{ status = 'error'; exitCode = $null; durationMs = 0; steps = @(); reports = @(); diagnostics = @('Vitest non trovato nelle dipendenze canoniche.') }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($step in $Steps) {
        $remaining = $TimeoutSeconds * 1000 - [int]$stopwatch.ElapsedMilliseconds
        if ($remaining -le 0) { $status = 'timeout'; $diagnostics.Add("Timeout complessivo raggiunto prima del passo $($step.name)."); break }
        $reportPath = Join-Path $rawDirectory "$($step.reportName).json"
        $stepOut = Join-Path $rawDirectory "step-$($step.name).stdout.tmp"
        $stepErr = Join-Path $rawDirectory "step-$($step.name).stderr.tmp"
        $environment = @{ VITE_CONFIG_NATIVE_IGNORE_WARNING = 'true' }
        foreach ($key in $step.environment.Keys) { $environment[$key] = $step.environment[$key] }
        try {
            $process = Invoke-ControlledProcess -CommandPath $vitest -Arguments @('run', '--config', $step.config, '--reporter=json', "--outputFile=$reportPath") `
                -WorkingDirectory $step.workingDirectory -StdoutPath $stepOut -StderrPath $stepErr -TimeoutMilliseconds $remaining -AdditionalEnvironment $environment
        }
        catch {
            $status = 'error'; $diagnostics.Add("Impossibile avviare il passo $($step.name)."); break
        }
        Add-StepLog -Path $stdoutLog -Header $step.name -StepFile $stepOut
        Add-StepLog -Path $stderrLog -Header $step.name -StepFile $stepErr
        Remove-Item -LiteralPath $stepOut, $stepErr -Force -ErrorAction SilentlyContinue
        $report = Test-VitestReport -Path $reportPath
        $results.Add([pscustomobject][ordered]@{ name = $step.name; exitCode = $process.exitCode; timedOut = $process.timedOut; durationMs = $process.durationMs; report = "raw/$($step.reportName).json"; reportValid = ($null -ne $report) })
        $lastExitCode = $process.exitCode

        if ($process.timedOut) { $status = 'timeout'; $diagnostics.Add("Timeout nel passo $($step.name)."); break }
        if ($process.exitCode -eq 0 -and $null -ne $report -and $report.success -eq $true) { continue }
        if ($process.exitCode -eq 1 -and $null -ne $report -and $report.success -eq $false) {
            if ($status -eq 'passed') { $status = 'failed' }
            $diagnostics.Add("Il passo $($step.name) ha test falliti.")
            continue
        }
        $status = 'error'
        $diagnostics.Add("Il passo $($step.name) ha prodotto un esito non interpretabile (codice $($process.exitCode), report valido: $($null -ne $report)).")
        break
    }
    $stopwatch.Stop()
    return [pscustomobject][ordered]@{
        status      = $status
        exitCode    = $lastExitCode
        durationMs  = [int]$stopwatch.ElapsedMilliseconds
        steps       = $results.ToArray()
        reports     = @($results | ForEach-Object { $_.report })
        diagnostics = $diagnostics.ToArray()
    }
}

<#
.SYNOPSIS
Esegue la suite pubblica canonica del task sulla copia di lavoro.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato, sorgente dei test pubblici (solo lettura).

.PARAMETER PublicManifestPath
Manifest pubblico canonico, che stabilisce quali scope eseguire e le loro configurazioni.

.OUTPUTS
Oggetto con `status` (`passed`, `failed`, `timeout`, `error`), `exitCode`, `durationMs`,
`steps`, `reports` e `diagnostics`.

.NOTES
Genera `System.IO.InvalidDataException` se la baseline non coincide con il manifest.
#>
function Invoke-PublicPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$PublicManifestPath,
        [int]$TimeoutSeconds = 120
    )

    $taskId = Get-RunTaskId -RunDirectory $RunDirectory
    $workPath = Join-Path (Join-Path $RunDirectory 'work') 'submission'
    if (-not (Test-Path -LiteralPath $workPath -PathType Container)) { throw [System.ArgumentException]::new('La run non ha una copia di lavoro.') }

    $manifest = Get-Content -LiteralPath $PublicManifestPath -Raw | ConvertFrom-Json
    $null = Install-CanonicalPublicSuite -RunDirectory $RunDirectory -BaselinePath $BaselinePath -PublicManifestPath $PublicManifestPath
    Initialize-WorkDependencies -Directory $workPath -ToolsNodeModulesPath $ToolsNodeModulesPath

    $steps = foreach ($scope in Get-PublicScopeNames -TaskId $taskId) {
        @{ name = $scope; config = $manifest.scopes.$scope.config; workingDirectory = $workPath; reportName = "public-$scope-report"; environment = @{} }
    }
    return Invoke-VitestSteps -Suite 'public' -RunDirectory $RunDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -Steps @($steps) -TimeoutSeconds $TimeoutSeconds
}

<#
.SYNOPSIS
Esegue la suite riservata del task sulla copia di lavoro.

.PARAMETER RepositoryRoot
Radice di questo repository (sorgente di `reserved/`, solo lettura).

.PARAMETER ReservedManifestPath
Manifest riservato canonico.

.OUTPUTS
Come Invoke-PublicPhase, piu `suiteIntact` e `integrityDifferences`: dopo l'esecuzione
i file riservati copiati vengono riverificati contro il manifest.

.NOTES
Genera `System.IO.InvalidDataException` se un file riservato non coincide con il manifest.
Le directory `work/submission` e `work/reserved` sono affiancate perche' i test importano
la soluzione da `../submission/src/index.ts`.
#>
function Invoke-ReservedPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ReservedManifestPath,
        [int]$TimeoutSeconds = 120
    )

    $taskId = Get-RunTaskId -RunDirectory $RunDirectory
    $workRoot = Join-Path $RunDirectory 'work'
    if (-not (Test-Path -LiteralPath (Join-Path $workRoot 'submission') -PathType Container)) { throw [System.ArgumentException]::new('La run non ha una copia di lavoro.') }

    $null = Install-ReservedSuite -RunDirectory $RunDirectory -TaskId $taskId -RepositoryRoot $RepositoryRoot -ReservedManifestPath $ReservedManifestPath
    Initialize-WorkDependencies -Directory $workRoot -ToolsNodeModulesPath $ToolsNodeModulesPath

    $steps = @(@{ name = $taskId; config = 'reserved/vitest.reserved-task.config.ts'; workingDirectory = $workRoot; reportName = 'reserved-report'; environment = @{ RESERVED_TASK_ID = $taskId } })
    $result = Invoke-VitestSteps -Suite 'reserved' -RunDirectory $RunDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -Steps $steps -TimeoutSeconds $TimeoutSeconds

    $differences = @(Test-ReservedSuiteIntact -RunDirectory $RunDirectory -TaskId $taskId -ReservedManifestPath $ReservedManifestPath)
    $result | Add-Member -NotePropertyName suiteIntact -NotePropertyValue ($differences.Count -eq 0)
    $result | Add-Member -NotePropertyName integrityDifferences -NotePropertyValue $differences
    return $result
}

Export-ModuleMember -Function Get-RunTaskId, Get-PublicScopeNames, Install-CanonicalPublicSuite, Install-ReservedSuite, Test-ReservedSuiteIntact, Invoke-PublicPhase, Invoke-ReservedPhase
