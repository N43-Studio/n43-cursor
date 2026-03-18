# Issue Creation Delegation Contract

This contract defines delegated, non-blocking Linear issue creation for Ralph workflows.

## Intent

- Keep the main Ralph iteration loop focused on issue execution.
- Queue issue-creation intents deterministically.
- Process creation intents in delegated worker mode with idempotency keys.
- Preserve replacement-child runnability during umbrella-issue decomposition.

## Artifacts

- Intent queue (append-only JSONL):
  - default: `.cursor/ralph/<project-slug>/issue-creation-intents.jsonl`
- Result ledger (append-only JSONL):
  - default: `.cursor/ralph/<project-slug>/issue-creation-results.jsonl`

## Intent Record Shape

Each queue row is a JSON object:

- `intent_id` (string): unique enqueue identifier.
- `dedup_key` (string): deterministic idempotency key.
- `created_at` (ISO timestamp).
- `status` (string): currently `pending`.
- `payload` (object): deterministic issue-creation payload.

When an intent represents decomposition of a superseded umbrella issue, payload must include:

- `supersedes_issue_id` (string): umbrella issue being replaced.
- `decomposition_guardrails` (object):
  - `require_children_runnable_before_parent_terminalization` (boolean, must be `true`)
  - `forbid_sub_issue_link_to_superseded_parent` (boolean, must be `true`)
  - `allowed_replacement_link_types` (array[string], expected values: `related`, `blockedBy`, `blocks`)
  - `preferred_parent_terminal_state` (string, expected value: `done`)

## Result Record Shape

Each result row is a JSON object:

- `timestamp` (ISO timestamp)
- `intent_id` (string)
- `dedup_key` (string)
- `outcome` (enum): `created` | `failed`
- `issue_id` (string, when created)
- `issue_url` (string|null, when created)
- `error` (string, when failed)

## Idempotency

- `dedup_key` is authoritative.
- Enqueue must skip when a matching pending intent already exists.
- Enqueue must skip when a matching successful result already exists.
- Worker must skip already-created dedup keys from result ledger.

## Non-Blocking Runtime Rule

- Main issue execution loop must not block per iteration on issue creation calls.
- Delegated processing may run after loop iterations and must not invalidate completed issue execution results.
- Delegated worker failures are reported in run summary but do not retroactively fail unrelated processed issues.

## Decomposition Safety Rule

When replacing umbrella issues with narrower child slices, delegated flows must follow this canonical order:

1. Create replacement child issues first.
2. Keep replacements runnable (`Human Required` absent, non-terminal status).
3. Link replacements via `related`/dependency edges, not parent/sub-issue hierarchy to the superseded umbrella.
4. Terminalize the superseded umbrella only after replacement children are confirmed runnable.
5. Prefer `Done` for superseded umbrella closure; avoid `Canceled` while active replacements remain.

## Retrospective Improvement Source

- Retrospective pipelines may enqueue issue-creation intents derived from `retrospective.json`.
- Only `critical` and `major` improvements should auto-enqueue by default.
- Minor improvements remain in retrospective output unless explicitly configured otherwise.
- Retrospective-derived intents must include deterministic dedup keys (for example, content-hash based source keys).

## Completion Reporting

Run summaries should include delegated creation outcomes:

- intents processed
- created count
- failed count
- created issue identifiers
