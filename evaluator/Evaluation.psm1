Set-StrictMode -Version Latest

# Ordine di importazione volutamente fissato: ogni modulo importa i propri con -Force e un
# nuovo caricamento rimuove l'istanza precedente dallo scope di chi l'aveva importata. I moduli
# foglia (ManifestCommon, ProcessRunner, EvaluationSummary) vanno quindi importati per ultimi,
# e ReportValidation prima di TestPhases (che importa).
Import-Module (Join-Path $PSScriptRoot 'PublicManifest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ReservedManifest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationInput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BuildPhase.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ReportValidation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TestPhases.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ManifestCommon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProcessRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EvaluationSummary.psm1') -Force

<#
.SYNOPSIS
Orchestrazione di una valutazione completa e produzione del riepilogo.

.DESCRIPTION
Concatena ingresso, build, suite pubblica, suite riservata e validazione dei report,
verifica l'integrita' di input e manifest, applica la precedenza degli esiti del contratto e
scrive `runs/<runId>/evidence/evaluation-summary.json` validato con lo schema.
#>

$script:RunIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

function Get-UtcTimestamp {
    param([datetime]$Value = [datetime]::UtcNow)
    return $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [cultureinfo]::InvariantCulture)
}

function Get-PackageVersion {
    param([string]$PackageJsonPath)
    try {
        if (-not (Test-Path -LiteralPath $PackageJsonPath -PathType Leaf)) { return 'unavailable' }
        $version = (Get-Content -LiteralPath $PackageJsonPath -Raw | ConvertFrom-Json).version
        if ($version) { return [string]$version }
    }
    catch { }
    return 'unavailable'
}

function Get-ToolOutput {
    param([string]$Name, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return 'unavailable' }
        $output = (& $Name @Arguments 2>$null) | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -and $output) { return ([string]$output).Trim() }
    }
    catch { }
    finally { $ErrorActionPreference = $previousPreference }
    return 'unavailable'
}

<#
.SYNOPSIS
Raccoglie le informazioni sull'ambiente richieste dal contratto.

.OUTPUTS
Tabella ordinata con windows, architecture, node, npm, typescript, vitest, lockFileSha256,
evaluatorVersion. Un valore non acquisibile e' la stringa `unavailable`, mai un valore inventato.
#>
function Get-EvaluationEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $windows = 'unavailable'
    try { $windows = [System.Environment]::OSVersion.VersionString } catch { }
    $architecture = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'unavailable' }

    $lockHash = 'unavailable'
    $lockPath = Join-Path $BaselinePath 'package-lock.json'
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) { $lockHash = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant() }

    $evaluatorVersion = Get-ToolOutput -Name 'git' -Arguments @('-C', $RepositoryRoot, 'rev-parse', 'HEAD')
    if ($evaluatorVersion -ne 'unavailable') {
        $dirty = Get-ToolOutput -Name 'git' -Arguments @('-C', $RepositoryRoot, 'status', '--porcelain', '--', 'evaluator', 'manifests', 'reserved', 'schemas')
        if ($dirty -ne 'unavailable') { $evaluatorVersion += '-dirty' }
    }

    return [ordered]@{
        windows          = $windows
        architecture     = $architecture
        node             = Get-ToolOutput -Name 'node' -Arguments @('--version')
        npm              = Get-ToolOutput -Name 'npm' -Arguments @('--version')
        typescript       = Get-PackageVersion -PackageJsonPath (Join-Path $ToolsNodeModulesPath 'typescript\package.json')
        vitest           = Get-PackageVersion -PackageJsonPath (Join-Path $ToolsNodeModulesPath 'vitest\package.json')
        lockFileSha256   = $lockHash
        evaluatorVersion = $evaluatorVersion
    }
}

<#
.SYNOPSIS
Confronta le versioni rilevate degli strumenti con il manifest degli strumenti.

.PARAMETER Environment
Tabella prodotta da Get-EvaluationEnvironment (chiavi `node`, `typescript`, `vitest`).

.PARAMETER ManifestPath
`manifests/toolchain.manifest.json`.

