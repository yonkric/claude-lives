#!/usr/bin/env bash
set -euo pipefail

# Inject or update the claude-lives memory section in a CLAUDE.md file.
#
# Usage:
#   inject_memory <claude_md> <life_name> [--progressive|--full] [project_name]
#
# Progressive mode: compact ~500-token index with file paths for on-demand reading.
# Full mode: complete memory, handover, and global content.
#
# When project_name is provided, injects project-specific context alongside
# life-level context (three-layer model: global → life → project).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
source "$SCRIPT_DIR/config_defaults.sh"
source "$SCRIPT_DIR/snapshot.sh"

strip_frontmatter() {
    # Strip only the FIRST YAML frontmatter block (lines between first --- pair).
    # Frontmatter must start on the very first line of the file.
    # Preserves --- horizontal rules in the body text (C3 fix).
    local file="$1"
    local in_frontmatter=false
    local frontmatter_done=false
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if ! $frontmatter_done; then
            if [[ "$line" == "---" ]]; then
                if [[ "$line_num" -eq 1 ]]; then
                    in_frontmatter=true
                    continue
                elif $in_frontmatter; then
                    in_frontmatter=false
                    frontmatter_done=true
                    continue
                fi
            fi
            if $in_frontmatter; then
                continue
            fi
        fi
        echo "$line"
    done < "$file"
}

extract_section() {
    # Extract content under a ## heading, up to the next ## heading or EOF.
    # Returns first N lines (default 3) of the section body.
    local file="$1"
    local heading="$2"
    local max_lines="${3:-3}"
    local in_section=false
    local count=0
    local content
    content=$(strip_frontmatter "$file")

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            local h="${BASH_REMATCH[1]}"
            if [[ "$h" == "$heading" ]]; then
                in_section=true
                continue
            elif $in_section; then
                break
            fi
        fi
        if $in_section && [[ -n "$line" ]]; then
            echo "$line"
            count=$((count + 1))
            if [[ $count -ge $max_lines ]]; then
                break
            fi
        fi
    done <<< "$content"
}

extract_frontmatter_value() {
    # Extract a value from YAML frontmatter (simple key: value).
    local file="$1"
    local key="$2"
    if [[ -f "$file" ]]; then
        grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//"
    fi
}

check_injection_patterns() {
    # Check a file for common prompt injection patterns.
    # Returns 0 if clean, 1 if suspicious patterns found.
    # Outputs warning lines to stderr.
    local file="$1"
    local found=0

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    # Role injection: lines that try to redefine Claude's identity
    if grep -qiE '^\s*(you are|system:|assistant:|human:|<\|im_start\|>)' "$file" 2>/dev/null; then
        echo "WARNING: Possible role injection in $file" >&2
        found=1
    fi

    # Instruction override: attempts to override or ignore previous instructions
    if grep -qiE '(ignore (all |previous |above )+instructions|disregard (all |previous )|forget (everything|all|your))' "$file" 2>/dev/null; then
        echo "WARNING: Instruction override attempt in $file" >&2
        found=1
    fi

    # Delimiter injection: fake XML/markdown boundaries
    if grep -qE '(</?system>|</?prompt>|</?instructions>|\]\]\]|```system)' "$file" 2>/dev/null; then
        echo "WARNING: Delimiter injection attempt in $file" >&2
        found=1
    fi

    # Marker spoofing: content that closes the injection block early
    if grep -qF "CLAUDE-LIVES:END" "$file" 2>/dev/null || grep -qF "CLAUDE-LIVES:START" "$file" 2>/dev/null; then
        echo "WARNING: Marker spoofing attempt in $file" >&2
        found=1
    fi

    return $found
}

