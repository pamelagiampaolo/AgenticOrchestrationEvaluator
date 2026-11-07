# Evaluator

La precedente implementazione basata su Windows Sandbox e stata rimossa per
consentire la costruzione pulita di un evaluator locale coerente con il modello
di fiducia corrente.

L'architettura dismessa e documentata in
`docs/archive/windows-sandbox-evaluator.md`. Il nuovo evaluator dovra conservare
integrita degli input, timeout, validazione dei report e tracciabilita delle
evidenze senza dipendere obbligatoriamente dalla virtualizzazione.
