#!/usr/bin/env bash
set -euo pipefail

# claude-lives installer
# Creates memory store, registers hooks, and installs slash commands.
#
# Usage: ./install.sh [--hooks-only] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVES_DIR="$HOME/.claude-lives"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LIB_DEST="$CLAUDE_DIR/claude-lives-lib"

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

echo "=== claude-lives installer ==="
echo ""

# ─── Dependency check ───

if ! command -v python3 &>/dev/null; then
    warn "python3 not found — required for hook registration and claude-mem migration"
    warn "Install Python 3.8+ and try again"
    exit 1
fi

# ─── Step 1: Create memory store ───

if ! $HOOKS_ONLY; then
    echo "Step 1: Creating memory store at $LIVES_DIR"

    if $DRY_RUN; then
        info "Would create: $LIVES_DIR/{global}"
    else
        mkdir -p "$LIVES_DIR/global"
        chmod 700 "$LIVES_DIR"

        if [[ ! -f "$LIVES_DIR/global/memory.md" ]]; then
            cat > "$LIVES_DIR/global/memory.md" <<'GLOBAL_MEM'
---
last_updated: $(date +%Y-%m-%d)
---

# Global Preferences

These preferences apply across all lives.

## Communication Style
(Not yet configured — tell Claude your preferred style)

## Tool Preferences
(Not yet configured)

## Formatting Preferences
(Not yet configured)
GLOBAL_MEM
            # Fix the date (heredoc doesn't expand)
            sed -i.bak "s/\$(date +%Y-%m-%d)/$(date +%Y-%m-%d)/" "$LIVES_DIR/global/memory.md" 2>/dev/null || \
            sed -i '' "s/\$(date +%Y-%m-%d)/$(date +%Y-%m-%d)/" "$LIVES_DIR/global/memory.md"
            rm -f "$LIVES_DIR/global/memory.md.bak"
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

    skills=("new-life" "save-session" "resume" "memory-status" "borrow" "compact-memory" "sync" "cl-inject" "import-claude-mem" "fresh" "search" "timeline" "checkpoint")

    for skill in "${skills[@]}"; do
        src="$SCRIPT_DIR/skills/${skill}/SKILL.md"
        dest_dir="$SKILLS_DIR/${skill}"

        if [[ ! -f "$src" ]]; then
            warn "Source not found: $src"
            continue
        fi

        if $DRY_RUN; then
            info "Would copy: $skill/SKILL.md"
        else
            mkdir -p "$dest_dir"
            cp "$src" "$dest_dir/SKILL.md"
            info "Installed /$skill"
        fi
    done

    # Clean up legacy commands/ from previous installs
    OLD_COMMANDS_DIR="$CLAUDE_DIR/commands"
    for skill in "${skills[@]}"; do
        if [[ -f "$OLD_COMMANDS_DIR/${skill}.md" ]]; then
            rm -f "$OLD_COMMANDS_DIR/${skill}.md"
        fi
    done

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

# Hooks point to the installed location, not the source tree.
# This ensures hooks work after npx cleanup or if the source is moved.
STOP_HOOK_COMMAND="bash \"$LIB_DEST/hooks/stop_hook.sh\""
POST_TOOL_HOOK_COMMAND="bash \"$LIB_DEST/hooks/post_tool_hook.sh\""

if $DRY_RUN; then
    info "Would register Stop hook: $STOP_HOOK_COMMAND"
    info "Would register PostToolUse hook: $POST_TOOL_HOOK_COMMAND"
else
    CL_SETTINGS_PATH="$SETTINGS_FILE" \
    CL_STOP_HOOK="$STOP_HOOK_COMMAND" \
    CL_POST_TOOL_HOOK="$POST_TOOL_HOOK_COMMAND" \
    python3 -c "
import json, os

settings_path = os.environ['CL_SETTINGS_PATH']
stop_hook = os.environ['CL_STOP_HOOK']
post_tool_hook = os.environ['CL_POST_TOOL_HOOK']

with open(settings_path) as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

def register_hook(settings, event_type, hook_command, matcher=''):
    if event_type not in settings['hooks']:
        settings['hooks'][event_type] = []

    already = any(
        h.get('command', '') == hook_command
        for entry in settings['hooks'][event_type]
        for h in entry.get('hooks', [])
    )

    if not already:
        # Remove any old claude-lives hooks (from previous installs with different paths)
        settings['hooks'][event_type] = [
            e for e in settings['hooks'][event_type]
            if not any('claude-lives' in h.get('command','') or 'stop_hook.sh' in h.get('command','') or 'post_tool_hook.sh' in h.get('command','')
                       for h in e.get('hooks',[]))
        ]
        settings['hooks'][event_type].append({
            'matcher': matcher,
            'hooks': [{
                'type': 'command',
                'command': hook_command
            }]
        })
        return True
    return False

registered_stop = register_hook(settings, 'Stop', stop_hook)
registered_post = register_hook(settings, 'PostToolUse', post_tool_hook)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=4)

if registered_stop:
    print('stop')
if registered_post:
    print('post')
"
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
fi

echo ""

# ─── Done ───

echo "=== Installation complete ==="
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
echo "  Then disable claude-mem (see docs/disable-claude-mem.md)"
echo ""
echo "Commands: /new-life, /save-session, /resume, /fresh, /memory-status,"
echo "          /compact-memory, /borrow, /sync, /import-claude-mem, /cl-inject (internal)"
echo ""
echo "Docs: README.md, docs/disable-claude-mem.md"
