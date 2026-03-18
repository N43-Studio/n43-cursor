#!/usr/bin/env bash
#
# Deterministic Ralph worktree lifecycle helper for isolated parallel runner execution.
# Commands:
#   create      Provision a deterministic worktree path + branch for a project/track
#   list        Enumerate Ralph-managed worktrees with health status
#   status      Show detailed status for a single worktree
#   prune       Remove a single worktree by path or project/track
#   prune-all   Remove all stale/orphaned worktrees (requires --confirm)
#

set -euo pipefail

STALE_THRESHOLD_SECONDS=$((24 * 60 * 60))

usage() {
  cat <<'USAGE'
Usage:
  scripts/ralph-worktree.sh <command> [options]

Commands:
  create        Create a deterministic worktree for a project runner
  list          List all Ralph-managed worktrees with health status
  status        Show detailed status for a single worktree
  prune         Remove a single worktree and its branch
  prune-all     Remove all stale/orphaned worktrees

Global options:
  --repo <path>           Repository path (default: .)
  --root <path>           Managed worktree root relative to repo (default: .ralph/worktrees)
  --help                  Show usage

create options:
  --project <slug>        Project slug (required)
  --track <id>            Track identifier, e.g. issue id (optional)
  --base <ref>            Base ref for new branch (default: current HEAD branch)

list options:
  --format text|json      Output format (default: json)

status options:
  --path <worktree-path>  Worktree path to inspect
  --project <slug>        Project slug (with --track, resolves path via glob)
  --track <id>            Track identifier (used with --project)

prune options:
  --path <worktree-path>  Worktree path to remove
  --project <slug>        Project slug (with --track, resolves path via glob)
  --track <id>            Track identifier (used with --project)
  --force                 Force removal of active (dirty) worktrees

prune-all options:
  --confirm               Required flag to execute pruning
  --force                 Force removal even for dirty worktrees

Exit codes:
  0   Success
  2   Invalid invocation
  12  Conflict (manual resolution required)
  1   Other error
USAGE
}

fail() {
  local message="$1"
  local code="${2:-1}"
  echo "ERROR: $message" >&2
  exit "$code"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "missing required command: $cmd"
  fi
}

slugify() {
  local raw="$1"
  local slug
  slug="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [ -z "$slug" ]; then
    fail "value cannot be normalized to a slug: $raw"
  fi
  printf '%s\n' "$slug"
}

resolve_path() {
  local base="$1"
  local input="$2"
  if [ "${input#/}" != "$input" ]; then
    printf '%s\n' "$input"
  else
    printf '%s/%s\n' "$base" "$input"
  fi
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
  date +%s
}

fs_timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

