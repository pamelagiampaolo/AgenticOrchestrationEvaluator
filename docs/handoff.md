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

- Esiste il manifest canonico della suite riservata (`manifests/reserved-suite.manifest.json`,
  `reserved-1`). Esiste anche `manifests/public-suite.manifest.json` (baseline e suite pubbliche,
  `public-1`, commit baseline dichiarato `ddf08e8`). Manca un manifest degli
  strumenti (versioni di Node, npm, TypeScript, Vitest) e del lock file come voce a parte.
- Il runner locale generale non e ancora implementato.
- Report machine-readable, schema JSON, exit code, timeout e verifiche generali
  di integrita non sono ancora congelati o validati end-to-end.
- `fixtures/t1-ipc-compliant` esiste su disco ma non e tracciato da Git; non ispezionato.
- Prettier non risultava disponibile nell'ambiente usato per le verifiche.
- Vitest/Vite emette un avviso non bloccante sulle configurazioni TypeScript con
  sintassi ESM caricate come CommonJS e sul futuro `configLoader: native`.

## Prossimo passo

Il 7 novembre 2026 `fixtures/t5/` e stato ispezionato (nessun riferimento da
test o configurazioni, tutti i file diversi dalle fixture canoniche, violazione
legacy coperta da T5-R01 AST) e rimosso con `git rm -r` su autorizzazione
dell'utente. Verifica eseguita in copia temporanea (Vitest di `BenchmarkTarget`):
T5-R01 passa con entrambe le fixture conformi e fallisce con `direct-persistence`;
T5-R02 e T5-R03 passano con le conformi e falliscono con le violanti.

Dopo il commit `69b860e` e stato aggiunto il manifest della suite riservata
(`evaluator/ReservedManifest.psm1`, `New-ReservedManifest.ps1`,
`Test-ReservedManifest.ps1`). Verificato: generazione deterministica (due
generazioni con hash identico), caso positivo exit 0, e exit 1 per hash
modificato, file rimosso, file extra e `test.skip`; exit 0 con CRLF; exit 2 per
manifest assente. Limite: `vitest list` non elenca i test saltati, quindi
skip/todo vanno rilevati anche nei report del futuro runner.

Manifest della baseline e delle suite pubbliche (`evaluator/PublicManifest.psm1`,
`New-PublicManifest.ps1`, `Test-PublicManifest.ps1`, `ManifestCommon.psm1`; il
modulo riservato e stato rifattorizzato sul modulo comune e rigenerato con output
identico). Verificato: generazione deterministica, positivo exit 0, exit 1 per
src modificato, test aggiunto, file extra, config rimossa e manifest alterato
(test inesistente, test spostato tra eseguiti/esclusi, conteggio incoerente),
exit 2 per manifest assente e baseline senza tsconfig. Limiti: la baseline
fallisce i test di task per costruzione, quindi il manifest non certifica nessuna
soluzione; i nomi non sono stati confrontati con una soluzione corretta.

Passo 2 completato: schema JSON del riepilogo (`schemas/evaluation-summary.schema.json`),
tabella esiti/exit code, precedenza tra cause e validazione in
`evaluator/EvaluationSummary.psm1`, test in `evaluator/tests/Test-EvaluationSummary.ps1`
(54 asserzioni superate). Verificato anche che i test falliscono se la validazione
e disattivata (34 falliti) o se la tabella degli exit code viene alterata (3).
Limiti: lo schema non e ancora prodotto da un runner reale; il validatore copre
solo il sottoinsieme di JSON Schema usato; i codici sono una proposta di questo
passo, documentata nel contratto e da confermare.

