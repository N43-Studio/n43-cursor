#!/usr/bin/env bash
# n43-cursor Bootstrap Script
#
# Interactive one-liner installer. Designed to be fetched and piped to bash:
#
#   bash <(curl -sL https://raw.githubusercontent.com/N43-Studio/n43-cursor/main/scripts/bootstrap.sh)
#
# Or run directly from inside the submodule after adding it manually:
#
#   bash .n43-cursor/scripts/bootstrap.sh
#
# What this does:
#   1. Checks prerequisites (git repo, required tools)
#   2. Adds the .n43-cursor submodule (if not already present)
#   3. Checks for GITHUB_PERSONAL_ACCESS_TOKEN (prompts if missing)
#   4. Runs setup.sh install
#   5. Runs setup.sh verify
#   6. Offers to commit the changes

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled if not a TTY)
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

info()    { echo -e "${BOLD}$*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}" >&2; }

# ---------------------------------------------------------------------------
# Prompt helper — reads from /dev/tty so it works with curl | bash
# Returns empty string if non-interactive (no /dev/tty available)
# ---------------------------------------------------------------------------

TTY_AVAILABLE=false
if [ -e /dev/tty ] && ( exec < /dev/tty ) 2>/dev/null; then
    TTY_AVAILABLE=true
fi

prompt() {
    local msg="$1"
    local reply=""
    if [ "$TTY_AVAILABLE" = true ]; then
        echo -en "${BOLD}${msg}${RESET}" > /dev/tty
        read -r reply < /dev/tty || true
    fi
    echo "${reply:-}"
}

prompt_secret() {
    local msg="$1"
    local reply=""
    if [ "$TTY_AVAILABLE" = true ]; then
        echo -en "${BOLD}${msg}${RESET}" > /dev/tty
        read -rs reply < /dev/tty || true
        echo "" > /dev/tty
    fi
    echo "${reply:-}"
}

# ---------------------------------------------------------------------------
# Determine repo root
# ---------------------------------------------------------------------------

# When run via curl pipe, we're at the user's cwd.
# When run from inside the submodule, we're at .n43-cursor/.
# We always want the host repo root.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

echo ""
echo -e "${BOLD}=== n43-cursor Bootstrap ===${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Step 0: Prerequisites
# ---------------------------------------------------------------------------

info "Checking prerequisites..."

# Must be inside a git repo
if [ -z "$REPO_ROOT" ]; then
    error "Not inside a git repository."
    echo "  Run this script from the root of a git-initialized project:"
    echo "    git init && bash <(curl -sL ...)"
    exit 1
fi

# Check that we are at (or can find) the repo root
cd "$REPO_ROOT"
echo "  Repo root: $REPO_ROOT"

# Check required tools
MISSING_TOOLS=()
for tool in git curl envsubst; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "  Install hints:"
    for t in "${MISSING_TOOLS[@]}"; do
        case "$t" in
            envsubst)
                echo "    envsubst:  brew install gettext  (macOS)"
                echo "               apt install gettext  (Debian/Ubuntu)"
                ;;
            curl)
                echo "    curl:      brew install curl     (macOS)"
                echo "               apt install curl      (Debian/Ubuntu)"
                ;;
            git)
                echo "    git:       https://git-scm.com/downloads"
                ;;
        esac
    done
    exit 1
fi

success "Prerequisites OK"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Submodule
# ---------------------------------------------------------------------------

info "Step 1: Checking .n43-cursor submodule..."

SUBMODULE_DIR="$REPO_ROOT/.n43-cursor"
N43_REPO="https://github.com/N43-Studio/n43-cursor.git"

if [ -f "$REPO_ROOT/.gitmodules" ] && grep -q '\.n43-cursor' "$REPO_ROOT/.gitmodules" 2>/dev/null; then
    if [ -d "$SUBMODULE_DIR/.git" ] || [ -f "$SUBMODULE_DIR/.git" ]; then
        success "Submodule already initialized"
    else
        echo "  Submodule registered but not initialized — initializing..."
        git submodule update --init .n43-cursor
        success "Submodule initialized"
    fi
else
    echo "  Adding submodule from $N43_REPO..."
    git submodule add "$N43_REPO" .n43-cursor
    success "Submodule added"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: GITHUB_PERSONAL_ACCESS_TOKEN
