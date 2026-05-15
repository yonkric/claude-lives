#!/bin/bash
# Unit tests for detect_life.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../lib" && pwd)"
source "$LIB_DIR/detect_life.sh"
set +euo pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "  ✓ PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "  ✗ FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $1"
}

# Setup
TEMP_DIR=$(mktemp -d)
export CLAUDE_LIVES_DIR="$TEMP_DIR/claude-lives"
mkdir -p "$CLAUDE_LIVES_DIR"

trap 'rm -rf "$TEMP_DIR"' EXIT

echo "================================"
echo "Life Detection Unit Tests"
echo "================================"
echo ""

# Test 1: Detect flat life from root
run_test "Detect flat life from root directory"
mkdir -p "$TEMP_DIR/flat-life"
cat > "$TEMP_DIR/flat-life/.claude-life" <<EOF
name: flat-life
type: flat
created: 2026-01-01
EOF

cd "$TEMP_DIR/flat-life"
result=$(detect_life 2>/dev/null || echo "NOTFOUND")
if [[ "$result" == "flat-life" ]]; then
    pass "Detected flat life from root"
else
    fail "Expected 'flat-life', got '$result'"
fi

# Test 2: Detect life from subdirectory
run_test "Detect life from subdirectory"
mkdir -p "$TEMP_DIR/flat-life/src/components"
cd "$TEMP_DIR/flat-life/src/components"
result=$(detect_life 2>/dev/null || echo "NOTFOUND")
if [[ "$result" == "flat-life" ]]; then
    pass "Detected life from deep subdirectory"
else
    fail "Expected 'flat-life', got '$result'"
fi

# Test 3: No life found (no marker)
run_test "No life found in directory without marker"
mkdir -p "$TEMP_DIR/no-life"
cd "$TEMP_DIR/no-life"
result=$(detect_life 2>/dev/null || echo "NOTFOUND")
if [[ "$result" == "NOTFOUND" ]]; then
    pass "Correctly returns error when no life found"
else
    fail "Should return error when no life found, got: $result"
fi

# Test 4: Get life root
run_test "Get life root directory"
cd "$TEMP_DIR/flat-life/src/components"
result=$(get_life_root 2>/dev/null || echo "NOTFOUND")
if [[ "$result" == "$TEMP_DIR/flat-life" ]]; then
    pass "Got correct life root"
else
    fail "Expected '$TEMP_DIR/flat-life', got '$result'"
fi

# Test 5: Detect flat life type
run_test "Detect flat life type"
cd "$TEMP_DIR/flat-life"
result=$(detect_life_type)
if [[ "$result" == "flat" ]]; then
    pass "Detected flat type"
else
    fail "Expected 'flat', got '$result'"
fi

# Test 6: Detect workspace life type
run_test "Detect workspace life type"
mkdir -p "$TEMP_DIR/workspace-life"
cat > "$TEMP_DIR/workspace-life/.claude-life" <<EOF
name: workspace-life
type: workspace
created: 2026-01-01
EOF

cd "$TEMP_DIR/workspace-life"
result=$(detect_life_type)
if [[ "$result" == "workspace" ]]; then
    pass "Detected workspace type"
else
    fail "Expected 'workspace', got '$result'"
fi

# Summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo "Total:  $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
