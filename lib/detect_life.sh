#!/usr/bin/env bash
set -euo pipefail

# Detect the current "life" and optionally the "project" within it.
#
# Three-layer model:
#   Global → Life → Project
#
# A life with type: workspace has child directories that are separate projects.
# A life with type: flat (default) IS the project — subdirectories are part of it.
#
# Usage: detect_life.sh [start_directory]
# Output: life name on stdout, or empty + exit 1 if none found
#
# Environment: CLAUDE_LIFE overrides directory detection.

detect_life() {
    local start_dir="${1:-$(pwd)}"

    if [[ -n "${CLAUDE_LIFE:-}" ]]; then
        if [[ "$CLAUDE_LIFE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "$CLAUDE_LIFE"
            return 0
        else
            echo "Invalid life name: $CLAUDE_LIFE" >&2
            return 1
        fi
    fi

    local dir
    dir="$(cd "$start_dir" && pwd -P)"

    while true; do
        if [[ -f "$dir/.claude-life" ]]; then
            local name
            name=$(grep -E '^name:' "$dir/.claude-life" | head -1 | sed 's/^name:[[:space:]]*//')
            if [[ -n "$name" ]]; then
                if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo "Invalid life name in .claude-life: $name" >&2
                    return 1
                fi
                echo "$name"
                return 0
            fi
        fi

        if [[ "$dir" == "/" ]]; then
            break
        fi

        dir="$(dirname "$dir")"
    done

    return 1
}

get_life_root() {
    local start_dir="${1:-$(pwd)}"

    if [[ -n "${CLAUDE_LIFE:-}" ]]; then
        echo ""
        return 1
    fi

    local dir
    dir="$(cd "$start_dir" && pwd -P)"

    while true; do
        if [[ -f "$dir/.claude-life" ]]; then
            echo "$dir"
            return 0
        fi

        if [[ "$dir" == "/" ]]; then
            break
        fi

        dir="$(dirname "$dir")"
    done

    return 1
}

detect_life_type() {
    local start_dir="${1:-$(pwd)}"
    local life_root
    life_root=$(get_life_root "$start_dir") || { echo "flat"; return 0; }

    local life_type
    life_type=$(grep -E '^type:' "$life_root/.claude-life" 2>/dev/null | head -1 | sed 's/^type:[[:space:]]*//')

    if [[ "$life_type" == "workspace" ]]; then
        echo "workspace"
    else
        echo "flat"
    fi
}

detect_project() {
    local start_dir="${1:-$(pwd)}"
    local life_root
    life_root=$(get_life_root "$start_dir") || return 0

    local life_type
    life_type=$(detect_life_type "$start_dir")

    if [[ "$life_type" != "workspace" ]]; then
        return 0
    fi

    local cwd
    cwd="$(cd "$start_dir" && pwd -P)"

    if [[ "$cwd" == "$life_root" ]]; then
        return 0
    fi

    local rel_path="${cwd#"$life_root"/}"
    local project_name="${rel_path%%/*}"

    if [[ -n "$project_name" && "$project_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo "$project_name"
    fi
}

get_project_storage_dir() {
    local life_name="$1"
    local project_name="$2"
    local lives_dir="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
    echo "$lives_dir/$life_name/projects/$project_name"
}

auto_init_project() {
    local life_name="$1"
    local project_name="$2"
    local lives_dir="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
    local project_dir="$lives_dir/$life_name/projects/$project_name"

    if [[ -d "$project_dir" ]]; then
        return 0
    fi

    mkdir -p "$project_dir/sessions" "$project_dir/archive"

    local today
    today=$(date +%Y-%m-%d)

    cat > "$project_dir/memory.md" <<EOF
---
life: $life_name
project: $project_name
last_compressed: $today
session_count: 0
---

# $project_name — Project Memory

## Current Focus
(New project — no sessions yet)

## Key Context
(Context will be added after first /save-session)
EOF

    cat > "$project_dir/handover.md" <<EOF
---
life: $life_name
project: $project_name
last_updated: $today
---

# Handover Notes

## What Was Happening
Project auto-initialized. No previous session.

## Next Steps
Ready for first session.

## Pending Decisions
(None)

## Key Files Being Worked On
(None)
EOF

    echo "Auto-initialized project: $project_name (under $life_name)" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_life "$@"
fi
