#!/usr/bin/env bash
set -eo pipefail

# Comprehensive test runner for claude-lives
# Runs all unit, integration, and phase tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

        output=$(bash "$test_file" 2>&1)
        exit_code=$?
        echo "$output"

        # Extract results - try different formats
        # Format 1: "X Y passed" (unit tests)
        local passed=$(echo "$output" | grep -E "Passed:|passed" | tail -1 | grep -oE "[0-9]+" | head -1)
        local total=$(echo "$output" | grep -E "Total:|Failed:" | tail -1 | grep -oE "[0-9]+" | head -1)

        # Format 2: "Results: X/Y passed" (phase tests)
        if [[ -z "$passed" ]]; then
            local results_line=$(echo "$output" | grep "passed," | tail -1)
            passed=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) passed.*/\1/' 2>/dev/null || echo 0)
            total=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) passed.*/\2/' 2>/dev/null || echo 0)
        fi

        # Default to 0 if empty
        passed=${passed:-0}
        total=${total:-0}
        local failed=$((total - passed))

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
        local test_name=$(basename "$test_file" .sh | sed 's/test_//;s/_/ /g')
        run_test_file "$test_file" "$test_name"
    fi
done

# Final Summary
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     FINAL AGGREGATE RESULTS           ║"
echo "║     Passed: $TOTAL_PASS                          ║"
echo "║     Failed: $TOTAL_FAIL                           ║"
echo "║     Total:  $((TOTAL_PASS + TOTAL_FAIL))                         ║"
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
