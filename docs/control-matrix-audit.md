# Audit della matrice canonica dei controlli

## Stato del documento

- Data: 7 novembre 2026.
- Fase: completamento del progetto dei test esterni, Passo 1.
- Scopo: confrontare il contratto approvato con i controlli, le configurazioni e
  le fixture realmente presenti prima di modificare suite o runner.
- Fonti: `docs/evaluator-contract.md`, `docs/evaluation-threat-model.md`,
  `reserved/`, `fixtures/` e le suite pubbliche presenti in
  `C:\repos\AgenticOrchestrationBenchmark\benchmark\BenchmarkTarget`.
- Natura dell'audit: ispezione statica, aggiornata con le evidenze runtime delle
  iterazioni completate. `Presente` non significa `validato` in assenza di una
  prova positiva e negativa registrata.
- Aggiornamento finale (7 novembre 2026, riconciliazione documentale): suite
  congelate nei manifest `reserved-1` (ora `reserved-2`) e `public-1` e matrice eseguita attraverso
  l'orchestratore (sezione "Verifica attraverso l'orchestratore"). Le sezioni
  storiche sono conservate e annotate dove lo stato e cambiato.

## Criteri di classificazione

- **Presente da validare**: esiste un controllo dedicato coerente, per quanto
  osservabile staticamente, con il requisito dichiarato. Mancano comunque le
  fixture positiva e negativa canoniche richieste dal contratto.
- **Parziale**: esiste una parte del controllo, ma manca indipendenza, copertura
  discriminante o conformita a un vincolo esplicito del contratto.
- **Da sostituire**: l'implementazione corrente usa una tecnica esclusa dal
  contratto e non puo essere congelata come controllo canonico.
- **Mancante**: non esiste un controllo corrispondente.

Ogni controllo e ora validato individualmente con una fixture conforme, una
fixture con violazione mirata e una prova runtime del motivo discriminante. La
matrice e congelata in `manifests/reserved-suite.manifest.json` (`reserved-2`).
Viene eseguita attraverso il runner generale da
`evaluator/tests/Test-ControlMatrix.ps1`.

## Matrice riservata

