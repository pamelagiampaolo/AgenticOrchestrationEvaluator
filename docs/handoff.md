# Passaggio di consegne

## Stato del passaggio

- Data: 7 novembre 2026.
- Responsabile operativo successivo: Claude.
- Commit di riferimento: `6c33e78` (riconciliazione documentale), piu l'intervento 1 (da committare).
  Il passaggio iniziale era su `5cbc11a`.
- Working tree: pulito a `6c33e78`. L'intervento 1 modifica `TestPhases.psm1`, `ManifestCommon.psm1`,
  `Test-Acceptance.ps1` e la documentazione.
- Scopo: permettere a Claude di proseguire senza perdere il contesto e a Codex
  di recuperare lo stato effettivo quando tornera sul repository.

Claude deve aggiornare questo documento durante il lavoro e prima di restituire
la responsabilita, riportando commit, modifiche, verifiche realmente eseguite,
problemi aperti e prossimo passo. Restano applicabili tutte le istruzioni di
`AGENTS.md`, in particolare il divieto di creare commit senza autorizzazione
esplicita dell'utente.

## Attivita completate

- Il contratto del valutatore locale e documentato in
  `docs/evaluator-contract.md`.
- Il modello di fiducia e documentato in
  `docs/evaluation-threat-model.md`.
- L'audit corrente e registrato in `docs/control-matrix-audit.md`.
- Tutti i 19 controlli riservati canonici dispongono di evidenza positiva e
  negativa tramite fixture conformi e con violazione mirata.
- T5-R01 usa l'AST TypeScript e comprende due varianti conformi e una violante.
- T5-R02 e T5-R03 sono controlli indipendenti; il precedente controllo combinato
  e stato pensionato.
- Le suite complete delle fixture introdotte nelle ultime iterazioni sono state
  eseguite per verificare che ciascuna violazione fallisse soltanto il controllo
  previsto.

- Manifest congelati: suite riservata (`reserved-1`) e baseline piu suite pubbliche
  (`public-1`).
- Evaluator locale completo (Passi 2-8): ingresso, build, suite pubblica e
  riservata, validazione dei report e riepilogo validato con lo schema. E coperto
  da test unitari, di accettazione e dalla matrice dei 39 controlli eseguita
  attraverso l'orchestratore.
- Riconciliazione documentale finale: contratto, audit, threat model, README e
  CLAUDE.md allineati allo stato reale.

## Ancora aperto

Valido dopo la riconciliazione del 7 novembre 2026.

- **Nessuna prova pilota o valutazione ufficiale e stata eseguita.** Sono
  attivita successive e richiedono una nuova autorizzazione. Servono a confermare
  timeout, schema v1 e versioni dell'ambiente.
- **Manca un manifest dell'esperimento con le versioni degli strumenti**: Node,
  npm, TypeScript, Vitest e lock file. Le versioni sono registrate in ogni
  riepilogo, ma non sono congelate.
- **Decisioni dei Passi 3-6 non ancora confermate esplicitamente dall'utente.**
  Sono descritte nel contratto, nelle sezioni "Input del comando", "Fase di
  build", "Fasi di test" e "Validazione dei report", e sono tuttora marcate
  "da confermare". Quelle del Passo 7 sono state confermate.
- **Limiti accettati** (contratto, sezione "Accettazione e isolamento"):
  - dipendenze canoniche non verificate;
  - 11 fixture validate solo sul proprio controllo;
  - T3 superato dalla baseline;
  - test riservati leggibili dal codice candidato.
- **Non ancora integrato con l'orchestratore principale** della sperimentazione.
- **Residui e avvisi dell'ambiente:**
  - `fixtures/t1-ipc-compliant/` contiene solo directory vuote non tracciate,
    residuo della pipeline IPC dismessa. Non e stato rimosso, perche serve
    autorizzazione;
  - Prettier non e disponibile;
  - Vitest/Vite emette un avviso non bloccante sulle configurazioni TypeScript.

## Cronologia dei passi

Il 7 novembre 2026 `fixtures/t5/` e stato ispezionato (nessun riferimento da
test o configurazioni, tutti i file diversi dalle fixture canoniche, violazione
legacy coperta da T5-R01 AST) e rimosso con `git rm -r` su autorizzazione
dell'utente. Verifica eseguita in copia temporanea (Vitest di `BenchmarkTarget`):
T5-R01 passa con entrambe le fixture conformi e fallisce con `direct-persistence`;
T5-R02 e T5-R03 passano con le conformi e falliscono con le violanti.

Dopo il commit `69b860e` e stato aggiunto il manifest della suite riservata
(`evaluator/ReservedManifest.psm1`, `New-ReservedManifest.ps1`,
`Test-ReservedManifest.ps1`). Verificato: generazione deterministica (due
generazioni con hash identico), caso positivo exit 0, e exit 1 per hash
modificato, file rimosso, file extra e `test.skip`; exit 0 con CRLF; exit 2 per
manifest assente. Limite: `vitest list` non elenca i test saltati, quindi
skip/todo vanno rilevati anche nei report del futuro runner.

