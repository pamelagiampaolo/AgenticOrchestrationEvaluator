# Evaluator

Evaluator locale in Windows PowerShell 5.1, senza dipendenze proprie. TypeScript e
Vitest arrivano da un `node_modules` esterno, indicato con `-ToolsNodeModulesPath`.
Sostituisce la precedente implementazione basata su Windows Sandbox, documentata in
`docs/archive/windows-sandbox-evaluator.md`.

Il punto di ingresso e `Invoke-Evaluation.ps1` (sezione "Valutazione completa").
Gli altri script eseguono le singole fasi e servono per diagnosi e test.
L'evaluator e stato provato con soluzioni di prova e con le 50 fixture dei
controlli, ma non ancora usato per prove pilota o valutazioni ufficiali.

Strumenti e baseline da usare stanno fuori dal repository principale, a cui gli agenti accedono:

- `-ToolsNodeModulesPath C:\repos\TesiEvaluatorTools\tools\node_modules`;
- `-BaselinePath C:\repos\TesiEvaluatorTools\baseline-ddf08e8`.

Vitest viene sempre eseguito con `--cache=false --fsModuleCache=false`, perche le sue cache
conterrebbero i moduli trasformati dei test riservati.

Il contratto, con le decisioni e i limiti accettati, e in
`docs/evaluator-contract.md`. Lo stato del lavoro e in `docs/handoff.md`.

## Manifest della suite riservata

`manifests/reserved-suite.manifest.json` (versione `reserved-2`) congela i 39 file
di `reserved/` con SHA-256 (CRLF normalizzato in LF) e i 19 test attesi per task,
piu il test smoke. Gli identificatori sono ricavati da `vitest list --json`.

```powershell
# Verifica (exit 0 coerente, 1 differenze, 2 errore dello strumento)
.\evaluator\Test-ReservedManifest.ps1 -ToolsNodeModulesPath <percorso-node_modules-con-vitest>
# Rigenerazione: solo per una nuova versione della suite
.\evaluator\New-ReservedManifest.ps1 -ToolsNodeModulesPath <percorso> -Force
```

Senza `-ToolsNodeModulesPath` la verifica controlla solo file e hash e lo dichiara.
Una modifica ai test riservati richiede una nuova `suiteVersion`, non un
aggiornamento retroattivo.

## Ingresso della valutazione (preparazione della run)

```powershell
.\evaluator\Initialize-EvaluationRun.ps1 -SubmissionPath <BenchmarkTarget-copia> -TaskId T1 [-RunsRoot <dir>] [-RunId <id>]
```

Valida `TaskId` (`T1`..`T6`, maiuscolo), `RunId` e la struttura della submission
(`package.json`, `package-lock.json`, `tsconfig.json`, `src/`), calcola
`submission-manifest.json` (SHA-256 sui byte esatti), archivia una copia in sola
lettura in `runs/<runId>/input/submission/` e prepara `runs/<runId>/work/submission/`.
`node_modules/` e `dist/` di primo livello sono esclusi e la loro presenza e
registrata; symlink e junction altrove sono rifiutati. Sorgente, archivio e copia di
lavoro vengono confrontati col manifest prima di dichiarare la run pronta.
Stampa JSON su stdout. Exit code: 0 `ready`, 20 `invalid-input`, 30
`integrity-error`, 40 `evaluator-error`. Un input non valido non crea directory.
Test: `.\evaluator\tests\Test-EvaluationInput.ps1`. Questo script non esegue build
ne test.

## Fase di build

```powershell
.\evaluator\Invoke-BuildPhase.ps1 -RunDirectory <runs\runId> -ToolsNodeModulesPath <node_modules-con-typescript> [-TimeoutSeconds 60]
```

Esegue nella copia di lavoro `tsc --noEmit` e `tsc --outDir <copia>\dist` con il
compilatore canonico (junction `node_modules`), timeout complessivo che termina
l'albero dei processi e ambiente ridotto. Scrive `raw/build.stdout.txt` e
`raw/build.stderr.txt`. JSON su stdout; exit code 0 `passed`, 11 `build-failure`, 12
`timeout`, 40 `evaluator-error`. Non esegue test e non rimuove la copia di lavoro:
`Remove-EvaluationWorkspace` (in `BuildPhase.psm1`) elimina prima la junction.
Test: `.\evaluator\tests\Test-BuildPhase.ps1 -ToolsNodeModulesPath <node_modules>`.

## Fasi di test

```powershell
.\evaluator\Invoke-TestPhase.ps1 -Suite public   -RunDirectory <runs\runId> -ToolsNodeModulesPath <node_modules-con-vitest> -BaselinePath <BenchmarkTarget> [-TimeoutSeconds 120]
.\evaluator\Invoke-TestPhase.ps1 -Suite reserved -RunDirectory <runs\runId> -ToolsNodeModulesPath <node_modules-con-vitest> [-TimeoutSeconds 120]
```

La suite pubblica sostituisce i test della submission con quelli canonici della
baseline (hash verificati contro `public-suite.manifest.json`) ed esegue `common` e
il task (T1-T4) oppure solo il task (T5, T6). La suite riservata copia in
`work/reserved/` i soli file del task (hash verificati contro
`reserved-suite.manifest.json`), li esegue accanto a `work/submission/` e li
riverifica dopo l'esecuzione. Report JSON grezzi in `raw/`. Exit code: 0 `passed`, 10
`test-failures`, 12 `timeout`, 30 `integrity-error`, 40 `evaluator-error`. Lo script da
solo non confronta i report con i manifest: lo fanno `Test-PhaseReports.ps1` e
l'orchestratore. Test:
`.\evaluator\tests\Test-TestPhases.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`.

