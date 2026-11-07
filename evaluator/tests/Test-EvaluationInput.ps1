<#
.SYNOPSIS
Test automatici della fase di ingresso (validazione, manifest, copie).

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito.
Tutto avviene in una directory temporanea creata e rimossa dal test; il
repository non viene toccato.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\EvaluationInput.psm1') -Force
$entryScript = Join-Path $PSScriptRoot '..\Initialize-EvaluationRun.ps1'

$script:failures = 0
$script:total = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" } else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function Get-ErrorType {
    param([scriptblock]$Action)
    try { & $Action | Out-Null; return 'none' } catch { return $_.Exception.GetType().Name }
}

function New-SampleSubmission {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path "$Path\src", "$Path\tests\public", "$Path\node_modules\pkg", "$Path\dist" | Out-Null
    Set-Content "$Path\package.json" '{"name":"x"}' -Encoding ascii
    Set-Content "$Path\package-lock.json" '{"lockfileVersion":3}' -Encoding ascii
    Set-Content "$Path\tsconfig.json" '{}' -Encoding ascii
    Set-Content "$Path\src\index.ts" 'export const a = 1;' -Encoding ascii
    Set-Content "$Path\tests\public\a.test.ts" 'test("a", () => {});' -Encoding ascii
    Set-Content "$Path\node_modules\pkg\index.js" 'module.exports = 1;' -Encoding ascii
    Set-Content "$Path\dist\out.js" 'x' -Encoding ascii
}

