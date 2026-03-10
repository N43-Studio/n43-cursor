# Model Routing Rubric

## Purpose

Define deterministic per-issue model-tier routing for `ralph-run` so easier issues use lower-cost models while higher-risk issues route to deeper reasoning tiers.

## Runtime Components

- Router implementation: `scripts/select-model-tier.sh`
- Default policy: `model-routing-policy.default.json`
- Runtime integration: `commands/ralph/run.md` + `commands/ralph/core/commands/ralph-run.md`

## Signals

The router computes a score from:

- Linear `priority`
- issue estimate (`estimatedPoints`/`estimate`)
- dependency depth (`dependsOn`/`blockedBy`)
- description complexity (word-count band)
- risk keyword hits
- historical failures for the same issue ID from `run-log.jsonl`
- `Human Required` presence (penalty/boost signal for higher-tier routing)

## Tier Mapping

Using policy thresholds:

- `score <= lowMax` -> `low`
- `score <= mediumMax` -> `medium`
- otherwise -> `high`

Selected tier maps to model name using policy `models` map.

## Confidence + Fallback

Confidence is deterministic from signal presence and limited history bonus.

- Missing key signals reduce confidence.
- If insufficient signal coverage exists, router sets `fallbackUsed=true` and uses policy `fallbackTier`.

## Required Routing Record

Each issue routing output includes:

- `selectedTier`
- `selectedModel`
- `score`
- `confidence`
- `fallbackUsed`
- factor object
- rationale list

`ralph-run` persists routing records in:

- progress markers (`RUN_MODEL_ROUTING`)
- `run-log.jsonl` (`modelRouting`)
- loop-state `last_iteration`

## Tuning Without Code Changes

Tune behavior by editing `model-routing-policy.default.json` (or passing an alternate policy path):

- threshold bands
- feature weights
- confidence penalties/bonus
- risk keywords
- model names per tier
- fallback tier
