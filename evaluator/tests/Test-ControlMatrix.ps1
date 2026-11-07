<#
.SYNOPSIS
Matrice di accettazione dei controlli riservati, eseguita attraverso l'orchestratore reale.

.DESCRIPTION
Per ogni fixture di `fixtures/controls/<Task>/<Rxx>/{compliant,violating}` (comprese le varianti
di T5-R01) esegue una valutazione completa e verifica, dal report riservato grezzo:
- fixture conforme: tutta la suite riservata del task passa (conteggi del manifest);
- fixture violante: fallisce esattamente il test del proprio controllo e passano tutti gli altri.
In entrambi i casi la build deve riuscire, l'esito non deve essere un errore del valutatore, di
integrita o di input, e il riepilogo non deve contenere identificatori riservati.
Le suite pubbliche falliscono per costruzione (le fixture sono soluzioni minime per i controlli).

.PARAMETER Tasks
Sottoinsieme di task (default: T1..T6).

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito. Circa 8 secondi per fixture.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
    [Parameter(Mandatory)][string]$BaselinePath,
    [ValidateSet('T1', 'T2', 'T3', 'T4', 'T5', 'T6')][string[]]$Tasks = @('T1', 'T2', 'T3', 'T4', 'T5', 'T6')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'AcceptanceHelpers.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Evaluation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EvaluationSummary.psm1') -Force
$schemaPath = Join-Path $repositoryRoot 'schemas\evaluation-summary.schema.json'
$reservedManifest = Get-Content (Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json') -Raw | ConvertFrom-Json

# Controlli le cui fixture soddisfano soltanto la proprieta "sul proprio controllo": la conforme supera
# il proprio controllo e la violante lo fallisce, ma entrambe falliscono anche altri controlli del task.
# Deroga accettata dall'utente il 7 novembre 2026 (docs/evaluator-contract.md, sezione "Accettazione e
# isolamento"): per queste si verifica la sola proprieta registrata.
$ownControlOnly = @('T2-R03', 'T5-R01', 'T5-R02', 'T5-R03', 'T6-R04')

# Elenco delle fixture: ogni directory con un package.json sotto compliant/ o violating/.
$fixtures = New-Object System.Collections.Generic.List[object]
$controlsRoot = Join-Path $repositoryRoot 'fixtures\controls'
foreach ($taskDirectory in Get-ChildItem $controlsRoot -Directory | Where-Object { $_.Name -in $Tasks }) {
    foreach ($controlDirectory in Get-ChildItem $taskDirectory.FullName -Directory) {
        foreach ($kind in 'compliant', 'violating') {
            $kindRoot = Join-Path $controlDirectory.FullName $kind
            foreach ($package in Get-ChildItem $kindRoot -Filter package.json -Recurse -File) {
                $relative = $package.DirectoryName.Substring($controlsRoot.Length + 1)
                $fixtures.Add([pscustomobject]@{ task = $taskDirectory.Name; controlId = ($taskDirectory.Name + '-' + $controlDirectory.Name); kind = $kind; relative = $relative })
            }
        }
    }
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('matrix-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $runs = Join-Path $workspace 'runs'
    $index = 0
    foreach ($fixture in $fixtures) {
        $index++
        $label = "$($fixture.controlId) $($fixture.kind) [$($fixture.relative)]"
        $submission = Join-Path $workspace "fx-$index"
        New-FixtureSubmission -Path $submission -FixtureRelativePath $fixture.relative
        $runId = "matrix-$index"
        $result = Invoke-Evaluation -SubmissionPath $submission -TaskId $fixture.task -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot $runs -RunId $runId
        $summary = $result.summary
        $expectedCount = @($reservedManifest.tasks.($fixture.task).tests).Count

        $reportPath = Join-Path $runs "$runId\raw\reserved-report.json"
        $tests = @()
        if (Test-Path $reportPath) { $tests = @((Read-JsonFile $reportPath).testResults | ForEach-Object { $_.assertionResults }) }
        $passedNames = @($tests | Where-Object { $_.status -eq 'passed' } | ForEach-Object { $_.fullName })
        $failedNames = @($tests | Where-Object { $_.status -eq 'failed' } | ForEach-Object { $_.fullName })

        $structuralOk = $null -ne $summary -and $summary.phases.build.status -eq 'passed' -and $result.outcome -in 'test-failures', 'passed' -and $summary.reservedTests.expected -eq $expectedCount -and $summary.reservedTests.missing -eq 0 -and $summary.reservedTests.unexpected -eq 0 -and $summary.reservedTests.skipped -eq 0
        $summaryText = if ($result.summaryPath) { [System.IO.File]::ReadAllText($result.summaryPath) } else { '' }
        $cleanSummary = $result.summaryPath -and $summaryText -notmatch 'T\d-R\d\d' -and @(Test-EvaluationSummary -Summary (Read-JsonFile $result.summaryPath) -SchemaPath $schemaPath).Count -eq 0
        $detail = "(esito: $($result.outcome); build: $($summary.phases.build.status); riservata: $($summary.phases.reserved.status); passati: $($passedNames.Count); falliti: $($failedNames -join ', '); $($result.diagnostics -join ' | '))"

        $ownPassed = @($passedNames | Where-Object { $_.StartsWith($fixture.controlId, [System.StringComparison]::Ordinal) }).Count -eq 1
        $ownFailed = @($failedNames | Where-Object { $_.StartsWith($fixture.controlId, [System.StringComparison]::Ordinal) }).Count -eq 1
        if ($fixture.controlId -in $ownControlOnly) {
            if ($fixture.kind -eq 'compliant') {
                Assert-That "$label -> supera il proprio controllo (validata solo sul proprio controllo)" ($structuralOk -and $ownPassed -and -not $ownFailed -and $cleanSummary) $detail
            }
            else {
                Assert-That "$label -> fallisce il proprio controllo (validata solo sul proprio controllo)" ($structuralOk -and $ownFailed -and $cleanSummary) $detail
            }
            continue
        }
        if ($fixture.kind -eq 'compliant') {
            Assert-That "$label -> suite riservata del task superata ($expectedCount/$expectedCount)" ($structuralOk -and $summary.phases.reserved.status -eq 'passed' -and $summary.reservedTests.passed -eq $expectedCount -and $failedNames.Count -eq 0 -and $cleanSummary) $detail
        }
        else {
            $onlyOwnControl = $failedNames.Count -eq 1 -and $failedNames[0].StartsWith($fixture.controlId, [System.StringComparison]::Ordinal) -and $passedNames.Count -eq ($expectedCount - 1)
            Assert-That "$label -> fallisce soltanto il proprio controllo" ($structuralOk -and $summary.phases.reserved.status -eq 'failed' -and $onlyOwnControl -and $cleanSummary) $detail
        }
    }
    Assert-That 'le dipendenze canoniche reali sono ancora presenti' (Test-Path (Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'))
}
finally {
    Remove-TestWorkspace -Path $workspace
}

Write-Output "Fixture eseguite: $($fixtures.Count). Totale: $script:total, falliti: $script:failures"
if ($script:failures -gt 0) { exit 1 }
exit 0
