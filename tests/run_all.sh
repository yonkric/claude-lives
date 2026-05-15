#!/usr/bin/env bash
set -uo pipefail

# Comprehensive test runner for claude-lives
# Runs all unit, integration, and phase tests
# Note: do NOT use set -e here — test failures should be recorded, not abort the runner

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "========================================"
echo "claude-lives Comprehensive Test Suite"
echo "========================================"
echo ""
echo "Started at: $(date)"
echo ""

# Function to run a test and extract results
run_test_file() {
    local test_file="$1"
    local test_name="$2"

    if [[ -f "$test_file" ]]; then
        echo ""
        echo "========================================"
        echo "Running: $test_name"
        echo "========================================"

        local output exit_code
        output=$(bash "$test_file" 2>&1)
        exit_code=$?
        echo "$output"

        # Extract results from structured output
        # Look for "Passed: N" and "Failed: N" lines (unit test format)
        local passed=""
        local failed=""
        passed=$(echo "$output" | grep -E "^Passed:" | tail -1 | grep -oE "[0-9]+" | head -1) || true
        failed=$(echo "$output" | grep -E "^Failed:" | tail -1 | grep -oE "[0-9]+" | head -1) || true

        # Fallback: try "Results: X/Y tests passed" format (integration/phase tests)
        if [[ -z "$passed" ]]; then
            local results_line
            results_line=$(echo "$output" | grep -E "Results:.*passed" | tail -1) || true
            if [[ -n "$results_line" ]]; then
                passed=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) .*/\1/' 2>/dev/null) || true
                local total
                total=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) .*/\2/' 2>/dev/null) || true
                if [[ -n "$total" && -n "$passed" ]]; then
                    failed=$((total - passed))
                fi
            fi
        fi

        # Default to 0 if still empty
        passed=${passed:-0}
        failed=${failed:-0}

        # Safety: if exit code is non-zero but we parsed 0 failures, record at least 1
        if [[ $exit_code -ne 0 && "$failed" -eq 0 ]]; then
            failed=1
        fi

        TOTAL_PASS=$((TOTAL_PASS + passed))
        TOTAL_FAIL=$((TOTAL_FAIL + failed))

        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ $test_name completed${NC}"
        else
            echo -e "${RED}✗ $test_name failed${NC}"
        fi
    fi
}

# Run unit tests
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     UNIT TESTS                        ║"
echo "╚═══════════════════════════════════════╝"

run_test_file "$SCRIPT_DIR/unit/lib/test_token_count.sh" "Token Count Unit Tests"
run_test_file "$SCRIPT_DIR/unit/lib/test_detect_life.sh" "Life Detection Unit Tests"
run_test_file "$SCRIPT_DIR/unit/lib/test_resilience.sh" "Resilience Unit Tests"

# Run integration tests
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     INTEGRATION TESTS                 ║"
echo "╚═══════════════════════════════════════╝"

run_test_file "$SCRIPT_DIR/integration/test_install.sh" "Installation Test"
run_test_file "$SCRIPT_DIR/integration/test_session.sh" "End-to-End Session Test"

# Run existing phase tests
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     PHASE TESTS                       ║"
echo "╚═══════════════════════════════════════╝"

for test_file in "$SCRIPT_DIR"/test_phase*.sh "$SCRIPT_DIR"/test_critique_fixes.sh "$SCRIPT_DIR"/test_token_optimization.sh "$SCRIPT_DIR"/test_project_layer.sh "$SCRIPT_DIR"/test_auto_session.sh "$SCRIPT_DIR"/test_cherry_pick.sh "$SCRIPT_DIR"/test_audit_fixes.sh "$SCRIPT_DIR"/test_snapshots.sh; do
    if [[ -f "$test_file" ]]; then
        test_name=$(basename "$test_file" .sh | sed 's/test_//;s/_/ /g')
        run_test_file "$test_file" "$test_name"
    fi
done

# Final Summary
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     FINAL AGGREGATE RESULTS           ║"
printf "║     Passed: %-26s║\n" "$TOTAL_PASS"
printf "║     Failed: %-26s║\n" "$TOTAL_FAIL"
printf "║     Total:  %-26s║\n" "$((TOTAL_PASS + TOTAL_FAIL))"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "Finished at: $(date)"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
