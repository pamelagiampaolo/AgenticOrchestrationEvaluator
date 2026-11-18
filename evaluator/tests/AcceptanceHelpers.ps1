# Funzioni condivise dai test di accettazione. Va incluso con dot-sourcing (. .\AcceptanceHelpers.ps1)
# dopo aver definito $BaselinePath, $ToolsNodeModulesPath e $repositoryRoot.

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

# Soluzione di prova per T1: la baseline piu findProductsBelowStock. E' codice di prova, non una soluzione sperimentale.
function New-Submission {
    param([string]$Path, [switch]$ImplementT1, [switch]$Broken, [string]$ExtraSource = '')
    New-Item -ItemType Directory -Force -Path "$Path\src" | Out-Null
    foreach ($name in 'package.json', 'package-lock.json', 'tsconfig.json') {
        Copy-Item (Join-Path $BaselinePath $name) "$Path\$name"
        (Get-Item -LiteralPath "$Path\$name").IsReadOnly = $false
    }
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
    if ($Broken) { $source += "`nexport const = ;`n" }
    if ($ExtraSource) { $source += "`n$ExtraSource`n" }
    [System.IO.File]::WriteAllText("$Path\src\index.ts", $source)
}

# Frammento TypeScript che, al caricamento del modulo, tenta di scrivere nei percorsi indicati.
# Usa process.getBuiltinModule perche' la baseline non ha i tipi di Node (types: []).
function New-WriterSnippet {
    param([string[]]$Targets)
    $list = ($Targets | ForEach-Object { '"' + $_.Replace('\', '/') + '"' }) -join ', '
    return @"
const attackerProcess = (globalThis as any).process;
const attackerFs = attackerProcess.getBuiltinModule("node:fs");
for (const attackTarget of [$list]) {
  try { attackerFs.chmodSync(attackTarget, 0o666); attackerFs.appendFileSync(attackTarget, "\n// alterato dal codice candidato\n"); } catch {}
}
"@
}

# Copia una fixture di controllo come submission. Le fixture non hanno un lock file (l'ingresso lo
# richiede): ne viene aggiunto uno minimo solo nella copia temporanea. Il resto della fixture e' usato
# cosi' com'e', compreso il tsconfig.json (con rootDir esplicito, necessario alla build di TypeScript 7).
function New-FixtureSubmission {
    param([string]$Path, [string]$FixtureRelativePath)
    Copy-Item (Join-Path $repositoryRoot "fixtures\controls\$FixtureRelativePath") $Path -Recurse
    if (-not (Test-Path "$Path\package-lock.json")) { Set-Content "$Path\package-lock.json" '{"lockfileVersion":3}' -Encoding ascii }
}

function Remove-TestWorkspace {
    param([string]$Path)
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue) { if ($file.IsReadOnly) { $file.IsReadOnly = $false } }
    foreach ($junction in Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }) {
        [System.IO.Directory]::Delete($junction.FullName)
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Read-JsonFile { param([string]$Path) return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
