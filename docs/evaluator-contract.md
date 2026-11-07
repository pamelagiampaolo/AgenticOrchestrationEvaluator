# Contratto del valutatore esterno

## Stato del documento

- Fase: nato al Passo 0 come contratto da congelare prima dell'implementazione;
  aggiornato fino al Passo 8 e alla riconciliazione documentale finale (7 novembre 2026).
- Stato: decisioni del Passo 0 approvate dall'utente il 7 novembre 2026. Le sezioni
  successive (Passi 3-8) registrano le decisioni prese durante l'implementazione e il
  loro stato di conferma.
- Implementazione: `evaluator/Invoke-Evaluation.ps1` realizza il contratto. E stato
  provato con soluzioni di prova (T1) e con le 39 fixture dei controlli (T1-T6), ma
  non ancora usato per prove pilota o valutazioni ufficiali.
- Dove il testo del Passo 0 e l'implementazione divergono, la divergenza e
  indicata nella sezione interessata.

## Obiettivo

Il valutatore esegue in modo riproducibile i controlli pubblici e riservati su
una submission prodotta da una delle condizioni sperimentali. Produce evidenze
destinate al ricercatore e non offre agli agenti un ciclo di correzione basato
sui risultati riservati.

Il modello di fiducia applicabile e definito in
`docs/evaluation-threat-model.md`.

## Unita di valutazione

Una valutazione riguarda esattamente:

- una submission;
- un task tra T1, T2, T3, T4, T5 e T6;
- una versione della baseline;
- una versione canonica delle suite pubbliche e riservate;
- una singola esecuzione identificata da `runId`.

I task sono indipendenti e non cumulativi. Ogni submission parte dalla stessa
baseline approvata e contiene soltanto la soluzione del task assegnato. La
valutazione di T4, per esempio, non richiede e non esegue le soluzioni T1-T3.

## Input del comando

L'entry point deve ricevere almeno submission e task. L'implementazione richiede
anche la baseline canonica e le dipendenze canoniche (TypeScript e Vitest), che il
repository fidato non contiene:

```powershell
.\evaluator\Invoke-Evaluation.ps1 `
    -SubmissionPath <directory-BenchmarkTarget> `
    -TaskId T1 `
    -BaselinePath <BenchmarkTarget-canonico> `
    -ToolsNodeModulesPath <node_modules-con-typescript-e-vitest>
```

Parametri facoltativi: `-RunsRoot`, `-RunId`, `-BuildTimeoutSeconds`,
`-PublicTimeoutSeconds`, `-ReservedTimeoutSeconds`, `-KeepWorkspace`.

`SubmissionPath` identifica una directory contenente una copia completa di
`BenchmarkTarget`, inclusi almeno `package.json`, lock file, configurazione
TypeScript e sorgenti.

L'evaluator non lavora direttamente nella directory ricevuta. Prima
dell'esecuzione:

1. risolve e valida il percorso;
2. crea il manifest della submission originale;
3. archivia una copia completa e immutabile della submission sotto la run;
4. crea una copia di lavoro separata;
5. esegue build e test soltanto sulla copia di lavoro;
6. verifica che submission archiviata e input originale non siano cambiati.

Decisioni del Passo 3 (7 novembre 2026), da confermare:

- `node_modules/` e `dist/` di primo livello non fanno parte dell'input valutato:
  le dipendenze canoniche sono fornite dal valutatore. L'esclusione e il fatto
  che fossero presenti nel sorgente sono registrati in
  `input/submission-manifest.json`.
- Symlink e junction nel resto della submission sono rifiutati come
  `invalid-input` e non vengono seguiti.
- Il manifest della submission usa SHA-256 sui byte esatti (nessuna
  normalizzazione dei fine riga), a differenza dei manifest delle suite.
- "Immutabile" significa attributo di sola lettura sui file archiviati piu
  verifica con manifest; non e una barriera di sicurezza contro codice ostile.
