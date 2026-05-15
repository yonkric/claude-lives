#!/usr/bin/env bash
set -euo pipefail

# Resilience utilities for claude-lives
# Handles edge cases: disk full, corrupt files, concurrent sessions, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
source "$SCRIPT_DIR/config_defaults.sh"

# Check if disk is getting full (< 100MB free)
check_disk_space() {
    local dir="${1:-$CLAUDE_LIVES_DIR}"
    local required_mb="${2:-100}"

    # Get available space in KB, then convert to MB
    local available_kb
    available_kb=$(df -k "$dir" 2>/dev/null | awk 'NR==2 {print $4}') || available_kb=0
    local available_mb=$((available_kb / 1024))

    if [[ "$available_mb" -lt "$required_mb" ]]; then
        echo "error: Low disk space: ${available_mb}MB available, ${required_mb}MB required"
        return 1
    fi
    return 0
}

# Validate .claude-life file format
validate_life_marker() {
    local marker_file="$1"

    if [[ ! -f "$marker_file" ]]; then
        echo "error: Marker file not found: $marker_file"
        return 1
    fi

    # Check required fields
    local name
    name=$(grep -E '^name:' "$marker_file" 2>/dev/null | head -1 | sed 's/^name:[[:space:]]*//') || name=""

    if [[ -z "$name" ]]; then
        echo "error: Missing 'name:' field in $marker_file"
        return 1
    fi

    # Validate name format
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "error: Invalid life name '$name' in $marker_file (alphanumeric, hyphen, underscore only)"
        return 1
    fi

    # Check for type field (optional but validates format)
    local life_type
    life_type=$(grep -E '^type:' "$marker_file" 2>/dev/null | head -1 | sed 's/^type:[[:space:]]*//') || life_type="flat"

    if [[ "$life_type" != "flat" && "$life_type" != "workspace" ]]; then
        echo "warning: Unknown life type '$life_type', defaulting to 'flat'"
    fi

    echo "valid"
    return 0
}

