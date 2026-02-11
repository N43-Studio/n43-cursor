#!/usr/bin/env bash
# n43-cursor Setup Script
#
# Two modes:
#   verify (default) — Validates directory symlinks, MCP config, and .gitignore.
#   install          — Full bootstrap: submodule init, symlinks, MCP config, templates.
#
# Usage:
#   .n43-cursor/scripts/setup.sh                              # verify (default)
#   .n43-cursor/scripts/setup.sh install                       # full install
#   .n43-cursor/scripts/setup.sh install --target /path/.cursor # custom target
#   .n43-cursor/scripts/setup.sh install --dry-run             # preview changes
#
# Environment variables:
#   GITHUB_PERSONAL_ACCESS_TOKEN — Used for GitHub MCP integration

set +e  # Don't exit on error — NEVER block container startup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Determine repo root (for git operations) ---
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Determine mode ---
MODE="verify"
if [ "${1:-}" = "install" ]; then
    MODE="install"
    shift
fi

# --- Parse flags ---
CURSOR_DIR=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --target)    shift; CURSOR_DIR="$1" ;;
        --dry-run)   DRY_RUN=true ;;
        --help|-h)
            echo "Usage: setup.sh [install] [--target <dir>] [--dry-run]"
            echo ""
            echo "Modes:"
            echo "  (default)  Verify directory symlinks, MCP config, and .gitignore"
            echo "  install    Full bootstrap: submodule, symlinks, MCP config, templates"
            echo ""
            echo "Options:"
            echo "  --target <dir>  Target .cursor directory (default: <repo-root>/.cursor)"
            echo "  --dry-run       Preview without changes (install mode only)"
            exit 0
            ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

# --- Set default target ---
if [ -z "$CURSOR_DIR" ]; then
    CURSOR_DIR="$REPO_ROOT/.cursor"
fi

echo "=== n43-cursor Setup ==="
echo "Source:  $WORKFLOW_DIR"
echo "Target:  $CURSOR_DIR"
echo "Mode:    $MODE"
echo ""

# ============================================================================
# VERIFY MODE — check symlinks, MCP config, and .gitignore
# ============================================================================

if [ "$MODE" = "verify" ]; then

    DIRS=(agents commands references skills rules)
    ALL_OK=true

    # --- Verify directory symlinks ---

    echo "Verifying directory symlinks..."
    for dir in "${DIRS[@]}"; do
        if [ -L "$CURSOR_DIR/$dir" ] && [ -d "$CURSOR_DIR/$dir" ]; then
            echo "  ✅ .cursor/$dir -> $(readlink "$CURSOR_DIR/$dir")"
        else
            echo "  ⚠️  .cursor/$dir symlink missing or broken"
            ALL_OK=false
        fi
    done

    # --- Verify MCP config exists ---

    echo ""
    echo "Verifying MCP configuration..."
    MCP_FILE="$CURSOR_DIR/mcp.json"
    if [ -f "$MCP_FILE" ]; then
        echo "  ✅ .cursor/mcp.json exists"
    else
        echo "  ⚠️  .cursor/mcp.json not found"
        echo "     Run: .n43-cursor/scripts/setup.sh install"
        ALL_OK=false
    fi

    # --- Verify .cursor/.gitignore ---

    echo ""
    echo "Verifying .cursor/.gitignore..."
    GITIGNORE="$CURSOR_DIR/.gitignore"
    if [ -f "$GITIGNORE" ] && grep -qxF 'mcp.json' "$GITIGNORE" 2>/dev/null; then
        echo "  ✅ .cursor/.gitignore contains mcp.json"
    else
        if [ ! -f "$GITIGNORE" ]; then
            echo "  ⚠️  .cursor/.gitignore not found"
        else
            echo "  ⚠️  .cursor/.gitignore missing 'mcp.json' entry"
        fi
        echo "     Run: .n43-cursor/scripts/setup.sh install"
        ALL_OK=false
    fi

    # --- Summary ---

    echo ""
    if [ "$ALL_OK" = true ]; then
        echo "✅ All checks passed"
    else
        echo "⚠️  Some checks failed"
        echo "   Run: .n43-cursor/scripts/setup.sh install"
    fi

    echo ""
    echo "=== Verify Complete ==="
    exit 0
