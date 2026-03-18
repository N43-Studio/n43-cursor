#!/usr/bin/env bash
#
# Safely decompose an umbrella issue by unparenting children before terminalization.
# Prevents Linear's parent-cancel cascade from auto-canceling replacement children.
#

set -euo pipefail

PARENT_ID=""
STRATEGY="done"
DRY_RUN=false
LINEAR_MCP_SERVER="user-Linear"

usage() {
  cat <<'EOF'
Usage: scripts/safe-decompose-issue.sh [options]

Safely decompose an umbrella issue by neutralizing parent-child links before
terminalizing the parent. Prevents Linear's cascade cancellation behavior.

Options:
  --parent <issue-id>          Parent/umbrella issue identifier (required, e.g., N43-467)
  --strategy <done|cancel>     Terminalization strategy (default: done)
  --dry-run                    Preview actions without executing
  --help                       Show this help

Strategies:
  done    - Mark parent as Done (safest; Done does not cascade to children)
  cancel  - Unparent all children first, then Cancel the parent

See: contracts/ralph/core/issue-decomposition-safety.md
EOF
}

log() {
  echo "[safe-decompose] $*" >&2
}

die() {
  echo "[safe-decompose] ERROR: $*" >&2
  exit 1
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --parent) shift; PARENT_ID="${1:-}" ;;
    --strategy) shift; STRATEGY="${1:-}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

if [ -z "$PARENT_ID" ]; then
  usage >&2
  exit 1
fi

case "$STRATEGY" in
  done|cancel) ;;
  *) die "invalid strategy '${STRATEGY}' — must be 'done' or 'cancel'" ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  die "jq is required"
fi

actions='[]'
errors='[]'

add_action() {
  local action="$1"
  local target="$2"
  local detail="$3"
  actions="$(jq -c --arg a "$action" --arg t "$target" --arg d "$detail" \
    '. + [{"action": $a, "target": $t, "detail": $d}]' <<< "$actions")"
}

add_error() {
  local msg="$1"
  errors="$(jq -c --arg m "$msg" '. + [$m]' <<< "$errors")"
}

log "fetching parent issue ${PARENT_ID}..."

parent_json="$(cursor-mcp-call "${LINEAR_MCP_SERVER}" get_issue "{\"id\": \"${PARENT_ID}\"}" 2>/dev/null || true)"

if [ -z "$parent_json" ] || ! jq -e '.' <<< "$parent_json" >/dev/null 2>&1; then
  log "NOTE: Linear MCP not available in this context."
  log "This script is designed to be invoked by an agent with MCP access."
  log ""
  log "Manual equivalent steps for --strategy=${STRATEGY} on ${PARENT_ID}:"
  log ""

  if [ "$STRATEGY" = "done" ]; then
    log "  1. In Linear, set ${PARENT_ID} state to Done"
    log "  2. Add comment: 'Superseded by replacement issues. Marked Done to prevent cascade.'"
  else
    log "  1. In Linear, list all child issues of ${PARENT_ID}"
    log "  2. For each child: edit → remove parent issue (set parentId to null)"
    log "  3. Verify children no longer show as sub-issues of ${PARENT_ID}"
    log "  4. Cancel ${PARENT_ID}"
    log "  5. Add comment: 'Children unparented before cancellation to prevent cascade.'"
  fi

  log ""
  log "Or use the MCP tools directly in a Cursor/Codex agent session:"
  log ""
  log "  # List children"
  log "  CallMcpTool: ${LINEAR_MCP_SERVER} / list_issues"
  log "  Arguments: { \"parentId\": \"${PARENT_ID}\" }"
  log ""

  if [ "$STRATEGY" = "cancel" ]; then
    log "  # Unparent each child"
    log "  CallMcpTool: ${LINEAR_MCP_SERVER} / save_issue"
    log "  Arguments: { \"id\": \"<child-id>\", \"parentId\": null }"
    log ""
  fi

  log "  # Terminalize parent"
  log "  CallMcpTool: ${LINEAR_MCP_SERVER} / save_issue"
  log "  Arguments: { \"id\": \"${PARENT_ID}\", \"state\": \"${STRATEGY}d\" }"

  jq -n -c \
    --arg parent "$PARENT_ID" \
    --arg strategy "$STRATEGY" \
    --argjson dry_run "$DRY_RUN" \
    '{
      parent: $parent,
      strategy: $strategy,
      dry_run: $dry_run,
      outcome: "mcp_unavailable",
      message: "Linear MCP not available — printed manual steps to stderr"
    }'
  exit 0
fi

parent_state="$(jq -r '.state // .status // ""' <<< "$parent_json")"
parent_title="$(jq -r '.title // ""' <<< "$parent_json")"
log "parent: ${PARENT_ID} — \"${parent_title}\" [${parent_state}]"

log "listing children of ${PARENT_ID}..."
children_json="$(cursor-mcp-call "${LINEAR_MCP_SERVER}" list_issues "{\"parentId\": \"${PARENT_ID}\"}" 2>/dev/null || echo '[]')"

if ! jq -e '.' <<< "$children_json" >/dev/null 2>&1; then
  children_json='[]'
fi

