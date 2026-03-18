> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Wrapper is HITL orchestration around a deterministic terminal script runtime -->

# Run Ralph (Multi-Surface Runtime Wrapper)

Run Ralph by invoking the canonical deterministic script:

`scripts/ralph-run.sh`

`/ralph/run` is a runtime entrypoint that maps to the same canonical iteration contract used by script and Codex surfaces.

Surface behavior is contract-equivalent to script and Codex entrypoints:

- issue selection order
- stop conditions
- status/label transition semantics
- shared-validation output/result shape

`workflow_mode` controls review behavior only. Standalone vs orchestrated dispatch ownership is defined separately in `contracts/ralph/core/dispatch-protocol.md`.

## Input

`$ARGUMENTS` supports:

- `prd=<path>` (required)
- `max=<number>` (default: `5`)
- `usage_limit=<number>` (optional)
- `autocommit=true|false` (default: `true`)
- `sync_linear=true|false` (default: `false`)
- `workflow_mode=independent|human-in-the-loop` (default: `independent`)
- `resume=true|false` (default: `false`)
- `stale_after_seconds=<number>` (default: `1800`)
- `max_retries_per_issue=<number>` (default: `3`)
- `agent_cmd=<command>` (default: `scripts/configured-issue-agent.sh`)
- `progress=<path>` (default: `progress.txt`)
- `run_log=<path|none>` (default: `run-log.jsonl`; set `none` to disable sidecar)
- `loop_state=<path>` (default: `.cursor/ralph/<project-slug>/loop-state.json`)
- `issue_intent_queue=<path>` (default: `.cursor/ralph/<project-slug>/issue-creation-intents.jsonl`)
- `issue_intent_results=<path>` (default: `.cursor/ralph/<project-slug>/issue-creation-results.jsonl`)
- `process_issue_intents=true|false` (default: `true`)
- `issue_intent_worker_cmd=<command>` (default: `scripts/issue-intent-worker.sh`)
- `review_feedback_events=<path>` (default: `.cursor/ralph/<project-slug>/review-feedback-events.jsonl`)
- `review_feedback_state=<path>` (default: `.cursor/ralph/<project-slug>/review-feedback-state.json`)
- `process_review_feedback_sweep=true|false` (default: `true`)
- `review_feedback_sweep_cmd=<command>` (default: `scripts/review-feedback-sweep.sh`)
- `review_feedback_statuses=<csv>` (default: `Reviewed,Needs Review`)
- `retrospective=<path>` (default: `.cursor/ralph/<project-slug>/retrospective.json`)
- `process_retrospective=true|false` (default: `true`)
- `retrospective_cmd=<command>` (default: `scripts/generate-retrospective.sh`)
- `process_retrospective_improvements=true|false` (default: `true`)
- `retrospective_improvement_cmd=<command>` (default: `scripts/retrospective-to-issue-intents.sh`)
- `process_model_routing=true|false` (default: `true`)
- `model_router_cmd=<command>` (default: `scripts/select-model-tier.sh`)
- `model_routing_policy=<path>` (default: `contracts/ralph/core/model-routing-policy.default.json`)
- `model_cmd_low=<command>` (optional tier override)
- `model_cmd_medium=<command>` (optional tier override)
- `model_cmd_high=<command>` (optional tier override)
- `workdir=<path>` (optional; default repo root)
- `dispatch_mode=standalone|orchestrated` (default: `standalone`)
- `dispatch_id=<id>` (required in orchestrated mode)
- `dispatch_run_id=<id>` (required in orchestrated mode)
- `dispatch_log=<path>` (optional; dispatch event output; defaults to stdout in orchestrated mode)

## Label-Independent Operation

`ralph-run` does **not** require `Ralph Queue`, `Ralph Claimed`, `Ralph Completed`, or any other deprecated claim label for issue selection, readiness gating, or claim-state tracking.

Issue scheduling uses two readiness paths evaluated in order:

1. **Structural readiness** (primary) — description-based checks per `contracts/ralph/core/readiness-taxonomy.md`.
2. **Label migration fallback** — `Ralph` + `PRD Ready` labels admit the issue only when structural checks are not yet satisfied.

Deprecated claim labels are ignored during selection. If present on issues, they are treated as compatibility aliases only and must not influence scheduling order, readiness admission, or claim safety. See `contracts/ralph/core/claim-label-deprecation.md` for the full deprecation contract.

## Required Gate

