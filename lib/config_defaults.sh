#!/usr/bin/env bash

# Default configuration values for claude-lives.
# These are used when no config.yaml overrides are present.

CLAUDE_LIVES_DIR="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"

DEFAULT_GLOBAL_TOKEN_BUDGET=1000
DEFAULT_LIFE_TOKEN_BUDGET=4000
DEFAULT_PROJECT_TOKEN_BUDGET=3000
DEFAULT_HANDOVER_TOKEN_BUDGET=1500
DEFAULT_TOTAL_TOKEN_BUDGET=6500

DEFAULT_COMPRESSION_THRESHOLD_PCT=80
DEFAULT_DECAY_SESSION_THRESHOLD=10
DEFAULT_INJECTION_MODE="progressive"  # "progressive" or "full"

DEFAULT_SNAPSHOT_TOOL_THRESHOLD=20
DEFAULT_SNAPSHOT_MAX_TOKENS=150
DEFAULT_SNAPSHOT_ENABLED=true

get_config_value() {
    local life_name="$1"
    local key="$2"
    local default="$3"

    local life_config="$CLAUDE_LIVES_DIR/$life_name/config.yaml"
    if [[ -f "$life_config" ]]; then
        local val
        val=$(grep -E "^${key}:" "$life_config" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//")
        if [[ -n "$val" ]]; then
            echo "$val"
            return 0
        fi
    fi

    echo "$default"
}

get_life_token_budget() {
    local life_name="$1"
    get_config_value "$life_name" "life_token_budget" "$DEFAULT_LIFE_TOKEN_BUDGET"
}

get_handover_token_budget() {
    local life_name="$1"
    get_config_value "$life_name" "handover_token_budget" "$DEFAULT_HANDOVER_TOKEN_BUDGET"
}

get_global_token_budget() {
    get_config_value "global" "global_token_budget" "$DEFAULT_GLOBAL_TOKEN_BUDGET"
}
