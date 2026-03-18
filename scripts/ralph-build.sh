#!/usr/bin/env bash
#
# Ralph build pipeline: chains create-project -> populate-project ->
# generate-prd-from-project -> audit-project as a single-entry setup flow.
#
# Phases 1-2 (create/populate) require Linear MCP and are interactive.
# When --project-id is supplied, Phase 1 is skipped.
# Build state is persisted to enable resumption.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GOAL=""
TEAM="Studio"
PROJECT_ID=""
PROJECT_NAME=""
PROJECT_URL=""
DRY_RUN="false"
STOP_AT=""
OUTPUT_PATH=""
BRANCH=""
INCLUDE_DONE="false"
AUDIT_MODE="read-only"
PREFLIGHT_QUESTION_SCAN="true"
TARGET_DATE=""
STATE=""
ISSUE_COUNT=""

VALID_STOP_AT="create populate generate-prd audit"

usage() {
  cat <<'EOF'
Usage: scripts/ralph-build.sh --goal <text> [options]

Chains Ralph setup phases: create-project -> populate-project ->
generate-prd-from-project -> audit-project.

Options:
  --goal <text>           Description of what to build (required unless --project-id)
  --team <name>           Linear team name (default: Studio)
  --project-id <id>       Resume from existing project (skip create phase)
  --dry-run               Show phase plan without executing
  --stop-at <phase>       Stop after phase: create|populate|generate-prd|audit
  --output <path>         PRD output path (default: .cursor/ralph/<slug>/prd.json)
  --branch <name>         Branch name for PRD (default: feature/<slug>)
  --include-done          Include done issues in PRD generation
  --audit-mode <mode>     read-only|propose-fixes (default: read-only)
  --preflight-question-scan <bool>  true|false (default: true)
  --target-date <date>    Target date YYYY-MM-DD for project creation
  --state <state>         Target state for populate phase
  --issue-count <num>     Soft target issue count for populate phase
  --help                  Show this help
EOF
}

fail() {
  echo "ERROR: $1" >&2
  exit "${2:-1}"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

slugify() {
  local raw="$1"
  if [ -z "$raw" ]; then
    printf 'default\n'
    return
  fi
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

abs_path() {
  local input="$1"
  if [ "${input#/}" != "$input" ]; then
    printf '%s\n' "$input"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$input"
  fi
}

is_valid_stop_at() {
  local val="$1"
  for v in $VALID_STOP_AT; do
    if [ "$v" = "$val" ]; then
      return 0
    fi
  done
  return 1
}

phase_index() {
  case "$1" in
    create) echo 0 ;;
    populate) echo 1 ;;
    generate-prd) echo 2 ;;
    audit) echo 3 ;;
    *) echo 99 ;;
  esac
}

should_execute_phase() {
  local phase="$1"
  if [ -z "$STOP_AT" ]; then
    return 0
  fi
  local stop_idx
  local phase_idx
  stop_idx="$(phase_index "$STOP_AT")"
  phase_idx="$(phase_index "$phase")"
  [ "$phase_idx" -le "$stop_idx" ]
}

emit_phase() {
  local phase="$1"
  local status="$2"
  local extra="${3:-}"
  local timestamp
  timestamp="$(now_iso)"
  if [ -n "$extra" ]; then
    echo "BUILD_PHASE timestamp=$timestamp phase=$phase status=$status $extra"
  else
    echo "BUILD_PHASE timestamp=$timestamp phase=$phase status=$status"
  fi
}