# ---------------------------------------------------------------------------

info "Step 2: Checking GITHUB_PERSONAL_ACCESS_TOKEN..."

if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    success "Token already set in environment"
else
    warn "GITHUB_PERSONAL_ACCESS_TOKEN is not set"
    echo ""
    echo "  This token is used to configure the GitHub MCP server in Cursor,"
    echo "  enabling AI features that interact with GitHub (issues, PRs, etc.)."
    echo "  The token is only used to generate .cursor/mcp.json and is not stored"
    echo "  anywhere else by this script."
    echo ""
    echo "  Options:"
    echo "    1) Provide it now (for this session only)"
    echo "    2) Skip (you can re-run setup later with the token set)"
    echo ""

    CHOICE=$(prompt "  Enter 1 or 2: ")

    if [ "$CHOICE" = "1" ]; then
        TOKEN=$(prompt_secret "  Paste your GitHub Personal Access Token: ")
        if [ -n "$TOKEN" ]; then
            export GITHUB_PERSONAL_ACCESS_TOKEN="$TOKEN"
            success "Token set for this session"
        else
            warn "No token entered — continuing without GitHub MCP"
        fi
    else
        warn "Skipping — GitHub MCP integration will need manual configuration"
        echo "  Add GITHUB_PERSONAL_ACCESS_TOKEN to your shell profile and re-run:"
        echo "    bash .n43-cursor/scripts/setup.sh install"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Run setup.sh install
# ---------------------------------------------------------------------------

info "Step 3: Running setup..."
echo ""

SETUP_SCRIPT="$SUBMODULE_DIR/scripts/setup.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    error "setup.sh not found at $SETUP_SCRIPT"
    echo "  The submodule may not have been populated correctly."
    echo "  Try: git submodule update --init --recursive .n43-cursor"
    exit 1
fi

bash "$SETUP_SCRIPT" install

echo ""

# ---------------------------------------------------------------------------
# Step 4: Verify
# ---------------------------------------------------------------------------

info "Step 4: Verifying installation..."
echo ""

VERIFY_OUTPUT=$(bash "$SETUP_SCRIPT" 2>&1)
echo "$VERIFY_OUTPUT"
echo ""

if echo "$VERIFY_OUTPUT" | grep -q "✅ All checks passed"; then
    success "All checks passed"
else
    warn "Some checks failed — review the output above"
    echo "  You can re-run verification at any time:"
    echo "    bash .n43-cursor/scripts/setup.sh"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 5: Commit prompt
# ---------------------------------------------------------------------------

info "Step 5: Commit changes?"
echo ""
echo "  The following files are ready to commit:"
echo "    .cursor/        (symlinks to submodule)"
echo "    .gitmodules     (submodule registration)"
echo "    .n43-cursor     (submodule reference)"
echo "    AGENTS.md       (project context template — edit before committing)"
echo ""

COMMIT_CHOICE=$(prompt "  Commit now? [y/N] ")

if [[ "$COMMIT_CHOICE" =~ ^[Yy]$ ]]; then
    git add .cursor/ .gitmodules .n43-cursor AGENTS.md 2>/dev/null || true
    git commit -m "chore: add n43-cursor submodule with workspace symlinks"
    success "Committed"
else
    echo "  Skipping commit. When ready:"
    echo ""
    echo "    git add .cursor/ .gitmodules .n43-cursor AGENTS.md"
    echo "    git commit -m \"chore: add n43-cursor submodule with workspace symlinks\""
fi

echo ""

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo -e "${BOLD}=== Bootstrap Complete ===${RESET}"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit AGENTS.md with your project's non-discoverable context:"
echo "       - Issue tracker config (platform, prefix, magic words)"
echo "       - Commit scopes specific to your project"
echo "       - Architectural constraints not obvious from code"
echo "     Do NOT add tech stack, directory structure, or commands already"
echo "     in package.json — agents discover those automatically."
echo ""
echo "  2. Reload Cursor to pick up the new rules, skills, and MCP config."
echo ""
echo "  3. (Optional) Set GITHUB_PERSONAL_ACCESS_TOKEN in your shell profile"
echo "     if you didn't provide it above, then re-run:"
echo "       bash .n43-cursor/scripts/setup.sh install"
echo ""
