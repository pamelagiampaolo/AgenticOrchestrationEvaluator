# Audit della matrice canonica dei controlli

## Stato del documento

- Data: 7 novembre 2026.
- Fase: completamento del progetto dei test esterni, Passo 1.
- Scopo: confrontare il contratto approvato con i controlli, le configurazioni e
  le fixture realmente presenti prima di modificare suite o runner.
- Fonti: `docs/evaluator-contract.md`, `docs/evaluation-threat-model.md`,
  `reserved/`, `fixtures/` e le suite pubbliche presenti in
  `C:\Users\Utente\TesiAgenticAI\BenchmarkTarget`.
- Natura dell'audit: ispezione statica, aggiornata con le evidenze runtime delle
  iterazioni completate. `Presente` non significa `validato` in assenza di una
  prova positiva e negativa registrata.

## Criteri di classificazione

- **Presente da validare**: esiste un controllo dedicato coerente, per quanto
  osservabile staticamente, con il requisito dichiarato. Mancano comunque le
  fixture positiva e negativa canoniche richieste dal contratto.
- **Parziale**: esiste una parte del controllo, ma manca indipendenza, copertura
  discriminante o conformita a un vincolo esplicito del contratto.
- **Da sostituire**: l'implementazione corrente usa una tecnica esclusa dal
  contratto e non puo essere congelata come controllo canonico.
- **Mancante**: non esiste un controllo corrispondente.

Nessun controllo e classificato come `conforme`: il contratto richiede, per
ciascun identificatore, una fixture conforme, una fixture con violazione mirata
e la prova che il fallimento derivi dal requisito osservato. Tale evidenza non e
oggi disponibile per l'intera matrice.

## Matrice riservata

