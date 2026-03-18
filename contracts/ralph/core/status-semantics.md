# Linear Status Semantics

This document defines canonical Linear status behavior for Ralph workflow lifecycle decisions.

## Status Mapping

| Linear Status | Auto-Selectable For New Work | Ralph Behavior |
| --- | --- | --- |
| `Backlog` | No | Planned but not yet admitted to active automation queue. |
| `Triage` | No | Incomplete/uncertain issue definition; blocked from execution. |
| `In Progress` | Conditional | Active execution or active human-followup loop. In `human-in-the-loop`, keep work here while in-loop review/unknown resolution is active. |
| `Needs Review` | No | `independent` mode async review checkpoint. Do not use as an interim clarification/review checkpoint in `human-in-the-loop`. |
| `Reviewed` | Conditional | Review decision state: either accepted terminal completion or explicit requeue for rework. |
| `Done` | No | Terminal issue completion state. |
| `Canceled` | No | Terminal non-execution state. |

## Selection Rules

- New automation selection defaults to issues not in active/terminal review states:
  - exclude `Triage`, `Needs Review`, `Done`, `Canceled`
  - treat `In Progress` as non-selectable unless resume policy explicitly applies
- Status checks are combined with structural readiness checks and absence of `Human Required`; `Ralph` + `PRD Ready` remains a migration-only fallback signal.

## Workflow Mode Semantics

- `independent`:
  - preserve the current async Linear review cycle
  - `Needs Review` -> `Reviewed` remains the canonical human review path
  - reviewed-state requeue behavior uses `review-feedback-sweep-contract.md`
- `human-in-the-loop`:
  - resolve review checks and unknowns inside the active execution cycle when possible
  - keep issues in `In Progress`/active claim state until review or clarification is complete
  - avoid interim `Needs Review` transitions for mid-execution clarification/review
  - use `Human Required` only when the active cycle is genuinely blocked waiting on out-of-band human input

## Review-Cycle Semantics

- `Needs Review` -> `Reviewed`:
  - If accepted: mark terminal completion (`Done` policy by team configuration).
  - If changes requested: reopen into runnable flow by restoring structural readiness requirements and any optional migration-label/legacy-claim-label aliasing needed for compatibility, then set a non-terminal state.
- `Reviewed` with rework required must include explicit requeue action so automation can pick it back up deterministically.
- Review queue processing semantics follow `review-queue-contract.md` with deterministic decision outcomes and mandatory structured comments.

## Needs Human Label Semantics

- Canonical label is `Human Required`.
- `Needs Human` may be treated as an alias in review-queue selection for backward compatibility.
- Queue processors must normalize either label to the same rework/triage handling behavior.

## Audit Requirements

`audit-project` must verify:

- Required statuses exist and are unambiguous for the team.
- Status transitions used by Ralph are mappable to deterministic behavior.
- Review-cycle behavior (`Needs Review` -> `Reviewed` -> done/requeue) is explicit and automation-safe.
- Review-queue processing for `Needs Review` + `Needs Human`/`Human Required` is deterministic and auditable.
- Workflow mode semantics are documented so operators know when async review vs in-loop review is expected.