write_build_state() {
  local state_path="$1"
  local create_status="$2"
  local create_at="${3:-null}"
  local populate_status="$4"
  local populate_at="${5:-null}"
  local gen_prd_status="$6"
  local gen_prd_at="${7:-null}"
  local audit_status="$8"
  local audit_at="${9:-null}"

  mkdir -p "$(dirname "$state_path")"

  jq -n \
    --arg goal "$GOAL" \
    --arg project_id "$PROJECT_ID" \
    --arg project_name "$PROJECT_NAME" \
    --arg project_url "$PROJECT_URL" \
    --arg team "$TEAM" \
    --arg prd_path "${PRD_PATH:-}" \
    --arg create_status "$create_status" \
    --arg create_at "$create_at" \
    --arg populate_status "$populate_status" \
    --arg populate_at "$populate_at" \
    --arg gen_prd_status "$gen_prd_status" \
    --arg gen_prd_at "$gen_prd_at" \
    --arg audit_status "$audit_status" \
    --arg audit_at "$audit_at" \
    '
    {
      goal: $goal,
      project_id: (if $project_id == "" then null else $project_id end),
      project_name: (if $project_name == "" then null else $project_name end),
      project_url: (if $project_url == "" then null else $project_url end),
      team: $team,
      prd_path: (if $prd_path == "" then null else $prd_path end),
      phases: {
        create: {
          status: $create_status,
          completed_at: (if $create_at == "null" then null else $create_at end)
        },
        populate: {
          status: $populate_status,
          completed_at: (if $populate_at == "null" then null else $populate_at end)
        },
        generate_prd: {
          status: $gen_prd_status,
          completed_at: (if $gen_prd_at == "null" then null else $gen_prd_at end)
        },
        audit: {
          status: $audit_status,
          completed_at: (if $audit_at == "null" then null else $audit_at end)
        }
      }
    }' > "$state_path"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --goal)
      shift; GOAL="${1:-}"; ;;
    --team)
      shift; TEAM="${1:-}"; ;;
    --project-id)
      shift; PROJECT_ID="${1:-}"; ;;
    --dry-run)
      DRY_RUN="true"; ;;
    --stop-at)
      shift; STOP_AT="${1:-}"; ;;
    --output)
      shift; OUTPUT_PATH="${1:-}"; ;;
    --branch)
      shift; BRANCH="${1:-}"; ;;
    --include-done)
      INCLUDE_DONE="true"; ;;
    --audit-mode)
      shift; AUDIT_MODE="${1:-}"; ;;
    --preflight-question-scan)
      shift; PREFLIGHT_QUESTION_SCAN="${1:-}"; ;;
    --target-date)
      shift; TARGET_DATE="${1:-}"; ;;
    --state)
      shift; STATE="${1:-}"; ;;
    --issue-count)
      shift; ISSUE_COUNT="${1:-}"; ;;
    --help|-h)
      usage; exit 0; ;;
    *)
      fail "unknown argument: $1"; ;;
  esac
  shift
done

if [ -z "$GOAL" ] && [ -z "$PROJECT_ID" ]; then
  fail "one of --goal or --project-id is required"
fi

if [ -n "$STOP_AT" ] && ! is_valid_stop_at "$STOP_AT"; then
  fail "--stop-at must be one of: create, populate, generate-prd, audit"
fi

command -v jq >/dev/null 2>&1 || fail "jq is required"

project_slug=""
if [ -n "$PROJECT_ID" ]; then
  project_slug="$(slugify "$PROJECT_ID")"
elif [ -n "$GOAL" ]; then
  project_slug="$(slugify "$GOAL" | cut -c1-40)"
fi
if [ -z "$project_slug" ]; then
  project_slug="default"
fi

BUILD_STATE_DIR=".cursor/ralph/${project_slug}"
BUILD_STATE_PATH="${BUILD_STATE_DIR}/build-state.json"
BUILD_STATE_ABS="$(abs_path "$BUILD_STATE_PATH")"

PRD_PATH=""
if [ -n "$OUTPUT_PATH" ]; then
  PRD_PATH="$OUTPUT_PATH"
else
  PRD_PATH="${BUILD_STATE_DIR}/prd.json"
fi

if [ -z "$BRANCH" ]; then
  BRANCH="feature/${project_slug}"
fi

CREATE_STATUS="pending"
CREATE_AT="null"
POPULATE_STATUS="pending"
POPULATE_AT="null"
GEN_PRD_STATUS="pending"
GEN_PRD_AT="null"
AUDIT_STATUS="pending"
AUDIT_AT="null"