.OUTPUTS
Messaggi di non conformita' (nessuno se gli strumenti coincidono). Un manifest illeggibile o
incompleto e' anch'esso una non conformita': senza versioni attese la run non e' affidabile.
#>
function Test-EvaluationToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return @('Manifest degli strumenti illeggibile.') }
    if ($null -eq $manifest) { return @('Manifest degli strumenti illeggibile.') }
    $label = 'manifest degli strumenti'
    if ($manifest.PSObject.Properties['toolchainVersion']) { $label = "manifest degli strumenti $($manifest.toolchainVersion)" }

    $issues = @()
    foreach ($tool in 'node', 'typescript', 'vitest') {
        $expected = $null
        if ($manifest.PSObject.Properties[$tool]) { $expected = [string]$manifest.$tool }
        if (-not $expected) { $issues += "Il $label non indica la versione attesa di $tool."; continue }
        $actual = [string]$Environment[$tool]
        if ($actual -cne $expected) { $issues += "Strumento non conforme al ${label}: $tool atteso $expected, trovato $actual." }
    }
    return $issues
}

function New-PhaseSummary {
    param([string]$Status = 'not-run', $DurationMs = $null, $ExitCode = $null)
    return [ordered]@{ status = $Status; durationMs = $DurationMs; exitCode = $ExitCode }
}

function ConvertTo-SummaryCounts {
    param($Counts)
    return [ordered]@{ expected = [int]$Counts.expected; executed = [int]$Counts.executed; passed = [int]$Counts.passed; failed = [int]$Counts.failed; skipped = [int]$Counts.skipped; missing = [int]$Counts.missing; unexpected = [int]$Counts.unexpected }
}

function Limit-DiagnosticText {
    param([string]$Text)
    if ($Text.Length -le 500) { return $Text }
    return $Text.Substring(0, 497) + '...'
}

# Raffina l'esito di una fase di test con la validazione dei report. Restituisce lo stato finale
# della fase, i conteggi (nulli se non disponibili) e se si e' verificata un'anomalia strutturale.
function Resolve-TestPhase {
    param($Phase, $Validation)

    $reportsPresent = @($Phase.steps | Where-Object { $_.reportValid }).Count -gt 0
    if ($Phase.status -eq 'timeout') { return [pscustomobject]@{ status = 'timeout'; counts = $null; evaluatorError = $false; testsFailed = $false } }
    if (-not $reportsPresent -or $null -eq $Validation) {
        return [pscustomobject]@{ status = 'error'; counts = $null; evaluatorError = $true; testsFailed = $false }
    }
    $counts = ConvertTo-SummaryCounts -Counts $Validation.counts
    if ($Validation.outcome -eq 'evaluator-error') { return [pscustomobject]@{ status = 'error'; counts = $counts; evaluatorError = $true; testsFailed = $false } }
    if ($Validation.outcome -eq 'test-failures') { return [pscustomobject]@{ status = 'failed'; counts = $counts; evaluatorError = $false; testsFailed = $true } }
    # Vitest ha dichiarato fallimenti ma la validazione non ne trova: incoerenza.
    if ($Phase.status -ne 'passed') { return [pscustomobject]@{ status = 'error'; counts = $counts; evaluatorError = $true; testsFailed = $false } }
    return [pscustomobject]@{ status = 'passed'; counts = $counts; evaluatorError = $false; testsFailed = $false }
}

<#
.SYNOPSIS
Esegue una valutazione completa.

.PARAMETER SubmissionPath
Copia completa di `BenchmarkTarget` da valutare. Non viene mai modificata.

.PARAMETER TaskId
Uno tra T1..T6.

.PARAMETER BaselinePath
`BenchmarkTarget` approvato (sorgente dei test pubblici).

.PARAMETER ToolsNodeModulesPath
Dipendenze canoniche (TypeScript e Vitest).

.PARAMETER RunsRoot
Default: runs/ del repository.

.PARAMETER KeepWorkspace
Non rimuove la copia di lavoro (diagnostica).

.OUTPUTS
Oggetto con `outcome`, `exitCode`, `summary` (nullo se non producibile), `summaryPath` e
`diagnostics`.