function Get-TreeSnapshot {
    param([string]$Path)
    return (Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
            "$($_.FullName.Substring($Path.Length))|$((Get-FileHash $_.FullName).Hash)"
        }) -join "`n"
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('input-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $source = Join-Path $workspace 'submission-src'
    $runs = Join-Path $workspace 'runs'
    New-SampleSubmission -Path $source
    $before = Get-TreeSnapshot -Path $source

    # --- Esecuzione valida -------------------------------------------------------
    $run = New-EvaluationRun -SubmissionPath $source -TaskId 'T2' -RunsRoot $runs
    $archived = $run.archivedSubmissionPath
    $manifestPath = Join-Path $run.runDirectory 'input\submission-manifest.json'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $metadata = Get-Content (Join-Path $run.runDirectory 'input\metadata.json') -Raw | ConvertFrom-Json

    Assert-That 'run valida: struttura delle directory' ((Test-Path $archived) -and (Test-Path $run.workSubmissionPath) -and (Test-Path $manifestPath))
    Assert-That 'run valida: il runId generato rispetta il formato' ($run.runId -cmatch '^\d{8}T\d{6}Z-T2-[0-9a-f]{8}$')
    Assert-That 'run valida: 5 file inclusi (node_modules e dist esclusi)' ($manifest.fileCount -eq 5 -and $run.fileCount -eq 5)
    Assert-That 'run valida: nessun file di node_modules o dist nelle copie' (-not (Test-Path "$archived\node_modules") -and -not (Test-Path "$archived\dist") -and -not (Test-Path "$($run.workSubmissionPath)\node_modules"))
    $excluded = @{}; foreach ($e in $manifest.excludedTopLevelEntries) { $excluded[$e.name] = $e.presentInSource }
    Assert-That 'run valida: esclusioni registrate nel manifest' ($excluded['node_modules'] -eq $true -and $excluded['dist'] -eq $true)
    Assert-That 'run valida: copia archiviata identica al manifest' (@(Compare-SubmissionToManifest -Root $archived -Manifest $manifest -Scope 'a').Count -eq 0)
    Assert-That 'run valida: copia di lavoro identica al manifest' (@(Compare-SubmissionToManifest -Root $run.workSubmissionPath -Manifest $manifest -Scope 'w').Count -eq 0)
    Assert-That 'run valida: sorgente invariato' ((Get-TreeSnapshot -Path $source) -eq $before)
    Assert-That 'run valida: metadata coerenti' ($metadata.taskId -eq 'T2' -and $metadata.runId -eq $run.runId -and $metadata.executionMode -eq 'local-controlled' -and $metadata.treeSha256 -eq $manifest.treeSha256)
    Assert-That 'run valida: file archiviati in sola lettura' (@(Get-ChildItem $archived -File -Recurse | Where-Object { -not $_.IsReadOnly }).Count -eq 0)
    $writeError = Get-ErrorType { Add-Content -LiteralPath "$archived\src\index.ts" 'x' -ErrorAction Stop }
    Assert-That 'run valida: scrittura sulla copia archiviata rifiutata' ($writeError -ne 'none')

    # --- La copia di lavoro e' indipendente dall'archivio -------------------------
    Add-Content "$($run.workSubmissionPath)\src\index.ts" '// modifica del build'
    Assert-That 'copia di lavoro modificata: archivio ancora conforme' (@(Compare-SubmissionToManifest -Root $archived -Manifest $manifest -Scope 'a').Count -eq 0)
    Assert-That 'copia di lavoro modificata: la differenza e rilevata sulla copia di lavoro' (@(Compare-SubmissionToManifest -Root $run.workSubmissionPath -Manifest $manifest -Scope 'w').Count -gt 0)

    # --- Rilevamento di alterazioni dell'archivio ---------------------------------
    $archivedFile = Get-Item "$archived\src\index.ts"; $archivedFile.IsReadOnly = $false
    Add-Content $archivedFile.FullName '// alterazione'
    Assert-That 'archivio alterato: hash diverso rilevato' (@(Compare-SubmissionToManifest -Root $archived -Manifest $manifest -Scope 'a' | Where-Object { $_ -like '*hash diverso*' }).Count -gt 0)
    Remove-Item "$archived\tsconfig.json" -Force
    Assert-That 'archivio alterato: file mancante rilevato' (@(Compare-SubmissionToManifest -Root $archived -Manifest $manifest -Scope 'a' | Where-Object { $_ -like '*file mancante*' }).Count -gt 0)
    Set-Content "$archived\extra.txt" 'x'
    Assert-That 'archivio alterato: file extra rilevato' (@(Compare-SubmissionToManifest -Root $archived -Manifest $manifest -Scope 'a' | Where-Object { $_ -like '*non dichiarato*' }).Count -gt 0)

    # --- Controllo di integrita dell'ingresso (sorgente, archivio, copia di lavoro) ----------
    $intact = New-EvaluationRun -SubmissionPath $source -TaskId 'T5' -RunsRoot $runs
    $intactManifest = Get-Content (Join-Path $intact.runDirectory 'input\submission-manifest.json') -Raw | ConvertFrom-Json
    $check = { Assert-RunInputIntegrity -SourcePath $source -ArchivedPath $intact.archivedSubmissionPath -WorkPath $intact.workSubmissionPath -Manifest $intactManifest }
    Assert-That 'integrita: tre copie conformi -> nessun errore' ((Get-ErrorType $check) -eq 'none')
    Add-Content "$source\src\index.ts" '// il sorgente cambia durante la copia'
    $sourceError = Get-ErrorType $check
    $sourceMessage = try { & $check } catch { $_.Exception.Message }
    Assert-That 'integrita: sorgente cambiato -> InvalidDataException con scope sorgente' ($sourceError -eq 'InvalidDataException' -and $sourceMessage -like '*sorgente*')
    Set-Content "$source\src\index.ts" 'export const a = 1;' -Encoding ascii
    Assert-That 'integrita: sorgente ripristinato -> di nuovo conforme' ((Get-ErrorType $check) -eq 'none')
    Add-Content "$($intact.workSubmissionPath)\src\index.ts" '// x'
    $workMessage = try { & $check } catch { $_.Exception.Message }
    Assert-That 'integrita: copia di lavoro alterata -> segnalata' ($workMessage -like '*copia di lavoro*')

    # --- Determinismo e sensibilita' ai byte ----------------------------------------
    $second = New-EvaluationRun -SubmissionPath $source -TaskId 'T2' -RunsRoot $runs
    Assert-That 'determinismo: stessa submission, stessa impronta' ($second.treeSha256 -eq $run.treeSha256)
    $crlfSource = Join-Path $workspace 'crlf-src'
    New-SampleSubmission -Path $crlfSource
    [System.IO.File]::WriteAllBytes("$crlfSource\src\index.ts", [System.Text.Encoding]::ASCII.GetBytes("export const a = 1;`r`n"))
    $lfSource = Join-Path $workspace 'lf-src'
    New-SampleSubmission -Path $lfSource
    [System.IO.File]::WriteAllBytes("$lfSource\src\index.ts", [System.Text.Encoding]::ASCII.GetBytes("export const a = 1;`n"))
    Assert-That 'hash a byte esatti: CRLF e LF danno impronte diverse' ((New-SubmissionManifestObject -Root $crlfSource).treeSha256 -ne (New-SubmissionManifestObject -Root $lfSource).treeSha256)

    # --- Input non validi: nessuna directory creata -----------------------------------
    $runsBefore = @(Get-ChildItem $runs).Count
    $cases = [ordered]@{
        'TaskId T7'                    = { New-EvaluationRun -SubmissionPath $source -TaskId 'T7' -RunsRoot $runs }
        'TaskId minuscolo'             = { New-EvaluationRun -SubmissionPath $source -TaskId 't1' -RunsRoot $runs }
        'TaskId vuoto'                 = { New-EvaluationRun -SubmissionPath $source -TaskId '' -RunsRoot $runs }
        'percorso inesistente'         = { New-EvaluationRun -SubmissionPath "$workspace\nope" -TaskId 'T1' -RunsRoot $runs }
        'percorso vuoto'               = { New-EvaluationRun -SubmissionPath '' -TaskId 'T1' -RunsRoot $runs }
        'percorso che e un file'       = { New-EvaluationRun -SubmissionPath "$source\package.json" -TaskId 'T1' -RunsRoot $runs }
        'runId con path traversal'     = { New-EvaluationRun -SubmissionPath $source -TaskId 'T1' -RunsRoot $runs -RunId '..\evil' }
        'runId gia esistente'          = { New-EvaluationRun -SubmissionPath $source -TaskId 'T1' -RunsRoot $runs -RunId $run.runId }
        'RunsRoot dentro la submission' = { New-EvaluationRun -SubmissionPath $source -TaskId 'T1' -RunsRoot "$source\runs" }
        'submission dentro RunsRoot'   = { New-EvaluationRun -SubmissionPath "$runs\$($run.runId)\work\submission" -TaskId 'T1' -RunsRoot $runs }
    }
    foreach ($name in $cases.Keys) {
        Assert-That "invalid-input: $name" ((Get-ErrorType $cases[$name]) -eq 'ArgumentException')
    }
    foreach ($missing in 'package.json', 'package-lock.json', 'tsconfig.json', 'src') {
        $broken = Join-Path $workspace "broken-$missing"
        New-SampleSubmission -Path $broken
        Remove-Item "$broken\$missing" -Recurse -Force
        Assert-That "invalid-input: manca $missing" ((Get-ErrorType { New-EvaluationRun -SubmissionPath $broken -TaskId 'T1' -RunsRoot $runs }) -eq 'ArgumentException')
    }

    # --- Collegamenti ---------------------------------------------------------------------
    $outside = Join-Path $workspace 'outside'
    New-Item -ItemType Directory -Path $outside | Out-Null
    Set-Content "$outside\secret.txt" 'esterno'
    $linked = Join-Path $workspace 'linked-src'
    New-SampleSubmission -Path $linked
    New-Item -ItemType Junction -Path "$linked\src\collegamento" -Target $outside | Out-Null
    Assert-That 'invalid-input: junction dentro la submission' ((Get-ErrorType { New-EvaluationRun -SubmissionPath $linked -TaskId 'T1' -RunsRoot $runs }) -eq 'ArgumentException')
    Assert-That 'il file esterno non e stato copiato ne modificato' ((Get-Content "$outside\secret.txt") -eq 'esterno' -and @(Get-ChildItem $runs -Recurse -Filter secret.txt).Count -eq 0)
    $linkedExcluded = Join-Path $workspace 'linked-excluded-src'
    New-SampleSubmission -Path $linkedExcluded
    Remove-Item "$linkedExcluded\node_modules" -Recurse -Force
    New-Item -ItemType Junction -Path "$linkedExcluded\node_modules" -Target $outside | Out-Null
    $okRun = New-EvaluationRun -SubmissionPath $linkedExcluded -TaskId 'T1' -RunsRoot $runs
    Assert-That 'node_modules collegamento: escluso senza essere seguito' ($okRun.fileCount -eq 5 -and @(Get-ChildItem $okRun.runDirectory -Recurse -Filter secret.txt).Count -eq 0)
    $linkedRunsBefore = @(Get-ChildItem $runs).Count
    Assert-That 'invalid-input: nessuna directory creata dai rifiuti' (($linkedRunsBefore - $runsBefore) -eq 1)  # solo $okRun e $second sono ammessi

    # --- Script di ingresso ------------------------------------------------------------------
    $ready = & powershell -NoProfile -File $entryScript -SubmissionPath $source -TaskId 'T3' -RunsRoot $runs
    $readyCode = $LASTEXITCODE
    $readyObject = $ready -join "`n" | ConvertFrom-Json
    Assert-That 'script: input valido -> exit 0 e status ready' ($readyCode -eq 0 -and $readyObject.status -eq 'ready' -and (Test-Path $readyObject.workSubmissionPath))
    $invalid = & powershell -NoProfile -File $entryScript -SubmissionPath $source -TaskId 'X' -RunsRoot $runs
    $invalidCode = $LASTEXITCODE
    $invalidObject = $invalid -join "`n" | ConvertFrom-Json
    Assert-That 'script: input non valido -> exit 20 e status invalid-input' ($invalidCode -eq 20 -and $invalidObject.status -eq 'invalid-input' -and @($invalidObject.diagnostics).Count -eq 1)
    $unwritable = Join-Path $workspace 'file-as-runs-root'
    Set-Content $unwritable 'x'
    $failed = & powershell -NoProfile -File $entryScript -SubmissionPath $source -TaskId 'T4' -RunsRoot "$unwritable\sub"
    $failedCode = $LASTEXITCODE
    Assert-That 'script: errore di ambiente -> exit 40 evaluator-error' ($failedCode -eq 40 -and ($failed -join "`n" | ConvertFrom-Json).status -eq 'evaluator-error')
    Assert-That 'script: il sorgente resta invariato dopo tutti i casi' ((Get-TreeSnapshot -Path $source) -eq $before)
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
