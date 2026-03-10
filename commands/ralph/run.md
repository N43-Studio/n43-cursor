> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Wrapper is HITL orchestration around a deterministic terminal script runtime -->

# Run Ralph (Terminal Script Wrapper)

Run Ralph by invoking the canonical deterministic script:

`scripts/ralph-run.sh`

`/ralph/run` is a human-in-the-loop helper. It does not implement iteration logic itself.

## Input

`$ARGUMENTS` supports:

- `prd=<path>` (required)
- `max=<number>` (default: `5`)
- `usage_limit=<number>` (optional)
- `autocommit=true|false` (default: `true`)
- `sync_linear=true|false` (default: `false`)
- `resume=true|false` (default: `false`)
- `stale_after_seconds=<number>` (default: `1800`)
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
  --retrospective-improvement-cmd "<retrospective_improvement_cmd>"
```

4. If `usage_limit` is provided, append `--usage-limit "<usage_limit>"`.
5. If `workdir` is provided, append `--workdir "<workdir>"`.
6. Use `resume=true` to continue an interrupted run from loop state; active non-stale runs are protected from concurrent resume.
7. Delegated issue-creation outcomes are reported in completion output and do not block per-iteration execution.
8. Reviewed-state feedback sweep runs between iterations and can requeue issues without checkpoint pauses.
9. Automatic retrospective runs after iteration loop and before final completion summary.
10. Critical/major retrospective improvements can be converted to delegated issue-creation intents before intent-worker processing.

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
3. Cursor/Codex usage here is HITL orchestration only.
