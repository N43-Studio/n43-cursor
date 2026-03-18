#!/usr/bin/env bash
#
# generate-squash-artifacts.sh — End-to-end squash artifact orchestrator.
#
# Wraps the four-phase squash workflow for Ralph-heavy branches:
#   Phase 1: Pre-squash plan   → squash-plan.json
#   Phase 2: Squash execution  → commit-mapping.json  (on a temp branch)
#   Phase 3: Equivalence check → equivalence-report.json (tree SHA + optional validations)
#   Phase 4: PR summary        → pr-summary.json, pr-summary.md
#
# Safe to run repeatedly: temp branches are cleaned up on failure, original
# branch is never mutated.
#
# Usage:
#   scripts/generate-squash-artifacts.sh --branch <name> [--base <ref>] [--output-dir <path>]
#
# Examples:
#   scripts/generate-squash-artifacts.sh --branch feature/ralph-wiggum-flow
#   scripts/generate-squash-artifacts.sh --branch feature/foo --base develop
#   scripts/generate-squash-artifacts.sh --branch feature/bar --output-dir .ralph/squash-artifacts
#   scripts/generate-squash-artifacts.sh --branch feature/baz --skip-validation
#   scripts/generate-squash-artifacts.sh --branch feature/qux --plan-only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── Defaults ────────────────────────────────────────────────────────────────

BRANCH=""
BASE=""
OUTPUT_DIR=".ralph/squash-artifacts"
ISSUE_ID=""
STRATEGY=""
RATIONALE=""
SKIP_VALIDATION=false
PLAN_ONLY=false
DRY_RUN=false

# ── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: scripts/generate-squash-artifacts.sh [options]

Options:
  --branch <name>        Branch to squash (required)
  --base <ref>           Base ref (default: upstream tracking branch, then origin/main)
  --output-dir <path>    Artifact output root (default: .ralph/squash-artifacts)
  --issue-id <id>        Linear issue id (e.g. N43-473)
  --strategy <s>         Force strategy: single|grouped|split (default: auto-detect)
  --rationale <text>     Squash rationale for plan/summary artifacts
  --skip-validation      Skip lint/typecheck/test/build validation checks
  --plan-only            Only emit Phase 1 plan artifact, skip squash execution
  --dry-run              Show what would happen without creating branches or artifacts
  --help                 Show this help

Examples:
  scripts/generate-squash-artifacts.sh --branch feature/ralph-wiggum-flow
  scripts/generate-squash-artifacts.sh --branch feature/foo --base develop --issue-id N43-100
  scripts/generate-squash-artifacts.sh --branch feature/bar --plan-only
USAGE
}

# ── Arg parsing ─────────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --branch)          shift; BRANCH="${1:-}" ;;
    --base)            shift; BASE="${1:-}" ;;
    --output-dir)      shift; OUTPUT_DIR="${1:-}" ;;
    --issue-id)        shift; ISSUE_ID="${1:-}" ;;
    --strategy)        shift; STRATEGY="${1:-}" ;;
    --rationale)       shift; RATIONALE="${1:-}" ;;
    --skip-validation) SKIP_VALIDATION=true ;;
    --plan-only)       PLAN_ONLY=true ;;
    --dry-run)         DRY_RUN=true ;;
    --help|-h)         usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$BRANCH" ]; then
  echo "error: --branch is required" >&2
  usage >&2
  exit 1
fi

# ── Resolve base ref ───────────────────────────────────────────────────────

if [ -z "$BASE" ]; then
  upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$BRANCH" 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    BASE="$upstream"
  elif git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
    BASE="origin/main"
  elif git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    BASE="main"
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    BASE="master"
  else
    echo "error: could not infer base ref; pass --base explicitly" >&2
    exit 1
  fi
fi

# ── Pre-flight checks ──────────────────────────────────────────────────────

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || {
  echo "error: not in a git repository" >&2; exit 1
}

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working directory has uncommitted changes; commit or stash first" >&2
  exit 1
fi

git rev-parse --verify "$BRANCH" > /dev/null 2>&1 || {
  echo "error: branch '$BRANCH' does not exist" >&2; exit 1
}

git rev-parse --verify "$BASE" > /dev/null 2>&1 || {
  echo "error: base ref '$BASE' does not exist" >&2; exit 1
}

MERGE_BASE="$(git merge-base "$BASE" "$BRANCH" 2>/dev/null)" || {
  echo "error: could not compute merge-base between '$BASE' and '$BRANCH'" >&2
  exit 1
}