Passo 3 completato: ingresso del runner (`evaluator/EvaluationInput.psm1`,
`Initialize-EvaluationRun.ps1`, test in `evaluator/tests/Test-EvaluationInput.ps1`,
44 asserzioni superate). Decisioni da confermare: esclusione di `node_modules` e
`dist`, rifiuto di symlink/junction, hash a byte esatti, "immutabile" = sola
lettura + manifest (dettagli nel contratto). Mutazioni di controllo: senza
controllo dei collegamenti (3 falliti), senza esclusioni (crash e 3 falliti),
senza sola lettura (3 falliti), senza `RunsRoot` annidato (2 falliti), senza
verifica del sorgente (1 fallito). Limite: non e coperto dai test che
`New-EvaluationRun` chiami davvero `Assert-RunInputIntegrity`; la funzione e
testata da sola. Non verificati: percorsi molto lunghi, caratteri speciali nei
nomi dei file, concorrenza di piu run.

Passo 4 completato: fase di build (`evaluator/ProcessRunner.psm1`, `BuildPhase.psm1`,
`Invoke-BuildPhase.ps1`, test in `evaluator/tests/Test-BuildPhase.ps1`, 29 asserzioni
superate con TypeScript reale e compilatori simulati). Decisioni da confermare nel
contratto (sezione "Fase di build"). Mutazioni di controllo rilevate: ambiente non
ripulito, timeout per passo invece che complessivo, ogni codice non nullo come
`failed`; albero dei processi non terminato verificato in modo mirato (il discendente
resta vivo). NON discriminata dai test: l'eliminazione esplicita della junction in
`Remove-EvaluationWorkspace`, perche in questo ambiente (PowerShell 5.1.26100)
`Remove-Item -Recurse` non attraversa le junction (verificato con directory
usa-e-getta); resta come precauzione. Incidente di processo: una mutazione senza
terminazione dell'albero ha lasciato processi orfani che bloccavano la pulizia; ho
chiuso solo quelli del mio test (catena dei PID) e rimosso la sola directory temporanea
creata. Non verificati: output molto grandi (nessun limite di dimensione dei log),
percorsi con caratteri speciali di cmd (`&`, `%`), emissioni di `tsc` fuori dalla copia
di lavoro diverse da `--outDir`, versioni degli strumenti non ancora registrate.

Passo 5 completato: fasi di test pubblica e riservata (`evaluator/TestPhases.psm1`,
`Invoke-TestPhase.ps1`, test in `evaluator/tests/Test-TestPhases.ps1`, 25 asserzioni
superate con Vitest reale e Vitest simulato). `ProcessRunner` ora accetta variabili
d'ambiente aggiuntive ed espone `Add-StepLog` (usato anche dalla fase di build).
Decisioni da confermare nel contratto (sezione "Fasi di test"). Mutazioni di
controllo rilevate: test pubblici non sostituiti (il test va in errore), hash
canonici non verificati, nessuna riverifica dei file riservati (2 falliti), exit 1
senza report come `failed`, scope comune sempre eseguito, tutti i file riservati
copiati. Per la soluzione reale di T1 ho costruito nel test la baseline piu
`findProductsBelowStock`: e codice di prova, non una soluzione sperimentale. Limiti:
nessuna validazione dei report rispetto ai manifest (passo 6); `passed` di fase non
certifica che i test attesi siano stati eseguiti; la cache di Vitest viene scritta
dentro le dipendenze canoniche; nessun limite di dimensione dei log; reserved e
submission condividono processo e identita (accettato dal threat model).

Passi successivi pianificati: (6) validazione dei report rispetto ai manifest;
(7) test di accettazione e isolamento end-to-end; (8) riconciliazione documentale.
Non avviare il runner senza nuova autorizzazione.
Nota: Vitest non e installato in questo repository; per le prove si e usato
`node_modules` di `C:\Users\Utente\TesiAgenticAI\BenchmarkTarget`.

## Verifiche richieste alla ripresa

Prima di intervenire:

1. eseguire `git status --short`;
2. confrontare `git log -5 --oneline` con il commit indicato sopra;
3. leggere integralmente `AGENTS.md`, questo documento, il contratto, il threat
   model e l'audit;
4. non assumere che lo stato sia rimasto invariato se Claude ha aggiunto commit;
5. distinguere sempre lavoro completato, pianificato e non verificato.
