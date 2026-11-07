# Passaggio di consegne

## Stato del passaggio

- Data: 7 novembre 2026.
- Responsabile operativo successivo: Claude.
- Commit di riferimento: `5cbc11a` (`test: complete reserved control matrix with T6-R03`).
- Working tree al momento del passaggio: pulito.
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

Questi risultati certificano i singoli controlli e le proprieta direttamente
osservate. Non certificano ancora un'esecuzione end-to-end del valutatore.

## Stato non ancora completato

- Non esistono ancora manifest canonici congelati per le suite pubbliche e
  riservate.
- Il runner locale generale non e ancora implementato.
- Report machine-readable, schema JSON, exit code, timeout e verifiche generali
  di integrita non sono ancora congelati o validati end-to-end.
- Resta un gruppo di fixture legacy sotto `fixtures/t5/`.
- Prettier non risultava disponibile nell'ambiente usato per le verifiche.
- Vitest/Vite emette un avviso non bloccante sulle configurazioni TypeScript con
  sintassi ESM caricate come CommonJS e sul futuro `configLoader: native`.

## Prossimo passo autorizzato

Il prossimo passo e esclusivamente un'ispezione read-only di `fixtures/t5/`:

1. inventariare tutti i file del gruppo legacy;
2. cercare riferimenti in configurazioni, test e documentazione;
3. confrontarne la copertura con T5-R01, T5-R02 e T5-R03 canonici;
4. stabilire se il gruppo e completamente sostituito;
5. riportare gli esatti file candidati alla rimozione.

L'ispezione era stata avviata ma interrotta dall'utente prima di produrre
risultati; il comando era read-only e non ha modificato il repository.

Qualsiasi eliminazione richiede una nuova autorizzazione esplicita dell'utente.
Dopo l'eventuale pensionamento del gruppo legacy, il passo pianificato e la
generazione e verifica dei manifest canonici, non l'avvio automatico del runner.

## Verifiche richieste alla ripresa

Prima di intervenire:

1. eseguire `git status --short`;
2. confrontare `git log -5 --oneline` con il commit indicato sopra;
3. leggere integralmente `AGENTS.md`, questo documento, il contratto, il threat
   model e l'audit;
4. non assumere che lo stato sia rimasto invariato se Claude ha aggiunto commit;
5. distinguere sempre lavoro completato, pianificato e non verificato.
