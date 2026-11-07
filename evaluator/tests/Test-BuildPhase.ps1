<#
.SYNOPSIS
Test automatici di ProcessRunner e della fase di build.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche con TypeScript reale e Node nel PATH, per i test non simulati.

.NOTES
Exit code: 0 tutti i test superati; 1 almeno un test fallito.
Tutto avviene in una directory temporanea creata e rimossa dal test.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolsNodeModulesPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\BuildPhase.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EvaluationInput.psm1') -Force
# Per ultimo: BuildPhase reimporta ProcessRunner con -Force e ne sostituirebbe il caricamento.
Import-Module (Join-Path $PSScriptRoot '..\ProcessRunner.psm1') -Force
$buildScript = Join-Path $PSScriptRoot '..\Invoke-BuildPhase.ps1'

$script:failures = 0
$script:total = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:total++
    if ($Condition) { Write-Output "PASS  $Name" } else { $script:failures++; Write-Output "FAIL  $Name $Detail" }
}

function Read-Text { param([string]$Path) if (Test-Path -LiteralPath $Path) { return [System.IO.File]::ReadAllText($Path) } return '' }

function New-FakeTools {
    param([string]$Path, [string]$Body, [int]$DelayPings = 0)
    New-Item -ItemType Directory -Force -Path "$Path\.bin" | Out-Null
    Set-Content "$Path\delay.txt" $DelayPings -Encoding ascii
    Set-Content "$Path\.bin\tsc.cmd" $Body -Encoding ascii
}

