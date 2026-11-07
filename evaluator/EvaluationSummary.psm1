Set-StrictMode -Version Latest

<#
.SYNOPSIS
Esiti, exit code e validazione del riepilogo di una valutazione.

.DESCRIPTION
Il riepilogo e' descritto da `schemas/evaluation-summary.schema.json`. Windows
PowerShell 5.1 non dispone di `Test-Json`, quindi questo modulo include un
validatore per il sottoinsieme di JSON Schema effettivamente usato dallo schema.
Una parola chiave non supportata genera un errore: non viene mai ignorata
silenziosamente. Le regole tra campi diversi sono verificate separatamente da
Test-EvaluationSummary.
#>

# Esito -> exit code. Le decine separano le cause: 1x attribuibili alla submission,
# 2x input, 3x integrita', 4x errore del valutatore.
$script:ExitCodes = [ordered]@{
    'passed'          = 0
    'test-failures'   = 10
    'build-failure'   = 11
    'timeout'         = 12
    'invalid-input'   = 20
    'integrity-error' = 30
    'evaluator-error' = 40
}

$script:AnnotationKeywords = @('$schema', '$id', '$defs', 'title', 'description')
$script:SupportedKeywords = @('type', 'enum', 'const', 'required', 'properties', 'additionalProperties', 'items', 'minimum', 'maximum', 'minLength', 'maxLength', 'pattern', '$ref')

<#
.SYNOPSIS
Restituisce l'exit code associato a un esito.

.NOTES
Genera un errore per un esito sconosciuto.
#>
function Get-EvaluationExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Outcome)

    if (-not $script:ExitCodes.Contains($Outcome)) { throw "Esito sconosciuto: $Outcome" }
    return $script:ExitCodes[$Outcome]
}

<#
.SYNOPSIS
Determina l'esito complessivo da un insieme di fatti osservati.

.DESCRIPTION
Quando piu condizioni sono vere vale la prima, in quest'ordine:
`invalid-input`, `integrity-error`, `evaluator-error`, `timeout`, `build-failure`,
`test-failures`, `passed`. Le cause che invalidano la valutazione (input,
integrita', errore del valutatore) prevalgono su quelle attribuibili alla
submission, cosi' un risultato non affidabile non viene mai presentato come un
fallimento della soluzione.
#>
function Get-EvaluationOutcome {
    [CmdletBinding()]
    param(
        [bool]$InputInvalid,
        [bool]$IntegrityViolated,
        [bool]$EvaluatorError,
        [bool]$TimedOut,
        [bool]$BuildFailed,
        [bool]$TestsFailed
    )

    if ($InputInvalid) { return 'invalid-input' }
    if ($IntegrityViolated) { return 'integrity-error' }
    if ($EvaluatorError) { return 'evaluator-error' }
    if ($TimedOut) { return 'timeout' }
    if ($BuildFailed) { return 'build-failure' }
    if ($TestsFailed) { return 'test-failures' }
    return 'passed'
}

function Test-JsonValueType {
    param($Value, [string]$TypeName)

    switch ($TypeName) {
        'null' { return $null -eq $Value }
        'boolean' { return $Value -is [bool] }
        'string' { return $Value -is [string] }
        'integer' { return ($Value -is [int] -or $Value -is [long]) }
        'number' { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) }
        'array' { return ($null -ne $Value -and $Value -is [System.Array]) }
        'object' { return $Value -is [System.Management.Automation.PSCustomObject] }
        default { throw "Tipo JSON Schema non supportato: $TypeName" }
    }
}

function Resolve-SchemaReference {
    param([string]$Reference, $RootSchema)

    if ($Reference -notmatch '^#/\$defs/([A-Za-z0-9_-]+)$') { throw "Riferimento non supportato: $Reference" }
    $definition = $RootSchema.'$defs'.PSObject.Properties[$Matches[1]]
    if ($null -eq $definition) { throw "Definizione non trovata: $Reference" }
    return $definition.Value
}

<#
.SYNOPSIS
Valida un valore rispetto a uno schema nel sottoinsieme supportato.

