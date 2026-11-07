Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestPhases.psm1') -Force

<#
.SYNOPSIS
Validazione dei report grezzi di Vitest rispetto ai manifest canonici.

.DESCRIPTION
I report prodotti dalle fasi di test sono dati non fidati: prima di usarne i conteggi
se ne verificano struttura e coerenza e si confrontano i test osservati con quelli
attesi dal manifest.

Classificazione (stessa distinzione del contratto tra fallimento della soluzione ed
errore del valutatore):
- `test-failures`: test falliti, file di test che non si carica, o fallimento a
  livello di run (`success: false`) senza altre anomalie;
- `evaluator-error`: anomalie strutturali (test attesi mancanti non spiegati da un
  file fallito, test saltati o `todo`, test non previsti, duplicati, test esclusi
  eseguiti, stati sconosciuti, report assente o incoerente);
- `passed`: nessuna anomalia e nessun fallimento.
Le anomalie strutturali prevalgono sui fallimenti.
#>

$script:ExecutedStatuses = @('passed', 'failed')
$script:NotExecutedStatuses = @('pending', 'skipped', 'todo', 'disabled')

<#
.SYNOPSIS
Legge un report JSON di Vitest; restituisce `$null` se assente o non valido.
#>
function Read-VitestReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
    foreach ($name in 'testResults', 'success', 'numTotalTests') {
        if ($null -eq $report.PSObject.Properties[$name]) { return $null }
    }
    return $report
}

function New-ScopeResult {
    param([string]$Scope, [int]$Expected, [string[]]$Issues, [bool]$Structural, [bool]$FailureIndicated, $Counts, [string[]]$FileFailures)
    $outcome = if ($Structural) { 'evaluator-error' } elseif ($FailureIndicated) { 'test-failures' } else { 'passed' }
    return [pscustomobject][ordered]@{
        scope        = $Scope
        outcome      = $outcome
        counts       = $Counts
        fileFailures = @($FileFailures)
        issues       = @($Issues)
    }
}

function New-Counts {
    param([int]$Expected, [int]$Passed = 0, [int]$Failed = 0, [int]$Skipped = 0, [int]$Missing = 0, [int]$Unexpected = 0)
    return [pscustomobject][ordered]@{ expected = $Expected; executed = $Passed + $Failed; passed = $Passed; failed = $Failed; skipped = $Skipped; missing = $Missing; unexpected = $Unexpected }
}

<#
.SYNOPSIS
Confronta un report con i test attesi di uno scope.

.PARAMETER Report
Oggetto ottenuto con Read-VitestReport, oppure `$null` se il report manca o non e' valido.

.PARAMETER BasePath
Directory rispetto a cui i percorsi del report diventano relativi ai percorsi del manifest.

.PARAMETER Executed
Test attesi ed eseguiti: oggetti con `name` e `file` (percorso relativo con `/`).

.PARAMETER Excluded
Test dichiarati ma non eseguiti (esclusioni T6): se compaiono eseguiti sono anomalie.

.OUTPUTS
Oggetto con `scope`, `outcome`, `counts` (expected, executed, passed, failed, skipped,
missing, unexpected), `fileFailures` e `issues`.
#>
function Compare-ReportToExpectation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [AllowNull()]$Report,
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Executed,
        [AllowEmptyCollection()][object[]]$Excluded = @()
    )

    $issues = New-Object System.Collections.Generic.List[string]
    $expectedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($test in $Executed) { $null = $expectedKeys.Add("$($test.file)::$($test.name)") }

    if ($null -eq $Report) {
        $issues.Add('report assente o non valido')
        return New-ScopeResult -Scope $Scope -Expected $expectedKeys.Count -Issues $issues.ToArray() -Structural $true -FailureIndicated $false `
            -Counts (New-Counts -Expected $expectedKeys.Count -Missing $expectedKeys.Count) -FileFailures @()
    }

    $excludedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($test in $Excluded) { $null = $excludedKeys.Add("$($test.file)::$($test.name)") }

    $basePrefix = [System.IO.Path]::GetFullPath($BasePath).Replace('\', '/').TrimEnd('/') + '/'
    $observed = New-Object System.Collections.Generic.List[object]
    $fileFailures = New-Object System.Collections.Generic.List[string]
    foreach ($fileResult in @($Report.testResults)) {
        $absolute = [System.IO.Path]::GetFullPath(([string]$fileResult.name).Replace('/', '\')).Replace('\', '/')
        if ($absolute.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $relative = $absolute.Substring($basePrefix.Length) }
        else { $relative = $absolute; $issues.Add('file di test fuori dalla directory attesa') }
        $assertions = @()
        if ($null -ne $fileResult.PSObject.Properties['assertionResults']) { $assertions = @($fileResult.assertionResults) }
        if ($fileResult.status -eq 'failed' -and $assertions.Count -eq 0) { $fileFailures.Add($relative) }
        foreach ($assertion in $assertions) { $observed.Add([pscustomobject]@{ file = $relative; name = [string]$assertion.fullName; status = [string]$assertion.status }) }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $passed = 0; $failed = 0; $skipped = 0; $unexpected = 0
    foreach ($test in $observed) {
        $key = "$($test.file)::$($test.name)"
        if (-not $seen.Add($key)) { $issues.Add("test duplicato: $key"); continue }
        if ($expectedKeys.Contains($key)) {
            if ($test.status -eq 'passed') { $passed++ }
            elseif ($test.status -eq 'failed') { $failed++ }
            elseif ($test.status -in $script:NotExecutedStatuses) { $skipped++; $issues.Add("test atteso non eseguito ($($test.status)): $key") }
            else { $issues.Add("stato sconosciuto '$($test.status)': $key") }
        }
        elseif ($excludedKeys.Contains($key)) {
            if ($test.status -in $script:ExecutedStatuses) { $unexpected++; $issues.Add("test escluso eseguito: $key") }
            elseif ($test.status -notin $script:NotExecutedStatuses) { $issues.Add("stato sconosciuto '$($test.status)': $key") }
        }
        else { $unexpected++; $issues.Add("test non previsto dal manifest: $key") }
    }

    # I test mancanti di un file che ha fallito al caricamento sono spiegati da quel fallimento.
    $missing = 0
    foreach ($test in $Executed) {
        $key = "$($test.file)::$($test.name)"
        if ($seen.Contains($key)) { continue }
        $missing++
        if ($test.file -notin $fileFailures) { $issues.Add("test atteso mancante: $key") }
    }
    $unexplainedMissing = @($Executed | Where-Object { -not $seen.Contains("$($_.file)::$($_.name)") -and $_.file -notin $fileFailures }).Count

    # Coerenza interna del report: i contatori dichiarati devono riflettere le asserzioni.
    if ($Report.numTotalTests -ne $observed.Count) { $issues.Add("numTotalTests $($Report.numTotalTests) diverso dalle asserzioni osservate $($observed.Count)") }
    $incoherent = $Report.numTotalTests -ne $observed.Count
    if ($Report.success -eq $true -and ($failed -gt 0 -or $fileFailures.Count -gt 0)) { $issues.Add('success true con test o file falliti'); $incoherent = $true }

    $structural = $incoherent -or $skipped -gt 0 -or $unexpected -gt 0 -or $unexplainedMissing -gt 0 -or @($issues | Where-Object { $_ -like 'test duplicato*' -or $_ -like 'stato sconosciuto*' -or $_ -like 'file di test fuori*' }).Count -gt 0
    $failureIndicated = $failed -gt 0 -or $fileFailures.Count -gt 0 -or $Report.success -eq $false
    return New-ScopeResult -Scope $Scope -Expected $expectedKeys.Count -Issues $issues.ToArray() -Structural $structural -FailureIndicated $failureIndicated `
        -Counts (New-Counts -Expected $expectedKeys.Count -Passed $passed -Failed $failed -Skipped $skipped -Missing $missing -Unexpected $unexpected) -FileFailures $fileFailures.ToArray()
}