if [ -f "$BUILD_STATE_ABS" ]; then
  existing_create="$(jq -r '.phases.create.status // "pending"' "$BUILD_STATE_ABS")"
  existing_create_at="$(jq -r '.phases.create.completed_at // "null"' "$BUILD_STATE_ABS")"
  existing_populate="$(jq -r '.phases.populate.status // "pending"' "$BUILD_STATE_ABS")"
  existing_populate_at="$(jq -r '.phases.populate.completed_at // "null"' "$BUILD_STATE_ABS")"
  existing_gen_prd="$(jq -r '.phases.generate_prd.status // "pending"' "$BUILD_STATE_ABS")"
  existing_gen_prd_at="$(jq -r '.phases.generate_prd.completed_at // "null"' "$BUILD_STATE_ABS")"
  existing_audit="$(jq -r '.phases.audit.status // "pending"' "$BUILD_STATE_ABS")"
  existing_audit_at="$(jq -r '.phases.audit.completed_at // "null"' "$BUILD_STATE_ABS")"
  existing_project_id="$(jq -r '.project_id // ""' "$BUILD_STATE_ABS")"
  existing_project_name="$(jq -r '.project_name // ""' "$BUILD_STATE_ABS")"
  existing_project_url="$(jq -r '.project_url // ""' "$BUILD_STATE_ABS")"
  existing_prd_path="$(jq -r '.prd_path // ""' "$BUILD_STATE_ABS")"

  if [ "$existing_create" = "complete" ]; then
    CREATE_STATUS="complete"
    CREATE_AT="$existing_create_at"
  fi
  if [ "$existing_populate" = "complete" ]; then
    POPULATE_STATUS="complete"
    POPULATE_AT="$existing_populate_at"
  fi
  if [ "$existing_gen_prd" = "complete" ]; then
    GEN_PRD_STATUS="complete"
    GEN_PRD_AT="$existing_gen_prd_at"
  fi
  if [ "$existing_audit" = "complete" ]; then
    AUDIT_STATUS="complete"
    AUDIT_AT="$existing_audit_at"
  fi

  if [ -z "$PROJECT_ID" ] && [ -n "$existing_project_id" ]; then
    PROJECT_ID="$existing_project_id"
  fi
  if [ -z "$PROJECT_NAME" ] && [ -n "$existing_project_name" ]; then
    PROJECT_NAME="$existing_project_name"
  fi
  if [ -z "$PROJECT_URL" ] && [ -n "$existing_project_url" ]; then
    PROJECT_URL="$existing_project_url"
  fi
  if [ -n "$existing_prd_path" ] && [ -z "$OUTPUT_PATH" ]; then
    PRD_PATH="$existing_prd_path"
  fi

  echo "INFO: Loaded existing build state from $BUILD_STATE_PATH"
fi

if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "=== RALPH BUILD - DRY RUN ==="
  echo ""
  echo "Goal:       ${GOAL:-<from existing project>}"
  echo "Team:       $TEAM"
  echo "Project ID: ${PROJECT_ID:-<will be created>}"
  echo "PRD path:   $PRD_PATH"
  echo "Branch:     $BRANCH"
  echo "Stop at:    ${STOP_AT:-<all phases>}"
  echo ""
  echo "Phase Plan:"

  for phase in create populate generate-prd audit; do
    if should_execute_phase "$phase"; then
      case "$phase" in
        create)
          if [ -n "$PROJECT_ID" ]; then
            echo "  1. create-project       -> skip (project already provided: $PROJECT_ID)"
          elif [ "$CREATE_STATUS" = "complete" ]; then
            echo "  1. create-project       -> skip (already complete)"
          else
            echo "  1. create-project       -> will execute"
          fi
          ;;
        populate)
          if [ "$POPULATE_STATUS" = "complete" ]; then
            echo "  2. populate-project     -> skip (already complete)"
          else
            echo "  2. populate-project     -> will execute"
          fi
          ;;
        generate-prd)
          if [ "$GEN_PRD_STATUS" = "complete" ]; then
            echo "  3. generate-prd         -> skip (already complete)"
          else
            echo "  3. generate-prd         -> will execute -> $PRD_PATH"
          fi
          ;;
        audit)
          if [ "$AUDIT_STATUS" = "complete" ]; then
            echo "  4. audit-project        -> skip (already complete)"
          else
            echo "  4. audit-project        -> will execute (mode=$AUDIT_MODE)"
          fi
          ;;
      esac
    else
      echo "  $(phase_index "$phase" | awk '{print $1+1}'). $phase -> skipped (--stop-at $STOP_AT)"
    fi
  done

  echo ""
  echo "Build state: $BUILD_STATE_PATH"
  echo ""
  echo "No changes made (dry run)."
  exit 0
