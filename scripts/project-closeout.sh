#!/usr/bin/env bash
#
# project-closeout.sh — Orchestrate all 6 closeout stages into a single
# operator-facing closeout packet.
#
# Composes: branch divergence, artifact triage, coherence checks, release
# notes, squash preparation artifacts, and a Linear transition checklist.
#
# Usage:
#   scripts/project-closeout.sh --project "Ralph Wiggum Flow"
#   scripts/project-closeout.sh --project "My Feature" --branch feature/foo --base origin/main
#   scripts/project-closeout.sh --project "My Feature" --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT=""
BRANCH=""
BASE="origin/main"
OUTPUT_DIR=".ralph/closeout"
DRY_RUN=false
PRD_PATH=""

usage() {
  cat <<'USAGE'
Usage: scripts/project-closeout.sh [options]

Options:
  --project <name>    Project name (required)
  --branch <ref>      Branch to close out (default: current branch)
  --base <ref>        Base ref for comparison (default: origin/main)
  --output-dir <dir>  Output directory (default: .ralph/closeout/)
  --prd <path>        Path to prd.json for Linear checklist (optional)
  --dry-run           Show what would be done without executing
  --help              Show this help

Examples:
  scripts/project-closeout.sh --project "Ralph Wiggum Flow"
  scripts/project-closeout.sh --project "My Feature" --branch feature/foo --dry-run
  scripts/project-closeout.sh --project "My Feature" --prd .cursor/ralph/my-feature/prd.json
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) shift; PROJECT="${1:-}" ;;
    --branch)  shift; BRANCH="${1:-}" ;;
    --base)    shift; BASE="${1:-}" ;;
    --output-dir) shift; OUTPUT_DIR="${1:-}" ;;
    --prd)     shift; PRD_PATH="${1:-}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$PROJECT" ]; then
  echo "error: --project is required" >&2
  usage >&2
  exit 1
fi

if [ -z "$BRANCH" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Kebab-case slug for directory naming
PROJECT_SLUG="$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
CLOSEOUT_DIR="$OUTPUT_DIR/$PROJECT_SLUG"

log() { echo "[closeout] $*"; }
warn() { echo "[closeout] WARNING: $*" >&2; }

# ───────────────────────────────────────────────────────────────────────────
# Dry-run gate — prints the planned action and returns 0 (skip) or 1 (run)
# ───────────────────────────────────────────────────────────────────────────
dry_run_check() {
  local stage_label="$1"
  if $DRY_RUN; then
    log "[dry-run] Would execute: $stage_label"
    return 0
  fi
  return 1
}

# ───────────────────────────────────────────────────────────────────────────
# Resolve merge base
# ───────────────────────────────────────────────────────────────────────────
MERGE_BASE="$(git merge-base "$BASE" "$BRANCH" 2>/dev/null)" || {
  echo "error: could not compute merge-base between '$BASE' and '$BRANCH'" >&2
  exit 1
}

log "Project:    $PROJECT"
log "Branch:     $BRANCH"
log "Base:       $BASE"
log "Merge base: ${MERGE_BASE:0:12}"
log "Output dir: $CLOSEOUT_DIR"
log "Dry-run:    $DRY_RUN"
log ""

if ! $DRY_RUN; then
  mkdir -p "$CLOSEOUT_DIR"
fi

STAGES_PASSED=0
STAGES_SKIPPED=0
STAGES_FAILED=0
STAGE_RESULTS=""

record_stage() {
  local num="$1" name="$2" status="$3" detail="${4:-}"
  case "$status" in
    pass) STAGES_PASSED=$((STAGES_PASSED + 1)) ;;
    skip) STAGES_SKIPPED=$((STAGES_SKIPPED + 1)) ;;
    fail) STAGES_FAILED=$((STAGES_FAILED + 1)) ;;
  esac
  if [ -z "$STAGE_RESULTS" ]; then
    STAGE_RESULTS="{\"stage\":$num,\"name\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}"
  else
    STAGE_RESULTS="$STAGE_RESULTS,{\"stage\":$num,\"name\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Stage 1: Inventory — Branch divergence report
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 1: Inventory (branch divergence) ━━━"

