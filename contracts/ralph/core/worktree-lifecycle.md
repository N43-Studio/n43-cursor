# Worktree Lifecycle Contract

## Intent

Define the deterministic worktree naming, lifecycle states, and cleanup behavior Ralph uses to give each parallel runner an isolated git working directory.

This contract is intentionally separate from:

- `dispatch-protocol.md`, which defines dispatch ownership, lease, and heartbeat semantics
- `cli-issue-execution-contract.md`, which defines the per-issue worker input/output JSON
- `commands/ralph-run.md`, which defines loop semantics and scheduling policy

## Naming Conventions

### Directory Path

```
.ralph/worktrees/<project>-<track>-<timestamp>/
```

| Segment | Source | Required | Example |
|---------|--------|----------|---------|
| `<project>` | `--project` slugified | Yes | `dispatch-v2` |
| `<track>` | `--track` slugified | No | `n43-476` |
| `<timestamp>` | UTC filesystem-safe timestamp | Yes (generated) | `20260318T120000Z` |

When `--track` is omitted, the path simplifies to:

```
.ralph/worktrees/<project>-<timestamp>/
```

All path segments are lowercased and normalized through the `slugify` function (`[^a-z0-9] -> -`, leading/trailing dashes stripped).

### Branch Name

```
ralph/<project>/<track>/<timestamp>
```

When `--track` is omitted:

```
ralph/<project>/<timestamp>
```

Branches follow the same slugification rules as directory segments.

### Determinism

Path and branch are fully determined by the combination of `--project`, `--track`, and the wall-clock second at creation time. Two creates in the same second with the same arguments will collide and the second will fail explicitly (exit 12). This is intentional -- silent overwrite is never permitted.

## Lifecycle States

```
provisioned -> active -> stale -> pruned
                  |
                  +----> orphaned -> pruned
```

### provisioned

Worktree directory and branch exist. The worktree was just created and has not diverged from its base ref.

### active

The worktree has received commits within the last 24 hours. A runner is likely using it.

### stale

No commits on the worktree's branch for more than 24 hours. The runner has likely finished or been interrupted.

### orphaned

The worktree path exists but its branch reference has been deleted, or git reports it as prunable. This can happen when a branch is manually deleted or force-pruned without cleaning up the worktree directory.

### pruned

The worktree and its branch have been removed. This is a terminal state; pruned worktrees leave no artifacts.

## Conflict Resolution

All conflict cases produce JSON output with `status: "conflict"`, a `conflict_reason` field, and exit code 12. Conflicts are never silently resolved.

| Conflict | Reason | Resolution |
|----------|--------|------------|
| Path already exists | `path_occupied` | Remove existing path or use different project/track |
| Branch already checked out | `branch_in_use` | Remove the worktree holding the branch |
| git worktree add failure | `git_worktree_conflict` | Inspect git error and resolve manually |
| Prune of active worktree | `active` | Pass `--force` to override |
| Prune of dirty worktree | `remove_failed` | Pass `--force` to override |

## Relationship to Dispatch Protocol

In orchestrated dispatch mode, each dispatched worker receives its own worktree:

1. **Orchestrator creates worktree**: Before dispatching an issue to a worker, the orchestrator calls `ralph-worktree.sh create --project <slug> --track <issue-id>` to provision an isolated directory.
2. **Worker receives workdir**: The `--workdir` flag on `ralph-run.sh` points at the worktree path from the create output.
3. **Worker executes in isolation**: The worker's git operations (commits, branch changes) are confined to its worktree and do not affect other workers or the main working directory.
4. **Orchestrator prunes after completion**: After the worker's `complete` dispatch event, the orchestrator calls `ralph-worktree.sh prune --path <worktree-path>` to clean up.

### Standalone Mode

In standalone dispatch mode, worktrees are optional. The runner uses the repo's main working directory by default. Worktrees become necessary only when running multiple standalone runners concurrently against different PRDs.

### Parallel Safety

- Each worktree has its own `.git` reference file and working tree, so concurrent git operations in different worktrees do not conflict.
- The `.ralph/worktrees/` root directory can contain many worktrees simultaneously.
- `prune-all` only targets stale and orphaned worktrees; active worktrees are left untouched unless `--force` is passed.

## Config File Propagation

On `create`, the following config files are copied from the repo root into the new worktree if they exist and are not already present in the worktree:

- `.cursor/rules/` (directory, recursive copy)
- `.prettierrc.json`
- `.eslintrc.json`
- `.eslintrc.js`
- `tsconfig.json`
- `package.json`
- `pnpm-lock.yaml`

This ensures the worktree has access to formatting, linting, and type-checking configuration without requiring a full `npm install` or symlink setup.

## Script Reference

```
scripts/ralph-worktree.sh <command> [options]
```

| Command | Purpose |
|---------|---------|
| `create` | Provision worktree with deterministic path and branch |
| `list` | Enumerate managed worktrees with health status |
| `status` | Detailed status for a single worktree |
| `prune` | Remove one worktree and its branch |
| `prune-all` | Remove all stale/orphaned worktrees |

See `scripts/ralph-worktree.sh --help` for full flag reference.

## Compatibility Rules

- Existing `--issue`-based naming from prior script versions is not forward-compatible with the `--project`/`--track` naming. Worktrees created with the old naming should be pruned manually or via `prune --path`.
- The `stale` threshold (24 hours with no commits) is a heuristic. Runners that intentionally pause for longer than 24 hours should be considered stale and cleaned up.
- Branch deletion during `prune` is best-effort. If the branch cannot be deleted (e.g., it is the repo's current HEAD), the worktree is still removed but the branch persists.
