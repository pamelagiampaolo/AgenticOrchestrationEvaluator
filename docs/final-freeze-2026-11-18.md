# Freeze finale dell'evaluator — 18 novembre 2026

## Stato

Configurazione candidata verificata; il commit definitivo deve essere ricavato
dopo il commit di queste modifiche. Nessuna valutazione pilota o ufficiale è
autorizzata da questo documento.

## Input congelati

- baseline pubblica: `C:\repos\AgenticOrchestrationTools\baseline-aee8d11`;
- commit dichiarato: `aee8d1162bb496895990a00095cc14c2651ff752`;
- toolchain: `C:\AgenticAIToolchain\node-v24.17.0-lock-586b704e\packages\node_modules`;
- manifest pubblico: `public-2`, SHA-256
  `dc5f7dbb2d4e8d8811e6e5335391f76199b7b1c1c1ba0635059672317abc7e5b`;
- manifest riservato invariato: `reserved-2`, SHA-256
  `ce05f45cb2e93ee0e499abd86102cf8e8c2505f7029c83b099c8ddeecb8bad09`;
- schema del riepilogo, SHA-256
  `4ddc434c343db376516db44423e33c1e3da1d9f124e158c5d57a135366f537bf`.

La baseline contiene 19 file verificati contro il manifest sorgente del
benchmark. I file riservati non sono stati modificati, copiati nel benchmark o
esposti alle aree agente.

## Modifiche

- nuova versione `public-2` del manifest pubblico;
- parametro `-DeclaredCommit` per conservare la provenienza di una baseline
  estratta senza metadati `.git`;
- percorsi operativi aggiornati nei README;
- helper di accettazione adattato a rendere scrivibili soltanto le proprie copie
  temporanee della baseline, lasciando protetta la baseline fidata.

## Verifiche osservate

- manifest pubblico: coerente, identificatori verificati;
- manifest riservato: coerente, identificatori verificati;
- test di accettazione: `20/20` superati;
- matrice dei controlli: 50 fixture, 51 controlli, zero fallimenti;
- parser PowerShell dei tre file modificati: superato;
- `git diff --check`: superato.

Il primo test di accettazione si era fermato dopo due controlli perché la copia
temporanea ereditava l'attributo di sola lettura dalla nuova baseline. La
correzione riguarda esclusivamente la fixture; la ripetizione completa ha
superato tutti i 20 controlli.

## Passo rimanente

Dopo il commit, registrare l'object ID completo come versione definitiva
dell'evaluator usata dai sei nuovi piloti e dalle successive run ufficiali.