.OUTPUTS
Elenco di stringhe con percorso e motivo di ogni violazione; vuoto se valido.
#>
function Test-JsonSchemaSubset {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)]$Schema,
        [Parameter(Mandatory)]$RootSchema,
        [string]$Path = '$'
    )

    foreach ($keyword in $Schema.PSObject.Properties.Name) {
        if ($keyword -notin $script:SupportedKeywords -and $keyword -notin $script:AnnotationKeywords) {
            throw "Parola chiave dello schema non supportata dal validatore: $keyword (in $Path)"
        }
    }

    $errors = New-Object System.Collections.Generic.List[string]
    $has = { param($name) $null -ne $Schema.PSObject.Properties[$name] }

    if (& $has '$ref') {
        foreach ($e in Test-JsonSchemaSubset -Value $Value -Schema (Resolve-SchemaReference -Reference $Schema.'$ref' -RootSchema $RootSchema) -RootSchema $RootSchema -Path $Path) { $errors.Add($e) }
    }
    if (& $has 'const') {
        if (-not ($Value -ceq $Schema.const) -or $null -eq $Value) { $errors.Add("${Path}: valore diverso dalla costante $($Schema.const)") }
    }
    if (& $has 'enum') {
        $matched = $false
        foreach ($allowed in $Schema.enum) { if ($null -ne $Value -and $Value -ceq $allowed) { $matched = $true } }
        if (-not $matched) { $errors.Add("${Path}: valore non ammesso") }
    }
    if (& $has 'type') {
        $types = @($Schema.type)
        $typeMatched = $false
        foreach ($typeName in $types) { if (Test-JsonValueType -Value $Value -TypeName $typeName) { $typeMatched = $true } }
        if (-not $typeMatched) {
            $errors.Add("${Path}: tipo non valido, atteso $($types -join '|')")
            return @($errors)
        }
    }

    if ($Value -is [string]) {
        if ((& $has 'minLength') -and $Value.Length -lt $Schema.minLength) { $errors.Add("${Path}: stringa piu corta di $($Schema.minLength)") }
        if ((& $has 'maxLength') -and $Value.Length -gt $Schema.maxLength) { $errors.Add("${Path}: stringa piu lunga di $($Schema.maxLength)") }
        if ((& $has 'pattern') -and $Value -cnotmatch $Schema.pattern) { $errors.Add("${Path}: non conforme al pattern") }
    }
    if (($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and $Value -isnot [bool]) {
        if ((& $has 'minimum') -and $Value -lt $Schema.minimum) { $errors.Add("${Path}: minore di $($Schema.minimum)") }
        if ((& $has 'maximum') -and $Value -gt $Schema.maximum) { $errors.Add("${Path}: maggiore di $($Schema.maximum)") }
    }
    if ($Value -is [System.Array] -and (& $has 'items')) {
        for ($index = 0; $index -lt $Value.Count; $index++) {
            foreach ($e in Test-JsonSchemaSubset -Value $Value[$index] -Schema $Schema.items -RootSchema $RootSchema -Path "$Path[$index]") { $errors.Add($e) }
        }
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $present = @($Value.PSObject.Properties.Name)
        if (& $has 'required') {
            foreach ($name in $Schema.required) { if ($name -cnotin $present) { $errors.Add("${Path}: campo obbligatorio mancante '$name'") } }
        }
        $declared = if (& $has 'properties') { @($Schema.properties.PSObject.Properties.Name) } else { @() }
        if ((& $has 'additionalProperties') -and $Schema.additionalProperties -eq $false) {
            foreach ($name in $present) { if ($name -cnotin $declared) { $errors.Add("${Path}: campo non previsto '$name'") } }
        }
        foreach ($name in $declared) {
            if ($name -cin $present) {
                foreach ($e in Test-JsonSchemaSubset -Value $Value.$name -Schema $Schema.properties.$name -RootSchema $RootSchema -Path "$Path.$name") { $errors.Add($e) }
            }
        }
    }
    return @($errors)
}

<#
.SYNOPSIS
Verifica le regole di coerenza tra campi di un riepilogo gia valido per lo schema.

