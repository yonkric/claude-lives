#!/usr/bin/env bash
set -uo pipefail

# Run all phase tests and report aggregate results.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

for test_file in "$SCRIPT_DIR"/test_phase*.sh "$SCRIPT_DIR"/test_critique_fixes.sh "$SCRIPT_DIR"/test_token_optimization.sh "$SCRIPT_DIR"/test_project_layer.sh "$SCRIPT_DIR"/test_auto_session.sh "$SCRIPT_DIR"/test_cherry_pick.sh "$SCRIPT_DIR"/test_audit_fixes.sh "$SCRIPT_DIR"/test_snapshots.sh; do
    if [[ -f "$test_file" ]]; then
        echo ""
        output=$(bash "$test_file" 2>&1)
        exit_code=$?
        echo "$output"

        # Extract "X/Y passed" from the results line (macOS-compatible)
        results_line=$(echo "$output" | grep "passed," | tail -1)
        passed=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) passed.*/\1/' || echo 0)
        total=$(echo "$results_line" | sed -E 's/.*Results: ([0-9]+)\/([0-9]+) passed.*/\2/' || echo 0)
        failed=$((total - passed))

        TOTAL_PASS=$((TOTAL_PASS + passed))
        TOTAL_FAIL=$((TOTAL_FAIL + failed))
    fi
done

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     AGGREGATE RESULTS                 ║"
echo "║     Passed: $TOTAL_PASS                          ║"
echo "║     Failed: $TOTAL_FAIL                           ║"
echo "║     Total:  $((TOTAL_PASS + TOTAL_FAIL))                         ║"
echo "╚═══════════════════════════════════════╝"

if [[ $TOTAL_FAIL -gt 0 ]]; then
    exit 1
fi
