<#
.SYNOPSIS
Test automatici delle fasi di test pubblica e riservata.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con Vitest reale.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato (solo lettura): sorgente dei test pubblici e base della soluzione di prova.

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
Import-Module (Join-Path $PSScriptRoot '..\TestPhases.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\ManifestCommon.psm1') -Force
$phaseScript = Join-Path $PSScriptRoot '..\Invoke-TestPhase.ps1'
$publicManifest = Join-Path $repositoryRoot 'manifests\public-suite.manifest.json'
$reservedManifest = Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json'

$script:failures = 0
$script:total = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" } else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function Read-Json { param([string]$Path) return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }

function New-FakeVitest {
    param([string]$Path, [string]$Body)
    New-Item -ItemType Directory -Force -Path "$Path\.bin" | Out-Null
    Set-Content "$Path\.bin\vitest.cmd" $Body -Encoding ascii
}

# Copia la baseline senza dipendenze, test e artefatti; facoltativamente implementa T1.
function New-BaselineSubmission {
    param([string]$Path, [switch]$ImplementT1)
    New-Item -ItemType Directory -Force -Path "$Path\src" | Out-Null
    foreach ($name in 'package.json', 'package-lock.json', 'tsconfig.json') { Copy-Item (Join-Path $BaselinePath $name) "$Path\$name" }
    $source = [System.IO.File]::ReadAllText((Join-Path $BaselinePath 'src\index.ts'))
    if ($ImplementT1) {
        $method = @'

  public findProductsBelowStock(threshold: number): InitialProduct[] {
    if (!Number.isInteger(threshold) || threshold < 0) {
      throw new InventoryManagementError("INVALID_THRESHOLD", "Threshold must be a non-negative integer.");
    }
    return this.listProducts()
      .map(({ productId, name }) => ({ productId, name, availableQuantity: this.getAvailableQuantity(productId) }))
      .filter(({ availableQuantity }) => availableQuantity < threshold);
  }
}

function compareProductIds
'@
        $source = $source.Replace('| "ORDER_ALREADY_CONFIRMED";', '| "ORDER_ALREADY_CONFIRMED"' + "`n  | `"INVALID_THRESHOLD`";")
        $source = $source.Replace("}`n`nfunction compareProductIds", $method.TrimEnd("`r", "`n"))
        if (-not $source.Contains('findProductsBelowStock')) { throw 'Impossibile costruire la soluzione di prova.' }
    }
    [System.IO.File]::WriteAllText("$Path\src\index.ts", $source)
}

function New-FixtureSubmission {
    param([string]$Path, [string]$Fixture)
    Copy-Item (Join-Path $repositoryRoot "fixtures\controls\$Fixture") $Path -Recurse
    Set-Content "$Path\package-lock.json" '{"lockfileVersion":3}' -Encoding ascii
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('phases-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $runs = Join-Path $workspace 'runs'
    $solution = Join-Path $workspace 'solution-t1'; New-BaselineSubmission -Path $solution -ImplementT1
    $unimplemented = Join-Path $workspace 'unimplemented'; New-BaselineSubmission -Path $unimplemented
    $compliant = Join-Path $workspace 'fx-compliant'; New-FixtureSubmission -Path $compliant -Fixture 'T1\R01\compliant'
    $violating = Join-Path $workspace 'fx-violating'; New-FixtureSubmission -Path $violating -Fixture 'T1\R01\violating'

    # --- Fase pubblica ------------------------------------------------------------------
    # La submission contiene un test pubblico indebolito e uno aggiuntivo che fallirebbe.
    New-Item -ItemType Directory -Force -Path "$solution\tests\public\t1" | Out-Null
    Set-Content "$solution\tests\public\t1\find-products-below-stock.test.ts" "import { test } from 'vitest'; test('sempre vero', () => {});" -Encoding ascii
    Set-Content "$solution\tests\public\extra.test.ts" "import { test, expect } from 'vitest'; test('extra', () => { expect(1).toBe(2); });" -Encoding ascii
    $run = New-EvaluationRun -SubmissionPath $solution -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifest
    $canonicalT1 = Get-NormalizedFileSha256 -Path (Join-Path $BaselinePath 'tests\public\t1\find-products-below-stock.test.ts')
    Assert-That 'pubblica T1, soluzione reale: passed con i due scope common e T1' ($result.status -eq 'passed' -and $result.exitCode -eq 0 -and @($result.steps).Count -eq 2 -and $result.steps[0].name -eq 'common' -and $result.steps[1].name -eq 'T1') "(stato: $($result.status); $($result.diagnostics -join ' '))"
    Assert-That 'pubblica: i test pubblici della submission sono sostituiti da quelli canonici' ((Get-NormalizedFileSha256 -Path "$($run.workSubmissionPath)\tests\public\t1\find-products-below-stock.test.ts") -eq $canonicalT1 -and -not (Test-Path "$($run.workSubmissionPath)\tests\public\extra.test.ts"))
    $commonReport = Read-Json (Join-Path $run.runDirectory 'raw\public-common-report.json'); $t1Report = Read-Json (Join-Path $run.runDirectory 'raw\public-T1-report.json')
    Assert-That 'pubblica: report grezzi per scope con i conteggi del manifest (27 comuni, 4 di T1)' ($commonReport.numPassedTests -eq 27 -and $t1Report.numPassedTests -eq 4 -and $t1Report.numFailedTests -eq 0)
    $log = [System.IO.File]::ReadAllText((Join-Path $run.runDirectory 'raw\public.stdout.txt'))
    Assert-That 'pubblica: log con intestazioni per scope' ($log -match '=== common ===' -and $log -match '=== T1 ===')
    Assert-That 'pubblica: l''archivio della submission non e stato toccato' (@(Compare-SubmissionToManifest -Root $run.archivedSubmissionPath -Manifest (Read-Json (Join-Path $run.runDirectory 'input\submission-manifest.json')) -Scope 'a').Count -eq 0)

    $run = New-EvaluationRun -SubmissionPath $unimplemented -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifest
    $t1Report = Read-Json (Join-Path $run.runDirectory 'raw\public-T1-report.json')
    Assert-That 'pubblica T1, funzione mancante: failed, entrambi gli scope eseguiti' ($result.status -eq 'failed' -and $result.exitCode -eq 1 -and @($result.steps).Count -eq 2 -and $t1Report.numFailedTests -eq 4)

    $tamperedManifest = Join-Path $workspace 'public-tampered.json'
    $copy = Read-Json $publicManifest
    $target = @($copy.baseline.files | Where-Object { $_.path -like 'tests/public/*' })[0]
    $target.sha256 = ('0' * 64)
    $copy | ConvertTo-Json -Depth 10 | Set-Content $tamperedManifest -Encoding utf8
    $installError = try { $null = Install-CanonicalPublicSuite -RunDirectory $run.runDirectory -BaselinePath $BaselinePath -PublicManifestPath $tamperedManifest; 'none' } catch { $_.Exception.GetType().Name }
    Assert-That 'pubblica: file canonico non coincidente con il manifest -> InvalidDataException' ($installError -eq 'InvalidDataException') "(file: $($target.path); errore: $installError)"

    # --- Fase riservata -------------------------------------------------------------------
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    $reservedReport = Read-Json (Join-Path $run.runDirectory 'raw\reserved-report.json')
    Assert-That 'riservata T1, fixture conforme: passed, file intatti, 3 test' ($result.status -eq 'passed' -and $result.suiteIntact -and $reservedReport.numPassedTests -eq 3 -and $reservedReport.numFailedTests -eq 0) "(stato: $($result.status); $($result.diagnostics -join ' '))"
    $copied = @(Get-ChildItem "$($run.runDirectory)\work\reserved" -File | ForEach-Object Name)
    Assert-That 'riservata: copiati solo i file del task (3 test e la configurazione)' ($copied.Count -eq 4 -and 'vitest.reserved-task.config.ts' -in $copied -and -not ($copied | Where-Object { $_ -like 't2-*' }))
    Assert-That 'riservata: nessun file riservato dentro la copia della submission ne nell''archivio' (-not (Test-Path "$($run.workSubmissionPath)\reserved") -and @(Get-ChildItem $run.archivedSubmissionPath -Recurse -Filter 't1-r*').Count -eq 0)

    $run = New-EvaluationRun -SubmissionPath $violating -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    $reservedReport = Read-Json (Join-Path $run.runDirectory 'raw\reserved-report.json')
    $failedNames = @($reservedReport.testResults | ForEach-Object { $_.assertionResults } | Where-Object { $_.status -eq 'failed' } | ForEach-Object { $_.fullName })
    Assert-That 'riservata T1, fixture violante: failed solo per T1-R01' ($result.status -eq 'failed' -and $result.suiteIntact -and $failedNames.Count -eq 1 -and $failedNames[0] -eq 'T1-R01') "(falliti: $($failedNames -join ', '))"
    $envProbeRun = $run.runDirectory

    # --- Esiti non interpretabili e timeout con Vitest simulato -----------------------------------
    $fakeSleep = Join-Path $workspace 'fake-sleep'; New-FakeVitest -Path $fakeSleep -Body "@echo off`r`nping -n 40 127.0.0.1 >nul"
    $fakeNoReportFail = Join-Path $workspace 'fake-fail'; New-FakeVitest -Path $fakeNoReportFail -Body "@echo off`r`necho crash 1>&2`r`nexit /b 1"
    $fakeNoReportOk = Join-Path $workspace 'fake-ok'; New-FakeVitest -Path $fakeNoReportOk -Body "@echo off`r`nexit /b 0"
    $fakeTamper = Join-Path $workspace 'fake-tamper'; New-FakeVitest -Path $fakeTamper -Body "@echo off`r`necho // alterato>> reserved\t1-r01.test.ts`r`nexit /b 0"

    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeSleep -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest -TimeoutSeconds 2
    Assert-That 'riservata: processo bloccato -> timeout' ($result.status -eq 'timeout' -and $null -eq $result.exitCode -and $result.durationMs -lt 20000)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeNoReportFail -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    Assert-That 'riservata: exit 1 senza report -> error (non failed)' ($result.status -eq 'error' -and -not $result.steps[0].reportValid)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeNoReportOk -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    Assert-That 'riservata: exit 0 senza report -> error (passed richiede un report)' ($result.status -eq 'error')
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeTamper -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifest
    Assert-That 'riservata: file riservato alterato durante l''esecuzione -> suiteIntact falso' (-not $result.suiteIntact -and @($result.integrityDifferences | Where-Object { $_ -like '*hash diverso*t1-r01*' }).Count -eq 1)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $result = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeSleep -BaselinePath $BaselinePath -PublicManifestPath $publicManifest -TimeoutSeconds 2
    Assert-That 'pubblica: processo bloccato -> timeout al primo scope, il secondo non parte' ($result.status -eq 'timeout' -and @($result.steps).Count -eq 1)

    # --- Task con configurazione comune inclusa (T5): un solo scope ------------------------------------
    $run = New-EvaluationRun -SubmissionPath $unimplemented -TaskId 'T5' -RunsRoot $runs
    $result = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifest
    Assert-That 'pubblica T5: un solo scope (la configurazione del task include i test comuni)' (@($result.steps).Count -eq 1 -and $result.steps[0].name -eq 'T5' -and $result.steps[0].reportValid)

    # --- Script di ingresso ---------------------------------------------------------------------------------
    $run = New-EvaluationRun -SubmissionPath $solution -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite public -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath
    Assert-That 'script pubblica: soluzione reale -> exit 0' ($LASTEXITCODE -eq 0 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'passed')
    $run = New-EvaluationRun -SubmissionPath $unimplemented -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite public -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath
    Assert-That 'script pubblica: test falliti -> exit 10' ($LASTEXITCODE -eq 10 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'failed')
    $run = New-EvaluationRun -SubmissionPath $violating -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite reserved -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'script riservata: controllo violato -> exit 10' ($LASTEXITCODE -eq 10 -and ($json -join "`n" | ConvertFrom-Json).suiteIntact -eq $true)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite reserved -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeTamper
    Assert-That 'script riservata: file riservato alterato -> exit 30 (prevale su tutto)' ($LASTEXITCODE -eq 30)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite reserved -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeSleep -TimeoutSeconds 2
    Assert-That 'script riservata: timeout -> exit 12' ($LASTEXITCODE -eq 12)
    $json = & powershell -NoProfile -File $phaseScript -Suite reserved -RunDirectory (Join-Path $workspace 'nessuna-run') -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'script riservata: run inesistente -> exit 40' ($LASTEXITCODE -eq 40)
    $run = New-EvaluationRun -SubmissionPath $compliant -TaskId 'T1' -RunsRoot $runs
    $json = & powershell -NoProfile -File $phaseScript -Suite public -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'script pubblica: senza BaselinePath -> exit 40' ($LASTEXITCODE -eq 40)
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
