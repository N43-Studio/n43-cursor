# Shared Validation Contract

This file defines validations that apply to both Cursor and Codex surfaces.

## Validation Gates

- `SV-001` Issue identity: input must include a non-empty Linear `Issue` identifier.
- `SV-002` Contract mapping: invoked surface command/skill must exist in `../adapters/mapping.md`.
- `SV-003` Sequence conformance: workflow phase order must follow `linear-workflow.md`.
- `SV-004` Terminology lock: outputs must use `Issue` terminology.
- `SV-005` Audit gate: `ralph-run` invocation requires successful `audit-project`.
- `SV-006` Readiness gate: runnable issues must pass structural readiness checks and must not include `Human Required`; during migration, `Ralph` + `PRD Ready` is allowed as a compatibility fallback when structural checks are missing; `Agent Generated` is provenance-only.
- `SV-007` Claim-state gate: runnable issues must preserve single-owner active claim semantics and stale-claim recovery. Deprecated legacy claim labels (`Ralph Queue`, `Ralph Claimed`, `Ralph Completed`) are optional compatibility markers only and must never be required for readiness or execution selection.

## Output Requirement

Each wrapper emits a normalized result with:

- `issue_id`
- `command_contract`
- `status`
- `validation_results` (list of `SV-*` checks with pass/fail)
- `schema_freshness_hash`
- `mapping_freshness_hash`

Canonical schema: `schema/normalized-result.schema.json`
