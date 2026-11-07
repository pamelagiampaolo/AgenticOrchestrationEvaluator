<#
.SYNOPSIS
Test automatici di schema, exit code e coerenza del riepilogo di valutazione.

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito.
Non usa Pester per non dipendere dalla versione installata nel sistema.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\EvaluationSummary.psm1') -Force

$schemaPath = Join-Path $PSScriptRoot '..\..\schemas\evaluation-summary.schema.json'
$script:failures = 0
$script:total = 0

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" }
    else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function New-Counts {
    param([int]$Expected, [int]$Passed, [int]$Failed = 0, [int]$Skipped = 0, [int]$Missing = 0, [int]$Unexpected = 0)
    return [ordered]@{ expected = $Expected; executed = $Passed + $Failed; passed = $Passed; failed = $Failed; skipped = $Skipped; missing = $Missing; unexpected = $Unexpected }
}

function New-Phase {
    param([string]$Status)
    $exitCode = $null; $duration = $null
    if ($Status -ne 'not-run') { $duration = 1200; $exitCode = if ($Status -eq 'passed') { 0 } else { 1 } }
    return [ordered]@{ status = $Status; durationMs = $duration; exitCode = $exitCode }
}

# Riepilogo coerente per l'esito indicato; restituisce una tabella da serializzare.
function New-SummaryTable {
    param([string]$Outcome)

    $summary = [ordered]@{
        schemaVersion = 1
        runId         = 'run-2026-11-07-T1-001'
        taskId        = 'T1'
        outcome       = $Outcome
        exitCode      = Get-EvaluationExitCode -Outcome $Outcome
        startedAtUtc  = '2026-11-07T10:00:00.000Z'
        finishedAtUtc = '2026-11-07T10:00:09.500Z'
        durationMs    = 9500
        suites        = [ordered]@{ reservedSuiteVersion = 'reserved-1'; publicSuiteVersion = 'public-1'; baselineDeclaredCommit = 'ddf08e8759ef172a5b654168a1d2d6b66c9cd248' }
        phases        = [ordered]@{ build = New-Phase 'passed'; public = New-Phase 'passed'; reserved = New-Phase 'passed' }
        publicTests   = New-Counts -Expected 31 -Passed 31
        reservedTests = New-Counts -Expected 3 -Passed 3
        integrity     = [ordered]@{ originalInputUnchanged = $true; archivedSubmissionUnchanged = $true; suiteManifestsVerified = $true }
        environment   = [ordered]@{ windows = 'unavailable'; architecture = 'x64'; node = 'v24.17.0'; npm = '11.13.0'; typescript = '7.0.2'; vitest = '5.1.0'; lockFileSha256 = 'unavailable'; evaluatorVersion = 'unavailable' }
        diagnostics   = @()
    }
    switch ($Outcome) {
        'test-failures' {
            $summary.phases.reserved = New-Phase 'failed'
            $summary.reservedTests = New-Counts -Expected 3 -Passed 2 -Failed 1
        }
        'build-failure' {
            $summary.phases.build = New-Phase 'failed'
            $summary.phases.public = New-Phase 'not-run'; $summary.phases.reserved = New-Phase 'not-run'
            $summary.publicTests = $null; $summary.reservedTests = $null
        }
        'timeout' {
            $summary.phases.public = New-Phase 'timeout'; $summary.phases.reserved = New-Phase 'not-run'
            $summary.publicTests = $null; $summary.reservedTests = $null
        }
        'invalid-input' {
            foreach ($phase in 'build', 'public', 'reserved') { $summary.phases[$phase] = New-Phase 'not-run' }
            $summary.publicTests = $null; $summary.reservedTests = $null
            $summary.integrity = [ordered]@{ originalInputUnchanged = $null; archivedSubmissionUnchanged = $null; suiteManifestsVerified = $null }
            $summary.diagnostics = @('SubmissionPath non contiene package.json.')
        }
        'integrity-error' {
            $summary.integrity.archivedSubmissionUnchanged = $false
            $summary.diagnostics = @('La submission archiviata non coincide con il manifest.')
        }
        'evaluator-error' {
            $summary.phases.public = New-Phase 'error'; $summary.phases.reserved = New-Phase 'not-run'
            $summary.publicTests = $null; $summary.reservedTests = $null
            $summary.diagnostics = @('Report pubblico assente o non valido.')
        }
    }
    return $summary
}

# Serializza e rilegge la tabella, come farebbe il consumatore reale del file.
function ConvertTo-SummaryObject {
    param($Table)
    return ($Table | ConvertTo-Json -Depth 10) | ConvertFrom-Json
}

