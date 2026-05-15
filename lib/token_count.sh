#!/usr/bin/env bash
set -euo pipefail

# Token counter with tiktoken support for accurate Claude token counting.
# Falls back to character heuristic (4 chars ≈ 1 token) if tiktoken unavailable.
#
# Usage:
#   token_count.sh <file>           — count tokens in a file
#   token_count.sh --string "text"  — count tokens in a string
#   token_count.sh --dir <path>     — count tokens in all .md files under path
#   token_count.sh --check          — check if tiktoken is available

# Cache for tiktoken availability check
_TIKTOKEN_CHECKED=""
_TIKTOKEN_AVAILABLE=""

# Check if tiktoken is available via Python
check_tiktoken() {
    if [[ -n "$_TIKTOKEN_CHECKED" ]]; then
        [[ "$_TIKTOKEN_AVAILABLE" == "true" ]]
        return
    fi

    if command -v python3 &>/dev/null; then
        # Check if tiktoken is importable
        if python3 -c "import tiktoken" 2>/dev/null; then
            _TIKTOKEN_AVAILABLE="true"
            _TIKTOKEN_CHECKED="yes"
            return 0
        fi
    fi

    _TIKTOKEN_AVAILABLE="false"
    _TIKTOKEN_CHECKED="yes"
    return 1
}

# Count tokens using tiktoken (cl100k_base encoding, used by Claude)
count_with_tiktoken() {
    local text="$1"
    python3 -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
# Handle special characters safely
import sys
text = sys.argv[1]
print(len(enc.encode(text)))
" "$text" 2>/dev/null
}

# Fallback: character-based heuristic
count_with_heuristic() {
    local chars="$1"
    echo $(( (chars + 3) / 4 ))
}

count_tokens_string() {
    local text="$1"

    if check_tiktoken; then
        # Use actual tokenization
        local count
        count=$(count_with_tiktoken "$text") && echo "$count" && return 0
    fi

    # Fallback to heuristic
    local chars=${#text}
    count_with_heuristic "$chars"
}

count_tokens_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    if check_tiktoken; then
        # Read file and count with tiktoken
        local content
        content=$(cat "$file" 2>/dev/null) || { echo "0"; return 1; }
        local count
        count=$(count_with_tiktoken "$content") && echo "$count" && return 0
    fi

    # Fallback to heuristic
    local chars
    chars=$(wc -c < "$file" | tr -d ' ')
    count_with_heuristic "$chars"
}

count_tokens_dir() {
    local dir="$1"

    if check_tiktoken; then
        DIR_PATH="$dir" python3 <<'EOF' 2>/dev/null
import tiktoken
import os

enc = tiktoken.get_encoding('cl100k_base')
total = 0
dir_path = os.environ['DIR_PATH']

try:
    for root, dirs, files in os.walk(dir_path):
        for filename in files:
            if filename.endswith('.md'):
                filepath = os.path.join(root, filename)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                        total += len(enc.encode(content))
                except Exception:
                    pass
    print(total)
except Exception:
    print(0)
EOF
        return
    fi

    # Fallback: heuristic-based counting
    local total=0
    # H3 fix: -type f excludes symlinks and directories
    while IFS= read -r -d '' file; do
        local chars
        chars=$(wc -c < "$file" | tr -d ' ')
        total=$(( total + (chars + 3) / 4 ))
    done < <(find "$dir" -type f -name '*.md' -print0 2>/dev/null)
    echo "$total"
}

