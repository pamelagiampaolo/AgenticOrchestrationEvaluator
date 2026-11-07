Set-StrictMode -Version Latest

<#
.SYNOPSIS
Esecuzione di processi con timeout, ambiente ridotto e log su file.
#>

# Variabili d'ambiente passate ai processi figli. Tutte le altre (credenziali,
# token, configurazioni dell'utente) vengono rimosse.
$script:AllowedEnvironmentVariables = @('PATH', 'PATHEXT', 'SystemRoot', 'windir', 'ComSpec', 'SystemDrive', 'TEMP', 'TMP', 'OS', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE')

function ConvertTo-CmdArgument {
    param([string]$Argument)
    if ($Argument.Contains('"')) { throw [System.ArgumentException]::new('Argomento non ammesso: contiene doppi apici.') }
    if ($Argument -match '[\s&|<>^%()]' -or $Argument -eq '') { return '"' + $Argument + '"' }
    return $Argument
}

<#
.SYNOPSIS
Termina un processo e tutti i suoi discendenti.
#>
function Stop-ProcessTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

<#
.SYNOPSIS
Esegue un comando (eseguibile o .cmd) con timeout, scrivendo stdout e stderr su file.

.PARAMETER CommandPath
Percorso dell'eseguibile o dello script `.cmd`.

.PARAMETER Arguments
Argomenti; non possono contenere doppi apici.

.PARAMETER WorkingDirectory
Directory di lavoro del processo.

.PARAMETER StdoutPath
.PARAMETER StderrPath
File di destinazione (creati o sovrascritti, anche se l'output e' vuoto).

.PARAMETER TimeoutMilliseconds
Superato il limite l'intero albero dei processi viene terminato.

.OUTPUTS
Oggetto con `exitCode` (nullo se in timeout), `timedOut` e `durationMs`.

.NOTES
Il processo parte con l'ambiente ridotto a `$script:AllowedEnvironmentVariables`.
Genera un errore se il processo non puo' essere avviato.
#>
function Invoke-ControlledProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath,
        [Parameter(Mandatory)][int]$TimeoutMilliseconds
    )

    $commandLine = '"' + $CommandPath + '"'
    foreach ($argument in $Arguments) { $commandLine += ' ' + (ConvertTo-CmdArgument -Argument $argument) }
    $commandLine += ' 1>"' + $StdoutPath + '" 2>"' + $StderrPath + '"'

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c "' + $commandLine + '"'
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $inherited = @{}
    foreach ($name in $script:AllowedEnvironmentVariables) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ($null -ne $value) { $inherited[$name] = $value }
    }
    $startInfo.EnvironmentVariables.Clear()
    foreach ($name in $inherited.Keys) { $startInfo.EnvironmentVariables[$name] = $inherited[$name] }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $finished = $process.WaitForExit($TimeoutMilliseconds)
        if (-not $finished) {
            Stop-ProcessTree -ProcessId $process.Id
            $null = $process.WaitForExit(10000)
        }
        $stopwatch.Stop()
        $exitCode = $null
        if ($finished) { $exitCode = $process.ExitCode }
        return [pscustomobject][ordered]@{ exitCode = $exitCode; timedOut = (-not $finished); durationMs = [int]$stopwatch.ElapsedMilliseconds }
    }
    finally {
        $process.Dispose()
    }
}

Export-ModuleMember -Function Stop-ProcessTree, Invoke-ControlledProcess
