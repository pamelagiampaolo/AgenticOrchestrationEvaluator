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

The evaluator currently expects the main repository at
`C:\Users\Utente\TesiAgenticAI`. This path is configured in the host-side
PowerShell scripts.