git_worktree_records() {
  git -C "$REPO_ROOT_ABS" worktree list --porcelain | awk '
    BEGIN { path = ""; branch = ""; head = ""; prunable = "false" }
    /^worktree / {
      if (path != "") { print path "\t" branch "\t" head "\t" prunable }
      path = substr($0, 10)
      branch = ""; head = ""; prunable = "false"
      next
    }
    /^branch / { branch = $2; sub(/^refs\/heads\//, "", branch); next }
    /^HEAD / { head = $2; next }
    /^prunable/ { prunable = "true"; next }
    END { if (path != "") { print path "\t" branch "\t" head "\t" prunable } }
  '
}

find_record_by_path() {
  local target_path="$1"
  while IFS=$'\t' read -r path branch head prunable; do
    if [ "$path" = "$target_path" ]; then
      printf '%s\t%s\t%s\n' "$branch" "$head" "$prunable"
      return 0
    fi
  done < <(git_worktree_records)
  return 1
}

find_record_by_branch() {
  local target_branch="$1"
  while IFS=$'\t' read -r path branch head prunable; do
    if [ "$branch" = "$target_branch" ]; then
      printf '%s\t%s\t%s\n' "$path" "$head" "$prunable"
      return 0
    fi
  done < <(git_worktree_records)
  return 1
}

resolve_worktree_by_project_track() {
  local project_slug="$1"
  local track_slug="$2"
  local prefix="${project_slug}-${track_slug}-"
  local matches=()

  if [ ! -d "$WORKTREE_ROOT_ABS" ]; then
    return 1
  fi

  for entry in "$WORKTREE_ROOT_ABS"/${prefix}*/; do
    [ -d "$entry" ] || continue
    matches+=("${entry%/}")
  done

  if [ "${#matches[@]}" -eq 0 ]; then
    return 1
  fi

  # Return the most recent (last sorted) match
  local sorted
  sorted="$(printf '%s\n' "${matches[@]}" | sort -r | head -1)"
  printf '%s\n' "$sorted"
}

worktree_health() {
  local wt_path="$1"
  local wt_branch="$2"
  local wt_prunable="$3"

  if [ "$wt_prunable" = "true" ]; then
    printf 'orphaned\n'
    return
  fi

  if [ -z "$wt_branch" ]; then
    printf 'orphaned\n'
    return
  fi

  if ! git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$wt_branch" 2>/dev/null; then
    printf 'orphaned\n'
    return
  fi

  local last_commit_epoch
  last_commit_epoch="$(git -C "$wt_path" log -1 --format='%ct' 2>/dev/null || echo 0)"
  if ! [[ "$last_commit_epoch" =~ ^[0-9]+$ ]]; then
    last_commit_epoch=0
  fi

  local now_ep
  now_ep="$(now_epoch)"
  local age=$((now_ep - last_commit_epoch))

  if [ "$age" -gt "$STALE_THRESHOLD_SECONDS" ]; then
    printf 'stale\n'
  else
    printf 'active\n'
  fi
}

copy_ralph_config() {
  local wt_path="$1"

  local configs=(".cursor/rules" ".prettierrc.json" ".eslintrc.json" ".eslintrc.js" "tsconfig.json" "package.json" "pnpm-lock.yaml")
  for cfg in "${configs[@]}"; do
    local src="$REPO_ROOT_ABS/$cfg"
    if [ -e "$src" ]; then
      local dest="$wt_path/$cfg"
      if [ ! -e "$dest" ]; then
        mkdir -p "$(dirname "$dest")"
        if [ -d "$src" ]; then
          cp -R "$src" "$dest"
        else
          cp "$src" "$dest"
        fi
      fi
    fi
  done
}

# --- Parse command ---

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  usage
  exit 2
fi
shift || true

REPO_PATH="."
WORKTREE_ROOT_REL=".ralph/worktrees"
PROJECT=""
TRACK=""
BASE_REF=""
FORMAT="json"
FORCE="false"
CONFIRM="false"
WT_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)       shift; REPO_PATH="${1:-}" ;;
    --root)       shift; WORKTREE_ROOT_REL="${1:-}" ;;
    --project)    shift; PROJECT="${1:-}" ;;
    --track)      shift; TRACK="${1:-}" ;;
    --base)       shift; BASE_REF="${1:-}" ;;
    --format)     shift; FORMAT="${1:-}" ;;
    --path)       shift; WT_PATH="${1:-}" ;;
    --force)      FORCE="true" ;;
    --confirm)    CONFIRM="true" ;;
    --help|-h)    usage; exit 0 ;;
    *)            fail "unknown argument: $1" 2 ;;
  esac
  shift || true
done

require_cmd git
require_cmd jq

REPO_ROOT_ABS="$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT_ABS" ]; then
  fail "--repo is not inside a git repository: $REPO_PATH"
fi

WORKTREE_ROOT_ABS="$(resolve_path "$REPO_ROOT_ABS" "$WORKTREE_ROOT_REL")"

# --- Subcommands ---

