#!/usr/bin/env bash
set -euo pipefail

# Stop hook for claude-lives.
# 1. Writes .last-session timestamp when Claude's session ends
# 2. Extracts session metadata from transcript (significance filter)
# 3. Writes .last-session-meta.json for stale session detection
#
# For workspace lives, writes to the project directory if in a project.
# Reads JSON from stdin (Claude Code provides transcript_path).
# Registered as a Stop hook in ~/.claude/settings.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/config_defaults.sh"
source "$LIB_DIR/detect_life.sh"

# Read stdin (Claude Code hook input) and pass through
input=""
if [[ ! -t 0 ]]; then
    input=$(cat 2>/dev/null) || input=""
fi
printf '%s' "$input"

life_name=$(detect_life 2>/dev/null) || true

if [[ -z "$life_name" ]]; then
    exit 0
fi

life_dir="$CLAUDE_LIVES_DIR/$life_name"

# H2 fix: create store directory if life is detected but store is missing
if [[ ! -d "$life_dir" ]]; then
    mkdir -p "$life_dir/sessions" "$life_dir/archive" 2>/dev/null || exit 0
fi

# Determine target directory (project or life level)
project_name=$(detect_project 2>/dev/null) || true
if [[ -n "$project_name" ]]; then
    auto_init_project "$life_name" "$project_name" 2>/dev/null || true
    target_dir="$life_dir/projects/$project_name"
else
    target_dir="$life_dir"
fi

# Write timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "$timestamp" > "$target_dir/.last-session"

# Extract transcript_path from stdin JSON via node (guaranteed by Claude Code)
transcript_path=""
if [[ -n "$input" ]] && command -v node &>/dev/null; then
    transcript_path=$(echo "$input" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
try{process.stdout.write(JSON.parse(d).transcript_path||'')}catch(e){}
});" 2>/dev/null) || true
fi

# Parse transcript for session metadata
user_msgs=0
files_modified=0
session_tokens=0

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    user_msgs=$(grep -c '"type"[[:space:]]*:[[:space:]]*"user"' "$transcript_path" 2>/dev/null || echo "0")
    files_modified=$(grep -oE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit)"' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    # Approximate token count: file size / 4 (rough chars-to-tokens ratio)
    transcript_bytes=$(wc -c < "$transcript_path" 2>/dev/null | tr -d ' ' || echo "0")
    session_tokens=$((transcript_bytes / 4))
fi

# Validate numeric fields
[[ "$user_msgs" =~ ^[0-9]+$ ]] || user_msgs=0
[[ "$files_modified" =~ ^[0-9]+$ ]] || files_modified=0
[[ "$session_tokens" =~ ^[0-9]+$ ]] || session_tokens=0

# Determine significance
significant=false
if [[ "$user_msgs" -gt 3 ]] || [[ "$files_modified" -gt 0 ]]; then
    significant=true
fi

# Clear snapshot sentinel so next session starts fresh (PPID-scoped)
rm -f "$CLAUDE_LIVES_DIR/.snapshot-dir.$PPID" 2>/dev/null || true
# Also clean up any stale sentinels from crashed sessions
find "$CLAUDE_LIVES_DIR" -maxdepth 1 -name '.snapshot-dir.*' -mmin +120 -delete 2>/dev/null || true

# Check for unsaved snapshots
snapshot_dir="$target_dir/.session-snapshots"
has_snapshots=false
if [[ -f "$snapshot_dir/snapshots.md" && -s "$snapshot_dir/snapshots.md" ]]; then
    last_saved_file="$target_dir/.last-saved"
    session_id_file="$snapshot_dir/session-id"

    snapshot_ts=""
    if [[ -f "$session_id_file" ]]; then
        snapshot_ts=$(grep '^timestamp:' "$session_id_file" 2>/dev/null | sed 's/^timestamp:[[:space:]]*//')
    fi

    saved_ts=""
    if [[ -f "$last_saved_file" ]]; then
        saved_ts=$(cat "$last_saved_file" 2>/dev/null)
    fi

    # If session was not saved (no .last-saved, or .last-saved is older than snapshot session)
    if [[ -z "$saved_ts" || ( -n "$snapshot_ts" && "$snapshot_ts" > "$saved_ts" ) ]]; then
        has_snapshots=true
    else
        # Session was saved — clean up snapshots
        rm -rf "$snapshot_dir" 2>/dev/null || true
    fi
fi

# Write session metadata
cat > "$target_dir/.last-session-meta.json" <<EOF
{
  "timestamp": "$timestamp",
  "user_messages": $user_msgs,
  "files_modified": $files_modified,
  "session_tokens": $session_tokens,
  "significant": $significant,
  "has_snapshots": $has_snapshots
}
EOF
