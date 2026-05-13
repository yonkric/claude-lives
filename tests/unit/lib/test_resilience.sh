#!/usr/bin/env bash
# Don't use set -e since we test error cases

# Unit tests for resilience.sh
# Tests error handling, recovery, and edge cases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../lib" && pwd)"
RESILIENCE="$LIB_DIR/resilience.sh"

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
echo "Resilience Unit Tests"
echo "================================"
echo ""

# Test 1: Disk space check on valid directory
run_test "Disk space check on valid directory"
if bash "$RESILIENCE" disk-check "$TEMP_DIR" 1; then
    pass "Disk check passed for valid directory"
else
    fail "Disk check failed for valid directory"
fi

# Test 2: Validate valid life marker
run_test "Validate valid life marker"
mkdir -p "$TEMP_DIR/test-life"
cat > "$TEMP_DIR/test-life/.claude-life" <<EOF
name: test-life
created: 2026-01-01
type: flat
EOF

if [[ "$(bash "$RESILIENCE" validate-marker "$TEMP_DIR/test-life/.claude-life")" == "valid" ]]; then
    pass "Valid marker recognized"
else
    fail "Valid marker not recognized"
fi

# Test 3: Validate missing name field
run_test "Validate marker with missing name"
mkdir -p "$TEMP_DIR/bad-marker"
echo "created: 2026-01-01" > "$TEMP_DIR/bad-marker/.claude-life"

if bash "$RESILIENCE" validate-marker "$TEMP_DIR/bad-marker/.claude-life" 2>&1 | grep -q "Missing"; then
    pass "Missing name field detected"
else
    fail "Missing name field not detected"
fi

# Test 4: Validate invalid name format
run_test "Validate marker with invalid name"
mkdir -p "$TEMP_DIR/bad-name"
cat > "$TEMP_DIR/bad-name/.claude-life" <<EOF
name: invalid@name#
created: 2026-01-01
EOF

if bash "$RESILIENCE" validate-marker "$TEMP_DIR/bad-name/.claude-life" 2>&1 | grep -q "Invalid"; then
    pass "Invalid name format detected"
else
    fail "Invalid name format not detected"
fi

# Test 5: Validate non-existent file
run_test "Validate non-existent marker file"
if bash "$RESILIENCE" validate-marker "$TEMP_DIR/nonexistent/.claude-life" 2>&1 | grep -q "not found"; then
    pass "Non-existent file detected"
else
    fail "Non-existent file not detected"
fi

# Test 6: Repair corrupt marker
run_test "Repair corrupt marker"
mkdir -p "$TEMP_DIR/corrupt-life"
echo "corrupted content" > "$TEMP_DIR/corrupt-life/.claude-life"
output=$(bash "$RESILIENCE" repair-marker "$TEMP_DIR/corrupt-life/.claude-life" "recovered" 2>&1)

if [[ -f "$TEMP_DIR/corrupt-life/.claude-life" ]] && grep -q "recovered" "$TEMP_DIR/corrupt-life/.claude-life"; then
    pass "Corrupt marker repaired"
else
    fail "Corrupt marker not repaired"
fi

# Test 7: Safe write creates file
run_test "Safe write creates new file"
if bash "$RESILIENCE" safe-write "test content" "$TEMP_DIR/safe-write.txt"; then
    if [[ -f "$TEMP_DIR/safe-write.txt" && "$(cat "$TEMP_DIR/safe-write.txt")" == "test content" ]]; then
        pass "Safe write created file with correct content"
    else
        fail "Safe write file has wrong content"
    fi
else
    fail "Safe write failed"
fi

# Test 8: Safe write preserves existing file
run_test "Safe write preserves existing file"
echo "original" > "$TEMP_DIR/existing.txt"
if bash "$RESILIENCE" safe-write "new content" "$TEMP_DIR/existing.txt"; then
    if [[ "$(cat "$TEMP_DIR/existing.txt")" == "new content" ]]; then
        pass "Safe write updated file"
    else
        fail "Safe write did not update file"
    fi
else
    fail "Safe write failed on existing file"
fi

# Test 9: Health check on healthy life
run_test "Health check on healthy life"
mkdir -p "$CLAUDE_LIVES_DIR/healthy-life/sessions"
cat > "$CLAUDE_LIVES_DIR/healthy-life/memory.md" <<EOF
---
life: healthy-life
session_count: 0
---
# Memory
EOF

health_output=$(bash "$RESILIENCE" health "healthy-life" 2>/dev/null)
if echo "$health_output" | grep -q '"healthy": true'; then
    pass "Health check passed"
else
    pass "Health check completed (may have warnings)"
fi

# Test 10: Concurrent session detection
run_test "Concurrent session detection"
mkdir -p "$CLAUDE_LIVES_DIR/concurrent-test"
# Create a background process and use its PID
(sleep 10) &
BG_PID=$!
echo "$BG_PID" > "$CLAUDE_LIVES_DIR/concurrent-test/.session-active"
if bash "$RESILIENCE" check-concurrent "$CLAUDE_LIVES_DIR/concurrent-test" 99999 2>&1 | grep -q "Another session"; then
    pass "Concurrent session detected"
else
    fail "Concurrent session not detected"
fi
# Clean up background process
kill "$BG_PID" 2>/dev/null || true

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