fi

mkdir -p "$(dirname "$BUILD_STATE_ABS")"

# --- Phase 1: create-project ---

if should_execute_phase "create"; then
  if [ -n "$PROJECT_ID" ] || [ "$CREATE_STATUS" = "complete" ]; then
    emit_phase "create-project" "pass" "reason=\"existing project: ${PROJECT_ID}\""
    CREATE_STATUS="complete"
    if [ "$CREATE_AT" = "null" ]; then
      CREATE_AT="$(now_iso)"
    fi
  else
    emit_phase "create-project" "start"
    echo ""
    echo "Phase 1 requires Linear MCP interaction."
    echo "Run the following command in Cursor or Codex, then rerun with --project-id:"
    echo ""
    echo "  /linear/create-project ${GOAL}"
    if [ -n "$TARGET_DATE" ]; then
      echo "    target_date=$TARGET_DATE"
    fi
    echo "    team=$TEAM"
    echo ""
    echo "After the project is created, rerun:"
    echo ""
    echo "  scripts/ralph-build.sh --goal \"$GOAL\" --project-id <project-id> --team $TEAM"
    echo ""

    CREATE_STATUS="failed"
    write_build_state "$BUILD_STATE_ABS" \
      "$CREATE_STATUS" "$CREATE_AT" \
      "$POPULATE_STATUS" "$POPULATE_AT" \
      "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
      "$AUDIT_STATUS" "$AUDIT_AT"

    emit_phase "create-project" "fail" "reason=\"requires MCP interaction; rerun with --project-id\""
    exit 1
  fi
else
  CREATE_STATUS="skipped"
fi

write_build_state "$BUILD_STATE_ABS" \
  "$CREATE_STATUS" "$CREATE_AT" \
  "$POPULATE_STATUS" "$POPULATE_AT" \
  "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
  "$AUDIT_STATUS" "$AUDIT_AT"

# --- Phase 2: populate-project ---

if should_execute_phase "populate"; then
  if [ "$POPULATE_STATUS" = "complete" ]; then
    emit_phase "populate-project" "pass" "reason=\"already complete\""
  else
    emit_phase "populate-project" "start"
    echo ""
    echo "Phase 2 requires Linear MCP interaction."
    echo "Run the following command in Cursor or Codex:"
    echo ""
    echo "  /linear/populate-project project=\"$PROJECT_ID\" team=$TEAM"
    if [ -n "$STATE" ]; then
      echo "    state=$STATE"
    fi
    if [ -n "$ISSUE_COUNT" ]; then
      echo "    issue_count=$ISSUE_COUNT"
    fi
    echo ""
    echo "After issues are populated, rerun this script."
    echo ""

    POPULATE_STATUS="failed"
    write_build_state "$BUILD_STATE_ABS" \
      "$CREATE_STATUS" "$CREATE_AT" \
      "$POPULATE_STATUS" "$POPULATE_AT" \
      "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
      "$AUDIT_STATUS" "$AUDIT_AT"

    emit_phase "populate-project" "fail" "reason=\"requires MCP interaction\""
    exit 1
  fi
else
  POPULATE_STATUS="skipped"
fi

write_build_state "$BUILD_STATE_ABS" \
  "$CREATE_STATUS" "$CREATE_AT" \
  "$POPULATE_STATUS" "$POPULATE_AT" \
  "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
  "$AUDIT_STATUS" "$AUDIT_AT"