Manifest della baseline e delle suite pubbliche (`evaluator/PublicManifest.psm1`,
`New-PublicManifest.ps1`, `Test-PublicManifest.ps1`, `ManifestCommon.psm1`; il
modulo riservato e stato rifattorizzato sul modulo comune e rigenerato con output
identico). Verificato: generazione deterministica, positivo exit 0, exit 1 per
src modificato, test aggiunto, file extra, config rimossa e manifest alterato
(test inesistente, test spostato tra eseguiti/esclusi, conteggio incoerente),
exit 2 per manifest assente e baseline senza tsconfig. Limiti: la baseline
fallisce i test di task per costruzione, quindi il manifest non certifica nessuna
soluzione; i nomi non sono stati confrontati con una soluzione corretta.

Passo 2 completato: schema JSON del riepilogo (`schemas/evaluation-summary.schema.json`),
tabella esiti/exit code, precedenza tra cause e validazione in
`evaluator/EvaluationSummary.psm1`, test in `evaluator/tests/Test-EvaluationSummary.ps1`
(54 asserzioni superate). Verificato anche che i test falliscono se la validazione
e disattivata (34 falliti) o se la tabella degli exit code viene alterata (3).
Limiti: lo schema non e ancora prodotto da un runner reale; il validatore copre
solo il sottoinsieme di JSON Schema usato; i codici sono una proposta di questo
passo, documentata nel contratto e da confermare.

Passo 3 completato: ingresso del runner (`evaluator/EvaluationInput.psm1`,
`Initialize-EvaluationRun.ps1`, test in `evaluator/tests/Test-EvaluationInput.ps1`,
44 asserzioni superate). Decisioni da confermare: esclusione di `node_modules` e
`dist`, rifiuto di symlink/junction, hash a byte esatti, "immutabile" = sola
lettura + manifest (dettagli nel contratto). Mutazioni di controllo: senza
controllo dei collegamenti (3 falliti), senza esclusioni (crash e 3 falliti),
senza sola lettura (3 falliti), senza `RunsRoot` annidato (2 falliti), senza
verifica del sorgente (1 fallito). Limite: non e coperto dai test che
`New-EvaluationRun` chiami davvero `Assert-RunInputIntegrity`; la funzione e
testata da sola. Non verificati: percorsi molto lunghi, caratteri speciali nei
nomi dei file, concorrenza di piu run.

Passo 4 completato: fase di build (`evaluator/ProcessRunner.psm1`, `BuildPhase.psm1`,
`Invoke-BuildPhase.ps1`, test in `evaluator/tests/Test-BuildPhase.ps1`, 29 asserzioni
superate con TypeScript reale e compilatori simulati). Decisioni da confermare nel
contratto (sezione "Fase di build"). Mutazioni di controllo rilevate: ambiente non
ripulito, timeout per passo invece che complessivo, ogni codice non nullo come
`failed`; albero dei processi non terminato verificato in modo mirato (il discendente
resta vivo). NON discriminata dai test: l'eliminazione esplicita della junction in
`Remove-EvaluationWorkspace`, perche in questo ambiente (PowerShell 5.1.26100)
`Remove-Item -Recurse` non attraversa le junction (verificato con directory
usa-e-getta); resta come precauzione. Incidente di processo: una mutazione senza
terminazione dell'albero ha lasciato processi orfani che bloccavano la pulizia; ho
chiuso solo quelli del mio test (catena dei PID) e rimosso la sola directory temporanea
creata. Non verificati: output molto grandi (nessun limite di dimensione dei log),
percorsi con caratteri speciali di cmd (`&`, `%`), emissioni di `tsc` fuori dalla copia
di lavoro diverse da `--outDir`, versioni degli strumenti non ancora registrate.

Passo 5 completato: fasi di test pubblica e riservata (`evaluator/TestPhases.psm1`,
`Invoke-TestPhase.ps1`, test in `evaluator/tests/Test-TestPhases.ps1`, 25 asserzioni
superate con Vitest reale e Vitest simulato). `ProcessRunner` ora accetta variabili
d'ambiente aggiuntive ed espone `Add-StepLog` (usato anche dalla fase di build).
Decisioni da confermare nel contratto (sezione "Fasi di test"). Mutazioni di
controllo rilevate: test pubblici non sostituiti (il test va in errore), hash
canonici non verificati, nessuna riverifica dei file riservati (2 falliti), exit 1
senza report come `failed`, scope comune sempre eseguito, tutti i file riservati
copiati. Per la soluzione reale di T1 ho costruito nel test la baseline piu
`findProductsBelowStock`: e codice di prova, non una soluzione sperimentale. Limiti:
nessuna validazione dei report rispetto ai manifest (passo 6); `passed` di fase non
certifica che i test attesi siano stati eseguiti; la cache di Vitest viene scritta
dentro le dipendenze canoniche; nessun limite di dimensione dei log; reserved e
submission condividono processo e identita (accettato dal threat model).

