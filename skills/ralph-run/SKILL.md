---
name: ralph-run
description: Codex wrapper for the Ralph ralph-run command contract. Use when executing Ralph workflow after audit-project passes.
---

# Ralph Run Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/ralph-run.md`
- CLI issue execution contract: `contracts/ralph/core/cli-issue-execution-contract.md`
- CLI result schema: `contracts/ralph/core/schema/cli-issue-execution-result.schema.json`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-005` from shared validations.
2. Invoke `scripts/ralph-run.sh` as the canonical iterative runtime.
3. Preserve the selected workflow mode (`independent` or `human-in-the-loop`) with semantics equivalent to Cursor `/ralph/ralph-run` and script entrypoints.
4. Emit normalized output fields required by shared validations with semantics equivalent to Cursor `/ralph/ralph-run` and script entrypoints.

## Intent Boundary

- Owns only the Ralph execution/runtime contract phase.
- Do not use for Linear PM triage/admin workflows.
- For non-contract project/issue administration, hand off to the `linear` skill group.