fi

# ============================================================================
# INSTALL MODE — full bootstrap
# ============================================================================

$DRY_RUN && echo "DRY RUN — no changes will be made"
echo ""

# --- Step 1: Ensure submodule exists and is initialized ---

echo "Step 1: Checking .n43-cursor submodule..."

SUBMODULE_DIR="$REPO_ROOT/.n43-cursor"

if [ ! -f "$REPO_ROOT/.gitmodules" ] || ! grep -q '\.n43-cursor' "$REPO_ROOT/.gitmodules" 2>/dev/null; then
    echo "  Submodule not registered — adding..."
    if $DRY_RUN; then
        echo "  [dry-run] Would run: git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor"
    else
        (cd "$REPO_ROOT" && git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor)
        if [ $? -eq 0 ]; then
            echo "  ✅ Submodule added"
        else
            echo "  ❌ Failed to add submodule"
            echo "     You may need to add it manually: git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor"
        fi
    fi
elif [ ! -d "$SUBMODULE_DIR/.git" ] && [ ! -f "$SUBMODULE_DIR/.git" ]; then
    echo "  Submodule registered but not initialized — initializing..."
    if $DRY_RUN; then
        echo "  [dry-run] Would run: git submodule update --init .n43-cursor"
    else
        (cd "$REPO_ROOT" && git submodule update --init .n43-cursor)
        if [ $? -eq 0 ]; then
            echo "  ✅ Submodule initialized"
        else
            echo "  ❌ Failed to initialize submodule"
        fi
    fi
else
    echo "  ✅ Submodule already initialized"
fi

# --- Step 2: Create .cursor/ directory ---

echo ""
echo "Step 2: Ensuring $CURSOR_DIR exists..."

if [ ! -d "$CURSOR_DIR" ]; then
    if $DRY_RUN; then
        echo "  [dry-run] Would create $CURSOR_DIR"
    else
        mkdir -p "$CURSOR_DIR"
        echo "  ✅ Created $CURSOR_DIR"
    fi
else
    echo "  ✅ $CURSOR_DIR already exists"
fi

# --- Step 3: Create directory-level symlinks ---

echo ""
echo "Step 3: Creating directory symlinks..."

# Compute relative path from .cursor/ to .n43-cursor/
# This should be ../.n43-cursor (one level up from .cursor/)
REL_PREFIX="$(python3 -c "import os.path; print(os.path.relpath('$WORKFLOW_DIR', '$CURSOR_DIR'))" 2>/dev/null || echo "../.n43-cursor")"

DIRS=(agents commands references skills rules)

for dir in "${DIRS[@]}"; do
    TARGET="$CURSOR_DIR/$dir"
    LINK_TARGET="$REL_PREFIX/$dir"

    if [ -L "$TARGET" ]; then
        CURRENT="$(readlink "$TARGET")"
        if [ "$CURRENT" = "$LINK_TARGET" ]; then
            echo "  ✅ .cursor/$dir -> $LINK_TARGET (already correct)"
            continue
        else
            echo "  🔄 .cursor/$dir -> $CURRENT (updating to $LINK_TARGET)"
            if ! $DRY_RUN; then
                rm "$TARGET"
            fi
        fi
    elif [ -d "$TARGET" ]; then
        echo "  ⚠️  .cursor/$dir is a real directory — skipping (remove manually to use symlink)"
        continue
    fi

    if $DRY_RUN; then
        echo "  [dry-run] Would create .cursor/$dir -> $LINK_TARGET"
    else
        ln -s "$LINK_TARGET" "$TARGET"
        echo "  ✅ .cursor/$dir -> $LINK_TARGET"
    fi
