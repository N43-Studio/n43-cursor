# Linear Status Semantics

This document defines canonical Linear status behavior for Ralph workflow lifecycle decisions.

## Status Mapping

| Linear Status | Auto-Selectable For New Work | Ralph Behavior |
| --- | --- | --- |
| `Backlog` | No | Planned but not yet admitted to active automation queue. |
| `Triage` | No | Incomplete/uncertain issue definition; blocked from execution. |
| `In Progress` | Conditional | Active execution or active human-followup loop. Select only for explicit resume/revision ownership, not new claim. |
| `Needs Review` | No | Iteration complete, awaiting human review decision. |
| `Reviewed` | Conditional | Review decision state: either accepted terminal completion or explicit requeue for rework. |
| `Done` | No | Terminal issue completion state. |
| `Canceled` | No | Terminal non-execution state. |

## Selection Rules

- New automation selection defaults to issues not in active/terminal review states:
  - exclude `Triage`, `Needs Review`, `Done`, `Canceled`
  - treat `In Progress` as non-selectable unless resume policy explicitly applies
- Status checks are combined with label/readiness checks (`Ralph`, `PRD Ready`, absence of `Human Required`).

## Review-Cycle Semantics

- `Needs Review` -> `Reviewed`:
  - If accepted: mark terminal completion (`Done` policy by team configuration).
  - If changes requested: reopen into runnable flow by restoring readiness labels/queue semantics and setting non-terminal state.
- `Reviewed` with rework required must include explicit requeue action so automation can pick it back up deterministically.

## Audit Requirements

`audit-project` must verify:

- Required statuses exist and are unambiguous for the team.
- Status transitions used by Ralph are mappable to deterministic behavior.
- Review-cycle behavior (`Needs Review` -> `Reviewed` -> done/requeue) is explicit and automation-safe.
