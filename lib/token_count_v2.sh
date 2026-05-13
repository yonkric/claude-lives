#!/usr/bin/env bash
set -euo pipefail

# Token counting using tiktoken (Claude's actual tokenizer) instead of char/4 heuristic
# Falls back to char/4 if tiktoken is not available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"

# Cache for tiktoken availability
TIKTOKEN_AVAILABLE=""

# Check if tiktoken CLI is available
check_tiktoken() {
    if [[ -n "$TIKTOKEN_AVAILABLE" ]]; then
        return "$([[ "$TIKTOKEN_AVAILABLE" == "true" ]] && echo 0 || echo 1)"
    fi

    if command -v python3 &>/dev/null; then
        # Check if tiktoken is importable
        if python3 -c "import tiktoken" 2>/dev/null; then
            TIKTOKEN_AVAILABLE="true"
            return 0
        fi
    fi

    TIKTOKEN_AVAILABLE="false"
    return 1
}

# Count tokens in a string using tiktoken
# Usage: count_tokens_string "text to count"
count_tokens_string() {
    local text="$1"

    if check_tiktoken; then
        python3 -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
print(len(enc.encode('''$text''')))
"
    else
        # Fallback: character-based heuristic (4 chars ≈ 1 token)
        local char_count=${#text}
        echo $(( (char_count + 3) / 4 ))
    fi
}

# Count tokens in a file using tiktoken
# Usage: count_tokens_file "/path/to/file"
count_tokens_file() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "0"
        return 0
    fi

    if check_tiktoken; then
        python3 -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
with open('''$file_path''', 'r', encoding='utf-8') as f:
    content = f.read()
print(len(enc.encode(content)))
"
    else
        # Fallback: character-based heuristic
        local char_count
        char_count=$(wc -c < "$file_path" 2>/dev/null | tr -d ' ' || echo "0")
        echo $(( (char_count + 3) / 4 ))
    fi
}

# Batch count multiple files efficiently
# Usage: batch_count_tokens "file1" "file2" ...
batch_count_tokens() {
    if check_tiktoken && [[ $# -gt 0 ]]; then
        python3 <<EOF
import tiktoken
import sys

enc = tiktoken.get_encoding('cl100k_base')
total = 0

for filepath in sys.argv[1:]:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            count = len(enc.encode(content))
            total += count
    except Exception:
        pass

print(total)
EOF
    else
        # Fallback: sum char counts
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
# Usage: get_budget_status "life_name" ["project_name"]
get_budget_status() {
    local life_name="$1"
    local project_name="${2:-}"

    source "$SCRIPT_DIR/config_defaults.sh"

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

    # Get budget from config (default 4000)
    local budget=4000
    if [[ -f "$life_dir/config.yaml" ]]; then
        local config_budget
        config_budget=$(grep -E '^life_token_budget:' "$life_dir/config.yaml" 2>/dev/null | sed 's/^life_token_budget:[[:space:]]*//' | tr -d ' ' || echo "")
        if [[ "$config_budget" =~ ^[0-9]+$ ]]; then
            budget="$config_budget"
        fi
    fi

    # Count tokens
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

    # Output JSON for easy parsing
    cat <<EOF
{
  "life": "$life_name",
  "project": "${project_name:-(life-level)}",
  "budget": $budget,
  "memory_tokens": $memory_tokens,
  "handover_tokens": $handover_tokens,
  "total_tokens": $total_tokens,
  "percentage": $percentage,
  "warning_threshold": 80,
  "critical_threshold": 95,
  "using_tiktoken": $(check_tiktoken && echo "true" || echo "false")
}
EOF
}

# Export functions for use by other scripts
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    # Direct execution - run tests or CLI
    case "${1:-}" in
        "file")
            shift
            count_tokens_file "$@"
            ;;
        "string")
            shift
            count_tokens_string "$@"
            ;;
        "batch")
            shift
            batch_count_tokens "$@"
            ;;
        "status")
            shift
            get_budget_status "$@"
            ;;
        "test")
            echo "Token counting tests:"
            echo "1. Simple string: $(count_tokens_string "hello world")"
            echo "2. This file: $(count_tokens_file "${BASH_SOURCE[0]}")"
            echo "3. Tiktoken available: $(check_tiktoken && echo "yes" || echo "no (using fallback)")"
            ;;
        *)
            echo "Usage: $0 {file|status} [args...]"
            echo "       $0 test           # Run self-tests"
            ;;
    esac
fi
