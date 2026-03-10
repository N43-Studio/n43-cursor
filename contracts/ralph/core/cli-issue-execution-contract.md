# CLI Issue Execution Contract

This contract defines the canonical one-issue invocation used by `scripts/ralph-run.sh`.

## Intent

- Execute exactly one Linear `Issue` per CLI invocation.
- Keep invocation and result payloads machine-readable.
- Make retry and human handoff behavior deterministic.

## Invocation

Ralph runners invoke a CLI agent with file-based JSON I/O:

```bash
<agent-cmd> --input-json <path> --output-json <path>
```

Rules:

- `--input-json` and `--output-json` are required.
- Input file MUST exist and be valid JSON.
- Output file MUST be written before process exit.
- Output JSON MUST validate against `schema/cli-issue-execution-result.schema.json`.

## Required Input Payload

Input payload is a JSON object with:

- `contract_version` (string): must be `1.0`.
- `iteration` (integer): 1-based run iteration.
- `issue` (object):
  - `id` (string): Linear issue identifier (for example `N43-407`).
  - `title` (string)
  - `description` (string)
  - `priority` (integer or null)
  - `linear_issue_id` (string or null)
- `execution_context` (object):
  - `branch` (string): target branch name.
  - `repo_root` (string): absolute repo path.
  - `workdir` (string): working directory for issue execution.
  - `autocommit` (boolean)
  - `sync_linear` (boolean)
- `validation_expectations` (array[string]): ordered checks to run (for example `["lint","typecheck","test","build"]`).
- `artifacts` (object):
  - `run_log_path` (string): optional sidecar destination; empty string means sidecar disabled.
  - `progress_path` (string)
  - `result_path` (string)

## Result Payload

The CLI agent MUST write a JSON object matching `schema/cli-issue-execution-result.schema.json`.

Required semantics:

- `outcome`:
  - `success`: issue work completed; `exit_code` must be `0`.
  - `failure`: issue not complete; `exit_code` must be non-zero.
  - `human_required`: work paused for review/input; `exit_code` must be `20`.
- `failure_category` must be set for non-success outcomes.
- `retryable` indicates whether deterministic retry is allowed without new human input.
- `handoff_required` must be `true` when `outcome=human_required`.
- `handoff` must be populated when `handoff_required=true`.

## Failure Categories

Allowed `failure_category` values:

- `validation_failure`: test/lint/typecheck/build failure from deterministic checks.
- `implementation_error`: issue implementation incomplete or incorrect.
- `ambiguous_requirements`: requirements unclear; human input required.
- `transient_infrastructure`: network/tooling/transient environment failure.
- `tool_timeout`: execution timed out.
- `tool_contract_violation`: input or output contract violation.
- `unknown`: fallback when category cannot be narrowed.

## Exit Code Semantics

- `0`: success.
- `10`: non-retryable failure (`outcome=failure`, `retryable=false`).
- `11`: retryable failure (`outcome=failure`, `retryable=true`).
- `20`: human handoff required (`outcome=human_required`, `handoff_required=true`).
- `30`: contract violation (missing/invalid input or output schema mismatch).

The result payload remains the source of truth; exit code must agree with payload fields.

## Deterministic Retry And Handoff Rules

- Retry is allowed only when `retryable=true` and `failure_category` is not `ambiguous_requirements`.
- `retry_after_seconds` provides a deterministic backoff delay. Omit or set `0` for immediate retry eligibility.
- When `handoff_required=true`, runner must not auto-retry the issue until human follow-up clears the handoff condition.
- Handoff payload must include:
  - `assumptions_made`
  - `questions_for_human`
  - `impact_if_wrong`
  - `proposed_revision_plan`

## Run-Level Resume Semantics

- The runner must persist loop state after every iteration in `loop-state.json`.
- Resume mode must restore at least:
  - executed iteration count
  - blocked issue set
  - cumulative token usage
  - last iteration metadata
- Active non-stale runs must reject resume to prevent concurrent execution.
- Stale-running state may be resumed after configured stale threshold.
- Iteration journal (`run-log.jsonl`) remains append-only across resume boundaries.

## Canonical vs Sidecar Artifacts

- `progress.txt` is canonical for loop progress signaling.
- `run-log.jsonl` is a structured sidecar and may be disabled.
- Completion detection and loop control must not require sidecar availability.

## Compatibility

- Contract is tool-agnostic and valid for local terminal runs and CI runners.
- Version changes require a new `contract_version` and schema update in the same change set.
