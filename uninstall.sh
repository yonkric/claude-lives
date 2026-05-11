#!/usr/bin/env bash
set -euo pipefail

# claude-lives uninstaller
# Removes hooks and skills. Memory data is preserved by default.
#
# Usage: ./uninstall.sh [--delete-data]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    if command -v python3 &>/dev/null; then
        CL_SETTINGS_PATH="$SETTINGS_FILE" python3 -c "
import json, os
settings_path = os.environ['CL_SETTINGS_PATH']
with open(settings_path) as f:
    s = json.load(f)

def remove_hook(settings, event_type, script_name):
    if 'hooks' not in settings or event_type not in settings['hooks']:
        return False
    before = len(settings['hooks'][event_type])
    settings['hooks'][event_type] = [
        e for e in settings['hooks'][event_type]
        if not any(script_name in h.get('command','') for h in e.get('hooks',[]))
    ]
    if not settings['hooks'][event_type]:
        del settings['hooks'][event_type]
    return len(settings['hooks'].get(event_type, [])) < before

removed_stop = remove_hook(s, 'Stop', 'stop_hook.sh')
removed_post = remove_hook(s, 'PostToolUse', 'post_tool_hook.sh')

with open(settings_path,'w') as f:
    json.dump(s, f, indent=4)

if removed_stop:
    print('stop')
if removed_post:
    print('post')
"
        result=$?
        if [[ $result -eq 0 ]]; then
            grep -qF "stop_hook.sh" "$SETTINGS_FILE" 2>/dev/null || info "Removed Stop hook"
            grep -qF "post_tool_hook.sh" "$SETTINGS_FILE" 2>/dev/null || info "Removed PostToolUse hook"
        else
            warn "Could not remove hooks — remove manually from $SETTINGS_FILE"
        fi
    else
        warn "python3 not found — remove hooks manually from $SETTINGS_FILE"
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
