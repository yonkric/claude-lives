#!/usr/bin/env bash
set -euo pipefail

# claude-lives installer
# Creates memory store, registers hooks, and installs slash commands.
#
# Safe for upgrades: replaces skills and hooks, never modifies existing memory data.
# Can be run repeatedly — idempotent.
#
# Usage: ./install.sh [--hooks-only] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIVES_DIR="$HOME/.claude-lives"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LIB_DEST="$CLAUDE_DIR/claude-lives-lib"
VERSION="0.3.4"

DRY_RUN=false
HOOKS_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --hooks-only) HOOKS_ONLY=true ;;
    esac
done

info() { echo "  [+] $1"; }
warn() { echo "  [!] $1"; }
skip() { echo "  [-] $1 (already exists)"; }

# Detect upgrade
PREV_VERSION=""
if [[ -f "$LIB_DEST/.version" ]]; then
    PREV_VERSION=$(cat "$LIB_DEST/.version" 2>/dev/null) || PREV_VERSION=""
fi

if [[ -n "$PREV_VERSION" ]]; then
    echo "=== claude-lives installer (upgrading $PREV_VERSION → $VERSION) ==="
else
    echo "=== claude-lives installer ==="
fi
echo ""

# ─── Step 1: Create memory store ───

if ! $HOOKS_ONLY; then
    echo "Step 1: Creating memory store at $LIVES_DIR"

    if $DRY_RUN; then
        info "Would create: $LIVES_DIR/{global}"
    else
        mkdir -p "$LIVES_DIR/global"
        chmod 700 "$LIVES_DIR"

        if [[ ! -f "$LIVES_DIR/global/memory.md" ]]; then
            today=$(date +%Y-%m-%d)
            cat > "$LIVES_DIR/global/memory.md" <<EOF
---
last_updated: $today
---

# Global Preferences

These preferences apply across all lives.

## Communication Style
(Not yet configured — tell Claude your preferred style)

## Tool Preferences
(Not yet configured)

## Formatting Preferences
(Not yet configured)
EOF
            info "Created global/memory.md"
        else
            skip "global/memory.md"
        fi

        if [[ ! -f "$LIVES_DIR/global/config.yaml" ]]; then
            echo "global_token_budget: 1000" > "$LIVES_DIR/global/config.yaml"
            info "Created global/config.yaml"
        else
            skip "global/config.yaml"
        fi

        if [[ ! -f "$LIVES_DIR/config.yaml" ]]; then
            cat > "$LIVES_DIR/config.yaml" <<EOF
# claude-lives global configuration
version: 1
memory_backend: claude-code
EOF
            info "Created config.yaml (memory_backend: claude-code)"
        else
            skip "config.yaml"
        fi
    fi

    # Add .gitignore to prevent committing sensitive files
    if [[ ! -f "$LIVES_DIR/.gitignore" ]]; then
        if $DRY_RUN; then
            info "Would create .gitignore"
        else
            cat > "$LIVES_DIR/.gitignore" <<'GITIGNORE'
*.lock
*.tmp.*
.env
*.key
*.pem
credentials*
GITIGNORE
            info "Created .gitignore"
        fi
    else
        skip ".gitignore"
    fi

    # Initialize git repo
    if [[ ! -d "$LIVES_DIR/.git" ]]; then
        if $DRY_RUN; then
            info "Would initialize git repo in $LIVES_DIR"
        else
            if (cd "$LIVES_DIR" && git init -q && git add -A && git commit -q -m "init: claude-lives memory store" 2>/dev/null); then
                info "Initialized git repo"
            else
                (cd "$LIVES_DIR" && git init -q 2>/dev/null) || true
                warn "Git repo initialized but initial commit failed (configure git user.name/email)"
            fi
        fi
    else
        skip "Git repo (already initialized)"
    fi

    echo ""
fi

# ─── Step 2: Install skills ───

