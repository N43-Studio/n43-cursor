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

## Input

`$ARGUMENTS` supports:

- `prd=<path>` (required)
- `max=<number>` (default: `5`)
- `usage_limit=<number>` (optional)
- `autocommit=true|false` (default: `true`)
- `sync_linear=true|false` (default: `false`)
- `resume=true|false` (default: `false`)
- `stale_after_seconds=<number>` (default: `1800`)
- `max_retries_per_issue=<number>` (default: `3`)
- `agent_cmd=<command>` (default: `scripts/mock-issue-agent.sh`)
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

## Required Gate

Before starting, if `/linear/audit-project` has not been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before starting Ralph?`

If user declines, continue.

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
6. Use `resume=true` to continue an interrupted run from loop state; active non-stale runs are protected from concurrent resume.
7. Delegated issue-creation outcomes are reported in completion output and do not block per-iteration execution.
8. Reviewed-state feedback sweep runs between iterations and can requeue issues without checkpoint pauses.
9. Automatic retrospective runs after iteration loop and before final completion summary.
10. Critical/major retrospective improvements can be converted to delegated issue-creation intents before intent-worker processing.
11. Issue selection follows deterministic scheduling policy from `contracts/ralph/core/commands/ralph-run.md` and writes `RUN_SCHEDULE_DECISION` markers.
12. Per-issue model routing writes `RUN_MODEL_ROUTING` markers and passes selected tier/model hints into issue execution (`RALPH_MODEL_TIER`, `RALPH_MODEL_NAME`).
13. Retry/escalation policy is bounded and deterministic:
    - repeated failures promote routing floor (`low` -> `medium` -> `high`)
    - high-tier failure or max retries triggers escalation marker (`RUN_MODEL_ESCALATION`) and human-required handoff logging.
14. Stage-level telemetry is captured (`execution` tokens/attempts, `validation` failures, `review` handoffs) for cost/quality tuning.

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
- Delegated issue creation contract: `contracts/ralph/core/issue-creation-delegation-contract.md`
- Review feedback sweep contract: `contracts/ralph/core/review-feedback-sweep-contract.md`
- Retrospective contract: `contracts/ralph/core/retrospective-contract.md`
- Model routing policy: `contracts/ralph/core/model-routing-policy.default.json`
- Stage model strategy: `contracts/ralph/core/stage-model-strategy.md`
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