# Batch count multiple files efficiently
batch_count_tokens() {
    if check_tiktoken && [[ $# -gt 0 ]]; then
        python3 - "$@" <<'EOF' 2>/dev/null
import tiktoken
import sys

enc = tiktoken.get_encoding('cl100k_base')
total = 0

for filepath in sys.argv[1:]:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            total += len(enc.encode(content))
    except Exception:
        pass

print(total)
EOF
    else
        local total_chars=0
        for file in "$@"; do
            if [[ -f "$file" ]]; then
                local chars
                chars=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
                total_chars=$((total_chars + chars))
            fi
        done
        echo $(( (total_chars + 3) / 4 ))
    fi
}

# Get budget status for a life
get_budget_status() {
    local life_name="$1"
    local project_name="${2:-}"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
    source "$script_dir/config_defaults.sh"

    local lives_dir="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
    local life_dir="$lives_dir/$life_name"

    local memory_file
    local handover_file

    if [[ -n "$project_name" ]]; then
        memory_file="$life_dir/projects/$project_name/memory.md"
        handover_file="$life_dir/projects/$project_name/handover.md"
    else
        memory_file="$life_dir/memory.md"
        handover_file="$life_dir/handover.md"
    fi

    local budget=4000
    if [[ -f "$life_dir/config.yaml" ]]; then
        local config_budget
        config_budget=$(grep -E '^life_token_budget:' "$life_dir/config.yaml" 2>/dev/null | sed 's/^life_token_budget:[[:space:]]*//' | tr -d ' ' || echo "")
        if [[ "$config_budget" =~ ^[0-9]+$ ]] && (( config_budget > 0 )); then
            budget="$config_budget"
        fi
    fi

    local memory_tokens=0
    local handover_tokens=0

    if [[ -f "$memory_file" ]]; then
        memory_tokens=$(count_tokens_file "$memory_file")
    fi

    if [[ -f "$handover_file" ]]; then
        handover_tokens=$(count_tokens_file "$handover_file")
    fi

    local total_tokens=$((memory_tokens + handover_tokens))
    local percentage=$((total_tokens * 100 / budget))
    local using_tiktoken
    using_tiktoken=$(check_tiktoken && echo "true" || echo "false")

    if command -v jq &>/dev/null; then
        jq -n \
            --arg life "$life_name" \
            --arg project "${project_name:-(life-level)}" \
            --argjson budget "$budget" \
            --argjson memory_tokens "$memory_tokens" \
            --argjson handover_tokens "$handover_tokens" \
            --argjson total_tokens "$total_tokens" \
            --argjson percentage "$percentage" \
            --argjson using_tiktoken "$using_tiktoken" \
            '{life: $life, project: $project, budget: $budget, memory_tokens: $memory_tokens, handover_tokens: $handover_tokens, total_tokens: $total_tokens, percentage: $percentage, warning_threshold: 80, critical_threshold: 95, using_tiktoken: $using_tiktoken}'
    else
        printf '{"life":"%s","project":"%s","budget":%d,"memory_tokens":%d,"handover_tokens":%d,"total_tokens":%d,"percentage":%d,"warning_threshold":80,"critical_threshold":95,"using_tiktoken":%s}\n' \
            "$life_name" "${project_name:-(life-level)}" "$budget" "$memory_tokens" "$handover_tokens" "$total_tokens" "$percentage" "$using_tiktoken"
    fi
}

# Get tokenization method info
get_tokenizer_info() {
    if check_tiktoken; then
        echo "tiktoken (cl100k_base)"
    else
        echo "heuristic (4 chars ≈ 1 token)"
    fi
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    case "${1:-}" in
        --string)
            count_tokens_string "${2:-}"
            ;;
        --dir)
            count_tokens_dir "${2:-.}"
            ;;
        --batch)
            shift
            batch_count_tokens "$@"
            ;;
        --status)
            shift
            get_budget_status "$@"
            ;;
        --check)
            if check_tiktoken; then
                echo "tiktoken available ($(get_tokenizer_info))"
                exit 0
            else
                echo "tiktoken not available ($(get_tokenizer_info))"
                exit 1
            fi
            ;;
        --info)
            echo "Tokenizer: $(get_tokenizer_info)"
            ;;
        *)
            count_tokens_file "${1:-/dev/null}"
            ;;
    esac
fi
