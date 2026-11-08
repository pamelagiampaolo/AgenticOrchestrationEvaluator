<#
.SYNOPSIS
Test automatici dell'orchestratore Invoke-Evaluation (esecuzioni complete end-to-end).

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con TypeScript e Vitest reali.

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
Import-Module (Join-Path $PSScriptRoot '..\Evaluation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EvaluationSummary.psm1') -Force
$entryScript = Join-Path $PSScriptRoot '..\Invoke-Evaluation.ps1'
$schemaPath = Join-Path $repositoryRoot 'schemas\evaluation-summary.schema.json'

$script:failures = 0
$script:total = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" } else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function Get-TreeSnapshot {
    param([string]$Path)
    return (Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Sort-Object FullName | ForEach-Object { "$($_.FullName.Substring($Path.Length))|$((Get-FileHash $_.FullName).Hash)" }) -join "`n"
}

function Read-Summary { param([string]$Path) return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Test-SummaryFile {
    param([string]$Path)
    return @(Test-EvaluationSummary -Summary (Read-Summary -Path $Path) -SchemaPath $schemaPath)
}

# Baseline senza dipendenze; facoltativamente con T1 implementato (anche in modo errato) o rotta.
function New-Submission {
    param([string]$Path, [switch]$ImplementT1, [switch]$Violating, [switch]$Broken)
    New-Item -ItemType Directory -Force -Path "$Path\src" | Out-Null
    foreach ($name in 'package.json', 'package-lock.json', 'tsconfig.json') { Copy-Item (Join-Path $BaselinePath $name) "$Path\$name" }
    $source = [System.IO.File]::ReadAllText((Join-Path $BaselinePath 'src\index.ts'))
    if ($ImplementT1) {
        $comparison = if ($Violating) { '<=' } else { '<' }
        $method = @"

  public findProductsBelowStock(threshold: number): InitialProduct[] {
    if (!Number.isInteger(threshold) || threshold < 0) {
      throw new InventoryManagementError("INVALID_THRESHOLD", "Threshold must be a non-negative integer.");
    }
    return this.listProducts()
      .map(({ productId, name }) => ({ productId, name, availableQuantity: this.getAvailableQuantity(productId) }))
      .filter(({ availableQuantity }) => availableQuantity $comparison threshold);
  }
}

function compareProductIds
"@
        $source = $source.Replace('| "ORDER_ALREADY_CONFIRMED";', '| "ORDER_ALREADY_CONFIRMED"' + "`n  | `"INVALID_THRESHOLD`";")
        $source = $source.Replace("}`n`nfunction compareProductIds", $method.TrimEnd("`r", "`n"))
        if (-not $source.Contains('findProductsBelowStock')) { throw 'Impossibile costruire la soluzione di prova.' }
    }
    if ($Broken) { $source += "`nexport const = ;`n" }
    [System.IO.File]::WriteAllText("$Path\src\index.ts", $source)
}

$toolchain = Get-Content (Join-Path $repositoryRoot 'manifests\toolchain.manifest.json') -Raw | ConvertFrom-Json

# Strumenti simulati: dichiarano le versioni del manifest degli strumenti (salvo indicazione diversa)
# cosi' il controllo preliminare li accetta e si possono provare le fasi successive.
function New-FakeTools {
    param([string]$Path, [string]$VitestBody = "@echo off`r`nexit /b 1", [string]$TypeScriptVersion = $toolchain.typescript, [string]$VitestVersion = $toolchain.vitest)
    New-Item -ItemType Directory -Force -Path "$Path\.bin" | Out-Null
    Set-Content "$Path\.bin\tsc.cmd" "@echo off`r`nexit /b 0" -Encoding ascii
    Set-Content "$Path\.bin\vitest.cmd" $VitestBody -Encoding ascii
    foreach ($package in @(@('typescript', $TypeScriptVersion), @('vitest', $VitestVersion))) {
        if (-not $package[1]) { continue }
        New-Item -ItemType Directory -Force -Path "$Path\$($package[0])" | Out-Null
        Set-Content "$Path\$($package[0])\package.json" "{ `"name`": `"$($package[0])`", `"version`": `"$($package[1])`" }" -Encoding ascii
    }
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('evaluation-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $runs = Join-Path $workspace 'runs'
    $solution = Join-Path $workspace 'solution'; New-Submission -Path $solution -ImplementT1
    $violating = Join-Path $workspace 'violating'; New-Submission -Path $violating -ImplementT1 -Violating
    $unimplemented = Join-Path $workspace 'unimplemented'; New-Submission -Path $unimplemented
    $broken = Join-Path $workspace 'broken'; New-Submission -Path $broken -ImplementT1 -Broken
    $evaluate = { param($Path, $Task = 'T1', $Tools = $ToolsNodeModulesPath, $Baseline = $BaselinePath, $Id = '')
        $arguments = @{ SubmissionPath = $Path; TaskId = $Task; BaselinePath = $Baseline; ToolsNodeModulesPath = $Tools; RunsRoot = $runs }
        if ($Id) { $arguments.RunId = $Id }
        Invoke-Evaluation @arguments }

    # --- Esecuzione conforme --------------------------------------------------------------------------
    $before = Get-TreeSnapshot -Path $solution
    $result = & $evaluate $solution
    $summary = $result.summary
    $runDirectory = Join-Path $runs $summary.runId
    Assert-That 'conforme: outcome passed, exit 0' ($result.outcome -eq 'passed' -and $result.exitCode -eq 0 -and $summary.exitCode -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    Assert-That 'conforme: tutte le fasi passed' (@($summary.phases.build.status, $summary.phases.public.status, $summary.phases.reserved.status) -join ',' -eq 'passed,passed,passed')
    Assert-That 'conforme: conteggi pubblici 31/31 e riservati 3/3, nessuna anomalia' ($summary.publicTests.expected -eq 31 -and $summary.publicTests.passed -eq 31 -and $summary.reservedTests.expected -eq 3 -and $summary.reservedTests.passed -eq 3 -and $summary.publicTests.missing -eq 0 -and $summary.reservedTests.unexpected -eq 0)
    Assert-That 'conforme: integrita tutta true e nessuna diagnostica' ($summary.integrity.originalInputUnchanged -and $summary.integrity.archivedSubmissionUnchanged -and $summary.integrity.suiteManifestsVerified -and @($summary.diagnostics).Count -eq 0)
    $problems = @(Test-SummaryFile -Path $result.summaryPath)
    Assert-That 'conforme: il riepilogo scritto su file e valido per schema e coerenza' ($problems.Count -eq 0 -and (Test-Path (Join-Path $runDirectory 'evidence\report-validation.json'))) "(problemi: $($problems -join ' ; '))"
    Assert-That 'conforme: copia di lavoro rimossa, archivio, manifest e log conservati' (-not (Test-Path (Join-Path $runDirectory 'work')) -and (Test-Path (Join-Path $runDirectory 'input\submission\src\index.ts')) -and (Test-Path (Join-Path $runDirectory 'input\submission-manifest.json')) -and (Test-Path (Join-Path $runDirectory 'raw\build.stdout.txt')) -and (Test-Path (Join-Path $runDirectory 'raw\reserved-report.json')) -and (Test-Path (Join-Path $runDirectory 'raw\public-common-report.json')))
    Assert-That 'conforme: sorgente invariato' ((Get-TreeSnapshot -Path $solution) -eq $before)
    $tsVersion = (Get-Content (Join-Path $ToolsNodeModulesPath 'typescript\package.json') -Raw | ConvertFrom-Json).version
    $lockHash = (Get-FileHash (Join-Path $BaselinePath 'package-lock.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $env1 = $summary.environment
    Assert-That 'conforme: ambiente registrato (TypeScript, Vitest, Node, lock file, versione evaluator)' ($env1.typescript -eq $tsVersion -and $env1.vitest -ne 'unavailable' -and $env1.node -match '^v\d' -and $env1.lockFileSha256 -eq $lockHash -and $env1.evaluatorVersion -match '^([0-9a-f]{40}(-dirty)?|unavailable)$') "(env: $($env1 | ConvertTo-Json -Compress))"
    $summaryText = [System.IO.File]::ReadAllText($result.summaryPath)
    Assert-That 'conforme: il riepilogo non contiene identificatori dei test riservati' ($summaryText -notmatch 'T1-R0' -and $summaryText -notmatch 'reserved/t1')

    # --- Controllo riservato violato ---------------------------------------------------------------------
    $result = & $evaluate $violating
    $summary = $result.summary
    $summaryText = [System.IO.File]::ReadAllText($result.summaryPath)
    $validationText = [System.IO.File]::ReadAllText((Join-Path $runs "$($summary.runId)\evidence\report-validation.json"))
    # Con '<=' fallisce anche il test pubblico T1-P02 (soglia 0 deve restituire []); dei controlli riservati fallisce solo il primo.
    Assert-That 'violante (<=): test-failures, exit 10, pubblica con 1 test fallito e riservata con 1 su 3' ($result.outcome -eq 'test-failures' -and $result.exitCode -eq 10 -and $summary.phases.public.status -eq 'failed' -and $summary.publicTests.failed -eq 1 -and $summary.phases.reserved.status -eq 'failed' -and $summary.reservedTests.failed -eq 1 -and $summary.reservedTests.passed -eq 2) "(esito: $($result.outcome); fasi: $($summary.phases | ConvertTo-Json -Compress))"
    Assert-That 'violante: nessun identificatore riservato nel riepilogo' ($summaryText -notmatch 'T1-R0')
    Assert-That 'violante: riepilogo valido' (@(Test-SummaryFile -Path $result.summaryPath).Count -eq 0)

    # --- Funzione mancante ----------------------------------------------------------------------------------
    $result = & $evaluate $unimplemented
    $summary = $result.summary
    Assert-That 'funzione mancante: test-failures con falliti sia pubblici sia riservati' ($result.outcome -eq 'test-failures' -and $summary.phases.public.status -eq 'failed' -and $summary.phases.reserved.status -eq 'failed' -and $summary.publicTests.failed -eq 4) "(esito: $($result.outcome))"
    Assert-That 'funzione mancante: riepilogo valido' (@(Test-SummaryFile -Path $result.summaryPath).Count -eq 0)

    # --- Non compilabile -----------------------------------------------------------------------------------------
    $result = & $evaluate $broken
    $summary = $result.summary
    Assert-That 'non compilabile: build-failure, exit 11, fasi di test not-run senza conteggi' ($result.outcome -eq 'build-failure' -and $result.exitCode -eq 11 -and $summary.phases.build.status -eq 'failed' -and $summary.phases.public.status -eq 'not-run' -and $summary.phases.reserved.status -eq 'not-run' -and $null -eq $summary.publicTests -and $null -eq $summary.reservedTests)
    Assert-That 'non compilabile: riepilogo valido' (@(Test-SummaryFile -Path $result.summaryPath).Count -eq 0)

    # --- KeepWorkspace -------------------------------------------------------------------------------------------------
    $kept = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot $runs -KeepWorkspace
    Assert-That 'KeepWorkspace: la copia di lavoro resta' ($kept.outcome -eq 'passed' -and (Test-Path (Join-Path $runs "$($kept.summary.runId)\work\submission\src\index.ts")))

    # --- Input non validi ---------------------------------------------------------------------------------------------------
    $result = & $evaluate (Join-Path $workspace 'nessuna-cartella')
    Assert-That 'input inesistente: invalid-input, exit 20, riepilogo scritto e valido' ($result.outcome -eq 'invalid-input' -and $result.exitCode -eq 20 -and $null -ne $result.summaryPath -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(diagnostica: $($result.diagnostics -join ' | '))"
    $result = & $evaluate $solution 'T7'
    $runsBefore = @(Get-ChildItem $runs).Count
    Assert-That 'TaskId non valido: exit 20 senza riepilogo' ($result.outcome -eq 'invalid-input' -and $result.exitCode -eq 20 -and $null -eq $result.summary -and $null -eq $result.summaryPath -and @(Get-ChildItem $runs).Count -eq $runsBefore)
    $submissionSnapshot = Get-TreeSnapshot -Path $solution
    $inside = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot (Join-Path $solution 'runs')
    Assert-That 'RunsRoot dentro la submission: invalid-input e nessun file scritto nella submission' ($inside.outcome -eq 'invalid-input' -and (Get-TreeSnapshot -Path $solution) -eq $submissionSnapshot -and -not (Test-Path (Join-Path $solution 'runs')))
    $first = & $evaluate $solution 'T1' $ToolsNodeModulesPath $BaselinePath 'run-fissa-001'
    $firstHash = (Get-FileHash $first.summaryPath).Hash
    $second = & $evaluate $solution 'T1' $ToolsNodeModulesPath $BaselinePath 'run-fissa-001'
    Assert-That 'RunId esistente: invalid-input, riepilogo originale non sovrascritto' ($first.outcome -eq 'passed' -and $second.outcome -eq 'invalid-input' -and $null -eq $second.summaryPath -and (Get-FileHash $first.summaryPath).Hash -eq $firstHash)
    $badId = & $evaluate $solution 'T1' $ToolsNodeModulesPath $BaselinePath '..\fuori'
    Assert-That 'RunId con path traversal: invalid-input e nulla scritto fuori da RunsRoot' ($badId.outcome -eq 'invalid-input' -and $null -eq $badId.summaryPath -and -not (Test-Path (Join-Path $workspace 'fuori')))

    # --- Baseline alterata: i manifest non coincidono ---------------------------------------------------------------------------
    $tamperedBaseline = Join-Path $workspace 'baseline-alterata'
    New-Item -ItemType Directory -Path $tamperedBaseline | Out-Null
    foreach ($item in 'src', 'tests') { Copy-Item (Join-Path $BaselinePath $item) (Join-Path $tamperedBaseline $item) -Recurse }
    foreach ($item in 'package.json', 'package-lock.json', 'tsconfig.json') { Copy-Item (Join-Path $BaselinePath $item) $tamperedBaseline }
    Copy-Item (Join-Path $BaselinePath 'vitest.public*.ts') $tamperedBaseline
    Add-Content (Join-Path $tamperedBaseline 'tests\public\t1\find-products-below-stock.test.ts') '// alterato'
    $result = & $evaluate $solution 'T1' $ToolsNodeModulesPath $tamperedBaseline
    Assert-That 'baseline alterata: integrity-error, exit 30, nessuna fase eseguita, riepilogo valido' ($result.outcome -eq 'integrity-error' -and $result.exitCode -eq 30 -and $result.summary.phases.build.status -eq 'not-run' -and $result.summary.integrity.suiteManifestsVerified -eq $false -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"

    # --- Strumenti non conformi al manifest degli strumenti ------------------------------------------------------------------------------
    $wrongTs = Join-Path $workspace 'tools-ts-diverso'; New-FakeTools -Path $wrongTs -TypeScriptVersion '6.0.0'
    $runsBefore = @(Get-ChildItem $runs).Count
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $wrongTs -RunsRoot $runs
    $runDirectory = Join-Path $runs $result.summary.runId
    Assert-That 'TypeScript diverso dal manifest: evaluator-error, exit 40, nessuna fase eseguita' ($result.outcome -eq 'evaluator-error' -and $result.exitCode -eq 40 -and (@($result.summary.phases.build.status, $result.summary.phases.public.status, $result.summary.phases.reserved.status) -join ',') -eq 'not-run,not-run,not-run') "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    Assert-That 'TypeScript diverso: diagnostica con versione attesa e trovata, submission non copiata, riepilogo valido' ((($result.diagnostics -join ' ') -match "typescript atteso $([regex]::Escape($toolchain.typescript)), trovato 6\.0\.0") -and -not (Test-Path (Join-Path $runDirectory 'input')) -and @(Get-ChildItem $runs).Count -eq $runsBefore + 1 -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(diagnostica: $($result.diagnostics -join ' | '))"
    $wrongVitest = Join-Path $workspace 'tools-vitest-diverso'; New-FakeTools -Path $wrongVitest -VitestVersion '5.1.1'
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $wrongVitest -RunsRoot $runs
    Assert-That 'Vitest diverso dal manifest: evaluator-error con diagnostica su vitest' ($result.outcome -eq 'evaluator-error' -and $result.summary.phases.build.status -eq 'not-run' -and ($result.diagnostics -join ' ') -match 'vitest atteso') "(diagnostica: $($result.diagnostics -join ' | '))"
    $noVersions = Join-Path $workspace 'tools-senza-versioni'; New-FakeTools -Path $noVersions -TypeScriptVersion '' -VitestVersion ''
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $noVersions -RunsRoot $runs
    Assert-That 'strumenti senza versione leggibile: evaluator-error, versioni registrate come unavailable' ($result.outcome -eq 'evaluator-error' -and $result.summary.phases.build.status -eq 'not-run' -and $result.summary.environment.typescript -eq 'unavailable' -and $result.summary.environment.vitest -eq 'unavailable' -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome))"

    # Confronto diretto: Node non si puo' sostituire nel test, quindi si passa un ambiente sintetico.
    $toolchainPath = Join-Path $repositoryRoot 'manifests\toolchain.manifest.json'
    $goodEnvironment = [ordered]@{ node = $toolchain.node; typescript = $toolchain.typescript; vitest = $toolchain.vitest }
    Assert-That 'strumenti conformi: nessuna non conformita' (@(Test-EvaluationToolchain -Environment $goodEnvironment -ManifestPath $toolchainPath).Count -eq 0)
    $oldNode = [ordered]@{ node = 'v22.11.0'; typescript = $toolchain.typescript; vitest = $toolchain.vitest }
    $issues = @(Test-EvaluationToolchain -Environment $oldNode -ManifestPath $toolchainPath)
    Assert-That 'Node diverso: una sola non conformita, su node' ($issues.Count -eq 1 -and $issues[0] -match 'node atteso .* trovato v22\.11\.0') "(non conformita: $($issues -join ' | '))"
    $unavailableNode = [ordered]@{ node = 'unavailable'; typescript = $toolchain.typescript; vitest = $toolchain.vitest }
    Assert-That 'Node non rilevabile: non conforme' (@(Test-EvaluationToolchain -Environment $unavailableNode -ManifestPath $toolchainPath).Count -eq 1)
    $brokenManifest = Join-Path $workspace 'toolchain-rotto.json'; Set-Content $brokenManifest '{ non json' -Encoding ascii
    $partialManifest = Join-Path $workspace 'toolchain-parziale.json'; Set-Content $partialManifest '{ "toolchainVersion": "prova", "node": "v24.17.0" }' -Encoding ascii
    Assert-That 'manifest degli strumenti illeggibile, assente o incompleto: non conforme' (@(Test-EvaluationToolchain -Environment $goodEnvironment -ManifestPath $brokenManifest).Count -eq 1 -and @(Test-EvaluationToolchain -Environment $goodEnvironment -ManifestPath (Join-Path $workspace 'assente.json')).Count -eq 1 -and @(Test-EvaluationToolchain -Environment $goodEnvironment -ManifestPath $partialManifest).Count -eq 2)
    Assert-That 'gli strumenti canonici reali corrispondono al manifest degli strumenti' (@(Test-EvaluationToolchain -Environment (Get-EvaluationEnvironment -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -RepositoryRoot $repositoryRoot) -ManifestPath $toolchainPath).Count -eq 0)

    # --- Vitest simulato: timeout, errore, alterazione dei file riservati ---------------------------------------------------------------
    $fakeSleep = Join-Path $workspace 'fake-sleep'; New-FakeTools -Path $fakeSleep -VitestBody "@echo off`r`nping -n 40 127.0.0.1 >nul"
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $fakeSleep -RunsRoot $runs -PublicTimeoutSeconds 2 -ReservedTimeoutSeconds 2
    Assert-That 'timeout: outcome timeout, exit 12, fasi pubblica e riservata in timeout, conteggi nulli' ($result.outcome -eq 'timeout' -and $result.exitCode -eq 12 -and $result.summary.phases.public.status -eq 'timeout' -and $result.summary.phases.reserved.status -eq 'timeout' -and $null -eq $result.summary.publicTests) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    Assert-That 'timeout: riepilogo valido' (@(Test-SummaryFile -Path $result.summaryPath).Count -eq 0)
    $fakeCrash = Join-Path $workspace 'fake-crash'; New-FakeTools -Path $fakeCrash -VitestBody "@echo off`r`nexit /b 1"
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $fakeCrash -RunsRoot $runs
    Assert-That 'vitest senza report: evaluator-error, exit 40, riepilogo valido' ($result.outcome -eq 'evaluator-error' -and $result.exitCode -eq 40 -and $result.summary.phases.public.status -eq 'error' -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    $fakeTamper = Join-Path $workspace 'fake-tamper'; New-FakeTools -Path $fakeTamper -VitestBody "@echo off`r`nif exist reserved\t1-r01.test.ts echo // alterato>> reserved\t1-r01.test.ts`r`nexit /b 1"
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $fakeTamper -RunsRoot $runs
    Assert-That 'file riservato alterato durante la run: integrity-error, exit 30, riepilogo valido' ($result.outcome -eq 'integrity-error' -and $result.exitCode -eq 30 -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    Assert-That 'file riservato alterato: la diagnostica non espone nomi di test riservati' (([string]($result.diagnostics -join ' ')) -notmatch 'T1-R0')

    # --- Alterazione dell'input durante la valutazione ----------------------------------------------------------------------------------
    $mutableSource = Join-Path $workspace 'solution-mutabile'; New-Submission -Path $mutableSource -ImplementT1
    $fakeSourceWriter = Join-Path $workspace 'fake-source-writer'; New-FakeTools -Path $fakeSourceWriter -VitestBody "@echo off`r`necho // alterato>> `"$mutableSource\src\index.ts`"`r`nexit /b 1"
    $result = Invoke-Evaluation -SubmissionPath $mutableSource -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $fakeSourceWriter -RunsRoot $runs
    Assert-That 'sorgente modificato durante la run: integrity-error, originalInputUnchanged false' ($result.outcome -eq 'integrity-error' -and $result.exitCode -eq 30 -and $result.summary.integrity.originalInputUnchanged -eq $false -and $result.summary.integrity.archivedSubmissionUnchanged -eq $true -and @(Test-SummaryFile -Path $result.summaryPath).Count -eq 0) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"
    $archiveId = 'run-archivio-alterato'
    $archivedFile = Join-Path $runs "$archiveId\input\submission\src\index.ts"
    $fakeArchiveWriter = Join-Path $workspace 'fake-archive-writer'; New-FakeTools -Path $fakeArchiveWriter -VitestBody "@echo off`r`nattrib -r `"$archivedFile`"`r`necho // alterato>> `"$archivedFile`"`r`nexit /b 1"
    $result = Invoke-Evaluation -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $fakeArchiveWriter -RunsRoot $runs -RunId $archiveId
    Assert-That 'archivio modificato durante la run: integrity-error, archivedSubmissionUnchanged false' ($result.outcome -eq 'integrity-error' -and $result.exitCode -eq 30 -and $result.summary.integrity.archivedSubmissionUnchanged -eq $false -and $result.summary.integrity.originalInputUnchanged -eq $true) "(esito: $($result.outcome); $($result.diagnostics -join ' | '))"

    # --- Script di ingresso -----------------------------------------------------------------------------------------------------------------------
    $json = & powershell -NoProfile -File $entryScript -SubmissionPath $solution -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot $runs
    $code = $LASTEXITCODE
    $parsed = $json -join "`n" | ConvertFrom-Json
    Assert-That 'script: valutazione conforme -> exit 0 e riepilogo JSON su stdout' ($code -eq 0 -and $parsed.outcome -eq 'passed' -and $parsed.exitCode -eq 0)
    $json = & powershell -NoProfile -File $entryScript -SubmissionPath $violating -TaskId 'T1' -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot $runs
    Assert-That 'script: controllo violato -> exit 10' ($LASTEXITCODE -eq 10)
    $json = & powershell -NoProfile -File $entryScript -SubmissionPath $solution -TaskId 'X' -BaselinePath $BaselinePath -ToolsNodeModulesPath $ToolsNodeModulesPath -RunsRoot $runs
    Assert-That 'script: TaskId non valido -> exit 20 con diagnostica' ($LASTEXITCODE -eq 20 -and ($json -join "`n" | ConvertFrom-Json).outcome -eq 'invalid-input')
    Assert-That 'le dipendenze canoniche reali sono ancora presenti' (Test-Path (Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'))
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