function Get-Problems {
    param($Table)
    return @(Test-EvaluationSummary -Summary (ConvertTo-SummaryObject -Table $Table) -SchemaPath $schemaPath)
}

function Assert-Rejected {
    param([string]$Name, $Table, [string]$ExpectedFragment)
    $problems = @(Get-Problems -Table $Table)
    $matched = @($problems | Where-Object { $_ -like "*$ExpectedFragment*" }).Count -gt 0
    Assert-That -Name "rifiuta: $Name" -Condition $matched -Detail "(problemi: $($problems -join ' ; '))"
}

# --- Esiti validi -----------------------------------------------------------
foreach ($outcome in 'passed', 'test-failures', 'build-failure', 'timeout', 'invalid-input', 'integrity-error', 'evaluator-error') {
    $problems = @(Get-Problems -Table (New-SummaryTable -Outcome $outcome))
    Assert-That -Name "accetta riepilogo valido: $outcome" -Condition ($problems.Count -eq 0) -Detail "(problemi: $($problems -join ' ; '))"
}

# --- Exit code ed esiti -------------------------------------------------------
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
$outcomes = @($schema.properties.outcome.enum)
$codes = @($outcomes | ForEach-Object { Get-EvaluationExitCode -Outcome $_ })
Assert-That -Name 'lo schema elenca 7 esiti' -Condition ($outcomes.Count -eq 7)
Assert-That -Name 'gli exit code sono tutti distinti' -Condition (@($codes | Select-Object -Unique).Count -eq 7)
Assert-That -Name 'gli exit code coincidono con l''enum dello schema' -Condition (-not (Compare-Object @($schema.properties.exitCode.enum) $codes))
Assert-That -Name 'passed vale 0 e nessun altro esito vale 0' -Condition ((Get-EvaluationExitCode -Outcome 'passed') -eq 0 -and @($codes | Where-Object { $_ -eq 0 }).Count -eq 1)
$threw = $false; try { Get-EvaluationExitCode -Outcome 'sconosciuto' | Out-Null } catch { $threw = $true }
Assert-That -Name 'un esito sconosciuto genera un errore' -Condition $threw

$allFalse = @{ InputInvalid = $false; IntegrityViolated = $false; EvaluatorError = $false; TimedOut = $false; BuildFailed = $false; TestsFailed = $false }
Assert-That -Name 'nessuna causa -> passed' -Condition ((Get-EvaluationOutcome @allFalse) -eq 'passed')
$precedence = @(
    @('InputInvalid', 'invalid-input'), @('IntegrityViolated', 'integrity-error'), @('EvaluatorError', 'evaluator-error'),
    @('TimedOut', 'timeout'), @('BuildFailed', 'build-failure'), @('TestsFailed', 'test-failures')
)
for ($index = 0; $index -lt $precedence.Count; $index++) {
    $facts = @{}
    foreach ($key in $allFalse.Keys) { $facts[$key] = $false }
    for ($later = $index; $later -lt $precedence.Count; $later++) { $facts[$precedence[$later][0]] = $true }
    Assert-That -Name "precedenza: con $($precedence[$index][0]) e cause successive vale $($precedence[$index][1])" -Condition ((Get-EvaluationOutcome @facts) -eq $precedence[$index][1])
}

# --- Violazioni dello schema ----------------------------------------------------
$base = { New-SummaryTable -Outcome 'passed' }
$t = & $base; $t.Remove('runId'); Assert-Rejected 'campo obbligatorio mancante' $t "campo obbligatorio mancante 'runId'"
$t = & $base; $t['extra'] = 1; Assert-Rejected 'campo non previsto' $t "campo non previsto 'extra'"
$t = & $base; $t.durationMs = '9500'; Assert-Rejected 'tipo errato (durationMs stringa)' $t 'tipo non valido'
$t = & $base; $t.durationMs = 1.5; Assert-Rejected 'durationMs non intero' $t 'tipo non valido'
$t = & $base; $t.durationMs = -1; Assert-Rejected 'durata negativa' $t 'minore di 0'
$t = & $base; $t.outcome = 'ok'; Assert-Rejected 'esito sconosciuto' $t 'valore non ammesso'
$t = & $base; $t.taskId = 'T7'; Assert-Rejected 'taskId fuori elenco' $t 'valore non ammesso'
$t = & $base; $t.schemaVersion = 2; Assert-Rejected 'schemaVersion diversa' $t 'costante'
$t = & $base; $t.runId = '..\evil'; Assert-Rejected 'runId con path traversal' $t 'pattern'
$t = & $base; $t.startedAtUtc = '2026-11-07 10:00:00'; Assert-Rejected 'timestamp non ISO UTC' $t 'pattern'
$t = & $base; $t.exitCode = 3; Assert-Rejected 'exit code fuori elenco' $t 'valore non ammesso'
$t = & $base; $t.reservedTests.passed = -1; Assert-Rejected 'conteggio negativo' $t 'minore di 0'
$t = & $base; $t.phases.build.status = 'done'; Assert-Rejected 'stato di fase sconosciuto' $t 'valore non ammesso'
$t = & $base; $t.environment.Remove('node'); Assert-Rejected 'ambiente incompleto' $t "'node'"
$t = & $base; $t.diagnostics = @('x' * 501); Assert-Rejected 'diagnostica troppo lunga' $t 'piu lunga'
$t = & $base; $t.integrity.originalInputUnchanged = 'yes'; Assert-Rejected 'integrita non booleana' $t 'tipo non valido'

