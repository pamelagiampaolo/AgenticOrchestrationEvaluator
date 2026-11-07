# Archivio del precedente evaluator Windows Sandbox

## Stato

Questa architettura e stata rimossa dal percorso operativo del progetto. Il
documento ne conserva responsabilita, componenti e decisioni utili per eventuali
analisi future. Non costituisce la specifica del nuovo evaluator locale.

La rimozione non riguarda i test funzionali e architetturali in `reserved/`, le
fixture ordinarie o gli artefatti storici gia presenti in `runs/`.

## Motivazione della dismissione

Il precedente evaluator richiedeva obbligatoriamente Windows Sandbox e la CLI
`wsb.exe`. Il threat model corrente non considera le submission codice
intenzionalmente ostile: gli agenti lavorano sul repository principale, non
vedono questo repository e svolgono task applicativi di libreria.

La virtualizzazione proteggeva il computer host, ma nei flussi Vitest ordinari
non proteggeva la segretezza dei test riservati: test e submission venivano
eseguiti nello stesso processo Node, con la stessa identita e accesso allo stesso
filesystem interno. La complessita introdotta non forniva quindi la principale
proprieta di validita che sembrava promettere.

La decisione completa e mantenuta in `docs/evaluation-threat-model.md`.

## Struttura rimossa

L'implementazione era divisa in entry point host e worker guest:

```text
evaluator/
|-- host/
|   |-- Invoke-EvaluatorSmokeTest.ps1
|   |-- Invoke-SelectedTaskTestSuiteEvaluation.ps1
|   |-- Invoke-T1R01CandidateIsolationEvaluation.ps1
|   `-- Invoke-T5R01RepositoryArchitectureEvaluation.ps1
`-- guest/
    |-- Run-EvaluatorSmokeTestGuest.ps1
    |-- Run-SelectedTaskTestSuiteGuest.ps1
    |-- Run-T1R01CandidateIsolationGuest.ps1
    |-- Run-T5R01RepositoryArchitectureGuest.ps1
    `-- T1CandidateProcess.mjs
```

La prova T1 utilizzava inoltre:

```text
reserved/t1-r01-ipc-runner.ps1
fixtures/t1-ipc-compliant/src/index.mjs
```

## Modello host/guest precedente

Gli script `Invoke-*`:

1. individuavano Node, dipendenze e `wsb.exe`;
2. creavano `runs/<runId>/worker-input`, `worker-output` ed `evidence`;
3. copiavano submission, test, runtime e worker;
4. calcolavano un manifest SHA-256 della submission;
5. generavano una configurazione Windows Sandbox;
6. avviavano l'ambiente e richiamavano il worker come `System`;
7. arrestavano l'ambiente;
8. validavano report, manifest e stato finale;
9. producevano `evaluation-summary.json`.

La configurazione disabilitava rete, clipboard, periferiche e redirezioni non
necessarie. L'input veniva montato in sola lettura e l'output in scrittura.

Gli script `Run-*Guest.ps1`:

1. copiavano gli input da `C:\EvaluatorInput` a `C:\EvaluatorWork`;
2. avviavano Node e Vitest;
3. scrivevano report e log in `C:\EvaluatorOutput`;
4. registravano codici di uscita, durata e presenza di interfacce di rete.

## Flussi precedenti

### Smoke test

`Invoke-EvaluatorSmokeTest.ps1` e `Run-EvaluatorSmokeTestGuest.ps1` eseguivano
`reserved/smoke.test.ts` su una fixture aritmetica nota. Verificavano il
funzionamento di base dell'infrastruttura, la produzione del report e
l'immutabilita dell'input.

### Suite selezionata

`Invoke-SelectedTaskTestSuiteEvaluation.ps1` e il relativo worker eseguivano la
suite pubblica e tutti i controlli riservati corrispondenti al `TaskId` scelto.
Aggregavano i conteggi e deduplicavano alcune coperture condivise.

Il flusso dichiarava supporto T1-T6, ma selezionava sempre una submission da
`fixtures/t5-r02-r03`. Anche il `probeId` era specifico di T5-R02-R03. Questa
incoerenza deve essere evitata nel nuovo evaluator.

### Controllo dedicato T5-R01

`Invoke-T5R01RepositoryArchitectureEvaluation.ps1` e il relativo worker
eseguivano soltanto `reserved/t5-r01.test.ts` sulle fixture T5 conformi e
violating. Gran parte dell'orchestrazione duplicava lo smoke test e la suite
selezionata.

### Prova d'isolamento T1-R01

La pipeline T1 era una prova di sicurezza distinta dai normali test funzionali:

- creava un account Windows candidato;
- applicava ACL differenti a runtime, candidato, controlli e output fidato;
- avviava un runner fidato e un processo candidato separato;
- comunicava tramite named pipe;
- verificava il risultato funzionale, l'identita del candidato e il diniego di
  lettura del controllo riservato.

`T1CandidateProcess.mjs` importava la submission, eseguiva la richiesta,
controllava la propria identita e tentava intenzionalmente di leggere il file
riservato. `t1-r01-ipc-runner.ps1` gestiva il lato fidato del protocollo.

Questa pipeline e stata rimossa dal prodotto principale perche certificava un
threat model non richiesto dalla valutazione ordinaria.

## Parti concettuali da recuperare

Il nuovo evaluator locale puo riutilizzare queste idee senza recuperare la
dipendenza da Windows Sandbox:

- run identificati univocamente;
- layout separato per input, output ed evidenze;
- manifest SHA-256 prima e dopo l'esecuzione;
- timeout e terminazione del processo;
- stdout e stderr conservati;
- report JSON considerati non fidati e validati dall'host;
- distinzione fra test falliti ed errore dell'evaluator;
- conteggi pubblici e riservati verificati e aggregati;
- identificazione esplicita di submission, task e controlli eseguiti.

## Parti da non reintrodurre implicitamente

- dipendenza obbligatoria da `wsb.exe`;
- percorsi guest fissi come `C:\EvaluatorInput` e `C:\EvaluatorOutput`;
- copia completa di `node_modules` per ogni esecuzione senza una necessita
  misurata;
- duplicazione dello stesso ciclo di orchestrazione in piu entry point;
- fixture T5 incorporate in un comando dichiarato generale;
- associazione tra virtualizzazione e segretezza dei test senza separazione di
  processo e identita;
- commistione tra requisiti funzionali e prove sperimentali di sicurezza.

## Recuperabilita del codice

Il contenuto sorgente precedente resta recuperabile dalla cronologia Git del
repository. Questo archivio mantiene intenzionalmente la conoscenza
architetturale e non incorpora centinaia di righe di PowerShell obsolete.