.NOTES
Con un TaskId non valido non esiste riepilogo (lo schema ammette solo T1..T6). Per altri input
non validi il riepilogo e' scritto soltanto se la directory della run non esiste e RunsRoot non
e' dentro la submission, per non sovrascrivere ne' modificare nulla.
#>
function Invoke-Evaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SubmissionPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TaskId,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$ToolsNodeModulesPath,
        [string]$RunsRoot,
        [string]$RunId,
        [int]$BuildTimeoutSeconds = 60,
        [int]$PublicTimeoutSeconds = 120,
        [int]$ReservedTimeoutSeconds = 120,
        [switch]$KeepWorkspace
    )

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    if (-not $RunsRoot) { $RunsRoot = Join-Path $repositoryRoot 'runs' }
    $publicManifestPath = Join-Path $repositoryRoot 'manifests\public-suite.manifest.json'
    $reservedManifestPath = Join-Path $repositoryRoot 'manifests\reserved-suite.manifest.json'
    $schemaPath = Join-Path $repositoryRoot 'schemas\evaluation-summary.schema.json'
    $toolchainManifestPath = Join-Path $repositoryRoot 'manifests\toolchain.manifest.json'

    if (-not (Test-TaskId -TaskId $TaskId)) {
        return [pscustomobject]@{ outcome = 'invalid-input'; exitCode = (Get-EvaluationExitCode -Outcome 'invalid-input'); summary = $null; summaryPath = $null; diagnostics = @('TaskId non valido: atteso uno tra T1, T2, T3, T4, T5, T6. Nessun riepilogo prodotto.') }
    }

    $startedAt = [datetime]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $diagnostics = New-Object System.Collections.Generic.List[string]
    $runIdProvided = [bool]$RunId
    if (-not $RunId) { $RunId = New-RunId -TaskId $TaskId }
    $runIdUsable = $RunId -cmatch $script:RunIdPattern
    $runDirectory = if ($runIdUsable) { Join-Path ([System.IO.Path]::GetFullPath($RunsRoot)) $RunId } else { $null }
    $runExistedBefore = $runIdUsable -and (Test-Path -LiteralPath $runDirectory)

    # Stato raccolto durante la valutazione.
    $inputInvalid = $false; $integrityViolated = $false; $evaluatorError = $false; $timedOut = $false; $buildFailed = $false; $testsFailed = $false
    $phases = [ordered]@{ build = New-PhaseSummary; public = New-PhaseSummary; reserved = New-PhaseSummary }
    $publicCounts = $null; $reservedCounts = $null
    $integrity = [ordered]@{ originalInputUnchanged = $null; archivedSubmissionUnchanged = $null; suiteManifestsVerified = $null }
    $validationEvidence = [ordered]@{ public = $null; reserved = $null }
    $run = $null

    $environment = Get-EvaluationEnvironment -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -RepositoryRoot $repositoryRoot
    # Strumenti diversi da quelli congelati: nessuna fase viene eseguita, perche' un test che non si
    # carica per colpa degli strumenti verrebbe altrimenti attribuito alla submission.
    $toolchainIssues = @(Test-EvaluationToolchain -Environment $environment -ManifestPath $toolchainManifestPath)
    if ($toolchainIssues.Count -gt 0) { $evaluatorError = $true; foreach ($issue in $toolchainIssues) { $diagnostics.Add($issue) } }
    $suites = [ordered]@{ reservedSuiteVersion = 'unavailable'; publicSuiteVersion = 'unavailable'; baselineDeclaredCommit = 'unavailable' }
    try {
        $suites.reservedSuiteVersion = [string](Get-Content -LiteralPath $reservedManifestPath -Raw | ConvertFrom-Json).suiteVersion
        $publicManifestObject = Get-Content -LiteralPath $publicManifestPath -Raw | ConvertFrom-Json
        $suites.publicSuiteVersion = [string]$publicManifestObject.suiteVersion
        $suites.baselineDeclaredCommit = [string]$publicManifestObject.baseline.declaredCommit
    }
    catch { $evaluatorError = $true; $diagnostics.Add('Manifest delle suite illeggibili.') }

    # Verifica degli hash dei manifest prima di eseguire: se le suite canoniche sono cambiate la run non e' affidabile.
    function Test-SuiteManifests {
        $reservedDifferences = @((Compare-ReservedManifest -RepositoryRoot $repositoryRoot -ManifestPath $reservedManifestPath).mismatches)
        $publicDifferences = @((Compare-PublicManifest -BaselinePath $BaselinePath -ManifestPath $publicManifestPath).mismatches)
        return ($reservedDifferences.Count + $publicDifferences.Count) -eq 0
    }

    try {
        $suitesVerifiedBefore = Test-SuiteManifests
        if (-not $suitesVerifiedBefore) { $integrityViolated = $true; $diagnostics.Add('I file delle suite canoniche non coincidono con i manifest.') }
        $integrity.suiteManifestsVerified = $suitesVerifiedBefore
    }
    catch { $evaluatorError = $true; $diagnostics.Add("Verifica dei manifest non riuscita: $($_.Exception.GetType().Name)") }

    # --- Ingresso -----------------------------------------------------------------------------------
    if ($runIdProvided -and -not $runIdUsable) { $inputInvalid = $true; $diagnostics.Add('RunId non valido.') }
    elseif ($runExistedBefore) { $inputInvalid = $true; $diagnostics.Add('Esiste gia'' una run con questo RunId.') }
    elseif (-not $integrityViolated -and -not $evaluatorError) {
        try {
            $run = New-EvaluationRun -SubmissionPath $SubmissionPath -TaskId $TaskId -RunsRoot $RunsRoot -RunId $RunId
        }
        catch [System.ArgumentException] { $inputInvalid = $true; $diagnostics.Add((Limit-DiagnosticText $_.Exception.Message)) }
        catch [System.IO.InvalidDataException] { $integrityViolated = $true; $diagnostics.Add((Limit-DiagnosticText $_.Exception.Message)) }
        catch { $evaluatorError = $true; $diagnostics.Add("Errore del valutatore durante l'ingresso: $($_.Exception.GetType().Name)") }
    }

    $toolsReady = $true
    if ($null -ne $run) {
        # --- Build -----------------------------------------------------------------------------------
        try {
            $build = Invoke-BuildPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -TimeoutSeconds $BuildTimeoutSeconds
            $phases.build = New-PhaseSummary -Status $build.status -DurationMs $build.durationMs -ExitCode $build.exitCode
            foreach ($message in $build.diagnostics) { $diagnostics.Add($message) }
            if ($build.status -eq 'failed') { $buildFailed = $true }
            elseif ($build.status -eq 'timeout') { $timedOut = $true }
            elseif ($build.status -eq 'error') { $evaluatorError = $true }
        }
        catch { $evaluatorError = $true; $phases.build = New-PhaseSummary -Status 'error'; $diagnostics.Add("Errore del valutatore nella fase di build: $($_.Exception.GetType().Name)") }

        if ($phases.build.status -eq 'passed' -and -not $integrityViolated) {
            # --- Suite pubblica ----------------------------------------------------------------------------
            try {
                $publicPhase = Invoke-PublicPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -BaselinePath $BaselinePath -PublicManifestPath $publicManifestPath -TimeoutSeconds $PublicTimeoutSeconds
                $publicValidation = $null
                if (@($publicPhase.steps | Where-Object { $_.reportValid }).Count -gt 0) { $publicValidation = Test-PublicReports -RunDirectory $run.runDirectory -PublicManifestPath $publicManifestPath }
                $resolved = Resolve-TestPhase -Phase $publicPhase -Validation $publicValidation
                $phases.public = New-PhaseSummary -Status $resolved.status -DurationMs $publicPhase.durationMs -ExitCode $publicPhase.exitCode
                $publicCounts = $resolved.counts
                $validationEvidence.public = $publicValidation
                if ($resolved.status -eq 'timeout') { $timedOut = $true }
                if ($resolved.evaluatorError) { $evaluatorError = $true }
                if ($resolved.testsFailed) { $testsFailed = $true }
                if ($resolved.status -ne 'passed') { foreach ($message in $publicPhase.diagnostics) { $diagnostics.Add("Suite pubblica: $message") } }
                if ($resolved.evaluatorError) { $diagnostics.Add('Suite pubblica: validazione dei report non superata (dettagli in evidence/report-validation.json).') }
            }
            catch [System.IO.InvalidDataException] { $integrityViolated = $true; $phases.public = New-PhaseSummary -Status 'error'; $diagnostics.Add('Suite pubblica: file canonico non coincidente con il manifest.') }
            catch { $evaluatorError = $true; $phases.public = New-PhaseSummary -Status 'error'; $diagnostics.Add("Errore del valutatore nella suite pubblica: $($_.Exception.GetType().Name)") }

            # --- Suite riservata -------------------------------------------------------------------------------
            if (-not $integrityViolated) {
                try {
                    $reservedPhase = Invoke-ReservedPhase -RunDirectory $run.runDirectory -ToolsNodeModulesPath $ToolsNodeModulesPath -RepositoryRoot $repositoryRoot -ReservedManifestPath $reservedManifestPath -TimeoutSeconds $ReservedTimeoutSeconds
                    $reservedValidation = $null
                    if (@($reservedPhase.steps | Where-Object { $_.reportValid }).Count -gt 0) { $reservedValidation = Test-ReservedReport -RunDirectory $run.runDirectory -ReservedManifestPath $reservedManifestPath }
                    $resolved = Resolve-TestPhase -Phase $reservedPhase -Validation $reservedValidation
                    $phases.reserved = New-PhaseSummary -Status $resolved.status -DurationMs $reservedPhase.durationMs -ExitCode $reservedPhase.exitCode
                    $reservedCounts = $resolved.counts
                    $validationEvidence.reserved = $reservedValidation
                    if ($resolved.status -eq 'timeout') { $timedOut = $true }
                    if ($resolved.evaluatorError) { $evaluatorError = $true }
                    if ($resolved.testsFailed) { $testsFailed = $true }
                    if (-not $reservedPhase.suiteIntact) { $integrityViolated = $true; $diagnostics.Add('Suite riservata: i file copiati non coincidono piu con il manifest.') }
                    if ($resolved.status -ne 'passed') { foreach ($message in $reservedPhase.diagnostics) { $diagnostics.Add("Suite riservata: $message") } }
                    if ($resolved.evaluatorError) { $diagnostics.Add('Suite riservata: validazione dei report non superata (dettagli in evidence/report-validation.json).') }
                }
                catch [System.IO.InvalidDataException] { $integrityViolated = $true; $phases.reserved = New-PhaseSummary -Status 'error'; $diagnostics.Add('Suite riservata: file non coincidente con il manifest.') }
                catch { $evaluatorError = $true; $phases.reserved = New-PhaseSummary -Status 'error'; $diagnostics.Add("Errore del valutatore nella suite riservata: $($_.Exception.GetType().Name)") }
            }
        }

        # --- Integrita' finale di input, archivio e manifest ---------------------------------------------------
        try {
            $manifestObject = Get-Content -LiteralPath (Join-Path $run.runDirectory 'input\submission-manifest.json') -Raw | ConvertFrom-Json
            $integrity.originalInputUnchanged = (@(Compare-SubmissionToManifest -Root ([System.IO.Path]::GetFullPath($SubmissionPath)) -Manifest $manifestObject -Scope 'sorgente').Count -eq 0)
            $integrity.archivedSubmissionUnchanged = (@(Compare-SubmissionToManifest -Root $run.archivedSubmissionPath -Manifest $manifestObject -Scope 'archivio').Count -eq 0)
            if (-not $integrity.originalInputUnchanged) { $integrityViolated = $true; $diagnostics.Add('L''input originale e'' cambiato durante la valutazione.') }
            if (-not $integrity.archivedSubmissionUnchanged) { $integrityViolated = $true; $diagnostics.Add('La submission archiviata non coincide piu con il manifest.') }
            $suitesVerifiedAfter = Test-SuiteManifests
            if (-not $suitesVerifiedAfter) { $integrityViolated = $true; $diagnostics.Add('I file delle suite canoniche sono cambiati durante la valutazione.') }
            $integrity.suiteManifestsVerified = ($integrity.suiteManifestsVerified -eq $true) -and $suitesVerifiedAfter
        }
        catch { $evaluatorError = $true; $diagnostics.Add("Verifica finale dell'integrita non riuscita: $($_.Exception.GetType().Name)") }
    }

    # --- Esito e riepilogo -----------------------------------------------------------------------------------------
    $outcome = Get-EvaluationOutcome -InputInvalid $inputInvalid -IntegrityViolated $integrityViolated -EvaluatorError $evaluatorError -TimedOut $timedOut -BuildFailed $buildFailed -TestsFailed $testsFailed
    $stopwatch.Stop()
    $summary = [ordered]@{
        schemaVersion = 1
        runId         = $RunId
        taskId        = $TaskId
        outcome       = $outcome
        exitCode      = (Get-EvaluationExitCode -Outcome $outcome)
        startedAtUtc  = (Get-UtcTimestamp -Value $startedAt)
        finishedAtUtc = (Get-UtcTimestamp)
        durationMs    = [int]$stopwatch.ElapsedMilliseconds
        suites        = $suites
        phases        = $phases
        publicTests   = $publicCounts
        reservedTests = $reservedCounts
        integrity     = $integrity
        environment   = $environment
        diagnostics   = @(if ($outcome -ne 'passed') { $diagnostics | ForEach-Object { Limit-DiagnosticText $_ } })
    }

    # Il riepilogo e' validato con lo schema: un riepilogo non valido e' un errore del valutatore.
    $problems = @()
    if ($runIdUsable) { $problems = @(Test-EvaluationSummary -Summary (($summary | ConvertTo-Json -Depth 10) | ConvertFrom-Json) -SchemaPath $schemaPath) }
    if ($problems.Count -gt 0) {
        $summary.outcome = 'evaluator-error'
        $summary.exitCode = Get-EvaluationExitCode -Outcome 'evaluator-error'
        $problemText = 'Riepilogo non valido: ' + (($problems | Select-Object -First 3) -join '; ')
        $summary.diagnostics = @(@($summary.diagnostics) + (Limit-DiagnosticText $problemText))
        $outcome = 'evaluator-error'
    }

    # --- Scrittura delle evidenze ----------------------------------------------------------------------------------------
    $summaryPath = $null
    $targetRun = $null
    if ($null -ne $run) { $targetRun = $run.runDirectory }
    elseif ($runIdUsable -and -not $runExistedBefore) {
        # Ingresso rifiutato: si scrive solo se questo non sporca l'input (RunsRoot dentro la submission).
        $submissionFull = $null
        try { if ($SubmissionPath -and (Test-Path -LiteralPath $SubmissionPath -PathType Container)) { $submissionFull = (Resolve-Path -LiteralPath $SubmissionPath).Path.TrimEnd('\') + '\' } } catch { }
        $runsFull = [System.IO.Path]::GetFullPath($RunsRoot).TrimEnd('\') + '\'
        $insideSubmission = $submissionFull -and $runsFull.StartsWith($submissionFull, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $insideSubmission) { $targetRun = $runDirectory }
    }
    if ($null -ne $targetRun) {
        try {
            $evidenceDirectory = Join-Path $targetRun 'evidence'
            New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
            $encoding = New-Object System.Text.UTF8Encoding($false)
            $summaryPath = Join-Path $evidenceDirectory 'evaluation-summary.json'
            [System.IO.File]::WriteAllText($summaryPath, (($summary | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"), $encoding)
            [System.IO.File]::WriteAllText((Join-Path $evidenceDirectory 'report-validation.json'), (($validationEvidence | ConvertTo-Json -Depth 12).Replace("`r`n", "`n") + "`n"), $encoding)
        }
        catch { $summaryPath = $null; [Console]::Error.WriteLine("evaluator-error: scrittura delle evidenze non riuscita ($($_.Exception.GetType().Name))") }
    }

    # La copia di lavoro e' rimossa solo dopo aver acquisito report ed evidenze.
    if ($null -ne $run -and -not $KeepWorkspace) {
        try { Remove-EvaluationWorkspace -RunDirectory $run.runDirectory }
        catch { [Console]::Error.WriteLine("avviso: copia di lavoro non rimossa ($($_.Exception.GetType().Name))") }
    }

    return [pscustomobject]@{ outcome = $outcome; exitCode = $summary.exitCode; summary = $summary; summaryPath = $summaryPath; diagnostics = @($summary.diagnostics) }
}

Export-ModuleMember -Function Get-EvaluationEnvironment, Test-EvaluationToolchain, Invoke-Evaluation
