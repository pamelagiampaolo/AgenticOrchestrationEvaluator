# Valutatore fidato

Area di lavoro privata per la valutazione del progetto
`Agentic Orchestration Benchmark`.

Il repository mantiene i test riservati al di fuori del repository principale
del codice sorgente. Un valutatore locale e controllato esegue le suite canoniche
pubbliche e riservate su una submission. Scrive input, report grezzi ed evidenze
validate sotto `runs/`.

## Struttura

- `evaluator/`: valutatore locale in Windows PowerShell 5.1. Il punto di ingresso
  è `Invoke-Evaluation.ps1`. I test si trovano in `evaluator/tests/` e l'utilizzo
  è descritto in `evaluator/README.md`.
- `manifests/`: manifest congelati della suite riservata (`reserved-2`), della
  baseline con le suite pubbliche (`public-2`) e delle versioni degli strumenti
  (`toolchain-1`: Node, TypeScript, Vitest). Il valutatore si arresta con
  `evaluator-error` prima di qualsiasi fase se gli strumenti non corrispondono.
- `schemas/`: schema JSON del riepilogo della valutazione.
- `reserved/`: controlli Vitest privati e relative configurazioni.
- `fixture/`: submission congelata usata dallo smoke test riservato.
- `fixtures/controls/`: submission conformi e non conformi per ciascun controllo
  riservato.
- `docs/`: contratto del valutatore, modello delle minacce, audit della matrice
  dei controlli e passaggio di consegne. La documentazione è scritta in italiano.
- `runs/`: input, output ed evidenze generati dalle valutazioni (non versionati).

## Stato del valutatore

Il valutatore è implementato e coperto da test unitari, di accettazione e della
matrice dei controlli. È stato provato con soluzioni di test e con tutte le 39
fixture dei controlli. Non è ancora stato usato per esecuzioni pilota o
valutazioni ufficiali.

La precedente architettura basata su Windows Sandbox è stata dismessa. È
documentata in `docs/archive/windows-sandbox-evaluator.md`.

Il valutatore richiede due percorsi esterni, entrambi forniti come parametri. Si
trovano in `C:\repos\AgenticOrchestrationTools`, al di fuori del repository
principale accessibile agli agenti:

- `baseline-aee8d11`: la baseline congelata di `BenchmarkTarget`;
- `C:\AgenticAIToolchain\node-v24.17.0-lock-586b704e\packages\node_modules`:
  TypeScript e Vitest della toolchain definitiva.

Questo repository non ha dipendenze proprie.

## Passaggio di consegne dello sviluppo

Il responsabile attuale, lo stato verificato, il lavoro rimanente e il prossimo
passo autorizzato sono registrati in `docs/handoff.md`. Mantenere aggiornato quel
documento a ogni cambio di responsabilità dello sviluppo.
