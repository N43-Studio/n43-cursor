# Ownership And Boundaries

This note defines who owns each layer and the rules that prevent contract leakage.

## Ownership

- `contracts/ralph/core/` is owned by workflow contract maintainers.
- `contracts/ralph/adapters/cursor/` is owned by Cursor workflow maintainers.
- `contracts/ralph/adapters/codex/` is owned by Codex workflow maintainers.
- Cross-layer changes require acknowledgment from both core and relevant adapter owners.

## Boundary Rules

- Core defines semantics; adapters only map semantics.
- Core MUST NOT contain tool-specific instructions, command syntax, or skill wiring.
- Adapters MUST NOT redefine canonical schema, lifecycle, or terminology.
- All Linear work item references use `Issue` terminology only.

## Leakage Prevention Checklist

- Before merging, confirm every adapter mapping points to a core contract source.
- Reject adapter-only semantic changes that are not first represented in core.
- Reject core changes that do not update impacted adapters in the same change set.