# Repair a corrupt .claude-life marker
repair_life_marker() {
    local marker_file="$1"
    local suggested_name="${2:-}"

    echo "Attempting to repair $marker_file..."

    # Try to extract name from filename or directory
    local life_name="$suggested_name"
    if [[ -z "$life_name" ]]; then
        life_name=$(basename "$(dirname "$marker_file")")
        # Sanitize: remove special chars, keep alphanumeric
        life_name=$(echo "$life_name" | tr -cd 'a-zA-Z0-9_-')
        # If empty, use default
        if [[ -z "$life_name" ]]; then
            life_name="recovered-life"
        fi
    fi

    # Validate life name
    if [[ ! "$life_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        life_name="recovered-life"
    fi

    local today
    today=$(date +%Y-%m-%d)

    # Create minimal valid marker
    cat > "$marker_file" <<EOF
name: $life_name
created: $today
type: flat
# Recovered from corrupt marker
EOF

    echo "Repaired with name: $life_name"
}

# Safe write with backup and rollback capability
# Usage: safe_write "source_content" "target_file"
safe_write() {
    local content="$1"
    local target_file="$2"
    local backup_suffix=".backup.$(date +%s).$$"

    # Check disk space first
    local target_dir
    target_dir=$(dirname "$target_file")
    if ! check_disk_space "$target_dir" 10; then
        echo "error: Insufficient disk space to write $target_file"
        return 1
    fi

    # Create backup if file exists
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "${target_file}${backup_suffix}" 2>/dev/null || true
    fi

    # Write to temp file first
    local temp_file="${target_file}.tmp.$$"
    if ! echo "$content" > "$temp_file" 2>/dev/null; then
        echo "error: Failed to write temp file $temp_file"
        return 1
    fi

    # Verify temp file was written
    if [[ ! -s "$temp_file" ]]; then
        rm -f "$temp_file" 2>/dev/null
        echo "error: Temp file is empty"
        return 1
    fi

    # Atomic move
    if ! mv "$temp_file" "$target_file" 2>/dev/null; then
        rm -f "$temp_file" 2>/dev/null
        # Restore backup if available
        if [[ -f "${target_file}${backup_suffix}" ]]; then
            mv "${target_file}${backup_suffix}" "$target_file" 2>/dev/null || true
        fi
        echo "error: Failed to move temp file to target"
        return 1
    fi

    # Clean up backup on success
    rm -f "${target_file}${backup_suffix}" 2>/dev/null || true

    return 0
}

# Safe file append with crash recovery
# Usage: safe_append "content" "target_file"
safe_append() {
    local content="$1"
    local target_file="$2"
    local pending_file="${target_file}.pending.$$"

    # Write to pending file first
    echo "$content" >> "$pending_file" 2>/dev/null || {
        echo "error: Failed to write pending file"
        return 1
    }

    # Append to target
    cat "$pending_file" >> "$target_file" 2>/dev/null || {
        rm -f "$pending_file" 2>/dev/null
        echo "error: Failed to append to target"
        return 1
    }

    # Clean up pending file
    rm -f "$pending_file" 2>/dev/null
    return 0
}

# Process pending writes (recovery after crash)
process_pending_writes() {
    local dir="$1"

    find "$dir" -name '*.pending.*' -type f 2>/dev/null | while read -r pending_file; do
        local target_file="${pending_file%.pending.*}"

        # Check if pending file is recent (< 24 hours)
        local age_seconds
        age_seconds=$(($(date +%s) - $(stat -c %Y "$pending_file" 2>/dev/null || echo 0)))

        if [[ "$age_seconds" -lt 86400 ]]; then
            # Append to target
            cat "$pending_file" >> "$target_file" 2>/dev/null && rm "$pending_file" 2>/dev/null
        else
            # Stale pending file, just remove
            rm "$pending_file" 2>/dev/null
        fi
    done
}

# Concurrent access detection
# Returns 0 if no conflict, 1 if another session is active
check_concurrent_session() {
    local life_dir="$1"
    local current_session="${2:-$$}"

    local lock_file="$life_dir/.session-active"

    if [[ -f "$lock_file" ]]; then
        local other_session
        other_session=$(cat "$lock_file" 2>/dev/null) || other_session=""

        if [[ -n "$other_session" && "$other_session" != "$current_session" ]]; then
            # Validate PID is numeric before using with kill
            if [[ "$other_session" =~ ^[0-9]+$ ]] && kill -0 "$other_session" 2>/dev/null; then
                echo "warning: Another session is active (PID: $other_session)"
                return 1
            fi
        fi
    fi

    # Write current session
    echo "$current_session" > "$lock_file" 2>/dev/null || true
    return 0
}

# Release concurrent session lock
release_session_lock() {
    local life_dir="$1"
    local current_session="${2:-$$}"

    local lock_file="$life_dir/.session-active"

    if [[ -f "$lock_file" ]]; then
        local stored_session
        stored_session=$(cat "$lock_file" 2>/dev/null) || stored_session=""

        if [[ "$stored_session" == "$current_session" ]]; then
            rm -f "$lock_file" 2>/dev/null
        fi
    fi
}

# Validate CLAUDE.md markers
validate_claude_md_markers() {
    local claude_md="$1"
    local life_name="$2"

    if [[ ! -f "$claude_md" ]]; then
        echo "missing"
        return 1
    fi

    local start_marker="<!-- CLAUDE-LIVES:START:$life_name -->"
    local end_marker="<!-- CLAUDE-LIVES:END -->"

    if ! grep -qF "$start_marker" "$claude_md" 2>/dev/null; then
        echo "missing-start"
        return 1
    fi

    if ! grep -qF "$end_marker" "$claude_md" 2>/dev/null; then
        echo "missing-end"
        return 1
    fi

    # Check for proper nesting (start before end)
    local start_line end_line
    start_line=$(grep -n -F "$start_marker" "$claude_md" 2>/dev/null | head -1 | cut -d: -f1) || start_line=0
    end_line=$(grep -n -F "$end_marker" "$claude_md" 2>/dev/null | head -1 | cut -d: -f1) || end_line=0

    if [[ "$start_line" -ge "$end_line" ]]; then
        echo "invalid-nesting"
        return 1
    fi

    echo "valid"
    return 0
}

# Repair CLAUDE.md markers
repair_claude_md_markers() {
    local claude_md="$1"
    local life_name="$2"
    local injection_content="${3:-}"

    # Validate life_name contains only safe characters
    if [[ ! "$life_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "error: Invalid life name for marker repair: $life_name"
        return 1
    fi

    echo "Repairing CLAUDE.md markers for $life_name..."

    # Default content if none provided
    if [[ -z "$injection_content" ]]; then
        injection_content="## Life: $life_name

**Status:** Recovered from marker error

*Context reconstructed automatically.*"
    fi

    # Remove markers for this specific life only
    sed -i "/<!-- CLAUDE-LIVES:START:${life_name} -->/,/<!-- CLAUDE-LIVES:END -->/d" "$claude_md" 2>/dev/null || true

    # Remove any orphaned partial markers for this life
    sed -i "/<!-- CLAUDE-LIVES:START:${life_name}/d" "$claude_md" 2>/dev/null || true

    # Append fresh markers
    cat >> "$claude_md" <<EOF

<!-- CLAUDE-LIVES:START:$life_name -->
$injection_content
<!-- CLAUDE-LIVES:END -->
EOF

    echo "Markers repaired"
}

# Comprehensive health check for a life
health_check() {
    local life_name="$1"
    local lives_dir="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
    local life_dir="$lives_dir/$life_name"

    local issues=()

    # Check disk space
    if ! check_disk_space "$life_dir" 50; then
        issues+=("low-disk-space")
    fi

    # Check life marker if exists
    local life_root
    life_root=$(find /home -name ".claude-life" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) || life_root=""

    if [[ -n "$life_root" && -f "$life_root/.claude-life" ]]; then
        if [[ "$(validate_life_marker "$life_root/.claude-life")" != "valid" ]]; then
            issues+=("corrupt-marker")
        fi

        # Check CLAUDE.md markers
        if [[ -f "$life_root/CLAUDE.md" ]]; then
            local marker_status
            marker_status=$(validate_claude_md_markers "$life_root/CLAUDE.md" "$life_name")
            if [[ "$marker_status" != "valid" ]]; then
                issues+=("marker-$marker_status")
            fi
        fi
    fi

    # Check for pending writes
    local pending_count
    pending_count=$(find "$life_dir" -name '*.pending.*' -type f 2>/dev/null | wc -l)
    if [[ "$pending_count" -gt 0 ]]; then
        issues+=("pending-writes:$pending_count")
    fi

    # Check for old backups
    local backup_count
    backup_count=$(find "$life_dir" -name '*.backup.*' -type f -mtime +7 2>/dev/null | wc -l)
    if [[ "$backup_count" -gt 5 ]]; then
        issues+=("old-backups:$backup_count")
    fi

    # Output JSON
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json="[$(printf '\"%s\",' "${issues[@]}" | sed 's/,$//')]"
    fi

    cat <<EOF
{
  "life": "$life_name",
  "healthy": $([[ ${#issues[@]} -eq 0 ]] && echo "true" || echo "false"),
  "issues": $issues_json,
  "checks": {
    "disk_space": $(check_disk_space "$life_dir" 50 && echo "true" || echo "false"),
    "marker_valid": $([[ -n "$life_root" && "$(validate_life_marker "$life_root/.claude-life" 2>/dev/null)" == "valid" ]] && echo "true" || echo "false"),
    "pending_writes": $pending_count
  }
}
EOF
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    case "${1:-}" in
        "disk-check")
            shift
            check_disk_space "$@"
            ;;
        "validate-marker")
            shift
            validate_life_marker "$@"
            ;;
        "repair-marker")
            shift
            repair_life_marker "$@"
            ;;
        "health")
            shift
            health_check "$@"
            ;;
        "safe-write")
            shift
            safe_write "$@"
            ;;
        "check-concurrent")
            shift
            check_concurrent_session "$@"
            ;;
        *)
            echo "Usage: $0 {disk-check|validate-marker|repair-marker|health|safe-write|check-concurrent} [args...]"
            ;;
    esac
fi
