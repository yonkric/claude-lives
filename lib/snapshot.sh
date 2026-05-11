#!/usr/bin/env bash
set -euo pipefail

# Snapshot library for claude-lives.
# Manages mid-session snapshots that preserve context across auto-compactions.
#
# Scratch files live in .session-snapshots/ under the active life/project directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
source "$SCRIPT_DIR/config_defaults.sh"
source "$SCRIPT_DIR/detect_life.sh"

get_snapshot_dir() {
    local life_name="${1:-}"
    local project_name="${2:-}"
    local lives_dir="$CLAUDE_LIVES_DIR"

    if [[ -n "$life_name" && ! "$life_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Invalid life name for snapshot dir: $life_name" >&2
        return 1
    fi
    if [[ -n "$project_name" && ! "$project_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo "Invalid project name for snapshot dir: $project_name" >&2
        return 1
    fi

    if [[ -z "$life_name" ]]; then
        echo "$lives_dir/global/.session-snapshots"
    elif [[ -n "$project_name" ]]; then
        echo "$lives_dir/$life_name/projects/$project_name/.session-snapshots"
    else
        echo "$lives_dir/$life_name/.session-snapshots"
    fi
}

init_snapshot_session() {
    local snapshot_dir="$1"
    local life_name="${2:-}"
    local project_name="${3:-}"

    mkdir -p "$snapshot_dir"
    echo "0" > "$snapshot_dir/counter"
    : > "$snapshot_dir/snapshots.md"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$snapshot_dir/session-id" <<EOF
timestamp: $timestamp
life: $life_name
project: $project_name
EOF
}

increment_counter() {
    local snapshot_dir="$1"
    local counter_file="$snapshot_dir/counter"

    if [[ ! -f "$counter_file" ]]; then
        echo "1" > "$counter_file"
        return 0
    fi

    local current
    current=$(cat "$counter_file" 2>/dev/null) || current=0
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    echo $((current + 1)) > "$counter_file"
}

increment_counter_locked() {
    local snapshot_dir="$1"
    local lockfile="$snapshot_dir/counter.lock"

    if command -v flock &>/dev/null; then
        (
            flock -w 2 200 || { increment_counter "$snapshot_dir"; return; }
            increment_counter "$snapshot_dir"
        ) 200>"$lockfile"
    else
        increment_counter "$snapshot_dir"
    fi
}

read_counter() {
    local snapshot_dir="$1"
    local counter_file="$snapshot_dir/counter"

    if [[ -f "$counter_file" ]]; then
        local val
        val=$(cat "$counter_file" 2>/dev/null) || val=0
        [[ "$val" =~ ^[0-9]+$ ]] && echo "$val" || echo "0"
    else
        echo "0"
    fi
}

reset_counter() {
    local snapshot_dir="$1"
    echo "0" > "$snapshot_dir/counter"
}

read_snapshots() {
    local snapshot_dir="$1"
    local snapshot_file="$snapshot_dir/snapshots.md"

    if [[ -f "$snapshot_file" && -s "$snapshot_file" ]]; then
        cat "$snapshot_file"
    fi
}

snapshot_count() {
    local snapshot_dir="$1"
    local snapshot_file="$snapshot_dir/snapshots.md"

    if [[ -f "$snapshot_file" ]]; then
        local count
        count=$(grep -c '<!-- snapshot:' "$snapshot_file" 2>/dev/null) || count=0
        echo "$count"
    else
        echo "0"
    fi
}

cleanup_snapshots() {
    local snapshot_dir="$1"
    if [[ -d "$snapshot_dir" && "$snapshot_dir" == "$CLAUDE_LIVES_DIR"/* ]]; then
        rm -rf "$snapshot_dir"
    fi
}

is_stale_session() {
    local snapshot_dir="$1"
    local target_dir="$2"

    local session_id_file="$snapshot_dir/session-id"
    local last_session_file="$target_dir/.last-session"

    if [[ ! -f "$session_id_file" ]]; then
        return 0
    fi

    if [[ ! -f "$last_session_file" ]]; then
        return 1
    fi

    local snapshot_ts last_session_ts
    snapshot_ts=$(grep '^timestamp:' "$session_id_file" 2>/dev/null | sed 's/^timestamp:[[:space:]]*//')
    last_session_ts=$(cat "$last_session_file" 2>/dev/null)

    if [[ -z "$snapshot_ts" || -z "$last_session_ts" ]]; then
        return 1
    fi

    if [[ "$last_session_ts" > "$snapshot_ts" ]]; then
        return 0
    fi

    return 1
}

read_cached_life() {
    local snapshot_dir="$1"
    local session_id_file="$snapshot_dir/session-id"

    if [[ -f "$session_id_file" ]]; then
        grep '^life:' "$session_id_file" 2>/dev/null | sed 's/^life:[[:space:]]*//'
    fi
}

read_cached_project() {
    local snapshot_dir="$1"
    local session_id_file="$snapshot_dir/session-id"

    if [[ -f "$session_id_file" ]]; then
        grep '^project:' "$session_id_file" 2>/dev/null | sed 's/^project:[[:space:]]*//'
    fi
}

get_snapshot_threshold() {
    local life_name="${1:-}"
    if [[ -n "$life_name" ]]; then
        get_config_value "$life_name" "snapshot_tool_threshold" "${DEFAULT_SNAPSHOT_TOOL_THRESHOLD:-20}"
    else
        echo "${DEFAULT_SNAPSHOT_TOOL_THRESHOLD:-20}"
    fi
}

get_snapshot_enabled() {
    local life_name="${1:-}"
    if [[ -n "$life_name" ]]; then
        get_config_value "$life_name" "snapshot_enabled" "${DEFAULT_SNAPSHOT_ENABLED:-true}"
    else
        echo "${DEFAULT_SNAPSHOT_ENABLED:-true}"
    fi
}
