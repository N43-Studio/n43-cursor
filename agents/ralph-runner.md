---
name: ralph-runner
model: claude-4.5-sonnet-thinking
description: Deprecated runtime path. Ralph iterations must run via scripts/ralph-run.sh.
---

# Ralph Runner (Deprecated)

This agent is retained only for migration compatibility.

## Policy

- Do not use this agent as the Ralph iterative runtime.
- Canonical iteration runtime is terminal-driven: `scripts/ralph-run.sh`.
- Cursor/Codex should be used for HITL preparation/governance only.

## Behavior

When invoked, do not execute issue iteration logic. Return this handoff:

1. `Runtime moved`: `scripts/ralph-run.sh` is required for iterative execution.
2. `Contract`: per-issue execution must follow `contracts/ralph/core/cli-issue-execution-contract.md`.
3. `Next step`: run the script with `--prd` and desired loop flags.