build_progressive_block() {
    local life_name="$1"
    local project_name="${2:-}"
    local lives_dir="$CLAUDE_LIVES_DIR"

    local global_mem="$lives_dir/global/memory.md"
    local life_mem="$lives_dir/$life_name/memory.md"

    local start_marker="<!-- CLAUDE-LIVES:START:${life_name} -->"
    local end_marker="<!-- CLAUDE-LIVES:END -->"

    # Determine handover and session sources based on project vs flat
    local handover sessions_dir project_mem target_dir
    if [[ -n "$project_name" ]]; then
        local project_dir="$lives_dir/$life_name/projects/$project_name"
        target_dir="$project_dir"
        project_mem="$project_dir/memory.md"
        handover="$project_dir/handover.md"
        sessions_dir="$project_dir/sessions/"
    else
        target_dir="$lives_dir/$life_name"
        handover="$lives_dir/$life_name/handover.md"
        sessions_dir="$lives_dir/${life_name}/sessions/"
    fi

    local block=""
    block+="$start_marker"$'\n'

    if [[ -n "$project_name" ]]; then
        block+="## Life: ${life_name} | Project: ${project_name}"$'\n'
    else
        block+="## Life: ${life_name}"$'\n'
    fi
    block+=""$'\n'

    # Life identity (always from life memory)
    if [[ -f "$life_mem" ]]; then
        local identity
        identity=$(extract_section "$life_mem" "Identity" 2)
        if [[ -n "$identity" ]]; then
            block+="**Identity:** ${identity}"$'\n'
        fi
    fi

    # Focus: from project memory if project, else life memory
    local focus_source="${project_mem:-$life_mem}"
    if [[ -f "$focus_source" ]]; then
        local focus
        focus=$(extract_section "$focus_source" "Current Focus" 2)
        if [[ -n "$focus" ]]; then
            block+="**Focus:** ${focus}"$'\n'
        fi
    fi

    # Last session context (from project or life handover)
    if [[ -f "$handover" ]]; then
        local last_updated
        last_updated=$(extract_frontmatter_value "$handover" "last_updated")
        if [[ -n "$last_updated" ]]; then
            block+="**Last session:** ${last_updated}"$'\n'
        fi

        local what_happening
        what_happening=$(extract_section "$handover" "What Was Happening" 2)
        if [[ -n "$what_happening" ]]; then
            block+="**Was doing:** ${what_happening}"$'\n'
        fi

        local next_steps
        next_steps=$(extract_section "$handover" "Next Steps" 3)
        if [[ -n "$next_steps" ]]; then
            block+="**Next:** ${next_steps}"$'\n'
        fi
    fi

    # Life-level key context (always included, 3 lines for projects, 5 for flat)
    if [[ -f "$life_mem" ]]; then
        local life_ctx_lines=5
        local life_ctx_label="Key Context"
        if [[ -n "$project_name" ]]; then
            life_ctx_lines=3
            life_ctx_label="Life Context"
        fi
        local key_ctx
        key_ctx=$(extract_section "$life_mem" "Key Context" "$life_ctx_lines")
        if [[ -n "$key_ctx" ]]; then
            block+=""$'\n'
            block+="### ${life_ctx_label}"$'\n'
            block+="${key_ctx}"$'\n'
        fi
    fi

    # Project-specific key context (only for workspace projects)
    if [[ -n "$project_name" && -f "$project_mem" ]]; then
        local proj_ctx
        proj_ctx=$(extract_section "$project_mem" "Key Context" 5)
        if [[ -n "$proj_ctx" ]]; then
            block+=""$'\n'
            block+="### Project Context"$'\n'
            block+="${proj_ctx}"$'\n'
        fi
    fi

    # Global preferences summary
    if [[ -f "$global_mem" ]]; then
        local global_ctx global_stripped
        global_stripped=$(strip_frontmatter "$global_mem")
        global_ctx=$(echo "$global_stripped" | grep -v '^#' | grep -v '^$' | grep -v '^(' | head -4)
        if [[ -n "$global_ctx" ]]; then
            block+=""$'\n'
            block+="### Global"$'\n'
            block+="${global_ctx}"$'\n'
        fi
    fi

    # File paths for on-demand reading
    local meta_path="$target_dir/.last-session-meta.json"

    block+=""$'\n'
    block+="### Full Memory (read when needed)"$'\n'
    block+="- Life memory: \`${life_mem}\`"$'\n'
    if [[ -n "$project_name" ]]; then
        block+="- Project memory: \`${project_mem}\`"$'\n'
        block+="- Project handover: \`${handover}\`"$'\n'
    else
        block+="- Handover: \`${handover}\`"$'\n'
    fi
    block+="- Global: \`${global_mem}\`"$'\n'
    block+="- Sessions: \`${sessions_dir}\`"$'\n'
    block+="- Session meta: \`${meta_path}\`"$'\n'

    # Session protocol instructions
    local snapshot_dir
    snapshot_dir=$(get_snapshot_dir "$life_name" "$project_name" 2>/dev/null || echo "$lives_dir/$life_name/.session-snapshots")

    block+=""$'\n'
    block+="### Session Protocol"$'\n'
    block+="- **On start**: Read \`${meta_path}\` — if \`significant: true\` and no \`.last-saved\` file is newer, previous session may be unsaved. Note this briefly."$'\n'
    block+="- **Mid-session snapshots**: A tool-call counter increments at \`${snapshot_dir}/counter\`. When you read or write files and notice the counter exceeds 20, write a brief incremental summary (3-6 bullets, telegraphic) to \`${snapshot_dir}/snapshots.md\` using the format \`<!-- snapshot:N t:{ISO8601} tools:{counter} -->\\n## Snapshot N\\n- bullet\`, then write \`0\` to the counter file. This preserves early work before auto-compaction erases it."$'\n'
    block+="- **Before ending**: If you modified files, made key decisions, or learned important context — run /save-session before your final response. Also trigger on closing phrases (goodbye, thanks, done, that's all). Skip only for single-question Q&A with no file changes."$'\n'
    block+=""$'\n'
    block+="$end_marker"

    echo "$block"
}

