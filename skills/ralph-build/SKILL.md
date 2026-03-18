---
name: ralph-build
description: Codex wrapper for the Ralph build command contract. Use when running the single-entry setup flow through audit.
---

# Ralph Build Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/build.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute setup phases in canonical order:
   - `create-project`
   - `populate-project`
   - `generate-prd-from-project`
   - `audit-project`
3. Preserve artifact path defaults from the underlying command contracts.
4. Emit phase-by-phase status and actionable failure remediation.
5. Stop after audit output; do not start `ralph-run`.

## Intent Boundary

- Owns only the Ralph setup-wrapper contract phase.
- Do not use for Linear PM triage/admin workflows.
- For non-contract project/issue administration, hand off to the `linear` skill group.
