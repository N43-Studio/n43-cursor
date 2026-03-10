# Issue Creation Delegation Contract

This contract defines delegated, non-blocking Linear issue creation for Ralph workflows.

## Intent

- Keep the main Ralph iteration loop focused on issue execution.
- Queue issue-creation intents deterministically.
- Process creation intents in delegated worker mode with idempotency keys.

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
