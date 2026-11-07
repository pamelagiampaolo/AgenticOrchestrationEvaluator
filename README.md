# Trusted Evaluator

Private evaluation workspace for the `TesiAgenticAI` project.

The repository keeps reserved tests outside the main source repository. Its
evaluator is being rebuilt around a local controlled runner that will produce an
integrity manifest, machine-readable evidence, and execution logs under `runs/`.

## Structure

- `evaluator/`: clean starting point for the local evaluator. The retired
  Windows Sandbox architecture is documented under `docs/archive/`.
- `reserved/`: private Vitest controls and their configurations.
- `fixture/`: frozen submission used by the evaluator smoke test.
- `fixtures/`: compliant and violating submissions for architectural controls.
- `runs/`: generated evaluation inputs, outputs, and evidence (not versioned).

## Evaluator status

The previous Windows Sandbox entry points have been retired. Their behavior,
limitations, and reusable concepts are preserved in
`docs/archive/windows-sandbox-evaluator.md`. A local evaluator will replace
them incrementally, starting from the smoke test.

The evaluator currently expects the main repository at
`C:\Users\Utente\TesiAgenticAI`. This path is configured in the host-side
PowerShell scripts.

## Development handoff

The current owner, verified status, remaining work, and next authorized step are
recorded in `docs/handoff.md`. Keep that document updated whenever development
responsibility changes.