# --- Phase 3: generate-prd-from-project ---

if should_execute_phase "generate-prd"; then
  if [ "$GEN_PRD_STATUS" = "complete" ] && [ -f "$(abs_path "$PRD_PATH")" ]; then
    emit_phase "generate-prd" "pass" "reason=\"already complete, prd=$PRD_PATH\""
  else
    emit_phase "generate-prd" "start"
    echo ""
    echo "Phase 3 requires Linear MCP interaction."
    echo "Run the following command in Cursor or Codex:"
    echo ""
    echo "  /linear/generate-prd-from-project project=\"$PROJECT_ID\" team=$TEAM output=$PRD_PATH branch=$BRANCH"
    if [ "$INCLUDE_DONE" = "true" ]; then
      echo "    include_done=true"
    fi
    echo ""
    echo "After PRD is generated, rerun this script."
    echo ""

    GEN_PRD_STATUS="failed"
    write_build_state "$BUILD_STATE_ABS" \
      "$CREATE_STATUS" "$CREATE_AT" \
      "$POPULATE_STATUS" "$POPULATE_AT" \
      "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
      "$AUDIT_STATUS" "$AUDIT_AT"

    emit_phase "generate-prd" "fail" "reason=\"requires MCP interaction\""
    exit 1
  fi
else
  GEN_PRD_STATUS="skipped"
fi

write_build_state "$BUILD_STATE_ABS" \
  "$CREATE_STATUS" "$CREATE_AT" \
  "$POPULATE_STATUS" "$POPULATE_AT" \
  "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
  "$AUDIT_STATUS" "$AUDIT_AT"

# --- Phase 4: audit-project ---

if should_execute_phase "audit"; then
  if [ "$AUDIT_STATUS" = "complete" ]; then
    emit_phase "audit-project" "pass" "reason=\"already complete\""
  else
    emit_phase "audit-project" "start"
    echo ""
    echo "Phase 4 requires Linear MCP interaction."
    echo "Run the following command in Cursor or Codex:"
    echo ""
    echo "  /linear/audit-project project=\"$PROJECT_ID\" team=$TEAM mode=$AUDIT_MODE preflight_question_scan=$PREFLIGHT_QUESTION_SCAN"
    echo ""
    echo "After audit passes, the project is ready for /ralph/run."
    echo ""

    AUDIT_STATUS="failed"
    write_build_state "$BUILD_STATE_ABS" \
      "$CREATE_STATUS" "$CREATE_AT" \
      "$POPULATE_STATUS" "$POPULATE_AT" \
      "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
      "$AUDIT_STATUS" "$AUDIT_AT"

    emit_phase "audit-project" "fail" "reason=\"requires MCP interaction\""
    exit 1
  fi
else
  AUDIT_STATUS="skipped"
fi

write_build_state "$BUILD_STATE_ABS" \
  "$CREATE_STATUS" "$CREATE_AT" \
  "$POPULATE_STATUS" "$POPULATE_AT" \
  "$GEN_PRD_STATUS" "$GEN_PRD_AT" \
  "$AUDIT_STATUS" "$AUDIT_AT"

# --- Completion ---

echo ""
echo "=== RALPH BUILD COMPLETE ==="
echo ""
echo "Project ID:   ${PROJECT_ID:-<unknown>}"
echo "Project Name: ${PROJECT_NAME:-<unknown>}"
echo "PRD Path:     $PRD_PATH"
echo "Build State:  $BUILD_STATE_PATH"
echo ""
echo "Phase Results:"
echo "  1. create-project         $CREATE_STATUS"
echo "  2. populate-project       $POPULATE_STATUS"
echo "  3. generate-prd           $GEN_PRD_STATUS"
echo "  4. audit-project          $AUDIT_STATUS"
echo ""

PRD_ABS="$(abs_path "$PRD_PATH")"
if [ -f "$PRD_ABS" ]; then
  echo "Next step:"
  echo "  scripts/ralph-run.sh --prd \"$PRD_PATH\""
else
  echo "PRD not found at $PRD_PATH — run generate-prd phase first."
fi
