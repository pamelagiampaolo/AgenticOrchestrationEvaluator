<#
.SYNOPSIS
Test di accettazione e isolamento dell'orchestratore con strumenti reali.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con TypeScript e Vitest reali.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato (solo lettura).

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito.
Certifica soltanto le proprieta direttamente osservate: il rilevamento dell'alterazione di input e
suite riservate, non la sua prevenzione (candidato e controlli condividono processo e identita).
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
. (Join-Path $PSScriptRoot 'AcceptanceHelpers.ps1')
Import-Module (Join-Path $PSScriptRoot '..\Evaluation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EvaluationInput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EvaluationSummary.psm1') -Force
$schemaPath = Join-Path $repositoryRoot 'schemas\evaluation-summary.schema.json'
$entryScript = Join-Path $PSScriptRoot '..\Invoke-Evaluation.ps1'

function Test-SummaryFile {
    param([string]$Path)
    return @(Test-EvaluationSummary -Summary (Read-JsonFile -Path $Path) -SchemaPath $schemaPath)
}

function Get-DescendantProcessIds {
    param([int]$RootId)
    $all = @(Get-CimInstance Win32_Process)
    $found = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootId)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($child in $all | Where-Object { $_.ParentProcessId -eq $current }) { $found.Add([int]$child.ProcessId); $queue.Enqueue([int]$child.ProcessId) }
    }
    return $found.ToArray()
}

# Riepilogo privo dei campi che variano tra run equivalenti (identificativi, istanti e durate).
function Get-NormalizedSummaryText {
    param($Summary)
    $copy = $Summary | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $copy.runId = 'X'; $copy.startedAtUtc = 'X'; $copy.finishedAtUtc = 'X'; $copy.durationMs = 0
    foreach ($phase in 'build', 'public', 'reserved') { $copy.phases.$phase.durationMs = 0 }
    return $copy | ConvertTo-Json -Depth 10
}