Before starting, if `/linear/audit-project` has not been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before starting Ralph?`

If user declines, continue.

If latest audit output includes unresolved preflight question-scan risks:

- unresolved `critical`: do not proceed unattended until resolved or explicitly overridden
- unresolved `major`: surface warning + require explicit operator acknowledgement for unattended execution

## Process

1. Validate that `prd` exists.
2. Validate that `scripts/ralph-run.sh` exists and is executable.
3. Run:

```bash
scripts/ralph-run.sh \
  --prd "<prd>" \
  --max "<max>" \
  --autocommit "<autocommit>" \
  --sync-linear "<sync_linear>" \
  --workflow-mode "<workflow_mode>" \
  --resume "<resume>" \
  --stale-after-seconds "<stale_after_seconds>" \
  --max-retries-per-issue "<max_retries_per_issue>" \
  --agent-cmd "<agent_cmd>" \
  --progress "<progress>" \
  --run-log "<run_log>" \
  --loop-state "<loop_state>" \
  --issue-intent-queue "<issue_intent_queue>" \
  --issue-intent-results "<issue_intent_results>" \
  --process-issue-intents "<process_issue_intents>" \
  --issue-intent-worker-cmd "<issue_intent_worker_cmd>" \
  --review-feedback-events "<review_feedback_events>" \
  --review-feedback-state "<review_feedback_state>" \
  --process-review-feedback-sweep "<process_review_feedback_sweep>" \
  --review-feedback-sweep-cmd "<review_feedback_sweep_cmd>" \
  --review-feedback-statuses "<review_feedback_statuses>" \
  --retrospective "<retrospective>" \
  --process-retrospective "<process_retrospective>" \
  --retrospective-cmd "<retrospective_cmd>" \
  --process-retrospective-improvements "<process_retrospective_improvements>" \
  --retrospective-improvement-cmd "<retrospective_improvement_cmd>" \
  --process-model-routing "<process_model_routing>" \
  --model-router-cmd "<model_router_cmd>" \
  --model-routing-policy "<model_routing_policy>" \
  --model-cmd-low "<model_cmd_low>" \
  --model-cmd-medium "<model_cmd_medium>" \
  --model-cmd-high "<model_cmd_high>"
```

4. If `usage_limit` is provided, append `--usage-limit "<usage_limit>"`.
5. If `workdir` is provided, append `--workdir "<workdir>"`.
6. If `dispatch_mode` is provided, append `--dispatch-mode "<dispatch_mode>"`.
7. If `dispatch_mode=orchestrated`, append `--dispatch-id "<dispatch_id>" --dispatch-run-id "<dispatch_run_id>"`.
8. If `dispatch_log` is provided, append `--dispatch-log "<dispatch_log>"`.
9. The default runtime uses `scripts/configured-issue-agent.sh`, which defaults to `scripts/codex-issue-agent.sh` as the production backend. Set `RALPH_ISSUE_EXECUTOR_CMD` only when you want to override that backend with another command that implements the CLI issue execution contract. `scripts/mock-issue-agent.sh` is smoke-only.
10. Use `resume=true` to continue an interrupted run from loop state; active non-stale runs are protected from concurrent resume.
11. Delegated issue-creation outcomes are reported in completion output and do not block per-iteration execution.
12. Reviewed-state feedback sweep runs between iterations in `independent` mode and can requeue issues without checkpoint pauses.
13. Automatic retrospective runs after iteration loop and before final completion summary.
14. Critical/major retrospective improvements can be converted to delegated issue-creation intents before intent-worker processing.
15. Issue selection follows deterministic scheduling policy from `contracts/ralph/core/commands/ralph-run.md` and writes `RUN_SCHEDULE_DECISION` markers.
16. Per-issue model routing writes `RUN_MODEL_ROUTING` markers and passes selected tier/model hints into issue execution (`RALPH_MODEL_TIER`, `RALPH_MODEL_NAME`).
17. Retry/escalation policy is bounded and deterministic:
    - repeated failures promote routing floor (`low` -> `medium` -> `high`)
    - high-tier failure or max retries triggers escalation marker (`RUN_MODEL_ESCALATION`) and human-required handoff logging.
18. Stage-level telemetry is captured (`execution` tokens/attempts, `validation` failures, `review` handoffs) for cost/quality tuning.

## Workflow Modes

- `independent`:
  - default mode
  - preserves the existing async Linear review flow
  - `Needs Review`/`Reviewed` plus the feedback sweep remain the review path between iterations
- `human-in-the-loop`:
  - resolve unknowns and review inside the active execution cycle
  - keep issue progress in the active loop until review or clarification is complete
  - avoid interim `Needs Review` transitions solely for mid-execution clarification/review
  - the runner disables reviewed-state feedback sweep automatically because review is expected to happen in-loop

Use `independent` for unattended or async review workflows. Use `human-in-the-loop` when an operator plans to stay in the loop and wants review/clarification handled before the issue leaves the active cycle.

## Dispatch Modes

### `standalone` (default)

`scripts/ralph-run.sh` is the dispatcher. It owns candidate selection, loop state, retry coordination, and all post-loop processing. This is the existing behavior.

```bash
scripts/ralph-run.sh \
  --prd prd.json \
  --max 5 \
  --dispatch-mode standalone