- Le directory vuote non fanno parte del manifest.
- `work/submission/` sotto la run contiene la copia di lavoro; viene rimossa dopo
  l'acquisizione di report e manifest, come previsto sopra.

Finche l'orchestratore principale non garantira esplicitamente la conservazione
della submission, l'evaluator ne conserva sempre una copia completa.

## Provenienza delle suite

### Suite pubblica

La suite pubblica canonica proviene dal repository principale approvato, non
dalla submission modificabile. L'evaluator deve usare le proprie copie
controllate di:

- test pubblici comuni applicabili;
- test pubblici specifici del task;
- configurazione Vitest specifica del task.

I test eventualmente aggiunti dall'agente non entrano nel risultato canonico.
Modifiche o eliminazioni dei test pubblici presenti nella submission non cambiano
la suite eseguita dall'evaluator.

### Suite riservata

La suite riservata proviene esclusivamente da questo repository. Non viene
copiata nel repository di lavoro usato dagli agenti e non viene mostrata agli
agenti prima, durante o dopo la valutazione.

## Suite eseguite per task

Per il task selezionato l'evaluator esegue, nell'ordine:

1. installazione o verifica delle dipendenze canoniche;
2. typecheck e build della submission;
3. test pubblici comuni applicabili;
4. test pubblici specifici del task;
5. test riservati specifici del task.

Nell'implementazione il punto 1 si riduce al collegamento delle dipendenze
canoniche indicate da `-ToolsNodeModulesPath`: non vengono installate e il loro
contenuto non e verificato (limite accettato, vedi "Accettazione e isolamento").

Il riepilogo mantiene separati almeno:

- esito build/typecheck;
- conteggi pubblici;
- conteggi riservati;
- esito complessivo.

T6 applica soltanto i test comuni compatibili con il contratto T6. Le esclusioni
devono essere dichiarate nel manifest canonico; non possono dipendere da skip
aggiunti dinamicamente dalla submission.

## Matrice riservata canonica prevista

La matrice da implementare e validare comprende:

- T1: T1-R01, T1-R02, T1-R03;
- T2: T2-R01, T2-R02, T2-R03;
- T3: T3-R01, T3-R02, T3-R03;
- T4: T4-R01, T4-R02, T4-R03;
- T5: T5-R01, T5-R02, T5-R03;
- T6: T6-R01, T6-R02, T6-R03, T6-R04.

T2-R03 e T6-R04 devono essere implementati come controlli riservati reali e
indipendenti, anche quando una parte del comportamento e coperta pubblicamente.

## Validazione dei controlli riservati

Ogni singolo controllo riservato deve avere almeno:

- una fixture conforme che deve superarlo;
- una fixture con una violazione mirata che deve farlo fallire;
- un'aspettativa esplicita sul motivo discriminante;
- una verifica che la fixture violante non fallisca soltanto per errori estranei
  al requisito osservato.

Le fixture sono organizzate per controllo:

```text
fixtures/
|-- smoke/
|   `-- known-good/
`-- controls/
    |-- T1/
    |   `-- R01/
    |       |-- compliant/
    |       `-- violating/
    `-- ...
