# Trusted Evaluator

Private evaluation workspace for the `TesiAgenticAI` project.

The repository keeps reserved tests outside the main source repository. A
local, controlled evaluator runs the canonical public and reserved suites against
a submission. It writes inputs, raw reports and validated evidence under `runs/`.

## Structure

- `evaluator/`: local evaluator in Windows PowerShell 5.1. The entry point is
  `Invoke-Evaluation.ps1`. Tests are in `evaluator/tests/`, and usage is described
  in `evaluator/README.md`.
- `manifests/`: frozen manifests of the reserved suite (`reserved-1`), of the
  baseline plus public suites (`public-1`) and of the tool versions
  (`toolchain-1`: Node, TypeScript, Vitest). The evaluator stops with
  `evaluator-error` before any phase if the tools do not match.
- `schemas/`: JSON schema of the evaluation summary.
- `reserved/`: private Vitest controls and their configurations.
- `fixture/`: frozen submission used by the reserved smoke test.
- `fixtures/controls/`: compliant and violating submissions for each reserved control.
- `docs/`: evaluator contract, threat model, control-matrix audit and handoff.
  The documentation is written in Italian.
- `runs/`: generated evaluation inputs, outputs, and evidence (not versioned).

## Evaluator status

The evaluator is implemented and covered by unit, acceptance and control-matrix
tests. It has been exercised with test solutions and with all 39 control
fixtures. It has not yet been used for pilot runs or official evaluations.

The previous Windows Sandbox architecture is retired. It is documented in
`docs/archive/windows-sandbox-evaluator.md`.

The evaluator needs two external locations, both passed as parameters. They are
kept in `C:\repos\TesiEvaluatorTools`, outside the main repository that
agents can access:

- `baseline-ddf08e8`: the frozen `BenchmarkTarget` baseline;
- `tools\node_modules`: TypeScript and Vitest.

This repository has no dependencies of its own.

## Development handoff

The current owner, verified status, remaining work, and next authorized step are
recorded in `docs/handoff.md`. Keep that document updated whenever development
responsibility changes.