# --- Violazioni di coerenza -----------------------------------------------------
$t = & $base; $t.exitCode = 10; Assert-Rejected 'exit code incoerente con l''esito' $t 'incoerente con l''esito'
$t = & $base; $t.finishedAtUtc = '2026-11-07T09:59:59.000Z'; Assert-Rejected 'fine prima dell''inizio' $t 'precede'
$t = & $base; $t.reservedTests = New-Counts -Expected 3 -Passed 2 -Failed 1; Assert-Rejected 'passed con test falliti' $t 'passed richiede'
$t = & $base; $t.publicTests = New-Counts -Expected 31 -Passed 30 -Skipped 1; Assert-Rejected 'passed con test saltati' $t 'passed richiede'
$t = & $base; $t.publicTests = New-Counts -Expected 31 -Passed 30 -Missing 1; Assert-Rejected 'passed con test mancanti' $t 'executed uguale a expected'
$t = & $base; $t.reservedTests = New-Counts -Expected 3 -Passed 3 -Unexpected 1; Assert-Rejected 'passed con test inattesi' $t 'passed richiede'
$t = & $base; $t.integrity.suiteManifestsVerified = $null; Assert-Rejected 'passed con integrita non verificata' $t 'integrity.suiteManifestsVerified'
$t = & $base; $t.phases.reserved.status = 'not-run'; Assert-Rejected 'passed con fase non eseguita' $t 'tutte le fasi passed'
$t = & $base; $t.diagnostics = @('nota'); Assert-Rejected 'passed con diagnostica' $t 'diagnostics'
$t = & $base; $t.reservedTests.executed = 5; Assert-Rejected 'executed diverso da passed + failed' $t 'executed diverso'
$t = & $base; $t.publicTests = $null; Assert-Rejected 'conteggi nulli con fase passed' $t 'nullo'
$t = New-SummaryTable -Outcome 'build-failure'; $t.publicTests = New-Counts -Expected 31 -Passed 31; Assert-Rejected 'conteggi presenti con fase not-run' $t 'not-run'
$t = New-SummaryTable -Outcome 'test-failures'; $t.reservedTests = New-Counts -Expected 3 -Passed 3; $t.phases.reserved = New-Phase 'passed'; Assert-Rejected 'test-failures senza test falliti' $t 'almeno un test fallito'
$t = New-SummaryTable -Outcome 'build-failure'; $t.phases.build = New-Phase 'passed'; Assert-Rejected 'build-failure con build passed' $t 'build failed'
$t = New-SummaryTable -Outcome 'timeout'; $t.phases.public = New-Phase 'failed'; Assert-Rejected 'timeout senza fase in timeout' $t 'fase in timeout'
$t = New-SummaryTable -Outcome 'integrity-error'; $t.integrity.archivedSubmissionUnchanged = $true; Assert-Rejected 'integrity-error senza controllo falso' $t 'integrita false'
$t = New-SummaryTable -Outcome 'evaluator-error'; $t.diagnostics = @(); Assert-Rejected 'evaluator-error senza diagnostica' $t 'messaggio diagnostico'
$t = New-SummaryTable -Outcome 'invalid-input'; $t.diagnostics = @(); Assert-Rejected 'invalid-input senza diagnostica' $t 'messaggio diagnostico'

# --- Il validatore non ignora parole chiave sconosciute ---------------------------
$unsupported = '{"oneOf": []}' | ConvertFrom-Json
$threw = $false; try { Test-JsonSchemaSubset -Value 1 -Schema $unsupported -RootSchema $unsupported | Out-Null } catch { $threw = $true }
Assert-That -Name 'parola chiave dello schema non supportata genera un errore' -Condition $threw

Write-Output "Totale: $script:total, falliti: $script:failures"
if ($script:failures -gt 0) { exit 1 }
exit 0