DIVERGENCE_REPORT="$CLOSEOUT_DIR/divergence-report.json"

if dry_run_check "scripts/branch-divergence-report.sh → $DIVERGENCE_REPORT"; then
  record_stage 1 "inventory" "skip" "dry-run"
else
  if [ -x "$SCRIPT_DIR/branch-divergence-report.sh" ]; then
    "$SCRIPT_DIR/branch-divergence-report.sh" \
      --branch "$BRANCH" \
      --base "$BASE" \
      --format json \
      --output "$DIVERGENCE_REPORT" \
      && record_stage 1 "inventory" "pass" "$DIVERGENCE_REPORT" \
      || record_stage 1 "inventory" "fail" "divergence report failed"
  else
    warn "branch-divergence-report.sh not found; generating inline"
    COMMIT_COUNT="$(git rev-list --count "$MERGE_BASE".."$BRANCH")"
    CHANGED_FILE_COUNT="$(git diff --name-only "$MERGE_BASE".."$BRANCH" | grep -c . || true)"
    cat > "$DIVERGENCE_REPORT" <<ENDJSON
{
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "generated": "$NOW_ISO",
  "summary": {
    "commitCount": $COMMIT_COUNT,
    "changedFileCount": $CHANGED_FILE_COUNT
  }
}
ENDJSON
    record_stage 1 "inventory" "pass" "$DIVERGENCE_REPORT (inline)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Stage 2: Artifact Triage — classify as transient/archival/canonical
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 2: Artifact Triage ━━━"

TRIAGE_REPORT="$CLOSEOUT_DIR/artifact-triage.json"

