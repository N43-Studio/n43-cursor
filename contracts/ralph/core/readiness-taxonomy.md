# Ralph Readiness And Label Taxonomy

## Purpose

Define deterministic structural readiness for unattended execution, while preserving label-based compatibility during migration.

## Structural Readiness Contract

An `Issue` is structurally ready when all checks pass:

1. Description is non-empty.
2. Description includes `Goal` or `Context` framing.
3. Description includes `Scope` or implementation-plan details.
4. Description includes explicit acceptance criteria (heading and/or checklist).
5. Description includes validation expectations (section and/or `lint`/`typecheck`/`test`/`build` checks).
6. Description includes metadata rationale (section and/or explicit `priority` + `estimate` signals).
7. `Human Required` is absent.

These checks are the primary readiness gate for `ralph-run`.

Reference template: `templates/linear/prd-ready-issue.md`.

## Label Dimensions

1. Domain routing
   - `Ralph`: issue belongs to the Ralph automation domain.
2. Human intervention state
   - `Human Required`: canonical blocked-human signal; always excludes unattended execution.
3. Provenance
   - `Agent Generated`: provenance metadata only; never a readiness gate.
4. Migration compatibility
   - `PRD Ready`: compatibility alias during migration from label-driven readiness to structural readiness.

Deprecated compatibility-only claim labels:

- `Ralph Queue`
- `Ralph Claimed`
- `Ralph Completed`

## Eligibility Rule

Automation eligibility is evaluated in this order:

1. Exclude when `Human Required` is present.
2. Admit when structural readiness checks pass.
3. During migration, admit as a compatibility fallback when labels include `Ralph` and `PRD Ready`.

`Agent Generated` and deprecated claim labels must never be required for readiness.

## Default Operating Policy

- 95% default path: issues run through agent-managed structural readiness.
- 5% exception path: human-authored/human-executed work remains out of unattended flow until structurally ready.

## Metadata Expectations

Readiness and metadata remain separate:

- Structural readiness determines automation admission.
- Metadata quality determines planning/scheduling quality.

Automation-targeted issues should still follow `issue-metadata-rubric.md` and include:

- deterministic `priority`
- deterministic `estimate`
- `estimatedTokens` (recommended)
- concise `Metadata Rationale`

## Backlog Migration Policy

For existing issues:

1. Keep existing labels (`Ralph`, `PRD Ready`) while structural checks are rolled out.
2. Use `audit-project` to report structural readiness pass/fail reasons per issue.
3. Keep `PRD Ready` as a temporary compatibility path only when structural readiness is not yet satisfied.
4. Add `Human Required` for blocked or ambiguous items needing human input.
5. Remove dependence on `PRD Ready` once structural readiness adoption is complete for the project.

## Legacy Claim-Label Compatibility

`Ralph Queue`, `Ralph Claimed`, and `Ralph Completed` are deprecated compatibility aliases for older claim-state tooling.

- `populate-project` should not add them by default.
- `audit-project` should treat them as advisory compatibility signals only.
- `ralph-run` must ignore them for issue selection and readiness gating.
- When legacy labels are present, they must mirror canonical status/owner state and never override it.

## Tooling Reference

- **Standalone checker**: `scripts/check-structural-readiness.sh` — evaluates the 7 structural readiness checks against a PRD JSON file or individual issue JSON. Supports `--format text|json` output modes. Exit 0 = all ready, exit 1 = at least one not ready.
- **Operator checklist**: `contracts/ralph/core/structural-readiness-checklist.md` — maps each check to the required description content with pass/fail examples.
- **Audit integration**: `commands/linear/audit-project.md` Section C evaluates structural readiness per issue and flags label-migration fallback usage with deprecation warnings.

## Migration Timeline

Label-based readiness via `Ralph` + `PRD Ready` is a compatibility fallback only. The migration schedule:

1. **Current**: Both structural readiness and label-migration fallback are active. `audit-project` reports which path each issue uses and flags label-migration issues with deprecation warnings.
2. **Next milestone**: All new issues created by `populate-project` must satisfy structural readiness. Label fallback remains for pre-existing issues only.
3. **Final removal**: Label-migration fallback is removed from `ralph-run.sh` `next_issue()`. Issues that do not pass structural readiness are excluded regardless of labels. The `PRD Ready` label becomes provenance metadata only (like `Agent Generated`).

Operators should run `scripts/check-structural-readiness.sh` against their PRD to identify issues still relying on label fallback and add the missing structural headings before the final removal milestone.

## Command Contract Alignment

- `audit-project` validates structural readiness and reports migration-fallback usage.
- `populate-project` should generate structurally ready issue bodies and may include migration labels.
- `ralph-run` uses structural readiness first, then compatibility label fallback.
- Claim lifecycle details are defined in `claim-protocol.md`; legacy claim-label mirroring is optional compatibility behavior only.
