Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProcessRunner.psm1') -Force

<#
.SYNOPSIS
Fase di typecheck e build di una run preparata da New-EvaluationRun.

.DESCRIPTION
Esegue, nella copia di lavoro, i comandi canonici `tsc --noEmit` e `tsc` usando
il compilatore delle dipendenze del valutatore (collegate con una junction), non
gli `scripts` del `package.json` della submission. Il timeout e' complessivo per
le due fasi.
#>

# Codici di uscita di tsc che indicano errori di compilazione della submission
# (diagnostiche presenti). Qualunque altro codice non nullo e' un problema dello strumento.
$script:CompilerDiagnosticsExitCodes = @(1, 2)

<#
.SYNOPSIS
Rimuove la copia di lavoro di una run senza toccare le dipendenze collegate.

.DESCRIPTION
Precauzione: la junction `node_modules` viene eliminata da sola, prima del resto,
cosi' l'esito non dipende dal modo in cui la versione di PowerShell/Windows in uso
tratta le junction durante una rimozione ricorsiva. Nell'ambiente di verifica
(Windows PowerShell 5.1.26100) la rimozione ricorsiva non le attraversa: la
protezione esplicita non e' quindi dimostrata necessaria qui ne' discriminata dai test.
#>
function Remove-EvaluationWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunDirectory)

    $workDirectory = Join-Path $RunDirectory 'work'
    if (-not (Test-Path -LiteralPath $workDirectory)) { return }
    foreach ($junction in Get-ChildItem -LiteralPath $workDirectory -Directory -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }) {
        [System.IO.Directory]::Delete($junction.FullName)
    }
    Remove-Item -LiteralPath $workDirectory -Recurse -Force
}

function Write-StepLog {
    param([string]$Path, [string]$Header, [string]$StepFile)
    $body = ''
    if (Test-Path -LiteralPath $StepFile) { $body = [System.IO.File]::ReadAllText($StepFile) }
    [System.IO.File]::AppendAllText($Path, "=== $Header ===`n$body`n", (New-Object System.Text.UTF8Encoding($false)))
}

<#
.SYNOPSIS
Esegue typecheck e build nella copia di lavoro di una run.

.PARAMETER RunDirectory
Directory `runs/<runId>` creata da New-EvaluationRun.

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche (contengono `.bin\tsc.cmd`). Non vengono modificate.

.PARAMETER TimeoutSeconds
Limite complessivo per typecheck e build (default 60, dal contratto).

.OUTPUTS
Oggetto con `status` (`passed`, `failed`, `timeout`, `error`), `exitCode` e
`durationMs` dell'ultimo passo eseguito, `steps` e `diagnostics`.

.NOTES
`raw/build.stdout.txt` e `raw/build.stderr.txt` contengono l'output dei passi, ciascuno
preceduto da una riga `=== nome ===` aggiunta dal valutatore. Problemi dello strumento
(compilatore assente, codici di uscita imprevisti) producono `error`, non `failed`.
Genera `System.ArgumentException` se la run non ha una copia di lavoro.
#>
function Invoke-BuildPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [int]$TimeoutSeconds = 60
    )

    $workPath = Join-Path (Join-Path $RunDirectory 'work') 'submission'
    if (-not (Test-Path -LiteralPath $workPath -PathType Container)) { throw [System.ArgumentException]::new('La run non ha una copia di lavoro.') }
    $rawDirectory = Join-Path $RunDirectory 'raw'
    New-Item -ItemType Directory -Force -Path $rawDirectory | Out-Null
    $stdoutLog = Join-Path $rawDirectory 'build.stdout.txt'
    $stderrLog = Join-Path $rawDirectory 'build.stderr.txt'
    foreach ($log in $stdoutLog, $stderrLog) { [System.IO.File]::WriteAllText($log, '', (New-Object System.Text.UTF8Encoding($false))) }

    $steps = New-Object System.Collections.Generic.List[object]
    $compiler = Join-Path $ToolsNodeModulesPath '.bin\tsc.cmd'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        return [pscustomobject][ordered]@{ status = 'error'; exitCode = $null; durationMs = 0; steps = @(); diagnostics = @('Compilatore TypeScript non trovato nelle dipendenze canoniche.') }
    }
    $junction = Join-Path $workPath 'node_modules'
    if (Test-Path -LiteralPath $junction) {
        return [pscustomobject][ordered]@{ status = 'error'; exitCode = $null; durationMs = 0; steps = @(); diagnostics = @('La copia di lavoro contiene gia'' node_modules.') }
    }
    New-Item -ItemType Junction -Path $junction -Target (Resolve-Path -LiteralPath $ToolsNodeModulesPath).Path | Out-Null

    $definitions = @(
        @{ name = 'typecheck'; arguments = @('--noEmit') },
        @{ name = 'build'; arguments = @('--outDir', (Join-Path $workPath 'dist')) }
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'passed'; $lastExitCode = $null; $lastDuration = 0; $diagnostics = @()
    foreach ($definition in $definitions) {
        $remaining = $TimeoutSeconds * 1000 - [int]$stopwatch.ElapsedMilliseconds
        if ($remaining -le 0) { $status = 'timeout'; $diagnostics += "Timeout complessivo raggiunto prima del passo $($definition.name)."; break }
        $stepOut = Join-Path $rawDirectory ('step-' + $definition.name + '.stdout.tmp')
        $stepErr = Join-Path $rawDirectory ('step-' + $definition.name + '.stderr.tmp')
        try {
            $result = Invoke-ControlledProcess -CommandPath $compiler -Arguments $definition.arguments -WorkingDirectory $workPath `
                -StdoutPath $stepOut -StderrPath $stepErr -TimeoutMilliseconds $remaining
        }
        catch {
            $status = 'error'; $diagnostics += "Impossibile avviare il passo $($definition.name)."; break
        }
        Write-StepLog -Path $stdoutLog -Header $definition.name -StepFile $stepOut
        Write-StepLog -Path $stderrLog -Header $definition.name -StepFile $stepErr
        Remove-Item -LiteralPath $stepOut, $stepErr -Force -ErrorAction SilentlyContinue
        $steps.Add([pscustomobject][ordered]@{ name = $definition.name; exitCode = $result.exitCode; timedOut = $result.timedOut; durationMs = $result.durationMs })
        $lastExitCode = $result.exitCode; $lastDuration = $result.durationMs

        if ($result.timedOut) { $status = 'timeout'; $diagnostics += "Timeout nel passo $($definition.name)."; break }
        if ($result.exitCode -eq 0) { continue }
        if ($result.exitCode -in $script:CompilerDiagnosticsExitCodes) { $status = 'failed'; $diagnostics += "Il passo $($definition.name) ha riportato errori di compilazione."; break }
        $status = 'error'; $diagnostics += "Il passo $($definition.name) e' terminato con un codice imprevisto ($($result.exitCode))."; break
    }
    $stopwatch.Stop()
    return [pscustomobject][ordered]@{ status = $status; exitCode = $lastExitCode; durationMs = [int]$stopwatch.ElapsedMilliseconds; steps = $steps.ToArray(); diagnostics = $diagnostics }
}

Export-ModuleMember -Function Remove-EvaluationWorkspace, Invoke-BuildPhase
