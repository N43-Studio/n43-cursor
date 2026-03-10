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
- `agent_cmd=<command>` (default: `scripts/mock-issue-agent.sh`)
- `progress=<path>` (default: `progress.txt`)
- `run_log=<path>` (default: `run-log.jsonl`)
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
  --agent-cmd "<agent_cmd>" \
  --progress "<progress>" \
  --run-log "<run_log>"
```

4. If `usage_limit` is provided, append `--usage-limit "<usage_limit>"`.
5. If `workdir` is provided, append `--workdir "<workdir>"`.

## Contract References

- Core command contract: `contracts/ralph/core/commands/ralph-run.md`
- Per-issue CLI contract: `contracts/ralph/core/cli-issue-execution-contract.md`
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
