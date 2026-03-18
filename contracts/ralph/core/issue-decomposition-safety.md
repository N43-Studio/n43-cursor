# Issue Decomposition Safety Contract

## Purpose

Define the safe order of operations when decomposing broad umbrella issues into narrower replacement children. Linear's parent-child cascade behavior auto-cancels children when a parent is canceled, so the decomposition flow must neutralize the parent-child link before any terminal state change.

## Linear Cascade Behavior

| Parent Action | Effect on Children |
|---|---|
| **Cancel** parent | Cascades — all children auto-canceled |
| **Done** parent | Does NOT cascade — children unaffected |
| Remove parent-child link first | No cascade possible — issues are independent |

This cascade is a Linear platform behavior, not a Ralph-specific feature. Any workflow that creates children and later terminates the parent is at risk.

## Safe Decomposition Order of Operations

1. **Create** all replacement child issues first (runnable: `Todo` or `Backlog`).
2. **Verify** every replacement child is in a runnable state — not `Done`, not `Canceled`, no `Human Required` label blocking automation.
3. **Unparent** replacement children from the umbrella issue (`parentId → null`).
4. **Only then** terminalize the superseded umbrella issue.

Step 3 is the critical safety gate. Without it, step 4 may cascade and destroy the very issues created in step 1.

## Terminalization Decision Matrix

| Scenario | Recommended Strategy | Rationale |
|---|---|---|
| Umbrella was **partially implemented** | Mark **Done** with comment | Done does not cascade; acknowledges partial work |
| Umbrella was **never started** | Unparent children, then **Cancel** | Cancel is semantically correct; unparenting prevents cascade |
| Umbrella is being **replaced entirely** | Unparent children, then **Cancel** | Cancel + explicit superseded-by comment preserves audit trail |
| Umbrella has **external integrations** depending on its state | Mark **Done** with comment | Safest path — no cascade, no broken integrations |

### Strategy Details

#### `done` Strategy (Safest)

- Set umbrella state to `Done`.
- Add comment: `Superseded by replacement issues: [child-ids]. Marked Done to prevent cascade cancellation of children.`
- No unparenting required (Done does not cascade), but recommended for clarity.

#### `cancel` Strategy (Requires Unparenting)

- **Must** unparent all children before canceling.
- Set each child's `parentId` to `null` via Linear API.
- Verify unparenting succeeded (re-fetch each child, confirm no `parentId`).
- Only then set umbrella state to `Canceled`.
- Add comment: `Decomposed into replacement issues: [child-ids]. Children unparented before cancellation to prevent cascade.`

## Replacement Issue Linking

When creating replacement children for a superseded umbrella:

- **Do NOT** use parent/sub-issue hierarchy between replacements and the superseded umbrella.
- **Use** `relatedTo`, `blockedBy`, or `blocks` relations instead.
- This avoids the cascade risk entirely for new replacements.

Existing children that predate the decomposition must be explicitly unparented if the cancel strategy is chosen.

## Guardrail Requirements

Intent-based issue creation flows (e.g., `scripts/issue-intent-worker.sh`) that specify a `supersedes_issue_id` must include `decomposition_guardrails`:

```json
{
  "decomposition_guardrails": {
    "require_children_runnable_before_parent_terminalization": true,
    "forbid_sub_issue_link_to_superseded_parent": true,
    "allowed_replacement_link_types": ["related", "blockedBy", "blocks"],
    "preferred_parent_terminal_state": "done"
  }
}
```

These guardrails are validated by the intent worker before processing. Missing or invalid guardrails cause the intent to fail with `"replacement-child intent missing required decomposition guardrails"`.

## Agent Workflow Integration

### During `populate-project`

When the populate flow identifies existing umbrella issues being split:

1. Create replacement issues as standalone backlog items (no `parentId` to the umbrella).
2. Link replacements with `relatedTo` to the superseded umbrella.
3. Defer umbrella terminalization until all replacements are confirmed runnable.
4. Prefer `Done` over `Cancel` for the umbrella when children may still exist.

### During `retrospective-to-issue-intents`

When retrospective follow-ups decompose a broad finding:

1. Include `decomposition_guardrails` in the intent payload.
2. The intent worker validates guardrails before creating the issue.
3. The created issue description includes a cascade safety note when `parentId` is present.

### During Manual Backlog Normalization

Use `scripts/safe-decompose-issue.sh` to safely decompose an umbrella:

```bash
scripts/safe-decompose-issue.sh --parent N43-467 --strategy cancel --dry-run
scripts/safe-decompose-issue.sh --parent N43-467 --strategy cancel
```

## Related Contracts

- `contracts/ralph/core/commands/populate-project.md` — postcondition referencing this contract
- `contracts/ralph/core/issue-creation-defaults.md` — default metadata for created issues
- `contracts/ralph/core/issue-creation-delegation-contract.md` — delegation guardrails
- `commands/linear/populate-project.md` — command-level decomposition safety section