| ID | Proprieta discriminante prevista | Implementazione corrente | Fixture dedicate | Stato e azione necessaria |
| --- | --- | --- | --- | --- |
| T1-R01 | Soglia stretta: con soglia `5` e restituito solo `P-001` | `reserved/t1-r01.test.ts` | `fixtures/controls/T1/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T1; la violante usa `<=`, supera T1-R02/R03 e fallisce soltanto T1-R01 includendo `P-002`, la cui scorta e uguale alla soglia |
| T1-R02 | Catalogo vuoto restituisce una collezione vuota | `reserved/t1-r02.test.ts` | `fixtures/controls/T1/R02/{compliant,violating}` | Validato: la conforme supera l'intera suite T1; la violante restituisce un prodotto fantasma solo per il catalogo vuoto, supera T1-R01/R03 e fallisce soltanto T1-R02 |
| T1-R03 | La mutazione del risultato non altera lo stato interno | `reserved/t1-r03.test.ts` | `fixtures/controls/T1/R03/{compliant,violating}` | Validato con oracolo indipendente: la conforme supera l'intera suite T1; la violante espone gli oggetti interni, supera T1-R01/R02 e fallisce soltanto T1-R03 dopo la mutazione del nome restituito |
| T2-R01 | Quantita negativa o decimale fallisce senza mutazioni | `reserved/t2-r01.test.ts` | `fixtures/controls/T2/R01/{compliant,violating}` | Validato: la conforme supera l'intera suite T2; la violante aggiorna la scorta prima della validazione, supera T2-R02/R03 e fallisce soltanto T2-R01 dopo avere comunque emesso `INVALID_QUANTITY` |
| T2-R02 | Un carico sull'istanza A non modifica l'istanza B | `reserved/t2-r02.test.ts` | assenti | Presente da validare; creare positivo e violazione con stato condiviso |
| T2-R03 | Il carico modifica solo la scorta selezionata, non altre scorte o ordini | `reserved/t2-r03.test.ts` | `fixtures/controls/T2/R03/{compliant,violating}` | Validato: la fixture conforme passa; la violante fallisce per la sola modifica di `P-001` da `0` a `2` |
| T3-R01 | Duplicati non adiacenti sono aggregati correttamente | `reserved/t3-r01.test.ts` | assenti | Presente da validare; creare positivo e violazione che aggrega solo righe adiacenti |
| T3-R02 | Insufficienza tardiva lascia tutte le scorte e l'ordine invariati | `reserved/t3-r02.test.ts` | assenti | Presente da validare; creare positivo e violazione con mutazione parziale |
| T3-R03 | Tre righe duplicate al limite esatto confermano e portano la scorta a zero | `reserved/t3-r03.test.ts` | assenti | Presente da validare; creare positivo e violazione dell'aggregazione multipla |
| T4-R01 | Sospendere un prodotto inesistente fallisce senza mutazioni | `reserved/t4-r01.test.ts` | assenti | Presente da validare; creare positivo e violazione mirata |
| T4-R02 | Un ordine misto con prodotto sospeso fallisce atomicamente | `reserved/t4-r02.test.ts` | assenti | Presente da validare; creare positivo e violazione con aggiornamento parziale |
| T4-R03 | La sospensione successiva non altera un ordine storico confermato | `reserved/t4-r03.test.ts` | assenti | Presente da validare; creare positivo e violazione che lega lo storico allo stato corrente |
| T5-R01 | La logica applicativa dipende dai contratti, senza persistenza concreta interna | `reserved/t5-r01.test.ts` | `fixtures/controls/T5/R01/{compliant,violating}` con varianti interne | Validato con AST TypeScript 7: due forme conformi passano; la violante fallisce soltanto con `direct-persistence-field:ordersById` |
| T5-R02 | Factory e logica usano realmente tutti i repository sostitutivi ricevuti | `reserved/t5-r02.test.ts` | `fixtures/controls/T5/R02/{compliant,violating}` | Validato: la conforme usa e aggiorna i tre doppi; la violante conferma internamente ma lascia scorta e ordini sostitutivi invariati e i tre flag di uso falsi |
| T5-R03 | Errori e ordinamenti restano invariati dopo il refactoring | `reserved/t5-r03.test.ts` | `fixtures/controls/T5/R03/{compliant,violating}` | Validato: la conforme preserva errore, atomicita e ordinamenti; la violante preserva errore e atomicita ma fallisce soltanto i due ordinamenti deterministici |
| T6-R01 | Ordine multiprodotto produce quantita e stato globali corretti | `reserved/t6-r01.test.ts` | assenti | Presente da validare; creare positivo e violazione di allocazione multiprodotto |
| T6-R02 | Due ordini consumano la scorta secondo l'ordine delle conferme | `reserved/t6-r02.test.ts` | assenti | Presente da validare; creare positivo e violazione della priorita delle chiamate |
| T6-R03 | Un carico non valido non altera scorta o avanzamento dell'ordine | `reserved/t6-r03.test.ts` | assenti | Presente da validare; estendere la coppia di fixture al caso discriminante scelto |
| T6-R04 | Piu carichi ed evasioni intermedie conservano somme cumulative corrette | `reserved/t6-r04.test.ts` | `fixtures/controls/T6/R04/{compliant,violating}` | Validato: la fixture conforme passa; la violante fallisce al secondo ciclo per quantita evasa non cumulativa (`1` anziche `3`) |

### Conteggi osservati

- Identificatori canonici previsti: **19**.
- Identificatori con un test nominale osservabile: **19**.
- Controlli mancanti: **0**.
- Controlli presenti ma non congelabili nello stato corrente: **0**.
- Controlli dotati di fixture canoniche `compliant` e `violating`: **9**
  (`T1-R01`, `T1-R02`, `T1-R03`, `T2-R01`, `T2-R03`, `T5-R01`, `T5-R02`, `T5-R03`, `T6-R04`). `T5-R01` include
  due varianti conformi sintatticamente diverse. Resta un solo gruppo legacy sotto
  `fixtures/t5/`; il gruppo combinato `fixtures/t5-r02-r03/` e stato pensionato
  dopo la validazione indipendente di `T5-R02` e `T5-R03`.
- Controlli che soddisfano l'intero requisito di validazione positiva e negativa:
  **9 dimostrati** (`T1-R01`, `T1-R02`, `T1-R03`, `T2-R01`, `T2-R03`, `T5-R01`, `T5-R02`, `T5-R03`, `T6-R04`).

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
non il solo conteggio delle chiamate `test` presenti nel sorgente. Per T6 le 21
esclusioni positive sono gia espresse tramite `testNamePattern`, ma devono essere
trasformate in un manifest verificabile prima delle esecuzioni ufficiali.

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

## Decisione risultante e ordine di completamento

L'audit non congela ancora le suite. La matrice puo essere completata con
iterazioni indipendenti nel seguente ordine:

1. creare progressivamente le coppie di fixture degli altri controlli;
2. generare e verificare i manifest pubblici e riservati soltanto dopo che ogni
   controllo ha superato la propria validazione positiva e negativa.

Ogni punto costituisce un'iterazione distinta. Dopo il completamento di
`T2-R03`, `T6-R04`, della sostituzione AST di `T5-R01` e della separazione di
`T5-R02` e `T5-R03`, i file combinati legacy sono stati pensionati. Il primo
controllo successivo validato e `T2-R01`; il primo passo raccomandato e ora creare
e validare la coppia di fixture canoniche per `T2-R02`, senza iniziare
contestualmente il runner.

## Limiti e lavoro non verificato

- Sono stati eseguiti soltanto i test mirati `T1-R01`, `T1-R02`, `T1-R03`,
  `T2-R01`, `T2-R03`, `T5-R01`, `T5-R02`, `T5-R03` e `T6-R04`; gli altri controlli non sono stati eseguiti.
- E stata provata soltanto la compilazione delle fixture `T1-R01`, `T1-R02`,
  `T1-R03`, `T2-R01`, `T2-R03`, `T5-R01`, `T5-R02`, `T5-R03` e `T6-R04`.
- Non e stato verificato che le suite correnti producano report machine-readable
  validi.
- Non sono stati congelati hash, versioni degli strumenti, exit code o schema
  del riepilogo.
- La classificazione descrive il sorgente osservato e non certifica il
  comportamento runtime.
