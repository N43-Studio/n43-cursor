# Plan Mode Parity Smoke Run

## Goal

Verify Cursor and Codex planning entry points produce parity with `commands/implementation/plan-feature.md`.

## Procedure

1. Use the same feature prompt in both surfaces.
2. Trigger plan-mode entry point in each surface.
3. Confirm both produce/target `plan-v{N}.md` under `.cursor/plans/{feature}/`.
4. Confirm both require explicit approval before execution.
5. Reject an initial mode-switch prompt (if shown) and verify behavior still follows the same planning flow.
6. Compare plan structure sections:
   - scope/context
   - implementation tasks
   - dependencies and risks
   - validation commands
   - execution handoff instructions

## Pass Criteria

- Same canonical planning contract referenced.
- Approval checkpoint present in both outputs.
- Rejection fallback does not bypass planning.
- Plan structure is equivalent (section-level parity).