.OUTPUTS
Elenco di stringhe; vuoto se coerente.
#>
function Test-EvaluationSummaryConsistency {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Summary)

    $errors = New-Object System.Collections.Generic.List[string]
    $outcome = $Summary.outcome

    if ($Summary.exitCode -ne (Get-EvaluationExitCode -Outcome $outcome)) {
        $errors.Add("exitCode $($Summary.exitCode) incoerente con l'esito $outcome")
    }
    $started = [datetime]::Parse($Summary.startedAtUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    $finished = [datetime]::Parse($Summary.finishedAtUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    if ($finished -lt $started) { $errors.Add('finishedAtUtc precede startedAtUtc') }

    foreach ($suite in 'public', 'reserved') {
        $counts = $Summary."${suite}Tests"
        $status = $Summary.phases.$suite.status
        if ($status -in 'passed', 'failed' -and $null -eq $counts) { $errors.Add("${suite}Tests nullo con fase $status") }
        if ($status -eq 'not-run' -and $null -ne $counts) { $errors.Add("${suite}Tests presente con fase not-run") }
        if ($null -ne $counts) {
            if ($counts.executed -ne ($counts.passed + $counts.failed)) { $errors.Add("${suite}Tests: executed diverso da passed + failed") }
            if ($status -eq 'passed' -and $counts.failed -gt 0) { $errors.Add("fase $suite passed con test falliti") }
        }
    }

    $phaseStatuses = @($Summary.phases.build.status, $Summary.phases.public.status, $Summary.phases.reserved.status)
    $failedTests = 0
    foreach ($suite in 'public', 'reserved') { $counts = $Summary."${suite}Tests"; if ($null -ne $counts) { $failedTests += $counts.failed } }

    switch ($outcome) {
        'passed' {
            foreach ($status in $phaseStatuses) { if ($status -ne 'passed') { $errors.Add('passed richiede tutte le fasi passed') } }
            foreach ($suite in 'public', 'reserved') {
                $counts = $Summary."${suite}Tests"
                if ($null -eq $counts) { continue }
                if ($counts.failed -ne 0 -or $counts.skipped -ne 0 -or $counts.missing -ne 0 -or $counts.unexpected -ne 0) { $errors.Add("passed richiede ${suite}Tests senza falliti, saltati, mancanti o inattesi") }
                if ($counts.executed -ne $counts.expected) { $errors.Add("passed richiede ${suite}Tests con executed uguale a expected") }
            }
            foreach ($flag in 'originalInputUnchanged', 'archivedSubmissionUnchanged', 'suiteManifestsVerified') {
                if ($Summary.integrity.$flag -ne $true) { $errors.Add("passed richiede integrity.$flag true") }
            }
            if ($Summary.diagnostics.Count -ne 0) { $errors.Add('passed non ammette diagnostics') }
        }
        'test-failures' { if ($failedTests -eq 0) { $errors.Add('test-failures richiede almeno un test fallito') } }
        'build-failure' { if ($Summary.phases.build.status -ne 'failed') { $errors.Add('build-failure richiede la fase build failed') } }
        'timeout' { if ('timeout' -notin $phaseStatuses) { $errors.Add('timeout richiede una fase in timeout') } }
        'integrity-error' {
            $flags = @($Summary.integrity.originalInputUnchanged, $Summary.integrity.archivedSubmissionUnchanged, $Summary.integrity.suiteManifestsVerified)
            if ($false -notin $flags) { $errors.Add('integrity-error richiede almeno un controllo di integrita false') }
        }
        { $_ -in 'invalid-input', 'evaluator-error' } { if ($Summary.diagnostics.Count -eq 0) { $errors.Add("$outcome richiede almeno un messaggio diagnostico") } }
    }
    return @($errors)
}

<#
.SYNOPSIS
Valida un riepilogo: prima lo schema, poi la coerenza tra campi.

.PARAMETER Summary
Oggetto ottenuto con ConvertFrom-Json.

.PARAMETER SchemaPath
Percorso di `evaluation-summary.schema.json`.

.OUTPUTS
Elenco di stringhe; vuoto se il riepilogo e' valido e coerente.
#>
function Test-EvaluationSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)][string]$SchemaPath
    )

    $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
    $schemaErrors = @(Test-JsonSchemaSubset -Value $Summary -Schema $schema -RootSchema $schema)
    if ($schemaErrors.Count -gt 0) { return $schemaErrors }
    return @(Test-EvaluationSummaryConsistency -Summary $Summary)
}

Export-ModuleMember -Function Get-EvaluationExitCode, Get-EvaluationOutcome, Test-JsonSchemaSubset, Test-EvaluationSummaryConsistency, Test-EvaluationSummary
