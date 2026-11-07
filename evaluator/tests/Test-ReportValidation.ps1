<#
.SYNOPSIS
Test automatici della validazione dei report rispetto ai manifest.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con Vitest reale.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato (solo lettura).

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito.
Tutto avviene in una directory temporanea creata e rimossa dal test.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [Parameter(Mandatory)][string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\EvaluationInput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\ReportValidation.psm1') -Force
# Per ultimo: ReportValidation reimporta TestPhases con -Force e ne sostituirebbe il caricamento.
Import-Module (Join-Path $PSScriptRoot '..\TestPhases.psm1') -Force
$validateScript = Join-Path $PSScriptRoot '..\Test-PhaseReports.ps1'
$publicManifest = Join-Path $repositoryRoot 'manifests\public-suite.manifest.json'
$reservedManifest = Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json'

$script:failures = 0
$script:total = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" } else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function Format-Counts { param($Result) $c = $Result.counts; return "exp=$($c.expected) exe=$($c.executed) pas=$($c.passed) fai=$($c.failed) ski=$($c.skipped) mis=$($c.missing) une=$($c.unexpected)" }
function Test-Counts {
    param($Result, [int]$Expected, [int]$Passed, [int]$Failed = 0, [int]$Skipped = 0, [int]$Missing = 0, [int]$Unexpected = 0)
    $c = $Result.counts
    return ($c.expected -eq $Expected -and $c.executed -eq ($Passed + $Failed) -and $c.passed -eq $Passed -and $c.failed -eq $Failed -and $c.skipped -eq $Skipped -and $c.missing -eq $Missing -and $c.unexpected -eq $Unexpected)
}

# --- Report sintetici -------------------------------------------------------------------------
$base = 'C:\Fake\Work\submission'
$executed = @(
    [pscustomobject]@{ name = 'A one'; file = 'tests/a.test.ts' },
    [pscustomobject]@{ name = 'A two'; file = 'tests/a.test.ts' },
    [pscustomobject]@{ name = 'B one'; file = 'tests/b.test.ts' }
)
$excluded = @([pscustomobject]@{ name = 'B hidden'; file = 'tests/b.test.ts' })

# Costruisce un report nel formato del reporter JSON di Vitest, con percorsi assoluti con '/'.
function New-FakeReport {
    param([object[]]$Tests, [bool]$Success = $true, [string[]]$FailedFiles = @(), [Nullable[int]]$TotalOverride = $null, [string]$BasePath = $base, [string[]]$ExtraFiles = @())
    $files = @($Tests | ForEach-Object { $_.file } | Select-Object -Unique) + $ExtraFiles | Select-Object -Unique
    $testResults = foreach ($file in $files) {
        $assertions = @($Tests | Where-Object { $_.file -eq $file } | ForEach-Object { [pscustomobject]@{ fullName = $_.name; status = $_.status } })
        $fileStatus = if ($file -in $FailedFiles -or ($assertions | Where-Object { $_.status -eq 'failed' })) { 'failed' } else { 'passed' }
        [pscustomobject]@{ name = (($BasePath.Replace('\', '/')) + '/' + $file); status = $fileStatus; assertionResults = $assertions }
    }
    $total = if ($null -ne $TotalOverride) { [int]$TotalOverride } else { @($Tests).Count }
    return [pscustomobject]@{ numTotalTests = $total; success = $Success; testResults = @($testResults) }
}
function T { param([string]$File, [string]$Name, [string]$Status = 'passed') [pscustomobject]@{ file = $File; name = $Name; status = $Status } }
function Compare-Fake { param($Report) return Compare-ReportToExpectation -Scope 'S' -Report $Report -BasePath $base -Executed $executed -Excluded $excluded }

$allPassed = @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one'), (T 'tests/b.test.ts' 'B hidden' 'pending'))

$r = Compare-Fake (New-FakeReport $allPassed)
Assert-That 'sintetico: tutto superato con esclusione dichiarata -> passed' ($r.outcome -eq 'passed' -and (Test-Counts $r 3 3) -and $r.issues.Count -eq 0) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two' 'failed'), (T 'tests/b.test.ts' 'B one'), (T 'tests/b.test.ts' 'B hidden' 'pending')) -Success $false)
Assert-That 'sintetico: un test fallito -> test-failures' ($r.outcome -eq 'test-failures' -and (Test-Counts $r 3 2 1)) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport @($allPassed | Where-Object { $_.name -ne 'A two' }))
Assert-That 'sintetico: test atteso mancante -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and (Test-Counts $r 3 2 0 0 1)) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two' 'pending'), (T 'tests/b.test.ts' 'B one')))
Assert-That 'sintetico: test atteso saltato (pending) -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and (Test-Counts $r 3 2 0 1)) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two' 'todo'), (T 'tests/b.test.ts' 'B one')))
Assert-That 'sintetico: test atteso todo -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and $r.counts.skipped -eq 1)
$r = Compare-Fake (New-FakeReport ($allPassed + (T 'tests/a.test.ts' 'A extra')))
Assert-That 'sintetico: test non previsto -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and (Test-Counts $r 3 3 0 0 0 1)) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport ($allPassed + (T 'tests/a.test.ts' 'A one')))
Assert-That 'sintetico: test duplicato -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and @($r.issues | Where-Object { $_ -like 'test duplicato*' }).Count -eq 1)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one'), (T 'tests/b.test.ts' 'B hidden' 'passed')))
Assert-That 'sintetico: test escluso eseguito -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and $r.counts.unexpected -eq 1)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one')))
Assert-That 'sintetico: esclusione non comparsa nel report -> ancora passed' ($r.outcome -eq 'passed')
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two')) -Success $false -FailedFiles @('tests/b.test.ts') -ExtraFiles @('tests/b.test.ts'))
Assert-That 'sintetico: file che non si carica (0 asserzioni) -> test-failures, mancanti spiegati' ($r.outcome -eq 'test-failures' -and $r.fileFailures.Count -eq 1 -and (Test-Counts $r 3 2 0 0 1)) (Format-Counts $r)
$r = Compare-Fake (New-FakeReport $allPassed -Success $false)
Assert-That 'sintetico: success false senza test falliti (errore di run) -> test-failures' ($r.outcome -eq 'test-failures')
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two' 'failed'), (T 'tests/b.test.ts' 'B one')) -Success $true)
Assert-That 'sintetico: success true con test fallito -> evaluator-error (incoerente)' ($r.outcome -eq 'evaluator-error')
$r = Compare-Fake (New-FakeReport $allPassed -TotalOverride 9)
Assert-That 'sintetico: numTotalTests incoerente -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and @($r.issues | Where-Object { $_ -like 'numTotalTests*' }).Count -eq 1)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one'), (T 'tests/a.test.ts' 'A two' 'weird'), (T 'tests/b.test.ts' 'B one')))
Assert-That 'sintetico: stato sconosciuto -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and @($r.issues | Where-Object { $_ -like "stato sconosciuto*" }).Count -eq 1)
$r = Compare-Fake $null
Assert-That 'sintetico: report assente -> evaluator-error, tutti i test mancanti' ($r.outcome -eq 'evaluator-error' -and (Test-Counts $r 3 0 0 0 3))
$r = Compare-Fake (New-FakeReport $allPassed -BasePath 'C:\Altrove\submission')
Assert-That 'sintetico: file fuori dalla directory attesa -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and @($r.issues | Where-Object { $_ -like 'file di test fuori*' }).Count -ge 1)
$r = Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one' 'failed'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one'), (T 'tests/a.test.ts' 'Extra')) -Success $false)
Assert-That 'sintetico: fallimento piu anomalia strutturale -> prevale evaluator-error' ($r.outcome -eq 'evaluator-error' -and $r.counts.failed -eq 1)
$r = Compare-ReportToExpectation -Scope 'S' -Report (New-FakeReport $allPassed -BasePath 'c:\fake\work\SUBMISSION') -BasePath $base -Executed $executed -Excluded $excluded
Assert-That 'sintetico: confronto dei percorsi insensibile alle maiuscole' ($r.outcome -eq 'passed')
$merged = Merge-ScopeResults -Results @((Compare-Fake (New-FakeReport $allPassed)), (Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one' 'failed'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one')) -Success $false)))
Assert-That 'merge: somma dei conteggi ed esito peggiore' ($merged.outcome -eq 'test-failures' -and $merged.counts.expected -eq 6 -and $merged.counts.passed -eq 5 -and $merged.counts.failed -eq 1)
$merged = Merge-ScopeResults -Results @((Compare-Fake $null), (Compare-Fake (New-FakeReport @((T 'tests/a.test.ts' 'A one' 'failed'), (T 'tests/a.test.ts' 'A two'), (T 'tests/b.test.ts' 'B one')) -Success $false)))
Assert-That 'merge: evaluator-error prevale su test-failures' ($merged.outcome -eq 'evaluator-error')

