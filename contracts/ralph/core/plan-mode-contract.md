# Plan Mode Contract

## Intent

Keep planning behavior deterministic across Cursor and Codex by routing plan-mode requests through the same canonical planning command contract:

- `commands/implementation/plan-feature.md`

## Entry Point Routing

Both surfaces must route planning intents (for example, "plan mode", "create implementation plan", "switch to planning") to `plan-feature` semantics before any execution phase.

## Required Checkpoints

Before execution (`/implementation/execute` or equivalent), both surfaces must enforce:

1. Plan document is created.
2. Plan summary is presented.
3. Explicit human approval is captured.

Execution without explicit approval is contract-invalid.

## Mode-Switch Rejection Behavior

If an explicit mode switch is unavailable or rejected:

- Stay in current runtime mode.
- Continue using `plan-feature` planning methodology and output structure.
- Do not skip planning or approval checkpoints.

## Output Parity Requirements

Plan outputs must keep consistent structure across surfaces:

- Plan artifact path/version (`.cursor/plans/{feature}/plan-v{N}.md`)
- Task breakdown and complexity signals
- Dependencies/risks/validation commands
- Clear handoff to execution command after approval

## Verification

Parity verification procedure is documented in:

- `contracts/ralph/adapters/plan-mode-smoke-run.md`
