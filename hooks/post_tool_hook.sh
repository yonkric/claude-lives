#!/usr/bin/env bash

# PostToolUse hook for claude-lives.
# Increments a tool-call counter for the active life/project.
# Runs after EVERY tool call — must be fast (<50ms).
#
# Fast path: reads a .snapshot-dir sentinel file that caches the snapshot
# directory path from the first invocation. Subsequent calls skip life
# detection and library sourcing entirely — just read counter, increment, write.
#
# Slow path (first call): sources libraries, detects life, initializes
# snapshot session, writes the sentinel, then increments.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
LIVES_DIR="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
# Use PPID (Claude Code process) to make sentinel session-specific,
# preventing corruption when two sessions run concurrently.
SENTINEL_FILE="$LIVES_DIR/.snapshot-dir.$PPID"

# Pass stdin through to stdout (required by hook protocol)
input=""
if [[ ! -t 0 ]]; then
    input=$(cat 2>/dev/null) || input=""
fi
printf '%s' "$input"

# Fast path: sentinel file caches the active snapshot directory.
# If the sentinel exists and points to a valid dir, just increment and exit.
if [[ -f "$SENTINEL_FILE" ]]; then
    cached_dir=$(cat "$SENTINEL_FILE" 2>/dev/null) || cached_dir=""
    if [[ -n "$cached_dir" && -d "$cached_dir" && "$cached_dir" == "$LIVES_DIR"/* ]]; then
        counter_file="$cached_dir/counter"
        if [[ -f "$counter_file" ]]; then
            current=$(cat "$counter_file" 2>/dev/null) || current=0
            [[ "$current" =~ ^[0-9]+$ ]] || current=0
            if command -v flock &>/dev/null; then
                (
                    flock -w 2 200 || true
                    current=$(cat "$counter_file" 2>/dev/null) || current=0
                    [[ "$current" =~ ^[0-9]+$ ]] || current=0
                    echo $((current + 1)) > "$counter_file"
                ) 200>"$cached_dir/counter.lock"
            else
                echo $((current + 1)) > "$counter_file"
            fi
            exit 0
        fi
    fi
    # Sentinel is stale or invalid — fall through to slow path
fi

# Slow path (first call): source libraries, detect life, initialize
source "$LIB_DIR/config_defaults.sh" 2>/dev/null || exit 0
source "$LIB_DIR/snapshot.sh" 2>/dev/null || exit 0

life_name=$(detect_life 2>/dev/null) || true

if [[ -n "$life_name" ]]; then
    enabled=$(get_snapshot_enabled "$life_name")
    if [[ "$enabled" != "true" ]]; then
        exit 0
    fi

    project_name=$(detect_project 2>/dev/null) || true
    snapshot_dir=$(get_snapshot_dir "$life_name" "$project_name") || exit 0

    if [[ ! -d "$snapshot_dir" ]]; then
        init_snapshot_session "$snapshot_dir" "$life_name" "$project_name"
    elif is_stale_session "$snapshot_dir" "$(dirname "$snapshot_dir")"; then
        cleanup_snapshots "$snapshot_dir"
        init_snapshot_session "$snapshot_dir" "$life_name" "$project_name"
    fi

    increment_counter_locked "$snapshot_dir"
else
    # No life — use global
    enabled="${DEFAULT_SNAPSHOT_ENABLED:-true}"
    if [[ "$enabled" != "true" ]]; then
        exit 0
    fi

    snapshot_dir=$(get_snapshot_dir "" "") || exit 0

    if [[ ! -d "$snapshot_dir" ]]; then
        mkdir -p "$LIVES_DIR/global" 2>/dev/null || exit 0
        init_snapshot_session "$snapshot_dir" "" ""
    fi

    increment_counter_locked "$snapshot_dir"
fi

# Write sentinel for fast path on subsequent calls
echo "$snapshot_dir" > "$SENTINEL_FILE" 2>/dev/null || true

exit 0
