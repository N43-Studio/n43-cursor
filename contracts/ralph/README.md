# Ralph Workflow Contracts

This directory is the canonical source of truth for Ralph + Linear workflow contracts.

## Canonical Structure

```text
contracts/ralph/
├── core/                       # Tool-agnostic contract definitions
│   ├── README.md
│   ├── linear-workflow.md      # Workflow sequencing + invariants only
│   ├── status-semantics.md     # Canonical Linear status lifecycle mapping
│   ├── issue-metadata-rubric.md # Deterministic priority/estimate/tokens rubric
│   ├── shared-validations.md   # Shared validation gates for all surfaces
│   ├── cli-issue-execution-contract.md # Canonical single-issue CLI invocation contract
│   ├── issue-creation-delegation-contract.md # Delegated non-blocking issue-creation contract
│   ├── review-feedback-sweep-contract.md # Reviewed-state feedback sweep + requeue contract
│   ├── retrospective-contract.md # Deterministic post-run retrospective contract
│   ├── plan-mode-contract.md # Cross-surface plan-mode routing + approval parity contract
│   ├── schema/                 # Canonical normalized schema artifacts
│   │   └── normalized-result.schema.json
│   │   └── cli-issue-execution-result.schema.json
│   └── commands/               # Per-command contract specs
│       ├── README.md
│       ├── create-project.md
│       ├── create-issue.md
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

- `core/`: Defines normalized workflow semantics, invariants, CLI contracts, and terminology shared by every surface.
- `adapters/`: Maps each control surface to the `core/` contracts without changing meaning.

Core is authoritative. Adapters implement Core.

## Core vs Adapter Decision Matrix

| Change Type | Layer |
| --- | --- |
| Workflow invariant or lifecycle rule change | `core/` |
| Schema/result payload shape change | `core/` |
| Label/readiness/status semantics change | `core/` |
| Cursor slash-command wording/wiring only | `adapters/cursor/` |
| Codex skill wiring/invocation wording only | `adapters/codex/` |
| Mapping table row addition/update | `adapters/mapping.md` + impacted adapter docs |

If unsure, default to `core/` first, then adapt outward.

## Terminology

- Use `Issue` for Linear work items.
- Do not introduce non-canonical aliases when referring to Linear items.

## Change Rules

- Any contract meaning change starts in `core/`.
- Adapter updates must preserve core semantics and terminology.
- If core changes affect adapters, update impacted adapters in the same change set.
- Contract reviews must include a leakage check against `OWNERSHIP_AND_BOUNDARIES.md`.
