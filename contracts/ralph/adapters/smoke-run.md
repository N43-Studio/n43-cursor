# Cursor/Codex Parity Smoke Run

Date: 2026-03-04

## Objective

Demonstrate one-to-one parity between Cursor slash commands and Codex skill wrappers for the Ralph shared command set.

## Scope

- Mapping source: `contracts/ralph/adapters/mapping.md`
- Codex wrappers:
  - `skills/ralph-create-project/SKILL.md`
  - `skills/ralph-populate-project/SKILL.md`
  - `skills/ralph-generate-prd-from-project/SKILL.md`
  - `skills/ralph-audit-project/SKILL.md`
  - `skills/ralph-run/SKILL.md`

## Checks

1. Every command in mapping exists in Cursor and Codex columns.
2. Every Codex skill in mapping has a wrapper `SKILL.md`.
3. Each Codex wrapper references:
   - its command contract in `core/commands/`
   - `core/shared-validations.md`
   - `adapters/mapping.md`
4. Terminology remains `Issue` for Linear work items in Ralph contracts/skills.

## Result

- `create-project`: PASS
- `populate-project`: PASS
- `generate-prd-from-project`: PASS
- `audit-project`: PASS
- `ralph-run`: PASS

Overall parity status: PASS
