# Claim Label Deprecation Contract

## Status

**Deprecated** — active migration period.

## Purpose

Formalize the deprecation of Linear claim labels in favor of status-based claim state. This contract defines which labels are deprecated, what replaces them, migration behavior during the transition, and the timeline for full removal.

## Deprecated Labels

| Label | Former Purpose | Replacement |
|-------|---------------|-------------|
| `Ralph Queue` | Indicated issue was ready for automation pickup | Structural readiness checks (description-based) or `Ralph` + `PRD Ready` migration fallback |
| `Ralph Claimed` | Indicated a worker had claimed the issue | `In Progress` status + exactly one owner (`assignee` preferred, `delegate` allowed) |
| `Ralph Completed` | Indicated execution completed successfully | Terminal status (`Done`) per configured Linear workflow |

## What Replaces Them

Claim state is now determined entirely by Linear status, owner, and handoff context as defined in `claim-protocol.md`:

- **Readiness**: structural readiness checks per `readiness-taxonomy.md`, with `Ralph` + `PRD Ready` as a temporary migration fallback.
- **Active claim**: `In Progress` + exactly one owner.
- **Blocked-human**: `Human Required` label (not deprecated).
- **Terminal**: `Done` or `Canceled` status per `status-semantics.md`.

Deprecated claim labels are never readiness gates. Their presence or absence must not change scheduling, readiness evaluation, or claim safety outcomes.

## Migration Behavior

During the migration period:

1. **Existing labeled issues run safely.** Issues carrying deprecated claim labels alongside valid readiness signals (`structural` or `Ralph` + `PRD Ready`) continue to be scheduled normally.
2. **Labels are ignored for selection.** `scripts/ralph-run.sh` does not check for `Ralph Queue`, `Ralph Claimed`, or `Ralph Completed` in its `next_issue()` readiness evaluation.
3. **Labels may be mirrored for compatibility.** Older automations or external integrations that consume these labels may continue to receive them as optional compatibility aliases during claim lifecycle transitions (see `claim-protocol.md` lifecycle steps).
4. **Contradictions are flagged, not blocking.** `audit-project` reports contradictions between deprecated labels and canonical state (e.g., `Ralph Claimed` without an owner) but does not fail solely because labels are missing.

## Migration Steps for Existing Issues

1. Run `/linear/audit-project` with the Claim Label Deprecation Report to identify issues carrying deprecated labels.
2. For issues where structural readiness is satisfied and canonical claim state is consistent, remove deprecated labels.
3. For issues admitted only via `Ralph` + `PRD Ready` fallback, enrich descriptions to meet structural readiness before removing labels.
4. Verify with `scripts/test-ralph-claim-label-compat.sh` that the runner handles all label combinations correctly.

## Command Surface Alignment

| Command | Behavior |
|---------|----------|
| `populate-project` | Must not add deprecated claim labels to new issues. Labels exist at team level only for legacy compatibility. |
| `audit-project` | Reports deprecated label presence and contradictions via the Claim Label Deprecation Report (section E2). Absence is never a finding. |
| `ralph-run` | Ignores deprecated claim labels entirely for issue selection and readiness gating. Compatibility mirroring during claim lifecycle is optional. |

## Script Verification

`scripts/ralph-run.sh` `next_issue()` function (verified 2026-03-18):

- Structural readiness is the primary admission path. It evaluates description content signals (`Goal`, `Scope`, `Acceptance Criteria`, `Validation`, `Metadata Rationale`) without any reference to deprecated claim labels.
- Label migration fallback checks only `Ralph` + `PRD Ready` (not deprecated claim labels).
- `Ralph Queue`, `Ralph Claimed`, and `Ralph Completed` are parsed into `parse_labels` output but never appear in any readiness gate, status gate, or scheduling predicate.
- The `exclusionReason` and `scheduleDecision` fields do not reference deprecated claim labels.

Regression coverage: `scripts/test-ralph-claim-label-compat.sh`.

## Deprecation Timeline

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1: Soft deprecation** | Labels documented as deprecated. `populate-project` stops adding them to new issues. `audit-project` reports their presence. `ralph-run` ignores them. | **Current** |
| **Phase 2: Active removal** | `audit-project` in `propose-fixes` mode generates label-removal payloads. Operators remove labels from structurally-ready issues. | Next |
| **Phase 3: Full removal** | Labels are removed from team configuration. Any remaining references in contracts and compatibility code paths are cleaned up. | Future |

Phase transitions are operator-initiated via `/linear/audit-project mode=propose-fixes`. There is no automatic label removal.

## Related Contracts

- `contracts/ralph/core/claim-protocol.md` — canonical claim state and compatibility mode
- `contracts/ralph/core/readiness-taxonomy.md` — structural readiness and label taxonomy
- `contracts/ralph/core/status-semantics.md` — Linear status mapping
- `commands/linear/audit-project.md` — audit checks including section E2
- `commands/linear/populate-project.md` — issue creation label policy
- `commands/ralph/run.md` — label-independent operation documentation
