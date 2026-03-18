# Command Contract: `ralph-run`

## Intent

Execute deterministic Ralph issue iterations from `prd.json` after all prerequisite contract checks pass.

## Surface-Independent Semantics

`ralph-run` behavior is defined by this core contract and must be equivalent across supported runtime entrypoints:

- `scripts/ralph-run.sh`
- Cursor `/ralph/ralph-run`
- Codex `ralph-run` skill

Invocation mechanics may differ by surface, but they must not change:

- issue selection order
- stop conditions
- status/label transition semantics
- output/result shape required by shared validations

## Workflow Modes

Each runtime invocation must choose exactly one workflow mode:

- `independent`:
  - default behavior
  - preserves the existing asynchronous Linear review flow
  - intermediate review/rework may use `Needs Review`/`Reviewed` plus `review-feedback-sweep-contract.md`
- `human-in-the-loop`:
  - resolve unknowns and review checks inside the active execution cycle
  - keep issue progress in the active claim/execution state until review or clarification is complete
  - do not require interim `Needs Review` transitions solely for mid-execution clarification/review

Mode selection is a runtime input and must remain contract-equivalent across:

- `scripts/ralph-run.sh`
- Cursor `/ralph/ralph-run`
- Codex `ralph-run`

`workflow_mode` is orthogonal to dispatch ownership. Standalone vs orchestrated dispatch is defined separately in `../dispatch-protocol.md`.

## Dispatch Ownership Boundary

`ralph-run` must preserve one canonical dispatch boundary across all surfaces:

- `standalone` dispatch:
  - current default behavior
  - `scripts/ralph-run.sh` owns selection, retries, and local run-state artifacts
  - no external queue/lease authority exists beyond Ralph local artifacts
- `orchestrated` dispatch:
  - external orchestration may own queue admission, leases, heartbeats, and cross-worker retry coordination
  - per-issue execution must still use `../cli-issue-execution-contract.md`
  - Linear-visible claim/state semantics must still use `../claim-protocol.md` and `../status-semantics.md`

Dispatch ownership must not change workflow semantics. It only changes where dispatch/lease state lives and who schedules the next worker attempt.

## Preconditions

- `audit-project` completed with a pass result.
- When preflight question-scan findings exist, unresolved `critical`/`major` items are acknowledged before unattended execution.
- All required execution inputs are present and traceable.
- `scripts/ralph-run.sh` is the canonical runtime entrypoint.
- Per-issue invocation uses `../cli-issue-execution-contract.md`.
- Dispatch payload/lifecycle semantics use `../dispatch-protocol.md`.
- Delegated issue creation semantics use `../issue-creation-delegation-contract.md`.
- Reviewed-state feedback sweep semantics use `../review-feedback-sweep-contract.md`.
- Post-run retrospective semantics use `../retrospective-contract.md`.
- Status gating semantics follow `../status-semantics.md`.
- Model routing policy is available at `../model-routing-policy.default.json`.
- Model routing rubric semantics follow `../model-routing-rubric.md`.
- Stage model strategy follows `../stage-model-strategy.md`.
- Runnable issues satisfy structural readiness semantics from `../readiness-taxonomy.md`, with label migration fallback (`Ralph` + `PRD Ready`) when structural checks are not yet present.
- Runnable issues satisfy claim safety semantics with exactly one active owner at claim time when Linear sync is enabled.
- Deprecated claim labels (`Ralph Queue`, `Ralph Claimed`, `Ralph Completed`) are optional compatibility aliases only and must not affect deterministic selection or readiness gating.

## Postconditions

