# Ralph Workflow Contracts

This directory is the canonical source of truth for Ralph + Linear workflow contracts.

## Canonical Structure

```text
contracts/ralph/
├── core/                       # Tool-agnostic contract definitions
│   ├── README.md
│   ├── linear-workflow.md      # Workflow sequencing + invariants only
│   ├── shared-validations.md   # Shared validation gates for all surfaces
│   ├── schema/                 # Canonical normalized schema artifacts
│   │   └── normalized-result.schema.json
│   └── commands/               # Per-command contract specs
│       ├── README.md
│       ├── create-project.md
│       ├── populate-project.md
│       ├── generate-prd-from-project.md
│       ├── audit-project.md
│       └── ralph-run.md
├── adapters/                   # Tool-specific mappings to core contracts
│   ├── README.md
│   ├── mapping.md              # One-to-one contract mapping across surfaces
│   ├── smoke-run.md            # Documented parity run across Cursor/Codex
│   ├── codex/
│   │   └── README.md
│   └── cursor/
│       └── README.md
└── OWNERSHIP_AND_BOUNDARIES.md # Ownership model and leakage-prevention rules
```

## Layer Responsibilities

- `core/`: Defines normalized workflow semantics, invariants, and terminology shared by every surface.
- `adapters/`: Maps each control surface to the `core/` contracts without changing meaning.

Core is authoritative. Adapters implement Core.

## Terminology

- Use `Issue` for Linear work items.
- Do not introduce non-canonical aliases when referring to Linear items.

## Change Rules

- Any contract meaning change starts in `core/`.
- Adapter updates must preserve core semantics and terminology.
- If core changes affect adapters, update impacted adapters in the same change set.