case "$COMMAND" in

  create)
    if [ -z "$PROJECT" ]; then
      fail "create requires --project" 2
    fi

    project_slug="$(slugify "$PROJECT")"
    track_slug=""
    if [ -n "$TRACK" ]; then
      track_slug="$(slugify "$TRACK")"
    fi

    ts="$(fs_timestamp)"

    if [ -n "$track_slug" ]; then
      dir_name="${project_slug}-${track_slug}-${ts}"
      branch_name="ralph/${project_slug}/${track_slug}/${ts}"
    else
      dir_name="${project_slug}-${ts}"
      branch_name="ralph/${project_slug}/${ts}"
    fi

    worktree_path="$WORKTREE_ROOT_ABS/$dir_name"

    if [ -z "$BASE_REF" ]; then
      BASE_REF="$(git -C "$REPO_ROOT_ABS" symbolic-ref --short -q HEAD || git -C "$REPO_ROOT_ABS" rev-parse --short HEAD)"
    fi

    if [ -e "$worktree_path" ]; then
      jq -n \
        --arg status "conflict" \
        --arg worktree_path "$worktree_path" \
        --arg branch "$branch_name" \
        --arg base_ref "$BASE_REF" \
        --arg conflict_reason "path_occupied" \
        --arg message "Target path already exists; no silent overwrite." \
        --arg escalation "manual_resolution_required" \
        --arg next_step "Remove the existing path or choose a different track/project." \
        '{
          status: $status,
          worktree_path: $worktree_path,
          branch: $branch,
          base_ref: $base_ref,
          created_at: null,
          conflict_reason: $conflict_reason,
          message: $message,
          escalation: $escalation,
          next_step: $next_step
        }'
      exit 12
    fi

    if existing_by_branch="$(find_record_by_branch "$branch_name" 2>/dev/null)"; then
      existing_branch_path="${existing_by_branch%%$'\t'*}"
      jq -n \
        --arg status "conflict" \
        --arg worktree_path "$worktree_path" \
        --arg branch "$branch_name" \
        --arg base_ref "$BASE_REF" \
        --arg conflict_reason "branch_in_use" \
        --arg message "Branch is already checked out at $existing_branch_path." \
        --arg escalation "manual_resolution_required" \
        --arg next_step "Resolve branch collision, then rerun create." \
        '{
          status: $status,
          worktree_path: $worktree_path,
          branch: $branch,
          base_ref: $base_ref,
          created_at: null,
          conflict_reason: $conflict_reason,
          message: $message,
          escalation: $escalation,
          next_step: $next_step
        }'
      exit 12
    fi

    mkdir -p "$WORKTREE_ROOT_ABS"

    add_output=""
    set +e
    if git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$branch_name"; then
      add_output="$(git -C "$REPO_ROOT_ABS" worktree add "$worktree_path" "$branch_name" 2>&1)"
      add_rc=$?
    else
      add_output="$(git -C "$REPO_ROOT_ABS" worktree add -b "$branch_name" "$worktree_path" "$BASE_REF" 2>&1)"
      add_rc=$?
    fi
    set -e

    if [ "$add_rc" -ne 0 ]; then
      jq -n \
        --arg status "conflict" \
        --arg worktree_path "$worktree_path" \
        --arg branch "$branch_name" \
        --arg base_ref "$BASE_REF" \
        --arg conflict_reason "git_worktree_conflict" \
        --arg message "$add_output" \
        --arg escalation "manual_resolution_required" \
        --arg next_step "Resolve the git conflict, then rerun create." \
        '{
          status: $status,
          worktree_path: $worktree_path,
          branch: $branch,
          base_ref: $base_ref,
          created_at: null,
          conflict_reason: $conflict_reason,
          message: $message,
          escalation: $escalation,
          next_step: $next_step
        }'
      exit 12
    fi

    copy_ralph_config "$worktree_path"

    created_at="$(now_iso)"
    jq -n \
      --arg worktree_path "$worktree_path" \
      --arg branch "$branch_name" \
      --arg base_ref "$BASE_REF" \
      --arg created_at "$created_at" \
      '{
        worktree_path: $worktree_path,
        branch: $branch,
        base_ref: $base_ref,
        created_at: $created_at
      }'
    ;;

  list)
    if [ "$FORMAT" != "text" ] && [ "$FORMAT" != "json" ]; then
      fail "--format must be text|json" 2
    fi

    entries_json=""
    while IFS=$'\t' read -r path branch head prunable; do
      [ -z "$path" ] && continue

      managed="false"
      dir_name=""
      if [ "$path" = "$WORKTREE_ROOT_ABS" ] || [[ "$path" == "$WORKTREE_ROOT_ABS/"* ]]; then
        managed="true"
        dir_name="$(basename "$path")"
      fi

      if [ "$managed" != "true" ]; then
        continue
      fi

      health="$(worktree_health "$path" "$branch" "$prunable")"

      last_commit_time=""
      if [ -d "$path" ]; then
        last_commit_time="$(git -C "$path" log -1 --format='%ci' 2>/dev/null || echo "unknown")"
      fi

      entry_json="$(jq -n \
        --arg path "$path" \
        --arg branch "$branch" \
        --arg head "$head" \
        --arg status "$health" \
        --arg dir_name "$dir_name" \
        --arg creation_time "$last_commit_time" \
        '{
          path: $path,
          branch: (if $branch == "" then null else $branch end),
          head: $head,
          status: $status,
          dir_name: $dir_name,
          creation_time: $creation_time
        }')"
      entries_json+="$entry_json"$'\n'
    done < <(git_worktree_records)

    if [ -z "$entries_json" ]; then
      entries_array="[]"
    else
      entries_array="$(printf '%s' "$entries_json" | jq -s '.')"
    fi

    if [ "$FORMAT" = "json" ]; then
      jq -n \
        --arg worktree_root "$WORKTREE_ROOT_ABS" \
        --argjson entries "$entries_array" \
        '{
          worktree_root: $worktree_root,
          count: ($entries | length),
          active: ($entries | map(select(.status == "active")) | length),
          stale: ($entries | map(select(.status == "stale")) | length),
          orphaned: ($entries | map(select(.status == "orphaned")) | length),
          worktrees: $entries
        }'
    else
      total="$(jq 'length' <<< "$entries_array")"
      if [ "$total" -eq 0 ]; then
        echo "No Ralph-managed worktrees found."
      else
        printf '%-60s %-40s %-10s %s\n' "PATH" "BRANCH" "STATUS" "LAST COMMIT"
        printf '%-60s %-40s %-10s %s\n' "----" "------" "------" "-----------"
        jq -r '.[] | [.path, (.branch // "(detached)"), .status, .creation_time] | @tsv' <<< "$entries_array" | \
          while IFS=$'\t' read -r p b s t; do
            printf '%-60s %-40s %-10s %s\n' "$p" "$b" "$s" "$t"
          done
      fi
    fi
    ;;

  status)
    target_path=""
    if [ -n "$WT_PATH" ]; then
      target_path="$(resolve_path "$REPO_ROOT_ABS" "$WT_PATH")"
    elif [ -n "$PROJECT" ] && [ -n "$TRACK" ]; then
      project_slug="$(slugify "$PROJECT")"
      track_slug="$(slugify "$TRACK")"
      target_path="$(resolve_worktree_by_project_track "$project_slug" "$track_slug" || true)"
      if [ -z "$target_path" ]; then
        fail "no worktree found for project=$PROJECT track=$TRACK"
      fi
    elif [ -n "$PROJECT" ]; then
      project_slug="$(slugify "$PROJECT")"
      # Match without track: project-timestamp pattern
      if [ -d "$WORKTREE_ROOT_ABS" ]; then
        for entry in "$WORKTREE_ROOT_ABS"/${project_slug}-*/; do
          [ -d "$entry" ] || continue
          target_path="${entry%/}"
        done
      fi
      if [ -z "$target_path" ]; then
        fail "no worktree found for project=$PROJECT"
      fi
    else
      fail "status requires --path or --project (optionally with --track)" 2
    fi

    if [ ! -d "$target_path" ]; then
      fail "worktree path does not exist: $target_path"
    fi

    record=""
    wt_branch=""
    wt_head=""
    wt_prunable="false"
    if record="$(find_record_by_path "$target_path" 2>/dev/null)"; then
      wt_branch="$(cut -f1 <<< "$record")"
      wt_head="$(cut -f2 <<< "$record")"
      wt_prunable="$(cut -f3 <<< "$record")"
    fi

    health="$(worktree_health "$target_path" "$wt_branch" "$wt_prunable")"

    last_commit_hash=""
    last_commit_time=""
    last_commit_msg=""
    if [ -d "$target_path/.git" ] || [ -f "$target_path/.git" ]; then
      last_commit_hash="$(git -C "$target_path" log -1 --format='%H' 2>/dev/null || echo "")"
      last_commit_time="$(git -C "$target_path" log -1 --format='%ci' 2>/dev/null || echo "")"
      last_commit_msg="$(git -C "$target_path" log -1 --format='%s' 2>/dev/null || echo "")"
    fi

    files_changed=0
    files_staged=0
    files_untracked=0
    if [ -d "$target_path/.git" ] || [ -f "$target_path/.git" ]; then
      files_changed="$(git -C "$target_path" diff --name-only 2>/dev/null | wc -l | tr -d ' ')"
      files_staged="$(git -C "$target_path" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
      files_untracked="$(git -C "$target_path" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
    fi

    branch_exists="false"
    if [ -n "$wt_branch" ] && git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$wt_branch" 2>/dev/null; then
      branch_exists="true"
    fi

    ahead=0
    behind=0
    if [ "$branch_exists" = "true" ] && [ -n "$wt_branch" ]; then
      main_branch="$(git -C "$REPO_ROOT_ABS" symbolic-ref --short -q HEAD 2>/dev/null || echo "main")"
      if git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$main_branch" 2>/dev/null; then
        ahead="$(git -C "$REPO_ROOT_ABS" rev-list --count "$main_branch..$wt_branch" 2>/dev/null || echo 0)"
        behind="$(git -C "$REPO_ROOT_ABS" rev-list --count "$wt_branch..$main_branch" 2>/dev/null || echo 0)"
      fi
    fi

    jq -n \
      --arg path "$target_path" \
      --arg branch "$wt_branch" \
      --arg head "$wt_head" \
      --arg status "$health" \
      --arg last_commit_hash "$last_commit_hash" \
      --arg last_commit_time "$last_commit_time" \
      --arg last_commit_message "$last_commit_msg" \
      --argjson files_changed "$files_changed" \
      --argjson files_staged "$files_staged" \
      --argjson files_untracked "$files_untracked" \
      --arg branch_exists "$branch_exists" \
      --argjson ahead "$ahead" \
      --argjson behind "$behind" \
      '{
        path: $path,
        branch: (if $branch == "" then null else $branch end),
        head: $head,
        status: $status,
        last_commit: {
          hash: (if $last_commit_hash == "" then null else $last_commit_hash end),
          time: (if $last_commit_time == "" then null else $last_commit_time end),
          message: (if $last_commit_message == "" then null else $last_commit_message end)
        },
        working_tree: {
          files_changed: $files_changed,
          files_staged: $files_staged,
          files_untracked: $files_untracked,
          dirty: (($files_changed + $files_staged + $files_untracked) > 0)
        },
        branch_health: {
          exists: ($branch_exists == "true"),
          ahead: $ahead,
          behind: $behind
        }
      }'
    ;;

  prune)
    target_path=""
    if [ -n "$WT_PATH" ]; then
      target_path="$(resolve_path "$REPO_ROOT_ABS" "$WT_PATH")"
    elif [ -n "$PROJECT" ] && [ -n "$TRACK" ]; then
      project_slug="$(slugify "$PROJECT")"
      track_slug="$(slugify "$TRACK")"
      target_path="$(resolve_worktree_by_project_track "$project_slug" "$track_slug" || true)"
      if [ -z "$target_path" ]; then
        fail "no worktree found for project=$PROJECT track=$TRACK"
      fi
    elif [ -n "$PROJECT" ]; then
      project_slug="$(slugify "$PROJECT")"
      if [ -d "$WORKTREE_ROOT_ABS" ]; then
        for entry in "$WORKTREE_ROOT_ABS"/${project_slug}-*/; do
          [ -d "$entry" ] || continue
          target_path="${entry%/}"
        done
      fi
      if [ -z "$target_path" ]; then
        fail "no worktree found for project=$PROJECT"
      fi
    else
      fail "prune requires --path or --project (optionally with --track)" 2
    fi

    # Check health: refuse to prune active worktrees without --force
    wt_branch=""
    wt_prunable="false"
    if record="$(find_record_by_path "$target_path" 2>/dev/null)"; then
      wt_branch="$(cut -f1 <<< "$record")"
      wt_prunable="$(cut -f3 <<< "$record")"
    fi

    health="$(worktree_health "$target_path" "$wt_branch" "$wt_prunable")"

    if [ "$health" = "active" ] && [ "$FORCE" != "true" ]; then
      jq -n \
        --arg path "$target_path" \
        --arg branch "$wt_branch" \
        --arg status "$health" \
        --arg message "Worktree is active. Use --force to prune active worktrees." \
        '{
          status: "conflict",
          path: $path,
          branch: $branch,
          worktree_status: $status,
          message: $message,
          removed: false
        }'
      exit 12
    fi

    # Remove worktree
    remove_output=""
    set +e
    if [ "$FORCE" = "true" ]; then
      remove_output="$(git -C "$REPO_ROOT_ABS" worktree remove --force "$target_path" 2>&1)"
    else
      remove_output="$(git -C "$REPO_ROOT_ABS" worktree remove "$target_path" 2>&1)"
    fi
    remove_rc=$?
    set -e

    if [ "$remove_rc" -ne 0 ]; then
      jq -n \
        --arg path "$target_path" \
        --arg branch "$wt_branch" \
        --arg message "$remove_output" \
        '{
          status: "conflict",
          path: $path,
          branch: $branch,
          message: $message,
          removed: false
        }'
      exit 12
    fi

    # Delete the branch if it still exists
    branch_deleted="false"
    if [ -n "$wt_branch" ] && git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$wt_branch" 2>/dev/null; then
      if git -C "$REPO_ROOT_ABS" branch -D "$wt_branch" >/dev/null 2>&1; then
        branch_deleted="true"
      fi
    fi

    # Prune stale git metadata
    git -C "$REPO_ROOT_ABS" worktree prune >/dev/null 2>&1 || true

    prune_timestamp="$(now_iso)"
    jq -n \
      --arg path "$target_path" \
      --arg branch "$wt_branch" \
      --arg branch_deleted "$branch_deleted" \
      --arg pruned_at "$prune_timestamp" \
      '{
        status: "ok",
        path: $path,
        branch: (if $branch == "" then null else $branch end),
        branch_deleted: ($branch_deleted == "true"),
        removed: true,
        pruned_at: $pruned_at
      }'
    ;;

  prune-all)
    if [ "$CONFIRM" != "true" ]; then
      # Preview mode: show what would be pruned
      preview_entries=""
      while IFS=$'\t' read -r path branch head prunable; do
        [ -z "$path" ] && continue
        if [ "$path" = "$WORKTREE_ROOT_ABS" ] || [[ "$path" == "$WORKTREE_ROOT_ABS/"* ]]; then
          health="$(worktree_health "$path" "$branch" "$prunable")"
          if [ "$health" = "stale" ] || [ "$health" = "orphaned" ]; then
            entry="$(jq -n \
              --arg path "$path" \
              --arg branch "$branch" \
              --arg status "$health" \
              '{path: $path, branch: (if $branch == "" then null else $branch end), status: $status}')"
            preview_entries+="$entry"$'\n'
          fi
        fi
      done < <(git_worktree_records)

      if [ -z "$preview_entries" ]; then
        preview_array="[]"
      else
        preview_array="$(printf '%s' "$preview_entries" | jq -s '.')"
      fi

      jq -n \
        --argjson candidates "$preview_array" \
        '{
          status: "preview",
          message: "Pass --confirm to execute pruning.",
          candidates_count: ($candidates | length),
          candidates: $candidates
        }'
      exit 0
    fi

    # Execute pruning of stale/orphaned worktrees
    removed_entries=""
    failed_entries=""
    had_conflict="false"

    while IFS=$'\t' read -r path branch head prunable; do
      [ -z "$path" ] && continue
      if [ "$path" = "$WORKTREE_ROOT_ABS" ] || [[ "$path" == "$WORKTREE_ROOT_ABS/"* ]]; then
        health="$(worktree_health "$path" "$branch" "$prunable")"
        if [ "$health" != "stale" ] && [ "$health" != "orphaned" ]; then
          continue
        fi

        remove_output=""
        set +e
        if [ "$FORCE" = "true" ]; then
          remove_output="$(git -C "$REPO_ROOT_ABS" worktree remove --force "$path" 2>&1)"
        else
          remove_output="$(git -C "$REPO_ROOT_ABS" worktree remove "$path" 2>&1)"
        fi
        remove_rc=$?
        set -e

        if [ "$remove_rc" -eq 0 ]; then
          branch_deleted="false"
          if [ -n "$branch" ] && git -C "$REPO_ROOT_ABS" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
            if git -C "$REPO_ROOT_ABS" branch -D "$branch" >/dev/null 2>&1; then
              branch_deleted="true"
            fi
          fi
          entry="$(jq -n \
            --arg path "$path" \
            --arg branch "$branch" \
            --arg status "$health" \
            --arg branch_deleted "$branch_deleted" \
            '{path: $path, branch: (if $branch == "" then null else $branch end), prior_status: $status, branch_deleted: ($branch_deleted == "true")}')"
          removed_entries+="$entry"$'\n'
        else
          had_conflict="true"
          entry="$(jq -n \
            --arg path "$path" \
            --arg branch "$branch" \
            --arg message "$remove_output" \
            '{path: $path, branch: (if $branch == "" then null else $branch end), message: $message}')"
          failed_entries+="$entry"$'\n'
        fi
      fi
    done < <(git_worktree_records)

    git -C "$REPO_ROOT_ABS" worktree prune >/dev/null 2>&1 || true

    if [ -z "$removed_entries" ]; then
      removed_array="[]"
    else
      removed_array="$(printf '%s' "$removed_entries" | jq -s '.')"
    fi
    if [ -z "$failed_entries" ]; then
      failed_array="[]"
    else
      failed_array="$(printf '%s' "$failed_entries" | jq -s '.')"
    fi

    status="ok"
    exit_code=0
    if [ "$had_conflict" = "true" ]; then
      status="partial"
      exit_code=12
    fi

    jq -n \
      --arg status "$status" \
      --argjson removed "$removed_array" \
      --argjson failed "$failed_array" \
      --arg pruned_at "$(now_iso)" \
      '{
        status: $status,
        removed_count: ($removed | length),
        removed: $removed,
        failed_count: ($failed | length),
        failed: $failed,
        pruned_at: $pruned_at
      }'

    exit "$exit_code"
    ;;

  *)
    fail "unknown command: $COMMAND" 2
    ;;

esac