- Each selected issue is executed exactly once per iteration through the CLI issue execution contract.
- Execution result is recorded with status and associated Linear `Issue`.
- Output metadata is sufficient for parity checks across control surfaces.
- Each issue attempt appends a structured `run-log.jsonl` entry for retrospective/calibration consumers.
- Loop state is persisted every iteration for deterministic resume (`.cursor/ralph/<project>/loop-state.json` or explicit override path).
- Ambiguity requiring human input is recorded with structured assumptions and resumable revision context.
- Retry eligibility is explicit and deterministic (`retryable`, `retry_after_seconds`, `failure_category`).
- Stale running state is detected before resume; resume proceeds only when state is stale or explicitly non-running.
- `progress.txt` is canonical for run progress signaling; structured sidecars are optional and must not gate completion detection.
- Delegated issue-creation intents are handled via queue/worker flow and must not block per-iteration issue execution.
- Reviewed-state feedback sweep may requeue issues between iterations in `independent` mode and must not block unrelated runnable issues.
- Post-run retrospective generation must execute before run completion reporting and remain non-blocking on failure.
- Critical/major retrospective improvements may enqueue delegated issue-creation intents using deterministic dedup keys before worker processing.
- Each iteration records scheduling rationale (policy tuple + candidate diagnostics) for traceability.
- Readiness diagnostics include source (`structural` vs `label_migration`) and structural signal detail for explainability.
- Each iteration records deterministic model-routing decision (`selectedTier`, `selectedModel`, confidence, factors, fallback status).
- Quality-gated retry/escalation behavior is deterministic and bounded (`max_retries_per_issue`), with human-required handoff after high-tier failure or retry exhaustion.
- When audit preflight scan reports unresolved `critical` human-question risk, execution start is blocked until resolved or explicitly overridden by operator policy.
- When unresolved `major` preflight risk exists, execution emits explicit warning context and requires operator acknowledgement in unattended mode.
- Workflow mode selection is persisted in run state and propagated into each per-issue CLI execution payload.
- Dispatch mode, when explicitly represented by a runtime surface, must not be inferred from `workflow_mode` and must preserve the ownership boundary defined in `../dispatch-protocol.md`.
- Legacy claim labels, when still present on migrated issues, remain non-blocking compatibility metadata and do not change scheduling order or readiness outcomes.

## Deterministic Selection Policy

When selecting the next issue, apply gates and ordering in this exact order:

1. Pending gate: `passes != true`
2. Run-local block gate: not present in current blocked issue set
3. Dependency gate: all `dependsOn` issues are passed
4. Readiness gate:
   - exclude `Human Required`
   - pass when structural readiness checks succeed
   - otherwise allow migration fallback when labels include `Ralph` + `PRD Ready`
5. Status gate: exclude non-runnable states (`Triage`, `Needs Review`, `Reviewed`, `Done`, `Canceled`)
6. Ranking:
   - Linear priority ascending (`1` most urgent)
   - estimate ascending
   - issue identifier ascending (stable tie-break)

Scheduling outputs must include:

- selected issue tuple (`priority`, `estimate`, gate status)
- policy identifier string
- candidate diagnostics (pending/runnable counts and exclusion counts by reason)

## Deterministic Model Routing Policy

Before dispatching issue execution, route each issue to a model tier using deterministic signals:

1. issue metadata (`priority`, `estimate`)
2. dependency depth
3. description complexity
4. risk indicators (keywords/flags, including `Human Required`)
5. historical failure signal from run-log for the same issue

Routing output must include:

- selected tier (`low` | `medium` | `high`)
- selected model name
- score and confidence
- factor breakdown and rationale list
- explicit fallback indicator when required signals are missing

Routing thresholds/weights must be configurable via policy file without code changes.

Retry/escalation semantics:

- Prior failure count raises minimum tier floor (`low` -> `medium` -> `high`).
- Retries per issue are bounded by `max_retries_per_issue`.
- Failure at `high` tier transitions the issue to human-required escalation path.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (execution respects core semantics).
- `WF-INV-003` Ordered transitions (phase 5 terminal action).
- `WF-INV-004` Traceability (result linked to `Issue`).
- `WF-INV-005` Validation gate (requires successful audit).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (structural readiness drives eligibility; labels are migration compatibility only).
- `WF-INV-008` Claim safety (single-owner claim lifecycle with stale recovery).
- `WF-INV-009` Status semantics (deterministic status lifecycle and review requeue behavior).

## Contract Artifacts

- CLI invocation and payload semantics: `../cli-issue-execution-contract.md`
- Dispatch payloads and ownership boundary: `../dispatch-protocol.md`
- CLI result schema: `../schema/cli-issue-execution-result.schema.json`
- Delegated issue creation: `../issue-creation-delegation-contract.md`
- Review feedback sweep: `../review-feedback-sweep-contract.md`
- Retrospective generation: `../retrospective-contract.md`
- Model routing rubric: `../model-routing-rubric.md`
- Model routing policy: `../model-routing-policy.default.json`
- Stage model strategy: `../stage-model-strategy.md`
- Preflight question-scan rubric: `../preflight-question-scan-rubric.md`
