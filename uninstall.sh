#!/usr/bin/env bash
set -euo pipefail

# claude-lives uninstaller
# Removes hooks and skills. Memory data is preserved by default.
#
# Usage: ./uninstall.sh [--delete-data]

LIVES_DIR="$HOME/.claude-lives"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

DELETE_DATA=false
for arg in "$@"; do
    [[ "$arg" == "--delete-data" ]] && DELETE_DATA=true
done

info() { echo "  [+] $1"; }
warn() { echo "  [!] $1"; }

echo "=== claude-lives uninstaller ==="
echo ""

# Remove skills
echo "Step 1: Removing skills"
skills=("new-life" "save-session" "resume" "memory-status" "borrow" "compact-memory" "sync" "cl-inject" "import-claude-mem" "fresh" "search" "timeline" "checkpoint")
for skill in "${skills[@]}"; do
    dest_dir="$SKILLS_DIR/${skill}"
    if [[ -d "$dest_dir" ]]; then
        rm -rf "$dest_dir"
        info "Removed /$skill"
    fi
    # Also clean up legacy commands/ from older installs
    legacy="$CLAUDE_DIR/commands/${skill}.md"
    if [[ -f "$legacy" ]]; then
        rm -f "$legacy"
        info "Removed legacy command /$skill"
    fi
done
echo ""

# Remove hooks from settings.json
echo "Step 2: Removing hooks from settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
    if command -v node &>/dev/null; then
        CL_SETTINGS_PATH="$SETTINGS_FILE" node -e "
const fs = require('fs');
const settingsPath = process.env.CL_SETTINGS_PATH;
const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

function removeHook(eventType, scriptName) {
    if (!settings.hooks || !settings.hooks[eventType]) return false;
    const before = settings.hooks[eventType].length;
    settings.hooks[eventType] = settings.hooks[eventType].filter(e =>
        !e.hooks?.some(h => (h.command || '').includes(scriptName))
    );
    if (settings.hooks[eventType].length === 0) delete settings.hooks[eventType];
    return (settings.hooks[eventType]?.length || 0) < before;
}

removeHook('Stop', 'stop_hook.sh');
removeHook('PostToolUse', 'post_tool_hook.sh');

if (settings.hooks && Object.keys(settings.hooks).length === 0) delete settings.hooks;

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 4));
" 2>/dev/null
        result=$?
        if [[ $result -eq 0 ]]; then
            grep -qF "stop_hook.sh" "$SETTINGS_FILE" 2>/dev/null || info "Removed Stop hook"
            grep -qF "post_tool_hook.sh" "$SETTINGS_FILE" 2>/dev/null || info "Removed PostToolUse hook"
        else
            warn "Could not remove hooks — remove manually from $SETTINGS_FILE"
        fi
    else
        warn "node not found — remove hooks manually from $SETTINGS_FILE"
    fi
else
    info "No settings.json found"
fi
echo ""

# Remove library scripts
echo "Step 3: Removing library scripts"
LIB_DEST="$CLAUDE_DIR/claude-lives-lib"
if [[ -d "$LIB_DEST" ]]; then
    rm -rf "$LIB_DEST"
    info "Removed $LIB_DEST"
fi
echo ""

# Optionally delete data
if $DELETE_DATA; then
    echo "Step 4: Deleting memory data at $LIVES_DIR"
    warn "This will permanently delete all life memories!"
    if [[ -t 0 ]]; then
        read -p "  Are you sure? (y/N) " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            rm -rf "$LIVES_DIR"
            info "Deleted $LIVES_DIR"
        else
            info "Data preserved"
        fi
    else
        warn "Non-interactive mode — skipping data deletion for safety"
        warn "Run interactively to confirm deletion, or remove $LIVES_DIR manually"
    fi
else
    echo "Step 4: Memory data preserved at $LIVES_DIR"
    info "Use --delete-data to remove memory data"
fi

echo ""
echo "=== Uninstall complete ==="
