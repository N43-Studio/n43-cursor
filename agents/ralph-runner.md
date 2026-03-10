---
name: ralph-runner
model: claude-4.5-sonnet-thinking
description: Deprecated legacy subagent path. Use parity runtime entrypoints instead.
---

# Ralph Runner (Deprecated)

This agent is retained only for legacy compatibility.

## Policy

- Do not use this agent as the Ralph iterative runtime.
- Supported runtime entrypoints are:
  - `scripts/ralph-run.sh`
  - Cursor `/ralph/run`
  - Codex `ralph-run` skill

## Behavior

When invoked, do not execute issue iteration logic. Return this handoff:

1. `Runtime moved`: this subagent path is deprecated; use one of the supported parity runtime entrypoints.
2. `Contract`: per-issue execution must follow `contracts/ralph/core/cli-issue-execution-contract.md`.
3. `Next step`: run the script with `--prd` and desired loop flags.
