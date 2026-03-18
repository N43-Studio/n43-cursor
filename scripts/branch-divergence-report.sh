#!/usr/bin/env bash
#
# branch-divergence-report.sh — Deterministic closeout report for Ralph project branches.
#
# Inventories how a branch has diverged from a base (default: origin/main),
# classifies changed files and artifacts, and proposes cleanup actions for
# a coherent merge-ready end state.
#
# Usage during project closeout:
#   1. Run before starting cleanup to understand scope:
#        scripts/branch-divergence-report.sh
#   2. Save a machine-readable snapshot for tooling:
#        scripts/branch-divergence-report.sh --format json --output report.json
#   3. Compare a specific branch against a custom base:
#        scripts/branch-divergence-report.sh --branch feature/foo --base develop
#
# The report distinguishes canonical source changes (contracts, scripts,
# commands, etc.) from transient/generated artifacts (.ralph/, run-log.jsonl,
# progress.txt) so reviewers know which files represent real work vs. runtime
# leftovers that should be removed before merge.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BRANCH=""
BASE="origin/main"
OUTPUT=""
FORMAT="text"

usage() {
  cat <<'USAGE'
Usage: scripts/branch-divergence-report.sh [options]

Options:
  --branch <ref>   Branch to analyze (default: current branch)
  --base <ref>     Base ref for comparison (default: origin/main)
  --output <path>  Write report to file instead of stdout
  --format <fmt>   Output format: text (default) or json
  --help           Show this help

Examples:
  scripts/branch-divergence-report.sh
  scripts/branch-divergence-report.sh --format json --output divergence.json
  scripts/branch-divergence-report.sh --branch feature/foo --base develop
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) shift; BRANCH="${1:-}" ;;
    --base)   shift; BASE="${1:-}" ;;
    --output) shift; OUTPUT="${1:-}" ;;
    --format) shift; FORMAT="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$BRANCH" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

if [ "$FORMAT" != "text" ] && [ "$FORMAT" != "json" ]; then
  echo "error: --format must be 'text' or 'json'" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Gather git data
# ---------------------------------------------------------------------------

MERGE_BASE="$(git merge-base "$BASE" "$BRANCH" 2>/dev/null)" || {
  echo "error: could not compute merge-base between '$BASE' and '$BRANCH'" >&2
  exit 1
}

MERGE_BASE_SHORT="${MERGE_BASE:0:12}"
BRANCH_HEAD="$(git rev-parse "$BRANCH")"
BRANCH_HEAD_SHORT="${BRANCH_HEAD:0:12}"

COMMITS="$(git log --oneline "$MERGE_BASE".."$BRANCH" 2>/dev/null)"
COMMIT_COUNT="$(echo "$COMMITS" | grep -c . || true)"

CHANGED_FILES="$(git diff --name-only "$MERGE_BASE".."$BRANCH" 2>/dev/null)"
CHANGED_FILE_COUNT="$(echo "$CHANGED_FILES" | grep -c . || true)"

DIFF_STAT="$(git diff --stat "$MERGE_BASE".."$BRANCH" 2>/dev/null | tail -1)"

# ---------------------------------------------------------------------------
# Classify files into categories
# ---------------------------------------------------------------------------

declare -A CATEGORY_FILES
CATEGORIES=(contracts scripts commands skills templates rules config other)

