# Ralph Parallel Claim Protocol

## Purpose

Prevent multi-agent collisions by enforcing deterministic claim ownership and transition rules for runnable issues.

## Required Labels

- `Ralph Queue`: issue is eligible to be claimed when readiness gates pass.
- `Ralph Claimed`: issue is actively owned by one worker.
- `Ralph Completed`: issue finished execution and moved to review/completion flow.
- `Human Required`: issue is blocked on human input and is not claimable.

`Human Required` acts as the blocked-human claim state.

## Ownership Model

- Ownership identity is represented by `assignee` (preferred) or `delegate`.
- Exactly one owner may hold `Ralph Claimed` at a time.
- No worker may claim an issue already in `In Progress` under a different owner.

## Claim Lifecycle

1. Queue
   - Labels: `Ralph Queue`
   - Preconditions: readiness-eligible (`Ralph` + `PRD Ready`, no `Human Required`)
2. Claim
   - Set state to `In Progress`
   - Set owner (`assignee`/`delegate`)
   - Add `Ralph Claimed`
   - Remove `Ralph Queue`
   - Post claim comment with lane and owner
3. Heartbeat
   - Worker posts progress comments with a UTC timestamp
4. Success
   - Move to `Needs Review` (or terminal done policy)
   - Add `Ralph Completed`
   - Remove `Ralph Claimed`
5. Failure or Ambiguity
   - Keep `In Progress` only when active remediation is ongoing
   - Add `Human Required`
   - Remove `Ralph Claimed`
   - Add `Ralph Queue` only when issue becomes automation-eligible again

## Stale-Claim Recovery

- A claim is stale when all are true:
  - issue has `Ralph Claimed`
  - issue state is `In Progress`
  - no heartbeat/update comment from owner for 24h
- Recovery action:
  - post stale-claim recovery comment
  - remove `Ralph Claimed`
  - clear owner if unavailable
  - add `Ralph Queue` if readiness gates pass

## Conflict Detection

Flag as critical when:

- issue has `Ralph Claimed` with no owner
- issue has multiple ownership signals (`assignee` and conflicting `delegate`)
- issue has `Ralph Claimed` and `Human Required` simultaneously
- more than one issue-level claim event is posted by different owners without release

## Audit Alignment

- `audit-project` must validate required labels, stale claims, and conflict conditions.
- `ralph-run` must claim before work and release claim labels on terminal transition.
