#!/usr/bin/env bash
# Don't use set -e for test scripts

# Integration test: Full session workflow
# Tests life creation, session, and memory persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR"
export CLAUDE_LIVES_DIR="$HOME/.claude-lives"

# Source the lib files
source "$PROJECT_ROOT/lib/config_defaults.sh"
source "$PROJECT_ROOT/lib/detect_life.sh"
source "$PROJECT_ROOT/lib/resilience.sh"
set +euo pipefail

BG_PIDS=()
trap 'for p in "${BG_PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

test_pass() {
    echo "  ✓ PASS: $1"
    PASS=$((PASS + 1))
}

test_fail() {
    echo "  ✗ FAIL: $1"
    FAIL=$((FAIL + 1))
}

echo "================================"
echo "End-to-End Session Integration Test"
echo "================================"
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Setup: Create a test project
TEST_PROJECT="$TEST_DIR/my-project"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Test 1: Create a flat life
echo "Test 1: Create flat life"
mkdir -p "$CLAUDE_LIVES_DIR"
mkdir -p "$CLAUDE_LIVES_DIR/test-life/sessions"
mkdir -p "$CLAUDE_LIVES_DIR/test-life/archive"
mkdir -p "$CLAUDE_LIVES_DIR/global"

# Create life marker
cat > "$TEST_PROJECT/.claude-life" <<EOF
name: test-life
type: flat
created: 2026-05-12
EOF

# Create initial memory
cat > "$CLAUDE_LIVES_DIR/test-life/memory.md" <<EOF
---
life: test-life
last_compressed: 2026-05-12
session_count: 0
---

# test-life — Life Memory

## Identity
Test project for integration testing

## Current Focus
Testing claude-lives session workflow

## Key Context
- Testing environment: automated
- Project path: $TEST_PROJECT
EOF

# Create handover
cat > "$CLAUDE_LIVES_DIR/test-life/handover.md" <<EOF
---
life: test-life
last_updated: 2026-05-12
---

# Handover Notes

## What Was Happening
Initial test session setup

## Next Steps
Run integration tests

## Pending Decisions
(None)

## Key Files Being Worked On
(None)
EOF

if [[ -f "$TEST_PROJECT/.claude-life" ]]; then
    test_pass "Life marker created"
else
    test_fail "Life marker not created"
fi

# Test 2: Detect life
echo "Test 2: Detect life from project directory"
cd "$TEST_PROJECT"
DETECTED_LIFE=$(detect_life 2>/dev/null || echo "")
if [[ "$DETECTED_LIFE" == "test-life" ]]; then
    test_pass "Life detected correctly: $DETECTED_LIFE"
else
    test_fail "Life not detected correctly: $DETECTED_LIFE"
fi

# Test 3: Create CLAUDE.md with markers
echo "Test 3: Create CLAUDE.md with markers"
cat > "$TEST_PROJECT/CLAUDE.md" <<EOF
# Test Project

This is a test project.

<!-- CLAUDE-LIVES:START:test-life -->
## Life: test-life

Test content
<!-- CLAUDE-LIVES:END -->
EOF

if [[ -f "$TEST_PROJECT/CLAUDE.md" ]]; then
    test_pass "CLAUDE.md created"
else
    test_fail "CLAUDE.md not created"
fi

# Test 4: Validate markers
echo "Test 4: Validate CLAUDE.md markers"
if [[ "$(validate_claude_md_markers "$TEST_PROJECT/CLAUDE.md" "test-life")" == "valid" ]]; then
    test_pass "Markers are valid"
else
    test_fail "Markers are invalid"
fi

# Test 5: Simulate session save (create session log)
echo "Test 5: Simulate session save"
SESSION_FILE="$CLAUDE_LIVES_DIR/test-life/sessions/2026-05-12-001.md"
cat > "$SESSION_FILE" <<EOF
---
date: 2026-05-12
session: 001
life: test-life
---

## Summary
Integration test session

## Decisions Made
- Tests are important

## Completed
- Test setup

## Pending
- Run full test suite

## Key Findings
- Everything working so far

## Dead Ends
(None)
EOF

if [[ -f "$SESSION_FILE" ]]; then
    test_pass "Session log created"
else
    test_fail "Session log not created"
fi

# Test 6: Update memory
echo "Test 6: Update memory with new fact"
echo "- Integration test fact added" >> "$CLAUDE_LIVES_DIR/test-life/memory.md"
if grep -q "Integration test fact" "$CLAUDE_LIVES_DIR/test-life/memory.md"; then
    test_pass "Memory updated with new fact"
else
    test_fail "Memory not updated"
fi

# Test 7: Token counting
echo "Test 7: Count tokens in memory"
TOKEN_COUNT=$(bash "$PROJECT_ROOT/lib/token_count.sh" "$CLAUDE_LIVES_DIR/test-life/memory.md")
if [[ "$TOKEN_COUNT" =~ ^[0-9]+$ && "$TOKEN_COUNT" -gt 0 ]]; then
    test_pass "Token count: $TOKEN_COUNT"
else
    test_fail "Token count failed: $TOKEN_COUNT"
fi

# Test 8: Health check
echo "Test 8: Run health check"
HEALTH=$(health_check "test-life" 2>/dev/null) || true
if echo "$HEALTH" | grep -q '"healthy":true'; then
    test_pass "Health check passed"
else
    test_fail "Health check reported unhealthy"
fi

# Test 9: Detect concurrent session
echo "Test 9: Concurrent session detection"
mkdir -p "$CLAUDE_LIVES_DIR/concurrent-test"
# Create a background process and use its PID
(sleep 30) &
BG_PID=$!
BG_PIDS+=("$BG_PID")
sleep 0.5
echo "$BG_PID" > "$CLAUDE_LIVES_DIR/concurrent-test/.session-active"
result=$(bash "$PROJECT_ROOT/lib/resilience.sh" check-concurrent "$CLAUDE_LIVES_DIR/concurrent-test" 99999 2>&1)
echo "Check result: $result"
if echo "$result" | grep -q "Another session"; then
    test_pass "Concurrent session detected"
else
    test_fail "Concurrent session not detected"
fi
kill "$BG_PID" 2>/dev/null || true
wait "$BG_PID" 2>/dev/null || true

# Test 10: Repair corrupt marker
echo "Test 10: Repair corrupt marker"
mkdir -p "$TEST_DIR/corrupt-test"
echo "garbage" > "$TEST_DIR/corrupt-test/.claude-life"
bash "$PROJECT_ROOT/lib/resilience.sh" repair-marker "$TEST_DIR/corrupt-test/.claude-life" "recovered-life" 2>/dev/null || true
if grep -q "name: recovered-life" "$TEST_DIR/corrupt-test/.claude-life"; then
    test_pass "Corrupt marker repaired"
else
    test_fail "Marker not repaired"
fi

# Summary
echo ""
echo "================================"
echo "Results: $PASS/$((PASS+FAIL)) tests passed"
echo "================================"

if [[ $FAIL -eq 0 ]]; then
    echo "✓ All integration tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