function New-SampleSubmission {
    param([string]$Path, [string]$Source = 'export const total: number = 1 + 2;', [string]$OutDir = 'dist')
    New-Item -ItemType Directory -Force -Path "$Path\src" | Out-Null
    Set-Content "$Path\package.json" '{"name":"sample","version":"1.0.0","type":"module"}' -Encoding ascii
    Set-Content "$Path\package-lock.json" '{"lockfileVersion":3}' -Encoding ascii
    Set-Content "$Path\tsconfig.json" ('{"compilerOptions":{"target":"ES2022","module":"NodeNext","moduleResolution":"NodeNext","strict":true,"rootDir":"src","outDir":"' + $OutDir + '"},"include":["src"]}') -Encoding ascii
    Set-Content "$Path\src\index.ts" $Source -Encoding ascii
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('build-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
    $scratch = Join-Path $workspace 'scratch'
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $out = Join-Path $scratch 'o.txt'; $err = Join-Path $scratch 'e.txt'

    # --- ProcessRunner ------------------------------------------------------------------
    Set-Content "$scratch\exit7.cmd" "@echo off`r`necho to-stdout`r`necho to-stderr 1>&2`r`nexit /b 7" -Encoding ascii
    $r = Invoke-ControlledProcess -CommandPath "$scratch\exit7.cmd" -WorkingDirectory $scratch -StdoutPath $out -StderrPath $err -TimeoutMilliseconds 20000
    Assert-That 'processo: exit code propagato' ($r.exitCode -eq 7 -and -not $r.timedOut)
    Assert-That 'processo: stdout e stderr su file separati' ((Read-Text $out) -match 'to-stdout' -and (Read-Text $out) -notmatch 'to-stderr' -and (Read-Text $err) -match 'to-stderr')

    Set-Content "$scratch\slow.cmd" "@echo off`r`nping -n 40 127.0.0.1 >nul" -Encoding ascii
    $r = Invoke-ControlledProcess -CommandPath "$scratch\slow.cmd" -WorkingDirectory $scratch -StdoutPath $out -StderrPath $err -TimeoutMilliseconds 1500
    Assert-That 'processo: timeout rilevato e durata contenuta' ($r.timedOut -and $null -eq $r.exitCode -and $r.durationMs -lt 15000)

    $node = (Get-Command node -ErrorAction Stop).Source
    Set-Content "$scratch\spawn.js" "const {spawn}=require('child_process');const c=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});require('fs').writeFileSync(process.argv[2],String(c.pid));setInterval(()=>{},1000);" -Encoding ascii
    $pidFile = Join-Path $scratch 'grandchild.pid'
    $r = Invoke-ControlledProcess -CommandPath $node -Arguments @("$scratch\spawn.js", $pidFile) -WorkingDirectory $scratch -StdoutPath $out -StderrPath $err -TimeoutMilliseconds 3000
    $grandchild = [int](Get-Content $pidFile -Raw)
    $alive = $true
    foreach ($attempt in 1..20) { if (-not (Get-Process -Id $grandchild -ErrorAction SilentlyContinue)) { $alive = $false; break }; Start-Sleep -Milliseconds 250 }
    Assert-That 'processo: timeout termina anche i processi discendenti' ($r.timedOut -and -not $alive)

    $env:EVALUATOR_TEST_SECRET = 'valore-segreto'
    Set-Content "$scratch\env.cmd" "@echo off`r`necho SECRET=[%EVALUATOR_TEST_SECRET%]`r`necho ROOT=[%SystemRoot%]" -Encoding ascii
    $null = Invoke-ControlledProcess -CommandPath "$scratch\env.cmd" -WorkingDirectory $scratch -StdoutPath $out -StderrPath $err -TimeoutMilliseconds 20000
    Remove-Item Env:\EVALUATOR_TEST_SECRET
    Assert-That 'processo: variabili d''ambiente non ammesse rimosse' ((Read-Text $out) -match 'SECRET=\[\]' -and (Read-Text $out) -notmatch 'valore-segreto')
    Assert-That 'processo: variabili ammesse mantenute' ((Read-Text $out) -match 'ROOT=\[[A-Za-z]:')
    $quoteError = try { Invoke-ControlledProcess -CommandPath "$scratch\exit7.cmd" -Arguments @('a"b') -WorkingDirectory $scratch -StdoutPath $out -StderrPath $err -TimeoutMilliseconds 1000; 'none' } catch { $_.Exception.GetType().Name }
    Assert-That 'processo: argomento con doppi apici rifiutato' ($quoteError -eq 'ArgumentException')

    # --- Fase di build con compilatore simulato --------------------------------------------------
    $runsRoot = Join-Path $workspace 'runs'
    $sourceDirectory = Join-Path $workspace 'sample-src'
    New-SampleSubmission -Path $sourceDirectory
    $newRun = { New-EvaluationRun -SubmissionPath $sourceDirectory -TaskId 'T1' -RunsRoot $runsRoot }

    $fakeBody = {
        param($exitCode, $stderrLine)
        "@echo off`r`necho %*>> `"%~dp0..\args.log`"`r`necho fake-out`r`n$stderrLine`r`nset /p N=<`"%~dp0..\delay.txt`"`r`nif %N% GTR 0 ping -n %N% 127.0.0.1 >nul`r`nexit /b $exitCode"
    }

    $fakeOk = Join-Path $workspace 'fake-ok'
    New-FakeTools -Path $fakeOk -Body (& $fakeBody 0 'echo fake-err 1>&2')
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeOk
    $stdoutLog = Read-Text (Join-Path $run.runDirectory 'raw\build.stdout.txt'); $stderrLog = Read-Text (Join-Path $run.runDirectory 'raw\build.stderr.txt')
    $argLog = Read-Text "$fakeOk\args.log"
    Assert-That 'build simulata ok: status passed con due passi' ($result.status -eq 'passed' -and $result.exitCode -eq 0 -and @($result.steps).Count -eq 2)
    Assert-That 'build simulata ok: typecheck con --noEmit e build con --outDir nella copia di lavoro' ($argLog -match '--noEmit' -and $argLog.Replace('/', '\') -match [regex]::Escape("$($run.workSubmissionPath)\dist"))
    Assert-That 'build simulata ok: log con intestazioni, stdout e stderr separati' ($stdoutLog -match '=== typecheck ===' -and $stdoutLog -match '=== build ===' -and $stdoutLog -match 'fake-out' -and $stdoutLog -notmatch 'fake-err' -and $stderrLog -match 'fake-err' -and $stderrLog -notmatch 'fake-out')
    Assert-That 'build simulata ok: nessun file temporaneo residuo in raw' (@(Get-ChildItem (Join-Path $run.runDirectory 'raw') -Filter '*.tmp').Count -eq 0)
    Assert-That 'build simulata ok: node_modules e una junction verso le dipendenze canoniche' ((Get-Item "$($run.workSubmissionPath)\node_modules").Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory
    Assert-That 'pulizia: copia di lavoro rimossa e dipendenze canoniche intatte (non discrimina la protezione esplicita, vedi Remove-EvaluationWorkspace)' (-not (Test-Path (Join-Path $run.runDirectory 'work')) -and (Test-Path "$fakeOk\.bin\tsc.cmd") -and (Test-Path "$fakeOk\delay.txt"))
    Assert-That 'pulizia: archivio della submission non toccato' (Test-Path (Join-Path $run.archivedSubmissionPath 'src\index.ts'))

    $fakeFail = Join-Path $workspace 'fake-fail'
    New-FakeTools -Path $fakeFail -Body (& $fakeBody 2 'echo error TS2322 1>&2')
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeFail
    Assert-That 'tsc exit 2 -> failed, si ferma dopo il typecheck' ($result.status -eq 'failed' -and $result.exitCode -eq 2 -and @($result.steps).Count -eq 1)
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $fakeCrash = Join-Path $workspace 'fake-crash'
    New-FakeTools -Path $fakeCrash -Body (& $fakeBody 9 'echo crash 1>&2')
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeCrash
    Assert-That 'tsc exit 9 -> error (non failed)' ($result.status -eq 'error' -and $result.exitCode -eq 9)
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $fakeSlow = Join-Path $workspace 'fake-slow'
    New-FakeTools -Path $fakeSlow -Body (& $fakeBody 0 'echo slow 1>&2') -DelayPings 40
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeSlow -TimeoutSeconds 2
    Assert-That 'passo lento -> timeout' ($result.status -eq 'timeout' -and $null -eq $result.exitCode -and $result.durationMs -lt 20000)
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $fakeTwoSteps = Join-Path $workspace 'fake-two-steps'
    New-FakeTools -Path $fakeTwoSteps -Body (& $fakeBody 0 'echo s 1>&2') -DelayPings 3
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeTwoSteps -TimeoutSeconds 3
    Assert-That 'il timeout e complessivo: due passi da ~2s con limite 3s' ($result.status -eq 'timeout' -and @($result.steps).Count -eq 2 -and $result.steps[0].exitCode -eq 0)
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath (Join-Path $workspace 'no-tools')
    Assert-That 'compilatore assente -> error e nessuna junction creata' ($result.status -eq 'error' -and -not (Test-Path "$($run.workSubmissionPath)\node_modules"))
    $missingWork = try { Invoke-BuildPhase -RunDirectory (Join-Path $workspace 'nessuna-run') -ToolsNodeModulesPath $fakeOk; 'none' } catch { $_.Exception.GetType().Name }
    Assert-That 'run senza copia di lavoro -> ArgumentException' ($missingWork -eq 'ArgumentException')
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    # --- Fase di build con TypeScript reale -------------------------------------------------------
    $run = & $newRun
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'tsc reale: sorgente corretto -> passed' ($result.status -eq 'passed' -and $result.exitCode -eq 0) "(stato: $($result.status); $($result.diagnostics -join ' '))"
    Assert-That 'tsc reale: la build emette dist nella copia di lavoro' (Test-Path "$($run.workSubmissionPath)\dist\index.js")
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $brokenSource = Join-Path $workspace 'broken-src'
    New-SampleSubmission -Path $brokenSource -Source 'export const total: number = "non e un numero";'
    $run = New-EvaluationRun -SubmissionPath $brokenSource -TaskId 'T1' -RunsRoot $runsRoot
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    $realStdout = Read-Text (Join-Path $run.runDirectory 'raw\build.stdout.txt')
    Assert-That 'tsc reale: errore di tipo -> failed con diagnostica nel log' ($result.status -eq 'failed' -and ($realStdout + (Read-Text (Join-Path $run.runDirectory 'raw\build.stderr.txt'))) -match 'TS2322') "(stato: $($result.status))"
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    $escapeSource = Join-Path $workspace 'escape-src'
    New-SampleSubmission -Path $escapeSource -OutDir '../escape'
    $run = New-EvaluationRun -SubmissionPath $escapeSource -TaskId 'T1' -RunsRoot $runsRoot
    $result = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'tsc reale: outDir esterno nel tsconfig non scrive fuori dalla copia di lavoro' ($result.status -eq 'passed' -and -not (Test-Path (Join-Path $run.runDirectory 'work\escape')) -and (Test-Path "$($run.workSubmissionPath)\dist\index.js"))
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory

    # --- Script di ingresso ----------------------------------------------------------------------------
    $run = & $newRun
    $json = & powershell -NoProfile -File $buildScript -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    $code = $LASTEXITCODE
    Assert-That 'script: build corretta -> exit 0 e JSON passed' ($code -eq 0 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'passed')
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory
    $run = New-EvaluationRun -SubmissionPath $brokenSource -TaskId 'T1' -RunsRoot $runsRoot
    $json = & powershell -NoProfile -File $buildScript -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath
    Assert-That 'script: errore di compilazione -> exit 11' ($LASTEXITCODE -eq 11 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'failed')
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory
    $run = & $newRun
    $json = & powershell -NoProfile -File $buildScript -RunDirectory $run.runDirectory -ToolsNodeModulesPath $fakeSlow -TimeoutSeconds 2
    Assert-That 'script: timeout -> exit 12' ($LASTEXITCODE -eq 12 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'timeout')
    Remove-EvaluationWorkspace -RunDirectory $run.runDirectory
    $json = & powershell -NoProfile -File $buildScript -RunDirectory (Join-Path $workspace 'nessuna-run') -ToolsNodeModulesPath $fakeOk
    Assert-That 'script: run inesistente -> exit 40' ($LASTEXITCODE -eq 40 -and ($json -join "`n" | ConvertFrom-Json).status -eq 'error')
    Assert-That 'le dipendenze canoniche reali sono ancora presenti' (Test-Path (Join-Path $ToolsNodeModulesPath '.bin\tsc.cmd'))
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