if ! $HOOKS_ONLY; then
    echo "Step 2: Installing skills to $SKILLS_DIR"

    # Auto-discover skills from skills/ directory
    installed_count=0
    for src in "$SCRIPT_DIR"/skills/*/SKILL.md; do
        [[ -f "$src" ]] || continue
        skill="$(basename "$(dirname "$src")")"

        dest_dir="$SKILLS_DIR/${skill}"
        if $DRY_RUN; then
            info "Would copy: $skill/SKILL.md"
        else
            mkdir -p "$dest_dir"
            cp "$src" "$dest_dir/SKILL.md"
            info "Installed /$skill"
        fi
        installed_count=$((installed_count + 1))

        # Clean up legacy commands/ from previous installs
        OLD_COMMANDS_DIR="$CLAUDE_DIR/commands"
        if [[ -f "$OLD_COMMANDS_DIR/${skill}.md" ]]; then
            rm -f "$OLD_COMMANDS_DIR/${skill}.md"
            info "Removed legacy command /${skill}"
        fi
    done
    info "Total: $installed_count skills"

    echo ""
fi

# ─── Step 3: Register hooks ───

echo "Step 3: Registering hooks in $SETTINGS_FILE"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    warn "settings.json not found — creating minimal one"
    if ! $DRY_RUN; then
        mkdir -p "$CLAUDE_DIR"
        echo '{}' > "$SETTINGS_FILE"
    fi
fi

STOP_HOOK_COMMAND="bash \"$LIB_DEST/hooks/stop_hook.sh\""
POST_TOOL_HOOK_COMMAND="bash \"$LIB_DEST/hooks/post_tool_hook.sh\""

if $DRY_RUN; then
    info "Would register Stop hook: $STOP_HOOK_COMMAND"
    info "Would register PostToolUse hook: $POST_TOOL_HOOK_COMMAND"
else
    # Use node (guaranteed available — Claude Code requires it) for JSON manipulation
    CL_SETTINGS_PATH="$SETTINGS_FILE" \
    CL_STOP_HOOK="$STOP_HOOK_COMMAND" \
    CL_POST_TOOL_HOOK="$POST_TOOL_HOOK_COMMAND" \
    node -e "
const fs = require('fs');
const settingsPath = process.env.CL_SETTINGS_PATH;
const stopHook = process.env.CL_STOP_HOOK;
const postToolHook = process.env.CL_POST_TOOL_HOOK;

const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
if (!settings.hooks) settings.hooks = {};

function registerHook(eventType, hookCommand) {
    if (!settings.hooks[eventType]) settings.hooks[eventType] = [];

    // Remove any existing claude-lives hooks (handles upgrades with path changes)
    settings.hooks[eventType] = settings.hooks[eventType].filter(e =>
        !e.hooks?.some(h =>
            (h.command || '').includes('claude-lives') ||
            (h.command || '').includes('stop_hook.sh') ||
            (h.command || '').includes('post_tool_hook.sh')
        )
    );

    settings.hooks[eventType].push({
        matcher: '',
        hooks: [{ type: 'command', command: hookCommand }]
    });
}

registerHook('Stop', stopHook);
registerHook('PostToolUse', postToolHook);

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 4));
" 2>/dev/null
    result=$?
    if [[ $result -eq 0 ]]; then
        if grep -qF "stop_hook.sh" "$SETTINGS_FILE" 2>/dev/null; then
            info "Stop hook registered"
        fi
        if grep -qF "post_tool_hook.sh" "$SETTINGS_FILE" 2>/dev/null; then
            info "PostToolUse hook registered"
        fi
    else
        warn "Could not register hooks automatically"
        warn "Add these hooks manually to $SETTINGS_FILE:"
        warn "  Stop: $STOP_HOOK_COMMAND"
        warn "  PostToolUse: $POST_TOOL_HOOK_COMMAND"
    fi
fi

echo ""

# ─── Step 4: Copy library and hook scripts ───

echo "Step 4: Installing library scripts"

if $DRY_RUN; then
    info "Would copy lib scripts to $LIB_DEST/lib/"
    info "Would copy hook scripts to $LIB_DEST/hooks/"
    info "Would copy migration script to $LIB_DEST/"
else
    mkdir -p "$LIB_DEST/lib" "$LIB_DEST/hooks"
    cp "$SCRIPT_DIR/lib/"*.sh "$LIB_DEST/lib/"
    cp "$SCRIPT_DIR/hooks/"*.sh "$LIB_DEST/hooks/"
    chmod +x "$LIB_DEST/lib/"*.sh "$LIB_DEST/hooks/"*.sh
    info "Installed library scripts to $LIB_DEST/lib/"
    info "Installed hook scripts to $LIB_DEST/hooks/"

    if [[ -f "$SCRIPT_DIR/migration/claude_mem.py" ]]; then
        cp "$SCRIPT_DIR/migration/claude_mem.py" "$LIB_DEST/claude_mem.py"
        info "Installed migration script"
    fi

    # Write version marker for upgrade detection
    echo "$VERSION" > "$LIB_DEST/.version"
fi

echo ""

# ─── Done ───

if [[ -n "$PREV_VERSION" ]]; then
    echo "=== Upgrade complete ($PREV_VERSION → $VERSION) ==="
    echo ""
    echo "Updated: skills, hooks, and library scripts"
    echo "Preserved: all memory data at $LIVES_DIR"
else
    echo "=== Installation complete ==="
fi
echo ""
echo "Quick start:"
echo "  1. cd to a project directory"
echo "  2. Run /new-life to create a life context"
echo "     - 'Flat' life: this directory is one project (e.g., your PhD)"
echo "     - 'Workspace' life: this directory contains multiple projects (e.g., ~/work)"
echo "       Projects are auto-detected from child directories — no extra setup needed"
echo "  3. Work normally — Claude auto-saves substantial sessions before ending"
echo "  4. Switch tasks: /fresh (saves + tells you to /clear)"
echo "  5. Context is auto-loaded from CLAUDE.md — /resume for full details"
echo ""
echo "Coming from claude-mem?"
echo "  Run /import-claude-mem in each project directory to import your data"
echo ""
echo "Commands: /new-life, /save-session, /resume, /fresh, /memory-status,"
echo "          /compact-memory, /borrow, /sync, /export, /import-life,"
echo "          /import-claude-mem, /cl-inject (internal)"
