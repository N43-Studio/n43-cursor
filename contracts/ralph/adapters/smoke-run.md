# Cursor/Codex Parity Smoke Run

Date: 2026-03-10

## Objective

Demonstrate one-to-one parity between Cursor slash commands and Codex skill wrappers for the Ralph shared command set.

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

## Pass/Fail Matrix

| Command | Cursor Mapping | Codex Wrapper | Contract Wiring | Status |
| --- | --- | --- | --- | --- |
| `create-project` | `/ralph/create-project` | `ralph-create-project` | PASS | PASS |
| `populate-project` | `/ralph/populate-project` | `ralph-populate-project` | PASS | PASS |
| `generate-prd-from-project` | `/ralph/generate-prd-from-project` | `ralph-generate-prd-from-project` | PASS | PASS |
| `audit-project` | `/ralph/audit-project` | `ralph-audit-project` | PASS | PASS |
| `ralph-run` | `/ralph/ralph-run` | `ralph-run` | PASS | PASS |

Overall parity status: PASS