build_full_block() {
    local life_name="$1"
    local project_name="${2:-}"
    local lives_dir="$CLAUDE_LIVES_DIR"

    local global_mem="$lives_dir/global/memory.md"
    local life_mem="$lives_dir/$life_name/memory.md"

    local start_marker="<!-- CLAUDE-LIVES:START:${life_name} -->"
    local end_marker="<!-- CLAUDE-LIVES:END -->"

    local block=""
    block+="$start_marker"$'\n'

    if [[ -n "$project_name" ]]; then
        block+="## Life: ${life_name} | Project: ${project_name}"$'\n'
    else
        block+="## Life: ${life_name}"$'\n'
    fi
    block+=""$'\n'

    if [[ -f "$global_mem" ]]; then
        block+="### Global Preferences"$'\n'
        block+="$(strip_frontmatter "$global_mem" | sed '/^# /d')"$'\n'
        block+=""$'\n'
    fi

    if [[ -f "$life_mem" ]]; then
        block+="### Life Memory"$'\n'
        block+="$(strip_frontmatter "$life_mem" | sed '/^# /d')"$'\n'
        block+=""$'\n'
    fi

    if [[ -n "$project_name" ]]; then
        local project_dir="$lives_dir/$life_name/projects/$project_name"
        if [[ -f "$project_dir/memory.md" ]]; then
            block+="### Project Memory"$'\n'
            block+="$(strip_frontmatter "$project_dir/memory.md" | sed '/^# /d')"$'\n'
            block+=""$'\n'
        fi
        if [[ -f "$project_dir/handover.md" ]]; then
            block+="### Project Handover"$'\n'
            block+="$(strip_frontmatter "$project_dir/handover.md" | sed '/^# /d')"$'\n'
            block+=""$'\n'
        fi
    else
        local handover="$lives_dir/$life_name/handover.md"
        if [[ -f "$handover" ]]; then
            block+="### Handover"$'\n'
            block+="$(strip_frontmatter "$handover" | sed '/^# /d')"$'\n'
            block+=""$'\n'
        fi
    fi

    block+="$end_marker"

    echo "$block"
}