COMMIT_COUNT="$(git rev-list --count "$MERGE_BASE".."$BRANCH")"
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "Nothing to squash: $BRANCH has no commits ahead of $BASE."
  exit 0
fi

SQUASH_BRANCH="${BRANCH}-squash"
PARENT_SHORT="$(echo "$BASE" | sed 's|^origin/||')"
ORIGINAL_BRANCH="$(git branch --show-current)"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Squash Artifact Generator                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Branch:      $BRANCH"
echo "  Base:        $BASE"
echo "  Merge-base:  ${MERGE_BASE:0:12}"
echo "  Commits:     $COMMIT_COUNT"
echo "  Squash to:   $SQUASH_BRANCH"
echo "  Output:      $OUTPUT_DIR"
echo ""

if $DRY_RUN; then
  echo "[dry-run] Would generate artifacts for $COMMIT_COUNT commits."
  echo "[dry-run] Squash branch: $SQUASH_BRANCH"
  echo "[dry-run] Output directory: $OUTPUT_DIR"
  exit 0
fi

# ── Helper: cleanup on failure ──────────────────────────────────────────────

TEMP_BRANCH_CREATED=false

cleanup() {
  if $TEMP_BRANCH_CREATED; then
    echo ""
    echo "Cleaning up: returning to $ORIGINAL_BRANCH, deleting temp branch..."
    git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    git branch -D "$SQUASH_BRANCH" 2>/dev/null || true
  fi
}

trap cleanup ERR

# ── Build JS artifact generator args ────────────────────────────────────────

js_base_args=(
  --branch "$BRANCH"
  --parent "$PARENT_SHORT"
  --merge-base "$MERGE_BASE"
  --squash-branch "$SQUASH_BRANCH"
  --output-dir "$OUTPUT_DIR"
)

if [ -n "$ISSUE_ID" ]; then
  js_base_args+=(--issue-id "$ISSUE_ID")
fi

if [ -n "$STRATEGY" ]; then
  js_base_args+=(--strategy "$STRATEGY")
fi

if [ -n "$RATIONALE" ]; then
  js_base_args+=(--rationale "$RATIONALE")
fi

# ── Phase 1: Pre-squash plan ───────────────────────────────────────────────

echo "── Phase 1: Pre-squash plan ────────────────────────────────────"

PRE_OUTPUT="$(node "$SCRIPT_DIR/generate-squash-artifacts.js" --phase pre "${js_base_args[@]}")"
echo "$PRE_OUTPUT" | head -20
echo ""

PLAN_PATH="$(echo "$PRE_OUTPUT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).plan_path)")"
echo "  Plan artifact: $PLAN_PATH"

if $PLAN_ONLY; then
  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo "  Plan-only mode: stopping after Phase 1."
  echo "  Artifacts: $PLAN_PATH"
  exit 0
fi

# ── Phase 2: Squash execution ──────────────────────────────────────────────

echo ""
echo "── Phase 2: Squash execution ───────────────────────────────────"

if git show-ref --verify --quiet "refs/heads/$SQUASH_BRANCH"; then
  echo "  Squash branch '$SQUASH_BRANCH' already exists, deleting..."
  git branch -D "$SQUASH_BRANCH"
fi

git checkout -b "$SQUASH_BRANCH" "$BRANCH"
TEMP_BRANCH_CREATED=true
echo "  Created squash branch: $SQUASH_BRANCH"

git reset --soft "$MERGE_BASE"

COMMIT_SUBJECTS="$(git log --format='- %s' "$MERGE_BASE".."$BRANCH" | head -20)"
SQUASH_MSG="squash($BRANCH): consolidate $COMMIT_COUNT commits

$COMMIT_SUBJECTS"

if [ -n "$ISSUE_ID" ]; then
  SQUASH_MSG="$SQUASH_MSG

Refs: $ISSUE_ID"
fi

git commit -m "$SQUASH_MSG"
echo "  Squashed $COMMIT_COUNT commits into 1"

NEW_COMMIT="$(git rev-parse HEAD)"
echo "  New commit: ${NEW_COMMIT:0:12}"

# ── Phase 3: Equivalence verification ──────────────────────────────────────

echo ""
echo "── Phase 3: Equivalence verification ───────────────────────────"

ORIGINAL_TREE="$(git rev-parse "$BRANCH^{tree}")"
SQUASH_TREE="$(git rev-parse "$SQUASH_BRANCH^{tree}")"

