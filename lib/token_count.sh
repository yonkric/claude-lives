#!/usr/bin/env bash
set -euo pipefail

# Approximate token counter.
# Heuristic: 1 token ≈ 4 characters. Good enough for budget management.
#
# Usage:
#   token_count.sh <file>           — count tokens in a file
#   token_count.sh --string "text"  — count tokens in a string
#   token_count.sh --dir <path>     — count tokens in all .md files under path

count_tokens_string() {
    local text="$1"
    local chars=${#text}
    echo $(( (chars + 3) / 4 ))
}

count_tokens_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi
    local chars
    chars=$(wc -c < "$file" | tr -d ' ')
    echo $(( (chars + 3) / 4 ))
}

count_tokens_dir() {
    local dir="$1"
    local total=0
    # H3 fix: -type f excludes symlinks and directories
    while IFS= read -r -d '' file; do
        local chars
        chars=$(wc -c < "$file" | tr -d ' ')
        total=$(( total + (chars + 3) / 4 ))
    done < <(find "$dir" -type f -name '*.md' -print0 2>/dev/null)
    echo "$total"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    case "${1:-}" in
        --string)
            count_tokens_string "${2:-}"
            ;;
        --dir)
            count_tokens_dir "${2:-.}"
            ;;
        *)
            count_tokens_file "${1:-/dev/null}"
            ;;
    esac
fi
