# Evaluator

La precedente implementazione basata su Windows Sandbox e stata rimossa per
consentire la costruzione pulita di un evaluator locale coerente con il modello
di fiducia corrente.

L'architettura dismessa e documentata in
`docs/archive/windows-sandbox-evaluator.md`. Il nuovo evaluator dovra conservare
integrita degli input, timeout, validazione dei report e tracciabilita delle
evidenze senza dipendere obbligatoriamente dalla virtualizzazione.

Il contratto approvato del nuovo evaluator e definito in
`docs/evaluator-contract.md`. L'implementazione deve procedere per passi
verificabili a partire dall'audit della matrice dei controlli.

## Manifest della suite riservata

`manifests/reserved-suite.manifest.json` (versione `reserved-1`) congela i 39 file
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
