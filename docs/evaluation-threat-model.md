# Modello di fiducia dell'evaluator

## Contesto

Gli agenti sperimentali lavorano sul repository principale `TesiAgenticAI` e
non hanno accesso a questo repository fidato, ai test riservati o alle evidenze
prodotte dall'evaluator. I task consistono nello sviluppo di funzionalita di una
libreria gestionale; non fanno parte di una competizione adversarial e non viene
chiesto agli agenti di aggirare la valutazione.

## Distinzione fondamentale

La protezione del computer host e la veridicita della valutazione sono proprieta
diverse.

- L'isolamento dell'ambiente di esecuzione limita gli effetti che una submission
  difettosa o malevola puo avere sul computer host, sulla rete e sui file esterni.
- La segretezza dei controlli riservati richiede invece che il processo candidato
  non possa leggerli durante l'esecuzione.

Negli attuali flussi Vitest ordinari, test riservati e submission vengono
eseguiti nello stesso processo Node e con la stessa identita. La submission puo
quindi, in linea teorica, eseguire codice al caricamento e leggere file presenti
nell'ambiente di lavoro. L'ambiente isolato protegge l'host, ma da solo non rende
i test riservati illeggibili alla submission.

La pipeline T1 dedicata e differente: esegue il candidato con un'identita Windows
separata, applica ACL ai controlli riservati e usa un canale IPC con il runner
fidato. E questa separazione, non la sola virtualizzazione, a dimostrare il
diniego di lettura.

## Rischio concreto nel modello sperimentale

Poiche l'agente non vede questo repository durante la generazione della
soluzione e non interagisce con l'evaluator durante l'esecuzione, non puo leggere
i test riservati e poi correggere dinamicamente il proprio lavoro. Rimane
tecnicamente possibile che una submission contenga codice che esplora file,
processi o ambiente a runtime, ma questo non e un comportamento atteso dai task
di libreria e non costituisce, allo stato attuale, l'ipotesi sperimentale da
difendere.

Errori ordinari della libreria, eccezioni e cicli non terminanti possono essere
gestiti con directory temporanee, timeout, processi terminabili, manifest degli
input e validazione indipendente dei report. Queste misure non difendono da
codice intenzionalmente ostile, ma sono proporzionate a submission prodotte da
agenti limitati che svolgono task applicativi non adversarial.

## Decisione corrente

La virtualizzazione non e considerata un requisito necessario per la validita
sperimentale ordinaria del benchmark. Il valutatore deve supportare una modalita
locale controllata come percorso principale di sviluppo ed esecuzione, con:

- copia temporanea e separata della submission;
- test riservati mantenuti fuori dal repository visibile all'agente;
- timeout e terminazione del processo di test;
- input originali non modificabili e verificati tramite manifest;
- output e report trattati come dati non fidati e validati dal processo host;
- assenza di segreti o credenziali nell'ambiente del processo;
- registrazione esplicita della modalita di esecuzione nelle evidenze.

Una modalita fortemente isolata resta opzionale per eseguire submission
intenzionalmente ostili o provenienti da soggetti esterni. Non deve essere
presentata come protezione della segretezza dei test finche candidato e test
riservati condividono identita e processo.

## Conseguenze architetturali

1. L'evaluator non deve dipendere obbligatoriamente da una specifica tecnologia
   di virtualizzazione per eseguire le valutazioni ordinarie.
2. Il runner locale e il runner isolato, se mantenuto, devono condividere lo
   stesso contratto di input, output ed evidenze.
3. La pipeline T1 di separazione dell'identita e una prova di sicurezza distinta
   dai normali requisiti funzionali e non va confusa con essi.
4. L'introduzione o il mantenimento di isolamento forte deve essere giustificato
   da un threat model esplicito, non dalla sola presenza di codice generato.
5. Questa decisione va riesaminata se gli agenti ottengono accesso ai controlli,
   possono interagire durante la valutazione, ricevono strumenti di esplorazione
   dell'host oppure vengono accettate submission esterne non controllate.
