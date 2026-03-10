# Cursor/Codex Parity Smoke Run

Date: 2026-03-10

## Objective

Demonstrate one-to-one parity between Cursor slash commands and Codex skill wrappers for the Ralph shared command set.
Demonstrate runtime parity policy across script, Cursor, and Codex entrypoints.

## Scope

- Mapping source: `contracts/ralph/adapters/mapping.md`
- Cursor adapter: `contracts/ralph/adapters/cursor/README.md`
- Codex adapter: `contracts/ralph/adapters/codex/README.md`
- Codex wrappers:
  - `skills/ralph-create-project/SKILL.md`
  - `skills/ralph-populate-project/SKILL.md`
  - `skills/ralph-generate-prd-from-project/SKILL.md`
  - `skills/ralph-audit-project/SKILL.md`
  - `skills/ralph-run/SKILL.md`

## Reproducible Procedure

1. Run:
   - `scripts/check-ralph-drift.sh`
2. Confirm parity checks pass:
   - `== Check: Command Parity ==`
   - `== Check: Codex Skill Boundary Routing ==`
3. Confirm each mapped command has:
   - Cursor mapping row
   - Codex mapping row
   - Codex wrapper `SKILL.md` with command contract + shared validations + mapping references
4. Confirm terminology check passes (`Issue` only).
5. Confirm runtime parity references are present in:
   - `commands/ralph/run.md`
   - `contracts/ralph/adapters/cursor/README.md`
   - `contracts/ralph/adapters/codex/README.md`
   - `contracts/ralph/core/cli-issue-execution-contract.md`

## Pass/Fail Matrix

| Command | Cursor Mapping | Codex Wrapper | Contract Wiring | Status |
| --- | --- | --- | --- | --- |
| `create-project` | `/ralph/create-project` | `ralph-create-project` | PASS | PASS |
| `populate-project` | `/ralph/populate-project` | `ralph-populate-project` | PASS | PASS |
| `generate-prd-from-project` | `/ralph/generate-prd-from-project` | `ralph-generate-prd-from-project` | PASS | PASS |
| `audit-project` | `/ralph/audit-project` | `ralph-audit-project` | PASS | PASS |
| `ralph-run` | `/ralph/ralph-run` | `ralph-run` | PASS | PASS |

Overall parity status: PASS

## Runtime Surface Parity Matrix

| Runtime Surface | Entry Point | Contract Equivalence | Status |
| --- | --- | --- | --- |
| Script | `scripts/ralph-run.sh` | Canonical engine | PASS |
| Cursor | `/ralph/ralph-run` | Adapter to canonical contract | PASS |
| Codex | `ralph-run` skill | Adapter to canonical contract | PASS |