classify_artifact() {
  local f="$1"
  case "$f" in
    .ralph/results/*|.ralph/results-*/*) echo "transient" ;;
    .ralph/squash-artifacts/*)           echo "transient" ;;
    progress.txt)                        echo "transient" ;;
    run-log.jsonl)                       echo "archival" ;;
    assumptions-log.jsonl)               echo "transient" ;;
    .cursor/ralph/*/retrospective.json)  echo "archival" ;;
    .cursor/ralph/*/review-queue.json)   echo "archival" ;;
    .cursor/plans/*)                     echo "transient" ;;
    contracts/*|scripts/*|commands/*)    echo "canonical" ;;
    skills/*|templates/*|rules/*)        echo "canonical" ;;
    .cursor/rules/*|.cursor/skills/*)    echo "canonical" ;;
    .cursor/agents/*)                    echo "canonical" ;;
    README.md|commands/README.md)        echo "canonical" ;;
    *)                                   echo "canonical" ;;
  esac
}

if dry_run_check "Classify changed files into transient/archival/canonical"; then
  record_stage 2 "artifact-triage" "skip" "dry-run"
else
  CHANGED_FILES="$(git diff --name-only "$MERGE_BASE".."$BRANCH" 2>/dev/null || true)"
  UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
  ALL_FILES="$(printf '%s\n%s' "$CHANGED_FILES" "$UNTRACKED" | sort -u)"

  T_JSON="[]" A_JSON="[]" C_JSON="[]"
  T_LIST="" A_LIST="" C_LIST=""

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    category="$(classify_artifact "$file")"
    escaped="$(echo "$file" | sed 's/"/\\"/g')"
    case "$category" in
      transient) T_LIST="$T_LIST\"$escaped\"," ;;
      archival)  A_LIST="$A_LIST\"$escaped\"," ;;
      canonical) C_LIST="$C_LIST\"$escaped\"," ;;
    esac
  done <<< "$ALL_FILES"

  # Strip trailing commas, wrap in arrays
  T_JSON="[${T_LIST%,}]"
  A_JSON="[${A_LIST%,}]"
  C_JSON="[${C_LIST%,}]"

  cat > "$TRIAGE_REPORT" <<ENDJSON
{
  "generated": "$NOW_ISO",
  "branch": "$BRANCH",
  "transient": $T_JSON,
  "archival": $A_JSON,
  "canonical": $C_JSON,
  "actions": {
    "transient": "Delete from branch before merge",
    "archival": "Attach to Linear project, then delete from branch",
    "canonical": "Retain — these are the branch deliverables"
  }
}
ENDJSON
  T_COUNT="$(echo "$T_JSON" | tr ',' '\n' | grep -c '"' || true)"
  A_COUNT="$(echo "$A_JSON" | tr ',' '\n' | grep -c '"' || true)"
  C_COUNT="$(echo "$C_JSON" | tr ',' '\n' | grep -c '"' || true)"
  log "  Transient: $T_COUNT | Archival: $A_COUNT | Canonical: $C_COUNT"
  record_stage 2 "artifact-triage" "pass" "$TRIAGE_REPORT"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Stage 3: Coherence Review
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 3: Coherence Review ━━━"

COHERENCE_REPORT="$CLOSEOUT_DIR/coherence-review.json"

if dry_run_check "Run cross-reference, orphan, and README completeness checks"; then
  record_stage 3 "coherence-review" "skip" "dry-run"
else
  ISSUES=""
  ISSUE_COUNT=0

  add_issue() {
    local severity="$1" check="$2" detail="$3"
    detail="$(echo "$detail" | sed 's/"/\\"/g' | tr '\n' ' ')"
    if [ -z "$ISSUES" ]; then
      ISSUES="{\"severity\":\"$severity\",\"check\":\"$check\",\"detail\":\"$detail\"}"
    else
      ISSUES="$ISSUES,{\"severity\":\"$severity\",\"check\":\"$check\",\"detail\":\"$detail\"}"
    fi
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  }

  # 3a: Cross-reference integrity — find markdown refs to files that don't exist
  for dir in contracts commands templates; do
    [ -d "$dir" ] || continue
    while IFS= read -r mdfile; do
      [ -z "$mdfile" ] && continue
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        clean="$(echo "$ref" | tr -d '`')"
        # Only check relative paths that look like files (contain a dot or slash)
        case "$clean" in
          */*|*.md|*.sh|*.js|*.json|*.mdc)
            if [ ! -f "$clean" ] && [ ! -d "$clean" ]; then
              add_issue "warning" "broken-reference" "$mdfile references $clean (not found)"
            fi
            ;;
        esac
      done < <(grep -oE '`[^`]+\.(md|json|sh|js|mdc)`' "$mdfile" 2>/dev/null || true)
    done < <(find "$dir" -name '*.md' -type f 2>/dev/null)
  done

  # 3b: Orphan file check — changed .md files not referenced anywhere
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      .ralph/*|.cursor/plans/*) continue ;;
    esac
    BASENAME="$(basename "$f")"
    REF_COUNT="$(grep -rl "$BASENAME" --include='*.md' --include='*.mdc' . 2>/dev/null | grep -v "$f" | grep -c . || true)"
    if [ "$REF_COUNT" -eq 0 ]; then
      add_issue "info" "orphan-file" "$f is not referenced by any other markdown file"
    fi
  done < <(git diff --name-only "$MERGE_BASE".."$BRANCH" -- '*.md' 2>/dev/null)

  # 3c: README completeness — check commands/README.md lists all command files
  if [ -f "commands/README.md" ]; then
    while IFS= read -r cmd_file; do
      [ -z "$cmd_file" ] && continue
      CMD_BASENAME="$(basename "$cmd_file")"
      if ! grep -q "$CMD_BASENAME" commands/README.md 2>/dev/null; then
        add_issue "warning" "readme-missing-entry" "commands/README.md does not list $cmd_file"
      fi
    done < <(find commands -name '*.md' -not -name 'README.md' -type f 2>/dev/null)
  fi

  # 3d: Contract-command parity (lightweight — check for each command if a matching contract exists)
  if [ -d "contracts/ralph/core/commands" ] && [ -d "commands" ]; then
    while IFS= read -r contract; do
      [ -z "$contract" ] && continue
      CONTRACT_BASE="$(basename "$contract" .md)"
      FOUND=false
      if find commands -name "*.md" -type f 2>/dev/null | grep -q "$CONTRACT_BASE"; then
        FOUND=true
      fi
      if ! $FOUND; then
        add_issue "info" "contract-without-command" "Contract $contract has no matching command file"
      fi
    done < <(find contracts/ralph/core/commands -name '*.md' -not -name 'README.md' -type f 2>/dev/null)
  fi

  VERDICT="pass"
  WARNING_COUNT="$(echo "[$ISSUES]" | grep -o '"warning"' | grep -c . || true)"
  if [ "$WARNING_COUNT" -gt 0 ]; then
    VERDICT="warnings"
  fi

  cat > "$COHERENCE_REPORT" <<ENDJSON
{
  "generated": "$NOW_ISO",
  "branch": "$BRANCH",
  "verdict": "$VERDICT",
  "issueCount": $ISSUE_COUNT,
  "issues": [$ISSUES]
}
ENDJSON
  log "  Coherence verdict: $VERDICT ($ISSUE_COUNT issues)"
  record_stage 3 "coherence-review" "pass" "$COHERENCE_REPORT"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Stage 4: Release Summary
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 4: Release Summary ━━━"

RELEASE_NOTES_MD="$CLOSEOUT_DIR/release-notes.md"
RELEASE_NOTES_JSON="$CLOSEOUT_DIR/release-notes.json"

if dry_run_check "Generate release notes from commit history"; then
  record_stage 4 "release-summary" "skip" "dry-run"
else
  COMMIT_COUNT="$(git rev-list --count "$MERGE_BASE".."$BRANCH")"
  FILE_COUNT="$(git diff --name-only "$MERGE_BASE".."$BRANCH" | grep -c . || true)"

  {
    echo "# Release Notes: $PROJECT"
    echo ""
    echo "## Summary"
    echo ""
    echo "- Branch: \`$BRANCH\`"
    echo "- Base: \`$BASE\`"
    echo "- Commits: $COMMIT_COUNT"
    echo "- Files changed: $FILE_COUNT"
    echo "- Generated: $NOW_ISO"
    echo ""
    echo "## Changes by Type"
    echo ""

    for type in feat fix refactor docs chore test; do
      ENTRIES="$(git log --oneline "$MERGE_BASE".."$BRANCH" | grep -E "^[a-f0-9]+ $type" || true)"
      if [ -n "$ENTRIES" ]; then
        echo "### $type"
        echo ""
        while IFS= read -r line; do
          echo "- ${line#* }"
        done <<< "$ENTRIES"
        echo ""
      fi
    done

    echo "## Files Changed"
    echo ""
    echo "### By Directory"
    echo ""
    git diff --name-only "$MERGE_BASE".."$BRANCH" | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | while IFS= read -r line; do
      echo "- $line"
    done
    echo ""
  } > "$RELEASE_NOTES_MD"

  # Build a JSON sidecar with structured change data
  TYPES_JSON=""
  for type in feat fix refactor docs chore test; do
    COUNT="$(git log --oneline "$MERGE_BASE".."$BRANCH" | grep -cE "^[a-f0-9]+ $type" || true)"
    if [ -z "$TYPES_JSON" ]; then
      TYPES_JSON="\"$type\":$COUNT"
    else
      TYPES_JSON="$TYPES_JSON,\"$type\":$COUNT"
    fi
  done

  cat > "$RELEASE_NOTES_JSON" <<ENDJSON
{
  "generated": "$NOW_ISO",
  "project": "$PROJECT",
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "commitCount": $COMMIT_COUNT,
  "fileCount": $FILE_COUNT,
  "changesByType": {$TYPES_JSON},
  "markdownPath": "$RELEASE_NOTES_MD"
}
ENDJSON
  log "  Release notes: $RELEASE_NOTES_MD"
  record_stage 4 "release-summary" "pass" "$RELEASE_NOTES_MD"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Stage 5: Squash Preparation Artifacts
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 5: Squash Preparation ━━━"

SQUASH_PLAN="$CLOSEOUT_DIR/squash-plan.json"

if dry_run_check "Generate squash plan via scripts/generate-squash-artifacts.js"; then
  record_stage 5 "squash-prep" "skip" "dry-run"
else
  if [ -f "$SCRIPT_DIR/generate-squash-artifacts.js" ]; then
    node "$SCRIPT_DIR/generate-squash-artifacts.js" \
      --phase pre \
      --branch "$BRANCH" \
      --parent "$BASE" \
      --output-dir "$CLOSEOUT_DIR/squash-artifacts" \
      > "$SQUASH_PLAN" 2>/dev/null \
      && record_stage 5 "squash-prep" "pass" "$SQUASH_PLAN" \
      || record_stage 5 "squash-prep" "fail" "squash artifact generation failed"
  else
    warn "generate-squash-artifacts.js not found; generating minimal plan"
    COMMIT_COUNT="$(git rev-list --count "$MERGE_BASE".."$BRANCH")"
    cat > "$SQUASH_PLAN" <<ENDJSON
{
  "generated": "$NOW_ISO",
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "commitCount": $COMMIT_COUNT,
  "recommendedStrategy": "single",
  "note": "Full squash artifacts require scripts/generate-squash-artifacts.js"
}
ENDJSON
    record_stage 5 "squash-prep" "pass" "$SQUASH_PLAN (minimal)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Stage 6: Linear Transition Checklist
# ═══════════════════════════════════════════════════════════════════════════
log "━━━ Stage 6: Linear Transition Checklist ━━━"

LINEAR_CHECKLIST="$CLOSEOUT_DIR/linear-checklist.md"
LINEAR_CHECKLIST_JSON="$CLOSEOUT_DIR/linear-checklist.json"

if dry_run_check "Generate Linear transition checklist"; then
  record_stage 6 "linear-transition" "skip" "dry-run"
else
  # Gather PRD issue status if prd.json is available
  PRD_ISSUE_STATUS=""
  if [ -n "$PRD_PATH" ] && [ -f "$PRD_PATH" ] && command -v jq >/dev/null 2>&1; then
    TOTAL_ISSUES="$(jq '.issues | length' "$PRD_PATH" 2>/dev/null || echo 0)"
    DONE_ISSUES="$(jq '[.issues[] | select(.status == "Done" or .status == "done")] | length' "$PRD_PATH" 2>/dev/null || echo 0)"
    CANCELLED_ISSUES="$(jq '[.issues[] | select(.status == "Cancelled" or .status == "cancelled")] | length' "$PRD_PATH" 2>/dev/null || echo 0)"
    OPEN_ISSUES=$((TOTAL_ISSUES - DONE_ISSUES - CANCELLED_ISSUES))
    PRD_ISSUE_STATUS="Total: $TOTAL_ISSUES | Done: $DONE_ISSUES | Cancelled: $CANCELLED_ISSUES | Open: $OPEN_ISSUES"
  fi

  {
    echo "# Linear Transition Checklist: $PROJECT"
    echo ""
    echo "Generated: $NOW_ISO"
    echo ""
    echo "## Pre-Merge"
    echo ""
    echo "- [ ] All PRD issues are in terminal state (Done/Cancelled)"
    if [ -n "$PRD_ISSUE_STATUS" ]; then
      echo "  - Status: $PRD_ISSUE_STATUS"
      if [ "$OPEN_ISSUES" -gt 0 ]; then
        echo "  - **WARNING**: $OPEN_ISSUES issues are still open"
      fi
    fi
    echo "- [ ] Transient artifacts removed from branch"
    echo "- [ ] Coherence review passed (no broken cross-references)"
    echo "- [ ] Release notes generated and reviewed"
    echo "- [ ] Squash branch created and tree-equivalence verified"
    echo ""
    echo "## Artifact Archival"
    echo ""
    echo "- [ ] Attach release notes to Linear project update"
    echo "- [ ] Attach retrospective JSON (if exists) to Linear project"
    echo "- [ ] Attach run-log summary to Linear project (before deletion)"
    echo "- [ ] Attach squash verification to Linear project"
    echo ""
    echo "## Project Status"
    echo ""
    echo "- [ ] Set Linear project status to Completed"
    echo "- [ ] Add final project update summarizing closeout"
    echo "- [ ] Link PR to Linear project and relevant issues"
    echo ""
    echo "## Post-Merge"
    echo ""
    echo "- [ ] Delete feature branch"
    echo "- [ ] Verify main branch CI passes"
    echo "- [ ] Confirm Linear project marked as Completed"
    echo ""
  } > "$LINEAR_CHECKLIST"

  # JSON sidecar
  HAS_PRD=false
  if [ -n "$PRD_PATH" ] && [ -f "$PRD_PATH" ]; then
    HAS_PRD=true
  fi

  cat > "$LINEAR_CHECKLIST_JSON" <<ENDJSON
{
  "generated": "$NOW_ISO",
  "project": "$PROJECT",
  "branch": "$BRANCH",
  "prdPath": $(if $HAS_PRD; then echo "\"$PRD_PATH\""; else echo "null"; fi),
  "prdIssueStatus": $(if [ -n "$PRD_ISSUE_STATUS" ]; then echo "\"$PRD_ISSUE_STATUS\""; else echo "null"; fi),
  "checklistPath": "$LINEAR_CHECKLIST"
}
ENDJSON
  log "  Linear checklist: $LINEAR_CHECKLIST"
  record_stage 6 "linear-transition" "pass" "$LINEAR_CHECKLIST"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary — JSON + human-readable output
# ═══════════════════════════════════════════════════════════════════════════
log ""
log "━━━ Closeout Summary ━━━"

SUMMARY_JSON="$CLOSEOUT_DIR/closeout-summary.json"
SUMMARY_MD="$CLOSEOUT_DIR/closeout-summary.md"
TOTAL_STAGES=$((STAGES_PASSED + STAGES_SKIPPED + STAGES_FAILED))

if $DRY_RUN; then
  log "[dry-run] Would write summary to: $SUMMARY_JSON"
  log "[dry-run] Would write report to:  $SUMMARY_MD"
  log ""
  log "Stages: $TOTAL_STAGES total | $STAGES_PASSED passed | $STAGES_SKIPPED skipped | $STAGES_FAILED failed"

  # Still emit JSON to stdout for tooling consumption in dry-run mode
  cat <<ENDJSON
{
  "dryRun": true,
  "project": "$PROJECT",
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "generated": "$NOW_ISO",
  "outputDir": "$CLOSEOUT_DIR",
  "stages": [$STAGE_RESULTS],
  "summary": {
    "total": $TOTAL_STAGES,
    "passed": $STAGES_PASSED,
    "skipped": $STAGES_SKIPPED,
    "failed": $STAGES_FAILED
  }
}
ENDJSON
  exit 0
fi

OVERALL_VERDICT="pass"
if [ "$STAGES_FAILED" -gt 0 ]; then
  OVERALL_VERDICT="fail"
elif [ "$STAGES_SKIPPED" -gt 0 ]; then
  OVERALL_VERDICT="partial"
fi

cat > "$SUMMARY_JSON" <<ENDJSON
{
  "project": "$PROJECT",
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "generated": "$NOW_ISO",
  "outputDir": "$CLOSEOUT_DIR",
  "verdict": "$OVERALL_VERDICT",
  "stages": [$STAGE_RESULTS],
  "summary": {
    "total": $TOTAL_STAGES,
    "passed": $STAGES_PASSED,
    "skipped": $STAGES_SKIPPED,
    "failed": $STAGES_FAILED
  },
  "artifacts": {
    "divergenceReport": "$DIVERGENCE_REPORT",
    "artifactTriage": "$TRIAGE_REPORT",
    "coherenceReview": "$COHERENCE_REPORT",
    "releaseNotes": "$RELEASE_NOTES_MD",
    "releaseNotesJson": "$RELEASE_NOTES_JSON",
    "squashPlan": "$SQUASH_PLAN",
    "linearChecklist": "$LINEAR_CHECKLIST",
    "linearChecklistJson": "$LINEAR_CHECKLIST_JSON",
    "summaryJson": "$SUMMARY_JSON",
    "summaryMarkdown": "$SUMMARY_MD"
  }
}
ENDJSON

{
  echo "# Project Closeout Report: $PROJECT"
  echo ""
  echo "| Property | Value |"
  echo "|---|---|"
  echo "| Project | $PROJECT |"
  echo "| Branch | \`$BRANCH\` |"
  echo "| Base | \`$BASE\` |"
  echo "| Merge base | \`${MERGE_BASE:0:12}\` |"
  echo "| Generated | $NOW_ISO |"
  echo "| Verdict | **$OVERALL_VERDICT** |"
  echo ""
  echo "## Stage Results"
  echo ""
  echo "| # | Stage | Status |"
  echo "|---|---|---|"
  echo "| 1 | Inventory (branch divergence) | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":1[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo "| 2 | Artifact Triage | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":2[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo "| 3 | Coherence Review | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":3[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo "| 4 | Release Summary | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":4[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo "| 5 | Squash Preparation | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":5[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo "| 6 | Linear Transition | $(echo "[$STAGE_RESULTS]" | grep -o '"stage":6[^}]*"status":"[^"]*"' | grep -o '"status":"[^"]*"' | cut -d'"' -f4) |"
  echo ""
  echo "## Artifacts"
  echo ""
  echo "| Artifact | Path |"
  echo "|---|---|"
  echo "| Divergence report | \`$DIVERGENCE_REPORT\` |"
  echo "| Artifact triage | \`$TRIAGE_REPORT\` |"
  echo "| Coherence review | \`$COHERENCE_REPORT\` |"
  echo "| Release notes (MD) | \`$RELEASE_NOTES_MD\` |"
  echo "| Release notes (JSON) | \`$RELEASE_NOTES_JSON\` |"
  echo "| Squash plan | \`$SQUASH_PLAN\` |"
  echo "| Linear checklist | \`$LINEAR_CHECKLIST\` |"
  echo "| Summary JSON | \`$SUMMARY_JSON\` |"
  echo ""
  echo "## Next Steps"
  echo ""
  echo "1. Review the coherence report for any broken references or orphan files"
  echo "2. Complete the Linear transition checklist"
  echo "3. Remove transient artifacts identified in the triage report"
  echo "4. Create the squash branch using \`commands/git/squash.md\`"
  echo "5. Open a PR from the squash branch and link to the Linear project"
  echo ""
} > "$SUMMARY_MD"

log "Verdict: $OVERALL_VERDICT"
log "Stages:  $TOTAL_STAGES total | $STAGES_PASSED passed | $STAGES_SKIPPED skipped | $STAGES_FAILED failed"
log ""
log "Artifacts written to: $CLOSEOUT_DIR/"
log "  Summary JSON:    $SUMMARY_JSON"
log "  Summary report:  $SUMMARY_MD"

# Emit structured JSON to stdout for tooling
cat "$SUMMARY_JSON"
