# Istruzioni operative del repository

## Scopo del progetto

Questo repository contiene il valutatore fidato e privato del progetto
`TesiAgenticAI`. Mantiene separati i controlli riservati dal repository principale
e produce, per ogni valutazione, report, log ed evidenze di integrita sotto
`runs/`.

Il software deve consentire valutazioni oggettive, riproducibili e verificabili.
Non assumere che una soluzione o una condizione sperimentale debba ottenere un
risultato migliore delle altre.

## Metodo di lavoro

1. Eseguire un solo passo completo, circoscritto e verificabile alla volta.
2. Prima di intervenire, spiegare in termini generali cosa verra fatto, perche e
   necessario e come si inserisce nel valutatore.
3. Ispezionare lo stato reale del repository prima di formulare assunzioni.
4. Prima di iniziare, verificare se servono informazioni, vincoli o decisioni non
   ancora documentati. Chiedere chiarimenti solo quando la risposta cambierebbe
   materialmente il risultato e non sia gia presente nel repository o confermata
   dall'utente.
5. Dopo ogni modifica, eseguire direttamente tutte le verifiche tecniche
   disponibili e riportare comandi, risultati osservati ed eventuali errori.
6. Chiedere una verifica manuale all'utente soltanto quando non sia tecnicamente
   eseguibile da Codex; in tal caso fornire un comando PowerShell esatto.
7. Distinguere sempre attivita completate, pianificate e ancora da verificare.
8. Non dichiarare superato un test che non sia stato realmente eseguito.
9. Fermarsi al termine del passo richiesto senza iniziare automaticamente lavori
   successivi non autorizzati.
10. Al termine indicare un messaggio di commit consigliato. Creare il commit
    soltanto dopo un'autorizzazione esplicita dell'utente.

### Iterazioni di sviluppo

Ogni implementazione deve costituire una sola iterazione circoscritta e
verificabile. Prima di modificare il codice, rendere chiari:

1. obiettivo dell'iterazione;
2. componenti coinvolti;
3. comportamento atteso;
4. criteri oggettivi di accettazione.

Al termine documentare le verifiche realmente eseguite, i risultati osservati, i
limiti e i punti non verificati. Una prova parziale certifica soltanto la
proprieta direttamente osservata, non l'intero valutatore o sistema sperimentale.

## Confini e autorizzazioni

- Non creare commit, effettuare push, pubblicare dati o modificare servizi
  esterni senza autorizzazione esplicita.
- Non introdurre dipendenze, strumenti, servizi a pagamento o cambiamenti
  architetturali importanti senza averne spiegato necessita e alternative.
- Non eliminare dati o eseguire comandi Git distruttivi senza autorizzazione.
- Preservare la separazione tra test pubblici, accessibili agli agenti
  sperimentali, e test riservati usati per la valutazione indipendente.
- Non copiare o pubblicare i test riservati nel repository principale o in altre
  aree accessibili agli agenti sperimentali.
- Non permettere al codice candidato di modificare test riservati, evidenze o
  input originali della valutazione.
- Conservare l'area fidata esterna al repository principale valutato.

## Regole di qualita del codice

Applicare queste regole a PowerShell, TypeScript e JavaScript secondo le
convenzioni idiomatiche del linguaggio:

- Mantenere funzioni, script e classi piccoli, coesi e con una responsabilita
  chiara.
- Preferire nomi descrittivi ad abbreviazioni e commenti compensativi.
- Rendere espliciti input, output, codici di uscita, errori attesi e dipendenze.
- Evitare stato globale mutabile e comportamento dipendente dall'ordine quando
  non strettamente necessario.
- Separare selezione e preparazione degli input, esecuzione dei processi,
  validazione dei report e pubblicazione delle evidenze.
- Usare tipi rigorosi; evitare `any` in TypeScript salvo motivazione documentata.
- Gestire gli errori senza nasconderli e produrre messaggi diagnostici utili che
  non espongano credenziali, percorsi riservati o contenuti privati.
- Favorire risultati deterministici. Quando interviene casualita, rendere il seed
  configurabile e registrarlo.
- Non ottimizzare prematuramente e non aggiungere astrazioni prive di un uso
  reale.
- Mantenere la compatibilita con Windows e costruire i percorsi tramite le API
  del linguaggio, evitando concatenazioni fragili.
- Validare i dati prodotti dai processi guest prima di considerarli evidenze
  affidabili.
- Distinguere con chiarezza un fallimento della soluzione da un errore del
  valutatore.

## Regole per i commenti nel codice

- Documentare script, parametri, classi, interfacce, tipi e API pubbliche nel
  formato idiomatico del linguaggio quando il loro contratto non e gia evidente.
- Per ogni API pubblica spiegare scopo, parametri, valore restituito, errori
  significativi e invarianti quando pertinenti.
- Commentare proprieta o valori quando significato, unita di misura, formato o
  vincolo non siano evidenti dal nome e dal tipo.
- Inserire commenti interni per spiegare decisioni di sicurezza, vincoli
  sperimentali e passaggi algoritmici non ovvi.
- Non scrivere commenti che ripetano letteralmente il codice. Semplificare prima
  il codice e aggiungere poi soltanto il contesto utile.
- Aggiornare o rimuovere i commenti quando cambia il comportamento relativo.

## Standard di verifica

Per ogni modifica applicabile:

1. eseguire formattazione e controlli statici disponibili;
2. verificare il parsing degli script PowerShell modificati;
3. compilare o controllare i tipi dei componenti TypeScript interessati;
4. eseguire prima i test mirati e poi quelli piu ampi pertinenti;
5. controllare che non siano comparsi artefatti generati tra i file versionabili;
6. verificare che nomi di file, riferimenti interni, configurazioni e documentazione
   siano coerenti;
7. registrare il risultato effettivo, non quello atteso.

I criteri di successo devono essere osservabili e, quando possibile,
automatizzabili. Distinguere:

- test unitari per singole unita di logica;
- test di integrazione per la collaborazione tra componenti;
- test di accettazione per i requisiti esterni della valutazione;
- prove di integrita e isolamento, che certificano soltanto le proprieta
  esplicitamente osservate.

## Integrita e validita sperimentale

Applicare il modello di fiducia e la decisione architetturale documentati in
`docs/evaluation-threat-model.md`. Non assumere che la virtualizzazione protegga
la segretezza dei test quando candidato e controlli condividono processo e
identita.

Ogni confronto deve usare lo stesso commit iniziale, gli stessi requisiti, lo
stesso ambiente, gli stessi test di valutazione e limiti comparabili. Ogni
esecuzione deve partire da una copia pulita della baseline, senza modifiche o
informazioni residue.

Per ogni valutazione:

- identificare in modo non ambiguo submission, task, suite e controlli eseguiti;
- registrare hash o manifest degli input rilevanti e verificarne l'immutabilita;
- conservare separatamente input, output grezzi, log ed evidenze elaborate;
- validare struttura e coerenza dei report prima di aggregarne i conteggi;
- registrare timeout, codici di uscita, durata ed errori del valutatore;
- non confondere test falliti, test non eseguiti ed errori infrastrutturali;
- separare sempre dati misurati, stime e interpretazioni.

Quando disponibili, registrare almeno correttezza, test superati, tempo totale,
chiamate LLM, token di input/output e cache, tentativi di correzione, errori e
overhead di coordinamento.

## Documentazione sperimentale

Per ogni passo significativo registrare data, fase, obiettivo, file modificati,
decisioni e motivazioni, comandi eseguiti, risultati osservati, problemi,
soluzioni e lavoro rimanente. Non inventare risultati, metriche o verifiche.