if [ "$ORIGINAL_TREE" = "$SQUASH_TREE" ]; then
  echo "  Tree equivalence: PASS"
  echo "    Original tree: ${ORIGINAL_TREE:0:12}"
  echo "    Squash tree:   ${SQUASH_TREE:0:12}"
else
  echo "  Tree equivalence: FAIL"
  echo "    Original tree: ${ORIGINAL_TREE:0:12}"
  echo "    Squash tree:   ${SQUASH_TREE:0:12}"
  echo ""
  echo "  Differing files:"
  git diff --name-only "$BRANCH" "$SQUASH_BRANCH" | sed 's/^/    /'
fi

LINT_STATUS="skipped"
TYPECHECK_STATUS="skipped"
TEST_STATUS="skipped"
BUILD_STATUS="skipped"

if ! $SKIP_VALIDATION; then
  echo ""
  echo "  Running validation checks..."

  if [ -f "package.json" ]; then
    if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.lint?0:1)" 2>/dev/null; then
      echo "    lint..."
      if pnpm lint --quiet 2>/dev/null; then
        LINT_STATUS="pass"
      else
        LINT_STATUS="fail"
      fi
      echo "      lint: $LINT_STATUS"
    fi

    if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.typecheck?0:1)" 2>/dev/null; then
      echo "    typecheck..."
      if pnpm typecheck 2>/dev/null; then
        TYPECHECK_STATUS="pass"
      else
        TYPECHECK_STATUS="fail"
      fi
      echo "      typecheck: $TYPECHECK_STATUS"
    fi

    if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.test?0:1)" 2>/dev/null; then
      echo "    test..."
      if pnpm test 2>/dev/null; then
        TEST_STATUS="pass"
      else
        TEST_STATUS="fail"
      fi
      echo "      test: $TEST_STATUS"
    fi

    if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.build?0:1)" 2>/dev/null; then
      echo "    build..."
      if pnpm build 2>/dev/null; then
        BUILD_STATUS="pass"
      else
        BUILD_STATUS="fail"
      fi
      echo "      build: $BUILD_STATUS"
    fi
  else
    echo "    No package.json found; skipping validation."
  fi
fi

# ── Phase 4: Post-squash artifacts (mapping, verification, PR summary) ─────

echo ""
echo "── Phase 4: PR summary & artifact generation ───────────────────"

POST_OUTPUT="$(node "$SCRIPT_DIR/generate-squash-artifacts.js" \
  --phase post \
  "${js_base_args[@]}" \
  --validation-lint "$LINT_STATUS" \
  --validation-typecheck "$TYPECHECK_STATUS" \
  --validation-test "$TEST_STATUS" \
  --validation-build "$BUILD_STATUS")"

MAPPING_PATH="$(echo "$POST_OUTPUT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).mapping_path)")"
VERIFICATION_PATH="$(echo "$POST_OUTPUT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).verification_path)")"
PR_SUMMARY_MD_PATH="$(echo "$POST_OUTPUT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).pr_summary_markdown_path)")"
PR_SUMMARY_JSON_PATH="$(echo "$POST_OUTPUT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).pr_summary_json_path)")"

echo "  Commit mapping:      $MAPPING_PATH"
echo "  Verification:        $VERIFICATION_PATH"
echo "  PR summary (JSON):   $PR_SUMMARY_JSON_PATH"
echo "  PR summary (MD):     $PR_SUMMARY_MD_PATH"

# ── Return to original branch ──────────────────────────────────────────────

git checkout "$ORIGINAL_BRANCH" 2>/dev/null || git checkout "$BRANCH"
TEMP_BRANCH_CREATED=false

echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  Squash complete."
echo ""
echo "  Artifacts:"
echo "    Plan:           $PLAN_PATH"
echo "    Commit mapping: $MAPPING_PATH"
echo "    Verification:   $VERIFICATION_PATH"
echo "    PR summary:     $PR_SUMMARY_MD_PATH"
echo ""
echo "  Squash branch: $SQUASH_BRANCH (not pushed)"
echo ""
echo "  Next steps:"
echo "    1. Review artifacts:  cat $PR_SUMMARY_MD_PATH"
echo "    2. Push squash branch: git push -u origin $SQUASH_BRANCH"
echo "    3. Open PR from:       $SQUASH_BRANCH → $PARENT_SHORT"
echo ""