<#
.SYNOPSIS
Unisce i risultati di piu scope in un unico risultato di suite.

.DESCRIPTION
I conteggi si sommano; l'esito peggiore prevale (evaluator-error > test-failures > passed).
Gli issue sono prefissati dallo scope.
#>
function Merge-ScopeResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results)

    $totals = [ordered]@{ expected = 0; executed = 0; passed = 0; failed = 0; skipped = 0; missing = 0; unexpected = 0 }
    foreach ($result in $Results) { foreach ($name in @($totals.Keys)) { $totals[$name] += $result.counts.$name } }
    $outcome = 'passed'
    if (@($Results | Where-Object { $_.outcome -eq 'test-failures' }).Count -gt 0) { $outcome = 'test-failures' }
    if (@($Results | Where-Object { $_.outcome -eq 'evaluator-error' }).Count -gt 0) { $outcome = 'evaluator-error' }
    return [pscustomobject][ordered]@{
        outcome = $outcome
        counts  = [pscustomobject]$totals
        scopes  = @($Results)
        issues  = @($Results | ForEach-Object { $scope = $_.scope; $_.issues | ForEach-Object { "${scope}: $_" } })
    }
}

<#
.SYNOPSIS
Valida i report della suite pubblica di una run rispetto al manifest pubblico.
#>
function Test-PublicReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$PublicManifestPath
    )

    $taskId = Get-RunTaskId -RunDirectory $RunDirectory
    $manifest = Get-Content -LiteralPath $PublicManifestPath -Raw | ConvertFrom-Json
    $basePath = Join-Path (Join-Path $RunDirectory 'work') 'submission'
    $results = foreach ($scope in Get-PublicScopeNames -TaskId $taskId) {
        $report = Read-VitestReport -Path (Join-Path $RunDirectory "raw\public-$scope-report.json")
        Compare-ReportToExpectation -Scope $scope -Report $report -BasePath $basePath -Executed @($manifest.scopes.$scope.executed) -Excluded @($manifest.scopes.$scope.excluded)
    }
    return Merge-ScopeResults -Results @($results)
}

<#
.SYNOPSIS
Valida il report della suite riservata di una run rispetto al manifest riservato.
#>
function Test-ReservedReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ReservedManifestPath
    )

    $taskId = Get-RunTaskId -RunDirectory $RunDirectory
    $manifest = Get-Content -LiteralPath $ReservedManifestPath -Raw | ConvertFrom-Json
    $report = Read-VitestReport -Path (Join-Path $RunDirectory 'raw\reserved-report.json')
    $expected = @($manifest.tasks.$taskId.tests | ForEach-Object { [pscustomobject]@{ name = $_.name; file = $_.file } })
    $result = Compare-ReportToExpectation -Scope $taskId -Report $report -BasePath (Join-Path $RunDirectory 'work') -Executed $expected
    return Merge-ScopeResults -Results @($result)
}

Export-ModuleMember -Function Read-VitestReport, Compare-ReportToExpectation, Merge-ScopeResults, Test-PublicReports, Test-ReservedReport