done

# --- Step 4: Generate MCP config from template ---

echo ""
echo "Step 4: Generating MCP configuration..."

TEMPLATE="$WORKFLOW_DIR/templates/mcp.json.example"
MCP_OUTPUT="$CURSOR_DIR/mcp.json"

if [ ! -f "$TEMPLATE" ]; then
    echo "  ⚠️  MCP template not found at $TEMPLATE"
    echo "     Skipping MCP configuration"
else
    if $DRY_RUN; then
        echo "  [dry-run] Would generate $MCP_OUTPUT from template"
    else
        export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-}"
        envsubst '$GITHUB_PERSONAL_ACCESS_TOKEN' < "$TEMPLATE" > "$MCP_OUTPUT"
        echo "  ✅ MCP config written to $MCP_OUTPUT"
    fi

    if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
        echo "  ⚠️  GITHUB_PERSONAL_ACCESS_TOKEN not set"
        echo "     GitHub MCP integration will need manual configuration"
        echo "     Add GITHUB_PERSONAL_ACCESS_TOKEN to your environment and re-run install"
    else
        echo "  ✅ GitHub token applied"
    fi
fi

# --- Step 5: Create/update .cursor/.gitignore ---

echo ""
echo "Step 5: Managing .cursor/.gitignore..."

GITIGNORE="$CURSOR_DIR/.gitignore"

if [ -f "$GITIGNORE" ] && grep -qxF 'mcp.json' "$GITIGNORE" 2>/dev/null; then
    echo "  ✅ .cursor/.gitignore already contains mcp.json"
else
    if $DRY_RUN; then
        if [ -f "$GITIGNORE" ]; then
            echo "  [dry-run] Would append 'mcp.json' to $GITIGNORE"
        else
            echo "  [dry-run] Would create $GITIGNORE with 'mcp.json'"
        fi
    else
        if [ -f "$GITIGNORE" ]; then
            echo "mcp.json" >> "$GITIGNORE"
            echo "  ✅ Appended 'mcp.json' to $GITIGNORE"
        else
            echo "mcp.json" > "$GITIGNORE"
            echo "  ✅ Created $GITIGNORE with 'mcp.json'"
        fi
    fi
fi

# --- Step 6: Copy project-context template if missing ---

echo ""
echo "Step 6: Checking project-context template..."

CONTEXT_TEMPLATE="$WORKFLOW_DIR/templates/project-context.mdc.template"
# project-context goes at AGENTS.md in repo root.
# (.cursor/rules/ is a symlink into the submodule — we must not write there)
CONTEXT_DEST="$REPO_ROOT/AGENTS.md"

if [ ! -f "$CONTEXT_TEMPLATE" ]; then
    echo "  ⚠️  Project context template not found — skipping"
elif [ -f "$CONTEXT_DEST" ]; then
    echo "  ✅ $CONTEXT_DEST already exists — skipping"
else
    if $DRY_RUN; then
        echo "  [dry-run] Would copy project-context template to $CONTEXT_DEST"
    else
        cp "$CONTEXT_TEMPLATE" "$CONTEXT_DEST"
        echo "  ✅ Copied project-context template to $CONTEXT_DEST"
        echo "     Edit this file with your project's details"
    fi
fi

# --- Summary ---

echo ""
echo "=== Install Complete ==="
$DRY_RUN && echo "(DRY RUN — no changes were made)"
echo ""
echo "Next steps:"
echo "  1. Edit AGENTS.md with your project's tech stack and conventions"
echo "  2. Set GITHUB_PERSONAL_ACCESS_TOKEN in your environment for MCP"
echo "  3. Commit: git add .cursor/ .gitmodules .n43-cursor AGENTS.md"
echo "  4. Verify setup: .n43-cursor/scripts/setup.sh"