```

### `orchestrated`

An external orchestrator dispatches a single issue to `ralph-run.sh` as a worker. The script:

- Accepts exactly one pending issue in the PRD
- Emits `claim`, `heartbeat`, and `complete` dispatch lifecycle events
- Skips candidate selection, loop-state management, and post-loop processing
- Executes one attempt and exits

```bash
scripts/ralph-run.sh \
  --prd single-issue-prd.json \
  --dispatch-mode orchestrated \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --dispatch-run-id "run-20260318-01" \
  --dispatch-log .ralph/dispatch-events.jsonl \
  --agent-cmd scripts/configured-issue-agent.sh
```

`dispatch_mode` and `workflow_mode` are orthogonal. See `contracts/ralph/core/dispatch-protocol.md` for the full boundary definition, payload shapes, and migration guidance.

## Worktree Usage for Parallel Execution

When running multiple Ralph workers in parallel (orchestrated dispatch mode), each worker needs an isolated git worktree to avoid file conflicts. Use `scripts/ralph-worktree.sh` to manage worktree lifecycles.

### Creating a worktree for a dispatched worker

```bash
# Provision an isolated worktree for one issue
worktree_json=$(scripts/ralph-worktree.sh create \
  --project "dispatch-v2" \
  --track "N43-476" \
  --base "main")

worktree_path=$(jq -r '.worktree_path' <<< "$worktree_json")

# Pass the worktree path as --workdir to ralph-run.sh
scripts/ralph-run.sh \
  --prd single-issue-prd.json \
  --dispatch-mode orchestrated \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --dispatch-run-id "run-20260318-01" \
  --workdir "$worktree_path"
```

### Listing active worktrees

```bash
# JSON output with health status (active/stale/orphaned)
scripts/ralph-worktree.sh list

# Human-readable table
scripts/ralph-worktree.sh list --format text
```

### Cleaning up after a worker completes

```bash
# Prune a specific worktree by path
scripts/ralph-worktree.sh prune --path "$worktree_path"

# Or by project/track identifiers
scripts/ralph-worktree.sh prune --project "dispatch-v2" --track "N43-476"

# Clean up all stale/orphaned worktrees
scripts/ralph-worktree.sh prune-all --confirm
```

### `--workdir` flag integration

The `--workdir` flag on `ralph-run.sh` sets the working directory for issue execution. When combined with worktrees:

- The worker's git operations (commits, branch changes) are confined to the worktree
- Other workers and the main working directory are unaffected
- Config files (prettier, eslint, tsconfig) are copied into the worktree on creation

See `contracts/ralph/core/worktree-lifecycle.md` for the full lifecycle contract, naming conventions, and conflict resolution behavior.

## Canonical Artifact Contract

- Canonical artifact: `progress.txt`
- Sidecar artifact: `run-log.jsonl` (optional)

`progress.txt` lines are machine-readable and append-only:

- `RUN_START ...`
- `RUN_ITERATION ...`
- `RUN_COMPLETE ...`

Completion detection must rely on PRD state + deterministic loop logic, not sidecar availability.

## Contract References

- Core command contract: `contracts/ralph/core/commands/ralph-run.md`
- Status semantics: `contracts/ralph/core/status-semantics.md`
- Per-issue CLI contract: `contracts/ralph/core/cli-issue-execution-contract.md`
- Dispatch protocol: `contracts/ralph/core/dispatch-protocol.md`
- Delegated issue creation contract: `contracts/ralph/core/issue-creation-delegation-contract.md`
- Review feedback sweep contract: `contracts/ralph/core/review-feedback-sweep-contract.md`
- Retrospective contract: `contracts/ralph/core/retrospective-contract.md`
- Model routing policy: `contracts/ralph/core/model-routing-policy.default.json`
- Stage model strategy: `contracts/ralph/core/stage-model-strategy.md`
- Worktree lifecycle: `contracts/ralph/core/worktree-lifecycle.md`
- Claim label deprecation: `contracts/ralph/core/claim-label-deprecation.md`
- Preflight question-scan rubric: `contracts/ralph/core/preflight-question-scan-rubric.md`
- CLI result schema: `contracts/ralph/core/schema/cli-issue-execution-result.schema.json`

## Completion Response

Return:

1. Script exit code
2. Iteration count executed
3. Completed issues
4. Failed/handoff issues
5. Remaining pending issues

## Notes

1. Iteration behavior is owned by `scripts/ralph-run.sh`.
2. Per-issue execution must use JSON input/output contract semantics.
3. Runtime parity applies across script, Cursor `/ralph/run`, and Codex `ralph-run` skill entrypoints.
