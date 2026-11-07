# Evaluator

La precedente implementazione basata su Windows Sandbox e stata rimossa per
consentire la costruzione pulita di un evaluator locale coerente con il modello
di fiducia corrente.

L'architettura dismessa e documentata in
`docs/archive/windows-sandbox-evaluator.md`. Il nuovo evaluator dovra conservare
integrita degli input, timeout, validazione dei report e tracciabilita delle
evidenze senza dipendere obbligatoriamente dalla virtualizzazione.

Il contratto approvato del nuovo evaluator e definito in
`docs/evaluator-contract.md`. L'implementazione deve procedere per passi
verificabili a partire dall'audit della matrice dei controlli.

## Manifest della suite riservata

`manifests/reserved-suite.manifest.json` (versione `reserved-1`) congela i 39 file
di `reserved/` con SHA-256 (CRLF normalizzato in LF) e i 19 test attesi per task,
piu il test smoke. Gli identificatori sono ricavati da `vitest list --json`.

```powershell
# Verifica (exit 0 coerente, 1 differenze, 2 errore dello strumento)
.\evaluator\Test-ReservedManifest.ps1 -ToolsNodeModulesPath <percorso-node_modules-con-vitest>
# Rigenerazione: solo per una nuova versione della suite
.\evaluator\New-ReservedManifest.ps1 -ToolsNodeModulesPath <percorso> -Force
```

Senza `-ToolsNodeModulesPath` la verifica controlla solo file e hash e lo dichiara.
Una modifica ai test riservati richiede una nuova `suiteVersion`, non un
aggiornamento retroattivo.