Passo 6 completato: validazione dei report (`evaluator/ReportValidation.psm1`,
`Test-PhaseReports.ps1`, test in `evaluator/tests/Test-ReportValidation.ps1`, 33
asserzioni superate: 21 sintetiche e 12 su report reali). `TestPhases.psm1` ora esporta
`Get-RunTaskId` e `Get-PublicScopeNames` (usati dalla validazione). Regole di
classificazione da confermare nel contratto (sezione "Validazione dei report"). Mutazioni
di controllo rilevate: 8 su 8 (saltati, non previsti, mancanti non spiegati, duplicati,
incoerenza success/falliti, `numTotalTests`, precedenza struttura/fallimento, escluso
eseguito). Verificato su report reali: soluzione conforme, controllo violato, sorgente con
errore di sintassi (file che non si carica), funzione mancante, T6 con 6 esclusioni.
Limiti: non protegge da una submission che alteri il report durante la propria esecuzione;
non ancora assemblato il riepilogo finale.

Passo 7 completato: orchestratore (`evaluator/Evaluation.psm1`, `Invoke-Evaluation.ps1`, test in
`evaluator/tests/Test-Evaluation.ps1`, 34 asserzioni superate). Corretta una regola del passo 2:
`test-failures` richiede una fase di test `failed` (non `failed > 0`) e `integrity-error`
accetta anche un messaggio diagnostico (test del riepilogo: 56 asserzioni). Decisioni da
confermare nel contratto (sezione "Orchestratore e riepilogo"). Verificato end-to-end con Vitest
e TypeScript reali: soluzione T1 conforme `passed` (31/31 pubblici, 3/3 riservati, riepilogo
valido, copia di lavoro rimossa, nessun identificatore riservato nel riepilogo), soluzione con
`<=` `test-failures` (pubblica 1 fallito, riservata 1 su 3), funzione mancante `test-failures`,
sorgente non compilabile `build-failure`; input non valido, TaskId non valido, RunsRoot dentro la
submission, RunId esistente o con path traversal (nessun file sovrascritto o scritto fuori),
baseline alterata `integrity-error` prima di eseguire; con Vitest simulato timeout, assenza di
report, alterazione dei file riservati, del sorgente originale e dell'archivio durante la run.
Mutazioni di controllo rilevate: 6 su 6 significative (una equivalente per doppia difesa).
Limiti: non e coperto un riepilogo reso non valido da un bug (conversione in `evaluator-error`);
le anomalie strutturali dei report sono coperte dai test della validazione, non dall'orchestratore;
la verifica dei manifest nella run controlla gli hash dei file ma non rielenca i test con Vitest;
nessuna esecuzione parallela provata; il lock file registrato e quello della baseline.

Passo 8 completato: test di accettazione (`evaluator/tests/Test-Acceptance.ps1`, 19 asserzioni) e
matrice dei controlli attraverso l'orchestratore (`evaluator/tests/Test-ControlMatrix.ps1`, 39
fixture, 40 asserzioni), helper in `evaluator/tests/AcceptanceHelpers.ps1`. Decisioni del passo 7
confermate dall'utente. Risultati e limiti nel contratto (sezione "Accettazione e isolamento") e
nell'audit (sezione "Verifica attraverso l'orchestratore").

Questioni aperte del passo 8, decise dall'utente il 7 novembre 2026 e chiuse nello stesso giorno
(dettagli nel contratto, sezione "Accettazione e isolamento"):

1. Dipendenze canoniche modificabili dal codice candidato: accettato, nessuna verifica; agli agenti
   sara vietato modificare `node_modules`.
2. 11 fixture validate solo sul proprio controllo: deroga accettata, fixture invariate.
3. `rootDir` nelle fixture: corretto in tutti i 39 `tsconfig.json` (4 creati); tolto l'adattamento
   dal test della matrice.
4. T3 superato dalla baseline: documentato, nessun nuovo controllo.

Riconciliazione documentale finale (7 novembre 2026), solo documenti e nessuna modifica al
codice:

- contratto: stato, firma reale del comando, dipendenze non installate, layout reale della run,
  campi dell'ambiente, stato dei manifest canonici, limite superato della fase di test;
- audit: stato finale e problemi trasversali risolti (i percorsi assoluti T5 erano gia stati
  rimossi con `cd3110b`);
- threat model: pipeline T1 indicata come dismessa, nuova sezione sullo stato
  dell'implementazione;