# --- Report reali ----------------------------------------------------------------------------------
function New-BaselineSubmission {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path "$Path\src" | Out-Null
    foreach ($name in 'package.json', 'package-lock.json', 'tsconfig.json') { Copy-Item (Join-Path $BaselinePath $name) "$Path\$name" }
    Copy-Item (Join-Path $BaselinePath 'src\index.ts') "$Path\src\index.ts"
}
function New-FixtureSubmission {
    param([string]$Path, [string]$Fixture)
    Copy-Item (Join-Path $repositoryRoot "fixtures\controls\$Fixture") $Path -Recurse
    Set-Content "$Path\package-lock.json" '{"lockfileVersion":3}' -Encoding ascii
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('reports-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $runs = Join-Path $workspace 'runs'
    $unimplemented = Join-Path $workspace 'unimplemented'; New-BaselineSubmission -Path $unimplemented
    $compliant = Join-Path $workspace 'fx-compliant'; New-FixtureSubmission -Path $compliant -Fixture 'T1\R01\compliant'
    $violating = Join-Path $workspace 'fx-violating'; New-FixtureSubmission -Path $violating -Fixture 'T1\R01\violating'
    $broken = Join-Path $workspace 'fx-broken'; New-FixtureSubmission -Path $broken -Fixture 'T1\R01\compliant'
    Add-Content "$broken\src\index.ts" "`nexport const = ;"

    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $null = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    $r = Test-ReservedReport -RunDirectory $run.runDirectory -ReservedManifestPath $reservedManifest
    Assert-That 'reale riservata T1, fixture conforme: passed, 3/3' ($r.outcome -eq 'passed' -and (Test-Counts $r.scopes[0] 3 3) -and (Test-Counts $r 3 3)) (Format-Counts $r)
    $goodRun = $run.runDirectory

    $run = New-EvaluationRun -SubmissionPath $violating -TaskId 'T1' -RunsRoot $runs
    $null = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    $r = Test-ReservedReport -RunDirectory $run.runDirectory -ReservedManifestPath $reservedManifest
    Assert-That 'reale riservata T1, fixture violante: test-failures, 2 passati e 1 fallito' ($r.outcome -eq 'test-failures' -and (Test-Counts $r 3 2 1)) (Format-Counts $r)
    $violatingRun = $run.runDirectory

    $run = New-EvaluationRun -SubmissionPath $broken -TaskId 'T1' -RunsRoot $runs
    $phase = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    $r = Test-ReservedReport -RunDirectory $run.runDirectory -ReservedManifestPath $reservedManifest
    Assert-That 'reale riservata T1, sorgente con errore di sintassi: test-failures con file che non si caricano' ($r.outcome -eq 'test-failures' -and $r.scopes[0].fileFailures.Count -gt 0 -and $r.counts.missing -eq $r.scopes[0].fileFailures.Count -and $r.counts.expected -eq 3) "(fase: $($phase.status); $(Format-Counts $r); file falliti: $($r.scopes[0].fileFailures.Count); problemi: $($r.issues -join ' | '))"

    $run = New-EvaluationRun -SubmissionPath $unimplemented -TaskId 'T1' -RunsRoot $runs
    $null = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifest
    $r = Test-PublicReports -RunDirectory $run.runDirectory -PublicManifestPath $publicManifest
    Assert-That 'reale pubblica T1, funzione mancante: test-failures, 31 attesi, 27 passati e 4 falliti, due scope' ($r.outcome -eq 'test-failures' -and (Test-Counts $r 31 27 4) -and @($r.scopes).Count -eq 2) (Format-Counts $r)

    $run = New-EvaluationRun -SubmissionPath $unimplemented -TaskId 'T6' -RunsRoot $runs
    $null = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifest
    $r = Test-PublicReports -RunDirectory $run.runDirectory -PublicManifestPath $publicManifest
    Assert-That 'reale pubblica T6: 26 attesi (5 specifici + 21 comuni), 5 falliti e 6 esclusioni senza anomalie' ($r.outcome -eq 'test-failures' -and (Test-Counts $r 26 21 5) -and $r.issues.Count -eq 0) "(problemi: $($r.issues -join ' | '))"

    # --- Manomissione dei report reali -----------------------------------------------------------
    $reportPath = Join-Path $goodRun 'raw\reserved-report.json'
    $original = [System.IO.File]::ReadAllText($reportPath)
    $json = $original | ConvertFrom-Json
    $json.testResults[0].assertionResults = @()
    $json.numTotalTests = 2
    $json | ConvertTo-Json -Depth 20 | Set-Content $reportPath -Encoding utf8
    $r = Test-ReservedReport -RunDirectory $goodRun -ReservedManifestPath $reservedManifest
    Assert-That 'manomissione: asserzione rimossa dal report reale -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and $r.counts.missing -ge 1)
    [System.IO.File]::WriteAllText($reportPath, '{ non json')
    $r = Test-ReservedReport -RunDirectory $goodRun -ReservedManifestPath $reservedManifest
    Assert-That 'manomissione: report non JSON -> evaluator-error' ($r.outcome -eq 'evaluator-error' -and $r.counts.missing -eq 3)
    Remove-Item $reportPath
    $r = Test-ReservedReport -RunDirectory $goodRun -ReservedManifestPath $reservedManifest
    Assert-That 'manomissione: report assente -> evaluator-error' ($r.outcome -eq 'evaluator-error')
    [System.IO.File]::WriteAllText($reportPath, $original)
    $r = Test-ReservedReport -RunDirectory $goodRun -ReservedManifestPath $reservedManifest
    Assert-That 'report originale ripristinato -> di nuovo passed' ($r.outcome -eq 'passed')

    # --- Script di ingresso ---------------------------------------------------------------------------
    $json = & powershell -NoProfile -File $validateScript -Suite reserved -RunDirectory $goodRun
    Assert-That 'script: riservata conforme -> exit 0' ($LASTEXITCODE -eq 0 -and ($json -join "`n" | ConvertFrom-Json).outcome -eq 'passed')
    $json = & powershell -NoProfile -File $validateScript -Suite reserved -RunDirectory $violatingRun
    Assert-That 'script: riservata violata -> exit 10' ($LASTEXITCODE -eq 10 -and ($json -join "`n" | ConvertFrom-Json).counts.failed -eq 1)
    Remove-Item $reportPath
    $json = & powershell -NoProfile -File $validateScript -Suite reserved -RunDirectory $goodRun
    Assert-That 'script: report assente -> exit 40' ($LASTEXITCODE -eq 40)
    $json = & powershell -NoProfile -File $validateScript -Suite public -RunDirectory (Join-Path $workspace 'nessuna-run')
    Assert-That 'script: run inesistente -> exit 40' ($LASTEXITCODE -eq 40)
}
finally {
    foreach ($file in Get-ChildItem -LiteralPath $workspace -File -Recurse -Force -ErrorAction SilentlyContinue) { if ($file.IsReadOnly) { $file.IsReadOnly = $false } }
    foreach ($junction in Get-ChildItem -LiteralPath $workspace -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }) {
        [System.IO.Directory]::Delete($junction.FullName)
    }
    Remove-Item -LiteralPath $workspace -Recurse -Force
}

Write-Output "Totale: $script:total, falliti: $script:failures"
if ($script:failures -gt 0) { exit 1 }
exit 0