| ID | Proprieta discriminante prevista | Implementazione corrente | Fixture dedicate | Stato e azione necessaria |
| --- | --- | --- | --- | --- |
| T1-R01 | Soglia stretta: con soglia `5` e restituito solo `P-001` | `reserved/t1-r01.test.ts` | `fixtures/controls/T1/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T1; la violante usa `<=`, supera T1-R02/R03 e fallisce soltanto T1-R01 includendo `P-002`, la cui scorta e uguale alla soglia |
| T1-R02 | Catalogo vuoto restituisce una collezione vuota | `reserved/t1-r02.test.ts` | `fixtures/controls/T1/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T1; la violante restituisce un prodotto fantasma solo per il catalogo vuoto, supera T1-R01/R03 e fallisce soltanto T1-R02 |
| T1-R03 | La mutazione del risultato non altera lo stato interno | `reserved/t1-r03.test.ts` | `fixtures/controls/T1/R03/{compliant,violating}` | Validato con oracolo indipendente: la conforme supera l'intera suite T1; la violante espone gli oggetti interni, supera T1-R01/R02 e fallisce soltanto T1-R03 dopo la mutazione del nome restituito |
| T2-R01 | Quantita negativa o decimale fallisce senza mutazioni | `reserved/t2-r01.test.ts` | `fixtures/controls/T2/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T2; la violante aggiorna la scorta prima della validazione, supera T2-R02/R03 e fallisce soltanto T2-R01 dopo avere comunque emesso `INVALID_QUANTITY` |
| T2-R02 | Un carico sull'istanza A non modifica l'istanza B | `reserved/t2-r02.test.ts` | `fixtures/controls/T2/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T2; la violante condivide soltanto la mappa delle scorte, supera T2-R01/R03 e fallisce soltanto T2-R02 mostrando `P-002` modificato anche nell'istanza B |
| T2-R03 | Il carico modifica solo la scorta selezionata, non altre scorte o ordini | `reserved/t2-r03.test.ts` | `fixtures/controls/T2/R03/{compliant,violating}` | Validato: la fixture conforme passa; la violante fallisce per la sola modifica di `P-001` da `0` a `2` |
| T3-R01 | Duplicati non adiacenti sono aggregati correttamente | `reserved/t3-r01.test.ts` | `fixtures/controls/T3/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T3; la violante aggrega soltanto gruppi adiacenti, supera T3-R02/R03 e fallisce soltanto T3-R01 lasciando `P-002` a `2` anziche `0` |
| T3-R02 | Insufficienza tardiva lascia tutte le scorte e l'ordine invariati | `reserved/t3-r02.test.ts` | `fixtures/controls/T3/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T3; la violante applica le righe sequenzialmente, supera T3-R01/R03 e fallisce soltanto T3-R02 lasciando `P-002` a `3` dopo l'errore tardivo su `P-003` |
| T3-R03 | Tre righe duplicate al limite esatto confermano e portano la scorta a zero | `reserved/t3-r03.test.ts` | `fixtures/controls/T3/R03/{compliant,violating}` | Validato: la conforme supera l'intera suite T3; la violante ignora dalla terza occorrenza dello stesso prodotto, supera T3-R01/R02 e fallisce soltanto T3-R03 lasciando `P-002` a `2` anziche `0` |
| T4-R01 | Sospendere un prodotto inesistente fallisce senza mutazioni | `reserved/t4-r01.test.ts` | `fixtures/controls/T4/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T4; la violante sospende `P-001` prima di emettere `PRODUCT_NOT_FOUND`, supera T4-R02/R03 e fallisce soltanto T4-R01 per lo stato osservabile modificato |
| T4-R02 | Un ordine misto con prodotto sospeso fallisce atomicamente | `reserved/t4-r02.test.ts` | `fixtures/controls/T4/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T4; la violante applica la prima riga prima di rilevare il prodotto sospeso, supera T4-R01/R03 e fallisce soltanto T4-R02 lasciando `P-002` a `4` con l'ordine ancora `draft` |
| T4-R03 | La sospensione successiva non altera un ordine storico confermato | `reserved/t4-r03.test.ts` | `fixtures/controls/T4/R03/{compliant,violating}` | Validato: la conforme supera l'intera suite T4; la violante riporta a `draft` gli ordini confermati contenenti il prodotto sospeso, supera T4-R01/R02 e fallisce soltanto T4-R03 in `getOrder` e `listOrders`, lasciando correttamente la scorta a `4` |
| T5-R01 | La logica applicativa dipende dai contratti, senza persistenza concreta interna | `reserved/t5-r01.test.ts` | `fixtures/controls/T5/R01/{compliant,violating}` con varianti interne | Validato con AST TypeScript 7. In `reserved-2` (8 novembre 2026) accetta forme equivalenti: 10 conformi passano, 4 violanti falliscono (vedi "T5-R01: forme equivalenti") |
| T5-R02 | Factory e logica usano realmente tutti i repository sostitutivi ricevuti | `reserved/t5-r02.test.ts` | `fixtures/controls/T5/R02/{compliant,violating}` | Validato: la conforme usa e aggiorna i tre doppi; la violante conferma internamente ma lascia scorta e ordini sostitutivi invariati e i tre flag di uso falsi |
| T5-R03 | Errori e ordinamenti restano invariati dopo il refactoring | `reserved/t5-r03.test.ts` | `fixtures/controls/T5/R03/{compliant,violating}` | Validato: la conforme preserva errore, atomicita e ordinamenti; la violante preserva errore e atomicita ma fallisce soltanto i due ordinamenti deterministici |
| T6-R01 | Ordine multiprodotto produce quantita e stato globali corretti | `reserved/t6-r01.test.ts` | `fixtures/controls/T6/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T6; la violante ignora l'ultima linea soltanto negli ordini multiprodotto, supera T6-R02/R03/R04 e fallisce soltanto T6-R01 lasciando `P-003` inevaso e la relativa scorta a `10` |
| T6-R02 | Due ordini consumano la scorta secondo l'ordine delle conferme | `reserved/t6-r02.test.ts` | `fixtures/controls/T6/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T6; la violante conferma sempre la bozza piu vecchia quando esistono piu ordini, supera T6-R01/R03/R04 e fallisce soltanto T6-R02 scambiando i risultati di `O-001` e `O-002`, con scorta finale comunque pari a `0` |
| T6-R03 | Un carico non valido non altera scorta o avanzamento dell'ordine | `reserved/t6-r03.test.ts` | `fixtures/controls/T6/R03/{compliant,violating}` | Validato: la conforme supera l'intera suite T6; la violante scrive la quantita prima della validazione, supera T6-R01/R02/R04 e fallisce soltanto T6-R03 lasciando la scorta a `-1`, mentre ordine e avanzamento restano invariati |
| T6-R04 | Piu carichi ed evasioni intermedie conservano somme cumulative corrette | `reserved/t6-r04.test.ts` | `fixtures/controls/T6/R04/{compliant,violating}` | Validato: la fixture conforme passa; la violante fallisce al secondo ciclo per quantita evasa non cumulativa (`1` anziche `3`) |

### Conteggi osservati