write_block_to_file() {
    local claude_md="$1"
    local life_name="$2"
    local block="$3"

    local start_marker="<!-- CLAUDE-LIVES:START:${life_name} -->"
    local end_marker="<!-- CLAUDE-LIVES:END -->"

    local lockfile="${claude_md}.lock"

    _write_block_inner() {
        if [[ ! -f "$claude_md" ]]; then
            echo "$block" > "$claude_md"
            return 0
        fi

        local has_start=false has_end=false
        grep -qF "$start_marker" "$claude_md" && has_start=true || true
        grep -qF "$end_marker" "$claude_md" && has_end=true || true

        if $has_start && $has_end; then
            local tmpfile blockfile
            tmpfile=$(mktemp "${claude_md}.tmp.XXXXXX")
            blockfile=$(mktemp)
            echo "$block" > "$blockfile"

            local in_block=false
            while IFS= read -r line; do
                if [[ "$line" == "$start_marker" ]]; then
                    cat "$blockfile"
                    in_block=true
                    continue
                fi
                if [[ "$line" == "$end_marker" ]]; then
                    in_block=false
                    continue
                fi
                if ! $in_block; then
                    echo "$line"
                fi
            done < "$claude_md" > "$tmpfile"

            mv "$tmpfile" "$claude_md"
            rm -f "$blockfile"
        elif $has_start || $has_end; then
            local tmpfile
            tmpfile=$(mktemp "${claude_md}.tmp.XXXXXX")
            grep -vF "$start_marker" "$claude_md" | grep -vF "$end_marker" > "$tmpfile" || true
            echo "" >> "$tmpfile"
            echo "$block" >> "$tmpfile"
            mv "$tmpfile" "$claude_md"
        else
            local tmpfile
            tmpfile=$(mktemp "${claude_md}.tmp.XXXXXX")
            cat "$claude_md" > "$tmpfile"
            echo "" >> "$tmpfile"
            echo "$block" >> "$tmpfile"
            mv "$tmpfile" "$claude_md"
        fi
    }

    if command -v flock &>/dev/null; then
        (
            flock -w 10 200 || { echo "WARNING: Could not acquire lock on $claude_md" >&2; _write_block_inner; return; }
            _write_block_inner
        ) 200>"$lockfile"
        rm -f "$lockfile" 2>/dev/null || true
    else
        _write_block_inner
    fi
}

inject_memory() {
    local claude_md="$1"
    local life_name="$2"
    local mode="${3:---progressive}"
    local project_name="${4:-}"
    local lives_dir="$CLAUDE_LIVES_DIR"

    # Security: check memory files for prompt injection patterns
    local security_warn=false
    check_injection_patterns "$lives_dir/$life_name/memory.md" || security_warn=true
    check_injection_patterns "$lives_dir/global/memory.md" || security_warn=true

    if [[ -n "$project_name" ]]; then
        local pdir="$lives_dir/$life_name/projects/$project_name"
        check_injection_patterns "$pdir/memory.md" || security_warn=true
        check_injection_patterns "$pdir/handover.md" || security_warn=true
    else
        check_injection_patterns "$lives_dir/$life_name/handover.md" || security_warn=true
    fi

    if $security_warn; then
        echo "BLOCKED: Suspicious patterns detected in memory files. Review files manually before re-running." >&2
        echo "To override, set CLAUDE_LIVES_SKIP_SECURITY=1" >&2
        if [[ "${CLAUDE_LIVES_SKIP_SECURITY:-}" != "1" ]]; then
            return 1
        fi
    fi

    local block
    if [[ "$mode" == "--full" ]]; then
        block=$(build_full_block "$life_name" "$project_name")
    else
        block=$(build_progressive_block "$life_name" "$project_name")
    fi

    write_block_to_file "$claude_md" "$life_name" "$block"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: inject_memory.sh <claude_md_path> <life_name> [--progressive|--full] [project_name]" >&2
        exit 1
    fi
    inject_memory "$1" "$2" "${3:---progressive}" "${4:-}"
fi