# Impronta delle cache di Vitest nelle dipendenze canoniche (file e dimensioni). Le run non devono
# scriverci: le cache contengono esiti e moduli trasformati dei test, anche riservati.
function Get-ToolsCacheFingerprint {
    $entries = foreach ($name in '.vite', '.vitest-cache', '.vitest') {
        $path = Join-Path $ToolsNodeModulesPath $name
        if (Test-Path -LiteralPath $path) { Get-ChildItem -LiteralPath $path -Recurse -File -Force | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } }
    }
    return (@($entries) | Sort-Object) -join "`n"
}
$cacheBefore = Get-ToolsCacheFingerprint

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('acceptance-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $runs = Join-Path $workspace 'runs'
    $evaluate = { param($Path, $Task = 'T1', $Id = '', $Tools = $ToolsNodeModulesPath)
        $arguments = @{ SubmissionPath = $Path; TaskId = $Task; BaselinePath = $BaselinePath; ToolsNodeModulesPath = $Tools; RunsRoot = $runs }
        if ($Id) { $arguments.RunId = $Id }
        Invoke-Evaluation @arguments }

    $solution = Join-Path $workspace 'solution'; New-Submission -Path $solution -ImplementT1
    $unimplemented = Join-Path $workspace 'unimplemented'; New-Submission -Path $unimplemented

    # --- Determinismo --------------------------------------------------------------------------------------
    $first = & $evaluate $solution; $second = & $evaluate $solution
    Assert-That 'determinismo: due run della stessa submission danno riepiloghi equivalenti' ($first.outcome -eq 'passed' -and (Get-NormalizedSummaryText $first.summary) -eq (Get-NormalizedSummaryText $second.summary) -and $first.summary.runId -ne $second.summary.runId)

    # --- Il codice del candidato non entra nel risultato canonico ----------------------------------------------------
    $cheater = Join-Path $workspace 'cheater'; New-Submission -Path $cheater
    New-Item -ItemType Directory -Force -Path "$cheater\tests\public\t1", "$cheater\reserved", "$cheater\tests\reserved" | Out-Null
    Set-Content "$cheater\tests\public\t1\find-products-below-stock.test.ts" "import { test } from 'vitest'; test('sempre vero', () => {});" -Encoding ascii
    Set-Content "$cheater\reserved\t1-r01.test.ts" "import { test } from 'vitest'; test('T1-R01', () => {});" -Encoding ascii
    Set-Content "$cheater\tests\reserved\t1-r01.test.ts" "import { test } from 'vitest'; test('T1-R01', () => {});" -Encoding ascii
    $result = & $evaluate $cheater
    Assert-That 'test e finti test riservati forniti dal candidato sono ignorati: la funzione mancante resta test-failures' ($result.outcome -eq 'test-failures' -and $result.summary.publicTests.failed -eq 4 -and $result.summary.reservedTests.failed -eq 3 -and $result.summary.reservedTests.expected -eq 3) "(esito: $($result.outcome))"

    $markerFile = Join-Path $workspace 'marker-config.txt'
    $configAttack = Join-Path $workspace 'config-attack'; New-Submission -Path $configAttack -ImplementT1
    $markerCode = "import fs from 'node:fs'; fs.writeFileSync('" + $markerFile.Replace('\', '/') + "', 'eseguito'); export default {};"
    Set-Content "$configAttack\vitest.config.ts" $markerCode -Encoding ascii
    Set-Content "$configAttack\vite.config.ts" $markerCode -Encoding ascii
    New-Item -ItemType Directory -Force -Path "$configAttack\node_modules\.bin" | Out-Null
    Set-Content "$configAttack\node_modules\.bin\vitest.cmd" "@echo off`r`necho eseguito> `"$markerFile`"`r`nexit /b 0" -Encoding ascii
    $package = Get-Content "$configAttack\package.json" -Raw | ConvertFrom-Json
    $package | Add-Member -NotePropertyName scripts -NotePropertyValue ([pscustomobject]@{ build = "echo eseguito> $($markerFile)"; test = "echo eseguito> $($markerFile)" }) -Force
    $package | ConvertTo-Json -Depth 5 | Set-Content "$configAttack\package.json" -Encoding ascii
    $result = & $evaluate $configAttack
    Assert-That 'configurazioni Vite/Vitest, node_modules e scripts del candidato non vengono usati o eseguiti' ($result.outcome -eq 'passed' -and -not (Test-Path $markerFile)) "(esito: $($result.outcome); marker presente: $(Test-Path $markerFile))"

    $fakeCompiler = Join-Path $workspace 'fake-compiler'; New-Submission -Path $fakeCompiler -Broken
    New-Item -ItemType Directory -Force -Path "$fakeCompiler\node_modules\.bin" | Out-Null
    Set-Content "$fakeCompiler\node_modules\.bin\tsc.cmd" "@echo off`r`nexit /b 0" -Encoding ascii
    $result = & $evaluate $fakeCompiler
    Assert-That 'compilatore finto nel node_modules del candidato ignorato: l''errore di sintassi resta build-failure' ($result.outcome -eq 'build-failure' -and $result.exitCode -eq 11)

    # --- Alterazione dei file durante la run (rilevamento) ---------------------------------------------------------------
    $tamperReserved = Join-Path $workspace 'tamper-reserved'
    $reservedProbeId = 'run-attacco-riservati'
    $reservedTarget = Join-Path $runs "$reservedProbeId\work\reserved\t1-r01.test.ts"
    New-Submission -Path $tamperReserved -ImplementT1 -ExtraSource (New-WriterSnippet -Targets @($reservedTarget))
    $result = & $evaluate $tamperReserved 'T1' $reservedProbeId
    Assert-That 'codice candidato che modifica la copia dei test riservati: integrity-error (rilevato)' ($result.outcome -eq 'integrity-error' -and $result.exitCode -eq 30 -and @($result.diagnostics | Where-Object { $_ -like '*riservata*' }).Count -ge 1 -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"

    $tamperSource = Join-Path $workspace 'tamper-source'
    New-Submission -Path $tamperSource -ImplementT1 -ExtraSource (New-WriterSnippet -Targets @((Join-Path $tamperSource 'package.json')))
    $result = & $evaluate $tamperSource
    Assert-That 'codice candidato che modifica il proprio sorgente originale: integrity-error, originalInputUnchanged false' ($result.outcome -eq 'integrity-error' -and $result.summary.integrity.originalInputUnchanged -eq $false -and $result.summary.integrity.archivedSubmissionUnchanged -eq $true) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"

    $archiveProbeId = 'run-attacco-archivio'
    $tamperArchive = Join-Path $workspace 'tamper-archive'
    New-Submission -Path $tamperArchive -ImplementT1 -ExtraSource (New-WriterSnippet -Targets @((Join-Path $runs "$archiveProbeId\input\submission\package.json")))
    $result = & $evaluate $tamperArchive 'T1' $archiveProbeId
    Assert-That 'codice candidato che modifica la propria copia archiviata: integrity-error, archivedSubmissionUnchanged false' ($result.outcome -eq 'integrity-error' -and $result.summary.integrity.archivedSubmissionUnchanged -eq $false -and $result.summary.integrity.originalInputUnchanged -eq $true) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"

    # --- Instradamento per task sulla baseline non implementata --------------------------------------------------------------------------
    # Per ogni task: conteggi attesi dai manifest (pubblici, riservati) e stato osservato della suite riservata
    # sulla baseline non modificata. OSSERVAZIONE: per T3 la baseline supera tutti e 3 i controlli riservati
    # (il difetto che T3-P02 intercetta non e coperto da alcun controllo riservato); per gli altri task li fallisce.
    $expectedByTask = [ordered]@{
        T2 = @{ public = 31; reserved = 3; reservedStatus = 'failed' }
        T3 = @{ public = 30; reserved = 3; reservedStatus = 'passed' }
        T4 = @{ public = 31; reserved = 3; reservedStatus = 'failed' }
        T5 = @{ public = 30; reserved = 3; reservedStatus = 'failed' }
        T6 = @{ public = 26; reserved = 4; reservedStatus = 'failed' }
    }
    foreach ($task in $expectedByTask.Keys) {
        $expected = $expectedByTask[$task]
        $result = & $evaluate $unimplemented $task
        $s = $result.summary
        $ok = $result.outcome -eq 'test-failures' -and $s.phases.build.status -eq 'passed' -and $s.phases.public.status -eq 'failed' -and $s.phases.reserved.status -eq $expected.reservedStatus -and $s.publicTests.expected -eq $expected.public -and $s.reservedTests.expected -eq $expected.reserved -and $s.publicTests.missing -eq 0 -and $s.publicTests.unexpected -eq 0 -and $s.reservedTests.missing -eq 0 -and $s.reservedTests.unexpected -eq 0 -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0
        Assert-That "instradamento $task sulla baseline: test-failures, attesi pubblici $($expected.public) e riservati $($expected.reserved), suite riservata $($expected.reservedStatus)" $ok "(esito: $($result.outcome); riservata: $($s.phases.reserved.status); pubblici attesi $($s.publicTests.expected); riservati attesi $($s.reservedTests.expected); $($result.diagnostics -join ' | '))"
    }
    $mismatch = & $evaluate $solution 'T2'
    Assert-That 'soluzione T1 valutata come T2: test-failures (non errore del valutatore)' ($mismatch.outcome -eq 'test-failures' -and $mismatch.summary.phases.public.status -eq 'failed')

    # --- Interruzione della run ----------------------------------------------------------------------------------------------------------------
    $fakeSleep = Join-Path $workspace 'fake-sleep'
    New-Item -ItemType Directory -Force -Path "$fakeSleep\.bin" | Out-Null
    Set-Content "$fakeSleep\.bin\tsc.cmd" "@echo off`r`nexit /b 0" -Encoding ascii
    Set-Content "$fakeSleep\.bin\vitest.cmd" "@echo off`r`nping -n 60 127.0.0.1 >nul" -Encoding ascii
    # Versioni del manifest degli strumenti, altrimenti il controllo preliminare ferma la run prima delle fasi.
    $toolchain = Get-Content (Join-Path $repositoryRoot 'manifests\toolchain.manifest.json') -Raw | ConvertFrom-Json
    foreach ($package in 'typescript', 'vitest') {
        New-Item -ItemType Directory -Force -Path "$fakeSleep\$package" | Out-Null
        Set-Content "$fakeSleep\$package\package.json" "{ `"name`": `"$package`", `"version`": `"$($toolchain.$package)`" }" -Encoding ascii
    }
    $interruptedId = 'run-interrotta'
    $arguments = "-NoProfile -File `"$entryScript`" -SubmissionPath `"$solution`" -TaskId T1 -BaselinePath `"$BaselinePath`" -ToolsNodeModulesPath `"$fakeSleep`" -RunsRoot `"$runs`" -RunId $interruptedId"
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $sentinel = Join-Path $runs "$interruptedId\raw\step-common.stdout.tmp"
    $waited = 0
    while (-not (Test-Path $sentinel) -and $waited -lt 90) { Start-Sleep -Seconds 1; $waited++ }
    $descendants = @(Get-DescendantProcessIds -RootId $process.Id)
    & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
    Start-Sleep -Seconds 2
    $survivors = @($descendants | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    $partial = Join-Path $runs $interruptedId
    $partialManifest = Read-JsonFile -Path (Join-Path $partial 'input\submission-manifest.json')
    Assert-That 'interruzione: la run e stata fermata mentre la fase pubblica era in corso' ($waited -lt 90 -and $descendants.Count -gt 0) "(attesa: ${waited}s; discendenti: $($descendants.Count))"
    Assert-That 'interruzione: nessun riepilogo scritto e nessun processo superstite' (-not (Test-Path (Join-Path $partial 'evidence\evaluation-summary.json')) -and $survivors.Count -eq 0) "(superstiti: $($survivors -join ','))"
    Assert-That 'interruzione: archivio e manifest dell''input restano integri' (@(Compare-SubmissionToManifest -Root (Join-Path $partial 'input\submission') -Manifest $partialManifest -Scope 'a').Count -eq 0)
    $partialHash = (Get-FileHash (Join-Path $partial 'input\submission-manifest.json')).Hash
    $again = & $evaluate $solution 'T1' $interruptedId
    Assert-That 'interruzione: lo stesso RunId non puo essere riusato e la run parziale non viene toccata' ($again.outcome -eq 'invalid-input' -and $null -eq $again.summaryPath -and (Get-FileHash (Join-Path $partial 'input\submission-manifest.json')).Hash -eq $partialHash -and -not (Test-Path (Join-Path $partial 'evidence')))
    $retry = & $evaluate $solution 'T1' 'run-ripetuta'
    Assert-That 'interruzione: la stessa submission si valuta senza problemi con un nuovo RunId' ($retry.outcome -eq 'passed')

    Assert-That 'le dipendenze canoniche reali sono ancora presenti' (Test-Path (Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'))
    Assert-That 'le run non scrivono cache di Vitest (.vite, .vitest-cache, .vitest) nelle dipendenze canoniche' ((Get-ToolsCacheFingerprint) -eq $cacheBefore)
}
finally {
    Remove-TestWorkspace -Path $workspace
}

Write-Output "Totale: $script:total, falliti: $script:failures"
if ($script:failures -gt 0) { exit 1 }
exit 0