- README, `evaluator/README.md` e CLAUDE.md: aggiornati.

Nella cronologia sopra i conteggi riflettono lo stato del momento: il test del riepilogo, per
esempio, era a 54 asserzioni al Passo 2 ed e a 56 dal Passo 7.

## Prossimo passo

Il piano di costruzione e concluso. Le attivita successive richiedono una nuova
autorizzazione:

1. confermare o modificare le decisioni dei Passi 3-6;
2. eseguire prove pilota con soluzioni reali, per fissare timeout, schema e versioni;
3. congelare il manifest dell'esperimento con le versioni degli strumenti;
4. avviare le valutazioni ufficiali.

## Analisi generale e intervento 1 (7 novembre 2026)

Un'analisi in sola lettura del progetto ha individuato problemi da risolvere prima della
sperimentazione (rapporto: `C:\Users\Utente\.claude\plans\ticklish-meandering-sutton.md`).

L'intervento 1 e stato autorizzato ed eseguito:

- **Fuga dei test riservati.** Le cache di Vitest nel `node_modules` di BenchmarkTarget, nel
  repository principale e quindi accessibili agli agenti, contenevano:
  - `.vite`: esiti e titoli dei test riservati;
  - `.vitest-cache`: i moduli trasformati, cioe il codice dei test riservati.

  Entrambe sono state eliminate su autorizzazione. Una ricerca successiva nel repository principale
  non trova piu riferimenti, salvo quanto descritto nel punto seguente.
- **Riferimenti ancora presenti nel repository principale, non toccati.**
  `docs/benchmark/B2-progettazione-task.md` (tracciato da Git) descrive i controlli riservati con
  ID, input ed esito atteso. Decisione dell'utente (8 novembre 2026): nessun intervento. Gli
  agenti lavoreranno leggendo soltanto il progetto sandbox della libreria TypeScript e non
  dovrebbero avere accesso a `docs/`. Se questa condizione cambia, il documento torna a essere una
  fuga di specifica.
- **Copie di prova nella TEMP dell'utente.** Le copie dei test riservati lasciate nello scratchpad di
  Claude dalle prove di mutazione sono state eliminate su autorizzazione, l'8 novembre 2026. Sono
  state rimosse prima le junction verso il `node_modules` di BenchmarkTarget, senza attraversarle.
- **Strumenti e baseline dedicati** in `C:\Users\Utente\TesiEvaluatorTools`:
  - `tools\node_modules`: copia senza cache;
  - `baseline-ddf08e8`: `git archive` del commit dichiarato.

  Sono questi i percorsi da passare all'evaluator. Entrambi i manifest risultano coerenti con i
  nuovi percorsi.
- **Cache di Vitest disattivate** (`--cache=false --fsModuleCache=false`) in `TestPhases.psm1` e
  `ManifestCommon.psm1`. In `Test-Acceptance.ps1` e stata aggiunta un'asserzione che verifica che
  le run non scrivano cache.

Verifiche eseguite con i nuovi percorsi:

- regressione completa superata. Asserzioni superate per script:

  | Script | Asserzioni |
  | --- | ---: |
  | Accettazione | 20 |
  | Matrice (39 fixture) | 40 |
  | Orchestratore | 34 |
  | Validazione dei report | 33 |
  | Fasi di test | 25 |
  | Build | 29 |
  | Ingresso | 44 |
  | Riepilogo | 56 |

- entrambi i manifest coerenti;
- dopo la regressione, nessuna cache negli strumenti ne nel repository principale e nessun residuo
  in TEMP.

Controprova: togliendo i flag da `TestPhases.psm1` in una copia temporanea, fallisce esattamente la
nuova asserzione. I flag in `ManifestCommon.psm1` (strumenti dei manifest) non hanno un test dedicato.

Nota: la prima estrazione con `git archive` aveva convertito i fine riga in CRLF (`core.autocrlf=true`).
I manifest non se ne accorgono, perche normalizzano i fine riga, ma cambiano l'hash del lock file nel
riepilogo e l'helper dei test. La baseline va quindi estratta con
`git -c core.autocrlf=false archive ddf08e8 BenchmarkTarget`.

Interventi successivi proposti, ancora da autorizzare:

2. controllo delle versioni degli strumenti prima della run;
3. sonde sulle forme equivalenti di T5-R01;
4. regole per gli agenti;
5. prova pilota.

## Verifiche richieste alla ripresa

Prima di intervenire:

1. eseguire `git status --short`;
2. confrontare `git log -5 --oneline` con il commit indicato sopra;
3. leggere integralmente `AGENTS.md`, questo documento, il contratto, il threat
   model e l'audit;
4. non assumere che lo stato sia rimasto invariato se Claude ha aggiunto commit;
5. distinguere sempre lavoro completato, pianificato e non verificato.