classify_file() {
  local f="$1"
  case "$f" in
    contracts/*)  echo "contracts" ;;
    scripts/*)    echo "scripts" ;;
    commands/*)   echo "commands" ;;
    skills/*)     echo "skills" ;;
    templates/*)  echo "templates" ;;
    rules/*)      echo "rules" ;;
    .cursor/rules/*|.cursor/skills/*) echo "config" ;;
    .prettierrc*|.eslintrc*|package.json|pnpm-lock.yaml|tsconfig*) echo "config" ;;
    *)            echo "other" ;;
  esac
}

for cat in "${CATEGORIES[@]}"; do
  CATEGORY_FILES[$cat]=""
done

while IFS= read -r file; do
  [ -z "$file" ] && continue
  cat="$(classify_file "$file")"
  if [ -z "${CATEGORY_FILES[$cat]}" ]; then
    CATEGORY_FILES[$cat]="$file"
  else
    CATEGORY_FILES[$cat]="${CATEGORY_FILES[$cat]}"$'\n'"$file"
  fi
done <<< "$CHANGED_FILES"

category_count() {
  local val="${CATEGORY_FILES[$1]:-}"
  if [ -z "$val" ]; then
    echo 0
  else
    echo "$val" | grep -c . || true
  fi
}

# ---------------------------------------------------------------------------
# Identify transient/generated artifacts
# ---------------------------------------------------------------------------

TRANSIENT_PATTERNS=(
  "^\.ralph/"
  "^progress\.txt$"
  "^run-log\.jsonl$"
  "^assumptions-log\.jsonl$"
  "^\.cursor/ralph/"
  "^\.cursor/plans/"
  "^\.ralph/squash-artifacts/"
)

TRANSIENT_FILES=""
CANONICAL_FILES=""

while IFS= read -r file; do
  [ -z "$file" ] && continue
  is_transient=false
  for pat in "${TRANSIENT_PATTERNS[@]}"; do
    if echo "$file" | grep -qE "$pat"; then
      is_transient=true
      break
    fi
  done
  if $is_transient; then
    if [ -z "$TRANSIENT_FILES" ]; then
      TRANSIENT_FILES="$file"
    else
      TRANSIENT_FILES="$TRANSIENT_FILES"$'\n'"$file"
    fi
  else
    if [ -z "$CANONICAL_FILES" ]; then
      CANONICAL_FILES="$file"
    else
      CANONICAL_FILES="$CANONICAL_FILES"$'\n'"$file"
    fi
  fi
done <<< "$CHANGED_FILES"

TRANSIENT_COUNT=0
CANONICAL_COUNT=0
if [ -n "$TRANSIENT_FILES" ]; then
  TRANSIENT_COUNT="$(echo "$TRANSIENT_FILES" | grep -c . || true)"
fi
if [ -n "$CANONICAL_FILES" ]; then
  CANONICAL_COUNT="$(echo "$CANONICAL_FILES" | grep -c . || true)"
fi

# Also check for untracked transients in the worktree
UNTRACKED_TRANSIENTS=""
for pat_dir in .ralph progress.txt run-log.jsonl assumptions-log.jsonl; do
  if [ -e "$pat_dir" ]; then
    if [ -d "$pat_dir" ]; then
      count="$(find "$pat_dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
      if [ -z "$UNTRACKED_TRANSIENTS" ]; then
        UNTRACKED_TRANSIENTS="$pat_dir/ ($count files)"
      else
        UNTRACKED_TRANSIENTS="$UNTRACKED_TRANSIENTS"$'\n'"$pat_dir/ ($count files)"
      fi
    else
      if [ -z "$UNTRACKED_TRANSIENTS" ]; then
        UNTRACKED_TRANSIENTS="$pat_dir"
      else
        UNTRACKED_TRANSIENTS="$UNTRACKED_TRANSIENTS"$'\n'"$pat_dir"
      fi
    fi
  fi
done

# ---------------------------------------------------------------------------
# Suggest cleanup actions
# ---------------------------------------------------------------------------

CLEANUP_ACTIONS=""

add_action() {
  if [ -z "$CLEANUP_ACTIONS" ]; then
    CLEANUP_ACTIONS="$1"
  else
    CLEANUP_ACTIONS="$CLEANUP_ACTIONS"$'\n'"$1"
  fi
}

if [ "$TRANSIENT_COUNT" -gt 0 ] || [ -n "$UNTRACKED_TRANSIENTS" ]; then
  add_action "DELETE transient artifacts: .ralph/, progress.txt, run-log.jsonl, assumptions-log.jsonl"
fi

if echo "$CHANGED_FILES" | grep -qE "^\.cursor/plans/"; then
  add_action "ARCHIVE or DELETE .cursor/plans/ directories (implementation state, not source)"
fi

if echo "$CHANGED_FILES" | grep -qE "^\.cursor/ralph/"; then
  add_action "DELETE .cursor/ralph/ runtime state"
fi

if [ "$COMMIT_COUNT" -gt 20 ]; then
  add_action "SQUASH commits ($COMMIT_COUNT total) for a cleaner merge history"
fi

if [ "$CANONICAL_COUNT" -gt 0 ]; then
  add_action "REVIEW $CANONICAL_COUNT canonical source changes for completeness and consistency"
fi

add_action "RUN validation suite (pnpm lint, pnpm format --check, scripts/check-ralph-drift.sh)"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

output_text() {
  local out=""
  out+="╔══════════════════════════════════════════════════════════════╗"$'\n'
  out+="║           Branch Divergence Report                         ║"$'\n'
  out+="╚══════════════════════════════════════════════════════════════╝"$'\n'
  out+=""$'\n'
  out+="Branch:      $BRANCH"$'\n'
  out+="Base:        $BASE"$'\n'
  out+="Merge-base:  $MERGE_BASE_SHORT ($MERGE_BASE)"$'\n'
  out+="Branch HEAD: $BRANCH_HEAD_SHORT ($BRANCH_HEAD)"$'\n'
  out+="Generated:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")"$'\n'
  out+=""$'\n'
  out+="── Summary ────────────────────────────────────────────────────"$'\n'
  out+="  Commits since merge-base: $COMMIT_COUNT"$'\n'
  out+="  Changed files (total):    $CHANGED_FILE_COUNT"$'\n'
  out+="  Canonical source files:   $CANONICAL_COUNT"$'\n'
  out+="  Transient artifacts:      $TRANSIENT_COUNT"$'\n'
  out+="  Diff stat: $DIFF_STAT"$'\n'
  out+=""$'\n'
  out+="── File Breakdown by Category ─────────────────────────────────"$'\n'
  for cat in "${CATEGORIES[@]}"; do
    local cnt
    cnt="$(category_count "$cat")"
    if [ "$cnt" -gt 0 ]; then
      out+="  $cat: $cnt"$'\n'
      local files="${CATEGORY_FILES[$cat]}"
      while IFS= read -r f; do
        out+="    $f"$'\n'
      done <<< "$files"
    fi
  done
  out+=""$'\n'
  out+="── Transient / Generated Artifacts ────────────────────────────"$'\n'
  if [ "$TRANSIENT_COUNT" -gt 0 ]; then
    out+="  In diff ($TRANSIENT_COUNT files):"$'\n'
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      out+="    $f"$'\n'
    done <<< "$TRANSIENT_FILES"
  else
    out+="  None in diff."$'\n'
  fi
  if [ -n "$UNTRACKED_TRANSIENTS" ]; then
    out+=""$'\n'
    out+="  Untracked in worktree:"$'\n'
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      out+="    $f"$'\n'
    done <<< "$UNTRACKED_TRANSIENTS"
  fi
  out+=""$'\n'
  out+="── Commits ────────────────────────────────────────────────────"$'\n'
  out+="$COMMITS"$'\n'
  out+=""$'\n'
  out+="── Suggested Cleanup Actions ──────────────────────────────────"$'\n'
  local idx=1
  while IFS= read -r action; do
    [ -z "$action" ] && continue
    out+="  $idx. $action"$'\n'
    idx=$((idx + 1))
  done <<< "$CLEANUP_ACTIONS"
  out+=""$'\n'
  out+="══════════════════════════════════════════════════════════════"$'\n'

  echo "$out"
}

output_json() {
  # Build category breakdown as JSON object
  local cat_json="{"
  local first=true
  for cat in "${CATEGORIES[@]}"; do
    local cnt
    cnt="$(category_count "$cat")"
    local files_json="[]"
    if [ "$cnt" -gt 0 ]; then
      files_json="["
      local ffirst=true
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        if $ffirst; then
          files_json+="\"$f\""
          ffirst=false
        else
          files_json+=",\"$f\""
        fi
      done <<< "${CATEGORY_FILES[$cat]}"
      files_json+="]"
    fi
    if $first; then
      cat_json+="\"$cat\":{\"count\":$cnt,\"files\":$files_json}"
      first=false
    else
      cat_json+=",\"$cat\":{\"count\":$cnt,\"files\":$files_json}"
    fi
  done
  cat_json+="}"

  # Build transient files array
  local trans_json="[]"
  if [ "$TRANSIENT_COUNT" -gt 0 ]; then
    trans_json="["
    local tfirst=true
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if $tfirst; then
        trans_json+="\"$f\""
        tfirst=false
      else
        trans_json+=",\"$f\""
      fi
    done <<< "$TRANSIENT_FILES"
    trans_json+="]"
  fi

  # Build canonical files array
  local canon_json="[]"
  if [ "$CANONICAL_COUNT" -gt 0 ]; then
    canon_json="["
    local cfirst=true
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if $cfirst; then
        canon_json+="\"$f\""
        cfirst=false
      else
        canon_json+=",\"$f\""
      fi
    done <<< "$CANONICAL_FILES"
    canon_json+="]"
  fi

  # Build untracked transients array
  local untracked_json="[]"
  if [ -n "$UNTRACKED_TRANSIENTS" ]; then
    untracked_json="["
    local ufirst=true
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if $ufirst; then
        untracked_json+="\"$f\""
        ufirst=false
      else
        untracked_json+=",\"$f\""
      fi
    done <<< "$UNTRACKED_TRANSIENTS"
    untracked_json+="]"
  fi

  # Build commits array
  local commits_json="["
  local cofirst=true
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local sha="${line%% *}"
    local msg="${line#* }"
    msg="${msg//\\/\\\\}"
    msg="${msg//\"/\\\"}"
    if $cofirst; then
      commits_json+="{\"sha\":\"$sha\",\"message\":\"$msg\"}"
      cofirst=false
    else
      commits_json+=",{\"sha\":\"$sha\",\"message\":\"$msg\"}"
    fi
  done <<< "$COMMITS"
  commits_json+="]"

  # Build cleanup actions array
  local actions_json="["
  local afirst=true
  while IFS= read -r action; do
    [ -z "$action" ] && continue
    action="${action//\\/\\\\}"
    action="${action//\"/\\\"}"
    if $afirst; then
      actions_json+="\"$action\""
      afirst=false
    else
      actions_json+=",\"$action\""
    fi
  done <<< "$CLEANUP_ACTIONS"
  actions_json+="]"

  cat <<ENDJSON
{
  "branch": "$BRANCH",
  "base": "$BASE",
  "mergeBase": "$MERGE_BASE",
  "branchHead": "$BRANCH_HEAD",
  "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
    "commitCount": $COMMIT_COUNT,
    "changedFileCount": $CHANGED_FILE_COUNT,
    "canonicalFileCount": $CANONICAL_COUNT,
    "transientFileCount": $TRANSIENT_COUNT,
    "diffStat": "$(echo "$DIFF_STAT" | sed 's/"/\\"/g')"
  },
  "categories": $cat_json,
  "transientArtifacts": {
    "inDiff": $trans_json,
    "untrackedInWorktree": $untracked_json
  },
  "canonicalFiles": $canon_json,
  "commits": $commits_json,
  "suggestedCleanupActions": $actions_json
}
ENDJSON
}

emit() {
  if [ "$FORMAT" = "json" ]; then
    output_json
  else
    output_text
  fi
}

if [ -n "$OUTPUT" ]; then
  mkdir -p "$(dirname "$OUTPUT")"
  emit > "$OUTPUT"
  echo "Report written to $OUTPUT"
else
  emit
fi
