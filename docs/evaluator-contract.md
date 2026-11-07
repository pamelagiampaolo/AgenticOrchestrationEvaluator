# Contratto del valutatore esterno

## Stato del documento

- Fase: completamento del progetto dei test esterni, Passo 0.
- Stato: decisioni approvate dall'utente il 7 novembre 2026.
- Scopo: congelare input, output, criteri di successo e confini del nuovo
  evaluator locale prima di implementarlo.
- Fuori perimetro: questo documento non implementa runner, test o report.

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

L'entry point del futuro evaluator deve ricevere almeno:

```powershell
Invoke-Evaluation.ps1 `
    -SubmissionPath <directory-BenchmarkTarget> `
    -TaskId T1
```

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

Ogni run conserva almeno:

```text
runs/<runId>/
|-- input/
|   |-- submission/
|   |-- submission-manifest.json
|   `-- metadata.json
|-- raw/
|   |-- build.stdout.txt
|   |-- build.stderr.txt
|   |-- public-report.json
|   |-- public.stdout.txt
|   |-- public.stderr.txt
|   |-- reserved-report.json
|   |-- reserved.stdout.txt
|   `-- reserved.stderr.txt
`-- evidence/
    `-- evaluation-summary.json
```

La copia di lavoro temporanea non e parte delle evidenze e viene rimossa soltanto
dopo che report e manifest sono stati acquisiti. I dati persistenti non includono
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
processo corrente per limiti di permesso. Il futuro evaluator deve usare un
metodo leggibile senza privilegi elevati e registrare `unavailable` se un campo
non puo essere acquisito; non deve inventare valori.

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

Prima delle esecuzioni ufficiali devono essere congelati:

- manifest della baseline;
- manifest dei test pubblici per task;
- manifest dei test riservati per task;
- elenco e conteggio degli identificatori attesi;
- esclusioni comuni applicabili a T6;
- versioni degli strumenti;
- schema JSON del riepilogo.

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

Restano intenzionalmente da determinare mediante i passi successivi:

- inventario definitivo e conteggi canonici delle suite;
- versioni ufficiali dell'ambiente dopo le prove pilota;
- versione definitiva dello schema JSON dopo l'uso del runner reale (la v1 e
  stata definita ma non ancora prodotta da un runner);
- integrazione con l'orchestratore principale.
