Set-StrictMode -Version Latest

<#
.SYNOPSIS
Funzioni condivise dai manifest delle suite riservata e pubblica.
#>

<#
.SYNOPSIS
Calcola lo SHA-256 di un file normalizzando CRLF in LF.

.DESCRIPTION
La normalizzazione rende l'hash indipendente da `core.autocrlf`. Il contenuto
resta altrimenti invariato byte per byte.

.OUTPUTS
Stringa esadecimale minuscola di 64 caratteri.
#>
function Get-NormalizedFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = New-Object System.Collections.Generic.List[byte]
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $isCrLf = $bytes[$index] -eq 13 -and ($index + 1) -lt $bytes.Length -and $bytes[$index + 1] -eq 10
        if (-not $isCrLf) { $normalized.Add($bytes[$index]) }
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($normalized.ToArray())
    }
    finally {
        $sha256.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

<#
.SYNOPSIS
Restituisce percorso relativo (separatore `/`) e hash per i file indicati.

.PARAMETER Root
Directory rispetto a cui calcolare i percorsi relativi.

.PARAMETER Files
Oggetti `FileInfo` da includere.

.PARAMETER RawBytes
Calcola l'hash sui byte esatti, senza normalizzare i fine riga. Serve quando
si verifica l'integrita' di una copia; i manifest delle suite usano invece
l'hash normalizzato.

.OUTPUTS
Oggetti con `path` e `sha256`, ordinati per percorso (ordinamento ordinale).
#>
function Get-FileEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.IO.FileInfo[]]$Files,
        [switch]$RawBytes
    )

    $rootPrefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    $entries = foreach ($file in $Files) {
        if ($RawBytes) { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        else { $hash = Get-NormalizedFileSha256 -Path $file.FullName }
        [pscustomobject][ordered]@{
            path   = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            sha256 = $hash
        }
    }
    return @($entries | Sort-Object -Property @{ Expression = { $_.path }; Ascending = $true } -Culture 'iv' -CaseSensitive)
}

<#
.SYNOPSIS
Confronta due insiemi di voci `path`/`sha256` e restituisce le differenze.

.OUTPUTS
Elenco di stringhe; vuoto se gli insiemi coincidono.
#>
function Compare-FileEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actual
    )

    $expectedByPath = @{}
    foreach ($entry in $Expected) { $expectedByPath[$entry.path] = $entry.sha256 }
    $actualByPath = @{}
    foreach ($entry in $Actual) { $actualByPath[$entry.path] = $entry.sha256 }

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($path in ($expectedByPath.Keys | Sort-Object)) {
        if (-not $actualByPath.ContainsKey($path)) { $mismatches.Add("${Scope}: file mancante: $path") }
        elseif ($actualByPath[$path] -ne $expectedByPath[$path]) { $mismatches.Add("${Scope}: hash diverso: $path") }
    }
    foreach ($path in ($actualByPath.Keys | Sort-Object)) {
        if (-not $expectedByPath.ContainsKey($path)) { $mismatches.Add("${Scope}: file non dichiarato: $path") }
    }
    return @($mismatches)
}

<#
.SYNOPSIS
Crea una directory temporanea con `node_modules` collegato tramite junction.

.PARAMETER ToolsNodeModulesPath
Directory `node_modules` che contiene Vitest. Non viene modificata.

.OUTPUTS
Percorso della directory temporanea creata.
#>
function New-ToolsWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ToolsNodeModulesPath)

    if (-not (Test-Path -LiteralPath (Join-Path $ToolsNodeModulesPath '.bin\vitest.cmd'))) {
        throw 'Vitest non trovato nel percorso strumenti indicato.'
    }
    $workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('manifest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $workspace 'node_modules') -Target (Resolve-Path -LiteralPath $ToolsNodeModulesPath).Path | Out-Null
    return $workspace
}

<#
.SYNOPSIS
Rimuove una directory creata da New-ToolsWorkspace senza toccare gli strumenti.

.DESCRIPTION
La junction viene eliminata da sola: una rimozione ricorsiva potrebbe entrare
nella directory degli strumenti collegata.
#>
function Remove-ToolsWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)

    $junction = Join-Path $Workspace 'node_modules'
    if (Test-Path -LiteralPath $junction) { [System.IO.Directory]::Delete($junction) }
    Remove-Item -LiteralPath $Workspace -Recurse -Force
}

<#
.SYNOPSIS
Esegue Vitest nella directory indicata e restituisce codice di uscita e stdout.

.PARAMETER Arguments
Argomenti passati a Vitest (per esempio `list`, `--json`, `--config`, ...).

.PARAMETER EnvironmentVariables
Variabili d'ambiente da impostare soltanto per la durata della chiamata.

.OUTPUTS
Oggetto con `exitCode` e `stdout` (array di righe).

.NOTES
In Windows PowerShell 5.1 l'output su stderr di un eseguibile nativo diventa un
errore terminante con ErrorActionPreference=Stop. L'avviso di Vite sulle config
ESM e' non bloccante: l'esito e' stabilito dal chiamante tramite codice di
uscita e validita' dei dati prodotti, mai dal testo su stderr.
#>
function Invoke-Vitest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$EnvironmentVariables = @{}
    )

    $vitestCommand = Join-Path $Workspace 'node_modules\.bin\vitest.cmd'
    $variables = @{ VITE_CONFIG_NATIVE_IGNORE_WARNING = 'true' }
    foreach ($key in $EnvironmentVariables.Keys) { $variables[$key] = $EnvironmentVariables[$key] }

    $previous = @{}
    foreach ($key in $variables.Keys) { $previous[$key] = [System.Environment]::GetEnvironmentVariable($key) }
    $previousPreference = $ErrorActionPreference
    Push-Location $Workspace
    try {
        $ErrorActionPreference = 'Continue'
        foreach ($key in $variables.Keys) { [System.Environment]::SetEnvironmentVariable($key, $variables[$key]) }
        # Nessuna cache: altrimenti Vitest scrive nelle dipendenze canoniche (node_modules/.vite e
        # .vitest-cache) risultati e moduli trasformati, compresi quelli dei test riservati.
        $stdout = & $vitestCommand @Arguments '--cache=false' '--fsModuleCache=false' 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
        foreach ($key in $previous.Keys) { [System.Environment]::SetEnvironmentVariable($key, $previous[$key]) }
        Pop-Location
    }
    return [pscustomobject]@{ exitCode = $exitCode; stdout = @($stdout) }
}

Export-ModuleMember -Function Get-NormalizedFileSha256, Get-FileEntries, Compare-FileEntries, New-ToolsWorkspace, Remove-ToolsWorkspace, Invoke-Vitest