## Validazione dei report

```powershell
.\evaluator\Test-PhaseReports.ps1 -Suite public|reserved -RunDirectory <runs\runId>
```

Confronta i report grezzi in `raw/` con i manifest e stampa JSON con `outcome`,
`counts` (expected, executed, passed, failed, skipped, missing, unexpected), `scopes` e
`issues`. Exit code: 0 `passed`, 10 `test-failures`, 40 `evaluator-error` (anomalie
strutturali: mancanti non spiegati, saltati, non previsti, duplicati, report assente o
incoerente). Le anomalie strutturali prevalgono sui test falliti. Test:
`.\evaluator\tests\Test-ReportValidation.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`.

## Manifest degli strumenti

`manifests/toolchain.manifest.json` (versione `toolchain-1`) fissa Node `v24.17.0`,
TypeScript `7.0.2` e Vitest `5.1.0`. Prima di ogni fase l'orchestratore confronta queste
versioni con quelle rilevate: `node --version` dal `PATH` e i `package.json` di `typescript`
e `vitest` in `-ToolsNodeModulesPath`. Se una versione non coincide, non e leggibile, o se il
manifest e illeggibile, l'esito e `evaluator-error` (exit 40) e la submission non viene
copiata. Le fasi lanciate da sole e gli script dei manifest non applicano il controllo. Per
cambiare una versione serve una nuova `toolchainVersion`.

## Valutazione completa

```powershell
.\evaluator\Invoke-Evaluation.ps1 -SubmissionPath <copia-BenchmarkTarget> -TaskId T1 `
    -BaselinePath <BenchmarkTarget> -ToolsNodeModulesPath <node_modules-con-typescript-e-vitest> `
    [-RunsRoot <dir>] [-RunId <id>] [-BuildTimeoutSeconds 60] [-PublicTimeoutSeconds 120] [-ReservedTimeoutSeconds 120] [-KeepWorkspace]
```

Verifica gli strumenti con il manifest degli strumenti, poi esegue ingresso, build, suite pubblica, suite riservata e validazione dei report; scrive in
`runs/<runId>/evidence/` `evaluation-summary.json` (conteggi e messaggi generici, validato con lo
schema) e `report-validation.json` (dettagli, anche riservati: solo per il ricercatore); stampa
il riepilogo su stdout. Exit code: 0 `passed`, 10 `test-failures`, 11 `build-failure`, 12
`timeout`, 20 `invalid-input`, 30 `integrity-error`, 40 `evaluator-error`. La copia di lavoro e
rimossa a fine run. Test: `.\evaluator\tests\Test-Evaluation.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`.

## Test di accettazione

```powershell
.\evaluator\tests\Test-Acceptance.ps1    -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>   # ~1 minuto
.\evaluator\tests\Test-ControlMatrix.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget> [-Tasks T1,T2]   # ~2 minuti
```

Il primo verifica determinismo, isolamento del codice candidato (test, configurazioni, dipendenze e
script ignorati; alterazioni di input e suite riservate rilevate), instradamento per task e
interruzione della run. Il secondo esegue tutte le fixture dei controlli attraverso l'orchestratore.
Gli helper condivisi sono in `tests/AcceptanceHelpers.ps1`.

## Riepilogo ed exit code

`schemas/evaluation-summary.schema.json` (v1) descrive il riepilogo della
valutazione; `evaluator/EvaluationSummary.psm1` fornisce la tabella esito -> exit
code (0, 10, 11, 12, 20, 30, 40), la precedenza tra cause e la validazione (schema
piu coerenza tra campi). Il validatore e un sottoinsieme di JSON Schema scritto per
Windows PowerShell 5.1, che non ha `Test-Json`; una parola chiave non supportata
genera un errore. Test: `.\evaluator\tests\Test-EvaluationSummary.ps1` (exit 0 se
tutti superati, 1 altrimenti).

## Manifest della baseline e delle suite pubbliche

`manifests/public-suite.manifest.json` (versione `public-1`) congela 19 file della
baseline (`package.json`, lock file, `tsconfig.json`, `vitest.public*.ts`, `src/`,
`tests/public/`) e, per `common` e `T1`..`T6`, i test pubblici attesi. Gli
identificatori vengono da un'esecuzione reale di Vitest con reporter JSON sulla
baseline, perche `vitest list` non espande i test parametrici. Sulla baseline i
test specifici del task falliscono (funzionalita non implementata): il manifest
registra i nomi, non l'esito. Le esclusioni sono ammesse solo in T6 (6 test non
eseguiti per `testNamePattern`; 26 eseguiti = 5 specifici + 21 comuni ammessi).
Conteggi eseguiti: common 27, T1 4, T2 4, T3 3, T4 4, T5 30, T6 26.

```powershell
.\evaluator\Test-PublicManifest.ps1 -BaselinePath <BenchmarkTarget> -ToolsNodeModulesPath <node_modules-con-vitest>
.\evaluator\New-PublicManifest.ps1 -BaselinePath <BenchmarkTarget> -ToolsNodeModulesPath <node_modules> -Force
```

Exit code: 0 coerente, 1 differenze, 2 errore dello strumento. Se i file non
coincidono con il manifest i test non vengono eseguiti. Il manifest registra il
commit dichiarato della baseline (`ddf08e8...`) ma l'autorita e l'hash dei file.