child_count="$(jq 'if type == "array" then length else (.issues // []) | length end' <<< "$children_json")"
log "found ${child_count} child issue(s)"

children_array="$(jq -c 'if type == "array" then . else (.issues // []) end' <<< "$children_json")"

canceled_children="$(jq -c '[.[] | select((.state // .status // "") | test("cancel"; "i"))]' <<< "$children_array")"
canceled_count="$(jq 'length' <<< "$canceled_children")"

if [ "$canceled_count" -gt 0 ]; then
  add_error "${canceled_count} child issue(s) are already canceled — decomposition may have already cascaded"
  log "WARNING: ${canceled_count} children already canceled"
fi

child_ids="$(jq -r '.[].identifier // .[].id' <<< "$children_array" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"

if [ "$STRATEGY" = "done" ]; then
  add_action "set_state" "$PARENT_ID" "Done"
  add_action "add_comment" "$PARENT_ID" "Superseded by replacement issues: [${child_ids}]. Marked Done to prevent cascade cancellation of children."

  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] would set ${PARENT_ID} to Done"
    log "[dry-run] would add decomposition comment"
  else
    log "setting ${PARENT_ID} to Done..."
    cursor-mcp-call "${LINEAR_MCP_SERVER}" save_issue "{\"id\": \"${PARENT_ID}\", \"state\": \"Done\"}" >/dev/null 2>&1 || add_error "failed to set parent to Done"

    log "adding comment to ${PARENT_ID}..."
    comment_body="Superseded by replacement issues: ${child_ids}. Marked Done to prevent cascade cancellation of children. See \`contracts/ralph/core/issue-decomposition-safety.md\`."
    cursor-mcp-call "${LINEAR_MCP_SERVER}" save_comment "{\"issueId\": \"${PARENT_ID}\", \"body\": \"${comment_body}\"}" >/dev/null 2>&1 || add_error "failed to add comment"
  fi

elif [ "$STRATEGY" = "cancel" ]; then
  while IFS= read -r child_json; do
    [ -z "$child_json" ] && continue
    child_id="$(jq -r '.identifier // .id // ""' <<< "$child_json")"
    child_state="$(jq -r '.state // .status // ""' <<< "$child_json")"
    [ -z "$child_id" ] && continue

    if printf '%s' "$child_state" | grep -qi "cancel"; then
      log "skipping already-canceled child: ${child_id}"
      continue
    fi

    add_action "unparent" "$child_id" "Remove parentId (was ${PARENT_ID})"

    if [ "$DRY_RUN" = true ]; then
      log "[dry-run] would unparent ${child_id} from ${PARENT_ID}"
    else
      log "unparenting ${child_id}..."
      cursor-mcp-call "${LINEAR_MCP_SERVER}" save_issue "{\"id\": \"${child_id}\", \"parentId\": null}" >/dev/null 2>&1 || add_error "failed to unparent ${child_id}"
    fi
  done < <(jq -c '.[]' <<< "$children_array")

  add_action "set_state" "$PARENT_ID" "Canceled"
  add_action "add_comment" "$PARENT_ID" "Decomposed into replacement issues: [${child_ids}]. Children unparented before cancellation to prevent cascade."

  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] would cancel ${PARENT_ID}"
    log "[dry-run] would add decomposition comment"
  else
    log "canceling ${PARENT_ID}..."
    cursor-mcp-call "${LINEAR_MCP_SERVER}" save_issue "{\"id\": \"${PARENT_ID}\", \"state\": \"Canceled\"}" >/dev/null 2>&1 || add_error "failed to cancel parent"

    log "adding comment to ${PARENT_ID}..."
    comment_body="Decomposed into replacement issues: ${child_ids}. Children unparented before cancellation to prevent cascade. See \`contracts/ralph/core/issue-decomposition-safety.md\`."
    cursor-mcp-call "${LINEAR_MCP_SERVER}" save_comment "{\"issueId\": \"${PARENT_ID}\", \"body\": \"${comment_body}\"}" >/dev/null 2>&1 || add_error "failed to add comment"
  fi
fi

error_count="$(jq 'length' <<< "$errors")"
action_count="$(jq 'length' <<< "$actions")"

if [ "$DRY_RUN" = true ]; then
  outcome="dry_run"
elif [ "$error_count" -gt 0 ]; then
  outcome="completed_with_errors"
else
  outcome="success"
fi

jq -n -c \
  --arg parent "$PARENT_ID" \
  --arg parent_title "$parent_title" \
  --arg strategy "$STRATEGY" \
  --argjson dry_run "$DRY_RUN" \
  --argjson child_count "$child_count" \
  --argjson canceled_children_count "$canceled_count" \
  --arg outcome "$outcome" \
  --argjson action_count "$action_count" \
  --argjson actions "$actions" \
  --argjson errors "$errors" \
  --arg timestamp "$(now_iso)" \
  '{
    parent: $parent,
    parent_title: $parent_title,
    strategy: $strategy,
    dry_run: $dry_run,
    child_count: $child_count,
    canceled_children_found: $canceled_children_count,
    outcome: $outcome,
    action_count: $action_count,
    actions: $actions,
    errors: (if ($errors | length) > 0 then $errors else null end),
    timestamp: $timestamp
  }'