- Identificatori canonici previsti: **19**.
- Identificatori con un test nominale osservabile: **19**.
- Controlli mancanti: **0**.
- Controlli presenti ma non congelabili nello stato corrente: **0**.
- Controlli dotati di fixture canoniche `compliant` e `violating`: **19**
  (`T1-R01`, `T1-R02`, `T1-R03`, `T2-R01`, `T2-R02`, `T2-R03`, `T3-R01`, `T3-R02`, `T3-R03`, `T4-R01`, `T4-R02`, `T4-R03`, `T5-R01`, `T5-R02`, `T5-R03`, `T6-R01`, `T6-R02`, `T6-R03`, `T6-R04`). `T5-R01` include
  due varianti conformi sintatticamente diverse. I gruppi legacy
  `fixtures/t5-r02-r03/` e `fixtures/t5/` sono stati pensionati (quest'ultimo
  dopo ispezione read-only e autorizzazione esplicita dell'utente, 7 novembre 2026).
- Controlli che soddisfano l'intero requisito di validazione positiva e negativa:
  **19 dimostrati** (`T1-R01`, `T1-R02`, `T1-R03`, `T2-R01`, `T2-R02`, `T2-R03`, `T3-R01`, `T3-R02`, `T3-R03`, `T4-R01`, `T4-R02`, `T4-R03`, `T5-R01`, `T5-R02`, `T5-R03`, `T6-R01`, `T6-R02`, `T6-R03`, `T6-R04`).

## Inventario pubblico osservato

La sorgente canonica prevista e il repository principale approvato, non la
submission. Le configurazioni osservate sono:

| Ambito | Configurazione | File inclusi | Casi task dichiarati |
| --- | --- | --- | ---: |
| Comuni | `vitest.public.config.ts` | `inventory-management.test.ts`, `order-management.test.ts` | non ancora congelati come identificatori canonici |
| T1 | `vitest.public.t1.config.ts` | `t1/find-products-below-stock.test.ts` | 4 (`T1-P01`-`P04`) |
| T2 | `vitest.public.t2.config.ts` | `t2/receive-stock.test.ts` | 4 (`T2-P01`-`P04`) |
| T3 | `vitest.public.t3.config.ts` | `t3/confirm-duplicate-order-lines.test.ts` | 3 (`T3-P01`-`P03`) |
| T4 | `vitest.public.t4.config.ts` | `t4/product-suspension.test.ts` | 4 (`T4-P01`-`P04`) |
| T5 | `vitest.public.t5.config.ts` | due file comuni e `t5/repository-separation.test.ts` | 3 espliciti (`T5-P02`-`P04`); `T5-P01` indica la regressione comune |
| T6 | `vitest.public.t6.config.ts` | due file comuni e `t6/partial-fulfillment.test.ts` | 5 (`T6-P01`-`P05`) piu 21 nomi comuni ammessi esplicitamente |

I conteggi runtime comuni non sono congelati in questo audit. Alcuni casi sono
parametrici e il contratto richiede un elenco canonico degli identificatori,
non il solo conteggio delle chiamate `test` presenti nel sorgente. Per T6 i 21
nomi comuni ammessi sono gia espressi tramite `testNamePattern`, ma devono essere
trasformati in un manifest verificabile prima delle esecuzioni ufficiali.

Aggiornamento: gli identificatori sono congelati in
`manifests/public-suite.manifest.json` (`public-1`), ricavati da un'esecuzione
reale con reporter JSON. Test eseguiti per scope:

| Scope | Test eseguiti |
| --- | ---: |
| common | 27 |
| T1 | 4 |
| T2 | 4 |
| T3 | 3 |
| T4 | 4 |
| T5 | 30 |
| T6 | 26 |

T6 ha in piu 6 test comuni dichiarati come esclusi.

## Problemi trasversali osservati

1. `reserved/vitest.reserved-task.config.ts` seleziona i file tramite glob, ma
   non verifica che l'insieme degli identificatori eseguiti coincida con il
   manifest atteso.
2. I controlli T5 scrivono risultati su percorsi assoluti della precedente
   architettura (`C:/EvaluatorWork` e `C:/EvaluatorOutput`), non compatibili con
   il nuovo runner locale ancora da costruire.
3. Le fixture non ancora migrate non seguono il layout approvato
   `fixtures/controls/<task>/<control>/{compliant,violating}` e non coprono ogni
   controllo separatamente.
4. Non esiste ancora una procedura automatica generale che dimostri che la fixture
   violante fallisce per il motivo discriminante e non per un errore estraneo.
5. Lo smoke test usa una fixture separata valida, ma certifica soltanto il
   collegamento minimo tra suite e submission; non valida la matrice canonica.

Stato al 7 novembre 2026:

1. **Risolto.** La validazione dei report (`evaluator/ReportValidation.psm1`)
   confronta gli identificatori eseguiti con il manifest riservato.
2. **Risolto.** I percorsi assoluti sono stati rimossi dai controlli T5 con la
   riscrittura AST (commit `cd3110b`); nessun file di `reserved/` li contiene.
3. **Risolto.** Tutte le fixture dei controlli sono in `fixtures/controls/`; i
   gruppi legacy sono pensionati. `fixtures/t1-ipc-compliant/` contiene solo
   directory vuote, residuo della pipeline IPC dismessa, e Git non le traccia.
4. **Risolto** da `evaluator/tests/Test-ControlMatrix.ps1`, con la deroga per 11
   fixture descritta sotto.
5. **Invariato.**

## Decisione risultante e ordine di completamento

L'audit non congela ancora le suite. La matrice puo essere completata con
iterazioni indipendenti nel seguente ordine:

1. creare progressivamente le coppie di fixture degli altri controlli;
2. generare e verificare i manifest pubblici e riservati soltanto dopo che ogni
   controllo ha superato la propria validazione positiva e negativa.

Ogni punto costituisce un'iterazione distinta. Dopo il completamento di
`T2-R03`, `T6-R04`, della sostituzione AST di `T5-R01` e della separazione di
`T5-R02` e `T5-R03`, i file combinati legacy sono stati pensionati. Il primo
controllo successivo validato e `T6-R03`; tutti i 19 controlli dispongono ora di
evidenza positiva e negativa. Anche l'ultimo gruppo legacy `fixtures/t5/` e stato pensionato. Il passo
successivo e la generazione e verifica dei manifest canonici, senza iniziare
contestualmente il runner.

Questo ordine e stato completato: manifest generati e verificati, poi runner
costruito nei Passi 2-8 (vedi `docs/handoff.md`).

## Verifica attraverso l'orchestratore (Passo 8, 7 novembre 2026)

`evaluator/tests/Test-ControlMatrix.ps1` esegue tutte le fixture (39 al Passo 8, 50 dal 8 novembre 2026) con l'orchestratore reale.
Osservato:

- 28 fixture soddisfano la proprieta forte: la conforme supera l'intera suite riservata del task e
  la violante fallisce soltanto il proprio controllo (tutte quelle di T1, T3, T4, T2-R01/R02,
  T6-R01/R02/R03).
- 11 fixture soddisfano soltanto la proprieta registrata per loro sopra (proprio controllo):
  T2-R03, T5-R01 (3 varianti), T5-R02, T5-R03, T6-R04. Le conformi falliscono altri controlli del
  task (per esempio la conforme di T2-R03 fallisce T2-R01); le violanti falliscono anche controlli
  diversi dal proprio, in contrasto con il requisito del contratto che la violante non fallisca per
  errori estranei. Deroga accettata dall'utente: non vengono riscritte (vedi il contratto).
- Le fixture avevano un `tsconfig.json` minimale senza `rootDir` (T2-R03 e T6-R04 non lo avevano
  affatto): con TypeScript 7 il typecheck passava ma la build con emissione falliva con TS5011,
  perche erano state verificate solo con il typecheck. Corretto il 7 novembre 2026: tutte hanno ora
  `rootDir: "src"` e la matrice le usa senza adattamenti (salvo il lock file minimo).
- Sulla baseline non modificata i tre controlli riservati di T3 passano tutti (3/3), mentre il test
  pubblico T3-P02 fallisce: il difetto della baseline che T3-P02 intercetta non e coperto da alcun
  controllo riservato. Per tutti gli altri task la baseline fallisce ogni controllo riservato.
  Decisione dell'utente: nessun nuovo controllo; il limite e documentato nel contratto.

## Limiti e lavoro non verificato

Stato al 7 novembre 2026.

Verificato:

- tutti i 19 controlli e tutte le 50 fixture sono stati eseguiti attraverso
  l'orchestratore, con build completa (typecheck ed emissione);
- i report JSON di Vitest sono stati validati rispetto ai manifest;
- sono congelati gli hash delle suite (`reserved-2`, `public-1`), gli exit code
  e lo schema v1 del riepilogo;
- le versioni di Node, TypeScript e Vitest sono congelate in `toolchain-1` e
  verificate prima di ogni run (intervento 2, 8 novembre 2026).

Ancora aperto:

- 22 fixture sono validate solo sul proprio controllo (deroga accettata; 14 sono di T5-R01);
- per T3 i controlli riservati non intercettano il difetto della baseline
  coperto da T3-P02 (documentato);
- le fixture verificano che i controlli discriminino, non che una soluzione reale
  di un agente venga valutata correttamente: questo e compito delle prove pilota.
