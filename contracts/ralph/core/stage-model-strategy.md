# Stage Model Strategy

## Goal

Concentrate expensive reasoning in planning/decomposition stages while keeping iterative execution cost-efficient.

## Default Stage Tiers

| Stage | Default Tier | Default Model Intent |
| --- | --- | --- |
| Project decomposition / issue generation (`populate-project`) | High | maximize issue clarity and implementation specificity |
| PRD generation (`generate-prd-from-project`) | High | preserve deep reasoning quality in canonical execution artifacts |
| Issue execution (`ralph-run`) | Medium | balance cost with implementation throughput |
| Validation checks (`ralph-run`) | Low | lightweight pass/fail synthesis for deterministic checks |
| Review/handoff synthesis (`ralph-run`) | Medium | clear human-facing summaries without full planning cost |

## Policy Rules

- Planning artifacts must include enough detail for lower-cost execution models:
  - file targets
  - concrete implementation steps
  - validation expectations
  - edge-case notes
- Runtime routing may override execution tier per issue, but stage defaults remain baseline.
- Operator overrides must be available at run-time without code changes.

## Runtime Overrides

`scripts/ralph-run.sh` supports stage defaults per run:

- `--model-stage-planning-default`
- `--model-stage-execution-default`
- `--model-stage-validation-default`
- `--model-stage-review-default`

## Telemetry Expectations

Track stage-level cost/quality signals:

- execution attempts/tokens by selected model
- validation failure counts
- review/handoff counts

Telemetry is emitted in run markers and persisted in loop-state.
