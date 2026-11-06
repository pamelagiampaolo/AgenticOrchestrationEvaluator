# Trusted Evaluator

Private evaluation workspace for the `TesiAgenticAI` project.

The repository keeps reserved tests outside the main source repository and runs
them in an isolated Windows Sandbox. Each evaluation produces an integrity
manifest, machine-readable evidence, and execution logs under `runs/`.

## Structure

- `evaluator/`: host and guest PowerShell evaluation scripts.
- `reserved/`: private Vitest controls and their configurations.
- `fixture/`: frozen submission used by the evaluator smoke test.
- `fixtures/`: compliant and violating submissions for architectural controls.
- `runs/`: generated evaluation inputs, outputs, and evidence (not versioned).

## Evaluator entry points

- `Invoke-EvaluatorSmokeTest.ps1`: validates the evaluator itself with the
  frozen arithmetic fixture; it does not execute a T1-T6 task.
- `Invoke-T1R01CandidateIsolationEvaluation.ps1`: executes the dedicated
  T1-R01 candidate-identity and reserved-file access proof.
- `Invoke-T5R01RepositoryArchitectureEvaluation.ps1`: executes only T5-R01,
  which checks that application logic depends on repository contracts.
- `Invoke-SelectedTaskTestSuiteEvaluation.ps1 -TaskId T1|...|T6`: selects one
  task and executes both its public suite and every matching reserved control
  (`reserved/tN-r*.test.ts`).

Each `Invoke-*` host entry point has a correspondingly named `Run-*Guest.ps1`
worker. The worker is an implementation detail and is not invoked directly by
the user.

The evaluator currently expects the main repository at
`C:\Users\Utente\TesiAgenticAI`. This path is configured in the host-side
PowerShell scripts.
