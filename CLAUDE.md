# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cos'è questo repository

Valutatore fidato e **privato** del progetto `Agentic Orchestration Benchmark`. Contiene i test riservati (Vitest) e le fixture che li validano, separati dal repository principale `C:\repos\AgenticOrchestrationBenchmark` (la baseline valutata è `BenchmarkTarget` lì dentro; nessuno script contiene il percorso, che si passa con `-BaselinePath`). I test riservati non devono mai essere copiati nel repository principale né in aree accessibili agli agenti sperimentali.

`AGENTS.md` è vincolante (in italiano): un solo passo circoscritto alla volta, spiegare prima cosa si farà, verificare davvero ciò che si dichiara, **nessun commit/push/eliminazione senza autorizzazione esplicita**, suggerire un messaggio di commit a fine passo. Lo stato corrente e il prossimo passo autorizzato sono in `docs/handoff.md`: leggerlo (insieme a `docs/evaluator-contract.md`, `docs/evaluation-threat-model.md`, `docs/control-matrix-audit.md`) prima di intervenire e aggiornarlo quando cambia lo stato. La documentazione è scritta in italiano.

## Stato e architettura

- Il vecchio evaluator basato su Windows Sandbox è stato rimosso (vedi `docs/archive/windows-sandbox-evaluator.md`). **L'orchestratore `Invoke-Evaluation.ps1` è completo e testato. È stato provato con soluzioni di prova T1 e con le 50 fixture dei controlli T1–T6, ma non ancora usato per prove pilota o valutazioni ufficiali.** Componenti sotto `evaluator/` (PowerShell 5.1, nessuna dipendenza):
  - manifest della suite riservata (`manifests/reserved-suite.manifest.json`) e di baseline + suite pubbliche (`manifests/public-suite.manifest.json`), con `New-/Test-ReservedManifest.ps1` e `New-/Test-PublicManifest.ps1` (moduli condivisi: `ManifestCommon.psm1`). Richiedono `-ToolsNodeModulesPath` (un `node_modules` con Vitest; il repo non ne ha) e, per il pubblico, `-BaselinePath` = `BenchmarkTarget`. Exit code 0 coerente / 1 differenze / 2 errore dello strumento. I test pubblici si ricavano da un'esecuzione con reporter JSON perché `vitest list` non espande i `test.each`. Modificare `reserved/` o la baseline senza rigenerare il manifest (nuova `suiteVersion`) lo fa fallire.
  - ingresso della valutazione: `EvaluationInput.psm1` + `Initialize-EvaluationRun.ps1` (valida input, manifest della submission a byte esatti, copia archiviata in sola lettura in `runs/<runId>/input/`, copia di lavoro in `runs/<runId>/work/`; `node_modules`/`dist` esclusi, symlink/junction rifiutati). Test: `.\evaluator\tests\Test-EvaluationInput.ps1`.
  - fase di build: `ProcessRunner.psm1` (timeout con terminazione dell'albero, ambiente ridotto) + `BuildPhase.psm1` + `Invoke-BuildPhase.ps1` (`tsc --noEmit` e `tsc --outDir` della copia di lavoro con le dipendenze canoniche via junction; exit 0/11/12/40). Test: `.\evaluator\tests\Test-BuildPhase.ps1 -ToolsNodeModulesPath <node_modules>`. Attenzione: un test che lascia processi orfani può bloccare la pulizia; chiudere solo i PID creati dal test, mai per nome.
  - fasi di test: `TestPhases.psm1` + `Invoke-TestPhase.ps1 -Suite public|reserved` (test pubblici canonici sostituiti nella copia di lavoro e verificati col manifest; solo i file riservati del task copiati in `work/reserved/`, riverificati dopo l'esecuzione; report JSON grezzi in `raw/`; exit 0/10/12/30/40). Da solo non confronta i report con i manifest: lo fa la validazione dei report, che l'orchestratore applica sempre. Test: `.\evaluator\tests\Test-TestPhases.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`.
  - validazione dei report: `ReportValidation.psm1` + `Test-PhaseReports.ps1 -Suite public|reserved` (confronto con i manifest, conteggi del riepilogo; anomalie strutturali = `evaluator-error` che prevale su `test-failures`; exit 0/10/40). Test: `.\evaluator\tests\Test-ReportValidation.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`. 
  - orchestratore: `Evaluation.psm1` + `Invoke-Evaluation.ps1 -SubmissionPath -TaskId -BaselinePath -ToolsNodeModulesPath` (controllo delle versioni di Node, TypeScript e Vitest contro `manifests/toolchain.manifest.json`, `toolchain-1`: se non coincidono `evaluator-error` prima di ogni fase → ingresso → build → suite pubblica → suite riservata → validazione → `evidence/evaluation-summary.json` validato con lo schema; exit 0/10/11/12/20/30/40). L'ordine di `Import-Module` in `Evaluation.psm1` è voluto (i moduli si reimportano a vicenda con `-Force`). Test: `.\evaluator\tests\Test-Evaluation.ps1 -ToolsNodeModulesPath <node_modules> -BaselinePath <BenchmarkTarget>`. Gli strumenti finti dei test devono dichiarare in `typescript/package.json` e `vitest/package.json` le versioni del manifest, altrimenti la run si ferma prima delle fasi.
  - accettazione: `tests/Test-Acceptance.ps1` e `tests/Test-ControlMatrix.ps1` (50 fixture via orchestratore, `-Tasks` per sottoinsiemi); helper condivisi in `tests/AcceptanceHelpers.ps1`. Limiti accettati dall'utente (dipendenze canoniche non verificate, 22 fixture validate solo sul proprio controllo, T3 superato dalla baseline) nel contratto, sezione "Accettazione e isolamento".
  - riepilogo della valutazione: `schemas/evaluation-summary.schema.json` + `EvaluationSummary.psm1` (esiti e exit code 0/10/11/12/20/30/40, precedenza tra cause, validazione). Test: `.\evaluator\tests\Test-EvaluationSummary.ps1`.
- `reserved/`: 19 controlli canonici `tN-rMM.test.ts` (T1–T6; T6 ne ha 4) più `smoke.test.ts`. Ogni controllo ha una config `vitest.tN-rMM.config.ts` (mancano per T2-R03 e T6-R04, coperti dalla config per task). `vitest.reserved-task.config.ts` seleziona per task tramite la variabile `RESERVED_TASK_ID` (`T1`..`T6`) con glob `reserved/<task>-r*.test.ts`.
- I test importano la soluzione da `../submission/src/index.ts`: la submission va resa disponibile come directory `submission` sorella di `reserved/` nell'area di lavoro; il repository non la contiene.
- `fixtures/controls/<Task>/<Rxx>/{compliant,violating}`: per ogni controllo una fixture conforme (deve superare l'intera suite del task) e una con violazione mirata (deve fallire **solo** quel controllo). T5-R01 ha sottovarianti con nome della forma: 10 conformi (forme equivalenti: alias di tipo, operazioni ereditate, facciata, costanti e composizione statica, factory senza tipo di ritorno, file separati...) e 4 violanti. `fixture/submission` è la fixture smoke; `fixtures/t1-ipc-compliant` contiene solo directory vuote non tracciate, residuo della pipeline IPC dismessa.
- Regole di design dei controlli: T5-R02 è comportamentale (doppi di repository); T5-R01 usa l'AST TypeScript, mai regex, e deve riconoscere forme equivalenti; nessun controllo impone nomi o layout non presenti nella specifica pubblica.
- `runs/` è generato e ignorato da Git (copie di runtime, input, output, evidenze).

## Comandi

Non c'è un `package.json` radice e `node_modules/` è vuoto: Vitest va invocato esplicitamente (ad es. `npx vitest`), con la submission/fixture posizionata come `submission` accanto a `reserved/`. Verificare l'ambiente prima di assumere che gli strumenti (Vitest, `tsc`, Prettier — quest'ultimo non risultava disponibile) siano installati. Esempi coerenti con le config:

```powershell
npx vitest run --config reserved/vitest.t5-r01.config.ts          # un singolo controllo
$env:RESERVED_TASK_ID = "T2"; npx vitest run --config reserved/vitest.reserved-task.config.ts   # tutti i controlli di un task
npx vitest run --config reserved/vitest.reserved.config.ts        # smoke test
```

Vitest emette un avviso non bloccante sulle config TS con sintassi ESM caricate come CommonJS.

## Note operative

- Strumenti e baseline stanno fuori dall'area degli agenti, in `C:\repos\AgenticOrchestrationTools`: `tools\node_modules` (TypeScript 7.0.2, Vitest 5.1.0, copiati da BenchmarkTarget) è il `-ToolsNodeModulesPath`, `baseline-ddf08e8` (estratta con `git archive ddf08e8`) è il `-BaselinePath`. Non usare il `node_modules` o il BenchmarkTarget del repository principale: Vitest vi scriverebbe le cache, e le cache contengono i moduli trasformati dei test riservati. L'evaluator passa sempre `--cache=false --fsModuleCache=false`. Il ciclo completo di regressione dura circa 4 minuti.
- Distinguere sempre fallimento della submission da errore dell'evaluator, e test falliti da test non eseguiti.
- Le fixture violanti vanno validate eseguendo l'intera suite del task e verificando che fallisca soltanto il controllo previsto.
