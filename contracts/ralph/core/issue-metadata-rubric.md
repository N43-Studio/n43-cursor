# Issue Metadata Rubric

## Purpose

Define a deterministic rubric for setting Linear `priority` and `estimate` values from issue characteristics, with a traceable `estimatedTokens` prediction and confidence score.

## Scope

- Applies to issue-generation flows:
  - `populate-project`
  - `create-issue`
- Produces metadata for issue creation and downstream PRD planning.
- Uses calibration input when available but remains deterministic without calibration.

## Contract Inputs

Required issue draft fields (or deterministic fallbacks):

- `title`
- `description`
- `acceptanceCriteria` (array or markdown checklist)
- dependency sets (`dependsOn`, `blockedBy`, `blocks`)

Optional enrichment inputs:

- file targets (`files`, `filesToCreate`, `filesToModify`)
- validation expectations (`validation`)
- explicit `riskFlags`
- calibration snapshot (default path: `.cursor/ralph/calibration.json`)

## Signal Extraction

For each issue draft, extract:

- `filesCount`
- `acceptanceCount`
- `dependencyCount`
- `validationCount`
- `descriptionWordCount`
- `complexityBand`:
  - `0`: <= 80 words
  - `1`: 81-180 words
  - `2`: > 180 words
- `riskCount`:
  - explicit `riskFlags` count
  - plus deterministic keyword hits (`migration`, `rollback`, `security`, `auth`, `billing`, `payment`, `data loss`, `concurrency`, `production`, `incident`)

## Token Prediction Formula

Base token estimate:

`rawTokens = 1200 + (filesCount * 650) + (acceptanceCount * 320) + (dependencyCount * 280) + (validationCount * 250) + (complexityBand * 900) + (riskCount * 700)`

Calibration:

- Default `tokensPerPoint` baseline: `3200`.
- If calibration data is available, compute a deterministic multiplier from observed tokens-per-point.
- Clamp multiplier to `[0.70, 1.60]`.

Final estimate:

`estimatedTokens = round(rawTokens * calibrationMultiplier)`

## Point Mapping (Linear Estimate)

Map `estimatedTokens` to standard point scale:

- `<= 3200` -> `1`
- `<= 6400` -> `2`
- `<= 9600` -> `3`
- `<= 16000` -> `5`
- `> 16000` -> `8`

## Priority Mapping (Linear Priority)

Compute deterministic priority score:

`priorityScore = (riskCount * 2) + dependencyCount + (estimate >= 5 ? 2 : 0) + (validationCount >= 3 ? 1 : 0) + (complexityBand == 2 ? 1 : 0)`

Map score to Linear priority values:

- `>= 7` -> `1` (`Urgent`)
- `>= 4` -> `2` (`High`)
- `>= 2` -> `3` (`Medium`)
- `< 2` -> `4` (`Low`)

## Confidence Scoring

Start at `0.95`, subtract:

- `0.20` when `acceptanceCount == 0`
- `0.20` when `filesCount == 0`
- `0.20` when `descriptionWordCount < 40`
- `0.10` when `dependencyCount == 0`
- `0.10` when `validationCount == 0`

Clamp to `[0.20, 0.95]`.

Low-confidence threshold:

- `confidence < 0.60` => low-confidence metadata requiring audit attention.

## Required Rubric Output

Issue-generation flows must emit:

- `priority`
- `estimate`
- `estimatedTokens`
- `confidence`
- `lowConfidence`
- concise rationale summary referencing key signals and calibration usage.

## Calibration Notes

- Rubric must run without calibration data.
- Calibration is additive: when present, it adjusts token prediction but never changes deterministic mapping logic.
- Calibration and retrospective pipelines are documented in:
  - `retrospective-contract.md`
  - `review-feedback-sweep-contract.md`

