# Ralph Parallel Claim Protocol

## Purpose

Prevent multi-agent collisions by enforcing deterministic claim ownership and transition rules for runnable issues during and after migration away from label-driven claim state.

This protocol defines Linear-visible ownership only. Dispatch leases, worker heartbeats, and standalone vs orchestrated scheduler ownership are defined separately in `dispatch-protocol.md`.

## Canonical Claim State

Claim state is determined by status, owner, and resumable handoff context.

- readiness is structural-first with migration fallback: structural readiness checks, excluding `Human Required`; `Ralph` + `PRD Ready` may be used only as temporary compatibility fallback
- active claim is represented by `In Progress` plus exactly one owner (`assignee` preferred, `delegate` allowed)
- blocked-human claim state is represented by `Human Required`
- review/terminal state is represented by the configured Linear status flow

Legacy claim labels remain optional compatibility aliases only:

- `Ralph Queue`
- `Ralph Claimed`
- `Ralph Completed`

These labels are deprecated. Their absence must not block `populate-project`, `audit-project`, or `ralph-run`, and they must never be used as readiness gates.

## Compatibility Mode

During migration, legacy claim labels may still appear on issues or be mirrored for older automations.

- When present, they should reflect the canonical claim state.
- When absent, claim safety is still fully determined from status/owner/handoff semantics.
- `ralph-run` selection must ignore them.
- `audit-project` may report contradictory legacy labels, but must not fail solely because the labels are missing.

## Ownership Model

- Ownership identity is represented by `assignee` (preferred) or `delegate`.
- Exactly one owner may actively hold an `In Progress` claim at a time.
- No worker may claim an issue already in `In Progress` under a different owner.
- If legacy label `Ralph Claimed` is present, it must agree with the canonical active owner state.

## Claim Lifecycle

1. Queue / Ready
   - Preconditions: readiness-eligible (structural readiness pass, no `Human Required`; migration fallback may use `Ralph` + `PRD Ready`)
   - Optional compatibility alias: `Ralph Queue`
2. Claim
   - Set state to `In Progress`
   - Set owner (`assignee`/`delegate`)
   - Post claim comment with lane and owner
   - Optional compatibility aliases: add `Ralph Claimed`, remove `Ralph Queue`
3. Heartbeat
   - Worker posts progress comments with a UTC timestamp
4. Success
   - `independent`: move to `Needs Review` (or terminal done policy)
   - `human-in-the-loop`: keep issue in the active execution state until in-loop review/unknown resolution completes, then move directly to terminal done policy without an interim `Needs Review` checkpoint
   - Optional compatibility aliases: add `Ralph Completed`, remove `Ralph Claimed`
5. Failure or Ambiguity
   - Keep `In Progress` only when active remediation is ongoing
   - In `human-in-the-loop`, use `Human Required` only when work is blocked on out-of-band human input rather than an in-loop review step
   - Add `Human Required`
   - Optional compatibility aliases: remove `Ralph Claimed`; add `Ralph Queue` only when the issue becomes automation-eligible again

## Stale-Claim Recovery

- A claim is stale when all are true:
  - issue state is `In Progress`
  - the issue still has an active owner or legacy `Ralph Claimed` alias
  - no heartbeat/update comment from the active owner for 24h
- Recovery action:
  - post stale-claim recovery comment
  - clear owner if unavailable
  - remove legacy `Ralph Claimed` if present
  - add legacy `Ralph Queue` only when readiness gates pass and a legacy integration still consumes it

## Conflict Detection

Flag as critical when:

- issue is `In Progress` with no owner
- issue has multiple ownership signals (`assignee` and conflicting `delegate`)
- issue is `In Progress` and `Human Required` simultaneously without explicit blocked-hand-off intent
- legacy `Ralph Claimed` exists without an owner or while canonical state is not active
- more than one issue-level claim event is posted by different owners without release

## Audit Alignment

- `audit-project` must validate active-owner safety, stale-claim recovery, and compatibility-label contradictions.
- `ralph-run` must claim before work and release claim state on terminal transition, but claim safety must not depend on deprecated claim labels.