```

Una fixture puo essere condivisa soltanto quando la relazione e dichiarata e non
rende ambiguo quale proprieta abbia determinato il risultato.

Stato reale: le fixture dei controlli seguono il layout `fixtures/controls/`
(39 fixture; T5-R01 ha sottovarianti). La fixture smoke non e stata spostata in
`fixtures/smoke/known-good/` e resta in `fixture/submission/`. Per 11 fixture vale
soltanto la proprieta sul proprio controllo (deroga in "Accettazione e
isolamento").

## Regola specifica per T5

T5-R02 verifica comportamentalmente che la factory e la logica applicativa usino
realmente i repository sostitutivi ricevuti.

T5-R01 usa l'AST TypeScript soltanto per vincoli strutturali non dimostrabili
tramite comportamento. Non usa espressioni regolari come fonte autorevole e non
impone nomi, disposizione dei file o dettagli implementativi non richiesti dalla
specifica pubblica.

Ogni controllo AST deve essere accompagnato da casi equivalenti scritti in forme
TypeScript diverse, per dimostrare che il controllo riconosce il significato e
non una formattazione particolare.

## Criterio di successo

Una valutazione ha esito `passed` soltanto quando:

1. input, task e manifest sono validi;
2. dipendenze e strumenti richiesti sono disponibili;
3. typecheck e build terminano con successo;
4. tutti i test pubblici canonici applicabili sono stati eseguiti e superati;
5. tutti i test riservati canonici del task sono stati eseguiti e superati;
6. non risultano test inattesi, mancanti, saltati o `todo`;
7. i report sono validi e coerenti con i manifest;
8. la submission archiviata e gli input originali sono rimasti invariati;
9. nessun processo ha superato il timeout.

Un test fallito produce un fallimento attribuibile alla submission. Report
mancanti o malformati, strumenti indisponibili, manifest incoerenti ed errori
del runner producono invece un errore dell'evaluator. I due casi non devono mai
essere aggregati.

## Classificazione minima degli esiti

- `passed`: tutti i criteri canonici sono soddisfatti;
- `test-failures`: almeno un controllo pubblico o riservato e fallito;
- `build-failure`: typecheck o build della submission e fallito;
- `timeout`: almeno una fase ha superato il limite;
- `invalid-input`: submission, TaskId o manifest di input non valido;
- `evaluator-error`: errore del runner, della configurazione o dei report;
- `integrity-error`: input, suite o submission archiviata non corrispondono ai
  manifest attesi.

Gli exit code del runner sono definiti nel Passo 2 dell'implementazione (7
novembre 2026) e verificati da `evaluator/tests/Test-EvaluationSummary.ps1`.
Le decine separano le cause: 1x attribuibili alla submission, 2x input, 3x
integrita, 4x errore del valutatore. Nessun consumatore deve dedurre il
risultato dal solo testo stampato su console.

| Esito | Exit code |
| --- | ---: |
| `passed` | 0 |
| `test-failures` | 10 |
| `build-failure` | 11 |
| `timeout` | 12 |
| `invalid-input` | 20 |
| `integrity-error` | 30 |
| `evaluator-error` | 40 |

Quando piu cause coesistono prevale la prima di questo elenco: `invalid-input`,
`integrity-error`, `evaluator-error`, `timeout`, `build-failure`,
`test-failures`. Una causa che invalida la valutazione non viene quindi mai
presentata come fallimento della soluzione. Test mancanti, inattesi o saltati
rispetto al manifest non sono `test-failures` e vengono trattati come errore del
valutatore o di integrita.

Il riepilogo `evidence/evaluation-summary.json` e descritto da
`schemas/evaluation-summary.schema.json`; le regole tra campi (per esempio
`passed` richiede zero test falliti, saltati, mancanti e inattesi) sono in
`evaluator/EvaluationSummary.psm1`. Gli script di verifica dei manifest
(`Test-*Manifest.ps1`, exit code 0, 1, 2) sono strumenti separati e non seguono questa
tabella.

## Visibilita dei risultati

I report pubblici e riservati dettagliati sono destinati al ricercatore e
all'analisi sperimentale. L'agente non riceve:

- sorgenti dei controlli riservati;
- identificatori o messaggi diagnostici riservati durante il task;
- stack trace della suite riservata;
- una nuova opportunita di modificare la submission dopo la valutazione.

Il sistema puo pubblicare in seguito dati aggregati della sperimentazione, ma
questa eventuale pubblicazione e esterna al flusso di esecuzione degli agenti.

## Layout persistente di una run

Layout prodotto dall'implementazione:

```text
runs/<runId>/
|-- input/
|   |-- submission/                (copia archiviata, sola lettura)
|   |-- submission-manifest.json
|   `-- metadata.json
|-- raw/
|   |-- build.stdout.txt
|   |-- build.stderr.txt
|   |-- public-<scope>-report.json (uno per scope: common e/o task)
|   |-- public.stdout.txt
|   |-- public.stderr.txt
|   |-- reserved-report.json
|   |-- reserved.stdout.txt
|   `-- reserved.stderr.txt
|-- evidence/
|   |-- evaluation-summary.json    (senza identificatori riservati)
|   `-- report-validation.json     (dettagli, anche riservati: solo ricercatore)
`-- work/                          (copia di lavoro, rimossa a fine run)
```

Rispetto al layout del Passo 0, i report pubblici sono uno per scope invece di uno
unico, ed e stato aggiunto `evidence/report-validation.json`. I file presenti
dipendono da quanto la run e avanzata: per esempio, con build fallita non ci sono
report di test.

La copia di lavoro temporanea non e parte delle evidenze e viene rimossa soltanto
dopo che report e manifest sono stati acquisiti. Se la run viene interrotta,
resta su disco e va rimossa manualmente. I dati persistenti non includono
credenziali o variabili d'ambiente non pertinenti.

## Ambiente e riproducibilita

Le 54 esecuzioni ufficiali avvengono sulla stessa macchina Windows. Ogni report
registra almeno:

- versione e build di Windows disponibili al processo;
- architettura del sistema;
- versione di Node;
- versione di npm;
- versione di TypeScript;
- versione di Vitest;
- hash del lock file;
- versione o commit dell'evaluator;
- commit della baseline dichiarato dall'orchestratore;
- data e orari UTC di inizio e fine.

Durante la definizione del contratto sono stati osservati Node `v24.17.0` e npm
`11.13.0`. Questi valori descrivono l'ambiente corrente ma non diventano versioni
ufficiali finche non vengono confermati dalle prove pilota e congelati nel
manifest dell'esperimento.

L'interrogazione dettagliata del sistema operativo non era disponibile al
processo corrente per limiti di permesso. L'evaluator usa metodi leggibili senza
privilegi elevati e registra `unavailable` se un campo non puo essere acquisito;
non inventa valori.

L'implementazione registra questi campi nel riepilogo:

- in `environment`: `windows`, `architecture`, `node`, `npm`, `typescript`,
  `vitest`, `lockFileSha256` (lock file della baseline) e `evaluatorVersion`
  (commit, con `-dirty` se ci sono modifiche);
- in `suites.baselineDeclaredCommit`: il commit della baseline, preso dal manifest
  pubblico e non da un orchestratore esterno, che non esiste ancora;
- in `startedAtUtc` e `finishedAtUtc`: inizio e fine.

Le versioni non sono ancora congelate in un manifest dell'esperimento.

## Fase di build (Passo 4, 7 novembre 2026)

Decisioni da confermare:

- Typecheck e build usano il compilatore delle dipendenze canoniche del valutatore
  (`node_modules` collegato alla copia di lavoro con una junction), con i comandi
  `tsc --noEmit` e `tsc --outDir <copia di lavoro>\dist`; gli `scripts` del
  `package.json` della submission non vengono eseguiti.
- I codici di uscita 1 e 2 di `tsc` indicano errori di compilazione della submission
  (`build-failure`); qualunque altro codice non nullo, o un compilatore assente, e un
  problema dello strumento (`evaluator-error`).
- Il limite di 60 secondi e complessivo per i due passi; al superamento viene
  terminato l'intero albero dei processi (`timeout`).
- I processi partono con un ambiente ridotto a un elenco di variabili ammesse
  (`PATH`, `PATHEXT`, `SystemRoot`, `windir`, `ComSpec`, `SystemDrive`, `TEMP`, `TMP`, `OS`,
  `NUMBER_OF_PROCESSORS`, `PROCESSOR_ARCHITECTURE`).
- `raw/build.stdout.txt` e `raw/build.stderr.txt` contengono i passi in sequenza, ciascuno
  preceduto da una riga `=== nome ===` aggiunta dal valutatore.
- Limite noto: `--outDir` e forzato dentro la copia di lavoro, ma altri percorsi di
  emissione configurabili in `tsconfig.json` (per esempio `declarationDir`,
  `tsBuildInfoFile`) non sono confinati. Non e prevista difesa da codice ostile.

## Fasi di test (Passo 5, 7 novembre 2026)

Decisioni da confermare:

- Suite pubblica: prima dell'esecuzione `tests/public/` e `vitest.public*.ts` della
  copia di lavoro vengono eliminati e sostituiti con i file canonici della baseline,
  verificati contro l'hash del manifest pubblico. Un file canonico non coincidente e
  un `integrity-error`.
- Scope pubblici per task: per T1-T4 prima `common` (`vitest.public.config.ts`) e poi
  il task; per T5 e T6 solo la configurazione del task, che include gia i file comuni
  (per T6 solo i compatibili), cosi nessun test e contato due volte.
- Suite riservata: in `work/reserved/` sono copiati solo i file del task e
  `vitest.reserved-task.config.ts`, verificati contro il manifest riservato; la
  submission e in `work/submission/`, affiancata, perche i test la importano da
  `../submission/src/index.ts`. Dopo l'esecuzione i file copiati sono riverificati:
  una differenza e un `integrity-error` che prevale su ogni altro esito.
- Report grezzi, uno per scope, con il reporter JSON di Vitest:
  `raw/public-common-report.json`, `raw/public-<Task>-report.json`,
  `raw/reserved-report.json`; log in `raw/public.*.txt` e `raw/reserved.*.txt` con
  righe `=== scope ===` aggiunte dal valutatore. Variante del layout elencato sopra
  (che indica "almeno" i file citati): i report non vengono uniti.
- Esito di fase: `passed` richiede exit 0 e un report valido con `success: true`;
  exit 1 con report valido e `success: false` e `failed` (test falliti); qualunque
  altra combinazione (per esempio exit 1 senza report) e `error` (errore del
  valutatore). Un timeout termina l'albero dei processi e interrompe la sequenza.
- Limite: 120 secondi per fase (complessivo sugli scope della fase).
- `passed` di fase, preso da solo, significa soltanto che Vitest e il suo report non
  riportano fallimenti. Il confronto con i manifest (test mancanti, inattesi, saltati,
  `todo`, duplicati) e una fase separata, aggiunta al Passo 6 (`Test-PhaseReports.ps1`).
  L'orchestratore la applica sempre.
- Limite noto: Vitest scrive la propria cache in `node_modules/.vite` attraverso la
  junction, cioe dentro le dipendenze canoniche.

## Validazione dei report (Passo 6, 7 novembre 2026)

I report di Vitest sono dati non fidati. `evaluator/ReportValidation.psm1` li confronta
con i manifest (pubblico per scope, riservato per task) e calcola i conteggi del
riepilogo: `expected`, `executed` (= `passed` + `failed`), `passed`, `failed`,
`skipped`, `missing`, `unexpected`. Regole, da confermare:

- `test-failures` (colpa della soluzione): test falliti; file di test che non si carica
  (stato `failed` con zero asserzioni; i suoi test attesi risultano `missing` ma
  "spiegati" dal fallimento del file); `success: false` senza altre anomalie
  (per esempio un errore non gestito durante la run).
- `evaluator-error`: test attesi mancanti non spiegati, test saltati/`todo`/`pending`
  tra quelli attesi, test non previsti, test duplicati, test dichiarati escluso (T6)
  che risultano eseguiti, stati sconosciuti, file fuori dalla directory attesa,
  `numTotalTests` diverso dalle asserzioni, `success: true` con test o file falliti,
  report assente o non valido. Prevale su `test-failures`.
- `passed`: nessuna anomalia e nessun fallimento.
- Le esclusioni dichiarate di T6 che compaiono come non eseguite non sono anomalie.
- Gli issue possono contenere nomi di test riservati: sono evidenze per il ricercatore,
  non per l'agente.

Limite: la validazione e un'ulteriore verifica sulla stessa sorgente di dati; non
protegge da una submission che alteri il report durante la propria esecuzione
(stesso processo e stessa identita, come da threat model).

## Orchestratore e riepilogo (Passo 7, 7 novembre 2026)

`evaluator/Invoke-Evaluation.ps1` concatena ingresso, build, suite pubblica, suite riservata e
validazione dei report e produce `evidence/evaluation-summary.json`. Decisioni confermate
dall'utente il 7 novembre 2026 (vedi il Passo 8):

- Dopo una build riuscita le due suite girano sempre entrambe, anche se la prima ha test
  falliti, per raccogliere piu evidenze; si fermano solo per violazioni di integrita. Build
  fallita, in timeout o in errore: le fasi di test sono `not-run` e i conteggi nulli.
- I manifest delle suite (hash dei file) sono verificati prima e dopo la run; una differenza e
  `integrity-error` e, se rilevata prima, non viene eseguita alcuna fase. La verifica completa
  degli identificatori con Vitest resta una verifica separata, fatta al congelamento.
- Dopo la run si riverificano sorgente originale e archivio contro il manifest della submission.
- Le fasi di test si risolvono con la validazione dei report: test falliti -> `failed`; anomalie
  strutturali -> `error`; un timeout lascia i conteggi nulli.
- Il riepilogo contiene solo conteggi e messaggi generici, mai identificatori dei test riservati;
  i dettagli (che possono contenerli) sono in `evidence/report-validation.json`, per il
  ricercatore.
- Il riepilogo e validato con lo schema; se non e valido l'esito diventa `evaluator-error`.
- `test-failures` richiede almeno una fase di test `failed` (non `failed > 0`: un file di test che
  non si carica ha `failed = 0`); `integrity-error` richiede un controllo falso o un messaggio
  diagnostico (l'incoerenza rilevata all'ingresso non ha ancora controlli).
- Con `TaskId` non valido non esiste riepilogo (lo schema ammette solo T1..T6): exit 20 con una
  diagnostica su stdout. Per gli altri input non validi il riepilogo e scritto solo se la
  directory della run non esiste gia e `RunsRoot` non e dentro la submission.
- La copia di lavoro e rimossa a evidenze scritte (salvo `-KeepWorkspace`); un errore di rimozione
  e segnalato su stderr e non cambia l'esito.
- L'ambiente registra Windows, architettura, Node, npm, versioni di TypeScript e Vitest (dal
  `package.json` delle dipendenze canoniche), hash SHA-256 del lock file della baseline e commit
  dell'evaluator (con `-dirty` se i file rilevanti sono modificati); `unavailable` se non acquisibile.

## Accettazione e isolamento (Passo 8, 7 novembre 2026)

Le decisioni del Passo 7 sull'orchestratore sono state confermate dall'utente il 7 novembre 2026.
Risultati osservati con TypeScript 7.0.2 e Vitest 5.1.0 reali (`evaluator/tests/Test-Acceptance.ps1`,
`evaluator/tests/Test-ControlMatrix.ps1`):

- Determinismo: due run della stessa submission producono riepiloghi equivalenti.
- Ignorati dal risultato: test pubblici e finti test riservati forniti dal candidato,
  `vitest.config.ts`/`vite.config.ts`, `node_modules` (anche un `tsc` finto) e `scripts` della
  submission.
- Rilevati come `integrity-error`: codice candidato che, durante la propria esecuzione, modifica la
  copia dei test riservati, il proprio sorgente originale o la propria copia archiviata. Il
  valutatore rileva, non impedisce.
- Interruzione della run: nessun riepilogo scritto, archivio e manifest integri, lo stesso `RunId`
  non e riutilizzabile, la submission si rivaluta con un nuovo `RunId`. La copia di lavoro della run
  interrotta resta su disco e va rimossa manualmente.
- Matrice dei controlli (39 fixture attraverso l'orchestratore): vedi `docs/control-matrix-audit.md`.

Decisioni dell'utente sui limiti verificati (7 novembre 2026):

- **Dipendenze canoniche modificabili e non verificate: accettato, nessuna verifica.** Il codice
  candidato puo scrivere nella directory delle dipendenze attraverso la junction `node_modules` e il
  valutatore non lo rileva (esito `passed` nell'esperimento). La mitigazione e organizzativa: agli
  agenti sara vietato modificare `node_modules`; intervengono soltanto sul progetto. Resta un limite
  da dichiarare: le run successive userebbero dipendenze eventualmente alterate.
- **Fixture validate solo sul proprio controllo: accettato.** Per T2-R03, T5-R01 (tre varianti),
  T5-R02, T5-R03 e T6-R04 vale la proprieta "la conforme supera il proprio controllo e la violante
  lo fallisce per il motivo previsto", non quella sull'intera suite del task. Ogni controllo resta
  dimostrato discriminante; non si riscrivono le fixture.
- **`rootDir` nelle fixture: corretto.** Tutti i `tsconfig.json` delle fixture hanno ora
  `rootDir: "src"`; sono stati creati quelli mancanti di T2-R03 e T6-R04.
- **T3 superato dalla baseline: accettato e documentato, nessun nuovo controllo.** L'esito della
  valutazione resta corretto (una submission T3 invariata ottiene `test-failures` per T3-P02), ma
  per T3 il numero di controlli riservati superati misura robustezza e assenza di regressioni, non la
  presenza della funzionalita. Va considerato nell'analisi.
- **Test riservati leggibili** dal codice candidato durante la propria esecuzione: atteso dal modello
  di fiducia (stesso processo e stessa identita).

## Timeout iniziali

I limiti iniziali, da confermare tramite prove pilota, sono:

- 60 secondi per typecheck e build complessivi;
- 120 secondi per la suite pubblica;
- 120 secondi per la suite riservata.

Il timeout si applica all'albero dei processi della fase. Un superamento termina
la fase, conserva stdout e stderr disponibili e classifica la run come
`timeout`. I limiti definitivi devono essere identici per tutte le condizioni
sperimentali equivalenti.

## Manifest canonici

Prima delle esecuzioni ufficiali devono essere congelati i seguenti elementi.
Lo stato e quello del 7 novembre 2026.

- manifest della baseline: congelato in `manifests/public-suite.manifest.json`
  (`public-1`);
- manifest dei test pubblici per task: congelato nello stesso file;
- manifest dei test riservati per task: congelato in
  `manifests/reserved-suite.manifest.json` (`reserved-1`);
- elenco e conteggio degli identificatori attesi: congelati nei due manifest;
- esclusioni comuni applicabili a T6: congelate nel manifest pubblico (6 test);
- versioni degli strumenti: **non ancora congelate**. Sono registrate in ogni
  riepilogo, ma non c'e un manifest dell'esperimento che le fissi;
- schema JSON del riepilogo: v1, prodotto e validato dall'orchestratore; da
  confermare dopo le prove pilota.

Una modifica a uno di questi elementi richiede una nuova versione della suite e
non puo essere applicata retroattivamente soltanto ad alcune run.

## Confini del Passo 0

Con questo contratto sono approvati:

1. input come copia completa di `BenchmarkTarget` indicata da percorso;
2. indipendenza e non cumulativita dei task;
3. riesecuzione e separazione delle suite pubbliche e riservate;
4. risultati riservati visibili soltanto al ricercatore;
5. implementazione reale di T2-R03 e T6-R04;
6. validazione positiva e negativa di ogni controllo riservato;
7. T5-R02 comportamentale e T5-R01 basato su AST per i soli vincoli necessari;
8. ambiente Windows unico con versioni registrate;
9. conservazione completa della submission da parte dell'evaluator;
10. organizzazione delle fixture per task e controllo.

Erano lasciati da determinare nei passi successivi:

- inventario definitivo e conteggi canonici delle suite: determinati nei manifest
  `public-1` e `reserved-1`;
- versioni ufficiali dell'ambiente dopo le prove pilota: ancora aperto;
- versione definitiva dello schema JSON dopo l'uso del runner reale: la v1 e
  prodotta dall'orchestratore, ma la versione definitiva attende le prove pilota;
- integrazione con l'orchestratore principale: ancora aperto.
